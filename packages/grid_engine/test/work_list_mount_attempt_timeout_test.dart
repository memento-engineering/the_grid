import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

final class _TimeoutFirstMountAttemptRead implements BeadProbeReader {
  _TimeoutFirstMountAttemptRead(this.delegate);

  final BeadProbeReader delegate;
  bool _timedOut = false;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (!_timedOut && types.contains(GridIssueTypes.mountAttempt)) {
      _timedOut = true;
      throw TimeoutException('Future not completed');
    }
    return delegate.openBeads(
      types: types,
      metadataAll: metadataAll,
      metadataAny: metadataAny,
    );
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) =>
      delegate.openSuperseding(priorIds);
}

final class _Transport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map.unmodifiable(data)));
  }
}

JoinedSnapshot _snapshot() => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: const [
      Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open),
    ],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime(2026, 9, 4),
  ),
  sessionsByWorkBead: const {},
);

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

bool _plainCreateOf(List<String> args, IssueType type) {
  final typeIndex = args.indexOf('--type');
  return args.isNotEmpty &&
      args.first == 'create' &&
      (args.length < 2 || args[1] != '--graph') &&
      typeIndex >= 0 &&
      typeIndex + 1 < args.length &&
      args[typeIndex + 1] == type.wire;
}

void main() {
  test(
    'a mount-attempt timeout fences session I/O and retries after backoff',
    () async {
      final runner = RecordingBdRunner(createdId: 'tgdog-created');
      final reader = _TimeoutFirstMountAttemptRead(runner);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = StationServices(
        provider: provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: reader,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      );
      addTearDown(station.dispose);
      final transport = _Transport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(_snapshot());
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          child: InheritedSeed<JoinedSnapshotNotifier>(
            value: joined,
            child: InheritedSeed<StationServices>(
              value: station,
              child: InheritedSeed<CapabilityRegistry>(
                value: registry,
                child: InheritedSeed<SessionResolver>(
                  value: CircuitResolver((_) => _circuit),
                  child: Station([
                    SubstationScope(
                      configNotifier: SubstationConfigNotifier(
                        const SubstationConfig(
                          substationId: 'tg',
                          ownedSubstations: {'tg'},
                        ),
                      ),
                      services: ServiceBundle(transport: transport),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(owner.dispose);

      await _pumpUntil(
        owner,
        () => transport.flares.any(
          (flare) => flare.name == 'work.mountAttemptRecordFailed',
        ),
      );

      final failed = transport.flares.singleWhere(
        (flare) => flare.name == 'work.mountAttemptRecordFailed',
      );
      expect(failed.data, containsPair('beadId', 'tg-1'));
      expect(failed.data, containsPair('attempt', '1'));
      expect(
        failed.data,
        containsPair('deadlineConstant', 'DoltQueryService.queryTimeout'),
      );
      expect(failed.data, containsPair('deadlineMs', '10000'));
      expect(
        runner.calls.any(
          (call) => _plainCreateOf(call, GridIssueTypes.session),
        ),
        isFalse,
      );
      expect(runner.graphApplyCalls, isEmpty);
      expect(registry.events, isEmpty);

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      await _pumpUntil(owner, () => registry.events.isNotEmpty);

      expect(
        runner.calls.where(
          (call) => _plainCreateOf(call, GridIssueTypes.mountAttempt),
        ),
        hasLength(1),
      );
      expect(
        runner.calls.where(
          (call) => _plainCreateOf(call, GridIssueTypes.session),
        ),
        hasLength(1),
      );
      expect(runner.graphApplyCalls, hasLength(1));
      expect(registry.events, ['START agent(tgdog-created/tg-1/agent)']);
    },
  );
}
