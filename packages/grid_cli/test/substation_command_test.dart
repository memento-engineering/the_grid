import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _FakeClient extends StationCommandClient {
  _FakeClient(this.result);

  final StationCommandResult result;
  String? gridRoot;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<StationCommandResult> send({
    required String gridRoot,
    required String method,
    required Map<String, Object?> params,
  }) async {
    this.gridRoot = gridRoot;
    this.method = method;
    this.params = params;
    return result;
  }
}

final class _RecordingHandler implements GridCommandHandler {
  final List<GridCommandRequest> calls = [];

  @override
  Future<GridCommandResult> call(GridCommandRequest request) async {
    calls.add(request);
    return const GridCommandResult.completed(
      message: 'ok',
      value: {'ok': true},
    );
  }
}

StationStatus _status() => StationStatus(
  substation: 'state',
  stateStore: null,
  workRoot: null,
  dryRun: true,
  pid: 1,
  startedAt: DateTime.utc(2026),
  version: 'test',
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

Future<({int status, Map<String, Object?> body})> _post(
  StationControl control,
  Object body, {
  required int fence,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('${control.url}/command'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer token')
      ..set('X-Grid-Fence', '$fence')
      ..set('Idempotency-Key', 'command-$fence')
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final decoded = jsonDecode(
      await response.transform(const Utf8Decoder()).join(),
    );
    return (
      status: response.statusCode,
      body: (decoded as Map).cast<String, Object?>(),
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('parseSubstationSpec accepts name and optional prefix', () {
    expect(parseSubstationSpec('earth=/w/earth'), (
      name: 'earth',
      prefix: null,
      root: '/w/earth',
    ));
    expect(parseSubstationSpec('earth@ea=/w/earth'), (
      name: 'earth',
      prefix: 'ea',
      root: '/w/earth',
    ));
    for (final invalid in const ['earth', '=/w/earth', 'earth=']) {
      expect(parseSubstationSpec(invalid), isNull);
    }
  });

  test('attach sends the resident method and renders completion', () async {
    final output = <String>[];
    final client = _FakeClient(
      const StationCommandCompleted({
        'name': 'earth',
        'prefix': 'ea',
        'root': '/w/earth',
      }),
    );

    expect(
      await runSubstationAttach(
        gridRoot: '/grid',
        spec: 'earth@ea=/w/earth',
        client: client,
        out: output.add,
      ),
      0,
    );
    expect(client.gridRoot, '/grid');
    expect(client.method, 'grid/substation/attach');
    expect(client.params, {
      'name': 'earth',
      'prefix': 'ea',
      'root': '/w/earth',
    });
    expect(output.single, contains('attached earth'));
  });

  test('detach sends force and renders draining completion', () async {
    final output = <String>[];
    final client = _FakeClient(
      const StationCommandCompleted({
        'name': 'earth',
        'draining': true,
        'inFlight': ['ea-1'],
      }),
    );

    expect(
      await runSubstationDetach(
        gridRoot: '/grid',
        name: 'earth',
        force: true,
        client: client,
        out: output.add,
      ),
      0,
    );
    expect(client.method, 'grid/substation/detach');
    expect(client.params, {'name': 'earth', 'force': true});
    expect(output.single, contains('draining earth'));
  });

  for (final result in <StationCommandResult>[
    const StationCommandRefused('resident refused'),
    const StationCommandUnavailable('station unavailable'),
  ]) {
    test('attach renders ${result.runtimeType} loudly', () async {
      final errors = <String>[];
      expect(
        await runSubstationAttach(
          gridRoot: '/grid',
          spec: 'earth=/w/earth',
          client: _FakeClient(result),
          err: errors.add,
        ),
        64,
      );
      expect(errors.single, isNotEmpty);
    });
  }

  test(
    'StationControl decodes attach and detach and rejects a missing root',
    () async {
      final handler = _RecordingHandler();
      final control = await StationControl.start(
        port: 0,
        token: 'token',
        view: _status,
        commandHandler: handler,
      );
      addTearDown(control.dispose);

      final attach = await _post(control, {
        'id': 1,
        'method': 'grid/substation/attach',
        'params': {'name': 'earth', 'prefix': 'ea', 'root': '/w/earth'},
      }, fence: 1);
      expect(attach.status, HttpStatus.ok);
      expect(
        handler.calls.last,
        const GridCommandRequest.attachSubstation(
          name: 'earth',
          prefix: 'ea',
          root: '/w/earth',
        ),
      );

      final detach = await _post(control, {
        'id': 2,
        'method': 'grid/substation/detach',
        'params': {'name': 'earth', 'force': true},
      }, fence: 2);
      expect(detach.status, HttpStatus.ok);
      expect(
        handler.calls.last,
        const GridCommandRequest.detachSubstation(name: 'earth', force: true),
      );

      final invalid = await _post(control, {
        'id': 3,
        'method': 'grid/substation/attach',
        'params': {'name': 'earth'},
      }, fence: 3);
      expect(invalid.status, HttpStatus.badRequest);
      expect((invalid.body['error'] as Map)['code'], 'invalid_request');
    },
  );
}
