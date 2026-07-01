// Wave 4 / Track G — CONFORMANCE: derailment-invariant 2.
//
// "Only the chokepoint writes." (ADR-0006 Decision 2 / A32.) Every bd mutation
// the_grid issues flows through the single StationBeadWriter chokepoint — bd-only,
// `--actor grid-controller`, fail-closed on ownership, never a `bd show` and
// never raw `sql`. And no write EVER happens inside a `build()`: the capability
// hosts act in initState / on a runtime event / dispose; `build()` is a pure
// Idle leaf.
//
// This drives a FULL agent→committee→land cycle through the REAL StationKernel +
// the REAL `code` formula (FormulaResolver + buildCodeRegistry — agent → the four
// adversarial critics → route → land) with a RecordingBdRunner-backed
// StationBeadWriter (the chokepoint) + the fake provider/git/PR, emitting
// SessionStarted + a clean completion per step and advancing the per-node cursor
// (+ all-pass grades) via the fake STATE source. It then asserts the chokepoint
// discipline over the WHOLE recorded call log.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

const _sid = 'tgdog-sess1';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

/// A one-bead STATE snapshot carrying the committee session for `tg-1` at the
/// given [completed] node set + [grades] (the shared `committeeSession` builds
/// the per-node cursor + the `grid.result.*` grades the route reads).
GraphSnapshot _stateAt({
  Set<String> completed = const {},
  Map<String, String> grades = const {},
}) => _graph(
  beads: [committeeSession(id: _sid, completed: completed, grades: grades)],
  ready: const {},
);

/// The committee critic step (provider) name for relative node [rel].
String _step(String rel) => '$_sid/tg-1/$rel';

/// The four critic provider names, in committee order.
final List<String> _criticSteps = [for (final n in kCriticNodes) _step(n)];

/// All-pass grades (the happy committee — the route advances, never gates).
final Map<String, String> _allA = {for (final n in kCriticNodes) n: 'A'};

/// The live `code` registry + a git ServiceBundle so the land capability runs
/// its commit→push→PR through the fakes.
ServiceBundle _gitServices(Fakes f) => ServiceBundle(
  sourceControl: GitSourceControl(gitOps: GitOps(f.git), prOpener: f.pr),
);

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await pumpEventQueue();
  }
}

void main() {
  group('invariant 2 — only the chokepoint writes', () {
    test(
      'a full agent→committee→land cycle through the kernel: EVERY bd write is a '
      'chokepoint mutation (create/update/close), carries --actor '
      'grid-controller, and NO bd show / sql ever appears',
      () async {
        final f = buildFakes(createdId: _sid);
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
          stationServices: f.ctx,
          resolver: kCodeResolver,
          // Inline rubrics so the committee critics build their prompts without a
          // disk read (the on-disk loader is exercised by track_d_assets_test).
          registry: buildCodeRegistry(rubrics: (id) => '($id rubric bands)'),
          substations: [
            SubstationScope(
              configNotifier: SubstationConfigNotifier(
                const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
              ),
              // The git services are provided AT THE SCOPE (ADR-0008 D5), so the
              // land capability resolves this substation's SourceControl.
              services: _gitServices(f),
              key: const ValueKey('scope.tg'),
            ),
          ],
        );
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await _settle();

        // 1) AGENT — a ready owned task mounts the agent; the chokepoint mints the
        //    session bead (create + the birth stamp = one update). The step's
        //    provider name is '<sessionId>/<nodePath>'.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await _settle();
        expect(f.provider.started, hasLength(1));
        expect(f.provider.started.single.name, _step('agent'));

        // SessionStarted → per-node identity stamped through the chokepoint.
        f.provider.emit(
          SessionStarted(name: _step('agent'), pid: 112, pgid: 111),
        );
        await _settle();

        // agent completes → its host writes agent=complete (a chokepoint update);
        // the STATE source surfaces the advance → the `review` sub-formula inflates
        // its four critic lanes IN PARALLEL.
        f.provider.emit(Exited(name: _step('agent'), exitCode: 0));
        await _settle();
        state.push(_stateAt(completed: {kAgentNode}));
        await _settle();
        expect(f.provider.started, hasLength(5),
            reason: 'the four committee critics fanned out after the agent');

        // 2) COMMITTEE — every critic completes; the STATE source surfaces the
        //    advanced cursor + all-pass grades, and the route joins (await-all),
        //    reads the grades, and advances (a chokepoint update; no gate minted).
        for (final critic in _criticSteps) {
          f.provider.emit(Exited(name: critic, exitCode: 0));
        }
        await _settle();
        state.push(
          _stateAt(completed: {kAgentNode, ...kCriticNodes}, grades: _allA),
        );
        await _settle();

        // 3) LAND — route complete → the land capability (a ServiceCapability — no
        //    spawn) runs its commit→push→PR through the fakes; its host writes
        //    land=complete.
        state.push(_stateAt(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode},
          grades: _allA,
        ));
        await _settle();

        // 4) The terminal (land) is complete; the STATE source surfaces it and
        //    SessionScope closes the session.
        state.push(_stateAt(
          completed: {kAgentNode, ...kCriticNodes, kRouteNode, kLandNode},
          grades: _allA,
        ));
        await _settle();

        // --- The chokepoint discipline over the WHOLE recorded log ---

        // The cycle actually produced writes (else the assertions are vacuous):
        // create (mint), updates (birth stamp + identity + cursor advances), and a
        // close (the positive terminal).
        expect(f.runner.callsFor('create'), hasLength(1));
        expect(f.runner.callsFor('update'), isNotEmpty);
        expect(f.runner.callsFor('close'), hasLength(1));
        // The land Service really ran its orchestration through the fakes.
        expect(f.git.subcommands, containsAll(<String>['add', 'commit', 'push']));
        expect(f.pr.opened, isNotEmpty);

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
      'NO write happens inside build(): every host build() is a pure Idle leaf — '
      'driving the full tree, the work subtree leaves are all Idle and the '
      'recorded writes are all event-driven, never a build product',
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
          stationServices: f.ctx,
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

        // Mount a work bead. The agent spawns from the host lifecycle — a write
        // (the session mint) lands. But that write came from the lifecycle, not a
        // build: re-pushing the SAME snapshot (a redundant work tick) re-runs
        // WorkList/WorkBead/SessionScope/FormulaScope build() — and produces ZERO
        // new bd writes, because build() never writes.
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        final writesAfterMount = f.runner.calls.length;
        expect(writesAfterMount, greaterThan(0), reason: 'the mint landed');
        expect(f.provider.started, hasLength(1));

        // A redundant identical work tick → the subtree rebuilds (same keys, same
        // config) → NO new writes (build() is side-effect-free) and NO effect
        // churn (the keyed reconcile preserves the branches).
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
          reason: 'no respawn — the host branch persisted across rebuilds',
        );
        expect(f.provider.stopped, isEmpty);
      },
    );
  });
}
