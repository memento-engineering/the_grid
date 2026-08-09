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

/// A rebuild/swap harness: [poke] forces a rebuild of the CURRENT subtree
/// description; [swap] replaces the described subtree entirely.
final class _Host extends StatefulSeed {
  const _Host({required this.onCreate, required this.describe});

  final void Function(_HostState state) onCreate;
  final Seed Function() describe;

  @override
  State<_Host> createState() {
    final state = _HostState();
    onCreate(state);
    return state;
  }
}

final class _HostState extends State<_Host> {
  Seed Function()? _override;

  void poke() => setState(() {});

  void swap(Seed Function() describe) => setState(() => _override = describe);

  @override
  Seed build(TreeContext context) => (_override ?? seed.describe)();
}

final class _Slots extends MultiChildSeed {
  _Slots(List<Seed> children) : super(children: children);
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

final class _OtherDependencyProbe extends StatefulSeed {
  const _OtherDependencyProbe(this.values, this.dependencyChanges);

  final List<String?> values;
  final List<int> dependencyChanges;

  @override
  State<_OtherDependencyProbe> createState() => _OtherDependencyProbeState();
}

final class _OtherDependencyProbeState extends State<_OtherDependencyProbe> {
  @override
  void didChangeDependencies() {
    seed.dependencyChanges.add(seed.dependencyChanges.length + 1);
  }

  @override
  Seed build(TreeContext context) {
    seed.values.add(context.watch<_Other>()?.name);
    return const _Leaf();
  }
}

final class _ProbeChildren extends MultiChildSeed {
  _ProbeChildren(List<Seed> children) : super(children: children);
}

final class _ReadProbe extends StatefulSeed {
  const _ReadProbe({required this.onCreate, required this.builds});

  final void Function(_ReadProbeState state) onCreate;
  final List<int> builds;

  @override
  State<_ReadProbe> createState() {
    final state = _ReadProbeState();
    onCreate(state);
    return state;
  }
}

final class _ReadProbeState extends State<_ReadProbe> {
  String? readValue() => context.read<_Value>()?.name;

  @override
  Seed build(TreeContext context) {
    seed.builds.add(seed.builds.length + 1);
    return const _Leaf();
  }
}

/// Re-provides a mutable `.value` pair on every [update] — the reconcile-in-
/// place surface for the notification tests.
final class _ValueHost extends StatefulSeed {
  const _ValueHost({required this.onCreate, required this.child});

  final void Function(_ValueHostState state) onCreate;
  final Seed child;

  @override
  State<_ValueHost> createState() {
    final state = _ValueHostState();
    onCreate(state);
    return state;
  }
}

final class _ValueHostState extends State<_ValueHost> {
  _Value _value = const _Value('one');

  void update(_Value value) => setState(() => _value = value);

