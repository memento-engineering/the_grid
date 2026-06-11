import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';

import 'fake_grid_exploration_client.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('EventsPanel (fake client)', () {
    testWidgets('renders the empty state when no events are present', (
      tester,
    ) async {
      final client = FakeGridExplorationClient();
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(EventsPanel(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('events.empty')), findsOneWidget);
      expect(find.byKey(const Key('events.list')), findsNothing);
      // The panel seeds via the events tool on attach.
      expect(client.fetchEventsLimits, isNotEmpty);
    });

    testWidgets('seeds the backlog from the events tool', (tester) async {
      final client = FakeGridExplorationClient(
        seedEvents: const [
          GridEventRecord(type: 'beadCreated', id: 'grid-aaa'),
          GridEventRecord(type: 'readySetChanged'),
        ],
      );
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(EventsPanel(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('events.list')), findsOneWidget);
      expect(find.text('beadCreated'), findsOneWidget);
      expect(find.text('readySetChanged'), findsOneWidget);
      // beadCreated carries an id; readySetChanged does not.
      expect(find.text('grid-aaa'), findsOneWidget);
    });

    testWidgets('appends live postEvent records newest-first', (tester) async {
      final client = FakeGridExplorationClient();
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(EventsPanel(client: client)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('events.empty')), findsOneWidget);

      client.emit(const GridEventRecord(type: 'beadCreated', id: 'grid-001'));
      await tester.pumpAndSettle();
      client.emit(const GridEventRecord(type: 'beadClosed', id: 'grid-001'));
      await tester.pumpAndSettle();

      expect(find.text('beadCreated'), findsOneWidget);
      expect(find.text('beadClosed'), findsOneWidget);

      // Newest is rendered first: the top row (#2) is beadClosed.
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      final firstTitle = (tiles.first.title! as Text).data;
      expect(firstTitle, 'beadClosed');
    });
  });

  group('GridDevToolsShell handshake header', () {
    testWidgets('renders advertised plugins + tools on handshake success', (
      tester,
    ) async {
      final client = FakeGridExplorationClient();
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(GridDevToolsShell(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handshake.loaded')), findsOneWidget);
      expect(
        find.byKey(const Key('handshake.protocolVersion')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('handshake.plugin.grid')), findsOneWidget);
      expect(
        find.byKey(const Key('handshake.tool.grid.events')),
        findsOneWidget,
      );
      expect(client.handshakeCalls, 1);
    });

    testWidgets('shows the binding-missing banner when the host is absent', (
      tester,
    ) async {
      final client = FakeGridExplorationClient(
        handshakeError: const GridBindingMissing(),
      );
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(GridDevToolsShell(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handshake.bindingMissing')), findsOneWidget);
      expect(find.byKey(const Key('handshake.loaded')), findsNothing);
    });

    testWidgets('surfaces an arbitrary handshake failure', (tester) async {
      final client = FakeGridExplorationClient(
        handshakeError: StateError('boom'),
      );
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(GridDevToolsShell(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handshake.failed')), findsOneWidget);
    });
  });
}
