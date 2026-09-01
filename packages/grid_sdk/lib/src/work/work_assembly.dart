import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../command/command_operation.dart';
import '../command/station_command_handler.dart';
import '../stores/stores.dart';
import '../trajectory/trajectory_config.dart';
import '../trajectory/trajectory_harness.dart';
import 'station_work.dart';

/// One substation's assembly identity — mirrors the `Substation` the author
/// mounts (same name / ONE root / prefix axes), because the OFF-tree machinery
/// (controllers, worktree roots) is built per store while the tree is built
/// per scope; the runner derives both from one config.
class SubstationWorkSpec {
  /// A substation named [name] at [root] whose store mints `<prefix>-…` ids
  /// ([prefix] defaults to [name] — the `tg` precedent). [head], when set,
  /// pins the branch per-bead worktrees are cut from (a live
  /// `registerRootCheckout` otherwise probes `origin/HEAD`).
  const SubstationWorkSpec({
    required this.name,
    required this.root,
    String? prefix,
    this.head,
  }) : _prefix = prefix;

  /// The project's name (tree identity + `metadata.rig` marker axis).
  final String name;

  /// The project's single absolute root.
  final String root;

  final String? _prefix;

  /// The assign-head override for live worktree provisioning.
  final String? head;

  /// The work store's issue-id prefix (ownership's primary axis).
  String get prefix => _prefix ?? name;
}

/// The runner-held OFF-tree work machinery `assembleStationWork` assembles — the
/// v3 successor to the deleted `StationSources`/`StationWiring`/
/// `TreeRunWiring` boot path (H3), re-shaped for `runGrid`: the tree no longer
/// rides a kernel-owned `TreeOwner`; it mounts inside the `runGrid`
/// composition ([StationWork]/[SubstationWork]) while THIS object owns
/// everything off-tree.
///
/// Lifecycle (the pinned ordering, ADR-0007 §4):
///
/// ```dart
/// final work = await assembleStationWork(...);
/// await work.start();                       // controllers → freshness →
///                                           // restart-reconcile → bridge
/// final grid = await runGrid(delegate,      // NOW the tree mounts + spawns
///     onFlushed: work.afterFlush,           // D-5 cooldown/unclaimed re-scan
///     orphanSweep: work.sweepOrphans);      // the teardown reap
/// // ... resident ...
/// await grid.teardown();                    // unmount → effects kill → SWEEP
/// await work.shutdown();                    // bridge + controllers down
/// ```
class StationWorkRuntime {
  StationWorkRuntime._({
    required this.wiring,
    required this.commands,
    required this.git,
    required this.trajectory,
    required this.stateSubstation,
    required this.readPathName,
    required StationDriver driver,
    required RestartReconciler restart,
    required RuntimeProvider provider,
    required void Function(String message) onOrphan,
    required void Function(String message) onRefusal,
    required Future<void> Function() sourcesStart,
    required Future<void> Function() sourcesShutdown,
    required Future<void> Function() freshnessBarrier,
    required Map<String, GraphSyncStats> Function() syncStats,
    required Map<String, MemberFreshness> Function() workFreshness,
  }) : _driver = driver,
       _restart = restart,
       _provider = provider,
       _onOrphan = onOrphan,
       _onRefusal = onRefusal,
       _sourcesStart = sourcesStart,
       _sourcesShutdown = sourcesShutdown,
       _freshnessBarrier = freshnessBarrier,
       _syncStats = syncStats,
       _workFreshness = workFreshness;

  /// The ambient VALUES the tree's [StationWork] provides.
  final StationWorkWiring wiring;

  /// Operator commands executed by this resident station.
  final GridCommandHandler commands;

  /// The worktree git service (dry-inert or live) — the runner threads it into
  /// its substations' `GitGridAssets` so the tree's source control and THIS
  /// runtime's restart sweep share one service.
  final StationGitService git;

  /// The trajectory harness (stage1-wiring §1.1) — the fenced service's
  /// station-side owner, built beside the state writer. Always present:
  /// disabled or degraded it is a counting no-op, and a runner reads its
  /// [TrajectoryHarness.status] for the banner/`/status` block. Lifecycle is
  /// THIS runtime's: up inside [start] (after the sources), down inside
  /// [shutdown] (before them) — never blocking either.
  final TrajectoryHarness trajectory;

  /// The owned state partition sessions are minted into — re-sourced from the
  /// grid's own state store identity (its `dolt_database`), never a flag
  /// (Q5a).
  final String stateSubstation;

  /// The controllers' read-path provenance (`sql` / `cli` per store) — banner
  /// material.
  final String readPathName;

  final StationDriver _driver;
  final RestartReconciler _restart;
  final RuntimeProvider _provider;
  final void Function(String message) _onOrphan;

  /// The LOUD sink a dropped chokepoint write reports through (the same one the
  /// [StationBeadWriter] refuses on) — a dropped zombie reap (tg-szb) is never
  /// silent.
  final void Function(String message) _onRefusal;
  final Future<void> Function() _sourcesStart;
  final Future<void> Function() _sourcesShutdown;
  final Future<void> Function() _freshnessBarrier;
  final Map<String, GraphSyncStats> Function() _syncStats;
  final Map<String, MemberFreshness> Function() _workFreshness;

  /// Per-store sync-loop counters (tg-zd4v LOUD, the `/status` half): every
  /// work store's + the state store's (`state`) [GraphSyncStats] — per-origin
  /// signal counts, refresh count, last refresh/reaction latency, in-flight
  /// state. Today's `/status` says WHEN the last sync happened; this says WHY
  /// syncs are or are not happening, without attaching to the VM service.
  Map<String, GraphSyncStats> get syncStats => _syncStats();

  /// The federation's per-member freshness vector (D-F3) — capture age +
  /// ready-staleness per work store, never averaged into one scalar.
  Map<String, MemberFreshness> get workFreshness => _workFreshness();
  bool _started = false;
  bool _shutdown = false;
  RestartReport? _lastRestartReport;
  TeardownReplayReport? _lastTeardownReplay;

