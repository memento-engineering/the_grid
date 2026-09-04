import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_command_client.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLifecyclePhase, StationLockRecord;
import 'package:test/test.dart';

void main() {
  test('missing lock is unavailable and names exact path', () async {
    final root = await Directory.systemTemp.createTemp('station-client-');
    addTearDown(() => root.delete(recursive: true));
    final result = await StationCommandClient().send(
      gridRoot: root.path,
      method: 'grid/gate/ls',
      params: const {},
    );
    expect(result, isA<StationCommandUnavailable>());
    expect(
      (result as StationCommandUnavailable).message,
      contains('${root.path}/.grid/station.lock'),
    );
  });

  test('sends bearer, fence, idempotency key and payload', () async {
    final root = await Directory.systemTemp.createTemp('station-client-');
    addTearDown(() => root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late HttpHeaders headers;
    late Map<String, Object?> payload;
    server.listen((request) async {
      headers = request.headers;
      payload = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
          .cast<String, Object?>();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'result': {'gates': <Object?>[]},
          }),
        );
      await request.response.close();
    });
    final lock = File('${root.path}/.grid/station.lock');
    await lock.parent.create(recursive: true);
    await lock.writeAsString(
      jsonEncode(<String, Object?>{
        'pid': 42,
        'pgid': 42,
        'startedAt': DateTime.utc(2026).toIso8601String(),
        'controlUrl': 'http://127.0.0.1:${server.port}',
        'token': 'secret',
      }),
    );
    final result = await StationCommandClient(
      clock: () => DateTime.fromMicrosecondsSinceEpoch(123, isUtc: true),
    ).send(gridRoot: root.path, method: 'grid/gate/ls', params: const {});
    expect(result, isA<StationCommandCompleted>());
    expect(headers.value(HttpHeaders.authorizationHeader), 'Bearer secret');
    expect(headers.value('x-grid-fence'), '123');
    expect(headers.value('idempotency-key'), '42-123');
    expect(payload['method'], 'grid/gate/ls');
  });

  for (final phase in <StationLifecyclePhase>[
    StationLifecyclePhase.acquired,
    StationLifecyclePhase.releasing,
  ]) {
    test(
      '${phase.name} refuses before credential validation or HTTP',
      () async {
        final root = await Directory.systemTemp.createTemp('station-client-');
        addTearDown(() => root.delete(recursive: true));
        final lock = File('${root.path}/.grid/station.lock');
        await lock.parent.create(recursive: true);
        await lock.writeAsString(
          jsonEncode(
            StationLockRecord(
              pid: 42,
              pgid: 42,
              startedAt: DateTime.utc(2026),
              phase: phase,
              controlUrl: 'http://127.0.0.1:9',
              token: 'secret',
            ).toJson(),
          ),
        );

        final result = await StationCommandClient(
          httpClientFactory: () => fail('${phase.name} must not attempt HTTP'),
        ).send(gridRoot: root.path, method: 'grid/gate/ls', params: const {});

        expect(result, isA<StationCommandUnavailable>());
        expect(
          (result as StationCommandUnavailable).message,
          contains(
            phase == StationLifecyclePhase.acquired ? 'STARTING' : 'RELEASING',
          ),
        );
      },
    );
  }

  test(
    'live record with missing credentials reports unusable transport',
    () async {
      final root = await Directory.systemTemp.createTemp('station-client-');
      addTearDown(() => root.delete(recursive: true));
      final lock = File('${root.path}/.grid/station.lock');
      await lock.parent.create(recursive: true);
      await lock.writeAsString(
        jsonEncode(
          StationLockRecord(
            pid: 42,
            pgid: 42,
            startedAt: DateTime.utc(2026),
          ).toJson(),
        ),
      );

      final result = await StationCommandClient(
        httpClientFactory: () =>
            fail('missing credentials must not reach HTTP'),
      ).send(gridRoot: root.path, method: 'grid/gate/ls', params: const {});

      expect(result, isA<StationCommandUnavailable>());
      expect(
        (result as StationCommandUnavailable).message,
        contains('unusable control transport advertisement'),
      );
    },
  );
}
