/// M2 — online `CALL DOLT_GC()` on a shared multi-database server
/// (storage-call.md stage-0 item 2, and separate-STORE flip condition 1).
///
/// The probe only ever ran CLI gc against stopped databases, and the T8
/// journal finding turned gc from hygiene into a MANDATORY scheduled
/// operation (~22–24 KB of journal per append). So the question that decides
/// the gc schedule is: when gc runs against `trajectory`, what happens to the
/// connections serving the LEDGER database on the same server?
///
/// Shape: one hermetic server, two databases. A ledger connection reads and
/// writes continuously; the fenced appender writes trajectory continuously;
/// a third connection calls `DOLT_GC()` on trajectory mid-flight. Everything
/// each side survived — or did not — is recorded, including whether a killed
/// connection recovers by itself or needs a fresh session.
///
/// Run: `dart run tool/measurements/m2_online_gc.dart`
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

Future<void> main() async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm2'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  banner('M2 — online gc on a shared two-database server');
  final server = await MeasurementServer.start(scratchDir: scratch.path);
  say('hermetic server on ${MeasurementServer.host}:${server.port}');

  final admin = await TrajectoryConnection.connect(server.admin);
  await createTrajectoryDatabase(admin);
  await admin.execute('CREATE DATABASE IF NOT EXISTS ledger');

  final ledger = await TrajectoryConnection.connect(
    server.endpointFor('ledger'),
  );
  await seedLedgerDatabase(admin, ledger);
  say('ledger seeded (2,000 issues + event log)');

  final traj = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  await applyTrajectorySchema(traj);

  final appender = TrajectoryAppender(
    db: traj,
    station: 'm2',
    onEvent: (event) => say('  service event: ${event.kind.name}'),
  );
  await appender.claimEpoch(pid: pid, pgid: pid);

  // ── load: ledger read+write, trajectory append, both live ─────────────
  final stopLoad = Completer<void>();
  final load = LedgerLoad(ledger);
  final ledgerFuture = load.run(stopLoad.future);

  var appended = 0;
  final appendFailures = <String>[];
  Future<void> appendLoop() async {
    var i = 0;
    while (!stopLoad.isCompleted) {
      for (final record in familyOneLifecycle(
        i,
        at: DateTime.utc(2026, 8, 31).add(Duration(seconds: i)),
        stationPrefix: 'm2',
      )) {
        if (stopLoad.isCompleted) break;
        try {
          final outcome = await appender.append(record);
          if (outcome is Appended) {
            appended++;
          } else {
            appendFailures.add('$outcome');
          }
        } on Object catch (error) {
          appendFailures.add('$error');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      i++;
    }
  }

  final appendFuture = appendLoop();

  // Let both sides build a real working set (and a real journal) first.
  await Future<void>.delayed(const Duration(seconds: 12));
  final readsBefore = load.reads;
  final writesBefore = load.writes;
  final failuresBefore = load.failures.length;
  final appendedBefore = appended;
  say(
    'pre-gc: ledger reads=$readsBefore writes=$writesBefore '
    'failures=$failuresBefore | trajectory appends=$appendedBefore',
  );
  say(
    'trajectory dir before gc: '
    '${(await _dirSize(server.databaseDir('trajectory'))).toStringAsFixed(1)} MB',
  );

  // ── the gc, on its OWN connection, scoped to trajectory ───────────────
  final gcConn = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  await _callGc(gcConn, 'pass 1');
  // Sized immediately after the pass, and the append count taken with it: the
  // two together are what makes the journal-per-append arithmetic honest
  // rather than inferred across an unknown interval.
  final afterPass1 = await _dirSize(server.databaseDir('trajectory'));
  final appendsAtPass1 = appended;
  say(
    'trajectory dir immediately after gc pass 1: '
    '${afterPass1.toStringAsFixed(1)} MB (at $appendsAtPass1 appends)',
  );

  // A second pass after a longer soak: one fast gc over a thin journal is
  // not evidence about the steady state the T8 finding describes.
  await Future<void>.delayed(const Duration(seconds: 20));
  say('mid-soak: ledger reads=${load.reads} | trajectory appends=$appended');
  final beforePass2 = await _dirSize(server.databaseDir('trajectory'));
  final appendsAtPass2 = appended;
  say(
    'trajectory dir before gc pass 2: '
    '${beforePass2.toStringAsFixed(1)} MB (at $appendsAtPass2 appends)',
  );
  final grownBy = beforePass2 - afterPass1;
  final grownOver = appendsAtPass2 - appendsAtPass1;
  say(
    'journal growth between the passes: '
    '${grownBy.toStringAsFixed(1)} MB over $grownOver appends ⇒ '
    '${(grownBy * 1024 / grownOver).toStringAsFixed(1)} KB/append',
  );
  await _callGc(gcConn, 'pass 2');
  say(
    'trajectory dir immediately after gc pass 2: '
    '${(await _dirSize(server.databaseDir('trajectory'))).toStringAsFixed(1)} MB',
  );

  // Give both loads a beat to expose any post-gc damage.
  await Future<void>.delayed(const Duration(seconds: 8));
  stopLoad.complete();
  await ledgerFuture;
  await appendFuture;

  say(
    'post-gc: ledger reads=${load.reads} (+${load.reads - readsBefore}) '
    'writes=${load.writes} (+${load.writes - writesBefore}) '
    'failures=${load.failures.length} (+${load.failures.length - failuresBefore})',
  );
  say(
    'post-gc: trajectory appends=$appended (+${appended - appendedBefore}) '
    'append failures=${appendFailures.length}',
  );
  for (final failure in load.failures.take(5)) {
    say('  ledger failure: ${_oneLine(failure)}');
  }
  for (final failure in appendFailures.take(5)) {
    say('  append failure: ${_oneLine(failure)}');
  }
  say('appender state: inert=${appender.isInert} halted=${appender.isHalted}');
  say(
    'trajectory dir at the end: '
    '${(await _dirSize(server.databaseDir('trajectory'))).toStringAsFixed(1)} MB',
  );
  say(
    'ledger dir at the end: '
    '${(await _dirSize(server.databaseDir('ledger'))).toStringAsFixed(1)} MB',
  );

  // ── recovery: does the OLD ledger session still work, and does a fresh
  // one? "Killed but auto-recovering" and "killed and needs a new session"
  // are different operational answers and the schedule depends on which.
  try {
    final probe = await ledger.execute('SELECT COUNT(*) AS c FROM issues');
    say('old ledger session after gc: OK (${probe.rows.first['c']} issues)');
  } on Object catch (error) {
    say('old ledger session after gc: DEAD — ${_oneLine('$error')}');
  }
  try {
    final fresh = await TrajectoryConnection.connect(
      server.endpointFor('ledger'),
    );
    final probe = await fresh.execute('SELECT COUNT(*) AS c FROM issues');
    say('fresh ledger session after gc: OK (${probe.rows.first['c']} issues)');
    await fresh.close();
  } on Object catch (error) {
    say('fresh ledger session after gc: FAILED — ${_oneLine('$error')}');
  }
  try {
    final probe = await traj.execute('SELECT COUNT(*) AS c FROM trajectory');
    say('old trajectory session after gc: OK (${probe.rows.first['c']} rows)');
  } on Object catch (error) {
    say('old trajectory session after gc: DEAD — ${_oneLine('$error')}');
  }

  final serverLog = File(p.join(server.dataDirPath, 'server.log'));
  final killLines = serverLog.existsSync()
      ? const LineSplitter()
            .convert(serverLog.readAsStringSync())
            .where((line) => line.toLowerCase().contains('kill'))
            .length
      : -1;
  say('server log lines mentioning "kill": $killLines');

  await _closeQuietly(gcConn);
  await _closeQuietly(traj);
  await _closeQuietly(ledger);
  await _closeQuietly(admin);
  await server.dispose();
  // The sockets this harness opened can outlive their `close()`; a measurement
  // that has printed its numbers must not linger on the event loop.
  exit(0);
}

Future<void> _callGc(TrajectoryDb gcConn, String label) async {
  final watch = Stopwatch()..start();
  String verdict;
  try {
    await gcConn.execute('CALL DOLT_GC()');
    verdict = 'returned normally';
  } on Object catch (error) {
    verdict = 'threw: ${_oneLine('$error')}';
  }
  watch.stop();
  say(
    'DOLT_GC() on trajectory ($label): $verdict in '
    '${watch.elapsedMilliseconds}ms',
  );
}

/// Directory size in MB. `du -sk` is the measurement: dolt's on-disk journal
/// is what the T8 finding is about, and apparent size is what fills a disk.
Future<double> _dirSize(String path) async {
  final result = await Process.run('du', ['-sk', path]);
  final kilobytes = int.tryParse('${result.stdout}'.split('\t').first.trim());
  return kilobytes == null ? 0 : kilobytes / 1024;
}

Future<void> _closeQuietly(TrajectoryConnection connection) async {
  try {
    await connection.close();
  } on Object {
    // A gc-killed connection cannot be closed cleanly; that is the finding,
    // not an error to propagate.
  }
}

String _oneLine(String value, {int cap = 300}) {
  final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= cap ? flat : '${flat.substring(0, cap)}…';
}
