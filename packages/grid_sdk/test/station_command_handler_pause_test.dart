import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

Bead _session({bool closed = false, String? pauseState}) => Bead(
  id: 'tgdog-s1',
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'work_bead': 'tg-1',
    'rig': 'tgdog',
    if (pauseState != null) 'grid.session.pause_state': pauseState,
  },
);

Future<void> _expectRefused(
  StationCommandHandler handler,
  GridCommandRequest request, {
  required String code,
  required _RecordingRunner stateRunner,
  required _RecordingRunner workRunner,
}) async {
  final result = await handler(request);
  expect(
    result,
    isA<GridCommandRefused>().having((value) => value.code, 'code', code),
  );
  expect(stateRunner.calls, isEmpty, reason: 'refusal must be zero-write');
  expect(workRunner.calls, isEmpty, reason: 'refusal must be zero-write');
}

StationCommandHandler _handler({
  required _Source state,
  required _Source work,
  required _RecordingRunner stateRunner,
  required _RecordingRunner workRunner,
}) => StationCommandHandler(
  stateSource: state,
  refreshState: () async {},
  stateWriter: StationBeadWriter(
    bd: BdCliService(stateRunner),
    reader: stateRunner,
    ownership: BeadOwnershipPredicate(const {'tg', 'tgdog'}),
  ),
  stateOwnership: BeadOwnershipPredicate(const {'tg', 'tgdog'}),
  workStoresByIdentity: {
    'tg': WorkCommandStore(
      substation: 'tg',
      root: '/work/tg',
      source: work,
      refresh: () async {},
      writer: StationBeadWriter(
        bd: BdCliService(workRunner),
        reader: workRunner,
        ownership: BeadOwnershipPredicate(const {'tg'}),
      ),
    ),
  },
);

GraphSnapshot _snapshot(Iterable<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

final class _Source implements SnapshotSource {
  _Source(this.current);

  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast(sync: true);

  @override
  GraphSnapshot? current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;
}

final class _RecordingRunner implements BdRunner, BeadProbeReader {
  final calls = <List<String>>[];

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

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (args.isNotEmpty && args.first == 'export') {
      return const BdResult(exitCode: 0, stdout: '', stderr: '');
    }
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{}}',
      stderr: '',
    );
  }
}

void main() {
  setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

  test('pause stamps paused on the session bead and nothing else', () async {
    final stateRunner = _RecordingRunner();
    final handler = _handler(
      state: _Source(_snapshot([_session()])),
      work: _Source(_snapshot(const [])),
      stateRunner: stateRunner,
      workRunner: _RecordingRunner(),
    );

    final result = await handler(
      const GridCommandRequest.pauseSession(beadId: 'tg-1'),
    );

    expect(result, isA<GridCommandCompleted>());
    expect((result as GridCommandCompleted).value['changed'], true);
    expect(result.value['pauseState'], 'paused');
    final updates = stateRunner.calls.where((call) => call.first == 'update');
    expect(updates, hasLength(1));
    expect(
      updates.single,
      containsAllInOrder(<String>[
        'update',
        'tgdog-s1',
        '--set-metadata',
        'grid.session.pause_state=paused',
      ]),
    );
    expect(stateRunner.calls.any((call) => call.first == 'close'), isFalse);
    expect(stateRunner.calls.join(' '), isNot(contains('work_bead')));
  });

  test('resume stamps resumed on a paused session', () async {
    final stateRunner = _RecordingRunner();
    final handler = _handler(
      state: _Source(_snapshot([_session(pauseState: 'paused')])),
      work: _Source(_snapshot(const [])),
      stateRunner: stateRunner,
      workRunner: _RecordingRunner(),
    );

    final result = await handler(
      const GridCommandRequest.resumeSession(beadId: 'tg-1'),
    );

    expect((result as GridCommandCompleted).value['pauseState'], 'resumed');
    expect(
      stateRunner.calls.single,
      containsAllInOrder(<String>[
        'update',
        'tgdog-s1',
        '--set-metadata',
        'grid.session.pause_state=resumed',
      ]),
    );
  });

  test('both verbs are idempotent and write nothing', () async {
    for (final entry in const <(GridCommandRequest, String)>[
      (GridCommandRequest.pauseSession(beadId: 'tg-1'), 'paused'),
      (GridCommandRequest.resumeSession(beadId: 'tg-1'), 'resumed'),
    ]) {
      final stateRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(_snapshot([_session(pauseState: entry.$2)])),
        work: _Source(_snapshot(const [])),
        stateRunner: stateRunner,
        workRunner: _RecordingRunner(),
      );
      final result = await handler(entry.$1);
      expect((result as GridCommandCompleted).value['changed'], false);
      expect(stateRunner.calls, isEmpty);
    }
  });

  test('nonsense is refused loudly and without writes', () async {
    final cases = <(List<Bead>, GridCommandRequest, String)>[
      (
        [_session()],
        const GridCommandRequest.resumeSession(beadId: 'tg-1'),
        'session_not_paused',
      ),
      (
        [_session(closed: true)],
        const GridCommandRequest.pauseSession(beadId: 'tg-1'),
        'session_terminal',
      ),
      (
        [_session(closed: true, pauseState: 'paused')],
        const GridCommandRequest.resumeSession(beadId: 'tg-1'),
        'session_terminal',
      ),
      (
        <Bead>[],
        const GridCommandRequest.pauseSession(beadId: 'tg-1'),
        'session_not_found',
      ),
      (
        [_session(), _session().copyWith(id: 'tgdog-s2')],
        const GridCommandRequest.pauseSession(beadId: 'tg-1'),
        'session_ambiguous',
      ),
    ];
    for (final entry in cases) {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      await _expectRefused(
        _handler(
          state: _Source(_snapshot(entry.$1)),
          work: _Source(_snapshot(const [])),
          stateRunner: stateRunner,
          workRunner: workRunner,
        ),
        entry.$2,
        code: entry.$3,
        stateRunner: stateRunner,
        workRunner: workRunner,
      );
    }
  });
}
