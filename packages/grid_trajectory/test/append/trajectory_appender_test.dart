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
    appender = TrajectoryAppender(
      db: db,
      station: 'lunar',
      clock: () => now,
      onEvent: events.add,
    );
  }

  final db = ScriptedDb();
  final events = <TrajectoryServiceEvent>[];
  DateTime now = DateTime.utc(2026, 8, 31, 12);
  late final TrajectoryAppender appender;

  List<TrajectoryServiceEventKind> get eventKinds => [
    for (final event in events) event.kind,
  ];

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
    // The append path re-asserts the branch pin; a test that wants a
    // different branch registers its own rule BEFORE claim() (earlier
    // registrations win).
    db.on(
      'SELECT active_branch()',
      result: const SqlResult(
        rows: [
          {'b': 'main'},
        ],
      ),
    );
    final outcome = await appender.claimEpoch(pid: 11, pgid: 12);
    expect(outcome, isA<EpochClaimed>());
  }
}

void main() {
  group('epoch claim', () {
    test('single INSERT of server-side MAX+1, adopted from the claim\'s OWN '
        'transaction snapshot, then the fence-cell UPSERT seeded to '
        'epoch<<32', () async {
      final h = _Harness()..scriptClaimReads(epoch: 3);
      final outcome = await h.appender.claimEpoch(pid: 11, pgid: 12);

      expect(outcome, isA<EpochClaimed>());
      expect((outcome as EpochClaimed).epoch, 3);
      expect(h.appender.bootEpoch, 3);

      final insert = h.db.matching('INSERT INTO traj_epoch').single;
      expect(insert.sql, contains('COALESCE(MAX(epoch), 0) + 1'));
      expect(insert.params!['cause'], 'boot');

      // The epoch is read back INSIDE the claim transaction — the snapshot
      // makes it our own row, never a rival's re-read MAX.
      final sql = h.db.log.map((call) => call.sql).toList();
      final order = [
        sql.indexWhere((s) => s == 'START TRANSACTION'),
        sql.indexWhere((s) => s.contains('INSERT INTO traj_epoch')),
        sql.indexWhere((s) => s.contains('AS e FROM traj_epoch')),
        sql.indexWhere((s) => s == 'COMMIT'),
        sql.indexWhere((s) => s.contains('INSERT INTO traj_fence')),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)));
      expect(order, orderedEquals(List.of(order)..sort()));

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
      // The claim owns the FIRST transaction pair; the append's is the last.
      final order = [
        sql.lastIndexWhere((s) => s == 'START TRANSACTION'),
        sql.indexWhere((s) => s.contains('UPDATE traj_fence')),
        sql.indexWhere(
          (s) =>
              s.contains('SELECT seq, boot_epoch, epoch_seq FROM trajectory'),
        ),
        sql.indexWhere((s) => s.contains('INSERT INTO trajectory (')),
        sql.indexWhere((s) => s.contains('INSERT INTO proj_meta')),
        sql.lastIndexWhere((s) => s == 'COMMIT'),
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
        await h.claim();
        // Registered after the claim so the claim's own transaction commits.
        h.db.on('COMMIT', throwing: _serialization);

        final outcome = await h.appender.append(_note(1));

        expect((outcome as AppendFencedOut).reason, 'commit-1213');
        expect(h.appender.isInert, isTrue);
        expect(h.eventKinds, [TrajectoryServiceEventKind.fencedOut]);
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
          'boot_epoch, epoch_seq FROM trajectory',
          result: const SqlResult(
            rows: [
              {'seq': '900', 'boot_epoch': '9', 'epoch_seq': '3'},
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
        expect(
          h.eventKinds,
          contains(TrajectoryServiceEventKind.corruptionHalt),
        );
      },
    );

    test(
      'a seq/epoch_seq disagreement is the §5 alarm — corruption-halt',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld()
          ..scriptInsertSeq(901);
        // Same epoch, but the previous row already sits at epoch_seq 41 while
        // this append's serialized stream would write 1: unique, out of order.
        h.db.on(
          'boot_epoch, epoch_seq FROM trajectory',
          result: const SqlResult(
            rows: [
              {'seq': '900', 'boot_epoch': '1', 'epoch_seq': '41'},
            ],
          ),
        );
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect(outcome, isA<AppendCorruptionHalt>());
        expect((outcome as AppendCorruptionHalt).reason, contains('disagrees'));
        expect(h.appender.isHalted, isTrue);
        expect(h.db.matching('ROLLBACK'), hasLength(1));
      },
    );

    test('verifyBeltAtBoot passes a clean log and halts on a seq order that '
        'disagrees with (boot_epoch, epoch_seq)', () async {
      final h = _Harness()..scriptClaimReads();
      h.db.on(
        'ORDER BY seq',
        result: const SqlResult(
          rows: [
            {'seq': '1', 'boot_epoch': '1', 'epoch_seq': '1'},
            {'seq': '2', 'boot_epoch': '1', 'epoch_seq': '2'},
            {'seq': '3', 'boot_epoch': '2', 'epoch_seq': '1'},
          ],
        ),
        once: true,
      );
      await h.claim();
      expect(await h.appender.verifyBeltAtBoot(), isNull);
      expect(h.appender.isHalted, isFalse);

      h.db.on(
        'ORDER BY seq',
        result: const SqlResult(
          rows: [
            {'seq': '1', 'boot_epoch': '2', 'epoch_seq': '5'},
            {'seq': '2', 'boot_epoch': '1', 'epoch_seq': '9'},
          ],
        ),
      );
      final halt = await h.appender.verifyBeltAtBoot();
      expect(halt, isA<AppendCorruptionHalt>());
      expect(h.appender.isHalted, isTrue);
    });
  });

  group('the grant belt — per-append refusals, never a halt', () {
    _Harness grantHarness({
      required String expiresAt,
      String serverNow = '2026-08-31 12:00:00.000000',
      String? grantToken,
    }) {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        "record_type = 'admission.grant.issued'",
        result: SqlResult(
          rows: [
            {
              'expires_at': expiresAt,
              'fencing_token': grantToken,
              'server_now': serverNow,
            },
          ],
        ),
      );
      return h;
    }

    test('an expired grant REFUSES the consuming append — rolled back, '
        'typed, service stays live', () async {
      final h = grantHarness(expiresAt: '2026-08-31 11:00:00.000000')
        ..scriptInsertSeq(101);
      await h.claim();

      final outcome = await h.appender.append(
        const AdmissionGrantConsumed(grantId: 'G1'),
      );

      expect(outcome, isA<AppendGrantRefused>());
      final refused = outcome as AppendGrantRefused;
      expect(refused.grantId, 'G1');
      expect(refused.predicate, 'expires_at');
      expect(h.appender.isHalted, isFalse);
      expect(h.appender.isInert, isFalse);
      expect(h.db.matching('INSERT INTO trajectory ('), isEmpty);
      expect(h.db.matching('ROLLBACK'), hasLength(1));
      expect(h.eventKinds, [TrajectoryServiceEventKind.grantRefused]);

      // Live after the refusal: the next append lands.
      final next = await h.appender.append(_note(2));
      expect(next, isA<Appended>());
    });

    test('expiry is judged against the SERVER\'s NOW(6), not the client '
        'clock', () async {
      // Client clock says 12:00; the server says 10:00 and the grant runs to
      // 11:00 — live by server time, so the append proceeds.
      final h = grantHarness(
        expiresAt: '2026-08-31 11:00:00.000000',
        serverNow: '2026-08-31 10:00:00.000000',
      )..scriptInsertSeq(101);
      await h.claim();

      final outcome = await h.appender.append(
        const AdmissionGrantConsumed(grantId: 'G1'),
      );

      expect(outcome, isA<Appended>());
    });

    test('a fencing_token mismatch refuses; a matching token passes', () async {
      final h = grantHarness(
        expiresAt: '2026-08-31 13:00:00.000000',
        grantToken: '77',
      )..scriptInsertSeq(101);
      await h.claim();

      final refused = await h.appender.append(
        const AdmissionGrantConsumed(grantId: 'G1'),
        fencingToken: 66,
      );
      expect(refused, isA<AppendGrantRefused>());
      expect((refused as AppendGrantRefused).predicate, 'fencing_token');
      expect(h.appender.isHalted, isFalse);

      final passed = await h.appender.append(
        const AdmissionGrantConsumed(grantId: 'G1'),
        fencingToken: 77,
      );
      expect(passed, isA<Appended>());
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
      fresh.on(
        'SELECT active_branch()',
        result: const SqlResult(
          rows: [
            {'b': 'main'},
          ],
        ),
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

  group('the catch-all — no throwable escapes with a transaction open', () {
    test(
      'an unclassified server error rolls back and surfaces typed',
      () async {
        final h = _Harness()
          ..scriptClaimReads()
          ..scriptFenceHeld();
        h.db.on(
          'INSERT INTO trajectory (',
          throwing: const MySQLServerException('table not found', 1146),
          once: true,
        );
        await h.claim();

        final outcome = await h.appender.append(_note(1));

        expect(outcome, isA<AppendInternalError>());
        expect(h.db.matching('ROLLBACK'), hasLength(1));
        expect(h.appender.isHalted, isFalse);
        expect(h.appender.isInert, isFalse);

        // Not a latch: the next append runs normally.
        h.scriptInsertSeq(101);
        expect(await h.appender.append(_note(2)), isA<Appended>());
      },
    );

    test('a non-server throwable (malformed belt read) rolls back and '
        'surfaces typed', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'boot_epoch, epoch_seq FROM trajectory',
        result: const SqlResult(
          rows: [
            {'seq': '1', 'boot_epoch': 'garbage', 'epoch_seq': '1'},
          ],
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<AppendInternalError>());
      expect((outcome as AppendInternalError).cause, isA<FormatException>());
      expect(h.db.matching('ROLLBACK'), hasLength(1));
    });
  });

  group('dolt-commit cadence', () {
    test('the boundary set is exactly §5\'s three', () {
      expect(doltCommitBoundaryTypes, {
        'authority.epoch.advanced',
        'attempt.terminal',
        'attempt.round.retired',
      });
    });

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

    test('a branch change fails closed on the append path — a TYPED halt, '
        'before any transaction opens', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      h.db.on(
        'active_branch()',
        result: const SqlResult(
          rows: [
            {'b': 'scratch'},
          ],
        ),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      // Fail-closed, but INSIDE the sealed hierarchy: §5 lets no raw
      // throwable escape append(), and the pin's own refusal is the
      // corruption halt it has already latched.
      expect(outcome, isA<AppendCorruptionHalt>());
      expect((outcome as AppendCorruptionHalt).reason, contains('scratch'));
      expect(h.appender.isHalted, isTrue);
      // The pin refused before the transaction — no CAS, no insert.
      expect(h.db.matching('START TRANSACTION'), hasLength(1)); // the claim's
      expect(h.db.matching('UPDATE traj_fence'), isEmpty);
      expect(h.eventKinds, contains(TrajectoryServiceEventKind.corruptionHalt));

      // The latch holds: every later append refuses with the same outcome.
      expect(await h.appender.append(_note(2)), isA<AppendCorruptionHalt>());
    });

    test('M4\'s recorded gap: a DEAD connection at the branch pin is a sealed '
        'AppendInternalError, never a raw client exception', () async {
      final h = _Harness()
        ..scriptClaimReads()
        ..scriptFenceHeld();
      // The socket is dead by the time the append runs — M4's S1/S2 shape,
      // where the branch-pin SELECT is the first statement to find it.
      // Registered before claim() so it outranks the harness's main-branch
      // rule (earlier registrations win); the claim path never asks.
      h.db.on(
        'active_branch()',
        throwing: const MySQLClientException('socket has been closed'),
      );
      await h.claim();

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<AppendInternalError>());
      expect(
        (outcome as AppendInternalError).cause,
        isA<MySQLClientException>(),
      );
      // A transport failure is NOT the pin's fail-closed refusal: the appender
      // is neither halted nor inert, and the guarded reconnect owns recovery.
      expect(h.appender.isHalted, isFalse);
      expect(h.appender.isInert, isFalse);
      expect(
        h.eventKinds,
        isNot(contains(TrajectoryServiceEventKind.corruptionHalt)),
      );
      // Nothing was opened, so nothing is left open.
      expect(h.db.matching('START TRANSACTION'), hasLength(1)); // the claim's
      expect(h.db.matching('UPDATE traj_fence'), isEmpty);
    });

    test('a post-COMMIT cadence failure NEVER rewrites the append outcome — '
        'it surfaces as its own non-fatal signal', () async {
      final h = cadenceHarness();
      await h.claim();
      h.now = h.now.add(const Duration(seconds: 40)); // cadence due
      // The cadence path dies on its dolt_log read AFTER the row committed.
      h.db.on('FROM dolt_log', throwing: _serialization, once: true);

      final outcome = await h.appender.append(_note(1));

      expect(outcome, isA<Appended>());
      expect((outcome as Appended).seq, 500);
      expect(h.appender.isInert, isFalse);
      expect(h.appender.isHalted, isFalse);
      expect(h.eventKinds, [TrajectoryServiceEventKind.cadenceFailure]);
      // The batch stays pending — retried at the next cadence.
      expect(h.appender.pendingRows, 1);

      // And the next due call, with the fault cleared, commits it.
      scriptLogCount(h, 5);
      scriptLogCount(h, 6);
      h.now = h.now.add(const Duration(seconds: 11));
      await h.appender.doltCommitIfDue();
      expect(h.appender.verifiedDoltCommits, 1);
      expect(h.appender.pendingRows, 0);
    });
  });
}
