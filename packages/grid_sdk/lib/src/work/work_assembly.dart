import 'dart:async';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;

import '../stores/stores.dart';
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

/// The runner-held OFF-tree work machinery `buildStationWork` assembles — the
/// v3 successor to the deleted `StationSources`/`StationWiring`/
/// `TreeRunWiring` boot path (H3), re-shaped for `runGrid`: the tree no longer
/// rides a kernel-owned `TreeOwner`; it mounts inside the `runGrid`
/// composition ([StationWork]/[SubstationWork]) while THIS object owns
/// everything off-tree.
///
/// Lifecycle (the pinned ordering, ADR-0007 §4):
///
/// ```dart
/// final work = await buildStationWork(...);
/// await work.start();                       // controllers → freshness →
///                                           // restart-reconcile → bridge
/// final grid = runGrid(delegate,            // NOW the tree mounts + spawns
///     onFlushed: work.afterFlush,           // D-5 cooldown/unclaimed re-scan
///     orphanSweep: work.sweepOrphans);      // the teardown reap
/// // ... resident ...
/// await grid.teardown();                    // unmount → effects kill → SWEEP
/// await work.shutdown();                    // bridge + controllers down
/// ```
class StationWorkRuntime {
  StationWorkRuntime._({
    required this.wiring,
    required this.git,
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
  }) : _driver = driver,
       _restart = restart,
       _provider = provider,
       _onOrphan = onOrphan,
       _onRefusal = onRefusal,
       _sourcesStart = sourcesStart,
       _sourcesShutdown = sourcesShutdown,
       _freshnessBarrier = freshnessBarrier;

  /// The ambient VALUES the tree's [StationWork] provides.
  final StationWorkWiring wiring;

  /// The worktree git service (dry-inert or live) — the runner threads it into
  /// its substations' `GitGridAssets` so the tree's source control and THIS
  /// runtime's restart sweep share one service.
  final StationGitService git;

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
  bool _started = false;
  bool _shutdown = false;
  RestartReport? _lastRestartReport;

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

  /// Brings the off-tree machinery up in the pinned ordering (ADR-0007 §4):
  /// controllers start → the freshness barrier completes → the restart
  /// reconciler reconciles survivors (respawn-or-skip, BEFORE any tree could
  /// blindly respawn) → the bridge starts following. Call BEFORE `runGrid`
  /// mounts the armed tree. Idempotent.
  Future<void> start() async {
    if (_started || _shutdown) return;
    _started = true;
    await _sourcesStart();
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

bool _sameCanonicalRoot(String left, String right) =>
    p.equals(p.canonicalize(left), p.canonicalize(right));

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
Future<StationWorkRuntime> buildStationWork({
  required GridStateStore stateStore,
  required List<SubstationWorkSpec> substations,
  required SessionResolver resolver,
  required bool dryRun,
  CapabilityRegistry? registry,
  int maxConcurrentWork = kDefaultMaxConcurrentWork,
  bool preferSql = true,
  RuntimeProvider? providerOverride,
  StationGitService? gitOverride,
  BdCliService? stateBdOverride,
  ProcessGroupController? groupsOverride,
  void Function(String message)? onRefusal,
  void Function(String message)? onOrphan,
  void Function(String message)? onUnresolvedExternalDep,
  ExplorationTransport? transport,
  Duration wedgeThreshold = kDefaultWedgeThreshold,
  Duration wedgePollInterval = kDefaultWedgePollInterval,
}) async {
  if (substations.isEmpty) {
    throw ArgumentError(
      'buildStationWork: at least one substation is required — there is no '
      'default substation (v3 §0).',
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
          'buildStationWork: substations "$prior" and "${s.name}" share the '
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
        'buildStationWork: substation "${s.name}": could not parse the work '
        'store at ${s.root}/.beads (resolved: ${ws?.root ?? 'nothing'}).',
      );
    }
    workspacesByName[s.name] = ws;
  }
  if (!File('${stateStore.beadsDir}/metadata.json').existsSync()) {
    throw StoreRefusal(
      'buildStationWork: no grid state store at ${stateStore.beadsDir} — the '
      'grid\'s own store lives under <grid.root>/.grid/ (Q5a). Seed it with '
      'the substation-init process (docs/SUBSTATION-INIT.md) before arming.',
    );
  }
  final stateWs = BeadsWorkspace.discover(start: stateStore.runtimeDir);
  if (stateWs == null ||
      !_sameCanonicalRoot(stateWs.root, stateStore.runtimeDir)) {
    throw StoreRefusal(
      'buildStationWork: could not parse the grid state store at '
      '${stateStore.beadsDir} (resolved: ${stateWs?.root ?? 'nothing'}).',
    );
  }
  // The owned state partition — the grid identity's own store names it (its
  // dolt database == the prefix its session ids mint under), never a flag.
  final stateSubstation = stateWs.database;
  if (stateSubstation == null || stateSubstation.isEmpty) {
    throw StoreRefusal(
      'buildStationWork: the grid state store at ${stateStore.beadsDir} names '
      'no dolt_database in metadata.json — cannot derive the owned state '
      'partition (re-seed the store; see docs/SUBSTATION-INIT.md).',
    );
  }

  // --- the controllers (one per work store + the state store).
  final bundles = <String, GridRuntimeBundle>{};
  for (final entry in workspacesByName.entries) {
    bundles[entry.key] = await GridRuntimeFactory.build(
      workspace: entry.value,
      preferSql: preferSql,
    );
  }
  final stateBundle = await GridRuntimeFactory.build(
    workspace: stateWs,
    preferSql: preferSql,
  );
  final readPathName = [
    for (final e in bundles.entries) '${e.key}=${e.value.readPath.name}',
    'state=${stateBundle.readPath.name}',
  ].join(', ');

  final work = FederatedSnapshotSource(
    {
      for (final e in bundles.entries)
        e.key: _RuntimeSnapshotSource(e.value.runtime),
    },
    onUnresolvedExternalDep:
        onUnresolvedExternalDep ?? (m) => stdout.writeln(m),
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
    ownership: BeadOwnershipPredicate(allowSet),
    onRefusal: refusalSink,
  );

  // --- the transports (ONE dry/live posture, per-seam overrides = tests).
  final provider =
      providerOverride ?? (dryRun ? DryRunProvider() : SubprocessProvider());
  final git =
      gitOverride ??
      (dryRun
          ? buildDryStationGitService()
          : StationGitService(
              runner: SystemGitRunner(),
              prOpener: GhPrOpener(ghRunner),
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
        'buildStationWork: could not register root "${s.name}"="${s.root}": '
        '$e',
      );
    }
  }
  // THE single-root consumer's root (RestartReconciler; the D-M6 restart
  // fan-out across N substations stays deferred): the FIRST substation's.
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
  final leaseVendor = defaultProcessLeaseVendor(services);

