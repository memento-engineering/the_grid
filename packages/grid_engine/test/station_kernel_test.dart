// Track E/F — the REACTIVE LOOP through the ALREADY-AUTHORED StationKernel.
//
// This is the integration proof that the M4 tree engine drives
// implement → verify → land as RECONCILE TRANSITIONS: a bridge push marks the
// sole observer (WorkList) dirty, the kernel's microtask flush reconciles the
// work set, mount = spawn (an agent), a phase advance swaps the effect (stop
// old + start new). The DefaultEffectResolver (real) supplies the capabilities;
// the EffectContext is over the offline fakes (no live tg/gc/claude/git).
//
// Unlike Track A's track_a_reconcile_test (which calls owner.flush() directly),
// THIS test goes through the kernel's real `scheduleMicrotask` flush loop, so
// every step `await pumpEventQueue()` to let the scheduled flush run.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// ---------------------------------------------------------------------------
// Builders.
// ---------------------------------------------------------------------------

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

/// A `type=session` state bead linking [workBeadId] with cursor [phase] — the
/// row the join bridge projects + keys by `work_bead`, exactly as the real
/// state store holds it.
Bead _sessionBead({
  required String id,
  required String workBeadId,
  required WorkPhase phase,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    SessionBeadKeys.workBead: workBeadId,
    SessionBeadKeys.phase: phase.name,
  },
);

void main() {
  group('StationKernel — the reactive loop drives implement→verify→land', () {
    test(
      'a ready owned task spawns an agent; advancing the session cursor swaps '
      'the effect (stop old + start new) as a reconcile transition',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        // Empty baselines so the bridge seeds JoinedSnapshot.empty and the first
        // real push is what mounts the work bead.
        final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);

        final kernel = StationKernel(
          bridge: bridge,
          effectContext: f.ctx,
          resolver: const DefaultEffectResolver(),
          substations: [
            SubstationScope(
              configNotifier: SubstationConfigNotifier(
                const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
              ),
              key: const ValueKey('scope.tg'),
            ),
          ],
        );
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();
        // No work yet — nothing mounted.
        expect(f.provider.started, isEmpty);

        // 1) A ready owned task arrives on the WORK source → WorkList dirties →
        //    the kernel's microtask flush reconciles → mount = spawn the agent.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();

        expect(f.provider.started, hasLength(1), reason: 'the agent spawned');
        final agentStart = f.provider.started.single;
        // The implement capability is the coding agent (DefaultExtension opinion,
        // resolved through the REAL DefaultEffectResolver).
        expect(agentStart.config.command, 'claude');
        expect(agentStart.name, 'tgdog-sess1');
        // The engine-minted per-incarnation token rides config.env on the spawn.
        expect(
          agentStart.config.env['GRID_INSTANCE_TOKEN'],
          isNotEmpty,
          reason: 'the agent spawn carries GRID_INSTANCE_TOKEN',
        );
        expect(agentStart.config.env['GRID_BEAD_ID'], 'tg-1');

        // 2) Advance the bead's SESSION cursor implement → verify via the STATE
        //    source (A40: the cursor lives on the_grid's own session bead). The
        //    bridge re-joins, WorkList dirties, the flush swaps the effect.
        state.push(
          _graph(
            beads: [
              _sessionBead(
                id: 'tgdog-sess1',
                workBeadId: 'tg-1',
                phase: WorkPhase.verify,
              ),
            ],
            ready: const {},
          ),
        );
        await pumpEventQueue();

        // The swap: the old capability (agent) was killed; a new one started.
        expect(
          f.provider.stopped,
          contains('tgdog-sess1'),
          reason: 'the agent (implement) capability was unmounted → killed',
        );
        expect(
          f.provider.started,
          hasLength(2),
          reason: 'the verify capability spawned (the effect SWAPPED)',
        );
        final verifyStart = f.provider.started.last;
        // The verify capability runs the check via the SAME transport — and
        // reuses the EXISTING session (no second createSession).
        expect(verifyStart.config.command, 'sh');
        expect(verifyStart.name, 'tgdog-sess1');
        expect(
          f.runner.callsFor('create'),
          hasLength(1),
          reason: 'verify reuses the existing session — no new mint',
        );

        // 3) Advance verify → land via the STATE source → swap again.
        state.push(
          _graph(
            beads: [
              _sessionBead(
                id: 'tgdog-sess1',
                workBeadId: 'tg-1',
                phase: WorkPhase.land,
              ),
            ],
            ready: const {},
          ),
        );
        await pumpEventQueue();

        // land is git orchestration, NOT a supervised process — it does NOT
        // spawn through the provider. So the verify capability is killed
        // (stopped twice total) but no THIRD start lands.
        expect(
          f.provider.stopped.where((n) => n == 'tgdog-sess1').length,
          2,
          reason: 'verify was also unmounted → killed on the land swap',
        );
        expect(
          f.provider.started,
          hasLength(2),
          reason: 'land does not spawn a process (it is git/PR orchestration)',
        );
      },
    );
  });
}
