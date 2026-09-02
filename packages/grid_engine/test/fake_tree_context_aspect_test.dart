// The FakeTreeContext half of the genesis_tree 0.3.0 aspect adoption: the fake
// is the_grid's one external TreeContext implementation with declared members.

import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

final class _Ambient {
  const _Ambient(this.name);
  final String name;
}

void main() {
  group('FakeTreeContext aspects (genesis_tree 0.3.0)', () {
    test('an aspect-free depend still returns the ambient value', () {
      final context = FakeTreeContext(values: {_Ambient: const _Ambient('v')});

      expect(context.dependOnInheritedSeedOfExactType<_Ambient>()?.name, 'v');
    });

    test('a missing type is still null, not a throw', () {
      final context = FakeTreeContext();

      expect(context.dependOnInheritedSeedOfExactType<_Ambient>(), isNull);
    });

    test('a non-null aspect is refused LOUDLY, like a plain provider', () {
      final context = FakeTreeContext(values: {_Ambient: const _Ambient('v')});

      expect(
        () =>
            context.dependOnInheritedSeedOfExactType<_Ambient>(aspect: 'name'),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'aspect'),
        ),
        reason:
            'silently ignoring it would certify a call that throws against a '
            'real tree',
      );
    });

    test('the unmounted guard still fires before the aspect check', () {
      final context = FakeTreeContext()..mounted = false;

      expect(
        () =>
            context.dependOnInheritedSeedOfExactType<_Ambient>(aspect: 'name'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
