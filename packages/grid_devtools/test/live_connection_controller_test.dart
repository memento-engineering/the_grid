import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_devtools/src/live/live_connection_controller.dart';
import 'package:grid_devtools/src/live/station_lock_discovery.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

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

StationLockDiscovery _discovery({bool available = true}) =>
    StationLockDiscovery(
      workspaceRoots: () async => [Uri.parse('file:///workspace/')],
      readFile: (_) async {
        if (!available) throw StateError('missing');
        return '''
{"pid":1,"pgid":1,"startedAt":"2026-07-25T00:00:00.000Z",
 "controlUrl":"http://localhost:42","token":"secret"}''';
      },
    );

void main() {
  test('auto discovery publishes a connected source', () async {
    final source = _Source();
    final controller = LiveConnectionController(
      discovery: _discovery(),
      connectSource: ({required controlUrl, required token}) {
        expect(controlUrl, Uri.parse('http://localhost:42'));
        expect(token, 'secret');
        return source;
      },
    );

    await controller.autoDiscover();

    expect(controller.value, isA<LiveConnected>());
    controller.dispose();
  });

  test('discovery failure falls back to manual state', () async {
    final controller = LiveConnectionController(
      discovery: _discovery(available: false),
    );

    await controller.autoDiscover();

    expect(controller.value, isA<LiveManual>());
    controller.dispose();
  });

  test('replacement and disconnect dispose owned sources', () async {
    final sources = <_Source>[];
    final controller = LiveConnectionController(
      discovery: _discovery(),
      connectSource: ({required controlUrl, required token}) {
        final source = _Source();
        sources.add(source);
        return source;
      },
    );

    await controller.connect(controlUrl: 'http://one.test', token: 'a');
    await controller.connect(controlUrl: 'https://two.test', token: 'b');
    expect(sources.first.disposeCalls, 1);
    await controller.disconnect();
    expect(sources.last.disposeCalls, 1);
    expect(controller.value, isA<LiveDisconnected>());
    controller.dispose();
  });

  test(
    'invalid manual credentials fail without constructing a source',
    () async {
      var calls = 0;
      final controller = LiveConnectionController(
        discovery: _discovery(),
        connectSource: ({required controlUrl, required token}) {
          calls++;
          return _Source();
        },
      );

      await controller.connect(controlUrl: 'ws://wrong.test', token: '');

      expect(controller.value, isA<LiveFailed>());
      expect(calls, 0);
      controller.dispose();
    },
  );
}
