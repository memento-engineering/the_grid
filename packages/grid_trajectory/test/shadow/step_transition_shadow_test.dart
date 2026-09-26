/// The step lane's golden cases: what it compares, what it refuses to
/// compare, and which named gap each divergence shape earns.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

const String _session = 'tranquility-5xk';

TrajectoryEnvelope _transition({
  required int seq,
  required String stepPath,
  required String state,
  int round = 0,
  int stepRound = 0,
  int incarnation = 0,
  String? attemptId,
  String? cause,
  DateTime? cooldownUntil,
}) => envelope(
  recordType: 'step.transition',
  family: TrajectoryFamily.step,
  seq: seq,
  sessionId: _session,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  incarnation: incarnation,
  attemptId: attemptId,
  payload: {
    'state': state,
    if (cause != null) 'cause': cause,
    if (cooldownUntil != null)
      'cooldown_until': cooldownUntil.toIso8601String(),
  },
);

const String _attemptB = '01J8ATTEMPT000000000000002';

TrajectoryEnvelope _started({
  required int seq,
  required String stepPath,
  required String attemptId,
}) => envelope(
  recordType: 'attempt.process.started',
  family: TrajectoryFamily.attempt,
  seq: seq,
  sessionId: _session,
  attemptId: attemptId,
  incarnation: 1,
  stepPath: stepPath,
  payload: const {'pid': 4242, 'pgid': 4242},
);

SubjectRecords _records(List<TrajectoryEnvelope> rows) =>
    SubjectRecords(records: rows);

class _ScriptedSteps implements LegacyStepReader {
  _ScriptedSteps(this.views);

  final List<LegacyStepView> views;

  @override
  Future<List<LegacyStepView>> stepViews(String sessionId) async =>
      sessionId == _session ? views : const [];
}

/// A lane whose classifier is the default; the tests read the classification
/// off the emitted mismatch rather than calling the function directly, so the
/// wiring is exercised too.
StepTransitionShadow _lane(List<LegacyStepView> legacy) =>
    StepTransitionShadow(_ScriptedSteps(legacy));

