import 'package:genesis_foundation/genesis_foundation.dart';

/// Bundled snapshots for the fixture-only example.
final cockpitRecording = [
  _snapshot(day: 1, state: 'running', output: 420, cost: 0.018, grade: 'B'),
  _snapshot(day: 2, state: 'complete', output: 760, cost: 0.027, grade: 'A'),
];

TreeSnapshot _snapshot({
  required int day,
  required String state,
  required int output,
  required double cost,
  required String grade,
}) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 7, day),
  root: TreeNode(
    seedType: 'Grid',
    id: 'root',
    properties: [
      const DiagnosticsProperty.int(
        name: 'inputTokens',
        level: DiagnosticsLevel.info,
        value: 1200,
      ),
      DiagnosticsProperty.int(
        name: 'outputTokens',
        level: DiagnosticsLevel.info,
        value: output,
      ),
      DiagnosticsProperty.double(
        name: 'costUsd',
        level: DiagnosticsLevel.info,
        value: cost,
      ),
      DiagnosticsProperty.string(
        name: 'grade',
        level: DiagnosticsLevel.info,
        value: grade,
      ),
    ],
    children: [
      TreeNode(
        seedType: 'Substation',
        id: 'station-alpha',
        key: 'alpha',
        properties: const [
          DiagnosticsProperty.string(
            name: 'substationId',
            level: DiagnosticsLevel.info,
            value: 'alpha',
          ),
        ],
        children: [
          TreeNode(
            seedType: 'WorkBead',
            id: 'work-demo',
            key: 'tg-demo',
            properties: [
              const DiagnosticsProperty.string(
                name: 'beadId',
                level: DiagnosticsLevel.info,
                value: 'tg-demo',
              ),
              const DiagnosticsProperty.string(
                name: 'sessionId',
                level: DiagnosticsLevel.info,
                value: 'session-demo',
              ),
              DiagnosticsProperty.string(
                name: 'stepState',
                level: DiagnosticsLevel.info,
                value: state,
              ),
            ],
            children: [
              TreeNode(
                seedType: 'CircuitStep',
                id: 'pipeline-build',
                key: 'build',
                properties: [
                  const DiagnosticsProperty.string(
                    name: 'nodePath',
                    level: DiagnosticsLevel.info,
                    value: '/specify/build',
                  ),
                  DiagnosticsProperty.string(
                    name: 'stepState',
                    level: state == 'complete'
                        ? DiagnosticsLevel.info
                        : DiagnosticsLevel.warning,
                    value: state,
                  ),
                  const DiagnosticsProperty.duration(
                    name: 'duration',
                    level: DiagnosticsLevel.info,
                    value: Duration(milliseconds: 840),
                  ),
                  const DiagnosticsProperty.reference(
                    name: 'bead',
                    level: DiagnosticsLevel.info,
                    referenceKind: ReferenceKind.bead,
                    value: 'tg-demo',
                  ),
                ],
                children: const [],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);
