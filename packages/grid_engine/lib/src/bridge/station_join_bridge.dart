import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import '../domain/joined_snapshot.dart';
import '../domain/rework.dart';
import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
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
///   [JoinedSnapshot.sessionsByWorkBead].
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
      _attachReworkRounds(sessions);
    }
    return JoinedSnapshot(graph: work, sessionsByWorkBead: sessions);
  }

  /// Scans [state] for OPEN `type=gate` beads (D-7) and folds each one into the
  /// matching session projection's `openGates` — the re-arm signal
  /// `SessionScope` reads (a node leaves the map when its gate closes), plus the
  /// gate bead's own id + reason (tg-b3k), so the scope can auto-resolve a
  /// MACHINE-ACTIONABLE park and close that exact bead through the chokepoint
  /// without re-querying the store (A39).
  ///
  /// A gate bead carries `metadata.blocks` (a sessionId) + `metadata.node` (a
  /// nodePath) + `metadata.reason`. Mutates [sessions] in place, rebuilding the
  /// touched projection with `copyWith`. A gate whose `blocks` matches no known
  /// session — or that is CLOSED (resolved) — is ignored, so `openGates`
  /// reflects only live gates. Like the session scan, this is the JOIN's job
  /// (`projectSession` stays pure — a session bead never names its own gate).
  static void _attachOpenGates(
    GraphSnapshot state,
    Map<String, SessionProjection> sessions,
  ) {
    // sessionId → workBeadId, so a gate's `blocks` (a sessionId) finds its
    // projection (keyed by workBeadId).
    final workBeadBySessionId = <String, String>{};
    sessions.forEach((workBeadId, projection) {
      final sessionId = projection.sessionId;
      if (sessionId != null) workBeadBySessionId[sessionId] = workBeadId;
    });
    final gatesByWorkBead = <String, Map<String, OpenGate>>{};
    for (final bead in state.beadsById.values) {
      if (bead.issueType != IssueType.gate) continue;
      if (bead.isClosed) continue; // a resolved gate re-arms — drop it.
      final blocks = bead.metadata['blocks'] as String?;
      if (blocks == null) continue;
      final workBeadId = workBeadBySessionId[blocks];
      if (workBeadId == null) continue; // blocks an unknown session — ignore.
      final node = bead.metadata['node'] as String?;
      if (node == null) continue;
      (gatesByWorkBead[workBeadId] ??= <String, OpenGate>{})[node] = OpenGate(
        gateId: bead.id,
        nodePath: node,
        // The gate's REASON is the asset↔engine contract the auto-respec
        // transition reads (tg-b3k) — carried down pull-free (A39), so a tree
        // node never re-queries the store to learn why it parked.
        reason: (bead.metadata['reason'] as String?) ?? '',
      );
    }
    gatesByWorkBead.forEach((workBeadId, gates) {
      final projection = sessions[workBeadId];
      if (projection != null) {
        sessions[workBeadId] = projection.copyWith(openGates: gates);
      }
    });
  }

  /// Folds each session's RETIRED-ROUND count into its projection (tg-b3k) — the
  /// highest `N` across every session in this join keyed `<workBeadId>#r<N>`.
  ///
  /// Like [_attachOpenGates] this is the JOIN's job: a session bead never names
  /// its own retired rounds (`projectSession` stays pure), but the join sees them
  /// all (`_join` retains CLOSED sessions, so a retired round is a live map key)
  /// — so `SessionScope` can pick the next round and honour [kMaxReworkRounds]
  /// pull-free (A39), never re-querying the store from a tree node. `updateAll`
  /// rewrites values in place (it adds/removes no keys, so iterating the same map
  /// is safe).
  static void _attachReworkRounds(Map<String, SessionProjection> sessions) {
    final keys = sessions.keys.toList();
    sessions.updateAll((workBeadId, projection) {
      final rounds = maxReworkRound(workBeadId, keys);
      return rounds == 0
          ? projection
          : projection.copyWith(reworkRounds: rounds);
    });
  }
}
