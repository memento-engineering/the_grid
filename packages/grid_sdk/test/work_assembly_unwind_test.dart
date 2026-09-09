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

final class _EmptySnapshotReader implements SnapshotReader {
  const _EmptySnapshotReader();

  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime.utc(2026, 9, 9),
  );
}

final class _EmptyBeadProbeReader implements BeadProbeReader {
  const _EmptyBeadProbeReader();

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

final class _GatedGridControllerRuntime extends GridControllerRuntime {
  _GatedGridControllerRuntime({
    required this.label,
    required List<String> events,
    this.startGate,
  }) : record = events,
       super(reader: const _EmptySnapshotReader(), dirtySources: const []);

  final String label;
  final List<String> record;
  final Completer<void>? startGate;
  final Completer<void> startEntered = Completer<void>();
  var startCalls = 0;
  var requeryCalls = 0;
  var disposeCalls = 0;

  @override
  Future<void> start() async {
    startCalls++;
    record.add('$label source start');
    if (!startEntered.isCompleted) startEntered.complete();
    final gate = startGate;
    if (gate != null) await gate.future;
    await super.start();
  }

  @override
  Future<void> requery() {
    requeryCalls++;
    record.add('$label freshness barrier');
    return super.requery();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}

GridRuntimeBundle _controllerBundle({
  required _GatedGridControllerRuntime runtime,
  required List<String> events,
  required String shutdownEvent,
}) {
  var shutdown = false;
  return GridRuntimeBundle(
    runtime: runtime,
    probeReader: const _EmptyBeadProbeReader(),
    readPath: ReadPath.cli,
    shutdown: () async {
      if (shutdown) return;
      shutdown = true;
      events.add(shutdownEvent);
      await runtime.dispose();
    },
  );
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

final class _RecordingJoinBridge implements StationJoinBridge {
  factory _RecordingJoinBridge(List<String> events) {
    final latest = JoinedSnapshot.empty();
    return _RecordingJoinBridge._(events, latest);
  }

  _RecordingJoinBridge._(this.events, this._latest)
    : notifier = JoinedSnapshotNotifier(_latest);

  final List<String> events;

  @override
  final JoinedSnapshotNotifier notifier;

  final JoinedSnapshot _latest;
  bool _started = false;
  bool _disposed = false;
  var startCalls = 0;
  var disposeCalls = 0;

  @override
  JoinedSnapshot get latest => _latest;

  @override
  void start() {
    if (_started || _disposed) return;
    _started = true;
    startCalls++;
  }

  @override
  void repush() {
    if (_disposed) return;
    notifier.push(_latest);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disposeCalls++;
    events.add('join bridge dispose');
    notifier.dispose();
  }
}

final class _RecordingStartDriver extends StationDriver {
  _RecordingStartDriver({required super.bridge, required this.events});

  final List<String> events;
  var startCalls = 0;
  var disposeCalls = 0;

  @override
  void start() {
    startCalls++;
    events.add('station driver start');
    super.start();
  }

  @override
  void dispose() {
    disposeCalls++;
    events.add('station driver dispose');
    super.dispose();
  }
}

final class _StartThrowingRecordingDriver extends StationDriver {
  _StartThrowingRecordingDriver({
    required super.bridge,
    required this.events,
    required this.error,
    required this.stackTrace,
  });

  final List<String> events;
  final Object error;
  final StackTrace stackTrace;
  var startCalls = 0;
  var disposeCalls = 0;

  @override
  void start() {
    startCalls++;
    events.add('station driver start');
    Error.throwWithStackTrace(error, stackTrace);
  }

  @override
  void dispose() {
    disposeCalls++;
    events.add('station driver dispose');
    super.dispose();
  }
}

final class _ThrowingRecordingDriver extends StationDriver {
  _ThrowingRecordingDriver({required super.bridge, required this.events});

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

Future<TrajectoryHarness> _recordingTrajectory(
  List<String> events, {
  TrajectoryConfig config = const TrajectoryConfig(
    mode: TrajectoryConfigMode.required,
  ),
}) async {
  final harness = await TrajectoryHarness.build(
    config: config,
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
      StationWorkBundleBuilder? bundleBuilder,
      StationWorkFederatedSourceBuilder? federatedSourceBuilder,
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
      bundleBuilder: bundleBuilder,
      federatedSourceBuilder: federatedSourceBuilder,
      onRefusal: onRefusal,
      registryBuilder: (_) {
        events.add('construction failure');
        Error.throwWithStackTrace(failure, stackTrace);
      },
    );

    Future<StationWorkRuntime> assembleRecordingRuntime({
      required GridRuntimeBundle workBundle,
      required GridRuntimeBundle stateBundle,
      required _RecordingProvider provider,
      required TrajectoryHarness trajectory,
      required _RecordingFederatedSource federated,
      required _RecordingJoinBridge bridge,
      required StationWorkDriverBuilder driverBuilder,
      TrajectoryConfig trajectoryConfig = const TrajectoryConfig(),
    }) => assembleStationWork(
      stateStore: GridStateStore.forGridRoot('${temporary.path}/home'),
      substations: [
        SubstationWorkSpec(name: 'first', root: '${temporary.path}/first'),
      ],
      resolver: const _NullResolver(),
      dryRun: true,
      preferSql: false,
      providerOverride: provider,
      trajectoryConfig: trajectoryConfig,
      trajectoryOverride: trajectory,
      bundleBuilder:
          ({
            required storeName,
            required workspace,
            required buildDefault,
          }) async => storeName == 'state' ? stateBundle : workBundle,
      federatedSourceBuilder: ({required buildDefault}) => federated,
      joinBridgeBuilder: ({required buildDefault}) => bridge,
      driverBuilder: driverBuilder,
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
            bundleBuilder:
                ({
                  required storeName,
                  required workspace,
                  required buildDefault,
                }) async => storeName == 'state'
                ? stateBundle
                : workBundles[storeName]!,
            federatedSourceBuilder: ({required buildDefault}) => federated,
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
            bundleBuilder:
                ({
                  required storeName,
                  required workspace,
                  required buildDefault,
                }) async => storeName == 'state'
                ? stateBundle
                : workBundles[storeName]!,
            federatedSourceBuilder: ({required buildDefault}) => federated,
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

    test('cut refusal records the failed stage and original error', () async {
      final events = <String>[];
      final workSource = _GatedGridControllerRuntime(
        label: 'work',
        events: events,
      );
      final stateSource = _GatedGridControllerRuntime(
        label: 'state',
        events: events,
      );
      final workBundle = _controllerBundle(
        runtime: workSource,
        events: events,
        shutdownEvent: 'work bundle shutdown (first)',
      );
      final stateBundle = _controllerBundle(
        runtime: stateSource,
        events: events,
        shutdownEvent: 'state bundle shutdown',
      );
      final provider = _RecordingProvider(events);
      final trajectory = await _recordingTrajectory(
        events,
        config: const TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
          dualRead: DualReadMode.observe,
        ),
      );
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      late _RecordingStartDriver driver;
      final runtime = await assembleRecordingRuntime(
        workBundle: workBundle,
        stateBundle: stateBundle,
        provider: provider,
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        driverBuilder: ({required buildDefault}) =>
            driver = _RecordingStartDriver(bridge: bridge, events: events),
      );
      addTearDown(runtime.shutdown);

      Object? caught;
      StackTrace? caughtStack;
      try {
        await runtime.start();
      } on Object catch (error, stackTrace) {
        caught = error;
        caughtStack = stackTrace;
      }

      expect(caught, isA<CutPostureRefused>());
      final failure = runtime.lifecycle as StationWorkRuntimeFailed;
      expect(failure.stage, StationWorkStartStage.cutPostureCheck);
      expect(failure.error, same(caught));
      expect(failure.stackTrace, same(caughtStack));
      expect(driver.startCalls, 0);
    });

    test('start exposes sources progress and successful idempotence', () async {
      final events = <String>[];
      final sourceGate = Completer<void>();
      final workSource = _GatedGridControllerRuntime(
        label: 'work',
        events: events,
        startGate: sourceGate,
      );
      final stateSource = _GatedGridControllerRuntime(
        label: 'state',
        events: events,
      );
      final workBundle = _controllerBundle(
        runtime: workSource,
        events: events,
        shutdownEvent: 'work bundle shutdown (first)',
      );
      final stateBundle = _controllerBundle(
        runtime: stateSource,
        events: events,
        shutdownEvent: 'state bundle shutdown',
      );
      final provider = _RecordingProvider(events);
      final trajectory = await _recordingTrajectory(events);
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      late _RecordingStartDriver driver;
      final runtime = await assembleRecordingRuntime(
        workBundle: workBundle,
        stateBundle: stateBundle,
        provider: provider,
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        driverBuilder: ({required buildDefault}) =>
            driver = _RecordingStartDriver(bridge: bridge, events: events),
      );
      addTearDown(() async {
        if (!sourceGate.isCompleted) sourceGate.complete();
        await runtime.shutdown();
      });
      events.clear();

      expect(runtime.lifecycle, isA<StationWorkRuntimeNotStarted>());
      final starting = runtime.start();
      await workSource.startEntered.future;
      expect(
        runtime.lifecycle,
        const StationWorkRuntimeState.starting(
          stage: StationWorkStartStage.sourcesStart,
        ),
      );
      expect(runtime.lifecycle, isNot(isA<StationWorkRuntimeStarted>()));

      sourceGate.complete();
      await starting;
      expect(runtime.lifecycle, isA<StationWorkRuntimeStarted>());
      expect(workSource.startCalls, 1);
      expect(stateSource.startCalls, 1);
      expect(driver.startCalls, 1);
      expect(bridge.startCalls, 1);

      final firstStartEvents = List<String>.of(events);
      await runtime.start();
      expect(runtime.lifecycle, isA<StationWorkRuntimeStarted>());
      expect(events, firstStartEvents);
      expect(workSource.startCalls, 1);
      expect(stateSource.startCalls, 1);
      expect(driver.startCalls, 1);
    });

    test(
      'failed start refuses retry and shutdown unwinds acquired resources',
      () async {
        final events = <String>[];
        final workSource = _GatedGridControllerRuntime(
          label: 'work',
          events: events,
        );
        final stateSource = _GatedGridControllerRuntime(
          label: 'state',
          events: events,
        );
        final workBundle = _controllerBundle(
          runtime: workSource,
          events: events,
          shutdownEvent: 'work bundle shutdown (first)',
        );
        final stateBundle = _controllerBundle(
          runtime: stateSource,
          events: events,
          shutdownEvent: 'state bundle shutdown',
        );
        final provider = _RecordingProvider(events);
        const cutConfig = TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
        );
        final trajectory = await _recordingTrajectory(
          events,
          config: cutConfig,
        );
        final federated = _RecordingFederatedSource(events);
        final bridge = _RecordingJoinBridge(events);
        final originalError = StateError('driver start exploded');
        final originalStackTrace = StackTrace.current;
        late _StartThrowingRecordingDriver driver;
        final runtime = await assembleRecordingRuntime(
          workBundle: workBundle,
          stateBundle: stateBundle,
          provider: provider,
          trajectory: trajectory,
          federated: federated,
          bridge: bridge,
          trajectoryConfig: cutConfig,
          driverBuilder: ({required buildDefault}) =>
              driver = _StartThrowingRecordingDriver(
                bridge: bridge,
                events: events,
                error: originalError,
                stackTrace: originalStackTrace,
              ),
        );
        var admissionInvalidations = 0;
        runtime.wiring.services.admission.addInvalidationListener(
          () => admissionInvalidations++,
        );
        events.clear();

        Object? caught;
        StackTrace? caughtStack;
        try {
          await runtime.start();
        } on Object catch (error, stackTrace) {
          caught = error;
          caughtStack = stackTrace;
        }

        expect(caught, same(originalError));
        expect(caughtStack, same(originalStackTrace));
        final failure = runtime.lifecycle as StationWorkRuntimeFailed;
        expect(failure.stage, StationWorkStartStage.driverStart);
        expect(failure.error, same(originalError));
        expect(failure.stackTrace, same(originalStackTrace));
        final restartReport = runtime.lastRestartReport;
        final replayReport = runtime.lastTeardownReplay;
        final firstStartEvents = List<String>.of(events);

        StationWorkStartRefused? refused;
        try {
          await runtime.start();
        } on StationWorkStartRefused catch (error) {
          refused = error;
        }
        expect(refused, isNotNull);
        expect(refused!.failure, same(failure));
        expect(refused.failedStage, StationWorkStartStage.driverStart);
        expect(refused.originalError, same(originalError));
        expect(refused.originalStackTrace, same(originalStackTrace));
        expect(
          refused.toString(),
          'StationWorkStartRefused('
          'stage: StationWorkStartStage.driverStart, '
          'originalError: Bad state: driver start exploded)',
        );
        expect(runtime.lifecycle, same(failure));
        expect(runtime.lastRestartReport, same(restartReport));
        expect(runtime.lastTeardownReplay, same(replayReport));
        expect(events, firstStartEvents);
        expect(workSource.startCalls, 1);
        expect(stateSource.startCalls, 1);
        expect(driver.startCalls, 1);

        events.clear();
        await runtime.shutdown();
        await runtime.shutdown();

        expect(runtime.lifecycle, isA<StationWorkRuntimeShutdown>());
        expect(events, [
          'station driver dispose',
          'join bridge dispose',
          'trajectory.shutdown',
          'runtime provider dispose',
          'state bundle shutdown',
          'work bundle shutdown (first)',
          'federated source dispose',
        ]);
        expect(driver.disposeCalls, 1);
        expect(bridge.disposeCalls, 1);
        expect(provider.disposeCalls, 1);
        expect(stateSource.disposeCalls, 1);
        expect(workSource.disposeCalls, 1);
        expect(federated.disposeCalls, 1);

        final admissionHalt = runtime.wiring.trajectory!.admissionHalt!;
        expect(
          admissionHalt.latch(
            reason: 'post-shutdown probe',
            recordClass: 'test',
          ),
          isTrue,
        );
        expect(
          admissionInvalidations,
          0,
          reason: 'shutdown disposed admission and removed its halt listener',
        );
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
        final bridge = _RecordingJoinBridge(events);
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
          bundleBuilder:
              ({
                required storeName,
                required workspace,
                required buildDefault,
              }) async =>
                  storeName == 'state' ? stateBundle : workBundles[storeName]!,
          federatedSourceBuilder: ({required buildDefault}) => federated,
          joinBridgeBuilder: ({required buildDefault}) => bridge,
          driverBuilder: ({required buildDefault}) =>
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

    test('start order remains pinned', () {
      final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
      final start = source.indexOf('  Future<void> start() async {');
      final end = source.indexOf('  /// The `runGrid(onFlushed:)` hook', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final body = source.substring(start, end);

      var cursor = 0;
      for (final operation in [
        'await _sourcesStart();',
        'await trajectory.start();',
        'trajectory.config.cutPostureRefusal',
        'await _freshnessBarrier();',
        'await _restart.reconcile();',
        'await _restart.replayTeardownTail();',
        '_driver.start();',
      ]) {
        final next = body.indexOf(operation, cursor);
        expect(next, greaterThanOrEqualTo(cursor), reason: operation);
        cursor = next + operation.length;
      }
    });

    test('public assembly signature and acquisition order stay pinned', () {
      final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
      final signatureStart = source.indexOf(
        'Future<StationWorkRuntime> assembleStationWork({',
      );
      final signatureEnd = source.indexOf('}) async {', signatureStart);
      final signature = source.substring(signatureStart, signatureEnd);
      final parameters = RegExp(
        // Top-level parameters only: a function-typed parameter's own
        // parameter lines are indented deeper and end with a comma too.
        r'^  (?:\S.*?\s)?(\w+)(?:\s*=.*)?,$',
        multiLine: true,
      ).allMatches(signature).map((match) => match.group(1)).toList();
      expect(parameters, [
        'stateStore',
        'substations',
        'resolver',
        'dryRun',
        'registry',
        'registryBuilder',
        'registryBuilderWithSpecWriter',
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
        'bundleBuilder',
        'federatedSourceBuilder',
        'joinBridgeBuilder',
        'driverBuilder',
      ]);

      expect(
        source,
        contains('''typedef StationWorkBundleBuilder =
    Future<GridRuntimeBundle> Function({
      required String storeName,
      required BeadsWorkspace workspace,
      required Future<GridRuntimeBundle> Function() buildDefault,
    });'''),
      );
      expect(
        source,
        contains('''typedef StationWorkFederatedSourceBuilder =
    FederatedSnapshotSource Function({
      required FederatedSnapshotSource Function() buildDefault,
    });'''),
      );
      expect(
        source,
        contains('''typedef StationWorkJoinBridgeBuilder =
    StationJoinBridge Function({
      required StationJoinBridge Function() buildDefault,
    });'''),
      );
      expect(
        source,
        contains(
          '''typedef StationWorkDriverBuilder =
    StationDriver Function({required StationDriver Function() buildDefault});''',
        ),
      );
      for (final retired in [
        'workBundleOverrides',
        'stateBundleOverride',
        'federatedSourceOverride',
        'driverOverride',
      ]) {
        expect(source, isNot(contains(retired)), reason: retired);
      }

      final assembly = source.substring(signatureStart);
      var cursor = 0;
      for (final acquisition in [
        'Future<GridRuntimeBundle> buildDefault() => GridRuntimeFactory.build(',
        'bundleBuilder?.call(',
        'buildDefault: buildDefault',
        "step: 'work bundle shutdown (\${entry.key})'",
        'Future<GridRuntimeBundle> buildStateDefault() => GridRuntimeFactory.build(',
        'bundleBuilder?.call(',
        "storeName: 'state'",
        'buildDefault: buildStateDefault',
        "step: 'state bundle shutdown'",
        'buildFederatedSourceDefault() => FederatedSnapshotSource(',
        'federatedSourceBuilder?.call(',
        'buildDefault: buildFederatedSourceDefault',
        "step: 'federated source dispose'",
        'providerOverride ??',
        "step: 'runtime provider dispose'",
        'TrajectoryHarness.build(',
        "step: 'trajectory shutdown'",
        'git.registerRootCheckout(',
        'groupsOverride ??',
        'StationServices(',
        "step: 'station admission dispose'",
        'StationJoinBridge buildJoinBridgeDefault() => StationJoinBridge(',
        'joinBridgeBuilder?.call(buildDefault: buildJoinBridgeDefault)',
        "step: 'join bridge dispose'",
        'StationDriver buildDriverDefault() => StationDriver(',
        'driverBuilder?.call(buildDefault: buildDriverDefault)',
        "step: 'station driver dispose'",
      ]) {
        final next = assembly.indexOf(acquisition, cursor);
        expect(next, greaterThanOrEqualTo(cursor), reason: acquisition);
        cursor = next + acquisition.length;
      }
    });
  });
}
