import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'fixtures/session_ledger_metrics_snapshot.dart';

void main() {
  test(
    'typed node decode preserves raw fields and reports malformed values',
    () {
      final snapshot = sessionLedgerMetricsFixture();
      final before = Map<String, dynamic>.from(
        snapshot.bead('critic-1')!.metadata,
      );
      final projection = projectSessionLedgerMetrics(snapshot);
      final molecule = projection.sessionsById['session-molecule']!;
      final coherence = molecule.nodesByLane['coherence']!;
      expect(coherence, hasLength(2));
      expect(coherence.first.grade, LedgerGrade.f);
      expect(switch (coherence.first.transport) {
        ResultTransportReported(:final value) => value,
        ResultTransportAbsent() ||
        ResultTransportFailClosedDefault() ||
        ResultTransportOperatorRuling() => null,
      }, 'file-verdict');
      expect(coherence.first.rawFields['future_field'], 'preserved');
      expect(coherence.first.startedAt, DateTime.utc(2026, 7, 11, 14));
      expect(coherence.first.finishedAt, DateTime.utc(2026, 7, 11, 14, 1));
      expect(coherence.first.durationMs, 60000);
      expect(coherence.last.costUsd, isNull);
      expect(coherence.last.issues, isNotEmpty);
      final legacy = projection.sessionsById['session-legacy']!;
      expect(legacy.startedAt, DateTime.utc(2026, 7, 10, 15));
      expect(legacy.closedAt, DateTime.utc(2026, 7, 10, 15, 10));
      expect(legacy.nodesByLane['coherence']!.single.startedAt, isNull);
      expect(projection.sessionsByLane['coherence'], hasLength(2));
      expect(snapshot.bead('critic-1')!.metadata, before);
      expect(projectSessionLedgerMetrics(snapshot), projection);
      expect(() => projection.sessionsById.clear(), throwsUnsupportedError);
    },
  );

  test('grid-wide derived metrics use fixed denominators and partitions', () {
    final metrics = projectSessionLedgerMetrics(sessionLedgerMetricsFixture());
    expect(
      metrics.falseFs,
      const FalseFMetrics(
        total: 2,
        failClosedDefault: 1,
        realVerdict: 1,
        rate: 0.5,
      ),
    );
    expect(metrics.cacheHitRatio, 0.3);
    expect(metrics.reworkRoundsByWorkBead['tg-work-1'], 1);
    expect(metrics.costPerLandedDelivery, 2.5);
    expect(metrics.gradeDistributionByLane['coherence'], {
      LedgerGrade.f: 2,
      LedgerGrade.a: 1,
    });
  });

  test('malformed and orphan rows are total decode issues', () {
    final metrics = projectSessionLedgerMetrics(sessionLedgerMetricsFixture());
    final session = metrics.sessionsById['session-molecule']!;
    expect(session.nodesByLane['coherence'], hasLength(2));
    final malformed = session.nodesByLane['style']!.single;
    expect(
      (
        malformed.grade,
        malformed.tokensOut,
        malformed.numTurns,
        malformed.startedAt,
      ),
      (null, null, null, null),
    );
    expect(
      malformed.issues.map((issue) => (issue.field, issue.reason)),
      containsAll([
        (ResultKeys.grade, 'expected A through F'),
        (ResultMetricFields.tokensOut, 'must be non-negative integer'),
        (ResultMetricFields.numTurns, 'expected integer'),
        (MoleculeStepKeys.startedAt, 'expected ISO-8601 timestamp'),
      ]),
    );
    expect(
      metrics.issues.map((issue) => (issue.beadId, issue.reason)),
      containsAll([
        ('session-legacy', 'result key requires node path and field'),
        ('missing-path', 'missing node path'),
        ('orphan', 'orphan step result'),
      ]),
    );
  });

  test('pure immutable projection preserves input and order', () {
    final empty = projectSessionLedgerMetrics(
      GraphSnapshot.fromParts(
        beads: const <Bead>[],
        dependencies: const <BeadDependency>[],
        readyIds: const <String>[],
        capturedAt: DateTime.utc(2026, 7, 11),
      ),
    );
    expect(
      (empty.falseFs.rate, empty.cacheHitRatio, empty.costPerLandedDelivery),
      (null, null, null),
    );
    final snapshot = sessionLedgerMetricsFixture();
    final before = {
      for (final bead in snapshot.beads)
        bead.id: Map<String, dynamic>.from(bead.metadata),
    };
    final first = projectSessionLedgerMetrics(snapshot);
    final reversed = GraphSnapshot.fromParts(
      beads: snapshot.beads.toList().reversed.toList(),
      dependencies: snapshot.dependencies.toList().reversed.toList(),
      readyIds: const <String>[],
      capturedAt: snapshot.capturedAt,
    );
    expect(projectSessionLedgerMetrics(reversed), first);
    expect(projectSessionLedgerMetrics(snapshot), first);
    expect({for (final bead in snapshot.beads) bead.id: bead.metadata}, before);
    expect(() => first.sessionsById.clear(), throwsUnsupportedError);
    expect(
      () => first.sessionsById.values.first.nodes.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => first.gradeDistributionByLane['coherence']!.clear(),
      throwsUnsupportedError,
    );
  });
}
