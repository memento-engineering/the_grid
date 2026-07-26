import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_devtools/src/live/station_lock_discovery.dart';

void main() {
  test(
    'reads workspace locks in order and returns first usable record',
    () async {
      final reads = <Uri>[];
      final discovery = StationLockDiscovery(
        workspaceRoots: () async => [
          Uri.parse('file:///first/'),
          Uri.parse('file:///second/'),
        ],
        readFile: (uri) async {
          reads.add(uri);
          return jsonEncode({
            'pid': 1,
            'pgid': 1,
            'startedAt': '2026-07-25T00:00:00.000Z',
            if (uri.path.contains('second')) ...{
              'controlUrl': 'http://localhost:42',
              'token': 'secret',
            },
          });
        },
      );

      final record = await discovery.discover();

      expect(record.controlUrl, 'http://localhost:42');
      expect(reads, [
        Uri.parse('file:///first/.grid/station.lock'),
        Uri.parse('file:///second/.grid/station.lock'),
      ]);
    },
  );

  test('returns a typed failure when DTD roots are unavailable', () async {
    final discovery = StationLockDiscovery(
      workspaceRoots: () async => throw StateError('DTD unavailable'),
      readFile: (_) async => throw UnimplementedError(),
    );

    await expectLater(
      discovery.discover(),
      throwsA(isA<StationLockDiscoveryFailure>()),
    );
  });
}
