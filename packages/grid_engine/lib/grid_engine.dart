/// M4 tree engine — `genesis_tree` IS the engine (ADR-0007, Accepted
/// 2026-06-24).
///
/// `build(observed)` reconciles the running system: keyed reconcile + Branch
/// lifecycle = the work lifecycle (mount = spawn, unmount = kill, phase = a
/// reconcile transition). The kernel is opinion-light — capabilities are
/// effect Seeds contributed by an extension; the engine holds no landing /
/// VCS / provider opinion.
///
/// The public surface is filled by the Wave 1+ tracks. This barrel currently
/// proves only that the cross-workspace `genesis_tree` link resolves.
library;

// Wave 0 resolution smoke: prove the cross-workspace genesis_tree import
// resolves and analyzes before any Seed is authored. Replaced by the real
// Seed graph in Wave 1 (Track A).
import 'package:genesis_tree/genesis_tree.dart' show TreeOwner;

/// The engine's scheduler is genesis_tree's [TreeOwner] — never a hand-rolled
/// loop (ADR-0007 Decision 1). Placeholder alias; superseded by the real
/// `Grid` root Seed in Wave 1.
typedef EngineScheduler = TreeOwner;
