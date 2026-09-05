// The pure half: kind → durable class, and declaration → schedule.
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

const _fast = Duration(seconds: 9);
const _slow = Duration(seconds: 31);
const _long = Duration(minutes: 5);

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

  test('a bounded reason is truncated at construction', () {
    final failure = CapabilityFailure.invalidResult(
      ''.padRight(kMaxReasonChars + 50, 'x'),
    );
    expect(failure.reason.length, kMaxReasonChars);
    expect(failure.kind, CapabilityFailureKind.invalidResult);
  });
}
