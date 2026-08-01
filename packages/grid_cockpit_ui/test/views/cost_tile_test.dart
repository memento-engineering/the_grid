import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

import '../fixtures.dart';

void main() {
  testWidgets('cost tile updates and degrades absent fields independently', (
    tester,
  ) async {
    final source = ReplayTreeSource([
      snapshot(version: 1),
      snapshot(
        version: 2,
        properties: [
          intProperty('inputTokens', 12),
          const DiagnosticsProperty.double(
            name: 'costUsd',
            level: DiagnosticsLevel.info,
            value: 0.125,
          ),
          stringProperty('grade', 'A'),
          stringProperty('grade', 'F'),
        ],
      ),
      snapshot(version: 3),
    ]);
    final viewModel = CostRollupViewModel(source);

    await tester.pumpWidget(MaterialApp(home: CostTile(viewModel: viewModel)));
    expect(find.text('Cost unavailable'), findsOneWidget);
    expect(find.textContaining('—'), findsNWidgets(4));

    source.advance();
    await tester.pump();
    expect(find.text('Input tokens: 12'), findsOneWidget);
    expect(find.text('Output tokens: —'), findsOneWidget);
    expect(find.text('USD: 0.1250'), findsOneWidget);
    expect(find.text('Grade A'), findsOneWidget);
    expect(find.text('Grade F'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    source.advance();
    await tester.pump();
    expect(tester.takeException(), isNull);
    viewModel.dispose();
    await source.dispose();
  });
}
