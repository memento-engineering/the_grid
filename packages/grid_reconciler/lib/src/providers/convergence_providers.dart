import 'package:grid_controller/grid_controller.dart';
import 'package:riverpod/riverpod.dart';

import '../convergence/convergence_state.dart';
import '../projections/convergence.dart';
import '../projections/wisp.dart';

/// Pure convergence projection selectors over grid_controller's
/// [graphSnapshotProvider] (ADR-0002 D2 style, mirroring
/// `projection_providers.dart`): no new IO — they watch the snapshot stream
/// and project `convergence`-typed beads. Decode failures are dropped from
/// the success lists (never thrown); per-bead metadata failures remain
/// visible on each [Convergence.metadata].

GraphSnapshot? _snapshot(Ref ref) => ref.watch(graphSnapshotProvider).value;

/// All convergence loops in the current snapshot, with wisps resolved from
/// the snapshot's parent-child dependency edges.
final convergencesProvider = Provider<List<Convergence>>((ref) {
  final snapshot = _snapshot(ref);
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
});

/// One convergence loop by root bead id (null if absent or not a
/// convergence bead).
final convergenceProvider = Provider.family<Convergence?, String>((ref, id) {
  for (final convergence in ref.watch(convergencesProvider)) {
    if (convergence.id == id) return convergence;
  }
  return null;
});

/// Convergence loops grouped by their state **reading** — the five known
/// states plus the not-adopted and unrecognized readings as their own
/// groups, so nothing is silently dropped from the view.
final convergencesByStateProvider =
    Provider<Map<ConvergenceStateReading, List<Convergence>>>((ref) {
      final byState = <ConvergenceStateReading, List<Convergence>>{};
      for (final convergence in ref.watch(convergencesProvider)) {
        byState.putIfAbsent(convergence.state, () => []).add(convergence);
      }
      return byState;
    });

/// The resolved active wisp for one convergence loop (family by root bead
/// id) — null when the loop is absent, holds no `active_wisp`, or the
/// reference dangles ([Convergence.activeWisp]).
final activeWispProvider = Provider.family<Wisp?, String>((ref, id) {
  return ref.watch(convergenceProvider(id))?.activeWisp;
});
