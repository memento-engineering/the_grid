import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart'
    show Bead, BeadStatus, GraphSnapshot;
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart'
    show MoleculeStepKeys, SessionProjection, StepState, WedgeMonitor;
import 'package:grid_exploration/grid_exploration.dart' show armDevMode;
import 'package:grid_runtime/grid_runtime.dart'
    show GridIssueTypes, PrimaryCheckoutFreshness, PrimaryCheckoutState;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/recording_stdout.dart';

final class _View implements StationView {
  _View(this._label, {JoinedSnapshot? snapshot, WedgeMonitor? monitor})
    : snapshot = snapshot ?? JoinedSnapshot.empty(),
      monitor = monitor ?? WedgeMonitor(latest: JoinedSnapshot.empty);
  final String _label;
  final JoinedSnapshot snapshot;
  final WedgeMonitor monitor;
  @override
  String get stateSubstation => 'lunar-state';
  @override
  String get readPathName => _label;
  @override
  JoinedSnapshot get latest => snapshot;
  @override
  WedgeState get wedge => monitor.state;
  @override
  WedgeState wedgeFor(JoinedSnapshot snapshot) =>
      monitor.pollSnapshot(snapshot);
  @override
  Map<String, Object?> syncStatus() => const <String, Object?>{};
}

final class _Commands implements GridCommandHandler {
  @override
  Future<GridCommandResult> call(GridCommandRequest request) =>
      throw UnimplementedError();
}

/// The config-only fake: boot is the delegate's assembly rail; the vended
/// views are canned values labeled per delegate GENERATION (so a test can
/// tell WHICH delegate a per-request read reached); dispose records the
/// delegate's own step of the unwind.
final class _Delegate extends GridDelegate {
  _Delegate(
    this.events, {
    this.failAt,
    this.label = 'earth',
    this.vendsViews = true,
    this.snapshot,
    this.monitor,
  });

  final List<String> events;
  final String? failAt;
  final String label;
  final JoinedSnapshot? snapshot;
  final WedgeMonitor? monitor;

  /// False = the ABSENCE posture: this station vends neither a status view
  /// nor a command handler (the unified base's null defaults, tg-at3r), and
  /// the shell must render that honestly.
  final bool vendsViews;
  var _disposed = false;

  /// Whether [dispose] ran (the leak probes read this).
  bool get disposed => _disposed;

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('delegate.boot');
    if (failAt == 'boot') throw StateError('boom at boot');
  }

  @override
  StationView? get stationView {
    if (!vendsViews) return null;
    // The poisoned-corpse tripwire: a per-request read reaching a DISPOSED
    // delegate is exactly the hot-restart live-holder desync bug.
    if (_disposed) {
      throw StateError('stationView read on disposed delegate "$label"');
    }
    return _View(label, snapshot: snapshot, monitor: monitor);
  }

  @override
  GridCommandHandler? get commandHandler => vendsViews ? _Commands() : null;

  @override
  Future<void> sweepOrphans() async {
    // The disposed-corpse tripwire, on the SWEEP too: the contract says the
    // sweep reaps over the boot-assembled runtime, which dispose unwinds — a
    // runner sweeping after dispose would silently reopen the orphan window.
    if (_disposed) {
      throw StateError('sweepOrphans on disposed delegate "$label"');
    }
    events.add('sweep:$label');
  }

  @override
  void dispose() {
    _disposed = true;
    events.add('delegate.dispose');
    super.dispose();
  }
}

final class _Harness {
  _Harness._({
    required this.temp,
    required this.home,
    required this.workRoot,
    required this.missingRoot,
    required this.failAt,
    required this.devMode,
    required this.signalShutdown,
    required this.holdOpen,
    required this.restartBootFails,
    required this.includeMissingCoded,
    required this.checkoutFreshness,
    required this.vendsViews,
    required this.typesEnvelope,
    required this.typesError,
    required this.snapshot,
    required this.monitor,
  });

  static Future<_Harness> create({
    String? failAt,
    bool devMode = false,
    bool signalShutdown = false,
    bool holdOpen = false,
    bool restartBootFails = false,
    bool includeMissingCoded = false,
    bool seedWorkStore = true,
    bool vendsViews = true,
    Map<String, dynamic>? typesEnvelope,
    Object? typesError,
    JoinedSnapshot? snapshot,
    WedgeMonitor? monitor,
    Map<String, PrimaryCheckoutFreshness> checkoutFreshness =
        const <String, PrimaryCheckoutFreshness>{},
  }) async {
    final temp = Directory.systemTemp.createTempSync('resident-up-');
    final home = p.join(temp.path, 'home');
    final workRoot = p.join(temp.path, 'work');
    final missingRoot = p.join(temp.path, 'missing');
    seedStore(p.join(home, '.grid'));
    if (seedWorkStore) seedStore(workRoot);
    return _Harness._(
      temp: temp,
      home: home,
      workRoot: workRoot,
      missingRoot: missingRoot,
      failAt: failAt,
      devMode: devMode,
      signalShutdown: signalShutdown,
      holdOpen: holdOpen,
      restartBootFails: restartBootFails,
      includeMissingCoded: includeMissingCoded,
      checkoutFreshness: checkoutFreshness,
      vendsViews: vendsViews,
      typesEnvelope: typesEnvelope,
      typesError: typesError,
      snapshot: snapshot,
      monitor: monitor,
    );
  }

  final Directory temp;
  final String home;
  final String workRoot;
  final String missingRoot;
  final String? failAt;
  final bool devMode;
  final bool signalShutdown;
  final bool holdOpen;
  final bool restartBootFails;
  final bool includeMissingCoded;
  final Map<String, PrimaryCheckoutFreshness> checkoutFreshness;
  final bool vendsViews;
  final Map<String, dynamic>? typesEnvelope;
  final Object? typesError;
  final JoinedSnapshot? snapshot;
  final WedgeMonitor? monitor;
  final events = <String>[];
  final _stdout = ByteConsumer();
  final _stderr = ByteConsumer();

  /// Every delegate the command's factory built, in construction order (the
  /// launch delegate first, hot-restart generations after).
  final built = <_Delegate>[];
  TreeProjector? gridProjector;
  TreeProjector? controlProjector;

  /// The `/status` view closure handed to the control seat (per-request
  /// reads must come off the LIVE delegate, roster included).
  StationStatus Function()? statusView;

  /// The command handler handed to the control seat (routes to the LIVE
  /// delegate's vended handler — or renders its absence as a refusal).
  GridCommandHandler? controlCommandHandler;

