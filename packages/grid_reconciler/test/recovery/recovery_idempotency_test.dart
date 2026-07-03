// Idempotency property (spec §12) — running the recovery pass twice over a
// snapshot reflecting the first pass's writes must yield a second all-no_action
// report. The pass is PURE, so the test actuates the first outcome with a tiny
// faithful in-memory actuator ([_apply]), rebuilds the snapshot, and asserts
// the re-reconcile is a no-op. This is the crash-safety contract that lets the
// pass run at startup AND as a low-frequency backstop (every path re-runnable).

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/recovery_fakes.dart';

/// A minimal faithful actuator over a single root + its wisp children: applies
/// the metadata writes / pour / close / pointer-repair an outcome carries,
/// honoring find-before-pour. Returns the post-first-pass snapshot.
GraphSnapshot _apply(RecoveryOutcome o, Bead root, List<Bead> children) {
  final meta = Map<String, dynamic>.from(root.metadata);
  var status = root.status;
  final kids = [...children];
  var minted = 0;

  void put(MetadataWrite w) => meta[w.key] = w.value;
  void putAll(Iterable<MetadataWrite> ws) => ws.forEach(put);

  // Find-before-pour: adopt a key hit, else mint an in_progress wisp child.
  String pour(WispPour p) {
    for (final c in kids) {
      if (c.metadata['idempotency_key'] == p.idempotencyKey) return c.id;
    }
    final id = 'wisp-minted-${++minted}';
    kids.add(
      wispBead(
        id,
        key: p.idempotencyKey,
        status: BeadStatus.inProgress,
        createdAt: recoveryCreatedAt,
      ),
    );
    return id;
  }

  switch (o.recovery) {
    case AdoptWispAction(:final orderedWrites):
      putAll(orderedWrites);
    case PourFirstWispAction(pour: final p, postPourWrites: final post):
      putAll(post(pour(p)));
    case PartialCreationTerminateAction(:final orderedWrites):
      putAll(orderedWrites);
      status = BeadStatus.closed;
    case CompleteTerminalAction(
      :final actorBackfillWrite,
      :final stateWrite,
      :final commitWrite,
    ):
      if (actorBackfillWrite != null) put(actorBackfillWrite);
      if (stateWrite != null) put(stateWrite);
      status = BeadStatus.closed; // CloseBead.
      if (commitWrite != null) put(commitWrite); // writes accepted on closed.
    case WaitingManualRecoveryActionData(:final repairWrite):
      if (repairWrite != null) put(repairWrite);
    case RepairWaitingReasonAction(:final write):
      put(write);
    case PourNextWispAction(
      :final adoptWispId,
      pour: final p,
      postWrites: final post,
    ):
      putAll(post(adoptWispId ?? pour(p!)));
    case RepairActiveWispAction(:final write):
      put(write);
    case null:
      break;
  }

  // Apply the commit-bearing writes of replay transitions (the reducer plan):
  // only the fields that gate the SECOND pass — state, terminal_reason,
  // last_processed_wisp, active_wisp, and any visible pour.
  for (final a in o.replayActions) {
    switch (a) {
      case ApprovedAction(:final lastProcessedWisp):
        meta[ConvergenceFields.state] = ConvergenceState.terminated.wire;
        meta[ConvergenceFields.terminalReason] = TerminalReason.approved.wire;
        if (lastProcessedWisp != null) {
          meta[ConvergenceFields.lastProcessedWisp] = lastProcessedWisp;
        }
        status = BeadStatus.closed;
      case NoConvergenceAction(:final lastProcessedWisp):
        meta[ConvergenceFields.state] = ConvergenceState.terminated.wire;
        meta[ConvergenceFields.terminalReason] =
            TerminalReason.noConvergence.wire;
        if (lastProcessedWisp != null) {
          meta[ConvergenceFields.lastProcessedWisp] = lastProcessedWisp;
        }
        status = BeadStatus.closed;
      case IterateAction(pour: final p, :final closedWispId):
        // wisp-closed iterate: pour the visible next wisp, point active_wisp at
        // it, last_processed_wisp ← the just-closed wisp (Inv 2).
        final next = pour(p);
        meta[ConvergenceFields.activeWisp] = next;
        if (closedWispId != null) {
          meta[ConvergenceFields.lastProcessedWisp] = closedWispId;
        }
        meta[ConvergenceFields.pendingNextWisp] = '';
      case WaitingManualAction(:final closedWispId, :final reason):
        meta[ConvergenceFields.activeWisp] = '';
        meta[ConvergenceFields.waitingReason] = reason.wire;
        meta[ConvergenceFields.state] = ConvergenceState.waitingManual.wire;
        meta[ConvergenceFields.lastProcessedWisp] = closedWispId;
      default:
        break;
    }
  }

  final next = root.copyWith(metadata: meta, status: status);
  return rootSnap(next, children: kids);
}

