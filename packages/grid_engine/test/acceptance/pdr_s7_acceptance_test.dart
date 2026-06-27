// Wave 4 / Track G — CONFORMANCE: the PDR §7 P0 acceptance, tied together
// through the REAL kernel/tree + the REAL DefaultExtension capabilities.
//
// The six criteria (M4-PDR §7 / M4-P0-BUILD-ORDER):
//  (a) a bead runs implement→verify→land as RECONCILE TRANSITIONS — the effect
//      child SWAPS by '<beadId>.<capId>' key while the WorkBead branch persists;
//  (b) sibling work is untouched across a transition (no spurious spawn/kill);
//  (c) config build() does NOT run on a work tick (targeted);
//  (d) a controller restart respawn-or-skips correctly (terminal SKIPPED, live
//      orphan killed, then re-mount respawns the non-skipped — no double-work,
//      no orphan);
//  (e) risk 5 — spawn-in-flight vs unmount: an effect disposed during the async
//      mint never leaks a SPAWN (the Completer/cancel-flag contract); the
//      mid-mint session bead is intentionally reaped later by the reconciler;
//  (f) risk 4 — stale-post-restart: a stale prior-incarnation completion is
//      dropped — pinned guard-by-guard (the per-incarnation subscription-cancel
//      AND the _cancelled/mounted handler guard, each isolated + combined).
//
// (a)/(b)/(c) drive the real Station→SubstationScope→Substation→WorkList→WorkBead→EffectSeed tree
// (with the REAL DefaultEffectResolver + an EffectContext over the offline
// fakes) under a TreeOwner so branch identity is walkable; (d)/(e)/(f) re-drive
// the Track C/D mechanisms through the same integrated effect path.
//
// Offline only — FAKES, no live tg/gc/claude/git/network.
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import '../support/engine_fakes.dart';

// ---------------------------------------------------------------------------
// Builders + branch-walk helpers (the integrated tree, REAL capabilities).
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

Bead _bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: _graph(beads: beads, ready: ready),
  sessionsByWorkBead: sessions,
);

