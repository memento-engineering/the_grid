// Track E/F — the REACTIVE LOOP through the ALREADY-AUTHORED StationKernel.
//
// This is the integration proof that the M4 tree engine drives agent → verify →
// land as RECONCILE TRANSITIONS: a bridge push marks the sole observer (WorkList)
// dirty, the kernel's microtask flush reconciles the work set, mount = spawn (an
// agent), a per-node cursor advance swaps the running step (stop old + start
// new). The live `code` formula (FormulaResolver + buildCodeRegistry) supplies
// the capabilities; the EffectContext is over the offline fakes (no live
// tg/gc/claude/git).
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

/// A one-bead STATE snapshot carrying the session for `tg-1` with the given
/// [completed] step set (the shared `sessionBead` builds the per-node cursor —
/// `{'agent'}` makes verify eligible, `{'agent','verify'}` makes land eligible).
GraphSnapshot _stateAt(Set<String> completed) => _graph(
  beads: [sessionBead(id: 'tgdog-sess1', workBeadId: 'tg-1', completed: completed)],
  ready: const {},
);

void main() {
  group('StationKernel — the reactive loop drives agent→verify→land', () {
    test(
      'a ready owned task spawns an agent; advancing the per-node cursor swaps '
      'the running step (stop old + start new) as a reconcile transition',
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
          resolver: kCodeResolver,
          registry: buildCodeRegistry(),
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
        //    the kernel mints the session + spawns the agent (the 1-wide frontier
        //    of the `code` formula). The step's provider name is
        //    '<sessionId>/<nodePath>'.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();

        expect(f.provider.started, hasLength(1), reason: 'the agent spawned');
        final agentStart = f.provider.started.single;
        // The agent step is the coding agent (the `code` extension opinion,
        // resolved through the REAL FormulaResolver + registry).
        expect(agentStart.config.command, 'claude');
        expect(agentStart.name, 'tgdog-sess1/tg-1/agent');
        // The engine-minted per-incarnation token rides config.env on the spawn.
        expect(
          agentStart.config.env['GRID_INSTANCE_TOKEN'],
          isNotEmpty,
          reason: 'the agent spawn carries GRID_INSTANCE_TOKEN',
        );
        expect(agentStart.config.env['GRID_BEAD_ID'], 'tg-1');

        // 2) Advance the bead's per-node cursor (agent complete) via the STATE
        //    source (A40: the cursor lives on the_grid's own session bead). The
        //    bridge re-joins, WorkList dirties, the flush swaps the running step.
        state.push(_stateAt({'agent'}));
        await pumpEventQueue();

        // The swap: the old step (agent) was killed; verify started.
        expect(
          f.provider.stopped,
          contains('tgdog-sess1/tg-1/agent'),
          reason: 'the agent step was unmounted → killed',
        );
        expect(
          f.provider.started,
          hasLength(2),
          reason: 'the verify step spawned (the running step SWAPPED)',
        );
        final verifyStart = f.provider.started.last;
        // The verify step runs the check via the SAME transport — and reuses the
        // EXISTING session (no second createSession).
        expect(verifyStart.config.command, 'sh');
        expect(verifyStart.name, 'tgdog-sess1/tg-1/verify');
        expect(
          f.runner.callsFor('create'),
          hasLength(1),
          reason: 'verify reuses the existing session — no new mint',
        );

        // 3) Advance verify → land via the STATE source → swap again.
        state.push(_stateAt({'agent', 'verify'}));
        await pumpEventQueue();

        // land is a ServiceCapability (git orchestration), NOT a supervised
        // process — it does NOT spawn through the provider. So the verify step is
        // killed (agent + verify both stopped) but no THIRD start lands.
        expect(
          f.provider.stopped,
          containsAll(<String>['tgdog-sess1/tg-1/agent', 'tgdog-sess1/tg-1/verify']),
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
