/// The COMPUTE domain's BOUNDED "use" (ADR-0011 D3 + the Hazards RCE-bounds
/// note). A compute slot runs a CONSTRAINED command — an EXPLICIT argv (never a
/// shell string, so no interpolation/injection), an executable ALLOW-LIST, and a
/// timeout — NOT raw shell-as-a-service. LAN-trust + a token is not a license to
/// run anything; real sandboxing/authz is the deferred pluggable `Trust`.
///
/// The spawn is injectable ([ComputeSpawn], default [realComputeSpawn] — a real,
/// killable `Process.start`) so tests never spawn a process. Lib stays
/// print-free — an injectable [onLog] observes events.
///
/// On timeout the bound does NOT merely abandon the wait — it REAPS the spawned
/// process group via the M4 `terminateGroup`/pgid reaper (ADR-0011 Hazards:
/// orphaned work on the lessor), so a hung or abandoned command cannot keep
/// running on the lessor after its lease elapses.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_federation/grid_federation.dart' show DispatchHandler;
import 'package:grid_runtime/grid_runtime.dart'
    show
        GroupTerminateResult,
        ProcessGroupController,
        SystemProcessGroupController,
        terminateGroup;

import 'compute_command.dart';

/// Thrown when a [DispatchCommand] is REFUSED by the compute bounds: the
/// executable is not on the allow-list, or the command is empty. A hard refusal
/// — the lessor never runs an out-of-bounds command (ADR-0011 Hazards).
class ComputeBoundsException implements Exception {
  /// Creates a bounds violation carrying [message].
  const ComputeBoundsException(this.message);

  /// A human-readable description of the violation.
  final String message;

  @override
  String toString() => 'ComputeBoundsException: $message';
}

/// A spawned, REAPABLE compute process — the timeout-reap seam. The real impl
/// ([realComputeSpawn]) wraps `Process.start`; tests inject a fake whose
/// [exitCode] never completes (a hang) so the reap path runs offline.
abstract interface class ComputeProcess {
  /// The spawned process's pid (the reaper's liveness/pgid subject). A value
  /// `<= 1` marks "no real OS process" (an in-process fake) — the bound skips
  /// the group reaper and best-effort [kill]s instead.
  int get pid;

  /// Completes with the process exit code when it exits (the wait the bound
  /// races against the timeout).
  Future<int> get exitCode;

  /// The drained stdout (UTF-8), read once the process closes its stream.
  Future<String> stdoutText();

  /// The drained stderr (UTF-8), read once the process closes its stream.
  Future<String> stderrText();

  /// Best-effort direct kill — the fallback when the pgid is unresolvable or the
  /// group reaper refuses an unsafe group. Idempotent / never throws.
  void kill();
}

/// Spawns a [DispatchCommand] as a reapable [ComputeProcess]. Injectable
/// (default = [realComputeSpawn]); tests pass a fake so no process spawns.
typedef ComputeSpawn = Future<ComputeProcess> Function(DispatchCommand cmd);

/// Runs a compute [DispatchCommand] and returns its [CommandResult] — the
/// back-compat result-returning seam (a fake for tests / an in-process executor).
/// Prefer [ComputeSpawn] for the real path so a timeout can REAP the process.
typedef CommandExecutor = Future<CommandResult> Function(DispatchCommand cmd);

/// The declared bounds on the compute "use" (ADR-0011 D3 / Hazards): the set of
/// executables a lessor will run, and the per-command [timeout]. Immutable.
class ComputeBounds {
  /// Creates bounds permitting [allowedCommands] (matched against
  /// [DispatchCommand.command]) with a per-command [timeout].
  const ComputeBounds({
    required this.allowedCommands,
    this.timeout = const Duration(minutes: 5),
  });

  /// The exact executable names a lessor will run (an allow-list — anything else
  /// is refused with [ComputeBoundsException]).
  final Set<String> allowedCommands;

  /// The per-command wall-clock timeout (the upper bound on a single use).
  final Duration timeout;

  /// Whether [command] is permitted to run under these bounds.
  bool allows(String command) => allowedCommands.contains(command);
}

void _noLog(String _) {}

