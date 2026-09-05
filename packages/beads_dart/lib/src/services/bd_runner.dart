import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../errors/bd_exception.dart';

/// The captured result of one `bd` subprocess: exit code plus decoded
/// stdout/stderr text. Immutable, value-y — the [BdCliService] decodes
/// [stdout] via [BdEnvelope] and routes non-zero [exitCode]s through
/// [BdException.fromOutput].
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
/// through [BdEnvelope] and every error arrives enveloped on stdout, and under
/// `BD_NON_INTERACTIVE=1` so no command can use interactive-only fallbacks
/// (ADR-0001 Decision 4; SCRATCH-bd-repin §2 and §4 A4).
abstract interface class BdRunner {
  /// Runs `bd <args>`. Throws [BdTimeoutException] if the call exceeds
  /// [timeout] (the implementation kills the process tree); never throws for a
  /// non-zero exit — that is reported via [BdResult.exitCode] for the caller to
  /// route through [BdException.fromOutput].
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
/// - The base process environment is caller-supplied or inherited from
///   [Platform.environment]; this runner adds only the two bd control flags.
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

  /// Grace given to the post-exit pipe drain before detaching (tg-hceh).
  /// After the child exits, EOF is normally immediate; it is withheld only
  /// when an fd-inheriting descendant outlives the child — the case that
  /// must NEVER hold a concurrency permit hostage.
  static const Duration drainGrace = Duration(seconds: 2);

  final _Semaphore _semaphore;
  final Map<String, String> _baseEnvironment;

  /// The environment every spawn runs under: the base environment with
  /// `BD_JSON_ENVELOPE=1` and `BD_NON_INTERACTIVE=1` forced on. Exposed for
  /// tests asserting the contract.
  Map<String, String> get environment => {
    ..._baseEnvironment,
    'BD_JSON_ENVELOPE': '1',
    'BD_NON_INTERACTIVE': '1',
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
    // the child while we wait on stdout. BUFFERED listens (not `join()`) so
    // the bounded drain below can detach and still return everything read.
    // MALFORMED-TOLERANT decoding: the timeout below SIGKILLs the child, and a
    // pipe cut between the bytes of one multibyte character makes the STRICT
    // decoder throw `Unfinished UTF-8 octet sequence` from its close — inside
    // the transformer's done handler, which routes to the zone's uncaught
    // handler, NOT to this subscription's onError. No listener can catch it;
    // the resident isolate dies (lunar epoch 39, 2026-09-05, twice). A torn
    // tail decodes to U+FFFD instead; the caller already sees the kill as
    // [BdTimeoutException].
    const decoder = Utf8Decoder(allowMalformed: true);
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    final stdoutSub = process.stdout.transform(decoder).listen(stdoutBuf.write);
    final stderrSub = process.stderr.transform(decoder).listen(stderrBuf.write);
    // Capture the done-futures AT LISTEN TIME: `asFuture` attached after an
    // `await` would miss a `done` that fired during that await (the event is
    // delivered to a subscription with no onDone handler and dropped), and
    // every clean call would then eat the full [drainGrace] timeout.
    final stdoutDone = stdoutSub.asFuture<void>();
    final stderrDone = stderrSub.asFuture<void>();

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

    // Reap the pipes — BOUNDED (tg-hceh). After `bd` exits, pipe EOF only
    // arrives once every fd-INHERITING DESCENDANT lets go: a store daemon a
    // bd op leaves behind holds the write end open indefinitely. The old
    // unbounded `await join()` here then never returned — `guarded` never
    // released its permit, and a handful of such leaks emptied the
    // station-wide write semaphore: every later write parked on `acquire()`
    // forever with the VM idle (the silent-station latch, three arms
    // running). The child has already exited, so what is buffered IS its
    // output — give EOF a short grace, then detach and proceed.
    try {
      await Future.wait<void>([stdoutDone, stderrDone]).timeout(drainGrace);
    } on TimeoutException {
      await stdoutSub.cancel();
      await stderrSub.cancel();
      // The abandoned done-futures can still complete (with an error) after
      // the cancel; never let that surface as an unhandled async error.
      stdoutDone.ignore();
      stderrDone.ignore();
    }
    final stdout = stdoutBuf.toString();
    final stderr = stderrBuf.toString();

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
