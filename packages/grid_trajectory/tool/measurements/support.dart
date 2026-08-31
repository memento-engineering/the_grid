/// Shared machinery for the Stage-0 measurement harness (storage-call.md's
/// seven-item "what stage 0 must still measure" list).
///
/// These are PLAIN Dart scripts, not tests: each `mN_*.dart` runs standalone
/// (`dart run tool/measurements/mN_*.dart`), prints its own numbers, and
/// exits non-zero only when the harness itself could not run. A measurement
/// whose result contradicts the design's expectation still exits 0 and says
/// so — the verdict lives in the report, not the exit code.
///
/// HERMETIC, ALWAYS: every server here is a throwaway `dolt sql-server` on an
/// ephemeral port over a temp data dir. Nothing in this directory may open a
/// real `.beads`/`.grid` store's server, pid, lock, or proxy files. The one
/// measurement that touches real data (M1's copy-of-real-store variant) reads
/// the source with `cp` only, rewrites the COPY's listener port before any
/// process starts, and is loud about both.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

/// The scratch root every measurement works under — never inside a real
/// store, and never a path that outlives the machine it was measured on.
///
/// `GRID_TRAJECTORY_SCRATCH` overrides it, which is how the recorded run was
/// pinned to a session-local scratchpad; the default keeps the harness
/// runnable anywhere.
String get measurementScratchRoot {
  final override = Platform.environment['GRID_TRAJECTORY_SCRATCH'];
  return override != null && override.isNotEmpty
      ? p.join(override, 'measurements')
      : p.join(Directory.systemTemp.path, 'grid_trajectory_measurements');
}

/// Timestamped line on stdout — the harness's only output channel (the lint
/// bans `print`, and a measurement's log IS its receipt).
void say(String line) {
  final now = DateTime.now().toUtc().toIso8601String().substring(11, 23);
  stdout.writeln('[$now] $line');
}

/// A section banner, so a scrollback of seven runs stays readable.
void banner(String title) {
  stdout.writeln('');
  stdout.writeln('══ $title ${'═' * (68 - title.length).clamp(0, 68)}');
}

// ── the hermetic server ─────────────────────────────────────────────────────

/// A throwaway `dolt sql-server`: temp data dir, ephemeral port, wildcard-host
/// admin user created OFFLINE before the server starts (dolt's auto
/// root@localhost cannot authenticate over the 127.0.0.1 TCP address).
///
/// Unlike the test-suite twin this one is RESTARTABLE on the same data dir and
/// the same port — M4 (bounce mid-transaction) and M6 (restore drill) both
/// need the server to die and come back where the client expects it.
class MeasurementServer {
  MeasurementServer._({
    required this.doltBinary,
    required this.dataDirPath,
    required this.port,
    required Process server,
  }) : _server = server;

  static const String host = '127.0.0.1';
  static const String user = 'grid';
  static const String password = 'gridpw';

  final String doltBinary;
  final String dataDirPath;

  /// Fixed for the server's whole life, including across [restart].
  final int port;

  Process? _server;

  /// Server-level coordinates (no database selected).
  TrajectoryEndpoint get admin => TrajectoryEndpoint(
    host: host,
    port: port,
    user: user,
    password: password,
  );

  TrajectoryEndpoint endpointFor(String database) => TrajectoryEndpoint(
    host: host,
    port: port,
    user: user,
    password: password,
    database: database,
  );

  String databaseDir(String database) => p.join(dataDirPath, database);

  String get doltcfgDirPath => p.join(dataDirPath, '.doltcfg');

  /// Runs a dolt CLI op against this data dir.
  Future<ProcessResult> runDolt(
    List<String> args, {
    String? cwd,
    String? doltcfgDir,
  }) => Process.run(doltBinary, [
    if (doltcfgDir != null) ...['--doltcfg-dir', doltcfgDir],
    ...args,
  ], workingDirectory: cwd ?? dataDirPath);

  /// Boots a fresh server over a fresh temp data dir under [scratchDir].
  static Future<MeasurementServer> start({required String scratchDir}) async {
    final dolt = await _requireDolt();
    final dataDir = Directory(p.join(scratchDir, 'server'));
    if (dataDir.existsSync()) await dataDir.delete(recursive: true);
    dataDir.createSync(recursive: true);
    final resolved = dataDir.resolveSymbolicLinksSync();

    await Process.run(dolt, [
      'init',
      '--name',
      'traj-measure',
      '--email',
      'traj@measure.local',
    ], workingDirectory: resolved);
    final createUser = await Process.run(dolt, [
      'sql',
      '-q',
      "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password'; "
          "GRANT ALL ON *.* TO '$user'@'%' WITH GRANT OPTION;",
    ], workingDirectory: resolved);
    if (createUser.exitCode != 0) {
      throw StateError('offline CREATE USER failed: ${createUser.stderr}');
    }

    final port = await _freePort();
    final process = await _spawn(dolt, resolved, port);
    if (process == null) {
      throw StateError('hermetic dolt sql-server never accepted connections');
    }
    return MeasurementServer._(
      doltBinary: dolt,
      dataDirPath: resolved,
      port: port,
      server: process,
    );
  }