  /// The last boot's TEARDOWN REPLAY report (tg-tlea) — null before [start].
  /// Which sessions were caught mid-teardown and had their positive-terminal
  /// tail re-run, and which were left alone because a human holds them.
  TeardownReplayReport? get lastTeardownReplay => _lastTeardownReplay;

  /// The last boot's restart-reconcile report — null before [start]. What the
  /// pass skipped / killed / adopted, and which ZOMBIE `running` markers it
  /// reaped. A plain derived VALUE a runner's banner or status view can read.
  RestartReport? get lastRestartReport => _lastRestartReport;

  /// The off-tree restart reconciler this runtime owns — exposed so a composer
  /// (and the assembly's own test) can assert the pass is fully armed, notably
  /// that the ONE bd chokepoint reached it ([RestartReconciler.hasChokepoint]).
  /// A capability query on an off-tree machine, not an accessor over reactive
  /// state (D-H rule 2).
  RestartReconciler get restart => _restart;

  /// The producer-side latest join — status counts read THIS (what the bridge
  /// last pushed), never the notifier's reactive state (D-H rule 2).
  JoinedSnapshot get latest => _driver.bridge.latest;

  /// The station's WEDGE signal (tg-jwh) — the single source of truth a runner
  /// hands to its status view, so a watcher never re-derives "is the grid
  /// stuck?" from raw sessions. A plain derived VALUE, read fresh per request.
  WedgeState get wedge => _driver.wedge;

  /// Samples [snapshot] through the owned wedge latch for one status request.
  WedgeState wedgeFor(JoinedSnapshot snapshot) => _driver.wedgeFor(snapshot);

  /// Brings the off-tree machinery up in the pinned ordering (ADR-0007 §4):
  /// controllers start → the freshness barrier completes → the restart
  /// reconciler reconciles survivors (respawn-or-skip, BEFORE any tree could
  /// blindly respawn) → the bridge starts following. Call BEFORE `runGrid`
  /// mounts the armed tree. Idempotent.
  Future<void> start() async {
    if (_started || _shutdown) return;
    _started = true;
    await _sourcesStart();
    // Trajectory up — §1.2 step 2 of stage1-wiring: connect → belt verify →
    // epoch claim → tick, all inside the harness, which never throws and
    // never fails the boot (the trajectory can degrade; work cannot, §3).
    // The catch is the binding rule's last line of defense, not a live path.
    try {
      await trajectory.start();
    } on Object catch (error) {
      _onRefusal(
        'trajectory start failed (station booting legacy-only) — '
        '$error',
      );
    }
    await _freshnessBarrier();
    final report = await _restart.reconcile();
    _lastRestartReport = report;
    // A DROPPED zombie reap degrades to the pre-reaper behavior (the frontier
    // still re-mounts the node), so it is never fatal — but an operator MUST
    // know the cursor still reads `running` over a corpse, because that lie
    // blinds the wedge monitor and vetoes `grid rework`. LOUD or GONE
    // (ADR-0008 D3).
    for (final line in droppedReapReports(report)) {
      _onRefusal(line);
    }
    for (final line in droppedWorkTerminalSettlementReports(report)) {
      _onRefusal(line);
    }
    // The TEARDOWN REPLAY (tg-tlea) — the session-driven pass beside the
    // worktree-driven reconcile above. It runs BEFORE the driver starts so a
    // session caught mid-teardown is finished off before the tree could mount
    // anything against it, and it is non-fatal by construction: a replay that
    // throws must never stop a station from booting.
    try {
      _lastTeardownReplay = await _restart.replayTeardownTail();
    } on Object catch (error) {
      _onRefusal('teardown replay failed (station still booting) — $error');
    }
    _driver.start();
  }

  /// The `runGrid(onFlushed:)` hook — the driver's post-flush cooldown +
  /// unclaimed-frontier re-scans (D-5/F1).
  void afterFlush() => _driver.afterFlush();

  /// The `runGrid(orphanSweep:)` hook — the teardown-time ORPHAN SWEEP.
  /// `GridHandle.teardown()` runs it AFTER the unmount, so the station is
  /// reconciled against zero-expected: the transport's still-held sessions are
  /// stopped (the unmount's kill chain is fire-and-forget) and this station's
  /// OWN non-terminal session beads' live process groups are terminated. Scoped
  /// to the OWNED state partition and never broad (ADR-0006 coexistence); LOUD
  /// on every reap.
  ///
  /// It is the teardown twin of the boot [RestartReconciler.reconcile] [start]
  /// runs — the SAME reconciler, the same fence, the same guarded kill.
  Future<OrphanSweepReport> sweepOrphans() => _restart.sweepOrphans(
    transport: _provider,
    sessionPrefix: '$stateSubstation-',
    onOrphan: _onOrphan,
  );

  /// Tears the off-tree machinery down: the driver (backoff Timer + bridge),
  /// then the controllers. Call AFTER `grid.teardown()` unmounted the tree
  /// (effects torn down) — the bridge outlives the tree, never the reverse.
  /// Idempotent.
  Future<void> shutdown() async {
    if (_shutdown) return;
    _shutdown = true;
    _driver.dispose();
    // Trajectory down BEFORE the stores it reads (§1.2 shutdown order) —
    // guarded so it NEVER blocks sources shutdown (r2, major 9): the harness
    // settles every step internally (queue drain → fixpoint → boundary
    // commit → dispose) and never throws; the catch is insurance, so
    // _sourcesShutdown() below is unconditionally reached.
    try {
      await trajectory.shutdown();
    } on Object catch (error) {
      _onRefusal(
        'trajectory shutdown failed (sources still stopping) — '
        '$error',
      );
    }
    await _sourcesShutdown();
  }
}

