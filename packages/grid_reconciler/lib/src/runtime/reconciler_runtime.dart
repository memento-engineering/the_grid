import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import '../actuator/actuator.dart';
import '../actuator/bd_actuator.dart' show ActuationFailed;
import '../convergence/gate_result.dart';
import '../convergence/reconciler_action.dart';
import '../convergence/reducer_event.dart';
import '../projections/convergence.dart';
import '../reducer/reduce.dart';
import '../reducer/reduce_result.dart';
import '../recovery/recovery_pass.dart';
import 'convergence_source.dart';
import 'cycle_outcome.dart';
import 'gate_evaluator.dart';
import 'graph_event_adapter.dart';
import 'ownership.dart';
import 'per_bead_queue.dart';
import 'write_through_overlay.dart';

/// The reconciler runtime — the composition that makes the convergence machine
/// actually run (M2 Track G; ADR-0003 Decision 2).
///
/// It subscribes to beads_dart's `GraphEvent` stream (via a
/// [ConvergenceSource]), routes each event to the convergence loop it concerns,
/// and runs gc's reduce→gate→actuate cycle for that loop — serialized per bead
/// (invariant 7), evaluated against post-actuation state (the write-through
/// overlay, A17), gated by the ownership partition (Decision 6), and backstopped
/// by a periodic full recovery pass (Track C).
///
/// **Per-bead serialization (invariant 7).** Every event for the SAME
/// convergence root runs strictly in arrival order through a [PerBeadQueue]
/// mutex; DIFFERENT roots proceed concurrently — a slow gate on loop A never
/// blocks loop B. This is the single-writer-per-bead guarantee gc gets from its
/// one event loop (handler.go:143-145), reconstructed for a concurrent,
/// event-driven runtime.
///
/// **The reduce→gate→actuate cycle.** Each ingested event reduces over
/// the (overlaid) [Convergence]; if the reduce hands off a fresh gate
/// ([EvaluateGateAction]), the runtime runs Track D's [GateEvaluator] and
/// re-enters the reducer with `ReducerEvent.gateEvaluated` (the A22 phase
/// split), carrying the phase-1 speculative-pour outcome; the resulting
/// [ReduceResult] executes through the [Actuator]. A [RequeueAction]
/// (`OperatorStopEvent(postDrain: true)`) is re-enqueued behind the synthesized
/// drain pipeline on the same per-bead queue (the A19 drain protocol).
///
/// **Write-through freshness (A17).** Each actuation's metadata writes are
/// recorded in a [WriteThroughOverlay] and layered over the snapshot before the
/// next reduce for that bead — so a fast gate/closure that beats the Dolt
/// watcher cannot re-fire a transition (the duplicate-pour race). The actuator's
/// live idempotency probe (A26) is the second line of defense.
///
/// **The deferred live-error contract (A25).** A real store/probe/actuation
/// failure mid-transition surfaces as an [ActuationFailed]; the runtime records
/// a `failed` [CycleOutcome] and performs NO further mutation for that bead this
/// cycle. The loop is left at its prior state with no commit marker, so the next
/// cycle (or the periodic recovery pass) retries idempotently — the invariants
/// make replay safe.
///
/// **Coexistence (Decision 6).** Only loops the [OwnershipPredicate] accepts are
/// actuated; everything else is observed read-only (shadow mode is the dedicated
/// read-only runtime, [ShadowRuntime]). An event for a non-owned loop is reduced
/// for diagnostics but never actuated.
class ReconcilerRuntime {
  ReconcilerRuntime({
    required ConvergenceSource source,
    required Actuator actuator,
    required GateEvaluator gateEvaluator,
    OwnershipPredicate ownership = const OwnsNothing(),
    GraphEventAdapter adapter = const GraphEventAdapter(),
    Duration recoveryInterval = const Duration(seconds: 30),
    bool runRecoveryAtStartup = true,
    void Function(CycleOutcome outcome)? onCycle,
    void Function(Object error, StackTrace stack)? onError,
  }) : _source = source,
       _actuator = actuator,
       _gate = gateEvaluator,
       _ownership = ownership,
       _adapter = adapter,
       _recoveryInterval = recoveryInterval,
       _runRecoveryAtStartup = runRecoveryAtStartup,
       _onCycle = onCycle,
       _onError = onError;

