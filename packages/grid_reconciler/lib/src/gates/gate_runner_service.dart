import 'dart:async';

import '../convergence/gate_config.dart';
import '../convergence/gate_mode.dart';
import '../convergence/gate_outcome.dart';
import '../convergence/gate_result.dart';
import '../convergence/go_duration.dart';
import '../convergence/verdict.dart';
import 'condition_env.dart';
import 'output_capture.dart';
import 'process_runner.dart';

/// `textFileBusyRetryAttempts` (condition.go:23): extra pre-exec retries when a
/// freshly-written script is still held open for write (ETXTBSY).
const int textFileBusyRetryAttempts = 5;

/// `textFileBusyRetryDelay` (condition.go:24).
const Duration textFileBusyRetryDelay = Duration(milliseconds: 25);

/// The subprocess gate runner Service — ports gc's `condition.go`/`hybrid.go`
/// execution path (ADR-0003 D3, gates-exec.md §3-§8).
///
/// A predictable-flutter **Service**: stateless I/O behind a seam
/// ([ProcessRunner]), carrying a classifier name. It consumes Track A's typed
/// [GateConfig]/[GateEnvInputs] and produces a Track A [GateResult]; it never
/// re-reads or re-parses metadata (the reducer parsed the config at step 3a).
///
/// The verdict channel is **read, not reinterpreted** (ADR-0003 D3): hybrid
/// mode injects [GateEnvInputs.agentVerdict] verbatim into `GC_AGENT_VERDICT`
/// and the script's exit code — not the verdict — decides pass/fail.
class GateRunnerService {
  const GateRunnerService({
    required ProcessRunner processRunner,
    required Map<String, String> ambientEnvironment,
    required LookPathDir lookPathDir,
    required String tempDir,
  }) : _processRunner = processRunner,
       _ambient = ambientEnvironment,
       _lookPathDir = lookPathDir,
       _tempDir = tempDir;

  final ProcessRunner _processRunner;
  final Map<String, String> _ambient;
  final LookPathDir _lookPathDir;
  final String _tempDir;

  /// Port of `RunCondition` (condition.go:269-287): the timeout-retry loop over
  /// [runOnce]. Retries **only** on a `timeout` outcome and only while budget
  /// remains; any other outcome returns immediately. The returned result is the
  /// final attempt's, stamped with [GateResult.retryCount] = the number of
  /// timed-out attempts before it.
  ///
  /// [scriptPath] is the resolved, exec-eligible script (the reducer/caller is
  /// responsible for resolution; the convergence handler exec's the stored gate
  /// condition as-is, gates-exec.md §2). [timeout] is per attempt.
  Future<GateResult> runCondition({
    required String scriptPath,
    required ConditionEnv env,
    required GoDuration timeout,
    required int retryBudget,
    CancellationToken? parentCancelled,
  }) async {
    var retries = 0;
    GateResult last = const GateResult();

    for (var attempt = 0; attempt <= retryBudget; attempt++) {
      last = await runOnce(
        scriptPath: scriptPath,
        env: env,
        timeout: timeout,
        parentCancelled: parentCancelled,
      );
      if (!last.isTimeout || attempt == retryBudget) {
        return last.copyWith(retryCount: retries);
      }
      retries++;
    }
    return last.copyWith(retryCount: retries);
  }

  /// Port of `runOnce` (condition.go:290-309): a single attempt wrapped in the
  /// **text-file-busy** pre-exec retry — up to [textFileBusyRetryAttempts] extra
  /// runs with a [textFileBusyRetryDelay] sleep when the launcher reports
  /// `text file busy` (case-insensitive) on an `error` outcome. Independent of,
  /// and nested inside, the timeout-retry loop (gates-exec.md §3a). A cancelled
  /// parent aborts the sleep and returns the busy result immediately.
  Future<GateResult> runOnce({
    required String scriptPath,
    required ConditionEnv env,
    required GoDuration timeout,
    CancellationToken? parentCancelled,
  }) async {
    GateResult result = const GateResult();
    for (var attempt = 0; attempt <= textFileBusyRetryAttempts; attempt++) {
      result = await _runOnceNoPreExecRetry(
        scriptPath: scriptPath,
        env: env,
        timeout: timeout,
        parentCancelled: parentCancelled,
      );
      if (!_isTextFileBusyPreExecError(result) ||
          attempt == textFileBusyRetryAttempts) {
        return result;
      }
      if (parentCancelled?.isCancelled ?? false) return result;
      await Future<void>.delayed(textFileBusyRetryDelay);
      if (parentCancelled?.isCancelled ?? false) return result;
    }
    return result;
  }

