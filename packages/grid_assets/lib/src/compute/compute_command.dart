/// The COMPUTE asset domain's contract (ADR-0011 D2/D3 — contracts are
/// domain-defined). Moved OUT of the federation core at the M6 Track D split: the
/// kind-agnostic bus ([StationServer]/[StationClient]) carries these payloads as
/// an opaque envelope; only this domain knows what they MEAN.
///
/// This file is pure value types + the domain's declare-and-check capacity
/// predicate (no I/O). The bounded "use" (how a command actually runs) lives in
/// `bounded_use.dart`; the engine-side lease-as-Capability in
/// `lease_capability.dart`.
library;

import 'package:meta/meta.dart';

/// The compute resource-asset kind label — what a compute lease requests/offers.
/// The federation core treats `kind` as an opaque, equality-checked string; this
/// is the COMPUTE domain naming its own kind (ADR-0011 D3).
const String kComputeKind = 'compute';

/// A generic command to run on a leased compute slot — the COMPUTE domain's
/// dispatch payload, serialized into the kind-agnostic bus envelope.
///
/// **No inference this pass** — this is an ordinary process (an EXPLICIT argv,
/// never a shell string), the seed of the generic (claude-agnostic) coding/burn
/// capability. Whether the lessor actually runs it is gated by the domain's
/// bounded "use" (`bounded_use.dart`): only allow-listed executables run.
@immutable
class DispatchCommand {
  /// Creates a dispatch for [command] with [args] (the explicit argv — never a
  /// shell string), optionally in [workdir] on the lessor.
  const DispatchCommand({
    required this.command,
    this.args = const [],
    this.workdir,
  });

  /// The executable (matched against the bounded-use allow-list).
  final String command;

  /// Its arguments — explicit argv (no shell, so no string interpolation).
  final List<String> args;

  /// Optional working directory on the lessor (defaults to the lessor's cwd).
  final String? workdir;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'command': command,
    'args': args,
    if (workdir != null) 'workdir': workdir,
  };

  /// Parses [j].
  static DispatchCommand fromJson(Map<String, dynamic> j) => DispatchCommand(
    command: j['command'] as String,
    args: ((j['args'] as List?) ?? const []).cast<String>(),
    workdir: j['workdir'] as String?,
  );
}

/// The result of running a [DispatchCommand] on a leased compute slot.
@immutable
class CommandResult {
  /// Creates a result.
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  /// The process exit code.
  final int exitCode;

  /// Captured stdout.
  final String stdout;

  /// Captured stderr.
  final String stderr;

  /// Wall-clock duration in milliseconds.
  final int durationMs;

  /// Whether the command succeeded (exit 0).
  bool get ok => exitCode == 0;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
    'durationMs': durationMs,
  };

  /// Parses [j].
  static CommandResult fromJson(Map<String, dynamic> j) => CommandResult(
    exitCode: j['exitCode'] as int,
    stdout: (j['stdout'] as String?) ?? '',
    stderr: (j['stderr'] as String?) ?? '',
    durationMs: (j['durationMs'] as int?) ?? 0,
  );
}

/// The COMPUTE domain's declare-and-check CAPACITY PREDICATE (ADR-0011 D3 — the
/// capacity predicate is domain-owned, not engine code).
///
/// A compute slot is grantable iff the request names [kComputeKind] AND the
/// lessor has at least one free slot ([available] > 0). The federation core runs
/// the GENERIC kind+slot arithmetic ([LeaseManager]); this names what "compute
/// capacity" MEANS so the core stays kind-agnostic. Pure — no I/O, no state.
bool computeHasCapacity({required String kind, required int available}) =>
    kind == kComputeKind && available > 0;