/// The LOUD lines a restart pass's DROPPED zombie reaps produce.
///
/// A reap write that was dropped — a transient bd blip, an ownership refusal, or
/// no chokepoint wired at all — leaves that cursor node still claiming `running`
/// over a dead process. That is never fatal (the frontier still re-mounts it),
/// but it is the exact lie that blinds `sampleWedge` and vetoes `grid rework`,
/// so it is reported rather than swallowed. Pure, so the message contract is
/// pinned by a test instead of by scraping a log.
List<String> droppedReapReports(RestartReport report) => [
  for (final r in report.reaped)
    if (!r.isWritten)
      'grid: restart reap of ${r.sessionId}/${r.nodePath} was DROPPED '
          '(${r.failure}) — that cursor node still reads `running` over a dead '
          'pid ${r.pid ?? '<unrecorded>'}',
];

List<String> droppedWorkTerminalSettlementReports(RestartReport report) => [
  for (final settlement in report.workTerminalSettlements)
    if (settlement.failure case final failure?)
      'grid: restart work-terminal settlement of '
          '${settlement.sessionId}/${settlement.workBeadId} was DROPPED '
          '($failure) — terminal reason ${settlement.terminalReason}',
];

bool _sameCanonicalRoot(String left, String right) =>
    p.equals(p.canonicalize(left), p.canonicalize(right));

/// Appends [line] to the owned lifecycle bead identified by [beadId].
typedef WorkNoteAppender = Future<void> Function(String beadId, String line);

/// Builds a station capability registry over its owned [appendWorkNote] seam.
typedef CapabilityRegistryBuilder =
    CapabilityRegistry Function(WorkNoteAppender appendWorkNote);

/// Assembles the station's off-tree work machinery over REAL stores at their
/// roots — the v3 replacement for the deleted `buildControllers` +
/// `buildLiveWiring` + `composeStation` assembly (H3), consumed by every
/// runner (`space up`) so a station author never imports the private engine
/// (ADR-0008 D2).
///
/// Store binding is EXACT-at-root, fail-closed: each substation's `.beads/`
/// must exist at its exact root and the grid state store's at
/// `<grid.root>/.grid/.beads/` — absence is a LOUD [StoreRefusal] (seed via
/// the documented substation-init process), NEVER a walk-up that could bind an
/// ancestor store (for the state store that walk-up would land sessions in the
/// dual-role repo's WORK store — the A37 violation).
///
/// [dryRun] selects the inert seams as ONE posture (the old runner's shape):
/// a recording no-op bd chokepoint (sessions mint end-to-end, no store
/// touched), a would-spawn transport (no process), an inert git service (no
/// `git` executed, provisioning materializes nothing). Live wires
/// `ProcessBdRunner` over the state store, `SubprocessProvider`, and the real
/// `git`/`gh` service. The per-seam overrides are TEST seams.
/// The default sync FLOOR interval (tg-zd4v): the bounded worst-case refresh
/// age on the SQL read path, where the working-set probe is edge-triggered
/// and a quiet store would otherwise never re-capture. Coarse relative to the
/// 1s probe on purpose — the floor is correctness, not latency — and
/// threadable so a resident with many work stores can widen it.
const kDefaultSyncFloorInterval = Duration(seconds: 45);

