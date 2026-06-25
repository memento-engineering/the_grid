import 'dart:async';

import 'package:grid_controller/grid_controller.dart';

import '../domain/joined_snapshot.dart';
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
/// Seed-then-follow (replicates `grid_controller`'s `graphSnapshotProvider`):
/// the underlying broadcast streams do not replay, so the notifier is seeded
/// with the current join up front (or [JoinedSnapshot.empty] when no work
/// baseline exists yet); a late notifier subscriber sees that baseline, and the
/// first real emission fills it.
class GridJoinBridge {
  /// Creates a bridge over the [work] and [state] snapshot sources.
  ///
  /// If [notifier] is supplied, the bridge drives it but does **not** own its
  /// lifecycle (it is left undisposed on [dispose]); otherwise the bridge
  /// creates one, seeded with the current join, and disposes it itself.
  GridJoinBridge({
    required SnapshotSource work,
    required SnapshotSource state,
    JoinedSnapshotNotifier? notifier,
  }) : _work = work,
       _state = state,
       _ownsNotifier = notifier == null,
       notifier = notifier ?? JoinedSnapshotNotifier(_join(work.current, state.current));

  final SnapshotSource _work;
  final SnapshotSource _state;
  final bool _ownsNotifier;

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
    notifier.push(_join(_work.current, _state.current));
    // Use the freshly-emitted snapshot for the source that fired and `.current`
    // for the other — one push per real emission, never two for one change.
    _workSub = _work.snapshots.listen((workSnapshot) {
      notifier.push(_join(workSnapshot, _state.current));
    });
    _stateSub = _state.snapshots.listen((stateSnapshot) {
      notifier.push(_join(_work.current, stateSnapshot));
    });
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
    }
    return JoinedSnapshot(graph: work, sessionsByWorkBead: sessions);
  }
}
