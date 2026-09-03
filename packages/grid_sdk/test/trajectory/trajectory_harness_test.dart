// W1 (tg-zfek Stage 1) — the trajectory harness's lifecycle and failure
// branches, offline, with fakes at the appender/connection seams:
//
//   * config postures (§1.3): disabled / auto-unprovisioned / auto-provisioned
//     / required, and that no posture can fail a boot;
//   * verify-before-claim boot order (§1.2, r2 minor 17) and the claim;
//   * the bounded append queue + single writer loop (§2.5): FIFO, overflow
//     drop-and-count, the enqueue-never-awaits contract;
//   * the sealed-outcome mapping (§3): dedupe counts, internal errors drop +
//     reconnect eagerly, fenced-out latches quiet ONCE, corruption halts loud;
//   * guarded shutdown (§1.2): drain → fixpoint → boundary commit → dispose,
//     each settled, never thrown, sources never blocked;
//   * the gc cadence (M2) as its own non-fatal loop.
import 'dart:async';
import 'dart:io';

import 'package:grid_engine/grid_engine.dart'
    show
        DualReadMode,
        SessionHeadWon,
        TerminalReconcileOutcome,
        TerminalReconcileRequest,
        TrajectorySnapshotHealth;
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
// TEST-ONLY (tg-3o6b): the gc branches classify REAL server errors, so the
// suite throws the real shape rather than a stand-in.
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

/// The envelope a landed append hands back (cut-wiring §0.2's post-ACK mirror
/// seam) — the appender's own derivation, minus the service stamps a test
/// does not care about.
TrajectoryEnvelope committedEnvelope(
  TrajectoryRecord record, {
  required String recordId,
  DateTime? occurredAt,
  TrajectoryProvenance provenance = TrajectoryProvenance.observed,
  String? provenanceBasis,
  String? seat,
}) {
  final stamped = occurredAt ?? DateTime.utc(2026, 8, 31, 12);
  final json = <String, Object?>{
    'record_id': recordId,
    'idem_key': recordId.padRight(64, '0'),
    'idem_key_text': 'test:$recordId',
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': stamped.toIso8601String(),
    'recorded_at': stamped.toIso8601String(),
    'station': 'fake',
    'authority_id': 'fake/1',
    'boot_epoch': 1,
    'provenance': provenance.wire,
    if (provenance != TrajectoryProvenance.observed)
      'provenance_basis': provenanceBasis ?? 'test-basis',
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  };
  // ck_seat: the service derives the seat from the bead's store prefix.
  if (json['work_bead_id'] != null) json['seat'] = seat ?? 'tg';
  return TrajectoryEnvelope.fromJson(json);
}

/// The stale-fold shape probe's statement (r12) — the one boot read a test
/// that fails "every SELECT" usually still wants answered, because failing it
/// refuses the live arm outright.
bool _isShapeProbe(String sql) => sql.contains('information_schema.columns');

/// A scriptable [TrajectoryDb]: records statements, optionally throws.
final class _FakeDb implements TrajectoryDb {
  _FakeDb({this.onExecute});

  final List<String> statements = [];

  /// Re-assignable: the mirror's reseed guard is driven by CHANGING what the
  /// live session answers between two passes.
  Object? Function(String sql)? onExecute;
  bool closed = false;
  bool closeThrows = false;

  /// Runs INSIDE [close]'s await — the reconnect's connection-swap window,
  /// which is the only place a test can observe what the serial lane sees
  /// while the dead session is being retired.
  Future<void> Function()? onClose;

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    statements.add(sql);
    final scripted = onExecute?.call(sql);
    if (scripted is Object && scripted is! SqlResult) {
      // Anything non-result scripted for this statement is thrown.
      // ignore: only_throw_errors
      throw scripted;
    }
    if (scripted is SqlResult) return scripted;
    // DEFAULT: a grid home already at the WAVE-1 CUT SHAPE. `start()` refuses
    // the live arm on a pre-cut `proj_session_head` (the stale-fold refusal),
    // so the fake has to answer the shape probe or every harness test would
    // degrade at boot. A test that wants the PRE-CUT home scripts an empty (or
    // partial) answer for this statement.
    if (sql.contains('information_schema.columns')) {
      return SqlResult(
        rows: [
          for (final column in projSessionHeadCutColumns) {'name': column},
        ],
      );
    }
    return const SqlResult();
  }

  @override
  Future<void> close() async {
    if (closeThrows) throw StateError('close refused');
    await onClose?.call();
    closed = true;
  }
}

/// A trivial obligation: one SELECT on the harness's serial read lane, no
/// repairs. It exists to put a TICK QUERY on that lane at a chosen instant.
final class _ProbeQuery extends ObligationQuery {
  @override
  String get name => 'probe';

  @override
  String get sql => 'SELECT 1 AS one';

  @override
  Future<List<ObligationAppend>> repair(
    List<Map<String, String?>> rows,
  ) async => const [];
}

/// A scriptable appender: the harness drives THIS seam; the real §5 SQL path
/// is Stage-0-tested in grid_trajectory.
final class _FakeAppender extends TrajectoryAppender {
  _FakeAppender(_FakeDb db) : super(db: db, station: 'fake');

  /// Ordered call log — `verify`, `claim:<cause>`, `append:<type>`,
  /// `commit`, `reconnect`.
  final List<String> calls = [];

  AppendCorruptionHalt? verifyResult;
  EpochClaimOutcome claimResult = const EpochClaimed(epoch: 1);
  int? claimedPid;
  int? claimedPgid;

  /// Consumed FIFO; empty falls back to a fresh [Appended].
  final List<AppendOutcome> appendOutcomes = [];
  ReconnectOutcome reconnectResult = const ReconnectResumed(epoch: 1);
  Object? commitError;
  bool fakeInert = false;
  bool fakeHalted = false;

  /// Every record handed to [append], with its provenance — the subscriber
  /// tests read derived envelopes off these.
  final List<TrajectoryRecord> records = [];
  final List<TrajectoryProvenance> provenances = [];

  /// True wedges [append] forever (a dead socket that neither errors nor
  /// returns) — the shutdown-timeout test's writer.
  bool appendNeverCompletes = false;
  int _seq = 0;

  @override
  bool get isInert => fakeInert;

  @override
  bool get isHalted => fakeHalted;

  @override
  Future<AppendCorruptionHalt?> verifyBeltAtBoot() async {
    calls.add('verify');
    return verifyResult;
  }

  @override
  Future<EpochClaimOutcome> claimEpoch({
    required int pid,
    required int pgid,
    String cause = 'boot',
    int maxAttempts = 3,
  }) async {
    calls.add('claim:$cause');
    claimedPid = pid;
    claimedPgid = pgid;
    return claimResult;
  }

  @override
  Future<AppendOutcome> append(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    String? source,
    int? fencingToken,
  }) async {
    calls.add('append:${record.recordType}');
    records.add(record);
    provenances.add(provenance);
    if (appendNeverCompletes) return Completer<AppendOutcome>().future;
    if (appendOutcomes.isNotEmpty) return appendOutcomes.removeAt(0);
    _seq += 1;
    return Appended(
      recordId: 'r$_seq',
      seq: _seq,
      epochSeq: _seq,
      // The COMMITTED envelope the post-ACK mirror seam folds (cut-wiring
      // §0.2): derived from the record exactly as the real appender derives
      // it, so a mirror test sees real deltas rather than a stand-in.
      envelope: committedEnvelope(
        record,
        recordId: 'r$_seq',
        occurredAt: occurredAt,
        provenance: provenance,
        provenanceBasis: provenanceBasis,
        seat: seat,
      ),
    );
  }

  @override
  Future<void> doltCommitIfDue() async {
    calls.add('commit');
    final error = commitError;
    if (error != null) throw error;
  }

  @override
  Future<ReconnectOutcome> reconnect(TrajectoryDb db) async {
    calls.add('reconnect');
    return reconnectResult;
  }
}

final class _FakeTimer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

TrajectoryAppendRequest _note(int ordinal, {String session = 's-1'}) =>
    TrajectoryAppendRequest(
      AttemptNote(
        sessionId: session,
        body: 'note $ordinal',
        channel: 'test',
        noteOrdinal: ordinal,
      ),
    );

/// A record carrying BOTH promoted correlation keys the drop flare reports.
TrajectoryAppendRequest _stepTransition({
  String session = 's-1',
  String stepPath = 'code/deliver',
}) => TrajectoryAppendRequest(
  StepTransition(
    sessionId: session,
    round: 1,
    stepPath: stepPath,
    stepRound: 0,
    incarnation: 0,
    state: StepState.failed,
  ),
);

