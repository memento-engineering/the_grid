import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_lock.dart';
import 'package:test/test.dart';

/// RS-2 (D-A1, `docs/SCRATCH-resident-station.md` §4): the station lock —
/// ONE supervisor per station STATE store. Offline only: temp dirs, a fake
/// pid prober; NO live stores, NO real `claude`/`git`/`bd`. What this file
/// locks (the acceptance criteria):
///
///  (a) a second acquire against a LIVE holder → [StationRefusal] naming the
///      pid + the one-supervisor invariant (+ the `space status` hint);
///  (b) a stale (dead-holder) lock is stolen with a LOUD line;
///  (c) release removes the file and is idempotent;
///  (d) the codec round-trips with and without the RS-4 control fields;
///  (e) the lock file is 0600 (it will carry the RS-4 bearer token).
///
/// (The lost-steal-race refusal — a re-minted lock between our delete and the
/// retried exclusive create — has no injectable seam between those two IO
/// calls; that fail-closed branch is deliberately uncovered. The runner's
/// graceful-shutdown/boot-unwind release choreography around this lock lives
/// in the asset's own runner — e.g. space_station's `up` — not here.)
void main() {
  group('StationLockService.acquire — exclusive create', () {
    test('a fresh acquire mints the lock: pid/pgid/startedAt JSON, control '
        'fields ABSENT, mode 0600 (e)', () async {
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

    test('(c) release deletes the lock; a second release is a no-op', () async {
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

  group('StationLockRecord — the codec (d)', () {
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
