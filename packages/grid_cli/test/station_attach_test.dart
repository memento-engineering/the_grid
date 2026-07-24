import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_attach.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_cli/src/station_lock.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// RS-5a (tg-3s8.5, D-C3/D-C4, `docs/SCRATCH-resident-station.md` §3):
/// `StationAttach` — the thin attach client. Offline only: temp lock files +
/// a REAL ephemeral-port [StationControl]; a fake pid prober/signaller/
/// clock; NO live stores, NO real `claude`/`git`/`bd`. What this file locks
/// (the acceptance criteria):
///
///  (a) the up/down/stale/unauthorized matrix, against a real
///      ephemeral-port [StationControl] + temp locks;
///  (b) `stop` is SIGTERM-only, bounded, LOUD-by-type on timeout (a distinct
///      [TimedOut] variant, never silently collapsed into [Stopped]), a
///      clean [AlreadyDown] no-op;
///  (c) 401 surfaces as [Unauthorized], distinct from [Stale] — never
///      swallowed;
///  (d) no mutation path exists in the client — a construction property:
///      [StationAttach.status] only ever issues a `GET`, and
///      [StationAttach.stop] only ever signals + reads; neither writes,
///      deletes, or rewrites the lock file itself (asserted per-case below
///      where a test can observe the lock file surviving/absent as
///      expected).
void main() {
  group('StationAttach.status — the up/down/stale/unauthorized matrix (a)', () {
    test('no lock file at all → Down', () async {
      final store = _tempStore();
      final attach = StationAttach(
        isPidAlive: (_) => fail('no lock ⇒ no pid to probe'),
      );

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Down>());
    });

    test('a corrupt (torn-write) lock → Down, no pid probed', () async {
      final store = _tempStore();
      Directory('${store.path}/.grid').createSync(recursive: true);
      File(
        StationLockService.lockPath(store.path),
      ).writeAsStringSync('{"pid": tor');
      final attach = StationAttach(
        isPidAlive: (_) => fail('a torn lock names no holder to probe'),
      );

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Down>());
    });

    test('a lock naming a DEAD pid → Stale(pid), no HTTP attempted', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final probed = <int>[];
      final attach = StationAttach(
        isPidAlive: (p) {
          probed.add(p);
          return false;
        },
        httpClientFactory: () => fail('a dead pid must never reach HTTP'),
      );

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Stale>());
      expect((result as Stale).pid, 4242);
      expect(probed, [4242]);
    });

    test('a live pid but no controlUrl/token yet (RS-2-only lock, a '
        'boot-order race) → Stale(pid)', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242); // no controlUrl/token
      final attach = StationAttach(
        isPidAlive: (_) => true,
        httpClientFactory: () =>
            fail('nothing to attach to before control is advertised'),
      );

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Stale>());
      expect((result as Stale).pid, 4242);
    });

    test('a live pid, a live control surface, the right bearer → Up '
        '(the decoded /status payload)', () async {
      final store = _tempStore();
      final control = await StationControl.start(
        port: 0,
        token: 'right-token',
        view: () => _sampleStatus,
      );
      addTearDown(control.dispose);
      _mintLock(
        store,
        pid: 4242,
        controlUrl: control.url,
        token: 'right-token',
      );
      final attach = StationAttach(isPidAlive: (_) => true);

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Up>());
      final up = result as Up;
      expect(up.record.pid, 4242);
      expect(up.payload['station'], isA<Map<String, Object?>>());
      expect(
        (up.payload['station']! as Map<String, Object?>)['substation'],
        'tgdog',
      );
    });

    test('(c) a live pid, a live control surface, the WRONG bearer → '
        'Unauthorized — DISTINCT from Stale, never swallowed', () async {
      final store = _tempStore();
      final control = await StationControl.start(
        port: 0,
        token: 'right-token',
        view: () => _sampleStatus,
      );
      addTearDown(control.dispose);
      _mintLock(
        store,
        pid: 4242,
        controlUrl: control.url,
        token: 'wrong-token',
      );
      final attach = StationAttach(isPidAlive: (_) => true);

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Unauthorized>());
      expect((result as Unauthorized).record.pid, 4242);
    });

    test('a live pid but connection-refused (the control surface died '
        'without releasing the lock) → Stale(pid)', () async {
      final store = _tempStore();
      final control = await StationControl.start(
        port: 0,
        token: 't',
        view: () => _sampleStatus,
      );
      final deadUrl = control.url;
      await control.dispose(); // the port is now refusing connections
      _mintLock(store, pid: 4242, controlUrl: deadUrl, token: 't');
      final attach = StationAttach(isPidAlive: (_) => true);

      final result = await attach.status(stateWorkspaceDir: store.path);

      expect(result, isA<Stale>());
      expect((result as Stale).pid, 4242);
    });

    test('a live pid but the control surface never answers (hangs) → '
        'Stale(pid) once the bounded timeout elapses', () async {
      final store = _tempStore();
      final serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final accepted = <Socket>[];
      final sub = serverSocket.listen(accepted.add); // accept, never respond
      addTearDown(() async {
        await sub.cancel();
        for (final s in accepted) {
          s.destroy();
        }
        await serverSocket.close();
      });
      _mintLock(
        store,
        pid: 4242,
        controlUrl: 'http://127.0.0.1:${serverSocket.port}',
        token: 't',
      );
      final attach = StationAttach(isPidAlive: (_) => true);

      final result = await attach.status(
        stateWorkspaceDir: store.path,
        timeout: const Duration(milliseconds: 200),
      );

      expect(result, isA<Stale>());
      expect((result as Stale).pid, 4242);
    });
  });

  group('StationAttach.stop — SIGTERM-only, bounded, LOUD-by-type (b)', () {
    test('matching member pid uses the recorded group', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final lockFile = File(StationLockService.lockPath(store.path));
      var alive = true;
      late final _FakeGroups groups;
      groups = _FakeGroups(
        resolvedPgid: 4242,
        ownGroupId: 9999,
        onSignal: () {
          alive = false;
          lockFile.deleteSync();
        },
      );
      final attach = StationAttach(
        isPidAlive: (_) => alive,
        groups: groups,
        signal: (pid, signal) => fail('owned group must not use pid fallback'),
        log: (_) => fail('owned group must not log fallback'),
      );

      final result = await attach.stop(
        stateWorkspaceDir: store.path,
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(result, isA<Stopped>());
      expect(groups.signals, <(int, ProcessSignal)>[
        (4242, ProcessSignal.sigterm),
      ]);
    });

    for (final scenario
        in <({String name, int? actualPgid, int recordedPgid, int ownGroupId})>[
          (
            name: 'mismatched member',
            actualPgid: 700,
            recordedPgid: 4242,
            ownGroupId: 9999,
          ),
          (
            name: 'invalid group',
            actualPgid: 1,
            recordedPgid: 1,
            ownGroupId: 9999,
          ),
          (
            name: 'down command own group',
            actualPgid: 4242,
            recordedPgid: 4242,
            ownGroupId: 4242,
          ),
        ]) {
      test('${scenario.name} falls back loudly to pid only', () async {
        final store = _tempStore();
        _mintLock(store, pid: 4242, pgid: scenario.recordedPgid);
        final lockFile = File(StationLockService.lockPath(store.path));
        final groups = _FakeGroups(
          resolvedPgid: scenario.actualPgid,
          ownGroupId: scenario.ownGroupId,
        );
        final loud = <String>[];
        final pidSignals = <(int, ProcessSignal)>[];
        var alive = true;
        final attach = StationAttach(
          isPidAlive: (_) => alive,
          groups: groups,
          log: loud.add,
          signal: (target, signal) {
            pidSignals.add((target, signal));
            alive = false;
            lockFile.deleteSync();
            return true;
          },
        );

        final result = await attach.stop(
          stateWorkspaceDir: store.path,
          pollInterval: const Duration(milliseconds: 1),
        );

        expect(result, isA<Stopped>());
        expect(groups.signals, isEmpty);
        expect(pidSignals, <(int, ProcessSignal)>[
          (4242, ProcessSignal.sigterm),
        ]);
        expect(
          loud.single,
          allOf(
            contains('pid 4242'),
            contains('recorded pgid ${scenario.recordedPgid}'),
            contains('actual pgid ${scenario.actualPgid}'),
          ),
        );
      });
    }

    test('no lock file → AlreadyDown, no signal sent', () async {
      final store = _tempStore();
      final signalled = <(int, ProcessSignal)>[];
      final attach = StationAttach(
        isPidAlive: (_) => fail('no lock ⇒ no pid to probe'),
        signal: (pid, sig) {
          signalled.add((pid, sig));
          return true;
        },
      );

      final result = await attach.stop(stateWorkspaceDir: store.path);

      expect(result, isA<AlreadyDown>());
      expect(signalled, isEmpty);
    });

    test('a corrupt lock → AlreadyDown, no signal sent', () async {
      final store = _tempStore();
      Directory('${store.path}/.grid').createSync(recursive: true);
      File(
        StationLockService.lockPath(store.path),
      ).writeAsStringSync('{"pid": tor');
      final signalled = <(int, ProcessSignal)>[];
      final attach = StationAttach(
        isPidAlive: (_) => fail('a torn lock names no holder to signal'),
        signal: (pid, sig) {
          signalled.add((pid, sig));
          return true;
        },
      );

      final result = await attach.stop(stateWorkspaceDir: store.path);

      expect(result, isA<AlreadyDown>());
      expect(signalled, isEmpty);
    });

    test('a lock naming an already-DEAD pid → AlreadyDown, no signal sent '
        '(nothing live to stop)', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final signalled = <(int, ProcessSignal)>[];
      final attach = StationAttach(
        isPidAlive: (_) => false,
        signal: (pid, sig) {
          signalled.add((pid, sig));
          return true;
        },
      );

      final result = await attach.stop(stateWorkspaceDir: store.path);

      expect(result, isA<AlreadyDown>());
      expect(signalled, isEmpty);
    });

    test('a live pid: SIGTERM sent exactly once; the target exits AND '
        'releases its lock within the grace window → Stopped(pid)', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final lockFile = File(StationLockService.lockPath(store.path));
      final signalled = <(int, ProcessSignal)>[];
      var alive = true;
      final attach = StationAttach(
        isPidAlive: (_) => alive,
        signal: (pid, sig) {
          signalled.add((pid, sig));
          // The target runner's own graceful-shutdown path: it
          // exits AND releases its lock — simulated synchronously so this
          // test needs no real wall-clock wait.
          alive = false;
          lockFile.deleteSync();
          return true;
        },
      );

      final result = await attach.stop(
        stateWorkspaceDir: store.path,
        grace: const Duration(seconds: 5),
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(result, isA<Stopped>());
      expect((result as Stopped).pid, 4242);
      expect(signalled, [(4242, ProcessSignal.sigterm)]);
    });

    test('NEVER escalates to SIGKILL — only ProcessSignal.sigterm is ever '
        'sent', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242);
      final lockFile = File(StationLockService.lockPath(store.path));
      final signalled = <ProcessSignal>[];
      var alive = true;
      final attach = StationAttach(
        isPidAlive: (_) => alive,
        signal: (pid, sig) {
          signalled.add(sig);
          alive = false;
          lockFile.deleteSync();
          return true;
        },
      );

      await attach.stop(
        stateWorkspaceDir: store.path,
        pollInterval: const Duration(milliseconds: 1),
      );

      expect(signalled, everyElement(ProcessSignal.sigterm));
    });

    test(
      'the grace window elapses before exit+lock-removal → TimedOut(pid), '
      'a DISTINCT sealed variant (LOUD-by-type) — and the injected clock '
      'is honored (a 30s grace, but this test waits ZERO real time)',
      () async {
        final store = _tempStore();
        _mintLock(store, pid: 4242);
        var clockCalls = 0;
        DateTime clock() {
          clockCalls++;
          // Call 1 establishes `deadline = start + grace`; every call after
          // that (the loop's own deadline check) is already far past it —
          // proves the loop consults the injected clock, not a real timer.
          return clockCalls == 1
              ? DateTime.utc(2026, 7, 2)
              : DateTime.utc(2027, 1, 1);
        }

        final attach = StationAttach(
          isPidAlive: (_) => true, // never exits
          signal: (pid, sig) => true,
          clock: clock,
        );

        final result = await attach.stop(
          stateWorkspaceDir: store.path,
          grace: const Duration(seconds: 30),
          pollInterval: const Duration(milliseconds: 1),
        );

        expect(result, isA<TimedOut>());
        expect((result as TimedOut).pid, 4242);
        expect(clockCalls, greaterThan(1));
      },
    );
  });
}

