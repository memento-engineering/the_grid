import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import '../domain/joined_snapshot.dart';
import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../molecule/molecule_schema.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import 'snapshot_source.dart';

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
  factory StationJoinBridge({
    required SnapshotSource work,
    required SnapshotSource state,
    JoinedSnapshotNotifier? notifier,
  }) {
    final seed = _join(work.current, state.current);
    return StationJoinBridge._(
      work: work,
      state: state,
      ownsNotifier: notifier == null,
      notifier: notifier ?? JoinedSnapshotNotifier(seed),
      latest: seed,
    );
  }

  StationJoinBridge._({
    required SnapshotSource work,
    required SnapshotSource state,
    required bool ownsNotifier,
    required this.notifier,
    required JoinedSnapshot latest,
  }) : _work = work,
       _state = state,
       _ownsNotifier = ownsNotifier,
       _latest = latest;

  final SnapshotSource _work;
  final SnapshotSource _state;
  final bool _ownsNotifier;
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
    _push(_join(_work.current, _state.current));
    // Use the freshly-emitted snapshot for the source that fired and `.current`
    // for the other — one push per real emission, never two for one change.
    _workSub = _work.snapshots.listen((workSnapshot) {
      _push(_join(workSnapshot, _state.current));
    });
    _stateSub = _state.snapshots.listen((stateSnapshot) {
      _push(_join(_work.current, stateSnapshot));
    });
  }

  /// Re-emits a FRESH-instance copy of [latest] — the kernel's backoff re-poke
  /// (a cooldown expired; `WorkList` must re-run the frontier predicate). A
  /// fresh instance is required because [JoinedSnapshot] is reference-y (no
  /// value equality), so re-pushing the same instance would be a no-op.
  void repush() {
    _push(
      JoinedSnapshot(
        graph: _latest.graph,
        sessionsByWorkBead: _latest.sessionsByWorkBead,
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
  static JoinedSnapshot _join(GraphSnapshot? work, GraphSnapshot? state) {
    if (work == null) return JoinedSnapshot.empty();
    final sessions = <String, SessionProjection>{};
    if (state != null) {
      for (final bead in state.beadsById.values) {
        if (bead.issueType != IssueType.session) continue;
        final projection = projectSession(bead);
        if (projection.workBeadId.isEmpty) continue; // no JOIN key — skip.
        sessions[projection.workBeadId] = projection;
      }
      _attachOpenGates(state, sessions);
      _attachMoleculeBeads(state, sessions);
    }
    return JoinedSnapshot(graph: work, sessionsByWorkBead: sessions);
  }

  /// sessionId → workBeadId, shared by [_attachOpenGates] and
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

  /// Scans [state] for OPEN `type=gate` beads (D-7) and folds each one's blocked
  /// node into the matching session projection's `openGateNodes` — the re-arm
  /// signal `SessionScope` reads (a node leaves the set when its gate closes).
  ///
  /// A gate bead carries `metadata.blocks` (a sessionId) + `metadata.node` (a
  /// nodePath). Mutates [sessions] in place, rebuilding the touched projection
  /// with `copyWith`. A gate whose `blocks` matches no known session — or that
  /// is CLOSED (resolved) — is ignored, so `openGateNodes` reflects only live
  /// gates. Like the session scan, this is the JOIN's job (`projectSession`
  /// stays pure — a session bead never names its own gate).
  static void _attachOpenGates(
    GraphSnapshot state,
    Map<String, SessionProjection> sessions,
  ) {
    // sessionId → workBeadId, so a gate's `blocks` (a sessionId) finds its
    // projection (keyed by workBeadId).
    final workBeadBySessionId = _workBeadIdBySessionId(sessions);
    final gateNodesByWorkBead = <String, Set<String>>{};
    for (final bead in state.beadsById.values) {
      if (bead.issueType != IssueType.gate) continue;
      if (bead.isClosed) continue; // a resolved gate re-arms — drop it.
      final blocks = bead.metadata['blocks'] as String?;
      if (blocks == null) continue;
      final workBeadId = workBeadBySessionId[blocks];
      if (workBeadId == null) continue; // blocks an unknown session — ignore.
      final node = bead.metadata['node'] as String?;
      if (node == null) continue;
      (gateNodesByWorkBead[workBeadId] ??= <String>{}).add(node);
    }
    gateNodesByWorkBead.forEach((workBeadId, nodes) {
      final projection = sessions[workBeadId];
      if (projection != null) {
        sessions[workBeadId] = projection.copyWith(openGateNodes: nodes);
      }
    });
  }

  /// Scans [state] for `type=molecule`/`type=step` beads (R1's molecule
  /// schema, `DESIGN-tg-pm6.md` §4) and folds each one into the matching
  /// session projection's [SessionProjection.moleculeBeads] — the read-path
  /// substrate neither original proposal specified (§2, §10/R5a).
  ///
  /// A molecule bead carries its owning session id under
  /// [MoleculeCircuitKeys.session]; a step bead under
  /// [MoleculeStepKeys.session]. Mutates [sessions] in place, rebuilding the
  /// touched projection with `copyWith`, exactly like [_attachOpenGates]. A
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
      if (bead.issueType == IssueType.molecule) {
        sessionId = bead.metadata[MoleculeCircuitKeys.session] as String?;
      } else if (bead.issueType == IssueType.step) {
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
