import 'package:beads_dart/beads_dart.dart';

import 'session_projection.dart';

/// The single immutable value the tree builds from: the read-workspace work
/// graph JOINed with the_grid's owned session cursors, keyed by work bead id.
///
/// Assembled OUTSIDE the tree by the join bridge (Track B) and injected as a
/// `JoinedSnapshotNotifier` value; the tree only ever *consumes* it (A39 /
/// derailment-invariant 1) — no tree node re-detects or subscribes into a
/// pipeline.
///
/// Deliberately reference-y (like [GraphSnapshot]): change detection is the
/// bridge's job — it emits a new instance only on a real change — so this type
/// needs no deep value equality.
class JoinedSnapshot {
  /// Creates a joined value over [graph] and [sessionsByWorkBead].
  const JoinedSnapshot({required this.graph, this.sessionsByWorkBead = const {}});

  /// An empty baseline — the notifier's seed value before the first refresh
  /// (Track B: `runtime.current` may be null immediately after a fresh start;
  /// seed empty and let the first baseline refresh fill it).
  JoinedSnapshot.empty()
    : graph = GraphSnapshot.fromParts(
        beads: const [],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      sessionsByWorkBead = const {};

  /// The read-workspace work graph (pristine source — read-only, A37).
  final GraphSnapshot graph;

  /// The_grid's owned session cursor per work bead id (from the state store).
  final Map<String, SessionProjection> sessionsByWorkBead;
}
