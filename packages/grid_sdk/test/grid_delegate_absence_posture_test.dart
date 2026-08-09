// The unified delegate's ABSENCE POSTURES (tg-at3r): grid_cli's
// ResidentGridDelegate contract folded into GridDelegate as ONE class, and
// the absorbed vended views default to designed absence (docs/STYLE.md rules
// 3/4) — null views the shell renders honestly, no-op rails — never abstract
// members forcing every station to stub what it does not vend.
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// The barest possible station delegate: overrides NOTHING absorbed.
final class _BareDelegate extends GridDelegate {}

void main() {
  group('GridDelegate absence-posture defaults (tg-at3r)', () {
    late _BareDelegate delegate;

    setUp(() => delegate = _BareDelegate());
    tearDown(() => delegate.dispose());

    test('stationView defaults to null — absence, not an abstract burden', () {
      expect(delegate.stationView, isNull);
    });

    test('commandHandler defaults to null — the control surface renders the '
        'refusal, the delegate owes nothing', () {
      expect(delegate.commandHandler, isNull);
    });

    test('afterFlush defaults to a no-op on the flush rail', () {
      expect(delegate.afterFlush, returnsNormally);
    });

    test('sweepOrphans defaults to nothing-to-sweep', () {
      expect(delegate.sweepOrphans(), completes);
    });

    test('armedRoster is empty until resolveArmedRoster retains one', () {
      expect(delegate.armedRoster, isEmpty);
    });

    test('resolveArmedRoster refuses an empty armed roster LOUD with '
        'exit 1 — retention semantics unchanged by the fold (tg-4wqu owns '
        'their future)', () {
      expect(
        () => delegate.resolveArmedRoster(
          coded: const <SubstationWorkSpec>[],
          appended: const <SubstationConfig>[],
          onSkip: (_) => fail('nothing to skip'),
        ),
        throwsA(
          isA<StationRefusal>()
              .having((refusal) => refusal.code, 'code', 1)
              .having(
                (refusal) => refusal.message,
                'message',
                'no substation resolved a work store at its root.',
              ),
        ),
      );
    });
  });
}
