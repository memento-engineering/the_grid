import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('resident command dispatch', () {
    setUp(BdCliService.resetGuardedWriteCapabilityForTesting);

    test('grid/bead/set routes an owned description through writer', () async {
      final stateRunner = _RecordingRunner();
      final workRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(_snapshot(const [])),
        work: _Source(_workSnapshot()),
        stateRunner: stateRunner,
        workRunner: workRunner,
      );

      final result = await handler(
        const GridCommandRequest.setBeadText(
          beadId: 'tg-1',
          field: OperatorBeadTextField.description,
          content: 'operator description',
        ),
      );

      expect(result, isA<GridCommandCompleted>());
      expect(
        workRunner.calls.single,
        containsAllInOrder(['update', 'tg-1', '--body-file', '-']),
      );
    });

    test('grid/bead/set maps ownership and snapshot refusals', () async {
      for (final entry in <(GridCommandRequest, GraphSnapshot?, String)>[
        (
          const GridCommandRequest.setBeadText(
            beadId: 'other-1',
            field: OperatorBeadTextField.description,
            content: 'text',
          ),
          _workSnapshot(),
          'work_store_not_owned',
        ),
        (
          const GridCommandRequest.setBeadText(
            beadId: 'tg-1',
            field: OperatorBeadTextField.description,
            content: 'text',
          ),
          null,
          'snapshot_unavailable',
        ),
      ]) {
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        await _expectRefused(
          _handler(
            state: _Source(_snapshot(const [])),
            work: _Source(entry.$2),
            stateRunner: stateRunner,
            workRunner: workRunner,
          ),
          entry.$1,
          code: entry.$3,
          stateRunner: stateRunner,
          workRunner: workRunner,
        );
      }
    });

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

    test(
      'grid/rework publishes its own retire and replay does not retire twice',
      () async {
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        final state = _Source(_snapshot([_session('tgdog-session')]));
        final work = _Source(_workSnapshot());
        addTearDown(state.dispose);
        addTearDown(work.dispose);

        var refreshes = 0;
        final emitted = <GraphSnapshot>[];
        final subscription = state.snapshots.listen(emitted.add);
        addTearDown(subscription.cancel);

        final handler = _handler(
          state: state,
          work: work,
          stateRunner: stateRunner,
          workRunner: workRunner,
          refreshState: () async {
            refreshes++;
            if (refreshes == 2) {
              state.push(
                _snapshot([_session('tgdog-session', workBead: 'tg-1#r1')]),
              );
            }
          },
        );

        final first = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );

        expect(first, isA<GridCommandCompleted>());
        expect(refreshes, 2);
        expect(
          emitted.single.beads.single.metadata[SessionBeadKeys.workBead],
          'tg-1#r1',
        );
        expect(_reworkUpdates(stateRunner), hasLength(1));

        final replay = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );
        expect(
          replay,
          isA<GridCommandRefused>().having(
            (value) => value.code,
            'code',
            'session_not_found',
          ),
        );
        expect(_reworkUpdates(stateRunner), hasLength(1));
        expect(emitted, hasLength(1));
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

    test('grid/rework retirement retires mount attempt in reverse-topological '
        'reap', () async {
      final stateRunner =
          _RecordingRunner(
              exportBeads: const [
                Bead(
                  id: 'tgdog-session',
                  issueType: GridIssueTypes.session,
                  metadata: {'work_bead': 'tg-1', 'rig': 'tgdog'},
                ),
              ],
            )
            ..openBeadsResult = const [
              Bead(
                id: 'tgdog-att1',
                issueType: GridIssueTypes.mountAttempt,
                metadata: {
                  StationBeadWriter.mountAttemptWorkBeadKey: 'tg-1',
                  StationBeadWriter.mountAttemptCountKey: '1',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-molecule',
                issueType: GridIssueTypes.molecule,
                metadata: {
                  StationBeadWriter.moleculeSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-prereq',
                issueType: GridIssueTypes.molecule,
                metadata: {
                  StationBeadWriter.moleculeSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-code',
                issueType: GridIssueTypes.step,
                metadata: {
                  StationBeadWriter.stepSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-decision',
                issueType: GridIssueTypes.step,
                metadata: {
                  StationBeadWriter.stepSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-route',
                issueType: GridIssueTypes.step,
                metadata: {
                  StationBeadWriter.stepSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
            ]
            ..exportDependencies = const [
              BeadDependency(
                issueId: 'tgdog-code',
                dependsOnId: 'tgdog-prereq',
                type: DependencyType.blocks,
              ),
              BeadDependency(
                issueId: 'tgdog-route',
                dependsOnId: 'tgdog-code',
                type: DependencyType.blocks,
              ),
              BeadDependency(
                issueId: 'tgdog-route',
                dependsOnId: 'tgdog-decision',
                type: DependencyType.blocks,
              ),
              BeadDependency(
                issueId: 'tgdog-code',
                dependsOnId: 'tgdog-molecule',
                type: DependencyType.parentChild,
              ),
              BeadDependency(
                issueId: 'tgdog-decision',
                dependsOnId: 'tgdog-molecule',
                type: DependencyType.parentChild,
              ),
              BeadDependency(
                issueId: 'tgdog-route',
                dependsOnId: 'tgdog-molecule',
                type: DependencyType.parentChild,
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
      expect(
        stateRunner.calls.where(
          (call) => call.length > 1 && call[0] == 'dep' && call[1] == 'list',
        ),
        hasLength(1),
      );
      final batch = stateRunner.calls.singleWhere(
        (call) => call.first == 'batch',
      );
      final script = stateRunner.stdins[stateRunner.calls.indexOf(batch)]!;
      expect(
        script.split('\n'),
        orderedEquals([
          'close tgdog-att1',
          'close tgdog-decision',
          'close tgdog-prereq',
          'close tgdog-code',
          'close tgdog-route',
          'close tgdog-molecule',
        ]),
      );
      expect(
        script.split('\n').where((line) => line == 'close tgdog-att1'),
        hasLength(1),
      );
      expect(batch, isNot(contains('--force')));
      expect(script, isNot(contains('--force')));
    });

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

    group('grid/rework — a PARTIAL molecule pour parks the same way '
        '(tg-xpgx)', () {
      /// The live shape: `applyGraph` LANDED every step bead, then the
      /// crumb-stamping loop threw. The session therefore carries a FULL
      /// `pending` cursor (no `grid.step.state` key reads back as
      /// `StepState.pending`) AND an open gate at the bare work-bead root.
      List<Bead> partialPour() => const [
        Bead(
          id: 'tgdog-session',
          issueType: GridIssueTypes.session,
          metadata: {
            'work_bead': 'tg-1',
            'rig': 'tgdog',
            SessionBeadKeys.model: kSessionModelMolecule,
          },
        ),
        Bead(
          id: 'tgdog-gate',
          issueType: GridIssueTypes.gate,
          metadata: {
            'rig': 'tgdog',
            'blocks': 'tgdog-session',
            'node': 'tg-1',
            'reason':
                'Molecule pour failed: BdTimeoutException: bd timed out '
                'after 15000ms: bd update --set-metadata grid.step.crumb',
          },
        ),
        Bead(
          id: 'tgdog-step-specify',
          issueType: GridIssueTypes.step,
          metadata: {
            'rig': 'tgdog',
            MoleculeStepKeys.path: 'tg-1/specify',
            MoleculeStepKeys.session: 'tgdog-session',
          },
        ),
        Bead(
          id: 'tgdog-step-build',
          issueType: GridIssueTypes.step,
          metadata: {
            'rig': 'tgdog',
            MoleculeStepKeys.path: 'tg-1/build',
            MoleculeStepKeys.session: 'tgdog-session',
          },
        ),
      ];

      _RecordingRunner reapableStateRunner() =>
          _RecordingRunner()
            ..openBeadsResult = const [
              Bead(
                id: 'tgdog-step-specify',
                issueType: GridIssueTypes.step,
                metadata: {
                  StationBeadWriter.stepSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
              Bead(
                id: 'tgdog-step-build',
                issueType: GridIssueTypes.step,
                metadata: {
                  StationBeadWriter.stepSessionKey: 'tgdog-session',
                  'rig': 'tgdog',
                },
              ),
            ];

      Future<GridCommandResult> rework(
        List<Bead> stateBeads, {
        _RecordingRunner? stateRunner,
      }) =>
          _handler(
            state: _Source(_snapshot(stateBeads)),
            work: _Source(_workSnapshot()),
            stateRunner: stateRunner ?? _RecordingRunner(),
            workRunner: _RecordingRunner(),
          )(
            const GridCommandRequest.rework(
              beadId: 'tg-1',
              note: 'recovered partial molecule pour',
            ),
          );

      Matcher notParked() => isA<GridCommandRefused>().having(
        (value) => value.code,
        'code',
        'session_not_parked',
      );

      test('ACCEPTS a partial pour: a FULL pending cursor, no gated step, an '
          'open gate at the bare work-bead root', () async {
        final stateRunner = reapableStateRunner();
        expect(
          await rework(partialPour(), stateRunner: stateRunner),
          isA<GridCommandCompleted>(),
          reason:
              'the open gate naming the session IS the park; a cursor of '
              'never-run pending steps is not a mid-flight session',
        );
        expect(_reworkUpdates(stateRunner), hasLength(1));
      });

      test('the partial pour\'s landed graph is REAPED by the retire — no '
          'orphan step beads, no hand-closing', () async {
        final stateRunner = reapableStateRunner();
        await rework(partialPour(), stateRunner: stateRunner);
        final batch = stateRunner.calls.singleWhere(
          (call) => call.first == 'batch',
        );
        final script = stateRunner.stdins[stateRunner.calls.indexOf(batch)]!;
        expect(
          script.split('\n'),
          containsAll(<String>[
            'close tgdog-step-specify',
            'close tgdog-step-build',
          ]),
        );
      });

      test('REFUSES a RUNNING step even under an open gate — the widening '
          'never retires a live round', () async {
        expect(
          await rework([
            ...partialPour(),
            Bead(
              id: 'tgdog-step-agent',
              issueType: GridIssueTypes.step,
              metadata: {
                'rig': 'tgdog',
                MoleculeStepKeys.path: 'tg-1/agent',
                MoleculeStepKeys.session: 'tgdog-session',
                MoleculeStepKeys.state: StepState.running.name,
              },
            ),
          ]),
          notParked(),
        );
      });

      test(
        'REFUSES a pending cursor with NO open gate naming the session',
        () async {
          expect(
            await rework(
              partialPour()
                  .where((bead) => bead.issueType != GridIssueTypes.gate)
                  .toList(growable: false),
            ),
            notParked(),
          );
        },
      );

      test('a COMMITTEE-shaped park is unchanged: a gated step under a '
          'review/route gate still retires', () async {
        final stateRunner = _RecordingRunner();
        expect(
          await rework([
            const Bead(
              id: 'tgdog-session',
              issueType: GridIssueTypes.session,
              metadata: {
                'work_bead': 'tg-1',
                'rig': 'tgdog',
                SessionBeadKeys.model: kSessionModelMolecule,
              },
            ),
            const Bead(
              id: 'tgdog-gate',
              issueType: GridIssueTypes.gate,
              metadata: {
                'rig': 'tgdog',
                'blocks': 'tgdog-session',
                'node': 'tg-1/review/route',
              },
            ),
            Bead(
              id: 'tgdog-step-route',
              issueType: GridIssueTypes.step,
              metadata: {
                'rig': 'tgdog',
                MoleculeStepKeys.path: 'tg-1/review/route',
                MoleculeStepKeys.session: 'tgdog-session',
                MoleculeStepKeys.state: StepState.gated.name,
              },
            ),
          ], stateRunner: stateRunner),
          isA<GridCommandCompleted>(),
        );
        expect(_reworkUpdates(stateRunner), hasLength(1));
      });
    });

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
            _session('tgdog-r1', workBead: 'tg-1#r1', reachedVerdict: true),
            _session('tgdog-r2', workBead: 'tg-1#r2', reachedVerdict: true),
            _session('tgdog-r3', workBead: 'tg-1#r3', reachedVerdict: true),
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

    test('three verdict-less retired rounds do not spend the cap', () async {
      final stateRunner = _RecordingRunner();
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
        workRunner: _RecordingRunner(),
      );

      expect(
        await handler(const GridCommandRequest.rework(beadId: 'tg-1')),
        isA<GridCommandCompleted>(),
      );
      expect(
        stateRunner.calls.expand((call) => call),
        contains('work_bead=tg-1#r4'),
      );
    });

    test(
      'lenny-749o (tg-9q58): one verdict and two infrastructure losses spend one round',
      () async {
        final stateRunner = _RecordingRunner();
        final handler = _handler(
          state: _Source(
            _snapshot([
              _session('tgdog-r1', workBead: 'tg-1#r1', reachedVerdict: true),
              _session('tgdog-r2', workBead: 'tg-1#r2'),
              _session('tgdog-r3', workBead: 'tg-1#r3'),
              _session('tgdog-current'),
            ]),
          ),
          work: _Source(_workSnapshot()),
          stateRunner: stateRunner,
          workRunner: _RecordingRunner(),
        );

        expect(
          await handler(const GridCommandRequest.rework(beadId: 'tg-1')),
          isA<GridCommandCompleted>(),
        );
        expect(
          stateRunner.calls.expand((call) => call),
          contains('work_bead=tg-1#r4'),
        );
      },
    );

    test('tg-fqif readiness hold regression', () async {
      final stateRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            _session('tgdog-fqif-r1', workBead: 'tg-fqif#r1', molecule: true),
            _resultStep('tgdog-fqif-r1-step', sessionId: 'tgdog-fqif-r1'),
            _session('tgdog-fqif-r2', workBead: 'tg-fqif#r2', molecule: true),
            _resultStep(
              'tgdog-fqif-r2-step',
              sessionId: 'tgdog-fqif-r2',
              capability: 'readiness',
              result: const {
                ResultKeys.grade: 'E',
                ResultKeys.routeVerdict: kRouteVerdictEscalate,
              },
            ),
            _session('tgdog-fqif-r3', workBead: 'tg-fqif#r3', molecule: true),
            _resultStep('tgdog-fqif-r3-step', sessionId: 'tgdog-fqif-r3'),
            _session('tgdog-fqif-current', workBead: 'tg-fqif', molecule: true),
          ]),
        ),
        work: _Source(_workSnapshot('tg-fqif')),
        stateRunner: stateRunner,
        workRunner: _RecordingRunner(),
      );

      expect(
        await handler(const GridCommandRequest.rework(beadId: 'tg-fqif')),
        isA<GridCommandCompleted>(),
      );
      expect(
        stateRunner.calls.expand((call) => call),
        contains('work_bead=tg-fqif#r4'),
      );
    });

    test('tg-8900 transport miss regression', () async {
      final stateRunner = _RecordingRunner();
      final handler = _handler(
        state: _Source(
          _snapshot([
            for (final round in [1, 2]) ...[
              _session(
                'eight-r$round',
                workBead: 'tg-8900#r$round',
                molecule: true,
              ),
              _resultStep('eight-r$round-step', sessionId: 'eight-r$round'),
            ],
            _session('eight-r3', workBead: 'tg-8900#r3', molecule: true),
            _resultStep(
              'eight-r3-step',
              sessionId: 'eight-r3',
              capability: 'readiness',
              result: const {
                ResultKeys.grade: 'D',
                ResultKeys.routeVerdict: kRouteVerdictEscalate,
              },
            ),
            _session('eight-r4', workBead: 'tg-8900#r4', molecule: true),
            _resultStep('eight-r4-step', sessionId: 'eight-r4'),
            _session('eight-current', workBead: 'tg-8900', molecule: true),
          ]),
        ),
        work: _Source(_workSnapshot('tg-8900')),
        stateRunner: stateRunner,
        workRunner: _RecordingRunner(),
      );

      final result = await handler(
        const GridCommandRequest.rework(beadId: 'tg-8900'),
      );
      expect(
        result,
        isA<GridCommandRefused>()
            .having(
              (value) => value.message,
              'message',
              contains('4 rounds retired'),
            )
            .having(
              (value) => value.message,
              'message',
              contains('3 reached a verdict'),
            )
            .having(
              (value) => value.message,
              'message',
              contains('#r3 (pre-dispatch route escalation)'),
            ),
      );
      expect(stateRunner.calls, isEmpty);
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
        final causeUpdate = runner.calls
            .where(
              (call) =>
                  call.first == 'update' &&
                  call.any(
                    (arg) =>
                        arg ==
                        '${StationBeadWriter.gateCloseCauseKey}='
                            '${GateCloseCause.adjudicated.wireValue}',
                  ),
            )
            .single;
        expect(
          causeUpdate,
          containsAll(<String>['--if-assignee', '--if-status']),
        );
        expect(runner.calls.last.join(' '), contains('operator ruling'));
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
      expect(runner.calls.map((call) => call.first), [
        'update',
        'update',
        'update',
        'close',
      ]);
      expect(
        runner.calls.skip(1).every((call) => call.contains('tgdog-gate')),
        isTrue,
      );
      expect(runner.calls.join(' '), isNot(contains('tgdog-session')));
      expect(runner.calls.join(' '), isNot(contains('grid.result.')));
      final causeUpdate = runner.calls.singleWhere(
        (call) => call.join(' ').contains('grid.gate.close_cause=adjudicated'),
      );
      expect(
        causeUpdate,
        containsAll(<String>['--if-assignee', '--if-status']),
      );
      expect(
        runner.calls.last.join(' '),
        contains('resolved via grid gate resolve'),
      );
      expect(
        gateCloseCauseOf(
          const Bead(
            id: 'historical-gate',
            issueType: GridIssueTypes.gate,
            status: BeadStatus.closed,
          ),
        ),
        GateCloseCause.unclassified,
      );
    });

    test('grid/gate/resolve converts a conditional guard mismatch', () async {
      final runner = _RecordingRunner(refuseConditionalGateUpdate: true);
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-gate',
              issueType: GridIssueTypes.gate,
              assignee: 'operator',
              status: BeadStatus.open,
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

      expect(
        result,
        isA<GridCommandRefused>().having(
          (value) => value.code,
          'code',
          'ownership_refused',
        ),
      );
      expect(runner.calls.map((call) => call.first), ['update', 'update']);
      expect(runner.calls.first, ['update', '--help']);
      expect(
        runner.calls.skip(1).every((call) => call.contains('tgdog-gate')),
        isTrue,
      );
      final guardedUpdate = runner.calls.skip(1).single;
      expect(
        guardedUpdate,
        containsAll(<String>['--if-assignee', '--if-status']),
      );
      expect(runner.calls.where((call) => call.first == 'close'), isEmpty);
    });

    test(
      'grid/rework refreshes state and work after the durable retire',
      () async {
        final state = _Source(null);
        final work = _Source(null);
        final stateRunner = _RecordingRunner();
        final workRunner = _RecordingRunner();
        var stateRefreshes = 0;
        var workRefreshes = 0;
        final handler = _handler(
          state: state,
          work: work,
          stateRunner: stateRunner,
          workRunner: workRunner,
          refreshState: () async {
            stateRefreshes++;
            if (stateRefreshes == 1) {
              state.current = _snapshot([_session('tgdog-session')]);
            } else {
              expect(_reworkUpdates(stateRunner), hasLength(1));
              state.current = _snapshot([
                _session('tgdog-session', workBead: 'tg-1#r1'),
              ]);
            }
          },
          refreshWork: () async {
            workRefreshes++;
            if (workRefreshes == 1) {
              work.current = _workSnapshot();
            } else {
              expect(_reworkUpdates(stateRunner), hasLength(1));
            }
          },
        );

        final result = await handler(
          const GridCommandRequest.rework(beadId: 'tg-1'),
        );

        expect(result, isA<GridCommandCompleted>());
        expect(stateRefreshes, 2);
        expect(workRefreshes, 2);
        expect(_reworkUpdates(stateRunner), hasLength(1));
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
          _session('tgdog-r1', workBead: 'tg-1#r1', reachedVerdict: true),
          _session('tgdog-r2', workBead: 'tg-1#r2', reachedVerdict: true),
          _session('tgdog-r3', workBead: 'tg-1#r3', reachedVerdict: true),
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
  group('W4 — attempt.round.retired at the rework re-key (§2.3)', () {
    /// Runs one `grid rework` under [sink] and asserts the LEGACY re-key
    /// landed — the fact every posture below must preserve.
    Future<void> rework(TrajectoryRecordSink sink) async {
      final stateRunner = _RecordingRunner();
      const workBead = Bead(
        id: 'tg-1',
        issueType: IssueType.task,
        metadata: {'rig': 'tg'},
      );
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
        work: _Source(_snapshot(const [workBead])),
        stateRunner: stateRunner,
        workRunner: _RecordingRunner(exportBeads: const [workBead]),
        recorder: StationTrajectoryRecorder(sink: sink),
      );
      expect(
        await handler(const GridCommandRequest.rework(beadId: 'tg-1')),
        isA<GridCommandCompleted>(),
      );
      // The record shadows this write; it never leads it.
      expect(stateRunner.calls.single.join(' '), contains('tg-1#r1'));
    }

    test(
      'the record names the round being RETIRED, not the fresh one',
      () async {
        final sink = _CapturingSink();
        await rework(sink);
        expect(sink.records.map((r) => r.recordType), [
          'attempt.round.retired',
        ]);
        final fact = {
          ...sink.records.single.correlationToJson(),
          ...sink.records.single.payloadToJson(),
        };
        expect(fact['session_id'], 'tgdog-session');
        // `#r1` is the round being MINTED, so round 0 is the one retired —
        // the same `old_round` SessionScope derives from the `#rN` key it
        // later observes, which is what makes the two sites dedupe to ONE
        // record on the shared `round-retired:<session>:<oldRound>` key.
        expect(fact['old_round'], 0);
        expect(fact['new_round'], 1);
        expect(fact['cause'], 'rework');
      },
    );

    test('NON-FATAL: a throwing recorder still retires the round', () async {
      await rework(_ThrowingSink());
    });
  });

  // ── the step dual read at the park check (cut-wiring C4, consumer 3) ─────
  //
  // `grid rework`'s park check is the one cursor consumer with NO
  // SessionProjection to hang a `trajCursor` on, so its posture arrives by
  // constructor. What the group proves is the pair the rollback story needs:
  // `observe` is byte-identical to today, and `primary` actually reads the
  // fold — through the ENGINE's merge, with the same three protections.
  group('grid/rework — the step dual read (C4)', () {
    Future<GridCommandResult> park({
      required StepState beadState,
      required List<StepCursorView> rows,
      DualReadMode mode = DualReadMode.observe,
      TrajectorySnapshotHealth health = TrajectorySnapshotHealth.live,
      DualReadAccounting? accounting,
    }) {
      final handler = _handler(
        state: _Source(
          _snapshot([
            const Bead(
              id: 'tgdog-session',
              issueType: GridIssueTypes.session,
              metadata: {
                'work_bead': 'tg-1',
                'rig': 'tgdog',
                'grid.session.model': 'molecule',
              },
            ),
            Bead(
              id: 'tgdog-step-build',
              issueType: GridIssueTypes.step,
              metadata: {
                'rig': 'tgdog',
                MoleculeStepKeys.path: 'build',
                MoleculeStepKeys.session: 'tgdog-session',
                MoleculeStepKeys.state: beadState.name,
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
        stateRunner: _RecordingRunner(),
        workRunner: _RecordingRunner(),
        stepSnapshot: () => _StepSnapshot(rows, health: health),
        dualReadMode: mode,
        dualReadAccounting: accounting,
      );
      return handler(const GridCommandRequest.rework(beadId: 'tg-1'));
    }

    Matcher notParked() => isA<GridCommandRefused>().having(
      (value) => value.code,
      'code',
      'session_not_parked',
    );

    test('OBSERVE reads the BEAD: a running step refuses, however the fold '
        'reads', () async {
      expect(
        await park(
          beadState: StepState.running,
          rows: [_StepRow(stepPath: 'build', stepState: 'gated')],
        ),
        notParked(),
        reason: 'config off = today, at this site as at the other six',
      );
    });

    test('PRIMARY serves the FOLD: the SAME inputs proceed, because P2 says '
        'the node parked', () async {
      expect(
        await park(
          beadState: StepState.running,
          rows: [_StepRow(stepPath: 'build', stepState: 'gated')],
          mode: DualReadMode.primary,
        ),
        isA<GridCommandCompleted>(),
      );
    });

    test('MONOTONE NO-DEMOTION holds here too: a bead-parked node is never '
        'un-parked by a lagging P2', () async {
      // Bead `gated`, P2 still `running`: the append-in-flight window at the
      // rearm's own persist site. Serving P2 would make the session look busy
      // and refuse a legitimate rework — the operator-visible face of a
      // demotion.
      expect(
        await park(
          beadState: StepState.gated,
          rows: [_StepRow(stepPath: 'build', stepState: 'running')],
          mode: DualReadMode.primary,
        ),
        isA<GridCommandCompleted>(),
      );
    });

    test('THE NEVER-CREATES RULE: a P2 node with no step bead is dropped and '
        'counted, never parked on', () async {
      final accounting = DualReadAccounting();
      expect(
        await park(
          beadState: StepState.gated,
          rows: [
            _StepRow(stepPath: 'build', stepState: 'gated'),
            _StepRow(stepPath: 'ghost', stepState: 'running'),
          ],
          mode: DualReadMode.primary,
          accounting: accounting,
        ),
        isA<GridCommandCompleted>(),
        reason: 'a phantom running node would refuse the rework',
      );
      expect(accounting.p2Orphan, 1);
    });

    test('THE IDENTITY RULE: a sibling session\'s rows never reach this '
        'check, and the miss is counted', () async {
      final accounting = DualReadAccounting();
      expect(
        await park(
          beadState: StepState.running,
          rows: [
            _StepRow(
              sessionId: 'tgdog-OTHER',
              stepPath: 'build',
              stepState: 'gated',
            ),
          ],
          mode: DualReadMode.primary,
          accounting: accounting,
        ),
        notParked(),
        reason: 'no same-session rows ⇒ the P2-miss rule, not a sibling splice',
      );
      expect(accounting.p2Miss, 1);
    });

    test('health non-live reads the bead — the disengage covers this site', () {
      expect(
        park(
          beadState: StepState.running,
          rows: [_StepRow(stepPath: 'build', stepState: 'gated')],
          mode: DualReadMode.primary,
          health: TrajectorySnapshotHealth.compromised,
        ),
        completion(notParked()),
      );
    });

    test('the boot\'s DISENGAGE LATCH covers this site too', () {
      expect(
        park(
          beadState: StepState.running,
          rows: [_StepRow(stepPath: 'build', stepState: 'gated')],
          mode: DualReadMode.primary,
          accounting: DualReadAccounting()..overlayDisengaged = true,
        ),
        completion(notParked()),
      );
    });
  });
}

/// One P2 row for the park check's snapshot (cut-wiring C4).
final class _StepRow implements StepCursorView {
  _StepRow({
    required this.stepPath,
    required this.stepState,
    this.sessionId = 'tgdog-session',
  });

  @override
  final String sessionId;
  @override
  int get round => 0;
  @override
  final String stepPath;
  @override
  int get stepRound => 0;
  @override
  final String stepState;
  @override
  int get incarnation => 0;
  @override
  String? get attemptId => null;
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => null;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  int get lastSeq => 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  _StepSnapshot(this._rows, {this.health = TrajectorySnapshotHealth.live});

  final List<StepCursorView> _rows;

  @override
  int get version => 11;
  @override
  final TrajectorySnapshotHealth health;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => [
    for (final row in _rows)
      if (row.sessionId == sessionId) row,
  ];
}

Bead _session(
  String id, {
  String workBead = 'tg-1',
  bool reachedVerdict = false,
  bool molecule = false,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.closed,
  metadata: {
    'rig': 'tgdog',
    'work_bead': workBead,
    if (molecule) SessionBeadKeys.model: kSessionModelMolecule,
    if (reachedVerdict) 'grid.result.route/committee.grade': 'F',
  },
);

Bead _resultStep(
  String id, {
  required String sessionId,
  String capability = 'spec-critic',
  Map<String, String> result = const {ResultKeys.grade: 'F'},
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.closed,
  metadata: {
    'rig': 'tgdog',
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.path: '$sessionId/review/$capability',
    MoleculeStepKeys.capability: capability,
    MoleculeStepKeys.state: StepState.complete.name,
    ...nodeResultMetadata('$sessionId/review/$capability', result),
  },
);

GraphSnapshot _workSnapshot([String id = 'tg-1']) => _snapshot([
  Bead(id: id, issueType: IssueType.task, metadata: const {'rig': 'tg'}),
]);

GraphSnapshot _gateSnapshot() => _snapshot([
  const Bead(
    id: 'tgdog-gate',
    issueType: GridIssueTypes.gate,
    metadata: {'node': 'route/committee', 'rig': 'tgdog'},
  ),
]);

List<List<String>> _reworkUpdates(_RecordingRunner runner) => runner.calls
    .where(
      (call) =>
          call.length > 1 &&
          call[0] == 'update' &&
          call[1] == 'tgdog-session' &&
          call.any((argument) => argument.contains('tg-1#r1')),
    )
    .toList(growable: false);

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
  StationTrajectoryRecorder? recorder,
  TrajectoryStepSnapshot Function()? stepSnapshot,
  DualReadMode dualReadMode = DualReadMode.observe,
  DualReadAccounting? dualReadAccounting,
}) => StationCommandHandler(
  stateSource: state,
  refreshState: refreshState ?? () async {},
  // CONSUMER 3 of the step dual read (cut-wiring C4) — the park check.
  stepSnapshot: stepSnapshot,
  dualReadMode: dualReadMode,
  dualReadAccounting: dualReadAccounting,
  stateWriter: StationBeadWriter(
    bd: BdCliService(stateRunner),
    reader: stateRunner,
    ownership: BeadOwnershipPredicate(stateWriterOwnership),
  ),
  stateOwnership: BeadOwnershipPredicate(stateOwnership),
  recorder: recorder,
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

/// Captures the observations `grid rework` derives (stage1-wiring §2.3's
/// `attempt.round.retired` row) — the command handler is one of that record's
/// two observation sites; `SessionScope`'s retired-round close is the other,
/// and the shared idem key is what merges them into ONE record.
final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => records.add(record);
}

/// The §3 worst case: an accepting sink that throws inside the enqueue.
final class _ThrowingSink implements TrajectoryRecordSink {
  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('sink refused');
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

  void push(GraphSnapshot snapshot) {
    current = snapshot;
    _controller.add(snapshot);
  }

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;

  Future<void> dispose() async {
    await _controller.close();
  }
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
    this.refuseConditionalGateUpdate = false,
    List<BdResult> results = const [],
    this.exportBeads = const [],
  }) : _results = List.of(results);

  final bool blockFirst;
  bool refuseConditionalGateUpdate;

  /// When set, a `batch` invocation throws — the reap-failure shape.
  bool throwOnBatch = false;
  final List<BdResult> _results;
  final List<Bead> exportBeads;
  List<BeadDependency> exportDependencies = const <BeadDependency>[];
  final calls = <List<String>>[];
  final stdins = <String?>[];
  Completer<void>? _blocked;

  void release() => _blocked?.complete();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List.unmodifiable(args));
    stdins.add(stdin);
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'dep' && args.length > 1 && args[1] == 'list') {
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': [
            for (final dependency in exportDependencies) dependency.toJson(),
          ],
        }),
        stderr: '',
      );
    }
    if (refuseConditionalGateUpdate &&
        args.length > 1 &&
        args[0] == 'update' &&
        args[1] == 'tgdog-gate' &&
        args.contains('--if-assignee') &&
        args.contains('--if-status')) {
      refuseConditionalGateUpdate = false;
      return const BdResult(
        exitCode: 13,
        stdout:
            '{"schema_version":1,"data":{"error":"conditional update refused","guard_mismatch":true}}',
        stderr: '',
      );
    }
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
