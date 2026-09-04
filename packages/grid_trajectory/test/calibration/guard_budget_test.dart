import 'package:test/test.dart';

import '../support/guard_budget.dart';

void main() {
  group('resolveGuardHost', () {
    test('an unset variable is a developer machine', () {
      expect(resolveGuardHost(const {}), GuardHost.developer);
      expect(
        resolveGuardHost(const {kSharedRunnerEnvVar: ''}),
        GuardHost.developer,
      );
    });

    test('exactly "1" is a shared runner', () {
      expect(
        resolveGuardHost(const {kSharedRunnerEnvVar: '1'}),
        GuardHost.sharedRunner,
      );
    });

    test('any other value is refused LOUDLY', () {
      expect(
        () => resolveGuardHost(const {kSharedRunnerEnvVar: 'true'}),
        throwsA(isA<StateError>()),
      );
    });
  });

  test('the absolute pins apply on a developer machine only', () {
    expect(absolutePinsApply(GuardHost.developer), isTrue);
    expect(absolutePinsApply(GuardHost.sharedRunner), isFalse);
  });

  group('the shared-runner tolerances', () {
    test('are pinned at the tg-shry bands', () {
      expect(kDrainToleranceFraction, 0.30);
      expect(kTailToleranceFactor, 2.50);
    });

    test('the calibrated cost ratios are carried unchanged', () {
      expect(kFoldMeanCostRatio, 4.0);
      expect(kFoldTailCostRatio, 5.0);
    });

    test('the effective shared-runner ceilings are 13.33x and 12.5x', () {
      expect(
        kFoldMeanCostRatio / kDrainToleranceFraction,
        closeTo(13.333333333333334, 1e-9),
      );
      expect(kFoldTailCostRatio * kTailToleranceFactor, closeTo(12.5, 1e-9));
    });
  });

  group('GuardBudget', () {
    test('derives both bounds and both floors from the measured units', () {
      final budget = GuardBudget(
        baselineUnitMicros: 5000,
        baselineTailMicros: 10000,
      );
      expect(budget.baselineOpsPerSecond, 200);
      // 200 ops/s at the 4.0x fold cost => a 50/s bound; at 0.30 => 15/s.
      expect(budget.calibratedDrainBound, closeTo(50, 1e-9));
      expect(budget.minimumDrainPerSecond, closeTo(15, 1e-9));
      // A 10 ms tail at the 5.0x fold cost => a 50 ms bound; at 2.50 => 125.
      expect(budget.calibratedP99BoundMillis, closeTo(50, 1e-9));
      expect(budget.maximumP99Millis, closeTo(125, 1e-9));
    });

    test('a runner 6x slower scales both floors past the tg-2zao receipts', () {
      final budget = GuardBudget(
        baselineUnitMicros: 31000,
        baselineTailMicros: 62000,
      );
      expect(budget.minimumDrainPerSecond, lessThan(22.5));
      expect(budget.maximumP99Millis, greaterThan(297.775));
    });

    test('the round-4 receipt clears the floor and half of it does not', () {
      // Run 33818055118 (PR #297, rerun 23:37Z on 2026-09-03): the 0.60 band
      // demanded 120.77294685990339 appends/s and the run delivered
      // 120.69804320618569 — the floor sat ON the observation.
      const observedDrain = 120.69804320618569;
      final budget = GuardBudget(
        baselineUnitMicros: 1242,
        baselineTailMicros: 2484,
      );
      expect(
        budget.calibratedDrainBound * 0.60,
        closeTo(120.77294685990339, 1e-9),
        reason: 'a 1242 us unit is the unit CI\'s failing floor came from',
      );
      expect(budget.minimumDrainPerSecond, lessThan(observedDrain));
      // The band still has TEETH: a 2x fold slowdown of that same receipt
      // lands under the widened floor.
      expect(budget.minimumDrainPerSecond, greaterThan(observedDrain / 2));
    });

    test('the round-1 receipts clear the widened floor, which still '
        'outranks the absolute storm-production pin', () {
      // Run 33777666093: a 119.27/s calibrated bound => a 2096 us unit.
      final first = GuardBudget(
        baselineUnitMicros: 2096,
        baselineTailMicros: 4192,
      );
      expect(first.minimumDrainPerSecond, lessThan(106.65));
      expect(first.minimumDrainPerSecond, greaterThan(kStormProductionRateTop));
      // Run 33778914681: a 120.60/s calibrated bound => a 2073 us unit.
      final second = GuardBudget(
        baselineUnitMicros: 2073,
        baselineTailMicros: 4146,
      );
      expect(second.minimumDrainPerSecond, lessThan(109.51));
      expect(
        second.minimumDrainPerSecond,
        greaterThan(kStormProductionRateTop),
      );
    });

    test('the 297.775 ms tail receipt clears the widened ceiling', () {
      final budget = GuardBudget(
        baselineUnitMicros: 31000,
        baselineTailMicros: 62000,
      );
      expect(budget.maximumP99Millis, greaterThan(297.775));
      expect(budget.maximumP99Millis, lessThan(297.775 * 3));
    });

    test('a non-positive unit is refused LOUDLY', () {
      expect(
        () => GuardBudget(baselineUnitMicros: 0, baselineTailMicros: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => GuardBudget(baselineUnitMicros: 1, baselineTailMicros: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the W6 failure messages carry the receipt', () {
    // The round-4 units: the 1242 us machine-speed unit CI's failing floor was
    // derived from, and a 2484 us machine tail.
    final budget = GuardBudget(
      baselineUnitMicros: 1242,
      baselineTailMicros: 2484,
    );

    test('the drain message prints expected, actual and BOTH ratios', () {
      final message = drainFailureMessage(
        budget: budget,
        drainRate: 120.69804320618569,
      );
      expect(message, contains('expected: greater than 60.386 appends/s'));
      expect(message, contains('actual: 120.698 appends/s'));
      expect(message, contains('drain/probe-rate 0.1499'));
      expect(message, contains('drain/calibrated-bound 0.5996'));
      expect(
        message,
        contains('201.288/s calibrated bound at the 0.3x tg-shry'),
      );
    });

    test('the tail message prints expected, actual and BOTH ratios', () {
      final message = tailFailureMessage(budget: budget, p99Millis: 40.0);
      expect(message, contains('expected: less than 31.050 ms'));
      expect(message, contains('actual: 40.000 ms'));
      expect(message, contains('p99/probe-latency 16.1031'));
      expect(message, contains('p99/calibrated-bound 3.2206'));
      expect(
        message,
        contains('12.420 ms calibrated bound at the 2.5x tg-shry'),
      );
    });
  });
}
