// StationKernel — the kernel-root ProcessLeaseVendor provision (tg-h4u):
// null `processLeaseVendor` composes the REAL production vendor over
// StationServices (`defaultProcessLeaseVendor` — chokepoint writer, station
// transport spawner/dispatcher, `StationBeadWriter.metadataOf`); an explicit
// vendor OVERRIDES it (the deliberately-chosen degraded mode is a choice,
// never a silent substitution). Proven THROUGH THE MOUNTED TREE: a probe
// resolver's session Seed reads the ambient vendor with the effect verb from
// inside the kernel's own provider stack — never a white-box peek. Mirrors
// station_kernel_unclaimed_frontier_test.dart's harness. Zero I/O — fakes.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

/// Captures the ambient [ProcessLeaseVendor] the mounted tree resolves for a
/// session — the through-the-tree proof of the kernel-root provision.
class _ProbeSeed extends StatelessSeed {
  const _ProbeSeed(this.captured);
  final List<ProcessLeaseVendor?> captured;

  @override
  Seed build(TreeContext context) {
    captured.add(context.getInheritedSeedOfExactType<ProcessLeaseVendor>());
    return const Idle();
  }
}

class _ProbeResolver implements SessionResolver {
  _ProbeResolver(this.captured);
  final List<ProcessLeaseVendor?> captured;

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _ProbeSeed(captured);
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _emptyGraph() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

/// Boots a kernel over the fakes with [processLeaseVendor], pushes ONE ready
/// work bead so the probe resolver's session Seed actually mounts, and
/// returns what that Seed resolved as the ambient vendor.
Future<ProcessLeaseVendor?> _resolvedVendor({
  ProcessLeaseVendor? processLeaseVendor,
  required Fakes fakes,
}) async {
  final work = FakeSnapshotSource(_emptyGraph());
  final state = FakeSnapshotSource(_emptyGraph());
  addTearDown(work.close);
  addTearDown(state.close);
  final bridge = StationJoinBridge(work: work, state: state);
  final captured = <ProcessLeaseVendor?>[];
  final kernel = StationKernel(
    bridge: bridge,
    stationServices: fakes.ctx,
    resolver: _ProbeResolver(captured),
    substations: [
      SubstationScope(
        configNotifier: SubstationConfigNotifier(_tgConfig),
        key: const ValueKey('scope.tg'),
      ),
    ],
    processLeaseVendor: processLeaseVendor,
  );
  addTearDown(kernel.dispose);
  kernel.start();

  work.push(
    GraphSnapshot.fromParts(
      beads: [
        Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open),
      ],
      dependencies: const [],
      readyIds: const {'tg-1'},
      capturedAt: DateTime(2026),
    ),
  );
  await _pump();

  expect(
    captured,
    isNotEmpty,
    reason: 'the probe session Seed must have mounted for a ready work bead',
  );
  return captured.first;
}

Future<ProcessHandle> _neverSpawn(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('spawn must not be called'));

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

void main() {
  group('StationKernel — the kernel-root ProcessLeaseVendor provision '
      '(tg-h4u)', () {
    test('null processLeaseVendor ⇒ the REAL production vendor is ambient: a '
        'StationProcessLeaseVendor over StationServices (chokepoint writer, '
        'station spawner/dispatcher, StationBeadWriter.metadataOf)', () async {
      final fakes = buildFakes();
      final vendor = await _resolvedVendor(fakes: fakes);

      expect(vendor, isA<StationProcessLeaseVendor>());
      final station = vendor! as StationProcessLeaseVendor;
      expect(
        station.writer,
        same(fakes.ctx.writer),
        reason: 'the sole grid.lease.* writer IS the chokepoint',
      );
      expect(station.spawn, same(stationProcessSpawner));
      expect(station.dispatch, same(stationProcessDispatcher));
    });

    test('an explicit vendor OVERRIDES the default — the degraded mode is a '
        'deliberate choice, never a silent substitution', () async {
      final fakes = buildFakes();
      const explicit = SelfManagedProcessVendor(
        spawn: _neverSpawn,
        dispatch: _neverDispatch,
      );
      final vendor = await _resolvedVendor(
        processLeaseVendor: explicit,
        fakes: fakes,
      );
      expect(vendor, same(explicit));
    });
  });
}
