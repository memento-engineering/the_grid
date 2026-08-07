/// Reusable assembly for a composed foreground-resident station.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show GraphSnapshot;
import 'package:grid_engine/grid_engine.dart' show JoinedSnapshot, WedgeState;
import 'package:grid_exploration/grid_exploration.dart'
    show DevModeSeat, armDevMode, stationVmServiceUri;
import 'package:grid_runtime/grid_runtime.dart'
    show
        GitOps,
        GhPrOpener,
        PrimaryCheckoutFreshness,
        PrOpener,
        StationGitService,
        SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart'
    show
        CapabilityRegistry,
        ExplorationTransport,
        GridDelegate,
        GridCommandHandler,
        GridHandle,
        GridStateStore,
        ReassembleReport,
        SessionResolver,
        StationWorkRuntime,
        StationWorkWiring,
        StoreLocator,
        StoreRefusal,
        SubstationWorkSpec,
        TreeProjector,
        buildStationWork,
        ghRunner,
        runGrid;
import 'package:path/path.dart' as p;

import 'resident_station_flags.dart';
import 'resident_diagnostics_reporter.dart';
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

/// The lock resource owned by a resident boot.
abstract interface class ResidentLockResource {
  String get path;
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  });
  Future<void> updateVmService(String vmServiceUri);
  Future<void> release();
}

/// The work runtime operations consumed by the resident shell.
abstract interface class ResidentWorkResource {
  StationWorkWiring get wiring;
  GridCommandHandler get commands;
  StationGitService get git;
  String get stateSubstation;
  String get readPathName;
  JoinedSnapshot get latest;
  WedgeState get wedge;
  Future<void> start();
  void afterFlush();
  Future<void> sweepOrphans();
  Future<void> shutdown();
}

/// The mounted grid operations consumed by the resident shell.
abstract interface class ResidentGridResource {
  Future<ReassembleReport> hotReload();
  Future<ReassembleReport> hotRestart();
  Future<void> teardown();
}

/// The control resource owned by a resident boot.
abstract interface class ResidentControlResource {
  String get url;
  Future<void> dispose();
}

/// The optional development-mode resource owned by a resident boot.
abstract interface class ResidentDevModeResource {
  String get vmServiceUri;
  void register();
  Future<void> dispose();
}

typedef ResidentLockAcquirer =
    Future<ResidentLockResource> Function({
      required String stateWorkspaceDir,
      required int pid,
      required DateTime now,
    });
typedef ResidentWorkBuilder =
    Future<ResidentWorkResource> Function({
      required GridStateStore stateStore,
      required List<SubstationWorkSpec> substations,
      required SessionResolver resolver,
      required CapabilityRegistry registry,
      required bool dryRun,
      required int maxConcurrentWork,
      required ExplorationTransport transport,
    });
typedef ResidentGridRunner =
    ResidentGridResource Function(
      GridDelegate delegate, {
      required void Function() onFlushed,
      required Future<void> Function() orphanSweep,
      required TreeProjector treeProjector,
      GridDelegate Function()? delegateFactory,
    });
typedef ResidentControlStarter =
    Future<ResidentControlResource> Function({
      required int port,
      required String token,
      required StationStatus Function() view,
      required GridCommandHandler commandHandler,
      required TreeProjector treeProjector,
    });
typedef ResidentDevModeArmer =
    Future<ResidentDevModeResource?> Function({
      required String? vmServiceUri,
      required Future<Map<String, Object?>> Function() hotReload,
      required Future<Map<String, Object?>> Function() hotRestart,
      required GraphSnapshot Function() latest,
      required String Function() readPath,
    });