  @override
  Seed build(TreeContext context) => Nest(
    children: [
      Provider<_Value>.value(_value),
      Provider<_Other>.value(const _Other('stable')),
    ],
    child: seed.child,
  );
}

void main() {
  group('ownership and lifecycle', () {
    test('create runs exactly once per mount across forced rebuilds', () {
      var created = 0;
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _Host(
          onCreate: (state) => host = state,
          describe: () => Provider<_Value>(
            create: (_) {
              created++;
              return const _Value('owned');
            },
            child: _Watch(values),
          ),
        ),
      );
      expect(created, 1);
      expect(values, ['owned']);

      for (var i = 0; i < 3; i++) {
        host.poke();
        owner.flush();
      }
      // The provider reconciled in place three times: the child re-described
      // and rebuilt, the owned value was never re-created.
      expect(created, 1);
      expect(values, ['owned', 'owned', 'owned', 'owned']);
    });

    test('create(context) constructs from an ancestor-provided value', () {
      final values = <Object?>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        Nest(
          children: [
            Provider<_Value>(create: (_) => const _Value('cfg')),
            Provider<_Other>(
              // Dependency-free ambient lookup in initState: the read verb.
              create: (context) => _Other(context.read<_Value>()!.name),
            ),
          ],
          child: _WatchBoth(values),
        ),
      );
      expect(values, ['cfg', 'cfg']);
    });

    test('created values are disposed at unmount, adopted values never', () {
      final events = <String>[];
      final values = <Object?>[];
      final owner = TreeOwner();

      owner.mountRoot(
        Nest(
          children: [
            Provider<_Value>(
              create: (_) {
                events.add('create');
                return const _Value('owned');
              },
              dispose: (value) => events.add('dispose ${value.name}'),
            ),
            // Adopted: owner-held; the tree has no disposal hook for it at all.
            Provider<_Other>.value(const _Other('adopted')),
          ],
          child: _WatchBoth(values),
        ),
      );
      expect(values, ['owned', 'adopted']);
      expect(events, ['create']);

      owner.dispose();
      expect(events, ['create', 'dispose owned']);
    });

    test('keyed identity: same key updates in place, new key remounts', () {
      var created = 0;
      final disposed = <String>[];
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      Seed Function() describe(String key) =>
          () => Provider<_Value>(
            key: ValueKey(key),
            create: (_) {
              created++;
              return _Value('v$created');
            },
            dispose: (value) => disposed.add(value.name),
            child: _Watch(values),
          );

      owner.mountRoot(
        _Host(onCreate: (state) => host = state, describe: describe('a')),
      );
      expect(created, 1);
      expect(values, ['v1']);

      host.swap(describe('a'));
      owner.flush();
      // Same runtimeType + key: reconciled in place, no re-create, no dispose.
      expect(created, 1);
      expect(disposed, isEmpty);
      expect(values, ['v1', 'v1']);

      host.swap(describe('b'));
      owner.flush();
      // Key change: unmount + remount by substrate rules.
      expect(created, 2);
      expect(disposed, ['v1']);
      expect(values.last, 'v2');
    });
  });

  group('reconcile notification', () {
    test(
      '.value update notifies dependents once; an equal value is silent',
      () {
        final valueValues = <String?>[];
        final valueDependencyChanges = <int>[];
        final otherValues = <String?>[];
        final otherDependencyChanges = <int>[];
        late _ValueHostState host;
        final owner = TreeOwner();
        addTearDown(owner.dispose);

        owner.mountRoot(
          _ValueHost(
            onCreate: (state) => host = state,
            child: _ProbeChildren([
              _DependencyProbe(valueValues, valueDependencyChanges),
              _OtherDependencyProbe(otherValues, otherDependencyChanges),
            ]),
          ),
        );
        expect(valueValues, ['one']);
        expect(valueDependencyChanges, [1]);
        expect(otherValues, ['stable']);
        expect(otherDependencyChanges, [1]);

        host.update(_Value('one'));
        owner.flush();
        // Value-equal re-provide: InheritedSeed.updateShouldNotify declines.
        expect(valueDependencyChanges, [1]);
        expect(otherDependencyChanges, [1]);

        host.update(const _Value('two'));
        owner.flush();
        expect(valueDependencyChanges, [1, 2]);
        expect(valueValues.last, 'two');
        expect(otherDependencyChanges, [1]);
        expect(otherValues, ['stable']);
      },
    );
  });

  group('availability', () {
    test('watch is null when absent and the nearest provider shadows', () {
      final shadowed = <String?>[];
      final owner = TreeOwner();
      owner.mountRoot(
        Nest(
          children: [
            Provider<_Value>.value(const _Value('outer')),
            Provider<_Value>.value(const _Value('inner')),
          ],
          child: _Watch(shadowed),
        ),
      );
      expect(shadowed, ['inner']);
      owner.dispose();

      final absent = <String?>[];
      final absentOwner = TreeOwner();
      absentOwner.mountRoot(ProviderScope(child: _Watch(absent)));
      expect(absent, [null]);
      absentOwner.dispose();
    });

    test('a watch miss parks a pending registration the scope notifies on '
        'every later provider mount', () {
      final values = <String?>[];
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            // The dependent: a stable subtree nothing below ever re-describes.
            _Watch(values),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null]);

      // A Provider<_Value> mounts in the SIBLING slot. The scope's pending
      // registration is the ONLY edge that can reach the parked watcher —
      // nothing in its own ancestry changed. It rebuilds; resolution stays
      // ancestral (nearest provider), so the sibling value is out of reach and
      // the posture remains null.
      slot.swap(
        () => Provider<_Value>.value(
          const _Value('sibling'),
          child: const _Leaf(),
        ),
      );
      owner.flush();
      expect(values, [null, null]);

      // Unmount the sibling provider: the watcher holds no live edge to it,
      // so nothing pings the watcher.
      slot.swap(() => const _Leaf());
      owner.flush();
      expect(values, [null, null]);

      // The miss re-registered on the previous rebuild: a SECOND mount pings
      // the same parked watcher again.
      slot.swap(
        () =>
            Provider<_Value>.value(const _Value('again'), child: const _Leaf()),
      );
      owner.flush();
      expect(values, [null, null, null]);
    });

    test('availability is bidirectional: provider mount moves the dependent '
        'null-to-value and unmount moves it value-to-null', () {
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      final watcher = _Watch(values);
      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => watcher,
          ),
        ),
      );
      expect(values, [null]);

      host.swap(
        () => Provider<_Value>.value(const _Value('armed'), child: watcher),
      );
      owner.flush();
      expect(values, [null, 'armed']);

      host.swap(() => watcher);
      owner.flush();
      expect(values, [null, 'armed', null]);
    });

    test('read is the snapshot verb: no live edge, no pending registration', () {
      final builds = <int>[];
      late _ReadProbeState reader;
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _ReadProbe(onCreate: (state) => reader = state, builds: builds),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(builds, [1]);
      expect(reader.readValue(), isNull);

      // A provider of the missed type mounts: a WATCH miss would have parked a
      // pending registration and this mount would rebuild the reader. read<T>
      // registered NOTHING — the reader stays untouched.
      slot.swap(
        () =>
            Provider<_Value>.value(const _Value('late'), child: const _Leaf()),
      );
      owner.flush();
      expect(builds, [1]);
    });

    test('read sees a re-provided value without subscribing', () {
      final builds = <int>[];
      late _ValueHostState host;
      late _ReadProbeState reader;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _ValueHost(
          onCreate: (state) => host = state,
          child: _ReadProbe(
            onCreate: (state) => reader = state,
            builds: builds,
          ),
        ),
      );
      expect(builds, [1]);
      expect(reader.readValue(), 'one');

      host.update(const _Value('two'));
      owner.flush();
      // The snapshot moved with the tree; the reader itself never rebuilt.
      expect(reader.readValue(), 'two');
      expect(builds, [1]);
    });
  });

  group('composition', () {
    test('two providers under one Nest both resolve for the child', () {
      final values = <Object?>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        Nest(
          children: [
            Provider<_Value>.value(const _Value('first')),
            Provider<_Other>.value(const _Other('second')),
          ],
          child: _WatchBoth(values),
        ),
      );
      expect(values, ['first', 'second']);
    });
  });
}
