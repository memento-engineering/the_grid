import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/src/actuator/actuator.dart';
import 'package:grid_reconciler/src/actuator/bd_actuator.dart';
import 'package:grid_reconciler/src/actuator/fake_actuator.dart';
import 'package:grid_reconciler/src/convergence/convergence_metadata.dart';
import 'package:grid_reconciler/src/convergence/reconciler_action.dart';
import 'package:grid_reconciler/src/convergence/reducer_event.dart';
import 'package:grid_reconciler/src/projections/convergence.dart';
import 'package:grid_reconciler/src/reducer/reduce_result.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';
import 'support/recording_bd_runner.dart';

Convergence conv(
  String id, [
  List<Bead> children = const [],
  List<BeadDependency> edges = const [],
]) {
  final root = convergenceBead(id);
  final beadsById = {
    for (final b in [root, ...children]) b.id: b,
  };
  return (Convergence.project(root, dependencies: edges, beadsById: beadsById)
          as ProjectionOk<Convergence>)
      .value;
}

Future<String?> _miss(String parent, String key) async => null;

void main() {
  group(
    'stopped: force-close is a CLOSE (counts), root close, commit LAST',
    () {
      test(
        'force-close uses manualSupersede, then terminal, root close, lpw',
        () async {
          final runner = RecordingBdRunner();
          final actuator = BdActuator(BdCliService(runner), _miss);

          final action =
              ReconcilerAction.stopped(
                    convergenceBeadId: 'gt-c',
                    actor: 'operator:nico',
                    totalIterations: 1,
                    lastProcessedWisp: 'gt-w1',
                    forceCloseWispId: 'gt-w1',
                    closeReason: CloseReasons.manualStop,
                  )
                  as StoppedAction;

          await actuator.apply(ReduceResult.one(action), conv('gt-c'));

          // TWO closes: the force-closed wisp (manualSupersede) then the root.
          final closes = runner.closes;
          expect(closes, hasLength(2));
          expect(closes[0][1], 'gt-w1'); // force-close the active wisp FIRST.
          expect(closes[1][1], 'gt-c'); // then the root.
          // The active wisp was CLOSED, never deleted (a force-closed iteration
          // counts toward deriveIterationCount).
          expect(runner.deletes, isEmpty);
          // last_processed_wisp is written AFTER the root close.
          final lpwCall = runner.calls.indexWhere(
            (c) =>
                c.first == 'update' &&
                c.contains('--metadata') &&
                c[c.indexOf('--metadata') + 1].contains(
                  '"${ConvergenceFields.lastProcessedWisp}"',
                ),
          );
          final rootCloseCall = runner.calls.lastIndexWhere(
            (c) => c.first == 'close',
          );
          expect(rootCloseCall, lessThan(lpwCall));
        },
      );
    },
  );

  group('failed: surfaces ActuationFailed with NO transition commit', () {
    test('a failed action throws and writes no last_processed_wisp', () async {
      final runner = RecordingBdRunner();
      final actuator = BdActuator(BdCliService(runner), _miss);

      final action = ReconcilerAction.failed(
        convergenceBeadId: 'gt-c',
        message: 'cannot approve bead "gt-c": state is "active"',
      );

      await expectLater(
        actuator.apply(ReduceResult.one(action), conv('gt-c')),
        throwsA(isA<ActuationFailed>()),
      );
      // No commit marker written — the same event re-processes safely.
      expect(
        runner.metadataWrites.where(
          (w) => w.metadata.containsKey(ConvergenceFields.lastProcessedWisp),
        ),
        isEmpty,
      );
    });

    test(
      'failed misconfig burns a valid pending wisp BEFORE the error',
      () async {
        final runner = RecordingBdRunner();
        final actuator = BdActuator(BdCliService(runner), _miss);

        // A speculative wisp to burn (trap 9).
        final w = wispBead('gt-w2', key: 'converge:gt-c:iter:2');
        final c = conv('gt-c', [w], [parentChild('gt-w2', 'gt-c')]);

        final action = ReconcilerAction.failed(
          convergenceBeadId: 'gt-c',
          message: 'condition mode requires a condition',
          burnWispId: 'gt-w2',
        );

        await expectLater(
          actuator.apply(ReduceResult.one(action), c),
          throwsA(isA<ActuationFailed>()),
        );
        // The pending wisp was DELETED (burned) before the error surfaced.
        expect(runner.deletes.map((d) => d[1]), contains('gt-w2'));
        expect(runner.closes, isEmpty);
      },
    );
  });

  group('skipped: only the already-terminated guard closes the root', () {
    test('closeRootBestEffort closes the root with handlerCleanup', () async {
      final runner = RecordingBdRunner();
      final actuator = BdActuator(BdCliService(runner), _miss);

      final action = ReconcilerAction.skipped(
        convergenceBeadId: 'gt-c',
        reason: SkipReason.alreadyTerminated,
        closeRootBestEffort: true,
      );

      await actuator.apply(ReduceResult.one(action), conv('gt-c'));

      expect(runner.closes.single[1], 'gt-c');
      expect(
        runner.closes.single,
        containsAllInOrder(['--reason', CloseReasons.handlerCleanup]),
      );
    });

    test('a plain skip (dedup) writes nothing at all', () async {
      final runner = RecordingBdRunner();
      final actuator = BdActuator(BdCliService(runner), _miss);

      final action = ReconcilerAction.skipped(
        convergenceBeadId: 'gt-c',
        reason: SkipReason.duplicateWisp,
        wispId: 'gt-w1',
      );

      await actuator.apply(ReduceResult.one(action), conv('gt-c'));
      expect(runner.calls, isEmpty);
    });
  });

  group('requeue is a pure carrier (no writes, surfaced to Track G)', () {
    test(
      'a requeue action writes nothing and is returned on the result',
      () async {
        final runner = RecordingBdRunner();
        final actuator = BdActuator(BdCliService(runner), _miss);

        final requeue =
            ReconcilerAction.requeue(
                  event: const ReducerEvent.operatorStop(
                    convergenceBeadId: 'gt-c',
                    user: 'nico',
                    postDrain: true,
                  ),
                  reason: 'operator stop deferred behind drain',
                )
                as RequeueAction;

        // A skipped + requeue (a minimal drain shape).
        final skip = ReconcilerAction.skipped(
          convergenceBeadId: 'gt-c',
          reason: SkipReason.duplicateWisp,
        );

        final out = await actuator.apply(
          ReduceResult([skip, requeue]),
          conv('gt-c'),
        );

        expect(out.requeue, same(requeue));
        // The requeue itself emitted no bd call.
        expect(runner.calls, isEmpty);
      },
    );
  });

  group('FakeActuator records the applied results (Track G harness)', () {
    test('records each result, action, and convergence', () async {
      final fake = FakeActuator(
        nextResult: const ActuationResult(pouredWispId: 'gt-x'),
      );
      final action = ReconcilerAction.skipped(
        convergenceBeadId: 'gt-c',
        reason: SkipReason.duplicateWisp,
      );

      final out = await fake.apply(ReduceResult.one(action), conv('gt-c'));

      expect(out.pouredWispId, 'gt-x');
      expect(fake.applied, hasLength(1));
      expect(fake.actions.single, action);
      expect(fake.convergences.single.id, 'gt-c');
      // nextResult is consumed after one apply.
      final out2 = await fake.apply(ReduceResult.one(action), conv('gt-c'));
      expect(out2.pouredWispId, isNull);
    });
  });
}
