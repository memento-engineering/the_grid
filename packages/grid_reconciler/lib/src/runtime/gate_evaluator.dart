import 'dart:async';

import '../convergence/gate_outcome.dart';
import '../convergence/gate_result.dart';
import '../convergence/reconciler_action.dart';
import '../gates/artifact_dir.dart';
import '../gates/condition_env.dart';
import '../gates/gate_runner_service.dart';
import '../gates/process_runner.dart';

/// The runtime's bridge from the reducer's [EvaluateGateAction] (phase 1 of the
/// gate split, ADR-0000 A22) to a [GateResult] — it assembles the
/// [ConditionEnv] from the action's snapshot-derived [GateEnvInputs] and runs
/// Track D's [GateRunnerService], so the result can re-enter the reducer as
/// `ReducerEvent.gateEvaluated` (phase 2).
///
/// A seam in its own right: the live runtime composes [GateRunnerProcessGate]
/// over the real [ProcessRunner]; tests inject a [FakeGate] (or a real
/// [GateRunnerService] over a [FakeProcessRunner]) to drive the phase split
/// without touching the filesystem.
abstract interface class GateEvaluator {
  /// Runs the gate described by [action] and returns its result.
  Future<GateResult> evaluate(
    EvaluateGateAction action, {
    CancellationToken? parentCancelled,
  });
}

/// The production [GateEvaluator]: drives [GateRunnerService] over the action's
/// parsed [GateConfig] and the [ConditionEnv] built from its [GateEnvInputs].
///
/// The condition script path is the **stored** gate condition, exec'd as-is —
/// gc's convergence handler runs the operator-placed gate path without the
/// ralph trusted-roots resolution (gates-exec.md §2; ADR-0000 A23: the
/// containment guard is wired only at the ralph call site, not here).
class GateRunnerProcessGate implements GateEvaluator {
  const GateRunnerProcessGate({
    required GateRunnerService runner,
    String storePath = '',
    String workDir = '',
    String moleculeDir = '',
  }) : _runner = runner,
       _storePath = storePath,
       _workDir = workDir,
       _moleculeDir = moleculeDir;

  final GateRunnerService _runner;
  final String _storePath;
  final String _workDir;
  final String _moleculeDir;

  @override
  Future<GateResult> evaluate(
    EvaluateGateAction action, {
    CancellationToken? parentCancelled,
  }) {
    final env = conditionEnvFromInputs(
      action.env,
      beadId: action.convergenceBeadId,
      wispId: action.wispId,
      iteration: action.iteration,
      artifactDir: artifactDirFor(
        action.env.cityPath,
        action.convergenceBeadId,
        action.iteration,
      ),
      storePath: _storePath,
      workDir: _workDir,
      moleculeDir: _moleculeDir,
    );
    return _runner.evaluate(
      config: action.config,
      env: env,
      inputs: action.env,
      scriptPath: action.config.condition,
      parentCancelled: parentCancelled,
    );
  }
}

/// A programmable [GateEvaluator] for tests: returns a queued result per call
/// (or a default), recording every action it was asked to evaluate. Optionally
/// delays so a test can prove a slow gate on bead A does not block bead B.
class FakeGate implements GateEvaluator {
  FakeGate({GateResult? defaultResult, this.delay})
    : _default = defaultResult ?? GateResult.of(GateOutcome.fail, exitCode: 1);

  final GateResult _default;

  /// Optional artificial latency per gate, to exercise concurrency/ordering.
  Duration? delay;

  /// Results to return in order; falls back to the default when exhausted.
  final List<GateResult> queued = [];

  /// Every [EvaluateGateAction] evaluated, in order.
  final List<EvaluateGateAction> evaluated = [];

  /// Per-bead override of the delay (slow A, fast B).
  final Map<String, Duration> delayByBead = {};

  @override
  Future<GateResult> evaluate(
    EvaluateGateAction action, {
    CancellationToken? parentCancelled,
  }) async {
    evaluated.add(action);
    final d = delayByBead[action.convergenceBeadId] ?? delay;
    if (d != null) await Future<void>.delayed(d);
    if (queued.isNotEmpty) return queued.removeAt(0);
    return _default;
  }
}
