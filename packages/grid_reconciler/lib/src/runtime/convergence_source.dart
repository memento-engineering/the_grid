import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import '../projections/convergence.dart';

/// The runtime's read seam over beads_dart's reactive surface — the
/// current set of convergence loops + the snapshot they project from, plus the
/// event and snapshot streams.
///
/// The live implementation ([GridConvergenceSource]) reads
/// beads_dart's `GridControllerRuntime` (its `events`/`snapshots` streams
/// and `current` snapshot, projecting `convergence`-typed beads exactly as
/// `convergencesProvider` does). Tests inject a [FakeConvergenceSource] driving
/// a synthetic event stream + a programmable snapshot. The seam keeps the
/// orchestrator free of Riverpod and of beads_dart's projection wiring.
abstract interface class ConvergenceSource {
  /// The live typed change events (beads_dart's `GraphEvent` stream).
  Stream<GraphEvent> get events;

  /// Fresh snapshots as the graph changes.
  Stream<GraphSnapshot> get snapshots;

  /// The most recent snapshot, or null before the baseline.
  GraphSnapshot? get current;

  /// Projects every `convergence`-typed bead in the current snapshot — the
  /// `convergencesProvider` projection, computed on demand (the runtime
  /// re-reads it per cycle so it always reduces over fresh state).
  List<Convergence> get convergences;

  /// One convergence loop by root id, or null.
  Convergence? convergence(String id);
}

/// The live [ConvergenceSource] over a beads_dart [GridControllerRuntime].
class GridConvergenceSource implements ConvergenceSource {
  GridConvergenceSource(this._runtime);

  final GridControllerRuntime _runtime;

  @override
  Stream<GraphEvent> get events => _runtime.events;

  @override
  Stream<GraphSnapshot> get snapshots => _runtime.snapshots;

  @override
  GraphSnapshot? get current => _runtime.current;

  @override
  List<Convergence> get convergences => projectConvergences(_runtime.current);

  @override
  Convergence? convergence(String id) {
    for (final c in convergences) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Projects every `convergence`-typed bead in [snapshot] (the
/// `convergencesProvider` body, reusable by sources and shadow mode). Decode
/// failures are dropped from the list; per-field metadata failures remain on
/// each [Convergence.metadata].
List<Convergence> projectConvergences(GraphSnapshot? snapshot) {
  if (snapshot == null) return const [];
  final out = <Convergence>[];
  for (final bead in snapshot.beads) {
    if (bead.issueType != IssueType.convergence) continue;
    final result = Convergence.project(
      bead,
      dependencies: snapshot.dependencies,
      beadsById: snapshot.beadsById,
    );
    if (result case ProjectionOk<Convergence>(:final value)) out.add(value);
  }
  return out;
}
