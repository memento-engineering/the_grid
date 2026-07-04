/// The TRANSPORT-FREE federation contracts (ADR-0011 D3/D7/D8; the honesty-pass
/// D-A9/D-B5 split, 2026-07-03): the wire value types + the abstract bus seam
/// for cross-station resource leasing. The engine knows federation in CONCEPT
/// only — no transport, no MQTT, no HTTP. `grid_federation` supplies the impls
/// ([StationServer]/[HttpStationClient]/[LeaseManager] — the owner-authoritative
/// arbitration policy) over these same types; a future bus (MQTT/WS) implements
/// [StationClient] without this file changing.
///
/// The bus seam is **kind-agnostic** (ADR-0011 D3/D7): [Presence], [LeaseRequest]
/// and [LeaseGrant] are bus-level coordination types. A `kind` is an opaque,
/// equality-checked label — the core bakes in NO concrete asset kind; each ASSET
/// DOMAIN names + interprets its own (the dispatch payload is an opaque envelope
/// the domain (de)serializes; the domain payloads themselves live in the asset
/// packages, never here).
///
/// Plain immutable classes with hand-written JSON (no codegen): the federation
/// wire is small and must stay dependency-light so a lessor runs anywhere `dart`
/// runs.
library;

import 'package:meta/meta.dart';

/// The default resource-asset kind a request/offer carries when it leaves `kind`
/// unspecified — a GENERIC placeholder, deliberately NOT a concrete kind (which
/// each asset domain names for itself, ADR-0011 D3). The federation core treats
/// `kind` as an opaque, equality-checked label and assumes no domain.
const String kDefaultKind = 'resource';

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

  /// The resource-asset kinds this station offers (each named by its own asset
  /// domain — the core treats them as opaque labels).
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
  /// fact model ([CapabilityFacts]) — per-fact composition, containment
  /// matching, the dart/flutter probes — bridges onto this profile via
  /// [CapabilityFacts.toProfile]/[CapabilityFacts.fromProfile].
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
    this.kind = kDefaultKind,
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
    kind: (j['kind'] as String?) ?? kDefaultKind,
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
    this.kind = kDefaultKind,
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
    kind: (j['kind'] as String?) ?? kDefaultKind,
  );
}

/// The cross-station bus, lessee view: presence, lease, dispatch, release. The
/// **pluggable, kind-agnostic transport seam** (ADR-0011): impl #1
/// (`HttpStationClient`, over HTTP) lives in `grid_federation`; a future
/// MQTT/WS bus implements this same interface, so nothing above the seam
/// changes (Nico, 2026-06-29).
///
/// The seam carries only these bus-level coordination types plus an OPAQUE
/// dispatch envelope ([Map]) — no domain/kind specifics leak in (ADR-0011 D3).
/// The lessee holds the [LeaseGrant], so the fencing token rides every
/// dispatch/release automatically.
abstract interface class StationClient {
  /// Reads the peer's presence + free capacity. (An observation.)
  Future<Presence> presence();

  /// Requests one slot; throws [LeaseDeniedException] on refusal. (An act.)
  Future<LeaseGrant> requestLease(LeaseRequest req);

  /// Runs an opaque [payload] on the slot held by [lease], propagating its
  /// fencing token. Returns the opaque result envelope. Throws
  /// [LeaseInvalidException] if the lease is gone or the token is stale.
  ///
  /// [idempotencyKey] (when set) lets the owner dedup retries: the same key
  /// returns the SAME result, never a second run.
  Future<Map<String, dynamic>> dispatch(
    LeaseGrant lease,
    Map<String, dynamic> payload, {
    String idempotencyKey,
  });

  /// Sends a liveness HEARTBEAT for [lease], propagating its fencing token, so the
  /// owner does not reap the held slot as disconnected. Throws
  /// [LeaseInvalidException] if the lease is gone or the token is stale. (An act.)
  Future<void> heartbeat(LeaseGrant lease);

  /// Releases the slot held by [lease] (idempotent), propagating its fencing
  /// token so a stale holder cannot free a reissued slot.
  Future<void> release(LeaseGrant lease);

  /// Releases any held transport resources.
  Future<void> close();
}
