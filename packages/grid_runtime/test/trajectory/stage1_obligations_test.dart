// W7 (tg-zfek Stage 1) — the tick's shadow-posture obligation set
// (stage1-wiring §2.4).
//
// Every obligation is driven the way the tick drives it: read `sql` +
// `parameters`, hand `repair` the rows a server would have returned, and assert
// on the records it hands back and the statements it issued. The clock is fake
// (the detector's whole contract is "how stale is this beat"); the filesystem
// is real (the reaped backfill's external check is a directory that is either
// there or not — faking it would test nothing).
import 'dart:io';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final class _FakeDb implements TrajectoryDb {
  final List<({String sql, Map<String, dynamic>? params})> statements = [];
  SqlResult next = const SqlResult();

  @override
  Future<SqlResult> execute(String sql, [Map<String, dynamic>? params]) async {
    statements.add((sql: sql, params: params));
    return next;
  }

  @override
  Future<void> close() async {}
}

final class _FakeProcesses implements ProcessGroupController {
  _FakeProcesses(this.alive);

  final Set<int> alive;

  @override
  bool processAlive(int pid) => alive.contains(pid);

  @override
  int currentGroupId() => 1;

  @override
  Future<List<int>> groupMembers(int pgid) async => const <int>[];

  @override
  Future<int?> resolvePgid(int pid) async => pid;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}

final class _CountingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> enqueued = [];

  @override
  bool accepting = true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => enqueued.add(record);
}

