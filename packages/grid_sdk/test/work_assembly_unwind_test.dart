import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show LandGateOpen, LandGateRefused;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart'
    show SqlResult, TrajectoryDb, projSessionHeadCutColumns;
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

/// A probe reader over a mutable map, recording every id it is asked for.
final class _ScriptedProbeReader implements BeadProbeReader {
  _ScriptedProbeReader(Map<String, Bead> beads) : beads = {...beads};

  final Map<String, Bead> beads;
  final List<String> reads = [];

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    reads.add(id);
    final bead = beads[id];
    return bead != null && types.contains(bead.issueType) ? bead : null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

final class _FakeTrajectoryDb implements TrajectoryDb {
  final List<String> statements = [];
  bool closed = false;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    statements.add(sql);
    if (sql.contains('information_schema.columns') &&
        params?['table'] == 'proj_session_head') {
      return SqlResult(
        rows: [
          for (final column in projSessionHeadCutColumns) {'name': column},
        ],
      );
    }
    if (sql.contains("table_name = 'trajectory'")) {
      return const SqlResult(
        rows: [
          {'name': 'substation'},
        ],
      );
    }
    if (sql.contains('COALESCE(MAX(epoch), 0) AS e')) {
      return const SqlResult(
        rows: [
          {'e': '1'},
        ],
      );
    }
    return const SqlResult();
  }

  @override
  Future<void> close() async => closed = true;
}

final class _MutableStateReader implements SnapshotReader, BeadProbeReader {
  _MutableStateReader(Iterable<Bead> beads) : beads = beads.toList();

  List<Bead> beads;

  @override
  Future<GraphSnapshot> read() async => GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime.utc(2026, 9, 13),
  );

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    for (final bead in beads) {
      if (bead.id == id && types.contains(bead.issueType)) return bead;
    }
    return null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => [
    for (final bead in beads)
      if (bead.status == BeadStatus.open &&
          types.contains(bead.issueType) &&
          metadataAll.entries.every(
            (entry) => '${bead.metadata[entry.key]}' == entry.value,
          ) &&
          (metadataAny.isEmpty ||
              metadataAny.entries.any(
                (entry) => '${bead.metadata[entry.key]}' == entry.value,
              )))
        bead,
  ];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];

  void close(String id) {
    beads = [
      for (final bead in beads)
        bead.id == id ? bead.copyWith(status: BeadStatus.closed) : bead,
    ];
  }
}

final class _RecordingStateRunner implements BdRunner {
  _RecordingStateRunner(this.state);

  final _MutableStateReader state;
  final List<List<String>> calls = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.of(args));
    if (args case ['close', final id, ...]) state.close(id);
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":[]}',
      stderr: '',
    );
  }
}

final class _ScriptedModeProbeRunner implements BdRunner {
  _ScriptedModeProbeRunner(this.calls);

  final List<List<String>> calls;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    return switch (args) {
      ['query', 'id=grid-endpoint-warm', '--all', '--json', '--limit', '0'] ||
      ['types', '--json'] => const BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{}}',
        stderr: '',
      ),
      _ => throw StateError('unexpected mode-probe call: $args'),
    };
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map<String, String>.of(data)));
  }
}

/// A pooled Dolt service whose close NEVER confirms — the half-open proxy
/// socket epoch 87's resident parked on (tg-supq). Dials nothing.
final class _HangingDoltQueryService extends DoltQueryService {
  _HangingDoltQueryService()
    : super(
        const DoltEndpoint(
          host: '127.0.0.1',
          port: 65123,
          database: 'tranquility',
        ),
      );

  var closeCalls = 0;

  @override
  Future<void> close() {
    closeCalls++;
    return Completer<void>().future;
  }
}

/// A store connection fake for the confirm pass: closes, refuses, or hangs.
final class _FakeStore implements StoreConnection {
  _FakeStore(this.name, {this.refuses = false, this.hangs = false});

  @override
  final String name;
  final bool refuses;
  final bool hangs;
  var closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    if (refuses) throw StateError('close refused: $name');
    if (hangs) await Completer<void>().future;
  }
}

final class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

final class _BareDelegate extends GridDelegate {
  @override
  Seed build(TreeContext context, GridConfiguration configuration) =>
      const _Leaf();
}

final class _GatedGridControllerRuntime extends GridControllerRuntime {
  _GatedGridControllerRuntime({
    required this.label,
    required List<String> events,
    this.startGate,
    this.requeryFailureAtCall,
    this.requeryFailure,
    super.reader = const _EmptySnapshotReader(),
  }) : record = events,
       super(dirtySources: const []);

