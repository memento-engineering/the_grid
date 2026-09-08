import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit/grid_cockpit.dart';
import 'package:zero_conf_grid_assets/zero_conf_grid_assets.dart';

import 'fakes.dart';

void main() {
  test(
    'adapter maps StationAd.controlDoor through the injected MdnsBrowser',
    () async {
      const timeout = Duration(milliseconds: 750);
      final browser = FakeMdnsBrowser(
        ads: Stream<StationAd>.fromIterable(const [
          StationAd(
            station: 'alpha',
            host: 'federation.alpha.test',
            port: 7100,
            controlDoor: '  alpha.test:4242  ',
            trustHint: 'not-a-bearer',
          ),
          StationAd(
            station: 'beta',
            host: 'federation.beta.test',
            port: 7200,
            controlDoor: '   ',
          ),
          StationAd(
            station: 'gamma',
            host: 'federation.gamma.test',
            port: 7300,
          ),
        ]),
      );
      final discovery = MdnsStationDiscovery(browser: browser);

      final snapshots = await discovery.browse(timeout: timeout).toList();

      expect(browser.browseCalls, 1);
      expect(browser.lastTimeout, timeout);
      expect(snapshots, [
        const [StationChoice(station: 'alpha', controlDoor: 'alpha.test:4242')],
        const [
          StationChoice(station: 'alpha', controlDoor: 'alpha.test:4242'),
          StationChoice(station: 'beta', controlDoor: null),
        ],
        const [
          StationChoice(station: 'alpha', controlDoor: 'alpha.test:4242'),
          StationChoice(station: 'beta', controlDoor: null),
          StationChoice(station: 'gamma', controlDoor: null),
        ],
      ]);
      expect(snapshots.first, isNot(same(snapshots[1])));
      expect(
        () => snapshots.first.add(snapshots.last.last),
        throwsUnsupportedError,
      );
      expect(snapshots.first.single.isConnectable, isTrue);
      expect(snapshots[1].last.isConnectable, isFalse);
    },
  );
}
