/// M3 — append latency with the CURRENT synchronous projection set
/// (storage-call.md stage-0 item 3, and separate-STORE flip condition 2).
///
/// §5 pre-authorizes a retreat if a single serialized appender cannot hold
/// ~22–28 appends/s under an 8-attempt storm. The probe's 42/s carried ONE
/// projection upsert; §6 will eventually want P1–P6+P8 in the same
/// transaction. What exists today is `proj_meta` (the appender's step 5) plus
/// seat A's P1 delta in its INCREMENTAL mode — the SQL the Stage-1 appender
/// adopts — so that pair is what this measures.
///
/// The P1 delta is spliced in through [_StageOneProjectionDb]: a [TrajectoryDb]
/// decorator that recognises the appender's own `proj_meta` upsert and runs
/// `sessionHeadSqlFor` immediately after it, INSIDE the same transaction, at
/// the same `seq`. That is precisely the Stage-1 shape without forking the
/// Stage-0 appender — and when Stage 1 lands, this harness deletes the
/// decorator rather than changing the measurement.
///
/// Load shape: 8 logical writers' worth of attempt lifecycles interleaved into
/// ONE serialized appender (§12: there is only ever one), with a sibling
/// `ledger` database under continuous read+write traffic on the same server.
///
/// Run: `dart run tool/measurements/m3_append_latency.dart`
library;

import 'dart:async';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// Storm width: eight concurrent attempts is the §5 threshold's own shape.
const int stormWidth = 8;

/// At least the 2,000 the task asks for; a whole number of lifecycles.
const int lifecyclesPerWriter = 26; // 8 × 26 × 10 = 2,080 appends

Future<void> main() async {
  final scratch = Directory(p.join(measurementScratchRoot, 'm3'));
  if (scratch.existsSync()) await scratch.delete(recursive: true);
  scratch.createSync(recursive: true);

  banner('M3 — append latency, proj_meta + P1, ledger load alongside');
  final server = await MeasurementServer.start(scratchDir: scratch.path);
  say('hermetic server on ${MeasurementServer.host}:${server.port}');

  final admin = await TrajectoryConnection.connect(server.admin);
  await createTrajectoryDatabase(admin);
  await admin.execute('CREATE DATABASE IF NOT EXISTS ledger');
  final ledger = await TrajectoryConnection.connect(
    server.endpointFor('ledger'),
  );
  await seedLedgerDatabase(admin, ledger);
  say('ledger seeded');

  final stopLoad = Completer<void>();
  final load = LedgerLoad(ledger);
  final ledgerFuture = load.run(stopLoad.future);

  // ── control: proj_meta only (today's Stage-0 appender, untouched) ─────
  final controlStats = await _measure(
    server,
    database: 'trajectory',
    station: 'm3-control',
    withSessionHead: false,
  );
  say('CONTROL  (proj_meta only)         $controlStats');

  // ── the measurement: proj_meta + the Stage-1 P1 delta ────────────────
  final stageOneStats = await _measure(
    server,
    database: 'trajectory',
    station: 'm3-p1',
    withSessionHead: true,
  );
  say('STAGE-1  (proj_meta + P1 delta)   $stageOneStats');

  // ── the §6 headroom probe, labelled for what it is ───────────────────
  // §6 wants P1–P6+P8 in-transaction; only P1's delta exists. Repeating the
  // P1 upsert seven times is a STATEMENT-COUNT proxy — it buys the right
  // number of in-transaction round trips and writes, and it does NOT prove
  // anything about P2–P8's own row shapes or index costs. It is here because
  // the threshold question is about statement count, and a number is better
  // than the draft's "plausibly 35–45 ms".
  final sevenStats = await _measure(
    server,
    database: 'trajectory',
    station: 'm3-p7',
    withSessionHead: true,
    projectionStatements: 7,
  );
  say('§6 PROXY (proj_meta + 7 upserts)  $sevenStats');

  stopLoad.complete();
  await ledgerFuture;
  say(
    'ledger traffic during the run: reads=${load.reads} writes=${load.writes} '
    'failures=${load.failures.length}',
  );
  for (final failure in load.failures.take(3)) {
    say('  ledger failure: $failure');
  }

  final sevenVerdict = sevenStats.rateFor >= 28
      ? 'ABOVE the band'
      : sevenStats.rateFor >= 22
      ? 'INSIDE the band'
      : 'BELOW 22/s';
  say(
    '§6 proxy vs the same band: $sevenVerdict '
    '(${sevenStats.rateFor.toStringAsFixed(1)}/s)',
  );

  final threshold = stageOneStats.rateFor >= 28
      ? 'ABOVE the 22–28/s band — no retreat'
      : stageOneStats.rateFor >= 22
      ? 'INSIDE the 22–28/s band — margin is thin'
      : 'BELOW 22/s — §5 pre-authorized retreat triggers';
  say('verdict vs the §5 retreat threshold: $threshold');
  say(
    'P1\'s marginal cost: '
    '${(stageOneStats.meanMs - controlStats.meanMs).toStringAsFixed(2)}ms '
    '(${(controlStats.rateFor - stageOneStats.rateFor).toStringAsFixed(1)}/s)',
  );

  await ledger.close();
  await admin.close();
  await server.dispose();
  exit(0);
}

