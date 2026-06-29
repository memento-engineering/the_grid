/// Cross-station federation: resource leasing over a pluggable bus (ADR-0011).
///
/// A station OFFERS capacity ([StationServer]); a peer LEASES a slot
/// ([StationClient]/[HttpStationClient]) and dispatches a generic
/// [DispatchCommand], collecting a [CommandResult]. Capacity is arbitrated by
/// declare-and-check ([LeaseManager]). HTTP is impl #1 of the bus seam; MQTT/WS
/// drop in behind [StationClient] later.
library;

export 'src/lease_manager.dart';
export 'src/protocol.dart';
export 'src/station_client.dart';
export 'src/station_server.dart';
