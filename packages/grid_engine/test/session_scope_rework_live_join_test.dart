// tg-zat — reproduces the live rework re-arm through the REAL
// StationJoinBridge (not the hand-rolled `_joined()` snapshots
// `session_scope_rework_test.dart` builds by hand), so the join's own
// `work_bead` re-key handling is exercised exactly as `grid rework` +
// `StationJoinBridge._join` produce it, with a genuine OPEN `type=gate`
// bead in the mix (D-7) — the piece the hand-rolled test never modeled.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(
      stepId: 'verify',
      capabilityId: 'verify',
      dependsOn: {'agent'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

GraphSnapshot _state(List<Bead> beads, {int tick = 0}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

/// A the_grid session bead exactly as `grid rework`'s CLI-observed shape: round
/// 1's `agent`/`verify` complete, `route` GATED (a committee park), linked to
/// [workBead] — or, after the CLI's re-key, linked to `'$originalBead#r1'`
/// while every OTHER key (including the stale `route` gate cursor) is left
/// untouched (bd's `--metadata` merge, not a replace).
Bead _round1Session(String id, {required String workBead}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    ...nodeStateMetadata('tg-1/agent', StepState.complete),
    ...nodeStateMetadata('tg-1/verify', StepState.complete),
    ...nodeStateMetadata('tg-1/route', StepState.gated),
  },
);

/// The OPEN committee gate `grid rework` leaves standing (D-7) — it blocks
/// [sessionId] at `tg-1/route`; `grid rework` re-keys the SESSION, never this
/// bead, so it stays open across the rekey exactly like the live incident.
Bead _openGate(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: IssueType.gate,
  status: BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': sessionId, 'node': 'tg-1/route'},
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<SessionResolver>(
            value: CircuitResolver(rootCircuit),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(
                  const SubstationConfig(
                    substationId: 'tg',
                    ownedSubstations: {'tg'},
                  ),
                ),
                key: const ValueKey('scope.tg'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('SessionScope rework re-arm through the REAL StationJoinBridge', () {
    test(
      'a GATED round re-keyed by `grid rework` (leaving its gate bead OPEN, '
      'exactly as the CLI does) still closes the retired round and mints '
      'round N+1 — proving the join itself is not where the live deviation '
      'comes from',
      () async {
        final f = buildFakes(createdId: 'tgdog-round2');
        final reg = RecordingCapabilityRegistry(circuits: const {});

        final workSrc = FakeSnapshotSource(
          _work([bead('tg-1')], {'tg-1'}),
        );
        final stateSrc = FakeSnapshotSource(
          _state([
            _round1Session('tgdog-round1', workBead: 'tg-1'),
            _openGate('gate-1', sessionId: 'tgdog-round1'),
          ]),
        );
        final bridge = StationJoinBridge(work: workSrc, state: stateSrc)
          ..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // Adopted synchronously — round 1's gated session, no mint.
        expect(f.runner.callsFor('create'), isEmpty);

        // `grid rework tg-1`: re-keys ONLY `work_bead` on the SAME session
        // bead (bd `--metadata` merge — every other key, incl. the stale
        // `route` cursor, survives byte-identical) and leaves the gate bead
        // it never touches OPEN, exactly like `ReworkCommand.runRework`.
        stateSrc.push(
          _state([
            _round1Session('tgdog-round1', workBead: 'tg-1#r1'),
            _openGate('gate-1', sessionId: 'tgdog-round1'),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();
        m.owner.flush();
        await _pump();

        // The retired round-1 session is closed (D-2 fold).
        final closes = f.runner.callsFor('close');
        expect(closes.where((c) => c[1] == 'tgdog-round1'), hasLength(1));
        expect(closes.first.join(' '), contains('reworked'));

        // Round 2 minted fresh — a SECOND createSession, a NEW id — never a
        // reuse of tgdog-round1.
        expect(f.runner.callsFor('create'), hasLength(1));

        // The fresh round's leaf mounts under the NEW session id, from a
        // virgin cursor (never the stale `route: gated` carried over).
        expect(reg.events, contains('START agent(tgdog-round2/tg-1/agent)'));
      },
    );
  });
}