Future<LatencyStats> _measure(
  MeasurementServer server, {
  required String database,
  required String station,
  required bool withSessionHead,
  int projectionStatements = 1,
}) async {
  final raw = await TrajectoryConnection.connect(server.endpointFor(database));
  await applyTrajectorySchema(raw);
  final db = _StageOneProjectionDb(
    raw,
    enabled: withSessionHead,
    repeats: projectionStatements,
  );
  final appender = TrajectoryAppender(
    db: db,
    station: station,
    onEvent: (event) => say('  service event: ${event.kind.name}'),
  );
  await appender.claimEpoch(pid: pid, pgid: pid);

  // Eight interleaved lifecycles: writer w's record k lands at position
  // k * stormWidth + w, so the appender sees the round-robin a real storm
  // produces rather than eight tidy blocks.
  final base = DateTime.utc(2026, 8, 31, 9);
  final queue = <TrajectoryRecord>[];
  for (var lifecycle = 0; lifecycle < lifecyclesPerWriter; lifecycle++) {
    final batch = <List<TrajectoryRecord>>[
      for (var writer = 0; writer < stormWidth; writer++)
        familyOneLifecycle(
          lifecycle * stormWidth + writer,
          at: base.add(Duration(seconds: lifecycle * stormWidth + writer)),
          stationPrefix: station,
          beadPrefix: 'tg',
        ),
    ];
    for (var step = 0; step < batch.first.length; step++) {
      for (final writer in batch) {
        queue.add(writer[step]);
      }
    }
  }

  final samples = <int>[];
  var landed = 0;
  var refused = 0;
  final watch = Stopwatch()..start();
  for (final record in queue) {
    // The decorator needs the typed record to render the P1 delta; the
    // envelope it would key off does not exist until the appender builds it,
    // so the harness hands the record over first.
    db.pending = record;
    final one = Stopwatch()..start();
    final outcome = await appender.append(record);
    one.stop();
    samples.add(one.elapsedMicroseconds);
    if (outcome is Appended) {
      landed++;
    } else {
      refused++;
      say('  non-Appended outcome: $outcome');
    }
  }
  watch.stop();

  final heads = await raw.execute(
    'SELECT COUNT(*) AS c FROM proj_session_head',
  );
  final rows = await raw.execute(
    'SELECT COUNT(*) AS c FROM trajectory WHERE station = :station',
    {'station': station},
  );
  say(
    '$station: landed=$landed refused=$refused '
    'rows=${rows.rows.first['c']} heads=${heads.rows.first['c']} '
    'wall=${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s '
    'dolt commits=${appender.verifiedDoltCommits}',
  );
  await raw.close();
  return LatencyStats(samples);
}

/// Splices the Stage-1 P1 upsert into the Stage-0 append transaction.
///
/// The appender's step 5 is the ONLY `proj_meta` statement it issues, and it
/// carries the just-assigned `seq` in `:seq` — so recognising that statement
/// is a precise hook, not a heuristic over arbitrary SQL. With [enabled]
/// false this is a pass-through and the control run measures today's cost.
class _StageOneProjectionDb implements TrajectoryDb {
  _StageOneProjectionDb(this._inner, {required this.enabled, this.repeats = 1});

  final TrajectoryDb _inner;
  final bool enabled;

  /// How many times the P1 statement runs — 1 is the honest Stage-1 shape;
  /// more is the §6 statement-count proxy and nothing else.
  final int repeats;

  /// The record currently being appended, set by the caller before `append`.
  TrajectoryRecord? pending;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    final result = await _inner.execute(sql, params);
    if (!enabled || !sql.startsWith('INSERT INTO proj_meta')) return result;
    final record = pending;
    final seq = params?['seq'];
    if (record == null || seq is! int) return result;
    final delta = _deltaFor(record, seq);
    if (delta == null) return result;
    final statement = sessionHeadSqlFor(delta, lastSeq: seq);
    for (var i = 0; i < repeats; i++) {
      await _inner.execute(statement.sql, statement.params);
    }
    return result;
  }

  /// The delta the Stage-1 appender would compute from the record it already
  /// holds. It builds a minimal envelope because `sessionHeadDeltaFor` reads
  /// only `family`, `seat`, `occurred_at`, and `boot_epoch` off it when the
  /// decoded record is supplied.
  SessionHeadDelta? _deltaFor(TrajectoryRecord record, int seq) {
    if (record.family != TrajectoryFamily.attempt) return null;
    final envelope = TrajectoryEnvelope(
      seq: seq,
      recordId: 'm3',
      idemKey: 'm3',
      idemKeyText: 'm3',
      family: record.family,
      recordType: record.recordType,
      occurredAt: DateTime.utc(2026, 8, 31, 9),
      recordedAt: DateTime.utc(2026, 8, 31, 9),
      station: 'm3',
      authorityId: 'm3/1',
      bootEpoch: 1,
      source: 'm3',
      payload: const {},
    );
    return sessionHeadDeltaFor(envelope, decoded: record);
  }

  @override
  Future<void> close() => _inner.close();
}
