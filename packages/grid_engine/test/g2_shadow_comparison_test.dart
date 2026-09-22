import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

G2GraphObservation _graph({String kind = 'blocks'}) => G2GraphObservation(
  nodes: const ['build', 'verify'],
  edges: [
    G2GraphEdgeObservation(fromPath: 'verify', toPath: 'build', kind: kind),
  ],
);

G2MoleculeObservation _molecule({
  G2GraphObservation? legacy,
  G2GraphObservation? applied,
}) => G2MoleculeObservation(
  sessionId: 'session-1',
  round: 2,
  recordGraph: _graph(),
  legacyGraph: legacy ?? _graph(),
  appliedPlanGraph: applied ?? _graph(),
);

void main() {
  test('poured graph agreement and edge mismatch', () {
    final observer = DualReadStepObserver(mode: DualReadMode.observe);
    observer.observeG2Round(_molecule(), const [], headEpoch: 10);
    expect(observer.accounting.divergenceDetails, isEmpty);

    observer.observeG2Round(
      _molecule(legacy: _graph(kind: 'validates')),
      const [],
      headEpoch: 10,
    );
    observer.observeG2Round(
      _molecule(legacy: _graph(kind: 'validates')),
      const [],
      headEpoch: 10,
    );
    final detail = observer.accounting.divergenceDetails.single;
    expect(detail.cause, DualReadDivergenceCause.moleculeGraphMismatch);
    expect(
      detail.mismatchKey,
      'g2:molecule:session-1:2:legacy-graph:verify:build:kind',
    );
  });

  test('applied plan disagreement is classified', () {
    final observer = DualReadStepObserver(mode: DualReadMode.observe);
    observer.observeG2Round(
      _molecule(applied: _graph(kind: 'validates')),
      const [],
      headEpoch: 10,
    );
    final detail = observer.accounting.divergenceDetails.single;
    expect(detail.cause, DualReadDivergenceCause.graphApplyPlanMismatch);
    expect(detail.mismatchKey, contains(':applied-plan:'));
  });

  test('successor relationship and depth are classified', () {
    final observer = DualReadStepObserver(mode: DualReadMode.observe);
    observer.observeG2Round(null, [
      const G2SuccessorObservation(
        sessionId: 'session-1',
        round: 2,
        stepPath: 'build',
        newStepRound: 3,
        recordPresent: true,
        legacyPresent: true,
        recordSupersedes: 'old-step',
        legacySupersedes: 'wrong-step',
        recordDepth: 3,
        legacyDepth: 2,
      ),
    ], headEpoch: 10);
    expect(
      observer.accounting.divergenceDetails.map((detail) => detail.cause),
      [
        DualReadDivergenceCause.successorRelationshipMismatch,
        DualReadDivergenceCause.successorDepthMismatch,
      ],
    );
    expect(
      observer.accounting.divergenceDetails.last.mismatchKey,
      'g2:successor:session-1:2:build:3:depth',
    );
  });

  test('precedent classifications remain explained', () {
    expect(
      DualReadDivergenceCause.retiredRoundOpenByDesign.wire,
      'retired-round-open-by-design',
    );
    expect(
      DualReadDivergenceCause.operatorStoreEdit.wire,
      'operator-store-edit',
    );
    expect(
      DualReadDivergenceCause.foldAheadOfLegacy.wire,
      'fold-ahead-of-legacy',
    );
  });

  test('off posture does not compare G2 observations', () {
    final observer = DualReadStepObserver(mode: DualReadMode.off);
    observer.observeG2Round(
      _molecule(legacy: _graph(kind: 'validates')),
      const [],
      headEpoch: 10,
    );
    expect(observer.accounting.divergenceDetails, isEmpty);
  });
}
