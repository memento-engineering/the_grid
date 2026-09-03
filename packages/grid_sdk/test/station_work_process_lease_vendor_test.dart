// The ProcessLeaseVendor provision (tg-h4u / tg-2mb) at the PRODUCTION seat:
// `StationWork`, not the retired coordinator. Null wiring composes the
// REAL vendor over `StationServices` (`defaultProcessLeaseVendor` — the
// chokepoint writer, the station spawner/dispatcher); an explicit vendor
// OVERRIDES it (the degraded mode is a deliberate choice, never a silent
// substitution). Proven THROUGH the mounted tree with the effect verb, never a
// white-box peek. Zero I/O — fakes.
import 'package:beads_dart/beads_dart.dart' show Bead;
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/src/molecule/process_lease_vendor.dart'
    show ProcessHandle, ProcessLeaseRequest, SelfManagedProcessVendor;
import 'package:grid_engine/src/molecule/station_process_transport.dart'
    show stationProcessDispatcher, stationProcessSpawner;
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A leaf — an empty fan-out.
class _Leaf extends MultiChildSeed {
  const _Leaf() : super(children: const []);
}

/// Captures the ambient vendor the mounted subtree resolves — the
/// through-the-tree proof, using the EFFECT verb (ADR-0008 D3's two-verb
/// lookup story), never a white-box peek at the seed.
class _ProbeSeed extends StatelessSeed {
  const _ProbeSeed(this.captured);

  /// The sink the resolved vendor lands in.
  final List<engine.ProcessLeaseVendor?> captured;

  @override
  Seed build(TreeContext context) {
    captured.add(
      context.getInheritedSeedOfExactType<engine.ProcessLeaseVendor>(),
    );
    return const _Leaf();
  }
}

/// Resolves nothing — this suite exercises the provision, not a mounted work
/// subtree.
class _IdleResolver implements engine.SessionResolver {
  const _IdleResolver();

  @override
  Seed sessionFor({required Bead bead, engine.SessionProjection? session}) =>
      const _Leaf();
}

/// Mounts `StationWork` over [processLeaseVendor] and returns what the subtree
/// resolved as the ambient vendor.
engine.ProcessLeaseVendor? _resolvedVendor({
  required Fakes fakes,
  engine.ProcessLeaseVendor? processLeaseVendor,
}) {
  final captured = <engine.ProcessLeaseVendor?>[];
  final notifier = engine.JoinedSnapshotNotifier(engine.JoinedSnapshot.empty());
  addTearDown(notifier.dispose);
  final owner = TreeOwner();
  addTearDown(owner.dispose);
  owner.mountRoot(
    ProviderScope(
      child: StationWork(
        wiring: StationWorkWiring(
          notifier: notifier,
          services: fakes.ctx,
          resolver: const _IdleResolver(),
          processLeaseVendor: processLeaseVendor,
        ),
        child: _ProbeSeed(captured),
      ),
    ),
  );
  expect(captured, isNotEmpty, reason: 'the probe must have mounted');
  return captured.first;
}

void main() {
  test('null processLeaseVendor ⇒ the REAL production vendor is ambient: a '
      'StationProcessLeaseVendor over StationServices', () {
    final fakes = buildFakes();
    final vendor = _resolvedVendor(fakes: fakes);

    expect(vendor, isA<engine.StationProcessLeaseVendor>());
    final station = vendor! as engine.StationProcessLeaseVendor;
    expect(
      station.writer,
      same(fakes.ctx.writer),
      reason: 'the sole grid.lease.* writer IS the chokepoint',
    );
    expect(station.spawn, same(stationProcessSpawner));
    expect(station.dispatch, same(stationProcessDispatcher));
  });

  test('an explicit vendor OVERRIDES the default — the degraded mode is a '
      'deliberate choice, never a silent substitution', () {
    const explicit = SelfManagedProcessVendor(
      spawn: _neverSpawn,
      dispatch: _neverDispatch,
    );
    final vendor = _resolvedVendor(
      fakes: buildFakes(),
      processLeaseVendor: explicit,
    );
    expect(vendor, same(explicit));
  });
}

Future<ProcessHandle> _neverSpawn(
  ProcessLeaseRequest request,
  TreeContext context,
  engine.StepArgs args,
) => Future.error(StateError('spawn must not be called'));

Future<engine.StepOutcome> _neverDispatch(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  engine.StepArgs args,
) => Future.error(StateError('dispatch must not be called'));
