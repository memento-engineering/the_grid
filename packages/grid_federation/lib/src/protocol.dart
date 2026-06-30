/// Wire value types for cross-station resource leasing — the lossy-bus payloads
/// (ADR-0011). Plain immutable classes with hand-written JSON (no codegen): the
/// federation wire is small and must stay dependency-light so the lessor runs
/// anywhere `dart` runs.
///
/// The bus seam is **kind-agnostic** (ADR-0011 D3/D7): [Presence], [LeaseRequest]
/// and [LeaseGrant] are bus-level coordination types. [DispatchCommand] /
/// [CommandResult] are the COMPUTE domain's payloads — they ride the seam as an
/// opaque envelope and move to `grid_assets` at the M6 Track D split.
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

/// Thrown when a lessor REFUSES a lease (no capacity / not offered / the
/// wait-queue is full or the wait expired) — the declare-and-check denial
/// (HTTP 409).
class LeaseDeniedException extends FederationException {
  /// Creates a denial carrying [reason].
  const LeaseDeniedException(super.reason);
}

/// Thrown when a lease handle is no longer usable: the id is unknown, the TTL or
/// max-lifetime reaped it, or the dispatch/release carries a **stale fencing
/// token** (HTTP 404/410). Fencing rejections surface here so a zombie holder of
/// a reaped-then-reissued slot cannot act on it (ADR-0011 Hazards).
class LeaseInvalidException extends FederationException {
  /// Creates an invalid-lease error carrying [message].
  const LeaseInvalidException(super.message);
}

/// A station's advertised presence + current capacity (the `GET /presence`
/// body) — discovery plus a liveness/health probe.
///
/// Presence carries the **gossip** split (ADR-0011 D5/D7): the [profile] is the
/// **durable** half (a station's capability facts are truth, gossiped sparingly)
/// and [available] is the **ephemeral** half (free/used slots churn constantly).
@immutable
class Presence {
  /// Creates a presence snapshot.
  const Presence({
    required this.station,
    required this.kinds,
    required this.offered,
    required this.available,
    this.profile = const {},
  });

  /// The station id (e.g. `the-dashboard`).
  final String station;

  /// The resource-asset kinds this station offers (e.g. `['compute']`).
  final List<String> kinds;

  /// Total slots offered.
  final int offered;

  /// Slots currently free (offered minus held leases) — the EPHEMERAL half of
  /// the gossip (it churns; never reconciled cross-machine by wall-time).
  final int available;

  /// The station's **capability profile** — its advertised facts (the DURABLE
  /// half of the gossip). Scalar facts are strings; set-valued facts are lists
  /// (e.g. `{'system-os': 'linux', 'flutter-target': ['linux', 'android']}`).
  ///
  /// Carried here as opaque JSON so the wire is forward-compatible: the TYPED
  /// fact model, per-fact composition, the `InheritedSeed` cascade, containment
  /// matching, and the dart/flutter probes all land in M6 Track C — this is only
  /// the transport of the profile alongside capacity.
  final Map<String, Object?> profile;

  /// Returns a copy overriding [profile] (capacity is read from the owner).
  Presence copyWith({Map<String, Object?>? profile}) => Presence(
    station: station,
    kinds: kinds,
    offered: offered,
    available: available,
    profile: profile ?? this.profile,
  );

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'station': station,
    'kinds': kinds,
    'offered': offered,
    'available': available,
    if (profile.isNotEmpty) 'profile': profile,
  };

  /// Parses [j].
  static Presence fromJson(Map<String, dynamic> j) => Presence(
    station: j['station'] as String,
    kinds: (j['kinds'] as List).cast<String>(),
    offered: j['offered'] as int,
    available: j['available'] as int,
    profile: (j['profile'] as Map?)?.cast<String, Object?>() ?? const {},
  );
}

/// A lessee's request for one slot of [kind] (the `POST /lease` body).
///
/// [idempotencyKey] is a client-generated dedup key: a retried request carrying
/// the same key returns the SAME live grant, never a second grant (ADR-0011
/// lossy-bus idempotency). Empty = no dedup (each request is distinct).
@immutable
class LeaseRequest {
  /// Creates a lease request.
  const LeaseRequest({
    required this.lessee,
    this.kind = 'compute',
    this.idempotencyKey = '',
  });

  /// The requesting station id.
  final String lessee;

  /// The resource-asset kind requested.
  final String kind;

  /// The client-generated idempotency key (empty = none).
  final String idempotencyKey;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'lessee': lessee,
    'kind': kind,
    if (idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
  };

  /// Parses [j].
  static LeaseRequest fromJson(Map<String, dynamic> j) => LeaseRequest(
    lessee: j['lessee'] as String,
    kind: (j['kind'] as String?) ?? 'compute',
    idempotencyKey: (j['idempotencyKey'] as String?) ?? '',
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
    required this.fencingToken,
    this.heartbeatSeconds = 0,
    this.kind = 'compute',
  });

  /// The opaque lease handle.
  final String leaseId;

  /// The granting station id.
  final String station;

  /// Seconds the lease lives without activity before the lessor reaps it.
  final int ttlSeconds;

  /// The cadence (seconds) at which the lessee must HEARTBEAT to keep the lease
  /// alive; `0` = no heartbeat required (idle-TTL liveness only). The owner reaps
  /// a held lease once the heartbeat is missed past its threshold — **by its OWN
  /// clock** (no cross-machine timestamp math, ADR-0011 D5).
  final int heartbeatSeconds;

  /// The owner-issued **fencing token**: a monotonically increasing integer (the
  /// owner's own version counter, NEVER wall-clock — clock skew is fatal to
  /// cross-machine math, ADR-0011). Every grant on the owner gets a strictly
  /// greater token than any prior grant, so a reaped-then-reissued slot's new
  /// holder always carries a higher token. The owner REJECTS any dispatch/release
  /// whose token does not match the live lease's token (Chubby/Kleppmann
  /// fencing), so a zombie prior holder cannot double-use the slot.
  final int fencingToken;

  /// The leased resource-asset kind.
  final String kind;

  /// JSON form.
  Map<String, dynamic> toJson() => {
    'leaseId': leaseId,
    'station': station,
    'ttlSeconds': ttlSeconds,
    'fencingToken': fencingToken,
    'heartbeatSeconds': heartbeatSeconds,
    'kind': kind,
  };

  /// Parses [j].
  static LeaseGrant fromJson(Map<String, dynamic> j) => LeaseGrant(
    leaseId: j['leaseId'] as String,
    station: j['station'] as String,
    ttlSeconds: j['ttlSeconds'] as int,
    fencingToken: (j['fencingToken'] as int?) ?? 0,
    heartbeatSeconds: (j['heartbeatSeconds'] as int?) ?? 0,
    kind: (j['kind'] as String?) ?? 'compute',
  );
}

/// A generic command to run on a leased slot — the COMPUTE domain's dispatch
/// payload, serialized into the kind-agnostic bus envelope.
///
/// **No inference this pass** — this is an ordinary process, the seed of the
/// generic (claude-agnostic) coding/burn capability. Moves to `grid_assets` at
/// the M6 Track D compute-domain split; the federation core only sees the opaque
/// envelope it (de)serializes to.
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
