// Wave 4 / Track G — CONFORMANCE: derailment-invariant 4 (the genuinely-new
// one) — A37: the engine NEVER writes the pristine work source.
//
// In the foreign-rig live arm (A36/A37) the_grid BUILDS a foreign backlog: work
// beads carry a FOREIGN rig prefix (`genesis-*`, a read-only work source the
// grid could never stamp) while the_grid's OWN session/lifecycle beads live in
// the OWNED state rig (`tgdog-*`). A37 is the structural guarantee that every
// write lands on the OWNED state store and ZERO writes touch the foreign work
// source.
//
// This drives a full implement→verify cycle AND a RestartReconciler pass in the
// foreign-rig arm and asserts:
//  - every recorded bd write targets a state-rig (tgdog-*) bead — ZERO target a
//    work-rig (genesis-*) bead;
//  - the fail-closed proof: the GridBeadWriter chokepoint REFUSES
//    (OwnershipRefused) a write whose target is a foreign (genesis-*) bead.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'dart:io';

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

Bead _foreignWork(String id) =>
    Bead(id: id, issueType: IssueType.feature, status: BeadStatus.open);

/// An OWNED (tgdog) `type=session` state bead linking the FOREIGN [workBeadId]
/// with cursor [phase]; this is the_grid's own bead, written through the
/// chokepoint, carrying the foreign work-bead linkage.
Bead _ownedSession({
  required String id,
  required String workBeadId,
  required WorkPhase phase,
}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateRig,
    SessionBeadKeys.workBead: workBeadId,
    SessionBeadKeys.phase: phase.name,
  },
);

/// The bead id every recorded mutation targets (the arg after the subcommand).
String? _targetOf(List<String> call) => call.length >= 2 ? call[1] : null;

