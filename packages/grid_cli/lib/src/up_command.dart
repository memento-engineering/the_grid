/// Reusable assembly for a composed foreground-resident station.
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart'
    show BdCliService, BeadsWorkspace, GraphSnapshot, ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart'
    show SessionProjection, configuredBdTypeNames;
import 'package:grid_exploration/grid_exploration.dart'
    show DevModeHost, armDevMode, stationVmServiceUri;
import 'package:grid_runtime/grid_runtime.dart'
    show
        BeadOwnershipPredicate,
        GitOps,
        GridIssueTypes,
        PrimaryCheckoutFreshness,
        SystemGitRunner;
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridCommandHandler,
        GridCommandRequest,
        GridCommandResult,
        GridDelegate,
        GridHandle,
        GridHookError,
        GridStateStore,
        ReassembleReport,
        StalenessClear,
        StalenessRefused,
        StalenessWarned,
        StationRefusal,
        StationView,
        SubstationWorkSpec,
        TreeProjector,
        kNotWedged,
        runGrid;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'station_control.dart';
import 'station_flags.dart';
import 'station_lock.dart';
import 'station_stores.dart';
import 'state_store_gc.dart';

/// Builds the station-authored delegate from parsed boot configuration ALONE
/// (tg-1fa2.4): no wiring, no provisioner, no effect implementations —
/// assembly is `GridDelegate.boot`-owned. The dry-run posture TODAY is
/// boot-selected OFF-tree: boot hands the config's `dryRun` to grid_sdk's
/// station-work assembly, which picks inert implementations by type (no-op bd
/// runner, dry provider, dry git). Declaring it in the delegate's TREE (no
/// effect providers mounted, visible to the projection) is the TARGET state,
/// owned by the reference-boot follow-up bead — either way, no nulls thread
/// through this factory.
typedef GridDelegateFactory =
    GridDelegate Function({required StationConfig config});

/// Reads the station's coded roster for a particular grid home.
typedef RosterReader =
    List<SubstationWorkSpec> Function({required String gridHome});

/// Validates one caller-owned harness, returning a refusal or null.
typedef HarnessValidator = String? Function(String harness);

/// The lock resource owned by a resident boot.
abstract interface class LockResource {
  String get path;
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  });
  Future<void> updateVmService(String vmServiceUri);
  Future<void> release();
}

/// The mounted grid operations consumed by the resident shell.
abstract interface class GridResource {
  Future<ReassembleReport> hotReload();
  Future<ReassembleReport> hotRestart();
  Future<void> teardown();
}

/// The control resource owned by a resident boot.
abstract interface class ControlResource {
  String get url;
  Future<void> dispose();
}

/// The optional development-mode resource owned by a resident boot.
abstract interface class DevModeResource {
  String get vmServiceUri;
  void register();
  Future<void> dispose();
}