Future<StationWorkRuntime> assembleStationWork({
  required GridStateStore stateStore,
  required List<SubstationWorkSpec> substations,
  required SessionResolver resolver,
  required bool dryRun,
  CapabilityRegistry? registry,
  CapabilityRegistryBuilder? registryBuilder,
  int maxConcurrentWork = kDefaultMaxConcurrentWork,
  bool preferSql = true,
  RuntimeProvider? providerOverride,
  StationGitService? gitOverride,
  BdCliService? stateBdOverride,
  Map<String, BdCliService> workBdOverrides = const {},
  ProcessGroupController? groupsOverride,
  void Function(String message)? onRefusal,
  void Function(String message)? onOrphan,
  void Function(String message)? onUnresolvedExternalDep,
  ExplorationTransport? transport,
  Duration wedgeThreshold = kDefaultWedgeThreshold,
  Duration wedgePollInterval = kDefaultWedgePollInterval,
  Duration syncFloorInterval = kDefaultSyncFloorInterval,
  TrajectoryConfig trajectoryConfig = const TrajectoryConfig(),
  TrajectoryHarness? trajectoryOverride,
}) async {
  if (registry != null && registryBuilder != null) {
    throw ArgumentError(
      'assembleStationWork: registry and registryBuilder are mutually exclusive.',
    );
  }
  if (substations.isEmpty) {
    throw ArgumentError(
      'assembleStationWork: at least one substation is required — there is no '
      'default substation (v3 §0).',
    );
  }
  final knownWorkStores = substations.map((spec) => spec.name).toSet();
  final unknownOverrides = workBdOverrides.keys
      .where((name) => !knownWorkStores.contains(name))
      .toList(growable: false);
  if (unknownOverrides.isNotEmpty) {
    throw ArgumentError(
      'assembleStationWork: work bd overrides name unknown substations: '
      '${unknownOverrides.join(', ')}.',
    );
  }
  // Disjointness across BOTH identity axes (review finding, tg-yl8):
  // ownership matches name OR prefix (`BeadOwnershipPredicate`), so any token
  // shared between two substations — name/name, prefix/prefix, or one's name
  // colliding with the other's prefix — would mount the SAME bead under BOTH
  // WorkLists (the double-provision race that wedges a `grid/<beadId>` branch,
  // tg-e0p). Refuse LOUD at assembly, before any scope mounts.
  final identityOwner = <String, String>{};
  for (final s in substations) {
    for (final token in {s.name, s.prefix}) {
      final prior = identityOwner[token];
      if (prior != null) {
        throw ArgumentError(
          'assembleStationWork: substations "$prior" and "${s.name}" share the '
          'identity token "$token" (a name or prefix) — ownership matches '
          'EITHER axis, so a bead carrying it would mount under BOTH '
          'WorkLists. Give every substation disjoint {name, prefix} sets.',
        );
      }
      identityOwner[token] = s.name;
    }
  }

  // --- the stores, exact-at-root (LOUD refusal, no walk-up). StoreLocator
  // performs the substation checks; the state store is checked here because
  // BeadsWorkspace.discover WALKS UP — without the exact check first, a
  // missing `<grid.root>/.grid/.beads` would silently bind the dual-role
  // repo's work store and sessions would be minted into the work source (A37).
  final locator = StoreLocator();
  final workspacesByName = <String, BeadsWorkspace>{};
  for (final s in substations) {
    locator.locateWorkStore(
      root: p.canonicalize(s.root),
      substationName: s.name,
    );
    final ws = BeadsWorkspace.discover(start: s.root);
    if (ws == null || !_sameCanonicalRoot(ws.root, s.root)) {
      throw StoreRefusal(
        'assembleStationWork: substation "${s.name}": could not parse the work '
        'store at ${s.root}/.beads (resolved: ${ws?.root ?? 'nothing'}).',
      );
    }
    workspacesByName[s.name] = ws;
  }
  if (!File('${stateStore.beadsDir}/metadata.json').existsSync()) {
    throw StoreRefusal(
      'assembleStationWork: no grid state store at ${stateStore.beadsDir} — the '
      'grid\'s own store lives under <grid.root>/.grid/ (Q5a). Seed it with '
      'the substation-init process (docs/SUBSTATION-INIT.md) before arming.',
    );
  }
  final stateWs = BeadsWorkspace.discover(start: stateStore.runtimeDir);
  if (stateWs == null ||
      !_sameCanonicalRoot(stateWs.root, stateStore.runtimeDir)) {
    throw StoreRefusal(
      'assembleStationWork: could not parse the grid state store at '
      '${stateStore.beadsDir} (resolved: ${stateWs?.root ?? 'nothing'}).',
    );
  }
  // The owned state partition — the grid identity's own store names it (its
  // dolt database == the prefix its session ids mint under), never a flag.
  final stateSubstation = stateWs.database;
  if (stateSubstation == null || stateSubstation.isEmpty) {
    throw StoreRefusal(
      'assembleStationWork: the grid state store at ${stateStore.beadsDir} names '
      'no dolt_database in metadata.json — cannot derive the owned state '
      'partition (re-seed the store; see docs/SUBSTATION-INIT.md).',
    );
  }

  // --- the controllers (one per work store + the state store).
  final bundles = <String, GridRuntimeBundle>{};
  for (final entry in workspacesByName.entries) {
    final storeName = entry.key;
    bundles[entry.key] = await GridRuntimeFactory.build(
      workspace: entry.value,
      preferSql: preferSql,
      syncFloorInterval: syncFloorInterval,
      lifecycleTypes: {...IssueType.coreTypes, ...GridIssueTypes.all},
      onDirtySourceClosed: (source) => transport?.flare(
        'sync.dirtySignalsClosed',
        {'substation': storeName, 'source': source},
      ),
    );
  }
  final stateBundle = await GridRuntimeFactory.build(
    workspace: stateWs,
    preferSql: preferSql,
    syncFloorInterval: syncFloorInterval,
    lifecycleTypes: {...IssueType.coreTypes, ...GridIssueTypes.all},
    onDirtySourceClosed: (source) => transport?.flare(
      'sync.dirtySignalsClosed',
      {'substation': 'state', 'source': source},
    ),
  );
  final readPathName = [
    for (final e in bundles.entries) '${e.key}=${e.value.readPath.name}',
    'state=${stateBundle.readPath.name}',
  ].join(', ');

  // ONE sink for BOTH cross-store edge sources — the union's dependency rows
  // and the join's state-owned link beads report through the same LOUD channel.
  final unresolvedSink =
      onUnresolvedExternalDep ?? (String m) => stdout.writeln(m);

  final work = FederatedSnapshotSource(
    {
      for (final e in bundles.entries)
        e.key: _RuntimeSnapshotSource(e.value.runtime),
    },
    onUnresolvedExternalDep: unresolvedSink,
    // Ready-staleness by AGE (tg-zd4v face 2): a small multiple of the floor,
    // so a healthy member (re-capturing every floor tick) never trips it and
    // a genuinely quiet member stops minting ready ids instead of serving a
    // frozen frontier into a stale mint.
    readyStaleAge: syncFloorInterval * 3,
    // Rising-edge staleness flares ride the SAME emit-only transport as every
    // other engine LOUD signal (ADR-0008 D9 / ADR-0012 D2's armed reporter).
    onFlare: (name, data) => transport?.flare(name, data),
  );
  final SnapshotSource stateSource = _RuntimeSnapshotSource(
    stateBundle.runtime,
  );

  // --- THE single ownership allow-set: every substation's BOTH identity axes
  // (name = the `metadata.rig` marker, prefix = the issue-id shape) + the
  // grid's own state partition, so the chokepoint owns the session beads it
  // mints (A32/A36) whichever axis a bead presents.
  final allowSet = Set<String>.unmodifiable(<String>{
    for (final s in substations) ...{s.name, s.prefix},
    stateSubstation,
  });

  // --- the bd write chokepoint: dry-run → a recording no-op runner; live →
  // the real ProcessBdRunner over the grid's OWN state store. The chokepoint
  // re-checks ownership fail-closed either way.
  final bd =
      stateBdOverride ??
      (dryRun
          ? BdCliService(NoOpBdRunner())
          : BdCliService(ProcessBdRunner(workspaceRoot: stateWs.root)));
  final refusalSink = onRefusal ?? (String m) => stdout.writeln(m);
  final writer = StationBeadWriter(
    bd: bd,
    reader: stateBundle.probeReader,
    ownership: BeadOwnershipPredicate(allowSet),
    onRefusal: refusalSink,
    // C8a (cut-wiring): the STATE writer's flares were null-sunk — the work
    // writers below wired `onFlare` and this one did not, so `session.minted`,
    // `gate.autoClosed`, and `session.workTerminal` never reached the
    // transport for the partition that mints every session bead. That is
    // exactly the evidence the dual-read gates read.
    onFlare: transport?.flare,
  );

  // --- the runtime provider (ONE dry/live posture, per-seam override = a
  // test). Built HERE rather than with the other transports below because the
  // trajectory harness takes its `lastActivity` poll — liveness surface (b) of
  // stage1-wiring §2.3 — and the constructor itself starts nothing.
  final provider =
      providerOverride ?? (dryRun ? DryRunProvider() : SubprocessProvider());

  // --- the trajectory harness (stage1-wiring §1.1), built beside the state
  // writer — the one place that knows everything the fenced service needs:
  // the grid home, the state partition, the seat allow-set, and the flare
  // transport. Dry-run forces `disabled` (§1.3): a dry arm must not claim an
  // epoch or write anything — same physics as the recording no-op bd.
  // [trajectoryOverride] is a TEST seam, like every other per-seam override.
  final trajectory =
      trajectoryOverride ??
      await TrajectoryHarness.build(
        config: dryRun ? trajectoryConfig.asDisabled : trajectoryConfig,
        gridHome: stateStore.gridRoot,
        station: stateSubstation,
        seatPrefixes: allowSet,
        onFlare: transport?.flare,
        // The tick's liveness detector polls the provider (§2.4 obligation
        // 3); the worktree `.grid` mtime scan is the other surface and needs
        // nothing wired — it reads the paths P6 already carries.
        lastActivity: provider.lastActivity,
        // §1.1's runtime-event subscriber (harness-internal, over
        // `provider.events`): the observation surface for
        // `attempt.process.started`/`.exited` (§2.3 rows 2–3). The harness
        // subscribes only once LIVE, so a dry arm (disabled) never listens.
        runtimeEvents: provider.events,
      );
  // The harness's ONE derivation layer (stage1-wiring §2), threaded from here
  // to every observation site the design names: ambient over the work subtree
  // via `StationWorkWiring.trajectory`, and by constructor into the four
  // OFF-TREE collaborators built below (the git service, the lease vendor, the
  // command handler, the restart reconciler) — they are built beside the
  // harness rather than mounted under it, so an ambient value would never
  // reach them. One recorder, one queue, one appender: the sole-appender
  // invariant is threading, not convention.
  final recorder = trajectory.recorder;
  // THE POSTURE, READ ONCE (r13). `off` is the DEFAULT and the rollback: the
  // dual read is not merely inert then, it is UNWIRED — no observer reaches
  // the bridge or the reconciler, so the composition below is the pre-cut
  // composition, not a gated version of the new one.
  final dualReadArmed = trajectoryConfig.dualRead != DualReadMode.off;
  // THE SESSION-AXIS DUAL READ (cut-wiring C2/C3) — ONE accounting per boot,
  // shared by the join bridge's comparator pass and the restart reconciler's,
  // because the durable round summary must not report two different truths for
  // one boot, and because the OVERLAY DISENGAGE LATCH lives on it: a mirror
  // that missed an append must stop being served by BOTH readers at once.
  // Under `observe` nothing here changes a decision: the comparator
  // classifies, flares, and writes evidence. `primary` (C3) serves the
  // certified overlay from the same functions.
  final dualReadAccounting = dualReadArmed ? DualReadAccounting() : null;
  // THE STEP-AXIS DUAL READ (cut-wiring C4) — the same accounting object, so
  // one boot owes one durable round summary carrying both axes, and so the
  // OVERLAY DISENGAGE LATCH covers both: a boot whose P1 mirror missed an
  // append must stop serving the step axis too.
  final stepDualRead = dualReadArmed
      ? DualReadStepObserver(
          mode: trajectoryConfig.dualRead,
          accounting: dualReadAccounting,
          onFlare: transport?.flare,
        )
      : null;
  final dualRead = !dualReadArmed
      ? null
      : DualReadSessionObserver(
          mode: trajectoryConfig.dualRead,
          accounting: dualReadAccounting,
          // The harness's answer for one attempt — the heal must not race a terminal
          // record that is still queued (r8 — V2-B1).
          appendQueuedFor: trajectory.hasQueuedAppendFor,
          // The heal's guard pre-check + append live on the harness's serialized
          // lane; the bridge decides WHETHER, the harness decides ADMISSIBLE.
          healer: trajectory.requestTerminalReconcile,
          onFlare: transport?.flare,
          // §0.4's durable evidence: one `attempt.note` per session terminal plus a
          // boot-final note at the clean-down fixpoint, so bounces stop resetting
          // what the wave-1 gates read.
          onRoundSummary: (sessionId, body) => recorder
              .dualReadRoundSummaryNoted(sessionId: sessionId, body: body),
          // BOTH axes ride ONE note (C4): the summary reports what the STEP axis
          // actually did, read at emit time off the step observer — the same
          // served-fact discipline `overlay_engaged` has, for the same reason (a
          // `mode: primary` boot that disengaged certifies nothing).
          stepAxisEngaged: () => stepDualRead!.stepAxisEngaged,
          // THE APPEND SIDE OF THE SOAK GATE (C3): "zero drops" is not a fact any
          // comparator can observe — a dropped append leaves a hole in the fold
          // shaped exactly like a session that never happened — so the harness's own
          // counters ride the same durable note, in the same round.
          appendStats: () {
            final status = trajectory.status;
            return (
              appended: status.appended,
              deduped: status.deduped,
              dropped: status.dropped,
              suppressed: status.suppressed,
              refusedTestimony: status.refusedTestimony,
              queueDepth: status.queueDepth,
            );
          },
        );
  final workCommandStores = <String, WorkCommandStore>{};
  for (final spec in substations) {
    final workBd =
        workBdOverrides[spec.name] ??
        BdCliService(
          dryRun
              ? const NoOpBdRunner()
              : ProcessBdRunner(
                  workspaceRoot: workspacesByName[spec.name]!.root,
                ),
        );
    final binding = WorkCommandStore(
      source: _RuntimeSnapshotSource(bundles[spec.name]!.runtime),
      refresh: bundles[spec.name]!.runtime.requery,
      writer: StationBeadWriter(
        bd: workBd,
        reader: bundles[spec.name]!.probeReader,
        ownership: BeadOwnershipPredicate({spec.name, spec.prefix}),
        onRefusal: refusalSink,
        onFlare: transport?.flare,
      ),
    );
    workCommandStores[spec.name] = binding;
    workCommandStores[spec.prefix] = binding;
  }
  final writersByOwnedPrefix = <String, StationBeadWriter>{
    stateSubstation: writer,
    for (final entry in workCommandStores.entries)
      entry.key: entry.value.writer,
  };
  final resolvedRegistry =
      registry ??
      registryBuilder?.call((beadId, line) {
        final ownedPrefix = BeadOwnershipPredicate.ownedPrefixOf(
          beadId,
          writersByOwnedPrefix.keys,
        );
        return (writersByOwnedPrefix[ownedPrefix] ?? writer).update(
          beadId,
          metadata: const {},
          appendNotes: line,
        );
      });
  final commands = StationCommandHandler(
    stateSource: stateSource,
    refreshState: stateBundle.runtime.requery,
    stateWriter: writer,
    stateOwnership: BeadOwnershipPredicate(allowSet),
    workStoresByIdentity: workCommandStores,
    // `grid rework`'s re-key is one of `attempt.round.retired`'s two
    // observation sites (stage1-wiring §2.3).
    recorder: recorder,
    // CONSUMER 3 of the step dual read (C4): the park check has no
    // SessionProjection to carry a `trajCursor`, so its posture arrives by
    // constructor — the same three inputs the bridge derives engagement from.
    // UNWIRED at `off` (r13): the handler never reaches the mirror at all.
    stepSnapshot: dualReadArmed ? () => trajectory.stepCursors : null,
    dualReadMode: trajectoryConfig.dualRead,
    dualReadAccounting: dualReadAccounting,
  );

  // --- the transports (ONE dry/live posture, per-seam overrides = tests).
  // The provider itself is built above, beside the trajectory harness that
  // polls it.
  final git =
      gitOverride ??
      (dryRun
          ? buildDryStationGitService()
          : StationGitService(
              runner: SystemGitRunner(),
              prOpener: GhPrOpener(ghRunner),
              // `worktree.provisioned` is captured INSIDE provisionWorktree
              // (stage1-wiring §2.3, r2 blocker 3) — the only place that holds
              // `preexisting`, the branch, and the base sha at one instant.
              recorder: recorder,
            ));

  // --- the registered roots. Dry-run registers nothing (the inert service
  // provisions nothing) but the restart sweep still runs over the REAL root
  // path — no sentinel (v3 kills those). Live probes/pins the head.
  final rootsByName = <String, RootCheckout>{};
  for (final s in substations) {
    if (dryRun) {
      rootsByName[s.name] = RootCheckout(
        path: s.root,
        defaultBranch: 'main',
        substation: s.name,
      );
      continue;
    }
    try {
      rootsByName[s.name] = await git.registerRootCheckout(
        path: s.root,
        substation: s.name,
        head: s.head,
      );
    } on Object catch (e) {
      throw StoreRefusal(
        'assembleStationWork: could not register root "${s.name}"="${s.root}": '
        '$e',
      );
    }
  }
  final workRoot = rootsByName[substations.first.name]!;
  final groups = groupsOverride ?? const SystemProcessGroupController();
  final orphanSink = onOrphan ?? (String m) => stdout.writeln(m);

  Future<void> freshnessBarrier() async {
    await Future.wait(<Future<void>>[
      for (final b in bundles.values) b.runtime.requery(),
      stateBundle.runtime.requery(),
    ]);
  }

  final services = StationServices(
    provider: provider,
    writer: writer,
    stateSubstation: stateSubstation,
    maxConcurrentWork: maxConcurrentWork,
    // THE COMPLETION FENCE. A detached one-shot agent's vanish is reported as an
    // INFERRED clean exit — a murder and a completion look identical on the wire.
    // The engine advances the circuit on such an exit only for a capability that
    // DECLARED `CompletionContract.committedWorkspace` (the coding agent), and
    // only when THIS probe proves its workspace holds no uncommitted work OUTSIDE
    // the grid's own runtime dir. Every other one-shot (a critic, a `specify` —
    // which finish by writing an uncommitted artifact) is untouched. Dry-run gets
    // the inert git service (its no-op runner returns empty output ⇒ every probe
    // `clear`), so a dry run is unchanged.
    workSignal: stationWorkSignal(git),
  );

  // ONE production vendor for BOTH consumers (tg-eli phase 1: reuse, never
  // duplicate): the tree's molecule allocations (`StationWorkWiring`) and the
  // restart reconciler's molecule lease sweep resolve the SAME vendor over the
  // SAME services — so the breadcrumb a mount wrote is the breadcrumb the
  // sweep interprets.
  final leaseVendor = defaultProcessLeaseVendor(services, recorder: recorder);

  final restart = RestartReconciler(
    listWorktrees: git.listBeadWorktrees,
    reapWorktree: git.reap,
    workRoots: List<RootCheckout>.unmodifiable(rootsByName.values),
    groups: groups,
    // The ONE bd chokepoint — the zombie-running reap re-mounts a dead
    // generation's corpse through it, on the_grid's OWN session bead, BEFORE the
    // tree mounts. Optional on the ctor (a sibling repo's guardrails omit it),
    // so `restart.hasChokepoint` is what proves it actually reached here.
    writer: writer,
    freshnessBarrier: freshnessBarrier,
    stateSnapshot: () => stateSource.current ?? _emptyGraphSnapshot(),
    workSnapshot: () => work.current ?? _emptyGraphSnapshot(),
    // The MOLECULE lease sweep (tg-eli phase 1): the vendor is the only
    // grid.lease.* touchpoint (the reconciler stays lease-schema-ignorant);
    // `restart.hasLeaseSweep` proves it reached here. Its KILL GATE is NOT
    // the vendor's adopt-liveness (which stays at the never-adopt default
    // below): the reconciler binds it to its own real `groups` controller at
    // call time, so a crashed molecule station's live orphan groups ARE
    // reaped on reboot — flat-path parity. Until the D4 all-or-nothing adopt
    // wire arms, a live daemon is killed like a job (nothing would re-adopt
    // it).
    leaseVendor: leaseVendor,
    onOrphan: orphanSink,
    // The INFERRED half of `attempt.terminal(settled)` (stage1-wiring §2.3):
    // this pass settles a prior boot's sessions from evidence on disk. It also
    // carries C2's teardown-replay OBSERVER APPEND — the reconstructed close
    // that keeps a replayed teardown from leaving a permanently open head.
    recorder: recorder,
    // The dual read's reconciler half (cut-wiring C2): the same identity rule
    // and the same counters, plus the `incumbentAdjudication` class that only
    // `_projectOwnedSessions`' order-dependent winner can produce. UNWIRED at
    // `off` (r13) — the pass never reaches the mirror, so it is the pre-cut
    // pass, teardown-replay observer append included.
    headSnapshot: dualReadArmed ? () => trajectory.sessionHeads : null,
    dualReadAccounting: dualReadAccounting,
    // C3: the reconciler serves the SAME overlay under the SAME posture — a
    // disposition must not depend on which pass asked for it.
    dualReadMode: trajectoryConfig.dualRead,
    onFlare: transport?.flare,
    // Adopt-across-restart (ADR-0009 D4) stays UNARMED — both halves at their
    // never-adopt defaults; arming is a deliberate later wire, all-or-nothing.
  );

  final bridge = StationJoinBridge(
    work: work,
    state: stateSource,
    onUnresolvedCrossLink: unresolvedSink,
    // The DUAL READ's third input (cut-wiring §0.2/§0.3): a PRE-FETCHED,
    // immutable P1 mirror read — `_join` is pure and synchronous, and a P1 SQL
    // read is async, so nothing here awaits. `onHeadChanges` is the re-join
    // seam: a fold-side fact lands promptly instead of waiting for the next
    // work/state emission, and it pushes through the same single funnel.
    // BOTH ARE NULL AT `off` (r13): no pre-fetched read on the join path and
    // no acked-envelope handback subscription — the bridge composes exactly as
    // it did pre-cut.
    headSnapshot: dualReadArmed ? () => trajectory.sessionHeads : null,
    onHeadChanges: !dualReadArmed
        ? null
        : (listener) => trajectory.onSessionHeadsChanged(
            listener,
            fireImmediately: false,
          ),
    dualRead: dualRead,
    // THE STEP AXIS's third input (C4), on identical terms: a pre-fetched P2
    // read and its own re-join seam, both pushing through the same single
    // funnel. The pass fills `SessionProjection.trajCursor` under
    // `primary` + `live`, and every cursor consumer reads it through
    // `effectiveStepCursor` — so `observe` leaves all seven byte-identical.
    stepSnapshot: dualReadArmed ? () => trajectory.stepCursors : null,
    onStepChanges: !dualReadArmed
        ? null
        : (listener) =>
              trajectory.onStepCursorsChanged(listener, fireImmediately: false),
    stepDualRead: stepDualRead,
  );
  // The wedge (tg-jwh) flares `station.wedged` through the SAME emit-only
  // transport the engine's other LOUD signals use (ADR-0008 D9 / D-8) — no
  // parallel escalation channel.
  final driver = StationDriver(
    bridge: bridge,
    registry: resolvedRegistry,
    transport: transport,
    wedgeThreshold: wedgeThreshold,
    wedgePollInterval: wedgePollInterval,
  );

  final liveResolver = switch (resolver) {
    CircuitResolver(:final rootCircuitFor) => CircuitResolver(
      rootCircuitFor,
      reapWorktree: git.reap,
      workRoot: workRoot,
    ),
    _ => resolver,
  };

  return StationWorkRuntime._(
    wiring: StationWorkWiring(
      notifier: bridge.notifier,
      services: services,
      resolver: liveResolver,
      registry: resolvedRegistry,
      // tg-2mb: build the vendor OFF-tree (the DI rule — a branch never builds a
      // service) so the production work subtree resolves the SAME real vendor
      // StationKernel.start mounts. Without this the molecule allocation at the
      // readiness gate throws `No ProcessLeaseVendor` and the station wedges.
      // The SAME instance the restart reconciler sweeps with (tg-eli phase 1).
      processLeaseVendor: leaseVendor,
      transport: transport,
      // Stage 1's ONE new ambient value (stage1-wiring §1.1).
      trajectory: TrajectoryRecorderScope(recorder),
    ),
    commands: commands,
    git: git,
    trajectory: trajectory,
    stateSubstation: stateSubstation,
    readPathName: readPathName,
    driver: driver,
    restart: restart,
    provider: provider,
    onOrphan: orphanSink,
    onRefusal: refusalSink,
    sourcesStart: () async {
      await Future.wait(bundles.values.map((b) => b.runtime.start()));
      await stateBundle.runtime.start();
    },
    sourcesShutdown: () async {
      await stateBundle.shutdown();
      await Future.wait(bundles.values.map((b) => b.shutdown()));
      await work.dispose();
    },
    freshnessBarrier: freshnessBarrier,
    syncStats: () => {
      for (final e in bundles.entries) e.key: e.value.runtime.stats,
      'state': stateBundle.runtime.stats,
    },
    workFreshness: () => work.freshness,
  );
}