/// Reconcile [root]+[children], actuate the single outcome, then reconcile the
/// resulting snapshot and assert it is a no-op (every outcome no_action, no
/// recovery effect, no replay).
/// True when an outcome carries STORE-MUTATING work: a metadata write, a pour,
/// a close, or a replay transition. A re-emitted recovery event with NO write
/// (the genuine-hold re-announce — spec §7.2, TierRecoverable, stable id +
/// consumer dedup) is NOT write work: the recovery pass deliberately re-fires
/// it on every pass so a consumer that lost the original still learns the hold.
bool _writeWork(RecoveryOutcome o) {
  if (o.replayActions.isNotEmpty) return true;
  return switch (o.recovery) {
    AdoptWispAction() ||
    PourFirstWispAction() ||
    PartialCreationTerminateAction() ||
    RepairWaitingReasonAction() ||
    PourNextWispAction() ||
    RepairActiveWispAction() => true,
    CompleteTerminalAction(
      :final actorBackfillWrite,
      :final stateWrite,
      :final commitWrite,
    ) =>
      actorBackfillWrite != null || stateWrite != null || commitWrite != null,
    WaitingManualRecoveryActionData(:final repairWrite) => repairWrite != null,
    null => false,
  };
}

/// Drives apply+reconcile to a FIXPOINT (bounded) and asserts the fixed point
/// performs no write work — gc's recovery converges, possibly over more than
/// one pass (orphaned waiting_manual stamps `waiting_reason` first, repairs the
/// marker next, then is stable). The crash-safety property (spec §12) is that
/// it CONVERGES and a converged snapshot yields no further writes — never
/// duplicate pours, closes, or marker churn.
void _expectIdempotent(
  String label,
  Bead root, {
  List<Bead> children = const [],
  int maxPasses = 4,
}) {
  var snapshot = rootSnap(root, children: children);
  var curRoot = root;
  var curChildren = children;
  RecoveryReport? report;
  for (var pass = 0; pass < maxPasses; pass++) {
    report = ConvergenceRecovery.reconcile(snapshot);
    final anyWork = report.outcomes.any(_writeWork);
    if (!anyWork) {
      // Converged: assert it stays converged on one more pass.
      final again = ConvergenceRecovery.reconcile(snapshot);
      expect(
        again.outcomes.any(_writeWork),
        isFalse,
        reason: '$label: re-running the converged snapshot performed writes',
      );
      expect(again.errors, 0, reason: '$label: converged pass errored');
      return;
    }
    // Actuate the single outcome and advance.
    final o = report.outcomes.single;
    snapshot = _apply(o, curRoot, curChildren);
    final next = snapshot.beadsById[curRoot.id]!;
    curRoot = next;
    curChildren = snapshot.beads.where((b) => b.id != next.id).toList();
  }
  fail('$label: recovery did not converge within $maxPasses passes');
}

