import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:grid_cli/grid_cli.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show GridStateStore, SubstationWorkStore;
import 'package:test/test.dart';

/// Offline proofs for `grid rework` (tg-x1j) — Fakes, not mocks, no live
/// state, no real `bd`, NO writes to any live store. Re-seated on the v3
/// store-at-roots model (`SCRATCH-station-config-model.md`): the session lives
/// in the grid state store addressed from a **grid root** (`GridStateStore`),
/// the `--note` targets the WORK bead's substation work store (`--note-root`) —
/// neither a `--state-workspace`/`--workspace` path arg-list. The DoD:
///
///  1. rework on a positively-closed bead re-keys `work_bead` to
///     `bead#rN` through the chokepoint and reports round N (a);
///  2. an OPEN, ACTIVELY-RUNNING session refuses LOUD, zero writes (b);
///  3. an OPEN session PARKED AT A GATE (nothing running) is safe to rework
///     (the v2 gate-resolve transition's trigger) — proceeds;
///  4. the ~3-round cap refuses LOUD, zero writes (c);
///  5. --note lands on the WORK bead (a separate store) under a ROUND N header
///     (d); missing --note-root refuses LOUD before any write.
///
/// The molecule group (tg-eli phase 1) proves refusal-semantics PARITY for a
/// `grid.session.model=molecule` session, whose per-node state lives on its
/// own `type=step` beads rather than flat `grid.cursor.*` keys: running →
/// refuse (the live veto), gated-not-running → allow, open-non-gated →
/// refuse — identical to the flat cases above, which stand UNCHANGED as the
/// negative control.
void main() {
  group('grid rework — v1 acceptance', () {
    test('(a) a positively-closed session re-keys + reports round 1', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(out.join('\n'), contains('round 1'));
      expect(out.join('\n'), contains('tgdog-s1'));
      final updates = state.writes.where((c) => c.first == 'update').toList();
      expect(updates, hasLength(1));
      expect(updates.single, containsAllInOrder(['update', 'tgdog-s1']));
      expect(
        updates.single,
        containsAllInOrder(['--actor', 'grid-controller']),
      );
      final metaIdx = updates.single.indexOf('--metadata');
      final meta =
          jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
      expect(meta, {'work_bead': 'tg-9#r1'});
      final workUpdates = work.writes.where((c) => c.first == 'update');
      expect(workUpdates, hasLength(1));
    });

    test(
      '(b) an OPEN, actively-running session refuses LOUD (zero writes)',
      () async {
        final state = _FakeStore([
          _session('tgdog-s1', workBead: 'tg-9', running: true),
        ]);
        final work = _FakeStore([_workBead('tg-9')]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/work/tg'),
          workspaceOverride: _ws('tg'),
          bdOverride: BdCliService(work),
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
        expect(state.writes, isEmpty);
        expect(work.writes, isEmpty);
      },
    );

    test('(b) an OPEN session with no cursor at all (freshly spawning) '
        'refuses LOUD (zero writes)', () async {
      final state = _FakeStore([_session('tgdog-s1', workBead: 'tg-9')]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test('an OPEN HISTORICAL FLAT session parked at a gate now REFUSES — its '
        'legacy grid.cursor.* keys no longer project (tg-eli phase 2), so the '
        'empty cursor takes the refusal path; moot by construction (the '
        'engine can no longer drive a flat session; the molecule gated case '
        'proceeds — see the molecule group)', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', gated: true),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty, reason: 'fail-closed: zero writes');
      expect(work.writes, isEmpty);
    });

    test('(c) the ~3-round cap refuses LOUD (zero writes)', () async {
      final state = _FakeStore([
        _session('tgdog-r1', workBead: 'tg-9#r1', closed: true),
        _session('tgdog-r2', workBead: 'tg-9#r2', closed: true),
        _session('tgdog-r3', workBead: 'tg-9#r3', closed: true),
        _session('tgdog-cur', workBead: 'tg-9', closed: true),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('cap 3'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test(
      'round numbering: an existing #r1 makes the next rework round 2',
      () async {
        final state = _FakeStore([
          _session('tgdog-r1', workBead: 'tg-9#r1', closed: true),
          _session('tgdog-cur', workBead: 'tg-9', closed: true),
        ]);
        final work = _FakeStore([_workBead('tg-9')]);
        final out = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/work/tg'),
          workspaceOverride: _ws('tg'),
          bdOverride: BdCliService(work),
          out: out.add,
          err: (_) {},
        );

        expect(code, 0);
        expect(out.join('\n'), contains('round 2'));
        final updates = state.writes.where((c) => c.first == 'update').toList();
        final metaIdx = updates.single.indexOf('--metadata');
        final meta =
            jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
        expect(meta, {'work_bead': 'tg-9#r2'});
        expect(work.writes.where((c) => c.first == 'update'), hasLength(1));
      },
    );

    test('refuses (non-zero, zero writes) when no session is found', () async {
      final state = _FakeStore([]);
      final work = _FakeStore([_workBead('tg-nope')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-nope',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('no session found'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test(
      'refuses (non-zero, zero writes) on more than one current session',
      () async {
        final state = _FakeStore([
          _session('tgdog-a', workBead: 'tg-9', closed: true),
          _session('tgdog-b', workBead: 'tg-9', closed: true),
        ]);
        final work = _FakeStore([_workBead('tg-9')]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/work/tg'),
          workspaceOverride: _ws('tg'),
          bdOverride: BdCliService(work),
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('ambiguous'));
        expect(state.writes, isEmpty);
        expect(work.writes, isEmpty);
      },
    );

    test(
      'clears stale work-bead spec before the session re-key and advances round',
      () async {
        final state = _FakeStore([
          _session('tgdog-r1', workBead: 'tg-9#r1', closed: true),
          _session('tgdog-cur', workBead: 'tg-9', closed: true),
        ]);
        final work = _FakeStore([_workBead('tg-9')]);
        final out = <String>[];
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/work/tg'),
          workspaceOverride: _ws('tg'),
          bdOverride: BdCliService(work),
          out: out.add,
          err: errs.add,
        );

        expect(code, 0, reason: errs.join('\n'));
        expect(out.join('\n'), contains('round 2'));
        final workUpdates = work.writes
            .where((c) => c.first == 'update')
            .toList();
        expect(workUpdates, hasLength(1));
        expect(workUpdates.single, containsAllInOrder(['update', 'tg-9']));
        expect(workUpdates.single, containsAllInOrder(['--design', '']));
        expect(workUpdates.single, containsAllInOrder(['--acceptance', '']));
        expect(workUpdates.single, isNot(contains('--description')));
        expect(workUpdates.single, isNot(contains('--notes')));
        expect(workUpdates.single, isNot(contains('--append-notes')));
        final stateUpdates = state.writes
            .where((c) => c.first == 'update')
            .toList();
        expect(stateUpdates, hasLength(1));
        final metaIdx = stateUpdates.single.indexOf('--metadata');
        final meta =
            jsonDecode(stateUpdates.single[metaIdx + 1])
                as Map<String, dynamic>;
        expect(meta, {'work_bead': 'tg-9#r2'});
      },
    );

    test(
      'work spec clear failure exits loud and leaves the state round untouched',
      () async {
        final state = _FakeStore([
          _session('tgdog-s1', workBead: 'tg-9', closed: true),
        ]);
        final work = _FailingUpdateStore([_workBead('tg-9')]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/work/tg'),
          workspaceOverride: _ws('tg'),
          bdOverride: BdCliService(work),
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('work bead spec clear failed'));
        expect(work.writes.where((c) => c.first == 'update'), hasLength(1));
        expect(state.writes, isEmpty);
      },
    );
  });

  group('grid rework — molecule sessions (tg-eli phase 1 parity)', () {
    test('(a) an OPEN molecule session with a RUNNING step refuses LOUD — '
        'the live veto (zero writes)', () async {
      final state = _FakeStore([
        _moleculeSession('tgdog-s1', workBead: 'tg-9'),
        _stepBead(
          'tgdog-m1',
          sessionId: 'tgdog-s1',
          nodePath: 'tg-9/agent',
          state: StepState.running,
        ),
        _stepBead('tgdog-m2', sessionId: 'tgdog-s1', nodePath: 'tg-9/route'),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test('(b) an OPEN molecule session parked at a gate (nothing running) '
        'proceeds to the re-key', () async {
      final state = _FakeStore([
        _moleculeSession('tgdog-s1', workBead: 'tg-9'),
        _stepBead(
          'tgdog-m1',
          sessionId: 'tgdog-s1',
          nodePath: 'tg-9/agent',
          state: StepState.complete,
        ),
        _stepBead(
          'tgdog-m2',
          sessionId: 'tgdog-s1',
          nodePath: 'tg-9/route',
          state: StepState.gated,
        ),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(out.join('\n'), contains('round 1'));
      final updates = state.writes.where((c) => c.first == 'update').toList();
      expect(updates, hasLength(1));
      final metaIdx = updates.single.indexOf('--metadata');
      final meta =
          jsonDecode(updates.single[metaIdx + 1]) as Map<String, dynamic>;
      expect(meta, {'work_bead': 'tg-9#r1'});
      expect(work.writes.where((c) => c.first == 'update'), hasLength(1));
    });

    test('an OPEN molecule session with NO step beads yet (a crashed or '
        'still-pouring mint) refuses LOUD — open, non-gated (zero writes)',
        () async {
      final state = _FakeStore([
        _moleculeSession('tgdog-s1', workBead: 'tg-9'),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test('NEGATIVE CONTROL: another session\'s RUNNING step never vetoes this '
        'session\'s rework (the step-bead join is per-session)', () async {
      final state = _FakeStore([
        _moleculeSession('tgdog-s1', workBead: 'tg-9'),
        _stepBead(
          'tgdog-m1',
          sessionId: 'tgdog-s1',
          nodePath: 'tg-9/route',
          state: StepState.gated,
        ),
        // A NEIGHBOUR molecule session mid-flight on a different work bead —
        // its running step belongs to tgdog-s2's cursor, never tgdog-s1's.
        _moleculeSession('tgdog-s2', workBead: 'tg-8'),
        _stepBead(
          'tgdog-m9',
          sessionId: 'tgdog-s2',
          nodePath: 'tg-8/agent',
          state: StepState.running,
        ),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(state.writes.where((c) => c.first == 'update'), hasLength(1));
    });

    test('the ACTIVE incarnation decides (A52): a superseded gated step never '
        'masks its RUNNING successor — refused (zero writes)', () async {
      final state = _FakeStore(
        [
          _moleculeSession('tgdog-s1', workBead: 'tg-9'),
          _stepBead(
            'tgdog-m1',
            sessionId: 'tgdog-s1',
            nodePath: 'tg-9/agent',
            state: StepState.gated,
          ),
          _stepBead(
            'tgdog-m2',
            sessionId: 'tgdog-s1',
            nodePath: 'tg-9/agent',
            state: StepState.running,
          ),
        ],
        dependencies: [
          const BeadDependency(
            issueId: 'tgdog-m2',
            dependsOnId: 'tgdog-m1',
            type: DependencyType.supersedes,
          ),
        ],
      );
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, isNonZero);
      expect(errs.join('\n'), contains('OPEN and not parked at a gate'));
      expect(state.writes, isEmpty);
      expect(work.writes, isEmpty);
    });

    test('NEGATIVE CONTROL (A52 converse): a RETIRED running incarnation '
        'never vetoes when its GATED successor is the active step', () async {
      final state = _FakeStore(
        [
          _moleculeSession('tgdog-s1', workBead: 'tg-9'),
          _stepBead(
            'tgdog-m1',
            sessionId: 'tgdog-s1',
            nodePath: 'tg-9/agent',
            state: StepState.running,
          ),
          _stepBead(
            'tgdog-m2',
            sessionId: 'tgdog-s1',
            nodePath: 'tg-9/agent',
            state: StepState.gated,
          ),
        ],
        dependencies: [
          const BeadDependency(
            issueId: 'tgdog-m2',
            dependsOnId: 'tgdog-m1',
            type: DependencyType.supersedes,
          ),
        ],
      );
      final work = _FakeStore([_workBead('tg-9')]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: (_) {},
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      expect(state.writes.where((c) => c.first == 'update'), hasLength(1));
    });
  });

  group('grid rework — (d) --note lands on the WORK bead', () {
    test('appends the finding under a ROUND N header, into the WORK '
        'work store (a SEPARATE store from the state store)', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final work = _FakeStore([_workBead('tg-9')]);
      final out = <String>[];
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        note: 'the committee rejected on validation_plan drift',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        noteStore: SubstationWorkStore.forRoot('/work/tg'),
        workspaceOverride: _ws('tg'),
        bdOverride: BdCliService(work),
        out: out.add,
        err: errs.add,
      );

      expect(code, 0, reason: errs.join('\n'));
      // The state store gets exactly the re-key write.
      expect(state.writes.where((c) => c.first == 'update'), hasLength(1));
      // The WORK store clears stale spec first, then appends notes.
      final workUpdates = work.writes
          .where((c) => c.first == 'update')
          .toList();
      expect(workUpdates, hasLength(2));
      expect(workUpdates.first, containsAllInOrder(['update', 'tg-9']));
      expect(workUpdates.first, containsAllInOrder(['--design', '']));
      expect(workUpdates.first, containsAllInOrder(['--acceptance', '']));
      expect(workUpdates.first, isNot(contains('--append-notes')));
      expect(workUpdates.last, containsAllInOrder(['update', 'tg-9']));
      final noteIdx = workUpdates.last.indexOf('--append-notes');
      expect(noteIdx, greaterThan(-1));
      final note = workUpdates.last[noteIdx + 1];
      expect(note, contains('ROUND 1'));
      expect(note, contains('the committee rejected on validation_plan drift'));
      expect(workUpdates.last, isNot(contains('--design')));
      expect(workUpdates.last, isNot(contains('--acceptance')));
    });

    test('without --note-root refuses LOUD before any write', () async {
      final state = _FakeStore([
        _session('tgdog-s1', workBead: 'tg-9', closed: true),
      ]);
      final errs = <String>[];

      final code = await runRework(
        beadId: 'tg-9',
        stateStore: _stateStore(),
        stateStorePrefix: 'tgdog',
        stateWorkspaceOverride: _ws('tgdog'),
        stateBdOverride: BdCliService(state),
        out: (_) {},
        err: errs.add,
      );

      expect(code, 64);
      expect(errs.join('\n'), contains('--note-root is required'));
      expect(state.writes, isEmpty);
    });

    test(
      '--note whose WORK store is unreachable refuses LOUD before any write',
      () async {
        final state = _FakeStore([
          _session('tgdog-s1', workBead: 'tg-9', closed: true),
        ]);
        final errs = <String>[];

        final code = await runRework(
          beadId: 'tg-9',
          note: 'a finding',
          stateStore: _stateStore(),
          stateStorePrefix: 'tgdog',
          stateWorkspaceOverride: _ws('tgdog'),
          stateBdOverride: BdCliService(state),
          noteStore: SubstationWorkStore.forRoot('/definitely/not/a/store'),
          dirExists: (_) => false, // the work store does not exist at the root.
          out: (_) {},
          err: errs.add,
        );

        expect(code, isNonZero);
        expect(errs.join('\n'), contains('WORK store is unreachable'));
        expect(state.writes, isEmpty);
      },
    );
  });

  group('CLI wiring — the store axis is the grid root (fossils dead)', () {
    // The missing-flag refusals write to stderr inside the Command and return
    // the fail-closed code (64) — the observable CLI contract. (The messages
    // are asserted at the run-level tests, which take injectable sinks.)
    test('rework without --grid-root refuses LOUD (exit 64)', () async {
      final code = await _run(['rework', 'tg-9', '--prefix', 'tgdog']);
      expect(code, 64);
    });

    test('rework without --prefix refuses LOUD (exit 64)', () async {
      final code = await _run(['rework', 'tg-9', '--grid-root', '/home/grid']);
      expect(code, 64);
    });

    test('rework without --note-root refuses LOUD (exit 64)', () async {
      final code = await _run([
        'rework',
        'tg-9',
        '--grid-root',
        '/home/grid',
        '--prefix',
        'tgdog',
      ]);
      expect(code, 64);
    });

    test(
      'the retired --state-workspace / --workspace flags are GONE',
      () async {
        final errs = <String>[];
        final code = await _run([
          'rework',
          'tg-9',
          '--state-workspace',
          '/x',
          '--workspace',
          '/y',
        ], err: errs.add);
        expect(code, 64);
        expect(errs.join('\n'), contains('Could not find an option'));
      },
    );
  });
}

/// Runs the `rework` command through a real [CommandRunner] so the CLI wiring
/// (flag parsing + the missing-flag refusals) is exercised end to end.
Future<int> _run(List<String> args, {void Function(String)? err}) async {
  final writeErr = err ?? (_) {};
  final runner = CommandRunner<int>('grid', 'test')
    ..addCommand(ReworkCommand());
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    writeErr('$e');
    return 64;
  }
}

/// A state store addressed at a grid root (the v3 currency). Unused when a test
/// passes a `stateWorkspaceOverride` — the required, model-shaped handle.
GridStateStore _stateStore() => GridStateStore.forGridRoot('/home/grid');

/// A direct/embedded workspace (no real `.beads/` on disk needed — the bd
/// runner is faked).
BeadsWorkspace _ws(String database) => BeadsWorkspace(
  root: '/fake/$database',
  mode: DoltMode.direct,
  database: database,
  gtRoot: null,
  endpoint: null,
);

/// Builds a HISTORICAL flat `type=session` bead carrying the `work_bead`
/// linkage, optionally closed, and optionally carrying legacy `grid.cursor.*`
/// entries (`running` or `gated`) as RAW WIRE LITERALS — the flat codec is
/// deleted (tg-eli phase 2), so these keys are exactly what a pre-phase-2
/// store row still holds, and the verb must treat them as INERT.
Bead _session(
  String id, {
  required String workBead,
  bool closed = false,
  bool running = false,
  bool gated = false,
}) => Bead(
  id: id,
  title: 'grid session $workBead',
  issueType: IssueType.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  createdAt: DateTime.utc(2026, 7, 3, 12),
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBead,
    if (running) 'grid.cursor.$workBead/agent.state': 'running',
    if (gated) 'grid.cursor.$workBead/route.state': 'gated',
  },
);

/// Builds a MOLECULE-minted `type=session` bead (tg-eli phase 1): carries the
/// explicit `grid.session.model=molecule` discriminator stamped once at mint
/// (`SessionScope._mintMolecule`) and NO flat `grid.cursor.*` keys — its
/// per-node state lives on its own `type=step` beads ([_stepBead]).
Bead _moleculeSession(String id, {required String workBead, bool closed = false}) =>
    Bead(
      id: id,
      title: 'grid session $workBead',
      issueType: IssueType.session,
      status: closed ? BeadStatus.closed : BeadStatus.open,
      createdAt: DateTime.utc(2026, 7, 3, 12),
      metadata: {
        'rig': 'tgdog',
        'work_bead': workBead,
        SessionBeadKeys.model: kSessionModelMolecule,
      },
    );

/// Builds a `type=step` bead owned by [sessionId] at [nodePath], carrying the
/// fine state under the molecule schema's wire literals (`grid.step.*` —
/// `MoleculeStepKeys` now rides grid_engine's package root). A null [state]
/// mirrors a freshly-minted step bead: no fine state yet, read back as
/// `pending`.
Bead _stepBead(
  String id, {
  required String sessionId,
  required String nodePath,
  StepState? state,
}) => Bead(
  id: id,
  title: 'step $nodePath',
  issueType: IssueType.step,
  metadata: {
    'grid.step.session': sessionId,
    'grid.step.path': nodePath,
    if (state != null) 'grid.step.state': state.name,
  },
);

Bead _workBead(
  String id, {
  String description = 'operator description',
  String design = 'stale round design',
  String acceptanceCriteria = '- [ ] stale round criterion',
  String notes = 'operator note history',
}) => Bead(
  id: id,
  title: 'work',
  description: description,
  design: design,
  acceptanceCriteria: acceptanceCriteria,
  notes: notes,
  issueType: IssueType.task,
);

/// A fake [BdRunner] over a fixed set of staged beads (Fakes, not mocks): the
/// `export` read returns the staged beads as JSONL — each bead's staged
/// [dependencies] riding INLINE on its own line, exactly where the upstream
/// `Issue.Dependencies` field puts them and `exportAll`'s parse reads them —
/// mutations return a canned envelope and are recorded so a test can assert a
/// refusal performed ZERO writes.
class _FakeStore implements BdRunner {
  _FakeStore(this._beads, {List<BeadDependency> dependencies = const []})
    : _dependencies = dependencies;

  final List<Bead> _beads;
  final List<BeadDependency> _dependencies;
  final List<List<String>> calls = <List<String>>[];

  /// Every recorded invocation that is NOT the `export` read — i.e. the writes.
  List<List<String>> get writes =>
      calls.where((c) => c.isNotEmpty && c.first != 'export').toList();

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls.add(List<String>.unmodifiable(args));
    final cmd = args.isNotEmpty ? args.first : '';
    if (cmd == 'export') {
      final jsonl = _beads.map((b) {
        final json = b.toJson();
        final edges = _dependencies.where((d) => d.issueId == b.id).toList();
        if (edges.isNotEmpty) {
          json['dependencies'] = [for (final e in edges) e.toJson()];
        }
        return jsonEncode(json);
      }).join('\n');
      return Future<BdResult>.value(
        BdResult(exitCode: 0, stdout: jsonl, stderr: ''),
      );
    }
    final id = args.length >= 2 ? args[1] : '';
    return Future<BdResult>.value(
      BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":{"id":"$id"}}',
        stderr: '',
      ),
    );
  }
}

class _FailingUpdateStore extends _FakeStore {
  _FailingUpdateStore(super.beads);

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (args.isNotEmpty && args.first == 'update') {
      calls.add(List<String>.unmodifiable(args));
      return Future<BdResult>.value(
        const BdResult(
          exitCode: 1,
          stdout: '{"schema_version":1,"data":{"error":"spec clear failed"}}',
          stderr: '',
        ),
      );
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}
