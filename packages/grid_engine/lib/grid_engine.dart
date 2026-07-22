/// M4 tree engine — `genesis_tree` IS the engine (ADR-0007, Accepted
/// 2026-06-24).
///
/// `build(observed)` reconciles the running system: keyed reconcile + Branch
/// lifecycle = the work lifecycle (mount = spawn, unmount = kill, a cursor tick =
/// a reconcile transition). The kernel is opinion-light — a work bead's running
/// subtree is contributed by an extension via a [SessionResolver]; the engine
/// holds no landing / VCS / provider opinion.
///
/// The tree:
/// `Station` → `SubstationScope` → `Substation` → `WorkList` → `WorkBead` →
/// (`SessionResolver`) → `SessionScope` → `CircuitScope` → `CapabilityHost` →
/// `Allocation` (the live effect — ADR-0009's third tree).
/// Config flows down the *ancestors* (SubstationScope/Substation); the work axis is observed
/// by exactly one node, `WorkList` (derailment-invariant 1).
library;

// The join bridge (the only subscription into the snapshot pipelines, A39).
export 'src/bridge/station_join_bridge.dart';
export 'src/bridge/snapshot_source.dart';

// The federated work-source union (tg-nsj) — fans N LOCAL beads workspaces
// into the ONE SnapshotSource the bridge's `work` axis observes.
export 'src/bridge/federated_snapshot_source.dart';
// The ONE cross-store block enforcement, shared by the union's dependency-row
// edges and the join's state-owned link beads.
export 'src/bridge/block_guard.dart';

// The reentrant authoring SDK surface (ADR-0008 D2/D4 / M4-P1 Track A/E): the
// value-types + the pure frontier predicate + the opaque Capability/Service
// interfaces the author composes — never a Seed.
export 'src/sdk/capability.dart';
export 'src/sdk/sdk.dart';

// The reentrant engine (ENGINE-PRIVATE — never subclassed by an asset; the
// public/private package split is deferred, D1): the SessionScope adopt-or-mint
// lifecycle owner (D-2), the CircuitScope inflater + its registry/clock seam
// (Track D), and the resolver that roots the subtree at the SessionResolver seam.
export 'src/circuit/capability_host.dart';
export 'src/circuit/capability_registry.dart';
export 'src/circuit/default_capability_registry.dart';
export 'src/circuit/circuit_resolver.dart';
export 'src/circuit/circuit_scope.dart';
export 'src/circuit/session_handle.dart';
export 'src/circuit/session_scope.dart';
export 'src/circuit/unclaimed_frontier.dart';

// Molecule model — the process-lease seam the circuit's allocation resolves
// (the vendor StationKernel.start / StationWork mount ambient to the work
// subtree, tg-h4u / tg-2mb).
export 'src/molecule/process_lease_vendor.dart'
    show ProcessLeaseVendor, requireProcessLeaseVendor, StationProcessLeaseVendor;
export 'src/molecule/station_process_transport.dart'
    show defaultProcessLeaseVendor;
// The molecule read projection — consumed by OUT-OF-PACKAGE operator surfaces
// (grid_cli rework) that must read molecule step state (tg-eli phase 1).
// In-package readers (wedge sampling) import the codec relatively and do not
// ride this export.
export 'src/molecule/molecule_codec.dart' show projectMoleculeCursor;
// The molecule bead-metadata schema (R1) — the durable wire keys a
// `type=molecule`/`type=step` bead carries. Exported so an out-of-package
// reader (grid_cli rework's step→session JOIN) names the ONE definition
// instead of hand-mirroring the wire literal (tg-eli phase 2).
export 'src/molecule/molecule_schema.dart'
    show MoleculeCircuitKeys, MoleculeStepKeys;

// Domain (value types).
// The state-owned CROSS-REPO link bead: the metadata schema, the read
// projection, and the arming refusal for an unseeded `link` type. Exported
// because the authoring verbs mint and close these beads and must name the ONE
// definition of the wire keys.
export 'src/domain/cross_link.dart';
export 'src/domain/joined_snapshot.dart';
// The rework-round contract (tg-o90) — the ONE cap + retired-round key shape
// shared by the `Rewind` arm (the engine) and `grid rework` (the operator verb).
export 'src/domain/rework.dart';
export 'src/domain/session_bead.dart';
// The session DISPOSITION (tg-4rw) — the pure done|held|voided reading of a
// closed session, consumed by BOTH the mount boundary (WorkList) and the
// adopt-or-mint decision (SessionScope). A closed session is never blanket-
// blocking: a DEAD KEY (closed mid-flight) mints fresh instead of wedging.
export 'src/domain/session_disposition.dart';
export 'src/domain/substation_config.dart';
export 'src/domain/session_projection.dart';
// Wedge detection (tg-jwh) — the station's own "is the grid stuck?" derivation
// over the producer-side join; the status surface reports it, no watcher
// re-derives it from raw sessions.
export 'src/domain/wedge.dart';

// Grid opinions layered on beads' generic models (AL-1b): driveability
// narrowing over IssueType — the_grid's own reading of the generic beads
// primitives, not part of the pure beads client.
export 'src/domain/driveable_work.dart';

// The station-level ambient services (kernel-provided) a node resolves in one
// inherited lookup: process transport + the bd chokepoint + the owned state rig
// + the adopt-liveness seam. Substation-scoped concerns (source control, the
// workspace/branch layout) live on the SubstationScope's ServiceBundle, not here.
export 'src/kernel/station_services.dart';

// The OPINIONS (agent/verify/land + the `code` circuit + the git
// `SourceControl`) live in the `grid_assets` package, NEVER in the engine
// (ADR-0007 §1: the opinion-free kernel — a structural fence keeps them out).

// Kernel: the seams + the composition/flush driver. StationDriver is the
// off-tree work-axis machinery (bridge lifecycle + D-5 cooldown Timer +
// unclaimed scan) extracted so runGrid's tree (grid_sdk, tg-yl8) reuses it.
export 'src/kernel/session_resolver.dart';
export 'src/kernel/station_driver.dart';
export 'src/kernel/station_kernel.dart';
// The station's own stuck-detector — owned + ticked by the StationDriver.
export 'src/kernel/wedge_monitor.dart';
export 'src/kernel/idle.dart';

// Reactive sources (the only subscriptions into the pipelines live here).
export 'src/notifiers/joined_snapshot_notifier.dart';
export 'src/notifiers/substation_config_notifier.dart';

// Restart respawn-or-skip (Track D): reconcile the survivors (worktrees + owned
// session cursors) BEFORE the tree re-mounts — skip done, kill orphans, respawn
// the rest.
export 'src/restart/restart_reconciler.dart';

// The Seeds (the tree topology).
export 'src/seeds/station_seed.dart';
export 'src/seeds/substation.dart';
export 'src/seeds/substation_scope.dart';
export 'src/seeds/work_bead.dart';
export 'src/seeds/work_list.dart';
