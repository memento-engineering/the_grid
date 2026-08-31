/// The `legacy_attempt_count` join (§2.2): an INEQUALITY against a counter
/// that only ever increments, not an equality against a snapshot.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const String _session = 'tranquility-5xk';
const String _bead = 'tg-9abc';

TrajectoryEnvelope _started({int seq = 1, int? legacyAttemptCount}) => envelope(
  recordType: 'attempt.session.started',
  family: TrajectoryFamily.attempt,
  seq: seq,
  sessionId: _session,
  workBeadId: _bead,
  grantId: '01J8GRANT00000000000000001',
  mountAttemptId: '01J8MOUNT00000000000000001',
  payload: {
    'rig': 'operator',
    'model': 'molecule',
    'grant_basis': 'pre-stage3',
    if (legacyAttemptCount != null) 'legacy_attempt_count': legacyAttemptCount,
  },
);

TrajectoryEnvelope _mint({
  required int seq,
  required int mintAttempt,
  int? legacyAttemptCount,
}) => envelope(
  recordType: 'attempt.mint.outcome',
  family: TrajectoryFamily.attempt,
  seq: seq,
  workBeadId: _bead,
  mountAttemptId: '01J8MOUNT0000000000000000$mintAttempt',
  payload: {
    'phase': 'refused',
    'mint_attempt': mintAttempt,
    if (legacyAttemptCount != null) 'legacy_attempt_count': legacyAttemptCount,
  },
);

class _ScriptedLedger implements LegacyMountAttemptReader {
  _ScriptedLedger(this.counts);

  final Map<String, int> counts;
  final asked = <String>[];

  @override
  Future<int?> attemptCount(String workBeadId) async {
    asked.add(workBeadId);
    return counts[workBeadId];
  }
}

Future<ShadowCompareResult> _compare(
  Map<String, int> ledger,
  List<TrajectoryEnvelope> rows, {
  int? round,
}) => MountOrdinalShadow(_ScriptedLedger(ledger)).compare(
  sessionId: _session,
  records: SubjectRecords(records: rows),
  round: round,
);

void main() {
  test('equal ordinals agree', () async {
    final result = await _compare(
      {_bead: 2},
      [_started(legacyAttemptCount: 2)],
    );
    expect(result.mismatches, isEmpty);
  });

  test('a ledger AHEAD of the record is history, not divergence', () async {
    // The bead mounted again after this session: the counter is merged in
    // place and only increments, so `ledger > observed` is expected.
    final result = await _compare(
      {_bead: 3},
      [_started(legacyAttemptCount: 1)],
    );
    expect(result.mismatches, isEmpty);
  });

  test('a fold claiming an ordinal the ledger never reached is unexplained '
      'and blocks the cut', () async {
    final result = await _compare(
      {_bead: 1},
      [_started(legacyAttemptCount: 3)],
    );
    final row = result.mismatches.single;
    expect(row.field, 'legacy_attempt_count');
    expect(row.legacyValue, '1');
    expect(row.foldValue, '3');
    expect(row.classification, ShadowMismatchClass.unexplained);
  });

  test('an ordinal against a bead the ledger has no record of is '
      'unexplained', () async {
    final result = await _compare(const {}, [_started(legacyAttemptCount: 2)]);
    final row = result.mismatches.single;
    expect(row.legacyValue, isNull);
    expect(row.foldValue, '2');
    expect(row.classification, ShadowMismatchClass.unexplained);
  });

  test('the HIGHEST observed ordinal joins, not the last one seen', () async {
    final result = await _compare(
      {_bead: 3},
      [
        _mint(seq: 1, mintAttempt: 1, legacyAttemptCount: 3),
        _mint(seq: 2, mintAttempt: 2, legacyAttemptCount: 1),
      ],
    );
    expect(result.mismatches, isEmpty);
    // …and a ledger below the highest is caught even when the LAST record
    // would have agreed.
    final caught = await _compare(
      {_bead: 1},
      [
        _mint(seq: 1, mintAttempt: 1, legacyAttemptCount: 3),
        _mint(seq: 2, mintAttempt: 2, legacyAttemptCount: 1),
      ],
    );
    expect(caught.mismatches.single.foldValue, '3');
  });

  test('a ledger counting remounts with NO ordinal on any record is the '
      'non-atomic-crash class', () async {
    final result = await _compare({_bead: 3}, [_started()]);
    final row = result.mismatches.single;
    expect(row.legacyValue, '3');
    expect(row.foldValue, isNull);
    expect(row.classification, ShadowMismatchClass.nonAtomicCrash);
  });

  test('a first-try mount with no ordinal anywhere agrees', () async {
    expect((await _compare({_bead: 1}, [_started()])).mismatches, isEmpty);
    expect((await _compare(const {}, [_started()])).mismatches, isEmpty);
  });

  test('records with no work bead are not joined at all', () async {
    final ledger = _ScriptedLedger(const {});
    final result = await MountOrdinalShadow(ledger).compare(
      sessionId: _session,
      records: SubjectRecords(
        records: [
          envelope(
            recordType: 'attempt.rework_declined',
            family: TrajectoryFamily.attempt,
            seq: 1,
            sessionId: _session,
            round: 0,
            payload: const {'reason': 'held'},
          ),
        ],
      ),
    );
    expect(result.mismatches, isEmpty);
    expect(ledger.asked, isEmpty);
  });

  test('the join is NOT round-scoped — the ordinal spans rounds', () async {
    // A rework mints a fresh session against the SAME budget, so filtering by
    // round would hide exactly the remount history the ordinal measures.
    final result = await _compare(
      {_bead: 1},
      [_started(legacyAttemptCount: 3)],
      round: 7,
    );
    expect(result.mismatches, hasLength(1));
  });

  test(
    'a truncated stream is INCOMPLETE, never a highest-of-a-prefix',
    () async {
      final result = await MountOrdinalShadow(_ScriptedLedger(const {}))
          .compare(
            sessionId: _session,
            records: const SubjectRecords(records: [], truncatedAt: 1),
          );
      expect(result.isIncomplete, isTrue);
      expect(result.incompleteReason, contains('PREFIX'));
    },
  );
}
