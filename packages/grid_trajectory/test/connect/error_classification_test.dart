/// §5's server-error classification — and tg-3o6b's addition, the
/// PRIVILEGE-denied class the gc cadence treats as a posture.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:mysql_client/exception.dart';
import 'package:test/test.dart';

void main() {
  group('isPrivilegeDenied', () {
    test('THE 1105 DENIED-CALL SHAPE IS THE CLASS — cut-wiring C0\'s rule, '
        'restored (r13)', () {
      // Observed on lunar's first Stage-1 arm (tg-3o6b): dolt carries a denied
      // CALL on its unknown-error code, and that is the ONLY code a scoped
      // grant is ever refused with. The design names it normatively — "1105
      // privilege-denied ⇒ flare `trajectory.gcDisabled` once, never re-arm
      // this process" — so a codes-only predicate makes disable-on-deny
      // unreachable on exactly the homes it was written for.
      final deniedCall = MySQLServerException(
        "command denied to user 'trajectory'@'%'",
        1105,
      );
      expect(isPrivilegeDenied(deniedCall), isTrue);
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

    test('the bare word "denied" inside an unrelated 1105 does NOT latch the '
        'cadence off (r12 kept, in its narrow form)', () {
      // The predicate the r12 major reported matched the bare word anywhere
      // in a 1105's text, so ANY dolt catch-all error mentioning a denial
      // permanently disabled gc and the working set then grew unbounded. The
      // cure is the SERVER'S OWN PHRASING (`sqlDeniedCallMarker`), not
      // dropping 1105 from the class.
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
