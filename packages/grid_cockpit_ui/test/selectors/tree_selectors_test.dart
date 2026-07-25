import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/src/selectors/tree_selectors.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import '../fixtures.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1, 12);
  final allProperties = <DiagnosticsProperty>[
    stringProperty('string', 'text', level: DiagnosticsLevel.fine),
    intProperty('integer', 7),
    const DiagnosticsProperty.double(
      name: 'double',
      level: DiagnosticsLevel.warning,
      value: 1.5,
    ),
    const DiagnosticsProperty.flag(
      name: 'flag',
      level: DiagnosticsLevel.error,
      value: true,
    ),
    const DiagnosticsProperty.enumValue(
      name: 'enum',
      level: DiagnosticsLevel.info,
      value: 'ready',
      enumType: 'State',
    ),
    const DiagnosticsProperty.duration(
      name: 'duration',
      level: DiagnosticsLevel.info,
      value: Duration(microseconds: 12),
    ),
    DiagnosticsProperty.timestamp(
      name: 'timestamp',
      level: DiagnosticsLevel.info,
      value: timestamp,
    ),
    const DiagnosticsProperty.reference(
      name: 'reference',
      level: DiagnosticsLevel.info,
      referenceKind: ReferenceKind.bead,
      value: 'tg-1',
    ),
    DiagnosticsProperty.object(
      name: 'object',
      level: DiagnosticsLevel.info,
      properties: [stringProperty('nested', 'yes')],
    ),
  ];

  final recording = ReplayTreeSource([
    snapshot(
      version: 1,
      properties: allProperties,
      children: [
        node(
          id: 'station',
          seedType: 'Substation',
          key: 'fallback-station',
          properties: [stringProperty('substationId', 'alpha')],
          children: [
            node(
              id: 'work',
              seedType: 'WorkBead',
              properties: [
                stringProperty('beadId', 'tg-1'),
                const DiagnosticsProperty.reference(
                  name: 'sessionId',
                  level: DiagnosticsLevel.info,
                  referenceKind: ReferenceKind.session,
                  value: 'session-1',
                ),
                stringProperty('stepState', 'running'),
              ],
            ),
          ],
        ),
        for (final entry in {
          'pending': 'pending',
          'ready': 'ready',
          'complete': 'complete',
          'failed': 'failed',
          'gated': 'gated',
          'unknown': 'future',
        }.entries)
          node(
            id: entry.key,
            seedType: 'Step',
            key: entry.key,
            properties: [
              stringProperty('stepState', entry.value),
              if (entry.key == 'pending') ...[
                stringProperty('nodePath', '/pipeline/pending'),
                intProperty('durationMs', 4),
                const DiagnosticsProperty.reference(
                  name: 'supersedes',
                  level: DiagnosticsLevel.info,
                  referenceKind: ReferenceKind.bead,
                  value: 'old',
                ),
              ],
            ],
          ),
      ],
    ),
    snapshot(
      version: 2,
      properties: [
        intProperty('inputTokens', 10),
        const DiagnosticsProperty.double(
          name: 'costUsd',
          level: DiagnosticsLevel.info,
          value: 0.25,
        ),
      ],
      children: [
        node(
          id: 'cost-child',
          seedType: 'Usage',
          properties: [
            intProperty('inputTokens', 2),
            intProperty('outputTokens', 3),
            intProperty('costUsd', 1),
          ],
        ),
      ],
    ),
  ]);

  test('projects every property variant and nested objects', () {
    final inspector = inspectorOf(recording.latest, 'root');
    expect(inspector.properties, hasLength(9));
    expect(
      inspector.properties.map((row) => row.severity),
      containsAll(SeverityToken.values),
    );
    final object = inspector.properties.last.value as ObjectPropertyValue;
    expect(object.properties.single.name, 'nested');
    expect(
      (inspector.properties[7].value as ReferencePropertyValue).kind,
      ReferenceKind.bead,
    );
    expect(
      () => inspectorOf(recording.latest, 'missing'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Diagnostics node not found: missing',
        ),
      ),
    );
  });

  test('projects overview, work, and ordered pipeline states', () {
    final overview = overviewOf(recording.latest);
    expect(overview.substations.single.substationId, 'alpha');
    expect(overview.substations.single.mountedWorkCount, 1);
    expect(overview.activeWorkCount, 1);
    expect(overview.warningCount, 1);
    expect(overview.errorCount, 1);

    final work = workListOf(recording.latest).items.single;
    expect(work.beadId, 'tg-1');
    expect(work.sessionId, 'session-1');
    expect(work.state, StepVisualState.running);

    final pipeline = pipelineOf(recording.latest);
    expect(pipeline.roots.map((item) => item.state), [
      StepVisualState.running,
      StepVisualState.pending,
      StepVisualState.ready,
      StepVisualState.complete,
      StepVisualState.failed,
      StepVisualState.gated,
      StepVisualState.unknown,
    ]);
    expect(pipeline.roots[1].label, '/pipeline/pending');
    expect(pipeline.roots[1].incarnationDepth, 1);
    expect(pipeline.roots[1].duration, const Duration(milliseconds: 4));
  });

  test('rolls up optional costs recursively', () {
    expect(
      costRollupOf(recording.latest),
      const CostRollupState(hasData: false),
    );
    recording.advance();
    expect(
      costRollupOf(recording.latest),
      const CostRollupState(
        inputTokens: 12,
        outputTokens: 3,
        costUsd: 1.25,
        hasData: true,
      ),
    );
  });

  test('rolls up repeated step grades', () {
    final result = costRollupOf(
      snapshot(
        version: 3,
        children: [
          node(
            id: 'step',
            seedType: 'CircuitStep',
            properties: [
              intProperty('inputTokens', 10),
              intProperty('outputTokens', 4),
              stringProperty('grade', 'A'),
              stringProperty('grade', 'B'),
            ],
          ),
        ],
      ),
    );
    expect(
      result,
      const CostRollupState(
        inputTokens: 10,
        outputTokens: 4,
        grades: ['A', 'B'],
        hasData: true,
      ),
    );
  });
}
