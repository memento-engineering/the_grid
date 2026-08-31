/// Every branch of the §5 append/claim contract, driven over a scripted
/// connection: the asymmetric CAS signal, 1213-at-COMMIT, both 1105 shapes,
/// the belt, the guarded reconnect, and the dolt-commit cadence.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

const _serialization = MySQLServerException('serialization failure', 1213);
const _duplicate = MySQLServerException('duplicate primary key', 1062);

AttemptNote _note(int ordinal) => AttemptNote(
  sessionId: 'tranquility-1',
  body: 'observed',
  channel: 'ops',
  noteOrdinal: ordinal,
);

class _Harness {
  _Harness() {
    appender = TrajectoryAppender(db: db, station: 'lunar', clock: () => now);
  }

  final db = ScriptedDb();
  DateTime now = DateTime.utc(2026, 8, 31, 12);
  late final TrajectoryAppender appender;

  void scriptClaimReads({int epoch = 1}) {
    db.on(
      'AS e FROM traj_epoch',
      result: SqlResult(
        rows: [
          {'e': '$epoch'},
        ],
      ),
    );
  }

  void scriptFenceHeld() =>
      db.on('UPDATE traj_fence', result: const SqlResult(affectedRows: 1));

  void scriptInsertSeq(int seq) => db.on(
    'INSERT INTO trajectory (',
    respond: (_) => SqlResult(affectedRows: 1, lastInsertId: seq),
    once: true,
  );

  Future<void> claim() async {
    final outcome = await appender.claimEpoch(pid: 11, pgid: 12);
    expect(outcome, isA<EpochClaimed>());
  }
}

