import 'package:genesis_tree/genesis_tree.dart';
import 'package:test/test.dart';

import 'package:grid_engine/src/seeds/provider.dart';

final class _Value {
  const _Value(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is _Value && other.name == name;

  @override
  int get hashCode => name.hashCode;
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

final class _DependencyProbe extends StatefulSeed {
  const _DependencyProbe(this.values, this.dependencyChanges);

  final List<String?> values;
  final List<int> dependencyChanges;

  @override
  State<_DependencyProbe> createState() => _DependencyProbeState();
}

final class _DependencyProbeState extends State<_DependencyProbe> {
  @override
  void didChangeDependencies() {
    seed.dependencyChanges.add(seed.dependencyChanges.length + 1);
  }

  @override
  Seed build(TreeContext context) {
    seed.values.add(context.watch<_Value>()?.name);
    return const _Leaf();
  }
}

final class _ScopeRebuilder extends StatefulSeed {
  const _ScopeRebuilder({required this.onCreate, required this.child});

  final void Function(_ScopeRebuilderState state) onCreate;
  final Seed child;

  @override
  State<_ScopeRebuilder> createState() {
    final state = _ScopeRebuilderState();
    onCreate(state);
    return state;
  }
}

final class _ScopeRebuilderState extends State<_ScopeRebuilder> {
  _Value _value = const _Value('one');

  void update(_Value value) => setState(() => _value = value);

  @override
  Seed build(TreeContext context) => ProviderScope(
    key: const ValueKey('stable-provider-scope'),
    providers: <Provider<Object>>[Provider<_Value>.value(_value)],
    child: seed.child,
  );
}

void main() {
  group('notification stability', () {
    test('equal leaf rebuild is silent and changed leaf notifies once', () {
      final values = <String?>[];
      final dependencyChanges = <int>[];
      late _ScopeRebuilderState rebuilder;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _ScopeRebuilder(
          onCreate: (state) => rebuilder = state,
          child: _DependencyProbe(values, dependencyChanges),
        ),
      );

      expect(values, ['one']);
      expect(dependencyChanges, [1]);

      rebuilder.update(_Value('one'));
      owner.flush();
      expect(dependencyChanges, [1]);

      rebuilder.update(const _Value('two'));
      owner.flush();
      expect(dependencyChanges, [1, 2]);
      expect(values.last, 'two');
    });
  });

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
