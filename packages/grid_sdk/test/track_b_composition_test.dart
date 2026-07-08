// Track B (tg-vrz): the composition Seeds, pure and offline.
//
// Model clauses under test (SCRATCH-station-config-model.md v3, ratified):
// - "a store lives at a root; substation = project = name + ONE root" (§0/§3)
// - Station.root optional, defaulting to grid.root (§3)
// - validation lives in the types — an invalid composition refuses LOUD,
//   never defaults (§0: "unresolvable input = loud refusal")
// - the canonical §2 tree shape composes with Nest + conditionals + composed
//   substations (composition, never subclassing — ADR-0008 D2).
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// Runs [probe] against a live TreeContext at build time.
class OfProbe extends StatelessSeed {
  const OfProbe(this.probe, {super.key});

  final void Function(TreeContext) probe;

  @override
  Seed build(TreeContext context) {
    probe(context);
    return const Leaf();
  }
}

/// A terminal leaf (an empty fan-out).
class Leaf extends MultiChildSeed {
  const Leaf({super.key}) : super(children: const []);
}

/// A grid-provider stand-in: any [SingleChildStatelessSeed] is Nest-able.
class ProviderStandIn extends SingleChildStatelessSeed {
  const ProviderStandIn({super.child, super.key});

  @override
  Seed buildWithChild(TreeContext context, Seed child) => child;
}

/// A probe leaf that captures the ambient scopes it mounts under.
class ScopeProbe extends StatelessSeed {
  const ScopeProbe(this.seen, {super.key});

  final List<({GridRoot? grid, StationScope? station, SubstationScope? sub})>
  seen;

  @override
  Seed build(TreeContext context) {
    seen.add((
      grid: GridRoot.maybeOf(context),
      station: StationScope.maybeOf(context),
      sub: SubstationScope.maybeOf(context),
    ));
    return const Leaf();
  }
}

/// v3 §2's ButaneDevelopmentSubstation shape: a COMPOSED substation — a seed
/// whose build returns a Substation (never a subclass of it).
class ComposedSubstation extends StatelessSeed {
  const ComposedSubstation({
    required this.root,
    required this.probe,
    super.key,
  });

  final String root;
  final List<({GridRoot? grid, StationScope? station, SubstationScope? sub})>
  probe;

  @override
  Seed build(TreeContext context) {
    // Composed substations read ambient state before building (v3 §2 reads
    // config/targets; here the ambient StationScope proves context flows).
    final station = StationScope.of(context);
    return Substation(
      name: 'composed-under-${station.name}',
      root: root,
      assets: [ScopeProbe(probe)],
    );
  }
}

void mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(root);
  owner.flush();
}

