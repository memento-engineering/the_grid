import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/src/station_lock.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// RS-2 (D-A1, `docs/SCRATCH-resident-station.md` §4): the station lock —
/// ONE supervisor per station STATE store. Offline only: temp dirs, a fake
/// pid prober, injected signal streams; NO live stores, NO real
/// `claude`/`git`/`bd`. What this file locks (the acceptance criteria):
///
///  (a) a second acquire against a LIVE holder → [StationRefusal] naming the
///      pid + the one-supervisor invariant (+ the `space status` hint);
///  (b) a stale (dead-holder) lock is stolen with a LOUD line;
///  (c) release removes the file on the graceful paths (SIGINT AND SIGTERM);
///  (d) release fires on the `start()`-throw unwind (lock never wedges a
///      dead boot);
///  (e) the codec round-trips with and without the RS-4 control fields;
///  (f) the lock file is 0600 (it will carry the RS-4 bearer token).
///
/// (The lost-steal-race refusal — a re-minted lock between our delete and the
/// retried exclusive create — has no injectable seam between those two IO
/// calls; that fail-closed branch is deliberately uncovered.)
void main() {
  group('StationLockService.acquire — exclusive create', () {
    test('a fresh acquire mints the lock: pid/pgid/startedAt JSON, control '
        'fields ABSENT, mode 0600 (f)', () async {
      final store = _tempStore();
      final service = StationLockService(
        isPidAlive: (_) => fail('no collision — the probe must not run'),
        log: (_) {},
      );

      final handle = await service.acquire(
        stateWorkspaceDir: store.path,
        pid: 4242,
        pgid: 4242,
        now: DateTime.utc(2026, 7, 2, 12),
      );

      final lockFile = File(StationLockService.lockPath(store.path));
      expect(lockFile.existsSync(), isTrue);
      expect(handle.path, lockFile.path);
      final json =
          jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
      expect(json['pid'], 4242);
      expect(json['pgid'], 4242);
      expect(json['startedAt'], '2026-07-02T12:00:00.000Z');
      expect(
        json.containsKey('controlUrl'),
        isFalse,
        reason: 'absent control fields are OMITTED, not null (RS-4 forward)',
      );
      expect(json.containsKey('token'), isFalse);
      expect(_modeOf(lockFile.path), '600', reason: 'the bearer-token mode');
    });

    test('(a) a LIVE holder refuses: StationRefusal (exit 64) naming the '
        'holder pid, the store, the one-supervisor invariant, and the '
        '`space status` hint', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final probed = <int>[];
      final service = StationLockService(
        isPidAlive: (p) {
          probed.add(p);
          return true; // the holder is alive
        },
        log: (_) => fail('a live holder is never stolen'),
      );

      try {
        await service.acquire(
          stateWorkspaceDir: store.path,
          pid: 7777,
          pgid: 7777,
          now: DateTime.utc(2026, 7, 2),
        );
        fail('acquire against a live holder must refuse');
      } on StationRefusal catch (refusal) {
        expect(refusal.code, 64);
        expect(refusal.message, contains('pid 4242'));
        expect(refusal.message, contains(store.path));
        expect(
          refusal.message,
          contains('ONE supervisor per station state store'),
          reason: 'the refusal names the invariant (the guard principle)',
        );
        expect(refusal.message, contains('space status'));
      }
      expect(probed, [4242], reason: 'the seam probed the HOLDER pid');
      expect(
        jsonDecode(
          File(StationLockService.lockPath(store.path)).readAsStringSync(),
        ),
        containsPair('pid', 4242),
        reason: 'the live holder keeps its lock',
      );
    });

    test('(b) a DEAD holder is stolen with a LOUD line and the lock is '
        're-minted under the new pid', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final loud = <String>[];
      final service = StationLockService(
        isPidAlive: (_) => false, // the holder crashed without releasing
        log: loud.add,
      );

      final handle = await service.acquire(
        stateWorkspaceDir: store.path,
        pid: 7777,
        pgid: 7777,
        now: DateTime.utc(2026, 7, 2),
      );

      expect(
        loud.where(
          (l) => l.contains('STEALING stale station.lock')
              && l.contains('pid 4242 dead'),
        ),
        hasLength(1),
        reason: 'the steal is LOUD and names the dead pid',
      );
      expect(handle.record.pid, 7777);
      expect(
        jsonDecode(
          File(StationLockService.lockPath(store.path)).readAsStringSync(),
        ),
        containsPair('pid', 7777),
      );
      expect(_modeOf(handle.path), '600');
    });

    test('a corrupt (torn-write) lock is stolen LOUD without probing', () async {
      final store = _tempStore();
      Directory('${store.path}/.grid').createSync(recursive: true);
      File(StationLockService.lockPath(store.path))
          .writeAsStringSync('{"pid": tor'); // a crash mid-acquire
      final loud = <String>[];
      final service = StationLockService(
        isPidAlive: (_) => fail('no pid to probe in a torn lock'),
        log: loud.add,
      );

      final handle = await service.acquire(
        stateWorkspaceDir: store.path,
        pid: 7777,
        pgid: 7777,
        now: DateTime.utc(2026, 7, 2),
      );

      expect(
        loud.where((l) => l.contains('STEALING corrupt station.lock')),
        hasLength(1),
      );
      expect(handle.record.pid, 7777);
    });

    test('release deletes the lock; a second release is a no-op', () async {
      final store = _tempStore();
      final handle = await StationLockService(
        isPidAlive: (_) => true,
        log: (_) {},
      ).acquire(
        stateWorkspaceDir: store.path,
        pid: 7777,
        pgid: 7777,
        now: DateTime.utc(2026, 7, 2),
      );

      await handle.release();
      expect(File(handle.path).existsSync(), isFalse);
      await handle.release(); // idempotent — must not throw
    });

    test('updateControl (the RS-4 seam) writes controlUrl/token, preserves '
        'the identity fields, and keeps 0600', () async {
      final store = _tempStore();
      final handle = await StationLockService(
        isPidAlive: (_) => true,
        log: (_) {},
      ).acquire(
        stateWorkspaceDir: store.path,
        pid: 7777,
        pgid: 7676,
        now: DateTime.utc(2026, 7, 2, 12),
      );

      await handle.updateControl(
        controlUrl: 'http://127.0.0.1:8137',
        token: 's3cret',
      );

      final json = jsonDecode(File(handle.path).readAsStringSync())
          as Map<String, Object?>;
      expect(json['pid'], 7777);
      expect(json['pgid'], 7676);
      expect(json['startedAt'], '2026-07-02T12:00:00.000Z');
      expect(json['controlUrl'], 'http://127.0.0.1:8137');
      expect(json['token'], 's3cret');
      expect(_modeOf(handle.path), '600', reason: 'the token file stays 0600');
      expect(handle.record.token, 's3cret');
    });
  });

  group('StationLockRecord — the codec (e)', () {
    test('round-trips WITH the control fields', () {
      final full = StationLockRecord(
        pid: 1,
        pgid: 2,
        startedAt: DateTime.utc(2026, 7, 2),
      ).withControl(controlUrl: 'http://127.0.0.1:9', token: 't');
      final back = StationLockRecord.fromJson(
        jsonDecode(jsonEncode(full.toJson())) as Map<String, Object?>,
      );
      expect(back.pid, 1);
      expect(back.pgid, 2);
      expect(back.startedAt, DateTime.utc(2026, 7, 2));
      expect(back.controlUrl, 'http://127.0.0.1:9');
      expect(back.token, 't');
    });

    test('round-trips WITHOUT the control fields (absent keys, null fields)', () {
      final record = StationLockRecord(
        pid: 3,
        pgid: 4,
        startedAt: DateTime.utc(2026, 1, 1),
      );
      final json = record.toJson();
      expect(json.containsKey('controlUrl'), isFalse);
      expect(json.containsKey('token'), isFalse);
      final back = StationLockRecord.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(back.pid, 3);
      expect(back.pgid, 4);
      expect(back.controlUrl, isNull);
      expect(back.token, isNull);
    });

    test('tolerates unknown extra keys (forward-compatible)', () {
      final back = StationLockRecord.fromJson(<String, Object?>{
        'pid': 5,
        'pgid': 6,
        'startedAt': '2026-07-02T00:00:00.000Z',
        'someFutureField': 'ignored',
      });
      expect(back.pid, 5);
      expect(back.token, isNull);
    });
  });

  group('defaultPidProbe — the REAL seam (still offline: kill -0)', () {
    test('this process is alive; a reaped child is dead', () async {
      expect(defaultPidProbe(pid), isTrue);
      final child = await Process.start('sh', ['-c', 'true']);
      await child.exitCode;
      expect(defaultPidProbe(child.pid), isFalse);
    });
  });

  group('driveStation — the lock rides the run (c, d)', () {
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      test('(c) the lock is held while parked and RELEASED by the graceful '
          '$signal path', () async {
        final store = _tempStore();
        final h = _LockHarness(store: store);
        addTearDown(h.dispose);

        final run = h.drive();
        final lockFile = File(StationLockService.lockPath(store.path));
        await _until(
          () => _pidIn(lockFile) == pid,
          'the parked station to hold the lock naming THIS supervisor',
        );

        h.signals.add(signal);
        final code = await run.timeout(const Duration(seconds: 10));
        expect(code, 0);
        expect(
          lockFile.existsSync(),
          isFalse,
          reason: 'the graceful path released the lock',
        );
      });
    }

    test('(a) a second driveStation over the SAME store refuses while the '
        'first is parked — the double-supervisor story', () async {
      final store = _tempStore();
      final first = _LockHarness(store: store);
      addTearDown(first.dispose);
      final run = first.drive();
      final lockFile = File(StationLockService.lockPath(store.path));
      await _until(
        () => _pidIn(lockFile) == pid,
        'the first supervisor to hold the lock',
      );

      final second = _LockHarness(store: store);
      addTearDown(second.dispose);
      // The real defaultPidProbe: the holder pid is THIS process — alive.
      await expectLater(
        second.drive(lock: StationLockService(log: second.lines.add)),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(
              contains('pid $pid'),
              contains('ONE supervisor per station state store'),
            ),
          ),
        ),
      );

      // The first supervisor is undisturbed and still drains gracefully.
      expect(lockFile.existsSync(), isTrue);
      first.signals.add(ProcessSignal.sigint);
      expect(await run.timeout(const Duration(seconds: 10)), 0);
      expect(lockFile.existsSync(), isFalse);
    });

    test('(d) the start()-throw unwind releases the lock and rethrows '
        '(acquire happened BEFORE start — asserted inside the throw)', () async {
      final store = _tempStore();
      final lockFile = File(StationLockService.lockPath(store.path));
      final h = _LockHarness(
        store: store,
        sourcesStart: () async {
          expect(
            lockFile.existsSync(),
            isTrue,
            reason: 'acquired after validateArming, BEFORE sources.start()',
          );
          throw StateError('controller boot failed');
        },
      );
      addTearDown(h.dispose);

      await expectLater(h.drive(), throwsA(isA<StateError>()));
      expect(
        lockFile.existsSync(),
        isFalse,
        reason: 'a lock naming a dead boot would wedge the next `up`',
      );
    });

    test('no state workspace ⇒ no store to guard ⇒ the lock service is '
        'never asked', () async {
      final h = _LockHarness(store: null);
      addTearDown(h.dispose);

      final run = h.drive(lock: _MustNotAcquireLockService());
      // The single-subscription controller buffers until driveStation parks.
      h.signals.add(ProcessSignal.sigterm);
      expect(await run.timeout(const Duration(seconds: 10)), 0);
    });
  });
}

