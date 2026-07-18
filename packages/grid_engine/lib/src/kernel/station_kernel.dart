import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import '../bridge/station_join_bridge.dart';
import '../kernel/station_services.dart';
import '../circuit/capability_registry.dart';
import '../circuit/circuit_resolver.dart';
import '../circuit/unclaimed_frontier.dart';
import '../molecule/process_lease_vendor.dart';
import '../molecule/station_process_transport.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability_facts.dart';
import '../seeds/station_seed.dart';
import '../seeds/substation_scope.dart';
import 'session_resolver.dart';
import 'station_driver.dart';

/// The kernel: composes the running tree and drives it (ADR-0007 /
/// M4-P0-BUILD-ORDER Track E/F).
///
/// It assembles the ambient providers above the [Station] — the work-axis
/// [JoinedSnapshotNotifier] (from the [bridge]), the [StationServices] (the
/// provider/writer/stateSubstation the effects resolve), and the [SessionResolver]
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
  ///
  /// [rootCircuitFor] + [onUnclaimedFrontier] wire the D-B5 hook #1 (the
  /// unclaimed-frontier scan): [rootCircuitFor] is the SAME bead→circuit
  /// policy the composed [resolver] roots the live tree with (a composer
  /// passes the identical function to both — see `CircuitResolver`), and
  /// [onUnclaimedFrontier], when supplied, is called once per reconciliation
  /// phase (the baseline scan at [start] plus once per flush) with the
  /// CURRENT station-wide unclaimed requirement set. Both default to null —
  /// zero cost, and no behavior change, for a station composing no
  /// federation asset.
  ///
  /// [processLeaseVendor] is the molecule model's process-identity seam
  /// (`DESIGN-tg-pm6.md` §7, R3/R5; Decided item 5) — provided ambient
  /// beside [registry], the SAME kernel-tier trust level. Null (the default)
  /// composes the REAL production vendor over [stationServices]
  /// (`defaultProcessLeaseVendor`, tg-h4u: the chokepoint writer, the
  /// station transport spawner/dispatcher, `StationBeadWriter.metadataOf`,
  /// the station liveness seam) — the kernel-root provision, so
  /// `requireProcessLeaseVendor` resolves a real vendor on every
  /// kernel-rooted tree. Supplying one explicitly OVERRIDES it (e.g. a
  /// `SelfManagedProcessVendor` as the deliberately-chosen degraded mode —
  /// never substituted silently). A NON-kernel tree still refuses LOUD via
  /// `requireProcessLeaseVendor` when nothing mounts a vendor.
  StationKernel({
    required this.bridge,
    required StationServices stationServices,
    required SessionResolver resolver,
    required List<SubstationScope> substations,
    CapabilityRegistry? registry,
    ProcessLeaseVendor? processLeaseVendor,
    Seed Function(Seed root)? wrapRoot,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
    RootCircuitFor? rootCircuitFor,
    CapabilityFacts stationFacts = const CapabilityFacts(),
    void Function(List<UnclaimedRequirement>)? onUnclaimedFrontier,
  }) : _stationServices = stationServices,
       _resolver = resolver,
       _substations = substations,
       _registry = registry,
       _processLeaseVendor = processLeaseVendor,
       _wrapRoot = wrapRoot,
       _driver = StationDriver(
         bridge: bridge,
         clock: clock,
         scheduleTimer: scheduleTimer,
         rootCircuitFor: rootCircuitFor,
         registry: registry,
         stationFacts: stationFacts,
         onUnclaimedFrontier: onUnclaimedFrontier,
       );

  /// The join bridge feeding the work axis — the kernel owns its lifecycle
  /// (started in [start], disposed in [dispose]).
  final StationJoinBridge bridge;
  final StationServices _stationServices;
  final SessionResolver _resolver;
  final List<SubstationScope> _substations;

  /// The reentrant capability/circuit resolution seam (ADR-0008 D4) — provided
  /// as a stable ambient value the `CircuitScope` inflater resolves. Null when
  /// the resolver roots a non-reentrant subtree (a test fake that returns a
  /// plain leaf needs no registry).
  final CapabilityRegistry? _registry;

  /// The molecule model's ambient process-lease seam (`DESIGN-tg-pm6.md` §7,
  /// R3/R5) — provided at the SAME kernel-tier trust level as [_registry].
  /// Null defaults to the REAL vendor over `StationServices` at [start]
  /// (`defaultProcessLeaseVendor` — the tg-h4u kernel-root provision); an
  /// explicit vendor overrides it.
  final ProcessLeaseVendor? _processLeaseVendor;

  /// The composer's provider hook (ADR-0008 D-A, 2026-07-02): applied OUTERMOST
  /// around the kernel's own ambient stack, so an asset's `main()` mounts its
  /// station-default config values (`InheritedSeed<AgentConfig>`-style) as
  /// ancestors of everything — the kernel never knows what rides it (the
  /// opinion-free extension point; `Nest` chains multiple providers cleanly).
  final Seed Function(Seed root)? _wrapRoot;

  /// The off-tree work-axis machinery — the bridge lifecycle, the D-5/F1
  /// cooldown Timer + backoff re-poke, and the unclaimed-frontier scan —
  /// extracted to [StationDriver] (tg-yl8) so `runGrid`'s tree reuses it; the
  /// kernel delegates the same duties it always owned.
  final StationDriver _driver;

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
    // The driver starts the bridge (seeding the notifier's baseline BEFORE
    // WorkList subscribes below) and runs the baseline scans — the cooldown
    // arm for a restart that adopts a cooled-down session (D-5/F1) and the
    // baseline unclaimed-frontier scan (D-B5 hook #1). Both read only
    // bridge.latest, so running them before mount is value-identical.
    _driver.start();
    // Build the ambient-provider stack inside-out. Every provider is a plain
    // InheritedSeed: the root never rebuilds, and genesis's default identity
    // check declines to notify for a re-provided handle anyway (ADR-0008 D-6,
    // superseded 2026-07-02 — the StableInheritedSeed guard type is deleted).
    // The registry is wrapped only when present (a non-reentrant fake resolver
    // needs none). The `ServiceBundle` is NOT provided here — it is a
    // per-substation responsibility provided by each `SubstationScope` so two
    // substations get isolated source control (ADR-0008 D5).
    Seed root = Station(_substations);
    final registry = _registry;
    if (registry != null) {
      root = InheritedSeed<CapabilityRegistry>(value: registry, child: root);
    }
    // The molecule model's process-lease seam (R3/R5) — ALWAYS mounted at the
    // SAME kernel-tier trust level as the registry above: the composer's
    // explicit vendor when supplied, else the REAL production vendor over
    // StationServices (the tg-h4u kernel-root provision — so a molecule-mode
    // process step on a kernel-rooted tree always resolves a real vendor).
    final leaseVendor =
        _processLeaseVendor ?? defaultProcessLeaseVendor(_stationServices);
    root = InheritedSeed<ProcessLeaseVendor>(value: leaseVendor, child: root);
    root = InheritedSeed<SessionResolver>(value: _resolver, child: root);
    root = InheritedSeed<StationServices>(value: _stationServices, child: root);
    root = InheritedSeed<JoinedSnapshotNotifier>(
      value: bridge.notifier,
      child: root,
    );
    final wrap = _wrapRoot;
    if (wrap != null) root = wrap(root);
    _owner.mountRoot(root);
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      if (_disposed) return;
      _owner.flush();
      // Re-scan after each flush (the driver's cooldown + unclaimed-frontier
      // scans): a failure cursor written this tick may carry a new cooldown to
      // arm, and whatever this flush left unfulfillable is what a composed
      // claim asset sees next. No persistent subscription — the kernel already
      // owns this cycle.
      _driver.afterFlush();
    });
  }

  /// Tears down the tree (unmounting every effect → kill) and the driver
  /// (cancelling the backoff Timer, disposing the bridge). Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner.dispose();
    _driver.dispose();
  }
}
