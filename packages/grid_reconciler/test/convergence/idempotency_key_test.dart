import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

/// Parity suite for the idempotency-key port (handler.go:11-39). The
/// parse expectations are **Go ground truth** (the exact `ParseIterationFromKey`
/// body run under go1.26 against each input), not derived from this port.
void main() {
  group('idempotencyKey / idempotencyKeyPrefix (handler.go:13-21)', () {
    test('construct the exact gc shapes', () {
      expect(idempotencyKey('gt-abc', 1), 'converge:gt-abc:iter:1');
      expect(idempotencyKey('gt-abc', 42), 'converge:gt-abc:iter:42');
      expect(idempotencyKeyPrefix('gt-abc'), 'converge:gt-abc:iter:');
    });

    test('key always starts with its own prefix', () {
      expect(
        idempotencyKey('gt-abc', 7).startsWith(idempotencyKeyPrefix('gt-abc')),
        isTrue,
      );
    });

    test('bead ids containing ":" pass through verbatim', () {
      expect(idempotencyKey('a:b:c', 2), 'converge:a:b:c:iter:2');
      expect(idempotencyKeyPrefix('a:b:c'), 'converge:a:b:c:iter:');
    });

    test('negative iteration formats like Go %d (no validation — oddity '
        'preserved)', () {
      expect(idempotencyKey('x', -1), 'converge:x:iter:-1');
    });

    test('wisp metadata key literal (cmd/gc/convergence_store.go)', () {
      expect(wispIdempotencyKeyField, 'idempotency_key');
    });
  });

  group('parseIterationFromKey (handler.go:26-39) — Go ground truth', () {
    test('standard key', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:3'), 3);
    });

    test('zero is VALID (Go: n < 0 rejects, 0 passes)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:0'), 0);
    });

    test('negative is rejected after parsing (handler.go:35)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:-1'), isNull);
    });

    test('"+5" parses to 5 — strconv.Atoi accepts a leading plus (oddity '
        'preserved)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:+5'), 5);
    });

    test('"-0" parses to 0 — Atoi yields 0, and 0 is not < 0 (oddity '
        'preserved)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:-0'), 0);
    });

    test('leading zeros parse ("007" -> 7)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:007'), 7);
    });

    test('bead id itself containing ":iter:" — LastIndex wins '
        '(handler.go:29)', () {
      expect(parseIterationFromKey('converge:a:iter:b:iter:4'), 4);
    });

    test('empty suffix fails', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:'), isNull);
    });

    test('no marker fails', () {
      expect(parseIterationFromKey('converge:gt-abc'), isNull);
      expect(parseIterationFromKey('no-marker-at-all'), isNull);
    });

    test('marker at position 0 still parses (":iter:9" -> 9, Go behavior)', () {
      expect(parseIterationFromKey(':iter:9'), 9);
    });

    test('whitespace in the number fails — Atoi takes digits only '
        '(Dart int.parse would accept " 5"; the port must not)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter: 5'), isNull);
    });

    test('hex fails — Atoi is decimal only (Dart int.parse would accept '
        '"0x10"; the port must not)', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:0x10'), isNull);
    });

    test('non-numeric and mixed suffixes fail', () {
      expect(parseIterationFromKey('converge:gt-abc:iter:abc'), isNull);
      expect(parseIterationFromKey('converge:gt-abc:iter:5a'), isNull);
      expect(parseIterationFromKey('converge:gt-abc:iter:1.5'), isNull);
    });

    test('int64 overflow fails (Atoi ErrRange)', () {
      expect(
        parseIterationFromKey('converge:gt-abc:iter:9223372036854775808'),
        isNull,
      );
      // Max int64 itself parses.
      expect(
        parseIterationFromKey('converge:gt-abc:iter:9223372036854775807'),
        9223372036854775807,
      );
    });

    test('marker is case-sensitive', () {
      expect(parseIterationFromKey('converge:gt-abc:ITER:3'), isNull);
    });
  });

  group('goAtoi (strconv.Atoi semantics) — Go ground truth', () {
    test('valid forms', () {
      expect(goAtoi('5'), 5);
      expect(goAtoi('+5'), 5);
      expect(goAtoi('-5'), -5);
      expect(goAtoi('-0'), 0);
      expect(goAtoi('007'), 7);
      expect(goAtoi('9223372036854775807'), 9223372036854775807);
      expect(goAtoi('-9223372036854775808'), -9223372036854775808);
    });

    test('invalid forms', () {
      expect(goAtoi(''), isNull);
      expect(goAtoi(' 5'), isNull);
      expect(goAtoi('0x10'), isNull);
      expect(goAtoi('5a'), isNull);
      expect(goAtoi('9223372036854775808'), isNull); // ErrRange
      expect(goAtoi('+'), isNull);
      expect(goAtoi('-'), isNull);
    });
  });
}
