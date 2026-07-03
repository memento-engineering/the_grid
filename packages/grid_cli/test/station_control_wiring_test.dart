import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_cli/src/station_lock.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// RS-4 (D-C2, `docs/SCRATCH-resident-station.md` §3): the control surface
/// (RS-4) as `driveStation` actually wires it — RESIDENT mode only, riding
/// the RS-2 station lock. Offline only: temp dirs, a fake pid prober, an
/// injected signal stream; NO live stores, NO real `claude`/`git`/`bd`. What
/// this file locks (the acceptance criteria):
///
///  (c) after boot the lock carries `controlUrl`/`token` (a REAL bind — no
///      fake), the file stays 0600;
///  (e) the control surface is disposed BEFORE the lock releases, on the
///      graceful shutdown path.
///
/// (HTTP-shape correctness lives in station_control_test.dart; the GET-only/
/// no-writer/no-requery source posture lives in
/// station_control_gates_test.dart.)
void main() {
  group('driveStation — the RS-4 control surface rides the RS-2 lock', () {
    test('(c) a REAL bind: post-boot the lock carries controlUrl + token, '
        'the file stays 0600', () async {
      final store = _tempStore();
      final h = _ControlHarness(store: store);
      addTearDown(h.dispose);

      final run = h.drive();
      final lockFile = File(StationLockService.lockPath(store.path));
      late Map<String, Object?> json;
      await _until(() {
        if (!lockFile.existsSync()) return false;
        try {
          json =
              jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
        } on Object {
          return false;
        }
        return json['controlUrl'] != null && json['token'] != null;
      }, 'the lock to carry controlUrl/token after boot');

      expect(json['controlUrl'], startsWith('http://127.0.0.1:'));
      expect(json['token'], isA<String>());
      expect((json['token']! as String).length, greaterThan(10));
      expect(_modeOf(lockFile.path), '600', reason: 'the bearer-token mode');

      // The advertised endpoint actually answers, bearer-gated.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('${json['controlUrl']}/healthz'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${json['token']}',
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();

      h.signals.add(ProcessSignal.sigterm);
      expect(await run.timeout(const Duration(seconds: 10)), 0);
      expect(lockFile.existsSync(), isFalse);
    });

    test('(e) the control surface is disposed BEFORE the lock releases '
        '(the graceful path)', () async {
      final store = _tempStore();
      final order = <String>[];
      final lockFile = File(StationLockService.lockPath(store.path));
      final h = _ControlHarness(
        store: store,
        controlStarter:
            ({
              required int port,
              required String token,
              required StationStatus Function() view,
            }) async => _FakeStationControl(
              url: 'http://127.0.0.1:0',
              onDispose: () async {
                expect(
                  lockFile.existsSync(),
                  isTrue,
                  reason:
                      'dispose must run BEFORE the lock releases (RS-4 scope '
                      'fence)',
                );
                order.add('control.dispose');
              },
            ),
      );
      addTearDown(h.dispose);

      final run = h.drive();
      await _until(
        () => _controlUrlIn(lockFile) != null,
        'the fake control to be advertised through the lock',
      );

      h.signals.add(ProcessSignal.sigterm);
      expect(await run.timeout(const Duration(seconds: 10)), 0);

      expect(order, ['control.dispose'], reason: 'dispose ran exactly once');
      expect(
        lockFile.existsSync(),
        isFalse,
        reason: 'the lock released AFTER dispose (asserted inside dispose)',
      );
    });

    test('(e) the control surface is disposed BEFORE the lock releases on '
        'the start()-throw unwind too', () async {
      final store = _tempStore();
      final order = <String>[];
      final lockFile = File(StationLockService.lockPath(store.path));
      final h = _ControlHarness(
        store: store,
        sourcesStart: () async => throw StateError('controller boot failed'),
        controlStarter:
            ({
              required int port,
              required String token,
              required StationStatus Function() view,
            }) async => _FakeStationControl(
              url: 'http://127.0.0.1:0',
              onDispose: () async {
                expect(lockFile.existsSync(), isTrue);
                order.add('control.dispose');
              },
            ),
      );
      addTearDown(h.dispose);

      await expectLater(h.drive(), throwsA(isA<StateError>()));
      expect(order, ['control.dispose']);
      expect(lockFile.existsSync(), isFalse);
    });

    test('non-resident arming never binds the control surface, even with a '
        'state store held', () async {
      final store = _tempStore();
      final h = _ControlHarness(
        store: store,
        resident: false,
        controlStarter:
            ({
              required int port,
              required String token,
              required StationStatus Function() view,
            }) async => fail(
              'non-resident driveStation must never bind '
              'the control surface',
            ),
      );
      addTearDown(h.dispose);

      final run = h.drive();
      final lockFile = File(StationLockService.lockPath(store.path));
      await _until(() => _pidIn(lockFile) != null, 'the lock to be acquired');
      expect(_controlUrlIn(lockFile), isNull);

      h.signals.add(ProcessSignal.sigterm);
      expect(await run.timeout(const Duration(seconds: 10)), 0);
    });

    test('(rework) /status.work.ready counts only the OWNED substation\'s '
        'ready work — a shared store\'s OTHER substation never inflates it',
        () async {
      final store = _tempStore();
      final owned = Bead(
        id: 'tgdog-owned1',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      final foreign = Bead(
        id: 'otherrig-foreign1',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      final snapshot = GraphSnapshot.fromParts(
        beads: [owned, foreign],
        dependencies: const [],
        readyIds: {owned.id, foreign.id},
        capturedAt: DateTime.utc(2026, 7, 2),
      );
      final h = _ControlHarness(store: store, workSnapshot: snapshot);
      addTearDown(h.dispose);

      final run = h.drive();
      final lockFile = File(StationLockService.lockPath(store.path));
      await _until(
        () => _controlUrlIn(lockFile) != null && _tokenIn(lockFile) != null,
        'the lock to carry controlUrl/token after boot',
      );
      final controlUrl = _controlUrlIn(lockFile)!;
      final token = _tokenIn(lockFile)!;

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(Uri.parse('$controlUrl/status'));
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, Object?>;
      final work = body['work'] as Map<String, Object?>;
      expect(
        work['ready'],
        1,
        reason:
            'both beads are ready, but only "tgdog-owned1" is owned by the '
            'harness\'s "tgdog" substation — "otherrig-foreign1" must never '
            'count (the graph.readyCount regression this fix closes)',
      );

      h.signals.add(ProcessSignal.sigterm);
      expect(await run.timeout(const Duration(seconds: 10)), 0);
    });
  });
}

/// A temp state-store root (no `.grid/` yet — acquire creates it).
Directory _tempStore() {
  final dir = Directory.systemTemp.createTempSync('station-control-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// The POSIX permission bits of [path], octal (e.g. `600`).
String _modeOf(String path) =>
    (FileStat.statSync(path).mode & 0xFFF).toRadixString(8);

int? _pidIn(File lockFile) {
  try {
    final json = jsonDecode(lockFile.readAsStringSync());
    return (json as Map<String, Object?>)['pid'] as int?;
  } on Object {
    return null;
  }
}

String? _controlUrlIn(File lockFile) {
  try {
    final json = jsonDecode(lockFile.readAsStringSync());
    return (json as Map<String, Object?>)['controlUrl'] as String?;
  } on Object {
    return null;
  }
}

String? _tokenIn(File lockFile) {
  try {
    final json = jsonDecode(lockFile.readAsStringSync());
    return (json as Map<String, Object?>)['token'] as String?;
  } on Object {
    return null;
  }
}

/// Polls [condition] up to a bounded deadline (driveStation's boot spans real
/// async work — the banner's VM-service call, the lock's chmod subprocess,
/// and now the control bind).
Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A fake [StationControl] — records [onDispose] instead of running a real
/// server, so the ordering tests need no real socket.
class _FakeStationControl implements StationControl {
  _FakeStationControl({required this.url, required this.onDispose});

  @override
  final String url;

  final Future<void> Function() onDispose;

  @override
  Future<void> dispose() => onDispose();
}

/// The offline control-surface harness: a composed RESIDENT dry station whose
/// [StationSources] carry a temp-dir state workspace, parked by [drive] on an
/// injected signal stream — nothing live anywhere.
class _ControlHarness {
  _ControlHarness({
    required Directory store,
    bool resident = true,
    Future<void> Function()? sourcesStart,
    StationControlStarter? controlStarter,
    GraphSnapshot? workSnapshot,
  }) : _store = store,
       _resident = resident,
       _sourcesStart = sourcesStart,
       _controlStarter = controlStarter,
       _workSnapshot = workSnapshot;

  final Directory _store;
  final bool _resident;
  final Future<void> Function()? _sourcesStart;
  final StationControlStarter? _controlStarter;
  final GraphSnapshot? _workSnapshot;

  /// The injected signal seam.
  final StreamController<ProcessSignal> signals =
      StreamController<ProcessSignal>();

  late final _FakeSnapshotSource work = _FakeSnapshotSource(_workSnapshot);
  late final _NoopProvider provider = _NoopProvider();

  late final StationSources sources = StationSources(
    work: work,
    stateWorkspace: BeadsWorkspace(
      root: _store.path,
      mode: DoltMode.direct,
      database: null,
      gtRoot: null,
      endpoint: null,
    ),
    start: _sourcesStart,
  );

  /// Composes the resident dry station and parks it (run-forever) on
  /// [signals].
  Future<int> drive() {
    final writer = StationBeadWriter(
      bd: BdCliService(_CannedBdRunner()),
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
    );
    final wiring = composeStation(
      work: work,
      state: const EmptySnapshotSource(),
      stationServices: StationServices(
        provider: provider,
        writer: writer,
        stateSubstation: 'tgdog',
      ),
      substations: [
        SubstationConfig(
          substationId: 'tgdog',
          ownedSubstations: const {'tgdog'},
          resident: _resident,
        ),
      ],
      git: buildDryTreeGitService(),
      workRoot: const RootCheckout(
        path: '',
        defaultBranch: 'main',
        substation: 'tgdog',
      ),
      groups: _FakeProcessGroupController(),
      freshnessBarrier: () async {},
      resolver: const CircuitResolver(_markerCircuitFor),
      registry: DefaultCapabilityRegistry(
        capabilities: const {_markerStep: _MarkerCap()},
        circuits: const {'marker': _markerCircuit},
      ),
    );
    return driveStation(
      wiring: wiring,
      sources: sources,
      args: StationArgs(
        substations: const {'tgdog'},
        stateSubstation: 'tgdog',
        dryRun: true,
        resident: _resident,
      ),
      out: (_) {},
      signals: signals.stream,
      lock: StationLockService(isPidAlive: (_) => false, log: (_) {}),
      controlStarter: _controlStarter,
    );
  }

  Future<void> dispose() async {
    await work.close();
    await provider.close();
    unawaited(signals.close());
  }
}

// --- a minimal never-live asset (mirrors station_lock_test's marker) --------

const String _markerStep = 'marker';

const Circuit _markerCircuit = Circuit(
  id: 'marker',
  terminalStepId: _markerStep,
  steps: [
    CapabilityStep(
      stepId: _markerStep,
      capabilityId: _markerStep,
      kind: StepKind.job,
    ),
  ],
);

Circuit _markerCircuitFor(Bead bead) => _markerCircuit;

class _MarkerCap extends ProcessCapability {
  const _MarkerCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'true'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}

/// A fake [SnapshotSource] — a broadcast controller + a settable current.
class _FakeSnapshotSource implements SnapshotSource {
  _FakeSnapshotSource([this._current]);

  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  final GraphSnapshot? _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  @override
  GraphSnapshot? get current => _current;

  Future<void> close() => _controller.close();
}

/// A no-op recording [RuntimeProvider] (no work is ever pushed here).
class _NoopProvider implements RuntimeProvider {
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();
  final Set<String> _running = <String>{};

  @override
  Future<void> start(String name, RuntimeConfig config) async {
    if (_running.contains(name)) throw SessionAlreadyExists(name);
    _running.add(name);
  }

  @override
  Future<void> stop(String name) async => _running.remove(name);

  @override
  Future<void> interrupt(String name) async {}

  @override
  Stream<RuntimeEvent> get events => _events.stream;

  @override
  Stream<String> output(String name) => const Stream<String>.empty();

  @override
  bool isRunning(String name) => _running.contains(name);

  @override
  bool processAlive(String name) => _running.contains(name);

  @override
  String peek(String name, int lines) => '';

  @override
  List<String> listRunning(String prefix) =>
      _running.where((n) => n.startsWith(prefix)).toList(growable: false);

  @override
  DateTime? lastActivity(String name) => null;

  @override
  RuntimeCapabilities get capabilities => RuntimeCapabilities.subprocess;

  Future<void> close() => _events.close();
}

/// A fake [ProcessGroupController] — never reached (the dry git service finds
/// no survivors), but required to construct the RestartReconciler.
class _FakeProcessGroupController implements ProcessGroupController {
  @override
  int currentGroupId() => 99999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}

/// A canned [BdRunner] (Fakes, not mocks): returns an OWNED session id so the
/// chokepoint's mint could run end-to-end; no real `bd` anywhere.
class _CannedBdRunner implements BdRunner {
  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    final sub = args.isNotEmpty ? args.first : '';
    final id = sub == 'create'
        ? 'tgdog-sess1'
        : (args.length >= 2 ? args[1] : '');
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}
