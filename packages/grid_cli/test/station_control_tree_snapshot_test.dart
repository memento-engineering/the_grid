import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/diagnostics_reporter.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show stationTreeBearerProtocolPrefix;
import 'package:grid_engine/grid_engine.dart'
    show GridDiagnosticable, TreeProjector;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _DiagnosableRoot extends Seed with GridDiagnosticable {
  const _DiagnosableRoot();

  @override
  Branch createBranch() => _LeafBranch(this);
}

final class _LeafBranch extends Branch {
  _LeafBranch(super.seed);
}

final class _FakeCommandHandler implements GridCommandHandler {
  @override
  Future<GridCommandResult> call(GridCommandRequest request) async =>
      const GridCommandResult.completed(message: 'unused');
}

StationStatus _status() => StationStatus(
  substation: 'tg',
  stateStore: null,
  workRoot: null,
  dryRun: false,
  pid: pid,
  startedAt: DateTime.utc(2026, 7, 25),
  version: 'test',
  ready: 0,
  mounted: 0,
  liveSessions: 0,
  lastSyncAt: null,
);

Future<StationControl> _start({
  TreeProjector? projector,
  InternetAddress? address,
}) => StationControl.start(
  port: 0,
  token: 't',
  view: _status,
  commandHandler: _FakeCommandHandler(),
  treeProjector: projector,
  address: address,
);

Future<WebSocket> _connect(StationControl control) => WebSocket.connect(
  '${control.url.replaceFirst('http:', 'ws:')}/stream',
  headers: {HttpHeaders.authorizationHeader: 'Bearer t'},
);

Future<WebSocket> _connectWithProtocol(StationControl control, String token) =>
    WebSocket.connect(
      '${control.url.replaceFirst('http:', 'ws:')}/stream',
      protocols: ['$stationTreeBearerProtocolPrefix$token'],
    );

Future<WebSocket> _connectWithQuery(StationControl control, String token) {
  final uri = Uri.parse(
    '${control.url.replaceFirst('http:', 'ws:')}/stream',
  ).replace(queryParameters: <String, String>{'token': token});
  return WebSocket.connect(uri.toString());
}

Future<WebSocket> _connectGovernor(
  StationControl control, {
  bool queryBearer = false,
}) {
  final uri = Uri.parse('${control.url.replaceFirst('http:', 'ws:')}/stream')
      .replace(
        queryParameters: <String, String>{
          'feed': 'governor',
          if (queryBearer) 'token': 't',
        },
      );
  return WebSocket.connect(
    uri.toString(),
    headers: queryBearer
        ? null
        : const <String, String>{HttpHeaders.authorizationHeader: 'Bearer t'},
  );
}

TreeSnapshot _decode(Object? frame) => TreeSnapshot.fromJson(
  (jsonDecode(frame! as String) as Map).cast<String, Object?>(),
);

Future<int> _getStatus(StationControl control, {String? authorization}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('${control.url}/stream'));
    if (authorization != null) {
      request.headers.set(HttpHeaders.authorizationHeader, authorization);
    }
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

Future<List<TreeSnapshot>> _takeSnapshots(WebSocket socket, int count) => socket
    .map(_decode)
    .take(count)
    .toList()
    .timeout(const Duration(seconds: 5));

Future<Map<String, Object?>> _readStatus(StationControl control) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('${control.url}/status'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer t');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return (jsonDecode(await utf8.decoder.bind(response).join()) as Map)
        .cast<String, Object?>();
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _governorStatus(Map<String, Object?> status) =>
    (status['governorFlares']! as Map).cast<String, Object?>();

Future<Map<String, Object?>> _waitForGovernorStatus(
  StationControl control, {
  required int delivered,
  required int unacknowledged,
}) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final status = await _readStatus(control);
    final governor = _governorStatus(status);
    if (governor['delivered'] == delivered &&
        governor['unacknowledged'] == unacknowledged) {
      return governor;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'governor status never reached '
    '$delivered delivered/$unacknowledged unacknowledged',
  );
}

Future<Map<String, Object?>> _nextJson(StreamIterator<Object?> iterator) async {
  final hasNext = await iterator.moveNext().timeout(const Duration(seconds: 5));
  expect(hasNext, isTrue);
  return (jsonDecode(iterator.current! as String) as Map)
      .cast<String, Object?>();
}