  /// Captured dev-mode closures (the seat the operator's reload rides).
  Future<Map<String, Object?>> Function()? devHotRestart;
  String Function()? devReadPath;

  /// `holdOpen` coordination: [stationUp] completes when the run reaches the
  /// signal wait; the run unwinds when the test completes [release].
  final stationUp = Completer<void>();
  final release = Completer<void>();

  String get stdoutText => _stdout.text;
  String get stderrText => _stderr.text;

  Future<void> dispose() async {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }

  Future<int?> run({
    List<String> extra = const [],
    bool untimed = false,
  }) async {
    final stdoutSink = RecordingStdout(_stdout);
    final stderrSink = RecordingStdout(_stderr);
    _stdout.onText = (text) {
      if (!events.contains('render') && text.contains('lunar up —')) {
        events.add('render');
      }
    };
    final command = UpCommand(
      stationName: 'lunar',
      delegateFactory: ({required config}) {
        final generation = built.length;
        final delegate = _Delegate(
          events,
          failAt: generation == 0 ? failAt : (restartBootFails ? 'boot' : null),
          label: generation == 0 ? 'earth' : 'gen$generation',
          vendsViews: vendsViews,
          snapshot: snapshot,
          monitor: monitor,
        );
        built.add(delegate);
        return delegate;
      },
      codedRoster: ({required gridHome}) => [
        SubstationWorkSpec(name: 'earth', root: workRoot, prefix: 'earth'),
        if (includeMissingCoded)
          SubstationWorkSpec(name: 'dark', root: missingRoot, prefix: 'dark'),
      ],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
      acquireLock:
          ({required stateWorkspaceDir, required pid, required now}) async {
            events.add('lock');
            if (failAt == 'lock') {
              throw const StationRefusal('held', code: 64);
            }
            return _Lock(events, failAt: failAt);
          },
      runMountedGrid:
          (
            delegate, {
            required onFlushed,
            required orphanSweep,
            required onDelegateSwapped,
            required treeProjector,
            delegateFactory,
          }) async {
            gridProjector = treeProjector;
            // The seam's contract mirrors runGrid: the boot rail is awaited
            // before the first mount, and on ANY failure the delegate is
            // disposed before the error reaches the shell.
            try {
              await delegate.boot(const GridConfiguration());
              events.add('runGrid');
              _throwIf('runGrid');
            } on Object {
              delegate.dispose();
              rethrow;
            }
            return _Grid(
              events,
              delegate,
              orphanSweep: orphanSweep,
              delegateFactory: delegateFactory,
              onDelegateSwapped: onDelegateSwapped,
            );
          },
      startControl:
          ({
            required port,
            required token,
            required view,
            required commandHandler,
            required treeProjector,
          }) async {
            controlProjector = treeProjector;
            statusView = view;
            controlCommandHandler = commandHandler;
            events.add('control');
            _throwIf('control');
            return _Control(events, failAt: failAt);
          },
      armDevelopmentMode:
          ({
            required vmServiceUri,
            required hotReload,
            required hotRestart,
            required latest,
            required readPath,
          }) async {
            events.add('devMode');
            _throwIf('devMode');
            devHotRestart = hotRestart;
            devReadPath = readPath;
            return devMode ? _DevMode(events) : null;
          },
      readVmServiceUri: () async {
        _throwIf('vmService');
        return 'ws://vm';
      },
      inspectPrimaryCheckout: (seat) async {
        events.add('inspect:${seat.name}');
        _throwIf('inspect');
        return checkoutFreshness[seat.name] ??
            const PrimaryCheckoutFreshness(state: PrimaryCheckoutState.fresh);
      },
      maintainStateStore: ({required gridHome}) async {
        expect(gridHome, p.canonicalize(home));
        events.add('gc');
        if (failAt == 'gc-contained') {
          stderr.writeln('state-store gc FAILED: fake failure');
          return;
        }
        _throwIf('gc');
      },
      readStateStoreTypes: ({required gridHome}) async {
        expect(gridHome, p.canonicalize(home));
        events.add('types');
        if (typesError case final error?) throw error;
        return typesEnvelope ??
            <String, dynamic>{
              'custom_types': [
                for (final type in GridIssueTypes.customTypes) type.wire,
              ],
            };
      },
      waitForShutdown: () async {
        events.add('signal');
        if (holdOpen) {
          stationUp.complete();
          await release.future;
          return;
        }
        if (!signalShutdown) {
          throw StateError('unexpected signal wait');
        }
      },
    );
    final runner = CommandRunner<int>('lunar', 'test')..addCommand(command);
    final arguments = <String>[
      'up',
      '--grid-home',
      home,
      if (!untimed) ...['--for-seconds', '1'],
      ...extra,
    ];
    final result = await IOOverrides.runZoned(
      () => runner.run(arguments),
      stdout: () => stdoutSink,
      stderr: () => stderrSink,
    );
    await stdoutSink.flush();
    await stderrSink.flush();
    return result;
  }

  void _throwIf(String point) {
    if (failAt == point) throw StateError('boom at $point');
  }
}

final class _Lock implements LockResource {
  _Lock(this.events, {this.failAt});
  final List<String> events;
  final String? failAt;

  @override
  String get path => '/fake/station.lock';

  @override
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) async {
    events.add('lock.control');
    if (failAt == 'lock.control') throw StateError('boom at lock.control');
  }

  @override
  Future<void> updateVmService(String vmServiceUri) async {
    events.add('lock.vm');
    if (failAt == 'lock.vm') throw StateError('boom at lock.vm');
  }

  @override
  Future<void> release() async {
    events.add('lock.release');
  }
}

final class _Grid implements GridResource {
  _Grid(
    this.events,
    this.delegate, {
    required this.orphanSweep,
    this.delegateFactory,
    this.onDelegateSwapped,
  });

  final List<String> events;

  /// The MOUNTED live delegate — a successful hot restart retires it for the
  /// factory's fresh one, mirroring `GridHandle`.
  GridDelegate delegate;
  final Future<void> Function() orphanSweep;
  final GridDelegate Function()? delegateFactory;
  final void Function(GridDelegate next)? onDelegateSwapped;
  var _generation = 0;

  @override
  Future<ReassembleReport> hotReload() => throw UnimplementedError();

