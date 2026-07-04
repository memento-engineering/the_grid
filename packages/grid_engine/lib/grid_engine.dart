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

// Domain (value types).
export 'src/domain/joined_snapshot.dart';
export 'src/domain/session_bead.dart';
export 'src/domain/substation_config.dart';
export 'src/domain/session_projection.dart';

// Grid opinions layered on beads' generic models (AL-1b): driveability
// narrowing over IssueType, and session/message/molecule domain projections —
// the_grid's own reading of the generic beads primitives, not part of the
// pure beads client (`bd` itself has no notion of these).
export 'src/domain/driveable_work.dart';
export 'src/projections/agent_session.dart';
export 'src/projections/message.dart';
export 'src/projections/molecule.dart';

// The station-level ambient services (kernel-provided) a node resolves in one
// inherited lookup: process transport + the bd chokepoint + the owned state rig
// + the adopt-liveness seam. Substation-scoped concerns (source control, the
// workspace/branch layout) live on the SubstationScope's ServiceBundle, not here.
export 'src/kernel/station_services.dart';

// The OPINIONS (agent/verify/land + the `code` circuit + the git
// `SourceControl`) live in the `grid_assets` package, NEVER in the engine
// (ADR-0007 §1: the opinion-free kernel — a structural fence keeps them out).

// Kernel: the seams + the composition/flush driver.
export 'src/kernel/session_resolver.dart';
export 'src/kernel/station_kernel.dart';
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