  /// `isTextFileBusyPreExecError` (condition.go:311-313): an `error` outcome
  /// whose stderr contains `text file busy` (case-insensitive substring).
  static bool _isTextFileBusyPreExecError(GateResult r) =>
      r.outcomeWire == GateOutcome.error.wire &&
      r.stderr.toLowerCase().contains('text file busy');

  /// Port of `runOnceNoPreExecRetry` (condition.go:315-404): one execution with
  /// the deadline, the whitelist env, bounded capture, and the strict-order
  /// outcome classification.
  Future<GateResult> _runOnceNoPreExecRetry({
    required String scriptPath,
    required ConditionEnv env,
    required GoDuration timeout,
    CancellationToken? parentCancelled,
  }) async {
    final environment = env.environ(
      ambient: _ambient,
      lookPathDir: _lookPathDir,
      tempDir: _tempDir,
    );

    final start = DateTime.now();
    final run = await _processRunner.run(
      executable: scriptPath,
      workingDirectory: env.workingDirectory,
      environment: environment,
      timeout: timeout.toDuration(),
      parentCancelled: parentCancelled,
    );
    final duration = DateTime.now().difference(start);

    final out = truncateOutput(run.stdoutBytes, maxOutputBytes);
    final err = truncateOutput(run.stderrBytes, maxOutputBytes);
    final truncated =
        out.truncated ||
        err.truncated ||
        run.stdoutOverflowed ||
        run.stderrOverflowed;

    // Classification, in gc's strict order (condition.go:347-403):
    switch (run.outcome) {
      // 1. Parent cancelled FIRST → error (never retried; condition.go:350-358).
      case ProcessRunOutcome.parentCancelled:
        return GateResult.of(
          GateOutcome.error,
          stdout: out.text,
          stderr: err.text,
          duration: duration,
          truncated: truncated,
        );
      // 2. Per-script deadline → timeout, null exit (condition.go:361-369).
      case ProcessRunOutcome.deadline:
        return GateResult.of(
          GateOutcome.timeout,
          stdout: out.text,
          stderr: err.text,
          duration: duration,
          truncated: truncated,
        );
      // 4. Launch failure → error; the launcher message REPLACES captured
      //    stderr; stdout dropped (condition.go:385-391, trap #2).
      case ProcessRunOutcome.launchFailure:
        return GateResult.of(
          GateOutcome.error,
          stderr: run.launchError ?? 'gate launch failed',
          duration: duration,
          truncated: truncated,
        );
      // 3 & 5. The process exited: non-zero → fail with its code (signal-kill
      //    is the negative code, gates-exec.md trap #19); zero → pass with a
      //    non-null 0 (condition.go:371-403).
      case ProcessRunOutcome.exited:
        final code = run.exitCode ?? 0;
        if (code != 0) {
          return GateResult.of(
            GateOutcome.fail,
            exitCode: code,
            stdout: out.text,
            stderr: err.text,
            duration: duration,
            truncated: truncated,
          );
        }
        return GateResult.of(
          GateOutcome.pass,
          exitCode: 0,
          stdout: out.text,
          stderr: err.text,
          duration: duration,
          truncated: truncated,
        );
    }
  }

