// Wave 4 / Track G — CONFORMANCE: derailment-invariant 1.
//
// "No tree node subscribes into a pipeline." (ADR-0007 §6.1 / A39.) The work
// axis is observed by EXACTLY ONE node — `WorkList` — and only through the
// injected immutable JoinedSnapshot value pushed onto the
// JoinedSnapshotNotifier by the join bridge (the SOLE subscription into the
// snapshot pipelines). A single over-broad observation would re-create the
// "config built 100×" bug the invariant exists to prevent.
//
// This drives the FULL StationKernel over fake SnapshotSources and asserts the
// invariant three ways: (a) exactly one persistent notifier listener after
// mount; (b) the bridge is the only subscriber to the SnapshotSources (no tree
// node subscribes to a GraphSnapshot stream); (c) a work tick reconciles
// WITHOUT re-running a config ancestor's build — proven through the integrated
// kernel via the effect lifecycle (a work tick spawns/swaps an effect but does
// not re-build the config-observing SubstationScope).
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import '../support/asset_fakes.dart';
import 'conformance_probes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

void main() {
  group('invariant 1 — no tree node subscribes into a pipeline', () {
    test(
      '(a) after mount the JoinedSnapshotNotifier has EXACTLY ONE persistent '
      'listener — WorkList, the sole work-axis observer',
      () async {
        final f = buildFakes();
        final work = CountingSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = CountingSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        // The bridge drives our counting notifier — but does NOT own it (we
        // pass it in), so the count reflects tree listeners + the WorkList only.
        final notifier = CountingJoinedSnapshotNotifier(JoinedSnapshot.empty());
        final bridge = StationJoinBridge(
          work: work,
          state: state,
          notifier: notifier,
        );
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
        addTearDown(notifier.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        // Before mount: no tree listener at all.
        expect(notifier.liveListenerCount, 0);

        kernel.start();
        await pumpEventQueue();

        // After mounting the WHOLE tree: exactly ONE persistent listener — the
        // WorkList. Every other node (Station/SubstationScope/Substation/WorkBead/effects)
        // observes the work axis through NONE of its own subscriptions.
        expect(
          notifier.liveListenerCount,
          1,
          reason: 'WorkList is the only work-axis observer (invariant 1)',
        );

        // A work tick changes the value but NOT the listener count (the single
        // subscription is stable — no node opportunistically subscribes).
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        expect(
          notifier.liveListenerCount,
          1,
          reason: 'mounting a WorkBead+effect adds NO new pipeline listener',
        );

        // Mounting a second work bead also adds no listener — WorkBeads/effects
        // are pure-config-driven, never observers.
        work.push(
          _graph(beads: [bead('tg-1'), bead('tg-2')], ready: {'tg-1', 'tg-2'}),
        );
        await pumpEventQueue();
        expect(notifier.liveListenerCount, 1);
        expect(
          f.provider.started.length,
          2,
          reason: 'sanity: both work beads actually mounted+spawned',
        );
      },
    );

    test(
      '(b) the bridge is the ONLY subscriber to the SnapshotSources — no tree '
      'node subscribes to a GraphSnapshot stream',
      () async {
        final f = buildFakes();
        final work = CountingSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = CountingSnapshotSource(
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

        // Drive several real ticks through the kernel — mounting work beads,
        // advancing a cursor. Throughout, the source-stream subscription count
        // must stay at exactly the bridge's two (one per source).
        work.push(_graph(beads: [bead('tg-1')], ready: {'tg-1'}));
        await pumpEventQueue();
        work.push(
          _graph(beads: [bead('tg-1'), bead('tg-2')], ready: {'tg-1', 'tg-2'}),
        );
        await pumpEventQueue();

        expect(
          work.listenCount,
          1,
          reason: 'only the bridge subscribes to the WORK source',
        );
        expect(
          state.listenCount,
          1,
          reason: 'only the bridge subscribes to the STATE source',
        );
        // Sanity: the tree IS live (a work bead mounted+spawned through it), so
        // the no-tree-subscriber assertion is meaningful, not vacuous.
        expect(f.provider.started, isNotEmpty);
      },
    );

    test(
      '(c) the runtime guardrail through the integrated tree: a work tick '
      'reconciles WITHOUT re-running a config ancestor build — proven BOTH by '
      'effect-churn (a NEW work bead spawns, the existing one is untouched) AND '
      'STRUCTURALLY (the config subtree below SubstationScope keeps its branch '
      'identity — a config-ancestor rebuild would re-create the WorkList branch)',
      () async {
        final f = buildFakes();
        // Drive the SAME notifier the bridge would, but mount the integrated
        // tree under a TreeOwner so the config subtree is branch-walkable (the
        // kernel does not expose its root branch). The counting notifier doubles
        // as the invariant-1(a) listener-count probe through this path too.
        final joined = CountingJoinedSnapshotNotifier(JoinedSnapshot.empty());
        final owner = TreeOwner();
        final root = InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<StationServices>(
            value: f.ctx,
            child: StableInheritedSeed<CapabilityRegistry>(
              value: buildCodeRegistry(),
              child: InheritedSeed<SessionResolver>(
                value: kCodeResolver,
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(
                      const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
                    ),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        );
        final mounted = owner.mountRoot(root);
        addTearDown(owner.dispose);
        addTearDown(joined.dispose);
        addTearDown(f.provider.close);

        // First work tick: tg-1 arrives with an ADOPTED session (so the
        // SessionScope resolves synchronously and the agent spawns under one
        // flush — the manual owner has no kernel self-flush). → ONE agent spawn.
        joined.push(JoinedSnapshot(
          graph: _graph(beads: [bead('tg-1')], ready: {'tg-1'}),
          sessionsByWorkBead: const {
            'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-1'),
          },
        ));
        owner.flush();
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        expect(f.provider.stopped, isEmpty);
        // Capture the config subtree's identity: the WorkList branch sits BELOW
        // the config ancestors (SubstationScope→Substation→WorkList). A config-ancestor
        // rebuild re-creates this child branch (a new branchId).
        final workListId =
            _branchWhere(mounted, (s) => s is WorkList).branchId;

        // SECOND work tick: ADD tg-2 (tg-1 unchanged). If a config ancestor
        // (SubstationScope/Substation) re-built on the work tick, the whole work subtree would
        // be re-created — tg-1's effect torn down+respawned (a stop + duplicate
        // start) AND the WorkList branch RE-CREATED. The guardrail asserts BOTH
        // the effect-churn signal AND the structural branch-identity signal.
        joined.push(JoinedSnapshot(
          graph: _graph(beads: [bead('tg-1'), bead('tg-2')], ready: {'tg-1', 'tg-2'}),
          sessionsByWorkBead: const {
            'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-1'),
            'tg-2': SessionProjection(workBeadId: 'tg-2', sessionId: 'tgdog-2'),
          },
        ));
        owner.flush();
        await pumpEventQueue();

        // (1) effect-churn signal: exactly one NEW spawn (tg-2); tg-1's agent was
        // neither torn down nor re-created (config did not re-build).
        expect(
          f.provider.started,
          hasLength(2),
          reason: 'exactly one NEW spawn (tg-2); tg-1 was not re-created',
        );
        expect(
          f.provider.stopped,
          isEmpty,
          reason: 'tg-1 effect was never torn down — config did not re-build',
        );

        // (2) STRUCTURAL signal — the config subtree kept its identity; a
        // config-ancestor rebuild would have re-created the WorkList branch.
        // This is what makes 1(c) self-sufficient: even when genesis reconciles
        // the un-keyed work children positionally (so an effect would NOT churn
        // under a full config rebuild), this branch-identity check still catches
        // a config-ancestor re-create.
        expect(
          _branchWhere(mounted, (s) => s is WorkList).branchId,
          workListId,
          reason: 'a work tick does not re-create the config subtree',
        );
        // The work axis still has exactly one persistent observer (the WorkList).
        expect(joined.liveListenerCount, 1);
      },
    );
  });
}

/// All branches under [root], pre-order.
List<Branch> _allBranches(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _branchWhere(Branch root, bool Function(Seed seed) test) =>
    _allBranches(root).firstWhere((b) => test(b.seed));
