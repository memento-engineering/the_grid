import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _ConstructionFailure implements Exception {
  const _ConstructionFailure();
}

final class _NullResolver implements SessionResolver {
  const _NullResolver();

  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('not reached');
}

final class _RecordingProvider extends DryRunProvider {
  _RecordingProvider(this.record, {this.throwOnFirstDispose = false});

  final List<String> record;
  final bool throwOnFirstDispose;
  var disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    record.add('runtime provider dispose');
    if (throwOnFirstDispose && disposeCalls == 1) {
      throw StateError('provider dispose exploded');
    }
    await super.dispose();
  }
}

final class _RecordingFederatedSource extends FederatedSnapshotSource {
  _RecordingFederatedSource(this.events)
    : _recordingSnapshots = StreamController<GraphSnapshot>.broadcast(
        onCancel: () => events.add('join bridge dispose'),
      ),
      super(const <String, SnapshotSource>{});

  final List<String> events;
  final StreamController<GraphSnapshot> _recordingSnapshots;
  var disposeCalls = 0;

  @override
  Stream<GraphSnapshot> get snapshots => _recordingSnapshots.stream;

  @override
  Future<void> dispose() async {
    if (disposeCalls != 0) return;
    disposeCalls++;
    events.add('federated source dispose');
    await super.dispose();
    await _recordingSnapshots.close();
  }
}

final class _ThrowingRecordingDriver extends StationDriver {
  _ThrowingRecordingDriver({
    required StationJoinBridge bridge,
    required this.events,
  }) : super(bridge: bridge) {
    // Follow the real bridge so its fallback disposal is independently
    // observable when this fake's disposal refuses before delegating to it.
    bridge.start();
  }

  final List<String> events;
  var disposeCalls = 0;

  @override
  void dispose() {
    disposeCalls++;
    events.add('station driver dispose');
    throw StateError('driver dispose exploded');
  }
}

final class _ByteConsumer implements StreamConsumer<List<int>> {
  final _bytes = <int>[];

