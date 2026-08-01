import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

import '../fixtures.dart';

final class EmptyTreeSource implements TreeSource {
  final controller = StreamController<TreeSnapshot>.broadcast(sync: true);

  @override
  TreeSnapshot? get latest => null;

  @override
  Stream<TreeSnapshot> get snapshots => controller.stream;

  @override
  Future<void> dispose() => controller.close();
}

void main() {
  testWidgets('inspector renders empty state before the first live snapshot', (
    tester,
  ) async {
    final source = EmptyTreeSource();
    final viewModel = InspectorViewModel(source, nodeId: 'selected');

    await tester.pumpWidget(
      MaterialApp(home: DiagnosticsInspectorView(viewModel: viewModel)),
    );

    expect(find.text('No diagnostics selected'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    viewModel.dispose();
    await source.dispose();
  });

  testWidgets('pipeline renders nesting, state, duration, and selection', (
    tester,
  ) async {
    final source = ReplayTreeSource([
      snapshot(
        version: 1,
        children: [
          node(
            id: 'parent',
            seedType: 'CircuitStep',
            properties: [
              stringProperty('nodePath', '/parent'),
              stringProperty('stepState', 'running'),
              const DiagnosticsProperty.duration(
                name: 'duration',
                level: DiagnosticsLevel.info,
                value: Duration(microseconds: 12),
              ),
              const DiagnosticsProperty.reference(
                name: 'supersedes',
                level: DiagnosticsLevel.info,
                referenceKind: ReferenceKind.bead,
                value: 'old',
              ),
            ],
            children: [
              node(
                id: 'child',
                seedType: 'CircuitStep',
                properties: [
                  stringProperty('nodePath', '/child'),
                  stringProperty('stepState', 'failed'),
                  intProperty('durationMs', 4),
                ],
              ),
            ],
          ),
          for (final entry in {
            'pending': 'pending',
            'ready': 'ready',
            'complete': 'complete',
            'gated': 'gated',
            'unknown': 'future',
          }.entries)
            node(
              id: entry.key,
              seedType: 'CircuitStep',
              key: entry.key,
              properties: [stringProperty('stepState', entry.value)],
            ),
        ],
      ),
      snapshot(version: 2),
      snapshot(version: 3),
    ]);
    final viewModel = PipelineViewModel(source);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CircuitPipelineView(
              viewModel: viewModel,
              onSelectNode: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('/parent'), findsOneWidget);
    expect(find.text('/child'), findsOneWidget);
    expect(find.text('incarnation 1 · 12 µs'), findsOneWidget);
    expect(find.text('incarnation 0 · 4000 µs'), findsOneWidget);
    for (final state in StepVisualState.values) {
      expect(find.text(state.name), findsAtLeastNWidgets(1));
    }
    final childTile = find.byKey(const ValueKey('child'));
    final childPadding = tester.widget<Padding>(
      find.ancestor(of: childTile, matching: find.byType(Padding)).first,
    );
    expect(childPadding.padding, const EdgeInsets.only(left: 16));
    await tester.tap(childTile);
    expect(selected, 'child');

    source.advance();
    await tester.pump();
    expect(find.text('No circuit steps'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    source.advance();
    await tester.pump();
    expect(tester.takeException(), isNull);
    viewModel.dispose();
    await source.dispose();
  });

  testWidgets('inspector renders typed properties and forwards references', (
    tester,
  ) async {
    final source = ReplayTreeSource([
      snapshot(
        version: 1,
        children: [
          node(
            id: 'selected',
            seedType: 'CircuitStep',
            key: 'step-key',
            properties: [
              stringProperty('string', 'text'),
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
                value: DateTime.utc(2026),
              ),
              for (final target in const [
                (ReferenceKind.bead, 'bead-1'),
                (ReferenceKind.session, 'session-1'),
                (ReferenceKind.pid, '42'),
              ])
                DiagnosticsProperty.reference(
                  name: target.$1.name,
                  level: DiagnosticsLevel.info,
                  referenceKind: target.$1,
                  value: target.$2,
                ),
              DiagnosticsProperty.object(
                name: 'object',
                level: DiagnosticsLevel.info,
                properties: [stringProperty('nested', 'yes')],
              ),
            ],
          ),
        ],
      ),
      snapshot(
        version: 2,
        children: [
          node(id: 'selected', seedType: 'Replacement', properties: []),
        ],
      ),
      snapshot(
        version: 3,
        children: [node(id: 'selected', seedType: 'Final', properties: [])],
      ),
    ]);
    final viewModel = InspectorViewModel(source, nodeId: 'selected');
    final opened = <ReferenceTarget>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiagnosticsInspectorView(
              viewModel: viewModel,
              onOpenReference: opened.add,
            ),
          ),
        ),
      ),
    );
    expect(find.text('CircuitStep'), findsOneWidget);
    expect(find.text('step-key · selected'), findsOneWidget);
    final severities = tester
        .widgetList<PropertyRow>(find.byType(PropertyRow))
        .map((row) => row.property.severity);
    expect(severities, contains(SeverityToken.warning));
    expect(severities, contains(SeverityToken.error));
    for (final value in ['bead-1', 'session-1', '42']) {
      await tester.tap(find.text(value));
    }
    expect(opened.map((target) => target.kind), [
      ReferenceKind.bead,
      ReferenceKind.session,
      ReferenceKind.pid,
    ]);
    expect(opened.map((target) => target.value), ['bead-1', 'session-1', '42']);

    source.advance();
    await tester.pump();
    expect(find.text('Replacement'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    source.advance();
    await tester.pump();
    expect(tester.takeException(), isNull);
    viewModel.dispose();
    await source.dispose();
  });
}