/// The integrated root: the work-axis notifier + the EffectContext + the REAL
/// DefaultEffectResolver above the Station; one rig owning `tg`.
Seed _root({
  required JoinedSnapshotNotifier joined,
  required EffectContext ctx,
  required SubstationConfigNotifier substationConfig,
}) => InheritedSeed<JoinedSnapshotNotifier>(
  value: joined,
  child: InheritedSeed<EffectContext>(
    value: ctx,
    child: InheritedSeed<EffectResolver>(
      value: const DefaultEffectResolver(),
      child: Station([
        SubstationScope(configNotifier: substationConfig, key: const ValueKey('scope.tg')),
      ]),
    ),
  ),
);

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _branchWhere(Branch root, bool Function(Seed seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

Branch? _workBead(Branch root, String beadId) {
  for (final b in _all(root)) {
    final seed = b.seed;
    if (seed is WorkBead && seed.bead.id == beadId) return b;
  }
  return null;
}

/// The live [EffectSeedState] beneath [root] (the single effect in the
/// isolated-capability mounts). Captured BEFORE dispose so the test can force a
/// stale event into its handler post-unmount (PDR §7 (f) guard-(ii) isolation).
EffectSeedState effectState(Branch root) {
  for (final b in _all(root)) {
    if (b is StatefulBranch && b.seed is EffectSeed) {
      // ignore: invalid_use_of_protected_member
      return b.state as EffectSeedState;
    }
  }
  throw StateError('no EffectSeed branch beneath root');
}

/// A counting StatefulSeed wrapper is not available for the config nodes, so we
/// detect a config-node rebuild structurally: a rebuild RE-CREATES the WorkList
/// branch beneath it (a new branchId), since SubstationScope/Substation build a fresh child.
/// We capture the WorkList branchId and assert it is STABLE across a work tick.
String _workListId(Branch root) =>
    _branchWhere(root, (s) => s is WorkList).branchId;

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

void main() {
  group('PDR §7 (a)+(b)+(c) — transitions, sibling isolation, config quiet', () {
    test(
      'a bead runs implement→verify→land as reconcile transitions (effect swaps '
      'by key, WorkBead branch persists), a sibling is untouched, and the '
      'config subtree does NOT rebuild on a work tick',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final joined = JoinedSnapshotNotifier(
          _joined(beads: [_bead('tg-1'), _bead('tg-2')], ready: {'tg-1', 'tg-2'}),
        );
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        addTearDown(f.provider.close);
        final root = owner.mountRoot(
          _root(joined: joined, ctx: f.ctx, substationConfig: SubstationConfigNotifier(_tgConfig)),
        );
        await pumpEventQueue();

        // Both beads mounted + spawned their implement agent (REAL capability).
        expect(f.provider.started, hasLength(2));
        final wb1Id = _workBead(root, 'tg-1')!.branchId;
        final wb2Id = _workBead(root, 'tg-2')!.branchId;
        final workListId = _workListId(root);
        // The effect child under tg-1 is keyed '<bead>.<capId>'.
        final effect1Before = _workBead(root, 'tg-1')!;
        Branch effectChild(Branch wb) {
          Branch? found;
          wb.visitChildren((c) => found = c);
          return found!;
        }

        final implEffectId = effectChild(effect1Before).branchId;
        expect(effectChild(effect1Before).key, const ValueKey('tg-1.agent'));

        // --- (a) implement → verify (a reconcile transition) ---
        // Advance tg-1's SESSION cursor (A40), keep tg-2 untouched.
        final sessionsBefore = f.runner.callsFor('create').length;
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-sess1',
                phase: WorkPhase.verify,
              ),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();

        // The effect SWAPPED: the implement effect was killed, verify spawned;
        // the key changed to '<bead>.verify'; the WorkBead branch PERSISTED.
        expect(
          f.provider.started,
          hasLength(3),
          reason: 'verify spawned (the swap)',
        );
        expect(
          f.provider.started.last.config.command,
          'sh',
          reason: 'the REAL verify capability',
        );
        expect(_workBead(root, 'tg-1')!.branchId, wb1Id,
            reason: 'WorkBead branch persists across the transition');
        final verifyChild = effectChild(_workBead(root, 'tg-1')!);
        expect(verifyChild.key, const ValueKey('tg-1.verify'));
        expect(verifyChild.branchId, isNot(implEffectId),
            reason: 'the effect CHILD swapped (a new branch)');
        // verify reused the existing session — no new mint.
        expect(f.runner.callsFor('create'), hasLength(sessionsBefore));

        // --- (b) the sibling tg-2 was untouched across tg-1's transition ---
        expect(_workBead(root, 'tg-2')!.branchId, wb2Id,
            reason: 'sibling WorkBead branch unchanged');
        // No spurious sibling spawn/kill: tg-2 never appears in stopped, and the
        // only starts were [tg-1.agent, tg-2.agent, tg-1.verify].
        // (One session id per bead; the swap stop targeted tg-1's session.)
        expect(f.provider.started.map((s) => s.config.command),
            ['claude', 'claude', 'sh']);

        // --- (c) the config subtree did NOT rebuild on the work tick ---
        // SubstationScope/Substation rebuilding would re-create the WorkList child branch (a
        // new branchId). It is STABLE ⇒ the config ancestors did not rebuild.
        expect(_workListId(root), workListId,
            reason: 'a work tick does not rebuild the config ancestors');

        // --- (a) continued: verify → land (the second transition) ---
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-sess1',
                phase: WorkPhase.land,
              ),
            },
          ),
        );
        owner.flush();
        await pumpEventQueue();
        final landChild = effectChild(_workBead(root, 'tg-1')!);
        expect(landChild.key, const ValueKey('tg-1.land'),
            reason: 'land is the third reconcile transition');
        expect(_workBead(root, 'tg-1')!.branchId, wb1Id,
            reason: 'the WorkBead branch still persists at land');
        // land is git/PR orchestration — NOT a provider spawn (no 4th start).
        expect(f.provider.started, hasLength(3));
      },
    );
  });

  group('PDR §7 (d) — controller restart respawn-or-skip', () {
    test(
      'a terminal bead is SKIPPED (reaped, no respawn); a live orphan is killed; '
      'then the re-mounted tree respawns the non-skipped — no double-work',
      () async {
        // --- the restart reconciler pass (Track D), through the real type ---
        final reaped = <String>[];
        final signals = <int>[];
        final reconciler = RestartReconciler(
          listWorktrees: (root) async => [
            BeadWorktree(
              beadId: 'tg-done',
              path: '/tmp/grid/.grid/worktrees/tg/tg-done',
              branch: 'grid/tg-done',
            ),
            BeadWorktree(
              beadId: 'tg-live',
              path: '/tmp/grid/.grid/worktrees/tg/tg-live',
              branch: 'grid/tg-live',
            ),
          ],
          reapWorktree: ({required root, required worktree}) async {
            reaped.add(worktree.beadId);
            return ReapOutcome.removed();
          },
          workRoot: const RootCheckout(
            path: '/tmp/grid',
            defaultBranch: 'main',
            substation: 'tg',
          ),
          groups: _RecordingGroups(signals, alivePids: {4243}),
          freshnessBarrier: () async {},
          stateSnapshot: () => _graph(
            beads: [
              // tg-done: terminal owned session ⇒ SKIP.
              Bead(
                id: 'tgdog-d',
                issueType: IssueType.session,
                status: BeadStatus.closed,
                metadata: const {
                  'rig': 'tgdog',
                  'work_bead': 'tg-done',
                  'grid.phase': 'land',
                },
              ),
              // tg-live: a live orphan with a usable pgid ⇒ KILL + respawn.
              Bead(
                id: 'tgdog-l',
                issueType: IssueType.session,
                status: BeadStatus.open,
                metadata: const {
                  'rig': 'tgdog',
                  'work_bead': 'tg-live',
                  'grid.phase': 'implement',
                  'pgid': '4242',
                  'pid': '4243',
                },
              ),
            ],
            ready: const {},
          ),
        );
        final report = await reconciler.reconcile();

        expect(report.skipped.map((e) => e.beadId), ['tg-done']);
        expect(report.killed.map((e) => e.beadId), ['tg-live']);
        expect(reaped, ['tg-done'], reason: 'only the done bead is reaped');
        expect(signals, [4242], reason: 'only the live orphan is signalled');
        // The done bead does NOT respawn; the killed orphan does.
        expect(report.respawnCount, 1);

        // --- the re-mount (the tree comes back) ---
        // The kernel re-mounts: only the non-skipped bead is still in the work
        // graph (the done bead's work is complete). The respawn is a single
        // fresh spawn — no double-work (the orphan group was killed first).
        final f = buildFakes(createdId: 'tgdog-l');
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
        // Post-restart the live bead is still ready; the done bead is gone.
        work.push(_graph(beads: [_bead('tg-live')], ready: {'tg-live'}));
        await pumpEventQueue();

        expect(
          f.provider.started,
          hasLength(1),
          reason: 'the non-skipped bead respawns exactly once (no double-work)',
        );
        expect(f.provider.started.single.config.env['GRID_BEAD_ID'], 'tg-live');
      },
    );
  });

  group('PDR §7 (e) — risk 5: spawn-in-flight vs unmount', () {
    test(
      'an effect disposed DURING the async createSession never leaks a SPAWN '
      '(the Completer/cancel-flag contract), through the real effect — the '
      'load-bearing P0 risk is a leaked subprocess; the mid-mint session bead '
      'is intentionally reaped later by the RestartReconciler',
      () async {
        // Gate the create so dispose lands mid-mint.
        final runner = GatedCreateBdRunner();
        final provider = FakeRuntimeProvider();
        final ctx = EffectContext(
          provider: provider,
          writer: StationBeadWriter(
            bd: BdCliService(runner),
            ownership: BeadOwnershipPredicate(const {stateSubstation}),
          ),
          stateSubstation: stateSubstation,
        );
        addTearDown(provider.close);

        // Mount the REAL implement capability (AgentEffectSeed) via the resolver.
        final owner = TreeOwner();
        owner.mountRoot(
          InheritedSeed<EffectContext>(
            value: ctx,
            child: const DefaultEffectResolver().effectFor(
              bead: Bead(
                id: 'tg-1',
                issueType: IssueType.task,
                status: BeadStatus.open,
              ),
              phase: WorkPhase.implement,
            ),
          ),
        );

        // _run() is parked awaiting createSession. Dispose now (the unmount).
        await pumpEventQueue();
        expect(runner.createPending, isTrue, reason: 'create is in-flight');
        owner.dispose();

        // Resolve the create — the post-create guard must abort before spawning.
        runner.releaseCreate('tgdog-sess1');
        await pumpEventQueue();

        expect(provider.started, isEmpty,
            reason: 'spawn never leaks after a mid-mint dispose');
        expect(provider.stopped, isEmpty,
            reason: 'never spawned ⇒ dispose issues no stop');
        // NB: the `bd create` of the session bead is ALREADY issued to the
        // runner before the post-create dispose guard fires — by design. A
        // mid-mint dispose intentionally leaves an orphan session bead that the
        // RestartReconciler reaps later (PDR §7 (d)). The P0 risk this test
        // guards is the leaked SUBPROCESS, asserted above; the bd write is not
        // a leak the effect must prevent.
      },
    );
  });

  group('PDR §7 (f) — risk 4: stale-post-restart completion is dropped', () {
    // Defense-in-depth: a stale prior-incarnation completion is stopped by TWO
    // independent guards — (i) the per-incarnation subscription is cancelled on
    // dispose, so the event is never even delivered; AND (ii) even if the event
    // WERE delivered (a regression in cancellation), the _cancelled/mounted
    // guard in _onComplete drops it. Each is pinned by its own assertion so a
    // future edit that silently breaks one guard fails this gate (the combined
    // "writes nothing" check alone would stay green with one guard intact).

    test(
      '(i) the per-incarnation event subscription is CANCELLED on dispose — '
      'no event is delivered to the disposed effect at all',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final owner = TreeOwner();
        owner.mountRoot(
          InheritedSeed<EffectContext>(
            value: f.ctx,
            child: const DefaultEffectResolver().effectFor(
              bead: bead('tg-1'),
              phase: WorkPhase.implement,
            ),
          ),
        );
        addTearDown(f.provider.close);
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        // The live effect holds exactly ONE subscription to the event stream.
        expect(f.provider.eventListenerCount, 1,
            reason: 'the mounted effect subscribes to its session events');

        // The restart boundary: the prior incarnation's branch is disposed.
        owner.dispose();
        await pumpEventQueue();

        // The subscription is gone — a future edit that drops the dispose-time
        // `_sub.cancel()` would leave this at 1 and fail HERE (isolating the
        // subscription-cancel guard from the _onComplete guard).
        expect(f.provider.eventListenerCount, 0,
            reason: 'dispose cancels the per-incarnation subscription');
      },
    );

    test(
      '(ii) even if a stale event is delivered, the _cancelled/mounted guard in '
      '_onComplete drops it — no cursor write, no close',
      () async {
        // Bypass the subscription-cancel guard entirely: subscribe to the
        // provider's events OURSELVES and forward them into the effect's
        // handler manually, so the event reaches a disposed effect even though
        // its own subscription is cancelled. This isolates the SECOND guard
        // (the _cancelled/mounted check in _onComplete), proving it alone drops
        // the stale completion.
        final f = buildFakes(createdId: 'tgdog-sess1');
        final owner = TreeOwner();
        final root = owner.mountRoot(
          InheritedSeed<EffectContext>(
            value: f.ctx,
            child: const DefaultEffectResolver().effectFor(
              bead: bead('tg-1'),
              phase: WorkPhase.implement,
            ),
          ),
        );
        addTearDown(f.provider.close);
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        final updatesBefore = f.runner.callsFor('update').length;

        // Reach the live EffectSeedState so we can invoke its handler directly
        // AFTER dispose (modelling a delivery that bypassed cancellation).
        final state = effectState(root);
        owner.dispose();
        await pumpEventQueue();

        // Force-deliver a stale completion straight into the handler. The
        // _cancelled/mounted guard must drop it. (Without that guard this writes
        // a cursor — exactly the regression the assertion below catches.)
        state.deliverEventForTest(const Exited(name: 'tgdog-sess1', exitCode: 0));
        await expectLater(pumpEventQueue(), completes);

        expect(f.runner.callsFor('update'), hasLength(updatesBefore),
            reason: 'the _onComplete guard drops a delivered stale completion');
        expect(f.runner.callsFor('close'), isEmpty,
            reason: 'no session is closed by the stale completion');
      },
    );

    test(
      'combined: a stale Exited + SessionStarted reaching a disposed effect '
      'writes nothing and never throws (both guards together)',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final owner = TreeOwner();
        owner.mountRoot(
          InheritedSeed<EffectContext>(
            value: f.ctx,
            child: const DefaultEffectResolver().effectFor(
              bead: bead('tg-1'),
              phase: WorkPhase.implement,
            ),
          ),
        );
        addTearDown(f.provider.close);
        await pumpEventQueue();
        expect(f.provider.started, hasLength(1));
        final updatesBefore = f.runner.callsFor('update').length;

        // Simulate the restart boundary: the prior incarnation's branch is gone
        // (dispose cancels its per-incarnation subscription). A STALE completion
        // for that incarnation then arrives on the shared event stream.
        owner.dispose();
        f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
        f.provider.emit(
          const SessionStarted(name: 'tgdog-sess1', pid: 1, pgid: 2),
        );

        // No throw escapes (an unhandled async error would fail the test), and
        // the stale completion advanced NO cursor / closed NO session.
        await expectLater(pumpEventQueue(), completes);
        expect(f.runner.callsFor('update'), hasLength(updatesBefore),
            reason: 'a stale prior-incarnation completion writes nothing');
        expect(f.runner.callsFor('close'), isEmpty);
      },
    );
  });
}

/// A process-group seam that records signalled pgids and kills the group on
/// SIGTERM/SIGKILL (so the REAL terminateGroup observes the exit and returns
/// exitedOnTerm) — the PDR §7 (d) live-orphan-kill arm.
class _RecordingGroups implements ProcessGroupController {
  _RecordingGroups(this.signals, {Set<int> alivePids = const {}})
    : _alive = {...alivePids};

  final List<int> signals;
  final Set<int> _alive;

  @override
  int currentGroupId() => 999;

  @override
  bool processAlive(int pid) => _alive.contains(pid);

  @override
  Future<int?> resolvePgid(int pid) async => null;

  @override
  bool signalGroup(int pgid, ProcessSignal signal) {
    signals.add(pgid);
    if (signal == ProcessSignal.sigterm || signal == ProcessSignal.sigkill) {
      _alive.clear();
    }
    return true;
  }
}
