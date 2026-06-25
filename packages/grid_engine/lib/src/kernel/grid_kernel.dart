import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import '../bridge/grid_join_bridge.dart';
import '../effect/effect_context.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../seeds/grid_seed.dart';
import '../seeds/rig_scope.dart';
import 'effect_resolver.dart';

/// The kernel: composes the running tree and drives it (ADR-0007 /
/// M4-P0-BUILD-ORDER Track E/F).
///
/// It assembles the ambient providers above the [Grid] — the work-axis
/// [JoinedSnapshotNotifier] (from the [bridge]), the [EffectContext] (the
/// provider/writer/stateRig the effects resolve), and the [EffectResolver]
/// (phase → effect Seed) — mounts the tree under a [TreeOwner], and runs the
/// reactive loop:
///
///   a bridge push → `WorkList` (the sole observer) marks dirty → the owner's
///   empty→non-empty edge fires [TreeOwner.onNeedsFlush] → one batched
///   microtask flush reconciles the work set (mount = spawn, unmount = kill, a
///   phase advance = swap the effect child).
///
/// `root.markNeedsRebuild()` is NEVER called — only the observing `WorkList`
/// dirties (derailment-invariant 1); the kernel just drains what the dirty set
/// holds. Flushes are coalesced: many dirties between microtask turns collapse
/// into one flush.
class GridKernel {
  /// Assembles the kernel. The tree is not mounted until [start].
  GridKernel({
    required this.bridge,
    required EffectContext effectContext,
    required EffectResolver resolver,
    required List<RigScope> rigs,
  }) : _effectContext = effectContext,
       _resolver = resolver,
       _rigs = rigs;

  /// The join bridge feeding the work axis — the kernel owns its lifecycle
  /// (started in [start], disposed in [dispose]).
  final GridJoinBridge bridge;
  final EffectContext _effectContext;
  final EffectResolver _resolver;
  final List<RigScope> _rigs;

  final TreeOwner _owner = TreeOwner();
  bool _started = false;
  bool _disposed = false;
  bool _flushScheduled = false;

  /// Mounts the tree and starts the reactive loop. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Wire the flush trigger BEFORE mounting; the first build runs synchronously
    // in mountRoot (no markNeedsRebuild), so onNeedsFlush won't fire during it.
    _owner.onNeedsFlush = _scheduleFlush;
    bridge.start();
    _owner.mountRoot(
      InheritedSeed<JoinedSnapshotNotifier>(
        value: bridge.notifier,
        child: InheritedSeed<EffectContext>(
          value: _effectContext,
          child: InheritedSeed<EffectResolver>(
            value: _resolver,
            child: Grid(_rigs),
          ),
        ),
      ),
    );
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (!_disposed) _owner.flush();
    });
  }

  /// Tears down the tree (unmounting every effect → kill) and the bridge.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner.dispose();
    bridge.dispose();
  }
}
