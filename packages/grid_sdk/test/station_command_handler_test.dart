import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('resident command dispatch', () {
    test('grid/gate/ls refreshes and returns sorted open gates only', () async {
      var refreshed = false;
      final state = _Source(_snapshot(const []));
      final handler = _handler(
        state: state,
        work: _Source(_snapshot(const [])),
        stateRunner: _RecordingRunner(),
        workRunner: _RecordingRunner(),
        refreshState: () async {
          refreshed = true;
          state.current = _snapshot([
            const Bead(id: 'tgdog-z', issueType: GridIssueTypes.gate),
            const Bead(
              id: 'tgdog-closed',
              issueType: GridIssueTypes.gate,
              status: BeadStatus.closed,
            ),
            const Bead(id: 'tgdog-a', issueType: GridIssueTypes.gate),
            const Bead(id: 'tgdog-task', issueType: IssueType.task),
          ]);
        },
      );

      final result = await handler(const GridCommandRequest.listGates());

      expect(refreshed, isTrue);
      final value = (result as GridCommandCompleted).value;
      expect(
        (value['gates']! as List<Object?>).cast<Map<String, Object?>>().map(
          (row) => row['id'],
        ),
        ['tgdog-a', 'tgdog-z'],
      );
    });

    test(
      'grid/rework re-keys a closed session through resident writers',
      () async {
        final stateRunner = _RecordingRunner();
        final operatorWorkBead = const Bead(
          id: 'tg-1',
          issueType: IssueType.task,
          design: 'operator design',
          acceptanceCriteria: 'operator acceptance',
          metadata: {'rig': 'tg'},
        );
        final workRunner = _RecordingRunner(exportBeads: [operatorWorkBead]);
        final work = _Source(_snapshot([operatorWorkBead]));
        final handler = _handler(
          state: _Source(
            _snapshot([
              const Bead(
                id: 'tgdog-session',
                issueType: GridIssueTypes.session,
                status: BeadStatus.closed,
                metadata: {'work_bead': 'tg-1', 'rig': 'tgdog'},
              ),
            ]),
          ),
          work: work,
          stateRunner: stateRunner,
          workRunner: workRunner,
        );

        final result = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );

        expect(result, isA<GridCommandCompleted>());
        expect(
          workRunner.calls.where((call) => call.first == 'export'),
          isEmpty,
        );
        expect(
          workRunner.calls.where(
            (call) =>
                call.first == 'update' &&
                (call.contains('--design') || call.contains('--acceptance')),
          ),
          isEmpty,
        );
        expect(stateRunner.calls.single.join(' '), contains('tg-1#r1'));
        expect(work.current!.beads.single.design, 'operator design');
        expect(
          work.current!.beads.single.acceptanceCriteria,
          'operator acceptance',
        );
      },
    );

    test('grid/rework routes a hyphenated work-store prefix', () async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-session',
              issueType: GridIssueTypes.session,
              status: BeadStatus.closed,
              metadata: {'work_bead': 'swift-infer-097', 'rig': 'tgdog'},
            ),
          ]),
        ),
        work: _Source(
          _snapshot([
            const Bead(
              id: 'swift-infer-097',
              issueType: IssueType.task,
              metadata: {'rig': 'swift-infer'},
            ),
          ]),
        ),
        stateRunner: stateRunner,
        workRunner: workRunner,
        workIdentity: 'swift-infer',
        workWriterOwnership: const {'swift-infer'},
      );

      final result = await handler(
        const GridCommandRequest.rework(
          beadId: 'swift-infer-097',
          note: 'retry',
        ),
      );

      expect(result, isA<GridCommandCompleted>());
      expect(
        workRunner.calls,
        contains(containsAll(['update', 'swift-infer-097'])),
      );
      expect(
        stateRunner.calls.single.join(' '),
        contains('swift-infer-097#r1'),
      );
    });

    test(
      'grid/rework REAPS the retired round\'s molecule (tg-ehht): every '
      'open step/molecule bead of the retired session is batch-closed',
      () async {
        final stateRunner = _RecordingRunner()
          ..openBeadsResult = const [
            Bead(
              id: 'tgdog-step-a',
              issueType: GridIssueTypes.step,
              metadata: {'grid.step.session': 'tgdog-session', 'rig': 'tgdog'},
            ),
            Bead(
              id: 'tgdog-step-b',
              issueType: GridIssueTypes.step,
              metadata: {'grid.step.session': 'tgdog-session', 'rig': 'tgdog'},
            ),
            Bead(
              id: 'tgdog-step-other',
              issueType: GridIssueTypes.step,
              metadata: {'grid.step.session': 'tgdog-OTHER', 'rig': 'tgdog'},
            ),
          ];
        final workRunner = _RecordingRunner();
        final handler = _handler(
          state: _Source(
            _snapshot([
              const Bead(
                id: 'tgdog-session',
                issueType: GridIssueTypes.session,
                status: BeadStatus.closed,
                metadata: {'work_bead': 'tg-1', 'rig': 'tgdog'},
              ),
            ]),
          ),
          work: _Source(
            _snapshot([
              const Bead(
                id: 'tg-1',
                issueType: IssueType.task,
                metadata: {'rig': 'tg'},
              ),
            ]),
          ),
          stateRunner: stateRunner,
          workRunner: workRunner,
        );

        final result = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1', note: 'retry'),
        );

        expect(result, isA<GridCommandCompleted>());
        final batch = stateRunner.calls.where((c) => c.first == 'batch');
        expect(
          batch,
          hasLength(1),
          reason:
              'the retire must collect the retired round\'s graph — the '
              'rework exit left 9,389 orphaned step beads by 2026-08-07',
        );
      },
    );

    test(
      'grid/rework accepts a POUR-PARKED session: no steps at all, an open '
      'gate blocking the session at the work-bead root (tg-aec park)',
      () async {
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        final handler = _handler(
          state: _Source(
            _snapshot([
              const Bead(
                id: 'tgdog-parked',
                issueType: GridIssueTypes.session,
                metadata: {
                  'work_bead': 'tg-1',
                  'rig': 'tgdog',
                  'grid.session.model': 'molecule',
                },
              ),
              const Bead(
                id: 'tgdog-gate',
                issueType: GridIssueTypes.gate,
                metadata: {
                  'rig': 'tgdog',
                  'blocks': 'tgdog-parked',
                  'node': 'tg-1',
                  'reason': 'Molecule pour failed: BdTimeoutException',
                },
              ),
            ]),
          ),
          work: _Source(
            _snapshot([
              const Bead(
                id: 'tg-1',
                issueType: IssueType.task,
                metadata: {'rig': 'tg'},
              ),
            ]),
          ),
          stateRunner: stateRunner,
          workRunner: workRunner,
        );

        final result = await handler(
          const GridCommandRequest.rework(
            beadId: 'tg-1',
            note: 'recovered failed molecule pour',
          ),
        );

        expect(
          result,
          isA<GridCommandCompleted>(),
          reason:
              'a pour-failure park has no gated STEP to find — refusing it '
              'made the OPERATIONS 2.3 runbook unexecutable (2026-08-06 live)',
        );
        expect(
          stateRunner.calls.any((c) => c.join(' ').contains('tg-1#r1')),
          isTrue,
        );
      },
    );

    test('a THROWING reap is non-fatal: the retire and the note both land, and '
        'the failure rides the result LOUD (2026-08-07 live: a reap exception '
        'ate the round\'s findings behind a generic 500)', () async {
      final stateRunner = _RecordingRunner()
        ..openBeadsResult = const [
          Bead(
            id: 'tgdog-step-a',
            issueType: GridIssueTypes.step,
            metadata: {'grid.step.session': 'tgdog-session', 'rig': 'tgdog'},
          ),
        ]
        ..throwOnBatch = true;
      final workRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-session',
              issueType: GridIssueTypes.session,
              status: BeadStatus.closed,
              metadata: {'work_bead': 'tg-1', 'rig': 'tgdog'},
            ),
          ]),
        ),
        work: _Source(
          _snapshot([
            const Bead(
              id: 'tg-1',
              issueType: IssueType.task,
              metadata: {'rig': 'tg'},
            ),
          ]),
        ),
        stateRunner: stateRunner,
        workRunner: workRunner,
      );

      final result = await handler(
        const GridCommandRequest.rework(beadId: 'tg-1', note: 'finding'),
      );

      expect(result, isA<GridCommandCompleted>());
      final value = (result as GridCommandCompleted).value;
      expect(value['reapFailure'], isNotNull);
      expect(
        stateRunner.calls.any((c) => c.join(' ').contains('tg-1#r1')),
        isTrue,
        reason: 'the retire landed despite the reap throw',
      );
      expect(
        workRunner.calls.any((c) => c.contains('--append-notes')),
        isTrue,
        reason: 'the operator finding landed BEFORE the reap could throw',
      );
    });

    test('beyond-cap header binds the request actor', () async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            _session('tgdog-r1', workBead: 'tg-1#r1'),
            _session('tgdog-r2', workBead: 'tg-1#r2'),
            _session('tgdog-r3', workBead: 'tg-1#r3'),
            _session('tgdog-current'),
          ]),
        ),
        work: _Source(_workSnapshot()),
        stateRunner: stateRunner,
        workRunner: workRunner,
      );

      final result = await handler(
        const GridCommandRequest.rework(
          beadId: 'tg-1',
          beyondCap: true,
          actor: 'Nico',
          note: 'operator approved round four',
        ),
      );

      expect(result, isA<GridCommandCompleted>());
      final noteWrite = workRunner.calls.singleWhere(
        (call) => call.contains('--append-notes'),
      );
      expect(noteWrite.join(' '), contains('ROUND 4'));
      expect(noteWrite.join(' '), contains('BEYOND-CAP by Nico'));
      expect(noteWrite.join(' '), contains('operator approved round four'));
    });

    test(
      'grid/gate/resolve normalizes override metadata before close',
      () async {
        final runner = _RecordingRunner();
        final handler = _handler(
          state: _Source(
            _snapshot([
              const Bead(
                id: 'tgdog-gate',
                issueType: GridIssueTypes.gate,
                metadata: {
                  'node': 'route/committee',
                  'blocks': 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              const Bead(
                id: 'tgdog-session',
                issueType: GridIssueTypes.session,
                metadata: {'rig': 'tgdog'},
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
            grades: {' critic ': ' a '},
            rationale: '  operator inspected it  ',
          ),
        );

        expect(result, isA<GridCommandCompleted>());
        expect(runner.calls.map((call) => call.first), [
          'update',
          'update',
          'close',
        ]);
        final ruling = runner.calls.first.join(' ');
        // The node-path infix rides the tg-6e4j key encoding ('/' → '_s') so
        // the ruling write fits bd's metadata-key charset.
        expect(ruling, contains('grid.result.route_scritic.grade=A'));
        expect(ruling, contains('grid.result.route_scritic.transport'));
        expect(ruling, contains('operator-ruling'));
        expect(ruling, contains('grid.result.route_scritic.rationale'));
        expect(ruling, contains('operator inspected it'));
      },
    );

    test('grid/gate/resolve without grades closes only the gate', () async {
      final runner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-gate',
              issueType: GridIssueTypes.gate,
              metadata: {'rig': 'tgdog'},
            ),
          ]),
        ),
        work: _Source(_snapshot(const [])),
        stateRunner: runner,
        workRunner: _RecordingRunner(),
      );

      final result = await handler(
        const GridCommandRequest.resolveGate(gateId: 'tgdog-gate'),
      );

      expect(result, isA<GridCommandCompleted>());
      expect(runner.calls.map((call) => call.first), ['update', 'close']);
      expect(runner.calls.every((call) => call.contains('tgdog-gate')), isTrue);
      expect(runner.calls.join(' '), isNot(contains('tgdog-session')));
      expect(runner.calls.join(' '), isNot(contains('grid.result.')));
    });

    test(
      'grid/rework refresh callbacks supply snapshots before dispatch reads',
      () async {
        final state = _Source(null);
        final work = _Source(null);
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        final handler = _handler(
          state: state,
          work: work,
          stateRunner: stateRunner,
          workRunner: workRunner,
          refreshState: () async {
            state.current = _snapshot([
              const Bead(
                id: 'tgdog-session',
                issueType: GridIssueTypes.session,
                status: BeadStatus.closed,
                metadata: {'work_bead': 'tg-1', 'rig': 'tgdog'},
              ),
            ]);
          },
          refreshWork: () async {
            work.current = _snapshot([
              const Bead(
                id: 'tg-1',
                issueType: IssueType.task,
                metadata: {'rig': 'tg'},
              ),
            ]);
          },
        );

        final result = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );

        expect(result, isA<GridCommandCompleted>());
        expect(stateRunner.calls, hasLength(1));
        expect(workRunner.calls, isEmpty);
      },
    );

    test('back-to-back calls are serialized', () async {
      final runner = _RecordingRunner(blockFirst: true);
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-a',
              issueType: GridIssueTypes.gate,
              metadata: {'rig': 'tgdog'},
            ),
            const Bead(
              id: 'tgdog-b',
              issueType: GridIssueTypes.gate,
              metadata: {'rig': 'tgdog'},
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

  group('grid/rework refusals', () {
    Future<void> refused({
      required GraphSnapshot? state,
      required GraphSnapshot? work,
      required String code,
      GridCommandRequest request = const GridCommandRequest.rework(
        beadId: 'tg-1',
      ),
      Set<String> workWriterOwnership = const {'tg'},
    }) async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      await _expectRefused(
        _handler(
          state: _Source(state),
          work: _Source(work),
          stateRunner: stateRunner,
          workRunner: workRunner,
          workWriterOwnership: workWriterOwnership,
        ),
        request,
        code: code,
        stateRunner: stateRunner,
        workRunner: workRunner,
      );
    }

    test('unowned work-store prefix', () async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      await _expectRefused(
        _handler(
          state: _Source(_snapshot(const [])),
          work: _Source(_snapshot(const [])),
          stateRunner: stateRunner,
          workRunner: workRunner,
        ),
        const GridCommandRequest.rework(beadId: 'other-1'),
        code: 'work_store_not_owned',
        stateRunner: stateRunner,
        workRunner: workRunner,
      );
    });
    test(
      'missing resident snapshot',
      () => refused(
        state: null,
        work: _snapshot(const []),
        code: 'snapshot_unavailable',
      ),
    );
    test(
      'missing work bead',
      () => refused(
        state: _snapshot(const []),
        work: _snapshot(const []),
        code: 'work_bead_missing',
      ),
    );
    test(
      'no linked session',
      () => refused(
        state: _snapshot(const []),
        work: _workSnapshot(),
        code: 'session_not_found',
      ),
    );
    test(
      'multiple linked sessions',
      () => refused(
        state: _snapshot([_session('tgdog-a'), _session('tgdog-b')]),
        work: _workSnapshot(),
        code: 'session_ambiguous',
      ),
    );
    test(
      'open session not parked at a gate',
      () => refused(
        state: _snapshot([
          const Bead(
            id: 'tgdog-session',
            issueType: GridIssueTypes.session,
            metadata: {'work_bead': 'tg-1', 'grid.session.model': 'flat'},
          ),
        ]),
        work: _workSnapshot(),
        code: 'session_not_parked',
      ),
    );
    test(
      'rework round cap reached',
      () => refused(
        state: _snapshot([
          _session('tgdog-r1', workBead: 'tg-1#r1'),
          _session('tgdog-r2', workBead: 'tg-1#r2'),
          _session('tgdog-r3', workBead: 'tg-1#r3'),
          _session('tgdog-current'),
        ]),
        work: _workSnapshot(),
        code: 'rework_round_cap',
      ),
    );
    test(
      'beyond-cap requires actor first',
      () => refused(
        state: _snapshot(const []),
        work: _snapshot(const []),
        request: const GridCommandRequest.rework(
          beadId: 'tg-1',
          beyondCap: true,
          note: 'approved',
        ),
        code: 'actor_required',
      ),
    );
    test(
      'beyond-cap requires note after actor',
      () => refused(
        state: _snapshot(const []),
        work: _snapshot(const []),
        request: const GridCommandRequest.rework(
          beadId: 'tg-1',
          beyondCap: true,
          actor: 'Nico',
        ),
        code: 'note_required',
      ),
    );
    test(
      'beyond-cap is premature below round cap',
      () => refused(
        state: _snapshot([_session('tgdog-current')]),
        work: _workSnapshot(),
        request: const GridCommandRequest.rework(
          beadId: 'tg-1',
          beyondCap: true,
          actor: 'Nico',
          note: 'approved',
        ),
        code: 'beyond_cap_premature',
      ),
    );
    test(
      'writer rejects ownership',
      () => refused(
        state: _snapshot([_session('tgdog-session')]),
        work: _workSnapshot(),
        code: 'ownership_refused',
        workWriterOwnership: const {'other'},
      ),
    );
  });

  group('grid/gate/resolve refusals', () {
    Future<void> refused({
      required GraphSnapshot? snapshot,
      required GridCommandRequest request,
      required String code,
      Set<String> stateOwnership = const {'tg', 'tgdog'},
      Set<String> stateWriterOwnership = const {'tg', 'tgdog'},
    }) async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      await _expectRefused(
        _handler(
          state: _Source(snapshot),
          work: _Source(_snapshot(const [])),
          stateRunner: stateRunner,
          workRunner: workRunner,
          stateOwnership: stateOwnership,
          stateWriterOwnership: stateWriterOwnership,
        ),
        request,
        code: code,
        stateRunner: stateRunner,
        workRunner: workRunner,
      );
    }

    test(
      'missing state snapshot',
      () => refused(
        snapshot: null,
        request: const GridCommandRequest.resolveGate(gateId: 'tgdog-gate'),
        code: 'snapshot_unavailable',
      ),
    );
    test(
      'unknown gate id',
      () => refused(
        snapshot: _snapshot(const []),
        request: const GridCommandRequest.resolveGate(gateId: 'tgdog-gate'),
        code: 'gate_not_found',
      ),
    );
    test(
      'target is not a gate',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'tgdog-gate',
            issueType: IssueType.task,
            metadata: {'rig': 'tgdog'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(gateId: 'tgdog-gate'),
        code: 'not_a_gate',
      ),
    );
    test(
      'gate is already closed',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'tgdog-gate',
            issueType: GridIssueTypes.gate,
            status: BeadStatus.closed,
            metadata: {'rig': 'tgdog'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(gateId: 'tgdog-gate'),
        code: 'gate_closed',
      ),
    );
    test(
      'gate is outside station ownership',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'other-gate',
            issueType: GridIssueTypes.gate,
            metadata: {'rig': 'other'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(gateId: 'other-gate'),
        code: 'ownership_refused',
      ),
    );
    test(
      'grade is outside A through F',
      () => refused(
        snapshot: _gateSnapshot(),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'G'},
        ),
        code: 'invalid_grade',
      ),
    );
    test(
      'bare lane has no parked node',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'tgdog-gate',
            issueType: GridIssueTypes.gate,
            metadata: {'rig': 'tgdog'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'A'},
        ),
        code: 'lane_unresolvable',
      ),
    );
    test(
      'grade override has no rationale',
      () => refused(
        snapshot: _gateSnapshot(),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'A'},
          rationale: '  ',
        ),
        code: 'rationale_required',
      ),
    );
    test(
      'grade override has no blocked session',
      () => refused(
        snapshot: _gateSnapshot(),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'A'},
          rationale: 'operator ruling',
        ),
        code: 'session_not_found',
      ),
    );
    test(
      'unruled feeding F remains',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'tgdog-gate',
            issueType: GridIssueTypes.gate,
            metadata: {
              'node': 'route/committee',
              'blocks': 'tgdog-session',
              'rig': 'tgdog',
            },
          ),
          const Bead(
            id: 'tgdog-session',
            issueType: GridIssueTypes.session,
            metadata: {'rig': 'tgdog', 'grid.result.route/critic.grade': 'F'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'reviewer': 'A'},
          rationale: 'override reviewer only',
        ),
        code: 'feeding_grade_f',
      ),
    );
    test(
      'state writer rejects ownership',
      () => refused(
        snapshot: _snapshot([
          const Bead(
            id: 'tgdog-gate',
            issueType: GridIssueTypes.gate,
            metadata: {
              'node': 'route/committee',
              'blocks': 'tgdog-session',
              'rig': 'tgdog',
            },
          ),
          const Bead(
            id: 'tgdog-session',
            issueType: GridIssueTypes.session,
            metadata: {'rig': 'tgdog'},
          ),
        ]),
        request: const GridCommandRequest.resolveGate(
          gateId: 'tgdog-gate',
          grades: {'critic': 'A'},
          rationale: 'operator ruling',
        ),
        code: 'ownership_refused',
        stateWriterOwnership: const {'other'},
      ),
    );
  });
}

