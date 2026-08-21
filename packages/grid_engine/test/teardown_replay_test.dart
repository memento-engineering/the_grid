// tg-tlea — the BOOT-TIME TEARDOWN REPLAY.
//
// The positive-terminal close is a four-step tail: stamp grid.outcome=complete,
// reap the molecule, reap the worktree, close (then sweep the terminal gates).
// Steps 2 onward are LOUD-but-never-fatal, so a station killed between any two
// of them strands what it had already begun cleaning up — and no boot pass
// retried the molecule reap. That gap is the mechanism behind the pour-timeout
// cliff: 9,389 orphans across 307 closed sessions.
//
// The trigger is the marker the exit path already writes FIRST: still OPEN and
// already carrying grid.outcome=complete IS "teardown outstanding".
//
// Fakes, not mocks — a recording bd chokepoint plus the same FakeGit seams the
// reconciler suite uses.
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _FakeGit {
  _FakeGit({this.worktrees = const []});

  final List<BeadWorktree> worktrees;
  final List<String> reaped = [];

  Future<List<BeadWorktree>?> listWorktrees(RootCheckout root) async =>
      worktrees;

  Future<ReapOutcome> reapWorktree({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
    reaped.add(worktree.beadId);
    return ReapOutcome.removed();
  }
}

class _FakeGroups implements ProcessGroupController {
  @override
  bool processAlive(int pid) => false;
  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
  @override
  int currentGroupId() => 1;
  @override
  Future<int?> resolvePgid(int pid) async => null;
}

/// A reader whose probe THROWS — the boot must survive it.
class _ThrowingReader implements BeadProbeReader {
  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;
  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => throw StateError('probe exploded');
  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

class _SelectiveThrowingReader implements BeadProbeReader {
  _SelectiveThrowingReader(this.delegate);

  final BeadProbeReader delegate;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (types.contains(GridIssueTypes.molecule) ||
        types.contains(GridIssueTypes.step)) {
      throw StateError('closed reap exploded');
    }
    return delegate.openBeads(
      types: types,
      metadataAll: metadataAll,
      metadataAny: metadataAny,
    );
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) =>
      delegate.openSuperseding(priorIds);
}

const _workRoot = RootCheckout(
  path: '/workspace/example',
  defaultBranch: 'main',
  substation: 'tgdog',
);

BeadWorktree _wt(String beadId) => BeadWorktree(
  beadId: beadId,
  path: '/workspace/example/.grid/worktrees/tgdog/$beadId',
  branch: 'grid/$beadId',
);

/// A session bead. [outcome] stamps the completion marker; [escalation] and
/// [declined] stage the HUMAN markers.
Bead _session(
  String id, {
  required String workBead,
  bool closed = false,
  String? outcome = 'complete',
  String? escalation,
  String? declined,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'work_bead': workBead,
    if (outcome != null) 'grid.outcome': outcome,
    if (escalation != null) 'grid.escalation': escalation,
    if (declined != null) 'grid.rework_declined': declined,
  },
);

Bead _molecule(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: GridIssueTypes.molecule,
  status: BeadStatus.open,
  metadata: <String, dynamic>{
    'rig': 'tgdog',
    'grid.circuit.session': sessionId,
  },
);

Bead _step(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: <String, dynamic>{'rig': 'tgdog', 'grid.step.session': sessionId},
);

({RestartReconciler reconciler, RecordingBdRunner bd, List<String> loud})
_build({
  required List<Bead> state,
  List<BeadDependency> dependencies = const [],
  _FakeGit? git,
  Future<void> Function()? freshnessBarrier,
}) {
  final bd = RecordingBdRunner()
    ..exportBeads = state
    ..exportDependencies = dependencies;
  final loud = <String>[];
  final fakeGit = git ?? _FakeGit();
  return (
    reconciler: RestartReconciler(
      listWorktrees: fakeGit.listWorktrees,
      reapWorktree: fakeGit.reapWorktree,
      workRoot: _workRoot,
      groups: _FakeGroups(),
      writer: StationBeadWriter(
        bd: BdCliService(bd),
        reader: bd,
        ownership: BeadOwnershipPredicate(const {'tgdog'}),
      ),
      onOrphan: loud.add,
      freshnessBarrier: freshnessBarrier ?? () async {},
      stateSnapshot: () => GraphSnapshot.fromParts(
        beads: state,
        dependencies: dependencies,
        readyIds: const [],
        capturedAt: DateTime(2026, 8, 13),
      ),
    ),
    bd: bd,
    loud: loud,
  );
}

/// Every bead id the recorded calls closed (batch scripts included).
Set<String> _closedIds(RecordingBdRunner bd) {
  final ids = <String>{};
  for (var i = 0; i < bd.calls.length; i++) {
    final call = bd.calls[i];
    if (call.isEmpty) continue;
    if (call.first == 'close' && call.length > 1) ids.add(call[1]);
    if (call.first == 'batch') {
      final script = bd.stdins[i] ?? '';
      for (final line in script.split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.first == 'close') ids.add(parts[1]);
      }
    }
  }
  return ids;
}

