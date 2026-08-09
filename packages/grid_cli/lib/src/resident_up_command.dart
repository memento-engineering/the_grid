/// Reusable assembly for a composed foreground-resident station.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart' show GraphSnapshot;
import 'package:grid_exploration/grid_exploration.dart'
    show DevModeSeat, armDevMode, stationVmServiceUri;
import 'package:grid_runtime/grid_runtime.dart'
    show GitOps, PrimaryCheckoutFreshness, SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridCommandHandler,
        GridCommandRequest,
        GridCommandResult,
        GridHandle,
        GridHookError,
        ReassembleReport,
        SubstationWorkSpec,
        TreeProjector,
        runGrid;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'resident_grid_delegate.dart';
import 'resident_station_flags.dart';
import 'station_control.dart';
import 'station_lock.dart';

/// Builds the station-authored delegate from parsed boot configuration ALONE
/// (tg-1fa2.4): no wiring, no provisioner, no effect implementations —
/// assembly is `GridDelegate.boot`-owned, and the dry-run posture is declared
/// in the delegate's TREE (no effect providers mounted) instead of nulls
/// threaded through this factory.
typedef ResidentGridDelegateFactory =
    ResidentGridDelegate Function({required ResidentStationConfig config});

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

/// Mounts [delegate]'s grid (`runGrid`): awaits its boot rail before the
/// first mount, then mounts the tree. CONTRACT: on failure the delegate is
/// disposed before the error propagates (the shell then releases the
/// projector and the lock — the unwind's tail).
///
/// `onDelegateSwapped` is the hot-restart COMMIT seam: the runner invokes it
/// synchronously once a fresh `delegateFactory` delegate has booted and been
/// adopted as the live one — NEVER inside the factory call itself, and never
/// on a failed restart boot (the old delegate stays live and keeps serving
/// every per-request read).
typedef ResidentGridRunner =
    Future<ResidentGridResource> Function(
      ResidentGridDelegate delegate, {
      required void Function() onFlushed,
      required Future<void> Function() orphanSweep,
      required void Function(ResidentGridDelegate next) onDelegateSwapped,
      required TreeProjector? treeProjector,
      ResidentGridDelegate Function()? delegateFactory,
    });