void main() {
  group('validation lives in the types (loud refusal, never a default)', () {
    test('RawAssetGrid refuses an empty root', () {
      expect(
        () => mount(const RawAssetGrid(root: '')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('RawAssetGrid refuses a cwd-relative root (the ambience fossil)', () {
      expect(
        () => mount(const RawAssetGrid(root: 'relative/grid')),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('ABSOLUTE'),
          ),
        ),
      );
    });

    test('Substation refuses an empty name and a relative root', () {
      expect(
        () => mount(Substation(name: '', root: '/w')),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => mount(Substation(name: 'tg', root: 'w')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Station with no root and no enclosing RawAssetGrid refuses LOUD',
        () {
      expect(
        () => mount(const Station(name: 'orphan')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no default root'),
          ),
        ),
      );
    });

    test('scope lookups outside their scopes: maybeOf is null', () {
      final seen =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      mount(ScopeProbe(seen));
      expect(seen.single.grid, isNull);
      expect(seen.single.station, isNull);
      expect(seen.single.sub, isNull);
    });

    test('of() outside its scope throws StateError (loud, all three)', () {
      mount(
        OfProbe((ctx) {
          expect(() => GridRoot.of(ctx), throwsStateError);
          expect(() => StationScope.of(ctx), throwsStateError);
          expect(() => SubstationScope.of(ctx), throwsStateError);
        }),
      );
    });

    test('a consumer-authored GridRoot cannot default a bad root into a '
        'Station (re-validated at the mount point)', () {
      expect(
        () => mount(
          InheritedSeed<GridRoot>(
            value: const GridRoot(path: 'relative'),
            child: const Station(name: 'x'),
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('scoping + defaulting (v3 §3)', () {
    test('Station.root defaults to the ambient grid root', () {
      final seen =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      mount(
        RawAssetGrid(
          root: '/grid/home',
          assets: [
            Station(name: 'mbp', assets: [ScopeProbe(seen)]),
          ],
        ),
      );
      expect(seen.single.grid, const GridRoot(path: '/grid/home'));
      expect(
        seen.single.station,
        const StationScope(name: 'mbp', root: '/grid/home'),
      );
    });

    test('an explicit Station.root overrides the grid root', () {
      final seen =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      mount(
        RawAssetGrid(
          root: '/grid/home',
          assets: [
            Station(name: 'mbp', root: '/station/own', assets: [
              ScopeProbe(seen),
            ]),
          ],
        ),
      );
      expect(seen.single.station!.root, '/station/own');
    });

    test('Substation provides its scope to its assets; ONE root, no default',
        () {
      final seen =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      mount(
        RawAssetGrid(
          root: '/g',
          assets: [
            Station(name: 's', assets: [
              Substations(substations: [
                Substation(name: 'tg', root: '/work/tg', assets: [
                  ScopeProbe(seen),
                ]),
              ]),
            ]),
          ],
        ),
      );
      expect(
        seen.single.sub,
        const SubstationScope(name: 'tg', root: '/work/tg', prefix: 'tg'),
      );
      // The full ancestry is readable from the leaf: the asset serves the
      // project, inside the machine, inside the deployment.
      expect(seen.single.grid!.path, '/g');
      expect(seen.single.station!.name, 's');
    });
  });

  group('the canonical §2 tree (shape-faithful, offline)', () {
    test('Nest + conditionals + composed substations fan out', () {
      final probes =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      const kDebug = true;
      mount(
        RawAssetGrid(
          root: '/home/space_station',
          assets: [
            Nest(
              // Grid-scoped provider stand-ins (assets are just Seeds).
              children: const [ProviderStandIn(), ProviderStandIn()],
              child: Station(
                name: 'Space Station - MBP',
                assets: [
                  Substations(
                    substations: [
                      Substation(
                        name: 'the_grid',
                        root: '/work/the_grid',
                        assets: [ScopeProbe(probes)],
                      ),
                      Substation(
                        name: 'power_station',
                        root: '/work/power_station',
                        assets: [ScopeProbe(probes)],
                      ),
                      ComposedSubstation(root: '/work/butane', probe: probes),
                      if (kDebug)
                        Substation(
                          name: 'space_station',
                          root: '/home/space_station',
                          assets: [ScopeProbe(probes)],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      // Four substations mounted — literal, composed, and conditional alike.
      expect(probes, hasLength(4));
      // The intrinsic identity key: sibling substations reconcile by NAME
      // (a conditional anywhere in the list can never rebind a neighbour).
      expect(
        Substation(name: 'tg', root: '/w').key,
        const ValueKey<String>('substation:tg'),
      );
      expect(
        probes.map((s) => s.sub!.name),
        containsAll(<String>[
          'the_grid',
          'power_station',
          'composed-under-Space Station - MBP',
          'space_station',
        ]),
      );
      // Every probe sees the same machine + deployment above it.
      for (final s in probes) {
        expect(s.station!.name, 'Space Station - MBP');
        expect(s.station!.root, '/home/space_station');
        expect(s.grid!.path, '/home/space_station');
      }
      // The dual-role repo (Q5a): the self-substation's WORK root may equal
      // the grid's home — state under .grid/, work at .beads/, no collision
      // and no special case in the types.
      final self = probes.singleWhere((s) => s.sub!.name == 'space_station');
      expect(self.sub!.root, self.grid!.path);
    });
  });
}
