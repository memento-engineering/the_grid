// Event-ID formula conformance — the executable spec for the stable event IDs
// gc mints in `emitEvent` (events.go:36-81). This pins H27 `TestEventIDFormulas`
// (handler_test.go:1095, 7 rows) AND the per-event `eventID ==` assertions that
// H10 / H21 / M6 / M13 / M20 / TR2 each carry in the Go suite, plus the
// load-bearing trigger_advance↔iteration COLLISION rule (events.go:74-81; the
// TR2 Go assertion `eventID != EventIDIteration(root, N)`).
//
// **Ownership.** The reducer (Track B) is a pure transition: it returns the
// event-ID COMPONENTS — `convergenceBeadId`, the action's `iteration`, and the
// event type implied by the action/path — on each `EventEmission`-bearing
// action. It deliberately does NOT mint the stable ID string; minting is the
// emitter's job (the actuator/runtime, Track E/G — `emitEvent(type, EventIDx,
// …)`), and the production recorder even discards the ID (operator-trigger.md
// §"Emission sink reality check"; store.go (cmd):375-383). So the formulas
// below are the EMITTER CONTRACT, stated here as a guard until the emitter
// suite exists, and bound to LIVE reducer output (`_reduce*` helpers) so they
// are not a vacuous self-test: each row drives a real reduce and mints the ID
// from THAT action's own components, proving the reducer surfaces the right
// `(beadID, iteration, type)` for the emitter to mint a correct, non-colliding
// ID. If a future build moves minting onto the carrier, fold these into the
// emitter conformance suite (Track H) and delete this guard.

import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/reducer_fakes.dart';

// ===========================================================================
// The emitter contract — gc's events.go:36-81 formulas, verbatim. Track E/G
// must implement these; consumers dedup by the minted ID.
// ===========================================================================

String eventIdCreated(String beadId) => 'converge:$beadId:created';

String eventIdIteration(String beadId, int iteration) =>
    'converge:$beadId:iter:$iteration:iteration';

String eventIdWaitingManual(String beadId, int iteration) =>
    'converge:$beadId:iter:$iteration:waiting_manual';

String eventIdTerminated(String beadId) => 'converge:$beadId:terminated';

String eventIdManualApprove(String beadId) => 'converge:$beadId:manual_approve';

String eventIdManualIterate(String beadId, int iteration) =>
    'converge:$beadId:iter:$iteration:manual_iterate';

String eventIdManualStop(String beadId) => 'converge:$beadId:manual_stop';

// trigger_advance deliberately uses a distinct suffix so it can NEVER collide
// with the per-wisp `iteration` event the same iteration's wisp emits when it
// closes (events.go:74-81). N = the NEW wisp poured when the trigger fired.
String eventIdTriggerAdvance(String beadId, int iteration) =>
    'converge:$beadId:iter:$iteration:trigger_advance';

