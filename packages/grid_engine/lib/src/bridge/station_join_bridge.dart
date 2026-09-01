import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart' show GridIssueTypes;

import '../domain/cross_link.dart';
import '../domain/joined_snapshot.dart';
import '../domain/mount_attempt.dart';
import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../domain/trajectory_views.dart';
import '../molecule/molecule_codec.dart';
import '../molecule/molecule_schema.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import 'block_guard.dart';
import 'dual_read_pass.dart';
import 'snapshot_source.dart';

typedef _JoinedStepIncarnation = ({Bead bead, int ordinal});

/// The JOIN bridge — the **only** subscription into the snapshot pipelines
/// (A39 / derailment-invariant 1).
///
/// It joins TWO observed inputs into the single immutable [JoinedSnapshot] the
/// tree builds from, **outside the tree**, and pushes it onto the
/// [JoinedSnapshotNotifier] that `WorkList` observes:
///
/// - **work** — the read-workspace work graph (`GraphSnapshot`); the join's
///   [JoinedSnapshot.graph].
/// - **state** — the_grid's own state store, from which `type=session` beads are
///   projected ([projectSession]) and keyed by `metadata.work_bead` into
///   [JoinedSnapshot.sessionsByWorkBead]. Every `type=molecule`/`type=step`
///   bead in the same state store (R1's molecule schema) is ALSO bucketed
///   here, by its `grid.circuit.session`/`grid.step.session` stamp, into the
///   owning session's own [SessionProjection.moleculeBeads]
///   (`DESIGN-tg-pm6.md` §10, R5a) — empty for a flat session, the additive
///   read-path substrate neither original proposal specified.
///
/// The tree only ever *consumes* the joined value — it never re-detects. Each
/// real change on either source recomputes the join from the **latest of both**
/// (the newly-emitted snapshot for the source that fired, `.current` for the
/// other) and produces exactly one push.
///
/// Seed-then-follow (replicates `beads_dart`'s `graphSnapshotProvider`):
/// the underlying broadcast streams do not replay, so the notifier is seeded
/// with the current join up front (or [JoinedSnapshot.empty] when no work
/// baseline exists yet); a late notifier subscriber sees that baseline, and the
/// first real emission fills it.
class StationJoinBridge {
  /// Creates a bridge over the [work] and [state] snapshot sources.
  ///
  /// If [notifier] is supplied, the bridge drives it but does **not** own its
  /// lifecycle (it is left undisposed on [dispose]); otherwise the bridge
  /// creates one, seeded with the current join, and disposes it itself.
  ///
  /// [onUnresolvedCrossLink] is the LOUD sink an unenforceable cross-link is
  /// reported through (see [_applyCrossLinks]).
  /// [headSnapshot] and [dualRead] are the DUAL READ's third input (cut-wiring
  /// C2): a pre-fetched, immutable P1 mirror read and the comparator that
  /// observes it. Both are optional — an offline or trajectory-less
  /// composition passes neither and the join is byte-identical to before.
  /// [onHeadChanges] is the re-join seam so a fold-side fact lands promptly
  /// rather than waiting for the next work/state emission.
  factory StationJoinBridge({
    required SnapshotSource work,
    required SnapshotSource state,
    JoinedSnapshotNotifier? notifier,
    void Function(String message)? onUnresolvedCrossLink,
    TrajectoryHeadSnapshot Function()? headSnapshot,
    HeadSnapshotSubscribe? onHeadChanges,
    DualReadSessionObserver? dualRead,
  }) {
    final seed = _join(
      work.current,
      state.current,
      headSnapshot?.call(),
      onUnresolvedCrossLink: onUnresolvedCrossLink,
      dualRead: dualRead,
    );
    return StationJoinBridge._(
      work: work,
      state: state,
      ownsNotifier: notifier == null,
      notifier: notifier ?? JoinedSnapshotNotifier(seed),
      latest: seed,
      onUnresolvedCrossLink: onUnresolvedCrossLink,
      headSnapshot: headSnapshot,
      onHeadChanges: onHeadChanges,
      dualRead: dualRead,
    );
  }