/// The station's WORK-SIGNAL probe — the live binding of the engine's COMPLETION
/// FENCE.
///
/// Asks [git] whether a bead's workspace still holds UNCOMMITTED work, EXCLUDING
/// the grid's own runtime dir ([kGridRuntimeDirName]) — `.grid/critique/` (incl.
/// the pinned diff), `.grid/spec/`, `.grid/telemetry/`. That residue is written by
/// the grid's OWN steps (the critics, `pin-diff`, `specify`), none of which
/// commits it, so it is NOT a work signal.
///
/// The exclusion is what makes the signal SUBSTATION-INDEPENDENT: the_grid
/// gitignores `.grid` (git never reports it), while genesis and lenny do NOT (git
/// reports `?? .grid/`). Without it, a coding agent that CORRECTLY committed on
/// genesis would read as INTERRUPTED, respawn into the same residue, fail
/// identically, burn its restart budget, and escalate — a working completion
/// turned into a guaranteed failure loop.
///
/// [StationGitService.reap]'s three-gate check is untouched: it calls the same
/// probe with NO exclusion (ADR-0006 Decision 3, verbatim — residue in a worktree
/// it is about to REMOVE still blocks the removal).
WorkSignalProbe stationWorkSignal(StationGitService git) =>
    (workspaceDir) => git.hasUncommittedWork(
      workspaceDir,
      excluding: const <String>{kGridRuntimeDirName},
    );

