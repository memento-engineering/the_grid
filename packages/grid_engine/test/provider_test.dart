import 'dart:async';

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

final class _Third {
  const _Third();
}

/// The distinguishable failure a throwing `create` raises — never a
/// [StateError], so a test rethrow assertion cannot be satisfied by one of the
/// provider's own guard throws.
final class _Boom implements Exception {
  const _Boom();
}

/// An ADOPTED instance carrying a dispose spy: it exposes the canonical
/// `dispose()` protocol a wrong tree implementation would reach for (an
/// auto-dispose of disposable-looking adopted values, or a disposal wrongly
/// armed for a `.value` provider), and records into the shared events list so
/// an erroneous call also corrupts the events-order assertion. The
/// falsifiable channel for "adopted values are never disposed".
final class _DisposeSpy {
  _DisposeSpy(this.events);

  final List<String> events;
  bool disposed = false;

  void dispose() {
    disposed = true;
    events.add('dispose adopted');
  }
}

/// Watches the owned `_Value` and the adopted `_DisposeSpy` — the dependent
/// that keeps both providers' branches genuinely load-bearing while mounted.
final class _SpyWatch extends StatelessSeed {
  const _SpyWatch(this.values);
  final List<Object?> values;

  @override
  Seed build(TreeContext context) {
    values
      ..add(context.watch<_Value>()?.name)
      ..add(context.watch<_DisposeSpy>() != null);
    return const _Leaf();
  }
}

/// Drains the event queue (and with it the microtask queue): the availability
/// registry delivers its notifications from a microtask scheduled during the
/// announcing flush, so tests pump, then flush again to observe the rebuild.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

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

/// Depends with an aspect and records the substrate's rejection instead of
/// propagating it, so the mount completes and the provider branch's
/// bookkeeping stays observable.
final class _AspectWatch extends StatelessSeed {
  const _AspectWatch(this.errors);
  final List<ArgumentError> errors;

  @override
  Seed build(TreeContext context) {
    try {
      context.dependOnInheritedSeedOfExactType<_Value>(aspect: 'name');
    } on ArgumentError catch (error) {
      errors.add(error);
    }
    return const _Leaf();
  }
}

/// The registry-branch counterpart of [_AspectWatch]: an aspect-scoped depend
/// on the scope's own provided value.
final class _RegistryAspectWatch extends StatelessSeed {
  const _RegistryAspectWatch(this.errors);
  final List<ArgumentError> errors;