void main() {
  late Directory tmp;
  late List<(String, Map<String, String>)> flares;
  late List<(Duration, void Function(), _FakeTimer)> timers;
  late List<_FakeDb> connected;
  late _FakeAppender appender;
  DateTime now = DateTime.utc(2026, 8, 31, 12);
  Object? connectError;
  Object? Function(String sql)? dbScript;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tg-zfek-w1-');
    flares = [];
    timers = [];
    connected = [];
    appender = _FakeAppender(_FakeDb());
    connectError = null;
    dbScript = null;
    now = DateTime.utc(2026, 8, 31, 12);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  List<String> flareNames() => [for (final (name, _) in flares) name];

  /// The default config ARMS the dual read (`observe`). Production defaults to
  /// `off` (r13) and this file's `dualRead: off` group pins that posture
  /// explicitly; every other test here is about the cut's own machinery, which
  /// only exists when the posture asks for it.
  Future<TrajectoryHarness> harness({
    TrajectoryConfig config = const TrajectoryConfig(
      mode: TrajectoryConfigMode.required,
      dualRead: DualReadMode.observe,
    ),
    Stream<RuntimeEvent>? runtimeEvents,
    List<ObligationQuery>? tickQueries,
  }) => TrajectoryHarness.build(
    config: config,
    gridHome: tmp.path,
    station: 'tranquility',
    seatPrefixes: const {'tg', 'the_grid', 'tranquility'},
    onFlare: (name, data) => flares.add((name, data)),
    runtimeEvents: runtimeEvents,
    tickQueries: tickQueries,
    connect: () async {
      final error = connectError;
      if (error != null) throw error; // ignore: only_throw_errors
      final db = _FakeDb(onExecute: dbScript);
      connected.add(db);
      return db;
    },
    appenderFactory: (_) => appender,
    scheduleTimer: (duration, callback) {
      final timer = _FakeTimer();
      timers.add((duration, callback, timer));
      return timer;
    },
    clock: () => now,
    identity: (pid: 41, pgid: 42),
  );

  group('config postures (§1.3)', () {
    test(
      'disabled: no connection, no claim, enqueue is a SILENT no-op',
      () async {
        final h = await harness(
          config: const TrajectoryConfig(mode: TrajectoryConfigMode.disabled),
        );
        expect(h.mode, TrajectoryHarnessMode.disabled);
        await h.start();
        h.enqueue(_note(1));
        await h.shutdown();
        expect(connected, isEmpty);
        expect(appender.calls, isEmpty);
        expect(h.status.suppressed, 0);
        expect(h.status.queueDepth, 0);
        expect(flares, isEmpty, reason: 'a station chose legacy-only: silence');
      },
    );

    test('auto without the provisioning artifact boots legacy-only', () async {
      final h = await harness(
        config: const TrajectoryConfig(mode: TrajectoryConfigMode.auto),
      );
      expect(h.mode, TrajectoryHarnessMode.unprovisioned);
      expect(h.status.cause, contains('trajectory.secret'));
      await h.start();
      h.enqueue(_note(1));
      await h.shutdown();
      expect(connected, isEmpty);
      expect(flares, isEmpty, reason: 'a one-line notice, not a warning storm');
    });

    test('auto with the artifact present arms', () async {
      File(trajectorySecretPath(tmp.path))
        ..createSync(recursive: true)
        ..writeAsStringSync('secret');
      final h = await harness(
        config: const TrajectoryConfig(mode: TrajectoryConfigMode.auto),
      );
      expect(h.mode, TrajectoryHarnessMode.down);
      await h.start();
      expect(h.mode, TrajectoryHarnessMode.live);
    });

    test(
      'required with a refused connect degrades LOUD — never throws',
      () async {
        connectError = StateError('connection refused');
        final h = await harness();
        await h.start();
        expect(h.mode, TrajectoryHarnessMode.degraded);
        expect(h.status.cause, contains('connection refused'));
        expect(flareNames(), contains('trajectory.degraded'));
        // Work is never blocked: enqueue keeps short-circuiting to a count.
        h.enqueue(_note(1));
        expect(h.status.suppressed, 1);
      },
    );
  });

  group('boot (§1.2 step 2)', () {
    test('verify-before-claim: order pinned, identity threaded', () async {
      final h = await harness();
      await h.start();
      expect(appender.calls.sublist(0, 2), ['verify', 'claim:boot']);
      expect(appender.claimedPid, 41);
      expect(appender.claimedPgid, 42);
      expect(h.mode, TrajectoryHarnessMode.live);
      expect(h.status.epoch, 1);
      // Tick armed (boot pass ran + interval scheduled) and gc scheduled.
      expect(h.tick, isNotNull);
      expect(h.tick!.isArmed, isTrue);
      expect(h.tick!.lastPass, isNotNull);
      expect(
        [for (final (duration, _, _) in timers) duration],
        containsAll([
          const TrajectoryConfig().tickInterval,
          kDefaultTrajectoryGcInterval,
        ]),
      );
    });

    test('a halted belt verify means NO claim, no fence advance, flare, '
        'legacy-only boot', () async {
      appender.verifyResult = const AppendCorruptionHalt(
        reason: 'belt full-scan: out of order',
      );
      final h = await harness();
      await h.start();
      expect(appender.calls, ['verify'], reason: 'claimEpoch never ran');
      expect(h.mode, TrajectoryHarnessMode.halted);
      expect(flareNames(), contains('trajectory.halted'));
      expect(connected.single.closed, isTrue);
      expect(h.tick, isNull);
    });

    test(
      'a refused claim degrades to legacy-only, never a boot failure',
      () async {
        appender.claimResult = const EpochClaimRefused(attempts: 3);
        final h = await harness();
        await h.start();
        expect(h.mode, TrajectoryHarnessMode.degraded);
        expect(h.status.cause, contains('refused after 3 attempts'));
        expect(connected.single.closed, isTrue);
      },
    );

    // ── THE STALE-FOLD REFUSAL (cut-wiring C0, r12) ──────────────────────
    //
    // The wave-1 cut widened `proj_session_head`. The boot seed reads
    // `SELECT *` and nulls absent columns, so an un-reshaped home SEEDS CLEAN
    // and reads live — and then every terminal append dies inside its
    // transaction on an unknown column, rolls back whole, and lands as a
    // counted drop behind a RATE-LIMITED flare. The trajectory is dead for
    // that home and nothing says why. Fail closed and loud instead.
    test('a PRE-CUT proj_session_head REFUSES the live arm, before the claim, '
        'with a cause naming `traj replay`', () async {
      dbScript = (sql) => _isShapeProbe(sql)
          // The pre-cut shape: the table exists, the wave-1 columns do not.
          ? const SqlResult(
              rows: [
                {'name': 'session_id'},
                {'name': 'status'},
                {'name': 'outcome'},
              ],
            )
          : null;
      final h = await harness();
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.degraded);
      expect(h.status.cause, contains('traj replay'));
      expect(h.status.cause, contains('terminal_provenance'));
      expect(h.status.cause, contains('unknown_reason'));
      expect(flareNames(), contains('trajectory.degraded'));
      // NO EPOCH CLAIM: a boot that will not run must not advance the fence.
      expect(appender.calls, ['verify'], reason: 'claimEpoch never ran');
      expect(h.status.epoch, isNull);
      expect(h.tick, isNull);
      expect(connected.single.closed, isTrue);
    });

    test('the refusal is not silent death: an append enqueued after it is '
        'SUPPRESSED and counted, never a hole nobody can see', () async {
      dbScript = (sql) => _isShapeProbe(sql) ? const SqlResult() : null;
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      expect(h.mode, TrajectoryHarnessMode.degraded);
      expect(h.status.suppressed, greaterThan(0));
      expect(h.status.dropped, isZero, reason: 'refused up front, not dropped');
    });

    test('a home ALREADY at the cut shape arms normally, and the probe runs '
        'before the claim', () async {
      final h = await harness();
      await h.start();
      expect(h.mode, TrajectoryHarnessMode.live);
      final statements = connected.single.statements;
      expect(statements.first, contains('information_schema.columns'));
      expect(statements.first, contains(':table'));
    });

    // ── THE ROLLBACK POSTURE (r13) ───────────────────────────────────────
    //
    // `DualReadMode.off` is the DEFAULT and must be byte-equivalent to pre-cut
    // mainline. It is not enough for the comparator to be inert: the FOLD-SIDE
    // machinery has to be off too, or an existing home that upgraded without
    // running the quiesced `traj replay` refuses to arm — the exact population
    // the rollback is for.
    test('dualRead: off does NOT probe the projection shape — a PRE-CUT home '
        'arms exactly as it does on mainline', () async {
      dbScript = (sql) => _isShapeProbe(sql)
          ? const SqlResult(
              rows: [
                {'name': 'session_id'},
                {'name': 'status'},
              ],
            )
          : null;
      final h = await harness(
        config: const TrajectoryConfig(
          mode: TrajectoryConfigMode.required,
          dualRead: DualReadMode.off,
        ),
      );
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.live);
      expect(
        connected.single.statements.where(_isShapeProbe),
        isEmpty,
        reason: 'no reshape probe at the rollback posture',
      );
    });

    test('dualRead: off seeds NEITHER mirror and re-reads no generation set — '
        'the boot pays for no fold nobody reads', () async {
      final h = await harness(
        config: const TrajectoryConfig(
          mode: TrajectoryConfigMode.required,
          dualRead: DualReadMode.off,
        ),
      );
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.live);
      // The seed's five reads, by shape. (The Stage-1 obligation queries also
      // name `proj_session_head`; they are pre-cut and unrelated.)
      final statements = connected.single.statements;
      for (final seedRead in [
        'SELECT * FROM proj_session_head',
        'SELECT * FROM proj_step_cursor',
        'FROM proj_meta',
        'MIN(advanced_at)',
      ]) {
        expect(
          statements.where((s) => s.contains(seedRead)),
          isEmpty,
          reason: seedRead,
        );
      }
      expect(
        h.sessionHeads.health,
        TrajectorySnapshotHealth.refused,
        reason: 'never seeded is never live',
      );
      expect(h.stepCursors.health, TrajectorySnapshotHealth.refused);
      expect(flareNames(), isEmpty);
    });

    test('dualRead: off keeps the mirrors out of the append path, and a '
        'dropped append raises no dualReadCompromised', () async {
      appender.appendOutcomes.add(const AppendInternalError(cause: 'socket'));
      final h = await harness(
        config: const TrajectoryConfig(
          mode: TrajectoryConfigMode.required,
          dualRead: DualReadMode.off,
        ),
      );
      await h.start();
      h.enqueue(_note(1));
      await h.runToFixpoint();

      expect(h.status.dropped, 1);
      expect(
        flareNames(),
        isNot(contains('trajectory.dualReadCompromised')),
        reason: 'no mirror is being maintained to compromise',
      );
    });

    test('records enqueued before the claim drain once live', () async {
      final h = await harness();
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      expect(h.status.queueDepth, 2, reason: 'queued, not lost, not appended');
      await h.start();
      await h.runToFixpoint();
      expect(h.status.appended, 2);
    });
  });

  group('the append queue + single writer (§2.5)', () {
    test('enqueue returns synchronously and the writer drains FIFO', () async {
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      h.enqueue(_note(3));
      await h.runToFixpoint();
      expect(
        appender.calls.where((call) => call.startsWith('append:')).length,
        3,
      );
      expect(h.status.appended, 3);
      expect(h.status.queueDepth, 0);
    });

    test('overflow drops the INCOMING append, counts, and flares', () async {
      final h = await harness(
        config: const TrajectoryConfig(
          mode: TrajectoryConfigMode.required,
          dualRead: DualReadMode.observe,
          queueBound: 2,
        ),
      );
      await h.start();
      // #1 goes in-flight immediately; #2/#3 fill the bound; #4 overflows.
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      h.enqueue(_note(3));
      h.enqueue(_note(4));
      expect(h.status.dropped, 1);
      expect(flareNames(), contains('trajectory.queueOverflow'));
      await h.runToFixpoint();
      expect(h.status.appended, 3, reason: 'the queued three still land');
    });

    test('a dedupe is success, counted separately', () async {
      appender.appendOutcomes.add(const AppendDeduped(recordId: 'orig'));
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      await h.runToFixpoint();
      expect(h.status.deduped, 1);
      expect(h.status.dropped, 0);
      expect(flares, isEmpty);
    });
  });

  group('sealed-outcome mapping (§3)', () {
    test(
      'a dropped append NAMES the session and step it lost (tg-kzvs)',
      () async {
        appender.appendOutcomes.add(
          const AppendInternalError(
            cause: MySQLServerException(
              "string 'pow-26dd/deliver: …' is too large for column "
              "'work_terminal_reason'",
              1105,
            ),
          ),
        );
        final h = await harness();
        await h.start();
        h.enqueue(_stepTransition());
        await h.runToFixpoint();

        final data = flares
            .firstWhere((flare) => flare.$1 == 'trajectory.appendDropped')
            .$2;
        expect(data['recordType'], 'step.transition');
        expect(data['sessionId'], 's-1');
        expect(data['stepPath'], 'code/deliver');
        expect(data['reason'], contains('work_terminal_reason'));
        expect(data['dropped'], '1');
        expect(h.status.dropped, 1);
      },
    );

    test('AppendInternalError: drop + rate-limited flare + eager guarded '
        'reconnect on the next append', () async {
      appender.appendOutcomes.add(
        AppendInternalError(cause: StateError('socket died')),
      );
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      await h.runToFixpoint();
      expect(h.status.dropped, 1);
      expect(h.status.appended, 1, reason: 'the loop kept draining');
      expect(appender.calls, contains('reconnect'));
      expect(connected, hasLength(2), reason: 'the listener was re-dialed');
      expect(
        flareNames().where((name) => name == 'trajectory.appendDropped'),
        hasLength(1),
        reason: '30 s bucket: one flare per name',
      );
      expect(h.mode, TrajectoryHarnessMode.live);
    });

    test(
      'the appendDropped flare re-fires once the 30 s bucket rolls',
      () async {
        appender.appendOutcomes.addAll([
          AppendInternalError(cause: StateError('one')),
          AppendInternalError(cause: StateError('two')),
        ]);
        final h = await harness();
        await h.start();
        h.enqueue(_note(1));
        await h.runToFixpoint();
        now = now.add(const Duration(seconds: 31));
        h.enqueue(_note(2));
        await h.runToFixpoint();
        expect(
          flareNames().where((name) => name == 'trajectory.appendDropped'),
          hasLength(2),
        );
        expect(h.status.dropped, 2);
      },
    );

    test('fenced out latches QUIET: one flare, queue suppressed, later '
        'derivations short-circuit to a count', () async {
      appender.appendOutcomes.add(const AppendFencedOut(reason: 'cas-zero'));
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      await h.runToFixpoint();
      expect(h.mode, TrajectoryHarnessMode.fencedOut);
      expect(h.status.suppressed, 1, reason: 'the queued #2 was suppressed');
      h.enqueue(_note(3));
      expect(h.status.suppressed, 2);
      expect(
        flareNames().where((name) => name == 'trajectory.fencedOut'),
        hasLength(1),
        reason: 'ONCE — this process should be going down anyway',
      );
    });

    test('a corruption halt latches LOUD and stops the writer', () async {
      appender.appendOutcomes.add(
        const AppendCorruptionHalt(reason: 'uq_epoch_seq violation'),
      );
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      await h.runToFixpoint();
      expect(h.mode, TrajectoryHarnessMode.halted);
      expect(h.status.cause, contains('uq_epoch_seq'));
      expect(flareNames(), contains('trajectory.halted'));
    });

    test('an inert reconnect latches fenced out', () async {
      appender.appendOutcomes.add(
        AppendInternalError(cause: StateError('socket died')),
      );
      appender.reconnectResult = const ReconnectInert(
        staleEpoch: 1,
        liveEpoch: 2,
      );
      final h = await harness();
      await h.start();
      h.enqueue(_note(1));
      h.enqueue(_note(2));
      await h.runToFixpoint();
      expect(h.mode, TrajectoryHarnessMode.fencedOut);
      expect(h.status.cause, 'stale epoch 1 (live 2)');
    });

    test(
      'a failed reconnect drops the append and stays live for the next',
      () async {
        appender.appendOutcomes.add(
          AppendInternalError(cause: StateError('socket died')),
        );
        final h = await harness();
        await h.start();
        h.enqueue(_note(1));
        await h.runToFixpoint();
        connectError = StateError('listener gone');
        h.enqueue(_note(2));
        await h.runToFixpoint();
        expect(h.status.dropped, 2);
        expect(h.mode, TrajectoryHarnessMode.live);
        // The listener resolves again once bd rewrites the port (§4) — after
        // the debounce window (quality M3), which floors reconnect attempts
        // at one per [kReconnectDebounce].
        connectError = null;
        now = now.add(kReconnectDebounce);
        h.enqueue(_note(3));
        await h.runToFixpoint();
        expect(h.status.appended, 1);
      },
    );

    test(
      'reconnect is DEBOUNCED (quality M3): inside the window no dial is even '
      'attempted — one resolve+connect per window, never one per record',
      () async {
        appender.appendOutcomes.add(
          AppendInternalError(cause: StateError('socket died')),
        );
        final h = await harness();
        await h.start();
        h.enqueue(_note(1)); // consumes the internal error → needsReconnect
        await h.runToFixpoint();
        connectError = StateError('listener gone');
        h.enqueue(_note(2)); // the eager attempt: dials, fails
        await h.runToFixpoint();
        expect(h.status.dropped, 2);
        expect(connected, hasLength(1), reason: 'boot dial only');
        // The server comes BACK immediately — but the window has not lapsed,
        // so the next append still drops WITHOUT dialing (the whole point:
        // no per-record resolve+connect storm on the drain).
        connectError = null;
        h.enqueue(_note(3));
        await h.runToFixpoint();
        expect(h.status.dropped, 3);
        expect(
          connected,
          hasLength(1),
          reason: 'debounced: no dial inside the window',
        );
        expect(h.mode, TrajectoryHarnessMode.live);
        // The window lapses: the next append dials once and resumes.
        now = now.add(kReconnectDebounce);
        h.enqueue(_note(4));
        await h.runToFixpoint();
        expect(connected, hasLength(2), reason: 'exactly one reconnect dial');
        expect(h.status.appended, 1);
      },
    );

    test('a resumed reconnect PUBLISHES the fresh session before retiring the '
        'dead one: a tick query landing in the swap window never sees a '
        'closed connection', () async {
      final probe = _ProbeQuery();
      final h = await harness(tickQueries: [probe]);
      await h.start();
      // The swap window is exactly the dead session's `close()`. Run a tick
      // pass from inside it — the same serial lane the tick's reads ride, so
      // this is the real interleaving, not a simulated one.
      TrajectoryTickPass? windowPass;
      connected.single.onClose = () async {
        windowPass = await h.tick!.runPass();
      };
      appender.appendOutcomes.add(
        AppendInternalError(cause: StateError('socket died')),
      );
      h.enqueue(_note(1)); // consumes the error → needsReconnect
      h.enqueue(_note(2)); // the eager reconnect, and the swap
      await h.runToFixpoint();

      expect(connected, hasLength(2), reason: 'sanity: the reconnect dialled');
      expect(windowPass, isNotNull, reason: 'sanity: the window was entered');
      expect(
        windowPass!.refusals,
        isEmpty,
        reason:
            'ordering the close FIRST nulls _db across an await, and the '
            'lane reads it: the pass refused with "trajectory connection is '
            'closed" against a harness that had just reconnected fine',
      );
      expect(windowPass!.queriesRun, 1);
      expect(h.mode, TrajectoryHarnessMode.live);
      expect(h.status.appended, 1);
      // The dead session was still retired — publishing first is a reorder,
      // never a leak.
      expect(connected.first.closed, isTrue);
    });
  });

  group('guarded shutdown (§1.2)', () {
    test(
      'drain → fixpoint → boundary commit → dispose → close, receipted',
      () async {
        final h = await harness();
        await h.start();
        h.enqueue(_note(1));
        await h.shutdown();
        expect(h.status.appended, 1, reason: 'the queue drained first');
        expect(appender.calls.last, 'commit', reason: 'the boundary flush');
        expect(h.tick!.isArmed, isFalse, reason: 'tick disposed');
        expect(connected.single.closed, isTrue);
        final (name, data) = flares.single;
        expect(name, 'trajectory.shutdown');
        expect(data['appended'], '1');
        expect(data['fixpointReached'], 'true');
        expect(data['outstanding'], '0');
        // Idempotent: a second shutdown neither throws nor re-flares.
        await h.shutdown();
        expect(flares, hasLength(1));
      },
    );

    test(
      'a throwing boundary commit is the cadence-failure signal, caught',
      () async {
        appender.commitError = StateError('branch pin');
        final h = await harness();
        await h.start();
        await h.shutdown();
        expect(flareNames(), contains('trajectory.cadenceFailure'));
        expect(flareNames(), contains('trajectory.shutdown'));
        expect(connected.single.closed, isTrue, reason: 'close still reached');
      },
    );

    test('shutdown NEVER throws — even when every step does', () async {
      appender.commitError = StateError('commit refused');
      final h = await harness();
      await h.start();
      connected.single.closeThrows = true;
      await h.shutdown(); // completing at all is the assertion
      expect(flareNames(), contains('trajectory.shutdown'));
    });

    test('gc cadence cancels at shutdown', () async {
      final h = await harness();
      await h.start();
      final gc = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      await h.shutdown();
      expect(gc.$3.cancelled, isTrue);
    });

    test('enqueue after shutdown short-circuits to a count', () async {
      final h = await harness();
      await h.start();
      await h.shutdown();
      h.enqueue(_note(1));
      expect(h.status.suppressed, 1);
    });

    test(
      'a WEDGED writer cannot hang shutdown (quality M2): the drain is '
      'bounded, the remainder counted + flared, dispose still reached',
      () async {
        final h = await harness(
          config: const TrajectoryConfig(
            mode: TrajectoryConfigMode.required,
            dualRead: DualReadMode.observe,
            shutdownDrainTimeout: Duration(milliseconds: 200),
          ),
        );
        await h.start();
        // The dead-socket shape the guarantee exists for: an append that
        // neither returns nor throws.
        appender.appendNeverCompletes = true;
        h.enqueue(_note(1));
        h.enqueue(_note(2));
        final commitsBefore = appender.calls.where((c) => c == 'commit').length;
        final watch = Stopwatch()..start();
        await h.shutdown();
        watch.stop();
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 5)),
          reason: 'the guarantee covers hangs, not just throws',
        );
        expect(flareNames(), contains('trajectory.shutdownDrainTimeout'));
        expect(flareNames(), contains('trajectory.shutdown'));
        // The queued remainder is COUNTED as lost — §2.5's crash-loss class,
        // attributed by the successor boot's shadow-diff.
        expect(h.status.dropped, greaterThanOrEqualTo(1));
        // The serial lane is wedged, so shutdown's boundary commit is
        // SKIPPED rather than spent behind the wedge (the boot tick pass's
        // own commit predates the wedge and is not this step's).
        expect(
          appender.calls.where((c) => c == 'commit').length,
          commitsBefore,
        );
        expect(h.tick!.isArmed, isFalse, reason: 'dispose still reached');
      },
    );
  });

  group('the runtime-event subscriber (§1.1 — fidelity B1)', () {
    late StreamController<RuntimeEvent> events;
    setUp(() => events = StreamController<RuntimeEvent>.broadcast());
    tearDown(() => events.close());

    const attempt = 'AAAAAAAAAAAAAAAAAAAAAAAAAA';
    const name = 'tranquility-s1/tg-1/agent';

    Future<TrajectoryHarness> live() async {
      final h = await harness(runtimeEvents: events.stream);
      await h.start();
      return h;
    }

    test('SessionStarted derives attempt.process.started: the event\'s '
        'breadcrumb-backed attempt id, the name parsed to session/step, the '
        'mount-seeded correlation facts', () async {
      final h = await live();
      h.recorder.attemptSpawning(
        attemptId: attempt,
        sessionId: 'tranquility-s1',
        stepPath: 'tg-1/agent',
        stepRound: 1,
        incarnation: 2,
      );
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      await pumpEventQueue();
      expect(appender.calls, contains('append:attempt.process.started'));
      final record = appender.records.single as AttemptProcessStarted;
      expect(record.attemptId, attempt);
      expect(record.sessionId, 'tranquility-s1');
      expect(record.stepPath, 'tg-1/agent');
      expect((record.pid, record.pgid), (41, 42));
      expect(record.incarnation, 2);
      expect(record.stepRound, 1);
    });

    test('Exited(inferred) derives attempt.process.exited with '
        'provenance=inferred — the §2.3 mapping', () async {
      final h = await live();
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      await pumpEventQueue();
      events.add(
        const RuntimeEvent.exited(name: name, exitCode: 0, inferred: true),
      );
      await pumpEventQueue();
      final record = appender.records.last as AttemptProcessExited;
      expect(record.attemptId, attempt, reason: 'joined by session name');
      expect(record.exitKind, ExitKind.exited);
      expect(record.exitCode, 0);
      expect(record.inferred, isTrue);
      expect(record.pid, 41);
      expect(appender.provenances.last, TrajectoryProvenance.inferred);
      expect(h.status.appended, 2);
    });

    test('Died derives exitKind=died, observed, with the reason', () async {
      await live();
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      await pumpEventQueue();
      events.add(const RuntimeEvent.died(name: name, reason: 'watchdog'));
      await pumpEventQueue();
      final record = appender.records.last as AttemptProcessExited;
      expect(record.exitKind, ExitKind.died);
      expect(record.reason, 'watchdog');
      expect(record.inferred, isFalse);
      expect(appender.provenances.last, TrajectoryProvenance.observed);
    });

    test('an EMPTY attempt id derives nothing — the record reads identity, it '
        'never invents one (§2.1); and an exit with no observed start derives '
        'nothing either', () async {
      await live();
      events.add(
        const RuntimeEvent.sessionStarted(name: name, pid: 41, pgid: 42),
      );
      events.add(const RuntimeEvent.exited(name: 'other/step', exitCode: 1));
      await pumpEventQueue();
      expect(appender.records, isEmpty);
    });

    test('a failing append never reaches the provider stream, and shutdown '
        'UNSUBSCRIBES the harness', () async {
      final h = await live();
      final seen = <RuntimeEvent>[];
      final other = events.stream.listen(seen.add);
      appender.appendOutcomes.add(
        AppendInternalError(cause: StateError('socket died')),
      );
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      events.add(const RuntimeEvent.exited(name: name, exitCode: 3));
      // This pump completing WITHOUT an unhandled async error is itself
      // the non-fatality proof (the test harness fails on any).
      await pumpEventQueue();
      expect(seen, hasLength(2), reason: 'the co-listener saw every event');
      expect(h.mode, TrajectoryHarnessMode.live);
      await h.shutdown();
      expect(
        events.hasListener,
        isTrue,
        reason: 'only the harness unsubscribed; the co-listener remains',
      );
      await other.cancel();
      expect(
        events.hasListener,
        isFalse,
        reason: 'the harness\'s subscription died at shutdown',
      );
    });

    test(
      'an exit whose pid does NOT match the start held under that name is '
      'refused, not mis-joined — dropped, counted, and flared once',
      () async {
        final h = await live();
        events.add(
          const RuntimeEvent.sessionStarted(
            name: name,
            pid: 41,
            pgid: 42,
            attemptId: attempt,
          ),
        );
        await pumpEventQueue();
        // The session NAME is a slot: a stop racing a respawn can put a second
        // process behind it. Attributing THIS exit to the attempt above would
        // write a false `attempt.process.exited` for a process still running.
        events.add(
          const RuntimeEvent.exited(name: name, exitCode: 0, pid: 999),
        );
        await pumpEventQueue();
        expect(
          appender.records.whereType<AttemptProcessExited>(),
          isEmpty,
          reason:
              'a refused join derives NOTHING — the tick\'s '
              'unknown-terminal settlement owns the row it leaves',
        );
        expect(h.status.exitJoinGaps, 1);
        final gaps = flares.where(
          (flare) => flare.$1 == 'trajectory.exitJoinGap',
        );
        expect(gaps, hasLength(1), reason: 'rate-limited: one per 30 s bucket');
        expect(gaps.single.$2['reason'], 'pid-mismatch');
        expect(
          (gaps.single.$2['expectedPid'], gaps.single.$2['observedPid']),
          ('41', '999'),
        );
        // The entry SURVIVES the refusal: the process it names may still be
        // alive, and dropping it would turn one refused join into two.
        events.add(const RuntimeEvent.exited(name: name, exitCode: 3, pid: 41));
        await pumpEventQueue();
        final record = appender.records.last as AttemptProcessExited;
        expect(
          (record.attemptId, record.pid, record.exitCode),
          (attempt, 41, 3),
        );
        expect(h.status.exitJoinGaps, 1, reason: 'the real exit is no gap');
      },
    );

    test('an exit carrying NO pid still joins — a missing discriminator is '
        '"cannot check", never evidence of a mismatch', () async {
      final h = await live();
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      await pumpEventQueue();
      events.add(const RuntimeEvent.died(name: name, reason: 'vanished'));
      await pumpEventQueue();
      final record = appender.records.last as AttemptProcessExited;
      expect((record.attemptId, record.pid), (attempt, 41));
      expect(h.status.exitJoinGaps, 0);
    });

    test('a SessionStarted overwriting a LIVE un-exited entry counts the '
        'orphaned start — the stop-races-spawn named gap', () async {
      final h = await live();
      const successor = 'BBBBBBBBBBBBBBBBBBBBBBBBBB';
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 41,
          pgid: 42,
          attemptId: attempt,
        ),
      );
      await pumpEventQueue();
      // No exit for pid 41 ever arrived; the name is refilled.
      events.add(
        const RuntimeEvent.sessionStarted(
          name: name,
          pid: 77,
          pgid: 78,
          attemptId: successor,
        ),
      );
      await pumpEventQueue();
      expect(h.status.exitJoinGaps, 1);
      expect(
        flares.where((flare) => flare.$1 == 'trajectory.exitJoinGap').single.$2,
        containsPair('reason', 'overwrite'),
      );
      // Both starts still derived; only the JOIN was lost.
      expect(
        appender.records.whereType<AttemptProcessStarted>().map(
          (r) => r.attemptId,
        ),
        [attempt, successor],
      );
      // The name now belongs to the successor, and its exit joins there.
      events.add(const RuntimeEvent.exited(name: name, exitCode: 0, pid: 77));
      await pumpEventQueue();
      expect(
        (appender.records.last as AttemptProcessExited).attemptId,
        successor,
      );
    });

    test('a disabled harness never subscribes at all', () async {
      final h = await harness(
        config: const TrajectoryConfig(mode: TrajectoryConfigMode.disabled),
        runtimeEvents: events.stream,
      );
      await h.start();
      expect(events.hasListener, isFalse);
      await h.shutdown();
    });
  });

  group('the gc cadence (M2)', () {
    test('fires CALL DOLT_GC() on the interval and re-arms', () async {
      final h = await harness();
      await h.start();
      final (_, fire, _) = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      fire();
      await pumpEventQueue();
      expect(connected.single.statements, contains('CALL DOLT_GC()'));
      expect(
        timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
        hasLength(2),
        reason: 're-armed',
      );
      expect(h.mode, TrajectoryHarnessMode.live);
    });

    test('a gc failure flares and stays non-fatal', () async {
      dbScript = (sql) =>
          sql == 'CALL DOLT_GC()' ? StateError('gc refused') : null;
      final h = await harness();
      await h.start();
      final (_, fire, _) = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      fire();
      await pumpEventQueue();
      expect(flareNames(), contains('trajectory.gcFailed'));
      expect(h.mode, TrajectoryHarnessMode.live, reason: 'non-fatal');
      expect(
        timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
        hasLength(2),
        reason: 'still re-armed',
      );
    });

    // tg-3o6b: M2 made online gc the service's job, but the ratified
    // provision boundary grants the service `trajectory.*` ONLY and DOLT_GC
    // needs server-level privilege. THE BOUNDARY WINS — the denial is a
    // POSTURE, so the cadence disables itself instead of denying once a
    // cycle forever, and reclamation moves to the operator's `traj gc`.
    //
    // r13: the latch keys on the ACCESS-DENIED CODES **and** on dolt's own
    // 1105 denied-CALL shape — which is the only shape a scoped grant is ever
    // refused with, and the one cut-wiring C0 names normatively. What it does
    // NOT key on is the bare word "denied" in an arbitrary 1105 (the r12
    // major, kept in its narrow form) — see the test below.
    test('a PRIVILEGE-denied gc disables the cadence after ONE flare and '
        'never re-arms', () async {
      dbScript = (sql) => sql == 'CALL DOLT_GC()'
          ? MySQLServerException(
              "command denied to user 'trajectory'@'%'",
              1105,
            )
          : null;
      final h = await harness();
      await h.start();
      final (_, fire, _) = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      fire();
      await pumpEventQueue();

      expect(flareNames(), contains('trajectory.gcDisabled'));
      expect(flareNames(), isNot(contains('trajectory.gcFailed')));
      expect(
        flares.firstWhere((f) => f.$1 == 'trajectory.gcDisabled').$2['remedy'],
        contains('traj gc'),
      );
      expect(
        timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
        hasLength(1),
        reason: 'the disable latch means the timer is NOT re-armed',
      );
      expect(h.mode, TrajectoryHarnessMode.live, reason: 'growth-only');
    });

    test('the latch survives the loop: a second gc pass neither runs nor '
        're-flares', () async {
      dbScript = (sql) => sql == 'CALL DOLT_GC()'
          ? MySQLServerException(
              "Access denied for user 'trajectory'@'%'",
              1045,
            )
          : null;
      final h = await harness();
      await h.start();
      final (_, fire, _) = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      fire();
      await pumpEventQueue();
      Iterable<String> gcCalls() =>
          connected.single.statements.where((s) => s == 'CALL DOLT_GC()');
      expect(gcCalls(), hasLength(1));

      // The only timer this process will ever hold for gc is the spent one;
      // firing it again is the worst case (a stray callback). "Disabled"
      // means the collection does not run, whatever fired it.
      fire();
      await pumpEventQueue();
      expect(gcCalls(), hasLength(1), reason: 'the latch stops the work too');
      expect(
        flareNames().where((n) => n == 'trajectory.gcDisabled'),
        hasLength(1),
        reason: 'ONE flare, ever — the latch is what makes it once',
      );
      expect(
        timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
        hasLength(1),
      );
    });

    test(
      'a 1105 that merely CONTAINS the word "denied" does NOT latch (the '
      'r12 major, in its narrow form) — it keeps flaring and re-arming',
      () async {
        // dolt answers a denied CALL on its unknown-error code, the SAME code it
        // answers a commit-time unique violation on. Matching the bare word
        // "denied" anywhere in a 1105 permanently disabled reclamation on any
        // 1105 that happened to contain it; the cure is the server's own
        // phrasing (`command denied to user`), which this message is not.
        dbScript = (sql) => sql == 'CALL DOLT_GC()'
            ? MySQLServerException(
                'runtime error: access to table trajectory was denied by a '
                'policy',
                1105,
              )
            : null;
        final h = await harness();
        await h.start();
        final (_, fire, _) = timers.firstWhere(
          (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
        );
        fire();
        await pumpEventQueue();

        expect(flareNames(), contains('trajectory.gcFailed'));
        expect(flareNames(), isNot(contains('trajectory.gcDisabled')));
        expect(
          timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
          hasLength(2),
          reason: 'still re-armed',
        );
        expect(h.mode, TrajectoryHarnessMode.live);
      },
    );

    test('a non-privilege gc error is untouched by the latch — it keeps '
        'flaring and re-arming', () async {
      dbScript = (sql) => sql == 'CALL DOLT_GC()'
          ? MySQLServerException('unique key violation on uq_idem', 1105)
          : null;
      final h = await harness();
      await h.start();
      final (_, fire, _) = timers.firstWhere(
        (entry) => entry.$1 == kDefaultTrajectoryGcInterval,
      );
      fire();
      await pumpEventQueue();
      expect(flareNames(), contains('trajectory.gcFailed'));
      expect(flareNames(), isNot(contains('trajectory.gcDisabled')));
      expect(
        timers.where((entry) => entry.$1 == kDefaultTrajectoryGcInterval),
        hasLength(2),
        reason: 're-armed: a 1105 that is not a denial is transient',
      );
    });
  });

  group('recorder wiring (W3 — §2 handoff to the queue)', () {
    test(
      'a recorder derivation rides the single writer into the appender',
      () async {
        final h = await harness();
        await h.start();
        h.recorder.sessionMinted(
          sessionId: 'tranquility-s1',
          workBeadId: 'tg-9xk2#r1',
          rig: 'the_grid',
          model: 'claude-fable-5',
        );
        await pumpEventQueue();
        expect(appender.calls, contains('append:attempt.session.started'));
        expect(h.status.appended, 1);
        expect(h.recorder.stats.derived, 1);
      },
    );

    test(
      'records derived BEFORE the claim drain after it (down accepts)',
      () async {
        final h = await harness();
        h.recorder.processExited(
          attemptId: 'A' * 26,
          pid: 41,
          exitKind: ExitKind.exited,
          inferred: false,
        );
        expect(h.status.queueDepth, 1);
        await h.start();
        await pumpEventQueue();
        expect(appender.calls, contains('append:attempt.process.exited'));
      },
    );

    test('disabled harness: the recorder is a counting no-op — no call site '
        'ever branches on "is the trajectory up"', () async {
      final h = await harness(
        config: const TrajectoryConfig(mode: TrajectoryConfigMode.disabled),
      );
      await h.start();
      h.recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      expect(appender.calls, isEmpty);
      expect(h.recorder.stats.skipped, 1);
      expect(h.recorder.stats.derived, 0);
    });

    test(
      'a latch stops derivation at the recorder too (§3 counting no-op)',
      () async {
        final h = await harness();
        await h.start();
        appender.appendOutcomes.add(
          const AppendCorruptionHalt(reason: 'belt order violation'),
        );
        h.recorder.sessionMinted(
          sessionId: 's1',
          workBeadId: 'tg-1',
          rig: 'r',
          model: 'm',
        );
        await pumpEventQueue();
        expect(h.mode, TrajectoryHarnessMode.halted);
        h.recorder.roundRetired(
          sessionId: 's1',
          cause: RoundRetireCause.rework,
        );
        expect(h.recorder.stats.skipped, 1, reason: 'no record even built');
        expect(h.status.queueDepth, 0);
      },
    );
  });

  group('Stage-1 obligations (W7 — §2.4)', () {
    test('the DEFAULT tick set is the shadow-posture one, composed after the '
        'claim so the detector has an epoch to key on', () async {
      final h = await harness();
      await h.start();

      expect(h.tick!.queries.map((query) => query.name), [
        kUnknownTerminalSettlementObligation,
        kWorktreeReapedBackfillObligation,
        kLivenessDetectorObligation,
      ]);
      // SIX boot reads come first: the STALE-FOLD SHAPE PROBE (r12 — the
      // refusal that keeps a pre-cut home from dropping every terminal
      // append), then the fold boot seed's five (cut-wiring C1 + C4 / §0.2):
      // the lag rule, the generation set, the P1 row scan, the P2 row scan,
      // the era boundary — all before the mode goes live, so no post-ACK
      // delta can outrun them.
      final statements = connected.single.statements;
      expect(statements.take(6), everyElement(startsWith('SELECT')));
      expect(statements.first, contains('information_schema.columns'));
      // Then the boot pass ran the obligations: three SELECTs on the same
      // serial lane, plus the detector's pulse prune.
      final passStatements = statements.skip(6);
      expect(
        passStatements.where((sql) => sql.startsWith('SELECT')),
        hasLength(3),
      );
      expect(h.tick!.lastPass!.disposition, TickPassDisposition.ran);
      expect(h.tick!.lastPass!.queriesRun, 3);
      expect(h.tick!.lastPass!.refusals, isEmpty);
    });

    test('an EXPLICIT query list still wins — Stage 0\'s empty set is a '
        'station\'s prerogative', () async {
      final h = await TrajectoryHarness.build(
        config: const TrajectoryConfig(
          mode: TrajectoryConfigMode.required,
          dualRead: DualReadMode.observe,
        ),
        gridHome: tmp.path,
        station: 'tranquility',
        onFlare: (name, data) => flares.add((name, data)),
        connect: () async {
          final db = _FakeDb(onExecute: dbScript);
          connected.add(db);
          return db;
        },
        appenderFactory: (_) => appender,
        tickQueries: kStage0ObligationQueries,
        scheduleTimer: (duration, callback) {
          final timer = _FakeTimer();
          timers.add((duration, callback, timer));
          return timer;
        },
        clock: () => now,
      );
      await h.start();

      expect(h.tick!.queries, isEmpty);
      // Only the stale-fold shape probe plus the fold boot seed's own five
      // reads (P1 + P2): an empty obligation set still issues nothing of its
      // own.
      expect(connected.single.statements, hasLength(6));
      expect(connected.single.statements, everyElement(startsWith('SELECT')));
    });

    test('a refusing obligation files the stuck note after schema §5\'s N '
        'consecutive passes, and the note rides the QUEUE', () async {
      // Every SELECT the obligation set issues fails: the store is unreachable
      // for reads while the appender is fine — the shape the accounting is for.
      // The stale-fold SHAPE PROBE is exempted: a home that cannot answer it
      // is the r12 REFUSAL case (no live arm at all), which is a different
      // test — this one needs a harness that armed.
      dbScript = (sql) => sql.startsWith('SELECT') && !_isShapeProbe(sql)
          ? StateError('store unavailable')
          : null;
      final h = await harness();
      await h.start(); // pass 1 (the boot pass)
      for (var i = 0; i < kStuckObligationThreshold - 1; i++) {
        await h.tick!.runPass();
      }
      await pumpEventQueue();

      expect(h.stuckObligations, isEmpty, reason: 'streaks reset on filing');
      expect(
        appender.calls.where((call) => call == 'append:attempt.note'),
        // One note per refusing obligation that reached N.
        hasLength(3),
      );
      expect(flareNames(), contains('trajectory.obligationStuck'));
    });

    test('a fenced-out pass is no evidence: the streak holds rather than '
        'resetting or firing', () async {
      dbScript = (sql) => sql.startsWith('SELECT') && !_isShapeProbe(sql)
          ? StateError('store unavailable')
          : null;
      final h = await harness();
      await h.start();
      appender.fakeInert = true;
      for (var i = 0; i < 10; i++) {
        await h.tick!.runPass();
      }
      await pumpEventQueue();

      expect(h.stuckObligations.values, everyElement(1));
      expect(appender.calls, isNot(contains('append:attempt.note')));
    });
  });

  // ── the P1 mirror (cut-wiring C1 / §0.2) ──────────────────────────────────
  group('the P1 mirror', () {
    /// Scripts the four boot-seed reads. [rows] is the projection scan.
    Object? Function(String sql) seedScript({
      List<Map<String, String?>> rows = const [],
      int appliedSeq = 40,
      int maxSeq = 40,
      String? oldestUnappliedAt,
      List<Map<String, String?>> generations = const [
        {
          'projection': 'fold',
          'fold_version': '2',
          'applied_seq': '40',
          'skipped': null,
          'rebuilt_at': null,
        },
      ],
    }) => (sql) {
      if (sql.contains('AS max_seq')) {
        return SqlResult(
          rows: [
            {'max_seq': '$maxSeq', 'applied_seq': '$appliedSeq'},
          ],
        );
      }
      if (sql.contains('MIN(recorded_at)')) {
        return SqlResult(
          rows: [
            {'oldest': oldestUnappliedAt},
          ],
        );
      }
      if (sql.contains('FROM proj_meta')) return SqlResult(rows: generations);
      if (sql.contains('FROM proj_session_head')) return SqlResult(rows: rows);
      if (sql.contains('MIN(advanced_at)')) {
        return const SqlResult(
          rows: [
            {'first_at': '2026-08-01 09:00:00.000000'},
          ],
        );
      }
      return null;
    };

    Map<String, String?> headRow({
      required String sessionId,
      String workBeadId = 'tg-9abc',
      String round = '0',
      String status = 'open',
      String? outcome,
      String lastSeq = '4',
    }) => {
      'session_id': sessionId,
      'work_bead_id': workBeadId,
      'round': round,
      'status': status,
      'outcome': outcome,
      'terminal_provenance': null,
      'unknown_reason': null,
      'held': '0',
      'started_at': '2026-08-31 10:00:00.000000',
      'head_epoch': '1',
      'last_seq': lastSeq,
    };

    test('the boot seed publishes a LIVE snapshot with the fold\'s rows and '
        'the era boundary — one scan, before the mode goes live', () async {
      dbScript = seedScript(
        rows: [
          headRow(sessionId: 'tranquility-1'),
          headRow(sessionId: 'tranquility-2', round: '1'),
        ],
      );
      final h = await harness();
      await h.start();

      final snapshot = h.sessionHeads;
      expect(snapshot.health, TrajectorySnapshotHealth.live);
      expect(snapshot.seededAt, now);
      expect(snapshot.firstEpochClaimedAt, DateTime.utc(2026, 8, 1, 9));
      expect(snapshot.rows, hasLength(2));
      // The retired head is legible: an OPEN row at round 1.
      expect(snapshot.bySessionId('tranquility-2')!.round, 1);
      expect(
        (snapshot.byWorkBead('tg-9abc') as SessionHeadWon).row.sessionId,
        'tranquility-1',
      );
      expect(flareNames(), isNot(contains('trajectory.staleFold')));
    });

    test('a fold behind by more than the RECORD bound refuses the snapshot '
        'for the boot — loud, and the boot still succeeds', () async {
      dbScript = seedScript(appliedSeq: 10, maxSeq: 10 + staleLagLimit + 1);
      final h = await harness();
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.live, reason: 'never boot-blocking');
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.refused);
      expect(flareNames(), contains('trajectory.staleFold'));
    });

    test('a fold behind by more than the AGE bound refuses too — the other '
        'edge of the same rule', () async {
      dbScript = seedScript(
        appliedSeq: 10,
        maxSeq: 11,
        // 61s older than the harness clock.
        oldestUnappliedAt: '2026-08-31 11:58:59.000000',
      );
      final h = await harness();
      await h.start();

      expect(h.sessionHeads.health, TrajectorySnapshotHealth.refused);
      expect(flareNames(), contains('trajectory.staleFold'));
    });

    test('a fold INSIDE both bounds stays live', () async {
      dbScript = seedScript(
        appliedSeq: 10,
        maxSeq: 10 + staleLagLimit,
        oldestUnappliedAt: '2026-08-31 11:59:30.000000',
      );
      final h = await harness();
      await h.start();

      expect(h.sessionHeads.health, TrajectorySnapshotHealth.live);
      expect(flareNames(), isNot(contains('trajectory.staleFold')));
    });

    test('a landed append maintains the mirror POST-ACK, at the ordinal the '
        'append committed', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();

      h.recorder.sessionMinted(
        sessionId: 'tranquility-9',
        workBeadId: 'tg-9abc',
        rig: 'operator',
        model: 'molecule',
      );
      await pumpEventQueue();

      final row = h.sessionHeads.bySessionId('tranquility-9');
      expect(row, isNotNull);
      expect(row!.workBeadId, 'tg-9abc');
      expect(row.isOpen, isTrue);
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.live);
    });

    test('a DROPPED append never reaches the mirror, and latches the snapshot '
        'compromised — a frozen fold must never read live (B-B7)', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      appender.appendOutcomes.add(
        const AppendInternalError(cause: 'socket died'),
      );

      h.recorder.sessionMinted(
        sessionId: 'tranquility-9',
        workBeadId: 'tg-9abc',
        rig: 'operator',
        model: 'molecule',
      );
      await pumpEventQueue();

      expect(h.sessionHeads.bySessionId('tranquility-9'), isNull);
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.compromised);
      expect(flareNames(), contains('trajectory.dualReadCompromised'));
    });

    test('SUPPRESSION latches too — a fenced-out harness freezes the mirror '
        'while nothing is dropped (r4 — J6-B3)', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.live);

      appender.appendOutcomes.add(
        const AppendFencedOut(reason: 'cas-zero-rows'),
      );
      h.enqueue(_note(1));
      await pumpEventQueue();

      expect(h.status.dropped, 0, reason: 'a fence-out drops nothing');
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.compromised);
      expect(flareNames(), contains('trajectory.dualReadCompromised'));
    });

    test('a moved (projection, fold_version, rebuilt_at) triple RESEEDS the '
        'mirror — the detector for an out-of-contract replay', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      expect(h.sessionHeads.rows, isEmpty);

      // A replay ran under us: `rebuilt_at` moved and the rows changed.
      dbScript = seedScript(
        rows: [headRow(sessionId: 'tranquility-7')],
        generations: const [
          {
            'projection': 'fold',
            'fold_version': '2',
            'applied_seq': '40',
            'skipped': null,
            'rebuilt_at': '2026-08-31 12:00:00.000000',
          },
        ],
      );
      connected.single.onExecute = dbScript;
      // The guard rides the tick, no more often than the tick interval.
      now = now.add(const Duration(minutes: 1));
      await h.tick!.runPass();
      await pumpEventQueue();

      expect(h.sessionHeads.bySessionId('tranquility-7'), isNotNull);
      expect(flareNames(), contains('trajectory.mirrorReseeded'));
      expect(
        h.sessionHeads.health,
        TrajectorySnapshotHealth.live,
        reason: 'a reseed is a re-read, not a failure',
      );
    });

    test(
      'an UNCHANGED generation set reseeds nothing and flares nothing',
      () async {
        dbScript = seedScript(rows: [headRow(sessionId: 'tranquility-1')]);
        final h = await harness();
        await h.start();
        final seeded = h.sessionHeads.version;

        now = now.add(const Duration(minutes: 1));
        await h.tick!.runPass();
        await pumpEventQueue();

        expect(h.sessionHeads.version, seeded);
        expect(flareNames(), isNot(contains('trajectory.mirrorReseeded')));
      },
    );

    test('REFUSED TESTIMONY is counted on its own axis — not a drop, not a '
        'dedupe, and no health consequence', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      appender.appendOutcomes.add(
        const AppendRefusedTestimony(
          attemptId: '01J8ATTEMPT000000000000002',
          existingRecordId: '01OBSERVEDTERMINAL00000001',
          reason: 'the real terminal already landed',
        ),
      );

      h.enqueue(_note(1));
      await pumpEventQueue();

      expect(h.status.refusedTestimony, 1);
      expect(h.status.dropped, 0);
      expect(h.status.deduped, 0);
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.live);
    });

    test('a harness that never connected serves a REFUSED snapshot rather '
        'than an empty one that reads clean', () async {
      connectError = StateError('listener unreachable');
      final h = await harness();
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.degraded);
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.refused);
      expect(h.sessionHeads.rows, isEmpty);
    });
  });

  // ── the P2 mirror (cut-wiring C4 / §0.2) ──────────────────────────────────
  //
  // The step axis rides the P1 mirror's machinery exactly: one boot read on
  // the same serialized lane under the SAME lag verdict, the same post-ACK
  // apply off the same acked envelope, the same generation guard, the same
  // health latch. What is P2's OWN is EVICTION, driven off P1's terminality.
  group('the P2 mirror', () {
    Object? Function(String sql) seedScript({
      List<Map<String, String?>> heads = const [],
      List<Map<String, String?>> steps = const [],
      int appliedSeq = 40,
      int maxSeq = 40,
      List<Map<String, String?>> generations = const [
        {
          'projection': 'fold',
          'fold_version': '2',
          'applied_seq': '40',
          'skipped': null,
          'rebuilt_at': null,
        },
      ],
    }) => (sql) {
      if (sql.contains('AS max_seq')) {
        return SqlResult(
          rows: [
            {'max_seq': '$maxSeq', 'applied_seq': '$appliedSeq'},
          ],
        );
      }
      if (sql.contains('MIN(recorded_at)')) {
        return const SqlResult(
          rows: [
            {'oldest': null},
          ],
        );
      }
      if (sql.contains('FROM proj_meta')) return SqlResult(rows: generations);
      if (sql.contains('FROM proj_session_head')) return SqlResult(rows: heads);
      if (sql.contains('FROM proj_step_cursor')) return SqlResult(rows: steps);
      if (sql.contains('MIN(advanced_at)')) {
        return const SqlResult(
          rows: [
            {'first_at': '2026-08-01 09:00:00.000000'},
          ],
        );
      }
      return null;
    };

    Map<String, String?> headRow({
      required String sessionId,
      String status = 'open',
    }) => {
      'session_id': sessionId,
      'work_bead_id': 'tg-9abc',
      'round': '0',
      'status': status,
      'outcome': status == 'closed' ? 'succeeded' : null,
      'terminal_provenance': null,
      'unknown_reason': null,
      'held': '0',
      'started_at': '2026-08-31 10:00:00.000000',
      'head_epoch': '1',
      'last_seq': '4',
    };

    Map<String, String?> stepRow({
      required String sessionId,
      String stepPath = 'build',
      String state = 'running',
    }) => {
      'session_id': sessionId,
      'round': '0',
      'step_path': stepPath,
      'step_round': '0',
      'state': state,
      'incarnation': '0',
      'last_seq': '4',
    };

    test(
      'the boot seed reads P2 on the SAME lane, under the same verdict',
      () async {
        dbScript = seedScript(
          heads: [headRow(sessionId: 'tranquility-1')],
          steps: [
            stepRow(sessionId: 'tranquility-1'),
            stepRow(sessionId: 'tranquility-1', stepPath: 'review'),
            stepRow(sessionId: 'tranquility-2'),
          ],
        );
        final h = await harness();
        await h.start();

        expect(h.stepCursors.health, TrajectorySnapshotHealth.live);
        expect(h.stepCursors.seededAt, now);
        expect(h.stepCursors.firstEpochClaimedAt, DateTime.utc(2026, 8, 1, 9));
        expect(h.stepCursors.byP2SessionId('tranquility-1'), hasLength(2));
        expect(h.stepCursors.byP2SessionId('tranquility-2'), hasLength(1));
        // The two mirrors seed from ONE read pass, so a step row can never
        // describe a session the head seed missed.
        expect(h.sessionHeads.seededAt, h.stepCursors.seededAt);
      },
    );

    test('a STALE fold refuses BOTH mirrors — one verdict, one boot', () async {
      dbScript = seedScript(
        appliedSeq: 10,
        maxSeq: 10 + staleLagLimit + 1,
        steps: [stepRow(sessionId: 'tranquility-1')],
      );
      final h = await harness();
      await h.start();

      expect(h.mode, TrajectoryHarnessMode.live, reason: 'never boot-blocking');
      expect(h.sessionHeads.health, TrajectorySnapshotHealth.refused);
      expect(h.stepCursors.health, TrajectorySnapshotHealth.refused);
      expect(flareNames(), contains('trajectory.staleFold'));
    });

    test('a landed step transition maintains P2 POST-ACK', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();

      h.recorder.stepRunning(
        sessionId: 'tranquility-9',
        stepPath: 'build',
        stepRound: 0,
        incarnation: 0,
      );
      await pumpEventQueue();

      final rows = h.stepCursors.byP2SessionId('tranquility-9');
      expect(rows, hasLength(1));
      expect(rows.single.stepState, 'running');
    });

    test(
      'a DROPPED append latches BOTH mirrors compromised, and flares ONCE',
      () async {
        dbScript = seedScript();
        final h = await harness();
        await h.start();
        appender.appendOutcomes.add(
          const AppendInternalError(cause: 'socket died'),
        );

        h.recorder.stepRunning(
          sessionId: 'tranquility-9',
          stepPath: 'build',
          stepRound: 0,
          incarnation: 0,
        );
        await pumpEventQueue();

        expect(h.stepCursors.byP2SessionId('tranquility-9'), isEmpty);
        expect(h.stepCursors.health, TrajectorySnapshotHealth.compromised);
        expect(h.sessionHeads.health, TrajectorySnapshotHealth.compromised);
        expect(
          flareNames().where((n) => n == 'trajectory.dualReadCompromised'),
          hasLength(1),
          reason: 'one station, one health, one flare',
        );
      },
    );

    test('a moved generation triple RESEEDS P2 alongside P1', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      expect(h.stepCursors.byP2SessionId('tranquility-7'), isEmpty);

      dbScript = seedScript(
        heads: [headRow(sessionId: 'tranquility-7')],
        steps: [stepRow(sessionId: 'tranquility-7')],
        generations: const [
          {
            'projection': 'step_cursor',
            'fold_version': '1',
            'applied_seq': '40',
            'skipped': null,
            'rebuilt_at': '2026-08-31 12:00:00.000000',
          },
        ],
      );
      connected.single.onExecute = dbScript;
      now = now.add(const Duration(minutes: 1));
      await h.tick!.runPass();
      await pumpEventQueue();

      // A per-PROJECTION replay is expressible, so a mirror left on the old
      // generation while its sibling adopted the new one would be two folds in
      // one process — both re-seed on ANY moved triple.
      expect(h.stepCursors.byP2SessionId('tranquility-7'), hasLength(1));
      expect(h.sessionHeads.bySessionId('tranquility-7'), isNotNull);
      expect(flareNames(), contains('trajectory.mirrorReseeded'));
    });

    test('EVICTION: a session that CLOSES in P1 loses its ladder on the next '
        'tick', () async {
      dbScript = seedScript(
        heads: [
          headRow(sessionId: 'tranquility-1'),
          headRow(sessionId: 'tranquility-2'),
        ],
        steps: [
          stepRow(sessionId: 'tranquility-1'),
          stepRow(sessionId: 'tranquility-2'),
        ],
      );
      final h = await harness();
      await h.start();
      expect(h.stepCursors.byP2SessionId('tranquility-1'), hasLength(1));

      // The terminal lands post-ACK on P1; P2 has no status column of its own,
      // so P1's terminality is the ONLY direction the rule can be driven from.
      h.recorder.sessionCompleted(
        sessionId: 'tranquility-1',
        workBeadId: 'tg-9abc',
      );
      await pumpEventQueue();
      now = now.add(const Duration(minutes: 1));
      await h.tick!.runPass();
      await pumpEventQueue();

      expect(
        h.stepCursors.byP2SessionId('tranquility-1'),
        isEmpty,
        reason: 'the SQL fold keeps the ladder; the mirror need not',
      );
      expect(h.stepCursors.byP2SessionId('tranquility-2'), hasLength(1));
    });

    test(
      'a harness that never connected serves a REFUSED P2 snapshot',
      () async {
        connectError = StateError('listener unreachable');
        final h = await harness();
        await h.start();

        expect(h.stepCursors.health, TrajectorySnapshotHealth.refused);
        expect(h.stepCursors.byP2SessionId('tranquility-1'), isEmpty);
      },
    );

    test('the change seam publishes and the remover works', () async {
      dbScript = seedScript();
      final h = await harness();
      await h.start();
      final versions = <int>[];
      final remove = h.onStepCursorsChanged((s) => versions.add(s.version));

      h.recorder.stepRunning(
        sessionId: 'tranquility-9',
        stepPath: 'build',
        stepRound: 0,
        incarnation: 0,
      );
      await pumpEventQueue();
      expect(versions, isNotEmpty);

      remove();
      final seen = versions.length;
      h.recorder.stepRunning(
        sessionId: 'tranquility-9',
        stepPath: 'review',
        stepRound: 0,
        incarnation: 0,
      );
      await pumpEventQueue();
      expect(versions, hasLength(seen));
    });
  });

  group("the dual read's harness surfaces (cut-wiring C2)", () {
    TerminalReconcileRequest request(
      List<TerminalReconcileOutcome> reported, {
      String attemptId = '01J8ATTEMPT000000000000009',
    }) => TerminalReconcileRequest(
      sessionId: 'tranquility-1',
      attemptId: attemptId,
      workBeadId: 'tg-9abc',
      report: reported.add,
    );

    test('hasQueuedAppendFor sees BOTH the queued and the IN-FLIGHT request — '
        'the writer dequeues before it awaits, so a queue-only read has a '
        'real hole (r8 — V2-B1s trigger depends on this)', () async {
      final h = await harness();
      await h.start();
      appender.appendNeverCompletes = true;

      h
        ..enqueue(
          TrajectoryAppendRequest(
            AttemptTerminal(
              attemptId: 'A' * 26,
              sessionId: 's-1',
              outcome: TerminalOutcome.succeeded,
            ),
          ),
        )
        ..enqueue(
          TrajectoryAppendRequest(
            AttemptTerminal(
              attemptId: 'B' * 26,
              sessionId: 's-2',
              outcome: TerminalOutcome.succeeded,
            ),
          ),
        );
      await pumpEventQueue();

      expect(h.hasQueuedAppendFor('A' * 26), isTrue, reason: 'in flight');
      expect(h.hasQueuedAppendFor('B' * 26), isTrue, reason: 'queued');
      expect(h.hasQueuedAppendFor('C' * 26), isFalse);
    });

    test('THE GUARD PRE-CHECK (r9 — V3-B1): an existing terminal row for the '
        'attempt means the real record LANDED, so the heal SKIPS and counts — '
        'no append at all', () async {
      dbScript = (sql) {
        if (sql.contains('traj_terminal_guard')) {
          return const SqlResult(
            rows: [
              {'attempt_id': '01J8ATTEMPT000000000000009'},
            ],
          );
        }
        return null;
      };
      final h = await harness();
      await h.start();
      final reported = <TerminalReconcileOutcome>[];

      h.requestTerminalReconcile(request(reported));
      await pumpEventQueue();

      expect(reported, [TerminalReconcileOutcome.skippedGuard]);
      expect([
        for (final r in appender.records) r.recordType,
      ], isNot(contains('attempt.terminal')));
    });

    test('with no guard row the heal appends the reconstructed close under '
        'its OWN basis and its OWN idem grammar', () async {
      final h = await harness();
      await h.start();
      final reported = <TerminalReconcileOutcome>[];

      h.requestTerminalReconcile(request(reported));
      await pumpEventQueue();

      expect(reported, [TerminalReconcileOutcome.appended]);
      final terminal = appender.records.whereType<AttemptTerminal>().single;
      expect(terminal.outcome, TerminalOutcome.unknown);
      expect(terminal.unknownReason, 'external-close');
      expect(terminal.attemptId, '01J8ATTEMPT000000000000009');
      expect(terminal.attemptIdBasis, isNull, reason: 'never minted');
      expect(appender.provenances.last, TrajectoryProvenance.reconstructed);
    });

    test('a heal whose guard read THROWS reports failed and flares — the '
        'escalation rule keys on exactly that', () async {
      dbScript = (sql) => sql.contains('traj_terminal_guard')
          ? StateError('guard read exploded')
          : null;
      final h = await harness();
      await h.start();
      final reported = <TerminalReconcileOutcome>[];

      h.requestTerminalReconcile(request(reported));
      await pumpEventQueue();

      expect(reported, [TerminalReconcileOutcome.failed]);
      expect(flareNames(), contains('trajectory.terminalReconcileFailed'));
    });

    test(
      'a DOWN or degraded harness reports a SKIP, never a failure: a '
      'harness that cannot append never manufactures an escalation',
      () async {
        final h = await harness(
          config: const TrajectoryConfig(mode: TrajectoryConfigMode.disabled),
        );
        await h.start();
        final reported = <TerminalReconcileOutcome>[];

        h.requestTerminalReconcile(request(reported));
        await pumpEventQueue();

        // THE TRANSIENT MEMBER (r13): no guard row was read, and the entry
        // must stay healable so a later pass re-asks once the harness is live.
        expect(reported, [TerminalReconcileOutcome.skippedUnavailable]);
        expect(flares, isEmpty);
      },
    );

    test('the config carries the posture and defaults to OFF (r13) — the '
        'soak posture is armed explicitly by the runner', () {
      expect(const TrajectoryConfig().dualRead, DualReadMode.off);
      expect(
        const TrajectoryConfig(
          dualRead: DualReadMode.primary,
        ).asDisabled.dualRead,
        DualReadMode.primary,
        reason: 'dry-run forces the WRITE posture, never the read one',
      );
    });
  });
}
