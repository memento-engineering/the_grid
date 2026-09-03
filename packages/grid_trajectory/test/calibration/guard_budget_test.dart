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

  group('GuardBudget', () {
    test('derives both floors from the measured units', () {
      final budget = GuardBudget(
        baselineUnitMicros: 5000,
        baselineTailMicros: 10000,
      );
      expect(budget.baselineOpsPerSecond, 200);
      expect(budget.minimumDrainPerSecond, closeTo(30, 1e-9));
      expect(budget.maximumP99Millis, closeTo(80, 1e-9));
    });

    test('a runner 6x slower scales both floors past the tg-2zao receipts', () {
      final budget = GuardBudget(
        baselineUnitMicros: 31000,
        baselineTailMicros: 62000,
      );
      expect(budget.minimumDrainPerSecond, lessThan(22.5));
      expect(budget.maximumP99Millis, greaterThan(297.775));
    });

    test('the round-1 CI receipts clear the round-2 floor', () {
      // Run 33777666093: a 119.27/s calibrated bound => a 2096 us unit.
      final first = GuardBudget(
        baselineUnitMicros: 2096,
        baselineTailMicros: 4192,
      );
      expect(first.minimumDrainPerSecond, lessThan(106.65));
      expect(first.minimumDrainPerSecond, greaterThan(106.65 / 2));
      // Run 33778914681: a 120.60/s calibrated bound => a 2073 us unit.
      final second = GuardBudget(
        baselineUnitMicros: 2073,
        baselineTailMicros: 4146,
      );
      expect(second.minimumDrainPerSecond, lessThan(109.51));
      expect(second.minimumDrainPerSecond, greaterThan(109.51 / 2));
    });

    test('the 297.775 ms tail receipt clears the round-2 ceiling', () {
      final budget = GuardBudget(
        baselineUnitMicros: 31000,
        baselineTailMicros: 62000,
      );
      expect(budget.maximumP99Millis, greaterThan(297.775));
      expect(budget.maximumP99Millis, lessThan(297.775 * 2));
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
}
