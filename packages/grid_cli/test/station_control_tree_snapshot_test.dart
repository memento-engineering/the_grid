import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_control.dart';
import 'package:genesis_foundation/genesis_foundation.dart' show TreeSnapshot;
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
      await control.dispose();

      await activeDone.future;
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
