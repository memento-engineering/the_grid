import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';

Bead _step({
  required String id,
  required String session,
  String? path,
  String? grade,
  String? transport,
  String? startedAt = '2026-07-11T09:00:00-05:00',
  String? finishedAt = '2026-07-11T09:01:00-05:00',
  String? durationMs = '60000',
  Map<String, String> extras = const {},
}) {
  final metadata = <String, dynamic>{
    MoleculeStepKeys.session: session,
    if (path != null) MoleculeStepKeys.path: path,
    if (startedAt != null) MoleculeStepKeys.startedAt: startedAt,
    if (finishedAt != null) MoleculeStepKeys.finishedAt: finishedAt,
    if (durationMs != null) MoleculeStepKeys.durationMs: durationMs,
  };
  if (path != null) {
    if (grade != null) {
      metadata[ResultKeys.keyFor(path, ResultKeys.grade)] = grade;
    }
    if (transport != null) {
      metadata[ResultKeys.keyFor(path, ResultKeys.transport)] = transport;
    }
    for (final entry in extras.entries) {
      metadata[ResultKeys.keyFor(path, entry.key)] = entry.value;
    }
  }
  return Bead(
    id: id,
    issueType: GridIssueTypes.step,
    status: BeadStatus.open,
    metadata: metadata,
  );
}

GraphSnapshot sessionLedgerMetricsFixture() => GraphSnapshot.fromParts(
  beads: <Bead>[
    Bead(
      id: 'session-legacy',
      issueType: GridIssueTypes.session,
      status: BeadStatus.closed,
      metadata: <String, dynamic>{
        SessionBeadKeys.workBead: 'tg-work-1',
        SessionBeadKeys.startedAt: '2026-07-10T10:00:00-05:00',
        SessionBeadKeys.closedAt: '2026-07-10T10:10:00-05:00',
        ResultKeys.keyFor('review/coherence', ResultKeys.grade): 'F',
        ResultKeys.keyFor('review/coherence', ResultKeys.transport):
            'fail-closed-default',
        ResultKeys.keyFor('review/coherence', ResultMetricFields.costUsd):
            '2.5',
        ResultKeys.keyFor('review/coherence', ResultMetricFields.tokensIn):
            '100',
        ResultKeys.keyFor(
          'review/coherence',
          ResultMetricFields.cacheReadInputTokens,
        ): '300',
        ResultKeys.keyFor('land', ResultKeys.delivery): 'pr',
        'grid.result.broken': 'wire',
      },
    ),
    Bead(
      id: 'session-molecule',
      issueType: GridIssueTypes.session,
      status: BeadStatus.open,
      metadata: <String, dynamic>{SessionBeadKeys.workBead: 'tg-work-1'},
    ),
    _step(
      id: 'critic-0',
      session: 'session-molecule',
      path: 'review/coherence',
      grade: 'F',
      transport: 'file-verdict',
      extras: const {
        ResultMetricFields.costUsd: '1.5',
        ResultMetricFields.tokensIn: '100',
        ResultMetricFields.cacheCreationInputTokens: '500',
        'future_field': 'preserved',
      },
    ),
    _step(
      id: 'critic-1',
      session: 'session-molecule',
      path: 'review/coherence',
      grade: 'A',
      transport: 'operator-ruling',
      startedAt: '2026-07-11T09:02:00-05:00',
      finishedAt: '2026-07-11T09:03:00-05:00',
      extras: const {ResultMetricFields.costUsd: '-1'},
    ),
    _step(
      id: 'malformed',
      session: 'session-molecule',
      path: 'review/style',
      grade: 'Z',
      startedAt: 'not-a-date',
      finishedAt: null,
      durationMs: null,
      extras: const {
        ResultMetricFields.tokensOut: '-2',
        ResultMetricFields.numTurns: 'many',
      },
    ),
    _step(
      id: 'orphan',
      session: 'missing-session',
      path: 'review/orphan',
      grade: 'B',
    ),
    _step(id: 'missing-path', session: 'session-molecule', path: null),
  ],
  dependencies: const <BeadDependency>[
    BeadDependency(
      issueId: 'critic-1',
      dependsOnId: 'critic-0',
      type: DependencyType.supersedes,
    ),
  ],
  readyIds: const <String>[],
  capturedAt: DateTime.utc(2026, 7, 11),
);
