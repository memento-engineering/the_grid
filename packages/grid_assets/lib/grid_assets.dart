/// The_grid's opinion assets — the agent/verify/land [Capability] impls + the
/// `code` [Formula] + the git [SourceControl] (ADR-0008 D2 / M4-P1 §6).
///
/// These are the OPINIONS the opinion-free engine (grid_engine) must not carry
/// (ADR-0007 §1): the coding agent it spawns (`claude`), the check it runs, the
/// PR it opens. The composer (`grid_cli`) wires them via [buildCodeRegistry] +
/// a `FormulaResolver`. This is the in-repo home of the `power_station` assets
/// (D-1; the standalone-repo extraction is deferred).
///
/// The COMPUTE asset domain (ADR-0011 D2/D3, M6 Track D) also lives here: the
/// `DispatchCommand`/`CommandResult` payloads + the bounded "use" + the capacity
/// predicate moved OUT of the kind-agnostic `grid_federation` core, and the
/// `LeaseCapability` wraps a federation lease as an engine [Capability]
/// (mount = acquire + dispatch, unmount = release).
library;

export 'src/assets/asset_loader.dart';
export 'src/code/code_capabilities.dart';
export 'src/code/committee.dart';
export 'src/compute/bounded_use.dart';
export 'src/compute/compute_command.dart';
export 'src/compute/lease_capability.dart';
export 'src/dart/dart_command.dart';
export 'src/dart/dart_domain.dart';
export 'src/dart/dart_link_service.dart';
export 'src/dart/pub_links.dart';
export 'src/domain/domain_envelope.dart';
export 'src/lease/bus_lease.dart';
