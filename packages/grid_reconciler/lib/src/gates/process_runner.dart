import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'output_capture.dart';

/// The captured result of one gate-script subprocess run: the raw stdout/stderr
/// **bytes** plus how the run ended.
///
/// Bytes, not strings, because gc's capture truncates on a **byte** budget
/// (`MaxOutputBytes` = 4096/stream) with a UTF-8 rune-boundary backoff
/// (capture.go:47-69); decoding before truncation would change the byte count.
/// [GateRunnerService] applies [truncateOutput] over these slices.
///
/// [ProcessRunOutcome] distinguishes the four launch endings the gate runner's
/// classification (condition.go:350-403) branches on — a clean transcription of
/// Go's `(err, ctx.Err(), execCtx.Err())` triple onto a closed Dart enum so the
/// runner never re-derives "was this a deadline kill or a parent cancel?" from
/// platform error strings.
class ProcessRunResult {
  const ProcessRunResult({
    required this.outcome,
    required this.stdoutBytes,
    required this.stderrBytes,
    required this.stdoutOverflowed,
    required this.stderrOverflowed,
    this.exitCode,
    this.launchError,
  });

  /// How the run ended (exited / deadline / parent-cancel / launch failure).
  final ProcessRunOutcome outcome;

  /// Captured stdout, already bounded to the capture-buffer ceiling (4100B);
  /// further truncation to 4096B happens in the runner.
  final List<int> stdoutBytes;

  /// Captured stderr, bounded the same way.
  final List<int> stderrBytes;

  /// True when stdout exceeded the bounded-buffer ceiling (bytes were dropped).
  final bool stdoutOverflowed;

  /// True when stderr exceeded the bounded-buffer ceiling.
  final bool stderrOverflowed;

  /// The process exit code — present only when [outcome] is [ProcessRunOutcome.exited].
  /// Negative for signal-terminated processes (Dart `Process.exitCode`
  /// convention; gc reports the same via `exec.ExitError.ExitCode() == -1`,
  /// condition.go:371-384).
  final int? exitCode;

  /// The launcher error message, present only when [outcome] is
  /// [ProcessRunOutcome.launchFailure]. This is the substring the
  /// text-file-busy pre-exec retry matches against (condition.go:311-313) and
  /// the string that **replaces** captured stderr on the `error` outcome
  /// (condition.go:385-391).
  final String? launchError;
}

/// How a single gate-script run terminated. Mirrors gc's classification triple
/// (condition.go:347-392) as a closed set so the runner maps it to a
/// [GateOutcome] without re-inspecting platform errors.
enum ProcessRunOutcome {
  /// The process launched and exited with [ProcessRunResult.exitCode] (any
  /// code, including signal-kill negatives). → `pass`/`fail`.
  exited,

  /// The per-script deadline fired and the runner killed the process
  /// (SIGKILL). → `timeout`.
  deadline,

  /// The parent cancellation token was already (or became) cancelled. Checked
  /// BEFORE the deadline so a reconciler shutdown is never misread as a gate
  /// timeout (condition.go:347-358). → `error`.
  parentCancelled,

  /// The process could not be launched at all (not found, not executable, exec
  /// format error, text-file-busy). [ProcessRunResult.launchError] carries the
  /// message. → `error`.
  launchFailure,
}

/// A cooperative cancellation token standing in for Go's `context.Context`
/// parent-cancel channel (condition.go:316, 350). Dart has no ambient context,
/// so the runner threads one of these explicitly; [ProcessRunner]
/// implementations check [isCancelled] before/around a launch.
class CancellationToken {
  CancellationToken();

  /// A token that is already cancelled — the parent-cancel test fixture.
  CancellationToken.cancelled() : _cancelled = true;

  bool _cancelled = false;

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled;

  /// Requests cancellation. Idempotent.
  void cancel() => _cancelled = true;
}

/// The Process SEAM for gate execution — the single point where the gate runner
/// touches `dart:io`.
///
/// Mirrors grid_controller's [BdRunner] pattern: a real implementation
/// ([SystemProcessRunner]) spawns processes; tests inject a fake that returns
/// programmed [ProcessRunResult]s, so the whole outcome/timeout/hybrid matrix
/// runs offline (ADR-0001 D7: Fakes, not mocks). A reference type, so it carries
/// no classifier suffix beyond the Runner role name (predictable-flutter).
abstract interface class ProcessRunner {
  /// Runs [executable] directly — **no shell, zero arguments** (the exit-code
  /// contract collapses if a shell wrapper is introduced; condition.go:319).
  ///
  /// [environment] is the complete, explicit child environment (a whitelist,
  /// never the inherited process env; condition.go:79-150). [workingDirectory]
  /// is the child's cwd. [timeout] is the per-run deadline; on expiry the
  /// implementation kills the process tree with SIGKILL and reports
  /// [ProcessRunOutcome.deadline]. [parentCancelled], when cancelled, yields
  /// [ProcessRunOutcome.parentCancelled] (checked before the deadline).
  ///
  /// Never throws for a non-zero exit or a launch failure — both are reported
  /// through [ProcessRunResult] for the runner to classify.
  Future<ProcessRunResult> run({
    required String executable,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    CancellationToken? parentCancelled,
  });
}