  final String label;
  final List<String> record;
  final Completer<void>? startGate;
  final int? requeryFailureAtCall;
  final Object? requeryFailure;
  final Completer<void> startEntered = Completer<void>();
  StackTrace? requeryFailureStackTrace;
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
  Future<void> requery() async {
    requeryCalls++;
    record.add('$label freshness barrier');
    if (requeryCalls == requeryFailureAtCall) {
      final stackTrace = StackTrace.current;
      requeryFailureStackTrace = stackTrace;
      Error.throwWithStackTrace(
        requeryFailure ?? StateError('$label requery failed'),
        stackTrace,
      );
    }
    await super.requery();
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
  BeadProbeReader probeReader = const _EmptyBeadProbeReader(),
}) {
  var shutdown = false;
  return GridRuntimeBundle(
    runtime: runtime,
    probeReader: probeReader,
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

void _seedProxyEndpoint(String dir, {required String database}) {
  final dolt = Directory('$dir/.beads/dolt')..createSync(recursive: true);
  File('$dir/.beads/metadata.json').writeAsStringSync(
    '{"dolt_mode":"proxied-server","dolt_database":"$database"}',
  );
  File('${dolt.path}/beads_dart.secret').writeAsStringSync('test-secret');
  File('${dolt.path}/proxy.pid').writeAsStringSync('{"pid":$pid,"port":65123}');
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
        'unwind step "timed out" failed: budget of 5ms expired — no longer '
            'awaited',
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

  group('closeStoreConnections', () {
    test('confirms, refuses and hangs are reported by name with endpoint and '
        'the pass never throws or waits past its budget', () async {
      final refusals = <String>[];
      final flares = <({String name, Map<String, String> data})>[];
      final closing = _FakeStore('state');
      final refusing = _FakeStore('earth', refuses: true);
      final hanging = _FakeStore('mars', hangs: true);

      final report = await closeStoreConnections(
        [closing, refusing, hanging],
        within: const Duration(milliseconds: 40),
        onRefusal: refusals.add,
        onFlare: (name, data) => flares.add((name: name, data: data)),
      ).timeout(const Duration(seconds: 5));

      expect(report.attempted, 3);
      expect(report.allConfirmed, isFalse);
      expect(report.closed, ['state']);
      expect(report.outstanding.map((handle) => handle.name), [
        'earth',
        'mars',
      ]);
      expect(
        report.outstanding[0].reason,
        'close refused (unwind step "store close (earth)" failed: Bad state: '
        'close refused: earth)',
      );
      expect(
        report.outstanding[1].reason,
        'close did not confirm within '
        '40ms',
      );
      expect(report.outstanding[1].endpoint, '(endpoint not vended)');
      expect(report.narrative, [
        'store connections closed: 1/3',
        'store handle still outstanding: "earth" ((endpoint not vended)) — '
            'close refused (unwind step "store close (earth)" failed: Bad '
            'state: close refused: earth)',
        'store handle still outstanding: "mars" ((endpoint not vended)) — '
            'close did not confirm within 40ms',
      ]);
      // The per-handle refusal IS the settle step line — the same
      // `store close (<name>)` step the resident shell has always printed.
      expect(refusals, [
        'unwind step "store close (earth)" failed: Bad state: close refused: '
            'earth',
        'unwind step "store close (mars)" failed: budget of 40ms expired — no '
            'longer awaited',
      ]);
      expect(flares.map((flare) => flare.name), [
        'unwind.storeHandleOutstanding',
        'unwind.storeHandleOutstanding',
      ]);
      expect(flares[1].data, {
        'store': 'mars',
        'endpoint': '(endpoint not vended)',
        'reason': 'close did not confirm within 40ms',
        'budgetMs': '40',
      });
      expect(closing.closeCalls, 1);
      expect(hanging.closeCalls, 1);
    });

    test('settle reports an expired step through onTimeout only', () async {
      final timedOut = <(String, Duration)>[];
      const within = Duration(milliseconds: 5);
      expect(
        await settle(
          'hung',
          () => Completer<void>().future,
          within: within,
          onRefusal: (_) {},
          onTimeout: (step, budget) => timedOut.add((step, budget)),
        ),
        isFalse,
      );
      expect(
        await settle(
          'threw',
          () => throw StateError('exploded'),
          within: within,
          onRefusal: (_) {},
          onTimeout: (step, budget) => timedOut.add((step, budget)),
        ),
        isFalse,
      );
      expect(timedOut, [('hung', within)]);
    });

    test('an action that THROWS a TimeoutException is a failure, not a budget '
        'expiry: onTimeout never fires and the line carries the action\'s own '
        'exception (tg-supq review)', () async {
      final timedOut = <String>[];
      final refusals = <String>[];
      // The reviewer's case: a close whose own internal timer fires fast,
      // well inside a generous budget.
      expect(
        await settle(
          'self-timing close',
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            throw TimeoutException(
              'dolt close gave up',
              const Duration(seconds: 1),
            );
          },
          within: const Duration(seconds: 5),
          onRefusal: refusals.add,
          onTimeout: (step, _) => timedOut.add(step),
        ),
        isFalse,
      );
      // Synchronously thrown, too.
      expect(
        await settle(
          'sync self-timing close',
          () => throw TimeoutException('sync gave up'),
          within: const Duration(seconds: 5),
          onRefusal: refusals.add,
          onTimeout: (step, _) => timedOut.add(step),
        ),
        isFalse,
      );
      expect(timedOut, isEmpty);
      expect(refusals, [
        'unwind step "self-timing close" failed: TimeoutException after '
            '0:00:01.000000: dolt close gave up',
        'unwind step "sync self-timing close" failed: TimeoutException: sync '
            'gave up',
      ]);
      expect(refusals.join('\n'), isNot(contains('budget of')));
    });

    test('UnwindDeadline clamps each budget to what is left, holds back a '
        'reserve, and hands out zero once spent', () async {
      final deadline = UnwindDeadline(const Duration(milliseconds: 200));
      expect(
        deadline.budget(const Duration(seconds: 5)),
        lessThanOrEqualTo(const Duration(milliseconds: 200)),
      );
      expect(
        deadline.budget(const Duration(milliseconds: 10)),
        const Duration(milliseconds: 10),
      );
      expect(
        deadline.budget(
          const Duration(seconds: 5),
          reserve: const Duration(milliseconds: 100),
        ),
        lessThanOrEqualTo(const Duration(milliseconds: 100)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(deadline.expired, isTrue);
      expect(deadline.budget(const Duration(seconds: 5)), Duration.zero);
    });

    test('the store pass under a spent deadline still REQUESTS every close '
        'and names each handle without waiting', () async {
      final deadline = UnwindDeadline(Duration.zero);
      final stores = [
        for (var i = 0; i < 6; i++) _FakeStore('store$i', hangs: true),
      ];
      final watch = Stopwatch()..start();
      final report = await closeStoreConnections(
        stores,
        deadline: deadline,
        onRefusal: (_) {},
      ).timeout(const Duration(seconds: 5));
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(report.closed, isEmpty);
      expect(report.outstanding.map((handle) => handle.name), [
        for (var i = 0; i < 6; i++) 'store$i',
      ]);
      for (final store in stores) {
        expect(store.closeCalls, 1, reason: '${store.name} close requested');
      }
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
      bool dryRun = true,
      BdCliService? stateBdOverride,
      ExplorationTransport? transport,
      void Function(String)? onRefusal,
      Map<String, String>? environment,
      EndpointWarmRunnerFactory? endpointWarmRunnerFactory,
      List<String> extraWork = const <String>[],
      GridRuntimeBundle Function(String storeName)? workBundleFor,
    }) => assembleStationWork(
      stateStore: GridStateStore.forGridRoot('${temporary.path}/home'),
      substations: [
        SubstationWorkSpec(
          name: 'first',
          root: '${temporary.path}/first',
          head: 'main',
        ),
        for (final name in extraWork)
          SubstationWorkSpec(
            name: name,
            root: '${temporary.path}/$name',
            head: 'main',
          ),
      ],
      resolver: const _NullResolver(),
      dryRun: dryRun,
      preferSql: false,
      providerOverride: provider,
      gitOverride: buildDryStationGitService(),
      stateBdOverride: stateBdOverride,
      transport: transport,
      onRefusal: onRefusal,
      environment: environment,
      endpointWarmRunnerFactory: endpointWarmRunnerFactory,
      trajectoryConfig: trajectoryConfig,
      trajectoryOverride: trajectory,
      bundleBuilder:
          ({
            required storeName,
            required workspace,
            required buildDefault,
          }) async => storeName == 'state'
          ? stateBundle
          : workBundleFor?.call(storeName) ?? workBundle,
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

    test('cut posture contradiction retains its typed request details', () {
      final refusal = const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
        dualRead: DualReadMode.observe,
      ).cutPostureRefusal;

      expect(refusal, isA<CutPostureRefused>());
      expect(refusal!.requestedDualRead, DualReadMode.observe);
      expect(refusal.resolvedDualRead, DualReadMode.primary);
    });

    test('break-glass voids every open cut session before driver start and '
        'emits one banner and flare', () async {
      const reason = 'operator rollback';
      _seedProxyEndpoint('${temporary.path}/home/.grid', database: 'state');
      final events = <String>[];
      final state = _MutableStateReader([
        const Bead(
          id: 'state-cut-2',
          issueType: GridIssueTypes.session,
          status: BeadStatus.open,
          metadata: {
            SessionBeadKeys.workBead: 'tg-work-2',
            SessionBeadKeys.discipline: 'cut',
          },
        ),
        const Bead(
          id: 'state-cut-1',
          issueType: GridIssueTypes.session,
          status: BeadStatus.open,
          metadata: {
            SessionBeadKeys.workBead: 'tg-work-1',
            SessionBeadKeys.discipline: 'cut',
          },
        ),
      ]);
      final runner = _RecordingStateRunner(state);
      final workSource = _GatedGridControllerRuntime(
        label: 'work',
        events: events,
      );
      final stateSource = _GatedGridControllerRuntime(
        label: 'state',
        events: events,
        reader: state,
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
        probeReader: state,
      );
      const base = TrajectoryConfig(mode: TrajectoryConfigMode.disabled);
      final resolved = base.resolveForAssembly(
        dryRun: false,
        breakGlassReason: reason,
      );
      final trajectory = await TrajectoryHarness.build(
        config: resolved,
        gridHome: temporary.path,
        station: 'state',
      );
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      final transport = _RecordingTransport();
      final banners = <String>[];
      final modeProbeCalls = <List<String>>[];
      late _RecordingStartDriver driver;
      final runtime = await assembleRecordingRuntime(
        workBundle: workBundle,
        stateBundle: stateBundle,
        provider: _RecordingProvider(events),
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        trajectoryConfig: base,
        dryRun: false,
        stateBdOverride: BdCliService(runner),
        transport: transport,
        onRefusal: banners.add,
        environment: const {kGridG1BreakGlass: reason},
        endpointWarmRunnerFactory: (_) =>
            _ScriptedModeProbeRunner(modeProbeCalls),
        driverBuilder: ({required buildDefault}) =>
            driver = _RecordingStartDriver(bridge: bridge, events: events),
      );
      addTearDown(runtime.shutdown);

      await runtime.start();

      expect(driver.startCalls, 1);
      expect(stateSource.requeryCalls, greaterThanOrEqualTo(3));
      expect(
        state.beads.every((bead) => bead.status == BeadStatus.closed),
        isTrue,
      );
      expect(
        runner.calls
            .where((call) => call.first == 'close')
            .map((call) => call[1]),
        containsAll(<String>['state-cut-1', 'state-cut-2']),
      );
      final writes = runner.calls.map((call) => call.join(' ')).join('\n');
      expect(writes, contains('grid.voided_reason=break-glass:$reason'));
      expect(banners, ['grid: BREAK-GLASS reason=$reason voided=2']);
      expect(modeProbeCalls, [
        ['query', 'id=grid-endpoint-warm', '--all', '--json', '--limit', '0'],
        ['types', '--json'],
      ]);
      final breakGlassFlares = transport.flares
          .where((flare) => flare.name == 'trajectory.breakGlass')
          .toList(growable: false);
      expect(breakGlassFlares, hasLength(1));
      expect(breakGlassFlares.single.data, {'reason': reason, 'voided': '2'});
    });

    test('cut whose required harness is unavailable shuts it down, latches '
        'the typed failure, and never starts the driver', () async {
      _seedProxyEndpoint('${temporary.path}/home/.grid', database: 'state');
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
      const cut = TrajectoryConfig(discipline: TrajectoryDiscipline.cut);
      final trajectory = await TrajectoryHarness.build(
        config: cut,
        gridHome: temporary.path,
        station: 'state',
        connect: () async => throw StateError('trajectory unavailable'),
        onFlare: (name, _) => events.add(name),
      );
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      final modeProbeCalls = <List<String>>[];
      late _RecordingStartDriver driver;
      final runtime = await assembleRecordingRuntime(
        workBundle: workBundle,
        stateBundle: stateBundle,
        provider: provider,
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        trajectoryConfig: cut,
        dryRun: false,
        endpointWarmRunnerFactory: (_) =>
            _ScriptedModeProbeRunner(modeProbeCalls),
        driverBuilder: ({required buildDefault}) =>
            driver = _RecordingStartDriver(bridge: bridge, events: events),
      );
      addTearDown(runtime.shutdown);

      Object? first;
      try {
        await runtime.start();
      } on Object catch (error) {
        first = error;
      }
      expect(first, isA<CutTrajectoryUnavailable>());
      final failure = runtime.lifecycle as StationWorkRuntimeFailed;
      expect(failure.stage, StationWorkStartStage.trajectoryAvailability);
      expect(failure.error, same(first));
      expect(driver.startCalls, 0);
      expect(events, contains('trajectory.shutdown'));
      expect(modeProbeCalls, [
        ['query', 'id=grid-endpoint-warm', '--all', '--json', '--limit', '0'],
        ['types', '--json'],
      ]);

      await expectLater(
        runtime.start(),
        throwsA(
          isA<StationWorkStartRefused>()
              .having((refusal) => refusal.failure, 'failure', same(failure))
              .having(
                (refusal) => refusal.originalError,
                'originalError',
                same(first),
              ),
        ),
      );
      expect(driver.startCalls, 0);
    });

    test(
      'shadow start logs post-replay requery failure once and starts driver',
      () async {
        final events = <String>[];
        final refusals = <String>[];
        final requeryFailure = StateError('post-replay snapshot unavailable');
        final workSource = _GatedGridControllerRuntime(
          label: 'work',
          events: events,
        );
        final stateSource = _GatedGridControllerRuntime(
          label: 'state',
          events: events,
          requeryFailureAtCall: 4,
          requeryFailure: requeryFailure,
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
        const shadow = TrajectoryConfig(mode: TrajectoryConfigMode.disabled);
        final trajectory = await TrajectoryHarness.build(
          config: shadow,
          gridHome: temporary.path,
          station: 'state',
        );
        final federated = _RecordingFederatedSource(events);
        final bridge = _RecordingJoinBridge(events);
        late _RecordingStartDriver driver;
        final runtime = await assembleRecordingRuntime(
          workBundle: workBundle,
          stateBundle: stateBundle,
          provider: _RecordingProvider(events),
          trajectory: trajectory,
          federated: federated,
          bridge: bridge,
          trajectoryConfig: shadow,
          onRefusal: refusals.add,
          driverBuilder: ({required buildDefault}) =>
              driver = _RecordingStartDriver(bridge: bridge, events: events),
        );
        addTearDown(runtime.shutdown);

        await runtime.start();

        final requeryRefusals = refusals
            .where(
              (line) => line.contains(
                'state requery failed '
                '(discipline quiesce unevaluable)',
              ),
            )
            .toList(growable: false);
        expect(requeryRefusals, hasLength(1));
        expect(requeryRefusals.single, contains('$requeryFailure'));
        expect(stateSource.requeryCalls, 4);
        expect(driver.startCalls, 1);
        expect(runtime.lifecycle, isA<StationWorkRuntimeStarted>());
      },
    );

    test(
      'cut start converts post-replay requery failure to quiesce refusal',
      () async {
        _seedProxyEndpoint('${temporary.path}/home/.grid', database: 'state');
        final events = <String>[];
        final refusals = <String>[];
        final requeryFailure = StateError('post-replay snapshot unavailable');
        final workSource = _GatedGridControllerRuntime(
          label: 'work',
          events: events,
        );
        final stateSource = _GatedGridControllerRuntime(
          label: 'state',
          events: events,
          requeryFailureAtCall: 4,
          requeryFailure: requeryFailure,
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
        const cut = TrajectoryConfig(discipline: TrajectoryDiscipline.cut);
        final db = _FakeTrajectoryDb();
        final trajectory = await TrajectoryHarness.build(
          config: cut,
          gridHome: temporary.path,
          station: 'state',
          connect: () async => db,
          onFlare: (name, _) => events.add(name),
        );
        final federated = _RecordingFederatedSource(events);
        final bridge = _RecordingJoinBridge(events);
        final modeProbeCalls = <List<String>>[];
        late _RecordingStartDriver driver;
        final runtime = await assembleRecordingRuntime(
          workBundle: workBundle,
          stateBundle: stateBundle,
          provider: _RecordingProvider(events),
          trajectory: trajectory,
          federated: federated,
          bridge: bridge,
          trajectoryConfig: cut,
          dryRun: false,
          onRefusal: refusals.add,
          endpointWarmRunnerFactory: (_) =>
              _ScriptedModeProbeRunner(modeProbeCalls),
          driverBuilder: ({required buildDefault}) =>
              driver = _RecordingStartDriver(bridge: bridge, events: events),
        );
        addTearDown(runtime.shutdown);

        Object? first;
        StackTrace? firstStackTrace;
        try {
          await runtime.start();
        } on Object catch (error, stackTrace) {
          first = error;
          firstStackTrace = stackTrace;
        }

        expect(first, isA<DisciplineQuiesceRefused>());
        final refusal = first! as DisciplineQuiesceRefused;
        expect(refusal.discipline, TrajectoryDiscipline.cut);
        expect(refusal.reason, 'requery-failed');
        expect(refusal.offendingSessionIds, isEmpty);
        expect(
          () => refusal.offendingSessionIds.add('state-session'),
          throwsUnsupportedError,
        );
        expect(refusal.toString(), contains('reason: requery-failed'));
        expect(
          '$firstStackTrace',
          '${stateSource.requeryFailureStackTrace}',
          reason: 'the typed refusal retains the failed requery stack',
        );
        final requeryRefusals = refusals
            .where(
              (line) => line.contains(
                'state requery failed '
                '(discipline quiesce unevaluable)',
              ),
            )
            .toList(growable: false);
        expect(requeryRefusals, hasLength(1));
        expect(requeryRefusals.single, contains('$requeryFailure'));
        expect(stateSource.requeryCalls, 4);
        expect(driver.startCalls, 0);
        expect(db.closed, isTrue);
        expect(modeProbeCalls, [
          ['query', 'id=grid-endpoint-warm', '--all', '--json', '--limit', '0'],
          ['types', '--json'],
        ]);
        expect(
          events.where((event) => event == 'trajectory.shutdown'),
          hasLength(1),
        );

        final failure = runtime.lifecycle as StationWorkRuntimeFailed;
        expect(failure.stage, StationWorkStartStage.disciplineQuiesce);
        expect(failure.error, same(refusal));
        await expectLater(
          runtime.start(),
          throwsA(
            isA<StationWorkStartRefused>()
                .having((retry) => retry.failure, 'failure', same(failure))
                .having(
                  (retry) => retry.originalError,
                  'originalError',
                  same(refusal),
                ),
          ),
        );
        expect(driver.startCalls, 0);
      },
    );

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
        const config = TrajectoryConfig();
        final trajectory = await _recordingTrajectory(events, config: config);
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
          trajectoryConfig: config,
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

        expect(runtime.wiring.trajectory!.admissionHalt, isNull);
        expect(admissionInvalidations, 0);
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

    test(
      'shutdown runs past the trajectory fixpoint flare, confirms every store '
      'handle, and names the one whose close never completes — inside the '
      'grace window (tg-supq)',
      () async {
        final events = <String>[];
        final refusals = <String>[];
        final transport = _RecordingTransport();
        final hanging = _HangingDoltQueryService();
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
        // The measured shape: the state bundle's shutdown awaits the pool
        // close, and the pool close awaits a wire that never answers.
        var stateShutdown = false;
        final stateBundle = GridRuntimeBundle(
          runtime: stateSource,
          probeReader: const _EmptyBeadProbeReader(),
          readPath: ReadPath.sql,
          dolt: hanging,
          shutdown: () async {
            if (stateShutdown) return;
            stateShutdown = true;
            events.add('state bundle shutdown');
            await stateSource.dispose();
            await hanging.close();
          },
        );
        final provider = _RecordingProvider(events);
        final trajectory = await _recordingTrajectory(events);
        final federated = _RecordingFederatedSource(events);
        final bridge = _RecordingJoinBridge(events);
        final runtime = await assembleRecordingRuntime(
          workBundle: workBundle,
          stateBundle: stateBundle,
          provider: provider,
          trajectory: trajectory,
          federated: federated,
          bridge: bridge,
          transport: transport,
          onRefusal: refusals.add,
          driverBuilder: ({required buildDefault}) =>
              _RecordingStartDriver(bridge: bridge, events: events),
        );
        expect(runtime.openStores.map((store) => store.name), [
          'state',
          'trajectory',
        ]);
        expect(
          runtime.openStores.first.endpoint,
          '127.0.0.1:65123/tranquility',
        );
        expect(
          runtime.openStores[1].endpoint,
          '127.0.0.1:65123/trajectory',
          reason: 'the trajectory dials the state store server',
        );
        events.clear();

        const stepBudget = Duration(milliseconds: 100);
        const closeBudget = Duration(milliseconds: 80);
        // The wall-clock guard IS the acceptance: on the pre-fix code this
        // await never completes and the test times out instead of failing.
        final report = await runtime
            .shutdown(stepBudget: stepBudget, storeCloseBudget: closeBudget)
            .timeout(const Duration(seconds: 5));

        expect(runtime.lifecycle, isA<StationWorkRuntimeShutdown>());
        // The unwind ran PAST the final trajectory flare to the end.
        expect(events, [
          'station driver dispose',
          'join bridge dispose',
          'trajectory.shutdown',
          'runtime provider dispose',
          'state bundle shutdown',
          'work bundle shutdown (first)',
          'federated source dispose',
        ]);
        expect(report.isClean, isFalse);
        expect(report.timedOutSteps, ['state bundle shutdown']);
        // The hung handle is NAMED, with its endpoint, not awaited forever.
        expect(report.stores.closed, ['trajectory']);
        final outstanding = report.stores.outstanding.single;
        expect(outstanding.name, 'state');
        expect(outstanding.endpoint, '127.0.0.1:65123/tranquility');
        expect(outstanding.reason, 'close did not confirm within 80ms');
        expect(report.narrative, [
          'store connections closed: 1/2',
          'store handle still outstanding: "state" '
              '(127.0.0.1:65123/tranquility) — close did not confirm within '
              '80ms',
          'unwind step "state bundle shutdown" outlived its budget and is no '
              'longer awaited',
        ]);
        // Both the bundle step and the confirm pass attempted the close: a
        // refused-or-expired close is retried, never dropped.
        expect(hanging.closeCalls, 2);
        // A budget expiry is rendered AS an expiry — never as a
        // TimeoutException the step's action might itself have thrown.
        expect(refusals, [
          'unwind step "state bundle shutdown" failed: budget of 100ms '
              'expired — no longer awaited',
          'unwind step "store close (state)" failed: budget of 80ms expired '
              '— no longer awaited',
          'unwind: store handle "state" (127.0.0.1:65123/tranquility) — close '
              'did not confirm within 80ms — still open, no longer awaited',
        ]);
        // The harness's own `trajectory.shutdown` flare rides this fixture's
        // event log (asserted above); the unwind's flares ride the transport.
        expect(transport.flares.map((flare) => flare.name), [
          'unwind.stepTimedOut',
          'unwind.storeHandleOutstanding',
          'unwind.complete',
        ]);
        expect(transport.flares[0].data, {
          'step': 'state bundle shutdown',
          'budgetMs': '100',
          'deadlineMs': '${kUnwindDeadline.inMilliseconds}',
        });
        expect(transport.flares[1].data, {
          'store': 'state',
          'endpoint': '127.0.0.1:65123/tranquility',
          'reason': 'close did not confirm within 80ms',
          'budgetMs': '80',
        });
        expect(transport.flares[2].data, {
          'closedStores': 'trajectory',
          'outstandingStores': 'state',
          'timedOutSteps': 'state bundle shutdown',
          'deadlineMs': '${kUnwindDeadline.inMilliseconds}',
          'elapsedMs': '${report.elapsed.inMilliseconds}',
          'clean': 'false',
        });
        expect(report.elapsed, lessThan(kUnwindDeadline));

        // Idempotent: the second call is the same unwind, not a second one.
        expect(identical(await runtime.shutdown(), report), isTrue);
        expect(hanging.closeCalls, 2);
      },
    );

    test(
      'an unwind step that never returns (a bd child held open) is named and '
      'abandoned at its budget while the steps beneath it still run',
      () async {
        final events = <String>[];
        final refusals = <String>[];
        final workSource = _GatedGridControllerRuntime(
          label: 'work',
          events: events,
        );
        final stateSource = _GatedGridControllerRuntime(
          label: 'state',
          events: events,
        );
        final workBundle = GridRuntimeBundle(
          runtime: workSource,
          probeReader: const _EmptyBeadProbeReader(),
          readPath: ReadPath.cli,
          shutdown: () async {
            events.add('work bundle shutdown (first)');
            // A reap write whose bd child inherited a pipe into a reparented
            // grandchild: the process future never completes.
            await Completer<void>().future;
          },
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
        final runtime = await assembleRecordingRuntime(
          workBundle: workBundle,
          stateBundle: stateBundle,
          provider: provider,
          trajectory: trajectory,
          federated: federated,
          bridge: bridge,
          onRefusal: refusals.add,
          driverBuilder: ({required buildDefault}) =>
              _RecordingStartDriver(bridge: bridge, events: events),
        );
        events.clear();

        final report = await runtime
            .shutdown(stepBudget: const Duration(milliseconds: 50))
            .timeout(const Duration(seconds: 5));

        expect(events, [
          'station driver dispose',
          'join bridge dispose',
          'trajectory.shutdown',
          'runtime provider dispose',
          'state bundle shutdown',
          'work bundle shutdown (first)',
          'federated source dispose',
        ]);
        expect(report.timedOutSteps, ['work bundle shutdown (first)']);
        expect(report.stores.allConfirmed, isTrue);
        expect(report.isClean, isFalse);
        expect(refusals, [
          'unwind step "work bundle shutdown (first)" failed: budget of 50ms '
              'expired — no longer awaited',
        ]);
        expect(federated.disposeCalls, 1);
      },
    );

    test('on a roster-scale unwind where EVERY source bundle and EVERY store '
        'handle hangs, ONE total deadline bounds the wall clock — per-step '
        'budgets alone would sum to ~90 s — while every close is still '
        'requested and every hung thing is named (tg-supq review)', () async {
      // Lunar's roster shape: the state store plus twelve work stores
      // beside `first` — thirteen pooled handles, thirteen bundles.
      final extra = [
        for (var i = 1; i <= 12; i++) 'w${i.toString().padLeft(2, '0')}',
      ];
      for (final name in extra) {
        _seedStore('${temporary.path}/$name', database: name);
      }
      final events = <String>[];
      final refusals = <String>[];
      final transport = _RecordingTransport();
      final pools = <String, _HangingDoltQueryService>{};
      GridRuntimeBundle hangingBundle(String name, String event) {
        final pool = pools[name] ??= _HangingDoltQueryService();
        return GridRuntimeBundle(
          runtime: _GatedGridControllerRuntime(label: name, events: events),
          probeReader: const _EmptyBeadProbeReader(),
          readPath: ReadPath.sql,
          dolt: pool,
          shutdown: () async {
            events.add(event);
            await pool.close();
          },
        );
      }

      final provider = _RecordingProvider(events);
      final trajectory = await _recordingTrajectory(events);
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      final runtime = await assembleRecordingRuntime(
        workBundle: hangingBundle('first', 'work bundle shutdown (first)'),
        workBundleFor: (name) =>
            hangingBundle(name, 'work bundle shutdown ($name)'),
        extraWork: extra,
        stateBundle: hangingBundle('state', 'state bundle shutdown'),
        provider: provider,
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        transport: transport,
        onRefusal: refusals.add,
        driverBuilder: ({required buildDefault}) =>
            _RecordingStartDriver(bridge: bridge, events: events),
      );
      final work = ['first', ...extra];
      expect(runtime.openStores.map((store) => store.name), [
        'state',
        'trajectory',
        ...work,
      ]);
      events.clear();

      // DEFAULT per-step (5 s) and per-close (2 s) budgets: summed over
      // this roster they are 14 x 5 s + 14 x 2 s. Only the total bounds it.
      const deadline = Duration(milliseconds: 800);
      final watch = Stopwatch()..start();
      final report = await runtime
          .shutdown(deadline: deadline)
          .timeout(const Duration(seconds: 20));
      watch.stop();

      expect(
        watch.elapsed,
        lessThan(deadline + const Duration(milliseconds: 1500)),
        reason: 'the unwind is bounded by its TOTAL, not the per-step sum',
      );
      expect(report.deadline, deadline);
      // Every bundle step was still STARTED — a close never requested is a
      // socket never closed — and every pool saw a close.
      expect(events, containsAllInOrder(['trajectory.shutdown']));
      for (final name in work) {
        expect(events, contains('work bundle shutdown ($name)'));
      }
      expect(events, contains('state bundle shutdown'));
      expect(events, contains('federated source dispose'));
      for (final entry in pools.entries) {
        expect(
          entry.value.closeCalls,
          greaterThanOrEqualTo(1),
          reason: '${entry.key} pool close requested',
        );
      }
      // Every hung thing is named.
      expect(
        report.timedOutSteps,
        containsAll([
          'state bundle shutdown',
          for (final name in work) 'work bundle shutdown ($name)',
        ]),
      );
      expect(report.stores.closed, ['trajectory']);
      expect(report.stores.outstanding.map((handle) => handle.name), [
        'state',
        ...work,
      ]);
      for (final name in ['state', ...work]) {
        expect(
          refusals,
          contains(
            'unwind: store handle "$name" '
            '(127.0.0.1:65123/tranquility) — close did not confirm within '
            '0ms — still open, no longer awaited',
          ),
          reason: 'past the deadline each handle is named, not awaited',
        );
      }
    });

    test('the default total deadline sits inside the down client grace', () {
      // grid_cli's `kStationStopGrace` (10 s) is the authoritative pin (a
      // grid_cli test compares the two directly; grid_sdk cannot import it).
      expect(kUnwindDeadline, lessThan(const Duration(seconds: 10)));
      expect(kUnwindStepBudget, lessThanOrEqualTo(kUnwindDeadline));
      expect(kStoreCloseTimeout, lessThanOrEqualTo(kUnwindDeadline));
    });

    test('the PRODUCTION assembly injects the fresh-status delivery gate into '
        'StationServices, routed to the owning store and read at call time '
        '(tg-b1t8 review)', () async {
      final events = <String>[];
      final work = _ScriptedProbeReader({
        'first-1': const Bead(id: 'first-1', issueType: IssueType.task),
      });
      final state = _ScriptedProbeReader(const {});
      final workSource = _GatedGridControllerRuntime(
        label: 'work',
        events: events,
      );
      final stateSource = _GatedGridControllerRuntime(
        label: 'state',
        events: events,
      );
      final provider = _RecordingProvider(events);
      final trajectory = await _recordingTrajectory(events);
      final federated = _RecordingFederatedSource(events);
      final bridge = _RecordingJoinBridge(events);
      final runtime = await assembleRecordingRuntime(
        workBundle: _controllerBundle(
          runtime: workSource,
          events: events,
          shutdownEvent: 'work bundle shutdown (first)',
          probeReader: work,
        ),
        stateBundle: _controllerBundle(
          runtime: stateSource,
          events: events,
          shutdownEvent: 'state bundle shutdown',
          probeReader: state,
        ),
        provider: provider,
        trajectory: trajectory,
        federated: federated,
        bridge: bridge,
        driverBuilder: ({required buildDefault}) =>
            _RecordingStartDriver(bridge: bridge, events: events),
      );
      addTearDown(runtime.shutdown);

      final gate = runtime.wiring.services.deliveryGate;
      expect(gate, isNotNull, reason: 'the resident wires the gate');
      // Open at mount …
      expect(await gate!('first-1'), isA<LandGateOpen>());
      // … parked before push: the SAME gate, asked again, reads it fresh.
      work.beads['first-1'] = const Bead(
        id: 'first-1',
        issueType: IssueType.task,
        status: BeadStatus.deferred,
      );
      final deferred = await gate('first-1') as LandGateRefused;
      expect(deferred.status, 'deferred');
      expect(work.reads, ['first-1', 'first-1']);
      // An unmatched prefix is UNOWNED, and the state store is never read
      // for it.
      final unowned = await gate('zz-1') as LandGateRefused;
      expect(unowned.status, 'unowned');
      expect(state.reads, isEmpty);
    });

    test(
      'GridHandle.teardown names an orphan sweep that outlives its budget and '
      'still disposes the delegate',
      () async {
        final refusals = <GridHookError>[];
        final delegate = _BareDelegate();
        final handle = await runGrid(
          delegate,
          onError: refusals.add,
          orphanSweep: () => Completer<void>().future,
          orphanSweepBudget: const Duration(milliseconds: 50),
        );

        await handle.teardown().timeout(const Duration(seconds: 5));

        expect(handle.isTornDown, isTrue);
        final refusal = refusals.single;
        expect(refusal.hook, 'orphanSweep');
        final cause = refusal.cause;
        expect(cause, isA<TimeoutException>());
        expect(
          (cause as TimeoutException).message,
          contains('did not settle within 50ms — no longer awaited'),
        );
        expect(
          () => delegate.addListener((_) {}),
          throwsA(isA<Error>()),
          reason: 'the delegate was disposed after the abandoned sweep',
        );
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
        'trajectory.status.mode',
        'await _freshnessBarrier();',
        'await _restart.reconcile();',
        'await _restart.replayTeardownTail();',
        'await _stateRequery();',
        '_openSessions(state)',
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
        'onStateStorePruneReceipt',
        'transport',
        'wedgeThreshold',
        'wedgePollInterval',
        'syncFloorInterval',
        'trajectoryConfig',
        'trajectoryOverride',
        'environment',
        'endpointWarmRunnerFactory',
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
      expect(
        source,
        contains('''onProcessIdentityChanges: !dualReadArmed
        ? null
        : (listener) => trajectory.onProcessIdentitiesChanged(
            listener,
            fireImmediately: false,
          ),'''),
        reason: 'P6 rejoins only while the dual read is armed',
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
      final sourcesShutdownStart = assembly.indexOf(
        '    sourcesShutdown: ({required within, required onTimeout}) async {',
      );
      final sourcesShutdownEnd = assembly.indexOf(
        '\n    freshnessBarrier:',
        sourcesShutdownStart,
      );
      expect(sourcesShutdownStart, isNonNegative);
      expect(sourcesShutdownEnd, greaterThan(sourcesShutdownStart));
      final sourcesShutdown = assembly.substring(
        sourcesShutdownStart,
        sourcesShutdownEnd,
      );
      final shutdownSnapshot = sourcesShutdown.indexOf(
        '''final shutdownBundles = List<MapEntry<String, GridRuntimeBundle>>.of(
        bundles.entries,
      );''',
      );
      final firstAwait = sourcesShutdown.indexOf('await settle(');
      expect(shutdownSnapshot, isNonNegative);
      expect(firstAwait, greaterThan(shutdownSnapshot));
      expect(sourcesShutdown, contains('for (final entry in shutdownBundles)'));
      expect(
        sourcesShutdown,
        isNot(contains('for (final entry in bundles.entries)')),
        reason: 'an awaited shutdown loop must not retain a live map iterator',
      );

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
        'final writer = StationBeadWriter(',
        'final sessionLiveness = WorkSessionLiveness(',
        "step: 'work-session liveness dispose'",
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

      final shutdownStart = source.indexOf(
        '  Future<StationWorkUnwindReport> _runShutdown({',
      );
      final shutdownEnd = source.indexOf(
        '\n  /// The outer bound on the trajectory step',
        shutdownStart,
      );
      expect(shutdownStart, isNonNegative);
      expect(shutdownEnd, greaterThan(shutdownStart));
      final shutdown = source.substring(shutdownStart, shutdownEnd);
      var shutdownCursor = 0;
      for (final disposal in [
        "'station driver dispose'",
        "'join bridge dispose'",
        "'station admission dispose'",
        "'trajectory shutdown'",
        "'runtime provider dispose'",
        "'work-session liveness dispose'",
        'await _sourcesShutdown(',
        // The CONFIRM pass runs LAST, after every source bundle is down
        // (tg-supq): a handle that did not close is named there.
        'await closeStoreConnections(',
      ]) {
        final next = shutdown.indexOf(disposal, shutdownCursor);
        expect(next, greaterThanOrEqualTo(shutdownCursor), reason: disposal);
        shutdownCursor = next + disposal.length;
      }
    });
  });
}
