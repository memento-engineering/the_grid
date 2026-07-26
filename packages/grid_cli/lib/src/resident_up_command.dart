/// Reusable assembly for a composed foreground-resident station.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_exploration/grid_exploration.dart'
    show DevModeSeat, armDevMode, stationVmServiceUri;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, GhPrOpener, PrOpener, StationGitService, SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart'
    show
        CapabilityRegistry,
        GridDelegate,
        GridHandle,
        GridStateStore,
        SessionResolver,
        StationWorkRuntime,
        StationWorkWiring,
        StoreLocator,
        StoreRefusal,
        SubstationWorkSpec,
        buildStationWork,
        ghRunner,
        runGrid;
import 'package:path/path.dart' as p;

import 'resident_station_flags.dart';
import 'station_control.dart';
import 'station_lock.dart';

/// Builds the station-authored tree from shared boot values and injected
/// effect implementations.
typedef ResidentGridDelegateFactory =
    GridDelegate Function({
      required ResidentStationConfig config,
      required StationWorkWiring wiring,
      required StationGitService provisioner,
      required GitOps? gitOps,
      required PrOpener? prOpener,
    });

/// Reads the station's coded roster for a particular grid home.
typedef ResidentRosterReader =
    List<SubstationWorkSpec> Function({required String gridHome});

/// Validates one caller-owned harness, returning a refusal or null.
typedef ResidentHarnessValidator = String? Function(String harness);

/// Boots a foreground resident station over `runGrid`.
class ResidentUpCommand extends Command<int> {
  /// Creates a resident `up` command.
  ResidentUpCommand({
    required this.stationName,
    required ResidentGridDelegateFactory delegateFactory,
    required ResidentRosterReader codedRoster,
    required Set<String> harnessAllowList,
    required ResidentHarnessValidator validateHarness,
    required SessionResolver resolver,
    required CapabilityRegistry registry,
    StationLockService? lockService,
  }) : _delegateFactory = delegateFactory,
       _codedRoster = codedRoster,
       _harnessAllowList = Set.unmodifiable(harnessAllowList),
       _validateHarness = validateHarness,
       _resolver = resolver,
       _registry = registry,
       _lockService = lockService ?? StationLockService() {
    if (_harnessAllowList.isEmpty) {
      throw ArgumentError.value(harnessAllowList, 'harnessAllowList');
    }
    residentStationFlags(
      argParser,
      codedNames: [for (final seat in codedRoster(gridHome: '/')) seat.name],
      harnessAllowList: _harnessAllowList,
    );
  }

  /// The composing runner's operator-facing station name.
  final String stationName;
  final ResidentGridDelegateFactory _delegateFactory;
  final ResidentRosterReader _codedRoster;
  final Set<String> _harnessAllowList;
  final ResidentHarnessValidator _validateHarness;
  final SessionResolver _resolver;
  final CapabilityRegistry _registry;
  final StationLockService _lockService;

  @override
  String get name => 'up';

  @override
  String get description =>
      'Boot the foreground resident station; safe dry-run is the default.';

  @override
  Future<int> run() => _runResidentStation();

