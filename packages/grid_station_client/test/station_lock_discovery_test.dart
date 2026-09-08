import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_station_client/grid_station_client.dart';

Map<String, Object?> _lock({String? controlUrl, String? token}) => {
  'pid': 1,
  'pgid': 1,
  'startedAt': '2026-07-25T00:00:00.000Z',
  if (controlUrl != null) 'controlUrl': controlUrl,
  if (token != null) 'token': token,
};

void main() {
  test('unavailable capability bypasses discovery adapters', () async {
    var capabilityCalls = 0;
    var rootCalls = 0;
    var readCalls = 0;
    final discovery = StationLockDiscovery(
      isCapable: () async {
        capabilityCalls++;
        return false;
      },
      workspaceRoots: () async {
        rootCalls++;
        return [Uri.parse('file:///workspace/')];
      },
      readFile: (_) async {
        readCalls++;
        return jsonEncode(_lock());
      },
    );

    await expectLater(
      discovery.discover(),
      throwsA(
        isA<StationLockDiscoveryUnavailable>().having(
          (error) => error.toString(),
          'message',
          'Station lock auto-discovery is unavailable',
        ),
      ),
    );

    expect(capabilityCalls, 1);
    expect(rootCalls, 0);
    expect(readCalls, 0);
  });

  test('reads roots in order and returns the first usable AOT lock', () async {
    final reads = <Uri>[];
    final discovery = StationLockDiscovery(
      isCapable: () async => true,
      workspaceRoots: () async => [
        Uri.parse('file:///first/'),
        Uri.parse('file:///second/'),
      ],
      readFile: (uri) async {
        reads.add(uri);
        return jsonEncode(
          uri.path.contains('first')
              ? _lock(controlUrl: '  ', token: 'secret')
              : _lock(controlUrl: ' http://localhost:42 ', token: ' secret '),
        );
      },
    );

    final record = await discovery.discover();

    expect(record.controlUrl, ' http://localhost:42 ');
    expect(record.token, ' secret ');
    expect(record.vmServiceUri, isNull);
    expect(reads, [
      Uri.parse('file:///first/.grid/station.lock'),
      Uri.parse('file:///second/.grid/station.lock'),
    ]);
  });

  test('whitespace credentials produce an accumulated typed failure', () {
    final discovery = StationLockDiscovery(
      isCapable: () async => true,
      workspaceRoots: () async => [Uri.parse('file:///workspace/')],
      readFile: (_) async => jsonEncode(_lock(controlUrl: '\t', token: '  ')),
    );

    expect(
      discovery.discover(),
      throwsA(
        isA<StationLockDiscoveryFailure>().having(
          (failure) => failure.failures,
          'failures',
          hasLength(1),
        ),
      ),
    );
  });

  test(
    'root enumeration failures are reported without escaping raw errors',
    () {
      final discovery = StationLockDiscovery(
        isCapable: () async => true,
        workspaceRoots: () async => throw StateError('roots unavailable'),
        readFile: (_) async => throw UnimplementedError(),
      );

      expect(
        discovery.discover(),
        throwsA(
          isA<StationLockDiscoveryFailure>().having(
            (failure) => failure.toString(),
            'message',
            contains('roots unavailable'),
          ),
        ),
      );
    },
  );
}
