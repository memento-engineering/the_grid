import 'dart:convert';

import 'package:grid_reconciler/src/gates/condition_env.dart';
import 'package:grid_reconciler/src/gates/process_runner.dart';

/// A programmable [ProcessRunner] for offline tests (ADR-0001 D7: Fakes, not
/// mocks). Mirrors grid_controller's `FakeBdRunner` seam: replies are matched
/// against an invocation by an [executable]-keyed queue, the first reply for an
/// executable is consumed per call (a queue), and every call is recorded for
/// assertion (env contract, working dir, timeout).
///
/// A reply may carry a [delay] to exercise nothing time-sensitive here (the
/// fake never actually spawns) — the timeout-action matrix is driven by
/// returning a [ProcessRunOutcome.deadline] reply directly, not by sleeping.
class FakeProcessRunner implements ProcessRunner {
  FakeProcessRunner();

  /// Per-executable reply queues, consumed FIFO; a non-queued executable
  /// throws (no silent default, like FakeBdRunner).
  final Map<String, List<FakeRun>> _queues = <String, List<FakeRun>>{};

  /// Every invocation, in call order.
  final List<FakeCall> calls = <FakeCall>[];

  /// Queues [reply] for invocations of [executable]. Returns `this` for
  /// chaining. Replies are consumed in registration order.
  FakeProcessRunner stub(String executable, FakeRun reply) {
    _queues.putIfAbsent(executable, () => <FakeRun>[]).add(reply);
    return this;
  }

  /// Queues [count] identical [reply]s (the timeout-retry matrix needs the same
  /// deadline reply N+1 times).
  FakeProcessRunner stubRepeated(String executable, FakeRun reply, int count) {
    for (var i = 0; i < count; i++) {
      stub(executable, reply);
    }
    return this;
  }

  /// The env map the most recent call ran under (the env-contract assertions).
  Map<String, String> get lastEnvironment => calls.last.environment;

  @override
  Future<ProcessRunResult> run({
    required String executable,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    CancellationToken? parentCancelled,
  }) async {
    calls.add(
      FakeCall(
        executable: executable,
        workingDirectory: workingDirectory,
        environment: Map<String, String>.unmodifiable(environment),
        timeout: timeout,
        parentWasCancelled: parentCancelled?.isCancelled ?? false,
      ),
    );

    // Parent-cancel short-circuit, like the real runner's first check: a
    // cancelled token classifies as parentCancelled regardless of the queued
    // reply (condition.go:347-358).
    if (parentCancelled?.isCancelled ?? false) {
      return const ProcessRunResult(
        outcome: ProcessRunOutcome.parentCancelled,
        stdoutBytes: <int>[],
        stderrBytes: <int>[],
        stdoutOverflowed: false,
        stderrOverflowed: false,
      );
    }

    final queue = _queues[executable];
    if (queue == null || queue.isEmpty) {
      throw StateError('FakeProcessRunner: no stubbed reply for $executable');
    }
    final reply = queue.removeAt(0);
    return reply.toResult();
  }
}

/// A recorded [FakeProcessRunner] invocation.
class FakeCall {
  const FakeCall({
    required this.executable,
    required this.workingDirectory,
    required this.environment,
    required this.timeout,
    required this.parentWasCancelled,
  });

  final String executable;
  final String workingDirectory;
  final Map<String, String> environment;
  final Duration timeout;
  final bool parentWasCancelled;
}

/// A canned [FakeProcessRunner] reply. Construct with the named factories that
/// map onto the four [ProcessRunOutcome] endings.
class FakeRun {
  const FakeRun._({
    required this.outcome,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.launchError,
    this.stdoutBytes,
    this.stderrBytes,
    this.stdoutOverflowed = false,
    this.stderrOverflowed = false,
  });

  /// The process exited with [code]; [stdout]/[stderr] are captured.
  factory FakeRun.exited(int code, {String stdout = '', String stderr = ''}) =>
      FakeRun._(
        outcome: ProcessRunOutcome.exited,
        exitCode: code,
        stdout: stdout,
        stderr: stderr,
      );

  /// Exit 0 → pass.
  factory FakeRun.pass({String stdout = '', String stderr = ''}) =>
      FakeRun.exited(0, stdout: stdout, stderr: stderr);

  /// The per-script deadline fired → timeout.
  factory FakeRun.deadline({String stdout = '', String stderr = ''}) =>
      FakeRun._(
        outcome: ProcessRunOutcome.deadline,
        stdout: stdout,
        stderr: stderr,
      );

  /// The process could not be launched → error; [error] is the launcher string
  /// (the text-file-busy matcher and the stderr-replacement path read it).
  factory FakeRun.launchFailure(String error) =>
      FakeRun._(outcome: ProcessRunOutcome.launchFailure, launchError: error);

  /// Raw-bytes exit reply for the truncation/overflow tests.
  factory FakeRun.exitedBytes(
    int code, {
    List<int>? stdoutBytes,
    List<int>? stderrBytes,
    bool stdoutOverflowed = false,
    bool stderrOverflowed = false,
  }) => FakeRun._(
    outcome: ProcessRunOutcome.exited,
    exitCode: code,
    stdoutBytes: stdoutBytes,
    stderrBytes: stderrBytes,
    stdoutOverflowed: stdoutOverflowed,
    stderrOverflowed: stderrOverflowed,
  );

  final ProcessRunOutcome outcome;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final String? launchError;
  final List<int>? stdoutBytes;
  final List<int>? stderrBytes;
  final bool stdoutOverflowed;
  final bool stderrOverflowed;

  ProcessRunResult toResult() => ProcessRunResult(
    outcome: outcome,
    exitCode: exitCode,
    launchError: launchError,
    stdoutBytes: stdoutBytes ?? utf8.encode(stdout),
    stderrBytes: stderrBytes ?? utf8.encode(stderr),
    stdoutOverflowed: stdoutOverflowed,
    stderrOverflowed: stderrOverflowed,
  );
}

/// A map-backed [LookPathDir] for env-contract tests — no real `PATH` walk.
/// Returns the stubbed dir for a tool name, or null when absent.
LookPathDir fakeLookPath(Map<String, String> tools) =>
    (name) => tools[name];