Bead _session(String id, {String workBead = 'tg-1'}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.closed,
  metadata: {'work_bead': workBead},
);

GraphSnapshot _workSnapshot() => _snapshot([
  const Bead(id: 'tg-1', issueType: IssueType.task, metadata: {'rig': 'tg'}),
]);

GraphSnapshot _gateSnapshot() => _snapshot([
  const Bead(
    id: 'tgdog-gate',
    issueType: GridIssueTypes.gate,
    metadata: {'node': 'route/committee', 'rig': 'tgdog'},
  ),
]);

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
  Future<void> Function()? refreshState,
  Future<void> Function()? refreshWork,
  Set<String> stateOwnership = const {'tg', 'tgdog'},
  Set<String> stateWriterOwnership = const {'tg', 'tgdog'},
  Set<String> workWriterOwnership = const {'tg'},
  String workIdentity = 'tg',
}) => StationCommandHandler(
  stateSource: state,
  refreshState: refreshState ?? () async {},
  stateWriter: StationBeadWriter(
    bd: BdCliService(stateRunner),
    reader: stateRunner,
    ownership: BeadOwnershipPredicate(stateWriterOwnership),
  ),
  stateOwnership: BeadOwnershipPredicate(stateOwnership),
  workStoresByIdentity: {
    workIdentity: WorkCommandStore(
      source: work,
      refresh: refreshWork ?? () async {},
      writer: StationBeadWriter(
        bd: BdCliService(workRunner),
        reader: workRunner,
        ownership: BeadOwnershipPredicate(workWriterOwnership),
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

  @override
  GraphSnapshot? current;

  @override
  Stream<GraphSnapshot> get snapshots => const Stream.empty();
}

final class _RecordingRunner implements BdRunner, BeadProbeReader {
  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    final matches = exportBeads.where(
      (bead) => bead.id == id && types.contains(bead.issueType),
    );
    return matches.isEmpty ? null : matches.single;
  }

  /// Beads served to [openBeads] scans (e.g. `reapMolecule`'s collection
  /// probe), filtered by [types] + every [metadataAll] pair like the real
  /// probe reader.
  List<Bead> openBeadsResult = const [];

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => [
    for (final bead in openBeadsResult)
      if (types.contains(bead.issueType) &&
          metadataAll.entries.every(
            (e) => (bead.metadata[e.key] ?? '') == e.value,
          ))
        bead,
  ];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
  _RecordingRunner({
    this.blockFirst = false,
    List<BdResult> results = const [],
    this.exportBeads = const [],
  }) : _results = List.of(results);

  final bool blockFirst;

  /// When set, a `batch` invocation throws — the reap-failure shape.
  bool throwOnBatch = false;
  final List<BdResult> _results;
  final List<Bead> exportBeads;
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
    if (throwOnBatch && args.isNotEmpty && args.first == 'batch') {
      throw StateError('fake batch refused');
    }
    if (blockFirst && calls.length == 1) {
      _blocked = Completer<void>();
      await _blocked!.future;
    }
    if (args.isNotEmpty && args.first == 'export') {
      return BdResult(
        exitCode: 0,
        stdout: exportBeads.map((bead) => jsonEncode(bead.toJson())).join('\n'),
        stderr: '',
      );
    }
    return _results.isEmpty
        ? const BdResult(
            exitCode: 0,
            stdout: '{"schema_version":1,"data":{}}',
            stderr: '',
          )
        : _results.removeAt(0);
  }
}