typedef ResidentControlStarter =
    Future<ResidentControlResource> Function({
      required int port,
      required String token,
      required StationStatus Function() view,
      required GridCommandHandler commandHandler,
      required TreeProjector? treeProjector,
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
///
/// The shell owns the PROCESS concerns — flag parsing, the freshness probes,
/// the station lock, the control socket, the dev-mode seat, the diagnostics
/// [TreeProjector] (process-lifetime, so `/stream` survives hot restarts),
/// signals, exit codes — and reads everything stateful off the delegate's
/// narrow vended views ([ResidentGridDelegate]): reference types flow OUT of
/// the delegate, never in. Teardown: unmount tree → orphan sweep → dispose
/// the delegate (all inside the runner's teardown, in that order — the sweep
/// reaps over the delegate's boot-assembled runtime, so the delegate must
/// outlive it) → dispose the shell's projector → release lock.
class ResidentUpCommand extends Command<int> {
  /// Creates a resident `up` command.
  ResidentUpCommand({
    required this.stationName,
    required ResidentGridDelegateFactory delegateFactory,
    required ResidentRosterReader codedRoster,
    required Set<String> harnessAllowList,
    required ResidentHarnessValidator validateHarness,
    StationLockService? lockService,
    ResidentLockAcquirer? acquireLock,
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
       _lockService = lockService ?? StationLockService(),
       _acquireLock = acquireLock,
       _runMountedGrid = runMountedGrid ?? defaultRunMountedGrid,
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
  final StationLockService _lockService;
  final ResidentLockAcquirer? _acquireLock;
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
      // Membership needs no shell check: `residentStationFlags` declares both
      // harness flags with `allowed:` over the same allow list, so the parser
      // already refused any name outside it. The shell validates only the
      // CONFIGURATION of the armed environment.
      final refusal = _validateHarness(selected);
      if (refusal != null) {
        stderr.writeln(
          '$prefix: environment "$selected" is misconfigured: $refusal',
        );
        return 64;
      }
    }

    // Config-only construction; a fresh call (below, hot-restart only) re-arms
    // a fresh delegate from the same inputs. An ASSEMBLY verb, not `build*`:
    // this closure re-reads the coded roster and resolves the armed one —
    // filesystem probes, skip renders, possible refusals — which STYLE.md
    // rule 1 keeps out of any `build*` name.
    ResidentGridDelegate assembleFreshDelegate() {
      final delegate = _delegateFactory(config: config);
      try {
        delegate.resolveArmedRoster(
          coded: _codedRoster(gridHome: config.gridHome),
          appended: config.appended,
          onSkip: (message) => stdout.writeln('$prefix: $message'),
        );
      } on Object {
        // A restart-time refusal (the re-probe found no armed seat, or an
        // appended seat's store vanished) must leave nothing to unwind: the
        // runner never adopted this delegate, so dispose the fresh corpse
        // here and let the refusal reach the restart caller loudly.
        delegate.dispose();
        rethrow;
      }
      return delegate;
    }

    // The ARMING POLICY is the delegate's (skip-coded vs refuse-appended,
    // tg-1fa2.4); the shell renders its decisions and maps refusals to exit
    // codes — the operator-visible surface is unchanged.
    final ResidentGridDelegate delegate;
    try {
      delegate = _delegateFactory(config: config);
    } on Object catch (error) {
      stderr.writeln('$prefix: $error');
      return 64;
    }
    final List<SubstationWorkSpec> armed;
    try {
      armed = delegate.resolveArmedRoster(
        coded: roster,
        appended: config.appended,
        onSkip: (message) => stdout.writeln('$prefix: $message'),
      );
    } on StationRefusal catch (refusal) {
      delegate.dispose();
      stderr.writeln('$prefix: $refusal');
      return refusal.code;
    }

    // The shell OBSERVES checkout freshness (a process-level git probe); the
    // POSTURE over the observations is the delegate's.
    final freshness = await Future.wait([
      for (final seat in armed)
        _inspectPrimaryCheckout(
          seat,
        ).then((value) => (seat: seat, value: value)),
    ]);
    final freshnessText = freshness
        .map((entry) => '${entry.seat.name}: ${entry.value.verdict}')
        .join(', ');
    final posture = delegate.stalenessPosture(
      anyStale: freshness.any((entry) => !entry.value.isFresh),
      allowStale: config.allowStale,
      verdicts: freshnessText,
    );
    switch (posture) {
      case StalenessRefused(:final message):
        delegate.dispose();
        stderr.writeln('$prefix: $message');
        return 64;
      case StalenessWarned(:final message):
        stderr.writeln('$prefix: $message');
      case StalenessClear():
        break;
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
      delegate.dispose();
      stderr.writeln('$prefix: $error');
      return 64;
    }

    final vmServiceUri = await _readVmServiceUri();

    // The LIVE delegate: a hot restart retires the running one for a fresh
    // factory build, so every per-request read below goes through this
    // holder — never a captured stale instance. It is re-pointed ONLY at the
    // runner's commit seam (`onDelegateSwapped`), after the fresh delegate's
    // boot succeeded: swapping inside the factory would route reads to an
    // un-booted delegate during the awaited boot, and to a disposed corpse
    // forever after a FAILED restart boot.
    var live = delegate;

    // The diagnostics projection is SHELL-owned and process-lifetime: one
    // sink for `runGrid`'s flush rail and the control surface's `/stream`,
    // surviving hot restarts (a fresh delegate's tree flushes into the same
    // projector). The shell disposes it after the tree unmounts.
    final treeProjector = TreeProjector();

    final ResidentGridResource grid;
    try {
      grid = await _runMountedGrid(
        delegate,
        onFlushed: () => live.afterFlush(),
        orphanSweep: () => live.sweepOrphans(),
        onDelegateSwapped: (next) => live = next,
        treeProjector: treeProjector,
        delegateFactory: vmServiceUri == null ? null : assembleFreshDelegate,
      );
    } on Object catch (error) {
      // The runner's contract disposed the delegate; the shell's remaining
      // steps are its own projector and the lock.
      treeProjector.dispose();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 64;
    }

    // The ONE post-mount arming unwind: every shell seat created so far is
    // disposed in reverse creation order — including the seat whose OWN
    // arming step threw (a bound control socket or a registered dev-mode
    // seat must never be stranded because its lock advertisement failed).
    Future<int> failArming(
      Object error, {
      ResidentControlResource? control,
      ResidentDevModeResource? devMode,
    }) async {
      await devMode?.dispose();
      await control?.dispose();
      await grid.teardown();
      treeProjector.dispose();
      await stationLock.release();
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final token = mintControlToken();
    ResidentControlResource? armingControl;
    try {
      armingControl = await _startControl(
        port: config.controlPort,
        token: token,
        view: () => _status(config, armed, startedAt, live.stationView),
        commandHandler: _LiveDelegateCommandHandler(() => live),
        treeProjector: treeProjector,
      );
      await stationLock.updateControl(
        controlUrl: armingControl.url,
        token: token,
      );
    } on Object catch (error) {
      return failArming(error, control: armingControl);
    }
    final control = armingControl;

    ResidentDevModeResource? devMode;
    try {
      devMode = await _armDevelopmentMode(
        vmServiceUri: vmServiceUri,
        hotReload: () async => (await grid.hotReload()).toJson(),
        hotRestart: () async => (await grid.hotRestart()).toJson(),
        latest: () => live.stationView.latest.graph,
        readPath: () => live.stationView.readPathName,
      );
      devMode?.register();
      if (devMode != null) {
        await stationLock.updateVmService(devMode.vmServiceUri);
      }
    } on Object catch (error) {
      return failArming(error, control: control, devMode: devMode);
    }

    final view = live.stationView;
    stdout
      ..writeln('$stationName up — resident station (runGrid)')
      ..writeln(
        'mode: ${config.dryRun ? 'DRY-RUN (observe-only)' : 'LIVE'}  ·  '
        'substations: {$freshnessText}',
      )
      ..writeln(
        'stores: read-path {${view.readPathName}}  ·  state partition: '
        '${view.stateSubstation}',
      )
      ..writeln(
        'control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)',
      );

    // The unwind (tg-1fa2.4): unmount tree (in-tree resources unwind by
    // unmount order; `teardown` then runs the orphan sweep on the still-live
    // delegate and disposes it last) → release the shell's projector →
    // release lock. The shell's own seats (dev mode, the control socket)
    // close first — they are process concerns that never entered the tree.
    Future<void> unwind() async {
      await devMode?.dispose();
      await control.dispose();
      await grid.teardown();
      treeProjector.dispose();
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
    ResidentStationView view,
  ) {
    final latest = view.latest;
    final liveSessions = latest.sessionsByWorkBead.values
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
      mounted: liveSessions,
      liveSessions: liveSessions,
      lastSyncAt: capturedAt.millisecondsSinceEpoch == 0 ? null : capturedAt,
      wedge: view.wedge,
      sync: view.syncStatus(),
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

/// Routes each control-plane command to the LIVE delegate's handler — a hot
/// restart swaps the delegate under the running control socket, so the bound
/// handler must be re-read per request, never captured once at start.
final class _LiveDelegateCommandHandler implements GridCommandHandler {
  _LiveDelegateCommandHandler(this._live);
  final ResidentGridDelegate Function() _live;

  @override
  Future<GridCommandResult> call(GridCommandRequest request) =>
      _live().commandHandler(request);
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

/// The production [ResidentGridRunner]: `runGrid` plus the seam's
/// dispose-on-failure contract. Visible for testing so the contract is pinned
/// on THIS glue, not re-implemented by every test fake.
@visibleForTesting
Future<ResidentGridResource> defaultRunMountedGrid(
  ResidentGridDelegate delegate, {
  required void Function() onFlushed,
  required Future<void> Function() orphanSweep,
  required void Function(ResidentGridDelegate next) onDelegateSwapped,
  required TreeProjector? treeProjector,
  ResidentGridDelegate Function()? delegateFactory,
}) async {
  try {
    return _GridResource(
      await runGrid(
        delegate,
        onFlushed: onFlushed,
        orphanSweep: orphanSweep,
        treeProjector: treeProjector,
        delegateFactory: delegateFactory,
        // The only delegates the runner ever swaps in come from
        // `delegateFactory` above, which produces [ResidentGridDelegate]s —
        // the downcast is total by construction.
        onDelegateSwapped: (next) =>
            onDelegateSwapped(next as ResidentGridDelegate),
      ),
    );
  } on Object catch (error, stackTrace) {
    // runGrid's boot-failure path already disposed the delegate; the other
    // pre-handle failures (`didLaunch`, the mount itself) leave it live —
    // dispose it here so the seam's contract holds either way: on failure
    // the delegate is DOWN before the error reaches the shell.
    if (error is! GridHookError || error.hook != 'boot') {
      delegate.dispose();
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<ResidentControlResource> _defaultStartControl({
  required int port,
  required String token,
  required StationStatus Function() view,
  required GridCommandHandler commandHandler,
  required TreeProjector? treeProjector,
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