  StationJoinBridge._({
    required SnapshotSource work,
    required SnapshotSource state,
    required bool ownsNotifier,
    required this.notifier,
    required JoinedSnapshot latest,
    required void Function(String message)? onUnresolvedCrossLink,
    required TrajectoryHeadSnapshot Function()? headSnapshot,
    required HeadSnapshotSubscribe? onHeadChanges,
    required DualReadSessionObserver? dualRead,
  }) : _work = work,
       _state = state,
       _ownsNotifier = ownsNotifier,
       _latest = latest,
       _onUnresolvedCrossLink = onUnresolvedCrossLink,
       _headSnapshot = headSnapshot,
       _onHeadChanges = onHeadChanges,
       _dualRead = dualRead;

  final SnapshotSource _work;
  final SnapshotSource _state;
  final bool _ownsNotifier;

  /// The PRE-FETCHED P1 mirror read (§0.2). `_join` is pure and synchronous
  /// and a P1 SQL read is async, so the splice is state that was already
  /// fetched — never an inline await.
  final TrajectoryHeadSnapshot Function()? _headSnapshot;

  final HeadSnapshotSubscribe? _onHeadChanges;
  void Function()? _removeHeadListener;

  /// The comparator's bookkeeper — accounting, the two lag trackers, the
  /// flares, the heal requests, the durable round summaries. Under `observe`
  /// it only counts: decisions stay legacy in wave 1's C2.
  final DualReadSessionObserver? _dualRead;

  /// The LOUD sink an unenforceable cross-link is reported through — a
  /// malformed link bead, or a `to` target no federated work member observes.
  /// Emit-only; a null sink is the offline/no-op default and never changes what
  /// the guard DOES (the block is applied either way).
  final void Function(String message)? _onUnresolvedCrossLink;

  JoinedSnapshot _latest;

  /// The last joined value this bridge pushed — the PRODUCER's own record of
  /// its output (not a reactive read; D-H rule 2 forbids a public sync accessor
  /// on the notifier). The kernel's cooldown scan reads this.
  JoinedSnapshot get latest => _latest;

  /// The joined-snapshot value the tree's `WorkList` observes. Seeded with the
  /// current join (or [JoinedSnapshot.empty]) so a late subscriber sees the
  /// baseline rather than nothing.
  final JoinedSnapshotNotifier notifier;

  StreamSubscription<GraphSnapshot>? _workSub;
  StreamSubscription<GraphSnapshot>? _stateSub;
  bool _started = false;
  bool _disposed = false;

