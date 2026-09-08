import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit/grid_cockpit.dart';
import 'package:grid_station_client/grid_station_client.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

import 'fakes.dart';

StationLockDiscovery _missingLock() => StationLockDiscovery(
  isCapable: () async => true,
  workspaceRoots: () async => const <Uri>[],
  readFile: (_) async => throw StateError('unexpected lock read'),
);

CockpitConnectionController _controller(List<(Uri, String)> attempts) =>
    CockpitConnectionController(
      discovery: _missingLock(),
      connectSource: ({required controlUrl, required token}) {
        attempts.add((controlUrl, token));
        throw StateError('unexpected connection');
      },
    );

Future<void> _pumpCockpit(
  WidgetTester tester, {
  required CockpitConnectionController controller,
  required FakeMdnsBrowser browser,
}) async {
  await tester.pumpWidget(
    GridCockpitApp(
      controller: controller,
      stationDiscovery: MdnsStationDiscovery(browser: browser),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'picker lists fake browsed stations and fills the selected control door',
    (tester) async {
      final attempts = <(Uri, String)>[];
      final browser = FakeMdnsBrowser(
        ads: Stream<StationAd>.value(
          const StationAd(
            station: 'alpha',
            host: 'federation.alpha.test',
            port: 7100,
            controlDoor: 'alpha.test:4242',
          ),
        ),
      );
      await _pumpCockpit(
        tester,
        controller: _controller(attempts),
        browser: browser,
      );

      await tester.tap(find.byKey(const Key('cockpit.stationPicker')));
      await tester.pumpAndSettle();
      expect(find.text('alpha — alpha.test:4242'), findsWidgets);
      await tester.tap(find.text('alpha — alpha.test:4242').last);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('cockpit.host')))
            .controller
            ?.text,
        'alpha.test:4242',
      );
      expect(browser.browseCalls, 1);
      expect(attempts, isEmpty);
    },
  );

  testWidgets('picker leaves a station without a control door disabled', (
    tester,
  ) async {
    final attempts = <(Uri, String)>[];
    final browser = FakeMdnsBrowser(
      ads: Stream<StationAd>.value(
        const StationAd(
          station: 'alpha',
          host: 'federation.alpha.test',
          port: 7100,
        ),
      ),
    );
    await _pumpCockpit(
      tester,
      controller: _controller(attempts),
      browser: browser,
    );
    await tester.enterText(
      find.byKey(const Key('cockpit.host')),
      'manual.test:9000',
    );

    final dropdown = tester.widget<DropdownButton<StationChoice>>(
      find.byWidgetPredicate(
        (widget) => widget is DropdownButton<StationChoice>,
      ),
    );
    expect(dropdown.items, hasLength(1));
    expect(dropdown.items!.single.enabled, isFalse);
    await tester.tap(find.byKey(const Key('cockpit.stationPicker')));
    await tester.pumpAndSettle();
    expect(find.text('alpha — control door unavailable'), findsOneWidget);
    await tester.tap(find.text('alpha — control door unavailable'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cockpit.host')))
          .controller
          ?.text,
      'manual.test:9000',
    );
    expect(attempts, isEmpty);
  });

  testWidgets('picker preserves an operator bearer', (tester) async {
    final attempts = <(Uri, String)>[];
    final browser = FakeMdnsBrowser(
      ads: Stream<StationAd>.value(
        const StationAd(
          station: 'alpha',
          host: 'federation.alpha.test',
          port: 7100,
          controlDoor: 'alpha.test:4242',
          trustHint: 'advertised-hint',
        ),
      ),
    );
    await _pumpCockpit(
      tester,
      controller: _controller(attempts),
      browser: browser,
    );
    await tester.enterText(
      find.byKey(const Key('cockpit.token')),
      'operator-bearer',
    );

    await tester.tap(find.byKey(const Key('cockpit.stationPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha — alpha.test:4242').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('cockpit.token')))
          .controller
          ?.text,
      'operator-bearer',
    );
    expect(attempts, isEmpty);
  });

  testWidgets('picker reports browsing, empty, and failed browse states', (
    tester,
  ) async {
    final pendingAds = StreamController<StationAd>();
    final attempts = <(Uri, String)>[];
    final browser = FakeMdnsBrowser(ads: pendingAds.stream);
    await tester.pumpWidget(
      GridCockpitApp(
        controller: _controller(attempts),
        stationDiscovery: MdnsStationDiscovery(browser: browser),
      ),
    );
    await tester.pump();
    expect(find.text('Browsing for stations…'), findsOneWidget);

    await pendingAds.close();
    await tester.pumpAndSettle();
    expect(find.text('No stations found'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('cockpit.host'))).enabled,
      isTrue,
    );

    final failedBrowser = FakeMdnsBrowser(
      ads: Stream<StationAd>.error(StateError('browse exploded')),
    );
    await tester.pumpWidget(
      GridCockpitApp(
        key: const ValueKey('failed-app'),
        controller: _controller(attempts),
        stationDiscovery: MdnsStationDiscovery(browser: failedBrowser),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Station browse failed: Bad state: browse exploded'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('cockpit.token'))).enabled,
      isTrue,
    );
    expect(attempts, isEmpty);
  });
}
