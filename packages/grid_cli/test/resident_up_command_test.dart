import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart'
    show JoinedSnapshot, WedgeState, kNotWedged;
import 'package:grid_runtime/grid_runtime.dart'
    show PrimaryCheckoutFreshness, PrimaryCheckoutState;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _View implements ResidentStationView {
  const _View(this._label);
  final String _label;
  @override
  String get stateSubstation => 'lunar-state';
  @override
  String get readPathName => _label;
  @override
  JoinedSnapshot get latest => JoinedSnapshot.empty();
  @override
  WedgeState get wedge => kNotWedged;
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
final class _Delegate extends ResidentGridDelegate {
  _Delegate(this.events, {this.failAt, this.label = 'earth'});

  final List<String> events;
  final String? failAt;
  final String label;
  var _disposed = false;

  /// Whether [dispose] ran (the leak probes read this).
  bool get disposed => _disposed;

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('delegate.boot');
    if (failAt == 'boot') throw StateError('boom at boot');
  }

  @override
  ResidentStationView get stationView {
    // The poisoned-corpse tripwire: a per-request read reaching a DISPOSED
    // delegate is exactly the hot-restart live-holder desync bug.
    if (_disposed) {
      throw StateError('stationView read on disposed delegate "$label"');
    }
    return _View(label);
  }

  @override
  GridCommandHandler get commandHandler => _Commands();

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
  });

  static Future<_Harness> create({
    String? failAt,
    bool devMode = false,
    bool signalShutdown = false,
    bool holdOpen = false,
    bool restartBootFails = false,
    bool includeMissingCoded = false,
    bool seedWorkStore = true,
    Map<String, PrimaryCheckoutFreshness> checkoutFreshness =
        const <String, PrimaryCheckoutFreshness>{},
  }) async {
    final temp = Directory.systemTemp.createTempSync('resident-up-');
    final home = p.join(temp.path, 'home');
    final workRoot = p.join(temp.path, 'work');
    final missingRoot = p.join(temp.path, 'missing');
    _seedStore(p.join(home, '.grid'));
    if (seedWorkStore) _seedStore(workRoot);
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
  final events = <String>[];
  final _stdout = _ByteConsumer();
  final _stderr = _ByteConsumer();

  /// Every delegate the command's factory built, in construction order (the
  /// launch delegate first, hot-restart generations after).
  final built = <_Delegate>[];
  TreeProjector? gridProjector;
  TreeProjector? controlProjector;

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
    final stdoutSink = _RecordingStdout(_stdout);
    final stderrSink = _RecordingStdout(_stderr);
    _stdout.onText = (text) {
      if (!events.contains('render') && text.contains('lunar up —')) {
        events.add('render');
      }
    };
    final command = ResidentUpCommand(
      stationName: 'lunar',
      delegateFactory: ({required config}) {
        final generation = built.length;
        final delegate = _Delegate(
          events,
          failAt: generation == 0 ? failAt : (restartBootFails ? 'boot' : null),
          label: generation == 0 ? 'earth' : 'gen$generation',
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
            events.add('control');
            _throwIf('control');
            return _Control(events);
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
      readVmServiceUri: () async => 'ws://vm',
      inspectPrimaryCheckout: (seat) async {
        events.add('inspect:${seat.name}');
        return checkoutFreshness[seat.name] ??
            const PrimaryCheckoutFreshness(state: PrimaryCheckoutState.fresh);
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

final class _Lock implements ResidentLockResource {
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

final class _Grid implements ResidentGridResource {
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
  ResidentGridDelegate delegate;
  final Future<void> Function() orphanSweep;
  final ResidentGridDelegate Function()? delegateFactory;
  final void Function(ResidentGridDelegate next)? onDelegateSwapped;
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

final class _Control implements ResidentControlResource {
  _Control(this.events);
  final List<String> events;
  @override
  String get url => 'http://127.0.0.1:9999';
  @override
  Future<void> dispose() async {
    events.add('control.dispose');
  }
}

final class _DevMode implements ResidentDevModeResource {
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

final class _ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];
  void Function(String text)? onText;

  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
      onText?.call(text);
    }
  }

  @override
  Future<void> close() async {}
}

final class _RecordingStdout implements Stdout {
  _RecordingStdout(_ByteConsumer consumer) : _sink = IOSink(consumer);
  final IOSink _sink;

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  String lineTerminator = '\n';
  @override
  Future<void> get done => _sink.done;
  @override
  bool get hasTerminal => false;
  @override
  int get terminalColumns => 80;
  @override
  int get terminalLines => 24;
  @override
  bool get supportsAnsiEscapes => false;
  @override
  IOSink get nonBlocking => _sink;
  @override
  void add(List<int> data) => _sink.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> flush() => _sink.flush();
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
}

void _seedStore(String root) {
  final store = Directory(p.join(root, '.beads'))..createSync(recursive: true);
  File(
    p.join(store.path, 'metadata.json'),
  ).writeAsStringSync('{"dolt_mode":"embedded"}');
}

void main() {
  test('harness validation precedes store and delegate work', () async {
    final home = Directory.systemTemp.createTempSync('resident-up-');
    addTearDown(() => home.deleteSync(recursive: true));
    var delegateCalls = 0;
    var validations = 0;
    final command = ResidentUpCommand(
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
    final stderrBytes = _ByteConsumer();
    final stderrSink = _RecordingStdout(stderrBytes);
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
    final command = ResidentUpCommand(
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
    final source = File('lib/src/resident_up_command.dart').readAsStringSync();
    expect(source, isNot(contains('buildBuiltinEnvironmentRegistry')));
    // tg-1fa2.4: station-work assembly and the diagnostics-reporter effect
    // are boot-owned (the delegate's), never the shell's.
    expect(source, isNot(contains('assembleStationWork')));
    expect(source, isNot(contains('StationDiagnosticsReporter')));
    expect(source, isNot(contains('GhPrOpener')));
  });

  group('ResidentUpCommand assembly', () {
    test('success pins startup and the reverse shutdown', () async {
      final h = await _Harness.create(devMode: true);
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.events, <String>[
        'inspect:earth',
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
        containsAllInOrder(<String>['inspect:earth', 'lock', 'delegate.boot']),
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
      expect(h.events, <String>['inspect:earth', 'lock', 'delegate.dispose']);
      expect(h.stderrText, startsWith('lunar up:'));
    });

    test(
      'coded and appended roots are inspected in roster order before lock',
      () async {
        final h = await _Harness.create();
        addTearDown(h.dispose);
        final moon = p.join(h.temp.path, 'moon');
        _seedStore(moon);
        expect(await h.run(extra: <String>['--substation', 'moon=$moon']), 0);
        expect(
          h.events,
          containsAllInOrder(<String>['inspect:earth', 'inspect:moon', 'lock']),
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
      _seedStore(moon);
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
        expect(h.events, containsAllInOrder(<String>['inspect:earth', 'lock']));
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

  group('ResidentUpCommand three-step partial failure unwind', () {
    final cases = <(String point, int code, List<String> events)>[
      (
        'boot',
        64,
        [
          'inspect:earth',
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

  group('ResidentGridDelegate roster retention', () {
    test('resolveArmedRoster RETAINS the armed roster for boot', () async {
      // The one contract line a composing station's boot depends on: the
      // resolved roster is retained as `armedRoster` — what boot assembles
      // over — not merely returned to the shell.
      final temp = Directory.systemTemp.createTempSync('resident-roster-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final root = p.join(temp.path, 'earth');
      _seedStore(root);
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
    Future<ResidentGridResource> mount(_RunnerDelegate delegate) =>
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

    test('success: the resource mounts and its teardown disposes the '
        'delegate', () async {
      final delegate = _RunnerDelegate();
      final resource = await mount(delegate);
      expect(delegate.disposeCount, 0);
      await resource.teardown();
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
final class _RunnerDelegate extends ResidentGridDelegate {
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
  ResidentStationView get stationView => throw UnimplementedError();

  @override
  GridCommandHandler get commandHandler => throw UnimplementedError();

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}