  /// Subscribes to BOTH source streams. On either emission the join is
  /// recomputed from the latest of both and pushed once. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Re-seed from the latest of both before following: if a source published
    // its first baseline in the gap between construction and start(), that
    // (non-replaying, broadcast) event was missed — recover it from `.current`
    // so the notifier never carries a stale construction-time seed. A no-op in
    // the intended atomic construct-then-start composition.
    _push(_rejoin());
    // Use the freshly-emitted snapshot for the source that fired and `.current`
    // for the other — one push per real emission, never two for one change.
    _workSub = _work.snapshots.listen((workSnapshot) {
      _push(_rejoin(work: workSnapshot));
    });
    _stateSub = _state.snapshots.listen((stateSnapshot) {
      _push(_rejoin(state: stateSnapshot));
    });
    // THE THIRD AXIS (C2): a fold-side fact re-joins promptly. It is NOT a
    // fourth subscription into the snapshot pipelines (A39 / derailment
    // invariant 1) — the mirror is this process's own pre-fetched state, not a
    // store — and it pushes through the SAME funnel, so the "one push per real
    // change" rule still holds.
    _removeHeadListener = _onHeadChanges?.call((_) => _push(_rejoin()));
  }

  /// Recomputes the join from the latest of all three inputs, taking the
  /// freshly-emitted value for whichever source fired.
  JoinedSnapshot _rejoin({GraphSnapshot? work, GraphSnapshot? state}) => _join(
    work ?? _work.current,
    state ?? _state.current,
    _headSnapshot?.call(),
    onUnresolvedCrossLink: _onUnresolvedCrossLink,
    dualRead: _dualRead,
  );

  /// Re-emits a FRESH-instance copy of [latest] — the kernel's backoff re-poke
  /// (a cooldown expired; `WorkList` must re-run the frontier predicate). A
  /// fresh instance is required because [JoinedSnapshot] is reference-y (no
  /// value equality), so re-pushing the same instance would be a no-op.
  void repush() {
    _push(
      JoinedSnapshot(
        graph: _latest.graph,
        sessionsByWorkBead: _latest.sessionsByWorkBead,
        mountAttemptsByWorkBead: _latest.mountAttemptsByWorkBead,
      ),
    );
  }

  /// The single push funnel: records the producer-side [latest], then drives
  /// the notifier.
  void _push(JoinedSnapshot joined) {
    _latest = joined;
    notifier.push(joined);
  }

  /// Cancels both subscriptions and, if the bridge created the notifier,
  /// disposes it. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _workSub?.cancel();
    _stateSub?.cancel();
    _workSub = null;
    _stateSub = null;
    _removeHeadListener?.call();
    _removeHeadListener = null;
    // THE CLEAN-DOWN FIXPOINT (§0.4): one boot-final round summary, riding the
    // sessionId of the LAST terminal session of the boot. It runs HERE because
    // the driver disposes the bridge before the trajectory harness drains, so
    // the note is enqueued while there is still a writer to take it.
    final head = _headSnapshot;
    if (head != null) _dualRead?.finish(head());
    if (_ownsNotifier) notifier.dispose();
  }

  /// Joins a work snapshot with a state snapshot into the immutable value the
  /// tree builds from.
  ///
  /// `graph` is the work snapshot (or an empty baseline when there is no work
  /// snapshot yet). `sessionsByWorkBead` is every `type=session` bead in the
  /// state snapshot, projected and keyed by its `work_bead` linkage — a
  /// projection with an empty `work_bead` is skipped (it has no JOIN key).
  /// A CLOSED (terminal) session is **retained** so `WorkList` can see it and
  /// unmount the work node — terminals are never dropped from the join.
  ///
  /// Seed-then-follow holds in **both** directions: a state emission that lands
  /// before the first work baseline (`work == null`) is intentionally collapsed
  /// to [JoinedSnapshot.empty] — sessions have nothing to mount against until a
  /// work graph exists, so they are held until the work baseline arrives.
  ///
  /// Finally, the state store's OPEN `type=link` beads are folded into the work
  /// frontier by [_applyCrossLinks] — the state-owned CROSS-REPO blocking
  /// edges. This is where the link set enters the pipeline: the state axis
  /// already reaches here, so the fold adds NO new subscription and the bridge
  /// still pushes exactly once per real change.
  ///
  /// [head] is the DUAL READ's third input (cut-wiring §0.2/§0.3): a
  /// pre-fetched, immutable P1 mirror snapshot. It is PURE here — the join
  /// takes it as a value and never awaits it. Under `observe` it changes
  /// nothing the map holds; under `primary` (C3) it OVERLAYS the four
  /// certified fields onto the legacy base. The read is identity-matched
  /// (`bySessionId`) by the OVERLAY IDENTITY RULE, so a sibling row can never
  /// splice a terminal onto a live session.
  static JoinedSnapshot _join(
    GraphSnapshot? work,
    GraphSnapshot? state,
    TrajectoryHeadSnapshot? head, {
    void Function(String message)? onUnresolvedCrossLink,
    DualReadSessionObserver? dualRead,
  }) {
    if (work == null) return JoinedSnapshot.empty();
    var graph = work;
    final sessions = <String, SessionProjection>{};
    final attempts = <String, MountAttemptRecord>{};
    if (state != null) {
      for (final bead in state.beadsById.values) {
        // The DURABLE remount budget (tg-zlfu) projects in the SAME pass: the
        // mount predicate is synchronous and cannot read the store, so the
        // budget must already be in memory when `WorkList` evaluates.
        final attempt = projectMountAttempt(bead);
        if (attempt != null) {
          attempts[attempt.workBeadId] = attempt;
          continue;
        }
        if (bead.issueType != GridIssueTypes.session) continue;
        final projection = projectSession(bead);
        if (projection.workBeadId.isEmpty) continue; // no JOIN key — skip.
        sessions[projection.workBeadId] = projection;
      }
      _attachMoleculeBeads(state, sessions);
      _attachGateState(state, sessions);
      graph = _applyCrossLinks(work, state, onUnresolvedCrossLink);
    }
    // The comparator pass runs over the FINISHED sessions map — after the
    // molecule/gate attachments, so it compares what a decision would actually
    // read. It mutates nothing in `sessions`: it RETURNS the overlay entries
    // and the JOIN splices them, so the map keeps exactly one writer.
    //
    // Under `observe` that map is always empty and this is a no-op — C2's
    // "byte-for-byte what pure legacy produced" invariant is untouched. Under
    // `primary` (C3) each entry is `sessionProjectionOverlay`'s: the legacy
    // projection as BASE with P1 overriding exactly
    // `{isTerminal, completed, humanHeld, closedAt}`. Everything else — the
    // fence identity triple, the cursor, the molecule and gate attachments
    // made just above — rides its own live carrier, because wave 1 retires no
    // writer.
    if (head != null) {
      final overlays = dualRead?.observe(sessions, head);
      if (overlays != null && overlays.isNotEmpty) sessions.addAll(overlays);
    }
    return JoinedSnapshot(
      graph: graph,
      sessionsByWorkBead: sessions,
      mountAttemptsByWorkBead: attempts,
    );
  }

  /// Re-applies the state store's CROSS-REPO blocking edges over [work]'s ready
  /// set and returns the frontier the tree sees.
  ///
  /// An OPEN `type=link` bead in [state] carries its edge in its own metadata
  /// (`grid.link.from`/`to`/`type` — [CrossLinkKeys]), never as a dependency
  /// row, so no store holds a dangling reference for `bd doctor --fix` to
  /// classify orphaned and sever, and no work store is written to at all. This
  /// is the same shape [_attachGateState] already uses one level down: an OPEN
  /// state bead narrows what the tree sees; a CLOSED one retires the narrowing.
  ///
  /// The ENFORCEMENT is [applyBlockGuard]'s, shared with the federated union's
  /// dependency-row edges. Unlike that source, this one applies its edges
  /// whether or not the two ids share a store prefix: a link bead is an
  /// operator-authored edge no store's `is_blocked` knows about, so there is no
  /// origin `bd ready` to defer a same-store link to.
  ///
  /// Returns the [work] INSTANCE unchanged when nothing is excluded — the
  /// common case (no links at all, or every blocker closed) costs one scan and
  /// zero copies. A [GraphSnapshot] copies its maps on construction, so the
  /// copy is paid only when a link genuinely blocks.
  ///
  /// Note what this does NOT do: it narrows the READY set, so it gates which
  /// beads may newly mount. A bead already carrying a live session stays
  /// mounted (`work_list.dart`'s stays-mounted rule) — authoring a link never
  /// kills a running agent.
  static GraphSnapshot _applyCrossLinks(
    GraphSnapshot work,
    GraphSnapshot state,
    void Function(String message)? onUnresolved,
  ) {
    final links = projectCrossLinks(state, onMalformed: onUnresolved);
    if (links.isEmpty) return work;
    final guarded = applyBlockGuard(
      candidates: work.readyIds,
      beadsById: work.beadsById,
      edges: crossLinkEdges(links),
      onUnresolved: onUnresolved,
    );
    if (guarded.length == work.readyIds.length) return work;
    return GraphSnapshot(
      beadsById: work.beadsById,
      dependencies: work.dependencies,
      readyIds: guarded,
      capturedAt: work.capturedAt,
    );
  }

  /// sessionId → workBeadId, shared by [_attachGateState] and
  /// [_attachMoleculeBeads] — both resolve a foreign bead's own `blocks`/
  /// `session` stamp (a sessionId) back to the [sessions] map's workBeadId
  /// keying.
  static Map<String, String> _workBeadIdBySessionId(
    Map<String, SessionProjection> sessions,
  ) {
    final byId = <String, String>{};
    sessions.forEach((workBeadId, projection) {
      final sessionId = projection.sessionId;
      if (sessionId != null) byId[sessionId] = workBeadId;
    });
    return byId;
  }

  static _JoinedStepIncarnation? _incarnationForGate(
    Bead gate,
    List<_JoinedStepIncarnation> candidates,
  ) {
    if (candidates.isEmpty) return null;
    final gateCreatedAt = gate.createdAt;
    if (gateCreatedAt == null) {
      return candidates.length == 1 ? candidates.single : null;
    }
    _JoinedStepIncarnation? selected;
    for (final candidate in candidates) {
      final stepCreatedAt = candidate.bead.createdAt;
      if (stepCreatedAt == null || stepCreatedAt.isAfter(gateCreatedAt)) {
        continue;
      }
      if (selected == null) {
        selected = candidate;
        continue;
      }
      final selectedCreatedAt = selected.bead.createdAt!;
      if (stepCreatedAt.isAfter(selectedCreatedAt) ||
          (stepCreatedAt.isAtSameMomentAs(selectedCreatedAt) &&
              candidate.ordinal > selected.ordinal)) {
        selected = candidate;
      }
    }
    return selected;
  }

  /// Scans [state] for `type=gate` beads (D-7), folding open blockers and
  /// durable closed-gate history into each matching session projection. The
  /// open set is the re-arm signal `SessionScope` reads; the closed counts are
  /// the history-as-state source for gate-resume circuit rounds.
  ///
  /// A gate bead carries `metadata.blocks` (a sessionId) + `metadata.node` (a
  /// nodePath). Mutates [sessions] in place, rebuilding every projection with
  /// `copyWith`. A gate whose `blocks` matches no known session is ignored.
  /// Like the session scan, this is the JOIN's job (`projectSession` stays pure
  /// — a session bead never names its own gate).
  static void _attachGateState(
    GraphSnapshot state,
    Map<String, SessionProjection> sessions,
  ) {
    final workBeadBySessionId = _workBeadIdBySessionId(sessions);
    final incarnations = <String, Map<String, List<_JoinedStepIncarnation>>>{};
    for (final entry in sessions.entries) {
      final projection = entry.value;
      final depths = supersedesDepthByStepId(
        projection.moleculeBeads,
        projection.moleculeDependencies,
      );
      final byPath = incarnations[entry.key] ??=
          <String, List<_JoinedStepIncarnation>>{};
      for (final bead in projection.moleculeBeads) {
        if (bead.issueType != GridIssueTypes.step) continue;
        final nodePath = bead.metadata[MoleculeStepKeys.path];
        if (nodePath is! String || nodePath.isEmpty) continue;
        (byPath[nodePath] ??= <_JoinedStepIncarnation>[]).add((
          bead: bead,
          ordinal: depths[bead.id] ?? 0,
        ));
      }
    }

    final openByWorkBead = <String, Set<String>>{};
    final closedByWorkBead = <String, Map<String, int>>{};
    for (final bead in state.beadsById.values) {
      if (bead.issueType != GridIssueTypes.gate) continue;
      final blocks = bead.metadata['blocks'] as String?;
      final nodePath = bead.metadata['node'] as String?;
      if (blocks == null || nodePath == null) continue;
      final workBeadId = workBeadBySessionId[blocks];
      if (workBeadId == null) continue;
      if (!bead.isClosed) {
        (openByWorkBead[workBeadId] ??= <String>{}).add(nodePath);
        continue;
      }
      final owner = _incarnationForGate(
        bead,
        incarnations[workBeadId]?[nodePath] ?? const <_JoinedStepIncarnation>[],
      );
      if (owner == null) continue;
      final counts = closedByWorkBead[workBeadId] ??= <String, int>{};
      final key = closedGateCountKey(nodePath, owner.ordinal);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    for (final entry in sessions.entries.toList()) {
      sessions[entry.key] = entry.value.copyWith(
        openGateNodes: openByWorkBead[entry.key] ?? const <String>{},
        closedGateCountByNodePath:
            closedByWorkBead[entry.key] ?? const <String, int>{},
      );
    }
  }

  /// Scans [state] for `type=molecule`/`type=step` beads (R1's molecule
  /// schema, `DESIGN-tg-pm6.md` §4) and folds each one into the matching
  /// session projection's [SessionProjection.moleculeBeads] — the read-path
  /// substrate neither original proposal specified (§2, §10/R5a).
  ///
  /// A molecule bead carries its owning session id under
  /// [MoleculeCircuitKeys.session]; a step bead under
  /// [MoleculeStepKeys.session]. Mutates [sessions] in place, rebuilding the
  /// touched projection with `copyWith`, exactly like [_attachGateState]. A
  /// bead with no session stamp, or one stamped for a session this join does
  /// not know about, is skipped fail-closed — it never leaks into any
  /// session's bucket, and (being `type=molecule`/`type=step`, both non-core
  /// — `IssueType.isCore` — `driveable_work.dart`) it was never eligible to
  /// leak into a work/drive projection in the first place (the
  /// `work_list.dart:317` gate holds independently of this join).
  ///
  /// A FLAT session (no `type=molecule`/`type=step` beads ever minted for it)
  /// folds nothing here, so [SessionProjection.moleculeBeads] stays the
  /// freezed-default empty list — the additivity story: a flat projection's
  /// other fields are never touched by this scan.
  static void _attachMoleculeBeads(
    GraphSnapshot state,
    Map<String, SessionProjection> sessions,
  ) {
    final workBeadBySessionId = _workBeadIdBySessionId(sessions);
    final beadsByWorkBead = <String, List<Bead>>{};
    final workBeadByMoleculeBeadId = <String, String>{};
    for (final bead in state.beadsById.values) {
      final String? sessionId;
      if (bead.issueType == GridIssueTypes.molecule) {
        sessionId = bead.metadata[MoleculeCircuitKeys.session] as String?;
      } else if (bead.issueType == GridIssueTypes.step) {
        sessionId = bead.metadata[MoleculeStepKeys.session] as String?;
      } else {
        continue;
      }
      if (sessionId == null) continue; // unstamped — skip, fail-closed.
      final workBeadId = workBeadBySessionId[sessionId];
      if (workBeadId == null) continue; // stamped for an unknown session.
      (beadsByWorkBead[workBeadId] ??= <Bead>[]).add(bead);
      workBeadByMoleculeBeadId[bead.id] = workBeadId;
    }
    final depsByWorkBead = <String, List<BeadDependency>>{};
    for (final dep in state.dependencies) {
      final workBeadId = workBeadByMoleculeBeadId[dep.issueId];
      if (workBeadId == null) continue;
      if (workBeadByMoleculeBeadId[dep.dependsOnId] != workBeadId) continue;
      (depsByWorkBead[workBeadId] ??= <BeadDependency>[]).add(dep);
    }
    beadsByWorkBead.forEach((workBeadId, beads) {
      final projection = sessions[workBeadId];
      if (projection != null) {
        sessions[workBeadId] = projection.copyWith(
          moleculeBeads: beads,
          moleculeDependencies: depsByWorkBead[workBeadId] ?? const [],
        );
      }
    });
  }
}
