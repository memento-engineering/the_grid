import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

void main() {
  const found = RoundContext.round(
    beadId: 'tg-1',
    title: 'work',
    status: 'in_progress',
    sessionId: 'session-1',
    round: 2,
    validationPlan: 'dart test',
  );

  test('round renders and JSON-encodes trajectory lanes and gating', () async {
    final reader = _Reader([
      _verdict(seq: 1, lane: 'coherence', grade: 'A'),
      _verdict(seq: 2, lane: 'correctness', grade: 'F'),
      _route(seq: 3),
    ]);
    final output = <String>[];
    expect(
      await runBeadRound(
        gridRoot: '/grid',
        beadId: 'tg-1',
        client: _contextClient(found),
        open: (_) async => TrajectoryOpened(reader),
        out: output.add,
      ),
      0,
    );
    expect(output, contains(contains('> F  correctness')));
    expect(output, contains(contains('failed review')));
    expect(reader.closed, isTrue);

    final jsonReader = _Reader(reader.rows);
    final jsonOutput = <String>[];
    expect(
      await runBeadRound(
        gridRoot: '/grid',
        beadId: 'tg-1',
        client: _contextClient(found),
        open: (_) async => TrajectoryOpened(jsonReader),
        json: true,
        out: jsonOutput.add,
      ),
      0,
    );
    final decoded = jsonDecode(jsonOutput.single) as Map;
    expect(decoded['session_id'], 'session-1');
    expect(decoded['round'], 2);
    expect(decoded['validation_plan'], 'dart test');
    expect((decoded['verdicts'] as Map)['source'], 'trajectory');
    expect((decoded['verdicts'] as Map)['gating_lanes'], ['correctness']);
    expect(jsonReader.closed, isTrue);
  });

  test('no round exits zero and never opens trajectory', () async {
    const absent = RoundContext.noRound(
      beadId: 'tg-1',
      title: 'work',
      status: 'open',
      reason: 'between rounds',
    );
    var opens = 0;
    final output = <String>[];
    expect(
      await runBeadRound(
        gridRoot: '/grid',
        beadId: 'tg-1',
        client: _contextClient(absent),
        open: (_) async {
          opens++;
          return const TrajectoryUnavailable('must not open');
        },
        json: true,
        out: output.add,
      ),
      0,
    );
    expect(opens, 0);
    expect(
      (jsonDecode(output.single) as Map)['verdicts']['source'],
      'no_round',
    );
  });

  test('not bootstrapped is typed unavailable at exit zero', () async {
    final output = <String>[];
    expect(
      await runBeadRound(
        gridRoot: '/grid',
        beadId: 'tg-1',
        client: _contextClient(found),
        open: (_) async => const TrajectoryNotBootstrapped('not provisioned'),
        json: true,
        out: output.add,
      ),
      0,
    );
    final verdicts = (jsonDecode(output.single) as Map)['verdicts'] as Map;
    expect(verdicts['source'], 'unavailable');
    expect(verdicts['reason'], 'not provisioned');
  });

  test('trajectory connection failure exits one', () async {
    final errors = <String>[];
    expect(
      await runBeadRound(
        gridRoot: '/grid',
        beadId: 'tg-1',
        client: _contextClient(found),
        open: (_) async => const TrajectoryUnavailable('connection failed'),
        err: errors.add,
      ),
      1,
    );
    expect(errors.single, contains('connection failed'));
  });

  test('zero or two bead ids refuse before resident dispatch', () async {
    for (final args in const [
      ['bead', 'round', '--grid-root', '/grid'],
      ['bead', 'round', '--grid-root', '/grid', 'tg-1', 'tg-2'],
    ]) {
      final client = _FakeClient(const StationCommandCompleted({}));
      final runner = CommandRunner<int>('grid', 'test')
        ..addCommand(BeadCommand(client: client));
      expect(await runner.run(args), 64);
      expect(client.calls, 0);
    }
  });
}

_FakeClient _contextClient(RoundContext context) =>
    _FakeClient(StationCommandCompleted({'context': context.toJson()}));

TrajectoryEnvelope _verdict({
  required int seq,
  required String lane,
  required String grade,
}) => _envelope(
  recordType: 'verify.verdict.recorded',
  seq: seq,
  stepPath: 'review/$lane',
  payload: {
    'lane': lane,
    'rubric_version': 'v1',
    'grade': grade,
    'rationale': lane == 'correctness' ? 'failed review' : 'looks good',
    'transport': 'artifact',
    'pinned_head_sha': 'abc',
    'sha_drift': false,
  },
);

TrajectoryEnvelope _route({required int seq}) => _envelope(
  recordType: 'verify.route.verdict',
  seq: seq,
  stepPath: 'review/route',
  payload: const {
    'verdict': 'escalate',
    'rule': 'committee',
    'grades': {
      'coherence': {'grade': 'A'},
      'correctness': {'grade': 'F'},
    },
  },
);

TrajectoryEnvelope _envelope({
  required String recordType,
  required int seq,
  required String stepPath,
  required Map<String, Object?> payload,
}) => TrajectoryEnvelope(
  seq: seq,
  epochSeq: seq,
  recordId: '01JAAAAAAAAAAAAAAAAAAAAA${seq.toString().padLeft(2, '0')}',
  idemKey: 'f' * 64,
  idemKeyText: '$recordType|$seq',
  family: TrajectoryFamily.verification,
  recordType: recordType,
  occurredAt: DateTime.utc(2026, 9, 3),
  recordedAt: DateTime.utc(2026, 9, 3),
  station: 'test',
  authorityId: 'test/1',
  bootEpoch: 1,
  source: 'test',
  payload: payload,
  sessionId: 'session-1',
  round: 2,
  stepPath: stepPath,
  stepRound: 1,
  incarnation: 0,
  commitSha: recordType == 'verify.verdict.recorded' ? 'abc' : null,
);

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);

  final StationCommandResult result;
  int calls = 0;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    calls++;
    return result;
  }
}

final class _Reader implements TrajectoryLogReader {
  _Reader(this.rows);

  final List<TrajectoryEnvelope> rows;
  bool closed = false;

  @override
  Future<List<TrajectoryEnvelope>> rowsForSubject(
    String subject, {
    int limit = defaultReadLimit,
  }) async => rows.take(limit).toList();

  @override
  Future<SubjectRecords> allRecordsForSubject(
    String subject, {
    int ceiling = completeReadCeiling,
  }) async => SubjectRecords(records: rows.take(ceiling).toList());

  @override
  Future<SubjectRecords> recordsInWindow({
    DateTime? since,
    int? bootEpoch,
    int ceiling = completeReadCeiling,
  }) async => SubjectRecords(records: rows.take(ceiling).toList());

  @override
  Future<List<String>> sessions({int limit = defaultReadLimit}) async => const [
    'session-1',
  ];

  @override
  Future<FoldStaleness?> foldStaleness() async => null;

  @override
  Future<void> close() async {
    closed = true;
  }
}