void main() {
  test('agreement on state and cooldown is zero mismatches', () async {
    final cooldown = DateTime.utc(2026, 8, 31, 10, 15, 30);
    final result =
        await _lane([
          LegacyStepView(
            stepPath: 'build',
            state: 'failed',
            cooldownUntil: cooldown,
          ),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'running',
              attemptId: '01J8ATTEMPT000000000000001',
            ),
            _transition(
              seq: 2,
              stepPath: 'build',
              state: 'failed',
              attemptId: '01J8ATTEMPT000000000000001',
              cooldownUntil: cooldown,
            ),
          ]),
        );
    expect(result.mismatches, isEmpty);
    expect(result.isIncomplete, isFalse);
  });

  test('a step bead the fold never recorded is counted, and WITHOUT '
      'corroboration it is unexplained — the pending shape is named in '
      'the value', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
          const LegacyStepView(stepPath: 'review', state: 'pending'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'running',
              attemptId: '01J8ATTEMPT000000000000001',
            ),
          ]),
        );
    final row = result.mismatches.single;
    expect(row.field, 'step_presence');
    expect(row.stepPath, 'review');
    expect(row.legacyValue, 'present (pending, no process for path)');
    expect(row.foldValue, isNull);
    expect(row.classification, ShadowMismatchClass.unexplained);
    expect(row.basis, 'no corroboration supplied');
  });

  test('a step bead the fold never recorded WITH a crashed process for its '
      'path is non_atomic_crash — the join reaches the process record by '
      'step_path', () async {
    final records = [
      _transition(
        seq: 1,
        stepPath: 'build',
        state: 'running',
        attemptId: '01J8ATTEMPT000000000000001',
      ),
      _started(seq: 2, stepPath: 'review', attemptId: _attemptB),
    ];
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
          const LegacyStepView(stepPath: 'review', state: 'running'),
        ]).compare(
          sessionId: _session,
          records: _records(records),
          corroboration: ShadowCorroboration(
            attempts: {_attemptB: foldAttemptEvidence(_attemptB, records)},
          ),
        );
    final row = result.mismatches.single;
    expect(row.field, 'step_presence');
    expect(row.stepPath, 'review');
    expect(row.classification, ShadowMismatchClass.nonAtomicCrash);
    expect(row.basis, contains(_attemptB));
  });

  test('a REAPED molecule is nothing to compare, never a fold-side '
      'accusation', () async {
    // The legacy step beads are gone (reapMolecule survives Stage 1) while
    // the log keeps its rows forever. That is the ordinary end state, not
    // divergence — and reporting it would redden every finished session.
    final result = await _lane(const []).compare(
      sessionId: _session,
      records: _records([
        _transition(
          seq: 1,
          stepPath: 'build',
          state: 'complete',
          attemptId: '01J8ATTEMPT000000000000001',
        ),
      ]),
    );
    expect(result.mismatches, isEmpty);
  });

  test('a fold LAGGING the ledger on state is non_atomic_crash only when '
      'the row\'s attempt shows a crash; unexplained otherwise', () async {
    final records = [
      _transition(
        seq: 1,
        stepPath: 'build',
        state: 'running',
        attemptId: '01J8ATTEMPT000000000000001',
      ),
    ];
    final legacy = [const LegacyStepView(stepPath: 'build', state: 'complete')];
    final bare = await _lane(
      legacy,
    ).compare(sessionId: _session, records: _records(records));
    final row = bare.mismatches.single;
    expect(row.field, 'step_state');
    expect(row.legacyValue, 'complete');
    expect(row.foldValue, 'running');
    expect(row.classification, ShadowMismatchClass.unexplained);

    final corroborated = await _lane(legacy).compare(
      sessionId: _session,
      records: _records(records),
      corroboration: ShadowCorroboration(
        attempts: {
          '01J8ATTEMPT000000000000001': const AttemptEvidence(
            attemptId: '01J8ATTEMPT000000000000001',
            startedSeq: 1,
          ),
        },
      ),
    );
    expect(
      corroborated.mismatches.single.classification,
      ShadowMismatchClass.nonAtomicCrash,
    );
    expect(corroborated.mismatches.single.basis, contains('started'));
  });

  test('a fold AHEAD of the ledger on state stays unexplained and blocks the '
      'cut', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'complete',
              attemptId: '01J8ATTEMPT000000000000001',
            ),
          ]),
        );
    expect(
      result.mismatches.single.classification,
      ShadowMismatchClass.unexplained,
    );
  });

  test('a step the ledger says RAN with no attempt on the fold row is '
      'stop-races-spawn', () async {
    // The named gap: the provider killed the process before emitting
    // sessionStarted, so the process family produced zero records while the
    // step-bead write went through.
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(seq: 1, stepPath: 'build', state: 'running'),
          ]),
        );
    final row = result.mismatches.single;
    expect(row.field, 'step_attempt');
    expect(row.legacyValue, 'ran');
    expect(row.foldValue, isNull);
    expect(row.classification, ShadowMismatchClass.stopRacesSpawn);
    expect(row.basis, contains('no attempt on the fold row'));
  });

  test('a PENDING step with no attempt is not a gap — nothing ran '
      'yet', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'pending'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(seq: 1, stepPath: 'build', state: 'pending'),
          ]),
        );
    expect(result.mismatches, isEmpty);
  });

  test('a step bead with NO fine state compares nothing on the state '
      'axis', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: null),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(seq: 1, stepPath: 'build', state: 'running'),
          ]),
        );
    expect(result.mismatches, isEmpty);
  });

  test('cooldown compares at whole seconds — sub-second is a carrier '
      'artifact', () async {
    final result =
        await _lane([
          LegacyStepView(
            stepPath: 'build',
            state: 'failed',
            cooldownUntil: DateTime.utc(2026, 8, 31, 10, 15, 30),
          ),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'failed',
              attemptId: '01J8ATTEMPT000000000000001',
              cooldownUntil: DateTime.utc(2026, 8, 31, 10, 15, 30, 742, 19),
            ),
          ]),
        );
    expect(result.mismatches, isEmpty);
  });

  test(
    'a real cooldown divergence is reported and stays unexplained',
    () async {
      final result =
          await _lane([
            LegacyStepView(
              stepPath: 'build',
              state: 'failed',
              cooldownUntil: DateTime.utc(2026, 8, 31, 10, 15, 30),
            ),
          ]).compare(
            sessionId: _session,
            records: _records([
              _transition(
                seq: 1,
                stepPath: 'build',
                state: 'failed',
                attemptId: '01J8ATTEMPT000000000000001',
                cooldownUntil: DateTime.utc(2026, 8, 31, 11, 15, 30),
              ),
            ]),
          );
      final row = result.mismatches.single;
      expect(row.field, 'cooldown_until');
      expect(row.classification, ShadowMismatchClass.unexplained);
    },
  );

  test('the LATEST step_round is the comparable row', () async {
    // A gate-cleared rearm bumps step_round; the one bead's current state
    // belongs to the successor, not the superseded predecessor.
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'gated',
              attemptId: '01J8ATTEMPT000000000000001',
            ),
            _transition(
              seq: 2,
              stepPath: 'build',
              state: 'running',
              stepRound: 1,
              cause: 'gate_cleared',
              attemptId: '01J8ATTEMPT000000000000002',
            ),
          ]),
        );
    expect(result.mismatches, isEmpty);
  });

  test('a banked gate-resume predecessor-after-successor stream is the '
      'uninstrumented-resume class', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'complete'),
        ]).compare(
          sessionId: _session,
          records: _records([
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'gated',
              attemptId: '01J8ATTEMPT000000000000001',
            ),
            _transition(
              seq: 2,
              stepPath: 'build',
              stepRound: 1,
              state: 'pending',
              cause: 'gate_cleared',
            ),
            _transition(
              seq: 3,
              stepPath: 'build',
              state: 'complete',
              attemptId: '01J8ATTEMPT000000000000002',
            ),
          ]),
        );

    expect(result.mismatches, hasLength(2));
    expect(result.mismatches.map((row) => row.field).toSet(), {
      'step_state',
      'step_attempt',
    });
    expect(result.mismatches.map((row) => row.seq).toSet(), {2});
    expect(result.mismatches.map((row) => row.classification).toSet(), {
      ShadowMismatchClass.uninstrumentedResume,
    });
    expect(
      result.mismatches.map((row) => row.basis).toSet().single,
      contains('predecessor step_round 0'),
    );
  });

  test('--round scopes the comparable rows', () async {
    final rows = [
      _transition(
        seq: 1,
        stepPath: 'build',
        state: 'complete',
        attemptId: '01J8ATTEMPT000000000000001',
      ),
      _transition(
        seq: 2,
        stepPath: 'build',
        state: 'running',
        round: 1,
        attemptId: '01J8ATTEMPT000000000000002',
      ),
    ];
    final lane = _lane([
      const LegacyStepView(stepPath: 'build', state: 'running'),
    ]);
    expect(
      (await lane.compare(
        sessionId: _session,
        records: _records(rows),
        round: 1,
      )).mismatches,
      isEmpty,
    );
    // Scoped to round 0 the comparable row is the completed one, which the
    // bead's `running` no longer matches.
    expect(
      (await lane.compare(
        sessionId: _session,
        records: _records(rows),
        round: 0,
      )).mismatches.single.field,
      'step_state',
    );
  });

  test('a truncated stream is INCOMPLETE, never a folded prefix', () async {
    final result =
        await _lane([
          const LegacyStepView(stepPath: 'build', state: 'running'),
        ]).compare(
          sessionId: _session,
          records: const SubjectRecords(records: [], truncatedAt: 1),
        );
    expect(result.isIncomplete, isTrue);
    expect(result.mismatches, isEmpty);
    expect(result.incompleteReason, contains('fold of a prefix'));
  });

  test('§9 unshadowable fields are refused AT EMIT', () async {
    expect(
      () => _lane(const []).buildMismatch(
        sessionId: _session,
        stepPath: 'build',
        field: 'incarnation',
        legacyValue: '1',
        foldValue: '0',
        seq: 7,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('the lane compares no field §9 excludes', () {
    expect(
      _lane(const []).comparableFields.intersection(unshadowableMismatchFields),
      isEmpty,
    );
  });

  // ── CUT DISCIPLINE — THE RETIRED LEGACY CARRIER (tg-ul2v) ───────────────
  //
  // Under `discipline: cut` the step bead's running write and its
  // gate-cleared rearm write are retired, so these pairs have no legacy
  // oracle. They are printed as `legacy_carrier_retired` only with the
  // session's cut stamp AND the fold's own proof; everything else keeps its
  // ordinary classification.
  group('cut discipline — the retired legacy carrier (tg-ul2v)', () {
    const attemptA = '01J8ATTEMPT000000000000001';

    Future<List<ShadowMismatch>> compare(
      LegacyStepView legacy,
      List<TrajectoryEnvelope> records,
    ) async => (await _lane([
      legacy,
    ]).compare(sessionId: _session, records: _records(records))).mismatches;

    final rearmed = [
      _transition(
        seq: 1,
        stepPath: 'route',
        state: 'running',
        attemptId: attemptA,
      ),
      _transition(
        seq: 2,
        stepPath: 'route',
        state: 'gated',
        attemptId: attemptA,
      ),
      _transition(
        seq: 3,
        stepPath: 'route',
        stepRound: 1,
        state: 'pending',
        cause: 'gate_cleared',
      ),
    ];

    test('bead pending / fold running is the retired start write', () async {
      final rows = await compare(
        const LegacyStepView(
          stepPath: 'build',
          state: 'pending',
          cutDiscipline: true,
        ),
        [
          _transition(
            seq: 1,
            stepPath: 'build',
            state: 'running',
            attemptId: attemptA,
          ),
        ],
      );
      final row = rows.single;
      expect(row.field, 'step_state');
      expect(row.legacyValue, 'pending');
      expect(row.foldValue, 'running');
      expect(row.seq, 1);
      expect(row.classification, ShadowMismatchClass.legacyCarrierRetired);
      expect(row.classification.isUnshadowable, isTrue);
      expect(row.classification.isNamedGap, isFalse);
      expect(row.basis, contains('retired the step bead running write'));
    });

    test('bead gated / fold pending on the rearmed rung is the retired rearm '
        'write — and the bead\'s stale "ran" rides the same carrier', () async {
      final rows = await compare(
        const LegacyStepView(
          stepPath: 'route',
          state: 'gated',
          cutDiscipline: true,
        ),
        rearmed,
      );
      expect(rows.map((row) => row.field).toSet(), {
        'step_state',
        'step_attempt',
      });
      for (final row in rows) {
        expect(row.classification, ShadowMismatchClass.legacyCarrierRetired);
        expect(row.basis, contains('rearm write'));
        expect(row.seq, 3);
      }
    });

    test('bead gated / fold running on the rearmed rung (the re-run) is the '
        'retired rearm AND start writes', () async {
      final rows = await compare(
        const LegacyStepView(
          stepPath: 'route',
          state: 'gated',
          cutDiscipline: true,
        ),
        [
          ...rearmed,
          _transition(
            seq: 4,
            stepPath: 'route',
            stepRound: 1,
            state: 'running',
            attemptId: '01J8ATTEMPT000000000000009',
          ),
        ],
      );
      final row = rows.single;
      expect(row.field, 'step_state');
      expect(row.foldValue, 'running');
      expect(row.classification, ShadowMismatchClass.legacyCarrierRetired);
      expect(row.basis, contains('rearm and running writes'));
    });

    test('bead failed / fold running at the failure\'s bumped incarnation is '
        'the retired restart start write', () async {
      final rows = await compare(
        const LegacyStepView(
          stepPath: 'build',
          state: 'failed',
          cutDiscipline: true,
        ),
        [
          _transition(
            seq: 1,
            stepPath: 'build',
            state: 'running',
            attemptId: attemptA,
          ),
          _transition(
            seq: 2,
            stepPath: 'build',
            state: 'failed',
            incarnation: 1,
            attemptId: attemptA,
          ),
          _transition(
            seq: 3,
            stepPath: 'build',
            state: 'running',
            incarnation: 1,
            attemptId: '01J8ATTEMPT000000000000009',
          ),
        ],
      );
      expect(
        rows.single.classification,
        ShadowMismatchClass.legacyCarrierRetired,
      );
      expect(rows.single.basis, contains('incarnation 1'));
    });

    test(
      'WITHOUT the cut stamp the same pairs keep their ordinary class',
      () async {
        final ahead = await compare(
          const LegacyStepView(stepPath: 'build', state: 'pending'),
          [
            _transition(
              seq: 1,
              stepPath: 'build',
              state: 'running',
              attemptId: attemptA,
            ),
          ],
        );
        expect(ahead.single.classification, ShadowMismatchClass.unexplained);
        final gated = await compare(
          const LegacyStepView(stepPath: 'route', state: 'gated'),
          rearmed,
        );
        expect(
          gated.map((row) => row.classification),
          isNot(contains(ShadowMismatchClass.legacyCarrierRetired)),
        );
      },
    );

    test('NEGATIVE SPACE — a cut pair without the fold\'s proof is not the '
        'class', () async {
      // A rung-1 pending with NO gate-cleared link to its predecessor.
      final unlinked = await compare(
        const LegacyStepView(
          stepPath: 'route',
          state: 'gated',
          cutDiscipline: true,
        ),
        [
          _transition(
            seq: 1,
            stepPath: 'route',
            state: 'gated',
            attemptId: attemptA,
          ),
          _transition(
            seq: 2,
            stepPath: 'route',
            stepRound: 1,
            state: 'pending',
          ),
        ],
      );
      expect(
        unlinked.map((row) => row.classification),
        isNot(contains(ShadowMismatchClass.legacyCarrierRetired)),
      );
      // A failed bead over a fold still at the PRE-failure incarnation: the
      // failure's append is what is missing.
      final lostFailure = await compare(
        const LegacyStepView(
          stepPath: 'build',
          state: 'failed',
          cutDiscipline: true,
        ),
        [
          _transition(
            seq: 1,
            stepPath: 'build',
            state: 'running',
            attemptId: attemptA,
          ),
        ],
      );
      expect(
        lostFailure.single.classification,
        ShadowMismatchClass.unexplained,
      );
      // A bead AHEAD of the fold: the terminal write is never retired.
      final ahead = await compare(
        const LegacyStepView(
          stepPath: 'build',
          state: 'complete',
          cutDiscipline: true,
        ),
        [
          _transition(
            seq: 1,
            stepPath: 'build',
            state: 'running',
            attemptId: attemptA,
          ),
        ],
      );
      expect(
        ahead.single.classification,
        isNot(ShadowMismatchClass.legacyCarrierRetired),
      );
    });
  });
}
