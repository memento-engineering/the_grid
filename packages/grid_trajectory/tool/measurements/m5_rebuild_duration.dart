/// M5 — rebuild duration at realistic log size (storage-call.md stage-0
/// item 5; §5's Rebuild path).
///
/// **The recovery budget this measurement is judged against: 60 seconds.**
/// That is one station bounce. The station cannot `reload` (snapshot-resident
/// rule) so every code change is a bounce, restore is a bounce, and a fold
/// rebuild that outruns the bounce is a rebuild the operator will skip. 60 s
/// is also comfortably inside the 90 s liveness threshold the harness already
/// uses, so a rebuild inside budget cannot itself make a station look dead.
/// The epoch-boundary snapshot contingency triggers when this number stops
/// fitting.
///
/// Rows are seeded by BULK INSERT, deliberately: the measurement under test is
/// the REPLAY, and M3 already measures what the fenced append path costs. A
/// 100k-row seed through the appender would take ~27 minutes and would
/// measure M3 again.
///
/// Run: `dart run tool/measurements/m5_rebuild_duration.dart`
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// The stated budget, in one place so the verdict cannot drift from the text.
const Duration recoveryBudget = Duration(seconds: 60);

/// Scaling points: replay runs after each tranche, so the curve is visible
/// rather than assumed linear.
const List<int> tranches = [2500, 5000, 10000]; // sessions ⇒ 25k/50k/100k rows

Future<void> main() async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm5'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  banner('M5 — replay-fold duration at 25k / 50k / 100k records');
  final server = await MeasurementServer.start(scratchDir: scratch.path);
  say('hermetic server on ${MeasurementServer.host}:${server.port}');

  final admin = await TrajectoryConnection.connect(server.admin);
  await createTrajectoryDatabase(admin);
  await admin.close();

  final db = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  await applyTrajectorySchema(db);

  const station = 'm5';
  final base = DateTime.utc(2026, 8, 31, 11);
  var seeded = 0;
  var epochSeq = 0;
  var sessionsSeeded = 0;

  for (final target in tranches) {
    final envelopes = <TrajectoryEnvelope>[];
    for (var session = sessionsSeeded; session < target; session++) {
      final at = base.add(Duration(seconds: session));
      for (final record in familyOneLifecycle(
        session,
        at: at,
        stationPrefix: station,
      )) {
        envelopes.add(
          syntheticEnvelope(
            record,
            station: station,
            bootEpoch: 1,
            epochSeq: ++epochSeq,
            occurredAt: at,
          ),
        );
      }
    }
    sessionsSeeded = target;

    final seedWatch = Stopwatch()..start();
    seeded += await bulkInsertTrajectory(db, envelopes);
    seedWatch.stop();
    say(
      'seeded +${envelopes.length} rows (total $seeded) in '
      '${(seedWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s',
    );

    // Split the cost: the SELECT that streams the whole log, the pure fold
    // over it, then the whole truncate-and-rewrite the service actually runs.
    final readWatch = Stopwatch()..start();
    final scanned = await db.execute('SELECT * FROM trajectory ORDER BY seq');
    readWatch.stop();
    final envelopesRead = [
      for (final row in scanned.rows) envelopeFromRow(row),
    ];
    final foldWatch = Stopwatch()..start();
    final folded = foldSessionHeads(envelopesRead);
    foldWatch.stop();

    final replayWatch = Stopwatch()..start();
    final result = await replaySessionHeads(db);
    replayWatch.stop();

    final seconds = replayWatch.elapsedMilliseconds / 1000;
    say(
      'REPLAY at $seeded rows: ${seconds.toStringAsFixed(1)}s '
      '⇒ ${(seeded / seconds).round()} rows/s | '
      'read ${(readWatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s, '
      'pure fold ${(foldWatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s, '
      'heads ${result.rows.length}, appliedSeq ${result.appliedSeq}, '
      'skipped ${result.skipped}',
    );
    say(
      '  vs the ${recoveryBudget.inSeconds}s budget: '
      '${replayWatch.elapsed <= recoveryBudget ? 'INSIDE' : 'OVER'} '
      '(${(seconds / recoveryBudget.inSeconds * 100).toStringAsFixed(0)}% of it)',
    );
    if (folded.rows.length != result.rows.length) {
      say('  WARNING: pure fold and replay disagree on head count');
    }

    final staleness = await SqlTrajectoryLogReader(db).foldStaleness();
    say('  foldStaleness after replay: lag=${staleness?.lag}');
    final dbSize = await _dirSize(server.databaseDir('trajectory'));
    say('  trajectory database dir: $dbSize');
  }

  await db.close();
  await server.dispose();
  exit(0);
}

Future<String> _dirSize(String path) async {
  final result = await Process.run('du', ['-sk', path]);
  final kilobytes = int.tryParse('${result.stdout}'.split('\t').first.trim());
  return kilobytes == null
      ? 'unknown'
      : '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}