/// Execs `gh` for a delivery method's PR opener (inherits the parent env so `gh`
/// finds its own auth).
Future<GitRunResult> ghRunner(String workDir, List<String> args) async {
  final result = await Process.run('gh', args, workingDirectory: workDir);
  return GitRunResult(
    exitCode: result.exitCode,
    output: '${result.stdout}${result.stderr}',
  );
}

/// The INERT git service for dry-run — a no-op `git` (every invocation an
/// empty success) so `listBeadWorktrees` parses an empty worktree set WITHOUT
/// executing a real `git`, the restart reconcile finds no survivors, and
/// `provisionWorktree` materializes NOTHING. Exposed for the inertness
/// regression tests.
StationGitService buildDryStationGitService() => DryStationGitService();

/// Adapts a live [GridControllerRuntime] to the engine's [SnapshotSource] —
/// re-homed from the deleted `grid_cli` adapter (H3): a pure pass-through
/// that owns nothing and subscribes to nothing (the join bridge is the lone
/// subscriber, A39).
class _RuntimeSnapshotSource implements SnapshotSource {
  const _RuntimeSnapshotSource(this._runtime);

  final GridControllerRuntime _runtime;

  @override
  Stream<GraphSnapshot> get snapshots => _runtime.snapshots;

  @override
  GraphSnapshot? get current => _runtime.current;
}