/// A temp state-store root (no `.grid/` yet — acquire creates it).
Directory _tempStore() {
  final dir = Directory.systemTemp.createTempSync('station-lock-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Pre-mints a well-formed lock as an EARLIER supervisor left it.
void _mintLock(Directory store, {required int pid}) {
  Directory('${store.path}/.grid').createSync(recursive: true);
  File(StationLockService.lockPath(store.path)).writeAsStringSync(
    jsonEncode(
      StationLockRecord(
        pid: pid,
        pgid: pid,
        startedAt: DateTime.utc(2026, 7, 1),
      ).toJson(),
    ),
  );
}

/// The POSIX permission bits of [path], octal (e.g. `600`).
String _modeOf(String path) =>
    (FileStat.statSync(path).mode & 0xFFF).toRadixString(8);

/// The holder pid in a fully-written lock file, or null while the file is
/// absent or mid-write (the acquire spans a chmod subprocess — polling on the
/// parsed pid is the race-free "acquired" signal).
int? _pidIn(File lockFile) {
  try {
    final json = jsonDecode(lockFile.readAsStringSync());
    return (json as Map<String, Object?>)['pid'] as int?;
  } on Object {
    return null;
  }
}

/// Polls [condition] (driveStation's boot spans real async work — the banner's
/// VM-service call + the lock's chmod subprocess) up to a bounded deadline.
Future<void> _until(bool Function() condition, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The offline lock harness: a composed dry station (mirrors the RS-1 signal
/// harness) whose [StationSources] carry a temp-dir state workspace, parked by
/// [drive] on an injected signal stream — nothing live anywhere.
class _LockHarness {
  _LockHarness({required Directory? store, Future<void> Function()? sourcesStart})
    : _store = store,
      _sourcesStart = sourcesStart;

  static const StationArgs args = StationArgs(
    substations: {'tgdog'},
    stateSubstation: 'tgdog',
    dryRun: true,
  );

  final Directory? _store;
  final Future<void> Function()? _sourcesStart;

  /// The injected signal seam.
  final StreamController<ProcessSignal> signals =
      StreamController<ProcessSignal>();

  /// Every `out` line driveStation wrote (banner + lock log + shutdown).
  final List<String> lines = <String>[];

  final _FakeSnapshotSource work = _FakeSnapshotSource();
  late final _NoopProvider provider = _NoopProvider();

  late final StationSources sources = StationSources(
    work: work,
    stateWorkspace: _store == null
        ? null
        : BeadsWorkspace(
            root: _store.path,
            mode: DoltMode.direct,
            database: null,
            gtRoot: null,
            endpoint: null,
          ),
    start: _sourcesStart,
  );

  /// Composes the dry station and parks it (run-forever) on [signals].
  /// [lock] defaults to a service over a fake always-dead probe (fresh temp
  /// stores never collide; the collision tests inject their own).
  Future<int> drive({StationLockService? lock}) {
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
      substations: const [
        SubstationConfig(substationId: 'tgdog', ownedSubstations: {'tgdog'}),
      ],
      git: buildDryTreeGitService(),
      workRoot: const RootCheckout(
        path: '',
        defaultBranch: 'main',
        substation: 'tgdog',
      ),
      groups: _FakeProcessGroupController(),
      freshnessBarrier: () async {},
      resolver: const FormulaResolver(_markerFormulaFor),
      registry: DefaultCapabilityRegistry(
        capabilities: const {_markerStep: _MarkerCap()},
        formulas: const {'marker': _markerFormula},
      ),
    );
    return driveStation(
      wiring: wiring,
      sources: sources,
      args: args,
      out: lines.add,
      signals: signals.stream,
      lock:
          lock ??
          StationLockService(isPidAlive: (_) => false, log: lines.add),
    );
  }

  Future<void> dispose() async {
    await work.close();
    await provider.close();
    // NOT awaited: when driveStation refuses/unwinds BEFORE parking, nothing
    // ever listens to this single-subscription controller, and close()'s done
    // future then never completes.
    unawaited(signals.close());
  }
}

/// The no-state-store guard: asked ⇒ the wiring is wrong.
class _MustNotAcquireLockService extends StationLockService {
  _MustNotAcquireLockService() : super(isPidAlive: (_) => false, log: (_) {});

  @override
  Future<StationLockHandle> acquire({
    required String stateWorkspaceDir,
    required int pid,
    required int pgid,
    required DateTime now,
  }) => fail('no state workspace ⇒ driveStation must not acquire a lock');
}

// --- a minimal never-live asset (mirrors station_signals_test's marker) -----

const String _markerStep = 'marker';

const Formula _markerFormula = Formula(
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

Formula _markerFormulaFor(Bead bead) => _markerFormula;

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
  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();
  GraphSnapshot? _current;

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