  @override
  Seed build(TreeContext context) {
    try {
      context.dependOnInheritedSeedOfExactType<AvailabilityRegistry>(
        aspect: 'name',
      );
    } on ArgumentError catch (error) {
      errors.add(error);
    }
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

/// A watcher whose OWN branch can be dirtied directly ([poke]) — the shape
/// that lands the watch-calling branch itself in the owner's drained set, as
/// opposed to being force-rebuilt by a parent's update cascade.
final class _PokableWatch extends StatefulSeed {
  const _PokableWatch({required this.onCreate, required this.values});

  final void Function(_PokableWatchState state) onCreate;
  final List<String?> values;

  @override
  State<_PokableWatch> createState() {
    final state = _PokableWatchState();
    onCreate(state);
    return state;
  }
}

final class _PokableWatchState extends State<_PokableWatch> {
  void poke() => setState(() {});

  @override
  Seed build(TreeContext context) {
    seed.values.add(context.watch<_Value>()?.name);
    return const _Leaf();
  }
}

/// A watcher whose interest set CHANGES across rebuilds: it watches both
/// types until [retarget], only `_Other` after — the shape that leaves a
/// stale parked registration behind unless the release semantics consume it.
final class _RetargetingWatch extends StatefulSeed {
  const _RetargetingWatch({required this.onCreate, required this.values});

  final void Function(_RetargetingWatchState state) onCreate;
  final List<Object?> values;

  @override
  State<_RetargetingWatch> createState() {
    final state = _RetargetingWatchState();
    onCreate(state);
    return state;
  }
}

final class _RetargetingWatchState extends State<_RetargetingWatch> {
  bool _watchValue = true;

  void retarget() => setState(() => _watchValue = false);

  @override
  Seed build(TreeContext context) {
    if (_watchValue) seed.values.add(context.watch<_Value>()?.name);
    seed.values.add(context.watch<_Other>()?.name);
    return const _Leaf();
  }
}

/// A bare mounted-looking [Branch] fake for driving [AvailabilityRegistry]
/// directly: records [dependencyChanged] instead of scheduling, and reports
/// whatever mountedness the test sets (a Fake, not a mock — house rules).
final class _RecordingDependent extends Branch {
  _RecordingDependent() : super(const _Leaf());

  bool isMounted = true;
  int pings = 0;

  @override
  bool get mounted => isMounted;

  @override
  void dependencyChanged() => pings++;
}

/// A Fake dependent whose [dependencyChanged] THROWS — the batch-poisoning
/// shape for the delivery isolation tests.
final class _ThrowingDependent extends Branch {
  _ThrowingDependent() : super(const _Leaf());

  int pings = 0;

  @override
  bool get mounted => true;

  @override
  void dependencyChanged() {
    pings++;
    throw const _Boom();
  }
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

/// Records a last effect-path read during its own teardown — the
/// substrate-endorsed get-lookup from `State.dispose` ("a last read during
/// teardown", stateful.dart's dispose guard), which must observe a value the
/// tree has NOT yet disposed.
final class _TeardownRead extends StatefulSeed {
  const _TeardownRead(this.events);
  final List<String> events;

  @override
  State<_TeardownRead> createState() => _TeardownReadState();
}

final class _TeardownReadState extends State<_TeardownRead> {
  @override
  Seed build(TreeContext context) => const _Leaf();

  @override
  void dispose() {
    seed.events.add('teardown read ${context.read<_Value>()?.name}');
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
      // The adopted instance is TEST-held and carries a dispose spy: a tree
      // that wrongly disposed an adopted value WOULD record — the assertion
      // after unmount is falsifiable, not vacuous.
      final spy = _DisposeSpy(events);
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
            // Adopted: owner-held; ownership follows construction, so the
            // tree must leave the spy's dispose() untouched at unmount.
            Provider<_DisposeSpy>.value(spy),
          ],
          child: _SpyWatch(values),
        ),
      );
      expect(values, ['owned', true]);
      expect(events, ['create']);

      owner.dispose();
      // Ordering channel: a wrong adopted-dispose would also inject
      // 'dispose adopted' here and break the exact-events assertion.
      expect(events, ['create', 'dispose owned']);
      expect(
        spy.disposed,
        isFalse,
        reason:
            'an adopted value is held by its owner; the tree never '
            'disposes what it did not create',
      );
    });

    test('owned values dispose AFTER the subtree, inner before outer', () {
      final events = <String>[];
      final owner = TreeOwner();

      owner.mountRoot(
        Nest(
          children: [
            Provider<_Value>(
              create: (_) {
                events.add('create outer');
                return const _Value('outer');
              },
              dispose: (value) => events.add('dispose ${value.name}'),
            ),
            Provider<_Other>(
              // Constructed FROM the outer value — the dependency that makes
              // creation-order disposal unsound.
              create: (context) {
                events.add('create inner');
                return _Other('${context.read<_Value>()!.name}-derived');
              },
              dispose: (value) => events.add('dispose ${value.name}'),
            ),
          ],
          child: _TeardownRead(events),
        ),
      );
      expect(events, ['create outer', 'create inner']);

      owner.dispose();
      // Teardown is subtree-first: the descendant's State.dispose reads a
      // still-live owned value, then the chain disposes inner-before-outer —
      // REVERSE creation order, so the derived inner value goes down before
      // the outer value it was built from.
      expect(events, [
        'create outer',
        'create inner',
        'teardown read outer',
        'dispose outer-derived',
        'dispose outer',
      ]);
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

  group('failed mount unwind', () {
    test('a throwing create disposes the chain values already created — '
        'reverse creation order — and rethrows', () {
      // The substrate strands every branch mounted within the failed
      // reconcile (updateChild propagates before the child-slot assignment,
      // so unmount — the disposal site — never runs). The provider unwind
      // must dispose each already-created owned value as the error passes
      // its mount frame: innermost link first, the old ProviderScope
      // reverse-order contract.
      final events = <String>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose); // The root never mounted; dispose is a no-op.

      expect(
        () => owner.mountRoot(
          Nest(
            children: [
              Provider<_Value>(
                create: (_) {
                  events.add('create outer');
                  return const _Value('outer');
                },
                dispose: (value) => events.add('dispose ${value.name}'),
              ),
              Provider<_Other>(
                create: (context) {
                  events.add('create inner');
                  return _Other('${context.read<_Value>()!.name}-derived');
                },
                dispose: (value) => events.add('dispose ${value.name}'),
              ),
              Provider<_Third>(create: (_) => throw const _Boom()),
            ],
            child: const _Leaf(),
          ),
        ),
        throwsA(isA<_Boom>()),
      );
      expect(events, [
        'create outer',
        'create inner',
        'dispose outer-derived',
        'dispose outer',
      ]);
    });

    test('a failed mid-flush mount disposes an already-created ancestor '
        'value exactly once', () {
      final events = <String>[];
      late _HostState host;
      final owner = TreeOwner();
      // Deliberately NO owner.dispose teardown: a failed mid-flush reconcile
      // leaves the host's child slot pointing at the branch it already
      // unmounted (the assignment was skipped), so a root unmount cascade
      // would trip the substrate's double-unmount assert. The exactly-once
      // claim is carried by the events list instead.

      owner.mountRoot(
        _Host(onCreate: (state) => host = state, describe: () => const _Leaf()),
      );

      host.swap(
        () => Provider<_Value>(
          create: (_) {
            events.add('create');
            return const _Value('doomed');
          },
          dispose: (_) => events.add('dispose'),
          child: Provider<_Third>(
            create: (_) => throw const _Boom(),
            child: const _Leaf(),
          ),
        ),
      );
      expect(owner.flush, throwsA(isA<_Boom>()));
      expect(events, ['create', 'dispose']);
    });

    test('a create that throws on its own leaves nothing to dispose and '
        'rethrows the original error', () {
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      expect(
        () => owner.mountRoot(
          Provider<_Value>(
            create: (_) => throw const _Boom(),
            child: const _Leaf(),
          ),
        ),
        throwsA(isA<_Boom>()),
      );
    });
  });

  group('kind-swap guard', () {
    test('a mounted create-provider reconciled with .value throws '
        'StateError', () {
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _Host(
          onCreate: (state) => host = state,
          describe: () => Provider<_Value>(
            create: (_) => const _Value('owned'),
            child: _Watch(values),
          ),
        ),
      );
      expect(values, ['owned']);

      // Same runtimeType + key at the same slot: the substrate reconciles in
      // place, so the kind flip must be refused loudly — silently adopting
      // would shadow the owned value while its unmount disposal stays armed.
      host.swap(
        () => Provider<_Value>.value(
          const _Value('adopted'),
          child: _Watch(values),
        ),
      );
      expect(owner.flush, throwsStateError);
    });

    test('a mounted .value provider reconciled with create throws '
        'StateError', () {
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _Host(
          onCreate: (state) => host = state,
          describe: () => Provider<_Value>.value(
            const _Value('adopted'),
            child: _Watch(values),
          ),
        ),
      );
      expect(values, ['adopted']);

      host.swap(
        () => Provider<_Value>(
          create: (_) => const _Value('owned'),
          child: _Watch(values),
        ),
      );
      expect(owner.flush, throwsStateError);
    });

    test('a failing rebuild of an ATTACHED provider does not run the '
        'failed-mount unwind: the value stays live for the real unmount', () {
      final events = <String>[];
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();

      owner.mountRoot(
        _Host(
          onCreate: (state) => host = state,
          describe: () => Provider<_Value>(
            create: (_) => const _Value('owned'),
            dispose: (value) => events.add('dispose ${value.name}'),
            child: _Watch(values),
          ),
        ),
      );
      expect(values, ['owned']);

      // The kind flip throws INSIDE the attached provider's rebuild frame.
      // The mount-only guard ([_ProviderBranch._mountBuild]) must keep the
      // unwind out of this path: disposing here would leave the branch
      // attached over a dead value AND double-dispose at the real unmount.
      host.swap(
        () => Provider<_Value>.value(
          const _Value('adopted'),
          child: _Watch(values),
        ),
      );
      expect(owner.flush, throwsStateError);
      expect(
        events,
        isEmpty,
        reason: 'a failed ATTACHED rebuild must not dispose the live value',
      );

      owner.dispose();
      expect(events, [
        'dispose owned',
      ], reason: 'disposal rides the real unmount, exactly once');
    });
  });

  group('scope-less composition', () {
    test('a watch miss with no ProviderScope ancestor asserts, naming '
        'ProviderScope; read stays a silent null', () {
      final values = <String?>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      // The debug guard (watch<T> miss, no availability registry to park
      // with) fails LOUD in development; deleting the assert would leave a
      // mis-composed tree returning null forever with no signal.
      expect(
        () => owner.mountRoot(_Watch(values)),
        throwsA(
          isA<AssertionError>().having(
            (error) => '${error.message}',
            'message',
            contains('ProviderScope'),
          ),
        ),
      );

      // The effect verb stays silent on the same scope-less shape: a
      // one-shot snapshot has nothing to park and nothing to assert.
      final builds = <int>[];
      late _ReadProbeState reader;
      final readOwner = TreeOwner();
      addTearDown(readOwner.dispose);
      readOwner.mountRoot(
        _ReadProbe(onCreate: (state) => reader = state, builds: builds),
      );
      expect(reader.readValue(), isNull);
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
        'every later provider mount', () async {
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
      // nothing in its own ancestry changed. Notification is DEFERRED past
      // the announcing flush (the mount runs mid-flush; re-dirtying a branch
      // that pass already built would trip the substrate invariant), so the
      // rebuild lands in the NEXT flush after the microtask delivers. It
      // rebuilds; resolution stays ancestral (nearest provider), so the
      // sibling value is out of reach and the posture remains null.
      slot.swap(
        () => Provider<_Value>.value(
          const _Value('sibling'),
          child: const _Leaf(),
        ),
      );
      owner.flush();
      expect(values, [null], reason: 'delivery is deferred past the flush');
      await _pump();
      owner.flush();
      expect(values, [null, null]);

      // Unmount the sibling provider: the watcher holds no live edge to it,
      // so nothing pings the watcher.
      slot.swap(() => const _Leaf());
      owner.flush();
      await _pump();
      owner.flush();
      expect(values, [null, null]);

      // The miss re-registered on the previous rebuild: a SECOND mount pings
      // the same parked watcher again.
      slot.swap(
        () =>
            Provider<_Value>.value(const _Value('again'), child: const _Leaf()),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(values, [null, null, null]);
    });

    test('the pending drain is TYPE-SCOPED: a provider mount of a different '
        'type leaves a parked watcher untouched', () async {
      final values = <String?>[];
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _Watch(values),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null]);
      final registry = slot.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Value), hasLength(1));

      // A Provider<_Other> mounts in the sibling slot. The watcher is parked
      // under _Value; the mount drains only the pending set keyed by ITS type,
      // so no ping reaches the watcher — no rebuild, and the registration
      // stays parked under the missed type.
      slot.swap(
        () => Provider<_Other>.value(
          const _Other('unrelated'),
          child: const _Leaf(),
        ),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(values, [null], reason: 'no cross-type ping, no rebuild');
      expect(
        registry.debugPendingOf(_Value),
        hasLength(1),
        reason: 'the registration stays parked under its own type',
      );
    });

    test('a provider mount later in the SAME flush that already rebuilt a '
        'parked watcher defers the ping instead of re-dirtying it', () async {
      // Regression for the substrate flush invariant
      // (TreeOwner.scheduleRebuildFor: a branch must not be re-dirtied after
      // it was built in the in-progress pass). The watcher's own setState and
      // the provider-mounting swap land in ONE flush; depth/branchId order
      // drains the watcher first, so a synchronous pending-notify from the
      // provider's mount would re-dirty an already-built branch and crash
      // every asserts-enabled run.
      final values = <String?>[];
      late _PokableWatchState watcher;
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _PokableWatch(onCreate: (state) => watcher = state, values: values),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null]);

      watcher.poke();
      slot.swap(
        () => Provider<_Value>.value(
          const _Value('same-flush'),
          child: const _Leaf(),
        ),
      );
      owner.flush(); // Must not throw: the ping is deferred, not synchronous.
      expect(values, [null, null]);

      // The deferred notification delivers after the pass; the watcher
      // rebuilds in the next flush and, resolution being ancestral, the
      // sibling value stays out of reach.
      await _pump();
      owner.flush();
      expect(values, [null, null, null]);
    });

    test(
      'remount across a provider boundary moves the watcher null-to-value '
      'and back — the unmount/remount path, not registry notification',
      () async {
        // Honest scope note: swapping the child between `watcher` and
        // `Provider(child: watcher)` changes the runtimeType at the slot, so
        // the substrate unmounts the old _Watch branch and mounts a FRESH one
        // each time (canUpdate false). Every transition below is an initial
        // build of a new branch; on this no-reparent substrate a watcher can
        // never keep its branch across its provider's (un)mount, so this IS the
        // path a null-to-value or value-to-null transition actually rides. The
        // registry's genuine notification mechanism is pinned by the pending-
        // registration tests above and the direct-seam tests below.
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

        // No stray deferred pings land afterwards: the unmount announcement's
        // recipients went down with the provider subtree and are skipped by the
        // delivery's mounted guard.
        await _pump();
        owner.flush();
        expect(values, [null, 'armed', null]);
      },
    );

    test('an unmounting provider ANNOUNCES its collected live dependents to '
        'the registry — the transmit side of the bidirectional '
        'contract', () async {
      final left = <String?>[];
      final right = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => Provider<_Value>.value(
              const _Value('held'),
              child: _Slots([_Watch(left), _Watch(right)]),
            ),
          ),
        ),
      );
      expect(left, ['held']);
      expect(right, ['held']);
      final registry = host.context.read<AvailabilityRegistry>()!;
      expect(registry.debugNotifying, isEmpty);

      // Swap the provider subtree out. The provider branch must hand the
      // registry the live dependents it mirrored through addDependent: both
      // watcher branches land in the deferred delivery queue, observable
      // between the announcing flush and the delivery microtask.
      host.swap(() => const _Leaf());
      owner.flush();
      expect(
        registry.debugNotifying,
        hasLength(2),
        reason: 'both live dependents were announced',
      );
      expect(
        registry.debugNotifying.any((branch) => branch.mounted),
        isFalse,
        reason:
            'recipients went down with the subtree (no-reparent '
            'substrate); delivery will skip them on the mounted guard',
      );

      await _pump();
      expect(registry.debugNotifying, isEmpty, reason: 'the queue drains');
      expect(left, ['held'], reason: 'a dead recipient is never pinged');
      expect(right, ['held']);
    });

    test('the registry never retains a watcher that unmounted with its '
        'provider subtree', () async {
      // Leak regression: the old unmount announcement re-parked live
      // dependents into the pending map directly; a dependent that then
      // unmounted with the subtree released its PROVIDER edge, not a registry
      // edge, so the dead branch (and everything its State captured) stayed
      // in the scope-lifetime pending map forever.
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => Provider<_Value>.value(
              const _Value('held'),
              child: _Watch(values),
            ),
          ),
        ),
      );
      expect(values, ['held']);
      final registry = host.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Value), isEmpty);

      // The watcher holds a LIVE edge on the provider branch and unmounts
      // with it when the subtree swaps out.
      host.swap(() => const _Leaf());
      owner.flush();
      await _pump();
      owner.flush();
      expect(
        registry.debugPendingOf(_Value),
        isEmpty,
        reason: 'a dead dependent must not be parked on its way down',
      );
    });

    test('a parked watcher that unmounts is released from the pending map — '
        'the registry-branch dependency release', () {
      // The release path rides the substrate's own unmount bookkeeping: the
      // watch miss registered a dependency on the registry branch, so the
      // watcher's unmount reaches _RegistryBranch.removeDependent, which
      // drops the branch from every bucket (release semantics rule 3).
      final values = <String?>[];
      late _HostState slot;
      late _HostState watcherSlot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _Host(
              onCreate: (state) => watcherSlot = state,
              describe: () => _Watch(values),
            ),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null]);
      final registry = slot.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Value), hasLength(1));

      // Unmount ONLY the watcher (the scope stays up): the parked
      // registration must not survive the branch it belongs to.
      watcherSlot.swap(() => const _Leaf());
      owner.flush();
      expect(
        registry.debugPendingOf(_Value),
        isEmpty,
        reason: 'unmount releases the parked registration',
      );
    });

    test('a delivered ping consumes ALL of the recipient\'s parked '
        'registrations; its rebuild re-files only current interests', () async {
      // Release semantics rule 2, pinning the under-specified case: a branch
      // that rebuilt WITHOUT re-issuing watch<_Value> must not linger in the
      // _Value bucket past its next notification.
      final values = <Object?>[];
      late _RetargetingWatchState watcher;
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _RetargetingWatch(
              onCreate: (state) => watcher = state,
              values: values,
            ),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null, null]);
      final registry = slot.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Value), hasLength(1));
      expect(registry.debugPendingOf(_Other), hasLength(1));

      // The watcher rebuilds and stops watching _Value. No substrate hook
      // fires on the hook-free non-watch, so the stale _Value registration
      // survives THIS rebuild (the documented bounded posture)...
      watcher.retarget();
      owner.flush();
      expect(values, [null, null, null]);
      expect(registry.debugPendingOf(_Value), hasLength(1));

      // ...but the next delivered ping consumes it: a Provider<_Other> mount
      // in the sibling slot pings the watcher (parked under _Other), delivery
      // drops the branch from EVERY bucket, and the triggered rebuild
      // re-files only what the build still watches.
      slot.swap(
        () => Provider<_Other>.value(
          const _Other('sibling'),
          child: const _Leaf(),
        ),
      );
      owner.flush();
      await _pump();
      owner.flush();
      expect(values, [null, null, null, null]);
      expect(
        registry.debugPendingOf(_Value),
        isEmpty,
        reason: 'the stale interest must not outlive the next notification',
      );
      expect(
        registry.debugPendingOf(_Other),
        hasLength(1),
        reason: 'the current interest re-filed through the rebuild\'s miss',
      );
    });

    test('the mount-side drain removes the bucket AT the announcement, before '
        'delivery re-files anything', () async {
      // Pins providerMounted's remove-the-bucket semantics on its own: the
      // probe between the announcing flush and the delivery microtask sees an
      // EMPTY bucket (a drain that pinged without removing would show the old
      // registration still parked), and only the delivered rebuild's re-miss
      // re-files it.
      final values = <String?>[];
      late _HostState slot;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Slots([
            _Watch(values),
            _Host(
              onCreate: (state) => slot = state,
              describe: () => const _Leaf(),
            ),
          ]),
        ),
      );
      expect(values, [null]);
      final registry = slot.context.read<AvailabilityRegistry>()!;
      expect(registry.debugPendingOf(_Value), hasLength(1));

      slot.swap(
        () => Provider<_Value>.value(
          const _Value('sibling'),
          child: const _Leaf(),
        ),
      );
      owner.flush();
      expect(
        registry.debugPendingOf(_Value),
        isEmpty,
        reason: 'the drain consumed the bucket synchronously at the announce',
      );
      expect(registry.debugNotifying, hasLength(1));

      await _pump();
      owner.flush();
      expect(values, [null, null]);
      expect(
        registry.debugPendingOf(_Value),
        hasLength(1),
        reason: 'the rebuild\'s re-miss re-filed the registration',
      );
    });

    test('read is the snapshot verb: no live edge, no pending '
        'registration', () async {
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

      // Nor does the deferred delivery window reach it: read<T> queued
      // nothing, so pumping the microtask and flushing again is still silent.
      await _pump();
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

  group('availability registry (direct seam)', () {
    // The unmount-side announcement has no observable end-to-end effect on
    // this no-reparent substrate (a live dependent is always a descendant of
    // its provider and unmounts with it before delivery), so its contract
    // behavior is pinned HERE, against the registry itself, with a Fake
    // dependent.
    test('providerUnmounted pings surviving dependents — deferred, guarded '
        'on mounted, and never re-parked', () async {
      final registry = AvailabilityRegistry();
      final survivor = _RecordingDependent();
      final doomed = _RecordingDependent();

      registry.providerUnmounted(_Value, [survivor, doomed]);
      // Deferred: nothing is delivered inside the announcing pass.
      expect(survivor.pings, 0);
      expect(doomed.pings, 0);

      // The doomed dependent unmounts with the provider subtree before the
      // microtask runs — exactly what happens to every real dependent today.
      doomed.isMounted = false;

      await _pump();
      expect(survivor.pings, 1, reason: 'a survivor is notified');
      expect(doomed.pings, 0, reason: 'delivery guards on mounted');

      // Leak fix pinned at the unit level: the announcement re-parks NOTHING.
      // A genuine survivor re-registers pending through its own rebuild's
      // watch miss, which rides the registry-branch dependency path that IS
      // released at unmount.
      expect(registry.debugPendingOf(_Value), isEmpty);
    });

    test('one throwing dependent neither swallows the rest of the batch nor '
        'wedges the delivery guard', () async {
      final registry = AvailabilityRegistry();
      final thrower = _ThrowingDependent();
      final healthy = _RecordingDependent();
      final errors = <Object>[];

      // The delivery microtask is scheduled inside the guarded zone, so the
      // batch's rethrown failure lands in the zone handler — isolated from
      // the test's own zone, but NOT silenced.
      await runZonedGuarded(() async {
        registry.providerUnmounted(_Value, [thrower, healthy]);
        await _pump();
      }, (Object error, StackTrace stackTrace) => errors.add(error))!;

      expect(thrower.pings, 1);
      expect(
        healthy.pings,
        1,
        reason: 'the throw must not swallow the remaining notifications',
      );
      expect(errors, [
        isA<_Boom>(),
      ], reason: 'the failure is rethrown, not eaten');

      // Fail-closed flush guard: the throw did not wedge _deliveryScheduled —
      // a later announcement schedules and delivers a fresh batch.
      registry.providerUnmounted(_Other, [healthy]);
      await _pump();
      expect(healthy.pings, 2);
    });

    test('a second announcement in the same pass rides one delivery '
        'microtask', () async {
      final registry = AvailabilityRegistry();
      final dependent = _RecordingDependent();

      registry.providerUnmounted(_Value, [dependent]);
      registry.providerUnmounted(_Other, [dependent]);
      expect(dependent.pings, 0);

      await _pump();
      // The queue is a set and both announcements landed in one batch: the
      // dependent rebuilds once, not once per announcement.
      expect(dependent.pings, 1);
    });
  });

  group('aspect forwarding (genesis_tree 0.3.0)', () {
    test('a Provider REJECTS an aspect — the override reached super', () {
      final errors = <ArgumentError>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: Provider<_Value>.value(
            const _Value('held'),
            child: _AspectWatch(errors),
          ),
        ),
      );

      expect(errors, hasLength(1));
      expect(errors.single.name, 'aspect');
    });

    test('the REGISTRY branch rejects an aspect too', () {
      final errors = <ArgumentError>[];
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(ProviderScope(child: _RegistryAspectWatch(errors)));

      expect(errors, hasLength(1));
      expect(errors.single.name, 'aspect');
    });

    test('a rejected aspect leaves NO phantom live dependent', () {
      final errors = <ArgumentError>[];
      final values = <String?>[];
      late _HostState host;
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        ProviderScope(
          child: _Host(
            onCreate: (state) => host = state,
            describe: () => Provider<_Value>.value(
              const _Value('held'),
              child: _Slots([_Watch(values), _AspectWatch(errors)]),
            ),
          ),
        ),
      );
      expect(values, ['held'], reason: 'the aspect-free watcher resolved');
      expect(errors, hasLength(1), reason: 'the aspect-scoped one was refused');
      final registry = host.context.read<AvailabilityRegistry>()!;

      host.swap(() => const _Leaf());
      owner.flush();
      expect(
        registry.debugNotifying,
        hasLength(1),
        reason:
            'only the aspect-free watcher became a dependent; the refused '
            'branch must never have entered _live',
      );
    });
  });
}