  /// Port of `EvaluateHybrid` (hybrid.go:8-22): hybrid-mode evaluation.
  ///
  /// 1. No condition configured → `GateManualResult()` ([GateConfig.hybridNeedsManual]).
  /// 2. Else inject [verdict] verbatim into the env (`GC_AGENT_VERDICT`) — the
  ///    only place the verdict enters the script env — and run the condition.
  /// 3. Retry budget is `MaxGateRetries` (3) iff the timeout action is `retry`,
  ///    else 0 ([GateConfig.retryBudget]).
  ///
  /// The script's exit code, not the verdict, decides the outcome (D3: read,
  /// not reinterpreted).
  Future<GateResult> evaluateHybrid({
    required GateConfig config,
    required ConditionEnv env,
    required Verdict verdict,
    CancellationToken? parentCancelled,
  }) {
    if (config.hybridNeedsManual) {
      return Future<GateResult>.value(gateManualResult());
    }
    return runCondition(
      scriptPath: config.condition,
      env: env.withAgentVerdict(verdict.wire),
      timeout: config.timeout,
      retryBudget: config.retryBudget,
      parentCancelled: parentCancelled,
    );
  }

  /// The top-level mode dispatch (the M2 step-4 gate evaluation, gates-exec.md
  /// §8). A convenience over [runCondition]/[evaluateHybrid] driving directly
  /// off a [GateConfig] + [GateEnvInputs]:
  ///
  /// * `manual` → [gateManualResult] (the handler intercepts manual before gate
  ///   eval; this is the defensive direct-caller result).
  /// * `condition` → [runCondition] with the verdict **not** exported.
  /// * `hybrid` → [evaluateHybrid] (verdict exported).
  ///
  /// [env] is the assembled [ConditionEnv]; [inputs] supplies the gate-path
  /// verdict (already normalized/scoped by the reducer, gate_config.dart). The
  /// caller resolves [GateConfig.condition] to an exec-eligible [scriptPath]
  /// (or passes the stored path for the operator-trusted handler placement).
  Future<GateResult> evaluate({
    required GateConfig config,
    required ConditionEnv env,
    required GateEnvInputs inputs,
    required String scriptPath,
    CancellationToken? parentCancelled,
  }) {
    switch (config.mode) {
      case GateMode.manual:
        return Future<GateResult>.value(gateManualResult());
      case GateMode.hybrid:
        return evaluateHybrid(
          config: config,
          env: env,
          verdict: inputs.agentVerdict,
          parentCancelled: parentCancelled,
        );
      case GateMode.condition:
        // Pure condition mode never exports the verdict (handler.go:763-764).
        return runCondition(
          scriptPath: scriptPath,
          env: env,
          timeout: config.timeout,
          retryBudget: config.retryBudget,
          parentCancelled: parentCancelled,
        );
    }
  }
}

/// Port of `GateManualResult()` (gate.go:36-40): `pass` with a **null** exit
/// code (distinguishable from a real pass: `gate_exit_code` `''` vs `'0'`) and
/// every other field zero. Used for manual mode and the hybrid-no-condition
/// short-circuit. There is **no** `manual` outcome value (trap #20, §1.3).
GateResult gateManualResult() => GateResult.of(GateOutcome.pass);

/// Builds the gate-path [ConditionEnv] from Track A's snapshot-derived
/// [GateEnvInputs] plus the runner's own runtime config (the parts gc derives
/// from `Handler` state, gate_config.dart doc / handler.go:743-760):
/// [storePath] (`Handler.StorePath`), the resolved [artifactDir]
/// (`ArtifactDirFor`, computed by the caller), the [beadId]/[wispId]/[iteration]
/// identifying the closed wisp, and the optional [workDir].
///
/// `agentVerdict` is **not** set here — pure condition mode must leave it empty
/// (no `GC_AGENT_VERDICT`); hybrid mode injects it via [GateRunnerService.evaluateHybrid].
ConditionEnv conditionEnvFromInputs(
  GateEnvInputs inputs, {
  required String beadId,
  required String wispId,
  required int iteration,
  required String artifactDir,
  String storePath = '',
  String workDir = '',
  String moleculeDir = '',
}) => ConditionEnv(
  beadId: beadId,
  iteration: iteration,
  cityPath: inputs.cityPath,
  storePath: storePath,
  workDir: workDir,
  wispId: wispId,
  docPath: inputs.docPath,
  moleculeDir: moleculeDir,
  artifactDir: artifactDir,
  iterationDurationMs: inputs.iterationDuration.inMilliseconds,
  cumulativeDurationMs: inputs.cumulativeDuration.inMilliseconds,
  maxIterations: inputs.maxIterations,
);