void main() {
  // =========================================================================
  // H27 TestEventIDFormulas — handler_test.go:1095, 7 exact rows for
  // bead gc-conv-42 (the formulas as pure functions).
  // =========================================================================
  group('H27 event-ID formulas (handler_test.go:1095, 7 rows)', () {
    const bead = 'gc-conv-42';
    test('created', () {
      expect(eventIdCreated(bead), 'converge:gc-conv-42:created');
    });
    test('iteration(3)', () {
      expect(eventIdIteration(bead, 3), 'converge:gc-conv-42:iter:3:iteration');
    });
    test('waiting_manual(3)', () {
      expect(
        eventIdWaitingManual(bead, 3),
        'converge:gc-conv-42:iter:3:waiting_manual',
      );
    });
    test('terminated', () {
      expect(eventIdTerminated(bead), 'converge:gc-conv-42:terminated');
    });
    test('manual_approve', () {
      expect(eventIdManualApprove(bead), 'converge:gc-conv-42:manual_approve');
    });
    test('manual_iterate(4)', () {
      expect(
        eventIdManualIterate(bead, 4),
        'converge:gc-conv-42:iter:4:manual_iterate',
      );
    });
    test('manual_stop', () {
      expect(eventIdManualStop(bead), 'converge:gc-conv-42:manual_stop');
    });
  });

  // =========================================================================
  // The collision rule (events.go:74-81; TR2 Go: trigger_advance ID must NOT
  // equal the iteration ID for the same N). gap in H27 — pinned here per the
  // handler inventory trap #12 / operator-trigger §"For manual_iterate and
  // trigger_advance".
  // =========================================================================
  group('trigger_advance ↔ iteration collision rule (events.go:74-81)', () {
    test('the two IDs differ for the SAME bead + SAME N (no collision)', () {
      for (final n in [0, 1, 2, 3, 42]) {
        expect(
          eventIdTriggerAdvance('root-1', n),
          isNot(eventIdIteration('root-1', n)),
          reason:
              'trigger_advance(N) must never collide with iteration(N) — '
              'both would otherwise derive converge:root-1:iter:$n:…',
        );
      }
    });

    test(
      'manual_iterate also stays distinct from iteration for the same N',
      () {
        for (final n in [1, 2, 4]) {
          expect(
            eventIdManualIterate('root-1', n),
            isNot(eventIdIteration('root-1', n)),
          );
        }
      },
    );
  });

  // =========================================================================
  // Binding the contract to LIVE reducer output: each per-event Go assertion
  // (H10/H21/M6/M13/M20/TR2) mints its ID from the actual action's components.
  // This proves the reducer surfaces the right (beadID, iteration, type).
  // =========================================================================
  group('per-event eventID bound to reducer output', () {
    test('H10/H21 replay pass → approved: iteration ID uses the CLOSED wisp '
        'iteration; terminated ID is bead-scoped (handler.go:436,685)', () {
      final f = baseline(extra: replay('pass'));
      final a =
          ConvergenceReducer.reduce(
                f.convergence,
                const ReducerEvent.wispClosed(
                  convergenceBeadId: 'root-1',
                  wispId: 'wisp-iter-1',
                ),
                f.snapshot,
              ).primary
              as ApprovedAction;
      // The handler terminal path emits BOTH an iteration and a terminated
      // event; their IDs derive from the action's bead + iteration (= the
      // closed wisp's iteration, here 1).
      expect(a.iteration, 1);
      expect(
        eventIdIteration(a.convergenceBeadId, a.iteration),
        'converge:root-1:iter:1:iteration',
      );
      expect(
        eventIdTerminated(a.convergenceBeadId),
        'converge:root-1:terminated',
      );
    });

    test('M6 operator approve → manual_approve + terminated IDs are '
        'bead-scoped (manual.go:88,102)', () {
      final a =
          ConvergenceReducer.reduce(
                waitingManual().convergence,
                ReducerEvent.operatorApprove(
                  convergenceBeadId: 'root-1',
                  user: 'alice',
                ),
                waitingManual().snapshot,
              ).primary
              as ApprovedAction;
      expect(
        eventIdManualApprove(a.convergenceBeadId),
        'converge:root-1:manual_approve',
      );
      expect(
        eventIdTerminated(a.convergenceBeadId),
        'converge:root-1:terminated',
      );
    });

    test('M13 operator iterate → manual_iterate ID uses the NEW iteration '
        '(manual.go:210)', () {
      final a =
          ConvergenceReducer.reduce(
                waitingManual().convergence,
                ReducerEvent.operatorIterate(
                  convergenceBeadId: 'root-1',
                  user: 'alice',
                ),
                waitingManual().snapshot,
              ).primary
              as IterateAction;
      // derived count 1 → new iteration 2.
      expect(a.iteration, 2);
      expect(
        eventIdManualIterate(a.convergenceBeadId, a.iteration),
        'converge:root-1:iter:2:manual_iterate',
      );
    });

    test('M20 operator stop → manual_stop + terminated IDs are bead-scoped '
        '(manual.go:412,427)', () {
      final a =
          ConvergenceReducer.reduce(
                waitingManual().convergence,
                ReducerEvent.operatorStop(
                  convergenceBeadId: 'root-1',
                  user: 'alice',
                  postDrain: false,
                ),
                waitingManual().snapshot,
              ).primary
              as StoppedAction;
      expect(
        eventIdManualStop(a.convergenceBeadId),
        'converge:root-1:manual_stop',
      );
      expect(
        eventIdTerminated(a.convergenceBeadId),
        'converge:root-1:terminated',
      );
    });

    test('TR2 trigger advance → trigger_advance ID uses the NEW iteration and '
        'does NOT collide with iteration(N) (trigger.go:173)', () {
      final a =
          ConvergenceReducer.reduce(
                waitingTrigger().convergence,
                ReducerEvent.triggerPassed(
                  convergenceBeadId: 'root-1',
                  nextIteration: 1,
                ),
                waitingTrigger().snapshot,
              ).primary
              as IterateAction;
      expect(a.iteration, 1);
      expect(a.path, IteratePath.triggerAdvance);
      final advanceId = eventIdTriggerAdvance(a.convergenceBeadId, a.iteration);
      expect(advanceId, 'converge:root-1:iter:1:trigger_advance');
      // The TR2 Go assertion: distinct from the iteration ID for the same N.
      expect(
        advanceId,
        isNot(eventIdIteration(a.convergenceBeadId, a.iteration)),
      );
    });
  });
}
