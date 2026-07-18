// R5a — the join substrate: `grid.session.model` + the `moleculeBeads`
// bucket.
//
// The read path NEITHER original proposal specified (DESIGN-tg-pm6.md §2):
// molecule beads reach `SessionScope.build` only through this bucket
// (`session_scope.dart:667`'s `joined?.cursor` precedent). Exercised through
// the REAL `StationJoinBridge` — the established pattern for join-bucketing
// coverage (`track_a_gate_test.dart`'s "Track A3 — join" group, which proves
// `openGateNodes` the same way).
//
// DESIGN-tg-pm6.md §10 / §14. Zero I/O: FakeSnapshotSource only.
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

/// A work-graph snapshot from [beads] (every bead ready, for brevity) —
/// mirrors `track_a_gate_test.dart`'s `_graph` / `join_bridge_test.dart`'s
/// `graphOf`.
GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: {for (final b in beads) b.id},
  capturedAt: DateTime(2026),
);

/// A `type=molecule` bead owned by [sessionId] (`MoleculeCircuitKeys.session`).
Bead _moleculeBead(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: IssueType.molecule,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeCircuitKeys.formula: 'code',
    MoleculeCircuitKeys.session: sessionId,
  },
);

/// A `type=step` bead owned by [sessionId] (`MoleculeStepKeys.session`) at
/// engine coordinate [path].
Bead _stepBead(String id, {required String sessionId, required String path}) =>
    Bead(
      id: id,
      issueType: IssueType.step,
      status: BeadStatus.open,
      metadata: {
        'rig': stateSubstation,
        MoleculeStepKeys.stepId: path.split('/').last,
        MoleculeStepKeys.capability: 'agent',
        MoleculeStepKeys.kind: StepKind.job.name,
        MoleculeStepKeys.path: path,
        MoleculeStepKeys.session: sessionId,
      },
    );

