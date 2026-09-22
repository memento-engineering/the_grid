// The pure half: kind → durable class, and declaration → schedule.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _fast = Duration(seconds: 9);
const _slow = Duration(seconds: 31);
const _long = Duration(minutes: 5);

final class _StepRow implements StepCursorView {
  const _StepRow({
    this.stepState = 'failed',
    this.failureClass = 'infra',
    this.restartBudget = 0,
    this.incarnation = 3,
    this.attemptId = 'attempt-3',
    this.startedAt,
    this.cooldownUntil,
  });

  @override
  final String stepState;
  @override
  final String? failureClass;
  @override
  final int? restartBudget;
  @override
  final int incarnation;
  @override
  final String? attemptId;
  @override
  final DateTime? startedAt;
  @override
  final DateTime? cooldownUntil;
  @override
  String get sessionId => 'tranquility-ltkod1';
  @override
  int get round => 0;
  @override
  String get stepPath => 'tg-1/agent';
  @override
  int get stepRound => 0;
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  int get lastSeq => 7;
}

void main() {
  group('resolveFailureClass', () {
    test('work is work however fast it failed', () {
      for (final ranFor in <Duration?>[_fast, _slow, null]) {
        expect(
          resolveFailureClass(kind: CapabilityFailureKind.work, ranFor: ranFor),
          StepFailureClass.work,
        );
      }
    });

    test('a FAST noResult is infra; a slower one is no_result', () {
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.noResult,
          ranFor: _fast,
        ),
        StepFailureClass.infra,
      );
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.noResult,
          ranFor: _slow,
        ),
        StepFailureClass.noResult,
      );
      expect(
        resolveFailureClass(kind: CapabilityFailureKind.noResult, ranFor: null),
        StepFailureClass.noResult,
      );
    });

    test('an invalidResult is invalid_result even when fast', () {
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.invalidResult,
          ranFor: _fast,
        ),
        StepFailureClass.invalidResult,
      );
    });

    test('declared noResult is infra without changing inferred silence', () {
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.noResult,
          ranFor: _long,
          kindDeclared: true,
        ),
        StepFailureClass.infra,
      );
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.noResult,
          ranFor: _long,
        ),
        StepFailureClass.noResult,
      );
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.noResult,
          ranFor: _fast,
        ),
        StepFailureClass.infra,
      );
      expect(
        resolveFailureClass(
          kind: CapabilityFailureKind.invalidResult,
          ranFor: _long,
          kindDeclared: true,
        ),
        StepFailureClass.invalidResult,
      );
    });

    test('the wire values are additive and fit failure_class VARCHAR(24)', () {
      expect(StepFailureClass.noResult.wire, 'no_result');
      expect(StepFailureClass.invalidResult.wire, 'invalid_result');
      expect(
        StepFailureClass.fromWire('invalid_result'),
        StepFailureClass.invalidResult,
      );
      expect(StepFailureClass.invalidResult.wire.length, lessThanOrEqualTo(24));
    });
  });

  group('resolveRetryPolicy', () {
    ResolvedRetry resolve(
      SupervisionPolicy declared,
      CapabilityFailureKind kind, {
      StepFailureClass? failureClass,
      int circuitMaxRestarts = 3,
    }) => resolveRetryPolicy(
      declared: declared,
      kind: kind,
      failureClass:
          failureClass ?? resolveFailureClass(kind: kind, ranFor: _slow),
      circuitBackoff: Backoff.standard,
      circuitMaxRestarts: circuitMaxRestarts,
    );

    test('an undeclared policy inherits the circuit entirely', () {
      final r = resolve(
        const SupervisionPolicy.inherit(),
        CapabilityFailureKind.work,
      );
      expect(r.backoff, Backoff.standard);
      expect(r.maxRestarts, 3);
      expect(r.onExhaustion, ExhaustionBehavior.latchFailed);
    });

    test('an infra class keeps the wall-clock throttle schedule', () {
      final r = resolve(
        const SupervisionPolicy.inherit(),
        CapabilityFailureKind.noResult,
        failureClass: StepFailureClass.infra,
      );
      expect(r.backoff, Backoff.harnessThrottle);
      expect(r.onExhaustion, ExhaustionBehavior.parkAtGate);
    });

    test('declared noResult inherits infra retry and exhaustion policy', () {
      final failureClass = resolveFailureClass(
        kind: CapabilityFailureKind.noResult,
        ranFor: _long,
        kindDeclared: true,
      );
      final retry = resolveRetryPolicy(
        declared: const SupervisionPolicy.inherit(),
        kind: CapabilityFailureKind.noResult,
        failureClass: failureClass,
        circuitBackoff: Backoff.standard,
        circuitMaxRestarts: 3,
      );

      expect(retry.backoff, Backoff.harnessThrottle);
      expect(retry.onExhaustion, ExhaustionBehavior.parkAtGate);
    });

    test('a non-result parks at a gate; work latches', () {
      expect(
        defaultExhaustionFor(CapabilityFailureKind.noResult),
        ExhaustionBehavior.parkAtGate,
      );
      expect(
        defaultExhaustionFor(CapabilityFailureKind.invalidResult),
        ExhaustionBehavior.parkAtGate,
      );
      expect(
        defaultExhaustionFor(CapabilityFailureKind.work),
        ExhaustionBehavior.latchFailed,
      );
    });

    test('a declared per-kind override wins, and only for that kind', () {
      const declared = SupervisionPolicy(
        byKind: {
          CapabilityFailureKind.invalidResult: RetryPolicy(
            maxRestarts: 1,
            backoff: Backoff(
              min: Duration(seconds: 5),
              max: Duration(minutes: 1),
            ),
            onExhaustion: ExhaustionBehavior.latchFailed,
          ),
        },
      );
      final invalid = resolve(declared, CapabilityFailureKind.invalidResult);
      expect(invalid.maxRestarts, 1);
      expect(invalid.backoff.min, const Duration(seconds: 5));
      expect(invalid.onExhaustion, ExhaustionBehavior.latchFailed);

      final work = resolve(declared, CapabilityFailureKind.work);
      expect(work.maxRestarts, 3);
      expect(work.backoff, Backoff.standard);
    });

    test('a declared budget ABOVE the circuit is clamped (the pure frontier '
        'predicate reads Circuit.maxRestarts)', () {
      const declared = SupervisionPolicy(
        byKind: {CapabilityFailureKind.noResult: RetryPolicy(maxRestarts: 99)},
      );
      expect(resolve(declared, CapabilityFailureKind.noResult).maxRestarts, 3);
    });
  });

  test(
    'the non-result gate reason names the class, count, session and step',
    () {
      final reason = nonResultGateReason(
        failureClass: StepFailureClass.invalidResult,
        sessionId: 'tranquility-ltkod1',
        nodePath: 'tg-1/critic',
        attempts: 3,
        reason: 'verdict file is not valid JSON',
      );
      expect(reason, contains('invalid_result'));
      expect(reason, contains('3 attempt(s)'));
      expect(reason, contains('tranquility-ltkod1'));
      expect(reason, contains('tg-1/critic'));
      expect(reason, contains('verdict file is not valid JSON'));
    },
  );

  group('readPersistedFailureEvidence', () {
    test('decodes every known class into its existing policy kind', () {
      const expected = <String, CapabilityFailureKind>{
        'infra': CapabilityFailureKind.noResult,
        'no_result': CapabilityFailureKind.noResult,
        'invalid_result': CapabilityFailureKind.invalidResult,
        'work': CapabilityFailureKind.work,
        'store_unavailable': CapabilityFailureKind.work,
      };
      for (final entry in expected.entries) {
        final evidence = readPersistedFailureEvidence(
          _StepRow(failureClass: entry.key),
        );
        expect(evidence, isNotNull, reason: entry.key);
        expect(evidence!.kind, entry.value, reason: entry.key);
        expect(evidence.failureClass.wire, entry.key, reason: entry.key);
      }
    });

    test('carries immutable durable attempt and cooldown facts', () {
      final startedAt = DateTime.utc(2026, 9, 21, 1);
      final cooldownUntil = DateTime.utc(2026, 9, 21, 2);
      final evidence = readPersistedFailureEvidence(
        _StepRow(
          incarnation: 4,
          attemptId: 'attempt-4',
          startedAt: startedAt,
          cooldownUntil: cooldownUntil,
        ),
      )!;
      expect(evidence.incarnation, 4);
      expect(evidence.attemptId, 'attempt-4');
      expect(evidence.startedAt, startedAt);
      expect(evidence.cooldownUntil, cooldownUntil);
      expect(evidence.restartBudget, 0);
    });

    test('rejects non-failed, unknown, or incomplete rows', () {
      expect(
        readPersistedFailureEvidence(const _StepRow(stepState: 'running')),
        isNull,
      );
      expect(
        readPersistedFailureEvidence(const _StepRow(failureClass: 'unknown')),
        isNull,
      );
      expect(
        readPersistedFailureEvidence(
          const _StepRow(failureClass: 'future_class'),
        ),
        isNull,
      );
      expect(
        readPersistedFailureEvidence(const _StepRow(failureClass: null)),
        isNull,
      );
      expect(
        readPersistedFailureEvidence(const _StepRow(restartBudget: null)),
        isNull,
      );
    });
  });

  test('the exhaustion reason retains detail and names durable facts', () {
    final evidence = readPersistedFailureEvidence(const _StepRow())!;
    final reason = exhaustionGateReason(
      evidence: evidence,
      nodePath: 'tg-1/agent',
      detail:
          'harness throttled: 3 model steps exited without artifacts since '
          '2026-09-21T00:00:00.000Z',
    );
    expect(reason, contains('harness throttled'));
    expect(reason, contains('without artifacts'));
    expect(reason, contains('tg-1/agent'));
    expect(reason, contains('failure_class=infra'));
    expect(reason, contains('restart_budget=0 (spent)'));
  });

  test('a bounded reason is truncated at construction', () {
    final failure = CapabilityFailure.invalidResult(
      ''.padRight(kMaxReasonChars + 50, 'x'),
    );
    expect(failure.reason.length, kMaxReasonChars);
    expect(failure.kind, CapabilityFailureKind.invalidResult);
  });
}
