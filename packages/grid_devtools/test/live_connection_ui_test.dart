import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';

import 'fake_grid_exploration_client.dart';

StationLockDiscovery _unavailableDiscovery() => StationLockDiscovery(
  isCapable: () async => false,
  workspaceRoots: () async => throw UnimplementedError(),
  readFile: (_) async => throw UnimplementedError(),
);

void main() {
  testWidgets(
    'unavailable discovery is actionable and manual connection still works',
    (tester) async {
      final client = FakeGridExplorationClient();
      final source = bundledReplayTreeSource();
      Uri? observedUrl;
      String? observedToken;
      final controller = LiveConnectionController(
        discovery: _unavailableDiscovery(),
        connectSource: ({required controlUrl, required token}) {
          observedUrl = controlUrl;
          observedToken = token;
          return source;
        },
      );
      addTearDown(client.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: GridDevToolsShell(client: client, liveConnection: controller),
        ),
      );
      await tester.pumpAndSettle();
      await controller.autoConnect();
      await tester.pumpAndSettle();

      const notice =
          'Auto-connect is unavailable in this session. '
          'Enter the station URL and token.';
      final status = find.byKey(const Key('live.status'));
      expect(tester.widget<Text>(status).data, notice);
      expect(find.text('No IDE workspace roots are available'), findsNothing);
      expect(find.text('No workspace roots are available'), findsNothing);
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('live.url')))
            .controller
            ?.text,
        'localhost:<port>',
      );

      final token = tester.widget<TextField>(
        find.byKey(const Key('live.token')),
      );
      expect(token.obscureText, isTrue);
      await tester.enterText(
        find.byKey(const Key('live.url')),
        'http://localhost:42',
      );
      await tester.enterText(find.byKey(const Key('live.token')), 'secret');
      await tester.tap(find.byKey(const Key('live.connect')));
      await tester.pumpAndSettle();

      expect(observedUrl, Uri.parse('http://localhost:42'));
      expect(observedToken, 'secret');
      expect(controller.value, isA<LiveConnected>());
      expect(find.byKey(const Key('live.disconnect')), findsOneWidget);
    },
  );

  testWidgets('failed manual connection preserves Replay tabs', (tester) async {
    final client = FakeGridExplorationClient();
    final controller = LiveConnectionController(
      discovery: _unavailableDiscovery(),
    );
    addTearDown(client.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GridDevToolsShell(client: client, liveConnection: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('live.connect')));
    await tester.pumpAndSettle();

    expect(controller.value, isA<LiveFailed>());
    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Inspector'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
  });
}
