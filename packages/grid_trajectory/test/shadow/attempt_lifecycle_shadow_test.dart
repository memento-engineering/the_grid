/// Golden compare cases for the §9 Family-1 comparator: an agreeing pair is
/// zero mismatches, each divergent field is exactly its mismatch, the
/// allow-list classifies the non-atomic-crash shape, and the unshadowable
/// facts can never appear as mismatch fields.
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
      unknownReason:
          outcome == TerminalOutcome.unknown ? 'write_timeout' : null,
    ),
  ];

  const agreeingLegacy = LegacySessionView(
    sessionId: 's1',
    workBeadId: 'tg-9abc',
    closed: true,
    completed: true,
  );

  Future<List<ShadowMismatch>> compare({
    required List<TrajectoryEnvelope> records,
    LegacySessionView? legacy,
    String sessionId = 's1',
    int? round,
  }) => AttemptLifecycleShadow(
    _ScriptedLegacy({if (legacy != null) legacy.sessionId: legacy}),
  ).compare(sessionId: sessionId, records: records, round: round);

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

    test('closed with NO marker is outcome-indeterminate: not compared',
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
    });

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

    test('held', () async {
      final mismatches = await compare(
        records: closedLifecycle(),
        legacy: const LegacySessionView(
          sessionId: 's1',
          workBeadId: 'tg-9abc',
          closed: true,
          completed: true,
          held: true,
          heldReason: 'escalated',
        ),
      );
      final only = mismatches.single;
      expect(only.field, 'held');
      expect(only.legacyValue, 'true');
      expect(only.foldValue, 'false');
      expect(only.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('presence: ledger session the fold never saw', () async {
      final mismatches = await compare(records: const [], legacy: agreeingLegacy);
      final only = mismatches.single;
      expect(only.field, 'presence');
      expect(only.legacyValue, 'present');
      expect(only.foldValue, isNull);
      expect(only.classification, ShadowMismatchClass.nonAtomicCrash);
    });

    test('presence: fold session the ledger never saw — unexplained',
        () async {
      final mismatches = await compare(records: closedLifecycle(), legacy: null);
      final only = mismatches.single;
      expect(only.field, 'presence');
      expect(only.legacyValue, isNull);
      expect(only.foldValue, 'present');
      expect(only.classification, ShadowMismatchClass.unexplained);
    });
  });

  test('an operator-named round scopes out sessions on other rounds',
      () async {
    final mismatches = await compare(
      records: closedLifecycle(outcome: TerminalOutcome.failed),
      legacy: agreeingLegacy,
      round: 3,
    );
    expect(mismatches, isEmpty);
  });

  test('a classifier can only classify, never suppress', () async {
    ShadowMismatchClass allowEverything(String f, String? l, String? r) =>
        ShadowMismatchClass.nonAtomicCrash;
    final shadow = AttemptLifecycleShadow(
      _ScriptedLegacy(const {'s1': agreeingLegacy}),
      classifier: allowEverything,
    );
    final mismatches = await shadow.compare(
      sessionId: 's1',
      records: closedLifecycle(outcome: TerminalOutcome.failed),
    );
    expect(mismatches.single.classification, ShadowMismatchClass.nonAtomicCrash);
  });

  test('unshadowable fields are refused at emit (comparator self-check)',
      () async {
    // The public seam cannot produce one (the sets are disjoint, pinned
    // above); the refusal itself is pinned through the classifier's view of
    // the fields it is shown.
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
      records: closedLifecycle(outcome: TerminalOutcome.failed),
    );
    expect(seen, isNotEmpty);
    expect(seen.intersection(unshadowableMismatchFields), isEmpty);
  });
}
