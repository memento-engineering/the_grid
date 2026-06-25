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
/// `Grid` → `RigScope` → `Rig` → `WorkList` → `WorkBead` → effect Seed.
/// Config flows down the *ancestors* (RigScope/Rig); the work axis is observed
/// by exactly one node, `WorkList` (derailment-invariant 1).
library;

// The join bridge (the only subscription into the snapshot pipelines, A39).
export 'src/bridge/grid_join_bridge.dart';
export 'src/bridge/snapshot_source.dart';

// Domain (value types).
export 'src/domain/joined_snapshot.dart';
export 'src/domain/session_bead.dart';
export 'src/domain/rig_config.dart';
export 'src/domain/session_projection.dart';
export 'src/domain/work_phase.dart';

// The effect carrier — the runtime heart (Track C): a tree node whose Branch
// lifecycle IS the work-process lifecycle (mount = spawn, unmount = kill).
export 'src/effect/effect_context.dart';
export 'src/effect/effect_seed.dart';

// Kernel seams.
export 'src/kernel/effect_resolver.dart';
export 'src/kernel/idle.dart';

// Reactive sources (the only subscriptions into the pipelines live here).
export 'src/notifiers/joined_snapshot_notifier.dart';
export 'src/notifiers/rig_config_notifier.dart';

// The Seeds (the tree topology).
export 'src/seeds/grid_seed.dart';
export 'src/seeds/rig.dart';
export 'src/seeds/rig_scope.dart';
export 'src/seeds/work_bead.dart';
export 'src/seeds/work_list.dart';
