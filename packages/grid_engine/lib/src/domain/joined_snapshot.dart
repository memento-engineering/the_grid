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
  const JoinedSnapshot({
    required this.graph,
    this.sessionsByWorkBead = const {},
  });

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
  ///
  /// Each [SessionProjection] carries its own model discriminator
  /// ([SessionProjection.isMolecule]) and, for a molecule-mode session, its
  /// own `type=molecule`/`type=step` beads bucketed by the join into
  /// [SessionProjection.moleculeBeads] (`DESIGN-tg-pm6.md` §10, R5a) — always
  /// empty for a flat session. [JoinedSnapshot] itself carries no new field
  /// for the molecule model: the bucket rides inside the per-session
  /// projection it already holds, so a molecule session is additive, not a
  /// second parallel join.
  final Map<String, SessionProjection> sessionsByWorkBead;
}
