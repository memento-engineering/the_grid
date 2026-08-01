import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('step badges render every state with semantics', (tester) async {
    for (final state in StepVisualState.values) {
      await tester.pumpWidget(app(StepStateBadge(state: state)));
      expect(find.text(state.name), findsOneWidget);
      expect(
        find.bySemanticsLabel('Step state: ${state.name}'),
        findsOneWidget,
      );
    }
  });

  testWidgets('severity marker uses every semantic token', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    for (final severity in SeverityToken.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: PropertyRow(
            property: PropertyRowModel(
              name: severity.name,
              severity: severity,
              value: const PropertyValue.string('value'),
            ),
          ),
        ),
      );
      final marker = tester.widget<Icon>(find.byIcon(Icons.circle));
      expect(marker.color, severityColor(scheme, severity));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Severity: ${severity.name}',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('property rows render all scalar shapes and nested objects', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final properties = [
      const PropertyRowModel(
        name: 'string',
        severity: SeverityToken.info,
        value: PropertyValue.string('text'),
      ),
      const PropertyRowModel(
        name: 'integer',
        severity: SeverityToken.info,
        value: PropertyValue.integer(42),
      ),
      const PropertyRowModel(
        name: 'decimal',
        severity: SeverityToken.info,
        value: PropertyValue.decimal(2.5),
      ),
      const PropertyRowModel(
        name: 'flag',
        severity: SeverityToken.info,
        value: PropertyValue.flag(true),
      ),
      const PropertyRowModel(
        name: 'enum',
        severity: SeverityToken.info,
        value: PropertyValue.enumeration('running', 'StepState'),
      ),
      const PropertyRowModel(
        name: 'duration',
        severity: SeverityToken.info,
        value: PropertyValue.duration(Duration(microseconds: 99)),
      ),
      PropertyRowModel(
        name: 'timestamp',
        severity: SeverityToken.info,
        value: PropertyValue.timestamp(timestamp),
      ),
      const PropertyRowModel(
        name: 'reference',
        severity: SeverityToken.info,
        value: PropertyValue.reference(ReferenceKind.bead, 'tg-1'),
      ),
      const PropertyRowModel(
        name: 'object',
        severity: SeverityToken.info,
        value: PropertyValue.object([
          PropertyRowModel(
            name: 'nested',
            severity: SeverityToken.warning,
            value: PropertyValue.string('inside'),
          ),
        ]),
      ),
    ];

    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: Column(
            children: [
              for (final property in properties)
                PropertyRow(property: property),
            ],
          ),
        ),
      ),
    );
    for (final text in [
      'text',
      '42',
      '2.5',
      'true',
      'running',
      '99 \u00b5s',
      timestamp.toIso8601String(),
      'tg-1',
      'inside',
    ]) {
      expect(find.text(text), findsOneWidget);
    }
  });

  testWidgets('reference callback emits exact target only after activation', (
    tester,
  ) async {
    ReferenceTarget? opened;
    await tester.pumpWidget(
      app(
        PropertyRow(
          property: const PropertyRowModel(
            name: 'session',
            severity: SeverityToken.info,
            value: PropertyValue.object([
              PropertyRowModel(
                name: 'link',
                severity: SeverityToken.info,
                value: PropertyValue.reference(
                  ReferenceKind.session,
                  'session-7',
                ),
              ),
            ]),
          ),
          onOpenReference: (target) => opened = target,
        ),
      ),
    );
    expect(opened, isNull);
    await tester.tap(find.text('session-7'));
    expect(opened?.kind, ReferenceKind.session);
    expect(opened?.value, 'session-7');
  });
}