typedef LockAcquirer =
    Future<LockResource> Function({
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
typedef GridRunner =
    Future<GridResource> Function(
      GridDelegate delegate, {
      required void Function() onFlushed,
      required Future<void> Function() orphanSweep,
      required void Function(GridDelegate next) onDelegateSwapped,
      required TreeProjector? treeProjector,
      GridDelegate Function()? delegateFactory,
    });
typedef ControlStarter =
    Future<ControlResource> Function({
      required int port,
      required String token,
      required StationStatus Function() view,
      required GridCommandHandler commandHandler,
      required TreeProjector? treeProjector,
    });
typedef DevModeArmer =
    Future<DevModeResource?> Function({
      required String? vmServiceUri,
      required Future<Map<String, Object?>> Function() hotReload,
      required Future<Map<String, Object?>> Function() hotRestart,
      required GraphSnapshot Function() latest,
      required String Function() readPath,
    });
typedef VmServiceReader = Future<String?> Function();
typedef ShutdownWaiter = Future<void> Function();
typedef PrimaryCheckoutInspector =
    Future<PrimaryCheckoutFreshness> Function(SubstationWorkSpec substation);
typedef StateStoreMaintainer =
    Future<void> Function({required String gridHome});
typedef StateStoreTypesReader =
    Future<Map<String, dynamic>> Function({required String gridHome});

Future<Map<String, dynamic>> _defaultReadStateStoreTypes({
  required String gridHome,
}) {
  final BeadsWorkspace workspace = openStateStore(
    GridStateStore.forGridRoot(gridHome),
  );
  return BdCliService(ProcessBdRunner(workspaceRoot: workspace.root)).types();
}

/// Boots a foreground resident station over `runGrid`.
///
/// The shell owns the PROCESS concerns — flag parsing, the freshness probes,
/// the station lock, the control socket, the dev-mode host, the diagnostics
/// [TreeProjector] (process-lifetime, so `/stream` survives hot restarts),
/// signals, exit codes — and reads everything stateful off the delegate's
/// narrow vended views ([GridDelegate]): reference types flow OUT of
/// the delegate, never in. Teardown: unmount tree → orphan sweep → dispose
/// the delegate (all inside the runner's teardown, in that order — the sweep
/// reaps over the delegate's boot-assembled runtime, so the delegate must
/// outlive it) → dispose the shell's projector → release lock.
class UpCommand extends Command<int> {
  /// Creates a resident `up` command.
  ///
  /// [defaultHarness], when supplied, is the ambient `--harness` default and
  /// must be a member of [harnessAllowList]; a composing runner sets it
  /// without reaching around this constructor. Membership is enforced at the
  /// ONE locus that owns the option — `stationFlags` — and is never
  /// re-checked here.
  UpCommand({
    required this.stationName,
    required GridDelegateFactory delegateFactory,
    required RosterReader codedRoster,
    required Set<String> harnessAllowList,
    required HarnessValidator validateHarness,
    String? defaultHarness,
    StationLockService? lockService,
    LockAcquirer? acquireLock,
    GridRunner? runMountedGrid,
    ControlStarter? startControl,
    DevModeArmer? armDevelopmentMode,
    VmServiceReader? readVmServiceUri,
    ShutdownWaiter? waitForShutdown,
    PrimaryCheckoutInspector? inspectPrimaryCheckout,
    StateStoreMaintainer? maintainStateStore,
    StateStoreTypesReader? readStateStoreTypes,
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
       _maintainStateStore = maintainStateStore ?? _defaultMaintainStateStore,
       _readStateStoreTypes =
           readStateStoreTypes ?? _defaultReadStateStoreTypes,
       _waitForShutdown = waitForShutdown ?? _waitForTerminationSignal {
    if (_harnessAllowList.isEmpty) {
      throw ArgumentError.value(harnessAllowList, 'harnessAllowList');
    }
    stationFlags(
      argParser,
      codedNames: [for (final seat in codedRoster(gridHome: '/')) seat.name],
      harnessAllowList: _harnessAllowList,
      defaultHarness: defaultHarness,
    );
  }

  /// The composing runner's operator-facing station name.
  final String stationName;
  final GridDelegateFactory _delegateFactory;
  final RosterReader _codedRoster;
  final Set<String> _harnessAllowList;
  final HarnessValidator _validateHarness;
  final StationLockService _lockService;
  final LockAcquirer? _acquireLock;
  final GridRunner _runMountedGrid;
  final ControlStarter _startControl;
  final DevModeArmer _armDevelopmentMode;
  final VmServiceReader _readVmServiceUri;
  final PrimaryCheckoutInspector _inspectPrimaryCheckout;
  final StateStoreMaintainer _maintainStateStore;
  final StateStoreTypesReader _readStateStoreTypes;
  final ShutdownWaiter _waitForShutdown;

  static Future<PrimaryCheckoutFreshness> _defaultInspectPrimaryCheckout(
    SubstationWorkSpec seat,
  ) => GitOps(SystemGitRunner()).inspectPrimaryCheckout(seat.root);

  static Future<void> _defaultMaintainStateStore({required String gridHome}) =>
      StateStoreGc().run(gridHome: gridHome);

  @override
  String get name => 'up';

  @override
  String get description =>
      'Boot the foreground resident station; safe dry-run is the default.';

  @override
  Future<int> run() => _runStation();

  Future<int> _runStation() async {
    final args = argResults!;
    final prefix = '$stationName up';
    final rawHome = (args.option('grid-home') ?? args.option('state-workspace'))
        ?.trim();
    final roster = _codedRoster(
      gridHome: rawHome != null && p.isAbsolute(rawHome) ? rawHome : '/',
    );
    final StationConfig config;
    try {
      config = stationConfigFrom(
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
      // Membership needs no shell check: `stationFlags` declares both
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

    // Config-only construction — THE one delegate-assembly path, shared by
    // launch (below) and every hot restart: each call arms a fresh delegate
    // from the same inputs, resolving the roster from the canonicalized
    // `config.gridHome`. An ASSEMBLY verb, not `build*`: this closure
    // re-reads the coded roster and resolves the armed one — filesystem
    // probes, skip renders, possible refusals — which STYLE.md rule 1 keeps
    // out of any `build*` name.
    GridDelegate assembleFreshDelegate() {
      final delegate = _delegateFactory(config: config);
      try {
        delegate.resolveArmedRoster(
          coded: _codedRoster(gridHome: config.gridHome),
          appended: config.appended,
          onSkip: (message) => stdout.writeln('$prefix: $message'),
        );
      } on Object {
        // ANY resolution failure — a styled StationRefusal (no armed seat, a
        // vanished appended store) or an unexpected throw — must leave
        // nothing to unwind: no runner has adopted this delegate, so dispose
        // the fresh corpse here and let the error reach the caller loudly
        // (the launch call site maps it to an exit code; a restart caller
        // sees it raw).
        delegate.dispose();
        rethrow;
      }
      return delegate;
    }

    // The ARMING POLICY is the delegate's (skip-coded vs refuse-appended,
    // tg-1fa2.4); the shell renders its decisions and maps refusals to exit
    // codes — the operator-visible surface is unchanged. Launch rides the
    // SAME assembly closure as a hot restart (one roster-resolution path, off
    // the canonicalized `config.gridHome`); on any failure the closure has
    // already disposed the fresh delegate, so this site only renders: a
    // styled refusal keeps its own exit code, anything else is the factory's
    // (or the roster probe's) construction failure — exit 64, as before.
    final GridDelegate delegate;
    try {
      delegate = assembleFreshDelegate();
    } on StationRefusal catch (refusal) {
      stderr.writeln('$prefix: $refusal');
      return refusal.code;
    } on Object catch (error) {
      stderr.writeln('$prefix: $error');
      return 64;
    }
    final armed = delegate.armedRoster;

    // The shell OBSERVES checkout freshness (a process-level git probe); the
    // POSTURE over the observations is the delegate's. A THROWING inspector
    // is an unexpected error, not a styled refusal: dispose the delegate the
    // probes run under, then let the error propagate in its own shape.
    // One unwind step, loud-but-non-aborting (mirroring teardown's rail
    // posture): a throwing dispose is reported to stderr and the unwind
    // CONTINUES — every later step still runs, so the original error is
    // never masked and a lock release at the tail is guaranteed regardless
    // of which seat's dispose blew up.
    Future<void> settle(String step, FutureOr<void> Function() action) async {
      try {
        await action();
      } on Object catch (error) {
        stderr.writeln('$prefix: unwind step "$step" failed: $error');
      }
    }

    final List<({SubstationWorkSpec seat, PrimaryCheckoutFreshness value})>
    freshness;
    try {
      freshness = await Future.wait([
        for (final seat in armed)
          _inspectPrimaryCheckout(
            seat,
          ).then((value) => (seat: seat, value: value)),
      ]);
    } on Object {
      await settle('delegate dispose', delegate.dispose);
      rethrow;
    }
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

    if (!config.dryRun) {
      try {
        await _maintainStateStore(gridHome: config.gridHome);
      } on Object catch (error) {
        stderr.writeln('$prefix: state-store gc FAILED: error=$error');
      }
    }

    String? typesCustomWarning;
    try {
      final configured = configuredBdTypeNames(
        await _readStateStoreTypes(gridHome: config.gridHome),
      );
      final missing = <String>[
        for (final type in GridIssueTypes.customTypes)
          if (!configured.contains(type.wire)) type.wire,
      ];
      if (missing.isNotEmpty) {
        typesCustomWarning =
            'WARNING: types.custom is missing GridIssueTypes.customTypes: '
            '${missing.join(', ')} — station may be unable to mint its own beads; '
            'booting anyway.';
      }
    } on Object catch (error) {
      typesCustomWarning =
          'WARNING: types.custom probe FAILED: $error — booting anyway.';
    }

    final startedAt = DateTime.now();
    final LockResource stationLock;
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
      await settle('delegate dispose', delegate.dispose);
      stderr.writeln('$prefix: $error');
      return 64;
    }

    // Between the lock and the mount: a throwing VM-service probe must not
    // strand the un-disposed delegate NOR the held lock file. Unexpected
    // error, not a styled refusal — unwind (lock released LAST, the unwind's
    // standing tail) and rethrow in its own shape.
    final String? vmServiceUri;
    try {
      vmServiceUri = await _readVmServiceUri();
    } on Object {
      await settle('delegate dispose', delegate.dispose);
      await settle('lock release', stationLock.release);
      rethrow;
    }

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

    final GridResource grid;
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
      await settle('projector dispose', treeProjector.dispose);
      await settle('lock release', stationLock.release);
      stderr.writeln('$prefix: $error');
      return 64;
    }

    // The ONE post-mount arming unwind: every shell resource created so far is
    // disposed in reverse creation order — including the resource whose OWN
    // arming step threw (a bound control socket or a registered dev-mode host
    // must never be stranded because its lock advertisement failed).
    Future<int> failArming(
      Object error, {
      ControlResource? control,
      DevModeResource? devMode,
    }) async {
      if (devMode != null) await settle('dev-mode dispose', devMode.dispose);
      if (control != null) await settle('control dispose', control.dispose);
      await settle('grid teardown', grid.teardown);
      await settle('projector dispose', treeProjector.dispose);
      await settle('lock release', stationLock.release);
      stderr.writeln('$prefix: $error');
      return 1;
    }

    final token = mintControlToken();
    ControlResource? armingControl;
    try {
      armingControl = await _startControl(
        port: config.controlPort,
        token: token,
        // Per-request reads come off the LIVE delegate — roster included: a
        // hot restart re-resolves the armed roster, and a closure capturing
        // the launch-time list would render retired seats forever.
        view: () =>
            _status(config, live.armedRoster, startedAt, live.stationView),
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

    DevModeResource? devMode;
    try {
      devMode = await _armDevelopmentMode(
        vmServiceUri: vmServiceUri,
        hotReload: () async => (await grid.hotReload()).toJson(),
        hotRestart: () async => (await grid.hotRestart()).toJson(),
        // A station that vends no view has no join to serve, and a
        // fabricated snapshot would masquerade as a real one. The refusal
        // renders where each read actually reaches the delegate: [readPath]
        // is per-request and refuses LOUD through the RPC layer, while
        // [latest] feeds the host's graph refresh — the refused refresh
        // rides the runtime's errors stream, no baseline is ever captured,
        // and the graph tools serve the distinguishable never-joined shape
        // (zero beads, `capturedAt: null`), never a fabricated join. Pinned
        // end-to-end through the real `armDevMode` stack by
        // up_command_test's absence-posture group.
        latest: () => _requireView(live).latest.graph,
        readPath: () => _requireView(live).readPathName,
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
      // Absence is a designed posture (STYLE.md rule 3): a delegate that
      // vends no station view gets an honest banner line, not a crash.
      ..writeln(
        view == null
            ? 'stores: (no station view vended)'
            : 'stores: read-path {${view.readPathName}}  ·  state partition: '
                  '${view.stateSubstation}',
      )
      ..writeAll([if (typesCustomWarning != null) '$typesCustomWarning\n'])
      ..writeln(
        'control: ${control.url}  ·  token: (see ${stationLock.path}, 0600)',
      );

    // The shell's own resources (dev-mode host, the control socket) close
    // first — they are process concerns that never entered the tree.
    // Each step is settled independently: a throwing dispose is loud but
    // never strands the steps beneath it — the lock release always runs last.
    Future<void> unwind() async {
      if (devMode case final host?) {
        await settle('dev-mode dispose', host.dispose);
      }
      await settle('control dispose', control.dispose);
      await settle('grid teardown', grid.teardown);
      await settle('projector dispose', treeProjector.dispose);
      await settle('lock release', stationLock.release);
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

  /// Builds the `/status` snapshot off the LIVE delegate's vended [view].
  ///
  /// A null [view] is a designed absence (STYLE.md rule 3): `/status` still
  /// reports everything the shell knows first-hand (roster, mode, process),
  /// and renders the work axis empty — zero counts, no sync baseline
  /// (`lastSyncAt` null), the not-wedged default — never a throw.
  StationStatus _status(
    StationConfig config,
    List<SubstationWorkSpec> armed,
    DateTime startedAt,
    StationView? view,
  ) {
    final latest = view?.latest;
    final liveEntries =
        latest?.sessionsByWorkBead.entries
            .where((entry) => !entry.value.isTerminal)
            .toList(growable: false) ??
        const <MapEntry<String, SessionProjection>>[];
    final mountedIds = <String>{
      ...?latest?.graph.readyIds,
      for (final entry in liveEntries) entry.key,
    };
    final wedge = latest == null ? kNotWedged : view!.wedgeFor(latest);
    final prefixes = armed.map((seat) => seat.prefix).toSet();
    String? ownerOf(String id) =>
        BeadOwnershipPredicate.ownedPrefixOf(id, prefixes);
    final perSubstation = <SubstationStatus>[
      for (final seat in armed)
        () {
          final readyIds =
              latest?.graph.readyIds
                  .where((id) => ownerOf(id) == seat.prefix)
                  .toSet() ??
              <String>{};
          final liveIds = <String>{
            for (final entry in liveEntries)
              if (ownerOf(entry.key) == seat.prefix) entry.key,
          };
          return SubstationStatus(
            substation: seat.name,
            root: seat.root,
            ready: readyIds.length,
            mounted: <String>{...readyIds, ...liveIds}.length,
            live: liveIds.length,
          );
        }(),
    ];
    final capturedAt = latest?.graph.capturedAt;
    return StationStatus(
      substation: armed.map((seat) => seat.name).join(','),
      stateStore: config.gridHome,
      workRoot: armed.map((seat) => '${seat.name}=${seat.root}').join(', '),
      dryRun: config.dryRun,
      pid: pid,
      startedAt: startedAt,
      version: Platform.version,
      ready: latest?.graph.readyIds.length ?? 0,
      mounted: mountedIds.length,
      liveSessions: liveEntries.length,
      lastSyncAt: capturedAt == null || capturedAt.millisecondsSinceEpoch == 0
          ? null
          : capturedAt,
      perSubstation: perSubstation,
      wedge: wedge,
      sync: view?.syncStatus() ?? const <String, Object?>{},
    );
  }
}

/// Reads the LIVE delegate's vended view or refuses LOUD when the station
/// vends none — the dev-mode host's per-request reads have no honest empty
/// rendering (a fabricated snapshot would masquerade as a real join).
StationView _requireView(GridDelegate live) =>
    live.stationView ??
    (throw StateError(
      'this station\'s delegate vends no station view '
      '(GridDelegate.stationView is null).',
    ));

final class _StationLockResource implements LockResource {
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
/// handler must be re-read per request, never captured once at start. A
/// delegate that vends NO handler is a designed absence (STYLE.md rule 3):
/// every command is refused with a clear message, never a throw across the
/// control surface.
final class _LiveDelegateCommandHandler implements GridCommandHandler {
  _LiveDelegateCommandHandler(this._live);
  final GridDelegate Function() _live;

  @override
  Future<GridCommandResult> call(GridCommandRequest request) async {
    final handler = _live().commandHandler;
    if (handler == null) {
      return const GridCommandResult.refused(
        code: 'unsupported',
        message:
            'this station\'s delegate vends no command handler — '
            'POST /command is unavailable on this station.',
      );
    }
    return handler(request);
  }
}

final class _GridResource implements GridResource {
  _GridResource(this._handle);
  final GridHandle _handle;

  @override
  Future<ReassembleReport> hotReload() => _handle.hotReload();
  @override
  Future<ReassembleReport> hotRestart() => _handle.hotRestart();
  @override
  Future<void> teardown() => _handle.teardown();
}

final class _ControlResource implements ControlResource {
  _ControlResource(this._control);
  final StationControl _control;

  @override
  String get url => _control.url;
  @override
  Future<void> dispose() => _control.dispose();
}

final class _DevModeResource implements DevModeResource {
  _DevModeResource(this._host);
  final DevModeHost _host;

  @override
  String get vmServiceUri => _host.vmServiceUri;
  @override
  void register() => _host.register();
  @override
  Future<void> dispose() => _host.dispose();
}

/// The production [GridRunner]: `runGrid` plus the seam's
/// dispose-on-failure contract. Visible for testing so the contract is pinned
/// on THIS glue, not re-implemented by every test fake.
@visibleForTesting
Future<GridResource> defaultRunMountedGrid(
  GridDelegate delegate, {
  required void Function() onFlushed,
  required Future<void> Function() orphanSweep,
  required void Function(GridDelegate next) onDelegateSwapped,
  required TreeProjector? treeProjector,
  GridDelegate Function()? delegateFactory,
}) async {
  try {
    return _GridResource(
      await runGrid(
        delegate,
        onFlushed: onFlushed,
        orphanSweep: orphanSweep,
        treeProjector: treeProjector,
        delegateFactory: delegateFactory,
        onDelegateSwapped: onDelegateSwapped,
      ),
    );
  } on Object catch (error, stackTrace) {
    // runGrid's boot-failure path already disposed the delegate; the other
    // pre-handle failures (`didLaunch`, the mount itself) leave it live —
    // dispose it here so the seam's contract holds either way: on failure
    // the delegate is DOWN before the error reaches the shell. A throwing
    // dispose is loud but never masks the mount failure being rethrown.
    if (error is! GridHookError || error.hook != 'boot') {
      try {
        delegate.dispose();
      } on Object catch (disposeError) {
        stderr.writeln(
          'delegate dispose during failure unwind failed: $disposeError',
        );
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<ControlResource> _defaultStartControl({
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

Future<DevModeResource?> _defaultArmDevelopmentMode({
  required String? vmServiceUri,
  required Future<Map<String, Object?>> Function() hotReload,
  required Future<Map<String, Object?>> Function() hotRestart,
  required GraphSnapshot Function() latest,
  required String Function() readPath,
}) async {
  final host = await armDevMode(
    vmServiceUri: vmServiceUri,
    hotReload: hotReload,
    hotRestart: hotRestart,
    latest: latest,
    readPath: readPath,
  );
  return host == null ? null : _DevModeResource(host);
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