  @override
  Future<ReassembleReport> hotRestart() async {
    // Mirrors GridHandle.hotRestart: fresh factory delegate, boot AWAITED; a
    // failed boot disposes the fresh one, throws, and never commits (the old
    // delegate stays mounted); success adopts the fresh delegate, notifies
    // the shell's commit seam, THEN retires the old one.
    final factory = delegateFactory;
    if (factory == null) throw StateError('no delegateFactory armed');
    final next = factory();
    try {
      await next.boot(const GridConfiguration());
    } on Object catch (error, stackTrace) {
      next.dispose();
      Error.throwWithStackTrace(
        GridHookError('boot', next.runtimeType, error, stackTrace),
        stackTrace,
      );
    }
    final retired = delegate;
    delegate = next;
    onDelegateSwapped?.call(next);
    retired.dispose();
    return ReassembleReport(
      mode: ReassembleMode.restart,
      generation: ++_generation,
      rebuiltBranches: 1,
    );
  }

  @override
  Future<void> teardown() async {
    // runGrid's own teardown order: unmount the tree, run the orphan sweep on
    // the STILL-LIVE delegate (the shell's closure — it must reach the live
    // delegate, never a retired corpse, and the sweep reaps over the
    // boot-assembled runtime dispose unwinds), THEN dispose the delegate.
    events.add('grid.teardown');
    await orphanSweep();
    delegate.dispose();
  }
}

final class _Control implements ControlResource {
  _Control(this.events, {this.failAt});
  final List<String> events;
  final String? failAt;
  @override
  String get url => 'http://127.0.0.1:9999';
  @override
  Future<void> dispose() async {
    events.add('control.dispose');
    if (failAt == 'control.dispose') {
      throw StateError('boom at control.dispose');
    }
  }
}

final class _DevMode implements DevModeResource {
  _DevMode(this.events);
  final List<String> events;
  @override
  String get vmServiceUri => 'ws://vm';
  @override
  void register() => events.add('devMode.register');
  @override
  Future<void> dispose() async {
    events.add('devMode.dispose');
  }
}

JoinedSnapshot _statusSnapshot({
  required Set<String> readyIds,
  required Map<String, SessionProjection> sessions,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: readyIds,
    capturedAt: DateTime.utc(2026, 8, 21),
  ),
  sessionsByWorkBead: sessions,
);

SessionProjection _statusSession(String id, StepState state) =>
    SessionProjection(
      workBeadId: id,
      sessionId: 'tgdog-$id',
      isMolecule: true,
      moleculeBeads: [
        Bead(
          id: 'tgdog-$id-step',
          issueType: GridIssueTypes.step,
          status: BeadStatus.open,
          metadata: {
            MoleculeStepKeys.path: '$id/build',
            MoleculeStepKeys.state: state.name,
          },
        ),
      ],
    );

