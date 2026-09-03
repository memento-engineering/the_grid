import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_lock.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:test/test.dart';

/// tg-o2fy — the station lock's ATOMICITY pins (D-A1 + decision
/// `the_grid#station-lock-holds-never-steals-an-unreadable-record`). The P0:
/// `acquire` used to exclusive-create the lock, await a chmod SUBPROCESS, and
/// only THEN write the JSON — a process-spawn-wide window in which a second
/// acquirer read the file, failed to parse it, called it corrupt, and DELETED
/// the winner's lock. Two supervisors over one state store.
void main() {
  group('the populate window (the P0)', () {
    test('a second acquirer that collides mid-populate sees the claim EMPTY, '
        'holds, and then refuses the LIVE holder — the first acquirer keeps '
        'its lock', () async {
      final store = _tempStore();
      final lockFile = File(StationLockService.lockPath(store.path));
      final chmodEntered = Completer<void>();
      final releaseChmod = Completer<void>();

      final first = StationLockService(
        isPidAlive: (_) => fail('the first acquirer has no collision'),
        log: (_) {},
        prepareProcessGroup: (stationPid) async => stationPid,
        setMode: (path) async {
          if (!chmodEntered.isCompleted) chmodEntered.complete();
          await releaseChmod.future; // a chmod that takes forever
          await defaultChmod600(path); // then the REAL mode lands
        },
      ).acquire(
        stateWorkspaceDir: store.path,
        pid: 4242,
        now: DateTime.utc(2026, 9, 3, 10),
      );

      await chmodEntered.future;
      expect(lockFile.existsSync(), isTrue, reason: 'the claim is on disk');
      expect(
        lockFile.readAsStringSync(),
        isEmpty,
        reason: 'the claim carries NO content — the record rides a temp',
      );

      final probed = <int>[];
      final delays = <Duration>[];
      final second = StationLockService(
        isPidAlive: (p) {
          probed.add(p);
          return true;
        },
        log: (_) {},
        prepareProcessGroup: (stationPid) async => stationPid,
        delay: (d) async {
          delays.add(d);
          if (!releaseChmod.isCompleted) releaseChmod.complete();
          await first; // the first acquirer finishes publishing
        },
      );

      await expectLater(
        second.acquire(
          stateWorkspaceDir: store.path,
          pid: 7777,
          now: DateTime.utc(2026, 9, 3, 11),
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(contains('pid 4242'), contains('LIVE supervisor')),
          ),
        ),
      );

      expect(delays, [const Duration(milliseconds: 100)]);
      expect(probed, [4242], reason: 'it probed the REAL holder, once');
      final json =
          jsonDecode(lockFile.readAsStringSync()) as Map<String, Object?>;
      expect(json['pid'], 4242, reason: 'the winner kept its lock');
      expect(_modeOf(lockFile.path), '600');
      await (await first).release();
    });

    test('an unreadable record is re-probed on a doubling backoff and then '
        'REFUSED — the file is never deleted', () async {
      final store = _tempStore();
      Directory('${store.path}/.grid').createSync(recursive: true);
      final lockFile = File(StationLockService.lockPath(store.path))
        ..writeAsStringSync('{"pid": tor');
      final delays = <Duration>[];
      final loud = <String>[];

      await expectLater(
        StationLockService(
          isPidAlive: (_) => fail('no pid to probe'),
          log: loud.add,
          prepareProcessGroup: (stationPid) async => stationPid,
          delay: (d) async => delays.add(d),
        ).acquire(
          stateWorkspaceDir: store.path,
          pid: 7777,
          now: DateTime.utc(2026, 9, 3),
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(contains('UNREADABLE'), contains(lockFile.path)),
          ),
        ),
      );

      expect(delays, const [
        Duration(milliseconds: 100),
        Duration(milliseconds: 200),
        Duration(milliseconds: 400),
        Duration(milliseconds: 800),
        Duration(milliseconds: 1600),
      ], reason: 'the doubling hold, bounded by the 2s window');
      expect(lockFile.readAsStringSync(), '{"pid": tor');
      expect(loud.any((l) => l.contains('UNREADABLE')), isTrue);
    });

    test('a PARSEABLE record with a dead pid is still stolen LOUDLY, with no '
        'hold at all', () async {
      final store = _tempStore();
      _mintLock(store, pid: 4242, startedAt: DateTime.utc(2026, 9, 2));
      final loud = <String>[];
      final delays = <Duration>[];

      final handle = await StationLockService(
        isPidAlive: (_) => false,
        log: loud.add,
        prepareProcessGroup: (stationPid) async => stationPid,
        delay: (d) async => delays.add(d),
      ).acquire(
        stateWorkspaceDir: store.path,
        pid: 7777,
        now: DateTime.utc(2026, 9, 3),
      );

      expect(delays, isEmpty, reason: 'a readable record is arbitrated at once');
      expect(
        loud.where(
          (l) =>
              l.contains('STEALING stale station.lock') &&
              l.contains('pid 4242 dead'),
        ),
        hasLength(1),
      );
      expect(handle.record.pid, 7777);
    });
  });

  group('ownership is re-verified before every write', () {
    test('updateControl refuses a FOREIGN pid and leaves the file intact', () async {
      final store = _tempStore();
      final handle = await _acquire(store, pid: 7777);
      _mintLock(store, pid: 4242, startedAt: DateTime.utc(2026, 9, 2));

      await expectLater(
        handle.updateControl(
          controlUrl: 'http://127.0.0.1:8137',
          token: 's3cret',
        ),
        throwsA(
          isA<StationRefusal>().having(
            (r) => r.message,
            'message',
            allOf(contains('updateControl'), contains('NOT ours')),
          ),
        ),
      );
      final json =
          jsonDecode(File(handle.path).readAsStringSync())
              as Map<String, Object?>;
      expect(json['pid'], 4242, reason: 'the re-minted lock is untouched');
      expect(json.containsKey('token'), isFalse);
      expect(handle.record.token, isNull, reason: 'no in-memory advance');
    });

    test('updateVmService refuses a re-mint under the SAME pid (startedAt is '
        'half the nonce)', () async {
      final store = _tempStore();
      final handle = await _acquire(store, pid: 7777);
      _mintLock(store, pid: 7777, startedAt: DateTime.utc(2026, 9, 3, 23));

      await expectLater(
        handle.updateVmService('http://127.0.0.1:1234/tok=/'),
        throwsA(isA<StationRefusal>()),
      );
      expect(handle.record.vmServiceUri, isNull);
    });

    test('release refuses to delete a record that is not ours, LOUDLY', () async {
      final store = _tempStore();
      final loud = <String>[];
      final handle = await _acquire(store, pid: 7777, log: loud.add);
      _mintLock(store, pid: 4242, startedAt: DateTime.utc(2026, 9, 2));

      await handle.release();

      expect(File(handle.path).existsSync(), isTrue);
      expect(
        loud.where(
          (l) => l.contains('NOT releasing station.lock') && l.contains('4242'),
        ),
        hasLength(1),
      );
    });

    test('release still deletes OUR record and stays idempotent', () async {
      final store = _tempStore();
      final handle = await _acquire(store, pid: 7777);
      await handle.release();
      expect(File(handle.path).existsSync(), isFalse);
      await handle.release();
    });
  });

  group('the mode is terminal', () {
    test('a chmod failure aborts acquire and leaves NO lock and NO temp', () async {
      final store = _tempStore();
      final loud = <String>[];

      await expectLater(
        StationLockService(
          isPidAlive: (_) => fail('no collision'),
          log: loud.add,
          prepareProcessGroup: (stationPid) async => stationPid,
          setMode: (path) async =>
              throw FileSystemException('chmod 600 failed (exit 1)', path),
        ).acquire(
          stateWorkspaceDir: store.path,
          pid: 7777,
          now: DateTime.utc(2026, 9, 3),
        ),
        throwsA(
          isA<StationRefusal>()
              .having((r) => r.code, 'code', 1)
              .having((r) => r.message, 'message', contains('chmod 600')),
        ),
      );

      expect(loud.where((l) => l.contains('could NOT chmod 600')), hasLength(1));
      expect(
        File(StationLockService.lockPath(store.path)).existsSync(),
        isFalse,
      );
      expect(
        Directory(
          '${store.path}/.grid',
        ).listSync().where((e) => e.path.contains('station.lock')),
        isEmpty,
        reason: 'no claim and no temp survive a failed publish',
      );
    });

    test('a published lock is 0600 and leaves no temp behind', () async {
      final store = _tempStore();
      final handle = await _acquire(store, pid: 7777);
      await handle.updateControl(
        controlUrl: 'http://127.0.0.1:8137',
        token: 's3cret',
      );

      expect(_modeOf(handle.path), '600');
      expect(
        Directory('${store.path}/.grid')
            .listSync()
            .map((e) => e.path.split('/').last)
            .where((n) => n.startsWith('station.lock.tmp')),
        isEmpty,
      );
      expect(handle.record.token, 's3cret');
    });
  });
}

/// Acquires a lock with the REAL chmod and no collision expected.
Future<StationLockHandle> _acquire(
  Directory store, {
  required int pid,
  void Function(String)? log,
}) => StationLockService(
  isPidAlive: (_) => true,
  log: log ?? (_) {},
  prepareProcessGroup: (stationPid) async => stationPid,
).acquire(
  stateWorkspaceDir: store.path,
  pid: pid,
  now: DateTime.utc(2026, 9, 3, 12),
);

/// A temp state-store root (no `.grid/` yet — acquire creates it).
Directory _tempStore() {
  final dir = Directory.systemTemp.createTempSync('station-lock-race-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Overwrites the lock with a well-formed record from ANOTHER supervisor.
void _mintLock(
  Directory store, {
  required int pid,
  required DateTime startedAt,
}) {
  Directory('${store.path}/.grid').createSync(recursive: true);
  File(StationLockService.lockPath(store.path)).writeAsStringSync(
    jsonEncode(
      StationLockRecord(pid: pid, pgid: pid, startedAt: startedAt).toJson(),
    ),
  );
}

/// The POSIX permission bits of [path], octal (e.g. `600`).
String _modeOf(String path) =>
    (FileStat.statSync(path).mode & 0xFFF).toRadixString(8);
