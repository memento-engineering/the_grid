/// Wire value types for cross-station resource leasing — the lossy-bus payloads
/// (ADR-0011). Plain immutable classes with hand-written JSON (no codegen): the
/// federation wire is small and must stay dependency-light so the lessor runs
/// anywhere `dart` runs.
library;

import 'package:meta/meta.dart';

/// Base for every federation-protocol failure.
class FederationException implements Exception {
  /// Creates a federation exception carrying [message].
  const FederationException(this.message);

  /// A human-readable description.
  final String message;

  @override
  String toString() => 'FederationException: $message';
}

/// Thrown when a lessor REFUSES a lease (no capacity / not offered) — the
/// declare-and-check denial (HTTP 409).
class LeaseDeniedException extends FederationException {
  /// Creates a denial carrying [reason].
  const LeaseDeniedException(super.reason);
}

/// Thrown when a lease id is unknown or has EXPIRED (TTL reaped) — HTTP 404/410.
class LeaseInvalidException extends FederationException {
  /// Creates an invalid-lease error carrying [message].
  const LeaseInvalidException(super.message);
}

/// A station's advertised presence + current capacity (the `GET /presence`
/// body) — discovery plus a liveness/health probe.
@immutable
class Presence {
  /// Creates a presence snapshot.
  const Presence({
    required this.station,
    required this.kinds,
    required this.offered,
    required this.available,
  });

  /// The station id (e.g. `the-dashboard`).
  final String station;

  /// The resource-asset kinds this station offers (e.g. `['compute']`).
  final List<String> kinds;

  /// Total slots offered.
  final int offered;

  /// Slots currently free (offered minus held leases).
  final int available;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'station': station,
    'kinds': kinds,
    'offered': offered,
    'available': available,
  };

  /// Parses [j].
  static Presence fromJson(Map<String, dynamic> j) => Presence(
    station: j['station'] as String,
    kinds: (j['kinds'] as List).cast<String>(),
    offered: j['offered'] as int,
    available: j['available'] as int,
  );
}

/// A lessee's request for one slot of [kind] (the `POST /lease` body).
@immutable
class LeaseRequest {
  /// Creates a lease request.
  const LeaseRequest({required this.lessee, this.kind = 'compute'});

  /// The requesting station id.
  final String lessee;

  /// The resource-asset kind requested.
  final String kind;

  /// JSON form.
  Map<String, dynamic> toJson() => {'lessee': lessee, 'kind': kind};

  /// Parses [j].
  static LeaseRequest fromJson(Map<String, dynamic> j) => LeaseRequest(
    lessee: j['lessee'] as String,
    kind: (j['kind'] as String?) ?? 'compute',
  );
}

/// A granted lease (the `POST /lease` success body): the handle the lessee
/// dispatches against, plus the TTL after which the lessor reaps it.
@immutable
class LeaseGrant {
  /// Creates a grant.
  const LeaseGrant({
    required this.leaseId,
    required this.station,
    required this.ttlSeconds,
    this.kind = 'compute',
  });

  /// The opaque lease handle.
  final String leaseId;

  /// The granting station id.
  final String station;

  /// Seconds the lease lives without activity before the lessor reaps it.
  final int ttlSeconds;

  /// The leased resource-asset kind.
  final String kind;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'leaseId': leaseId,
    'station': station,
    'ttlSeconds': ttlSeconds,
    'kind': kind,
  };

  /// Parses [j].
  static LeaseGrant fromJson(Map<String, dynamic> j) => LeaseGrant(
    leaseId: j['leaseId'] as String,
    station: j['station'] as String,
    ttlSeconds: j['ttlSeconds'] as int,
    kind: (j['kind'] as String?) ?? 'compute',
  );
}

/// A generic command to run on a leased slot (the `POST .../dispatch` body).
/// **No inference this pass** — this is an ordinary process, the seed of the
/// generic (claude-agnostic) coding/burn capability.
@immutable
class DispatchCommand {
  /// Creates a dispatch.
  const DispatchCommand({
    required this.command,
    this.args = const [],
    this.workdir,
  });

  /// The executable.
  final String command;

  /// Its arguments.
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

/// The result of running a [DispatchCommand] on a leased slot.
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
