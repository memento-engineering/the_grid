import 'dart:math';

import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('IncarnationEnv', () {
    test('emits the four GRID_* vars with the renamed keys', () {
      final env = IncarnationEnv(
        sessionId: 'tgdog-sess-1',
        beadId: 'tgdog-work-7',
        instanceToken: 'deadbeef',
        runtimeEpoch: 3,
      ).toEnv();

      expect(env['GRID_SESSION_ID'], 'tgdog-sess-1');
      expect(env['GRID_BEAD_ID'], 'tgdog-work-7');
      expect(env['GRID_INSTANCE_TOKEN'], 'deadbeef');
      expect(env['GRID_RUNTIME_EPOCH'], '3');
      // No GC_* leakage — the rename is the coexistence guarantee.
      expect(env.keys.any((k) => k.startsWith('GC_')), isFalse);
    });

    test('mint defaults epoch to 1 and draws a 32-hex-char token', () {
      final env = IncarnationEnv.mint(
        sessionId: 's',
        beadId: 'b',
        random: Random(7),
      );

      expect(env.runtimeEpoch, 1);
      expect(env.instanceToken, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('newInstanceToken is 16 bytes => 32 lowercase hex chars', () {
      final token = newInstanceToken(Random(1));
      expect(token, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('newAttemptId — the trajectory name for one incarnation (§2.1)', () {
    test('is a CHAR(26) Crockford ULID, the schema attempt_id shape', () {
      expect(newAttemptId(), matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$')));
    });

    test('is fresh every call — one incarnation, one attempt', () {
      final ids = {for (var i = 0; i < 64; i++) newAttemptId()};
      expect(ids, hasLength(64));
    });

    test('is time-ordered — a later mint sorts after an earlier one', () async {
      final first = newAttemptId();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(newAttemptId().compareTo(first), isPositive);
    });

    test('does not displace the instance token — two separate mints of two '
        'separate shapes (Stage 1 dual-exports both)', () {
      expect(newAttemptId(), isNot(matches(RegExp(r'^[0-9a-f]{32}$'))));
    });
  });
}
