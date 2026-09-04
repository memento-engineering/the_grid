import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

void main() {
  test('folds recorded verdicts into alphabetical lanes', () {
    final result = foldBeadRound([
      _verdict(seq: 1, lane: 'security', grade: 'B'),
      _verdict(seq: 2, lane: 'coherence', grade: 'A'),
      _verdict(seq: 3, lane: 'correctness', grade: 'D'),
    ]);

    expect(result.lanes.map((lane) => lane.lane), [
      'coherence',
      'correctness',
      'security',
    ]);
    expect(result.recordsRead, 3);
  });

  test('a re-graded lane keeps the highest sequence row', () {
    final result = foldBeadRound([
      _verdict(seq: 3, lane: 'correctness', grade: 'F', rationale: 'old'),
      _verdict(seq: 8, lane: 'correctness', grade: 'A', rationale: 'fixed'),
    ]);

    expect(result.lanes.single.grade, 'A');
    expect(result.lanes.single.rationale, 'fixed');
  });

  test('recovered verdicts report envelope transport', () {
    final result = foldBeadRound([
      _verdict(seq: 1, lane: 'coherence', grade: 'B', recovered: true),
    ]);

    expect(result.lanes.single.transport, 'envelope');
  });

  test('an escalating route names only its adverse lanes as gating', () {
    final result = foldBeadRound([
      _verdict(seq: 1, lane: 'coherence', grade: 'B'),
      _verdict(seq: 2, lane: 'correctness', grade: 'F'),
      _route(
        seq: 3,
        verdict: 'escalate',
        grades: {
          'coherence': {'grade': 'B'},
          'correctness': {'grade': 'F'},
        },
      ),
    ]);

    expect(result.gatingLanes, ['correctness']);
    expect(result.route?.gatingLanes, ['correctness']);
    expect(result.route?.verdict, 'escalate');
  });

  test('an advancing route gates nothing beside an adverse lane', () {
    final result = foldBeadRound([
      _verdict(seq: 1, lane: 'correctness', grade: 'D'),
      _route(seq: 2, verdict: 'advance', grades: const {'correctness': 'D'}),
    ]);

    expect(result.gatingLanes, isEmpty);
  });

  test('without a route every adverse lane gates', () {
    final result = foldBeadRound([
      _verdict(seq: 1, lane: 'security', grade: 'F'),
      _verdict(seq: 2, lane: 'coherence', grade: 'A'),
      _verdict(seq: 3, lane: 'correctness', grade: 'D'),
    ]);

    expect(result.gatingLanes, ['correctness', 'security']);
  });

  test('unknown records are ignored and an empty input stays empty', () {
    final unknown = foldBeadRound([
      envelope(
        recordType: 'verify.future.fact',
        family: TrajectoryFamily.verification,
      ),
    ]);
    final empty = foldBeadRound(const []);

    expect(unknown.lanes, isEmpty);
    expect(unknown.recordsRead, 1);
    expect(empty.lanes, isEmpty);
    expect(empty.recordsRead, 0);
  });
}

TrajectoryEnvelope _verdict({
  required int seq,
  required String lane,
  required String grade,
  String rationale = 'because',
  bool recovered = false,
}) => envelope(
  recordType: recovered
      ? 'verify.verdict.recovered'
      : 'verify.verdict.recorded',
  family: TrajectoryFamily.verification,
  seq: seq,
  sessionId: 'session-1',
  round: 1,
  stepPath: 'review/$lane',
  stepRound: 1,
  incarnation: recovered ? null : 0,
  commitSha: recovered ? null : 'abc123',
  provenance: recovered
      ? TrajectoryProvenance.inferred
      : TrajectoryProvenance.observed,
  payload: {
    'lane': lane,
    'rubric_version': 'v1',
    'grade': grade,
    'rationale': rationale,
    'transport': recovered ? 'envelope' : 'artifact',
    'pinned_head_sha': 'abc123',
    'sha_drift': false,
  },
);

TrajectoryEnvelope _route({
  required int seq,
  required String verdict,
  required Map<String, Object?> grades,
}) => envelope(
  recordType: 'verify.route.verdict',
  family: TrajectoryFamily.verification,
  seq: seq,
  sessionId: 'session-1',
  round: 1,
  stepPath: 'review/route',
  stepRound: 1,
  incarnation: 0,
  payload: {'verdict': verdict, 'rule': 'committee', 'grades': grades},
);
