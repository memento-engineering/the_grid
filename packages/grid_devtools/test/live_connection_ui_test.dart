import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/grid_devtools.dart';

import 'fake_grid_exploration_client.dart';

StationLockDiscovery _unavailableDiscovery() => StationLockDiscovery(
  workspaceRoots: () async => const [],
  readFile: (_) async => throw UnimplementedError(),
);

void main() {
  testWidgets('manual connection is obscured and injects the live source', (
    tester,
  ) async {
    final client = FakeGridExplorationClient();
    final source = bundledReplayTreeSource();
    final controller = LiveConnectionController(
      discovery: _unavailableDiscovery(),
      connectSource: ({required controlUrl, required token}) => source,
    );
    addTearDown(client.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GridDevToolsShell(client: client, liveConnection: controller),
      ),
    );
    await tester.pumpAndSettle();

    final token = tester.widget<TextField>(find.byKey(const Key('live.token')));
    expect(token.obscureText, isTrue);
    await tester.enterText(
      find.byKey(const Key('live.url')),
      'http://localhost:42',
    );
    await tester.enterText(find.byKey(const Key('live.token')), 'secret');
    await tester.tap(find.byKey(const Key('live.connect')));
    await tester.pumpAndSettle();

    expect(controller.value, isA<LiveConnected>());
    expect(find.byKey(const Key('live.disconnect')), findsOneWidget);
  });

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
