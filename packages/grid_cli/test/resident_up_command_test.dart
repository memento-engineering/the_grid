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
  @override
  String get stateSubstation => 'lunar-state';
  @override
  String get readPathName => 'earth';
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
/// views are canned values; dispose records the delegate's own step of the
/// three-step unwind and releases the construction-owned projector.
final class _Delegate extends ResidentGridDelegate {
  _Delegate(this.events, {this.failAt, TreeProjector? projector})
    : _projector = projector;

  final List<String> events;
  final String? failAt;
  final TreeProjector? _projector;

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('delegate.boot');
    if (failAt == 'boot') throw StateError('boom at boot');
  }

  @override
  ResidentStationView get stationView => _View();

  @override
  GridCommandHandler get commandHandler => _Commands();

  @override
  TreeProjector? get treeProjector => _projector;

  @override
  void dispose() {
    events.add('delegate.dispose');
    _projector?.dispose();
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
    required this.includeMissingCoded,
    required this.checkoutFreshness,
  });

  static Future<_Harness> create({
    String? failAt,
    bool devMode = false,
    bool signalShutdown = false,
    bool includeMissingCoded = false,
    Map<String, PrimaryCheckoutFreshness> checkoutFreshness =
        const <String, PrimaryCheckoutFreshness>{},
  }) async {
    final temp = Directory.systemTemp.createTempSync('resident-up-');
    final home = p.join(temp.path, 'home');
    final workRoot = p.join(temp.path, 'work');
    final missingRoot = p.join(temp.path, 'missing');
    _seedStore(p.join(home, '.grid'));
    _seedStore(workRoot);
    return _Harness._(
      temp: temp,
      home: home,
      workRoot: workRoot,
      missingRoot: missingRoot,
      failAt: failAt,
      devMode: devMode,
      signalShutdown: signalShutdown,
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
  final bool includeMissingCoded;
  final Map<String, PrimaryCheckoutFreshness> checkoutFreshness;
  final events = <String>[];
  final _stdout = _ByteConsumer();
  final _stderr = _ByteConsumer();
  final projector = TreeProjector();
  TreeProjector? gridProjector;
  TreeProjector? controlProjector;

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
      delegateFactory: ({required config}) =>
          _Delegate(events, failAt: failAt, projector: projector),
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
            return _Lock(events);
          },
      runMountedGrid:
          (
            delegate, {
            required onFlushed,
            required orphanSweep,
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
            return _Grid(events, delegate);
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
  _Lock(this.events);
  final List<String> events;

  @override
  String get path => '/fake/station.lock';

  @override
  Future<void> updateControl({
    required String controlUrl,
    required String token,
  }) async {
    events.add('lock.control');
  }

  @override
  Future<void> updateVmService(String vmServiceUri) async {
    events.add('lock.vm');
  }

  @override
  Future<void> release() async {
    events.add('lock.release');
  }
}

final class _Grid implements ResidentGridResource {
  _Grid(this.events, this.delegate);
  final List<String> events;
  final ResidentGridDelegate delegate;

  @override
  Future<ReassembleReport> hotReload() => throw UnimplementedError();
  @override
  Future<ReassembleReport> hotRestart() => throw UnimplementedError();
  @override
  Future<void> teardown() async {
    // The three-step unwind's first two steps, in runGrid's own teardown
    // order: unmount the tree, THEN dispose the delegate.
    events.add('grid.teardown');
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
    expect(await runner.run(['up', '--grid-home', home.path]), 64);
    expect(validations, 1);
    expect(delegateCalls, 0);
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
    test('success pins startup and the three-step reverse shutdown', () async {
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
        'delegate.dispose',
        'lock.release',
      ]);
      expect(h.stdoutText, contains('lunar up — resident station (runGrid)'));
      // The delegate's construction-owned projector reaches BOTH consumers …
      expect(h.gridProjector, same(h.projector));
      expect(h.controlProjector, same(h.projector));
      // … and is released by the delegate's dispose (its snapshots close).
      await expectLater(h.projector.snapshots, emitsDone);
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
      expect(h.events, <String>['delegate.dispose']);
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
        // The delegate went down on every path, so its construction-owned
        // projector is released.
        await expectLater(h.projector.snapshots, emitsDone);
      });
    }
  });

  test('run-for shutdown does not enter the signal coordinator', () async {
    final h = await _Harness.create();
    addTearDown(h.dispose);
    expect(await h.run(), 0);
    expect(h.events, isNot(contains('signal')));
    expect(h.events.sublist(h.events.indexOf('render') + 1), <String>[
      'control.dispose',
      'grid.teardown',
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
}
