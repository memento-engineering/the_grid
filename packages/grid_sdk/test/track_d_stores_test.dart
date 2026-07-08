// Track D (tg-y1b): stores at roots + the substation initialization flow.
//
// Model clauses under test (SCRATCH-station-config-model.md v3, ratified):
// - Q5a: the grid STATE store lives under `<grid.root>/.grid/` (the station lock
//   colocates); a substation WORK store is `<root>/.beads/`; `.beads/` means
//   work store uniformly, everywhere; the dual-role repo has no collision.
// - `.beads/` is looked for EXACTLY at a root — never a walk-up (the ambience
//   fossil, §7 item 9); a substation whose root has no store is a LOUD refusal.
// - Q-mig: the substation init flow (seed a new store at a root, adopt its
//   prefix, mount it in the tree) ships as code + a documented process.
// - A37 (restated, no pseudo-substation): the state store is NOT a substation;
//   sessions/cursors write only to the grid store (a distinct type + location).
import 'package:grid_sdk/grid_sdk.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('store locations derive at roots (Q5a)', () {
    test('GridStateStore: state + lock colocate under <gridRoot>/.grid/', () {
      final s = GridStateStore.forGridRoot('/home/space_station');
      expect(s.runtimeDir, '/home/space_station/.grid');
      expect(s.beadsDir, '/home/space_station/.grid/.beads');
      expect(s.lockPath, '/home/space_station/.grid/station.lock');
      // The lock lives INSIDE the runtime dir, beside the state store.
      expect(p.dirname(s.lockPath), s.runtimeDir);
      expect(p.dirname(s.beadsDir), s.runtimeDir);
    });

    test('SubstationWorkStore: `.beads/` at the root, uniformly', () {
      expect(
        SubstationWorkStore.forRoot('/work/the_grid').beadsDir,
        '/work/the_grid/.beads',
      );
      // Uniform: the dir name never varies with the substation's name/identity.
      expect(
        SubstationWorkStore.forRoot('/anywhere/else').beadsDir,
        '/anywhere/else/.beads',
      );
    });

    test('the dual-role repo: grid root == substation root, NO collision', () {
      const shared = '/home/space_station';
      final state = GridStateStore.forGridRoot(shared);
      final work = SubstationWorkStore.forRoot(shared);
      // State under .grid/, work at .beads/ — different dirs at the same root.
      expect(state.beadsDir, '/home/space_station/.grid/.beads');
      expect(work.beadsDir, '/home/space_station/.beads');
      expect(state.beadsDir, isNot(work.beadsDir));
      // The state store's `.beads/` is NOT the work `.beads/` — it nests one
      // level under `.grid/`, so `.beads/`-at-a-root stays the work store.
      expect(p.isWithin(state.runtimeDir, state.beadsDir), isTrue);
      expect(p.isWithin(state.runtimeDir, work.beadsDir), isFalse);
    });

    test('non-absolute roots refuse LOUD (both store types)', () {
      expect(
        () => GridStateStore.forGridRoot('relative'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SubstationWorkStore.forRoot(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('value equality (plain value types)', () {
      expect(
        const GridStateStore(gridRoot: '/g'),
        const GridStateStore(gridRoot: '/g'),
      );
      expect(
        const SubstationWorkStore(root: '/w'),
        const SubstationWorkStore(root: '/w'),
      );
      expect(
        const SubstationWorkStore(root: '/w'),
        isNot(const SubstationWorkStore(root: '/x')),
      );
    });
  });

  group('stores derive from the Track B scopes', () {
    test('GridRoot.stateStore / SubstationScope.workStore', () {
      expect(
        const GridRoot(path: '/g').stateStore,
        const GridStateStore(gridRoot: '/g'),
      );
      expect(
        const SubstationScope(name: 'tg', root: '/w/tg', prefix: 'tg').workStore,
        const SubstationWorkStore(root: '/w/tg'),
      );
    });
  });

  group('discovery: exact-at-root, LOUD refusal (never a walk-up)', () {
    test('a present store at the root is located', () {
      final locator = StoreLocator(
        dirExists: (path) => path == '/work/tg/.beads',
      );
      expect(
        locator.locateWorkStore(root: '/work/tg', substationName: 'tg'),
        const SubstationWorkStore(root: '/work/tg'),
      );
    });

    test('an absent store at the root refuses LOUD (StoreRefusal)', () {
      final locator = StoreLocator(dirExists: (_) => false);
      expect(
        () => locator.locateWorkStore(root: '/work/tg', substationName: 'tg'),
        throwsA(
          isA<StoreRefusal>()
              .having((e) => e.message, 'message', contains('/work/tg'))
              .having(
                (e) => e.message,
                'names the invariant',
                contains('work store uniformly'),
              ),
        ),
      );
    });

    test('NO walk-up: a store at the PARENT does not satisfy the child', () {
      // Only the parent has `.beads/`; the substation root does not. The
      // fossil (BeadsWorkspace.discover) would walk up and find it — the v3
      // locator must NOT, so this is a refusal.
      final locator = StoreLocator(dirExists: (path) => path == '/work/.beads');
      expect(
        () => locator.locateWorkStore(root: '/work/tg'),
        throwsA(isA<StoreRefusal>()),
      );
    });

    test('grid state store existence is a probe, not a refusal', () {
      final state = GridStateStore.forGridRoot('/g');
      final absent = StoreLocator(dirExists: (_) => false);
      final present = StoreLocator(dirExists: (path) => path == state.beadsDir);
      expect(absent.gridStateStoreExists(state), isFalse);
      expect(present.gridStateStoreExists(state), isTrue);
    });
  });

  group('substation initialization flow (Q-mig)', () {
    test('seed → adopt prefix → yield a mountable substation', () async {
      final seeded = <({String root, String prefix})>[];
      // A stateful probe: no store before the seed, a store after it (the seeder
      // records the intent; the probe flips to reflect a real bd init).
      var created = false;
      final init = SubstationInitializer(
        dirExists: (path) => created && path == '/work/new/.beads',
        seed: ({required root, required prefix}) async {
          seeded.add((root: root, prefix: prefix));
          created = true;
        },
      );

      final result = await init.initSubstation(
        root: '/work/new',
        name: 'newsub',
      );

      // The prefix ADOPTED is the substation name (name == id-prefix axis).
      expect(seeded.single, (root: '/work/new', prefix: 'newsub'));
      expect(result.name, 'newsub');
      expect(result.store.beadsDir, '/work/new/.beads');

      // "Mount it in the tree": toSeed() yields the Track B Substation, keyed
      // by name, carrying the author's assets.
      final seed = result.toSeed(assets: const [_Marker()]);
      expect(seed, isA<Substation>());
      final sub = seed as Substation;
      expect(sub.name, 'newsub');
      expect(sub.root, '/work/new');
      expect(sub.assets, const [_Marker()]);
      expect(sub.key, const ValueKey<String>('substation:newsub'));
    });

    test('refuses to clobber an existing store (LOUD, no re-seed)', () async {
      var seedCalled = false;
      final init = SubstationInitializer(
        dirExists: (_) => true, // a store already exists at the root
        seed: ({required root, required prefix}) async => seedCalled = true,
      );
      await expectLater(
        init.initSubstation(root: '/work/existing', name: 'tg'),
        throwsA(
          isA<StoreRefusal>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
      expect(seedCalled, isFalse, reason: 'no seed once a store is present');
    });

    test(
      'refuses when the seed silently produced no store (post-verify)',
      () async {
        final init = SubstationInitializer(
          dirExists: (_) => false, // never appears, even after "seeding"
          seed: ({required root, required prefix}) async {}, // no-op
        );
        await expectLater(
          init.initSubstation(root: '/work/new', name: 'tg'),
          throwsA(
            isA<StoreRefusal>().having(
              (e) => e.message,
              'message',
              contains('no store'),
            ),
          ),
        );
      },
    );

    test(
      'validates the root (absolute) and the name (a prefix token)',
      () async {
        final init = SubstationInitializer(
          dirExists: (_) => false,
          seed: ({required root, required prefix}) async {},
        );
        await expectLater(
          init.initSubstation(root: 'relative', name: 'tg'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          init.initSubstation(root: '/w', name: ''),
          throwsA(isA<ArgumentError>()),
        );
        // A name with whitespace / separators cannot be a store id-prefix.
        await expectLater(
          init.initSubstation(root: '/w', name: 'space station'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          init.initSubstation(root: '/w', name: 'a/b'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });

  group('A37 restated: the state store is NOT a substation', () {
    test('distinct types + locations; toSeed only exists for substations', () {
      // The grid state store is grid-scoped, under `.grid/`, and never yields a
      // Substation (it is not in the fan-out). A substation's work store is a
      // distinct type at `.beads/`. Sessions/cursors target the grid store via
      // the chokepoint — never a substation work source (read-only, A37).
      final state = GridStateStore.forGridRoot('/home/space_station');
      final work = SubstationWorkStore.forRoot('/home/space_station');
      expect(state, isNot(isA<SubstationWorkStore>()));
      expect(work, isNot(isA<GridStateStore>()));
      expect(state.beadsDir, isNot(work.beadsDir));
      // The init flow ONLY produces work substations — there is no init flow
      // that mounts the state store as a substation.
      expect(
        const SubstationInitResult(
          name: 'x',
          root: '/home/space_station',
        ).toSeed(),
        isA<Substation>(),
      );
    });
  });
}

/// A marker asset — proves the author's assets ride through `toSeed`. `const`
/// instances are canonicalized, so the list-equality check compares by identity.
class _Marker extends StatelessSeed {
  const _Marker();

  @override
  Seed build(TreeContext context) => const Leaf();
}

/// A terminal leaf (an empty fan-out) — the marker never mounts, but `build`
/// must return a Seed.
class Leaf extends MultiChildSeed {
  const Leaf({super.key}) : super(children: const []);
}
