import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _circuit = Circuit(
  id: 'test',
  terminalStepId: 'finish',
  steps: [CapabilityStep(stepId: 'finish', capabilityId: 'finish')],
);

JoinedSnapshot _joined({
  required Bead work,
  required SessionProjection session,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [work],
    dependencies: const [],
    readyIds: const {},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: {work.id: session},
);

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices stationServices,
  ServiceBundle services = const ServiceBundle(),
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: stationServices,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(circuits: const {}),
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
                  services: services,
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

Future<void> _pump(TreeOwner owner) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
    owner.flush();
  }
}

Bead _stateSession(String id, {bool held = false, String workBead = 'tg-1'}) =>
    Bead(
      id: id,
      issueType: GridIssueTypes.session,
      status: BeadStatus.closed,
      metadata: {
        'rig': 'tgdog',
        'work_bead': workBead,
        if (held)
          'grid.escalation': 'breaker-exhausted'
        else
          'grid.outcome': 'complete',
      },
    );

Bead _gate(String id, String sessionId) => Bead(
  id: id,
  issueType: GridIssueTypes.gate,
  metadata: {'rig': 'tgdog', 'blocks': sessionId, 'node': 'review/route'},
);

void main() {
  test(
    'closed work sweeps a live session without writing the work store',
    () async {
      final f = buildFakes();
      final workRunner = RecordingBdRunner();
      f.runner.exportBeads = [
        const Bead(
          id: 'live-session',
          issueType: GridIssueTypes.session,
          metadata: {'rig': 'tgdog', 'work_bead': 'tg-1'},
        ),
        _gate('tgdog-closed-work-gate', 'live-session'),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(
          work: const Bead(
            id: 'tg-1',
            issueType: IssueType.task,
            status: BeadStatus.closed,
            metadata: {'rig': 'tg'},
          ),
          session: const SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'live-session',
          ),
        ),
      );
      final mounted = _mount(joined: joined, stationServices: f.ctx);
      addTearDown(mounted.owner.dispose);

      await _pump(mounted.owner);

      expect(
        f.runner.callsFor('close').map((call) => call[1]),
        contains('tgdog-closed-work-gate'),
      );
      expect(
        f.runner.calls
            .singleWhere(
              (call) =>
                  call.length > 1 &&
                  call.first == 'update' &&
                  call[1] == 'tgdog-closed-work-gate' &&
                  call.contains('--if-status'),
            )
            .join(' '),
        contains('grid.gate.close_cause=work-bead-closed'),
      );
      expect(workRunner.calls, isEmpty);
    },
  );

  test(
    'first historical done snapshot sweeps once across repeated emissions',
    () async {
      final f = buildFakes();
      final workRunner = RecordingBdRunner();
      f.runner.exportBeads = [
        _stateSession('done-session'),
        _gate('tgdog-historical-gate', 'done-session'),
      ];
      final snapshot = _joined(
        work: const Bead(
          id: 'tg-1',
          issueType: IssueType.task,
          metadata: {'rig': 'tg'},
        ),
        session: const SessionProjection(
          workBeadId: 'tg-1',
          sessionId: 'done-session',
          isTerminal: true,
          completed: true,
        ),
      );
      final joined = JoinedSnapshotNotifier(snapshot);
      final mounted = _mount(joined: joined, stationServices: f.ctx);
      addTearDown(mounted.owner.dispose);

      await _pump(mounted.owner);
      joined.push(snapshot);
      mounted.owner.flush();
      await _pump(mounted.owner);

      expect(
        f.runner.calls
            .singleWhere(
              (call) =>
                  call.length > 1 &&
                  call.first == 'update' &&
                  call[1] == 'tgdog-historical-gate' &&
                  call.contains('--if-status'),
            )
            .join(' '),
        contains('grid.gate.close_cause=session-terminal'),
      );
      expect(
        f.runner.calls.where(
          (call) =>
              call.length > 1 &&
              call.first == 'close' &&
              call[1] == 'tgdog-historical-gate',
        ),
        hasLength(1),
      );
      expect(workRunner.calls, isEmpty);
    },
  );

  test(
    'held historical session preserves its gate and reports the hold',
    () async {
      final f = buildFakes();
      final transport = RecordingExplorationTransport();
      f.runner.exportBeads = [
        _stateSession('held-session', held: true),
        _gate('tgdog-held-gate', 'held-session'),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(
          work: const Bead(
            id: 'tg-1',
            issueType: IssueType.task,
            metadata: {'rig': 'tg'},
          ),
          session: const SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'held-session',
            isTerminal: true,
            humanHeld: true,
          ),
        ),
      );
      final mounted = _mount(
        joined: joined,
        stationServices: f.ctx,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(mounted.owner.dispose);

      await _pump(mounted.owner);

      expect(
        f.runner.calls.where(
          (call) => call.first == 'update' || call.first == 'close',
        ),
        isEmpty,
      );
      expect(transport.named('work.held'), hasLength(1));
    },
  );
}
