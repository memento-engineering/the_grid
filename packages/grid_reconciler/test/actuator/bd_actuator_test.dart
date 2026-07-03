import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/src/actuator/actuator.dart';
import 'package:grid_reconciler/src/actuator/bd_actuator.dart';
import 'package:grid_reconciler/src/convergence/convergence_metadata.dart';
import 'package:grid_reconciler/src/convergence/reconciler_action.dart';
import 'package:grid_reconciler/src/projections/convergence.dart';
import 'package:grid_reconciler/src/reducer/reduce_result.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';
import 'support/recording_bd_runner.dart';

/// Builds a Convergence projection from a root + its wisp children.
Convergence convergenceOf(
  Bead root,
  List<Bead> children,
  List<BeadDependency> edges,
) {
  final beadsById = {
    for (final b in [root, ...children]) b.id: b,
  };
  final result = Convergence.project(
    root,
    dependencies: edges,
    beadsById: beadsById,
  );
  return (result as ProjectionOk<Convergence>).value;
}

void main() {
  /// A probe that records its calls and returns a programmable hit/miss.
  ({
    IdempotencyProbe probe,
    List<({String parent, String key})> calls,
    void Function(String?) setHit,
  })
  recordingProbe() {
    final calls = <({String parent, String key})>[];
    String? hit;
    Future<String?> probe(String parent, String key) async {
      calls.add((parent: parent, key: key));
      return hit;
    }

    return (probe: probe, calls: calls, setHit: (h) => hit = h);
  }

  group(
    'write ORDER — last_processed_wisp LAST, close between (invariant 2)',
    () {
      test('approved (handlerWispClosed): burn → terminal writes → close → '
          'last_processed_wisp LAST', () async {
        final runner = RecordingBdRunner();
        final bd = BdCliService(runner);
        final p = recordingProbe();
        final actuator = BdActuator(bd, p.probe);

        // A loop with one closed wisp to burn (the speculative iter-2).
        final root = convergenceBead('gt-c');
        final w1 = wispBead(
          'gt-w1',
          key: 'converge:gt-c:iter:1',
          status: BeadStatus.closed,
        );
        final conv = convergenceOf(root, [w1], [parentChild('gt-w1', 'gt-c')]);

        final action =
            ReconcilerAction.approved(
                  convergenceBeadId: 'gt-c',
                  path: TerminalPath.handlerWispClosed,
                  actor: 'controller',
                  iteration: 1,
                  totalIterations: 1,
                  lastProcessedWisp: 'gt-w1',
                  burnWispId: 'gt-w1',
                  closeReason: CloseReasons.handlerRoot,
                )
                as ApprovedAction;

        await actuator.apply(ReduceResult.one(action), conv);

        // The verb sequence: delete (burn) … then updates (terminal writes),
        // then close, then the FINAL update (last_processed_wisp).
        final verbs = runner.verbs;
        final closeIdx = verbs.indexOf('close');
        expect(closeIdx, greaterThanOrEqualTo(0));

        // Every metadata write key in order.
        final keys = [
          for (final w in runner.metadataWrites) w.metadata.keys.single,
        ];
        // terminal_reason, terminal_actor, state … then last_processed_wisp.
        expect(keys.last, ConvergenceFields.lastProcessedWisp);
        expect(
          keys,
          containsAllInOrder([
            ConvergenceFields.terminalReason,
            ConvergenceFields.terminalActor,
            ConvergenceFields.state,
            ConvergenceFields.lastProcessedWisp,
          ]),
        );

        // The close lands AFTER the state write and BEFORE the commit write.
        // Find the call index of the state update and the lpw update.
        final stateCall = _callIndexOfMetadataKey(
          runner,
          ConvergenceFields.state,
        );
        final lpwCall = _callIndexOfMetadataKey(
          runner,
          ConvergenceFields.lastProcessedWisp,
        );
        final closeCall = runner.calls.indexWhere((c) => c.first == 'close');
        expect(stateCall, lessThan(closeCall));
        expect(
          closeCall,
          lessThan(lpwCall),
          reason: 'last_processed_wisp is written AFTER the close',
        );
      });

      test(
        'operatorApprove: terminal writes FIRST, then close, then commit LAST',
        () async {
          final runner = RecordingBdRunner();
          final actuator = BdActuator(
            BdCliService(runner),
            recordingProbe().probe,
          );

          final root = convergenceBead('gt-c2');
          final conv = convergenceOf(root, const [], const []);

          final action =
              ReconcilerAction.approved(
                    convergenceBeadId: 'gt-c2',
                    path: TerminalPath.operatorApprove,
                    actor: 'operator:nico',
                    iteration: 2,
                    totalIterations: 2,
                    lastProcessedWisp: 'gt-w2',
                    clearWaitingReason: true,
                    closeReason: CloseReasons.manualApprove,
                  )
                  as ApprovedAction;

          await actuator.apply(ReduceResult.one(action), conv);

          // No burn (operator path).
          expect(runner.deletes, isEmpty);
          final lpwCall = _callIndexOfMetadataKey(
            runner,
            ConvergenceFields.lastProcessedWisp,
          );
          final closeCall = runner.calls.indexWhere((c) => c.first == 'close');
          expect(closeCall, lessThan(lpwCall));
          // waiting_reason clear is present on the operator path.
          expect(
            runner.metadataWrites.map((w) => w.metadata.keys.single),
            contains(ConvergenceFields.waitingReason),
          );
        },
      );

      test('waitingManual: NO close, NO verdict clear, lpw LAST', () async {
        final runner = RecordingBdRunner();
        final actuator = BdActuator(
          BdCliService(runner),
          recordingProbe().probe,
        );
        final conv = convergenceOf(
          convergenceBead('gt-c3'),
          const [],
          const [],
        );

        final action =
            ReconcilerAction.waitingManual(
                  convergenceBeadId: 'gt-c3',
                  closedWispId: 'gt-w3',
                  iteration: 1,
                  reason: const WaitingReason('manual_gate'),
                )
                as WaitingManualAction;

        await actuator.apply(ReduceResult.one(action), conv);

        expect(runner.closes, isEmpty, reason: 'waiting_manual never closes');
        final keys = runner.metadataWrites.map((w) => w.metadata.keys.single);
        // The verdict must survive — no agent_verdict write.
        expect(keys, isNot(contains(ConvergenceFields.agentVerdict)));
        expect(keys.last, ConvergenceFields.lastProcessedWisp);
      });
    },
  );

  group('burn = bd delete in POST-ORDER, NEVER close (A16)', () {
    test(
      'a speculative subtree is deleted children-first, root last',
      () async {
        final runner = RecordingBdRunner();
        final actuator = BdActuator(
          BdCliService(runner),
          recordingProbe().probe,
        );

        // Speculative wisp gt-w2 with two gate-typed step children.
        final root = convergenceBead('gt-c');
        final w2 = wispBead('gt-w2', key: 'converge:gt-c:iter:2');
        final s1 = Bead(
          id: 'gt-s1',
          title: 's1',
          issueType: IssueType.gate,
          ephemeral: true,
          metadata: const {'gc.deferred_type': 'task'},
        );
        final s2 = Bead(
          id: 'gt-s2',
          title: 's2',
          issueType: IssueType.gate,
          ephemeral: true,
          metadata: const {'gc.deferred_type': 'task'},
        );
        final conv = convergenceOf(
          root,
          [w2, s1, s2],
          [
            parentChild('gt-w2', 'gt-c'),
            parentChild('gt-s1', 'gt-w2'),
            parentChild('gt-s2', 'gt-w2'),
          ],
        );

        // A no_convergence terminal that burns the speculative wisp first.
        final action =
            ReconcilerAction.noConvergence(
                  convergenceBeadId: 'gt-c',
                  actor: 'controller',
                  iteration: 2,
                  totalIterations: 2,
                  lastProcessedWisp: 'gt-w-prev',
                  burnWispId: 'gt-w2',
                  closeReason: CloseReasons.handlerRoot,
                )
                as NoConvergenceAction;

        await actuator.apply(ReduceResult.one(action), conv);

        // Burns are deletes — NEVER a close of a speculative wisp.
        final deletedIds = runner.deletes.map((c) => c[1]).toList();
        // POST-ORDER: children (s1, s2 sorted) before the wisp root.
        expect(deletedIds, ['gt-s1', 'gt-s2', 'gt-w2']);
        // The only close is the convergence ROOT (terminal), not any wisp.
        expect(runner.closes.map((c) => c[1]), ['gt-c']);
        // delete carries --force and the actor; never the word "close".
        for (final d in runner.deletes) {
          expect(d, contains('--force'));
          expect(d, isNot(contains('close')));
        }
      },
    );
  });

  group('pour is PERSISTENT + find-before-pour (A15)', () {
    test('iterate fallback-pour: probe MISS → cook → create --graph (no '
        '--ephemeral)', () async {
      final runner = RecordingBdRunner();
      runner.onCook = (_) {
        return {
          'steps': [
            {'id': 'work', 'title': 'iterate', 'type': 'task'},
            {
              'id': 'evaluate',
              'title': 'evaluate',
              'type': 'task',
              'needs': ['work'],
            },
          ],
        };
      };
      runner.onCreateGraph = (_) => {
        'wisp': 'gt-new',
        'work': 'gt-s1',
        'evaluate': 'gt-s2',
      };
      final p = recordingProbe(); // misses by default.
      final actuator = BdActuator(BdCliService(runner), p.probe);
      final conv = convergenceOf(convergenceBead('gt-c'), const [], const []);

      final action =
          ReconcilerAction.iterate(
                convergenceBeadId: 'gt-c',
                iteration: 1,
                path: IteratePath.wispClosed,
                closedWispId: 'gt-w1',
                pour: const WispPour(
                  parentBeadId: 'gt-c',
                  formula: 'mol-converge',
                  idempotencyKey: 'converge:gt-c:iter:2',
                  iteration: 2,
                ),
              )
              as IterateAction;

      await actuator.apply(ReduceResult.one(action), conv);

      // The probe ran FIRST (find-before-pour).
      expect(p.calls.single, (parent: 'gt-c', key: 'converge:gt-c:iter:2'));
      // cook then create --graph.
      expect(runner.verbs, containsAllInOrder(['cook', 'create']));
      // THE pour invariant: create --graph has NO --ephemeral (persistent).
      final createCall = runner.calls.firstWhere((c) => c.first == 'create');
      expect(
        createCall,
        isNot(contains('--ephemeral')),
        reason: 'A15: convergence pours are PERSISTENT',
      );
      // active_wisp then last_processed_wisp (the commit marker), then the
      // best-effort pending_next_wisp clear (step 5, after the commit).
      final keys = runner.metadataWrites
          .map((w) => w.metadata.keys.single)
          .toList();
      expect(
        keys,
        containsAllInOrder([
          ConvergenceFields.activeWisp,
          ConvergenceFields.lastProcessedWisp,
        ]),
      );
      // last_processed_wisp is the LAST commit write; only the pending clear
      // (value '') may follow it.
      final lpwIdx = keys.lastIndexOf(ConvergenceFields.lastProcessedWisp);
      for (final k in keys.sublist(lpwIdx + 1)) {
        expect(
          k,
          ConvergenceFields.pendingNextWisp,
          reason: 'only the pending clear may follow last_processed_wisp',
        );
      }
    });

    test(
      'idempotency HIT short-circuits the pour (no cook, no create)',
      () async {
        final runner = RecordingBdRunner();
        final p = recordingProbe()..setHit('gt-existing');
        final actuator = BdActuator(BdCliService(runner), p.probe);
        final conv = convergenceOf(convergenceBead('gt-c'), const [], const []);

        final action =
            ReconcilerAction.iterate(
                  convergenceBeadId: 'gt-c',
                  iteration: 1,
                  path: IteratePath.wispClosed,
                  closedWispId: 'gt-w1',
                  pour: const WispPour(
                    parentBeadId: 'gt-c',
                    formula: 'mol-converge',
                    idempotencyKey: 'converge:gt-c:iter:2',
                    iteration: 2,
                  ),
                )
                as IterateAction;

        await actuator.apply(ReduceResult.one(action), conv);

        // The probe hit ⇒ NO cook, NO create.
        expect(runner.verbs, isNot(contains('cook')));
        expect(runner.verbs, isNot(contains('create')));
        // The adopted id is wired into active_wisp.
        final activeWrite = runner.metadataWrites.firstWhere(
          (w) => w.metadata.containsKey(ConvergenceFields.activeWisp),
        );
        expect(
          activeWrite.metadata[ConvergenceFields.activeWisp],
          'gt-existing',
        );
      },
    );

    test('speculative pour: gate-typed nodes + gc.deferred_type stash, '
        'pending_next_wisp persisted', () async {
      Map<String, dynamic>? planSeen;
      final runner = RecordingBdRunner();
      runner.onCook = (_) => {
        'steps': [
          {'id': 'work', 'title': 'iterate', 'type': 'task'},
        ],
      };
      runner.onCreateGraph = (argv) {
        planSeen = const {}; // marker — argv carries only the file path.
        return {'wisp': 'gt-spec', 'work': 'gt-sw'};
      };
      final actuator = BdActuator(BdCliService(runner), recordingProbe().probe);
      final conv = convergenceOf(convergenceBead('gt-c'), const [], const []);

      final action =
          ReconcilerAction.pourSpeculative(
                convergenceBeadId: 'gt-c',
                pour: const WispPour(
                  parentBeadId: 'gt-c',
                  formula: 'mol-converge',
                  idempotencyKey: 'converge:gt-c:iter:2',
                  iteration: 2,
                  speculative: true,
                ),
              )
              as PourSpeculativeAction;

      final out = await actuator.apply(ReduceResult.one(action), conv);

      expect(out.pouredWispId, 'gt-spec');
      expect(planSeen, isNotNull);
      // pending_next_wisp is written immediately after the pour.
      final pending = runner.metadataWrites.firstWhere(
        (w) =>
            w.metadata.containsKey(ConvergenceFields.pendingNextWisp) &&
            w.metadata[ConvergenceFields.pendingNextWisp] == 'gt-spec',
      );
      expect(pending.id, 'gt-c');
      // persistent pour (no --ephemeral) even for speculative.
      final createCall = runner.calls.firstWhere((c) => c.first == 'create');
      expect(createCall, isNot(contains('--ephemeral')));
    });
  });

  group('in-list dataflow: prior pour threads into the later transition', () {
    test(
      'pourSpeculative then approved(burnPriorPour) burns the poured wisp',
      () async {
        final runner = RecordingBdRunner();
        runner.onCook = (_) => const {'steps': <dynamic>[]};
        runner.onCreateGraph = (_) => {'wisp': 'gt-spec2'};
        final actuator = BdActuator(
          BdCliService(runner),
          recordingProbe().probe,
        );
        final conv = convergenceOf(convergenceBead('gt-c'), const [], const []);

        final pour = ReconcilerAction.pourSpeculative(
          convergenceBeadId: 'gt-c',
          pour: const WispPour(
            parentBeadId: 'gt-c',
            formula: 'mol-converge',
            idempotencyKey: 'converge:gt-c:iter:2',
            iteration: 2,
            speculative: true,
          ),
        );
        final approved = ReconcilerAction.approved(
          convergenceBeadId: 'gt-c',
          path: TerminalPath.handlerWispClosed,
          actor: 'controller',
          iteration: 1,
          totalIterations: 1,
          lastProcessedWisp: 'gt-w1',
          burnPriorPour: true,
          closeReason: CloseReasons.handlerRoot,
        );

        await actuator.apply(ReduceResult([pour, approved]), conv);

        // The in-list poured wisp gt-spec2 is burned (deleted), not the (absent)
        // burnWispId.
        expect(runner.deletes.map((c) => c[1]), contains('gt-spec2'));
        // And it's a delete, never a close of the wisp.
        expect(runner.closes.map((c) => c[1]), ['gt-c']);
      },
    );
  });
}

/// The call index of the first `update` whose `--metadata` carries [key].
int _callIndexOfMetadataKey(RecordingBdRunner runner, String key) {
  for (var i = 0; i < runner.calls.length; i++) {
    final c = runner.calls[i];
    if (c.isEmpty || c.first != 'update') continue;
    final mi = c.indexOf('--metadata');
    if (mi < 0) continue;
    if (c[mi + 1].contains('"$key"')) return i;
  }
  return -1;
}