  final ConvergenceSource _source;
  final Actuator _actuator;
  final GateEvaluator _gate;
  final OwnershipPredicate _ownership;
  final GraphEventAdapter _adapter;
  final Duration _recoveryInterval;
  final bool _runRecoveryAtStartup;
  final void Function(CycleOutcome)? _onCycle;
  final void Function(Object, StackTrace)? _onError;

  final PerBeadQueue _queue = PerBeadQueue();
  final WriteThroughOverlay _overlay = WriteThroughOverlay();

  StreamSubscription<GraphEvent>? _eventSub;
  StreamSubscription<GraphSnapshot>? _snapshotSub;
  Timer? _recoveryTimer;
  bool _started = false;
  bool _disposed = false;
  bool _recoveryInFlight = false;

  /// Every cycle outcome, in order (diagnostics / tests).
  final List<CycleOutcome> outcomes = [];

  /// How many times [runRecovery] has begun a pass (diagnostics / tests). The
  /// re-entrancy guard ([_recoveryInFlight]) keeps the periodic backstop from
  /// starting a pass while a prior one is still running, so this counts the
  /// passes that actually entered — gc's one-pass-at-a-time cadence.
  int recoveryPasses = 0;

  /// Subscribes the event + snapshot streams, runs the startup recovery pass,
  /// and arms the periodic backstop. Idempotent.
  ///
  /// The periodic recovery timer is a [Timer.periodic] at [recoveryInterval] —
  /// production runs it in real time; fake_async tests drive the same timer
  /// under their own zone. The cadence defaults near gc's 30s patrol tick
  /// (cmd/gc/convergence_tick.go; config default 30s).
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;

    _snapshotSub = _source.snapshots.listen(
      _onSnapshot,
      onError: _reportStreamError,
    );
    _eventSub = _source.events.listen(_onEvent, onError: _reportStreamError);

