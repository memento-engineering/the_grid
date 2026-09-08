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
      final source = GridEventsSource(client);
      addTearDown(() async {
        await source.close();
        await client.dispose();
      });
      await source.start();

      await tester.pumpWidget(_host(EventsPanel(source: source)));
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
      final source = GridEventsSource(client);
      addTearDown(() async {
        await source.close();
        await client.dispose();
      });
      await source.start();

      await tester.pumpWidget(_host(EventsPanel(source: source)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('events.list')), findsOneWidget);
      expect(find.text('beadCreated'), findsOneWidget);
      expect(find.text('readySetChanged'), findsOneWidget);
      // beadCreated carries an id; readySetChanged does not.
      expect(find.text('grid-aaa'), findsOneWidget);
    });

    testWidgets('appends live postEvent records newest-first', (tester) async {
      final client = FakeGridExplorationClient();
      final source = GridEventsSource(client);
      addTearDown(() async {
        await source.close();
        await client.dispose();
      });
      await source.start();

      await tester.pumpWidget(_host(EventsPanel(source: source)));
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
    testWidgets('captures a live event before the Events tab is visited', (
      tester,
    ) async {
      final client = FakeGridExplorationClient();
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(GridDevToolsShell(client: client)));

      expect(client.fetchEventsLimits, <int?>[64]);
      await tester.pump();
      expect(client.hasEventListener, isTrue);

      client.emit(
        const GridEventRecord(type: 'beadCreated', id: 'before-visit'),
      );
      await tester.pump();

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      final eventsList = find.byKey(const Key('events.list'));
      expect(eventsList, findsOneWidget);
      expect(
        find.descendant(of: eventsList, matching: find.text('beadCreated')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: eventsList, matching: find.text('before-visit')),
        findsOneWidget,
      );
    });

    testWidgets('replaces event capture once when the shell client changes', (
      tester,
    ) async {
      final firstClient = FakeGridExplorationClient();
      final secondClient = FakeGridExplorationClient();
      addTearDown(() async {
        await firstClient.dispose();
        await secondClient.dispose();
      });

      await tester.pumpWidget(_host(GridDevToolsShell(client: firstClient)));
      expect(firstClient.fetchEventsLimits, <int?>[64]);
      await tester.pump();
      expect(firstClient.hasEventListener, isTrue);

      await tester.pumpWidget(_host(GridDevToolsShell(client: secondClient)));
      expect(firstClient.hasEventListener, isFalse);
      expect(firstClient.fetchEventsLimits, <int?>[64]);
      expect(secondClient.fetchEventsLimits, <int?>[64]);
      await tester.pump();
      expect(secondClient.hasEventListener, isTrue);

      firstClient.emit(
        const GridEventRecord(type: 'oldClientEvent', id: 'old-client'),
      );
      secondClient.emit(
        const GridEventRecord(type: 'newClientEvent', id: 'new-client'),
      );
      await tester.pump();

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      expect(find.text('newClientEvent'), findsOneWidget);
      expect(find.text('new-client'), findsOneWidget);
      expect(find.text('oldClientEvent'), findsNothing);
      expect(find.text('old-client'), findsNothing);
      expect(firstClient.fetchEventsLimits, <int?>[64]);
      expect(secondClient.fetchEventsLimits, <int?>[64]);
    });

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
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
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
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
    });

    testWidgets('surfaces an arbitrary handshake failure', (tester) async {
      final client = FakeGridExplorationClient(
        handshakeError: StateError('boom'),
      );
      addTearDown(client.dispose);

      await tester.pumpWidget(_host(GridDevToolsShell(client: client)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handshake.failed')), findsOneWidget);
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
    });
  });
}