  Future<int> _runResidentStation() async {
    final args = argResults!;
    final prefix = '$stationName up';
    final rawHome = (args.option('grid-home') ?? args.option('state-workspace'))
        ?.trim();
    final roster = _codedRoster(
      gridHome: rawHome != null && p.isAbsolute(rawHome) ? rawHome : '/',
    );
    final ResidentStationConfig config;
    try {
      config = residentStationConfigFrom(
        args,
        stationName: stationName,
        codedNames: {for (final seat in roster) seat.name},
      );
    } on FormatException catch (error) {
      stderr.writeln('$prefix: ${error.message}');
      return 64;
    } on ArgumentError catch (error) {
      stderr.writeln('$prefix: ${error.message}');
      return 64;
    }

    for (final selected in [config.harness, config.buildHarness]) {
      if (selected == null) continue;
      if (!_harnessAllowList.contains(selected)) {
        stderr.writeln(
          '$prefix: harness "$selected" names no armed environment '
          '(armed: ${_harnessAllowList.join(', ')}).',
        );
        return 64;
      }
      final refusal = _validateHarness(selected);
      if (refusal != null) {
        stderr.writeln(
          '$prefix: environment "$selected" is misconfigured: $refusal',
        );
        return 64;
      }
    }

    final stateStore = GridStateStore.forGridRoot(config.gridHome);
    final locator = StoreLocator();
    final armed = <SubstationWorkSpec>[];
    for (final seat in roster) {
      try {
        locator.locateWorkStore(root: seat.root, substationName: seat.name);
        armed.add(seat);
      } on StoreRefusal {
        stdout.writeln(
          '$prefix: skipping coded substation "${seat.name}" — no work store '
          'at ${seat.root} (not present in this checkout).',
        );
      }
    }
    for (final seat in config.appended) {
      try {
        locator.locateWorkStore(root: seat.root, substationName: seat.name);
        armed.add(
          SubstationWorkSpec(
            name: seat.name,
            root: seat.root,
            prefix: seat.prefix,
          ),
        );
      } on ArgumentError catch (error) {
        stderr.writeln('$prefix: ${error.message}');
        return 64;
      } on StoreRefusal catch (error) {
        stderr.writeln('$prefix: $error');
        return 1;
      }
    }
    if (armed.isEmpty) {
      stderr.writeln(
        '$prefix: no substation resolved a work store at its root.',
      );
      return 1;
    }

    final startedAt = DateTime.now();
    final StationLockHandle stationLock;
    try {
      stationLock = await _lockService.acquire(
        stateWorkspaceDir: config.gridHome,
        pid: pid,
        now: startedAt,
      );
    } on Object catch (error) {
      stderr.writeln('$prefix: $error');
      return 64;
    }

    final StationWorkRuntime work;
    try {
      work = await buildStationWork(
        stateStore: stateStore,
        substations: armed,
        resolver: _resolver,
        registry: _registry,
        dryRun: config.dryRun,
        maxConcurrentWork: config.maxAgents,
      );
    } on Object catch (error) {
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }
    try {
      await work.start();
    } on Object catch (error) {
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final live = !config.dryRun;
    final vmServiceUri = await stationVmServiceUri();
    GridDelegate buildDelegate() => _delegateFactory(
      config: config,
      wiring: work.wiring,
      provisioner: work.git,
      gitOps: live ? GitOps(SystemGitRunner()) : null,
      prOpener: live ? GhPrOpener(ghRunner) : null,
    );

    final GridHandle grid;
    try {
      grid = runGrid(
        buildDelegate(),
        onFlushed: work.afterFlush,
        orphanSweep: () async {
          await work.sweepOrphans();
        },
        delegateFactory: vmServiceUri == null ? null : buildDelegate,
      );
    } on Object catch (error) {
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 64;
    }

    final token = mintControlToken();
    final StationControl control;
    try {
      control = await StationControl.start(
        port: config.controlPort,
        token: token,
        view: () => _status(config, armed, startedAt, work),
        commandHandler: work.commands,
      );
      await stationLock.updateControl(controlUrl: control.url, token: token);
    } on Object catch (error) {
      await grid.teardown();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final DevModeSeat? devMode;
    try {
      devMode = await armDevMode(
        vmServiceUri: vmServiceUri,
        hotReload: () async => (await grid.hotReload()).toJson(),
        hotRestart: () async => (await grid.hotRestart()).toJson(),
        latest: () => work.latest.graph,
        readPath: () => work.readPathName,
      );
      devMode?.register();
      if (devMode != null) {
        await stationLock.updateVmService(devMode.vmServiceUri);
      }
    } on Object catch (error) {
      await control.dispose();
      await grid.teardown();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    stdout
      ..writeln('$stationName up — resident station (runGrid)')
      ..writeln(
        'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
        'substations: {${armed.map((seat) => seat.name).join(', ')}}',
      )
      ..writeln(
        'stores: read-path {${work.readPathName}}  ·  state partition: '
        '${work.stateSubstation}',
      )
      ..writeln(
        'control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)',
      );

    Future<void> unwind() async {
      await devMode?.dispose();
      await control.dispose();
      await grid.teardown();
      await work.shutdown();
      await stationLock.release();
    }

    if (config.runFor case final runFor?) {
      await Future<void>.delayed(runFor);
      await unwind();
      return 0;
    }
    final interrupt = Completer<void>();
    final signals = <StreamSubscription<ProcessSignal>>[];
    for (final signal in const [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signals.add(
        signal.watch().listen((_) {
          if (!interrupt.isCompleted) interrupt.complete();
        }),
      );
    }
    await interrupt.future;
    stdout.writeln('\n$prefix: shutting down…');
    await unwind();
    for (final signal in signals) {
      await signal.cancel();
    }
    return 0;
  }

  StationStatus _status(
    ResidentStationConfig config,
    List<SubstationWorkSpec> armed,
    DateTime startedAt,
    StationWorkRuntime work,
  ) {
    final latest = work.latest;
    final live = latest.sessionsByWorkBead.values
        .where((session) => !session.isTerminal)
        .length;
    final capturedAt = latest.graph.capturedAt;
    return StationStatus(
      substation: armed.map((seat) => seat.name).join(','),
      stateStore: config.gridHome,
      workRoot: armed.map((seat) => '${seat.name}=${seat.root}').join(', '),
      dryRun: config.dryRun,
      pid: pid,
      startedAt: startedAt,
      version: Platform.version,
      ready: latest.graph.readyIds.length,
      mounted: live,
      liveSessions: live,
      lastSyncAt: capturedAt.millisecondsSinceEpoch == 0 ? null : capturedAt,
      wedge: work.wedge,
    );
  }
}
