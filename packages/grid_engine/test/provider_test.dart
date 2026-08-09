import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'package:grid_engine/src/seeds/provider.dart';

final class _Value {
  const _Value(this.name);
  final String name;
}

final class _Other {
  const _Other(this.name);
  final String name;
}

final class _Watch extends StatelessSeed {
  const _Watch(this.values);
  final List<String?> values;

  @override
  Seed build(TreeContext context) {
    values.add(context.watch<_Value>()?.name);
    return const _Leaf();
  }
}

final class _WatchBoth extends StatelessSeed {
  const _WatchBoth(this.values);
  final List<Object?> values;

  @override
  Seed build(TreeContext context) {
    values
      ..add(context.watch<_Value>()?.name)
      ..add(context.watch<_Other>()?.name);
    return const _Leaf();
  }
}

final class _Leaf extends Seed {
  const _Leaf();
  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(_Leaf super.seed);
}

void main() {
  group('ownership', () {
    test('creates once and disposes owned values in reverse order', () {
      final events = <String>[];
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          providers: <Provider<Object>>[
            Provider<_Value>(
              create: () {
                events.add('create value');
                return const _Value('owned');
              },
              dispose: (_) => events.add('dispose value'),
            ),
            Provider<_Other>(
              create: () {
                events.add('create other');
                return const _Other('owned');
              },
              dispose: (_) => events.add('dispose other'),
            ),
          ],
          child: _WatchBoth(events),
        ),
      );

      expect(events, ['create value', 'create other', 'owned', 'owned']);
      owner.dispose();
      expect(events.sublist(4), ['dispose other', 'dispose value']);
    });

    test('adopted values are never disposed', () {
      final values = <String?>[];
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          providers: <Provider<Object>>[
            Provider<_Value>.value(const _Value('adopted')),
          ],
          child: _Watch(values),
        ),
      );
      owner.dispose();
      expect(values, ['adopted']);
    });
  });

  group('availability', () {
    test('returns null when absent and nearest scope shadows its parent', () {
      final absent = <String?>[];
      final shadowed = <String?>[];
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          providers: <Provider<Object>>[
            Provider<_Value>.value(const _Value('outer')),
          ],
          child: ProviderScope(
            providers: <Provider<Object>>[
              Provider<_Value>.value(const _Value('inner')),
            ],
            child: _Watch(shadowed),
          ),
        ),
      );
      expect(shadowed, ['inner']);
      owner.dispose();

      final absentOwner = TreeOwner();
      absentOwner.mountRoot(
        ProviderScope(providers: const [], child: _Watch(absent)),
      );
      expect(absent, [null]);
      absentOwner.dispose();
    });

    test('keyed scope remounts move through null, value, and null', () {
      final values = <String?>[];
      for (final present in [false, true, false]) {
        final owner = TreeOwner();
        owner.mountRoot(
          ProviderScope(
            key: ValueKey(present),
            providers: <Provider<Object>>[
              if (present) Provider<_Value>.value(const _Value('available')),
            ],
            child: _Watch(values),
          ),
        );
        owner.dispose();
      }
      expect(values, [null, 'available', null]);
    });
  });

  group('refusal', () {
    test('duplicate descriptor types are refused', () {
      final owner = TreeOwner();
      expect(
        () => owner.mountRoot(
          ProviderScope(
            providers: <Provider<Object>>[
              Provider<_Value>.value(const _Value('one')),
              Provider<_Value>.value(const _Value('two')),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'ProviderScope contains duplicate provider type: _Value',
          ),
        ),
      );
    });

    test('throwing create rolls back earlier owned entries in reverse', () {
      final events = <String>[];
      final owner = TreeOwner();
      final failure = StateError('creation failed');
      expect(
        () => owner.mountRoot(
          ProviderScope(
            providers: <Provider<Object>>[
              Provider<_Value>(
                create: () => const _Value('one'),
                dispose: (_) => events.add('dispose value'),
              ),
              Provider<_Other>(
                create: () => const _Other('two'),
                dispose: (_) => events.add('dispose other'),
              ),
              Provider<Object>(create: () => throw failure),
            ],
          ),
        ),
        throwsA(same(failure)),
      );
      expect(events, ['dispose other', 'dispose value']);
    });
  });
}
