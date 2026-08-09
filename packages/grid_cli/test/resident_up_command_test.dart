import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_engine/grid_engine.dart'
    show JoinedSnapshot, SessionProjection, StepMount, WedgeState, kNotWedged;
import 'package:grid_runtime/grid_runtime.dart'
    show PrimaryCheckoutFreshness, PrimaryCheckoutState, StationGitService;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Resolver implements SessionResolver {
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      throw UnimplementedError();
}

class _Registry implements CapabilityRegistry {
  @override
  Circuit? circuit(String circuitId) => null;

  @override
  Seed host(StepMount mount) => throw UnimplementedError();

  @override
  DateTime now() => DateTime.utc(2026);
}

final class _Delegate extends GridDelegate {
  _Delegate(this._root);
  final String _root;

  @override
  String get root => _root;
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
  ExplorationTransport? transport;
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
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) => _Delegate(config.gridHome),
      codedRoster: ({required gridHome}) => [
        SubstationWorkSpec(name: 'earth', root: workRoot, prefix: 'earth'),
        if (includeMissingCoded)
          SubstationWorkSpec(name: 'dark', root: missingRoot, prefix: 'dark'),
      ],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
      resolver: _Resolver(),
      registry: _Registry(),
      acquireLock:
          ({required stateWorkspaceDir, required pid, required now}) async {
            events.add('lock');
            if (failAt == 'lock') {
              throw const StationRefusal('held', code: 64);
            }
            return _Lock(events);
          },
      buildWork:
          ({
            required stateStore,
            required substations,
            required resolver,
            required registry,
            required dryRun,
            required maxConcurrentWork,
            required transport,
          }) async {
            this.transport = transport;
            events.add('assembleStationWork');
            _throwIf('assembleStationWork');
            return _Work(events, failAt);
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
            events.add('runGrid');
            _throwIf('runGrid');
            return _Grid(events);
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

final class _Work implements ResidentWorkResource {
  _Work(this.events, this.failAt);
  final List<String> events;
  final String? failAt;

  @override
  StationWorkWiring get wiring => _Wiring();
  @override
  Map<String, Object?> syncStatus() => const <String, Object?>{};
  @override
  GridCommandHandler get commands => _Commands();
  @override
  StationGitService get git => _Git();
  @override
  String get stateSubstation => 'lunar-state';
  @override
  String get readPathName => 'earth';
  @override
  JoinedSnapshot get latest => JoinedSnapshot.empty();
  @override
  WedgeState get wedge => kNotWedged;

  @override
  Future<void> start() async {
    events.add('work.start');
    if (failAt == 'work.start') {
      throw StateError('boom at work.start');
    }
  }

  @override
  void afterFlush() {}
  @override
  Future<void> sweepOrphans() async {}
  @override
  Future<void> shutdown() async {
    events.add('work.shutdown');
  }
}

final class _Wiring implements StationWorkWiring {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Git implements StationGitService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Commands implements GridCommandHandler {
  @override
  Future<GridCommandResult> call(GridCommandRequest request) =>
      throw UnimplementedError();
}

final class _Grid implements ResidentGridResource {
  _Grid(this.events);
  final List<String> events;

  @override
  Future<ReassembleReport> hotReload() => throw UnimplementedError();
  @override
  Future<ReassembleReport> hotRestart() => throw UnimplementedError();
  @override
  Future<void> teardown() async {
    events.add('grid.teardown');
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
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) {
            delegateCalls++;
            throw UnimplementedError();
          },
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (name) {
        validations++;
        return 'not configured';
      },
      resolver: _Resolver(),
      registry: _Registry(),
    );
    final runner = CommandRunner<int>('lunar', 'test')..addCommand(command);
    expect(await runner.run(['up', '--grid-home', home.path]), 64);
    expect(validations, 1);
    expect(delegateCalls, 0);
  });

  test('safe dry-run is the parser default and no bead option exists', () {
    final command = ResidentUpCommand(
      stationName: 'lunar',
      delegateFactory:
          ({
            required config,
            required wiring,
            required provisioner,
            required gitOps,
            required prOpener,
          }) => throw UnimplementedError(),
      codedRoster: ({required gridHome}) => const [],
      harnessAllowList: const {'safe'},
      validateHarness: (_) => null,
      resolver: _Resolver(),
      registry: _Registry(),
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

  test('assembly never references a builtin environment registry', () {
    final source = File('lib/src/resident_up_command.dart').readAsStringSync();
    expect(source, isNot(contains('buildBuiltinEnvironmentRegistry')));
  });

  group('ResidentUpCommand assembly', () {
    test('success pins startup and reverse shutdown order', () async {
      final h = await _Harness.create(devMode: true);
      addTearDown(h.dispose);
      expect(await h.run(), 0);
      expect(h.events, <String>[
        'inspect:earth',
        'lock',
        'assembleStationWork',
        'work.start',
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
        'work.shutdown',
        'lock.release',
      ]);
      expect(h.stdoutText, contains('lunar up — resident station (runGrid)'));
      expect(h.transport, isA<StationDiagnosticsReporter>());
      final reporter = h.transport! as StationDiagnosticsReporter;
      expect(h.gridProjector, same(reporter.treeProjector));
      expect(h.controlProjector, same(reporter.treeProjector));
      reporter.flare('station.wedged', <String, String>{'gated': '2'});
      expect(jsonDecode(h.stderrText.trim()), <String, Object?>{
        'type': 'flare',
        'name': 'station.wedged',
        'data': <String, Object?>{'gated': '2'},
      });
      await expectLater(reporter.treeProjector.snapshots, emitsDone);
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
          'lock',
          'assembleStationWork',
        ]),
      );
    });

    test('missing appended store refuses loudly before lock', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      expect(await h.run(extra: ['--substation', 'moon=${h.missingRoot}']), 1);
      expect(h.stderrText, startsWith('lunar up:'));
      expect(h.events, isEmpty);
    });

    test('lock conflict refuses before build', () async {
      final h = await _Harness.create(failAt: 'lock');
      addTearDown(h.dispose);
      expect(await h.run(), 64);
      expect(h.events, <String>['inspect:earth', 'lock']);
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
          expect(h.events, <String>['inspect:earth']);
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
      expect(h.events, <String>['inspect:earth', 'inspect:moon']);
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

  group('ResidentUpCommand partial failure unwind', () {
    final cases = <(String point, int code, List<String> events)>[
      (
        'assembleStationWork',
        1,
        ['inspect:earth', 'lock', 'assembleStationWork', 'lock.release'],
      ),
      (
        'work.start',
        1,
        [
          'inspect:earth',
          'lock',
          'assembleStationWork',
          'work.start',
          'work.shutdown',
          'lock.release',
        ],
      ),
      (
        'runGrid',
        64,
        [
          'inspect:earth',
          'lock',
          'assembleStationWork',
          'work.start',
          'runGrid',
          'work.shutdown',
          'lock.release',
        ],
      ),
      (
        'control',
        1,
        [
          'inspect:earth',
          'lock',
          'assembleStationWork',
          'work.start',
          'runGrid',
          'control',
          'grid.teardown',
          'work.shutdown',
          'lock.release',
        ],
      ),
      (
        'devMode',
        1,
        [
          'inspect:earth',
          'lock',
          'assembleStationWork',
          'work.start',
          'runGrid',
          'control',
          'lock.control',
          'devMode',
          'control.dispose',
          'grid.teardown',
          'work.shutdown',
          'lock.release',
        ],
      ),
    ];
    for (final entry in cases) {
      test(
        '${entry.$1} failure cleans acquired resources in reverse',
        () async {
          final h = await _Harness.create(failAt: entry.$1);
          addTearDown(h.dispose);
          expect(await h.run(), entry.$2);
          expect(h.events, entry.$3);
          expect(h.stderrText, startsWith('lunar up:'));
          final reporter = h.transport! as StationDiagnosticsReporter;
          await expectLater(reporter.treeProjector.snapshots, emitsDone);
        },
      );
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
      'work.shutdown',
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
        'work.shutdown',
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
