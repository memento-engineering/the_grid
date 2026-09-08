import 'package:genesis_foundation/genesis_foundation.dart';

final fixtureTreeSnapshot = TreeSnapshot(
  contractVersion: 1,
  projectedAt: DateTime.utc(2026, 9, 7),
  root: const TreeNode(
    seedType: 'Grid',
    id: 'root',
    properties: [
      DiagnosticsProperty.int(
        name: 'inputTokens',
        level: DiagnosticsLevel.info,
        value: 120,
      ),
      DiagnosticsProperty.int(
        name: 'outputTokens',
        level: DiagnosticsLevel.info,
        value: 45,
      ),
      DiagnosticsProperty.double(
        name: 'costUsd',
        level: DiagnosticsLevel.info,
        value: 1.25,
      ),
      DiagnosticsProperty.string(
        name: 'grade',
        level: DiagnosticsLevel.info,
        value: 'A',
      ),
    ],
    children: [
      TreeNode(
        seedType: 'Substation',
        id: 'substation-alpha',
        key: 'alpha',
        properties: [
          DiagnosticsProperty.string(
            name: 'substationId',
            level: DiagnosticsLevel.info,
            value: 'alpha',
          ),
        ],
        children: [
          TreeNode(
            seedType: 'WorkBead',
            id: 'work-fixture',
            key: 'tg-fixture',
            properties: [
              DiagnosticsProperty.string(
                name: 'beadId',
                level: DiagnosticsLevel.info,
                value: 'tg-fixture',
              ),
              DiagnosticsProperty.string(
                name: 'sessionId',
                level: DiagnosticsLevel.info,
                value: 'session-fixture',
              ),
              DiagnosticsProperty.string(
                name: 'stepState',
                level: DiagnosticsLevel.info,
                value: 'running',
              ),
            ],
            children: [
              TreeNode(
                seedType: 'CircuitStep',
                id: 'pipeline-build-release',
                key: 'build.release',
                properties: [
                  DiagnosticsProperty.string(
                    name: 'nodePath',
                    level: DiagnosticsLevel.info,
                    value: 'build.release',
                  ),
                  DiagnosticsProperty.string(
                    name: 'stepState',
                    level: DiagnosticsLevel.info,
                    value: 'running',
                  ),
                ],
                children: [],
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);
