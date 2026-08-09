import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';

import '../bridge/station_join_bridge.dart';
import '../kernel/station_services.dart';
import '../circuit/capability_registry.dart';
import '../circuit/circuit_resolver.dart';
import '../circuit/unclaimed_frontier.dart';
import '../diagnostics/tree_projector.dart';
import '../molecule/process_lease_vendor.dart';
import '../molecule/station_process_transport.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability_facts.dart';
import '../seeds/station_seed.dart';
import '../seeds/substation_scope.dart';
import '../seeds/provider.dart';
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
/// How long the kernel waits before re-attempting a flush pass that threw
/// (tg-60n). Coarse on purpose: the retry exists to un-strand a dirty set, not
/// to drive latency.
const Duration _kFlushRetryDelay = Duration(seconds: 1);

/// How many CONSECUTIVE failed flush passes the kernel re-arms before it stops
/// and lets the stall become a visible wedge (tg-60n).
const int _kMaxFlushRetries = 5;

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
    TreeProjector? treeProjector,
    Seed Function(Seed root)? wrapRoot,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? scheduleTimer,
    RootCircuitFor? rootCircuitFor,
    CapabilityFacts stationFacts = const CapabilityFacts(),
    void Function(List<UnclaimedRequirement>)? onUnclaimedFrontier,
    void Function(Object error, StackTrace stack)? onFlushError,
  }) : _stationServices = stationServices,
       _resolver = resolver,
       _substations = substations,
       _registry = registry,
       _processLeaseVendor = processLeaseVendor,
       _treeProjector = treeProjector,
       _wrapRoot = wrapRoot,
       _scheduleTimer = scheduleTimer ?? Timer.new,
       _onFlushError = onFlushError ?? _rethrowToZone,
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

  /// Optional post-flush diagnostics projection seam; null has no projection
  /// cost.
  final TreeProjector? _treeProjector;

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

  /// The flush-failure sink (tg-60n). Defaults to [_rethrowToZone] — the
  /// SAME escalation an unguarded throw already had, so nothing about how a
  /// failure is REPORTED changes by default; what changes is that the rest of
  /// the tick no longer dies with it.
  final void Function(Object error, StackTrace stack) _onFlushError;

  /// The retry clock for [_rearmAfterFailedFlush] — injectable so the re-arm is
  /// driven deterministically offline, exactly like the driver's backoff.
  final Timer Function(Duration, void Function()) _scheduleTimer;

  final TreeOwner _owner = TreeOwner();
  Branch? _root;
  bool _started = false;
  bool _disposed = false;
  bool _flushScheduled = false;

  /// Consecutive failed flush passes — reset by the first clean pass. Bounds
  /// [_rearmAfterFailedFlush] so a branch that throws every single time
  /// degrades into a visible wedge instead of a hot retry loop.
  int _consecutiveFlushFailures = 0;

  /// The pending failure re-arm, if any (cancelled on [dispose]).
  Timer? _flushRetry;

  static void _rethrowToZone(Object error, StackTrace stack) =>
      Zone.current.handleUncaughtError(error, stack);

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
    // superseded 2026-07-02 — the prior stable-inherited-seed guard is deleted).
    // The registry is wrapped only when present (a non-reentrant fake resolver
    // needs none). The `ServiceBundle` is NOT provided here — it is a
    // per-substation responsibility provided by each `SubstationScope` so two
    // substations get isolated source control (ADR-0008 D5).
    final registry = _registry;
    // The molecule model's process-lease seam (R3/R5) — ALWAYS mounted at the
    // SAME kernel-tier trust level as the registry above: the composer's
    // explicit vendor when supplied, else the REAL production vendor over
    // StationServices (the tg-h4u kernel-root provision — so a molecule-mode
    // process step on a kernel-rooted tree always resolves a real vendor).
    final leaseVendor =
        _processLeaseVendor ?? defaultProcessLeaseVendor(_stationServices);
    Seed root = ProviderScope(
      providers: <Provider<Object>>[
        Provider<JoinedSnapshotNotifier>.value(bridge.notifier),
        Provider<StationServices>.value(_stationServices),
        Provider<SessionResolver>.value(_resolver),
        Provider<ProcessLeaseVendor>.value(leaseVendor),
        if (registry != null) Provider<CapabilityRegistry>.value(registry),
      ],
      child: Station(_substations),
    );
    final wrap = _wrapRoot;
    if (wrap != null) root = wrap(root);
    _root = _owner.mountRoot(root);
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    scheduleMicrotask(_runFlushPass);
  }

  /// One flush pass, FAIL-CLOSED (tg-60n).
  ///
  /// `TreeOwner.flush()` has no internal catch (genesis_tree 0.2.0
  /// `tree_owner.dart:69-93`), so one throwing `branch.rebuild()` propagates
  /// straight out. Before this guard that killed the WHOLE remainder of the
  /// tick, and the two consequences were invisible and unbounded:
  ///
  /// 1. **`_driver.afterFlush()` never ran.** The driver's post-flush scans
  ///    include `WedgeMonitor.poll` — the station's ONLY stall alarm. A
  ///    non-stalled sample cancels the monitor's timer by design ("a healthy
  ///    grid arms no wall clock at all"), so a flush is its only remaining
  ///    heartbeat. Skipping it froze the wedge state at its last good sample:
  ///    a live arm reported `wedged: false, live: 0` while `/status` computed
  ///    6 live sessions from the SAME bridge, for 18.6 hours (receipt on
  ///    tg-60n, 2026-08-06). The alarm could not fire in the one scenario it
  ///    exists for.
  /// 2. **The dirty set could strand NON-EMPTY.** `TreeOwner.scheduleRebuildFor`
  ///    fires `onNeedsFlush` only on the empty→non-empty EDGE. A pass that
  ///    threw part-way leaves branches dirty, so every later
  ///    `markNeedsRebuild` sees a non-empty set and schedules NOTHING — the
  ///    tree freezes for the life of the process. That is why a bounce was the
  ///    only cure ever found: it is the one thing that yields a fresh owner
  ///    with an empty dirty set.
  ///
  /// The guard fixes both: the driver's scans run in a `finally`, and a failed
  /// pass re-arms so a stranded set cannot wedge the tree silently.
  void _runFlushPass() {
    _flushScheduled = false;
    if (_disposed) return;
    var failed = false;
    try {
      _owner.flush();
      _treeProjector?.afterFlush(_root!);
      _consecutiveFlushFailures = 0;
    } on Object catch (error, stack) {
      failed = true;
      _consecutiveFlushFailures++;
      _report(error, stack);
    } finally {
      // Re-scan after each flush (the driver's cooldown + unclaimed-frontier
      // scans): a failure cursor written this tick may carry a new cooldown to
      // arm, and whatever this flush left unfulfillable is what a composed
      // claim asset sees next. No persistent subscription — the kernel already
      // owns this cycle. It runs even when the pass THREW: a broken tick is
      // exactly when the stall alarm must keep sampling.
      if (!_disposed) {
        try {
          _driver.afterFlush();
        } on Object catch (error, stack) {
          _report(error, stack);
        }
      }
    }
    if (failed) _rearmAfterFailedFlush();
  }

  /// Re-arms a flush after a failed pass, so a dirty set stranded by the throw
  /// cannot silently freeze the tree (the edge-trigger trap above).
  ///
  /// BOUNDED on purpose: a branch that throws on every pass would otherwise
  /// spin. After [_kMaxFlushRetries] consecutive failures the kernel stops
  /// re-arming and lets the station ripen into a VISIBLE wedge — which it now
  /// can, because `afterFlush` keeps running. Loud and stuck beats silent and
  /// stuck; a hot loop is neither.
  void _rearmAfterFailedFlush() {
    if (_disposed || _flushScheduled) return;
    if (_consecutiveFlushFailures > _kMaxFlushRetries) return;
    _flushRetry?.cancel();
    _flushRetry = _scheduleTimer(_kFlushRetryDelay, () {
      _flushRetry = null;
      if (_disposed) return;
      _scheduleFlush();
    });
  }

  void _report(Object error, StackTrace stack) {
    try {
      _onFlushError(error, stack);
    } on Object {
      // A throwing sink must never break the reconcile — the same posture
      // every other engine flare site takes.
    }
  }

  /// Tears down the tree (unmounting every effect → kill) and the driver
  /// (cancelling the backoff Timer, disposing the bridge). Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _flushRetry?.cancel();
    _flushRetry = null;
    _owner.dispose();
    _treeProjector?.dispose();
    _driver.dispose();
  }
}