/// Enforces [ComputeBounds] over an injectable [ComputeSpawn]: refuses any
/// out-of-bounds command (empty, or not on the allow-list) with a
/// [ComputeBoundsException] BEFORE spawning anything, then runs the in-bounds
/// command under the bounds' timeout. The explicit-argv [DispatchCommand] (no
/// shell) is what makes "no string interpolation" structural.
///
/// On timeout the spawned process group is REAPED (the M4
/// [terminateGroup]/pgid reaper over the injected [ProcessGroupController]),
/// closing ADR-0011's "orphaned work on the lessor" hazard — a non-zero
/// [CommandResult] (exit 124) is returned only AFTER the reap is requested.
class BoundedCommandExecutor {
  /// Creates a bounded executor over [bounds]. Provide [spawn] (the real path)
  /// OR a back-compat [executor] (a fake / in-process function) — not both;
  /// [spawn] defaults to [realComputeSpawn]. [groups] is the reaper seam
  /// (default [SystemProcessGroupController]); [onLog] defaults to a no-op.
  BoundedCommandExecutor({
    required this.bounds,
    ComputeSpawn? spawn,
    CommandExecutor? executor,
    ProcessGroupController? groups,
    void Function(String)? onLog,
  })  : assert(
          spawn == null || executor == null,
          'provide spawn OR executor, not both',
        ),
        _spawn = spawn ??
            (executor != null ? _executorAsSpawn(executor) : realComputeSpawn),
        _groups = groups ?? const SystemProcessGroupController(),
        _onLog = onLog ?? _noLog;

  /// The declared bounds (allow-list + timeout).
  final ComputeBounds bounds;
  final ComputeSpawn _spawn;
  final ProcessGroupController _groups;
  final void Function(String) _onLog;

  /// Runs [cmd] iff it is in-bounds; the returned future completes with a
  /// [ComputeBoundsException] otherwise (a rejection, never a synchronous throw).
  /// The in-bounds run is capped at [ComputeBounds.timeout] — past it the
  /// process group is REAPED and a non-zero [CommandResult] is returned. (An act.)
  Future<CommandResult> run(DispatchCommand cmd) async {
    if (cmd.command.isEmpty) {
      throw const ComputeBoundsException('empty command is not allowed');
    }
    if (!bounds.allows(cmd.command)) {
      final allowed = bounds.allowedCommands.toList()..sort();
      throw ComputeBoundsException(
        'command "${cmd.command}" is not on the compute allow-list $allowed',
      );
    }
    _onLog('compute RUN ${cmd.command} ${cmd.args.join(' ')}');

    final ComputeProcess proc;
    try {
      proc = await _spawn(cmd);
    } on ProcessException catch (e) {
      return CommandResult(
        exitCode: 127, // conventional "command not found / cannot spawn"
        stdout: '',
        stderr: 'compute: cannot spawn "${cmd.command}": ${e.message}',
        durationMs: 0,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final code = await proc.exitCode.timeout(bounds.timeout);
      sw.stop();
      return CommandResult(
        exitCode: code,
        stdout: await proc.stdoutText(),
        stderr: await proc.stderrText(),
        durationMs: sw.elapsedMilliseconds,
      );
    } on TimeoutException {
      sw.stop();
      _onLog(
        'compute TIMEOUT ${cmd.command} after ${bounds.timeout.inSeconds}s '
        '— reaping pid ${proc.pid}',
      );
      await _reap(proc);
      return CommandResult(
        exitCode: 124, // conventional "timed out" exit code
        stdout: '',
        stderr: 'compute: "${cmd.command}" timed out after '
            '${bounds.timeout.inSeconds}s (reaped)',
        durationMs: bounds.timeout.inMilliseconds,
      );
    }
  }

  /// Reaps [proc] on timeout: the whole process GROUP via the M4
  /// [terminateGroup] reaper (SIGTERM → grace → SIGKILL), falling back to a
  /// best-effort single-process [ComputeProcess.kill] when there is no real OS
  /// process (`pid <= 1`), the pgid is unresolvable, or the group is refused as
  /// unsafe (`pgid <= 1` / the caller's own group).
  Future<void> _reap(ComputeProcess proc) async {
    if (proc.pid <= 1) {
      proc.kill(); // in-process fake — nothing to group-reap
      return;
    }
    final pgid = await _groups.resolvePgid(proc.pid);
    if (pgid == null) {
      proc.kill(); // pgid unresolved — best-effort direct kill, never leak
      return;
    }
    final result = await terminateGroup(
      controller: _groups,
      pgid: pgid,
      leaderPid: proc.pid,
    );
    if (result == GroupTerminateResult.refusedUnsafe) {
      proc.kill(); // never leave the abandoned command running
    }
    _onLog('compute reaped pgid $pgid → ${result.name}');
  }
}

/// The real compute [ComputeSpawn]: a `Process.start` with EXPLICIT argv (no
/// shell — so no string interpolation / injection), killable + with a readable
/// exit code. Offline tests inject a fake instead of spawning a process.
Future<ComputeProcess> realComputeSpawn(DispatchCommand cmd) async {
  final p = await Process.start(
    cmd.command,
    cmd.args,
    workingDirectory: cmd.workdir,
  );
  return _RealComputeProcess(p);
}

/// Adapts a back-compat [CommandExecutor] (an in-process function / fake) into a
/// [ComputeSpawn] — a [_ResultComputeProcess] with no real OS process (pid `0`),
/// so the bound's timeout path skips the group reaper and no-ops [kill].
ComputeSpawn _executorAsSpawn(CommandExecutor executor) =>
    (cmd) async => _ResultComputeProcess(executor(cmd));

class _RealComputeProcess implements ComputeProcess {
  _RealComputeProcess(this._p)
      : _stdout = _p.stdout.transform(utf8.decoder).join().catchError((_) => ''),
        _stderr = _p.stderr.transform(utf8.decoder).join().catchError((_) => '');