/// The DRY-RUN bd seam: returns a canned envelope so the engine's session mint
/// runs end-to-end, but issues no real `bd` and touches no store.
class NoOpBdRunner implements BdRunner {
  /// Const-constructible.
  const NoOpBdRunner();

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? 'dry-session'
        : (args.length >= 2 ? args[1] : '');
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}

/// The dry-run transport: records every would-be spawn, spawns nothing.
class DryRunProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final Set<String> _running = <String>{};

  /// Every (would-be) spawn name, in call order (for the dry-run report).
  final List<String> wouldSpawn = <String>[];

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    wouldSpawn.add(name);
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async => _running.remove(name);

  @override
  Future<void> interrupt(String name) async {}

  @override
  Future<void> write(String name, List<int> bytes) => Future<void>.error(
    SessionNotWritable(name, 'dry-run sessions are not writable'),
  );

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  Stream<List<int>> interactionOutput(String name) =>
      throw SessionNotWritable(name, 'dry-run sessions have no interaction');

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => null;

  // A dry-run session never spawns and never ends, so no terminal is ever
  // retained ([RuntimeProvider.terminalOf]'s null case).
  @override
  RuntimeEvent? terminalOf(String name) => null;

  // No OS process exists behind a would-be spawn — a duplicate dry-run start
  // therefore fails acquire LOUD (tg-090) instead of waiting forever.
  @override
  ({int pid, int? pgid})? identityOf(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
}

