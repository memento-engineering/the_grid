import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

void main() {
  group('ConvergenceState wire literals', () {
    // Hardcoded against gascity/internal/convergence/metadata.go:50-56 —
    // round-tripping through the code's own constants would prove nothing
    // about gc compatibility.
    test('match metadata.go exactly', () {
      expect(ConvergenceState.creating.wire, 'creating'); // metadata.go:51
      expect(ConvergenceState.active.wire, 'active'); // metadata.go:52
      expect(
        ConvergenceState.waitingManual.wire,
        'waiting_manual', // metadata.go:53 — snake_case, not camelCase
      );
      expect(
        ConvergenceState.waitingTrigger.wire,
        'waiting_trigger', // metadata.go:54
      );
      expect(ConvergenceState.terminated.wire, 'terminated'); // metadata.go:55
    });

    test('the set is exactly five states', () {
      expect(ConvergenceState.values, hasLength(5));
    });

    test('fromWire resolves every literal and rejects the rest', () {
      expect(ConvergenceState.fromWire('creating'), ConvergenceState.creating);
      expect(ConvergenceState.fromWire('active'), ConvergenceState.active);
      expect(
        ConvergenceState.fromWire('waiting_manual'),
        ConvergenceState.waitingManual,
      );
      expect(
        ConvergenceState.fromWire('waiting_trigger'),
        ConvergenceState.waitingTrigger,
      );
      expect(
        ConvergenceState.fromWire('terminated'),
        ConvergenceState.terminated,
      );
      // Near-misses must not coerce.
      expect(ConvergenceState.fromWire('waitingManual'), isNull);
      expect(ConvergenceState.fromWire('Terminated'), isNull);
      expect(ConvergenceState.fromWire(''), isNull);
    });

    test('only terminated is terminal (ADR-0003 invariant 6)', () {
      expect(ConvergenceState.terminated.isTerminal, isTrue);
      for (final state in ConvergenceState.values) {
        if (state == ConvergenceState.terminated) continue;
        expect(state.isTerminal, isFalse, reason: state.wire);
      }
    });
  });

  group('ConvergenceStateReading', () {
    test('absent key reads as notAdopted (gc "" adopt path)', () {
      expect(
        ConvergenceStateReading.decode(null, present: false),
        const ConvergenceStateReading.notAdopted(),
      );
    });

    test('present-but-empty reads as notAdopted — gc map access cannot '
        'distinguish "" from absent (reconcile.go:73-76)', () {
      expect(
        ConvergenceStateReading.decode('', present: true),
        const ConvergenceStateReading.notAdopted(),
      );
    });

    test('known wire strings read as known', () {
      expect(
        ConvergenceStateReading.decode('active', present: true),
        const ConvergenceStateReading.known(ConvergenceState.active),
      );
      expect(
        ConvergenceStateReading.decode('waiting_manual', present: true),
        const ConvergenceStateReading.known(ConvergenceState.waitingManual),
      );
    });

    test('unknown non-empty state is a TYPED failure, never a coercion '
        '(gc errors: reconcile.go:101-106)', () {
      final reading = ConvergenceStateReading.decode('paused', present: true);
      expect(reading, const ConvergenceStateReading.unrecognized('paused'));
      expect(reading.stateOrNull, isNull);
    });

    test('non-String values are unrecognized, not crashes', () {
      expect(
        ConvergenceStateReading.decode(3, present: true),
        const ConvergenceStateReading.unrecognized(3),
      );
    });

    test(
      'notAdopted is not a sixth state — distinct from every known state',
      () {
        const notAdopted = ConvergenceStateReading.notAdopted();
        for (final state in ConvergenceState.values) {
          expect(notAdopted, isNot(ConvergenceStateReading.known(state)));
        }
        expect(notAdopted.stateOrNull, isNull);
      },
    );
  });
}
