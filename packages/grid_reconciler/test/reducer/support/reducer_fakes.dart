import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';

import '../../support/fakes.dart';

// Re-export the base bead/snapshot builders so reducer tests need one import.
export '../../support/fakes.dart'
    show convergenceBead, wispBead, parentChild, snap, fakeClock;

/// Reducer-test scaffolding: builds synthetic [Convergence] projections from
/// beads + parent-child edges (repo fakes-not-mocks convention) so the pure
/// reducer can be exercised exactly as Track G will call it.
///
/// gc's `handler_test.go` fake store sets `CreatedAt = now − 10m` and
/// `ClosedAt = now` on EVERY bead (handler_test.go:60-61) so duration math is
/// deterministic; [wispChild] mirrors that.

/// gc's fake-store timestamps: CreatedAt = [fakeClock] − 10m, ClosedAt =
/// [fakeClock] (handler_test.go:48-71).
final wispCreatedAt = fakeClock.subtract(const Duration(minutes: 10));
final wispClosedAt = fakeClock;

/// A closed wisp child of [rootId] at [iteration] (key
/// `converge:<root>:iter:<N>`). Timestamps mirror gc's fake.
Bead wispChild(
  String rootId,
  int iteration, {
  String? id,
  BeadStatus status = BeadStatus.closed,
  Map<String, dynamic> extraMetadata = const {},
}) => wispBead(
  id ?? 'wisp-iter-$iteration',
  key: idempotencyKey(rootId, iteration),
  status: status,
  createdAt: wispCreatedAt,
  closedAt: status == BeadStatus.closed ? wispClosedAt : null,
  extraMetadata: extraMetadata,
);

/// A wisp with an arbitrary (possibly foreign / unparseable) [key].
Bead wispChildKey(
  String id, {
  required String key,
  BeadStatus status = BeadStatus.closed,
  Map<String, dynamic> extraMetadata = const {},
}) => wispBead(
  id,
  key: key,
  status: status,
  createdAt: wispCreatedAt,
  closedAt: status == BeadStatus.closed ? wispClosedAt : null,
  extraMetadata: extraMetadata,
);

/// gc's `setupBasicHandler` baseline (handler_test.go:347-378): root `root-1`
/// (in_progress) with the eight baseline metadata keys + one closed wisp
/// `wisp-iter-1` (key iter:1). [extra] is merged on top of the baseline
/// metadata. Additional [wisps] are appended as parent-child children.
///
/// Returns the projected [Convergence] AND the backing [GraphSnapshot] (some
/// reductions need the snapshot's cross-bead reads).
({Convergence convergence, GraphSnapshot snapshot}) baseline({
  String rootId = 'root-1',
  Map<String, dynamic> extra = const {},
  List<Bead> wisps = const [],
  bool includeDefaultWisp = true,
}) {
  final meta = <String, dynamic>{
    ConvergenceFields.state: 'active',
    ConvergenceFields.iteration: '1',
    ConvergenceFields.maxIterations: '5',
    ConvergenceFields.formula: 'test-formula',
    ConvergenceFields.target: 'test-agent',
    ConvergenceFields.gateMode: 'condition',
    ConvergenceFields.gateTimeout: '60s',
    ConvergenceFields.gateTimeoutAction: 'iterate',
    ...extra,
  };
  final root = convergenceBead(rootId, metadata: meta);
  final children = <Bead>[
    if (includeDefaultWisp) wispChild(rootId, 1),
    ...wisps,
  ];
  return project(root, children);
}

/// `setupWaitingManualHandler` (manual_test.go:15-46): root `root-1` in
/// `waiting_manual` with one closed wisp `wisp-iter-1` and
/// `last_processed_wisp=wisp-iter-1`. [extra] merges on top.
({Convergence convergence, GraphSnapshot snapshot}) waitingManual({
  String rootId = 'root-1',
  Map<String, dynamic> extra = const {},
  List<Bead> wisps = const [],
  bool includeDefaultWisp = true,
}) {
  final meta = <String, dynamic>{
    ConvergenceFields.state: 'waiting_manual',
    ConvergenceFields.iteration: '1',
    ConvergenceFields.maxIterations: '5',
    ConvergenceFields.formula: 'test-formula',
    ConvergenceFields.target: 'test-agent',
    ConvergenceFields.gateMode: 'manual',
    ConvergenceFields.waitingReason: 'manual',
    ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
    ...extra,
  };
  final root = convergenceBead(rootId, metadata: meta);
  final children = <Bead>[
    if (includeDefaultWisp) wispChild(rootId, 1),
    ...wisps,
  ];
  return project(root, children);
}

/// `setupTriggerHandler` (trigger_test.go:81-104): root `root-1` in
/// `waiting_trigger`, iteration 0, trigger=event. No children by default.
({Convergence convergence, GraphSnapshot snapshot}) waitingTrigger({
  String rootId = 'root-1',
  Map<String, dynamic> extra = const {},
  List<Bead> wisps = const [],
}) {
  final meta = <String, dynamic>{
    ConvergenceFields.state: 'waiting_trigger',
    ConvergenceFields.iteration: '0',
    ConvergenceFields.maxIterations: '5',
    ConvergenceFields.formula: 'test-formula',
    ConvergenceFields.target: 'test-agent',
    ConvergenceFields.gateMode: 'condition',
    ConvergenceFields.gateCondition: '/gate/ignored-in-trigger-tests',
    ConvergenceFields.gateTimeout: '60s',
    ConvergenceFields.trigger: 'event',
    ConvergenceFields.triggerCondition: '/trigger/check.sh',
    ...extra,
  };
  final root = convergenceBead(rootId, metadata: meta);
  return project(root, wisps);
}

/// Projects [root] with [children] (each linked via a parent-child edge) into
/// a [Convergence] + the backing snapshot.
({Convergence convergence, GraphSnapshot snapshot}) project(
  Bead root,
  List<Bead> children,
) {
  final deps = <BeadDependency>[
    for (final child in children) parentChild(child.id, root.id),
  ];
  // Also wire any grandchildren edges present in extra beads via their own
  // metadata is not needed here — children are flat wisps.
  final snapshot = snap([root, ...children], deps: deps);
  final result = Convergence.project(
    root,
    dependencies: deps,
    beadsById: snapshot.beadsById,
  );
  return (
    convergence: (result as ProjectionOk<Convergence>).value,
    snapshot: snapshot,
  );
}

/// Replay metadata: `gate_outcome_wisp=[wisp]` + `gate_outcome=[outcome]`
/// (+ optional extras), the `replay <x>` shorthand from the conformance spec.
Map<String, dynamic> replay(
  String outcome, {
  String wisp = 'wisp-iter-1',
  Map<String, dynamic> extra = const {},
}) => {
  ConvergenceFields.gateOutcomeWisp: wisp,
  ConvergenceFields.gateOutcome: outcome,
  ConvergenceFields.gateRetryCount: '0',
  ...extra,
};
