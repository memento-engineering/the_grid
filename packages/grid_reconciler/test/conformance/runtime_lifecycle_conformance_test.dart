@Tags(['integration'])
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../gates/support/fake_process_runner.dart';
import '../runtime/support/runtime_fakes.dart';

/// TRACK H — END-TO-END conformance through the REAL [ReconcilerRuntime]
/// (ADR-0003 Decision 7 + ADR-0000 A27). The per-component conformance suites
/// (test/reducer, test/recovery, test/gates) pin the pure transitions; this
/// suite drives the gc lifecycle BRANCHES the per-component units cannot — the
/// full reduce→gate→actuate→(recovery) chain — and asserts the transition
/// sequence and gc-faithful action vocabulary the real composition produces.
///
/// Each scenario advances a single mutable in-memory "store" (the snapshot +
/// the actuator's recorded writes) by hand between events, modelling how the
/// live controller re-captures the snapshot after each bd-mediated transition.
/// The gate is the REAL [GateRunnerService] over a [FakeProcessRunner] (or a
/// [FakeGate] where the gate is irrelevant). NO live/real-workspace writes.
///
/// Branches covered here that the existing runtime tests do NOT drive end to
/// end as a CHAINED gc scenario:
///   - gate fail → iterate → … → iter≥max with gate≠pass → no_convergence
///     (handler.go:331-352 / reconcile table T5; runtime_bd_sequence only
///     drives the timeout→terminate terminal, never the gate-fail-at-max one).
///   - wispClosed manual short-circuit → waiting_manual → operator approve
///     terminates, AND → operator iterate resumes (the manual hold consumed
///     and resolved in ONE runtime, not pre-seeded at waiting_manual).
///   - wispClosed on a trigger-gated loop → waiting_trigger → triggerPassed →
///     active (the T6→T10 hold-then-advance chain, trigger.go:129-180).
///   - gate timeout → action=retry (the timeout action runtime_bd_sequence
///     omits; gate_test.go ParseGateConfig "retry" row + handler timeout
///     switch handler.go:336-344).
void main() {
  // The real Track-D gate over a fake process runner.
  GateRunnerProcessGate gateOver(FakeProcessRunner process) =>
      GateRunnerProcessGate(
        runner: GateRunnerService(
          processRunner: process,
          ambientEnvironment: const {},
          lookPathDir: (_) => null,
          tempDir: '/tmp',
        ),
      );

  Bead closedWisp(String root, int iter) => wispBead(
    '$root-w$iter',
    key: idempotencyKey(root, iter),
    status: BeadStatus.closed,
    createdAt: fakeClock.subtract(const Duration(minutes: 10)),
    closedAt: fakeClock,
  );

  group('lifecycle: gate fail → iterate → … → max → no_convergence', () {
    test('two iterates (gate fail below max) then the iter==max closure with '
        'gate fail terminates as no_convergence — NOT a third iterate '
        '(handler.go:331-352, table T5)', () async {
      const root = 'NC';
      Bead rootBead(Map<String, dynamic> meta) =>
          convergenceBead(root, metadata: meta);
      final baseMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '3',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'condition',
        ConvergenceFields.gateCondition: '/gate/check.sh',
        ConvergenceFields.gateTimeout: '60s',
        ConvergenceFields.gateTimeoutAction: 'iterate',
        ConvergenceFields.activeWisp: '$root-w1',
      };

      final source = FakeConvergenceSource(
        snapWith(
          roots: [rootBead(baseMeta)],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      final process = FakeProcessRunner();
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gateOver(process),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      // iter-1 closes, gate FAILS (1 < max 3) → iterate to iter-2.
      process.stub('/gate/check.sh', FakeRun.exited(1));
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...baseMeta,
              ConvergenceFields.activeWisp: '$root-w2',
              ConvergenceFields.lastProcessedWisp: '$root-w1',
            }),
          ],
          children: {
            root: [
              closedWisp(root, 1),
              wispBead(
                '$root-w2',
                key: idempotencyKey(root, 2),
                status: BeadStatus.open,
              ),
            ],
          },
        ),
      );

      // iter-2 closes, gate FAILS (2 < max 3) → iterate to iter-3 (== max).
      process.stub('/gate/check.sh', FakeRun.exited(1));
      actuator.nextResult = const ActuationResult(
        pouredWispId: '$root-w3-spec',
      );
      source.emit(beadClosedEvent(closedWisp(root, 2), closedWisp(root, 2)));
      await runtime.idle();
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...baseMeta,
              ConvergenceFields.activeWisp: '$root-w3',
              ConvergenceFields.lastProcessedWisp: '$root-w2',
            }),
          ],
          children: {
            root: [
              closedWisp(root, 1),
              closedWisp(root, 2),
              wispBead(
                '$root-w3',
                key: idempotencyKey(root, 3),
                status: BeadStatus.open,
              ),
            ],
          },
        ),
      );

      // iter-3 closes (iteration 3 == max 3), gate FAILS → the budget is spent:
      // iter >= max ∧ gate != pass → no_convergence (NOT a fourth iterate).
      process.stub('/gate/check.sh', FakeRun.exited(1));
      source.emit(beadClosedEvent(closedWisp(root, 3), closedWisp(root, 3)));
      await runtime.idle();
      await runtime.dispose();

      final iterates = actuator.actions.whereType<IterateAction>().toList();
      final noConv = actuator.actions.whereType<NoConvergenceAction>().toList();
      expect(iterates.length, 2, reason: 'iter-1 and iter-2 iterated');
      expect(noConv.length, 1, reason: 'iter-3 at max → no_convergence');
      expect(noConv.single.wire, 'no_convergence');
      // No speculative pour at the budget boundary (handler.go:254 guard): the
      // terminal closure poured nothing it must burn.
      expect(noConv.single.burnPriorPour, isFalse);
      // The gate ran once per closure (3 closures).
      expect(process.calls.length, 3);
    });
  });

  group('lifecycle: manual hold → operator command (chained)', () {
    /// Builds a runtime over a manual-gate active loop whose active wisp has
    /// just closed (unprocessed) and runs the closure → waiting_manual, then
    /// returns the runtime + actuator + source so a caller can issue the
    /// operator command over post-transition state.
    Future<
      ({
        ReconcilerRuntime runtime,
        RecordingActuator actuator,
        FakeConvergenceSource source,
      })
    >
    driveToManualHold(String root) async {
      Bead rootBead(Map<String, dynamic> meta) =>
          convergenceBead(root, metadata: meta);
      final activeMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'manual',
        ConvergenceFields.activeWisp: '$root-w1',
        // last_processed absent ⇒ w1 unprocessed.
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [rootBead(activeMeta)],
          children: {
            root: [closedWisp(root, 1)],
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

      // The active wisp closes → manual gate short-circuits → waiting_manual.
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();

      // Advance the store to reflect the manual-hold transition the actuator
      // committed (state=waiting_manual, last_processed=w1).
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...activeMeta,
              ConvergenceFields.state: 'waiting_manual',
              ConvergenceFields.waitingReason: 'manual',
              ConvergenceFields.activeWisp: '',
              ConvergenceFields.lastProcessedWisp: '$root-w1',
            }),
          ],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      return (runtime: runtime, actuator: actuator, source: source);
    }

    test('wispClosed (manual) → waiting_manual, then operator APPROVE → '
        'terminated/approved (manual.go:20-115)', () async {
      const root = 'MH';
      final h = await driveToManualHold(root);
      // The hold transition fired in the runtime.
      final manual = h.actuator.actions.whereType<WaitingManualAction>().single;
      expect(manual.reason.wire, WaitingReason.manual.wire);

      final out = await h.runtime.submit(
        ReducerEvent.operatorApprove(convergenceBeadId: root, user: 'alice'),
      );
      await h.runtime.idle();
      await h.runtime.dispose();

      expect(out.status, CycleStatus.actuated);
      final approved = h.actuator.actions.whereType<ApprovedAction>().single;
      expect(approved.wire, 'approved');
      expect(approved.path, TerminalPath.operatorApprove);
      expect(approved.actor, 'operator:alice');
      expect(approved.iteration, 1); // derived closed-child count.
    });

    test('wispClosed (manual) → waiting_manual, then operator ITERATE → '
        'active/iterate at the next iteration (manual.go:124-217)', () async {
      const root = 'MI';
      final h = await driveToManualHold(root);
      expect(h.actuator.actions.whereType<WaitingManualAction>(), hasLength(1));
      h.actuator.nextResult = const ActuationResult(pouredWispId: '$root-w2');

      final out = await h.runtime.submit(
        ReducerEvent.operatorIterate(convergenceBeadId: root, user: 'alice'),
      );
      await h.runtime.idle();
      await h.runtime.dispose();

      expect(out.status, CycleStatus.actuated);
      final iterate = h.actuator.actions.whereType<IterateAction>().single;
      expect(iterate.path, IteratePath.operatorIterate);
      expect(iterate.iteration, 2); // derived 1 + 1.
      expect(iterate.pour.idempotencyKey, 'converge:$root:iter:2');
      // The operator iterate writes NO dedup marker (manual.go has no
      // last_processed write on iterate).
      final w = iterate.postPourWrites('$root-w2');
      expect(
        w.any((m) => m.key == ConvergenceFields.lastProcessedWisp),
        isFalse,
      );
    });
  });

  group('lifecycle: trigger-gated hold → advance (chained)', () {
    test('wispClosed on a trigger-gated active loop → waiting_trigger '
        '(no next pour), then triggerPassed → active/iterate '
        '(trigger.go:129-180; T6 → T10)', () async {
      const root = 'TG';
      Bead rootBead(Map<String, dynamic> meta) =>
          convergenceBead(root, metadata: meta);
      // Active, condition gate, AND a trigger configured: a gate-fail closure
      // holds in waiting_trigger instead of pouring the next wisp.
      final activeMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'condition',
        ConvergenceFields.gateCondition: '/gate/check.sh',
        ConvergenceFields.gateTimeout: '60s',
        ConvergenceFields.gateTimeoutAction: 'iterate',
        ConvergenceFields.activeWisp: '$root-w1',
        ConvergenceFields.trigger: 'event',
        ConvergenceFields.triggerCondition: '/trigger/check.sh',
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [rootBead(activeMeta)],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      final actuator = RecordingActuator(
        // Phase 1 pours a speculative wisp; the trigger-gated terminal burns it.
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      final process = FakeProcessRunner()
        ..stub(
          '/gate/check.sh',
          FakeRun.exited(1),
        ); // gate FAIL → would iterate
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gateOver(process),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();

      // iter-1 closes: fresh condition gate fails, but a trigger gates the loop
      // → hold in waiting_trigger, NO next wisp poured/adopted.
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();

      final hold = actuator.actions.whereType<WaitingTriggerAction>().toList();
      expect(hold, hasLength(1), reason: 'trigger gates the iterate → hold');
      expect(hold.single.wire, 'waiting_trigger');
      // The trigger-gated terminal pours no successor it keeps — there is no
      // IterateAction in this closure.
      expect(actuator.actions.whereType<IterateAction>(), isEmpty);
      expect(process.calls.length, 1, reason: 'the gate ran once for w1');

      // Advance the store to waiting_trigger, last_processed=w1, iteration 1.
      source.setSnapshot(
        snapWith(
          roots: [
            rootBead({
              ...activeMeta,
              ConvergenceFields.state: 'waiting_trigger',
              ConvergenceFields.activeWisp: '',
              ConvergenceFields.lastProcessedWisp: '$root-w1',
            }),
          ],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );

      // The trigger condition later passes for iteration 2 → advance to active.
      actuator.nextResult = const ActuationResult(pouredWispId: '$root-w2');
      final out = await runtime.submit(
        ReducerEvent.triggerPassed(convergenceBeadId: root, nextIteration: 2),
      );
      await runtime.idle();
      await runtime.dispose();

      expect(out.status, CycleStatus.actuated);
      final advance = actuator.actions.whereType<IterateAction>().single;
      expect(advance.path, IteratePath.triggerAdvance);
      expect(advance.iteration, 2);
      expect(advance.pour.idempotencyKey, 'converge:$root:iter:2');
      // trigger advance WRITES the iteration counter and ends at state=active.
      final w = advance.postPourWrites('$root-w2');
      expect(w.first.key, ConvergenceFields.iteration);
      expect(w.last.key, ConvergenceFields.state);
      expect(w.last.value, ConvergenceState.active.wire);
    });
  });

  group('lifecycle: gate timeout → action=retry', () {
    test('a deadlined gate with timeout_action=retry is a normal '
        'GateOutcome.timeout (NOT an A25 live error) and the runtime reduces '
        'the retry timeout action into a transition (gate.go retry row, '
        'handler.go:336-344)', () async {
      const root = 'RT';
      final activeMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'condition',
        ConvergenceFields.gateCondition: '/gate/slow.sh',
        ConvergenceFields.gateTimeout: '100ms',
        ConvergenceFields.gateTimeoutAction: 'retry',
        ConvergenceFields.activeWisp: '$root-w1',
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [convergenceBead(root, metadata: activeMeta)],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      // The gate DEADLINES → GateOutcome.timeout (a transition, not a launch
      // failure → A25). timeout_action=retry re-runs the gate up to the gate
      // retry budget (GateTimeoutAction.maxGateRetries == 3, so 1 + 3 = 4 runs
      // on consecutive deadlines, gate_runner_service.dart:66 / condition.go
      // RunCondition). Once the budget is spent the timeout is non-terminal
      // (not manual, not terminate, below max) → iterate (handler.go:370-382).
      final process = FakeProcessRunner()
        ..stubRepeated('/gate/slow.sh', FakeRun.deadline(), 4);
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gateOver(process),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
        onError: (e, _) => fail('a gate timeout must NOT be a live error: $e'),
      );
      await runtime.start();
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();
      await runtime.dispose();

      // No cycle failed — the timeout is a transition, not a deferred live
      // error (A25). This is the load-bearing distinction for the retry action.
      expect(
        runtime.outcomes.any((o) => o.isFailure),
        isFalse,
        reason: 'timeout+retry is a transition, not A25',
      );
      // The gate re-ran the FULL retry budget on consecutive deadlines: 1 + 3
      // = 4 process spawns (GateTimeoutAction.maxGateRetries; gc's
      // TestRunConditionTimeoutRetry RetryCount==budget on a persistent
      // deadline, condition_test.go:734-755).
      expect(
        process.calls.length,
        4,
        reason: 'retry budget exhausted over 4 consecutive deadlines',
      );
      // The retry timeout-action resolves to a real transition (the gate ran,
      // and the loop iterates after the retry budget — never a no-op skip).
      final transition = actuator.actions.where((a) => a.wire != null).toList();
      expect(
        transition.whereType<SkippedAction>(),
        isEmpty,
        reason: 'a deadlined retry gate produced a real transition',
      );
      expect(
        actuator.actions.any(
          (a) => a is IterateAction || a is NoConvergenceAction,
        ),
        isTrue,
        reason:
            'timeout+retry resolves to iterate (default) once the budget '
            'is spent — a real terminal/iterate transition, not a stall',
      );
    });
  });

  group('lifecycle: operator-stop drain (the gate-pass composition, A19)', () {
    test('a stop on a closed-but-unprocessed active wisp whose gate PASSES '
        'drains through the handler, which APPROVES the loop, making the stop '
        'a no-op (TestStopHandler_DrainCompletedIteration, stop_test.go:52) '
        '— the drain ITSELF produces terminated/approved, NOT a manual hold', () async {
      const root = 'DA';
      // gc's setupActiveHandler shape: active loop, active_wisp=iter-2 CLOSED
      // but unprocessed (last_processed at iter-1), with a CACHED passing gate
      // (gate_outcome_wisp==active wisp, gate_outcome==pass — the replay
      // branch). The stop drains the closed wisp inline; the replay gate pass
      // terminates the loop as approved-via-the-handler-path, so the postDrain
      // re-entry is a no-op drainTerminated skip. This is the gate-pass drain
      // COMPOSITION the existing drain e2e tests never actuate: the manual-gate
      // drain short-circuits to waiting_manual (never approves) and the
      // condition-gate drain uses a default-fail FakeGate (iterates).
      final root2 = convergenceBead(
        root,
        metadata: {
          ConvergenceFields.state: 'active',
          ConvergenceFields.iteration: '1',
          ConvergenceFields.maxIterations: '5',
          ConvergenceFields.formula: 'f',
          ConvergenceFields.gateMode: 'condition',
          ConvergenceFields.gateCondition: '/gate/check.sh',
          ConvergenceFields.activeWisp: '$root-w2',
          ConvergenceFields.lastProcessedWisp: '$root-w1',
          // The cached gate outcome scoped to the closed active wisp → replay
          // branch (skipGateEval) → no fresh gate, the drain reduces in one
          // pass to the terminal.
          ConvergenceFields.gateOutcomeWisp: '$root-w2',
          ConvergenceFields.gateOutcome: GateOutcome.pass.wire,
        },
      );
      final source = FakeConvergenceSource(
        snapWith(
          roots: [root2],
          children: {
            root: [closedWisp(root, 1), closedWisp(root, 2)],
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
        ReducerEvent.operatorStop(convergenceBeadId: root, user: 'alice'),
      );
      await runtime.idle();
      await runtime.dispose();

      // The first reduce returned the drain pipeline + a postDrain requeue.
      expect(out.status, CycleStatus.requeued);
      expect((out.requeued! as OperatorStopEvent).postDrain, isTrue);

      // The drain ITSELF produced the terminated/approved transition — the
      // load-bearing assertion (gc's meta[FieldTerminalReason]==TerminalApproved
      // "drain should have approved"). No waiting_manual hold, no stopped
      // terminal: the gate-pass drain is what terminates the loop.
      final approved = actuator.actions.whereType<ApprovedAction>().single;
      expect(approved.wire, 'approved');
      expect(approved.path, TerminalPath.handlerWispClosed);
      expect(approved.gateOutcome, GateOutcome.pass);
      expect(approved.lastProcessedWisp, '$root-w2');
      expect(
        actuator.actions.whereType<WaitingManualAction>(),
        isEmpty,
        reason: 'a passing-gate drain approves; it does NOT hold for manual',
      );
      expect(
        actuator.actions.whereType<StoppedAction>(),
        isEmpty,
        reason: 'the stop is a no-op — the drain already terminated the loop',
      );

      // The postDrain stop re-entry, over the now terminated/approved loop, is
      // a drainTerminated skip (gc's no-reason ActionStopped, manual.go:303-308).
      final reentry = runtime.outcomes
          .map((o) => o.primary)
          .whereType<SkippedAction>()
          .where((s) => s.reason == SkipReason.drainTerminated)
          .toList();
      expect(
        reentry,
        hasLength(1),
        reason: 'the postDrain stop saw terminated/approved → drainTerminated',
      );
    });
  });

  group('lifecycle: hybrid gate driven through the real runtime', () {
    test('a hybrid-gate loop (agent verdict scoped to the closed wisp + a '
        'condition gate) drives the phase split: phase 1 threads the verdict '
        'into the gate env (GC_AGENT_VERDICT), phase 2 fires the terminal '
        '(handler.go:317-327; hybrid.go:8-22)', () async {
      const root = 'HY';
      // Active loop, gate_mode=hybrid WITH a condition (so the gate runs — not
      // the hybrid-no-condition manual fallback, which is the H08 reducer
      // case). An agent verdict scoped to the closing wisp must be injected
      // verbatim into the gate subprocess env (the hybrid verdict channel, D3:
      // read, not reinterpreted) and the script's exit code decides the
      // outcome. This is the reduce→gate(hybrid)→actuate composition the
      // per-component units (gate_phase_split, handler_conformance H08, the
      // gate-runner hybrid matrix) never exercise end-to-end.
      final activeMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'hybrid',
        ConvergenceFields.gateCondition: '/gate/hybrid.sh',
        ConvergenceFields.gateTimeout: '60s',
        ConvergenceFields.gateTimeoutAction: 'iterate',
        ConvergenceFields.activeWisp: '$root-w1',
        // Verdict scoped to the closing wisp — gc reads it only when
        // agent_verdict_wisp == the closing wisp (handler.go:318-323).
        ConvergenceFields.agentVerdict: 'approve',
        ConvergenceFields.agentVerdictWisp: '$root-w1',
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [convergenceBead(root, metadata: activeMeta)],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      final actuator = RecordingActuator();
      // The hybrid condition script exits 0 → pass → terminal approved.
      final process = FakeProcessRunner()
        ..stub('/gate/hybrid.sh', FakeRun.exited(0));
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gateOver(process),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();
      await runtime.dispose();

      // Phase 1's gate ran the hybrid condition exactly once, AND the scoped
      // verdict threaded into the subprocess env verbatim (the hybrid verdict
      // channel; pure condition mode would omit GC_AGENT_VERDICT).
      expect(process.calls.length, 1);
      final call = process.calls.single;
      expect(call.executable, '/gate/hybrid.sh');
      expect(
        call.environment['GC_AGENT_VERDICT'],
        'approve',
        reason: 'hybrid mode injects the scoped verdict into the gate env',
      );

      // Phase 2 read the gate pass and fired the terminal transition.
      final approved = actuator.actions.whereType<ApprovedAction>().single;
      expect(approved.wire, 'approved');
      expect(approved.path, TerminalPath.handlerWispClosed);
      expect(approved.gateOutcome, GateOutcome.pass);
      expect(
        runtime.outcomes.map((o) => o.status),
        containsAll([CycleStatus.gateEvaluated, CycleStatus.actuated]),
      );
    });

    test('a hybrid-gate FAIL below max iterates (the phase-split iterate arm) '
        '— the verdict is still injected', () async {
      const root = 'HZ';
      final activeMeta = <String, dynamic>{
        ConvergenceFields.state: 'active',
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'hybrid',
        ConvergenceFields.gateCondition: '/gate/hybrid.sh',
        ConvergenceFields.gateTimeout: '60s',
        ConvergenceFields.gateTimeoutAction: 'iterate',
        ConvergenceFields.activeWisp: '$root-w1',
        ConvergenceFields.agentVerdict: 'block',
        ConvergenceFields.agentVerdictWisp: '$root-w1',
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [convergenceBead(root, metadata: activeMeta)],
          children: {
            root: [closedWisp(root, 1)],
          },
        ),
      );
      final actuator = RecordingActuator(
        nextResult: const ActuationResult(pouredWispId: '$root-w2-spec'),
      );
      // The hybrid condition exits 1 → fail → iterate (1 < max 5).
      final process = FakeProcessRunner()
        ..stub('/gate/hybrid.sh', FakeRun.exited(1));
      final runtime = ReconcilerRuntime(
        source: source,
        actuator: actuator,
        gateEvaluator: gateOver(process),
        ownership: const OwnsEverything(),
        runRecoveryAtStartup: false,
      );
      await runtime.start();
      source.emit(beadClosedEvent(closedWisp(root, 1), closedWisp(root, 1)));
      await runtime.idle();
      await runtime.dispose();

      expect(process.calls.length, 1);
      expect(process.calls.single.environment['GC_AGENT_VERDICT'], 'block');
      final iterate = actuator.actions.whereType<IterateAction>().single;
      expect(iterate.path, IteratePath.wispClosed);
      // Phase 1 poured the speculative wisp + handed off the gate.
      expect(actuator.actions.whereType<PourSpeculativeAction>(), isNotEmpty);
      expect(
        actuator.actions.whereType<PersistGateOutcomeAction>(),
        isNotEmpty,
      );
    });
  });

  group('lifecycle: operator-stop from a HOLD state through the real runtime', () {
    /// A stop from a hold state (waiting_manual / waiting_trigger) has NO
    /// active wisp to drain or force-close: gc permits the stop from all three
    /// of active/waiting_manual/waiting_trigger (manual.go:258-263) and the
    /// hold-state stop goes straight to the terminal (no drain branch, no
    /// synthetic force-close iteration event — TestStopHandler_FromWaitingManual_
    /// NoForceClose stop_test.go:204). Drives the runtime's NON-drain stop
    /// orchestration end-to-end (the per-component G-STOP-4 / M15 only call the
    /// reducer directly).
    Future<({CycleOutcome out, RecordingActuator actuator})> stopFromHold({
      required String root,
      required String state,
      Map<String, dynamic> extra = const {},
    }) async {
      final meta = <String, dynamic>{
        ConvergenceFields.state: state,
        ConvergenceFields.iteration: '1',
        ConvergenceFields.maxIterations: '5',
        ConvergenceFields.formula: 'f',
        ConvergenceFields.gateMode: 'manual',
        // A hold state has no active_wisp pointer; one closed processed wisp.
        ConvergenceFields.lastProcessedWisp: '$root-w1',
        ...extra,
      };
      final source = FakeConvergenceSource(
        snapWith(
          roots: [convergenceBead(root, metadata: meta)],
          children: {
            root: [closedWisp(root, 1)],
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
        ReducerEvent.operatorStop(convergenceBeadId: root, user: 'alice'),
      );
      await runtime.idle();
      await runtime.dispose();
      return (out: out, actuator: actuator);
    }

    test('stop from waiting_manual → StoppedAction terminal, NO drain, NO '
        'force-close (manual.go:258; G-STOP-4 / M15 driven e2e)', () async {
      final r = await stopFromHold(
        root: 'WM',
        state: 'waiting_manual',
        extra: {ConvergenceFields.waitingReason: 'manual'},
      );
      expect(r.out.status, CycleStatus.actuated);
      final stopped = r.actuator.actions.whereType<StoppedAction>().single;
      expect(stopped.wire, 'stopped');
      // No active wisp ⇒ nothing force-closed (the hold-state stop is a plain
      // terminal, gc's TestStopHandler_FromWaitingManual_NoForceClose).
      expect(stopped.forceCloseWispId, isNull);
      // No drain pipeline ran: a hold-state stop has no closed active wisp.
      expect(r.actuator.actions.whereType<RequeueAction>(), isEmpty);
      expect(r.actuator.actions.whereType<WaitingManualAction>(), isEmpty);
    });

    test('stop from waiting_trigger → StoppedAction terminal, NO drain, NO '
        'force-close (manual.go:258; G-STOP-4 driven e2e)', () async {
      final r = await stopFromHold(root: 'WT', state: 'waiting_trigger');
      expect(r.out.status, CycleStatus.actuated);
      final stopped = r.actuator.actions.whereType<StoppedAction>().single;
      expect(stopped.wire, 'stopped');
      expect(stopped.forceCloseWispId, isNull);
      expect(r.actuator.actions.whereType<RequeueAction>(), isEmpty);
    });
  });
}
