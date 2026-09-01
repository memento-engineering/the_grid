/// §5's server-error classification — and tg-3o6b's addition, the
/// PRIVILEGE-denied class the gc cadence treats as a posture.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

void main() {
  group('isPrivilegeDenied', () {
    test('CODES ONLY: a 1105 is NOT the latching class, however its message '
        'reads (r12)', () {
      // Observed on lunar's first Stage-1 arm (tg-3o6b): dolt carries a denied
      // CALL on its unknown-error code — the SAME code it carries a
      // commit-time unique violation on. The gc cadence LATCHES on this
      // predicate for the whole process lifetime, so it may not be decided by
      // a message substring: one misclassified 1105 would disable reclamation
      // forever. A denied CALL falls to the ordinary flare-and-rearm loop
      // instead, which is the safe direction for a wrong answer.
      final deniedCall = MySQLServerException(
        "command denied to user 'trajectory'@'%'",
        1105,
      );
      expect(isPrivilegeDenied(deniedCall), isFalse);
      // The operator-facing HINT still reads it — it only decorates a one-shot
      // verb's error line, and it never latches anything.
      expect(readsAsPrivilegeDenial(deniedCall), isTrue);
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
      expect(readsAsPrivilegeDenial(unique), isFalse);
      expect(isUniqueViolationOn(unique, 'uq_idem'), isTrue);
    });

    test('the word "denied" inside an unrelated 1105 no longer latches the '
        'cadence off (r12 — the regression this predicate caused)', () {
      // The old predicate matched the bare word anywhere in a 1105's text, so
      // ANY dolt catch-all error mentioning a denial permanently disabled gc
      // and the working set then grew unbounded.
      final unrelated = MySQLServerException(
        'runtime error: access to table trajectory was denied by a policy',
        1105,
      );
      expect(isPrivilegeDenied(unrelated), isFalse);
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
