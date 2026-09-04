/// The Family-5 delta function, per record type (§6 rows 14–16 / schema §2
/// F5): what each step record does to P2 on the TWO-ladder key — and the
/// step_round chain rule, which writes the predecessor's
/// `superseded_by_step_round` on EVERY bump (step.superseded AND the
/// gate-cleared rearm).
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

void main() {
  final startedAt = DateTime.utc(2026, 8, 31, 10);

  TrajectoryEnvelope transition({
    int seq = 1,
    String state = 'running',
    int stepRound = 0,
    int incarnation = 0,
    String? cause,
    Map<String, Object?> extra = const {},
  }) => envelope(
    recordType: 'step.transition',
    family: TrajectoryFamily.step,
    seq: seq,
    sessionId: 'tranquility-1',
    round: 1,
    stepPath: 'work.build',
    stepRound: stepRound,
    incarnation: incarnation,
    attemptId: '01J8ATTEMPT000000000000002',
    payload: {'state': state, if (cause != null) 'cause': cause, ...extra},
  );

  group('stepCursorDeltaFor', () {
    test('step.transition upserts on the two-ladder key with exactly the '
        'carried columns', () {
      final delta = stepCursorDeltaFor(
        transition(
          state: 'running',
          extra: {'started_at': startedAt.toIso8601String()},
        ),
      );
      final upsert = delta! as StepCursorUpsert;
      expect(upsert.key, (
        sessionId: 'tranquility-1',
        round: 1,
        stepPath: 'work.build',
        stepRound: 0,
      ));
      expect(upsert.columns, {
        'state': 'running',
        'incarnation': 0,
        'attempt_id': '01J8ATTEMPT000000000000002',
        'started_at': startedAt,
      });
      expect(upsert.chainPredecessorStepRound, isNull);
    });

    test('a failure carries failure_class/cooldown/restart_budget/result', () {
      final cooldown = DateTime.utc(2026, 8, 31, 10, 5);
      final delta = stepCursorDeltaFor(
        transition(
          state: 'failed',
          extra: {
            'failure_class': 'store_unavailable',
            'cooldown_until': cooldown.toIso8601String(),
            'restart_budget': 2,
            'result': {'rc': 1},
          },
        ),
      );
      final upsert = delta! as StepCursorUpsert;
      expect(upsert.columns['state'], 'failed');
      expect(upsert.columns['failure_class'], 'store_unavailable');
      expect(upsert.columns['cooldown_until'], cooldown);
      expect(upsert.columns['restart_budget'], 2);
      expect(upsert.columns['result'], {'rc': 1});
    });

    test('the infra class rounds through the wire and reaches the fold', () {
      expect(StepFailureClass.infra.wire, 'infra');
      expect(StepFailureClass.fromWire('infra'), StepFailureClass.infra);
      expect(StepFailureClass.noResult.wire, 'no_result');
      expect(StepFailureClass.invalidResult.wire, 'invalid_result');
      expect(StepFailureClass.fromWire('no_result'), StepFailureClass.noResult);
      expect(
        StepFailureClass.fromWire('invalid_result'),
        StepFailureClass.invalidResult,
      );
      final delta = stepCursorDeltaFor(
        transition(state: 'failed', extra: {'failure_class': 'infra'}),
      );
      expect((delta! as StepCursorUpsert).columns['failure_class'], 'infra');
    });

    test('an invalid_result transition folds its class', () {
      final delta = stepCursorDeltaFor(
        transition(state: 'failed', extra: {'failure_class': 'invalid_result'}),
      );
      expect(
        (delta! as StepCursorUpsert).columns['failure_class'],
        'invalid_result',
      );
    });

    test('the gated half is a plain state on the cursor', () {
      final delta = stepCursorDeltaFor(transition(state: 'gated'));
      expect((delta! as StepCursorUpsert).columns['state'], 'gated');
    });

    test('a gate-cleared rearm at step_round N links predecessor N-1 — the '
        'chain rule\'s implicit half', () {
      final delta = stepCursorDeltaFor(
        transition(state: 'pending', stepRound: 2, cause: 'gate_cleared'),
      );
      final upsert = delta! as StepCursorUpsert;
      expect(upsert.stepRound, 2);
      expect(upsert.chainPredecessorStepRound, 1);
    });

    test('a gate-cleared transition at step_round 0 has no predecessor to '
        'link', () {
      final delta = stepCursorDeltaFor(
        transition(state: 'pending', cause: 'gate_cleared'),
      );
      expect((delta! as StepCursorUpsert).chainPredecessorStepRound, isNull);
    });

    test('a non-bump cause never claims a chain link', () {
      final delta = stepCursorDeltaFor(
        transition(state: 'running', stepRound: 2, cause: 'allocation'),
      );
      expect((delta! as StepCursorUpsert).chainPredecessorStepRound, isNull);
    });

    test('step.superseded is the explicit chain write — the successor row is '
        'NOT invented', () {
      final delta = stepCursorDeltaFor(
        envelope(
          recordType: 'step.superseded',
          family: TrajectoryFamily.step,
          sessionId: 'tranquility-1',
          round: 1,
          stepPath: 'work.build',
          stepRound: 3,
          payload: const {
            'cause': 'budget',
            'budget_remaining': 1,
            'old_step_round': 2,
            'new_step_round': 3,
          },
        ),
      );
      final supersede = delta! as StepCursorSupersede;
      expect(supersede.oldStepRound, 2);
      expect(supersede.newStepRound, 3);
    });

    test('gate/molecule records produce NO P2 delta — the DDL is the letter '
        '(their fields are P4\'s / proj_step_edges\')', () {
      final noOps = [
        envelope(
          recordType: 'gate.opened',
          family: TrajectoryFamily.step,
          sessionId: 'tranquility-1',
          gateId: 'tg-9abc.gate.0',
          payload: const {'node': 'review'},
        ),
        envelope(
          recordType: 'gate.regated',
          family: TrajectoryFamily.step,
          sessionId: 'tranquility-1',
          gateId: 'tg-9abc.gate.0',
          payload: const {'regate_cycle': 1},
        ),
        envelope(
          recordType: 'gate.closed',
          family: TrajectoryFamily.step,
          sessionId: 'tranquility-1',
          gateId: 'tg-9abc.gate.0',
          payload: const {'close_cause': 'adjudicated', 'cycle': 0},
        ),
        envelope(
          recordType: 'molecule.poured',
          family: TrajectoryFamily.step,
          sessionId: 'tranquility-1',
          round: 1,
          payload: const {
            'formula': 'work',
            'graph': {'nodes': <Object?>[]},
            'node_count': 0,
            'graph_digest': 'd',
          },
        ),
      ];
      for (final record in noOps) {
        // Each envelope decodes to its REAL typed record (never an opaque
        // fallback) — the null delta is a modelled fact, not a decode miss.
        expect(
          TrajectoryCodec.decode(record),
          isNot(isA<OpaqueRecord>()),
          reason: '${record.recordType} must decode',
        );
        expect(
          stepCursorDeltaFor(record),
          isNull,
          reason: '${record.recordType} must not touch P2',
        );
      }
    });

    test('non-step families are refused at the door', () {
      expect(
        stepCursorDeltaFor(
          envelope(
            recordType: 'attempt.session.started',
            family: TrajectoryFamily.attempt,
            sessionId: 'tranquility-1',
            grantId: '01J8GRANT00000000000000001',
            payload: const {'rig': 'operator', 'model': 'molecule'},
          ),
        ),
        isNull,
      );
    });
  });

  group('stepCursorSqlFor (the incremental mode)', () {
    test('upsert renders the INSERT whose duplicate arm advances exactly the '
        'carried columns + last_seq', () {
      final delta =
          stepCursorDeltaFor(
                transition(
                  state: 'running',
                  extra: {'started_at': startedAt.toIso8601String()},
                ),
              )!
              as StepCursorUpsert;
      final statements = stepCursorSqlFor(delta, lastSeq: 9);
      final statement = statements.single;
      expect(statement.sql, startsWith('INSERT INTO proj_step_cursor'));
      expect(
        statement.sql,
        endsWith(
          'ON DUPLICATE KEY UPDATE state = :state, '
          'incarnation = :incarnation, attempt_id = :attempt_id, '
          'started_at = :started_at, last_seq = :last_seq',
        ),
      );
      expect(statement.params['session_id'], 'tranquility-1');
      expect(statement.params['round'], 1);
      expect(statement.params['step_path'], 'work.build');
      expect(statement.params['step_round'], 0);
      expect(statement.params['state'], 'running');
      expect(statement.params['started_at'], '2026-08-31 10:00:00.000000');
      expect(statement.params['superseded_by_step_round'], isNull);
      expect(statement.params['last_seq'], 9);
    });

    test('the result column renders as encoded JSON', () {
      final delta =
          stepCursorDeltaFor(
                transition(
                  state: 'complete',
                  extra: {
                    'result': {'rc': 0},
                  },
                ),
              )!
              as StepCursorUpsert;
      final statement = stepCursorSqlFor(delta, lastSeq: 3).single;
      expect(statement.params['result'], '{"rc":0}');
    });

    test('a rearm renders TWO statements — the upsert plus the predecessor '
        'chain write at the same seq', () {
      final delta =
          stepCursorDeltaFor(
                transition(
                  state: 'pending',
                  stepRound: 2,
                  cause: 'gate_cleared',
                ),
              )!
              as StepCursorUpsert;
      final statements = stepCursorSqlFor(delta, lastSeq: 12);
      expect(statements, hasLength(2));
      final chain = statements[1];
      expect(chain.sql, startsWith('UPDATE proj_step_cursor'));
      expect(chain.sql, contains('superseded_by_step_round'));
      expect(chain.params, {
        'superseded_by_step_round': 2,
        'last_seq': 12,
        'session_id': 'tranquility-1',
        'round': 1,
        'step_path': 'work.build',
        'step_round': 1,
      });
    });

    test('step.superseded renders the chain write alone', () {
      final statements = stepCursorSqlFor(
        const StepCursorSupersede(
          sessionId: 'tranquility-1',
          round: 1,
          stepPath: 'work.build',
          oldStepRound: 0,
          newStepRound: 1,
        ),
        lastSeq: 5,
      );
      final statement = statements.single;
      expect(statement.params['step_round'], 0, reason: 'keys the PREDECESSOR');
      expect(statement.params['superseded_by_step_round'], 1);
    });
  });

  group('applyStepCursorDelta (the replay mode, same semantics)', () {
    test('the two-ladder key separates step_rounds: a bump births a NEW row '
        'and the predecessor keeps its history', () {
      final rows = <StepCursorKey, StepCursorRow>{};
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(transition(state: 'running', seq: 1))!,
        lastSeq: 1,
      );
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(transition(state: 'gated', seq: 2))!,
        lastSeq: 2,
      );
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(
          transition(state: 'pending', stepRound: 1, cause: 'gate_cleared'),
        )!,
        lastSeq: 3,
      );
      expect(rows, hasLength(2), reason: 'one row per step_round');
      final predecessor =
          rows[(
            sessionId: 'tranquility-1',
            round: 1,
            stepPath: 'work.build',
            stepRound: 0,
          )]!;
      expect(predecessor.state, 'gated', reason: 'history is never rewritten');
      expect(
        predecessor.supersededByStepRound,
        1,
        reason: 'the rearm chain-link landed on the predecessor',
      );
      expect(predecessor.lastSeq, 3);
      final successor =
          rows[(
            sessionId: 'tranquility-1',
            round: 1,
            stepPath: 'work.build',
            stepRound: 1,
          )]!;
      expect(successor.state, 'pending');
      expect(successor.supersededByStepRound, isNull);
    });

    test('step.superseded links the predecessor; an absent predecessor '
        'matches 0 rows', () {
      final rows = <StepCursorKey, StepCursorRow>{};
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(transition(state: 'failed'))!,
        lastSeq: 1,
      );
      applyStepCursorDelta(
        rows,
        const StepCursorSupersede(
          sessionId: 'tranquility-1',
          round: 1,
          stepPath: 'work.build',
          oldStepRound: 0,
          newStepRound: 1,
        ),
        lastSeq: 2,
      );
      expect(rows.values.single.supersededByStepRound, 1);
      // A chain write for a path with no row: nothing invented.
      applyStepCursorDelta(
        rows,
        const StepCursorSupersede(
          sessionId: 'tranquility-1',
          round: 1,
          stepPath: 'work.ghost',
          oldStepRound: 0,
          newStepRound: 1,
        ),
        lastSeq: 3,
      );
      expect(rows, hasLength(1));
    });

    test('a later transition advances exactly its carried columns', () {
      final rows = <StepCursorKey, StepCursorRow>{};
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(
          transition(
            state: 'running',
            extra: {'started_at': startedAt.toIso8601String()},
          ),
        )!,
        lastSeq: 1,
      );
      applyStepCursorDelta(
        rows,
        stepCursorDeltaFor(
          transition(
            state: 'complete',
            extra: {
              'completed_at': startedAt
                  .add(const Duration(minutes: 2))
                  .toIso8601String(),
              'result': {'rc': 0},
            },
          ),
        )!,
        lastSeq: 2,
      );
      final row = rows.values.single;
      expect(row.state, 'complete');
      expect(row.startedAt, startedAt, reason: 'untouched columns survive');
      expect(row.completedAt, startedAt.add(const Duration(minutes: 2)));
      expect(row.result, {'rc': 0});
      expect(row.lastSeq, 2);
    });

    test('applying an unknown column is a fold bug and throws', () {
      final row = StepCursorRow(
        sessionId: 's',
        round: 0,
        stepPath: 'p',
        stepRound: 0,
        state: 'running',
        incarnation: 0,
        lastSeq: 1,
      );
      expect(
        () => row.applying(const {'ghost': 1}, lastSeq: 2),
        throwsArgumentError,
      );
    });
  });
}
