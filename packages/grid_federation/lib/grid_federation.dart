/// Cross-station federation: resource leasing over a pluggable bus (ADR-0011).
///
/// The TRANSPORT-FREE contracts — [Presence]/[LeaseRequest]/[LeaseGrant]/the
/// `Federation*Exception`s, the [StationClient] bus-seam interface, and the
/// [CapabilityFacts] model (+ [CapabilityProbe]/[CapabilityRevalidator]) — now
/// live in `grid_engine`'s SDK (the honesty-pass D-A9/D-B5 split, 2026-07-03:
/// "the engine knows federation in CONCEPT, not detail") and are re-exported
/// here so every existing consumer keeps compiling unchanged. This package is
/// now IMPLS-ONLY over those types: it dies in AL-5b, when its impls move to
/// power_station's `federated_grid_assets`.
///
/// A station OFFERS capacity ([StationServer]); a peer LEASES a slot
/// ([StationClient]/[HttpStationClient]) and dispatches an OPAQUE payload (what
/// it means + what "use" runs is defined by the asset domain that owns the kind,
/// shipped in `grid_assets`), collecting a result. Capacity is
/// arbitrated by the owner-authoritative [LeaseManager], which bakes in the
/// ADR-0011 hazards: a monotonic fencing token, a max lease lifetime + a FIFO
/// wait-queue, owner-clock reaping, and request idempotency. HTTP is impl #1 of
/// the kind-agnostic bus seam; MQTT/WS drop in behind [StationClient] later.
///
/// Membership is **static** ([Membership]/[Peer]/[MembershipLoader], ADR-0011
/// D4): a station declares its peers in config; discovery is a later asset.
/// [Presence] carries the gossip split — the durable capability profile + the
/// ephemeral capacity — and a lessee [StationClient.heartbeat]s so the owner
/// reaps a disconnected lease by its own clock (a missed-heartbeat threshold).
///
/// SYNC is a SEPARATE channel from the lease bus (ADR-0011 D7): [GitSyncService]
/// distributes code/assets to a peer's bare repo over a git remote
/// ([GitSyncService.ensureRemote]/[GitSyncService.push]/[GitSyncService.distribute]),
/// SSH for real and a local file-path remote offline. The bus carries
/// coordination; git carries the code.
library;

export 'package:grid_engine/grid_engine.dart'
    show
        CapabilityFacts,
        CapabilityProbe,
        CapabilityRevalidator,
        FakeProbe,
        FederationException,
        LeaseDeniedException,
        LeaseGrant,
        LeaseInvalidException,
        LeaseRequest,
        Presence,
        RevalidationResult,
        StationClient,
        ToolchainProbe,
        ToolchainQuery,
        kDartTarget,
        kDefaultKind,
        kFlutterTarget,
        kRadio,
        kSetFactKeys,
        kSystemOs,
        kTargetChain,
        parseToolchainOs;

export 'src/git_sync.dart';
export 'src/lease_manager.dart';
export 'src/membership.dart';
export 'src/station_client.dart';
export 'src/station_server.dart';
