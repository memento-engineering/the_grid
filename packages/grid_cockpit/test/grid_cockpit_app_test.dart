import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit/grid_cockpit.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_station_client/grid_station_client.dart';

import 'fakes.dart';
import 'fixtures.dart';

StationLockDiscovery _discovery({bool capable = true, bool available = true}) =>
    StationLockDiscovery(
      isCapable: () async => capable,
      workspaceRoots: () async =>
          available ? <Uri>[Uri.parse('file:///workspace/')] : const <Uri>[],
      readFile: (_) async => jsonEncode({
        'pid': 1,
        'pgid': 1,
        'startedAt': '2026-09-07T00:00:00.000Z',
        'controlUrl': 'http://localhost:4242',
        'token': 'secret',
      }),
    );

void main() {
  testWidgets('discovery unavailable status is readable and explicit', (
    tester,
  ) async {
    final controller = CockpitConnectionController(
      discovery: _discovery(capable: false),
    );

    await tester.pumpWidget(
      GridCockpitApp(
        controller: controller,
        stationDiscovery: MdnsStationDiscovery(browser: FakeMdnsBrowser()),
      ),
    );
    await tester.pumpAndSettle();

    const notice =
        'Auto-connect is unavailable in this session. '
        'Enter the station URL and token.';
    final status = find.byKey(const Key('cockpit.status'));
    expect(tester.widget<Text>(status).data, notice);
    expect(controller.value, isA<CockpitDiscoveryUnavailable>());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('connected fake wire renders all four landed cockpit views', (
    tester,
  ) async {
    final wire = FakeTreeWireSource(latest: fixtureTreeSnapshot);
    final controller = CockpitConnectionController(
      discovery: _discovery(),
      connectSource: ({required controlUrl, required token}) =>
          LiveTreeSource(wire),
    );

    await tester.pumpWidget(
      GridCockpitApp(
        controller: controller,
        stationDiscovery: MdnsStationDiscovery(browser: FakeMdnsBrowser()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StationOverviewView), findsOneWidget);
    expect(find.byType(WorkListView), findsOneWidget);
    expect(find.byType(CircuitPipelineView), findsOneWidget);
    expect(find.byType(CostTile), findsOneWidget);
    for (final value in <String>[
      'alpha',
      'tg-fixture',
      'session-fixture',
      'build.release',
      'Input tokens: 120',
      'Output tokens: 45',
      'USD: 1.2500',
      'Grade A',
    ]) {
      expect(find.text(value), findsWidgets);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(wire.disposeCalls, 1);
  });

  testWidgets(
    'manual host and token connect; failure preserves enabled controls for retry',
    (tester) async {
      final wire = FakeTreeWireSource(latest: fixtureTreeSnapshot);
      final attempts = <(Uri, String)>[];
      final controller = CockpitConnectionController(
        discovery: _discovery(available: false),
        connectSource: ({required controlUrl, required token}) {
          attempts.add((controlUrl, token));
          if (attempts.length == 1) throw StateError('socket refused');
          return LiveTreeSource(wire);
        },
      );

      await tester.pumpWidget(
        GridCockpitApp(
          controller: controller,
          stationDiscovery: MdnsStationDiscovery(browser: FakeMdnsBrowser()),
        ),
      );
      await tester.pumpAndSettle();

      final tokenField = tester.widget<TextField>(
        find.byKey(const Key('cockpit.token')),
      );
      expect(tokenField.obscureText, isTrue);
      await tester.enterText(
        find.byKey(const Key('cockpit.host')),
        'station.test:4242',
      );
      await tester.enterText(find.byKey(const Key('cockpit.token')), 'secret');
      await tester.tap(find.byKey(const Key('cockpit.connect')));
      await tester.pumpAndSettle();

      expect(controller.value, isA<CockpitFailed>());
      expect(
        tester.widget<TextField>(find.byKey(const Key('cockpit.host'))).enabled,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cockpit.token')))
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cockpit.host')))
            .controller
            ?.text,
        'station.test:4242',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cockpit.token')))
            .controller
            ?.text,
        'secret',
      );

      await tester.tap(find.byKey(const Key('cockpit.connect')));
      await tester.pumpAndSettle();

      expect(attempts, [
        (Uri.parse('http://station.test:4242'), 'secret'),
        (Uri.parse('http://station.test:4242'), 'secret'),
      ]);
      expect(controller.value, isA<CockpitConnected>());
      expect(find.byKey(const Key('cockpit.disconnect')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
