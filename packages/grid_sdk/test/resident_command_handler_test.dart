import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('resident command dispatch', () {
    test(
      'grid/rework re-keys a closed session through resident writers',
      () async {
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        final state = _Source(
          _snapshot([
            Bead(
              id: 'tgdog-session',
              issueType: IssueType.session,
              status: BeadStatus.closed,
              metadata: const {'work_bead': 'tg-1', 'rig': 'tg'},
            ),
          ]),
        );
        final work = _Source(
          _snapshot([
            const Bead(
              id: 'tg-1',
              issueType: IssueType.task,
              metadata: {'rig': 'tg'},
            ),
          ]),
        );
        final handler = _handler(
          state: state,
          work: work,
          stateRunner: stateRunner,
          workRunner: workRunner,
        );

        final result = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );

        expect(result, isA<GridCommandCompleted>());
        expect(workRunner.calls.first, containsAll(['update', 'tg-1']));
        expect(stateRunner.calls.single.join(' '), contains('tg-1#r1'));
      },
    );

    test('grid/rework refuses an unbound prefix without mutation', () async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(_snapshot(const [])),
        work: _Source(_snapshot(const [])),
        stateRunner: stateRunner,
        workRunner: workRunner,
      );

      final result = await handler(
        const GridCommandRequest.rework(beadId: 'other-1'),
      );

      expect(
        result,
        const GridCommandResult.refused(
          code: 'work_store_not_owned',
          message: 'No resident work store owns "other-1".',
        ),
      );
      expect(stateRunner.calls, isEmpty);
      expect(workRunner.calls, isEmpty);
    });

    test('grid/gate/resolve writes rulings before closing the gate', () async {
      final runner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-gate',
              issueType: IssueType.gate,
              metadata: {
                'node': 'route/committee',
                'blocks': 'tgdog-session',
                'rig': 'tg',
              },
            ),
            const Bead(
              id: 'tgdog-session',
              issueType: IssueType.session,
              metadata: {'rig': 'tg'},
            ),
          ]),
        ),
        work: _Source(_snapshot(const [])),
        stateRunner: runner,
        workRunner: _RecordingRunner(),
      );

      final result = await handler(
        const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'A'},
          rationale: 'operator inspected it',
        ),
      );

      expect(result, isA<GridCommandCompleted>());
      expect(runner.calls.map((call) => call.first), [
        'update',
        'update',
        'close',
      ]);
      expect(runner.calls.first.join(' '), contains('route/critic'));
    });

    test('back-to-back calls are serialized', () async {
      final runner = _RecordingRunner(blockFirst: true);
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-a',
              issueType: IssueType.gate,
              metadata: {'rig': 'tg'},
            ),
            const Bead(
              id: 'tgdog-b',
              issueType: IssueType.gate,
              metadata: {'rig': 'tg'},
            ),
          ]),
        ),
        work: _Source(_snapshot(const [])),
        stateRunner: runner,
        workRunner: _RecordingRunner(),
      );

      final first = handler(
        const GridCommandRequest.resolveGate(gateId: 'tgdog-a'),
      );
      final second = handler(
        const GridCommandRequest.resolveGate(gateId: 'tgdog-b'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(runner.calls, hasLength(1));
      runner.release();
      await Future.wait([first, second]);
      expect(runner.calls.where((call) => call.first == 'close'), hasLength(2));
    });
  });
}

ResidentGridCommandHandler _handler({
  required _Source state,
  required _Source work,
  required _RecordingRunner stateRunner,
  required _RecordingRunner workRunner,
}) {
  return ResidentGridCommandHandler(
    stateSource: state,
    refreshState: () async {},
    stateWriter: StationBeadWriter(
      bd: BdCliService(stateRunner),
      ownership: BeadOwnershipPredicate(const {'tg', 'tgdog'}),
    ),
    stateOwnership: BeadOwnershipPredicate(const {'tg', 'tgdog'}),
    workStoresByIdentity: {
      'tg': ResidentWorkCommandStore(
        source: work,
        refresh: () async {},
        writer: StationBeadWriter(
          bd: BdCliService(workRunner),
          ownership: BeadOwnershipPredicate(const {'tg'}),
        ),
      ),
    },
  );
}

GraphSnapshot _snapshot(Iterable<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

final class _Source implements SnapshotSource {
  _Source(this.current);

  @override
  final GraphSnapshot current;

  @override
  Stream<GraphSnapshot> get snapshots => const Stream.empty();
}

final class _RecordingRunner implements BdRunner {
  _RecordingRunner({this.blockFirst = false});

  final bool blockFirst;
  final calls = <List<String>>[];
  Completer<void>? _blocked;

  void release() => _blocked?.complete();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    if (blockFirst && calls.length == 1) {
      _blocked = Completer<void>();
      await _blocked!.future;
    }
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{}}',
      stderr: '',
    );
  }
}