class _FakeClock {
  DateTime now = DateTime.utc(2026, 8, 31, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

StationTrajectoryRecorder _recorder({Set<String> substations = const {'tg'}}) =>
    StationTrajectoryRecorder(
      sink: _CountingSink(),
      substationPrefixes: substations,
    );

/// A `traj_pulse` beat as the server renders it back: DATETIME(6), no zone,
/// UTC — the same text the appender writes.
String _serverInstant(DateTime value) => sqlDateTime6(value);

void main() {
  group('the set (§2.4)', () {
    test('arms exactly the four shadow-posture obligations, in order', () {
      final queries = buildStage1ObligationQueries(
        recorder: _recorder(),
        db: _FakeDb(),
        station: 'tranquility',
        bootEpoch: () => 7,
      );

      // The external-close heal sits between settlement and the reaped
      // backfill: it CLOSES heads the backfill's `h.status = 'closed'` scan
      // then sees on the same fixpoint run, and settlement never touches its
      // reconstructed output (the record-keyed exclusion).
      expect(queries.map((query) => query.name), [
        kUnknownTerminalSettlementObligation,
        kExternalCloseTerminalObligation,
        kWorktreeReapedBackfillObligation,
        kLivenessDetectorObligation,
      ]);
    });

    test('writes NOTHING that mounts: no bd, no filesystem mutation, no '
        'eligibility clause — every statement is a trajectory read, a '
        'traj_pulse UPSERT, or a traj_pulse prune', () async {
      final db = _FakeDb();
      final queries = buildStage1ObligationQueries(
        recorder: _recorder(),
        db: db,
        station: 'tranquility',
        bootEpoch: () => 7,
      );

      for (final query in queries) {
        expect(
          query.sql.toUpperCase(),
          startsWith('SELECT'),
          reason: '${query.name} must key off a READ',
        );
        await query.repair(const []);
      }

      // The only write any of them issued with no rows to work on: the pulse
      // prune, which is dolt_ignore'd working-set state.
      expect(db.statements, hasLength(1));
      expect(db.statements.single.sql, startsWith('DELETE FROM traj_pulse'));
    });
  });

  group('obligation 1 — unknown-terminal settlement', () {
    Map<String, String?> row({
      String attemptId = 'A1',
      String? pid,
      String? worktree,
      String? workBeadId = 'tg-abc',
    }) => {
      'record_id': 'R1',
      'attempt_id': attemptId,
      'session_id': 'tranquility-1',
      'work_bead_id': workBeadId,
      'unknown_reason': 'write_timeout',
      'pid': pid,
      'worktree': worktree,
    };

    UnknownTerminalSettlementObligation build({
      Set<int> alive = const {},
      StationTrajectoryRecorder? recorder,
    }) => UnknownTerminalSettlementObligation(
      recorder: recorder ?? _recorder(),
      station: 'tranquility',
      processes: _FakeProcesses({...alive}),
    );

    test('queries the unsettled unknowns of THIS station only', () {
      final query = build();

      expect(query.sql, contains("t.outcome = 'unknown'"));
      expect(query.sql, contains('g.settled_by IS NULL'));
      expect(query.sql, contains('t.station = :station'));
      expect(query.parameters, {'station': 'tranquility'});
    });

    test('THE SETTLEMENT EXCLUSION (cut-wiring C2, r9 — V3-B2): the scan '
        'excludes reconstructed testimony ON THE RECORD, never on the '
        'head flag', () {
      // Keying the exclusion on the IMMUTABLE record is what makes it
      // permanent. Truth monotonicity clears the head's `terminal_provenance`
      // mark when a real observed terminal lands, so a head-keyed exclusion
      // would re-expose the stale reconstructed record and clobber the
      // observed outcome back to `settled` ⇒ `done`.
      expect(build().sql, contains("t.provenance != 'reconstructed'"));
      expect(build().sql, isNot(contains('terminal_provenance')));
    });

    test('settles a dead attempt with a SETTLING terminal — resolves the '
        'unknown row, inferred, with the probe basis', () async {
      final appends = await build().repair([row(pid: '4242')]);

      expect(appends, hasLength(1));
      final append = appends.single;
      final record = append.record as AttemptTerminal;
      expect(record.outcome, TerminalOutcome.settled);
      expect(record.resolvesRecordId, 'R1');
      expect(record.isSettling, isTrue);
      expect(record.attemptId, 'A1');
      expect(record.workBeadId, 'tg-abc');
      expect(record.reason, contains('pid 4242 gone'));
      expect(record.reason, contains('write_timeout'));
      expect(append.provenance, TrajectoryProvenance.inferred);
      expect(append.provenanceBasis, kTickUnknownSettlementBasis);
      // ck_substation: the record carries a work_bead_id, so it carries a
      // substation — the recorder's allowSet match, not the appender's fallback.
      expect(append.substation, 'tg');
    });

    test('settles an attempt with no pid on record — nothing to probe means '
        'nothing is holding it open', () async {
      final appends = await build().repair([row()]);

      expect(appends, hasLength(1));
      expect(
        (appends.single.record as AttemptTerminal).reason,
        contains('no pid on record'),
      );
    });

    test('leaves a LIVE attempt unsettled — the obligation stays open and the '
        'next tick re-asks the process table', () async {
      final appends = await build(alive: {4242}).repair([row(pid: '4242')]);

      expect(appends, isEmpty);
    });

    test('reports whether the worktree is still present in the settlement '
        'reason', () async {
      final root = Directory.systemTemp.createTempSync('w7-settle');
      addTearDown(() => root.deleteSync(recursive: true));

      final present = await build().repair([row(worktree: root.path)]);
      final absent = await build().repair([
        row(worktree: p.join(root.path, 'gone')),
      ]);

      expect(
        (present.single.record as AttemptTerminal).reason,
        contains('worktree present'),
      );
      expect(
        (absent.single.record as AttemptTerminal).reason,
        contains('worktree absent'),
      );
    });

    test(
      'skips a row missing the identity the settlement is keyed on',
      () async {
        final appends = await build().repair([
          {'record_id': null, 'attempt_id': 'A1', 'session_id': 's'},
          {'record_id': 'R1', 'attempt_id': null, 'session_id': 's'},
        ]);

        expect(appends, isEmpty);
      },
    );
  });

  group('the external-close terminal (tg-ffl6, ruling Q6)', () {
    Map<String, String?> row({
      String sessionId = 'tranquility-1',
      String? attemptId = 'A1',
      String? workBeadId = 'tg-abc',
    }) => {
      'session_id': sessionId,
      'work_bead_id': workBeadId,
      'attempt_id': attemptId,
      'last_seq': '40',
    };

    final clock = _FakeClock();

    ExternalCloseTerminalObligation build({
      SessionClosureProbe? closure,
      AppendQueuedProbe? queued,
      StationTrajectoryRecorder? recorder,
    }) => ExternalCloseTerminalObligation(
      recorder: recorder ?? _recorder(),
      station: 'tranquility',
      clock: clock.call,
      sessionClosure: closure,
      appendQueued: queued,
    );

    SessionClosure? closed(String _) => const SessionClosure();

    test('scans the OPEN heads of THIS station whose attempt never reached '
        'the terminal guard, oldest first — pre-spawn heads (no attempt id) '
        'are left out so they cannot hold the window', () {
      final query = build();

      expect(query.sql, contains("h.status = 'open'"));
      expect(query.sql, contains('h.attempt_id IS NOT NULL'));
      expect(query.sql, contains('LEFT JOIN traj_terminal_guard g'));
      expect(query.sql, contains('g.attempt_id IS NULL'));
      expect(query.sql, contains('h.rig = :station'));
      expect(query.sql, contains('ORDER BY h.last_seq'));
      expect(query.parameters, {'station': 'tranquility'});
    });

    test('an unwired ledger probe leaves the obligation INERT — it never '
        'heals on no evidence', () async {
      final appends = await build().repair([row()]);
      expect(appends, isEmpty);
    });

    test('a session the ledger still reads OPEN is a live round: nothing '
        'appends, and any earlier sighting is forgotten', () async {
      var closedNow = true;
      final query = build(
        closure: (_) => closedNow ? const SessionClosure() : null,
      );
      expect(await query.repair([row()]), isEmpty); // first sighting
      closedNow = false;
      clock.advance(const Duration(minutes: 5));
      expect(await query.repair([row()]), isEmpty);
      expect(query.lastOpenInLedger, 1);
      closedNow = true;
      // The grace restarts from this sighting — no heal yet.
      expect(await query.repair([row()]), isEmpty);
      expect(query.lastWithinGrace, 1);
    });

    test('holds the heal for the grace from its OWN first sighting, then '
        'appends ONE reconstructed external-close terminal with the heal\'s '
        'idem basis', () async {
      final query = build(closure: closed);
      expect(await query.repair([row()]), isEmpty);
      expect(query.lastWithinGrace, 1);
      clock.advance(kDefaultExternalCloseGrace - const Duration(seconds: 1));
      expect(await query.repair([row()]), isEmpty);
      clock.advance(const Duration(seconds: 1));

      final appends = await query.repair([row()]);

      expect(appends, hasLength(1));
      final append = appends.single;
      expect(append.provenance, TrajectoryProvenance.reconstructed);
      expect(append.provenanceBasis, kTerminalReconcileBasis);
      expect(append.substation, 'tg');
      final record = append.record as AttemptTerminal;
      expect(record.sessionId, 'tranquility-1');
      expect(record.attemptId, 'A1');
      expect(record.workBeadId, 'tg-abc');
      expect(record.outcome, TerminalOutcome.unknown);
      expect(record.unknownReason, kExternalCloseUnknownReason);
      expect(record.healBasis, kTerminalReconcileBasis);
      expect(record.attemptIdBasis, isNull, reason: 'never minted here');
      // The same idem key the comparator's heal takes: whichever fires second
      // dedupes rather than landing a second terminal.
      final comparatorForm = _recorder().buildTerminalReconciled(
        sessionId: 'tranquility-1',
        attemptId: 'A1',
      );
      expect(
        record.idemKeyText(
          const IdemContext(station: 'tranquility', bootEpoch: 7),
        ),
        comparatorForm.record.idemKeyText(
          const IdemContext(station: 'tranquility', bootEpoch: 7),
        ),
      );
    });

    test('a queued or in-flight append for the attempt defers the heal to '
        'the next pass — the real record is about to land', () async {
      var queued = true;
      final asked = <String>[];
      final query = build(
        closure: closed,
        queued: ({required sessionId, required attemptId}) {
          asked.add('$sessionId/$attemptId');
          return queued;
        },
      );
      expect(await query.repair([row()]), isEmpty);
      clock.advance(const Duration(minutes: 2));
      expect(await query.repair([row()]), isEmpty);
      expect(query.lastAppendQueued, 1);
      // Asked by SESSION and attempt: the head's attempt is the spawn's, the
      // observed terminal carries the recorder's per-session id.
      expect(asked.last, 'tranquility-1/A1');
      queued = false;
      expect(await query.repair([row()]), hasLength(1));
    });

    test('a RETIRED rework round is counted and left open — the fold keeps '
        'it open by schema design, and closing it is Q9\'s call', () async {
      final query = build(
        closure: (_) => const SessionClosure(
          outcome: TerminalOutcome.cancelled,
          reason: 'ledger close: reworked',
          retiredRound: true,
        ),
      );
      clock.advance(const Duration(hours: 1));
      expect(await query.repair([row()]), isEmpty);
      expect(await query.repair([row()]), isEmpty);
      expect(query.lastRetiredRound, 1);
      expect(query.lastWithinGrace, 0);
    });

    test('the ledger\'s closed_at rides the append as occurredAt, so the head '
        'closes at the ledger\'s instant, never the heal\'s', () async {
      final query = build(
        closure: (_) => SessionClosure(
          closedAt: DateTime.utc(2026, 9, 5, 20),
          outcome: TerminalOutcome.cancelled,
        ),
      );
      await query.repair([row()]);
      clock.advance(const Duration(minutes: 2));

      final append = (await query.repair([row()])).single;

      expect(append.occurredAt, DateTime.utc(2026, 9, 5, 20));
    });

    test(
      'the ledger\'s closed_at, when the chokepoint stamped one, is '
      'carried in the reason; a hand close without one still heals',
      () async {
        final stamped = build(
          closure: (_) =>
              SessionClosure(closedAt: DateTime.utc(2026, 9, 5, 20)),
        );
        final bare = build(closure: closed);
        await stamped.repair([row()]);
        await bare.repair([row(sessionId: 'tranquility-2')]);
        clock.advance(const Duration(minutes: 2));

        final withStamp =
            (await stamped.repair([row()])).single.record as AttemptTerminal;
        final withoutStamp =
            (await bare.repair([row(sessionId: 'tranquility-2')])).single.record
                as AttemptTerminal;

        expect(withStamp.reason, contains('2026-09-05T20:00:00.000Z'));
        expect(withoutStamp.reason, isNot(contains('at 2026')));
        expect(withoutStamp.outcome, TerminalOutcome.unknown);
      },
    );

    test('a ledger-derived outcome rides the record as-is — no '
        'unknown_reason, same heal basis, still reconstructed', () async {
      final query = build(
        closure: (_) => const SessionClosure(
          outcome: TerminalOutcome.cancelled,
          reason: 'ledger close: reworked',
        ),
      );
      await query.repair([row()]);
      clock.advance(const Duration(minutes: 2));

      final append = (await query.repair([row()])).single;
      final record = append.record as AttemptTerminal;

      expect(record.outcome, TerminalOutcome.cancelled);
      expect(record.unknownReason, isNull);
      expect(record.healBasis, kTerminalReconcileBasis);
      expect(record.reason, contains('(ledger close: reworked)'));
      expect(append.provenance, TrajectoryProvenance.reconstructed);
    });

    test('a row without an attempt id is skipped, never minted', () async {
      final query = build(closure: closed);
      clock.advance(const Duration(hours: 1));
      expect(await query.repair([row(attemptId: null)]), isEmpty);
    });
  });

  group('obligation 2 — worktree.reaped backfill', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('w7-reap'));
    tearDown(() => root.deleteSync(recursive: true));

    WorktreeReapedBackfillObligation build() =>
        WorktreeReapedBackfillObligation(recorder: _recorder());

    test('queries P6 live worktrees under a CLOSED P1 session', () {
      final query = build();

      expect(query.sql, contains("p.worktree_state = 'live'"));
      expect(query.sql, contains("h.status = 'closed'"));
    });

    test('appends the record when the path is GONE — the legacy reap already '
        'ran, only the record was lost', () async {
      final gone = p.join(root.path, 'tg-abc');

      final appends = await build().repair([
        {
          'session_id': 'tranquility-1',
          'worktree': gone,
          'branch': 'grid/tg-abc',
          'last_seq': '9',
        },
      ]);

      expect(appends, hasLength(1));
      final record = appends.single.record as WorktreeReaped;
      expect(record.sessionId, 'tranquility-1');
      expect(record.worktree, gone);
      // The flares omit path + branch today; the record does not (§2.3).
      expect(record.branch, 'grid/tg-abc');
      expect(appends.single.provenance, TrajectoryProvenance.inferred);
      expect(appends.single.provenanceBasis, kTickReapedBackfillBasis);
    });

    test('appends NOTHING while the worktree is still on disk — the live reap '
        'is the CUT\'s obligation, not the shadow window\'s', () async {
      final live = Directory(p.join(root.path, 'tg-live'))..createSync();

      final appends = await build().repair([
        {'session_id': 'tranquility-1', 'worktree': live.path, 'branch': null},
      ]);

      expect(appends, isEmpty);
      expect(live.existsSync(), isTrue, reason: 'the repair reaps nothing');
    });

    test('files ONE record per (session, worktree) even when an incarnation '
        'ladder returns several attempts', () async {
      final gone = p.join(root.path, 'tg-abc');
      final rows = [
        for (var i = 0; i < 3; i++)
          {
            'session_id': 'tranquility-1',
            'worktree': gone,
            'branch': 'grid/tg-abc',
          },
      ];

      expect(await build().repair(rows), hasLength(1));
    });
  });