  final restart = RestartReconciler(
    listWorktrees: git.listBeadWorktrees,
    reapWorktree: git.reap,
    workRoot: workRoot,
    groups: groups,
    // The ONE bd chokepoint — the zombie-running reap re-mounts a dead
    // generation's corpse through it, on the_grid's OWN session bead, BEFORE the
    // tree mounts. Optional on the ctor (a sibling repo's guardrails omit it),
    // so `restart.hasChokepoint` is what proves it actually reached here.
    writer: writer,
    freshnessBarrier: freshnessBarrier,
    stateSnapshot: () => stateSource.current ?? _emptyGraphSnapshot(),
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
    // Adopt-across-restart (ADR-0009 D4) stays UNARMED — both halves at their
    // never-adopt defaults; arming is a deliberate later wire, all-or-nothing.
  );

  final bridge = StationJoinBridge(work: work, state: stateSource);
  // The wedge (tg-jwh) flares `station.wedged` through the SAME emit-only
  // transport the engine's other LOUD signals use (ADR-0008 D9 / D-8) — no
  // parallel escalation channel.
  final driver = StationDriver(
    bridge: bridge,
    registry: registry,
    transport: transport,
    wedgeThreshold: wedgeThreshold,
    wedgePollInterval: wedgePollInterval,
  );

  return StationWorkRuntime._(
    wiring: StationWorkWiring(
      notifier: bridge.notifier,
      services: services,
      resolver: resolver,
      registry: registry,
      // tg-2mb: build the vendor OFF-tree (the DI rule — a branch never builds a
      // service) so the production work subtree resolves the SAME real vendor
      // StationKernel.start mounts. Without this the molecule allocation at the
      // readiness gate throws `No ProcessLeaseVendor` and the station wedges.
      // The SAME instance the restart reconciler sweeps with (tg-eli phase 1).
      processLeaseVendor: leaseVendor,
    ),
    git: git,
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
StationGitService buildDryStationGitService() => _DryStationGitService();

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
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

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

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;
}

/// The dry-run [StationGitService]: inherits the no-op-runner worktree probe
/// and overrides [provisionWorktree] so a dry run materializes NO worktree —
/// it returns a synthetic descriptor the host ignores.
class _DryStationGitService extends StationGitService {
  _DryStationGitService()
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
