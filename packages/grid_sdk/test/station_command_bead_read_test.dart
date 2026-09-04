import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('board and round stay resident, complete, and write-free', () async {
    final stateRunner = _FakeRunner();
    final alphaRunner = _FakeRunner();
    final betaRunner = _FakeRunner();
    final missingRunner = _FakeRunner();
    final brokenRunner = _FakeRunner();
    final alpha = _binding(
      name: 'alpha',
      root: '/alpha',
      source: _Source(
        _snapshot(const [
          Bead(id: 'a-1', title: 'round work'),
          Bead(id: 'a-2', title: 'between rounds'),
        ]),
      ),
      runner: alphaRunner,
    );
    final beta = _binding(
      name: 'beta',
      root: '/beta',
      source: _Source(_snapshot(const [Bead(id: 'b-1', title: 'beta')])),
      runner: betaRunner,
    );
    final missing = _binding(
      name: 'missing',
      root: '/missing',
      source: _Source(null),
      runner: missingRunner,
    );
    final broken = _binding(
      name: 'broken',
      root: '/broken',
      source: _Source(_snapshot(const [])),
      runner: brokenRunner,
      refresh: () async => throw StateError('refresh boom'),
    );
    final handler = StationCommandHandler(
      stateSource: _Source(
        _snapshot(const [
          Bead(
            id: 'tgdog-session',
            issueType: GridIssueTypes.session,
            metadata: {SessionBeadKeys.workBead: 'a-1'},
          ),
        ]),
      ),
      refreshState: () async {},
      stateWriter: _writer(stateRunner, {'tgdog'}),
      stateOwnership: BeadOwnershipPredicate(const {'tgdog'}),
      workStoresByIdentity: {
        'alpha': alpha,
        'a': alpha,
        'beta': beta,
        'b': beta,
        'missing': missing,
        'm': missing,
        'broken': broken,
        'z': broken,
      },
    );

    final board = await handler(const GridCommandRequest.board());
    expect(board, isA<GridCommandCompleted>());
    final rows = (board as GridCommandCompleted).value['rows']! as List;
    final decoded = rows
        .whereType<Map<Object?, Object?>>()
        .map((row) => BoardRow.fromJson(row.cast<String, dynamic>()))
        .toList();
    expect(decoded.whereType<BoardBeadRow>().map((row) => row.id), [
      'a-1',
      'a-2',
      'b-1',
    ]);
    expect(
      decoded.whereType<BoardStoreUnreadableRow>().map((row) => row.store),
      ['broken', 'missing'],
    );
    expect(
      decoded.whereType<BoardStoreUnreadableRow>().first.reason,
      contains('refresh boom'),
    );

    final found = await handler(
      const GridCommandRequest.beadRound(beadId: 'a-1'),
    );
    expect(
      RoundContext.fromJson(
        ((found as GridCommandCompleted).value['context']! as Map)
            .cast<String, dynamic>(),
      ),
      isA<BeadRoundFound>(),
    );
    final absent = await handler(
      const GridCommandRequest.beadRound(beadId: 'a-2'),
    );
    expect(
      RoundContext.fromJson(
        ((absent as GridCommandCompleted).value['context']! as Map)
            .cast<String, dynamic>(),
      ),
      isA<BeadRoundAbsent>(),
    );
    final refused = await handler(
      const GridCommandRequest.beadRound(beadId: 'unowned-1'),
    );
    expect(
      refused,
      isA<GridCommandRefused>().having(
        (result) => result.code,
        'code',
        'work_store_not_owned',
      ),
    );

    for (final runner in [
      stateRunner,
      alphaRunner,
      betaRunner,
      missingRunner,
      brokenRunner,
    ]) {
      expect(runner.calls, isEmpty, reason: 'READ verbs must never invoke bd');
    }
  });
}

GraphSnapshot _snapshot(Iterable<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026, 9, 3),
);

WorkCommandStore _binding({
  required String name,
  required String root,
  required _Source source,
  required _FakeRunner runner,
  Future<void> Function()? refresh,
}) => WorkCommandStore(
  substation: name,
  root: root,
  source: source,
  refresh: refresh ?? () async {},
  writer: _writer(runner, {name, name.substring(0, 1)}),
);

StationBeadWriter _writer(_FakeRunner runner, Set<String> ownership) =>
    StationBeadWriter(
      bd: BdCliService(runner),
      reader: runner,
      ownership: BeadOwnershipPredicate(ownership),
    );

final class _Source implements SnapshotSource {
  _Source(this.current);

  @override
  GraphSnapshot? current;

  @override
  Stream<GraphSnapshot> get snapshots => const Stream.empty();
}

final class _FakeRunner implements BdRunner, BeadProbeReader {
  final calls = <List<String>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    return const BdResult(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async =>
      null;

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}
