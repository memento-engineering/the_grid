import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:grid_cockpit/grid_cockpit.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_station_client/grid_station_client.dart';

final class _TreeSource implements TreeSource {
  final _snapshots = StreamController<TreeSnapshot>.broadcast();
  int disposeCalls = 0;

  @override
  TreeSnapshot? get latest => null;

  @override
  Stream<TreeSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    if (!_snapshots.isClosed) await _snapshots.close();
  }
}

String _lock({String? controlUrl, String? token}) => jsonEncode({
  'pid': 1,
  'pgid': 1,
  'startedAt': '2026-09-07T00:00:00.000Z',
  if (controlUrl != null) 'controlUrl': controlUrl,
  if (token != null) 'token': token,
});

void main() {
  test('cockpit vocabulary aliases the shared connection machine', () {
    const CockpitConnectionState state = CockpitConnectionState.disconnected();

    expect(state, isA<CockpitDisconnected>());
  });

  test(
    'shared discovery decodes an AOT lock and failures settle manual',
    () async {
      final reads = <Uri>[];
      Uri? observedControlUrl;
      String? observedToken;
      final source = _TreeSource();
      final discovery = StationLockDiscovery(
        workspaceRoots: () async => [Uri.parse('file:///workspace/')],
        readFile: (uri) async {
          reads.add(uri);
          return _lock(
            controlUrl: ' http://localhost:4242 ',
            token: ' boot-bearer ',
          );
        },
      );
      final controller = CockpitConnectionController(
        discovery: discovery,
        connectSource: ({required controlUrl, required token}) {
          observedControlUrl = controlUrl;
          observedToken = token;
          return source;
        },
      );

      await controller.autoConnect();

      expect(reads, [Uri.parse('file:///workspace/.grid/station.lock')]);
      expect(observedControlUrl, Uri.parse('http://localhost:4242'));
      expect(observedToken, 'boot-bearer');
      expect(controller.value, isA<CockpitConnected>());
      controller.dispose();

      final failures = <StationLockDiscovery>[
        StationLockDiscovery(
          workspaceRoots: () async => const [],
          readFile: (_) async => throw UnimplementedError(),
        ),
        StationLockDiscovery(
          workspaceRoots: () async => [Uri.parse('file:///workspace/')],
          readFile: (_) async => '{malformed',
        ),
        StationLockDiscovery(
          workspaceRoots: () async => [Uri.parse('file:///workspace/')],
          readFile: (_) async => _lock(controlUrl: ' ', token: ' '),
        ),
      ];
      for (final failedDiscovery in failures) {
        final failedController = CockpitConnectionController(
          discovery: failedDiscovery,
        );
        await failedController.autoConnect();
        expect(failedController.value, isA<CockpitManual>());
        failedController.dispose();
      }
    },
  );

  test(
    'manual normalization retries and owns each adopted source once',
    () async {
      final sources = <_TreeSource>[];
      final observed = <(Uri, String)>[];
      var fail = true;
      final controller = CockpitConnectionController(
        discovery: StationLockDiscovery(
          workspaceRoots: () async => const [],
          readFile: (_) async => throw UnimplementedError(),
        ),
        connectSource: ({required controlUrl, required token}) {
          observed.add((controlUrl, token));
          if (fail) {
            fail = false;
            throw StateError('connection failed');
          }
          final source = _TreeSource();
          sources.add(source);
          return source;
        },
      );

      await controller.connect(
        controlUrl: 'station.test:4242',
        token: ' token ',
      );
      expect(controller.value, isA<CockpitFailed>());
      await controller.connect(
        controlUrl: 'station.test:4242',
        token: ' token ',
      );
      expect(controller.value, isA<CockpitConnected>());
      await controller.connect(controlUrl: 'other.test:4243', token: 'next');
      expect(sources.first.disposeCalls, 1);
      await controller.disconnect();
      expect(sources.last.disposeCalls, 1);
      controller.dispose();

      expect(observed.first, (Uri.parse('http://station.test:4242'), 'token'));
      expect(observed.last, (Uri.parse('http://other.test:4243'), 'next'));
    },
  );

  test('invalid manual credentials never invoke the connector', () async {
    var calls = 0;
    final controller = CockpitConnectionController(
      discovery: StationLockDiscovery(
        workspaceRoots: () async => const [],
        readFile: (_) async => throw UnimplementedError(),
      ),
      connectSource: ({required controlUrl, required token}) {
        calls++;
        return _TreeSource();
      },
    );
    const invalid = <(String, String)>[
      ('station.test', 'token'),
      ('ws://station.test:4242', 'token'),
      ('http://:4242', 'token'),
      ('station.test:4242', ''),
    ];

    for (final credentials in invalid) {
      await controller.connect(
        controlUrl: credentials.$1,
        token: credentials.$2,
      );
      expect(controller.value, isA<CockpitFailed>());
    }
    expect(calls, 0);
    controller.dispose();
  });
}
