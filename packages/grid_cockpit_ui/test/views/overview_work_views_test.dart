import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

import '../fixtures.dart';

void main() {
  testWidgets(
    'overview and work views render replay updates and empty states',
    (tester) async {
      final first = snapshot(
        version: 1,
        children: [
          node(
            id: 'station',
            seedType: 'Substation',
            properties: [stringProperty('substationId', 'alpha')],
            children: [
              node(
                id: 'work',
                seedType: 'WorkBead',
                properties: [
                  stringProperty('beadId', 'bead-1'),
                  stringProperty('sessionId', 'session-1'),
                  stringProperty('stepState', 'running'),
                ],
              ),
            ],
          ),
        ],
      );
      final source = ReplayTreeSource([first, snapshot(version: 2), first]);
      final overview = OverviewViewModel(source);
      final work = WorkListViewModel(source);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  StationOverviewView(viewModel: overview),
                  WorkListView(viewModel: work),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Active 1'), findsOneWidget);
      expect(find.text('Warnings 0'), findsOneWidget);
      expect(find.text('Errors 0'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('1 mounted work'), findsOneWidget);
      expect(find.text('bead-1'), findsOneWidget);
      expect(find.text('session-1'), findsOneWidget);
      expect(find.text('running'), findsOneWidget);

      source.advance();
      await tester.pump();
      expect(find.text('No substations reporting'), findsOneWidget);
      expect(find.text('No work mounted'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      source.advance();
      await tester.pump();
      expect(tester.takeException(), isNull);
      overview.dispose();
      work.dispose();
      await source.dispose();
    },
  );
}
