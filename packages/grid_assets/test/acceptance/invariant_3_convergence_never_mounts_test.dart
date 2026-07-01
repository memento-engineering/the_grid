// Wave 4 / Track G — CONFORMANCE: derailment-invariant 3.
//
// "Convergence never mounts." (A41 — the allow-list mount boundary.) A ready
// set may contain an OWNED `type=convergence` root (the M2 two-writer axis),
// infra (agent/rig/role), and every the_grid orchestration noun bd ready leaks
// (convoy/event/step/spec/gate/molecule/message/merge-request) — NONE of them
// mount a work node or spawn an effect. Only plain coding-dispatchable work
// (the upstream core types) does.
//
// Track A's track_a_reconcile_test asserts the predicate at the WorkBead
// child-set level; THIS formalizes it at the kernel/effect-SPAWN level — driven
// through the real StationKernel + the real `code` formula, the allow-list is
// proven by what does (and does not) reach the provider.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

Bead _typed(String id, IssueType type) =>
    Bead(id: id, issueType: type, status: BeadStatus.open);

StationKernel _kernel(StationJoinBridge bridge, Fakes f) => StationKernel(
  bridge: bridge,
  stationServices: f.ctx,
  resolver: kCodeResolver,
  registry: buildCodeRegistry(),
  substations: [
    SubstationScope(
      configNotifier: SubstationConfigNotifier(
        // Own the `tg` prefix so the ONLY thing keeping the customs out is the
        // TYPE allow-list, not ownership (every bead below is `tg-*`).
        const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
      ),
      key: const ValueKey('scope.tg'),
    ),
  ],
);

void main() {
  group('invariant 3 — convergence (and infra + orchestration nouns) never '
      'mount through the kernel', () {
    test(
      'an OWNED convergence root + infra + every orchestration noun mount ZERO '
      'effects, while a plain owned task DOES spawn — asserted at the '
      'effect-spawn level',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);
        final kernel = _kernel(bridge, f);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();

        // Every the_grid non-core type, ALL owned (`tg-*`) + ALL ready. The
        // convergence root is the headline; the orchestration nouns a deny-list
        // missed (convoy/event/step/spec/gate/molecule/message/merge-request)
        // and infra (agent/rig/role) ride alongside — plus session.
        final customs = <String, IssueType>{
          'tg-conv': IssueType.convergence,
          'tg-cvy': IssueType.convoy,
          'tg-evt': IssueType.event,
          'tg-step': IssueType.step,
          'tg-spec': IssueType.spec,
          'tg-gate': IssueType.gate,
          'tg-mol': IssueType.molecule,
          'tg-msg': IssueType.message,
          'tg-mr': IssueType.mergeRequest,
          'tg-agent': IssueType.agent,
          'tg-rig': IssueType.rig,
          'tg-role': IssueType.role,
          'tg-sess': IssueType.session,
        };

        work.push(
          _graph(
            beads: [
              for (final e in customs.entries) _typed(e.key, e.value),
              _typed('tg-1', IssueType.task), // the one plain work bead
            ],
            ready: {...customs.keys, 'tg-1'},
          ),
        );
        await pumpEventQueue();

        // Exactly ONE effect reached the provider — the plain task's agent.
        expect(
          f.provider.started,
          hasLength(1),
          reason: 'only the plain task spawned; nothing else mounted',
        );
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-1');

        // And exactly ONE session was minted — for the plain task only. (A
        // convergence/orchestration mount would have minted its own session.)
        final creates = f.runner.callsFor('create');
        expect(creates, hasLength(1));

        // The birth stamp links the minted session to tg-1, proving the one
        // spawn was the plain task (and not, say, the convergence root).
        expect(f.runner.metadataOfUpdate(0)['work_bead'], 'tg-1');
      },
    );

    test(
      'an OWNED convergence root ALONE (the M2 two-writer axis) mounts nothing '
      '— zero spawn, zero mint',
      () async {
        final f = buildFakes();
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = StationJoinBridge(work: work, state: state);
        final kernel = _kernel(bridge, f);
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();

        // A lone OWNED, READY convergence bead — the most adversarial case (it
        // passes ownership; only the type gate stops it).
        work.push(
          _graph(
            beads: [_typed('tg-conv', IssueType.convergence)],
            ready: {'tg-conv'},
          ),
        );
        await pumpEventQueue();

        expect(f.provider.started, isEmpty, reason: 'convergence never spawns');
        expect(
          f.runner.callsFor('create'),
          isEmpty,
          reason: 'convergence never mints a session',
        );

        // Sanity (non-vacuous): the SAME kernel DOES spawn for a plain task, so
        // the zero-spawn above is the type gate, not a dead kernel.
        work.push(
          _graph(
            beads: [
              _typed('tg-conv', IssueType.convergence),
              _typed('tg-1', IssueType.task),
            ],
            ready: {'tg-conv', 'tg-1'},
          ),
        );
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-1');
      },
    );
  });
}
