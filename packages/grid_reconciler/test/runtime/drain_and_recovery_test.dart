import 'package:fake_async/fake_async.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import 'support/runtime_fakes.dart';

void main() {
  group('ReconcilerRuntime — operator-stop drain protocol (A19)', () {
    test('stop on a closed-but-unprocessed active wisp drains then re-enters '
        'postDrain', () async {
      // active loop, active_wisp closed but NOT yet processed
      // (last_processed_wisp behind). A stop must run the drain pipeline
      // (HandleWispClosed) first, then re-enter the stop postDrain.
      final loop = activeLoop(rootId: 'S', activeWispId: 'S-w1');
      // gate_mode manual so the drain short-circuits to waiting_manual in ONE
      // reduce (no async gate hop) — keeps the drain deterministic.
      final root = convergenceBead(
        'S',
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'manual',
          ConvergenceFields.activeWisp: 'S-w1',
          // last_processed_wisp absent ⇒ S-w1 (iter 1) is unprocessed.
        },
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [root],
          children: {
            'S': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      final out = await runtime.submit(
        ReducerEvent.operatorStop(convergenceBeadId: 'S', user: 'nico'),
      );
      await runtime.idle();
      await runtime.dispose();

      // The first reduce returned the drain pipeline + a requeue carrier.
      expect(out.status, CycleStatus.requeued);
      expect(out.requeued, isA<OperatorStopEvent>());
      expect((out.requeued! as OperatorStopEvent).postDrain, isTrue);
      // The drain ran a waiting_manual transition (manual short-circuit), and
      // the re-entered postDrain stop processed over post-drain state.
      expect(actuator.actions.whereType<WaitingManualAction>(), isNotEmpty);
      // The postDrain re-entry was reduced (a stopped transition or a skip).
      final reentryStop = runtime.outcomes.any(
        (o) =>
            o.primary is StoppedAction ||
            (o.primary is SkippedAction &&
                (o.primary! as SkippedAction).reason ==
                    SkipReason.drainTerminated),
      );
      expect(reentryStop, isTrue);
    });

    test('stop draining a closed wisp behind a FRESH condition gate still '
        'terminates — the requeue is not dropped (regression: gate-vs-requeue '
        'ordering)', () async {
      // Same closed-but-unprocessed active wisp, but gate_mode=condition (not
      // manual). The drain runs HandleWispClosed, which for a fresh condition
      // gate returns [pourSpeculative, evaluateGate, requeue(postDrain)]. The
      // runtime must route this through the drain — resolving the inner gate
      // AND re-entering the postDrain stop — NOT through the gate phase, which
      // would run the gate but silently drop the requeue (the loop would never
      // stop). `activeLoop` builds a condition-gate root.
      final loop = activeLoop(rootId: 'SC', activeWispId: 'SC-w1');
      final source = FakeConvergenceSource(
        snapWith(
          roots: [loop.root],
          children: {
            'SC': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator();
      // Default fail outcome; we only need the inner gate to resolve so the
      // drain's phase-2 transition runs before the postDrain stop re-enters.
      final gate = FakeGate();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gate,
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      final out = await runtime.submit(
        ReducerEvent.operatorStop(convergenceBeadId: 'SC', user: 'nico'),
      );
      await runtime.idle();
      await runtime.dispose();

      // The drain carrier was honored (BUG: this was `actuated`/`gateEvaluated`
      // because the gate path swallowed the requeue).
      expect(out.status, CycleStatus.requeued);
      expect((out.requeued! as OperatorStopEvent).postDrain, isTrue);
      // The inner drain gate actually ran (the drain was a real gate handoff).
      expect(gate.evaluated, isNotEmpty);
      // ...AND the postDrain stop terminated the loop (the bug = never fires).
      final terminated = runtime.outcomes.any(
        (o) =>
            o.primary is StoppedAction ||
            (o.primary is SkippedAction &&
                (o.primary! as SkippedAction).reason ==
                    SkipReason.drainTerminated),
      );
      expect(
        terminated,
        isTrue,
        reason: 'postDrain stop must be honored after the inner gate runs',
      );
    });

    test(
      'a plain stop on an open active wisp force-closes (no drain)',
      () async {
        // active loop with an OPEN active wisp ⇒ no drain, straight to stopped.
        final root = convergenceBead(
          'S2',
          metadata: {
            ConvergenceFields.state: 'active',
            ConvergenceFields.iteration: '1',
            ConvergenceFields.maxIterations: '5',
            ConvergenceFields.formula: 'f',
            ConvergenceFields.gateMode: 'manual',
            ConvergenceFields.activeWisp: 'S2-w1',
            ConvergenceFields.lastProcessedWisp: 'S2-w1',
          },
        );
        final openWisp = wispBead(
          'S2-w1',
          key: idempotencyKey('S2', 1),
          status: BeadStatus.open,
        );
        final source = FakeConvergenceSource(
          snapWith(
            roots: [root],
            children: {
              'S2': [openWisp],
            },
          ),
        );
        final actuator = RecordingActuator();
        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: FakeGate(),
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
        );
        await runtime.start();

        final out = await runtime.submit(
          ReducerEvent.operatorStop(convergenceBeadId: 'S2', user: 'nico'),
        );
        await runtime.idle();
        await runtime.dispose();

        expect(out.status, CycleStatus.actuated);
        final stopped = actuator.actions.whereType<StoppedAction>().single;
        expect(stopped.forceCloseWispId, 'S2-w1');
      },
    );
  });

  group('ReconcilerRuntime — deferred live-error contract (A25)', () {
    test(
      'an injected actuation failure → no_action + error + no further writes '
      'this cycle, retried next cycle',
      () async {
        final loop = activeLoop(rootId: 'E', activeWispId: 'E-w1');
        final source = FakeConvergenceSource(
          snapWith(
            roots: [loop.root],
            children: {
              'E': [loop.closedWisp],
            },
          ),
        );
        final actuator = RecordingActuator()
          // Fail the FIRST apply for bead E, then succeed.
          ..failBead = 'E';
        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: FakeGate(),
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
        );
        await runtime.start();

        // First closure → the phase-1 apply throws ActuationFailed.
        source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
        await runtime.idle();

        final failed = runtime.outcomes.where((o) => o.isFailure).toList();
        expect(
          failed,
          isNotEmpty,
          reason: 'the live failure surfaced as failed',
        );
        expect(failed.first.error, isA<ActuationFailed>());
        // No transition committed: the only applies were the failed phase-1
        // (which threw before any further action). The loop is left at prior
        // state so a retry is safe.
        final appliesBefore = actuator.appliesByBead['E']!;

        // Second closure (the retry) succeeds idempotently.
        source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
        await runtime.idle();
        await runtime.dispose();

        expect(
          actuator.appliesByBead['E'],
          greaterThan(appliesBefore),
          reason: 'the next cycle retried',
        );
        // The retry did NOT throw — it ran the gate and transitioned.
        expect(
          runtime.outcomes.last.isFailure,
          isFalse,
          reason: 'the retry succeeded idempotently',
        );
      },
    );
  });

  group('ReconcilerRuntime — periodic full reconcile (Track C)', () {
    test('runs at startup', () async {
      // A loop in state "" (not adopted) with no wisps ⇒ recovery would pour
      // wisp 1. We assert the startup pass scanned it (the pour-1 effect is a
      // RecoveryAction, not a reducer replay, so it is reported in scanned but
      // not actuated through the reducer path here).
      final root = convergenceBead(
        'R',
        metadata: {
          ConvergenceFields.formula: 'f',
          ConvergenceFields.maxIterations: '5',
        },
      );
      final source = FakeConvergenceSource(snapWith(roots: [root]));
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: RecordingActuator(),
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: true,
      );
      await runtime.start();
      await runtime.idle();
      await runtime.dispose();

      // The startup pass scanned the one non-closed convergence.
      final report = ConvergenceRecovery.reconcile(source.current!);
      expect(report.scanned, 1);
    });

    test('recovery after a live cycle does NOT double-apply over the stale '
        'snapshot (overlay re-reduce)', () async {
      // The A17 corruption guard: a live BeadClosed cycle processes Z-w1 (one
      // waiting_manual, overlay records last_processed_wisp ← Z-w1). A recovery
      // pass over the UNCHANGED raw snapshot (the watcher lag the overlay
      // exists to cover, A21) must re-reduce through the overlay and SKIP —
      // never re-fire a second transition over an already-processed closure.
      final loop = activeLoop(rootId: 'Z', activeWispId: 'Z-w1');
      final root = convergenceBead(
        'Z',
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'manual',
          ConvergenceFields.activeWisp: 'Z-w1',
          // last_processed_wisp absent ⇒ Z-w1 closed-but-unprocessed.
        },
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [root],
          children: {
            'Z': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      // Live close → manual short-circuit → waiting_manual; overlay records
      // last_processed_wisp ← Z-w1.
      source.emit(beadClosedEvent(loop.closedWisp, loop.closedWisp));
      await runtime.idle();
      final manualAfterLive = actuator.actions
          .whereType<WaitingManualAction>()
          .length;
      expect(manualAfterLive, 1, reason: 'the live cycle processed Z-w1 once');

      // Recovery over the still-stale raw snapshot — must dedup-skip.
      final report = await runtime.runRecovery();
      await runtime.idle();
      await runtime.dispose();

      expect(
        actuator.actions.whereType<WaitingManualAction>().length,
        1,
        reason: 'recovery did not re-fire the already-processed transition',
      );
      expect(actuator.appliesByBead['Z'], 1);
      expect(
        report.actuated,
        0,
        reason: 'the overlay re-reduce yielded no replay',
      );
    });

    test('the periodic backstop fires on the fake clock', () {
      fakeAsync((async) {
        // A closed-but-unprocessed active wisp ⇒ recovery REPLAYS it through
        // the reducer (a replay plan the runtime actuates). We drive the
        // periodic timer with fake_async and assert recovery ran on the tick.
        final loop = activeLoop(rootId: 'B', activeWispId: 'B-w1');
        final root = convergenceBead(
          'B',
          metadata: {
            ConvergenceFields.state: 'active',
            ConvergenceFields.iteration: '1',
            ConvergenceFields.maxIterations: '5',
            ConvergenceFields.formula: 'f',
            ConvergenceFields.gateMode: 'manual',
            ConvergenceFields.activeWisp: 'B-w1',
            // last_processed behind ⇒ closed-but-unprocessed ⇒ replay on the
            // recovery pass.
          },
        );
        final source = FakeConvergenceSource(
          snapWith(
            roots: [root],
            children: {
              'B': [loop.closedWisp],
            },
          ),
        );
        final actuator = RecordingActuator();
        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: FakeGate(),
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
          recoveryInterval: const Duration(seconds: 30),
        );

        runtime.start();
        async.flushMicrotasks();
        final appliesAtStart = actuator.appliesByBead['B'] ?? 0;

        // Advance past one recovery interval — the backstop fires.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();

        expect(
          (actuator.appliesByBead['B'] ?? 0),
          greaterThan(appliesAtStart),
          reason: 'the periodic reconcile replayed the closed-unprocessed wisp',
        );
        runtime.dispose();
        async.flushMicrotasks();
      });
    });

    test('the periodic backstop does not overlap: a pass slower than the '
        'interval defers the next tick (single-flight)', () {
      fakeAsync((async) {
        // A closed-but-unprocessed wisp ⇒ a replayable candidate, with a slow
        // apply so the recovery pass outruns the 30s interval. Without the
        // re-entrancy guard a second timer tick would start a concurrent pass;
        // the guard skips it (gc never overlaps its single reconcile loop).
        final loop = activeLoop(rootId: 'G', activeWispId: 'G-w1');
        final root = convergenceBead(
          'G',
          metadata: {
            ConvergenceFields.state: 'active',
            ConvergenceFields.iteration: '1',
            ConvergenceFields.maxIterations: '5',
            ConvergenceFields.formula: 'f',
            ConvergenceFields.gateMode: 'manual',
            ConvergenceFields.activeWisp: 'G-w1',
          },
        );
        final source = FakeConvergenceSource(
          snapWith(
            roots: [root],
            children: {
              'G': [loop.closedWisp],
            },
          ),
        );
        // Each apply takes 50s — longer than the 30s interval.
        final actuator = RecordingActuator()
          ..applyDelay = const Duration(seconds: 50);
        final runtime = ReconcilerRuntime(
          source: source,
          actuator: actuator,
          gateEvaluator: FakeGate(),
          ownership: const OwnsEverything(),
          runRecoveryAtStartup: false,
          recoveryInterval: const Duration(seconds: 30),
        );

        runtime.start();
        async.flushMicrotasks();

        // Tick 1 at 30s starts a pass; it holds the slow apply until 80s.
        // Tick 2 at 60s would overlap — the guard must skip it.
        async.elapse(const Duration(seconds: 65));
        async.flushMicrotasks();

        expect(
          runtime.recoveryPasses,
          1,
          reason: 'the second tick was skipped while the first pass ran',
        );
        // The slow first pass still completes exactly one apply.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(actuator.appliesByBead['G'], 1);

        runtime.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('ReconcilerRuntime — replay after a simulated restart (crash safety)', () {
    test('a fresh runtime over a mid-transition store converges the '
        'interrupted closure to ONE transition, idempotently', () async {
      // Model a crash mid-transition: the prior runtime closed the active wisp
      // and began the wisp-closed transition, but the process died before the
      // commit marker (last_processed_wisp) landed. The store the NEW runtime
      // boots over therefore shows: state=active, active_wisp=X-w1 (closed),
      // last_processed_wisp ABSENT — a closed-but-unprocessed wisp, exactly
      // gc's Path-4 closed-unprocessed replay candidate (reconcile.go:455-464).
      final loop = activeLoop(rootId: 'X', activeWispId: 'X-w1');
      final root = convergenceBead(
        'X',
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          // manual gate ⇒ the replay short-circuits to waiting_manual in ONE
          // reduce (deterministic, no async gate hop).
          ConvergenceFields.gateMode: 'manual',
          ConvergenceFields.activeWisp: 'X-w1',
          // last_processed_wisp ABSENT ⇒ X-w1 unprocessed (the interrupted
          // commit).
        },
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [root],
          children: {
            'X': [loop.closedWisp],
          },
        ),
      );
      final actuator = RecordingActuator();

      // The FRESH runtime (a clean restart: empty overlay, empty queue) boots
      // over the half-applied store and runs the startup recovery pass.
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: FakeGate(),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: true,
      );
      await runtime.start();
      await runtime.idle();

      // Startup recovery replayed the interrupted closure exactly once: ONE
      // waiting_manual transition, ONE apply for X.
      expect(
        actuator.actions.whereType<WaitingManualAction>().length,
        1,
        reason: 'the interrupted closure converged to a single transition',
      );
      expect(actuator.appliesByBead['X'], 1);

      // A SECOND recovery pass (the periodic backstop, or a redundant restart
      // pass) over the SAME unchanged raw snapshot — the watcher still lags the
      // commit write — must NOT re-fire: the overlay carries the advanced
      // last_processed_wisp, so the re-reduce dedup-skips (the A17 seam the
      // live cycle uses, not the snapshot-time plan).
      await runtime.runRecovery();
      await runtime.idle();
      await runtime.dispose();

      expect(
        actuator.actions.whereType<WaitingManualAction>().length,
        1,
        reason: 'replay-after-restart is idempotent — no duplicate transition',
      );
      expect(
        actuator.appliesByBead['X'],
        1,
        reason: 'the second pass dedup-skipped over the overlay',
      );
    });
  });
}
