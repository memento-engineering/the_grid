// W2-B (cut-wiring §W2.4) — the worktree-outstanding barrier's RESTORATION,
// executed rather than argued. AC10's condition is "when the P6 row flips to
// reaped", so this drives the actual flip: a standing `admission.refused` over
// a bead whose P6 row still says `live`, then the tick reap's `reaped`, against
// a REAL dolt trajectory schema.
//
// It is here rather than in grid_runtime for one mechanical reason: the
// obligation is grid_runtime's, the hermetic provisioned grid home is
// grid_sdk's, and grid_sdk depends on both. It also makes the obligation's SQL
// the only thing under test that a schema rename can break — the unit suite
// asserts substrings, this asserts dolt ACCEPTS them.
//
// FAIL-CLOSED without dolt on PATH (the stage0-guards-gate-prs convention): a
// skipped guard proves nothing at a stage cut.
@Tags(['integration'])
@Timeout(Duration(minutes: 3))
library;

import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart' show TrajectoryConnection;
import 'package:test/test.dart';

import 'support/hermetic_grid_home.dart';

/// The repair builds records; it never enqueues one. A sink that refuses
/// everything proves that.
final class _InertSink implements TrajectoryRecordSink {
  @override
  bool get accepting => false;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('the restoration obligation appends through the tick');
}

const String _station = 'it-station';
const String _bead = 'tg-abc';
const String _session = 'tranquility-w2b';
const String _attemptId = '01J8ZR0000000000000000000B';
const String _refusalId = '01J8ZR0000000000000000000A';
const String _restoredId = '01J8ZR0000000000000000000C';

void main() {
  late HermeticGridHome home;
  late TrajectoryConnection db;

  setUpAll(() async {
    home = await HermeticGridHome.create();
    await home.provision();
    db = await TrajectoryConnection.connect(home.adminEndpointFor('trajectory'));
  });

  tearDownAll(() async {
    await db.close();
    await home.dispose();
  });

  /// One row of the `trajectory` log, hand-seeded: the barrier's refusal is
  /// appended at the mount boundary, which this suite deliberately does not
  /// run — the flip is what is under test.
  Future<void> append({
    required String recordId,
    required int epochSeq,
    required String recordType,
    String? resolvesRecordId,
  }) => db.execute(
    'INSERT INTO trajectory (boot_epoch, epoch_seq, record_id, idem_key, '
    'idem_key_text, family, record_type, occurred_at, recorded_at, station, '
    'substation, authority_id, source, work_bead_id, mount_attempt_id, '
    'resolves_record_id, payload) '
    'VALUES (7, :epoch_seq, :record_id, :idem_key, :idem_key_text, '
    "'admission', :record_type, NOW(6), NOW(6), :station, 'tg', 'it-authority', "
    "'w2b-integration', :bead, :attempt, :resolves, "
    "JSON_OBJECT('clause', :clause, 'snapshot_rev', '1-abc'))",
    {
      'epoch_seq': epochSeq,
      'record_id': recordId,
      // CHAR(64), and UNIQUE — the digest's VALUE is irrelevant here, its
      // distinctness is not.
      'idem_key': recordId.padRight(64, '0'),
      'idem_key_text': '$recordType:$_bead:$kWorktreeOutstandingClause',
      'record_type': recordType,
      'station': _station,
      'bead': _bead,
      'attempt': _attemptId,
      'resolves': resolvesRecordId,
      'clause': kWorktreeOutstandingClause,
    },
  );

  AdmissionRestorationObligation obligation() => AdmissionRestorationObligation(
    recorder: StationTrajectoryRecorder(
      sink: _InertSink(),
      substationPrefixes: const {'tg'},
    ),
    station: _station,
  );

  Future<List<Map<String, String?>>> standing() async {
    final query = obligation();
    return (await db.execute(query.sql, query.parameters)).rows;
  }

  test('the refusal STANDS while P6 is live and RESTORES on the flip', () async {
    // The bead's P1 row — the only carrier of `session_id → work_bead_id`,
    // since P6 has no work-bead column — and the P6 row still holding the
    // worktree the barrier refused on.
    await db.execute(
      'INSERT INTO proj_session_head (session_id, work_bead_id, round, status, '
      'outcome, started_at, closed_at, head_epoch, last_seq) '
      "VALUES (:session, :bead, 0, 'closed', 'succeeded', NOW(6), NOW(6), 7, 1)",
      {'session': _session, 'bead': _bead},
    );
    await db.execute(
      'INSERT INTO proj_process_identity (attempt_id, session_id, round, '
      'step_path, step_round, incarnation, worktree, worktree_state, last_seq) '
      "VALUES (:attempt, :session, 0, 'tg-abc/build', 0, 0, :worktree, "
      "'live', 1)",
      {'attempt': _attemptId, 'session': _session, 'worktree': '/w/tg-abc'},
    );
    await append(
      recordId: _refusalId,
      epochSeq: 1,
      recordType: 'admission.refused',
    );

    // BEFORE THE FLIP. dolt accepts the query — every column name in it is
    // real — and it returns nothing: the worktree is still outstanding, so the
    // refusal stands.
    expect(
      await standing(),
      isEmpty,
      reason: 'a live P6 worktree keeps the refusal standing',
    );

    // THE FLIP — this is the tick reap landing, and nothing else changes.
    final flipped = await db.execute(
      "UPDATE proj_process_identity SET worktree_state = 'reaped' "
      'WHERE attempt_id = :attempt',
      {'attempt': _attemptId},
    );
    expect(flipped.affectedRows, 1);

    final rows = await standing();
    expect(rows, hasLength(1), reason: 'the flip is what opens the obligation');
    expect(rows.single['record_id'], _refusalId);
    expect(rows.single['work_bead_id'], _bead);

    final appends = await obligation().repair(rows);
    expect(appends, hasLength(1));
    final record = appends.single.record;
    expect(record.recordType, 'admission.restored');
    expect(
      record.idemKeyText(const IdemContext(station: _station, bootEpoch: 7)),
      'restored:$_bead:$kWorktreeOutstandingClause:$_refusalId',
    );
    expect(record.correlationToJson()['resolves_record_id'], _refusalId);
    expect(appends.single.substation, 'tg');

    // ONCE. With the restoration in the log the standing query closes, which
    // is the §5 invariant: the obligation keys off the external state it
    // repairs AND off its own resolved edge, so a fixpoint run terminates.
    await append(
      recordId: _restoredId,
      epochSeq: 2,
      recordType: 'admission.restored',
      resolvesRecordId: _refusalId,
    );
    expect(await standing(), isEmpty);
  });
}
