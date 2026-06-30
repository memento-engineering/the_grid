/// The COMPUTE domain's BOUNDED "use" (ADR-0011 D3 + the Hazards RCE-bounds
/// note). A compute slot runs a CONSTRAINED command — an EXPLICIT argv (never a
/// shell string, so no interpolation/injection), an executable ALLOW-LIST, and a
/// timeout — NOT raw shell-as-a-service. LAN-trust + a token is not a license to
/// run anything; real sandboxing/authz is the deferred pluggable `Trust`.
///
/// The executor is injectable ([CommandExecutor], default [defaultCommandExecutor]
/// — a real, timed `Process.run`) so tests never spawn a process. Lib stays
/// print-free — an injectable [onLog] observes events.
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_federation/grid_federation.dart' show DispatchHandler;

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

/// Runs a compute [DispatchCommand] and returns its [CommandResult]. Injectable
/// (default = [defaultCommandExecutor], a real timed `Process.run`); tests pass a
/// fake so no process spawns.
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

/// Enforces [ComputeBounds] over an injectable [CommandExecutor]: refuses any
/// out-of-bounds command (empty, or not on the allow-list) with a
/// [ComputeBoundsException] BEFORE running anything, then runs the in-bounds
/// command under the bounds' timeout. The explicit-argv [DispatchCommand] (no
/// shell) is what makes "no string interpolation" structural.
class BoundedCommandExecutor {
  /// Creates a bounded executor over [bounds]; [executor] defaults to
  /// [defaultCommandExecutor] (a real timed `Process.run`), [onLog] to a no-op.
  BoundedCommandExecutor({
    required this.bounds,
    CommandExecutor? executor,
    void Function(String)? onLog,
  }) : _executor = executor ?? defaultCommandExecutor,
       _onLog = onLog ?? _noLog;

  /// The declared bounds (allow-list + timeout).
  final ComputeBounds bounds;
  final CommandExecutor _executor;
  final void Function(String) _onLog;

  /// Runs [cmd] iff it is in-bounds; the returned future completes with a
  /// [ComputeBoundsException] otherwise (a rejection, never a synchronous throw).
  /// The in-bounds run is capped at [ComputeBounds.timeout] — past it the result
  /// is a non-zero [CommandResult] (the wait is bounded; hard process teardown
  /// on timeout is the deferred M4 `terminateGroup`/pgid reaper, ADR-0011
  /// Hazards). (An act.)
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
    return _executor(cmd).timeout(
      bounds.timeout,
      onTimeout: () => CommandResult(
        exitCode: 124, // conventional "timed out" exit code
        stdout: '',
        stderr: 'compute: "${cmd.command}" timed out after '
            '${bounds.timeout.inSeconds}s',
        durationMs: bounds.timeout.inMilliseconds,
      ),
    );
  }
}

/// The default compute [CommandExecutor]: a real `Process.run` with EXPLICIT
/// argv (no shell — so no string interpolation / injection), timed. Offline
/// tests inject a fake instead of spawning a process.
Future<CommandResult> defaultCommandExecutor(DispatchCommand cmd) async {
  final sw = Stopwatch()..start();
  final r = await Process.run(cmd.command, cmd.args, workingDirectory: cmd.workdir);
  sw.stop();
  return CommandResult(
    exitCode: r.exitCode,
    stdout: r.stdout.toString(),
    stderr: r.stderr.toString(),
    durationMs: sw.elapsedMilliseconds,
  );
}

/// Adapts the COMPUTE domain's BOUNDED "use" onto the federation's kind-agnostic
/// [DispatchHandler] (the lessor-side glue — moved out of the federation core at
/// the M6 Track D split). Decodes a [DispatchCommand], runs it through a
/// [BoundedCommandExecutor] (allow-list + timeout over [bounds]), encodes the
/// [CommandResult]. A refused (out-of-bounds) command surfaces as a non-zero
/// [CommandResult] (exit 126 = "command refused") so the lessee gets a clean
/// result rather than an opaque transport error — the lessor never runs it.
DispatchHandler computeDispatchHandler({
  required ComputeBounds bounds,
  CommandExecutor? executor,
  void Function(String)? onLog,
}) {
  final log = onLog ?? _noLog;
  final bounded = BoundedCommandExecutor(
    bounds: bounds,
    executor: executor,
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
