import 'package:beads_dart/beads_dart.dart';
import 'package:grid_cli/src/station_runner.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// tg-e0p: the double-provision race hypothesis behind the tg-rm5/tg-457
/// wedges was two [SubstationConfig]s with OVERLAPPING `ownedSubstations`
/// mounting TWO [SubstationScope]s over the SAME bead — each independently
/// minting a session and calling `provisionWorktree` for it, racing
/// `git worktree add -b grid/beadId`. [composeStation] now refuses that
/// composition LOUDLY instead of racing it at runtime.
void main() {
  StationServices services() => StationServices(
    provider: DryRunProvider(),
    writer: StationBeadWriter(
      bd: BdCliService(NoOpBdRunner()),
      ownership: BeadOwnershipPredicate(const {'tg'}),
    ),
    stateSubstation: 'tg',
  );

  RootCheckout root() =>
      const RootCheckout(path: '', defaultBranch: 'main', substation: 'tg');

  TreeRunWiring compose(List<SubstationConfig> substations) => composeStation(
    work: const EmptySnapshotSource(),
    state: const EmptySnapshotSource(),
    stationServices: services(),
    substations: substations,
    git: buildDryTreeGitService(),
    workRoot: root(),
    groups: const SystemProcessGroupController(),
    freshnessBarrier: () async {},
    resolver: CircuitResolver(
      (bead) => throw StateError('never reached — composition refuses first'),
    ),
    registry: DefaultCapabilityRegistry(),
  );

  test('disjoint ownedSubstations across configs compose cleanly', () {
    expect(
      () => compose(const [
        SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        SubstationConfig(
          substationId: 'power_station',
          ownedSubstations: {'power_station'},
        ),
      ]),
      returnsNormally,
    );
  });

  test('two configs claiming the SAME owned substation id refuse LOUD '
      '(the tg-rm5/tg-457 double-provision race, structurally prevented)', () {
    expect(
      () => compose(const [
        SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        // A misconfigured "extra root" scope that widened its OWN ownership
        // to include "tg" instead of routing via `metadata.grid.root` —
        // this is the exact overlap that raced two scopes onto one bead.
        SubstationConfig(
          substationId: 'power_station',
          ownedSubstations: {'tg', 'power_station'},
        ),
      ]),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('"tg"'),
            contains('"power_station"'),
            contains('SAME bead'),
          ),
        ),
      ),
    );
  });

  test('a single substation owning multiple ids is NOT an overlap', () {
    expect(
      () => compose(const [
        SubstationConfig(substationId: 'tg', ownedSubstations: {'tg', 'tgdog'}),
      ]),
      returnsNormally,
    );
  });
}