typedef ResidentVmServiceReader = Future<String?> Function();
typedef ResidentShutdownWaiter = Future<void> Function();
typedef ResidentPrimaryCheckoutInspector =
    Future<PrimaryCheckoutFreshness> Function(SubstationWorkSpec substation);

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
    ResidentLockAcquirer? acquireLock,
    ResidentWorkBuilder? buildWork,
    ResidentGridRunner? runMountedGrid,
    ResidentControlStarter? startControl,
    ResidentDevModeArmer? armDevelopmentMode,
    ResidentVmServiceReader? readVmServiceUri,
    ResidentShutdownWaiter? waitForShutdown,
    ResidentPrimaryCheckoutInspector? inspectPrimaryCheckout,
  }) : _delegateFactory = delegateFactory,
       _codedRoster = codedRoster,
       _harnessAllowList = Set.unmodifiable(harnessAllowList),
       _validateHarness = validateHarness,
       _resolver = resolver,
       _registry = registry,
       _lockService = lockService ?? StationLockService(),
       _acquireLock = acquireLock,
       _buildWork = buildWork ?? _defaultBuildWork,
       _runMountedGrid = runMountedGrid ?? _defaultRunMountedGrid,
       _startControl = startControl ?? _defaultStartControl,
       _armDevelopmentMode = armDevelopmentMode ?? _defaultArmDevelopmentMode,
       _readVmServiceUri = readVmServiceUri ?? stationVmServiceUri,
       _inspectPrimaryCheckout =
           inspectPrimaryCheckout ?? _defaultInspectPrimaryCheckout,
       _waitForShutdown = waitForShutdown ?? _waitForTerminationSignal {
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
  final ResidentLockAcquirer? _acquireLock;
  final ResidentWorkBuilder _buildWork;
  final ResidentGridRunner _runMountedGrid;
  final ResidentControlStarter _startControl;
  final ResidentDevModeArmer _armDevelopmentMode;
  final ResidentVmServiceReader _readVmServiceUri;
  final ResidentPrimaryCheckoutInspector _inspectPrimaryCheckout;
  final ResidentShutdownWaiter _waitForShutdown;

  static Future<PrimaryCheckoutFreshness> _defaultInspectPrimaryCheckout(
    SubstationWorkSpec seat,
  ) => GitOps(SystemGitRunner()).inspectPrimaryCheckout(seat.root);

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

    final freshness = await Future.wait([
      for (final seat in armed)
        _inspectPrimaryCheckout(
          seat,
        ).then((value) => (seat: seat, value: value)),
    ]);
    final freshnessText = freshness
        .map((entry) => '${entry.seat.name}: ${entry.value.verdict}')
        .join(', ');
    if (freshness.any((entry) => !entry.value.isFresh)) {
      if (!config.allowStale) {
        stderr.writeln(
          '$prefix: refusing stale primary checkout(s): {$freshnessText}; '
          'pass --allow-stale to warn and continue.',
        );
        return 64;
      }
      stderr.writeln(
        '$prefix: WARNING --allow-stale accepted primary checkout verdicts: '
        '{$freshnessText}',
      );
    }

    final startedAt = DateTime.now();
    final ResidentLockResource stationLock;
    try {
      final acquire =
          _acquireLock ??
          ({
            required String stateWorkspaceDir,
            required int pid,
            required DateTime now,
          }) async => _StationLockResource(
            await _lockService.acquire(
              stateWorkspaceDir: stateWorkspaceDir,
              pid: pid,
              now: now,
            ),
          );
      stationLock = await acquire(
        stateWorkspaceDir: config.gridHome,
        pid: pid,
        now: startedAt,
      );
    } on Object catch (error) {
      stderr.writeln('$prefix: $error');
      return 64;
    }

    final diagnostics = StationDiagnosticsReporter(writeLine: stderr.writeln);
    final ResidentWorkResource work;
    try {
      work = await _buildWork(
        stateStore: stateStore,
        substations: armed,
        resolver: _resolver,
        registry: _registry,
        dryRun: config.dryRun,
        maxConcurrentWork: config.maxAgents,
        transport: diagnostics,
      );
    } on Object catch (error) {
      diagnostics.dispose();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }
    try {
      await work.start();
    } on Object catch (error) {
      diagnostics.dispose();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final live = !config.dryRun;
    final vmServiceUri = await _readVmServiceUri();
    GridDelegate buildDelegate() => _delegateFactory(
      config: config,
      wiring: work.wiring,
      provisioner: work.git,
      gitOps: live ? GitOps(SystemGitRunner()) : null,
      prOpener: live ? GhPrOpener(ghRunner) : null,
    );

    final ResidentGridResource grid;
    try {
      grid = _runMountedGrid(
        buildDelegate(),
        onFlushed: work.afterFlush,
        orphanSweep: () async {
          await work.sweepOrphans();
        },
        treeProjector: diagnostics.treeProjector,
        delegateFactory: vmServiceUri == null ? null : buildDelegate,
      );
    } on Object catch (error) {
      diagnostics.dispose();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 64;
    }

    final token = mintControlToken();
    final ResidentControlResource control;
    try {
      control = await _startControl(
        port: config.controlPort,
        token: token,
        view: () => _status(config, armed, startedAt, work),
        commandHandler: work.commands,
        treeProjector: diagnostics.treeProjector,
      );
      await stationLock.updateControl(controlUrl: control.url, token: token);
    } on Object catch (error) {
      await grid.teardown();
      diagnostics.dispose();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final ResidentDevModeResource? devMode;
    try {
      devMode = await _armDevelopmentMode(
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
      diagnostics.dispose();
      await work.shutdown();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    stdout
      ..writeln('$stationName up — resident station (runGrid)')
      ..writeln(
        'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
        'substations: {$freshnessText}',
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
      diagnostics.dispose();
      await work.shutdown();
      await stationLock.release();
    }

    if (config.runFor case final runFor?) {
      await Future<void>.delayed(runFor);
      await unwind();
      return 0;
    }
    await _waitForShutdown();
    stdout.writeln('\n$prefix: shutting down…');
    await unwind();
    return 0;
  }

  StationStatus _status(
    ResidentStationConfig config,
    List<SubstationWorkSpec> armed,
    DateTime startedAt,
    ResidentWorkResource work,
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

final class _StationLockResource implements ResidentLockResource {
  _StationLockResource(this._handle);
  final StationLockHandle _handle;

  @override
  String get path => _handle.path;
  @override
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) => _handle.updateControl(controlUrl: controlUrl, token: token);
  @override
  Future<void> updateVmService(String vmServiceUri) =>
      _handle.updateVmService(vmServiceUri);
  @override
  Future<void> release() => _handle.release();
}

final class _StationWorkResource implements ResidentWorkResource {
  _StationWorkResource(this._runtime);
  final StationWorkRuntime _runtime;

  @override
  StationWorkWiring get wiring => _runtime.wiring;
  @override
  GridCommandHandler get commands => _runtime.commands;
  @override
  StationGitService get git => _runtime.git;
  @override
  String get stateSubstation => _runtime.stateSubstation;
  @override
  String get readPathName => _runtime.readPathName;
  @override
  JoinedSnapshot get latest => _runtime.latest;
  @override
  WedgeState get wedge => _runtime.wedge;
  @override
  Future<void> start() => _runtime.start();
  @override
  void afterFlush() => _runtime.afterFlush();
  @override
  Future<void> sweepOrphans() => _runtime.sweepOrphans();
  @override
  Future<void> shutdown() => _runtime.shutdown();
}

final class _GridResource implements ResidentGridResource {
  _GridResource(this._handle);
  final GridHandle _handle;

  @override
  Future<ReassembleReport> hotReload() => _handle.hotReload();
  @override
  Future<ReassembleReport> hotRestart() => _handle.hotRestart();
  @override
  Future<void> teardown() => _handle.teardown();
}

final class _ControlResource implements ResidentControlResource {
  _ControlResource(this._control);
  final StationControl _control;

  @override
  String get url => _control.url;
  @override
  Future<void> dispose() => _control.dispose();
}

final class _DevModeResource implements ResidentDevModeResource {
  _DevModeResource(this._seat);
  final DevModeSeat _seat;

  @override
  String get vmServiceUri => _seat.vmServiceUri;
  @override
  void register() => _seat.register();
  @override
  Future<void> dispose() => _seat.dispose();
}

Future<ResidentWorkResource> _defaultBuildWork({
  required GridStateStore stateStore,
  required List<SubstationWorkSpec> substations,
  required SessionResolver resolver,
  required CapabilityRegistry registry,
  required bool dryRun,
  required int maxConcurrentWork,
  required ExplorationTransport transport,
}) async => _StationWorkResource(
  await buildStationWork(
    stateStore: stateStore,
    substations: substations,
    resolver: resolver,
    registry: registry,
    dryRun: dryRun,
    maxConcurrentWork: maxConcurrentWork,
    transport: transport,
  ),
);

ResidentGridResource _defaultRunMountedGrid(
  GridDelegate delegate, {
  required void Function() onFlushed,
  required Future<void> Function() orphanSweep,
  required TreeProjector treeProjector,
  GridDelegate Function()? delegateFactory,
}) => _GridResource(
  runGrid(
    delegate,
    onFlushed: onFlushed,
    orphanSweep: orphanSweep,
    treeProjector: treeProjector,
    delegateFactory: delegateFactory,
  ),
);

Future<ResidentControlResource> _defaultStartControl({
  required int port,
  required String token,
  required StationStatus Function() view,
  required GridCommandHandler commandHandler,
  required TreeProjector treeProjector,
}) async => _ControlResource(
  await StationControl.start(
    port: port,
    token: token,
    view: view,
    commandHandler: commandHandler,
    treeProjector: treeProjector,
  ),
);

Future<ResidentDevModeResource?> _defaultArmDevelopmentMode({
  required String? vmServiceUri,
  required Future<Map<String, Object?>> Function() hotReload,
  required Future<Map<String, Object?>> Function() hotRestart,
  required GraphSnapshot Function() latest,
  required String Function() readPath,
}) async {
  final seat = await armDevMode(
    vmServiceUri: vmServiceUri,
    hotReload: hotReload,
    hotRestart: hotRestart,
    latest: latest,
    readPath: readPath,
  );
  return seat == null ? null : _DevModeResource(seat);
}

Future<void> _waitForTerminationSignal() async {
  final interrupt = Completer<void>();
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    for (final signal in const [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      signals.add(
        signal.watch().listen((_) {
          if (!interrupt.isCompleted) interrupt.complete();
        }),
      );
    }
    await interrupt.future;
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
  }
}