void main() {
  group('R5a — SessionBeadKeys.model (the mint-mode discriminator)', () {
    test('an ABSENT model key projects isMolecule=false — every in-flight '
        'flat session, unchanged', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final state = FakeSnapshotSource(
        _graph([sessionBead(id: 's1', workBeadId: 'w1')]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      final projection = bridge.latest.sessionsByWorkBead['w1'];
      expect(projection, isNotNull);
      expect(projection!.isMolecule, isFalse);
      expect(projection.moleculeBeads, isEmpty);
    });

    test('grid.session.model=molecule projects isMolecule=true even with '
        'ZERO molecule beads yet (a crashed pour must not sniff flat)', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final state = FakeSnapshotSource(
        _graph([
          sessionBead(
            id: 's1',
            workBeadId: 'w1',
            metadata: {SessionBeadKeys.model: kSessionModelMolecule},
          ),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      final projection = bridge.latest.sessionsByWorkBead['w1'];
      expect(projection, isNotNull);
      expect(projection!.isMolecule, isTrue);
      expect(
        projection.moleculeBeads,
        isEmpty,
        reason: 'the discriminator is EXPLICIT, never child-sniffed',
      );
    });

    test('an unrecognised model value is NOT molecule (fail-closed, like '
        'absent)', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final state = FakeSnapshotSource(
        _graph([
          sessionBead(
            id: 's1',
            workBeadId: 'w1',
            metadata: {SessionBeadKeys.model: 'some-future-model'},
          ),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      expect(bridge.latest.sessionsByWorkBead['w1']!.isMolecule, isFalse);
    });
  });

  group('R5a — the moleculeBeads bucket', () {
    test('a snapshot with one flat session + one molecule session projects '
        'BOTH correctly', () {
      final work = FakeSnapshotSource(_graph([bead('w1'), bead('w2')]));
      final state = FakeSnapshotSource(
        _graph([
          // w1: an ordinary flat session — no model key, no molecule beads.
          sessionBead(id: 's1', workBeadId: 'w1', completed: {'agent'}),
          // w2: a molecule-mode session with its own molecule + step beads.
          sessionBead(
            id: 's2',
            workBeadId: 'w2',
            metadata: {SessionBeadKeys.model: kSessionModelMolecule},
          ),
          _moleculeBead('m1', sessionId: 's2'),
          _stepBead('st1', sessionId: 's2', path: 'w2/build'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      final flat = bridge.latest.sessionsByWorkBead['w1']!;
      expect(flat.isMolecule, isFalse);
      expect(flat.moleculeBeads, isEmpty);
      // The flat session's OTHER fields stay byte-for-byte what they always
      // were — the molecule bucket touches nothing else on this projection.
      expect(flat.cursor['w1/agent']?.state, StepState.complete);

      final molecule = bridge.latest.sessionsByWorkBead['w2']!;
      expect(molecule.isMolecule, isTrue);
      expect(
        molecule.moleculeBeads.map((b) => b.id),
        containsAll(<String>['m1', 'st1']),
      );
      expect(molecule.moleculeBeads, hasLength(2));
    });

    test('a step/molecule bead stamped for an UNKNOWN session is skipped, '
        'fail-closed (no crash, no stray bucket)', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final state = FakeSnapshotSource(
        _graph([
          sessionBead(id: 's1', workBeadId: 'w1'),
          _moleculeBead('m-stray', sessionId: 'no-such-session'),
          _stepBead('st-stray', sessionId: 'no-such-session', path: 'x/y'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      expect(bridge.latest.sessionsByWorkBead, hasLength(1));
      expect(bridge.latest.sessionsByWorkBead['w1']!.moleculeBeads, isEmpty);
    });

    test('a molecule/step bead with NO session stamp is skipped (malformed, '
        'fail-closed)', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final unstamped = Bead(
        id: 'm-unstamped',
        issueType: IssueType.molecule,
        status: BeadStatus.open,
        metadata: const {'rig': stateSubstation},
      );
      final state = FakeSnapshotSource(
        _graph([sessionBead(id: 's1', workBeadId: 'w1'), unstamped]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      expect(bridge.latest.sessionsByWorkBead['w1']!.moleculeBeads, isEmpty);
    });

    test('a non-molecule, non-step, non-session, non-gate bead is ignored by '
        'the bucket', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final decoy = Bead(
        id: 'decoy',
        issueType: IssueType.task,
        status: BeadStatus.open,
        metadata: {MoleculeStepKeys.session: 's1'},
      );
      final state = FakeSnapshotSource(
        _graph([sessionBead(id: 's1', workBeadId: 'w1'), decoy]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      expect(bridge.latest.sessionsByWorkBead['w1']!.moleculeBeads, isEmpty);
    });
  });

  group('R5a — molecule beads never leak into work/drive projections '
      '(work_list.dart:317 regression, at the projection level)', () {
    test('IssueType.molecule / IssueType.step are non-core — the invariant '
        '`_isDispatchableWork` (work_list.dart:317) fails closed on, '
        'regardless of what mounts', () {
      expect(IssueType.molecule.isCore, isFalse);
      expect(IssueType.step.isCore, isFalse);
      expect(driveableTypes.contains(IssueType.molecule), isFalse);
      expect(driveableTypes.contains(IssueType.step), isFalse);
    });

    test('molecule/step beads live ONLY in sessionsByWorkBead[...].'
        'moleculeBeads — JoinedSnapshot.graph (the work axis WorkList reads) '
        'never carries them', () {
      final work = FakeSnapshotSource(_graph([bead('w1')]));
      final state = FakeSnapshotSource(
        _graph([
          sessionBead(
            id: 's1',
            workBeadId: 'w1',
            metadata: {SessionBeadKeys.model: kSessionModelMolecule},
          ),
          _moleculeBead('m1', sessionId: 's1'),
          _stepBead('st1', sessionId: 's1', path: 'w1/build'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state);
      addTearDown(bridge.dispose);

      // The bucket is populated...
      expect(
        bridge.latest.sessionsByWorkBead['w1']!.moleculeBeads,
        hasLength(2),
      );
      // ...but the WORK graph — the ONLY thing `WorkList` mounts from — is the
      // work source alone, untouched by the state-store scan.
      expect(bridge.latest.graph.beadsById.keys, ['w1']);
      expect(bridge.latest.graph.beadsById.keys, isNot(contains('m1')));
      expect(bridge.latest.graph.beadsById.keys, isNot(contains('st1')));
    });
  });
}