  /// SIGKILL — the abrupt death M4 needs, and the only honest stand-in for a
  /// machine losing the server mid-transaction.
  Future<void> kill() async {
    final process = _server;
    if (process == null) return;
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () => -1,
    );
    _server = null;
    // The listener takes a moment to actually free.
    while (await _portOpen(port)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Graceful stop — the "server quiesced" precondition M6's snapshot needs.
  Future<void> stop() async {
    final process = _server;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _server = null;
    while (await _portOpen(port)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Brings the server back on the SAME data dir and the SAME port.
  Future<void> restart() async {
    if (_server != null) await stop();
    final process = await _spawn(doltBinary, dataDirPath, port);
    if (process == null) {
      throw StateError('hermetic server did not come back on port $port');
    }
    _server = process;
  }

  Future<void> dispose({bool deleteDataDir = true}) async {
    await kill();
    if (!deleteDataDir) return;
    try {
      final dir = Directory(dataDirPath);
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Best effort: the scratch root is session-local and disposable.
    }
  }

  static Future<Process?> _spawn(String dolt, String dataDir, int port) async {
    final process = await Process.start(dolt, [
      'sql-server',
      '--host',
      host,
      '--port',
      '$port',
      '--data-dir',
      dataDir,
    ], workingDirectory: dataDir);
    // The server's own words are evidence for M2 (does gc kill connections?)
    // and M4 (what did the server say as it died?), so they go to a file
    // rather than the bit bucket.
    final log = File(
      p.join(dataDir, 'server.log'),
    ).openWrite(mode: FileMode.append);
    unawaited(log.addStream(process.stdout).then((_) => log.close()));
    unawaited(
      process.stderr.pipe(
        File(
          p.join(dataDir, 'server.err.log'),
        ).openWrite(mode: FileMode.append),
      ),
    );
    for (var i = 0; i < 160; i++) {
      if (await _portOpen(port)) return process;
      await Future<void>.delayed(const Duration(milliseconds: 125));
    }
    process.kill(ProcessSignal.sigkill);
    return null;
  }

  static Future<String> _requireDolt() async {
    final which = await Process.run('which', ['dolt']);
    if (which.exitCode != 0) {
      throw StateError('no dolt on PATH — the measurements need one');
    }
    return 'dolt';
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(host, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _portOpen(int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 250),
      );
      await socket.close();
      return true;
    } on Object {
      return false;
    }
  }
}

// ── latency bookkeeping ─────────────────────────────────────────────────────

/// Percentiles over a sample of per-operation microsecond costs. The retreat
/// threshold in §5 is a RATE (22–28 appends/s), so [rateFor] converts a mean
/// cost into the comparable number.
class LatencyStats {
  LatencyStats(List<int> microseconds)
    : _sorted = List<int>.from(microseconds)..sort();

  final List<int> _sorted;

  int get count => _sorted.length;

  double get meanMs => _sorted.isEmpty
      ? 0
      : _sorted.reduce((a, b) => a + b) / _sorted.length / 1000;

  double percentileMs(double q) {
    if (_sorted.isEmpty) return 0;
    final index = ((_sorted.length - 1) * q).round();
    return _sorted[index] / 1000;
  }

  double get p50Ms => percentileMs(0.50);

  double get p90Ms => percentileMs(0.90);

  double get p99Ms => percentileMs(0.99);

  double get maxMs => _sorted.isEmpty ? 0 : _sorted.last / 1000;

  /// Throughput a single serialized writer sustains at this mean cost.
  double get rateFor => meanMs == 0 ? 0 : 1000 / meanMs;

  @override
  String toString() =>
      'n=$count mean=${meanMs.toStringAsFixed(2)}ms '
      'p50=${p50Ms.toStringAsFixed(2)} p90=${p90Ms.toStringAsFixed(2)} '
      'p99=${p99Ms.toStringAsFixed(2)} max=${maxMs.toStringAsFixed(2)} '
      '⇒ ${rateFor.toStringAsFixed(1)}/s';
}

// ── synthetic Family-1 traffic ──────────────────────────────────────────────

/// The ten-record attempt lifecycle the fold consumes, for session [index].
/// Same shape as the Stage-0 fold integration test, so the numbers here and
/// the guard suite's are talking about the same stream.
List<TrajectoryRecord> familyOneLifecycle(
  int index, {
  required DateTime at,
  String stationPrefix = 'tranquility',
  String beadPrefix = 'tg',
}) {
  final sessionId = '$stationPrefix-m$index';
  final workBead = '$beadPrefix-m$index';
  final attemptId = mintUlid(now: at.add(Duration(microseconds: index)));
  const outcomes = [
    TerminalOutcome.succeeded,
    TerminalOutcome.failed,
    TerminalOutcome.lost,
  ];
  return <TrajectoryRecord>[
    AttemptSessionStarted(
      sessionId: sessionId,
      grantId: mintUlid(now: at),
      workBeadId: workBead,
      rig: 'operator',
      model: 'molecule',
    ),
    AttemptProcessStarted(
      attemptId: attemptId,
      sessionId: sessionId,
      incarnation: 0,
      pid: 10000 + index,
      pgid: 10000 + index,
    ),
    WorktreeProvisioned(
      attemptId: attemptId,
      sessionId: sessionId,
      worktree: '/scratch/wt/$workBead',
      branch: 'grid/$workBead',
      baseSha: 'a' * 40,
      adoptedExisting: false,
    ),
    AttemptLeaseTransition(
      attemptId: attemptId,
      phase: LeasePhase.acquired,
      token: attemptId,
    ),
    AttemptLivenessTransition(
      attemptId: attemptId,
      crossing: LivenessCrossing.lost,
      lastBeatAt: at,
      thresholdMs: 90000,
    ),
    AttemptLivenessTransition(
      attemptId: attemptId,
      crossing: LivenessCrossing.regained,
      lastBeatAt: at.add(const Duration(seconds: 30)),
      thresholdMs: 90000,
    ),
    AttemptRoundRetired(
      sessionId: sessionId,
      oldRound: 0,
      newRound: 1,
      cause: RoundRetireCause.rework,
    ),
    AttemptProcessExited(
      attemptId: attemptId,
      sessionId: sessionId,
      pid: 10000 + index,
      exitCode: 0,
      exitKind: ExitKind.exited,
      inferred: false,
    ),
    AttemptTerminal(
      attemptId: attemptId,
      sessionId: sessionId,
      workBeadId: workBead,
      outcome: outcomes[index % outcomes.length],
    ),
    WorktreeReaped(
      sessionId: sessionId,
      worktree: '/scratch/wt/$workBead',
      branch: 'grid/$workBead',
    ),
  ];
}

/// Builds the envelope the appender would build, WITHOUT the appender — M5
/// seeds 100k rows by bulk INSERT because the measurement under test is the
/// REBUILD, not the append path (which M3 measures at its real cost).
TrajectoryEnvelope syntheticEnvelope(
  TrajectoryRecord record, {
  required String station,
  required int bootEpoch,
  required int epochSeq,
  required DateTime occurredAt,
  String source = 'measurement_harness',
}) {
  final context = IdemContext(station: station, bootEpoch: bootEpoch);
  final json = <String, Object?>{
    'epoch_seq': epochSeq,
    'record_id': mintUlid(now: occurredAt),
    'idem_key': record.idemKey(context),
    'idem_key_text': record.idemKeyText(context),
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': occurredAt.toIso8601String(),
    'recorded_at': occurredAt.toIso8601String(),
    'station': station,
    'authority_id': '$station/$bootEpoch',
    'boot_epoch': bootEpoch,
    'provenance': 'observed',
    'source': source,
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  };
  // §2.6 rule 7 / ck_seat: seat is service-derived from the bead's prefix.
  final workBeadId = json['work_bead_id'] as String?;
  if (workBeadId != null) {
    final dash = workBeadId.indexOf('-');
    json['seat'] = dash <= 0 ? workBeadId : workBeadId.substring(0, dash);
  }
  return TrajectoryEnvelope.fromJson(json);
}

/// Multi-row INSERT of [envelopes] in batches of [batch]. Returns the number
/// of rows written. Deliberately NOT fenced: see [syntheticEnvelope].
Future<int> bulkInsertTrajectory(
  TrajectoryDb db,
  List<TrajectoryEnvelope> envelopes, {
  int batch = 500,
}) async {
  const columns = [
    'boot_epoch',
    'epoch_seq',
    'record_id',
    'idem_key',
    'idem_key_text',
    'family',
    'record_type',
    'type_version',
    'occurred_at',
    'recorded_at',
    'station',
    'seat',
    'authority_id',
    'provenance',
    'source',
    'work_bead_id',
    'session_id',
    'round',
    'attempt_id',
    'grant_id',
    'worktree',
    'branch',
    'commit_sha',
    'incarnation',
    'outcome',
    'payload',
  ];
  var written = 0;
  for (var offset = 0; offset < envelopes.length; offset += batch) {
    final slice = envelopes.skip(offset).take(batch).toList();
    final values = <String>[];
    for (final envelope in slice) {
      final json = envelope.toJson();
      values.add(
        '(${columns.map((column) => _sqlLiteral(column, json)).join(', ')})',
      );
    }
    await db.execute(
      'INSERT INTO trajectory (${columns.join(', ')}) '
      'VALUES ${values.join(', ')}',
    );
    written += slice.length;
  }
  return written;
}

String _sqlLiteral(String column, Map<String, Object?> json) {
  final value = json[column];
  if (value == null) return 'NULL';
  if (value is int) return '$value';
  if (column == 'payload') return _quote(jsonEncode(value));
  if (column == 'occurred_at' ||
      column == 'recorded_at' ||
      column == 'expires_at') {
    return _quote(sqlDateTime6(DateTime.parse(value as String)));
  }
  return _quote('$value');
}

String _quote(String value) =>
    "'${value.replaceAll('\\', r'\\').replaceAll("'", r"\'")}'";

// ── the synthetic ledger sibling ────────────────────────────────────────────

/// Creates a `ledger` database shaped like a work ledger (an issues table with
/// a JSON blob and an event log) and seeds [issues] rows. This is the stand-in
/// for bd's own database in M2/M3 — the point is a SECOND database on the same
/// server carrying real read/write traffic, not bd's exact schema.
Future<void> seedLedgerDatabase(
  TrajectoryDb admin,
  TrajectoryDb ledger, {
  int issues = 2000,
}) async {
  await admin.execute('CREATE DATABASE IF NOT EXISTS ledger');
  await ledger.execute('''
CREATE TABLE IF NOT EXISTS issues (
  id          VARCHAR(40) NOT NULL PRIMARY KEY,
  title       VARCHAR(255) NOT NULL,
  status      VARCHAR(24)  NOT NULL,
  priority    INT          NOT NULL,
  updated_at  DATETIME(6)  NOT NULL,
  body        TEXT         NULL,
  KEY ix_status (status, priority)
)''');
  await ledger.execute('''
CREATE TABLE IF NOT EXISTS issue_events (
  seq        BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  issue_id   VARCHAR(40) NOT NULL,
  kind       VARCHAR(32) NOT NULL,
  at         DATETIME(6) NOT NULL,
  KEY ix_issue (issue_id, seq)
)''');
  final now = DateTime.utc(2026, 8, 31);
  for (var offset = 0; offset < issues; offset += 500) {
    final rows = <String>[];
    for (var i = offset; i < offset + 500 && i < issues; i++) {
      rows.add(
        "('lg-$i', 'synthetic ledger issue $i', "
        "'${i % 3 == 0 ? 'open' : 'closed'}', ${i % 4}, "
        "'${sqlDateTime6(now)}', '${'body ' * 40}')",
      );
    }
    await ledger.execute(
      'INSERT INTO issues (id, title, status, priority, updated_at, body) '
      'VALUES ${rows.join(', ')}',
    );
  }
}

/// A read/write load generator against the ledger database. Runs until
/// [stop] completes; returns what it managed to do plus every failure it saw
/// (an empty failure list is the "ledger service undisturbed" evidence).
class LedgerLoad {
  LedgerLoad(this._db);

  final TrajectoryDb _db;

  int reads = 0;
  int writes = 0;
  final List<String> failures = [];

  Future<void> run(Future<void> stop, {bool write = true}) async {
    var running = true;
    unawaited(stop.then((_) => running = false));
    var i = 0;
    while (running) {
      i++;
      try {
        await _db.execute(
          "SELECT COUNT(*) AS c FROM issues WHERE status = 'open' "
          'AND priority = :p',
          {'p': i % 4},
        );
        reads++;
        if (write) {
          await _db.execute(
            "INSERT INTO issue_events (issue_id, kind, at) VALUES (:id, 'touch', :at)",
            {'id': 'lg-${i % 2000}', 'at': sqlDateTime6(DateTime.now())},
          );
          writes++;
        }
      } on Object catch (error) {
        failures.add('$error');
        // A killed connection is exactly what M2 is looking for; keep going
        // so recovery (or its absence) is observable rather than fatal.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
}