void main() {
  group('the trigger set', () {
    test(
      'W1 — killed between the outcome stamp and the molecule reap: the '
      'orphaned molecule and step beads are collected on the next boot',
      () async {
        final f = _build(
          state: [
            _session('tgdog-sess1', workBead: 'tg-1'),
            _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
            _step('tgdog-step1', sessionId: 'tgdog-sess1'),
          ],
        );

        final report = await f.reconciler.replayTeardownTail();

        expect(report.replayed.map((e) => e.sessionId), ['tgdog-sess1']);
        final closed = _closedIds(f.bd);
        expect(closed, containsAll(['tgdog-mol1', 'tgdog-step1']));
        expect(closed, contains('tgdog-sess1'));
      },
    );

    test('W3 — killed after the worktree reap but before the close: the open '
        'complete-marked session is closed even though NO worktree survives, '
        'the window a worktree-driven pass structurally cannot see', () async {
      // No worktrees at all: a worktree-driven walk has nothing to find this
      // session by.
      final f = _build(
        state: [_session('tgdog-sess1', workBead: 'tg-1')],
        git: _FakeGit(worktrees: const []),
      );

      final report = await f.reconciler.replayTeardownTail();

      final entry = report.replayed.single;
      expect(entry.sessionId, 'tgdog-sess1');
      expect(entry.reapedWorktree, isFalse);
      expect(_closedIds(f.bd), contains('tgdog-sess1'));
    });

    test('a session with a SURVIVING worktree has it reaped (W2)', () async {
      final git = _FakeGit(worktrees: [_wt('tg-1')]);
      final f = _build(
        state: [_session('tgdog-sess1', workBead: 'tg-1')],
        git: git,
      );

      final report = await f.reconciler.replayTeardownTail();

      expect(git.reaped, ['tg-1']);
      expect(report.replayed.single.reapedWorktree, isTrue);
    });

    test('an empty trigger set does no work at all', () async {
      final f = _build(state: const []);

      final report = await f.reconciler.replayTeardownTail();

      expect(report.entries, isEmpty);
      expect(_closedIds(f.bd), isEmpty);
    });
  });

  group('HELD sessions are never drained', () {
    test('an ESCALATED session keeps its molecule, its worktree and its open '
        'bead', () async {
      final git = _FakeGit(worktrees: [_wt('tg-1')]);
      final f = _build(
        state: [
          _session(
            'tgdog-sess1',
            workBead: 'tg-1',
            escalation: 'breaker exhausted',
          ),
          _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
        ],
        git: git,
      );

      final report = await f.reconciler.replayTeardownTail();

      expect(report.replayed, isEmpty);
      expect(report.held.map((e) => e.sessionId), ['tgdog-sess1']);
      expect(git.reaped, isEmpty, reason: 'the worktree is the human evidence');
      expect(_closedIds(f.bd), isEmpty);
    });

    test('a DECLINED-rework session is held for the same reason', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1', declined: 'operator'),
        ],
      );

      final report = await f.reconciler.replayTeardownTail();

      expect(report.replayed, isEmpty);
      expect(report.held, hasLength(1));
    });
  });

  group('externally closed sessions', () {
    test('externally closed done session collects children', () async {
      final git = _FakeGit(worktrees: [_wt('tg-1')]);
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1', closed: true),
          _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1'),
        ],
        git: git,
      );

      final entry = (await f.reconciler.replayTeardownTail()).replayed.single;

      expect(entry.sessionId, 'tgdog-sess1');
      expect(_closedIds(f.bd), containsAll(['tgdog-mol1', 'tgdog-step1']));
      expect(_closedIds(f.bd), isNot(contains('tgdog-sess1')));
      expect(git.reaped, isEmpty);
      expect(f.bd.callsFor('update'), isEmpty, reason: 'no gate sweep');
    });

    test(
      'externally closed held session collects children but preserves worktree',
      () async {
        final git = _FakeGit(worktrees: [_wt('tg-1')]);
        final f = _build(
          state: [
            _session(
              'tgdog-sess1',
              workBead: 'tg-1',
              closed: true,
              escalation: 'breaker exhausted',
            ),
            _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
            _step('tgdog-step1', sessionId: 'tgdog-sess1'),
          ],
          git: git,
        );

        final entry = (await f.reconciler.replayTeardownTail()).replayed.single;

        expect(entry.disposition, GateSweepSessionDisposition.held);
        expect(_closedIds(f.bd), containsAll(['tgdog-mol1', 'tgdog-step1']));
        expect(_closedIds(f.bd), isNot(contains('tgdog-sess1')));
        expect(git.reaped, isEmpty);
        expect(f.bd.callsFor('update'), isEmpty, reason: 'no gate sweep');
      },
    );

    test('externally closed orphan-cleanup result collects children', () async {
      final f = _build(
        state: [
          _session(
            'tgdog-sess1',
            workBead: 'tg-closed-work',
            closed: true,
            outcome: null,
          ),
          _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
          _step('tgdog-step1', sessionId: 'tgdog-sess1'),
        ],
      );

      await f.reconciler.replayTeardownTail();

      expect(_closedIds(f.bd), containsAll(['tgdog-mol1', 'tgdog-step1']));
      expect(_closedIds(f.bd), isNot(contains('tgdog-sess1')));
      expect(f.bd.callsFor('update'), isEmpty, reason: 'no gate sweep');
    });

    test('closed-session reap failure is loud and boot continues', () async {
      final state = [
        _session('tgdog-sess1', workBead: 'tg-1', closed: true),
        _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
      ];
      final bd = RecordingBdRunner()..exportBeads = state;
      final loud = <String>[];
      final git = _FakeGit();
      final reconciler = RestartReconciler(
        listWorktrees: git.listWorktrees,
        reapWorktree: git.reapWorktree,
        workRoot: _workRoot,
        groups: _FakeGroups(),
        writer: StationBeadWriter(
          bd: BdCliService(bd),
          reader: _SelectiveThrowingReader(bd),
          ownership: BeadOwnershipPredicate(const {'tgdog'}),
        ),
        onOrphan: loud.add,
        freshnessBarrier: () async {},
        stateSnapshot: () => GraphSnapshot.fromParts(
          beads: state,
          dependencies: const [],
          readyIds: const [],
          capturedAt: DateTime(2026, 8, 13),
        ),
      );

      final entry = (await reconciler.replayTeardownTail()).replayed.single;

      expect(entry.failures, ['molecule']);
      expect(
        loud.single,
        allOf(
          contains('tgdog-sess1'),
          contains('externally-closed'),
          contains('closed reap exploded'),
        ),
      );
      expect(_closedIds(bd), isNot(contains('tgdog-sess1')));
    });

    test('dependency cycle is loud and boot continues', () async {
      const firstSessionId = 'tgdog-cycle';
      const secondSessionId = 'tgdog-acyclic';
      final firstGraphIds = {
        'tgdog-cycle-molecule',
        'tgdog-cycle-step-a',
        'tgdog-cycle-step-b',
      };
      final secondGraphIds = {'tgdog-acyclic-molecule', 'tgdog-acyclic-step'};
      final f = _build(
        state: [
          _session(firstSessionId, workBead: 'tg-1', closed: true),
          _molecule('tgdog-cycle-molecule', sessionId: firstSessionId),
          _step('tgdog-cycle-step-a', sessionId: firstSessionId),
          _step('tgdog-cycle-step-b', sessionId: firstSessionId),
          _session(secondSessionId, workBead: 'tg-2', closed: true),
          _molecule('tgdog-acyclic-molecule', sessionId: secondSessionId),
          _step('tgdog-acyclic-step', sessionId: secondSessionId),
        ],
        dependencies: const [
          BeadDependency(
            issueId: 'tgdog-cycle-step-a',
            dependsOnId: 'tgdog-cycle-step-b',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-cycle-step-b',
            dependsOnId: 'tgdog-cycle-step-a',
            type: DependencyType.blocks,
          ),
          BeadDependency(
            issueId: 'tgdog-acyclic-step',
            dependsOnId: 'tgdog-acyclic-molecule',
            type: DependencyType.parentChild,
          ),
        ],
      );

      final report = await f.reconciler.replayTeardownTail();

      final first = report.entries.singleWhere(
        (entry) => entry.sessionId == firstSessionId,
      );
      expect(first.failures, ['molecule']);
      expect(
        f.loud.single,
        allOf(
          contains(firstSessionId),
          contains('molecule reap dependency cycle:'),
        ),
      );
      expect(_closedIds(f.bd), everyElement(isNot(isIn(firstGraphIds))));
      expect(_closedIds(f.bd), containsAll(secondGraphIds));
    });
  });

  group('the boot contract', () {
    test(
      'the freshness barrier completes BEFORE anything is decided',
      () async {
        final order = <String>[];
        final f = _build(
          state: [_session('tgdog-sess1', workBead: 'tg-1')],
          freshnessBarrier: () async => order.add('barrier'),
        );

        await f.reconciler.replayTeardownTail();

        expect(order, ['barrier']);
        expect(
          f.bd.calls.isNotEmpty,
          isTrue,
          reason: 'the barrier ran, then the pass read and wrote',
        );
      },
    );

    test('running the replay TWICE changes nothing the second time', () async {
      final f = _build(
        state: [
          _session('tgdog-sess1', workBead: 'tg-1'),
          _molecule('tgdog-mol1', sessionId: 'tgdog-sess1'),
        ],
      );

      await f.reconciler.replayTeardownTail();
      // The second boot reads the store as the first left it: the session is
      // closed, so `openBeads` no longer returns it at all.
      f.bd
        ..exportBeads = [
          _session('tgdog-sess1', workBead: 'tg-1', closed: true),
        ]
        ..calls.clear();

      final second = await f.reconciler.replayTeardownTail();

      expect(second.entries, isEmpty);
      expect(_closedIds(f.bd), isEmpty);
    });

    test('a reader failure still RETURNS — a replay must never stop a '
        'station from booting', () async {
      final git = _FakeGit();
      final reconciler = RestartReconciler(
        listWorktrees: git.listWorktrees,
        reapWorktree: git.reapWorktree,
        workRoot: _workRoot,
        groups: _FakeGroups(),
        writer: StationBeadWriter(
          bd: BdCliService(RecordingBdRunner()),
          reader: _ThrowingReader(),
          ownership: BeadOwnershipPredicate(const {'tgdog'}),
        ),
        freshnessBarrier: () async {},
        stateSnapshot: () => GraphSnapshot.fromParts(
          beads: const [],
          dependencies: const [],
          readyIds: const [],
          capturedAt: DateTime(2026, 8, 13),
        ),
      );

      expect((await reconciler.replayTeardownTail()).entries, isEmpty);
    });

    test(
      'with NO chokepoint composed the pass is inert, never a crash',
      () async {
        final git = _FakeGit();
        final reconciler = RestartReconciler(
          listWorktrees: git.listWorktrees,
          reapWorktree: git.reapWorktree,
          workRoot: _workRoot,
          groups: _FakeGroups(),
          freshnessBarrier: () async {},
          stateSnapshot: () => GraphSnapshot.fromParts(
            beads: const [],
            dependencies: const [],
            readyIds: const [],
            capturedAt: DateTime(2026, 8, 13),
          ),
        );

        expect((await reconciler.replayTeardownTail()).entries, isEmpty);
      },
    );
  });
}
