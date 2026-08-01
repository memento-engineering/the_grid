@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_foundation/genesis_foundation.dart'
    show TreeNode, TreeSnapshot;
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_cli/src/station_control.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart'
    show StationLockRecord;
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show TreeOwner, GridCommandHandler, GridCommandRequest, GridCommandResult;
import 'package:test/test.dart';

final class _IdleResolver implements SessionResolver {
  const _IdleResolver();

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

final class _FakeCommandHandler implements GridCommandHandler {
  @override
  Future<GridCommandResult> call(GridCommandRequest request) async =>
      const GridCommandResult.completed(message: 'unused');
}

Bead _workBead(BeadStatus status) =>
    Bead(id: 'tg-headless', issueType: IssueType.task, status: status);

JoinedSnapshot _workspaceSnapshot(BeadStatus status, DateTime capturedAt) {
  final bead = _workBead(status);
  return JoinedSnapshot(
    graph: GraphSnapshot.fromParts(
      beads: [bead],
      dependencies: const [],
      readyIds: status == BeadStatus.open ? {bead.id} : const <String>{},
      capturedAt: capturedAt,
    ),
    sessionsByWorkBead: const {},
  );
}

StationStatus _status() => StationStatus(
  substation: 'tg',
  stateStore: null,
  workRoot: null,
  dryRun: true,
  pid: pid,
  startedAt: DateTime.utc(2026, 7, 25),
  version: 'test',
  ready: 1,
  mounted: 1,
  liveSessions: 0,
  lastSyncAt: DateTime.utc(2026, 7, 25),
);

TreeSnapshot _decode(Object? frame) => TreeSnapshot.fromJson(
  (jsonDecode(frame! as String) as Map).cast<String, Object?>(),
);

TreeNode _onlyChild(TreeNode node) {
  expect(node.children, hasLength(1));
  return node.children.single;
}

Future<StationLockRecord> _readLock(Directory workspace) async {
  final lock = File('${workspace.path}/.grid/station.lock');
  return StationLockRecord.fromJson(
    (jsonDecode(await lock.readAsString()) as Map).cast<String, Object?>(),
  );
}

Future<WebSocket> _connectFromLock(StationLockRecord lock) {
  final controlUrl = lock.controlUrl!;
  return WebSocket.connect(
    '${controlUrl.replaceFirst('http:', 'ws:')}/stream',
    headers: {HttpHeaders.authorizationHeader: 'Bearer ${lock.token!}'},
  );
}

Future<int> _streamStatus(Uri controlUrl, String token) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(controlUrl.resolve('/stream'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'headless client discovers the door and observes a closed bead',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'grid-leonard-headless-',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final joined = JoinedSnapshotNotifier(
        _workspaceSnapshot(BeadStatus.open, DateTime.utc(2026, 7, 25)),
      );
      addTearDown(joined.dispose);
      final fakes = buildFakes();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<StationServices>(
            value: fakes.ctx,
            child: InheritedSeed<SessionResolver>(
              value: const _IdleResolver(),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'tg',
                      ownedSubstations: {'tg'},
                    ),
                  ),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      );
      var tick = 0;
      final projector = TreeProjector(
        clock: () => DateTime.utc(2026, 7, 25, 0, 0, tick++),
      );
      addTearDown(projector.dispose);
      projector.afterFlush(root);

      const token = 'headless-test-bearer';
      final control = await StationControl.start(
        port: 0,
        token: token,
        view: _status,
        commandHandler: _FakeCommandHandler(),
        treeProjector: projector,
      );
      addTearDown(control.dispose);
      final gridDir = Directory('${workspace.path}/.grid');
      await gridDir.create();
      final lockFile = File('${gridDir.path}/station.lock');
      await lockFile.writeAsString(
        jsonEncode(
          StationLockRecord(
            pid: pid,
            pgid: pid,
            startedAt: DateTime.utc(2026, 7, 25),
            controlUrl: control.url,
            token: token,
          ).toJson(),
        ),
      );

      final lock = await _readLock(workspace);
      final socket = await _connectFromLock(lock);
      addTearDown(socket.close);
      final snapshots = StreamIterator<TreeSnapshot>(socket.map(_decode));
      addTearDown(snapshots.cancel);

      expect(await snapshots.moveNext(), isTrue);
      final first = snapshots.current;
      expect(first.contractVersion, 1);
      final scope = _onlyChild(first.root);
      final substation = _onlyChild(scope);
      final workList = _onlyChild(substation);
      final workBead = _onlyChild(workList);
      expect(
        [
          first.root.seedType,
          scope.seedType,
          substation.seedType,
          workList.seedType,
          workBead.seedType,
        ],
        ['Station', 'SubstationScope', 'Substation', 'WorkList', 'WorkBead'],
      );

      joined.push(
        _workspaceSnapshot(BeadStatus.closed, DateTime.utc(2026, 7, 25, 0, 1)),
      );
      owner.flush();
      projector.afterFlush(root);

      expect(await snapshots.moveNext(), isTrue);
      final second = snapshots.current;
      expect(second.projectedAt, isNot(first.projectedAt));
      expect(second.root.id, first.root.id);
      final secondWorkList = _onlyChild(_onlyChild(_onlyChild(second.root)));
      expect(secondWorkList.seedType, 'WorkList');
      expect(secondWorkList.children, isEmpty);
    },
  );

  test('headless client cannot upgrade with a different bearer', () async {
    final projector = TreeProjector();
    addTearDown(projector.dispose);
    final owner = TreeOwner();
    addTearDown(owner.dispose);
    final root = owner.mountRoot(Station([]));
    projector.afterFlush(root);
    final control = await StationControl.start(
      port: 0,
      token: 'lock-bearer',
      view: _status,
      commandHandler: _FakeCommandHandler(),
      treeProjector: projector,
    );
    addTearDown(control.dispose);

    expect(
      await _streamStatus(Uri.parse(control.url), 'different-bearer'),
      HttpStatus.unauthorized,
    );
  });
}
