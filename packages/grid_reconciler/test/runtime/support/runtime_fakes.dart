import 'dart:async';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';

import '../../support/fakes.dart';

export '../../support/fakes.dart'
    show convergenceBead, wispBead, parentChild, snap, fakeClock;

/// A test [ConvergenceSource] over a programmable snapshot + a synthetic event
/// stream. Drives the runtime exactly as the live `GridConvergenceSource`
/// would, but with no IO: the test pushes snapshots via [setSnapshot] and
/// events via [emit].
class FakeConvergenceSource implements ConvergenceSource {
  FakeConvergenceSource([GraphSnapshot? initial]) : _current = initial;

  GraphSnapshot? _current;
  final StreamController<GraphEvent> _events =
      StreamController<GraphEvent>.broadcast();
  final StreamController<GraphSnapshot> _snapshots =
      StreamController<GraphSnapshot>.broadcast();

  @override
  Stream<GraphEvent> get events => _events.stream;

  @override
  Stream<GraphSnapshot> get snapshots => _snapshots.stream;

  @override
  GraphSnapshot? get current => _current;

  @override
  List<Convergence> get convergences => projectConvergences(_current);

  @override
  Convergence? convergence(String id) {
    for (final c in convergences) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Replaces the current snapshot and notifies the snapshot stream.
  void setSnapshot(GraphSnapshot snapshot) {
    _current = snapshot;
    _snapshots.add(snapshot);
  }

  /// Replaces the snapshot WITHOUT emitting on the stream (simulates the
  /// post-actuation store state the live probe would see while the watcher
  /// still lags — used to prove the write-through overlay, not the snapshot,
  /// is what deduplicates).
  void setSnapshotSilently(GraphSnapshot snapshot) {
    _current = snapshot;
  }

  /// Emits a graph event onto the stream.
  void emit(GraphEvent event) => _events.add(event);

  Future<void> close() async {
    await _events.close();
    await _snapshots.close();
  }
}

/// An [Actuator] that RECORDS every apply and flags whether it was ever asked
/// to perform a mutating action — the shadow-safety canary. It also threads a
/// programmable [ActuationResult] per apply (for the in-list pour id / requeue)
/// and can be made to FAIL on a chosen bead (the A25 deferred-error contract).
///
/// "Mutating" = any action whose [ReconcilerAction.wire] is non-null (the
/// transition vocabulary) OR a pour/burn/persist carrier. A pure `skipped`
/// (no writes) does not flag — the writing runtime applying a skip is harmless.
class RecordingActuator implements Actuator {
  RecordingActuator({this.nextResult});

  /// Programmable result for the next apply (then reset to null).
  ActuationResult? nextResult;

  /// Every action applied, flattened, in order.
  final List<ReconcilerAction> actions = [];

  /// Every (result, convergence) applied.
  final List<ReduceResult> applied = [];

  /// Set true the first time any mutating action is applied.
  bool didMutate = false;

  /// Per-bead apply count.
  final Map<String, int> appliesByBead = {};

  /// When set, apply throws [ActuationFailed] for this bead (the live-error
  /// injection). Cleared after it fires once unless [failPersistently].
  String? failBead;
  bool failPersistently = false;
  int failCount = 0;

  /// Optional artificial latency per apply — used to make a recovery pass
  /// outrun the periodic interval so the re-entrancy guard can be exercised.
  Duration? applyDelay;

  @override
  Future<ActuationResult> apply(
    ReduceResult result,
    Convergence convergence,
  ) async {
    final delay = applyDelay;
    if (delay != null) await Future<void>.delayed(delay);
    applied.add(result);
    actions.addAll(result.actions);
    appliesByBead.update(convergence.id, (n) => n + 1, ifAbsent: () => 1);
    for (final action in result.actions) {
      if (_isMutating(action)) didMutate = true;
    }
    if (failBead == convergence.id) {
      failCount++;
      if (!failPersistently) failBead = null;
      throw ActuationFailed('injected live failure for ${convergence.id}');
    }
    final out = nextResult ?? const ActuationResult();
    nextResult = null;
    return out;
  }

  static bool _isMutating(ReconcilerAction action) {
    if (action.wire != null) return true;
    return switch (action) {
      PourSpeculativeAction() ||
      PersistGateOutcomeAction() ||
      RepairIterationAction() ||
      FailedAction() => true,
      EvaluateGateAction() || RequeueAction() || SkippedAction() => false,
      _ => false,
    };
  }
}

/// Builds a snapshot of [roots] + their [children] with parent-child edges.
GraphSnapshot snapWith({
  required List<Bead> roots,
  Map<String, List<Bead>> children = const {},
}) {
  final beads = <Bead>[...roots];
  final deps = <BeadDependency>[];
  for (final entry in children.entries) {
    for (final child in entry.value) {
      beads.add(child);
      deps.add(parentChild(child.id, entry.key));
    }
  }
  return snap(beads, deps: deps);
}

/// A `BeadClosed` event for [closed] transitioning from [before].
GraphEvent beadClosedEvent(Bead before, Bead closed) =>
    GraphEvent.beadClosed(before: before, after: closed);

/// A `BeadUpdated` event on a convergence root (shadow-mode gc-command
/// detection).
GraphEvent beadUpdatedEvent(
  Bead before,
  Bead after, {
  Set<String> changedFields = const {},
}) => GraphEvent.beadUpdated(
  before: before,
  after: after,
  changedFields: changedFields,
);

/// A convergence root in `active` state with [activeWisp] as the active wisp
/// pointer and one closed wisp at iteration 1.
({Bead root, Bead closedWisp}) activeLoop({
  String rootId = 'root-1',
  String activeWispId = 'wisp-iter-1',
  Map<String, dynamic> extra = const {},
}) {
  final root = convergenceBead(
    rootId,
    metadata: {
      ConvergenceFields.state: 'active',
      ConvergenceFields.iteration: '1',
      ConvergenceFields.maxIterations: '5',
      ConvergenceFields.formula: 'test-formula',
      ConvergenceFields.target: 'test-agent',
      ConvergenceFields.gateMode: 'condition',
      ConvergenceFields.gateCondition: '/gate/check.sh',
      ConvergenceFields.gateTimeout: '60s',
      ConvergenceFields.gateTimeoutAction: 'iterate',
      ConvergenceFields.activeWisp: activeWispId,
      ...extra,
    },
  );
  final wisp = wispBead(
    activeWispId,
    key: idempotencyKey(rootId, 1),
    status: BeadStatus.closed,
    createdAt: fakeClock.subtract(const Duration(minutes: 10)),
    closedAt: fakeClock,
  );
  return (root: root, closedWisp: wisp);
}
