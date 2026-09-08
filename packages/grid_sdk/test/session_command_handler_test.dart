import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

const _root = RootCheckout(
  path: '/root',
  defaultBranch: 'main',
  substation: 'tg',
);

const _worktree1 = BeadWorktree(
  beadId: 'tg-1',
  path: '/root/.grid/worktrees/tg/tg-1',
  branch: 'grid/tg-1',
);

const _worktree2 = BeadWorktree(
  beadId: 'tg-2',
  path: '/root/.grid/worktrees/tg/tg-2',
  branch: 'grid/tg-2',
);

void main() {
  setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

  test(
    'grid/session/ls lists only closed held sessions with preserved worktrees',
    () async {
      var lists = 0;
      final harness = _harness(
        beads: [
          _heldSession(
            'tgdog-held-b',
            workBead: 'tg-2#r1',
            marker: SessionBeadKeys.escalation,
            reason: 'needs human ruling',
          ),
          _heldSession(
            'tgdog-held-a',
            workBead: 'tg-1',
            marker: SessionBeadKeys.reworkDeclined,
            reason: 'declined by operator',
          ),
          _heldSession('tgdog-no-worktree', workBead: 'tg-9'),
          const Bead(
            id: 'tgdog-done',
            issueType: GridIssueTypes.session,
            status: BeadStatus.closed,
            metadata: {
              'rig': 'tgdog',
              SessionBeadKeys.workBead: 'tg-3',
              SessionBeadKeys.outcome: 'complete',
            },
          ),
          _heldSession('tgdog-open', workBead: 'tg-4', closed: false),
        ],
        listBeadWorktrees: (_) async {
          lists++;
          return const [_worktree1, _worktree2];
        },
      );

      final result = await harness.handler(
        const GridCommandRequest.listHeldSessions(),
      );

      final rows = _rows(result);
      expect(lists, 1, reason: 'one listing per distinct mounted root');
      expect(rows.map((row) => row['sessionId']), [
        'tgdog-held-a',
        'tgdog-held-b',
      ]);
      expect(rows.first.keys, {
        'workBeadId',
        'sessionId',
        'worktree',
        'branch',
        'heldReason',
      });
      expect(
        rows.first,
        containsPair('heldReason', 'grid.rework_declined=declined by operator'),
      );
      expect(rows.last, containsPair('workBeadId', 'tg-2'));
      expect(rows.last, containsPair('branch', 'grid/tg-2'));
      harness.expectNoBdWrites();
    },
  );

  test(
    'grid/session/collect refuses uncertain or foreign targets before reap',
    () async {
      final base = <Bead>[
        _heldSession('tgdog-held', workBead: 'tg-1'),
        _heldSession('tgdog-open', workBead: 'tg-2', closed: false),
        const Bead(
          id: 'tgdog-done',
          issueType: GridIssueTypes.session,
          status: BeadStatus.closed,
          metadata: {
            'rig': 'tgdog',
            SessionBeadKeys.workBead: 'tg-3',
            SessionBeadKeys.outcome: 'complete',
          },
        ),
        const Bead(
          id: 'tgdog-task',
          issueType: IssueType.task,
          status: BeadStatus.closed,
          metadata: {'rig': 'tgdog'},
        ),
        _heldSession('other-held', workBead: 'tg-4', rig: 'other'),
        _heldSession('tgdog-foreign-work', workBead: 'other-1'),
      ];
      final cases =
          <
            ({
              String code,
              List<String> ids,
              bool bulk,
              List<Bead> extra,
              List<BeadWorktree>? worktrees,
            })
          >[
            (
              code: 'session_not_found',
              ids: const ['tgdog-missing'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'duplicate_session',
              ids: const ['tgdog-held', 'tgdog-held'],
              bulk: true,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'bulk_required',
              ids: const ['tgdog-held', 'tgdog-done'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'not_a_session',
              ids: const ['tgdog-task'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'session_not_closed',
              ids: const ['tgdog-open'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'session_not_held',
              ids: const ['tgdog-done'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'ownership_refused',
              ids: const ['other-held'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'work_store_not_owned',
              ids: const ['tgdog-foreign-work'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'worktree_probe_failed',
              ids: const ['tgdog-held'],
              bulk: false,
              extra: const [],
              worktrees: null,
            ),
            (
              code: 'worktree_not_found',
              ids: const ['tgdog-held'],
              bulk: false,
              extra: const [],
              worktrees: const [],
            ),
            (
              code: 'worktree_in_use',
              ids: const ['tgdog-held'],
              bulk: false,
              extra: [
                _heldSession(
                  'tgdog-successor',
                  workBead: 'tg-1#r2',
                  closed: false,
                ),
              ],
              worktrees: const [_worktree1],
            ),
          ];

      for (final testCase in cases) {
        var reaps = 0;
        final harness = _harness(
          beads: [...base, ...testCase.extra],
          listBeadWorktrees: (_) async => testCase.worktrees,
          reapWorktree:
              ({
                required root,
                required worktree,
                dryRun = false,
                overrideUnsafe = false,
              }) async {
                reaps++;
                return ReapOutcome.removed();
              },
        );

        final result = await harness.handler(
          GridCommandRequest.collectHeldSessions(
            sessionIds: testCase.ids,
            bulk: testCase.bulk,
          ),
        );

        expect(
          result,
          isA<GridCommandRefused>().having(
            (value) => value.code,
            'code',
            testCase.code,
          ),
          reason: 'case ${testCase.code}',
        );
        expect(reaps, 0, reason: '${testCase.code} must precede reap');
        harness.expectNoBdWrites();
      }
    },
  );

  test(
    'grid/session/collect previews, preflights bulk, and acts through one reap seam',
    () async {
      final sink = _CapturingSink();
      final calls = <({String beadId, bool dryRun, bool overrideUnsafe})>[];
      final harness = _harness(
        beads: [
          _heldSession('tgdog-b', workBead: 'tg-2'),
          _heldSession('tgdog-a', workBead: 'tg-1'),
        ],
        recorder: StationTrajectoryRecorder(sink: sink),
        listBeadWorktrees: (_) async => const [_worktree1, _worktree2],
        reapWorktree:
            ({
              required root,
              required worktree,
              dryRun = false,
              overrideUnsafe = false,
            }) async {
              calls.add((
                beadId: worktree.beadId,
                dryRun: dryRun,
                overrideUnsafe: overrideUnsafe,
              ));
              return dryRun
                  ? ReapOutcome.wouldRemove(
                      uncommitted: GateOutcome.present,
                      unpushed: GateOutcome.clear,
                      stashed: GateOutcome.clear,
                    )
                  : ReapOutcome.removed(uncommitted: GateOutcome.present);
            },
      );
      const request = GridCommandRequest.collectHeldSessions(
        sessionIds: ['tgdog-b', 'tgdog-a'],
        bulk: true,
        overrideUnsafe: true,
      );

      final preview = await harness.handler(request);
      expect(_rows(preview).map((row) => row['status']), [
        'would_collect',
        'would_collect',
      ]);
      expect(calls, [
        (beadId: 'tg-1', dryRun: true, overrideUnsafe: true),
        (beadId: 'tg-2', dryRun: true, overrideUnsafe: true),
      ]);
      expect(sink.records, isEmpty);

      calls.clear();
      final acted = await harness.handler(
        const GridCommandRequest.collectHeldSessions(
          sessionIds: ['tgdog-b', 'tgdog-a'],
          act: true,
          bulk: true,
          overrideUnsafe: true,
        ),
      );
      expect(_rows(acted).map((row) => row['status']), [
        'collected',
        'collected',
      ]);
      expect(calls, [
        (beadId: 'tg-1', dryRun: true, overrideUnsafe: true),
        (beadId: 'tg-2', dryRun: true, overrideUnsafe: true),
        (beadId: 'tg-1', dryRun: false, overrideUnsafe: true),
        (beadId: 'tg-2', dryRun: false, overrideUnsafe: true),
      ]);
      expect(
        sink.records.where((record) => record.recordType == 'worktree.reaped'),
        hasLength(2),
      );
      harness.expectNoBdWrites();
    },
  );

  test(
    'grid/session/collect refuses bulk before removing any target',
    () async {
      final calls = <({String beadId, bool dryRun})>[];
      final harness = _harness(
        beads: [
          _heldSession('tgdog-b', workBead: 'tg-2'),
          _heldSession('tgdog-a', workBead: 'tg-1'),
        ],
        listBeadWorktrees: (_) async => const [_worktree1, _worktree2],
        reapWorktree:
            ({
              required root,
              required worktree,
              dryRun = false,
              overrideUnsafe = false,
            }) async {
              calls.add((beadId: worktree.beadId, dryRun: dryRun));
              if (worktree.beadId == 'tg-2') {
                return ReapOutcome.refused(
                  uncommitted: GateOutcome.present,
                  unpushed: GateOutcome.clear,
                  stashed: GateOutcome.clear,
                  reason: 'uncommitted=present',
                );
              }
              return ReapOutcome.wouldRemove(
                uncommitted: GateOutcome.clear,
                unpushed: GateOutcome.clear,
                stashed: GateOutcome.clear,
              );
            },
      );

      final result = await harness.handler(
        const GridCommandRequest.collectHeldSessions(
          sessionIds: ['tgdog-b', 'tgdog-a'],
          act: true,
          bulk: true,
        ),
      );

      expect(
        result,
        isA<GridCommandRefused>()
            .having((value) => value.code, 'code', 'worktree_reap_refused')
            .having(
              (value) => value.message,
              'message',
              contains('uncommitted=present'),
            ),
      );
      expect(calls, [
        (beadId: 'tg-1', dryRun: true),
        (beadId: 'tg-2', dryRun: true),
      ]);
      harness.expectNoBdWrites();
    },
  );

  test('an acted collection refusal records worktree.held', () async {
    final sink = _CapturingSink();
    var calls = 0;
    final harness = _harness(
      beads: [_heldSession('tgdog-held', workBead: 'tg-1')],
      recorder: StationTrajectoryRecorder(sink: sink),
      listBeadWorktrees: (_) async => const [_worktree1],
      reapWorktree:
          ({
            required root,
            required worktree,
            dryRun = false,
            overrideUnsafe = false,
          }) async {
            calls++;
            if (dryRun) {
              return ReapOutcome.wouldRemove(
                uncommitted: GateOutcome.clear,
                unpushed: GateOutcome.clear,
                stashed: GateOutcome.clear,
              );
            }
            return ReapOutcome.refused(
              uncommitted: GateOutcome.present,
              unpushed: GateOutcome.clear,
              stashed: GateOutcome.clear,
              reason: 'changed after preflight',
            );
          },
    );

    final result = await harness.handler(
      const GridCommandRequest.collectHeldSessions(
        sessionIds: ['tgdog-held'],
        act: true,
      ),
    );

    expect(result, isA<GridCommandRefused>());
    expect(calls, 2);
    expect(
      sink.records.where((record) => record.recordType == 'worktree.held'),
      hasLength(1),
    );
    harness.expectNoBdWrites();
  });
}

List<Map<String, Object?>> _rows(GridCommandResult result) =>
    (((result as GridCommandCompleted).value['sessions']!) as List<Object?>)
        .cast<Map<String, Object?>>();

Bead _heldSession(
  String id, {
  required String workBead,
  String marker = SessionBeadKeys.escalation,
  String reason = 'operator hold',
  String rig = 'tgdog',
  bool closed = true,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': rig, SessionBeadKeys.workBead: workBead, marker: reason},
);

_Harness _harness({
  required List<Bead> beads,
  ListBeadWorktrees? listBeadWorktrees,
  ReapWorktree? reapWorktree,
  StationTrajectoryRecorder? recorder,
}) {
  final stateRunner = _RecordingRunner();
  final workRunner = _RecordingRunner();
  final workSource = _Source(_snapshot(const []));
  return _Harness(
    stateRunner: stateRunner,
    workRunner: workRunner,
    handler: StationCommandHandler(
      stateSource: _Source(_snapshot(beads)),
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
          root: '/work',
          source: workSource,
          refresh: () async {},
          writer: StationBeadWriter(
            bd: BdCliService(workRunner),
            reader: workRunner,
            ownership: BeadOwnershipPredicate(const {'tg'}),
          ),
        ),
      },
      listBeadWorktrees: listBeadWorktrees,
      reapWorktree: reapWorktree,
      workRootsByIdentity: const {'tg': _root},
      recorder: recorder,
    ),
  );
}

final class _Harness {
  const _Harness({
    required this.handler,
    required this.stateRunner,
    required this.workRunner,
  });

  final StationCommandHandler handler;
  final _RecordingRunner stateRunner;
  final _RecordingRunner workRunner;

  void expectNoBdWrites() {
    expect(stateRunner.calls, isEmpty, reason: 'A37 state writes forbidden');
    expect(workRunner.calls, isEmpty, reason: 'A37 work writes forbidden');
  }
}

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
  final List<List<String>> calls = [];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.of(args));
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{}}',
      stderr: '',
    );
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

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => records.add(record);
}
