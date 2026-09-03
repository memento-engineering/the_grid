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
      expect(budget.minimumDrainPerSecond, 50);
      expect(budget.maximumP99Millis, 50);
    });

    test('a runner 6x slower scales both floors past the tg-2zao receipts', () {
      final budget = GuardBudget(
        baselineUnitMicros: 31000,
        baselineTailMicros: 62000,
      );
      expect(budget.minimumDrainPerSecond, lessThan(22.5));
      expect(budget.maximumP99Millis, greaterThan(297.775));
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
