import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_foundation/genesis_foundation.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_station_client/grid_station_client.dart';

final class _Source implements TreeSource {
  final controller = StreamController<TreeSnapshot>.broadcast();
  int disposeCalls = 0;

  @override
  TreeSnapshot? get latest => null;

  @override
  Stream<TreeSnapshot> get snapshots => controller.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await controller.close();
  }
}

StationLockDiscovery _discovery(String contents) => StationLockDiscovery(
  workspaceRoots: () async => [Uri.parse('file:///workspace/')],
  readFile: (_) async => contents,
);

String _lock({String? controlUrl, String? token}) => jsonEncode({
  'pid': 1,
  'pgid': 1,
  'startedAt': '2026-07-25T00:00:00.000Z',
  if (controlUrl != null) 'controlUrl': controlUrl,
  if (token != null) 'token': token,
});

void main() {
  test('auto connect trims AOT lock credentials', () async {
    Uri? observedUrl;
    String? observedToken;
    final source = _Source();
    final controller = LiveConnectionController(
      discovery: _discovery(
        _lock(controlUrl: ' http://localhost:4242 ', token: ' secret '),
      ),
      connectSource: ({required controlUrl, required token}) {
        observedUrl = controlUrl;
        observedToken = token;
        return source;
      },
    );

    await controller.autoConnect();

    expect(observedUrl, Uri.parse('http://localhost:4242'));
    expect(observedToken, 'secret');
    expect(controller.value, isA<LiveConnected>());
    controller.dispose();
  });

  test('discovery, decode, and validation errors settle manual', () async {
    final discoveries = <StationLockDiscovery>[
      StationLockDiscovery(
        workspaceRoots: () async => const [],
        readFile: (_) async => throw UnimplementedError(),
      ),
      _discovery('not json'),
      _discovery(_lock(controlUrl: ' ', token: ' ')),
      _discovery(_lock(controlUrl: 'ws://localhost:42', token: 'secret')),
    ];

    for (final discovery in discoveries) {
      final controller = LiveConnectionController(discovery: discovery);
      await controller.autoConnect();
      expect(controller.value, isA<LiveManual>());
      controller.dispose();
    }
  });

  test(
    'manual host:port normalizes and connector failures can retry',
    () async {
      var attempts = 0;
      Uri? observedUrl;
      String? observedToken;
      final source = _Source();
      final controller = LiveConnectionController(
        discovery: _discovery(_lock()),
        connectSource: ({required controlUrl, required token}) {
          attempts++;
          observedUrl = controlUrl;
          observedToken = token;
          if (attempts == 1) throw StateError('socket refused');
          return source;
        },
      );

      await controller.connect(
        controlUrl: ' station.test:4242 ',
        token: ' key ',
      );
      expect(controller.value, isA<LiveFailed>());
      await controller.connect(
        controlUrl: ' station.test:4242 ',
        token: ' key ',
      );

      expect(observedUrl, Uri.parse('http://station.test:4242'));
      expect(observedToken, 'key');
      expect(controller.value, isA<LiveConnected>());
      controller.dispose();
    },
  );

  test(
    'manual URL contract accepts explicit ports and rejects portless URLs',
    () async {
      final calls = <({Uri controlUrl, String token})>[];
      final controller = LiveConnectionController(
        discovery: _discovery(_lock()),
        connectSource: ({required controlUrl, required token}) {
          calls.add((controlUrl: controlUrl, token: token));
          return _Source();
        },
      );

      await controller.connect(
        controlUrl: 'station.test:4242',
        token: 'secret',
      );
      expect(calls, [
        (controlUrl: Uri.parse('http://station.test:4242'), token: 'secret'),
      ]);

      await controller.connect(
        controlUrl: 'https://station.test:4343',
        token: 'secret',
      );
      expect(calls, [
        (controlUrl: Uri.parse('http://station.test:4242'), token: 'secret'),
        (controlUrl: Uri.parse('https://station.test:4343'), token: 'secret'),
      ]);

      await controller.connect(
        controlUrl: 'https://station.test',
        token: 'secret',
      );
      expect(calls, hasLength(2));
      expect(
        controller.value,
        const LiveConnectionState.failed(
          message:
              'Enter host:port or an absolute http(s) control URL with an '
              'explicit port and a non-empty token.',
        ),
      );
      controller.dispose();
    },
  );

  test('manual validation requires HTTP(S), host, port, and token', () async {
    var calls = 0;
    final controller = LiveConnectionController(
      discovery: _discovery(_lock()),
      connectSource: ({required controlUrl, required token}) {
        calls++;
        return _Source();
      },
    );
    const invalid = <(String, String)>[
      ('', 'secret'),
      ('ws://station.test:42', 'secret'),
      ('http://:42', 'secret'),
      ('http://station.test', 'secret'),
      ('station.test:42', ''),
    ];

    for (final credentials in invalid) {
      await controller.connect(
        controlUrl: credentials.$1,
        token: credentials.$2,
      );
      expect(
        controller.value,
        const LiveConnectionState.failed(
          message:
              'Enter host:port or an absolute http(s) control URL with an '
              'explicit port and a non-empty token.',
        ),
      );
    }
    expect(calls, 0);
    controller.dispose();
  });

  test(
    'replacement, disconnect, and dispose release owned sources once',
    () async {
      final sources = <_Source>[];
      final controller = LiveConnectionController(
        discovery: _discovery(_lock()),
        connectSource: ({required controlUrl, required token}) {
          final source = _Source();
          sources.add(source);
          return source;
        },
      );

      await controller.connect(controlUrl: 'one.test:41', token: 'a');
      await controller.connect(controlUrl: 'two.test:42', token: 'b');
      expect(sources.first.disposeCalls, 1);
      await controller.disconnect();
      expect(sources.last.disposeCalls, 1);
      await controller.connect(controlUrl: 'three.test:43', token: 'c');
      controller.dispose();
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(sources[0].disposeCalls, 1);
      expect(sources[1].disposeCalls, 1);
      expect(sources[2].disposeCalls, 1);
    },
  );
}
