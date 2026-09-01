/// §5's server-error classification — and tg-3o6b's addition, the
/// PRIVILEGE-denied class the gc cadence treats as a posture.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

void main() {
  group('isPrivilegeDenied', () {
    test('the LIVE shape: a 1105 denying the command to the scoped user', () {
      // Observed on lunar's first Stage-1 arm (tg-3o6b): dolt carries a
      // denied CALL on its unknown-error code, so the code alone cannot
      // discriminate it from a commit-time unique violation.
      expect(
        isPrivilegeDenied(
          MySQLServerException("command denied to user 'trajectory'@'%'", 1105),
        ),
        isTrue,
      );
    });

    test('the classic access-denied codes land in the same class', () {
      for (final code in sqlErrAccessDenied) {
        expect(
          isPrivilegeDenied(
            MySQLServerException('Access denied for user', code),
          ),
          isTrue,
          reason: 'code $code',
        );
      }
    });

    test('a 1105 that is NOT a denial stays out — a unique violation must '
        'never disable a cadence', () {
      final unique = MySQLServerException(
        'unique key violation on uq_idem',
        1105,
      );
      expect(isPrivilegeDenied(unique), isFalse);
      expect(isUniqueViolationOn(unique, 'uq_idem'), isTrue);
    });

    test('a transport-level throwable is not a privilege answer', () {
      expect(isPrivilegeDenied(StateError('socket closed')), isFalse);
      expect(
        isPrivilegeDenied(MySQLServerException('deadlock detected', 1213)),
        isFalse,
      );
      expect(
        isSerializationFailure(MySQLServerException('deadlock detected', 1213)),
        isTrue,
      );
    });
  });
}
