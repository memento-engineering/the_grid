import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:test/test.dart';

void main() {
  final projectedAt = DateTime.utc(2026, 7, 23, 12, 30);
  final timestamp = DateTime.utc(2026, 7, 23, 12, 29, 59);
  final properties = <DiagnosticsProperty>[
    const DiagnosticsProperty.string(
      name: 'label',
      level: DiagnosticsLevel.info,
      value: 'build',
    ),
    const DiagnosticsProperty.int(
      name: 'attempt',
      level: DiagnosticsLevel.fine,
      value: 2,
    ),
    const DiagnosticsProperty.double(
      name: 'cost',
      level: DiagnosticsLevel.info,
      value: 1.25,
    ),
    const DiagnosticsProperty.flag(
      name: 'failed',
      level: DiagnosticsLevel.warning,
      value: false,
    ),
    const DiagnosticsProperty.enumValue(
      name: 'state',
      level: DiagnosticsLevel.info,
      value: 'running',
      enumType: 'StepState',
    ),
    const DiagnosticsProperty.duration(
      name: 'elapsed',
      level: DiagnosticsLevel.fine,
      value: Duration(seconds: 3),
    ),
    DiagnosticsProperty.timestamp(
      name: 'startedAt',
      level: DiagnosticsLevel.info,
      value: timestamp,
    ),
    const DiagnosticsProperty.reference(
      name: 'work',
      level: DiagnosticsLevel.info,
      referenceKind: ReferenceKind.bead,
      value: 'work-1',
    ),
    const DiagnosticsProperty.object(
      name: 'allocation',
      level: DiagnosticsLevel.warning,
      properties: [
        DiagnosticsProperty.reference(
          name: 'process',
          level: DiagnosticsLevel.info,
          referenceKind: ReferenceKind.pid,
          value: '4242',
        ),
      ],
    ),
  ];

  test('TreeSnapshot round-trips the complete recursive tree', () {
    final snapshot = TreeSnapshot(
      contractVersion: 1,
      projectedAt: projectedAt,
      root: TreeNode(
        seedType: 'Station',
        id: 'root-1',
        properties: properties,
        children: const [
          TreeNode(
            seedType: 'CircuitStep',
            id: 'step-1',
            key: 'specify',
            properties: [],
            children: [],
          ),
        ],
      ),
    );

    final json = snapshot.toJson();
    expect(json['contractVersion'], 1);
    expect(json['projectedAt'], projectedAt.toIso8601String());
    expect(TreeSnapshot.fromJson(json), snapshot);
  });

  test('all nine property kinds round-trip with exhaustive consumption', () {
    final kinds = <String>[];
    for (final property in properties) {
      kinds.add(switch (property) {
        DiagnosticsStringProperty() => 'string',
        DiagnosticsIntProperty() => 'int',
        DiagnosticsDoubleProperty() => 'double',
        DiagnosticsFlagProperty() => 'flag',
        DiagnosticsEnumProperty() => 'enumValue',
        DiagnosticsDurationProperty() => 'duration',
        DiagnosticsTimestampProperty() => 'timestamp',
        DiagnosticsReferenceProperty() => 'reference',
        DiagnosticsObjectProperty() => 'object',
      });
      expect(DiagnosticsProperty.fromJson(property.toJson()), property);
      expect(property.toJson()['name'], property.name);
      expect(property.toJson()['level'], property.level.name);
    }

    expect(kinds, [
      'string',
      'int',
      'double',
      'flag',
      'enumValue',
      'duration',
      'timestamp',
      'reference',
      'object',
    ]);
  });

  test('object preserves typed nested references', () {
    final decoded = DiagnosticsProperty.fromJson(properties.last.toJson());

    expect(
      decoded,
      const DiagnosticsProperty.object(
        name: 'allocation',
        level: DiagnosticsLevel.warning,
        properties: [
          DiagnosticsProperty.reference(
            name: 'process',
            level: DiagnosticsLevel.info,
            referenceKind: ReferenceKind.pid,
            value: '4242',
          ),
        ],
      ),
    );
  });

  test('unknown property kind fails loudly', () {
    expect(
      () => DiagnosticsProperty.fromJson(const {
        'kind': 'treeDelta',
        'name': 'reserved',
        'level': 'info',
        'value': 'x',
      }),
      throwsA(isA<CheckedFromJsonException>()),
    );
  });
}