void main() {
  late TreeOwner owner;
  late Branch root;
  late TreeProjector projector;

  setUp(() {
    owner = TreeOwner();
    root = owner.mountRoot(const _DiagnosableRoot());
    var tick = 0;
    projector = TreeProjector(
      clock: () => DateTime.utc(2026, 7, 25, 0, 0, tick++),
    );
  });

  tearDown(() {
    projector.dispose();
    owner.dispose();
  });

  test(
    'authorized stream replays latest then forwards full snapshots in order',
    () async {
      projector.afterFlush(root);
      final expected = <TreeSnapshot>[projector.latest!];
      final control = await _start(projector: projector);
      addTearDown(control.dispose);
      final socket = await _connect(control);
      addTearDown(socket.close);
      final frames = _takeSnapshots(socket, 3);

      projector.afterFlush(root);
      expected.add(projector.latest!);
      projector.afterFlush(root);
      expected.add(projector.latest!);

      expect(await frames, expected);
    },
  );

  test('stream before first flush waits for the first snapshot', () async {
    final control = await _start(projector: projector);
    addTearDown(control.dispose);
    final socket = await _connect(control);
    addTearDown(socket.close);
    final frames = _takeSnapshots(socket, 1);

    expect(projector.latest, isNull);
    projector.afterFlush(root);

    expect(await frames, [projector.latest]);
  });

  test('legacy bearer subprotocol authenticates and is selected', () async {
    final control = await _start(projector: projector);
    addTearDown(control.dispose);
    final socket = await _connectWithProtocol(control, 't');
    addTearDown(socket.close);

    expect(socket.protocol, '${stationTreeBearerProtocolPrefix}t');
  });

  test('query bearer authenticates without selecting a protocol', () async {
    projector.afterFlush(root);
    final control = await _start(projector: projector);
    addTearDown(control.dispose);
    final socket = await _connectWithQuery(control, 't');
    addTearDown(socket.close);

    expect(socket.protocol, isNull);
    expect(await _takeSnapshots(socket, 1), [projector.latest]);
  });

  test(
    'governor feed delivers stable unique ids once per flare and counts once',
    () async {
      final lines = <String>[];
      final reporter = StationDiagnosticsReporter(writeLine: lines.add);
      addTearDown(reporter.dispose);
      final control = await _start();
      addTearDown(control.dispose);
      reporter.addTransport(control);

      expect(_governorStatus(await _readStatus(control)), {
        'delivered': 0,
        'unacknowledged': 0,
      });
      final firstSocket = await _connectGovernor(control);
      final secondSocket = await _connectGovernor(control, queryBearer: true);
      addTearDown(firstSocket.close);
      addTearDown(secondSocket.close);
      final firstFrames = StreamIterator<Object?>(firstSocket);
      final secondFrames = StreamIterator<Object?>(secondSocket);

      final firstNext = _nextJson(firstFrames);
      final secondNext = _nextJson(secondFrames);
      reporter.flare('relay.escalated', {'beadId': 'tg-a'});
      final first = await firstNext;
      final second = await secondNext;
      expect(first, second);
      expect(first, {
        'type': 'flare',
        'id': 'governor-1',
        'name': 'relay.escalated',
        'data': {'beadId': 'tg-a'},
      });
      expect(
        await _waitForGovernorStatus(control, delivered: 1, unacknowledged: 1),
        {'delivered': 1, 'unacknowledged': 1},
      );

      final firstNextId = _nextJson(firstFrames);
      final secondNextId = _nextJson(secondFrames);
      reporter.flare('relay.absent', {'beadId': 'tg-b'});
      final nextFrames = await Future.wait([firstNextId, secondNextId]);
      expect(nextFrames[0], nextFrames[1]);
      expect(nextFrames[0]['id'], isNot(first['id']));
      expect(lines, hasLength(2));
      expect(
        await _waitForGovernorStatus(control, delivered: 2, unacknowledged: 2),
        {'delivered': 2, 'unacknowledged': 2},
      );
    },
  );

  test(
    'governor acknowledgements are explicit, idempotent, and text-only',
    () async {
      final control = await _start();
      addTearDown(control.dispose);
      final socket = await _connectGovernor(control);
      addTearDown(socket.close);
      final frames = StreamIterator<Object?>(socket);

      final firstNext = _nextJson(frames);
      control.flare('relay.escalated', const {});
      final first = await firstNext;
      expect(
        await _waitForGovernorStatus(control, delivered: 1, unacknowledged: 1),
        {'delivered': 1, 'unacknowledged': 1},
      );

      socket.add(jsonEncode({'ack': first['id']}));
      expect(
        await _waitForGovernorStatus(control, delivered: 1, unacknowledged: 0),
        {'delivered': 1, 'unacknowledged': 0},
      );

      final secondNext = _nextJson(frames);
      control.flare('relay.absent', const {});
      final second = await secondNext;
      socket
        ..add(jsonEncode({'ack': first['id']}))
        ..add(jsonEncode({'ack': 'governor-unknown'}))
        ..add('{malformed')
        ..add(const <int>[1, 2, 3])
        ..add(jsonEncode({'ack': 7}))
        ..add(jsonEncode({'ack': second['id']}));
      expect(
        await _waitForGovernorStatus(control, delivered: 2, unacknowledged: 0),
        {'delivered': 2, 'unacknowledged': 0},
      );
    },
  );

  test(
    'snapshot and governor feeds are isolated and missed flares are not replayed',
    () async {
      final lines = <String>[];
      final reporter = StationDiagnosticsReporter(
        writeLine: lines.add,
        treeProjector: projector,
      );
      final control = await _start(projector: projector);
      addTearDown(control.dispose);
      reporter.addTransport(control);
      projector.afterFlush(root);

      final snapshotSocket = await _connect(control);
      addTearDown(snapshotSocket.close);
      final snapshotFrames = StreamIterator<Object?>(snapshotSocket);
      expect(
        TreeSnapshot.fromJson(await _nextJson(snapshotFrames)),
        projector.latest,
      );

      reporter.flare('relay.noSubscriber', {'beadId': 'tg-missed'});
      expect(lines, hasLength(1));
      expect(_governorStatus(await _readStatus(control)), {
        'delivered': 0,
        'unacknowledged': 0,
      });

      final governorSocket = await _connectGovernor(control);
      addTearDown(governorSocket.close);
      final governorFrames = StreamIterator<Object?>(governorSocket);
      final nextGovernor = _nextJson(governorFrames);
      final nextSnapshot = _nextJson(snapshotFrames);

      projector.afterFlush(root);
      reporter.flare('station.wedged', {'gated': '1'});
      reporter.flare('relay.absent', {'beadId': 'tg-live'});

      expect(TreeSnapshot.fromJson(await nextSnapshot), projector.latest);
      expect(await nextGovernor, {
        'type': 'flare',
        'id': 'governor-1',
        'name': 'relay.absent',
        'data': {'beadId': 'tg-live'},
      });
      expect(lines.map(jsonDecode).map((line) => line['name']), [
        'relay.noSubscriber',
        'station.wedged',
        'relay.absent',
      ]);
      expect(
        await _waitForGovernorStatus(control, delivered: 1, unacknowledged: 1),
        {'delivered': 1, 'unacknowledged': 1},
      );
    },
  );

  test('wrong query and legacy bearer are rejected before upgrade', () async {
    final control = await _start(projector: projector);
    addTearDown(control.dispose);

    await expectLater(
      _connectWithQuery(control, 'wrong'),
      throwsA(isA<WebSocketException>()),
    );
    await expectLater(
      _connectWithProtocol(control, 'wrong'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test(
    'stream requires bearer before upgrade and reports unavailable projector',
    () async {
      final control = await _start(projector: projector);
      addTearDown(control.dispose);
      expect(await _getStatus(control), HttpStatus.unauthorized);
      expect(
        await _getStatus(control, authorization: 'Bearer wrong'),
        HttpStatus.unauthorized,
      );
      expect(
        await _getStatus(control, authorization: 'Bearer t'),
        HttpStatus.upgradeRequired,
      );

      final unavailable = await _start();
      addTearDown(unavailable.dispose);
      expect(
        await _getStatus(unavailable, authorization: 'Bearer t'),
        HttpStatus.serviceUnavailable,
      );
    },
  );

  test(
    'closing stream cancels delivery and control disposal closes clients',
    () async {
      final control = await _start(projector: projector);
      final first = await _connect(control);
      final firstDone = Completer<void>();
      final closedFrames = <Object?>[];
      first.listen(closedFrames.add, onDone: firstDone.complete);
      await first.close();
      await firstDone.future;
      projector.afterFlush(root);
      expect(closedFrames, isEmpty);

      final active = await _connect(control);
      final activeDone = Completer<void>();
      active.listen((_) {}, onDone: activeDone.complete);
      final governor = await _connectGovernor(control);
      final governorDone = Completer<void>();
      governor.listen((_) {}, onDone: governorDone.complete);
      await control.dispose();

      await activeDone.future;
      await governorDone.future;
      expect(projector.latest, isNotNull);
      projector.afterFlush(root);
      expect(projector.latest, isNotNull);
    },
  );

  test(
    'binding defaults to loopback and accepts an explicit address',
    () async {
      final loopback = await _start(projector: projector);
      expect(
        Uri.parse(loopback.url).host,
        InternetAddress.loopbackIPv4.address,
      );
      await loopback.dispose();

      final any = await _start(
        projector: projector,
        address: InternetAddress.anyIPv4,
      );
      expect(Uri.parse(any.url).host, InternetAddress.anyIPv4.address);
      await any.dispose();
    },
  );
}
