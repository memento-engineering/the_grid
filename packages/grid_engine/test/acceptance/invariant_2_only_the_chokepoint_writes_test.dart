// Wave 4 / Track G — CONFORMANCE: derailment-invariant 2.
//
// "Only the chokepoint writes." (ADR-0006 Decision 2 / A32.) Every bd mutation
// the_grid issues flows through the single StationBeadWriter chokepoint — bd-only,
// `--actor grid-controller`, fail-closed on ownership, never a `bd show` and
// never raw `sql`. And no write EVER happens inside a `build()`: effects act in
// initState / onComplete / dispose; `build()` is a pure Idle leaf.
//
// This drives a FULL implement→verify→land cycle through the REAL StationKernel
// with a RecordingBdRunner-backed StationBeadWriter (the chokepoint) + the fake
// provider/git/PR, emitting SessionStarted + a clean completion per phase and
// advancing the session cursor via the fake STATE source. It then asserts the
// chokepoint discipline over the WHOLE recorded call log.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/engine_fakes.dart';

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
/// row the join bridge projects + keys by `work_bead`. Carries the owned `rig`
/// marker so the chokepoint's ownership re-check passes.
Bead _sessionBead({
  required String id,
  required String workBeadId,
  required WorkPhase phase,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBeadId,
    SessionBeadKeys.phase: phase.name,
  },
);

void main() {
  group('invariant 2 — only the chokepoint writes', () {
    test(
      'a full implement→verify→land cycle through the kernel: EVERY bd write '
      'is a chokepoint mutation (create/update/close), carries --actor '
      'grid-controller, and NO bd show / sql ever appears',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        f.pr.url = 'https://github.com/memento/genesis/pull/7';
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
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

        // 1) IMPLEMENT — a ready owned task mounts the agent; the chokepoint
        //    mints the session bead (create + the birth stamp = one update).
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));

        // SessionStarted → identity stamped through the chokepoint.
        f.provider.emit(
          const SessionStarted(name: 'tgdog-sess1', pid: 112, pgid: 111),
        );
        await pumpEventQueue();

        // implement completes → cursor advances to verify (a chokepoint update).
        f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
        await pumpEventQueue();

        // 2) VERIFY — the STATE source surfaces the advanced cursor; the effect
        //    swaps; verify runs; its completion advances the cursor to land.
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
        f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
        await pumpEventQueue();

        // 3) LAND — the STATE source surfaces the land cursor; the land effect
        //    commits→pushes→opens the PR, records pr_url + closes the session,
        //    all through the chokepoint.
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

        // --- The chokepoint discipline over the WHOLE recorded log ---

        // The cycle actually produced writes (else the assertions are vacuous):
        // create (mint), updates (birth stamp + identity + 2 cursor advances +
        // pr_url), and a close (the land terminal).
        expect(f.runner.callsFor('create'), hasLength(1));
        expect(f.runner.callsFor('update'), isNotEmpty);
        expect(f.runner.callsFor('close'), hasLength(1));

        // (a) NO bd write bypasses the chokepoint: the ONLY BdRunner in the
        //     system is the one inside the StationBeadWriter, so EVERY recorded bd
        //     call IS a chokepoint call. A `show` or `sql` would mean a bypass.
        expect(
          f.runner.neverShowOrSql,
          isTrue,
          reason: 'no bd show / sql ever issued (the chokepoint forbids them)',
        );

        // (b) every recognised mutation carried --actor grid-controller.
        const mutations = {'create', 'update', 'close', 'delete', 'batch'};
        for (final c in f.runner.calls) {
          if (c.isEmpty || !mutations.contains(c.first)) continue;
          final i = c.indexOf('--actor');
          expect(
            i >= 0 && i + 1 < c.length && c[i + 1] == 'grid-controller',
            isTrue,
            reason: 'mutation $c lacked --actor grid-controller',
          );
        }

        // (c) every bd call is one of the chokepoint's allowed subcommands —
        //     nothing else (a positive whitelist, so an unexpected escape is
        //     caught even if it is not `show`/`sql`).
        const allowed = {'create', 'update', 'close', 'delete', 'batch'};
        for (final c in f.runner.calls) {
          expect(
            c.isNotEmpty && allowed.contains(c.first),
            isTrue,
            reason: 'unexpected bd subcommand bypassing the chokepoint: $c',
          );
        }
      },
    );

    test(
      'NO write happens inside build(): every effect build() is a pure Idle '
      'leaf — driving the full tree, the work subtree leaves are all Idle and '
      'the recorded writes are all event-driven, never a build product',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
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

        // Mount a work bead. The agent spawns from initState — a write (the
        // session mint) lands. But that write came from the lifecycle, not a
        // build: re-pushing the SAME snapshot (a redundant work tick) re-runs
        // WorkList.build() and the WorkBead.build() — and produces ZERO new bd
        // writes, because build() never writes.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        final writesAfterMount = f.runner.calls.length;
        expect(writesAfterMount, greaterThan(0), reason: 'the mint landed');
        expect(f.provider.started, hasLength(1));

        // A redundant identical work tick → WorkList rebuilds, WorkBead rebuilds
        // (same key, same config) → NO new writes (build() is side-effect-free)
        // and NO effect churn (the keyed reconcile preserves the branch).
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();

        expect(
          f.runner.calls.length,
          writesAfterMount,
          reason: 'build() writes nothing — redundant rebuilds add no bd calls',
        );
        expect(
          f.provider.started,
          hasLength(1),
          reason: 'no respawn — the effect branch persisted across rebuilds',
        );
        expect(f.provider.stopped, isEmpty);
      },
    );
  });
}