void main() {
  group('epoch claim', () {
    test('single INSERT of server-side MAX+1, then the fence-cell UPSERT '
        'seeded to epoch<<32', () async {
      final h = _Harness()..scriptClaimReads(epoch: 3);
      final outcome = await h.appender.claimEpoch(pid: 11, pgid: 12);

      expect(outcome, isA<EpochClaimed>());
      expect((outcome as EpochClaimed).epoch, 3);
      expect(h.appender.bootEpoch, 3);

      final insert = h.db.matching('INSERT INTO traj_epoch').single;
      expect(insert.sql, contains('COALESCE(MAX(epoch), 0) + 1'));
      expect(insert.params!['cause'], 'boot');

      final seed = h.db.matching('INSERT INTO traj_fence').single;
      expect(seed.sql, contains('ON DUPLICATE KEY UPDATE'));
      expect(seed.params!['state'], 3 << 32);
    });

    test('1213 on the claim re-reads MAX and retries', () async {
      final h = _Harness();
      h.db.on('INSERT INTO traj_epoch', throwing: _serialization, once: true);
      h.scriptClaimReads(epoch: 6);

      final outcome = await h.appender.claimEpoch(pid: 11, pgid: 12);

      expect((outcome as EpochClaimed).epoch, 6);
      expect(h.db.matching('INSERT INTO traj_epoch'), hasLength(2));
    });

    test('1213 past the retry budget refuses', () async {
      final h = _Harness();
      h.db.on('INSERT INTO traj_epoch', throwing: _serialization);
      h.scriptClaimReads();

      final outcome = await h.appender.claimEpoch(pid: 11, pgid: 12);

      expect(outcome, isA<EpochClaimRefused>());
      expect((outcome as EpochClaimRefused).attempts, 3);
    });

    test('1062 is NOT caught — the PK is not the arbiter', () async {
      final h = _Harness();
      h.db.on('INSERT INTO traj_epoch', throwing: _duplicate);

      await expectLater(
        h.appender.claimEpoch(pid: 11, pgid: 12),
        throwsA(
          isA<MySQLServerException>().having((e) => e.errorCode, 'code', 1062),
        ),
      );
    });
  });

  group('append transaction', () {
    test('runs fence CAS, belt read, row INSERT, proj_meta advance, COMMIT — '
        'in that order', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld()
        ..scriptInsertSeq(101);
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<Appended>());
      final appended = outcome as Appended;
      expect(appended.seq, 101);
      expect(appended.epochSeq, 1);

      final sql = h.db.log.map((call) => call.sql).toList();
      final order = [
        sql.indexWhere((s) => s == 'START TRANSACTION'),
        sql.indexWhere((s) => s.contains('UPDATE traj_fence')),
        sql.indexWhere((s) => s.contains('SELECT boot_epoch FROM trajectory')),
        sql.indexWhere((s) => s.contains('INSERT INTO trajectory (')),
        sql.indexWhere((s) => s.contains('INSERT INTO proj_meta')),
        sql.indexWhere((s) => s == 'COMMIT'),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)));
      expect(order, orderedEquals(List.of(order)..sort()));

      final cas = h.db.matching('UPDATE traj_fence').single;
      expect(cas.sql, contains('(fence_state >> 32) = :epoch'));

      final row = h.db.matching('INSERT INTO trajectory (').single.params!;
      expect(row['epoch_seq'], 1);
      expect(row['boot_epoch'], 1);
      expect(row['station'], 'lunar');
      expect(row['authority_id'], 'lunar/1');
      expect(row['record_type'], 'attempt.note');
      expect(row['idem_key_text'], 'note:tranquility-1:1');
      expect(row['occurred_at'], '2026-08-31 12:00:00.000000');

      final meta = h.db.matching('INSERT INTO proj_meta').single;
      expect(meta.params!['seq'], 101);
    });

    test(
      'epoch_seq is a serialized stream: consecutive appends take 1, 2',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld()
          ..scriptInsertSeq(101)
          ..scriptInsertSeq(102);
        await h.claim();

        await h.appender.append(_note(1));
        final second = await h.appender.append(_note(2)) as Appended;

        expect(second.epochSeq, 2);
        final rows = h.db.matching('INSERT INTO trajectory (');
        expect(rows[1].params!['epoch_seq'], 2);
      },
    );

    test(
      'seat is service-derived from the work bead store prefix (ck_seat)',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld()
          ..scriptInsertSeq(101);
        await h.claim();

        await h.appender.append(
          const AdmissionGrantConsumed(grantId: 'G1', workBeadId: 'tg-zfek'),
        );

        final row = h.db.matching('INSERT INTO trajectory (').single.params!;
        expect(row['work_bead_id'], 'tg-zfek');
        expect(row['seat'], 'tg');
      },
    );
  });

  group('the fence — asymmetric signal', () {
    test(
      '0-row CAS match is ALWAYS fenced out: rollback, no insert, inert',
      () async {
        final h = _Harness()..scriptClaimReads();
        h.db.on('UPDATE traj_fence', result: const SqlResult(affectedRows: 0));
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect(outcome, isA<AppendFencedOut>());
        expect((outcome as AppendFencedOut).reason, 'cas-zero-rows');
        expect(h.appender.isInert, isTrue);
        expect(h.db.matching('INSERT INTO trajectory ('), isEmpty);
        expect(h.db.matching('ROLLBACK'), hasLength(1));

        // Inert appends NOTHING further — not even SQL.
        final logLength = h.db.log.length;
        final again = await h.appender.append(_note(2));
        expect(again, isA<AppendFencedOut>());
        expect((again as AppendFencedOut).reason, 'inert');
        expect(h.db.log.length, logLength);
      },
    );

    test(
      '1 row is never proof: 1213 at COMMIT is the fenced-out signal',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld()
          ..scriptInsertSeq(101);
        h.db.on('COMMIT', throwing: _serialization);
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect((outcome as AppendFencedOut).reason, 'commit-1213');
        expect(h.appender.isInert, isTrue);
      },
    );
  });

  group('1105, branched on the constraint named', () {
    test('uq_idem is the designed dedupe: the ORIGINAL record_id returns as '
        'success', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.onUniqueViolation('INSERT INTO trajectory (', 'uq_idem');
      h.db.on(
        'SELECT record_id FROM trajectory',
        result: const SqlResult(
          rows: [
            {'record_id': '01ORIGINAL00000000000000AA'},
          ],
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<AppendDeduped>());
      expect((outcome as AppendDeduped).recordId, '01ORIGINAL00000000000000AA');
      expect(h.appender.isInert, isFalse);
      expect(h.appender.isHalted, isFalse);
    });

    test('a dedupe does not consume epoch_seq', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.onUniqueViolation('INSERT INTO trajectory (', 'uq_idem', once: true);
      h.db.on(
        'SELECT record_id FROM trajectory',
        result: const SqlResult(
          rows: [
            {'record_id': '01ORIGINAL00000000000000AA'},
          ],
        ),
      );
      h.scriptInsertSeq(102);
      await h.claim();

      await h.appender.append(_note(1));
      final next = await h.appender.append(_note(2)) as Appended;

      expect(next.epochSeq, 1);
    });

    test('statement-time 1062 (the dolt 2.2 same-snapshot shape) dedupes when '
        'the log holds our idem_key', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'INSERT INTO trajectory (',
        throwing: const MySQLServerException(
          'duplicate unique key given: [abc123]',
          1062,
        ),
      );
      h.db.on(
        'SELECT record_id FROM trajectory',
        result: const SqlResult(
          rows: [
            {'record_id': '01ORIGINAL00000000000000AA'},
          ],
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<AppendDeduped>());
      expect((outcome as AppendDeduped).recordId, '01ORIGINAL00000000000000AA');
    });

    test('statement-time 1062 with NO matching idem_key is the belt class — '
        'halt', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'INSERT INTO trajectory (',
        throwing: const MySQLServerException(
          'duplicate unique key given: [lunar,1,1]',
          1062,
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<AppendCorruptionHalt>());
      expect(h.appender.isHalted, isTrue);
    });

    test(
      'uq_epoch_seq is detect-and-halt; the appender refuses forever after',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld();
        h.db.onUniqueViolation('INSERT INTO trajectory (', 'uq_epoch_seq');
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect(outcome, isA<AppendCorruptionHalt>());
        expect(h.appender.isHalted, isTrue);

        final logLength = h.db.log.length;
        final again = await h.appender.append(_note(2));
        expect(again, isA<AppendCorruptionHalt>());
        expect(h.db.log.length, logLength);
      },
    );
  });

  group('the belt', () {
    test(
      'a decreasing boot_epoch over seq is the corruption-halt class',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld();
        h.db.on(
          'SELECT boot_epoch FROM trajectory',
          result: const SqlResult(
            rows: [
              {'boot_epoch': '9'},
            ],
          ),
        );
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect(outcome, isA<AppendCorruptionHalt>());
        expect(
          (outcome as AppendCorruptionHalt).reason,
          contains('boot_epoch would decrease'),
        );
        expect(h.appender.isHalted, isTrue);
        expect(h.db.matching('INSERT INTO trajectory ('), isEmpty);
        expect(h.db.matching('ROLLBACK'), hasLength(1));
      },
    );

    test('an expired grant refuses the consuming append', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        "record_type = 'admission.grant.issued'",
        result: const SqlResult(
          rows: [
            {'expires_at': '2026-08-31 11:00:00.000000'},
          ],
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(
        const AdmissionGrantConsumed(grantId: 'G1'),
      );

      expect(outcome, isA<AppendCorruptionHalt>());
      expect((outcome as AppendCorruptionHalt).reason, contains('expired'));
    });
  });

  group('terminal guard', () {
    test('an unsettled terminal INSERTs its guard row', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld()
        ..scriptInsertSeq(101);
      await h.claim();

      await h.appender.append(
        AttemptTerminal(
          attemptId: '01ATTEMPT000000000000000AA',
          outcome: TerminalOutcome.succeeded,
        ),
      );

      final guard = h.db.matching('INSERT INTO traj_terminal_guard').single;
      expect(guard.params!['attempt_id'], '01ATTEMPT000000000000000AA');
      expect(guard.params!['seq'], 101);
    });

    test('a settling terminal UPDATEs seq and settled_by instead', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld()
        ..scriptInsertSeq(102);
      await h.claim();

      await h.appender.append(
        AttemptTerminal(
          attemptId: '01ATTEMPT000000000000000AA',
          outcome: TerminalOutcome.settled,
          resolvesRecordId: '01UNKNOWN000000000000000AA',
        ),
      );

      expect(h.db.matching('INSERT INTO traj_terminal_guard'), isEmpty);
      final settle = h.db.matching('UPDATE traj_terminal_guard').single;
      expect(settle.params!['seq'], 102);
      expect(settle.params!['settled_by'], isNotNull);
    });
  });

  group('guarded reconnect', () {
    test('same live epoch: re-seeds the cell by UPSERT and resumes the '
        'epoch_seq stream', () async {
      final h = _Harness()..scriptClaimReads();
      await h.claim();

      final fresh = ScriptedDb();
      fresh.on(
        'AS e FROM traj_epoch',
        result: const SqlResult(
          rows: [
            {'e': '1'},
          ],
        ),
      );
      fresh.on(
        'AS s FROM trajectory',
        result: const SqlResult(
          rows: [
            {'s': '41'},
          ],
        ),
      );
      fresh.on('UPDATE traj_fence', result: const SqlResult(affectedRows: 1));
      fresh.on(
        'INSERT INTO trajectory (',
        respond: (_) => const SqlResult(affectedRows: 1, lastInsertId: 900),
      );

      final outcome = await h.appender.reconnect(fresh);

      expect(outcome, isA<ReconnectResumed>());
      expect(fresh.matching('INSERT INTO traj_fence'), hasLength(1));

      final appended = await h.appender.append(_note(9)) as Appended;
      expect(appended.epochSeq, 42);
    });

    test('stale epoch goes INERT without touching the cell', () async {
      final h = _Harness()..scriptClaimReads();
      await h.claim();

      final fresh = ScriptedDb();
      fresh.on(
        'AS e FROM traj_epoch',
        result: const SqlResult(
          rows: [
            {'e': '2'},
          ],
        ),
      );

      final outcome = await h.appender.reconnect(fresh);

      expect(outcome, isA<ReconnectInert>());
      final inert = outcome as ReconnectInert;
      expect(inert.staleEpoch, 1);
      expect(inert.liveEpoch, 2);
      expect(h.appender.isInert, isTrue);
      expect(fresh.matching('traj_fence'), isEmpty);

      final refused = await h.appender.append(_note(1));
      expect(refused, isA<AppendFencedOut>());
    });
  });

  group('dolt-commit cadence', () {
    _Harness cadenceHarness() {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'INSERT INTO trajectory (',
        respond: (_) => const SqlResult(affectedRows: 1, lastInsertId: 500),
      );
      h.db.on(
        'active_branch()',
        result: const SqlResult(
          rows: [
            {'b': 'main'},
          ],
        ),
      );
      return h;
    }

    void scriptLogCount(_Harness h, int count) => h.db.on(
      'FROM dolt_log',
      result: SqlResult(
        rows: [
          {'c': '$count'},
        ],
      ),
      once: true,
    );

    test('no dolt commit lands inside the hard 10s minimum interval', () async {
      final h = cadenceHarness();
      await h.claim();
      h.now = h.now.add(const Duration(seconds: 5));

      await h.appender.append(_note(1));

      expect(h.db.matching('DOLT_COMMIT'), isEmpty);
      expect(h.appender.pendingRows, 1);
    });

    test('a boundary event within the minimum defers to the next call, then '
        'commits — verified only via dolt_log growth', () async {
      final h = cadenceHarness();
      await h.claim();
      h.now = h.now.add(const Duration(seconds: 5));

      await h.appender.append(
        const AttemptRoundRetired(
          sessionId: 'tranquility-1',
          oldRound: 0,
          newRound: 1,
          cause: RoundRetireCause.rework,
        ),
      );
      expect(h.db.matching('DOLT_COMMIT'), isEmpty);

      h.now = h.now.add(const Duration(seconds: 6)); // 11s after claim
      scriptLogCount(h, 5);
      scriptLogCount(h, 6);
      await h.appender.doltCommitIfDue();

      expect(h.db.matching('DOLT_ADD'), hasLength(1));
      final commit = h.db.matching('DOLT_COMMIT').single;
      expect(commit.params!['message'], 'traj: seq 500..500 epoch 1');
      expect(h.appender.verifiedDoltCommits, 1);
      expect(h.appender.pendingRows, 0);
    });

    test('the 30s cadence commits without a boundary; a non-growing dolt_log '
        'is never counted', () async {
      final h = cadenceHarness();
      await h.claim();
      h.now = h.now.add(const Duration(seconds: 15));
      await h.appender.append(_note(1));
      expect(h.db.matching('DOLT_COMMIT'), isEmpty); // 15s < 30s cadence

      h.now = h.now.add(const Duration(seconds: 20)); // 35s after claim
      scriptLogCount(h, 7);
      scriptLogCount(h, 7); // DOLT_COMMIT silently no-opped
      await h.appender.doltCommitIfDue();

      expect(h.db.matching('DOLT_COMMIT'), hasLength(1));
      expect(h.appender.verifiedDoltCommits, 0);
      expect(h.appender.pendingRows, 1); // still pending — commit never landed

      scriptLogCount(h, 7);
      scriptLogCount(h, 8);
      await h.appender.doltCommitIfDue();
      expect(h.appender.verifiedDoltCommits, 1);
      expect(h.appender.pendingRows, 0);
    });

    test('a branch change fails closed', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'INSERT INTO trajectory (',
        respond: (_) => const SqlResult(affectedRows: 1, lastInsertId: 500),
      );
      h.db.on(
        'active_branch()',
        result: const SqlResult(
          rows: [
            {'b': 'scratch'},
          ],
        ),
      );
      await h.claim();
      h.now = h.now.add(const Duration(seconds: 40));

      await expectLater(h.appender.append(_note(1)), throwsStateError);
      expect(h.appender.isHalted, isTrue);
    });
  });
}
