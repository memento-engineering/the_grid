/// `grid run --tree` composition — wires the M4 tree engine (ADR-0007: the
/// running grid IS `genesis_tree`) from INJECTABLE seams, exactly as
/// [composeRun] wires the M2/M3 spine, so the dry-run smoke drives the whole
/// assembly with fakes (no live `tg`, no real `claude`, no real `git`).
///
/// **Pure composition.** [composeRunTree] constructs no process, opens no
/// socket, and writes no bead — it builds the [GridKernel] + the
/// [RestartReconciler] and hands back a [TreeRunWiring]. *Starting* is
/// [TreeRunWiring.start]'s job; with a dry [EffectContext.provider] (a recording
/// no-op transport) and the land ops left null, `start()` is inert beyond the
/// in-memory tree mount + the (recorded) spawn.
///
/// The live `grid run --tree` COMMAND — one that actually spawns `claude` and
/// touches a real workspace + state store + root checkout — is the human gate
/// (the M3 precedent): not built here.
library;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';

/// The resolved tree-engine wiring — built by [composeRunTree] from the
/// injectable seams, started/torn down by the caller. A value-ish holder so a
/// test can assert the composition WITHOUT running a live loop.
class TreeRunWiring {
  TreeRunWiring({
    required this.kernel,
    required this.restart,
    required Future<void> Function() freshnessBarrier,
  }) : _freshnessBarrier = freshnessBarrier;

  /// The composed M4 kernel — the running tree. Not mounted until [start].
  final GridKernel kernel;

  /// The Track-D restart respawn-or-skip reconciler, run once BEFORE the kernel
  /// mounts (so survivors are reconciled before the tree blindly respawns).
  final RestartReconciler restart;

  final Future<void> Function() _freshnessBarrier;

  /// Brings the tree up in the build-order's pinned ordering (ADR-0007 §4 /
  /// M4-P0-BUILD-ORDER Track D): the freshness barrier completes, THEN the
  /// restart reconciler reconciles the survivors, THEN — and only then — the
  /// kernel mounts and spawns. "Spawns mount only after the barrier completes."
  Future<void> start() async {
    await _freshnessBarrier();
    await restart.reconcile();
    kernel.start();
  }

  /// Tears down the tree (unmounting every effect → kill) + the join bridge.
  Future<void> teardown() async => kernel.dispose();
}

/// Assembles the M4 tree-engine [TreeRunWiring] from injectable seams.
///
/// Mirrors [composeRun]'s injectable-seam style so the dry-run smoke drives the
/// whole composition with fakes: the [work]/[state] [SnapshotSource]s (fakes in
/// a test; [RuntimeSnapshotSource] over the real controllers in the live arm),
/// the [effectContext] (a dry provider + the bd write chokepoint; land ops left
/// null for an offline build), the per-rig [rigs] config, the [git] service +
/// [workRoot] (the Track-D worktree seam), the [groups] process-group
/// controller (the orphan-kill seam — kept REAL so its `pgid <= 1` guard is
/// exercised), and the [freshnessBarrier] (a completed re-query of the read +
/// state runtimes).
///
/// Construction only: it builds
///  - a [GridJoinBridge] over [work] + [state] (the lone subscription, A39),
///  - a [DefaultEffectResolver] (the compiled built-in capability set),
///  - the [RigScope]s (one per [RigConfig], keyed by rig id so a rig add/remove
///    mounts/unmounts exactly that scope),
///  - a [RestartReconciler] binding the engine's narrow worktree seams to the
///    injected [git] service's `listBeadWorktrees`/`reap` (the engine never
///    names the concrete VCS service — ADR-0007 §1), reading the post-barrier
///    OWNED session cursors from [state]'s `current` snapshot, and
///  - the [GridKernel] over the bridge + context + resolver + scopes.
///
/// Nothing is started; [TreeRunWiring.start] drives the barrier → restart →
/// mount ordering.
TreeRunWiring composeRunTree({
  required SnapshotSource work,
  required SnapshotSource state,
  required EffectContext effectContext,
  required List<RigConfig> rigs,
  required GridGitService git,
  required RootCheckout workRoot,
  required ProcessGroupController groups,
  required Future<void> Function() freshnessBarrier,
}) {
  final bridge = GridJoinBridge(work: work, state: state);
  const resolver = DefaultEffectResolver();

  // One config scope per rig, keyed by rig id so a rig add/remove mounts /
  // unmounts exactly that scope (the Grid reconciles its scope children by key).
  final rigScopes = rigs
      .map(
        (config) => RigScope(
          configNotifier: RigConfigNotifier(config),
          key: ValueKey('scope.${config.rigId}'),
        ),
      )
      .toList(growable: false);

  // Track D — bind the engine's narrow worktree seams to the injected git
  // service so the engine never names the concrete VCS service (ADR-0007 §1).
  // The state-store cursor read happens AFTER the barrier; an absent baseline
  // (state.current == null before the first emission) projects no cursors —
  // every survivor is then respawn-pending, never wrongly skipped.
  final restart = RestartReconciler(
    listWorktrees: git.listBeadWorktrees,
    reapWorktree: git.reap,
    workRoot: workRoot,
    groups: groups,
    freshnessBarrier: freshnessBarrier,
    stateSnapshot: () => state.current ?? _emptySnapshot(),
  );

  final kernel = GridKernel(
    bridge: bridge,
    effectContext: effectContext,
    resolver: resolver,
    rigs: rigScopes,
  );

  return TreeRunWiring(
    kernel: kernel,
    restart: restart,
    freshnessBarrier: freshnessBarrier,
  );
}

/// An empty [GraphSnapshot] — the fail-safe the restart reconciler projects
/// cursors from when the state store has no baseline yet (no sessions ⇒ every
/// survivor respawn-pending, never wrongly skipped).
GraphSnapshot _emptySnapshot() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
