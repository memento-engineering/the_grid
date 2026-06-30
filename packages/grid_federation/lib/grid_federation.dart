/// Cross-station federation: resource leasing over a pluggable bus (ADR-0011).
///
/// A station OFFERS capacity ([StationServer]); a peer LEASES a slot
/// ([StationClient]/[HttpStationClient]) and dispatches an opaque payload (the
/// COMPUTE domain's [DispatchCommand] → [CommandResult] this pass), collecting a
/// result. Capacity is arbitrated by the owner-authoritative [LeaseManager],
/// which bakes in the ADR-0011 hazards: a monotonic fencing token, a max lease
/// lifetime + a FIFO wait-queue, owner-clock reaping, and request idempotency.
/// HTTP is impl #1 of the kind-agnostic bus seam; MQTT/WS drop in behind
/// [StationClient] later.
library;

export 'src/lease_manager.dart';
export 'src/protocol.dart';
export 'src/station_client.dart';
export 'src/station_server.dart';
