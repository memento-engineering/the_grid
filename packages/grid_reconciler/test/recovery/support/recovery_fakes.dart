import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';

import '../../support/fakes.dart';

// Track C is not yet on the package barrel (the orchestrator wires it after
// this track lands — collision rule 1), so dependent tests reach it through
// this re-export from the recovery sub-barrel.
export 'package:grid_reconciler/src/recovery/recovery.dart';

// Re-export the base builders so recovery tests need one import.
export '../../support/fakes.dart'
    show convergenceBead, wispBead, parentChild, snap, fakeClock;

/// Recovery-test scaffolding (fakes-not-mocks, repo convention): builds
/// synthetic [GraphSnapshot]s of convergence roots + wisp children so the pure
/// recovery pass can be exercised exactly as Track G will read it.
///
/// gc's `handler_test.go` fake store stamps `CreatedAt = now − 10m`,
/// `ClosedAt = now` on every bead (handler_test.go:48-71) so the duration math
/// is deterministic (≈600000 ms per closed wisp); [closedWisp] mirrors that.

/// gc's fake-store timestamps (handler_test.go:48-71).
final recoveryCreatedAt = fakeClock.subtract(const Duration(minutes: 10));
final recoveryClosedAt = fakeClock;

/// One closed wisp's contribution to cumulative duration (≈600000 ms).
final closedWispDurationMs = recoveryClosedAt
    .difference(recoveryCreatedAt)
    .inMilliseconds;

/// A wisp child of [rootId] at [iteration] (key `converge:<root>:iter:<N>`),
/// with gc's deterministic timestamps. Closed by default.
Bead wisp(
  String rootId,
  int iteration, {
  String? id,
  BeadStatus status = BeadStatus.closed,
  Map<String, dynamic> extraMetadata = const {},
}) => wispBead(
  id ?? 'wisp-iter-$iteration',
  key: idempotencyKey(rootId, iteration),
  status: status,
  createdAt: recoveryCreatedAt,
  closedAt: status == BeadStatus.closed ? recoveryClosedAt : null,
  extraMetadata: extraMetadata,
);

/// A wisp child with an explicit [id] and [key] (foreign / unparseable keys).
Bead wispKeyed(
  String id, {
  required String key,
  required String rootId,
  BeadStatus status = BeadStatus.closed,
}) => wispBead(
  id,
  key: key,
  status: status,
  createdAt: recoveryCreatedAt,
  closedAt: status == BeadStatus.closed ? recoveryClosedAt : null,
);

/// Builds a single-root snapshot: [root] plus [children], each linked to the
/// root by a parent-child edge (gc's direction).
GraphSnapshot rootSnap(Bead root, {List<Bead> children = const []}) {
  final deps = <BeadDependency>[
    for (final child in children) parentChild(child.id, root.id),
  ];
  return snap([root, ...children], deps: deps);
}

/// Projects [root] + [children] into a [Convergence] (the recovery pass takes
/// the projection; this mirrors what `ConvergenceRecovery._scan` produces).
({Convergence convergence, GraphSnapshot snapshot}) project(
  Bead root, {
  List<Bead> children = const [],
}) {
  final snapshot = rootSnap(root, children: children);
  final result = Convergence.project(
    root,
    dependencies: snapshot.dependencies,
    beadsById: snapshot.beadsById,
  );
  return (
    convergence: (result as ProjectionOk<Convergence>).value,
    snapshot: snapshot,
  );
}

/// The single outcome of reconciling [root] (+ optional [children]) — the
/// common one-root case.
RecoveryOutcome reconcileOne(Bead root, {List<Bead> children = const []}) {
  final snapshot = rootSnap(root, children: children);
  return ConvergenceRecovery.reconcile(snapshot).outcomes.single;
}

/// gc's `setupReconciler` baseline metadata (reconcile_test.go fixtures): the
/// create-time keys a started loop carries. [state] and [extra] override.
Map<String, dynamic> meta({
  String? state,
  Map<String, dynamic> extra = const {},
}) => <String, dynamic>{
  if (state != null) ConvergenceFields.state: state,
  ConvergenceFields.formula: 'test-formula',
  ConvergenceFields.maxIterations: '5',
  ConvergenceFields.target: 'test-agent',
  ...extra,
};
