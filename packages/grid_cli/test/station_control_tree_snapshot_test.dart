import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grid_cli/src/station_control.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';
import 'package:grid_engine/grid_engine.dart' show Diagnosable, TreeProjector;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

final class _DiagnosableRoot extends Seed with Diagnosable {
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

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
      final frames = <TreeSnapshot>[];
      final subscription = socket.listen((frame) => frames.add(_decode(frame)));
      addTearDown(subscription.cancel);

      await _pump();
      projector.afterFlush(root);
      expected.add(projector.latest!);
      projector.afterFlush(root);
      expected.add(projector.latest!);
      await _pump();

      expect(frames, expected);
    },
  );

  test('stream before first flush waits for the first snapshot', () async {
    final control = await _start(projector: projector);
    addTearDown(control.dispose);
    final socket = await _connect(control);
    addTearDown(socket.close);
    final frames = <TreeSnapshot>[];
    final subscription = socket.listen((frame) => frames.add(_decode(frame)));
    addTearDown(subscription.cancel);

    await _pump();
    expect(frames, isEmpty);
    projector.afterFlush(root);
    await _pump();

    expect(frames, [projector.latest]);
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
      await _pump();
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
