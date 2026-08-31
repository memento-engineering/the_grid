/// Golden compare cases for the §9 Family-1 comparator: an agreeing pair is
/// zero mismatches, each divergent field is exactly its mismatch, the
/// allow-list classifies the non-atomic-crash shape, a truncated stream is
/// `incomplete` rather than clean, presence survives `--round` scoping, and
/// the unshadowable facts are refused at emit.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

class _ScriptedLegacy implements LegacySessionReader {
  _ScriptedLegacy(this.views);

  final Map<String, LegacySessionView> views;

  @override
  Future<LegacySessionView?> sessionView(String sessionId) async =>
      views[sessionId];
}

void main() {
  const attempt = '01J8ATTEMPT000000000000002';

  List<TrajectoryEnvelope> closedLifecycle({
    String sessionId = 's1',
    TerminalOutcome outcome = TerminalOutcome.succeeded,
  }) => [
    envelope(
      recordType: 'attempt.session.started',
      family: TrajectoryFamily.attempt,
      seq: 1,
      sessionId: sessionId,
      workBeadId: 'tg-9abc',
      grantId: '01J8GRANT00000000000000001',
      payload: const {'rig': 'operator', 'model': 'molecule'},
    ),
    envelope(
      recordType: 'attempt.terminal',
      family: TrajectoryFamily.attempt,
      seq: 2,
      sessionId: sessionId,
      attemptId: attempt,
      outcome: outcome,
      unknownReason: outcome == TerminalOutcome.unknown
          ? 'write_timeout'
          : null,
    ),
  ];

  const agreeingLegacy = LegacySessionView(
    sessionId: 's1',
    workBeadId: 'tg-9abc',
    closed: true,
    completed: true,
  );

  Future<ShadowCompareResult> compareResult({
    required List<TrajectoryEnvelope> records,
    LegacySessionView? legacy,
    String sessionId = 's1',
    int? round,
    int? truncatedAt,
  }) =>
      AttemptLifecycleShadow(
        _ScriptedLegacy({if (legacy != null) legacy.sessionId: legacy}),
      ).compare(
        sessionId: sessionId,
        records: SubjectRecords(records: records, truncatedAt: truncatedAt),
        round: round,
      );

  Future<List<ShadowMismatch>> compare({
    required List<TrajectoryEnvelope> records,
    LegacySessionView? legacy,
    String sessionId = 's1',
    int? round,
  }) async => (await compareResult(
    records: records,
    legacy: legacy,
    sessionId: sessionId,
    round: round,
  )).mismatches;

  test('the comparable set never intersects the unshadowable facts', () {
    final shadow = AttemptLifecycleShadow(_ScriptedLegacy(const {}));
    expect(
      shadow.comparableFields.intersection(unshadowableMismatchFields),
      isEmpty,
    );
    expect(shadow.unavailableReason, isNull);
  });

  test('agreeing pair -> zero mismatches', () async {
    expect(
      await compare(records: closedLifecycle(), legacy: agreeingLegacy),
      isEmpty,
    );
  });

  test('both sides blind -> zero mismatches (nothing to certify)', () async {
    expect(await compare(records: const [], legacy: null), isEmpty);
  });

  group('each divergent field -> exactly its mismatch', () {
    test('work_bead_id', () async {
      final mismatches = await compare(
        records: closedLifecycle(),
        legacy: const LegacySessionView(
          sessionId: 's1',
          workBeadId: 'tg-OTHER',
          closed: true,
          completed: true,
        ),
      );
      final only = mismatches.single;
      expect(only.field, 'work_bead_id');
      expect(only.legacyValue, 'tg-OTHER');
      expect(only.foldValue, 'tg-9abc');
      expect(only.seq, 2);
      expect(only.classification, ShadowMismatchClass.unexplained);
    });

    test('status (fold lagging) — classified non_atomic_crash', () async {
      final mismatches = await compare(
        // Only the start reached the trajectory; the ledger already closed.
        records: closedLifecycle().sublist(0, 1),
        legacy: agreeingLegacy,
      );
      expect(mismatches, hasLength(2)); // status + outcome, both fold-lag
      final status = mismatches.singleWhere((m) => m.field == 'status');
      expect(status.legacyValue, 'closed');
      expect(status.foldValue, 'open');
      expect(status.classification, ShadowMismatchClass.nonAtomicCrash);
      final outcome = mismatches.singleWhere((m) => m.field == 'outcome');
      expect(outcome.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('outcome (both terminal, disagreeing) — unexplained', () async {
      final mismatches = await compare(
        records: closedLifecycle(outcome: TerminalOutcome.failed),
        legacy: agreeingLegacy,
      );
      final only = mismatches.single;
      expect(only.field, 'outcome');
      expect(only.legacyValue, 'succeeded');
      expect(only.foldValue, 'failed');
      expect(only.classification, ShadowMismatchClass.unexplained);
    });

    test('a voided legacy key expects the lost outcome', () async {
      final mismatches = await compare(
        records: closedLifecycle(outcome: TerminalOutcome.lost),
        legacy: const LegacySessionView(
          sessionId: 's1',
          workBeadId: 'tg-9abc',
          closed: true,
          voided: true,
        ),
      );
      expect(mismatches, isEmpty);
    });

    test(
      'closed with NO marker is outcome-indeterminate: not compared',
      () async {
        final mismatches = await compare(
          records: closedLifecycle(outcome: TerminalOutcome.failed),
          legacy: const LegacySessionView(
            sessionId: 's1',
            workBeadId: 'tg-9abc',
            closed: true,
          ),
        );
        expect(mismatches, isEmpty);
      },
    );

    test('round (a retired #rN key names one)', () async {
      final mismatches = await compare(
        records: closedLifecycle(),
        legacy: const LegacySessionView(
          sessionId: 's1',
          workBeadId: 'tg-9abc',
          closed: true,
          completed: true,
          round: 2,
        ),
      );
      final only = mismatches.single;
      expect(only.field, 'round');
      expect(only.legacyValue, '2');
      expect(only.foldValue, '0');
    });

    test('held — a genuine divergence still mismatches', () async {
      // The legacy side declined rework; the trajectory carries no
      // rework_declined record and no escalated terminal, so the fold's
      // comparable-held really is false. That is the fold-lag shape.
      final mismatches = await compare(
        records: closedLifecycle(),
        legacy: const LegacySessionView(
          sessionId: 's1',
          workBeadId: 'tg-9abc',
          closed: true,
          completed: true,
          held: true,
          heldReason: 'rework_declined',
        ),
      );
      final only = mismatches.single;
      expect(only.field, 'held');
      expect(only.legacyValue, 'true');
      expect(only.foldValue, 'false');
      expect(only.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('presence: ledger session the fold never saw', () async {
      final mismatches = await compare(
        records: const [],
        legacy: agreeingLegacy,
      );
      final only = mismatches.single;
      expect(only.field, 'presence');
      expect(only.legacyValue, 'present');
      expect(only.foldValue, isNull);
      expect(only.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('presence: fold session the ledger never saw — unexplained', () async {
      final mismatches = await compare(
        records: closedLifecycle(),
        legacy: null,
      );
      final only = mismatches.single;
      expect(only.field, 'presence');
      expect(only.legacyValue, isNull);
      expect(only.foldValue, 'present');
      expect(only.classification, ShadowMismatchClass.unexplained);
    });
  });

  group('the held axis — legacy folds two axes into one (§6 row 4)', () {
    // grid_engine's session_projection.dart: humanHeld is escalation OR
    // rework_declined. P1 keeps the axes apart, so the disjunction is
    // re-derived on the COMPARATOR's fold side, never in P1.
    const escalatedLegacy = LegacySessionView(
      sessionId: 's1',
      workBeadId: 'tg-9abc',
      closed: true,
      held: true,
      heldReason: 'escalation',
    );

    test('an escalated session with legacy held=true compares clean', () async {
      final mismatches = await compare(
        records: closedLifecycle(outcome: TerminalOutcome.escalated),
        legacy: escalatedLegacy,
      );
      // No held mismatch, and no auto-classified non_atomic_crash standing in
      // for one: the escalated class is not a crash and must not be filed as
      // one.
      expect(mismatches, isEmpty);
    });

    test(
      'escalation does NOT widen P1 itself — the raw axis stays false',
      () async {
        final fold = foldSessionHeads(
          closedLifecycle(outcome: TerminalOutcome.escalated),
        );
        final row = fold.rows['s1']!;
        expect(row.outcome, TerminalOutcome.escalated);
        expect(row.held, isFalse); // rework_declined only, per §6 row 4
      },
    );

    test(
      'an escalated fold the ledger does NOT hold still mismatches',
      () async {
        final mismatches = await compare(
          records: closedLifecycle(outcome: TerminalOutcome.escalated),
          legacy: const LegacySessionView(
            sessionId: 's1',
            workBeadId: 'tg-9abc',
            closed: true,
          ),
        );
        final only = mismatches.single;
        expect(only.field, 'held');
        expect(only.legacyValue, 'false');
        expect(only.foldValue, 'true');
        // The fold ahead of the ledger is never the non-atomic crash shape.
        expect(only.classification, ShadowMismatchClass.unexplained);
      },
    );
  });

  group('a truncated stream is INCOMPLETE, never a clean run', () {
    test('the comparator refuses to fold a cut stream', () async {
      final result = await compareResult(
        records: closedLifecycle().sublist(0, 1),
        legacy: agreeingLegacy,
        truncatedAt: 1,
      );
      expect(result.isIncomplete, isTrue);
      expect(result.incompleteReason, contains('cut at 1 rows'));
      // NOT a mismatch list at all — neither an unearned zero nor an
      // unearned divergence.
      expect(result.mismatches, isEmpty);
    });

    test(
      'the same prefix read COMPLETE is a real (divergent) comparison',
      () async {
        // Same rows, no truncation flag: now the fold genuinely lags and the
        // comparator says so. This is what proves the incomplete outcome is
        // about the READ, not about the rows.
        final result = await compareResult(
          records: closedLifecycle().sublist(0, 1),
          legacy: agreeingLegacy,
        );
        expect(result.isIncomplete, isFalse);
        expect(result.mismatches, isNotEmpty);
      },
    );
  });

  group('--round scoping', () {
    test(
      'an operator-named round scopes out sessions on other rounds',
      () async {
        final mismatches = await compare(
          records: closedLifecycle(outcome: TerminalOutcome.failed),
          legacy: agreeingLegacy,
          round: 3,
        );
        expect(mismatches, isEmpty);
      },
    );

    test(
      'a fold-missing session still reports presence under --round',
      () async {
        // The fold has no row, so it has no round to filter on. Scoping this
        // out would let --round hide exactly the divergence §9 cares about.
        final mismatches = await compare(
          records: const [],
          legacy: agreeingLegacy,
          round: 3,
        );
        final only = mismatches.single;
        expect(only.field, 'presence');
        expect(only.legacyValue, 'present');
        expect(only.foldValue, isNull);
      },
    );

    test(
      'a legacy-missing session still reports presence under --round',
      () async {
        final mismatches = await compare(
          records: closedLifecycle(),
          legacy: null,
          round: 3,
        );
        final only = mismatches.single;
        expect(only.field, 'presence');
        expect(only.legacyValue, isNull);
        expect(only.foldValue, 'present');
      },
    );
  });

  test('a classifier can only classify, never suppress', () async {
    ShadowMismatchClass allowEverything(String f, String? l, String? r) =>
        ShadowMismatchClass.nonAtomicCrash;
    final shadow = AttemptLifecycleShadow(
      _ScriptedLegacy(const {'s1': agreeingLegacy}),
      classifier: allowEverything,
    );
    final result = await shadow.compare(
      sessionId: 's1',
      records: SubjectRecords(
        records: closedLifecycle(outcome: TerminalOutcome.failed),
      ),
    );
    expect(
      result.mismatches.single.classification,
      ShadowMismatchClass.nonAtomicCrash,
    );
  });

  group('unshadowable fields are refused AT EMIT', () {
    test('a comparator forced to emit one throws', () async {
      // The refusal is exercised, not argued about: this comparator is built
      // for the sole purpose of emitting a banned field, and the guard is
      // what stops it reaching the §9 report.
      final shadow = _BannedFieldShadow(
        _ScriptedLegacy(const {'s1': agreeingLegacy}),
      );
      await expectLater(
        shadow.compare(
          sessionId: 's1',
          records: const SubjectRecords(records: []),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('commit_sha'), contains('unshadowable')),
          ),
        ),
      );
    });

    test('every field the real comparator emits passes the guard', () async {
      final seen = <String>{};
      ShadowMismatchClass spy(String field, String? l, String? r) {
        seen.add(field);
        return ShadowMismatchClass.unexplained;
      }

      await AttemptLifecycleShadow(
        _ScriptedLegacy(const {'s1': agreeingLegacy}),
        classifier: spy,
      ).compare(
        sessionId: 's1',
        records: SubjectRecords(
          records: closedLifecycle(outcome: TerminalOutcome.failed),
        ),
      );
      expect(seen, isNotEmpty);
      expect(seen.intersection(unshadowableMismatchFields), isEmpty);
    });
  });
}

/// A comparator that tries to report a §9-unshadowable fact. It exists only to
/// drive [AttemptLifecycleShadow.buildMismatch]'s refusal — the shipped
/// comparator cannot reach it (its comparable set is disjoint from the banned
/// set, pinned above), and a guard nobody can reach is a guard nobody has
/// checked.
class _BannedFieldShadow extends AttemptLifecycleShadow {
  _BannedFieldShadow(super.legacy);

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async => ShadowCompareResult([
    buildMismatch(
      sessionId: sessionId,
      field: 'commit_sha',
      legacyValue: null,
      foldValue: 'deadbeef',
      seq: 7,
    ),
  ]);
}
