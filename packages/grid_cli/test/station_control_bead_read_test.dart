import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/grid_cli.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('POST /command decodes bead board and round requests', () async {
    final handler = _Handler();
    final control = await StationControl.start(
      port: 0,
      token: 'token',
      view: _status,
      commandHandler: handler,
    );
    addTearDown(control.dispose);

    final board = await _post(control.url, 'board', {
      'id': 'board',
      'method': 'grid/bead/board',
      'params': {
        'stores': ['alpha'],
        'statuses': ['open'],
        'blocked': true,
        'approved': false,
      },
    });
    final round = await _post(control.url, 'round', {
      'id': 'round',
      'method': 'grid/bead/round',
      'params': {'beadId': 'tg-1'},
    });

    expect(board.statusCode, HttpStatus.ok);
    expect(round.statusCode, HttpStatus.ok);
    expect(
      handler.calls.first,
      const GridCommandRequest.board(
        stores: {'alpha'},
        statuses: {'open'},
        blockedOnly: true,
        approved: false,
      ),
    );
    expect(
      handler.calls.last,
      const GridCommandRequest.beadRound(beadId: 'tg-1'),
    );
  });

  test('invalid bead read params return invalid_request', () async {
    final handler = _Handler();
    final control = await StationControl.start(
      port: 0,
      token: 'token',
      view: _status,
      commandHandler: handler,
    );
    addTearDown(control.dispose);

    final badBoard = await _post(control.url, 'bad-board', {
      'id': 'bad-board',
      'method': 'grid/bead/board',
      'params': {
        'stores': [1],
      },
    });
    final badRound = await _post(control.url, 'bad-round', {
      'id': 'bad-round',
      'method': 'grid/bead/round',
      'params': {'beadId': ''},
    });

    for (final response in [badBoard, badRound]) {
      expect(response.statusCode, HttpStatus.badRequest);
      expect(
        (jsonDecode(response.body) as Map)['error']['code'],
        'invalid_request',
      );
    }
    expect(handler.calls, isEmpty);
  });
}

StationStatus _status() => StationStatus(
  substation: 'test',
  stateStore: null,
  workRoot: null,
  dryRun: true,
  pid: 1,
  startedAt: DateTime.utc(2026, 9, 3),
  version: 'test',
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

Future<({int statusCode, String body})> _post(
  String base,
  String key,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$base/command'));
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer token')
      ..set('X-Grid-Fence', '1')
      ..set('Idempotency-Key', key)
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    return (
      statusCode: response.statusCode,
      body: await response.transform(const Utf8Decoder()).join(),
    );
  } finally {
    client.close(force: true);
  }
}

final class _Handler implements GridCommandHandler {
  final calls = <GridCommandRequest>[];

  @override
  Future<GridCommandResult> call(GridCommandRequest request) async {
    calls.add(request);
    return const GridCommandResult.completed(message: 'ok');
  }
}