/// A temp state-store root (no `.grid/` yet — `_mintLock` creates it).
Directory _tempStore() {
  final dir = Directory.systemTemp.createTempSync('station-attach-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Pre-mints a well-formed lock as a (possibly RS-4-advertising) supervisor
/// left it. Omitting [controlUrl]/[token] mirrors a lock read before the
/// control surface finished advertising itself.
void _mintLock(
  Directory store, {
  required int pid,
  int? pgid,
  String? controlUrl,
  String? token,
}) {
  Directory('${store.path}/.grid').createSync(recursive: true);
  var record = StationLockRecord(
    pid: pid,
    pgid: pgid ?? pid,
    startedAt: DateTime.utc(2026, 7, 2),
  );
  if (controlUrl != null && token != null) {
    record = record.withControl(controlUrl: controlUrl, token: token);
  }
  File(
    StationLockService.lockPath(store.path),
  ).writeAsStringSync(jsonEncode(record.toJson()));
}

class _FakeGroups implements ProcessGroupController {
  _FakeGroups({
    required this.resolvedPgid,
    required this.ownGroupId,
    this.onSignal,
  });

  final int? resolvedPgid;
  final int ownGroupId;
  final void Function()? onSignal;
  final List<(int, ProcessSignal)> signals = <(int, ProcessSignal)>[];

  @override
  int currentGroupId() => ownGroupId;

  @override
  bool processAlive(int pid) => true;

  @override
  Future<int?> resolvePgid(int pid) async => resolvedPgid;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add((pgid, signal));
    onSignal?.call();
    return true;
  }
}

StationStatus get _sampleStatus => StationStatus(
  substation: 'tgdog',
  stateStore: '/tmp/tgdog-state',
  workRoot: '/tmp/root',
  dryRun: true,
  pid: 4242,
  startedAt: DateTime.utc(2026, 7, 2),
  version: 'test-vm',
  ready: 1,
  mounted: 1,
  liveSessions: 0,
  lastSyncAt: null,
);