/// Spawns real gate-script subprocesses via `dart:io`.
///
/// - **No shell, no args:** `Process.start(executable, const [])` — the kernel
///   exec's the script by its shebang + exec bit (condition.go:319).
/// - **Whitelist env only:** `includeParentEnvironment: false` so the child
///   sees exactly [ProcessRunner.run]'s `environment` — the sandbox
///   (`HOME`=cityPath, narrow `PATH`, no controller token) is a security
///   boundary (condition.go:79-150).
/// - **Deadline → SIGKILL:** a [Timer] kills the tree on expiry; a 1s post-kill
///   grace mirrors gc's `cmd.WaitDelay = time.Second` so a grandchild holding a
///   pipe open cannot wedge the wait (condition.go:330).
/// - **Bounded capture:** stdout/stderr each drain into a [BoundedByteSink]
///   capped at the capture-buffer ceiling, so a chatty script cannot exhaust
///   memory and the overflow flag is observable (capture.go:17-43).
class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner({this.postKillGrace = const Duration(seconds: 1)});

  /// Grace after SIGKILL before the wait gives up on draining pipes
  /// (gc's `cmd.WaitDelay`, condition.go:330).
  final Duration postKillGrace;

  @override
  Future<ProcessRunResult> run({
    required String executable,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    CancellationToken? parentCancelled,
  }) async {
    final stdoutSink = BoundedByteSink(captureBufferBytes);
    final stderrSink = BoundedByteSink(captureBufferBytes);

    final Process process;
    try {
      process = await Process.start(
        executable,
        const <String>[],
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
    } on ProcessException catch (e) {
      // Launch failure: not found, not executable, exec format error, ETXTBSY.
      // gc surfaces these as a non-exit error whose .Error() string the runner
      // uses verbatim (condition.go:385-391) and the text-file-busy matcher
      // scans (condition.go:311-313).
      return ProcessRunResult(
        outcome: ProcessRunOutcome.launchFailure,
        stdoutBytes: const <int>[],
        stderrBytes: const <int>[],
        stdoutOverflowed: false,
        stderrOverflowed: false,
        launchError: _launchErrorString(executable, e),
      );
    }

    final stdoutDone = stdoutSink.addStream(process.stdout);
    final stderrDone = stderrSink.addStream(process.stderr);

    var deadlineHit = false;
    final timer = Timer(timeout, () {
      deadlineHit = true;
      process.kill(ProcessSignal.sigkill);
    });

    final int rawExit;
    try {
      rawExit = await process.exitCode;
    } finally {
      timer.cancel();
    }

    // Drain the pipes, but never block longer than the post-kill grace after a
    // deadline kill — a grandchild holding a pipe open must not wedge us
    // (condition.go:330).
    await Future.wait(<Future<void>>[
      stdoutDone,
      stderrDone,
    ]).timeout(postKillGrace, onTimeout: () => const <void>[]);

    // Parent cancellation is checked FIRST (condition.go:347-358): an external
    // shutdown must classify as `error`, never `timeout`, or the retry loop
    // would hammer a dead parent.
    if (parentCancelled?.isCancelled ?? false) {
      return ProcessRunResult(
        outcome: ProcessRunOutcome.parentCancelled,
        stdoutBytes: stdoutSink.bytes,
        stderrBytes: stderrSink.bytes,
        stdoutOverflowed: stdoutSink.overflowed,
        stderrOverflowed: stderrSink.overflowed,
      );
    }

    if (deadlineHit) {
      return ProcessRunResult(
        outcome: ProcessRunOutcome.deadline,
        stdoutBytes: stdoutSink.bytes,
        stderrBytes: stderrSink.bytes,
        stdoutOverflowed: stdoutSink.overflowed,
        stderrOverflowed: stderrSink.overflowed,
      );
    }

    return ProcessRunResult(
      outcome: ProcessRunOutcome.exited,
      exitCode: rawExit,
      stdoutBytes: stdoutSink.bytes,
      stderrBytes: stderrSink.bytes,
      stdoutOverflowed: stdoutSink.overflowed,
      stderrOverflowed: stderrSink.overflowed,
    );
  }

  static String _launchErrorString(String executable, ProcessException e) {
    // Shape the message like gc's `fork/exec <path>: <reason>` so the
    // text-file-busy substring match (case-insensitive) survives the port and
    // the persisted gate_stderr stays human-legible (gates-exec.md trap #2).
    final reason = e.message.isNotEmpty ? e.message : 'exec failed';
    return 'fork/exec $executable: $reason';
  }
}

/// Decodes captured gate output to a string the way gc's `string(data)` does:
/// lossy UTF-8 (invalid sequences become U+FFFD), preserving truncated byte
/// counts. Exposed for the runner and its tests.
String decodeGateOutput(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
