import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../errors/bd_exception.dart';

/// The captured result of one `bd` subprocess: exit code plus decoded
/// stdout/stderr text. Immutable, value-y — the [BdCliService] decodes
/// [stdout] via [BdEnvelope] and routes non-zero [exitCode]s through
/// [BdCommandFailed.fromOutput].
class BdResult {
  const BdResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  @override
  String toString() =>
      'BdResult(exit: $exitCode, '
      'stdout: ${stdout.length}B, stderr: ${stderr.length}B)';
}

/// Runs one `bd` subprocess and returns its [BdResult].
///
/// The single seam the service layer is built on: the real implementation
/// ([ProcessBdRunner]) spawns processes; tests inject a `FakeBdRunner` that
/// returns programmed results, so all of [BdCliService] is exercised offline
/// (ADR-0001 Decision 7: Fakes, not mocks).
///
/// Implementations MUST run under `BD_JSON_ENVELOPE=1` so every read decodes
/// through [BdEnvelope] and every error arrives enveloped on stdout
/// (ADR-0001 Decision 4).
abstract interface class BdRunner {
  /// Runs `bd <args>`. Throws [BdTimeoutException] if the call exceeds
  /// [timeout] (the implementation kills the process tree); never throws for a
  /// non-zero exit — that is reported via [BdResult.exitCode] for the caller to
  /// route through [BdCommandFailed.fromOutput].
  ///
  /// [stdin], when provided, is written to the child's stdin and the stream is
  /// closed (EOF). `bd batch` reads its line-oriented script this way — one
  /// spawn, one Dolt transaction (ADR-0001 D4).
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin});
}

/// Spawns real `bd` subprocesses in the workspace root.
///
/// - Working directory is the [BeadsWorkspace.root] (so `.beads/` is found and
///   `bd` writes land in the right store).
/// - `BD_JSON_ENVELOPE=1` is merged over [Platform.environment] (ADR-0001 D4);
///   the inherited environment carries `GT_ROOT`, `GC_DOLT_*`, `PATH`, etc.
/// - Default timeout 15s (ADR-0001 D4); on timeout the process tree is killed
///   ([ProcessSignal.sigkill]) and [BdTimeoutException] is thrown.
/// - Concurrency is capped by an internal counting semaphore (default 4,
///   ADR-0001 D4) so a burst of calls never floods the box with `bd` spawns.
class ProcessBdRunner implements BdRunner {
  ProcessBdRunner({
    required this.workspaceRoot,
    this.executable = 'bd',
    this.defaultTimeout = const Duration(seconds: 15),
    int maxConcurrency = 4,
    Map<String, String>? environment,
  }) : assert(maxConcurrency > 0, 'maxConcurrency must be positive'),
       _semaphore = _Semaphore(maxConcurrency),
       _baseEnvironment = environment ?? Platform.environment;

  /// Directory `bd` runs in — the workspace root containing `.beads/`.
  final String workspaceRoot;

  /// The `bd` executable name or path (default `bd`, resolved via `PATH`).
  final String executable;

  /// Timeout applied when [run] is called without an explicit one.
  final Duration defaultTimeout;

  final _Semaphore _semaphore;
  final Map<String, String> _baseEnvironment;

  /// The environment every spawn runs under: the base environment with
  /// `BD_JSON_ENVELOPE=1` forced on. Exposed for tests asserting the contract.
  Map<String, String> get environment => {
    ..._baseEnvironment,
    'BD_JSON_ENVELOPE': '1',
  };

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    final effectiveTimeout = timeout ?? defaultTimeout;
    return guarded(() => _runOne(args, effectiveTimeout, stdin));
  }

  /// Runs [action] under the concurrency permit (max [maxConcurrency] in
  /// flight). [run] routes every spawn through here; exposed so the cap can be
  /// asserted directly against this class's real semaphore without spawning
  /// processes (ADR-0001 D7: offline tests).
  @visibleForTesting
  Future<T> guarded<T>(Future<T> Function() action) async {
    await _semaphore.acquire();
    try {
      return await action();
    } finally {
      _semaphore.release();
    }
  }

  Future<BdResult> _runOne(
    List<String> args,
    Duration timeout,
    String? stdin,
  ) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workspaceRoot,
      environment: environment,
      // Do not inherit the parent's env wholesale on top of ours — we pass a
      // complete, explicit environment.
      includeParentEnvironment: false,
      runInShell: false,
    );

    // Feed the script to the child's stdin, if any, then close it (EOF) so a
    // stdin-reading command like `bd batch` can proceed.
    if (stdin != null) {
      process.stdin.write(stdin);
      await process.stdin.flush();
      await process.stdin.close();
    }

    // Drain both pipes concurrently so a full stderr buffer can never deadlock
    // the child while we wait on stdout.
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      // Kill the whole tree: SIGKILL is not catchable, so a wedged `bd`
      // (or a child it spawned) cannot keep the call hanging.
      process.kill(ProcessSignal.sigkill);
    });

    final int exitCode;
    try {
      exitCode = await process.exitCode;
    } finally {
      timer.cancel();
    }

    // Reap the pipes regardless, so we never leak the subscriptions.
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;

    if (timedOut) {
      throw BdTimeoutException(
        command: [executable, ...args],
        timeout: timeout,
      );
    }

    return BdResult(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }
}

/// A minimal counting semaphore: [acquire] returns immediately while permits
/// remain, otherwise queues a completer that [release] resolves in FIFO order.
class _Semaphore {
  _Semaphore(this._permits) : assert(_permits > 0);

  int _permits;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit straight to the next waiter; net permit count unchanged.
      _waiters.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}