    if (_runRecoveryAtStartup) {
      await runRecovery();
    }
    _recoveryTimer = Timer.periodic(_recoveryInterval, (_) {
      // The periodic pass is fire-and-forget on the timer, but a single pass
      // must complete before the next begins: gc never overlaps its recovery
      // (convergenceStartupReconcile + processConvergenceRequests +
      // convergenceTick all run sequentially on the one select-loop,
      // city_runtime.go:1223-1229). A pass that outruns the interval (many
      // owned beads, a backed-up per-bead queue behind a slow gate) would
      // otherwise have two passes capturing+applying plans before either's
      // writes reach a new snapshot — the [_recoveryInFlight] guard restores
      // gc's one-pass-at-a-time cadence. (The re-reduce-over-overlay fix above
      // already defuses the double-apply; this guard is independently warranted
      // to match the single-loop cadence and bound concurrency.)
      unawaited(_safeRecovery());
    });
  }

  // ===========================================================================
  // Event ingestion → per-bead serialized processing
  // ===========================================================================

  void _onEvent(GraphEvent event) {
    final mapped = _adapter.adapt(event, _source.convergences);
    if (mapped == null) return;
    // Serialize per convergence root (invariant 7). The queue returns a Future;
    // we don't await it here (the stream callback is sync), but the queue keeps
    // same-bead cycles ordered. A cycle error never escapes — the deferred
    // live-error contract already records a `failed` outcome; this guard only
    // catches an unexpected throw above the cycle's own try/catch.
    unawaited(
      _queue.run<CycleOutcome>(mapped.event.convergenceBeadId, () async {
        try {
          return await _runCycle(mapped.event);
        } on Object catch (e, st) {
          _onError?.call(e, st);
          return CycleOutcome.noop(mapped.event.convergenceBeadId);
        }
      }),
    );
  }

  void _onSnapshot(GraphSnapshot snapshot) {
    // Reconcile the overlay against the fresh snapshot: drop overlay keys the
    // snapshot has caught up to, keep the rest (the watcher may still lag).
    for (final bead in snapshot.beads) {
      if (bead.issueType != IssueType.convergence) continue;
      _overlay.reconcileWithSnapshot(bead.id, bead.metadata);
    }
  }

  /// Submits an out-of-band reducer event (an operator command minted by the
  /// command surface, or a trigger pass from the trigger poller) onto the same
  /// per-bead serial queue the live closure events use.
  Future<CycleOutcome> submit(ReducerEvent event) =>
      _queue.run(event.convergenceBeadId, () => _runCycle(event));

  /// Completes once stream-delivered events have been ingested and the per-bead
  /// queue has drained — the test settle point. Broadcast-stream delivery is
  /// asynchronous, so a freshly-[emit]ted event reaches [_onEvent] only after
  /// the event loop turns; this pumps the loop, then awaits the queue. Pumps a
  /// few turns so a cycle that enqueues a follow-up (a phase-split re-entry runs
  /// inline, but a stream-driven snapshot can land mid-cycle) settles too.
  Future<void> idle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
      await _queue.idle();
    }
  }

  // ===========================================================================
  // The reduce → gate → actuate cycle
  // ===========================================================================

  /// Runs one full cycle for [event] (already serialized for its bead). Handles
  /// the phase split (fresh gate) and the operator-stop drain requeue inline,
  /// since both stay on this bead's serial turn.
  Future<CycleOutcome> _runCycle(ReducerEvent event) async {
    final beadId = event.convergenceBeadId;
    final convergence = _currentConvergence(beadId);
    if (convergence == null) {
      final out = CycleOutcome.noop(beadId);
      _record(out);
      return out;
    }

    final snapshot = _source.current;
    if (snapshot == null) {
      final out = CycleOutcome.noop(beadId);
      _record(out);
      return out;
    }

    // The coexistence partition (ADR-0003 Decision 6) gates the WHOLE cycle, not
    // just the terminal actuation: a non-owned loop's events are reduced for
    // diagnostics but NEVER actuated — and crucially the cycle must not run the
    // gate or pour speculatively against a bead gc owns (that is a mutation /
    // a subprocess against another writer's loop). Reduce-only, no actuation.
    if (!_ownership.owns(convergence)) {
      final result = ConvergenceReducer.reduce(convergence, event, snapshot);
      final out = CycleOutcome(
        convergenceBeadId: beadId,
        status: CycleStatus.skipped,
        result: result,
      );
      _record(out);
      return out;
    }

    final result = ConvergenceReducer.reduce(convergence, event, snapshot);
    return _executeReduceResult(
      beadId: beadId,
      convergence: convergence,
      snapshot: snapshot,
      event: event,
      result: result,
    );
  }

  /// Executes a [ReduceResult] — resolving the fresh-gate phase split and the
  /// operator-stop drain requeue, then actuating. Recursion depth is bounded:
  /// the phase split re-enters once (gateEvaluated never re-emits an
  /// evaluateGate), and the drain re-enters once (postDrain is absorbed).
  Future<CycleOutcome> _executeReduceResult({
    required String beadId,
    required Convergence convergence,
    required GraphSnapshot snapshot,
    required ReducerEvent event,
    required ReduceResult result,
  }) async {
    // The drain carrier (operator-stop inline drain, A19) MUST be checked
    // before the gate handoff. When the drained active wisp triggers a *fresh*
    // condition/hybrid gate, the reducer returns
    // `[pourSpeculative, evaluateGate, requeue(postDrain)]` — routing on
    // `evaluateGate` alone would run the gate but DROP the requeue, silently
    // losing the operator stop (the loop would never terminate). `_runDrain`
    // resolves that inner gate through the same phase machinery AND re-enters
    // the postDrain stop, so route there first.
    final requeue = _findRequeue(result);
    if (requeue != null) {
      return _runDrain(
        beadId: beadId,
        convergence: convergence,
        result: result,
        requeue: requeue,
      );
    }

    // Phase 1 of a fresh gate: run the gate, re-enter the reducer (phase 2).
    final evaluateGate = _findEvaluateGate(result);
    if (evaluateGate != null) {
      return _runGatePhase(
        beadId: beadId,
        convergence: convergence,
        result: result,
        evaluateGate: evaluateGate,
      );
    }

    return _actuate(beadId, convergence, event, result);
  }

  /// Phase split: run Track D's gate for [evaluateGate], thread its result +
  /// the phase-1 speculative-pour outcome back into the reducer as
  /// `gateEvaluated`, and execute the phase-2 transition.
  Future<CycleOutcome> _runGatePhase({
    required String beadId,
    required Convergence convergence,
    required ReduceResult result,
    required EvaluateGateAction evaluateGate,
  }) async {
    // Execute phase-1 effects (repairIteration, the speculative pour) so the
    // pour id is available to thread into phase 2 and the overlay reflects the
    // pre-gate writes. The actuator returns the poured wisp id (gc's
    // speculativeWispID); a deferred pour failure is signalled by no id.
    ActuationResult phase1;
    try {
      phase1 = await _applyActions(beadId, convergence, result.actions);
    } on ActuationFailed catch (e) {
      return _failure(beadId, result, e);
    }

    final GateResult gateResult;
    try {
      gateResult = await _gate.evaluate(evaluateGate);
    } on Object catch (e, st) {
      // A real gate-runner failure is a live error (A25): no transition.
      _onError?.call(e, st);
      final out = CycleOutcome(
        convergenceBeadId: beadId,
        status: CycleStatus.failed,
        result: result,
        error: e,
      );
      _record(out);
      return out;
    }

    // Re-read the (overlaid) convergence — phase-1 writes (pending_next_wisp,
    // repaired iteration) are now visible, so phase 2 reduces over fresh state.
    final fresh = _currentConvergence(beadId) ?? convergence;
    final snapshot = _source.current;
    if (snapshot == null) return _noop(beadId);

    final phase2Event = ReducerEvent.gateEvaluated(
      convergenceBeadId: beadId,
      wispId: evaluateGate.wispId,
      result: gateResult,
      pouredSpeculativeWispId: phase1.pouredWispId,
      pourFailed: phase1.pourFailed,
    );
    final phase2 = ConvergenceReducer.reduce(fresh, phase2Event, snapshot);
    final out = await _actuate(beadId, fresh, phase2Event, phase2);
    // Tag phase 1 in the trace for observability (phase 2 carries its own).
    _record(
      CycleOutcome(
        convergenceBeadId: beadId,
        status: CycleStatus.gateEvaluated,
        result: result,
        actuation: phase1,
      ),
    );
    return out;
  }

  /// The operator-stop drain (A19): execute every action up to (and including)
  /// the drain pipeline, then re-enqueue the carried `OperatorStopEvent(
  /// postDrain: true)` behind it — on the SAME per-bead turn, so the re-entry
  /// reduces over post-drain state with the per-bead lock still held.
  Future<CycleOutcome> _runDrain({
    required String beadId,
    required Convergence convergence,
    required ReduceResult result,
    required RequeueAction requeue,
  }) async {
    // The drain actions are everything except the requeue carrier itself.
    final drainActions = result.actions
        .where((a) => a is! RequeueAction)
        .toList(growable: false);

    // The drain may itself be a fresh-gate handoff (the closed active wisp's
    // gate eval, possibly multi-minute in gc). Resolve it through the same
    // phase machinery so a slow drain gate stays on this bead's turn.
    final drainResult = ReduceResult(drainActions);
    final drainEvaluateGate = _findEvaluateGate(drainResult);
    if (drainEvaluateGate != null) {
      await _runGatePhase(
        beadId: beadId,
        convergence: convergence,
        result: drainResult,
        evaluateGate: drainEvaluateGate,
      );
    } else if (drainActions.isNotEmpty) {
      try {
        await _applyActions(beadId, convergence, drainActions);
      } on ActuationFailed catch (e) {
        // A failed drain leaves the loop at prior state; the re-entry will
        // re-drain next cycle. Record + stop (no requeue this cycle).
        return _failure(beadId, result, e);
      }
    }

    // Re-enter the deferred stop over post-drain state (postDrain marker on the
    // carried event — never stripped). Same serial turn.
    final reentry = _currentConvergence(beadId);
    final snapshot = _source.current;
    final out = CycleOutcome(
      convergenceBeadId: beadId,
      status: CycleStatus.requeued,
      result: result,
      requeued: requeue.event,
    );
    _record(out);
    if (reentry != null && snapshot != null) {
      final reResult = ConvergenceReducer.reduce(
        reentry,
        requeue.event,
        snapshot,
      );
      await _executeReduceResult(
        beadId: beadId,
        convergence: reentry,
        snapshot: snapshot,
        event: requeue.event,
        result: reResult,
      );
    }
    return out;
  }

  /// Actuates [result] — gated by ownership — and records the trace. A
  /// no-op/skip result records `skipped`; a transition records `actuated`; a
  /// live failure records `failed` and stops (A25).
  Future<CycleOutcome> _actuate(
    String beadId,
    Convergence convergence,
    ReducerEvent event,
    ReduceResult result,
  ) async {
    // Coexistence partition: never write to a loop the_grid does not own.
    if (!_ownership.owns(convergence)) {
      final out = CycleOutcome(
        convergenceBeadId: beadId,
        status: CycleStatus.skipped,
        result: result,
      );
      _record(out);
      return out;
    }

    // A pure no-op (skipped / failed-action with no writes) still goes through
    // the actuator (it threads nothing and writes nothing for a skip), but we
    // classify the trace by the primary action.
    try {
      final actuation = await _applyActions(
        beadId,
        convergence,
        result.actions,
      );
      final out = CycleOutcome(
        convergenceBeadId: beadId,
        status: _isNoopResult(result)
            ? CycleStatus.skipped
            : CycleStatus.actuated,
        result: result,
        actuation: actuation,
      );
      _record(out);
      return out;
    } on ActuationFailed catch (e) {
      return _failure(beadId, result, e);
    }
  }

  /// Applies a list of actions through the actuator and records their metadata
  /// writes into the overlay (A17 — so the next same-bead reduce reads
  /// post-actuation state). Returns the actuation result (poured wisp id +
  /// requeue), augmented with the deferred pour-failure flag the phase split
  /// needs.
  Future<ActuationResult> _applyActions(
    String beadId,
    Convergence convergence,
    List<ReconcilerAction> actions,
  ) async {
    final actuation = await _actuator.apply(ReduceResult(actions), convergence);
    for (final action in actions) {
      _overlay.recordAction(action);
    }
    return actuation;
  }

  CycleOutcome _failure(String beadId, ReduceResult result, ActuationFailed e) {
    final out = CycleOutcome(
      convergenceBeadId: beadId,
      status: CycleStatus.failed,
      result: result,
      error: e,
    );
    _record(out);
    return out;
  }

  CycleOutcome _noop(String beadId) {
    final out = CycleOutcome.noop(beadId);
    _record(out);
    return out;
  }

  // ===========================================================================
  // Periodic full recovery (Track C)
  // ===========================================================================

  /// Runs the full recovery pass over the current snapshot (Track C) and
  /// actuates each owned outcome's effects on the per-bead queue. Idempotent;
  /// safe at any cadence (the pass is pure and the invariants make replay safe).
  ///
  /// **Re-reduce over the overlay, not the snapshot (A17).** The candidate scan
  /// runs over the raw snapshot to enumerate which loops need attention, but the
  /// replay PLAN for each candidate is recomputed inside its per-bead queued
  /// task, against the WRITE-THROUGH-OVERLAID convergence — the same
  /// `_currentConvergence` seam the live cycle reduces over. This matches gc,
  /// whose `reconcileBead` re-reads fresh store metadata at every bead
  /// (reconcile.go:65) and whose replay re-reads again inside `HandleWispClosed`
  /// (handler.go:165), so a closure the live cycle already advanced
  /// (`last_processed_wisp` bumped, recorded in the overlay) reduces to a
  /// dedup-skip — empty replay — instead of re-firing the transition. Reusing
  /// the snapshot-time plan would double-apply against a snapshot the overlay
  /// already knows is stale (the A21 watcher lag the overlay exists to cover).
  Future<RecoveryRunReport> runRecovery() async {
    recoveryPasses++;
    final snapshot = _source.current;
    if (snapshot == null) {
      return const RecoveryRunReport(scanned: 0, actuated: 0, failures: 0);
    }
    // Enumerate candidates over the raw snapshot; the plan is recomputed
    // per-bead over the overlay below (so `scanned` matches gc's pass count).
    final report = ConvergenceRecovery.reconcile(snapshot);
    var actuated = 0;
    var failures = 0;
    for (final outcome in report.outcomes) {
      // Only the reducer-shaped replay paths (closed-adopt, closed-unprocessed)
      // actuate through the existing actuator here; the recovery-specific
      // effects ([recovery]) are surfaced for the caller but their bd surface
      // lands with the Track-G recovery actuator. A candidate with no
      // snapshot-time replay can be skipped — the overlay only ever ADDS
      // dedup state, never converts a non-replay outcome INTO a replay.
      if (outcome.replayActions.isEmpty) continue;
      try {
        final didActuate = await _queue.run<bool>(
          outcome.convergenceBeadId,
          () => _runRecoveryReplay(outcome.convergenceBeadId, snapshot),
        );
        if (didActuate) actuated++;
      } on ActuationFailed {
        // Deferred live-error contract: a failed replay is left for the next
        // pass (the invariants make it safe to retry).
        failures++;
      }
    }
    return RecoveryRunReport(
      scanned: report.scanned,
      actuated: actuated,
      failures: failures,
    );
  }

  /// Recomputes the replay plan for [beadId] over the OVERLAID convergence
  /// (A17) and actuates it. Returns whether any replay action was applied — an
  /// already-advanced closure re-reduces to an empty plan (dedup-skip) and
  /// applies nothing. Runs on [beadId]'s serial turn (caller holds the queue).
  Future<bool> _runRecoveryReplay(String beadId, GraphSnapshot snapshot) async {
    final convergence = _currentConvergence(beadId);
    if (convergence == null) return false;
    if (!_ownership.owns(convergence)) return false;
    // Re-reduce through the overlay — the seam the live cycle uses. A closure
    // the live cycle already processed advances last_processed_wisp in the
    // overlay, so this re-reduce yields an empty replay (the reducer's
    // monotonic dedup, handler.go:199), NOT a second transition.
    final replay = ConvergenceRecovery.reconcileBead(
      convergence,
      snapshot,
    ).replayActions;
    if (replay.isEmpty) return false;
    await _applyActions(beadId, convergence, replay);
    return true;
  }

  Future<void> _safeRecovery() async {
    // Single-flight: skip if a prior pass is still running (re-entrancy guard,
    // matching gc's one-pass-at-a-time loop). The skipped tick is harmless —
    // the backstop is periodic and the next tick re-scans.
    if (_recoveryInFlight) return;
    _recoveryInFlight = true;
    try {
      await runRecovery();
    } on Object catch (e, st) {
      _onError?.call(e, st);
    } finally {
      _recoveryInFlight = false;
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// The current [Convergence] for [beadId] with the write-through overlay
  /// applied — the post-actuation view the reducer must run over (A17).
  Convergence? _currentConvergence(String beadId) {
    final base = _source.convergence(beadId);
    if (base == null) return null;
    return _overlay.apply(base);
  }

  static EvaluateGateAction? _findEvaluateGate(ReduceResult result) {
    for (final action in result.actions) {
      if (action is EvaluateGateAction) return action;
    }
    return null;
  }

  static RequeueAction? _findRequeue(ReduceResult result) {
    for (final action in result.actions) {
      if (action is RequeueAction) return action;
    }
    return null;
  }

  /// Whether the result is a pure no-op (a lone skip, or a phase-1-less result
  /// whose only action is a skip) — for trace classification.
  static bool _isNoopResult(ReduceResult result) =>
      result.actions.length == 1 && result.actions.single is SkippedAction;

  void _record(CycleOutcome outcome) {
    outcomes.add(outcome);
    _onCycle?.call(outcome);
  }

  void _reportStreamError(Object error, StackTrace stack) {
    _onError?.call(error, stack);
  }

  /// Tears down the subscriptions and the recovery timer. Does not dispose the
  /// injected source/actuator (their owners do).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _recoveryTimer?.cancel();
    await _eventSub?.cancel();
    await _snapshotSub?.cancel();
    await _queue.idle();
  }
}

/// What [ReconcilerRuntime.runRecovery] did this pass.
class RecoveryRunReport {
  const RecoveryRunReport({
    required this.scanned,
    required this.actuated,
    required this.failures,
  });

  /// Convergence loops scanned (gc's `ReconcileReport.Scanned`).
  final int scanned;

  /// Replay plans actuated this pass.
  final int actuated;

  /// Replays that hit a live failure (deferred to the next pass).
  final int failures;

  @override
  String toString() =>
      'RecoveryRunReport(scanned=$scanned, actuated=$actuated, '
      'failures=$failures)';
}
