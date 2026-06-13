import 'package:grid_controller/grid_controller.dart';
import 'package:riverpod/riverpod.dart';

import 'recovery_outcome.dart';
import 'recovery_pass.dart';

/// The full-reconcile pass as a pure selector over grid_controller's
/// [graphSnapshotProvider] (ADR-0002 D2 style, mirroring
/// `convergence_providers.dart`): no new IO — it watches the snapshot stream
/// and runs [ConvergenceRecovery.reconcile] over it.
///
/// This is the **backstop** cadence's read surface: Track G watches it at a low
/// frequency (and once at startup) and actuates the non-empty outcomes,
/// serialized per bead (ADR-0003 invariant 7). On an absent snapshot it yields
/// an empty report (scanned 0) — gc's clean-store all-`no_action` shape.
///
/// ⚠ Coexistence (ADR-0003 Decision 6): the outcomes here are MUTATING plans.
/// Track G must filter to grid-owned beads before actuating; shadow mode diffs
/// them and writes nothing.
final recoveryReportProvider = Provider<RecoveryReport>((ref) {
  final snapshot = ref.watch(graphSnapshotProvider).value;
  if (snapshot == null) return RecoveryReport(const []);
  return ConvergenceRecovery.reconcile(snapshot);
});