  group('obligation 3 — the liveness detector', () {
    late Directory root;
    late _FakeDb db;
    late _FakeClock clock;

    setUp(() {
      root = Directory.systemTemp.createTempSync('w7-liveness');
      db = _FakeDb();
      clock = _FakeClock();
    });
    tearDown(() => root.deleteSync(recursive: true));

    /// A worktree whose `.grid` last changed at [beatAt].
    String worktreeBeating({required DateTime beatAt, String name = 'tg-abc'}) {
      final dir = Directory(p.join(root.path, name, '.grid'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'agent.usage.json'))
        ..writeAsStringSync('{}')
        ..setLastModifiedSync(beatAt);
      return p.join(root.path, name);
    }

    LivenessDetectorObligation build({
      LastActivityPoll? lastActivity,
      int epoch = 7,
      Duration threshold = const Duration(minutes: 10),
      Duration coalesce = const Duration(seconds: 30),
    }) => LivenessDetectorObligation(
      recorder: _recorder(),
      db: db,
      station: 'tranquility',
      bootEpoch: () => epoch,
      clock: clock.call,
      lastActivity: lastActivity,
      threshold: threshold,
      coalesce: coalesce,
    );

    Map<String, String?> row({
      String attemptId = 'A1',
      String? worktree,
      String? beatAt,
      String stepPath = 'tg-abc/build',
    }) => {
      'attempt_id': attemptId,
      'session_id': 'tranquility-1',
      'step_path': stepPath,
      'worktree': worktree,
      'beat_at': beatAt,
    };

    test(
      'joins pulses of the CURRENT epoch only — the unknown rule, in SQL',
      () {
        final query = build(epoch: 12);

        expect(query.sql, contains('u.boot_epoch = :boot_epoch'));
        expect(query.sql, contains("u.kind = 'attempt'"));
        expect(query.parameters, {'boot_epoch': 12, 'station': 'tranquility'});
        expect(query.sql, contains("h.status = 'open'"));
      },
    );

    test('is scoped and bounded like its two siblings: a station predicate '
        'and the standing per-pass LIMIT', () {
      final query = build();

      expect(query.sql, contains('h.rig = :station'));
      expect(query.sql, contains('LIMIT $kObligationBatchSize'));
      expect(query.parameters['station'], 'tranquility');
    });

    test('UNKNOWN: a subject with no observable beat emits NOTHING and writes '
        'no pulse — a restored log can never mint a loss', () async {
      final detector = build();
      clock.advance(const Duration(hours: 4));

      final appends = await detector.repair([row()]);

      expect(appends, isEmpty);
      expect(detector.lastUnknownSubjects, 1);
      expect(
        db.statements.map((statement) => statement.sql),
        everyElement(startsWith('DELETE FROM traj_pulse')),
        reason: 'an unknown subject gets no UPSERT',
      );
    });

    test('a beat carried by a PRIOR epoch never reaches the detector — the '
        'row simply arrives with beat_at NULL', () async {
      // The epoch predicate lives in the join, so a prior-epoch pulse row is
      // indistinguishable from no row: same unknown, same silence.
      final detector = build();
      expect(await detector.repair([row(beatAt: null)]), isEmpty);
      expect(detector.lastUnknownSubjects, 1);
    });

    test(
      'a fresh worktree mtime beat UPSERTs traj_pulse and crosses nothing',
      () async {
        final worktree = worktreeBeating(
          beatAt: clock.now.subtract(const Duration(minutes: 1)),
        );

        final appends = await build().repair([row(worktree: worktree)]);

        expect(appends, isEmpty);
        final upsert = db.statements.first;
        expect(upsert.sql, startsWith('INSERT INTO traj_pulse'));
        expect(upsert.sql, contains('ON DUPLICATE KEY UPDATE'));
        expect(upsert.params!['subject_id'], 'A1');
        expect(upsert.params!['boot_epoch'], 7);
        expect(upsert.params!['observed_via'], kPulseViaWorktreeMtime);
      },
    );

    test(
      'LOST once, on the crossing — a stale beat observed this epoch',
      () async {
        final beat = clock.now;
        final worktree = worktreeBeating(beatAt: beat);
        final detector = build();
        await detector.repair([row(worktree: worktree)]);

        clock.advance(const Duration(minutes: 11));
        final crossing = await detector.repair([
          row(worktree: worktree, beatAt: _serverInstant(beat)),
        ]);
        final again = await detector.repair([
          row(worktree: worktree, beatAt: _serverInstant(beat)),
        ]);

        expect(crossing, hasLength(1));
        final record = crossing.single.record as AttemptLivenessTransition;
        expect(record.crossing, LivenessCrossing.lost);
        expect(record.attemptId, 'A1');
        expect(record.lastBeatAt, beat);
        expect(record.thresholdMs, const Duration(minutes: 10).inMilliseconds);
        expect(crossing.single.provenance, TrajectoryProvenance.observed);
        expect(again, isEmpty, reason: 'transitions only, never per-pass');
      },
    );

    test('REGAINED when the subject beats again after a loss', () async {
      final beat = clock.now;
      final worktree = worktreeBeating(beatAt: beat);
      final detector = build();
      clock.advance(const Duration(minutes: 11));
      await detector.repair([
        row(worktree: worktree, beatAt: _serverInstant(beat)),
      ]);

      // The agent writes again: a new mtime, at the new now.
      final revived = clock.now;
      File(p.join(worktree, '.grid', 'agent.usage.json'))
        ..writeAsStringSync('{"turns": 2}')
        ..setLastModifiedSync(revived);
      final appends = await detector.repair([
        row(worktree: worktree, beatAt: _serverInstant(beat)),
      ]);

      expect(appends, hasLength(1));
      final record = appends.single.record as AttemptLivenessTransition;
      expect(record.crossing, LivenessCrossing.regained);
      expect(record.lastBeatAt, revived);
    });

    test('polls the provider too, and the NEWER surface is the beat', () async {
      final stale = clock.now.subtract(const Duration(hours: 2));
      final worktree = worktreeBeating(beatAt: stale);
      final polled = clock.now.subtract(const Duration(seconds: 5));

      final appends = await build(
        lastActivity: (name) =>
            name == 'tranquility-1/tg-abc/build' ? polled : null,
      ).repair([row(worktree: worktree)]);

      expect(appends, isEmpty, reason: 'the provider says it is alive');
      final upsert = db.statements.first;
      expect(upsert.params!['observed_via'], kPulseViaRuntime);
      expect(upsert.params!['beat_at'], sqlDateTime6(polled));
    });

    test('coalesces: a beat within the window does not rewrite the row '
        '(schema §4: ≥30s per subject)', () async {
      final stored = clock.now.subtract(const Duration(seconds: 10));
      final worktree = worktreeBeating(beatAt: clock.now);

      await build().repair([
        row(worktree: worktree, beatAt: _serverInstant(stored)),
      ]);

      expect(
        db.statements.where(
          (statement) => statement.sql.startsWith('INSERT INTO traj_pulse'),
        ),
        isEmpty,
      );
    });

    test(
      'prunes the pulses of settled subjects every pass (§4 prune rule)',
      () async {
        await build().repair([row()]);

        final prune = db.statements.last;
        expect(prune.sql, startsWith('DELETE FROM traj_pulse'));
        expect(prune.sql, contains("h.status = 'closed'"));
      },
    );

    test(
      'publishes its scan cost — the in-budget number an operator reads',
      () async {
        final detector = build();
        final worktree = worktreeBeating(beatAt: clock.now);

        await detector.repair([row(worktree: worktree)]);

        expect(detector.lastScanCost, isNotNull);
        expect(detector.lastScanCost!.worktrees, 1);
        expect(detector.lastScanCost!.scanned, 1);
      },
    );
  });
}
