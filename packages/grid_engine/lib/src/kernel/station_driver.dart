import 'dart:async';

import '../bridge/station_join_bridge.dart';
import '../circuit/capability_registry.dart';
import '../circuit/circuit_resolver.dart';
import '../circuit/unclaimed_frontier.dart';
import '../domain/wedge.dart';
import '../sdk/capability.dart';
import '../sdk/capability_facts.dart';
import 'wedge_monitor.dart';

/// The station's OFF-TREE work-axis machinery (extracted from [StationKernel]
/// so a tree mounted by a DIFFERENT owner — `runGrid`'s, tg-yl8 — reuses it
/// unchanged): the join-bridge lifecycle, the supervised-restart cooldown
/// Timer (D-5/F1: the driver owns the wall clock + the cooldown Timer, NEVER a
/// Seed), the backoff re-poke, and the unclaimed-frontier scan (D-B5 hook #1).
///
/// It adds NO subscription of its own: scans read the PRODUCER-side
/// [StationJoinBridge.latest] (what the bridge last pushed — never a sync read
/// of the notifier's reactive state, D-H rule 2, and never a persistent
/// listener), and the re-poke goes back through the notifier via
/// [StationJoinBridge.repush] so `WorkList` stays the sole observer + dirtier
/// (derailment-invariant 1).
///
/// Lifecycle: the owner calls [start] once (starts the bridge + the baseline
/// scans), [afterFlush] once per completed tree flush (a failure cursor
/// written this tick may carry a new cooldown to arm; whatever the flush left
/// unfulfillable is what a composed claim asset sees next), and [dispose] at
/// teardown (cancels the timer, disposes the bridge). `StationKernel` wires
/// these into its own flush loop; `runGrid` wires [afterFlush] through its
/// `onFlushed` hook.
class StationDriver {
  /// Assembles the driver over [bridge]. [clock] / [scheduleTimer] are the
  /// backoff seam (injectable so the re-poke — and the wedge poll — are driven
  /// deterministically offline). [rootCircuitFor] + [registry] +
  /// [onUnclaimedFrontier] wire the unclaimed-frontier scan — all-or-nothing:
  /// any of them null skips the scan entirely (no federation asset composed ⇒
  /// nothing to compute). [transport] is the emit-only observability sink the
  /// wedge alarm flares through (D-8); null (the default) still computes the
  /// state — it just flares to nobody.
  StationDriver({
    required this.bridge,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
    RootCircuitFor? rootCircuitFor,
    CapabilityRegistry? registry,
    CapabilityFacts stationFacts = const CapabilityFacts(),
    void Function(List<UnclaimedRequirement>)? onUnclaimedFrontier,
    ExplorationTransport? transport,
    Duration wedgeThreshold = kDefaultWedgeThreshold,
    Duration wedgePollInterval = kDefaultWedgePollInterval,
  }) : _clock = clock ?? DateTime.now,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _rootCircuitFor = rootCircuitFor,
       _registry = registry,
       _stationFacts = stationFacts,
       _onUnclaimedFrontier = onUnclaimedFrontier {
    _wedge = WedgeMonitor(
      latest: () => bridge.latest,
      threshold: wedgeThreshold,
      pollInterval: wedgePollInterval,
      transport: transport,
      clock: _clock,
      scheduleTimer: _scheduleTimer,
    );
  }

  /// The join bridge feeding the work axis — the driver owns its lifecycle
  /// (started in [start], disposed in [dispose]).
  final StationJoinBridge bridge;

  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _scheduleTimer;
  final RootCircuitFor? _rootCircuitFor;
  final CapabilityRegistry? _registry;
  final CapabilityFacts _stationFacts;
  final void Function(List<UnclaimedRequirement>)? _onUnclaimedFrontier;

  /// The station's own stuck-detector (tg-jwh) — sampled on the driver's timer
  /// seam, never on a subscription; it flares `station.wedged` through the
  /// emit-only transport, and the status surface reports [wedge].
  late final WedgeMonitor _wedge;

  Timer? _cooldownTimer;
  bool _started = false;
  bool _disposed = false;

  /// The station's current WEDGE signal — the single source of truth a watcher
  /// reads instead of re-deriving "is the grid stuck?" from raw sessions (RS-4).
  WedgeState get wedge => _wedge.state;

  /// Starts the bridge and runs the baseline scans (a restart that adopts a
  /// cooled-down session — D-5/F1 — plus the baseline unclaimed-frontier
  /// scan). Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    bridge.start();
    _scanCooldowns();
    _scanUnclaimedFrontier();
    // The wedge baseline. It arms its own poll timer only while STALLED (a
    // WEDGED station produces no flushes, so the alarm can never be
    // flush-driven; a flowing one arms no wall clock at all) — tg-jwh.
    _wedge.start();
  }

  /// Re-scans after a completed tree flush: a failure cursor written this tick
  /// may carry a new cooldown to arm (or a re-keyed step may clear one), and
  /// "the end of a reconciliation phase" is when the unclaimed frontier is
  /// re-computed. No persistent subscription — the owner's flush loop drives
  /// this.
  void afterFlush() {
    if (_disposed) return;
    _scanCooldowns();
    _scanUnclaimedFrontier();
    // A resumed grid clears the alarm on the very next flush.
    _wedge.poll();
  }

  /// Scans every owned session's cursor for the EARLIEST future cooldown and
  /// (re)arms the backoff Timer for it (D-5/F1).
  void _scanCooldowns() {
    if (_disposed) return;
    final now = _clock();
    DateTime? earliest;
    for (final session in bridge.latest.sessionsByWorkBead.values) {
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

  /// Computes + hands the STATION-WIDE unclaimed requirement set to the
  /// composed sink (D-B5 hook #1) — a no-op unless the policy, registry, AND
  /// sink are all wired.
  void _scanUnclaimedFrontier() {
    final onUnclaimed = _onUnclaimedFrontier;
    final rootCircuitFor = _rootCircuitFor;
    final registry = _registry;
    if (onUnclaimed == null || rootCircuitFor == null || registry == null) {
      return;
    }
    onUnclaimed(
      stationUnclaimedFrontier(
        bridge.latest,
        rootCircuitFor: rootCircuitFor,
        registry: registry,
        stationFacts: _stationFacts,
      ),
    );
  }

  /// A cooldown expired — re-emit a FRESH-instance copy of the latest snapshot
  /// (the bridge's `repush`) so `WorkList` re-runs the frontier predicate (now
  /// past the cooldown) and re-keys the eligible failed step (the backoff
  /// re-mount). The re-emit goes through the notifier (WorkList stays the sole
  /// dirtier); `root.markNeedsRebuild` is NEVER called.
  void _repokeCooldown() {
    _cooldownTimer = null;
    if (_disposed) return;
    bridge.repush();
  }

  /// Cancels the backoff Timer and disposes the bridge. Idempotent. Call AFTER
  /// the owning tree is unmounted (effects torn down) — the bridge outlives
  /// the tree, never the reverse.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _wedge.dispose();
    bridge.dispose();
  }
}
