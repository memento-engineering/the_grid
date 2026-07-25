import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

const _info = DiagnosticsLevel.info;

/// Creates the bundled two-frame proving recording.
ReplayTreeSource bundledReplayTreeSource() => ReplayTreeSource([
  _snapshot(buildState: 'running'),
  _snapshot(buildState: 'complete'),
]);

TreeSnapshot _snapshot({required String buildState}) => TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 7, buildState == 'running' ? 24 : 25),
  root: TreeNode(
    seedType: 'Grid',
    id: 'root',
    properties: const [],
    children: [
      TreeNode(
        seedType: 'Substation',
        id: 'substation-alpha',
        properties: const [
          DiagnosticsProperty.reference(
            name: 'substationId',
            level: _info,
            referenceKind: ReferenceKind.substation,
            value: 'alpha',
          ),
        ],
        children: [
          TreeNode(
            seedType: 'WorkBead',
            id: 'work-tg-demo',
            properties: const [
              DiagnosticsProperty.reference(
                name: 'beadId',
                level: _info,
                referenceKind: ReferenceKind.bead,
                value: 'tg-demo',
              ),
              DiagnosticsProperty.reference(
                name: 'sessionId',
                level: _info,
                referenceKind: ReferenceKind.session,
                value: 'session-demo',
              ),
              DiagnosticsProperty.enumValue(
                name: 'stepState',
                level: _info,
                value: 'running',
                enumType: 'StepState',
              ),
            ],
            children: [
              const TreeNode(
                seedType: 'CircuitStep',
                id: 'specify',
                properties: [
                  DiagnosticsProperty.enumValue(
                    name: 'stepState',
                    level: _info,
                    value: 'complete',
                    enumType: 'StepState',
                  ),
                  DiagnosticsProperty.string(
                    name: 'nodePath',
                    level: _info,
                    value: 'specify',
                  ),
                  DiagnosticsProperty.duration(
                    name: 'duration',
                    level: _info,
                    value: Duration(seconds: 3),
                  ),
                  DiagnosticsProperty.int(
                    name: 'inputTokens',
                    level: _info,
                    value: 120,
                  ),
                  DiagnosticsProperty.int(
                    name: 'outputTokens',
                    level: _info,
                    value: 80,
                  ),
                  DiagnosticsProperty.double(
                    name: 'costUsd',
                    level: _info,
                    value: 0.012,
                  ),
                  DiagnosticsProperty.string(
                    name: 'grade',
                    level: _info,
                    value: 'A',
                  ),
                ],
                children: [],
              ),
              TreeNode(
                seedType: 'CircuitStep',
                id: 'build',
                properties: [
                  DiagnosticsProperty.enumValue(
                    name: 'stepState',
                    level: _info,
                    value: buildState,
                    enumType: 'StepState',
                  ),
                  const DiagnosticsProperty.string(
                    name: 'nodePath',
                    level: _info,
                    value: 'build',
                  ),
                  const DiagnosticsProperty.duration(
                    name: 'duration',
                    level: _info,
                    value: Duration(seconds: 8),
                  ),
                  const DiagnosticsProperty.int(
                    name: 'inputTokens',
                    level: _info,
                    value: 250,
                  ),
                  const DiagnosticsProperty.int(
                    name: 'outputTokens',
                    level: _info,
                    value: 140,
                  ),
                  const DiagnosticsProperty.double(
                    name: 'costUsd',
                    level: _info,
                    value: 0.024,
                  ),
                  const DiagnosticsProperty.string(
                    name: 'grade',
                    level: _info,
                    value: 'B',
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