  final Process _p;
  final Future<String> _stdout;
  final Future<String> _stderr;

  @override
  int get pid => _p.pid;

  @override
  Future<int> get exitCode => _p.exitCode;

  @override
  Future<String> stdoutText() => _stdout;

  @override
  Future<String> stderrText() => _stderr;

  @override
  void kill() => _p.kill(ProcessSignal.sigkill);
}

class _ResultComputeProcess implements ComputeProcess {
  _ResultComputeProcess(this._result);

  final Future<CommandResult> _result;

  @override
  int get pid => 0; // sentinel — no real OS process to reap

  @override
  Future<int> get exitCode async => (await _result).exitCode;

  @override
  Future<String> stdoutText() async => (await _result).stdout;

  @override
  Future<String> stderrText() async => (await _result).stderr;

  @override
  void kill() {} // nothing to kill (an in-process executor)
}

/// Adapts the COMPUTE domain's BOUNDED "use" onto the federation's kind-agnostic
/// [DispatchHandler] (the lessor-side glue — moved out of the federation core at
/// the M6 Track D split). Decodes a [DispatchCommand], runs it through a
/// [BoundedCommandExecutor] (allow-list + timeout + reap over [bounds]), encodes
/// the [CommandResult]. A refused (out-of-bounds) command surfaces as a non-zero
/// [CommandResult] (exit 126 = "command refused") so the lessee gets a clean
/// result rather than an opaque transport error — the lessor never runs it.
DispatchHandler computeDispatchHandler({
  required ComputeBounds bounds,
  ComputeSpawn? spawn,
  CommandExecutor? executor,
  ProcessGroupController? groups,
  void Function(String)? onLog,
}) {
  final log = onLog ?? _noLog;
  final bounded = BoundedCommandExecutor(
    bounds: bounds,
    spawn: spawn,
    executor: executor,
    groups: groups,
    onLog: log,
  );
  return (payload) async {
    final cmd = DispatchCommand.fromJson(payload);
    try {
      return (await bounded.run(cmd)).toJson();
    } on ComputeBoundsException catch (e) {
      log('compute REFUSED: ${e.message}');
      return CommandResult(
        exitCode: 126, // conventional "command cannot execute / refused"
        stdout: '',
        stderr: 'compute: ${e.message}',
        durationMs: 0,
      ).toJson();
    }
  };
}
