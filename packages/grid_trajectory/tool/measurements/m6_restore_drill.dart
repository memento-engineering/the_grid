/// M6 — the two-database restore drill, end to end (storage-call.md stage-0
/// item 6).
///
/// The storage call's backup contract is "one snapshot procedure over
/// `.beads/dolt/` (server quiesced), both databases always as a pair", and
/// its restore contract is "both databases to the paired time, then mandatory
/// fold rebuild, liveness `unknown` until the next beat, head re-stamp repair
/// pass". This runs exactly that, and checks each clause:
///
///   1. seed both databases, fold, and stamp a ledger-side `last_seq` head
///      pointer (the only cross-database consistency seam this shape has);
///   2. quiesce the server, snapshot the WHOLE data dir as one unit;
///   3. keep writing afterwards, so the restore genuinely rolls time back;
///   4. destroy both databases, restore the pair, restart;
///   5. run the mandatory replay, then read `traj show` and `foldStaleness`;
///   6. detect the head pointer that now outruns the restored log, and
///      document what liveness reads.
///
/// Run: `dart run tool/measurements/m6_restore_drill.dart`
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

const String station = 'm6';

Future<void> main() async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm6'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  banner('M6 — two-database restore drill');
  final server = await MeasurementServer.start(scratchDir: scratch.path);
  say('hermetic server on ${MeasurementServer.host}:${server.port}');

  // ── 1. seed the pair ──────────────────────────────────────────────────
  final admin = await TrajectoryConnection.connect(server.admin);
  await createTrajectoryDatabase(admin);
  await admin.execute('CREATE DATABASE IF NOT EXISTS ledger');
  var ledger = await TrajectoryConnection.connect(server.endpointFor('ledger'));
  await seedLedgerDatabase(admin, ledger, issues: 500);
  // The head stamp: the ledger's own record of how far it has read the
  // trajectory log. Nothing transactional couples it to trajectory — that is
  // the whole point of the seam, and why a restore needs a repair pass.
  await ledger.execute('''
CREATE TABLE IF NOT EXISTS grid_head (
  station    VARCHAR(64) NOT NULL PRIMARY KEY,
  last_seq   BIGINT      NOT NULL,
  stamped_at DATETIME(6) NOT NULL
)''');

  var db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
  await applyTrajectorySchema(db);
  var appender = TrajectoryAppender(db: db, station: station, onEvent: (_) {});
  await appender.claimEpoch(pid: pid, pgid: pid);

  final base = DateTime.utc(2026, 8, 31, 12);
  var landed = 0;
  for (var session = 0; session < 70; session++) {
    for (final record in familyOneLifecycle(
      session,
      at: base.add(Duration(seconds: session)),
      stationPrefix: station,
    )) {
      if (await appender.append(record) is Appended) landed++;
    }
  }
  await replaySessionHeads(db);
  // Liveness state is working-set-only (dolt_ignore'd) and unrebuildable —
  // §10.3 says only `traj_pulse` cannot come back from the log.
  await db.execute(
    'INSERT INTO traj_pulse '
    '(subject_id, kind, boot_epoch, beat_at, observed_via) '
    "VALUES ('$station-m0', 'attempt', 1, :at, 'runtime') "
    'ON DUPLICATE KEY UPDATE beat_at = :at',
    {'at': sqlDateTime6(DateTime.now().toUtc())},
  );
  final snapshotSeq = await _maxSeq(db);
  await ledger.execute(
    'INSERT INTO grid_head (station, last_seq, stamped_at) '
    'VALUES (:station, :seq, :at) '
    'ON DUPLICATE KEY UPDATE last_seq = :seq, stamped_at = :at',
    {
      'station': station,
      'seq': snapshotSeq,
      'at': sqlDateTime6(DateTime.now().toUtc()),
    },
  );
  say('seeded: $landed trajectory rows, head stamped at seq $snapshotSeq');

  // ── 2. quiesce and snapshot the pair as one unit ──────────────────────
  await db.close();
  await ledger.close();
  await admin.close();
  await server.stop();
  say('server quiesced');

  final snapshot = p.join(scratch.path, 'snapshot');
  final snapWatch = Stopwatch()..start();
  var copy = await Process.run('cp', ['-Rc', server.dataDirPath, snapshot]);
  if (copy.exitCode != 0) {
    copy = await Process.run('cp', ['-R', server.dataDirPath, snapshot]);
  }
  snapWatch.stop();
  say(
    'snapshot of the whole data dir: exit=${copy.exitCode} in '
    '${snapWatch.elapsedMilliseconds}ms',
  );
  // dolt_ignore'd tables live in the working set, and a FILESYSTEM snapshot
  // takes the working set with it — unlike a `dolt clone`/`dolt backup`, which
  // carries committed history only. Whether proj_* and traj_pulse survive the
  // round trip is therefore a property of the procedure, not of the design,
  // and this drill measures the procedure the storage call actually names.
  final snapshotHasProjections = Directory(
    p.join(snapshot, 'trajectory'),
  ).existsSync();
  say('snapshot contains the trajectory database dir: $snapshotHasProjections');

  await server.restart();
  say('server back up');

  // ── 3. keep writing past the snapshot ─────────────────────────────────
  db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
  appender = TrajectoryAppender(db: db, station: station, onEvent: (_) {});
  await appender.claimEpoch(pid: pid, pgid: pid);
  for (var session = 70; session < 90; session++) {
    for (final record in familyOneLifecycle(
      session,
      at: base.add(Duration(seconds: session)),
      stationPrefix: station,
    )) {
      await appender.append(record);
    }
  }
  final postSnapshotSeq = await _maxSeq(db);
  ledger = await TrajectoryConnection.connect(server.endpointFor('ledger'));
  await ledger.execute(
    'UPDATE grid_head SET last_seq = :seq WHERE station = :station',
    {'seq': postSnapshotSeq, 'station': station},
  );
  say(
    'post-snapshot writes: log head now $postSnapshotSeq, ledger head '
    'stamp advanced to match',
  );
  await db.close();
  await ledger.close();

  // ── 4. destroy and restore the pair ───────────────────────────────────
  await server.stop();
  for (final database in const ['trajectory', 'ledger']) {
    final dir = Directory(server.databaseDir(database));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
  say('both databases destroyed');
  for (final database in const ['trajectory', 'ledger']) {
    final restore = await Process.run('cp', [
      '-Rc',
      p.join(snapshot, database),
      server.databaseDir(database),
    ]);
    say('restored $database: exit=${restore.exitCode}');
  }
  await server.restart();
  say('server back up on the restored pair');

  // ── 5. mandatory replay, then the read surfaces ───────────────────────
  db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
  final restoredSeq = await _maxSeq(db);
  say(
    'restored log head: $restoredSeq '
    '(snapshot was $snapshotSeq, pre-destroy was $postSnapshotSeq)',
  );

  final stalenessBefore = await SqlTrajectoryLogReader(db).foldStaleness();
  say(
    'foldStaleness BEFORE the mandatory replay: '
    'lag=${stalenessBefore?.lag} applied=${stalenessBefore?.appliedSeq}',
  );

  final replayWatch = Stopwatch()..start();
  final replayed = await replaySessionHeads(db);
  replayWatch.stop();
  say(
    'mandatory replay: ${replayed.rows.length} heads in '
    '${replayWatch.elapsedMilliseconds}ms, appliedSeq '
    '${replayed.appliedSeq}, skipped ${replayed.skipped}',
  );

  final staleness = await SqlTrajectoryLogReader(db).foldStaleness();
  final sane = staleness != null && staleness.lag == 0;
  say(
    'foldStaleness AFTER replay: lag=${staleness?.lag} '
    '${sane ? '(sane — the fold is at the log head)' : '(NOT sane)'}',
  );

  final out = <String>[];
  final code = await runTrajShow(
    gridHome: '/hermetic-unused',
    subject: '$station-m7',
    open: (_) async {
      final showDb = await TrajectoryConnection.connect(
        server.endpointFor('trajectory'),
      );
      return TrajectoryOpened(SqlTrajectoryLogReader(showDb));
    },
    out: out.add,
    err: out.add,
  );
  say('traj show on the restored store: exit=$code');
  for (final line in out.take(4)) {
    say('  $line');
  }
  say(
    'traj show emitted the §5 staleness warning: '
    '${out.join('\n').contains('warning — the fold lags')}',
  );

  // ── 6. liveness and the head re-stamp repair ──────────────────────────
  final pulse = await db.execute('SELECT COUNT(*) AS c FROM traj_pulse');
  final pulseRows = int.parse(pulse.rows.first['c'] ?? '0');
  say(
    'traj_pulse rows after restore: $pulseRows — '
    '${pulseRows == 0 ? 'liveness is UNKNOWN until the next beat (nothing to '
              'rebuild from: the log records liveness TRANSITIONS, not the '
              'beat itself)' : 'the filesystem snapshot carried the working '
              'set through, so beats survive — but they are STALE, and a '
              'beat older than the threshold still reads as lost/unknown'}',
  );
  final fence = await db.execute(
    'SELECT fence_state FROM traj_fence WHERE station = :station',
    {'station': station},
  );
  say(
    'traj_fence after restore: '
    '${fence.rows.isEmpty ? 'absent — the claim path re-seeds it' : fence.rows.first['fence_state']}',
  );

  ledger = await TrajectoryConnection.connect(server.endpointFor('ledger'));
  final head = await ledger.execute(
    'SELECT last_seq FROM grid_head WHERE station = :station',
    {'station': station},
  );
  final headSeq = int.parse(head.rows.first['last_seq']!);
  say(
    'ledger head stamp after restore: $headSeq vs restored log head '
    '$restoredSeq — ${headSeq > restoredSeq ? 'OUTRUNS the log: the repair '
              'pass is REQUIRED' : 'within the log'}',
  );
  if (headSeq > restoredSeq) {
    await ledger.execute(
      'UPDATE grid_head SET last_seq = :seq WHERE station = :station',
      {'seq': restoredSeq, 'station': station},
    );
    final repaired = await ledger.execute(
      'SELECT last_seq FROM grid_head WHERE station = :station',
      {'station': station},
    );
    say(
      'head re-stamp repair applied: last_seq now '
      '${repaired.rows.first['last_seq']}',
    );
  }

  final issues = await ledger.execute('SELECT COUNT(*) AS c FROM issues');
  say(
    'ledger after restore: ${issues.rows.first['c']} issues (the pair came '
    'back to the same instant)',
  );

  // ── 7. the history-only restore, simulated ────────────────────────────
  // A filesystem snapshot carries the WORKING SET, so `proj_*` and
  // `traj_pulse` came back above and the fold was already at the head. A
  // `dolt backup`/`dolt clone` restore carries committed history ONLY, so the
  // projections arrive empty — which is the case §5 calls the mandatory
  // rebuild for. Emptying them reproduces that restore shape exactly.
  banner('M6b — history-only restore shape (projections arrive empty)');
  await db.execute('DELETE FROM proj_session_head');
  await db.execute('DELETE FROM proj_meta');
  await db.execute('DELETE FROM traj_pulse');
  final emptyStaleness = await SqlTrajectoryLogReader(db).foldStaleness();
  say(
    'foldStaleness with empty projections: ${emptyStaleness == null ? 'null — proj_meta carries no row, the reader has nothing to compare' : 'lag=${emptyStaleness.lag}'}',
  );
  final emptyOut = <String>[];
  await runTrajShow(
    gridHome: '/hermetic-unused',
    subject: '$station-m7',
    open: (_) async {
      final showDb = await TrajectoryConnection.connect(
        server.endpointFor('trajectory'),
      );
      return TrajectoryOpened(SqlTrajectoryLogReader(showDb));
    },
    out: emptyOut.add,
    err: emptyOut.add,
  );
  say(
    'traj show still renders the LOG (the log is the truth, projections '
    'are derived): ${emptyOut.first}',
  );
  say(
    'traj show warns about the lagging fold: '
    '${emptyOut.join('\n').contains('warning — the fold lags')}',
  );
  final rebuild = await replaySessionHeads(db);
  say(
    'mandatory rebuild restored ${rebuild.rows.length} heads; '
    'foldStaleness lag now '
    '${(await SqlTrajectoryLogReader(db).foldStaleness())?.lag}',
  );
  final pulseAfter = await db.execute('SELECT COUNT(*) AS c FROM traj_pulse');
  say(
    'traj_pulse after the rebuild: ${pulseAfter.rows.first['c']} — '
    'UNREBUILDABLE by design (§10.3): liveness reads unknown until the '
    'next beat, and every consumer must render that rather than infer '
    'death from an absent pulse',
  );

  // ── 8. the head re-stamp repair, on the divergence that causes it ─────
  // The paired restore above put the ledger back to the SAME instant, so its
  // head stamp could not outrun the log. The pointer only outruns when the
  // two databases are recovered to DIFFERENT instants — the ledger survives
  // (or is recovered from its own remote) while trajectory rolls back. That
  // is the case the repair pass exists for, so it is the case this drills.
  banner('M6c — trajectory rolled back alone: the head re-stamp repair');
  appender = TrajectoryAppender(db: db, station: station, onEvent: (_) {});
  await appender.claimEpoch(pid: pid, pgid: pid);
  for (var session = 90; session < 105; session++) {
    for (final record in familyOneLifecycle(
      session,
      at: base.add(Duration(seconds: session)),
      stationPrefix: station,
    )) {
      await appender.append(record);
    }
  }
  final divergedSeq = await _maxSeq(db);
  await ledger.execute(
    'UPDATE grid_head SET last_seq = :seq WHERE station = :station',
    {'seq': divergedSeq, 'station': station},
  );
  say('ledger head stamped at $divergedSeq');
  await db.close();
  await ledger.close();
  await server.stop();
  Directory(server.databaseDir('trajectory')).deleteSync(recursive: true);
  final rollback = await Process.run('cp', [
    '-Rc',
    p.join(snapshot, 'trajectory'),
    server.databaseDir('trajectory'),
  ]);
  say(
    'trajectory alone rolled back to the snapshot: exit=${rollback.exitCode}',
  );
  await server.restart();

  db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
  ledger = await TrajectoryConnection.connect(server.endpointFor('ledger'));
  final rolledSeq = await _maxSeq(db);
  final divergedHead = await ledger.execute(
    'SELECT last_seq FROM grid_head WHERE station = :station',
    {'station': station},
  );
  final divergedHeadSeq = int.parse(divergedHead.rows.first['last_seq']!);
  say(
    'ledger head $divergedHeadSeq vs restored log head $rolledSeq — '
    '${divergedHeadSeq > rolledSeq ? 'OUTRUNS: repair REQUIRED' : 'no divergence'}',
  );
  if (divergedHeadSeq > rolledSeq) {
    await replaySessionHeads(db);
    await ledger.execute(
      'UPDATE grid_head SET last_seq = :seq WHERE station = :station',
      {'seq': rolledSeq, 'station': station},
    );
    final repaired = await ledger.execute(
      'SELECT last_seq FROM grid_head WHERE station = :station',
      {'station': station},
    );
    say(
      'repair pass: head re-stamped to '
      '${repaired.rows.first['last_seq']} (the log head), after the '
      'mandatory replay — the ledger never points past the log again',
    );
  }

  await ledger.close();
  await db.close();
  await server.dispose();
  exit(0);
}

Future<int> _maxSeq(TrajectoryDb db) async {
  final result = await db.execute(
    'SELECT COALESCE(MAX(seq), 0) AS m FROM trajectory',
  );
  return int.parse(result.rows.first['m'] ?? '0');
}
