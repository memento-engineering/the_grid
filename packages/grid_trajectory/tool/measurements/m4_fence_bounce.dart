/// M4 — fence behavior across a server bounce mid-transaction
/// (storage-call.md stage-0 item 4; §10.1's reconnect-with-fence-recheck).
///
/// The contract under test: kill the server between an appender's CAS and its
/// COMMIT and the service must fail LOUDLY and TYPED — no hang, no silent
/// half-append, no double append — then the guarded reconnect must either
/// resume (our epoch is still live) or go inert WITHOUT touching the fence
/// cell (a successor claimed a higher epoch while we were away).
///
/// Three scenarios, all with a real SIGKILL of a real `dolt sql-server`:
///
///   S1  kill after the fence CAS, before the row INSERT;
///   S2  kill after the INSERT, at COMMIT — the worst case, because the
///       transaction is complete except for durability;
///   S3  the same bounce, but a SUCCESSOR claims the next epoch during the
///       outage — the reconnect must go inert and leave the fence alone.
///
/// Run: `dart run tool/measurements/m4_fence_bounce.dart`
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

Future<void> main() async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm4'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  banner('M4 — fence across a server bounce mid-transaction');
  final server = await MeasurementServer.start(scratchDir: scratch.path);
  say('hermetic server on ${MeasurementServer.host}:${server.port}');

  final admin = await TrajectoryConnection.connect(server.admin);
  await createTrajectoryDatabase(admin);
  await admin.close();
  final boot = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  await applyTrajectorySchema(boot);
  await boot.close();

  await _scenario(
    server,
    label: 'S1 — kill after the fence CAS, before the INSERT',
    trigger: _KillPoint.beforeInsert,
    successorClaims: false,
  );
  await _scenario(
    server,
    label: 'S2 — kill at COMMIT, transaction otherwise complete',
    trigger: _KillPoint.atCommit,
    successorClaims: false,
  );
  await _scenario(
    server,
    label: 'S3 — kill at COMMIT, successor claims the epoch during the outage',
    trigger: _KillPoint.atCommit,
    successorClaims: true,
  );

  await server.dispose();
  exit(0);
}

enum _KillPoint { beforeInsert, atCommit }

Future<void> _scenario(
  MeasurementServer server, {
  required String label,
  required _KillPoint trigger,
  required bool successorClaims,
}) async {
  banner(label);
  final station = 'm4-${trigger.name}-${successorClaims ? 'succ' : 'solo'}';

  final raw = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  final db = _BounceDb(raw, server: server, killAt: trigger);
  final appender = TrajectoryAppender(
    db: db,
    station: station,
    onEvent: (event) =>
        say('  service event: ${event.kind.name} — ${event.reason}'),
  );
  final claim = await appender.claimEpoch(pid: pid, pgid: pid);
  say('epoch claim: ${claim is EpochClaimed ? claim.epoch : claim}');

  // A short healthy run first, so the bounce interrupts a live stream rather
  // than a cold appender.
  final warmup = familyOneLifecycle(
    0,
    at: DateTime.utc(2026, 8, 31, 10),
    stationPrefix: station,
  );
  for (final record in warmup) {
    await appender.append(record);
  }
  final beforeCount = await _count(server, station);
  say('warm-up landed $beforeCount rows');

  // The victim: one more record, with the kill armed.
  final victim = familyOneLifecycle(
    1,
    at: DateTime.utc(2026, 8, 31, 10, 1),
    stationPrefix: station,
  ).first;
  db.armed = true;
  final watch = Stopwatch()..start();
  Object? thrown;
  AppendOutcome? outcome;
  try {
    outcome = await appender
        .append(victim)
        .timeout(const Duration(seconds: 30));
  } on Object catch (error) {
    thrown = error;
  }
  watch.stop();
  say(
    'mid-transaction bounce: ${watch.elapsedMilliseconds}ms — '
    '${thrown != null ? 'THREW ${thrown.runtimeType}: ${_oneLine('$thrown')}' : 'returned ${outcome.runtimeType}'}',
  );
  if (watch.elapsed >= const Duration(seconds: 30)) {
    say('  VERDICT: HUNG — the 30s guard fired, the contract is violated');
  } else {
    say('  VERDICT: no hang');
  }
  say(
    'appender state after the bounce: inert=${appender.isInert} '
    'halted=${appender.isHalted}',
  );

  // The next append while the server is still down: does the service stay
  // typed, or does a raw throwable escape? Both are recordable; only one is
  // the contract.
  Object? nextThrown;
  AppendOutcome? nextOutcome;
  try {
    nextOutcome = await appender
        .append(warmup[1])
        .timeout(const Duration(seconds: 20));
  } on Object catch (error) {
    nextThrown = error;
  }
  say(
    'append while the server is DOWN: '
    '${nextThrown != null ? 'THREW ${nextThrown.runtimeType}' : 'returned ${nextOutcome.runtimeType}'}',
  );

  // ── the bounce completes ──────────────────────────────────────────────
  await server.restart();
  say('server back on port ${server.port}');

  if (successorClaims) {
    // A successor authority boots while we were away — exactly the situation
    // the guarded reconnect exists for.
    final successorDb = await TrajectoryConnection.connect(
      server.endpointFor('trajectory'),
    );
    final successor = TrajectoryAppender(
      db: successorDb,
      station: station,
      onEvent: (_) {},
    );
    final successorClaim = await successor.claimEpoch(
      pid: pid + 1,
      pgid: pid + 1,
      cause: 'steal',
    );
    say(
      'successor claimed epoch '
      '${successorClaim is EpochClaimed ? successorClaim.epoch : successorClaim}',
    );
    await successorDb.close();
  }

  final fenceBefore = await _fenceState(server, station);
  final fresh = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  final reconnect = await appender.reconnect(fresh);
  final fenceAfter = await _fenceState(server, station);
  say(
    'reconnect: ${reconnect.runtimeType} '
    '${reconnect is ReconnectInert ? '(stale ${reconnect.staleEpoch}, live ${reconnect.liveEpoch})' : ''}',
  );
  say(
    'fence cell: $fenceBefore → $fenceAfter '
    '${fenceBefore == fenceAfter ? '(untouched)' : '(re-seeded)'}',
  );

  // ── no double append, and the row is either there once or not at all ──
  final afterCount = await _count(server, station);
  final victimRows = await _rowsForIdem(server, station, victim);
  say('rows for this station: $beforeCount → $afterCount');
  say(
    'rows carrying the victim\'s idem_key: $victimRows '
    '${victimRows <= 1 ? '(no double append)' : '(DOUBLE APPEND)'}',
  );

  final belt = await appender.verifyBeltAtBoot();
  say(
    'boot belt full-scan: ${belt == null ? 'clean' : 'HALT — ${belt.reason}'}',
  );

  if (reconnect is ReconnectResumed) {
    // Re-presenting the interrupted record is the §5 at-least-once path: it
    // must land exactly once, and a second presentation must dedupe.
    final first = await appender.append(victim);
    final second = await appender.append(victim);
    final finalCount = await _count(server, station);
    say(
      're-append after resume: ${first.runtimeType} then '
      '${second.runtimeType}; rows $afterCount → $finalCount',
    );
  } else {
    final refused = await appender.append(victim);
    say(
      'append after an inert reconnect: ${refused.runtimeType} '
      '(must be AppendFencedOut)',
    );
  }

  await fresh.close();
}

