/// The butane burn asset domain (ADR-0011 D9, M6 Track F) — the cross-station
/// BURN formula, offline end-to-end.
///
/// The burn is two capability-scoped orders + two orthogonal channels:
///  - **orders** — `burn-follower` ([BurnFollowerCapability]) leased to a
///    capability match + `burn-host` ([BurnHostCapability]) local, composed into
///    [kBurnFormula] at the engine Capability seam (mirroring
///    `grid_assets/src/code`);
///  - **channels** — the federation BUS (lease + endpoint rendezvous, via
///    `grid_federation`'s `StationClient`) and the DIRECT `leonard_drive` ↔
///    `ext.exploration.*` perception channel ([LeonardDrive]), kept orthogonal.
///
/// The follower side ([ButaneFollowerRunner]) provisions/builds/launches the
/// app-under-test exposing exploration ([FollowerLauncher]), publishes its
/// [FollowerEndpoint], and is GUARANTEED to be torn down via the M4
/// `terminateGroup`/pgid reaper. The host runs a SCRIPTED [DriveScenario] (zero
/// inference) and collects a domain [TestReport].
///
/// In-repo home for M6; the sibling-to-`butane_flutter` placement is the later
/// split (ADR-0011 build-order placement decision).
library;

export 'src/burn/burn_capabilities.dart';
export 'src/burn/burn_report.dart';
export 'src/burn/burn_scenario.dart';
export 'src/burn/follower.dart';
