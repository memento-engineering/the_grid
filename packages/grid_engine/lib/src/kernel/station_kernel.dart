import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import '../bridge/station_join_bridge.dart';
import '../domain/joined_snapshot.dart';
import '../effect/effect_context.dart';
import '../formula/capability_registry.dart';
import '../formula/stable_inherited.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability.dart';
import '../seeds/station_seed.dart';
import '../seeds/substation_scope.dart';
import 'effect_resolver.dart';

/// The kernel: composes the running tree and drives it (ADR-0007 /
/// M4-P0-BUILD-ORDER Track E/F).
///
/// It assembles the ambient providers above the [Station] — the work-axis
/// [JoinedSnapshotNotifier] (from the [bridge]), the [EffectContext] (the
/// provider/writer/stateSubstation the effects resolve), and the [EffectResolver]
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
class StationKernel {
  /// Assembles the kernel. The tree is not mounted until [start].
  ///
  /// [clock] / [scheduleTimer] are the supervised-restart backoff seam (D-5/F1):
  /// the kernel owns the wall clock + the cooldown Timer (NEVER a Seed-owned
  /// timer), injectable so the re-poke is driven deterministically offline.
  StationKernel({
    required this.bridge,
    required EffectContext effectContext,
    required EffectResolver resolver,
    required List<SubstationScope> substations,
    CapabilityRegistry? registry,
    ServiceBundle services = const ServiceBundle(),
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
  }) : _effectContext = effectContext,
       _resolver = resolver,
       _substations = substations,
       _registry = registry,
       _services = services,
       _clock = clock ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? Timer.new;

  /// The join bridge feeding the work axis — the kernel owns its lifecycle
  /// (started in [start], disposed in [dispose]).
  final StationJoinBridge bridge;
  final EffectContext _effectContext;
  final EffectResolver _resolver;
  final List<SubstationScope> _substations;

  /// The reentrant capability/formula resolution seam (ADR-0008 D4) — provided
  /// as a stable ambient value the `FormulaScope` inflater resolves. Null when
  /// the resolver roots a non-reentrant subtree (a test fake that returns a
  /// plain leaf needs no registry).
  final CapabilityRegistry? _registry;

  /// The pluggable Service collaborators (source control / trust / transport —
  /// ADR-0008 D5), provided stably above `Station`; a `CapabilityHost` resolves
  /// them for its capability. Empty by default (an offline build wires none).
  final ServiceBundle _services;

  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _scheduleTimer;

  final TreeOwner _owner = TreeOwner();
  bool _started = false;
  bool _disposed = false;
  bool _flushScheduled = false;
  Timer? _cooldownTimer;

  /// Mounts the tree and starts the reactive loop. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    // Wire the flush trigger BEFORE mounting; the first build runs synchronously
    // in mountRoot (no markNeedsRebuild), so onNeedsFlush won't fire during it.
    _owner.onNeedsFlush = _scheduleFlush;
    bridge.start();
    // Build the ambient-provider stack inside-out. The reentrant engine's
    // CapabilityRegistry + ServiceBundle are STABLE handles (D-6:
    // updateShouldNotify => false), so the resolving→ready transitions inside a
    // formula subtree never fan-rebuild from them; the work-axis notifier +
    // context + resolver keep their existing (plain) provision. The registry is
    // wrapped only when present (a non-reentrant fake resolver needs none).
    Seed root = Station(_substations);
    root = StableInheritedSeed<ServiceBundle>(value: _services, child: root);
    final registry = _registry;
    if (registry != null) {
      root = StableInheritedSeed<CapabilityRegistry>(
        value: registry,
        child: root,
      );
    }
    root = InheritedSeed<EffectResolver>(value: _resolver, child: root);
    root = InheritedSeed<EffectContext>(value: _effectContext, child: root);
    root = InheritedSeed<JoinedSnapshotNotifier>(
      value: bridge.notifier,
      child: root,
    );
    _owner.mountRoot(root);
    // Arm the backoff Timer for any baseline cooldown (a restart that adopts a
    // cooled-down session — D-5/F1). Steady-state scans happen in the flush
    // cycle below, so the kernel adds NO persistent notifier listener (WorkList
    // stays the sole observer + dirtier, invariant 1).
    _scanCooldowns();
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (_disposed) return;
      _owner.flush();
      // Re-scan after each flush: a failure cursor written this tick may carry a
      // new cooldown to arm (or a re-keyed step may clear one). No persistent
      // subscription — the kernel already owns this cycle.
      _scanCooldowns();
    });
  }

  /// Scans every owned session's cursor for the EARLIEST future cooldown and
  /// (re)arms the backoff Timer for it (D-5/F1). Reads the latest join through
  /// the notifier's synchronous accessor — NOT a persistent listener.
  void _scanCooldowns() {
    if (_disposed) return;
    final now = _clock();
    DateTime? earliest;
    for (final session in bridge.notifier.current.sessionsByWorkBead.values) {
      for (final node in session.cursor.values) {
        final cooldown = node.cooldownUntil;
        if (cooldown != null &&
            cooldown.isAfter(now) &&
            (earliest == null || cooldown.isBefore(earliest))) {
          earliest = cooldown;
        }
      }
    }
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    if (earliest != null) {
      _cooldownTimer = _scheduleTimer(earliest.difference(now), _repokeCooldown);
    }
  }

  /// A cooldown expired — re-emit a FRESH-instance copy of the current snapshot
  /// so `WorkList` re-runs the frontier predicate (now past the cooldown) and
  /// re-keys the eligible failed step (the backoff re-mount). A fresh instance is
  /// required because `JoinedSnapshot` is reference-y (no value equality), so an
  /// identical push would be a no-op. The re-emit goes through the notifier
  /// (WorkList stays the sole dirtier); `root.markNeedsRebuild` is NEVER called.
  void _repokeCooldown() {
    _cooldownTimer = null;
    if (_disposed) return;
    final current = bridge.notifier.current;
    bridge.notifier.push(
      JoinedSnapshot(
        graph: current.graph,
        sessionsByWorkBead: current.sessionsByWorkBead,
      ),
    );
  }

  /// Tears down the tree (unmounting every effect → kill) and the bridge.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _owner.dispose();
    bridge.dispose();
  }
}
