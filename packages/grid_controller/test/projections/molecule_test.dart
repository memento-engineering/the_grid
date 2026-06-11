import 'package:grid_controller/grid_controller.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

Bead _firstBead(String fixture) {
  final env = BdEnvelope.parse(fixtureText(fixture));
  return Bead.fromJson(env.dataList.first);
}

Bead _step(String id, {required BeadStatus status}) =>
    Bead(id: id, title: id, issueType: IssueType.step, status: status);

void main() {
  group('Molecule.project against hq-molecule-sample.json (ga-dda)', () {
    test('maps the molecule bead; closed with steps complete', () {
      final bead = _firstBead('hq-molecule-sample.json');
      final molecule = Molecule.project(bead).valueOrNull!;

      expect(molecule.id, 'ga-dda');
      expect(molecule.title, 'mol-dog-stale-db');
      expect(molecule.isClosed, isTrue);
      expect(molecule.closeReason, 'all steps complete');
      expect(molecule.closedAt, isNotNull);
      // not ephemeral, no wisp_type → not a wisp.
      expect(molecule.isWisp, isFalse);
    });

    test('maps the gc.* routing metadata namespace', () {
      final molecule = Molecule.project(
        _firstBead('hq-molecule-sample.json'),
      ).valueOrNull!;
      expect(molecule.metadata.routedTo, 'dolt.dog');
      expect(molecule.metadata.runTarget, 'dog');
    });

    test('unknown / raw metadata preserved', () {
      final molecule = Molecule.project(
        _firstBead('hq-molecule-sample.json'),
      ).valueOrNull!;
      expect(molecule.metadata.raw['gc.routed_to'], 'dolt.dog');
    });

    test('a molecule with no captured steps has progress 1.0', () {
      final molecule = Molecule.project(
        _firstBead('hq-molecule-sample.json'),
      ).valueOrNull!;
      expect(molecule.steps, isEmpty);
      expect(molecule.progress, 1.0);
      expect(molecule.runnableSteps, isEmpty);
    });
  });

  group('Molecule step composition (synthetic — no step fixture in M1)', () {
    // mol --parent-child-- s1, s2, s3 ; s2 needs s1 ; s3 needs s2.
    const molId = 'mol-1';
    final molBead = Bead(
      id: molId,
      title: 'formula',
      issueType: IssueType.molecule,
    );

    List<BeadDependency> deps() => const [
      BeadDependency(
        issueId: 's1',
        dependsOnId: molId,
        type: DependencyType.parentChild,
      ),
      BeadDependency(
        issueId: 's2',
        dependsOnId: molId,
        type: DependencyType.parentChild,
      ),
      BeadDependency(
        issueId: 's3',
        dependsOnId: molId,
        type: DependencyType.parentChild,
      ),
      BeadDependency(
        issueId: 's2',
        dependsOnId: 's1',
        type: DependencyType.blocks,
      ),
      BeadDependency(
        issueId: 's3',
        dependsOnId: 's2',
        type: DependencyType.blocks,
      ),
    ];

    Map<String, Bead> beadsById(BeadStatus s1, BeadStatus s2, BeadStatus s3) =>
        {
          molId: molBead,
          's1': _step('s1', status: s1),
          's2': _step('s2', status: s2),
          's3': _step('s3', status: s3),
        };

    test('resolves child steps from parent-child edges', () {
      final molecule = Molecule.project(
        molBead,
        dependencies: deps(),
        beadsById: beadsById(BeadStatus.open, BeadStatus.open, BeadStatus.open),
      ).valueOrNull!;
      expect(molecule.steps.map((s) => s.id), ['s1', 's2', 's3']);
    });

    test('step needs come from blocking edges between sibling steps', () {
      final molecule = Molecule.project(
        molBead,
        dependencies: deps(),
        beadsById: beadsById(BeadStatus.open, BeadStatus.open, BeadStatus.open),
      ).valueOrNull!;
      final byId = {for (final s in molecule.steps) s.id: s};
      expect(byId['s1']!.needs, isEmpty);
      expect(byId['s2']!.needs, ['s1']);
      expect(byId['s3']!.needs, ['s2']);
    });

    test('progress = closed/total', () {
      final molecule = Molecule.project(
        molBead,
        dependencies: deps(),
        beadsById: beadsById(
          BeadStatus.closed,
          BeadStatus.open,
          BeadStatus.open,
        ),
      ).valueOrNull!;
      expect(molecule.stepCount, 3);
      expect(molecule.closedStepCount, 1);
      expect(molecule.progress, closeTo(1 / 3, 1e-9));
    });

    test('runnableSteps = open steps whose needs are all closed', () {
      // s1 closed → s2 becomes runnable; s3 still blocked by open s2.
      final molecule = Molecule.project(
        molBead,
        dependencies: deps(),
        beadsById: beadsById(
          BeadStatus.closed,
          BeadStatus.open,
          BeadStatus.open,
        ),
      ).valueOrNull!;
      expect(molecule.runnableSteps.map((s) => s.id), ['s2']);
    });

    test('first step with no needs is immediately runnable', () {
      final molecule = Molecule.project(
        molBead,
        dependencies: deps(),
        beadsById: beadsById(BeadStatus.open, BeadStatus.open, BeadStatus.open),
      ).valueOrNull!;
      expect(molecule.runnableSteps.map((s) => s.id), ['s1']);
    });
  });

  group('wisp + step decode', () {
    test('ephemeral bead projects to a wisp molecule', () {
      const bead = Bead(
        id: 'w',
        issueType: IssueType.molecule,
        ephemeral: true,
      );
      expect(Molecule.project(bead).valueOrNull!.isWisp, isTrue);
    });

    test('wisp_type in metadata flags a wisp molecule', () {
      const bead = Bead(
        id: 'w',
        issueType: IssueType.molecule,
        metadata: {'wisp_type': 'health-advisory'},
      );
      final molecule = Molecule.project(bead).valueOrNull!;
      expect(molecule.isWisp, isTrue);
      expect(molecule.metadata.wispType, 'health-advisory');
    });

    test('a non-molecule bead returns a typed ProjectionError', () {
      const bead = Bead(id: 'x', issueType: IssueType.session);
      final result = Molecule.project(bead);
      expect(result.isOk, isFalse);
      expect(result.errorOrNull!.projection, 'Molecule');
    });

    test('Step.project rejects a non-step bead', () {
      const bead = Bead(id: 'x', issueType: IssueType.molecule);
      final result = Step.project(bead);
      expect(result.isOk, isFalse);
      expect(result.errorOrNull!.projection, 'Step');
    });
  });
}