void main() {
  test('status projection uses one snapshot', () async {
    final fixtures = <({JoinedSnapshot snapshot, int gated, bool ripens})>[
      (
        snapshot: _statusSnapshot(readyIds: {}, sessions: {}),
        gated: 0,
        ripens: false,
      ),
      (
        snapshot: _statusSnapshot(
          readyIds: {},
          sessions: {
            'earth-running': _statusSession('earth-running', StepState.running),
          },
        ),
        gated: 0,
        ripens: false,
      ),
      (
        snapshot: _statusSnapshot(
          readyIds: {},
          sessions: {
            for (final id in ['earth-a', 'earth-b', 'earth-c'])
              id: _statusSession(id, StepState.gated),
          },
        ),
        gated: 3,
        ripens: true,
      ),
    ];

    for (final fixture in fixtures) {
      var now = DateTime.utc(2026, 8, 21);
      final monitor = WedgeMonitor(
        latest: () => fixture.snapshot,
        threshold: const Duration(minutes: 10),
        clock: () => now,
      );
      addTearDown(monitor.dispose);
      final h = await _Harness.create(
        holdOpen: true,
        snapshot: fixture.snapshot,
        monitor: monitor,
      );
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      var body = h.statusView!().toJson();
      var wedge = body['wedge'] as Map<String, Object?>;
      final work = body['work'] as Map<String, Object?>;
      expect(wedge['live'], work['liveSessions']);
      expect(wedge['gated'], fixture.gated);

      if (fixture.ripens) {
        now = now.add(const Duration(minutes: 10));
        body = h.statusView!().toJson();
        wedge = body['wedge'] as Map<String, Object?>;
        expect(
          wedge['live'],
          (body['work'] as Map<String, Object?>)['liveSessions'],
        );
        expect(wedge['gated'], fixture.gated);
        expect(wedge['wedged'], isTrue);
        expect(wedge['since'], isNotNull);
        expect(wedge['reason'], contains('parked at a gate'));
      }

      h.release.complete();
      expect(await run, 0);
    }
  });

  test('status projection populates every armed substation', () async {
    final snapshot = _statusSnapshot(
      readyIds: {'earth-ready'},
      sessions: {'earth-live': _statusSession('earth-live', StepState.running)},
    );
    final monitor = WedgeMonitor(latest: () => snapshot);
    addTearDown(monitor.dispose);
    final h = await _Harness.create(
      includeMissingCoded: true,
      holdOpen: true,
      snapshot: snapshot,
      monitor: monitor,
    );
    addTearDown(h.dispose);
    seedStore(h.missingRoot);
    final run = h.run(untimed: true);
    await h.stationUp.future;

    final status = h.statusView!();
    final rows = {for (final row in status.perSubstation) row.substation: row};
    expect(rows.keys, {'earth', 'dark'});
    expect(rows['earth']!.root, h.workRoot);
    expect(rows['earth']!.ready, 1);
    expect(rows['earth']!.live, 1);
    expect(rows['earth']!.mounted, 2);
    expect(rows['dark']!.root, h.missingRoot);
    expect(rows['dark']!.ready, 0);
    expect(rows['dark']!.live, 0);
    expect(rows['dark']!.mounted, 0);
    expect(status.ready, 1);
    expect(status.liveSessions, 1);
    expect(status.mounted, 2);
    final wireWork = status.toJson()['work'] as Map<String, Object?>;
    final wireRows = wireWork['perSubstation'] as List<Object?>;
    expect(wireRows, hasLength(2));
    expect(
      wireRows.cast<Map<String, Object?>>().singleWhere(
        (row) => row['substation'] == 'dark',
      )['live'],
      0,
    );

    h.release.complete();
    expect(await run, 0);
  });

  test('harness validation precedes store and delegate work', () async {
    final home = Directory.systemTemp.createTempSync('resident-up-');
    addTearDown(() => home.deleteSync(recursive: true));
    var delegateCalls = 0;
    var validations = 0;
    final command = UpCommand(
      stationName: 'lunar',
      delegateFactory: ({required config}) {
        delegateCalls++;
        throw UnimplementedError();
      },
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (name) {
        validations++;
        return 'not configured';
      },
    );
    final runner = CommandRunner<int>('lunar', 'test')..addCommand(command);
    final stderrBytes = ByteConsumer();
    final stderrSink = RecordingStdout(stderrBytes);
    final result = await IOOverrides.runZoned(
      () => runner.run(['up', '--grid-home', home.path]),
      stderr: () => stderrSink,
    );
    await stderrSink.flush();
    expect(result, 64);
    expect(validations, 1);
    expect(delegateCalls, 0);
    // The refusal is LOUD, not just the exit code: the operator is told which
    // environment refused and why (a silent exit-64 must not survive).
    expect(
      stderrBytes.text,
      contains('environment "safe" is misconfigured: not configured'),
    );
  });

  test('safe dry-run is the parser default and no bead option exists', () {
    final command = UpCommand(
      stationName: 'lunar',
      delegateFactory: ({required config}) => throw UnimplementedError(),
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
    );
    expect(command.argParser.defaultFor('dry-run'), isTrue);
    expect(command.argParser.defaultFor('allow-stale'), isFalse);
    expect(
      command.argParser.parse(<String>['--allow-stale']).flag('allow-stale'),
      isTrue,
    );
    expect(command.argParser.options['allow-stale']!.abbr, isNull);
    expect(command.argParser.options, isNot(contains('bead')));
  });

  test('the shell neither assembles work nor hardcodes diagnostics', () {
    final source = File('lib/src/up_command.dart').readAsStringSync();
    expect(source, isNot(contains('buildBuiltinEnvironmentRegistry')));
    // tg-1fa2.4: station-work assembly and the diagnostics-reporter effect
    // are boot-owned (the delegate's), never the shell's.
    expect(source, isNot(contains('assembleStationWork')));
    expect(source, isNot(contains('StationDiagnosticsReporter')));
    expect(source, isNot(contains('GhPrOpener')));
  });

  group('UpCommand assembly', () {
    test(
      'incomplete types.custom warns once in banner and boots anyway',
      () async {
        final all = [for (final type in GridIssueTypes.customTypes) type.wire];
        final missing = <String>[all[1], all[all.length - 2]];
        final h = await _Harness.create(
          typesEnvelope: <String, dynamic>{
            'custom_types': <Object>[
              for (var index = 0; index < all.length; index++)
                if (!missing.contains(all[index]))
                  index.isEven ? all[index] : {'name': all[index]},
            ],
          },
        );
        addTearDown(h.dispose);

        expect(await h.run(extra: const ['--no-dry-run']), 0);
        final lines = h.stdoutText.split('\n');
        final warning = lines.where((line) => line.contains('types.custom'));
        expect(warning, hasLength(1));
        expect(
          warning.single,
          'WARNING: types.custom is missing GridIssueTypes.customTypes: '
          '${missing.join(', ')} — station may be unable to mint its own beads; '
          'booting anyway.',
        );
        final warningIndex = lines.indexOf(warning.single);
        expect(lines[warningIndex - 1], startsWith('stores:'));
        expect(lines[warningIndex + 1], startsWith('control:'));
        expect(
          h.events,
          containsAllInOrder(<String>[
            'gc',
            'types',
            'lock',
            'delegate.boot',
            'runGrid',
            'control',
          ]),
        );
      },
    );

    test('complete types.custom boots without vocabulary noise', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.stdoutText, isNot(contains('types.custom')));
      expect(h.events, containsAllInOrder(<String>['types', 'runGrid']));
    });

    test('types probe failure warns once and boots anyway', () async {
      final h = await _Harness.create(typesError: StateError('probe boom'));
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      final warnings = h.stdoutText
          .split('\n')
          .where((line) => line.contains('WARNING'));
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('probe boom'));
      expect(warnings.single, contains('booting anyway'));
      expect(h.events, containsAllInOrder(<String>['types', 'runGrid']));
    });

    test('oversized live state store runs maintenance before lock', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(extra: const ['--no-dry-run']), 0);
      expect(
        h.events,
        containsAllInOrder(<String>[
          'inspect:earth',
          'gc',
          'lock',
          'delegate.boot',
        ]),
      );
    });

    test('dry-run skips state-store maintenance', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.events, isNot(contains('gc')));
    });

    test('work stores never enter maintenance', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final moon = p.join(h.temp.path, 'oversized-work-store');
      seedStore(moon);
      expect(
        await h.run(
          extra: <String>['--no-dry-run', '--substation', 'moon=$moon'],
        ),
        0,
      );
      expect(h.events.where((event) => event == 'gc'), hasLength(1));
    });

    test('maintenance failure is loud and non-aborting', () async {
      final h = await _Harness.create(failAt: 'gc-contained');
      addTearDown(h.dispose);
      expect(await h.run(extra: const ['--no-dry-run']), 0);
      expect(h.stderrText, contains('state-store gc FAILED'));
      expect(
        h.events,
        containsAllInOrder(<String>['gc', 'lock', 'delegate.boot', 'runGrid']),
      );
    });

    test('throwing maintenance is loud and boot continues', () async {
      final h = await _Harness.create(failAt: 'gc');
      addTearDown(h.dispose);
      expect(await h.run(extra: const ['--no-dry-run']), 0);
      expect(h.stderrText, contains('state-store gc FAILED'));
      expect(h.stderrText, contains('boom at gc'));
      expect(
        h.events,
        containsAllInOrder(<String>['gc', 'lock', 'delegate.boot', 'runGrid']),
      );
      final gc = h.events.indexOf('gc');
      final boot = h.events.indexOf('delegate.boot');
      expect(h.events.sublist(gc, boot), isNot(contains('delegate.dispose')));
    });

    test('success pins startup and the reverse shutdown', () async {
      final h = await _Harness.create(devMode: true);
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.events, <String>[
        'inspect:earth',
        'types',
        'lock',
        'delegate.boot',
        'runGrid',
        'control',
        'lock.control',
        'devMode',
        'devMode.register',
        'lock.vm',
        'render',
        'devMode.dispose',
        'control.dispose',
        'grid.teardown',
        'sweep:earth',
        'delegate.dispose',
        'lock.release',
      ]);
      expect(h.stdoutText, contains('lunar up — resident station (runGrid)'));
      // The SHELL-owned projector reaches BOTH consumers as one instance …
      expect(h.gridProjector, isNotNull);
      expect(h.controlProjector, same(h.gridProjector));
      // … and is released by the shell's unwind (its snapshots close).
      await expectLater(h.gridProjector!.snapshots, emitsDone);
    });

    test('missing coded store skips loudly and continues', () async {
      final h = await _Harness.create(includeMissingCoded: true);
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.stdoutText, contains('lunar up: skipping coded substation'));
      expect(
        h.events,
        containsAllInOrder(<String>[
          'inspect:earth',
          'types',
          'lock',
          'delegate.boot',
        ]),
      );
    });

    test('missing appended store refuses loudly before lock', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(extra: ['--substation', 'moon=${h.missingRoot}']), 1);
      expect(h.stderrText, startsWith('lunar up:'));
      // The message BODY, not just the prefix: the operator is told which
      // seat and what remedy.
      expect(h.stderrText, contains('"moon"'));
      expect(h.stderrText, contains('has no work store'));
      expect(h.events, <String>['delegate.dispose']);
    });

    test('an empty armed roster refuses LOUD with exit 1', () async {
      // The only coded seat's root has no store and nothing is appended, so
      // NO seat arms: booting over an empty roster must refuse, not proceed.
      final h = await _Harness.create(seedWorkStore: false);
      addTearDown(h.dispose);
      expect(await h.run(), 1);
      expect(h.stdoutText, contains('skipping coded substation "earth"'));
      expect(
        h.stderrText,
        contains('no substation resolved a work store at its root.'),
      );
      expect(h.events, <String>['delegate.dispose']);
    });

    test('a malformed appended spec refuses with exit 64 before any '
        'delegate', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(extra: ['--substation', 'moon']), 64);
      expect(h.stderrText, contains('--substation "moon"'));
      expect(h.stderrText, contains('<name>[@<prefix>]=<root>'));
      expect(h.events, isEmpty);
    });

    test('lock conflict refuses before boot', () async {
      final h = await _Harness.create(failAt: 'lock');
      addTearDown(h.dispose);
      expect(await h.run(), 64);
      expect(h.events, <String>[
        'inspect:earth',
        'types',
        'lock',
        'delegate.dispose',
      ]);
      expect(h.stderrText, startsWith('lunar up:'));
    });

    test(
      'coded and appended roots are inspected in roster order before lock',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        final moon = p.join(h.temp.path, 'moon');
        seedStore(moon);
        expect(await h.run(extra: <String>['--substation', 'moon=$moon']), 0);
        expect(
          h.events,
          containsAllInOrder(<String>[
            'inspect:earth',
            'inspect:moon',
            'types',
            'lock',
          ]),
        );
        expect(
          h.stdoutText,
          contains('substations: {earth: fresh, moon: fresh}'),
        );
      },
    );

    test('every non-fresh state refuses before lock', () async {
      final cases = <PrimaryCheckoutFreshness>[
        const PrimaryCheckoutFreshness(state: PrimaryCheckoutState.unreadable),
        const PrimaryCheckoutFreshness(state: PrimaryCheckoutState.detached),
        const PrimaryCheckoutFreshness(
          state: PrimaryCheckoutState.remoteUnreadable,
          branch: 'main',
        ),
        const PrimaryCheckoutFreshness(
          state: PrimaryCheckoutState.offDefaultBranch,
          branch: 'work',
          defaultBranch: 'main',
        ),
        const PrimaryCheckoutFreshness(
          state: PrimaryCheckoutState.behind,
          branch: 'main',
          defaultBranch: 'main',
          behindBy: 5,
        ),
      ];
      for (final value in cases) {
        final h = await _Harness.create(
          checkoutFreshness: <String, PrimaryCheckoutFreshness>{'earth': value},
        );
        try {
          expect(await h.run(), 64);
          expect(h.events, <String>['inspect:earth', 'delegate.dispose']);
          expect(h.stderrText, contains(value.verdict));
          expect(h.stderrText, contains('pass --allow-stale'));
        } finally {
          await h.dispose();
        }
      }
    });

    test('multiple verdicts occupy one refusal line in roster order', () async {
      final h = await _Harness.create(
        checkoutFreshness: const <String, PrimaryCheckoutFreshness>{
          'earth': PrimaryCheckoutFreshness(
            state: PrimaryCheckoutState.behind,
            branch: 'main',
            defaultBranch: 'main',
            behindBy: 5,
          ),
          'moon': PrimaryCheckoutFreshness(
            state: PrimaryCheckoutState.detached,
          ),
        },
      );
      addTearDown(h.dispose);
      final moon = p.join(h.temp.path, 'moon');
      seedStore(moon);
      expect(await h.run(extra: <String>['--substation', 'moon=$moon']), 64);
      final lines = h.stderrText.trim().split('\n');
      expect(lines, hasLength(1));
      expect(
        lines.single,
        contains(
          '{earth: stale: 5 commits behind origin/main, '
          'moon: stale: detached HEAD}',
        ),
      );
      expect(h.events, <String>[
        'inspect:earth',
        'inspect:moon',
        'delegate.dispose',
      ]);
    });

    test(
      'allow-stale warns once with unchanged verdict and reaches lock',
      () async {
        const stale = PrimaryCheckoutFreshness(
          state: PrimaryCheckoutState.behind,
          branch: 'main',
          defaultBranch: 'main',
          behindBy: 5,
        );
        final h = await _Harness.create(
          checkoutFreshness: const <String, PrimaryCheckoutFreshness>{
            'earth': stale,
          },
        );
        addTearDown(h.dispose);
        expect(await h.run(extra: const <String>['--allow-stale']), 0);
        final warnings = h.stderrText
            .trim()
            .split('\n')
            .where((line) => line.contains('WARNING'));
        expect(warnings, hasLength(1));
        expect(warnings.single, contains('{earth: ${stale.verdict}}'));
        expect(
          h.events,
          containsAllInOrder(<String>['inspect:earth', 'types', 'lock']),
        );
      },
    );

    test('fresh banner retains mode and atomic checkout verdict', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(
        h.stdoutText,
        contains(
          'mode: DRY-RUN (observe-only)  ·  substations: {earth: fresh}',
        ),
      );
    });
  });

  group('UpCommand three-step partial failure unwind', () {
    final cases = <(String point, int code, List<String> events)>[
      (
        'boot',
        64,
        [
          'inspect:earth',
          'types',
          'lock',
          'delegate.boot',
          'delegate.dispose',
          'lock.release',
        ],
      ),
      (
        'runGrid',
        64,
        [
          'inspect:earth',
          'types',
          'lock',
          'delegate.boot',
          'runGrid',
          'delegate.dispose',
          'lock.release',
        ],
      ),
      (
        'control',
        1,
        [
          'inspect:earth',
          'types',
          'lock',
          'delegate.boot',
          'runGrid',
          'control',
          'grid.teardown',
          'sweep:earth',
          'delegate.dispose',
          'lock.release',
        ],
      ),
      (
        'devMode',
        1,
        [
          'inspect:earth',
          'types',
          'lock',
          'delegate.boot',
          'runGrid',
          'control',
          'lock.control',
          'devMode',
          'control.dispose',
          'grid.teardown',
          'sweep:earth',
          'delegate.dispose',
          'lock.release',
        ],
      ),
    ];
    for (final entry in cases) {
      test('${entry.$1} failure unwinds tree, delegate, then lock', () async {
        final h = await _Harness.create(failAt: entry.$1);
        addTearDown(h.dispose);
        expect(await h.run(), entry.$2);
        expect(h.events, entry.$3);
        expect(h.stderrText, startsWith('lunar up:'));
        // The shell released its projector on every path (snapshots close).
        await expectLater(h.gridProjector!.snapshots, emitsDone);
      });
    }

    test('a throwing checkout inspector unwinds the delegate and propagates '
        'raw — the lock was never acquired', () async {
      // Unexpected error, not a styled refusal: the probes run under a live
      // delegate that must not leak, and the error keeps its own shape.
      final h = await _Harness.create(failAt: 'inspect');
      addTearDown(h.dispose);
      await expectLater(
        h.run(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'boom at inspect',
          ),
        ),
      );
      expect(h.events, ['inspect:earth', 'delegate.dispose']);
      expect(h.built.single.disposed, isTrue);
    });

    test('a throwing VM-service probe unwinds the delegate and releases the '
        'held lock LAST, rethrowing raw', () async {
      // The probe sits between lock acquisition and the mount: a throw must
      // strand neither the delegate nor the lock file, and the release is
      // the unwind's standing tail.
      final h = await _Harness.create(failAt: 'vmService');
      addTearDown(h.dispose);
      await expectLater(
        h.run(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'boom at vmService',
          ),
        ),
      );
      expect(h.events, [
        'inspect:earth',
        'types',
        'lock',
        'delegate.dispose',
        'lock.release',
      ]);
    });

    test('an updateControl failure disposes the bound control socket '
        'first', () async {
      // The lock advertisement throws AFTER the control socket bound: the
      // unwind must close the socket, never strand it while everything
      // beneath tears down.
      final h = await _Harness.create(failAt: 'lock.control');
      addTearDown(h.dispose);
      expect(await h.run(), 1);
      expect(h.events, <String>[
        'inspect:earth',
        'types',
        'lock',
        'delegate.boot',
        'runGrid',
        'control',
        'lock.control',
        'control.dispose',
        'grid.teardown',
        'sweep:earth',
        'delegate.dispose',
        'lock.release',
      ]);
      expect(h.stderrText, startsWith('lunar up:'));
    });

    test('a dev-mode arming failure disposes the registered seat '
        'first', () async {
      // The VM-service advertisement throws AFTER the dev-mode seat armed
      // and registered: the seat is the newest resource, so it unwinds
      // first — before the control socket, the tree, and the lock.
      final h = await _Harness.create(devMode: true, failAt: 'lock.vm');
      addTearDown(h.dispose);
      expect(await h.run(), 1);
      expect(h.events, <String>[
        'inspect:earth',
        'types',
        'lock',
        'delegate.boot',
        'runGrid',
        'control',
        'lock.control',
        'devMode',
        'devMode.register',
        'lock.vm',
        'devMode.dispose',
        'control.dispose',
        'grid.teardown',
        'sweep:earth',
        'delegate.dispose',
        'lock.release',
      ]);
      expect(h.stderrText, startsWith('lunar up:'));
    });
  });

  test('a throwing control dispose is loud and never strands the teardown '
      'or the lock', () async {
    // The unwind runs each step in its own guard (teardown's rail posture):
    // the control socket's dispose blowing up must not skip the tree
    // teardown, the sweep, the delegate, the projector — or the lock release
    // at the tail.
    final h = await _Harness.create(devMode: true, failAt: 'control.dispose');
    addTearDown(h.dispose);
    expect(await h.run(), 0);
    expect(h.events.sublist(h.events.indexOf('render') + 1), <String>[
      'devMode.dispose',
      'control.dispose',
      'grid.teardown',
      'sweep:earth',
      'delegate.dispose',
      'lock.release',
    ]);
    expect(h.stderrText, contains('unwind step "control dispose" failed'));
  });

  test('run-for shutdown does not enter the signal coordinator', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.run(), 0);
    expect(h.events, isNot(contains('signal')));
    expect(h.events.sublist(h.events.indexOf('render') + 1), <String>[
      'control.dispose',
      'grid.teardown',
      'sweep:earth',
      'delegate.dispose',
      'lock.release',
    ]);
  });

  test('signal coordinator owns the untimed graceful shutdown path', () async {
    final h = await _Harness.create(signalShutdown: true);
    addTearDown(h.dispose);
    expect(await h.run(untimed: true), 0);
    expect(
      h.events,
      containsAllInOrder(<String>[
        'render',
        'signal',
        'control.dispose',
        'grid.teardown',
        'sweep:earth',
        'delegate.dispose',
        'lock.release',
      ]),
    );
    expect(h.stdoutText, contains('lunar up: shutting down…'));
  });

  test('dev mode absent neither registers, advertises, nor disposes', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.run(), 0);
    expect(h.events, contains('devMode'));
    expect(h.events, isNot(contains('devMode.register')));
    expect(h.events, isNot(contains('lock.vm')));
    expect(h.events, isNot(contains('devMode.dispose')));
  });

  group('hot restart routes the live-delegate holder at the COMMIT seam', () {
    test('a FAILED fresh boot leaves every read on the old delegate', () async {
      final h = await _Harness.create(
        devMode: true,
        holdOpen: true,
        restartBootFails: true,
      );
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      await expectLater(
        h.devHotRestart!(),
        throwsA(
          isA<GridHookError>().having((error) => error.hook, 'hook', 'boot'),
        ),
      );
      // The fresh delegate was built, booted, failed, and was disposed …
      expect(h.built, hasLength(2));
      // … and was NEVER committed: per-request reads still serve the launch
      // delegate (a desynced holder would trip the disposed-corpse tripwire
      // or answer with the fresh generation's label).
      expect(h.devReadPath!(), 'earth');

      h.release.complete();
      expect(await run, 0);
      // The final teardown's orphan sweep also ran on the OLD live delegate.
      expect(h.events, contains('sweep:earth'));
      expect(h.events, isNot(contains('sweep:gen1')));
    });

    test('a successful restart re-points reads at the fresh delegate '
        'only after its boot completed', () async {
      final h = await _Harness.create(devMode: true, holdOpen: true);
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      expect(h.devReadPath!(), 'earth');
      await h.devHotRestart!();
      expect(h.devReadPath!(), 'gen1');

      h.release.complete();
      expect(await run, 0);
      // The final sweep ran on the LIVE (fresh) delegate, not the retiree.
      expect(h.events, contains('sweep:gen1'));
      expect(h.events, isNot(contains('sweep:earth')));
    });

    test('/status renders the LIVE delegate\'s re-resolved roster, not the '
        'captured launch list', () async {
      // The dark seat's store is absent at launch (skip-coded-loudly), then
      // appears before the restart: the fresh delegate re-resolves and arms
      // it. A view closure capturing the launch-time roster would keep
      // rendering the single-seat list forever.
      final h = await _Harness.create(
        devMode: true,
        holdOpen: true,
        includeMissingCoded: true,
      );
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      expect(h.statusView!().substation, 'earth');

      seedStore(h.missingRoot);
      await h.devHotRestart!();
      expect(h.statusView!().substation, 'earth,dark');

      h.release.complete();
      expect(await run, 0);
    });

    test('a restart-time roster refusal disposes the fresh delegate and '
        'leaves every read on the live one', () async {
      final h = await _Harness.create(devMode: true, holdOpen: true);
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      // The only coded seat's store vanishes between launch and restart: the
      // factory's re-probe skips it, the roster resolves EMPTY, and the
      // refusal is thrown from the factory — before the runner ever adopts
      // the fresh delegate, so the shell must dispose it (a StateNotifier
      // with a live listener surface must never leak on the refusal path).
      Directory(p.join(h.workRoot, '.beads')).deleteSync(recursive: true);
      await expectLater(h.devHotRestart!(), throwsA(isA<StationRefusal>()));
      expect(h.built, hasLength(2));
      expect(h.built.last.disposed, isTrue);
      // The launch delegate stays live and keeps serving per-request reads.
      expect(h.devReadPath!(), 'earth');

      h.release.complete();
      expect(await run, 0);
      // ... and the final teardown's sweep still ran on the live delegate.
      expect(h.events, contains('sweep:earth'));
    });
  });

  group('absence postures (tg-at3r — STYLE.md rule 3: rendered, never '
      'thrown)', () {
    test('a delegate vending no view or handler boots; the banner and '
        '/status render the absence honestly and commands refuse with a '
        'clear message', () async {
      final h = await _Harness.create(holdOpen: true, vendsViews: false);
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      // /status reports what the shell knows first-hand and renders the
      // work axis EMPTY — zero counts, no sync baseline, not wedged.
      final status = h.statusView!();
      expect(status.substation, 'earth');
      expect(status.dryRun, isTrue);
      expect(status.ready, 0);
      expect(status.mounted, 0);
      expect(status.liveSessions, 0);
      expect(status.lastSyncAt, isNull);
      expect(status.wedge, kNotWedged);
      expect(status.sync, isEmpty);

      // POST /command refuses with a clear message — never a throw across
      // the control surface, never a silent success.
      final result = await h.controlCommandHandler!(
        const GridCommandRequest.listGates(),
      );
      expect(
        result,
        isA<GridCommandRefused>()
            .having((refusal) => refusal.code, 'code', 'unsupported')
            .having(
              (refusal) => refusal.message,
              'message',
              'this station\'s delegate vends no command handler — '
                  'POST /command is unavailable on this station.',
            ),
      );

      h.release.complete();
      expect(await run, 0);
      // The banner's stores line renders the absence, not a crash.
      expect(h.stdoutText, contains('stores: (no station view vended)'));
      expect(
        h.stdoutText,
        isNot(contains('read-path')),
        reason: 'no view — no fabricated read-path banner material',
      );
    });

    test('the dev-mode per-request reads refuse LOUD without a view — a '
        'fabricated snapshot would masquerade as a real join', () async {
      final h = await _Harness.create(
        devMode: true,
        holdOpen: true,
        vendsViews: false,
      );
      addTearDown(h.dispose);
      final run = h.run(untimed: true);
      await h.stationUp.future;

      expect(
        () => h.devReadPath!(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'this station\'s delegate vends no station view '
                '(GridDelegate.stationView is null).',
          ),
        ),
      );

      h.release.complete();
      expect(await run, 0);
    });

    test('through the REAL armDevMode stack, a null-view station arms '
        'dev mode and never fabricates a join: no baseline is captured, '
        'the graph tools render the never-joined shape, the refused '
        'refresh rides the errors stream, and the per-request read '
        'refuses LOUD', () async {
      // The default dev-mode wiring hands `armDevMode` closures that read
      // the LIVE delegate's vended view; with no view they refuse. The
      // injected-seam test above pins the refusal itself — THIS test pins
      // what the refusal renders as end-to-end through the production
      // stack: `latest` feeds the seat's graph refresh, whose refusal is
      // published on the runtime's errors stream (never thrown into the
      // boot, never a fabricated snapshot), so the graph tools serve zero
      // beads with `capturedAt: null` — distinguishable from every real
      // join, which always carries its capture time — while `readPath` is
      // read per-request and throws through to the RPC layer.
      StationView? vended; // a delegate vending no station view
      StationView requireView() =>
          vended ??
          (throw StateError(
            'this station\'s delegate vends no station view '
            '(GridDelegate.stationView is null).',
          ));
      final seat = (await armDevMode(
        vmServiceUri: 'ws://test-vm',
        hotReload: () async => const {},
        hotRestart: () async => const {},
        latest: () => requireView().latest.graph,
        readPath: () => requireView().readPathName,
      ))!;
      addTearDown(seat.dispose);

      // Arming SURVIVED the refused baseline read — and captured nothing.
      expect(seat.runtime.current, isNull);

      // The latest-backed graph tools render the honest never-joined
      // shape, not a fabricated join.
      final snapshot = await seat.host.plugin.dispatch('snapshot', const {});
      expect(snapshot['ok'], isTrue);
      final value = snapshot['value']! as Map<String, Object?>;
      expect(value['beadCount'], 0);
      expect(value['readyCount'], 0);
      expect(value['readyBeads'], isEmpty);
      expect(value['capturedAt'], isNull);

      // The refused refresh is published on the runtime's errors stream —
      // where a listener finds it — never swallowed into a thrown boot.
      final refusals = <Object>[];
      final tap = seat.runtime.errors.listen(
        (refusal) => refusals.add(refusal.error),
      );
      addTearDown(tap.cancel);
      final requery = await seat.host.plugin.dispatch('requery', const {});
      expect(requery['ok'], isTrue);
      await pumpEventQueue();
      expect(refusals, [
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('vends no station view'),
        ),
      ]);
      expect(seat.runtime.current, isNull, reason: 'still no baseline');

      // The per-request read refuses LOUD through to the RPC layer.
      expect(
        () => seat.host.plugin.observe(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'this station\'s delegate vends no station view '
                '(GridDelegate.stationView is null).',
          ),
        ),
      );
    });
  });

  group('GridDelegate lifecycle contract', () {
    test('dispose tolerates a delegate that never resolved a roster nor '
        'booted', () {
      // Five shell paths dispose never-booted (or partially-booted)
      // delegates: the restart-refusal, launch-refusal, staleness, and lock
      // paths, plus runGrid's boot-throw. The contract (class doc, step 5):
      // dispose must never assume resolveArmedRoster/boot ran.
      final delegate = _Delegate(<String>[]);
      expect(delegate.armedRoster, isEmpty);
      expect(delegate.dispose, returnsNormally);
      expect(delegate.disposed, isTrue);
    });
  });

  group('GridDelegate roster retention', () {
    test('resolveArmedRoster RETAINS the armed roster for boot', () async {
      // The one contract line a composing station's boot depends on: the
      // resolved roster is retained as `armedRoster` — what boot assembles
      // over — not merely returned to the shell.
      final temp = Directory.systemTemp.createTempSync('resident-roster-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final root = p.join(temp.path, 'earth');
      seedStore(root);
      final delegate = _Delegate(<String>[]);
      addTearDown(delegate.dispose);

      expect(delegate.armedRoster, isEmpty, reason: 'empty until resolved');
      final armed = delegate.resolveArmedRoster(
        coded: [SubstationWorkSpec(name: 'earth', root: root, prefix: 'earth')],
        appended: const [],
        onSkip: (message) => fail('nothing to skip: $message'),
      );
      expect(armed.map((seat) => seat.name), ['earth']);
      expect(delegate.armedRoster, same(armed));
      // Retained UNMODIFIABLE: boot assembles over a fixed roster.
      expect(() => delegate.armedRoster.clear(), throwsUnsupportedError);
    });
  });

  group('defaultRunMountedGrid dispose-on-failure contract', () {
    Future<GridResource> mount(_RunnerDelegate delegate) =>
        defaultRunMountedGrid(
          delegate,
          onFlushed: () {},
          orphanSweep: () async {},
          onDelegateSwapped: (_) {},
          treeProjector: null,
          delegateFactory: null,
        );

    test('boot failure: runGrid already disposed the delegate; the guard '
        'must NOT double-dispose', () async {
      final delegate = _RunnerDelegate(bootError: StateError('boom at boot'));
      await expectLater(
        mount(delegate),
        throwsA(
          isA<GridHookError>().having((error) => error.hook, 'hook', 'boot'),
        ),
      );
      expect(delegate.disposeCount, 1);
    });

    test('didLaunch failure: the guard disposes exactly once', () async {
      final delegate = _RunnerDelegate(
        didLaunchError: StateError('boom at didLaunch'),
      );
      await expectLater(
        mount(delegate),
        throwsA(
          isA<GridHookError>().having(
            (error) => error.hook,
            'hook',
            'didLaunch',
          ),
        ),
      );
      expect(delegate.disposeCount, 1);
    });

    test('mount failure (build throws): the guard disposes exactly '
        'once', () async {
      final delegate = _RunnerDelegate(buildError: StateError('boom at build'));
      await expectLater(mount(delegate), throwsA(isA<Object>()));
      expect(delegate.disposeCount, 1);
    });

    test('success: the resource mounts and its teardown sweeps on the LIVE '
        'delegate before disposing it', () async {
      final delegate = _RunnerDelegate();
      var sweepRan = false;
      final resource = await defaultRunMountedGrid(
        delegate,
        onFlushed: () {},
        // The sweep-after-dispose regression class, pinned HERE (grid_cli is
        // self-sufficient — not only in grid_sdk's track_c): the sweep reaps
        // over the boot-assembled runtime, which dispose unwinds.
        orphanSweep: () async {
          sweepRan = true;
          expect(
            delegate.disposeCount,
            0,
            reason: 'the sweep must run on the still-live delegate',
          );
        },
        onDelegateSwapped: (_) {},
        treeProjector: null,
        delegateFactory: null,
      );
      expect(delegate.disposeCount, 0);
      await resource.teardown();
      expect(sweepRan, isTrue, reason: 'teardown must run the wired sweep');
      expect(delegate.disposeCount, 1);
    });
  });
}

/// A leaf for [_RunnerDelegate.build] — an empty fan-out.
final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Drives the REAL `defaultRunMountedGrid` glue (production code, not a fake):
/// each error hook reproduces one of runGrid's failure classes so the seam's
/// dispose-on-failure contract is pinned on the shipped default.
final class _RunnerDelegate extends GridDelegate {
  _RunnerDelegate({this.bootError, this.didLaunchError, this.buildError});

  final Object? bootError;
  final Object? didLaunchError;
  final Object? buildError;

  /// How many times [dispose] ran — the contract is EXACTLY once on failure.
  var disposeCount = 0;

  @override
  void didLaunch() {
    if (didLaunchError case final error?) throw error;
  }

  @override
  Future<void> boot(GridConfiguration configuration) async {
    if (bootError case final error?) throw error;
  }

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    if (buildError case final error?) throw error;
    return const _Leaf();
  }

  @override
  StationView get stationView => throw UnimplementedError();

  @override
  GridCommandHandler get commandHandler => throw UnimplementedError();

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}
