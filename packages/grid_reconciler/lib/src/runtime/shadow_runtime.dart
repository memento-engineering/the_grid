import 'dart:async';

import 'package:grid_controller/grid_controller.dart';

import '../convergence/reconciler_action.dart';
import '../reducer/reduce.dart';
import '../recovery/recovery_outcome.dart';
import '../recovery/recovery_pass.dart';
import 'convergence_source.dart';
import 'graph_event_adapter.dart';

/// SHADOW MODE — the strictly read-only conformance runtime (ADR-0003
/// Decision 6; ADR-0000 A7). It computes every transition the_grid WOULD make
/// over the convergence loops it observes and DIFFS them against what gc
/// ACTUALLY did (observed in subsequent snapshots), emitting a structured
/// [DivergenceReport]. It constructs **NO writer at all** — no [Actuator], no
/// `BdCliService`, nothing capable of a mutating bd verb — so it is
/// *structurally* impossible for shadow mode to write to a bead gc owns.
///
/// **Why no writer (the safety boundary).** gc's convergence handler assumes a
/// single writer per bead (invariant 7); a second reconciler on a live
/// gc-owned convergence corrupts state for both. Shadow mode exists precisely
/// to observe gc's live convergence traffic and build confidence in the_grid's
/// reducer BEFORE the_grid ever writes — so it must be incapable of writing.
/// This class takes a [ConvergenceSource] (reads only) and the pure reducer /
/// recovery pass (pure functions). There is no constructor parameter through
/// which an [Actuator] or a bd surface could be passed.
///
/// **The partition predicate gates ACTUATION, not observation.** Shadow mode
/// observes ALL convergence loops (that is the point — watch gc's). The
/// ownership predicate lives on the *writing* runtime; here, because there is
/// no actuation at all, the partition is honored vacuously. Shadow mode records
/// which loops it observed as gc-owned for the report, but performs no write
/// against any of them.
class ShadowRuntime {
  ShadowRuntime({
    required ConvergenceSource source,
    GraphEventAdapter adapter = const GraphEventAdapter(),
    void Function(DivergenceReport report)? onDivergence,
  }) : _source = source,
       _adapter = adapter,
       _onDivergence = onDivergence;

  final ConvergenceSource _source;
  final GraphEventAdapter _adapter;
  final void Function(DivergenceReport)? _onDivergence;

  StreamSubscription<GraphEvent>? _eventSub;
  bool _started = false;
  bool _disposed = false;

  /// The would-be transition the_grid computed per closed wisp, keyed by the
  /// `(convergenceBeadId, wispId)` it concerns — so a subsequent gc-observed
  /// command can be diffed against it.
  final Map<String, _Predicted> _predictions = {};

  /// Every divergence report emitted, in order.
  final List<DivergenceReport> reports = [];

  /// Subscribes the event stream read-only. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _eventSub = _source.events.listen(_onEvent);
  }

  void _onEvent(GraphEvent event) {
    // (1) A wisp closure on an observed loop ⇒ compute what the_grid WOULD do.
    final mapped = _adapter.adapt(event, _source.convergences);
    if (mapped != null) {
      final snapshot = _source.current;
      if (snapshot != null) {
        final result = ConvergenceReducer.reduce(
          mapped.convergence,
          mapped.event,
          snapshot,
        );
        final predicted = result.primary;
        _predictions[mapped.event.convergenceBeadId] = _Predicted(
          beadId: mapped.event.convergenceBeadId,
          predictedWire: predicted.wire,
          predicted: predicted,
        );
      }
    }

    // (2) A convergence-root metadata change ⇒ infer what gc ACTUALLY did, and
    // diff it against the prediction. This is a read-only inference over gc's
    // own writes (operator-trigger.md §1.6 detection signatures).
    final observed = _adapter.observedGcCommand(event);
    if (observed != null) {
      _diff(observed);
    }
  }

  void _diff(ObservedGcCommand observed) {
    final prediction = _predictions[observed.beadId];
    final report = DivergenceReport(
      convergenceBeadId: observed.beadId,
      predictedWire: prediction?.predictedWire,
      observed: observed,
      diverged: !_agrees(prediction, observed),
    );
    reports.add(report);
    _onDivergence?.call(report);
  }

  /// Whether the_grid's prediction agrees with gc's observed command. A
  /// terminal `approved`/`no_convergence`/`stopped` matches when the wire
  /// labels correspond; a `waiting_*` prediction against a gc command is a
  /// divergence (the_grid would have held, gc advanced — or vice versa).
  static bool _agrees(_Predicted? prediction, ObservedGcCommand observed) {
    if (prediction == null) return false;
    final predicted = prediction.predictedWire;
    return switch (observed.command) {
      GcCommandKind.operatorApprove ||
      GcCommandKind.handlerApproved => predicted == 'approved',
      GcCommandKind.handlerNoConvergence => predicted == 'no_convergence',
      GcCommandKind.operatorStop => predicted == 'stopped',
      GcCommandKind.operatorIterate ||
      GcCommandKind.triggerAdvance => predicted == 'iterate',
    };
  }

  /// A one-shot read-only conformance pass: computes the recovery outcomes the
  /// grid WOULD apply over the current snapshot WITHOUT actuating them — the
  /// shadow analog of [ReconcilerRuntime.runRecovery]. Returns the would-be
  /// recovery report. No writes.
  RecoveryReport shadowRecovery() {
    final snapshot = _source.current;
    if (snapshot == null) return RecoveryReport(const <RecoveryOutcome>[]);
    return ConvergenceRecovery.reconcile(snapshot);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
  }
}

/// One predicted transition the_grid's reducer computed for a closed wisp.
class _Predicted {
  const _Predicted({
    required this.beadId,
    required this.predictedWire,
    required this.predicted,
  });

  final String beadId;
  final String? predictedWire;
  final ReconcilerAction predicted;
}

/// A structured shadow-mode divergence: what the_grid's reducer predicted vs
/// what gc was observed to do for one convergence loop. Read-only diagnostic —
/// never an instruction to write.
class DivergenceReport {
  const DivergenceReport({
    required this.convergenceBeadId,
    required this.predictedWire,
    required this.observed,
    required this.diverged,
  });

  final String convergenceBeadId;

  /// The wire action the_grid's reducer would have taken (`approved`,
  /// `iterate`, `waiting_manual`, …), or null when the_grid made no prediction
  /// (no observed wisp closure preceded gc's command).
  final String? predictedWire;

  /// The gc command inferred from the metadata write-set (read-only).
  final ObservedGcCommand observed;

  /// True when the_grid's prediction disagrees with gc's observed action — the
  /// signal a conformance audit watches for.
  final bool diverged;

  @override
  String toString() =>
      'DivergenceReport($convergenceBeadId, predicted=$predictedWire, '
      'observed=${observed.command.name}, diverged=$diverged)';
}