  String get text => utf8.decode(_bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

final class _RecordingStderr implements Stdout {
  _RecordingStderr(_ByteConsumer consumer) : _sink = IOSink(consumer);

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

void _seedStore(String dir, {required String database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File(
    '$dir/.beads/metadata.json',
  ).writeAsStringSync('{"dolt_mode":"embedded","dolt_database":"$database"}');
}

Future<TrajectoryHarness> _recordingTrajectory(List<String> events) async {
  final harness = await TrajectoryHarness.build(
    config: const TrajectoryConfig(mode: TrajectoryConfigMode.required),
    gridHome: '/unwind-test',
    station: 'state',
    connect: () async => throw StateError('offline test trajectory'),
    onFlare: (name, _) => events.add(name),
  );
  await harness.start();
  return harness;
}

Future<GridRuntimeBundle> _recordingBundle({
  required String root,
  required String substation,
  required String event,
  required List<String> events,
}) async {
  final owned = await GridRuntimeFactory.build(
    workspace: BeadsWorkspace.discover(start: root)!,
    preferSql: false,
    runner: NoOpBdRunner(substation: substation),
  );
  var shutdown = false;
  return GridRuntimeBundle(
    runtime: owned.runtime,
    probeReader: owned.probeReader,
    readPath: owned.readPath,
    dolt: owned.dolt,
    shutdown: () async {
      if (shutdown) return;
      shutdown = true;
      events.add(event);
      await owned.shutdown();
    },
  );
}

void main() {
  group('settle', () {
    test('runs synchronous and asynchronous actions once', () async {
      var synchronousCalls = 0;
      var asynchronousCalls = 0;

      expect(await settle('synchronous', () => synchronousCalls++), isTrue);
      expect(
        await settle('asynchronous', () async {
          await Future<void>.delayed(Duration.zero);
          asynchronousCalls++;
        }),
        isTrue,
      );
      expect(synchronousCalls, 1);
      expect(asynchronousCalls, 1);
    });

    test('reports throwing and timed-out actions without throwing', () async {
      final refusals = <String>[];
      final never = Completer<void>();
      var continued = false;

      expect(
        await settle(
          'throwing',
          () => throw StateError('exploded'),
          onRefusal: refusals.add,
        ),
        isFalse,
      );
      expect(
        await settle(
          'timed out',
          () => never.future,
          within: const Duration(milliseconds: 5),
          onRefusal: refusals.add,
        ),
        isFalse,
      );
      expect(
        await settle(
          'asynchronous throwing',
          () async => throw StateError('async exploded'),
          onRefusal: refusals.add,
        ),
        isFalse,
      );
      expect(await settle('continued', () => continued = true), isTrue);
      expect(refusals, [
        'unwind step "throwing" failed: Bad state: exploded',
        startsWith(
          'unwind step "timed out" failed: TimeoutException after 0:00:00.005000',
        ),
        'unwind step "asynchronous throwing" failed: '
            'Bad state: async exploded',
      ]);
      expect(continued, isTrue);

      final bytes = _ByteConsumer();
      final capturedStderr = _RecordingStderr(bytes);
      await IOOverrides.runZoned(
        () => settle('default sink', () => throw StateError('stderr refusal')),
        stderr: () => capturedStderr,
      );
      await capturedStderr.flush();
      expect(
        bytes.text,
        'unwind step "default sink" failed: Bad state: stderr refusal\n',
      );
    });
  });

  group('station work ownership', () {
    late Directory temporary;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('assembly-unwind-');
      _seedStore('${temporary.path}/first', database: 'first');
      _seedStore('${temporary.path}/second', database: 'second');
      _seedStore('${temporary.path}/home/.grid', database: 'state');
    });

    tearDown(() => temporary.deleteSync(recursive: true));

    Future<void> failAssembly({
      required _RecordingProvider provider,
      required TrajectoryHarness trajectory,
      required Object failure,
      required StackTrace stackTrace,
      required List<String> events,
      Map<String, GridRuntimeBundle> workBundleOverrides = const {},
      GridRuntimeBundle? stateBundleOverride,
      FederatedSnapshotSource? federatedSourceOverride,
      void Function(String message)? onRefusal,
    }) => assembleStationWork(
      stateStore: GridStateStore.forGridRoot('${temporary.path}/home'),
      substations: [
        SubstationWorkSpec(name: 'first', root: '${temporary.path}/first'),
        SubstationWorkSpec(name: 'second', root: '${temporary.path}/second'),
      ],
      resolver: const _NullResolver(),
      dryRun: true,
      preferSql: false,
      providerOverride: provider,
      trajectoryOverride: trajectory,
      workBundleOverrides: workBundleOverrides,
      stateBundleOverride: stateBundleOverride,
      federatedSourceOverride: federatedSourceOverride,
      onRefusal: onRefusal,
      registryBuilder: (_) {
        events.add('construction failure');
        Error.throwWithStackTrace(failure, stackTrace);
      },
    );

    test(
      'construction failures unwind acquired resources in reverse',
      () async {
        final events = <String>[];
        final provider = _RecordingProvider(events);
        final trajectory = await _recordingTrajectory(events);
        events.clear();

        await expectLater(
          failAssembly(
            provider: provider,
            trajectory: trajectory,
            failure: const _ConstructionFailure(),
            stackTrace: StackTrace.current,
            events: events,
          ),
          throwsA(isA<_ConstructionFailure>()),
        );

        expect(events, [
          'construction failure',
          'trajectory.shutdown',
          'runtime provider dispose',
        ]);
        expect(provider.disposeCalls, 1);
      },
    );

    test(
      'construction failures unwind all acquired resource classes in strict reverse order',
      () async {
        final events = <String>[];
        final workBundles = <String, GridRuntimeBundle>{
          'first': await _recordingBundle(
            root: '${temporary.path}/first',
            substation: 'first',
            event: 'work bundle shutdown (first)',
            events: events,
          ),
          'second': await _recordingBundle(
            root: '${temporary.path}/second',
            substation: 'second',
            event: 'work bundle shutdown (second)',
            events: events,
          ),
        };
        final stateBundle = await _recordingBundle(
          root: '${temporary.path}/home/.grid',
          substation: 'state',
          event: 'state bundle shutdown',
          events: events,
        );
        final federated = _RecordingFederatedSource(events);
        final provider = _RecordingProvider(events);
        final trajectory = await _recordingTrajectory(events);
        events.clear();

        await expectLater(
          failAssembly(
            provider: provider,
            trajectory: trajectory,
            failure: const _ConstructionFailure(),
            stackTrace: StackTrace.current,
            events: events,
            workBundleOverrides: workBundles,
            stateBundleOverride: stateBundle,
            federatedSourceOverride: federated,
          ),
          throwsA(isA<_ConstructionFailure>()),
        );

        expect(events, [
          'construction failure',
          'trajectory.shutdown',
          'runtime provider dispose',
          'federated source dispose',
          'state bundle shutdown',
          'work bundle shutdown (second)',
          'work bundle shutdown (first)',
        ]);
        expect(provider.disposeCalls, 1);
        expect(federated.disposeCalls, 1);
      },
    );

    test(
      'construction unwind settles every disposer and preserves the original error',
      () async {
        final events = <String>[];
        final refusals = <String>[];
        final workBundles = <String, GridRuntimeBundle>{
          'first': await _recordingBundle(
            root: '${temporary.path}/first',
            substation: 'first',
            event: 'work bundle shutdown (first)',
            events: events,
          ),
          'second': await _recordingBundle(
            root: '${temporary.path}/second',
            substation: 'second',
            event: 'work bundle shutdown (second)',
            events: events,
          ),
        };
        final stateBundle = await _recordingBundle(
          root: '${temporary.path}/home/.grid',
          substation: 'state',
          event: 'state bundle shutdown',
          events: events,
        );
        final federated = _RecordingFederatedSource(events);
        final provider = _RecordingProvider(events, throwOnFirstDispose: true);
        final trajectory = await _recordingTrajectory(events);
        events.clear();
        const failure = _ConstructionFailure();
        final originalStack = StackTrace.current;

        Object? caught;
        StackTrace? caughtStack;
        try {
          await failAssembly(
            provider: provider,
            trajectory: trajectory,
            failure: failure,
            stackTrace: originalStack,
            events: events,
            onRefusal: refusals.add,
            workBundleOverrides: workBundles,
            stateBundleOverride: stateBundle,
            federatedSourceOverride: federated,
          );
        } on Object catch (error, stackTrace) {
          caught = error;
          caughtStack = stackTrace;
        }

        expect(caught, same(failure));
        expect('$caughtStack', '$originalStack');
        expect(provider.disposeCalls, 1);
        expect(refusals, [
          'unwind step "runtime provider dispose" failed: '
              'Bad state: provider dispose exploded',
        ]);
        expect(events, [
          'construction failure',
          'trajectory.shutdown',
          'runtime provider dispose',
          'federated source dispose',
          'state bundle shutdown',
          'work bundle shutdown (second)',
          'work bundle shutdown (first)',
        ]);
        expect(federated.disposeCalls, 1);

        await provider.dispose();
      },
    );

    test(
      'shutdown settles throwing driver and admission disposers once',
      () async {
        final calls = <String>[];
        final refusals = <String>[];
        var shutdown = false;

        Future<void> shutdownOnce() async {
          if (shutdown) return;
          shutdown = true;
          final steps = <({String name, FutureOr<void> Function() action})>[
            (
              name: 'station driver dispose',
              action: () {
                calls.add('station driver dispose');
                throw StateError('driver exploded');
              },
            ),
            (
              name: 'join bridge dispose',
              action: () => calls.add('join bridge dispose'),
            ),
            (
              name: 'station admission dispose',
              action: () {
                calls.add('station admission dispose');
                throw StateError('admission exploded');
              },
            ),
            (
              name: 'trajectory shutdown',
              action: () async => calls.add('trajectory shutdown'),
            ),
            (
              name: 'state bundle shutdown',
              action: () async => calls.add('state bundle shutdown'),
            ),
            (
              name: 'work bundle shutdown (first)',
              action: () async => calls.add('work bundle shutdown (first)'),
            ),
            (
              name: 'federated source dispose',
              action: () async => calls.add('federated source dispose'),
            ),
          ];
          for (final step in steps) {
            await settle(step.name, step.action, onRefusal: refusals.add);
          }
        }

        await shutdownOnce();
        await shutdownOnce();

        expect(calls, [
          'station driver dispose',
          'join bridge dispose',
          'station admission dispose',
          'trajectory shutdown',
          'state bundle shutdown',
          'work bundle shutdown (first)',
          'federated source dispose',
        ]);
        expect(refusals, [
          'unwind step "station driver dispose" failed: '
              'Bad state: driver exploded',
          'unwind step "station admission dispose" failed: '
              'Bad state: admission exploded',
        ]);
      },
    );

    test(
      'real StationWorkRuntime shutdown settles a throwing driver and runs every teardown once',
      () async {
        final events = <String>[];
        final refusals = <String>[];
        final workBundles = <String, GridRuntimeBundle>{
          'first': await _recordingBundle(
            root: '${temporary.path}/first',
            substation: 'first',
            event: 'work bundle shutdown (first)',
            events: events,
          ),
          'second': await _recordingBundle(
            root: '${temporary.path}/second',
            substation: 'second',
            event: 'work bundle shutdown (second)',
            events: events,
          ),
        };
        final stateBundle = await _recordingBundle(
          root: '${temporary.path}/home/.grid',
          substation: 'state',
          event: 'state bundle shutdown',
          events: events,
        );
        final federated = _RecordingFederatedSource(events);
        final provider = _RecordingProvider(events);
        final trajectory = await _recordingTrajectory(events);
        late _ThrowingRecordingDriver driver;
        final runtime = await assembleStationWork(
          stateStore: GridStateStore.forGridRoot('${temporary.path}/home'),
          substations: [
            SubstationWorkSpec(name: 'first', root: '${temporary.path}/first'),
            SubstationWorkSpec(
              name: 'second',
              root: '${temporary.path}/second',
            ),
          ],
          resolver: const _NullResolver(),
          dryRun: true,
          preferSql: false,
          providerOverride: provider,
          trajectoryOverride: trajectory,
          workBundleOverrides: workBundles,
          stateBundleOverride: stateBundle,
          federatedSourceOverride: federated,
          driverOverride: (bridge) =>
              driver = _ThrowingRecordingDriver(bridge: bridge, events: events),
          onRefusal: refusals.add,
        );
        events.clear();

        await runtime.shutdown();
        await runtime.shutdown();

        expect(events, [
          'station driver dispose',
          'join bridge dispose',
          'trajectory.shutdown',
          'runtime provider dispose',
          'state bundle shutdown',
          'work bundle shutdown (first)',
          'work bundle shutdown (second)',
          'federated source dispose',
        ]);
        expect(refusals, [
          'unwind step "station driver dispose" failed: '
              'Bad state: driver dispose exploded',
        ]);
        expect(driver.disposeCalls, 1);
        expect(provider.disposeCalls, 1);
        expect(federated.disposeCalls, 1);
      },
    );

    test('public assembly signature and acquisition order stay pinned', () {
      final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
      final signatureStart = source.indexOf(
        'Future<StationWorkRuntime> assembleStationWork({',
      );
      final signatureEnd = source.indexOf('}) async {', signatureStart);
      final signature = source.substring(signatureStart, signatureEnd);
      final parameters = RegExp(
        r'\b(\w+)(?:\s*=.*)?,$',
        multiLine: true,
      ).allMatches(signature).map((match) => match.group(1)).toList();
      expect(parameters, [
        'stateStore',
        'substations',
        'resolver',
        'dryRun',
        'registry',
        'registryBuilder',
        'maxConcurrentWork',
        'preferSql',
        'providerOverride',
        'gitOverride',
        'stateBdOverride',
        'workBdOverrides',
        'groupsOverride',
        'onRefusal',
        'onOrphan',
        'onUnresolvedExternalDep',
        'transport',
        'wedgeThreshold',
        'wedgePollInterval',
        'syncFloorInterval',
        'trajectoryConfig',
        'trajectoryOverride',
        'workBundleOverrides',
        'stateBundleOverride',
        'federatedSourceOverride',
        'driverOverride',
      ]);

      final assembly = source.substring(signatureStart);
      var cursor = 0;
      for (final acquisition in [
        'workBundleOverrides[storeName] ??',
        'GridRuntimeFactory.build(',
        "step: 'work bundle shutdown (\${entry.key})'",
        'stateBundleOverride ??',
        'GridRuntimeFactory.build(',
        "step: 'state bundle shutdown'",
        'federatedSourceOverride ??',
        'FederatedSnapshotSource(',
        "step: 'federated source dispose'",
        'providerOverride ??',
        "step: 'runtime provider dispose'",
        'TrajectoryHarness.build(',
        "step: 'trajectory shutdown'",
        'git.registerRootCheckout(',
        'groupsOverride ??',
        'StationServices(',
        "step: 'station admission dispose'",
        'StationJoinBridge(',
        "step: 'join bridge dispose'",
        'driverOverride?.call(bridge) ??',
        'StationDriver(',
        "step: 'station driver dispose'",
      ]) {
        final next = assembly.indexOf(acquisition, cursor);
        expect(next, greaterThanOrEqualTo(cursor), reason: acquisition);
        cursor = next + acquisition.length;
      }
    });
  });
}