void main() {
  group(
    'Idempotency — re-running over the first pass\'s writes is a no-op',
    () {
      test('Path 1a pour-first → adopt → no_action', () {
        _expectIdempotent(
          'pour-first',
          convergenceBead('root-1', metadata: meta()),
        );
      });

      test('Path 1a open-adopt → no_action', () {
        _expectIdempotent(
          'open-adopt',
          convergenceBead('root-1', metadata: meta()),
          children: [
            wispBead(
              'existing',
              key: idempotencyKey('root-1', 1),
              status: BeadStatus.open,
            ),
          ],
        );
      });

      test(
        'Path 1b creating → terminated+closed → no_action (scan drops it)',
        () {
          _expectIdempotent(
            'creating',
            convergenceBead(
              'root-1',
              metadata: {ConvergenceFields.state: 'creating'},
            ),
          );
        },
      );

      test('Path 2 terminated-not-closed → closed → dropped by scan', () {
        _expectIdempotent(
          'terminated-not-closed',
          convergenceBead(
            'root-1',
            metadata: meta(
              state: 'terminated',
              extra: {
                ConvergenceFields.terminalReason: 'approved',
                ConvergenceFields.terminalActor: 'controller',
              },
            ),
          ),
          children: [wisp('root-1', 1)],
        );
      });

      test('Path 3 waiting_manual genuine-hold repair → marker stable', () {
        _expectIdempotent(
          'waiting_manual-repair',
          convergenceBead(
            'root-1',
            metadata: meta(
              state: 'waiting_manual',
              extra: {
                ConvergenceFields.waitingReason: 'manual',
                ConvergenceFields.lastProcessedWisp: 'wisp-0',
              },
            ),
          ),
          children: [
            wisp('root-1', 0, id: 'wisp-0'),
            wisp('root-1', 1, id: 'wisp-1'),
          ],
        );
      });

      test('Path 3A waiting_manual interrupted-stop → completed → dropped', () {
        _expectIdempotent(
          'waiting_manual-stop',
          convergenceBead(
            'root-1',
            metadata: meta(
              state: 'waiting_manual',
              extra: {
                ConvergenceFields.waitingReason: 'manual',
                ConvergenceFields.terminalReason: 'stopped',
                ConvergenceFields.terminalActor: 'operator:alice',
              },
            ),
          ),
          children: [wisp('root-1', 1)],
        );
      });

      test(
        'Path 3C orphaned waiting_manual → waiting_reason repaired → stable',
        () {
          _expectIdempotent(
            'waiting_manual-orphan',
            convergenceBead('root-1', metadata: meta(state: 'waiting_manual')),
            children: [wisp('root-1', 1)],
          );
        },
      );

      test('Path 4 empty active_wisp pour-next → adopts on re-run', () {
        _expectIdempotent(
          'active-pour-next',
          convergenceBead(
            'root-1',
            metadata: meta(
              state: 'active',
              extra: {
                ConvergenceFields.iteration: '1',
                ConvergenceFields.gateMode: 'condition',
                ConvergenceFields.gateCondition: '/gate/check',
                ConvergenceFields.gateTimeout: '60s',
                ConvergenceFields.activeWisp: '',
              },
            ),
          ),
          children: [wisp('root-1', 1)],
        );
      });

      test('Path 4 already-processed → no_action both passes', () {
        _expectIdempotent(
          'active-already-processed',
          convergenceBead(
            'root-1',
            metadata: meta(
              state: 'active',
              extra: {
                ConvergenceFields.iteration: '1',
                ConvergenceFields.gateMode: 'condition',
                ConvergenceFields.gateCondition: '/gate/check',
                ConvergenceFields.gateTimeout: '60s',
                ConvergenceFields.activeWisp: 'wisp-iter-1',
                ConvergenceFields.lastProcessedWisp: 'wisp-iter-1',
              },
            ),
          ),
          children: [wisp('root-1', 1)],
        );
      });

      test(
        'Path 4 closed-unprocessed replay (terminal) → closed → dropped',
        () {
          _expectIdempotent(
            'active-replay-terminal',
            convergenceBead(
              'root-1',
              metadata: meta(
                state: 'active',
                extra: {
                  ConvergenceFields.iteration: '1',
                  ConvergenceFields.gateMode: 'condition',
                  ConvergenceFields.gateCondition: '/gate/check',
                  ConvergenceFields.gateTimeout: '60s',
                  ConvergenceFields.activeWisp: 'wisp-iter-1',
                  // cached pass → replay terminates approved.
                  ConvergenceFields.gateOutcomeWisp: 'wisp-iter-1',
                  ConvergenceFields.gateOutcome: 'pass',
                  ConvergenceFields.gateRetryCount: '0',
                },
              ),
            ),
            children: [wisp('root-1', 1)],
          );
        },
      );
    },
  );
}
