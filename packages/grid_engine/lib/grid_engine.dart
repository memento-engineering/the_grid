/// M4 tree engine — `genesis_tree` IS the engine (ADR-0007, Accepted
/// 2026-06-24).
///
/// `build(observed)` reconciles the running system: keyed reconcile + Branch
/// lifecycle = the work lifecycle (mount = spawn, unmount = kill, phase = a
/// reconcile transition). The kernel is opinion-light — capabilities are effect
/// Seeds contributed by an extension via an [EffectResolver]; the engine holds
/// no landing / VCS / provider opinion.
///
/// The tree (Wave 1 / Track A):
/// `Station` → `SubstationScope` → `Substation` → `WorkList` → `WorkBead` → effect Seed.
/// Config flows down the *ancestors* (SubstationScope/Substation); the work axis is observed
/// by exactly one node, `WorkList` (derailment-invariant 1).
library;

// The join bridge (the only subscription into the snapshot pipelines, A39).
export 'src/bridge/station_join_bridge.dart';
export 'src/bridge/snapshot_source.dart';

// The reentrant authoring SDK surface (ADR-0008 D2/D4 / M4-P1 Track A/E): the
// value-types + the pure frontier predicate + the opaque Capability/Service
// interfaces the author composes — never a Seed.
export 'src/sdk/capability.dart';
export 'src/sdk/sdk.dart';

// The reentrant engine (ENGINE-PRIVATE — never subclassed by an asset; the
// public/private package split is deferred, D1): the SessionScope adopt-or-mint
// lifecycle owner (D-2), the FormulaScope inflater + its registry/clock seam
// (Track D), and the resolver that roots the subtree at the EffectResolver seam.
export 'src/formula/capability_host.dart';
export 'src/formula/capability_registry.dart';
export 'src/formula/default_capability_registry.dart';
export 'src/formula/formula_resolver.dart';
export 'src/formula/formula_scope.dart';
export 'src/formula/session_handle.dart';
export 'src/formula/session_scope.dart';
export 'src/formula/stable_inherited.dart';

// Domain (value types).
export 'src/domain/joined_snapshot.dart';
export 'src/domain/session_bead.dart';
export 'src/domain/substation_config.dart';
export 'src/domain/session_projection.dart';
export 'src/domain/work_phase.dart';

// The effect carrier — the runtime heart (Track C): a tree node whose Branch
// lifecycle IS the work-process lifecycle (mount = spawn, unmount = kill).
export 'src/effect/effect_context.dart';
export 'src/effect/effect_seed.dart';

// Extension (the compiled DefaultExtension capabilities) — the OPINIONS live
// here, never in the kernel/effect core (ADR-0007 §1): the agent/verify/land
// capability Seeds + the resolver that maps a phase to one.
export 'src/extension/default_extension.dart';

// Kernel: the seams + the composition/flush driver.
export 'src/kernel/effect_resolver.dart';
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