/// The dry-run [StationGitService]: inherits the no-op-runner worktree probe
/// and overrides [provisionWorktree] so a dry run materializes NO worktree —
/// it returns a synthetic descriptor the host ignores. PUBLIC so the effect
/// posture is assertable by type: the dry-run inertness tests pin that
/// `dryRun: true` (and only `dryRun: true`) selects THIS service.
class DryStationGitService extends StationGitService {
  /// Creates the inert service over the no-op runner and PR opener.
  DryStationGitService()
    : super(runner: const _DryGitRunner(), prOpener: const _DryPrOpener());

  @override
  Future<BeadWorktree> provisionWorktree({
    required RootCheckout root,
    required String beadId,
  }) async => BeadWorktree(
    beadId: beadId,
    path: '${root.path}/.grid/worktrees/${root.substation}/$beadId',
    branch: 'grid/$beadId',
  );
}

/// A no-op `git` — every invocation is an empty success; no real `git` runs.
class _DryGitRunner implements GitRunner {
  const _DryGitRunner();

  @override
  Future<GitRunResult> run({
    required String workingDirectory,
    required List<String> args,
  }) async => const GitRunResult(exitCode: 0, output: '');
}

/// A no-op PR opener — never reached in dry-run (land ops are null), but the
/// git service requires one; it opens nothing.
class _DryPrOpener implements PrOpener {
  const _DryPrOpener();

  @override
  Future<PullRequestResult> open({
    required String workDir,
    required String branch,
    required String baseBranch,
    required String title,
    String body = '',
  }) async => PullRequestResult.failed(const PrOpenFailure('dry-run: no PR'));
}

/// An empty [GraphSnapshot] — the fail-safe the restart reconciler projects
/// cursors from before the state baseline lands (no sessions ⇒ every survivor
/// respawn-pending, never wrongly skipped).
GraphSnapshot _emptyGraphSnapshot() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);