void main() {
  group('invariant 4 — A37: the engine never writes the pristine work source', () {
    test(
      'foreign-rig arm: a full cycle + a restart pass write ONLY tgdog-* beads '
      '— ZERO writes target a genesis-* (read-only work source) bead',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final work = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final state = FakeSnapshotSource(
          _graph(beads: const [], ready: const {}),
        );
        final bridge = GridJoinBridge(work: work, state: state);
        final kernel = GridKernel(
          bridge: bridge,
          effectContext: f.ctx,
          resolver: const DefaultEffectResolver(),
          rigs: [
            RigScope(
              configNotifier: RigConfigNotifier(
                // The WORK axis owns the FOREIGN rig (the live foreign-rig arm:
                // the_grid builds the genesis backlog), so the genesis-* bead
                // MOUNTS. The chokepoint's allow-set is still {tgdog} — that
                // split is exactly what A37 protects.
                const RigConfig(rigId: 'genesis', ownedRigs: {'genesis'}),
              ),
              key: const ValueKey('scope.genesis'),
            ),
          ],
        );
        addTearDown(kernel.dispose);
        addTearDown(f.provider.close);
        addTearDown(work.close);
        addTearDown(state.close);

        kernel.start();
        await pumpEventQueue();

        // 1) A FOREIGN work bead enters ready → mounts → mints a tgdog session.
        work.push(
          _graph(beads: [_foreignWork('genesis-7r9')], ready: {'genesis-7r9'}),
        );
        await pumpEventQueue();
        expect(
          f.provider.started,
          hasLength(1),
          reason: 'the foreign work bead mounted + spawned',
        );

        // Drive identity + a completion (cursor advance to verify).
        f.provider.emit(
          const SessionStarted(name: 'tgdog-sess1', pid: 9, pgid: 8),
        );
        await pumpEventQueue();
        f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
        await pumpEventQueue();

        // 2) verify surfaces via the STATE source (the_grid's own bead).
        state.push(
          _graph(
            beads: [
              _ownedSession(
                id: 'tgdog-sess1',
                workBeadId: 'genesis-7r9',
                phase: WorkPhase.verify,
              ),
            ],
            ready: const {},
          ),
        );
        await pumpEventQueue();

        // 3) A RestartReconciler pass in the SAME foreign-rig arm: a foreign
        //    work bead with a TERMINAL owned session ⇒ SKIP (reap, no write to
        //    the foreign bead) — the A40/A37 fix (the cursor is on the OWNED
        //    bead, so done shows even for an unwritable foreign work bead).
        final reapLog = <String>[];
        final reconciler = RestartReconciler(
          listWorktrees: (root) async => [
            BeadWorktree(
              beadId: 'genesis-7r9',
              path: '/tmp/genesis-grid/.grid/worktrees/genesis/genesis-7r9',
              branch: 'grid/genesis-7r9',
            ),
          ],
          reapWorktree: ({required root, required worktree}) async {
            reapLog.add(worktree.beadId);
            return ReapOutcome.removed();
          },
          workRoot: const RootCheckout(
            path: '/tmp/genesis-grid',
            defaultBranch: 'main',
            rig: 'genesis',
          ),
          groups: _NoopGroups(),
          freshnessBarrier: () async {},
          stateSnapshot: () => _graph(
            beads: [
              // The OWNED session for the foreign bead is CLOSED (terminal).
              Bead(
                id: 'tgdog-sess1',
                issueType: IssueType.session,
                status: BeadStatus.closed,
                metadata: const {
                  'rig': stateRig,
                  'work_bead': 'genesis-7r9',
                  'grid.phase': 'land',
                },
              ),
            ],
            ready: const {},
          ),
        );
        final report = await reconciler.reconcile();
        expect(report.skipped.single.beadId, 'genesis-7r9');
        // The reap was on the foreign worktree — but reap is a git op, NOT a bd
        // write; it issues no bd call against the foreign bead.
        expect(reapLog, ['genesis-7r9']);

        // --- THE A37 ASSERTION: every recorded bd write targets tgdog-*; ZERO
        //     target genesis-*. ---
        const mutations = {'create', 'update', 'close', 'delete', 'batch'};
        expect(f.runner.calls, isNotEmpty, reason: 'the cycle did write');
        var sawCreate = false;
        for (final call in f.runner.calls) {
          if (call.isEmpty || !mutations.contains(call.first)) continue;
          if (call.first == 'create') {
            // `create` has no target id yet (the id is minted by the reply);
            // the chokepoint asserts the REQUESTED rig (tgdog) before it runs.
            sawCreate = true;
            continue;
          }
          final target = _targetOf(call);
          expect(target, isNotNull, reason: 'mutation $call had no target id');
          expect(
            target!.startsWith('tgdog'),
            isTrue,
            reason: 'A37 violated — bd write targeted a non-state-rig bead: '
                '$call',
          );
          expect(
            target.startsWith('genesis'),
            isFalse,
            reason: 'A37 violated — bd write targeted the foreign work source: '
                '$call',
          );
        }
        expect(sawCreate, isTrue, reason: 'a session was minted (tgdog rig)');
      },
    );

    test(
      'the fail-closed structural guarantee behind A37: the GridBeadWriter '
      'REFUSES (OwnershipRefused) a write whose target is a foreign genesis-* '
      'bead — for update, close, AND delete',
      () async {
        // A chokepoint owning ONLY the tgdog state rig (exactly the live arm).
        final runner = RecordingBdRunner();
        final writer = GridBeadWriter(
          bd: BdCliService(runner),
          ownership: BeadOwnershipPredicate(const {stateRig}),
        );

        // A write to an OWNED tgdog bead succeeds (proves the refusal is the
        // FOREIGN-ness, not a dead writer).
        await writer.update('tgdog-sess1', metadata: {'grid.phase': 'verify'});
        expect(runner.callsFor('update'), hasLength(1));

        // A write to a FOREIGN genesis-* bead is refused, loudly, on EVERY
        // mutation surface — the engine can never write the pristine source.
        await expectLater(
          writer.update('genesis-7r9', metadata: {'grid.phase': 'verify'}),
          throwsA(isA<OwnershipRefused>()),
        );
        await expectLater(
          writer.close('genesis-7r9'),
          throwsA(isA<OwnershipRefused>()),
        );
        await expectLater(
          writer.delete('genesis-7r9'),
          throwsA(isA<OwnershipRefused>()),
        );
        // createSession into a foreign rig is refused BEFORE any bd create.
        await expectLater(
          writer.createSession(
            rig: 'genesis',
            title: 'illegal',
            workBeadId: 'genesis-7r9',
          ),
          throwsA(isA<OwnershipRefused>()),
        );

        // NONE of the refused writes reached the bd runner (fail-closed: refused
        // BEFORE the bd call, not after).
        expect(
          runner.calls.every((c) => _targetOf(c)?.startsWith('genesis') != true),
          isTrue,
          reason: 'no refused foreign write leaked to bd',
        );
        // The refusal names the operation + the foreign target (a loud error).
        try {
          await writer.update('genesis-7r9', metadata: const {});
          fail('expected OwnershipRefused');
        } on OwnershipRefused catch (e) {
          expect(e.operation, 'update');
          expect(e.targetId, 'genesis-7r9');
          expect(e.toString(), contains('genesis'));
        }
      },
    );
  });
}

/// A no-op process-group seam — the restart pass in this test only exercises the
/// SKIP (reap) path, which never terminates a group.
class _NoopGroups implements ProcessGroupController {
  @override
  int currentGroupId() => 999;

  @override
  bool processAlive(int pid) => false;

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
}