Future<int> _count(MeasurementServer server, String station) async {
  final db = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  final result = await db.execute(
    'SELECT COUNT(*) AS c FROM trajectory WHERE station = :station',
    {'station': station},
  );
  await db.close();
  return int.parse(result.rows.first['c'] ?? '0');
}

/// Rows carrying THIS record's idem key, under every epoch the station has
/// claimed — the idem key is epoch-scoped (§5), so a bounce-induced double
/// append could land under either epoch and only a scan of all of them
/// answers the question.
Future<int> _rowsForIdem(
  MeasurementServer server,
  String station,
  TrajectoryRecord record,
) async {
  final db = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  final epochs = await db.execute(
    'SELECT epoch FROM traj_epoch WHERE station = :station',
    {'station': station},
  );
  final keys = [
    for (final row in epochs.rows)
      record.idemKey(
        IdemContext(station: station, bootEpoch: int.parse(row['epoch']!)),
      ),
  ];
  if (keys.isEmpty) {
    await db.close();
    return 0;
  }
  final placeholders = [for (var i = 0; i < keys.length; i++) ':k$i'];
  final result = await db.execute(
    'SELECT COUNT(*) AS c FROM trajectory '
    'WHERE idem_key IN (${placeholders.join(', ')})',
    {for (var i = 0; i < keys.length; i++) 'k$i': keys[i]},
  );
  await db.close();
  return int.parse(result.rows.first['c'] ?? '0');
}

Future<String> _fenceState(MeasurementServer server, String station) async {
  final db = await TrajectoryConnection.connect(
    server.endpointFor('trajectory'),
  );
  final result = await db.execute(
    'SELECT fence_state FROM traj_fence WHERE station = :station',
    {'station': station},
  );
  await db.close();
  return result.rows.isEmpty ? 'absent' : '${result.rows.first['fence_state']}';
}

/// Kills the server from inside the append transaction, at the statement the
/// scenario names. The kill happens BEFORE the statement reaches the wire, so
/// the client is talking to a socket that is already gone — the honest shape
/// of a machine losing its server mid-write.
class _BounceDb implements TrajectoryDb {
  _BounceDb(this._inner, {required this.server, required this.killAt});

  final TrajectoryDb _inner;
  final MeasurementServer server;
  final _KillPoint killAt;

  bool armed = false;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    if (armed && _isTrigger(sql)) {
      armed = false;
      say('  ⚡ SIGKILL the server before: ${_oneLine(sql, cap: 60)}');
      await server.kill();
    }
    return _inner.execute(sql, params);
  }

  bool _isTrigger(String sql) => switch (killAt) {
    _KillPoint.beforeInsert => sql.startsWith('INSERT INTO trajectory'),
    _KillPoint.atCommit => sql == 'COMMIT',
  };

  @override
  Future<void> close() => _inner.close();
}

String _oneLine(String value, {int cap = 300}) {
  final flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= cap ? flat : '${flat.substring(0, cap)}…';
}
