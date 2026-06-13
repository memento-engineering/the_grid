import 'package:freezed_annotation/freezed_annotation.dart';

import 'convergence_metadata.dart';
import 'convergence_state.dart';
import 'gate_config.dart';
import 'gate_mode.dart';
import 'gate_outcome.dart';
import 'gate_result.dart';
import 'go_scalars.dart';
import 'reducer_event.dart';

part 'reconciler_action.freezed.dart';

/// The canonical close reasons gc stamps on convergence-driven closes
/// (handler.go:47-55). Every reason is ≥20 chars to satisfy bd's
/// `validation.on-close=error` validator.
abstract final class CloseReasons {
  /// handler.go:48 — `CloseReasonCreateRollback`.
  static const createRollback = 'convergence: bead-create rollback after error';

  /// handler.go:49 — `CloseReasonRetryRollback`.
  static const retryRollback = 'convergence: retry-create rollback after error';

  /// handler.go:50 — `CloseReasonManualApprove`.
  static const manualApprove =
      'convergence: iteration closed by manual approve';

  /// handler.go:51 — `CloseReasonManualSupersede`.
  static const manualSupersede =
      'convergence: active wisp superseded during manual stop';

  /// handler.go:52 — `CloseReasonManualStop`.
  static const manualStop = 'convergence: iteration closed by manual stop';

  /// handler.go:53 — `CloseReasonReconcileDone`.
  static const reconcileDone =
      'convergence reconcile: terminated-state bead closed';

  /// handler.go:54 — `CloseReasonHandlerCleanup`.
  static const handlerCleanup =
      'convergence: terminated state observed; closing root';

  /// handler.go:55 — `CloseReasonHandlerRoot`.
  static const handlerRoot =
      'convergence: workflow handler closing root after terminate';
}

/// gc's speculative-pour deferral keys
/// (gascity/internal/molecule/molecule.go:58-74): a speculative pour
/// withholds each actionable node's claimability by pouring it as the
/// ready-excluded type `gate` and stashing the real type / assignee /
/// routing under these keys (molecule.go:1009-1026, graph_apply.go:268-287).
/// `ActivateWisp` promotes them back via per-node updates, recursing over
/// children (cmd/gc/convergence_store.go:204-246). Verified against pinned
/// bd 1.0.5 in `tool/wisp_pour_spike.sh`.
abstract final class DeferredWispFields {
  /// molecule.go:60 — assignee withheld during speculative creation.
  static const assignee = 'gc.deferred_assignee';

  /// molecule.go:64 — `gc.routed_to` withheld.
  static const routedTo = 'gc.deferred_routed_to';

  /// molecule.go:68 — `gc.execution_routed_to` withheld.
  static const executionRoutedTo = 'gc.deferred_execution_routed_to';

  /// molecule.go:73 — the real bead type; the node pours as type `gate`
  /// (ready-excluded) until activation restores this (molecule.go:1009-1017).
  static const type = 'gc.deferred_type';
}

/// One ordered metadata write (`Store.SetMetadata` analog): the exact key and
/// the exact wire-encoded value. gc clears a key by writing the empty string.
///
/// **Actuation, pinned against bd 1.0.5** (`tool/wisp_pour_spike.sh`):
/// `bd update <id> --metadata '{…}'` **MERGES** into the existing map —
/// keys carried overwrite, keys absent are preserved
/// (beads/cmd/bd/update.go:546-573 `mergeMetadata`; verified empirically) —
/// and **succeeds on a CLOSED bead** (required by handler-9step trap 1: the
/// terminal `last_processed_wisp` is written AFTER `CloseBead`,
/// handler.go:699-704). A write sequence therefore carries ONLY its named
/// keys, exactly like gc's single-key `SetMetadata` granularity — never a
/// snapshot read-modify-write of the whole map, which would clobber the
/// agent-owned `convergence.agent_verdict`/`agent_verdict_wisp` channel
/// (gates-exec.md §9).
@freezed
abstract class MetadataWrite with _$MetadataWrite {
  const MetadataWrite._();

  const factory MetadataWrite({required String key, required String value}) =
      _MetadataWrite;

  @override
  String toString() => 'MetadataWrite($key = "$value")';
}

/// The full payload of a wisp pour — everything gc passes to
/// `Store.PourWisp`/`PourSpeculativeWisp` (handler.go:94-100), realized
/// through the A15 recipe (`bd cook --mode=runtime` → `bd create --graph
/// --ephemeral` with `parent_id` → [parentBeadId] and
/// `metadata.idempotency_key` = [idempotencyKey]).
///
/// **Find-before-pour (A15 actuation divergence):** pinned bd 1.0.5
/// `bd create --graph` does NOT fail on a duplicate idempotency key — the
/// key is plain metadata, deduplicated by nothing (idempotency is the_grid's
/// own job; A15, M2-BUILD-ORDER Track 0.2). gc's
/// pour-then-probe-on-CREATE-error sequencing therefore **inverts** under bd
/// actuation: the actuator MUST establish the key is unpoured BEFORE
/// pouring and adopt a hit — pouring blind creates a sibling duplicate that
/// permanently inflates `deriveIterationCount` once closed (ADR-0003
/// invariant 4; handler-9step trap 2).
///
/// **Freshness contract — a snapshot scan alone is NOT sufficient.** gc is
/// safe only because `PourWisp` is store-level idempotent
/// (find-before-create inside the store, convergence_store.go:169) and
/// every handler entry re-reads fresh store metadata; a snapshot probe
/// replaces that with a stale read (the same lag this package pins
/// elsewhere: a fast actuation routinely beats the Dolt watcher poll —
/// `ReducerEvent.gateEvaluated`). A re-delivered `triggerPassed` /
/// double-submitted `operatorIterate` reducing over a pre-pour snapshot
/// passes every guard and decides a second pour of the same key. The grid
/// therefore requires BOTH layers gc has:
///
/// 1. **Track G freshness regime:** per-bead event processing MUST be
///    serialized, and events MUST be evaluated against post-actuation
///    state (a write-through per-bead overlay), never the raw snapshot —
///    mirroring gc's single-writer event loop + fresh metadata read at
///    every handler entry (trigger.go:52-56, manual.go:125-130).
/// 2. **Live actuator probe:** the find-before-pour probe MUST be a LIVE
///    query issued immediately before `bd create --graph`. The Actuator
///    seam declares this as `findWispByIdempotencyKey(parentId, key)` —
///    one live children-by-metadata lookup, gc's `FindByIdempotencyKey`
///    analog (cmd/gc/convergence_store.go:248-270) — and the actuator
///    adopts a hit instead of pouring. `Convergence.findByIdempotencyKey`
///    (the snapshot scan) remains the fast path and the shadow-mode path:
///    a snapshot HIT is trustworthy (adopt without a live round-trip); a
///    snapshot MISS proves nothing and must fall through to the live
///    probe.
///
/// The documented on-pour-failure probes remain for REAL pour errors
/// (cook/create failures), where the probe distinguishes a
/// torn-but-completed pour from never-poured — those probes are live too
/// (manual.go:169-175, trigger.go:136-142).
@freezed
abstract class WispPour with _$WispPour {
  const WispPour._();

  const factory WispPour({
    /// The convergence root bead the wisp hangs off (a parent-child edge;
    /// the `parent_id` column stays null — A15).
    required String parentBeadId,

    /// The formula to cook (`convergence.formula`).
    required String formula,

    /// `converge:{beadID}:iter:{N}` for [iteration].
    required String idempotencyKey,

    /// The 1-based iteration this pour creates.
    required int iteration,

    /// Template variables (`var.*` metadata, prefix stripped — template.go:43).
    @Default(<String, String>{}) Map<String, String> vars,

    /// Prompt for the injected evaluate step (`convergence.evaluate_prompt`).
    String? evaluatePrompt,

    /// True for the step-3b speculative pour (handler.go:98-100): the A15
    /// graph plan is built with each actionable node poured as the
    /// ready-excluded type `gate` and its real type/assignee/routing
    /// stashed under [DeferredWispFields] (molecule.go:1009-1026) — agents
    /// cannot claim it and `bd ready`/`bd children` never surface it.
    /// Activation = per-node `bd update` promoting the deferred values
    /// back (convergence_store.go:204-246; spike-verified). False for a
    /// directly-visible pour (operator iterate, trigger advance).
    @Default(false) bool speculative,
  }) = _WispPour;
}

/// Why a `skipped` action carries no transition.
enum SkipReason {
  /// Step-1 guard: the loop is already `terminated` (handler.go:171-175).
  /// gc also best-effort closes the root ([SkippedAction.closeRootBestEffort]).
  alreadyTerminated,

  /// Step-2 monotonic dedup: the wisp's iteration is ≤ the
  /// `last_processed_wisp` iteration (handler.go:199-201; ADR-0003
  /// invariant 1).
  duplicateWisp,

  /// `HandleTrigger` guard: the loop is not in `waiting_trigger`
  /// (trigger.go:58-61).
  notWaitingTrigger,

  /// The trigger condition did not pass — keep waiting; re-evaluated next
  /// tick (trigger.go:96-99, `result.Outcome != GatePass` → skipped).
  triggerNotSatisfied,

  /// Operator approve on a loop already `terminated` +
  /// `terminal_reason=approved` — an idempotent no-op SUCCESS whose
  /// HandlerResult action is `approved`, not `skipped` (manual.go:30-34).
  alreadyApproved,

  /// Operator stop on a loop already `terminated` +
  /// `terminal_reason=stopped` — idempotent no-op, reported as `stopped`
  /// (manual.go:251-255).
  alreadyStopped,

  /// Operator stop drained the closed active wisp through
  /// `HandleWispClosed` and that terminated the loop — stop becomes a
  /// no-op reported as `stopped` (manual.go:296-308). Reached ONLY for
  /// `OperatorStopEvent(postDrain: true)`: gc's drain return reports
  /// `ActionStopped` without checking `terminal_reason` precisely because
  /// the same call ran the drain (manual.go:303-308). A `postDrain: false`
  /// stop landing on the same `terminated/non-stopped` shape is a FRESH
  /// stop on an already-terminated loop and takes gc's error path instead
  /// (manual.go:258-263), NOT this reason. The marker is what disambiguates
  /// the two from an otherwise-identical snapshot — see
  /// [ReducerEvent.operatorStop].
  drainTerminated,
}

/// Snapshot-derived data the actuator needs to emit gc's step-8 events for
/// a transition **without re-reading live metadata**.
///
/// gc builds every payload from the metadata SNAPSHOT taken at handler
/// entry: `iterate` and `waitingTrigger` clear the verdict in the store and
/// then report it from the snapshot (handler.go:532-535, 599-601 —
/// handler-9step trap 6). An actuator that re-reads live metadata emits
/// empty verdicts. Durations are gc's `computeDurations`
/// (handler.go:829-850), computable purely over the `GraphSnapshot`.
@freezed
abstract class EventEmission with _$EventEmission {
  const EventEmission._();

  const factory EventEmission({
    /// Normalized verdict scoped to the closed wisp, `''` when unscoped —
    /// the *payload* semantics (handler.go:532-535), NOT the gate path's
    /// `block` substitute (handler.go:319-324).
    @Default('') String agentVerdict,

    /// `gateConfig.Mode` for the payload. The stop path's synthetic
    /// iteration event defaults an empty stored mode to manual
    /// (manual.go:387-389).
    GateMode? gateMode,

    /// Full gate result for `GateResultToPayload` parity (events.go:195-206
    /// returns nil when the outcome is empty — no gate ran).
    GateResult? gateResult,

    /// `wisp.ClosedAt − wisp.CreatedAt` (handler.go:830-835).
    @Default(Duration.zero) Duration iterationDuration,

    /// Σ closed convergence-keyed children durations (handler.go:837-849).
    @Default(Duration.zero) Duration cumulativeDuration,

    /// `PriorState` for `ManualActionPayload` (operator and trigger-advance
    /// events — manual.go:97, 204, 422; trigger.go:167).
    ConvergenceState? priorState,

    /// `convergence.rig`, stamped into EVERY emitted payload: gc's
    /// `withEventRig` (handler.go:860-884) injects `meta[FieldRig]`
    /// (metadata.go:35) into each payload type before marshalling; an
    /// empty rig leaves the payload untouched (handler.go:862-864), so
    /// null here ⇒ omit the field. gc re-reads live metadata for this
    /// (`eventRig`, handler.go:886-895); the reducer populates it from the
    /// SAME snapshot it reduced over — `convergence.rig` is written once
    /// at create (create.go:27-31) and never mutated afterwards, so the
    /// snapshot read is exact.
    String? rig,

    /// gc's `eventWispID` local — the value of `ManualActionPayload
    /// .wisp_id`, which comes from HERE and **never** from the
    /// commit-write fields (the actions' `lastProcessedWisp` /
    /// `closedWispId` are metadata WRITE values; they diverge from the
    /// event value exactly in the corner cases: `active_wisp` still set
    /// while waiting_manual on approve, and stop without a force-close).
    /// Per-path selection, by the reducer, from the reduced-over snapshot:
    ///
    /// * **operator approve**: `active_wisp`, falling back to
    ///   `last_processed_wisp` when empty (manual.go:54-56; payload
    ///   manual.go:100);
    /// * **operator stop**: the same active-else-last-processed selection,
    ///   evaluated AFTER the drain/recovery/force-close steps refreshed
    ///   `active_wisp` (manual.go:359-361; payload manual.go:425). The
    ///   synthetic force-close iteration payload uses the force-closed
    ///   wisp id directly, not this field (manual.go:398);
    /// * **operator iterate**: `last_processed_wisp` — the PRIOR wisp,
    ///   never the just-poured one, which travels as `next_wisp_id`
    ///   (manual.go:207-208);
    /// * **trigger advance**: `last_processed_wisp`, null on the
    ///   entry-gated first iteration (trigger.go:170).
    ///
    /// Null ⇒ `wisp_id` marshals as JSON null (gc's `NullableString` of
    /// the empty string).
    String? eventWispId,
  }) = _EventEmission;
}

/// Which gc code path produced an `iterate` decision. Each has its **own**
/// exact pour/activation/write sequence — see [IterateActionWrites].
enum IteratePath {
  /// `handler.go` `iterate()` (lines 480-573) — the wisp-closed path.
  wispClosed,

  /// `manual.go` `IterateHandler` (lines 124-217) — operator iterate from
  /// `waiting_manual`.
  operatorIterate,

  /// `trigger.go` `advanceFromTrigger` (lines 129-180) — the ADR-0003 row
  /// `waitingTrigger / trigger condition passes → active / iterate`.
  triggerAdvance,
}

/// Which gc code path produced a terminal `approved` decision. The two
/// origins have **different event-emit orderings relative to the terminal
/// writes** (handler.go:662-704 vs manual.go:62-109) — see
/// [ReconcilerAction.approved] — and conflating them on the handler path
/// loses TierCritical events after a crash.
enum TerminalPath {
  /// `handler.go` `terminate()` (lines 638-711) via `HandleWispClosed` —
  /// gate pass (and the `no_convergence` terminals). BOTH step-8 events are
  /// emitted BEFORE the first terminal metadata write.
  handlerWispClosed,

  /// `manual.go` `ApproveHandler` (lines 20-115) — operator approve from
  /// `waiting_manual`. Terminal writes come FIRST; `terminated` is emitted
  /// between `state=terminated` and the close.
  operatorApprove,
}

/// A reconciler decision, as **data**: everything an actuator needs to
/// execute gc's exact write sequence without consulting the Go source.
///
/// The seven transition variants mirror gc's `HandlerAction` vocabulary
/// (handler.go:120-128; [wire]). Six further variants carry effects that
/// have no `HandlerAction` of their own but are load-bearing for the
/// crash-safety invariants: [ReconcilerAction.repairIteration] (step 3,
/// invariant 4), [ReconcilerAction.pourSpeculative] (step 3b, invariant 5),
/// [ReconcilerAction.evaluateGate] (step 4's fresh branch — the explicit
/// gate-run request to Track D), [ReconcilerAction.persistGateOutcome]
/// (step 5, invariant 2's gate half), [ReconcilerAction.failed] (gc's
/// `(HandlerResult{}, err)` returns), and [ReconcilerAction.requeue] (the
/// carrier for gc's inline operator-stop drain, manual.go:272-314).
///
/// **In-list dataflow rule (gc's `speculativeWispID` local):** gc threads
/// the step-3b pour result through steps 4→7 as a LOCAL
/// (handler.go:247-275, 381, 385). When a [ReconcilerAction.pourSpeculative]
/// and a transition action are emitted in the SAME action list (the replay
/// path — `gate_outcome_wisp == wispId` — still pours at 3b), the later
/// action binds the earlier pour's runtime result via
/// [IterateAction.adoptFromPriorPour] / the terminal actions'
/// `burnPriorPour` flags: the reducer cannot name a wisp that does not
/// exist yet, and re-pouring the same key would duplicate it
/// (find-before-pour, [WispPour]). Across the wispClosed → gateEvaluated
/// phase split the same locals travel as event data
/// (`GateEvaluatedEvent.pouredSpeculativeWispId` / `pourFailed`), never via
/// a snapshot re-read.
///
/// Each variant exposes its **ordered** metadata-write sequence as derived
/// getters so the ordering invariants (ADR-0003 invariant 2:
/// `last_processed_wisp` LAST — it IS the commit point; `gate_outcome_wisp`
/// LAST in gate persistence) are encoded once, here, and cannot be
/// re-derived wrongly by an actuator.
///
/// **Burn protocol** (every `burnWispId` field): burn = recursive
/// **post-order subtree DELETE** — children first, then the wisp
/// (handler.go:908-933, `bd delete` against pinned bd; spike-verified) —
/// followed by a best-effort `pending_next_wisp` ← `''`. **NEVER close**: a
/// closed speculative wisp keeps the idempotency-key prefix + closed status
/// and permanently inflates `deriveIterationCount` (handler-9step trap 2;
/// invariant 4). ⚠ `bd children` cannot enumerate gate-typed (speculative)
/// steps — enumerate the subtree from the snapshot or the pour's id map.
@freezed
sealed class ReconcilerAction with _$ReconcilerAction {
  const ReconcilerAction._();

  /// Pour/adopt the next wisp and continue iterating. Three distinct gc
  /// paths share this action — [path] selects the exact protocol:
  ///
  /// **[IteratePath.wispClosed]** (handler.go:480-573):
  /// 1. Apply [IterateActionWrites.preWrites] — the scoped verdict clears,
  ///    BEFORE the next wisp can run (handler.go:491-498; clearing after
  ///    activation races the next wisp's agent — gates-exec trap 21).
  /// 2. Resolve the next wisp:
  ///    * [adoptWispId] set → adopt it (a reduce-time-known id:
  ///      snapshot-validated `pending_next_wisp`, or the phase-2 event's
  ///      `pouredSpeculativeWispId` — handler.go:505-507);
  ///    * else if [adoptFromPriorPour] → bind the wisp produced by the
  ///      [ReconcilerAction.pourSpeculative] EARLIER IN THIS SAME action
  ///      list (its fresh pour or its `adoptPendingWispId` adoption) — gc's
  ///      `speculativeWispID` local threading 3b→7 (handler.go:247-275,
  ///      381). If that pour recorded a deferred failure (no wisp
  ///      resulted), execute [slingFailureFallback] INSTEAD of iterating
  ///      (handler.go:370-373) — never fall through to a second pour of
  ///      the key the prior action just poured;
  ///    * else **fallback-pour** [pour] (visible, handler.go:514) under
  ///      the find-before-pour obligation ([WispPour]); if a real pour
  ///      error occurs and the idempotency probe misses, execute
  ///      [slingFailureFallback] — a full waiting_manual transition with
  ///      `sling_failure`, including its own commit (handler.go:515-523,
  ///      714-726).
  /// 3. Activate the wisp ([IterateActionWrites.activatesWisp];
  ///    handler.go:525 — promote [DeferredWispFields] per node).
  /// 4. Apply [IterateActionWrites.postPourWrites] — `active_wisp`, then
  ///    `last_processed_wisp` LAST (handler.go:557-562).
  /// 5. Best-effort clear `pending_next_wisp`
  ///    ([IterateActionWrites.clearsPendingNextWisp]; handler.go:563-565).
  ///
  /// **[IteratePath.operatorIterate]** (manual.go:124-217):
  /// 1. Pour [pour] FIRST — visible, **no activation** (manual.go:166; gc's
  ///    IterateHandler never calls ActivateWisp). On pour failure probe the
  ///    key; on a miss **hard error, no writes** — the bead stays
  ///    `waiting_manual` and the verdict survives for retry
  ///    (manual.go:158-175).
  /// 2. Apply [IterateActionWrites.postPourWrites] — verdict clears (AFTER
  ///    the pour, deliberately — manual.go:177-187), `waiting_reason` ← '',
  ///    `state` ← active, `active_wisp` (manual.go:189-199). NO
  ///    `last_processed_wisp` (manual.go:121-123), no pending clear.
  ///
  /// **[IteratePath.triggerAdvance]** (trigger.go:129-180):
  /// 1. Pour [pour] (visible), probe on failure, hard error on a miss
  ///    (trigger.go:135-143).
  /// 2. Activate (trigger.go:144-146).
  /// 3. Apply [IterateActionWrites.postPourWrites] —
  ///    `convergence.iteration` ← EncodeInt([WispPour.iteration]), then
  ///    `active_wisp`, then `state` ← active LAST (trigger.go:148-156). NO
  ///    waiting_reason write, NO verdict clears (the waitingTrigger
  ///    transition already cleared them), NO dedup marker.
  const factory ReconcilerAction.iterate({
    required String convergenceBeadId,

    /// gc `HandlerResult.Iteration`: the closed wisp's iteration on
    /// [IteratePath.wispClosed]; the NEW iteration on
    /// [IteratePath.operatorIterate] (manual.go:214) and
    /// [IteratePath.triggerAdvance] (trigger.go:177).
    required int iteration,

    /// The pour payload for the **next** wisp.
    required WispPour pour,

    /// Which gc path this decision came from — selects the write protocol.
    required IteratePath path,

    /// A speculatively-poured wisp to adopt instead of pouring
    /// (handler.go:505-507). wispClosed path only. Reduce-time-known ids
    /// only: the snapshot's validated `pending_next_wisp`, or phase 2's
    /// `GateEvaluatedEvent.pouredSpeculativeWispId`.
    String? adoptWispId,

    /// wispClosed path only: bind the wisp produced by the
    /// [ReconcilerAction.pourSpeculative] earlier in the SAME action list —
    /// the pour result no reduce input can name (the replay path pours at
    /// 3b in the same reduce that decides to iterate). Mutually exclusive
    /// with [adoptWispId]; see protocol step 2 and the class-doc in-list
    /// dataflow rule.
    @Default(false) bool adoptFromPriorPour,

    /// The wisp whose closure triggered this — becomes the new
    /// `last_processed_wisp`. Null off the wispClosed path, which alone
    /// writes the dedup marker.
    String? closedWispId,

    /// True when the verdict is scoped and must be cleared — scoped to the
    /// closed wisp on the wispClosed path (handler.go:491), to
    /// `last_processed_wisp` on the operator path (manual.go:180).
    @Default(false) bool clearVerdict,

    /// The gate outcome that decided to iterate (informational).
    GateOutcome? gateOutcome,

    /// wispClosed path only: the pre-built `sling_failure` waiting_manual
    /// transition the actuator executes when the fallback pour fails AND
    /// the idempotency probe misses (handler.go:520-521 →
    /// handleSlingFailure, 714-726).
    WaitingManualAction? slingFailureFallback,

    /// Step-8 event data (`convergence.iteration` on the wispClosed path,
    /// emitted BEFORE the commit writes, handler.go:538-553;
    /// `manual_iterate` / `trigger_advance` on the others, emitted after
    /// their writes — manual.go:201-210, trigger.go:158-173).
    EventEmission? events,
  }) = IterateAction;

  /// Terminal transition with `terminal_reason=approved` — gate pass
  /// (handler.go `terminate`, lines 638-711) or operator approve
  /// (manual.go `ApproveHandler`, lines 20-115). [path] selects the
  /// protocol; **the two event orders are NOT interchangeable**.
  ///
  /// **[TerminalPath.handlerWispClosed]** (handler.go:384-387 + 638-711):
  /// 1. Burn [burnWispId] / the prior in-list pour ([burnPriorPour]) — gc
  ///    burns BEFORE entering `terminate()` (handler.go:384-387; class-doc
  ///    burn protocol).
  /// 2. Emit `convergence.iteration` AND `convergence.terminated` — BOTH
  ///    BEFORE ANY terminal write (handler.go:675 and :685 precede the
  ///    step-9 writes at :689-697). At-least-once hangs on this order
  ///    (handler-9step §6): a crash after `state=terminated` re-enters
  ///    through the step-1 guard as `skipped` with no re-emit, so
  ///    events-after-writes would be lost forever.
  /// 3. [ApprovedActionWrites.terminalWrites] in order.
  /// 4. Close the root with [closeReason] ([CloseReasons.handlerRoot],
  ///    handler.go:699).
  /// 5. [ApprovedActionWrites.commitWrite] LAST (handler.go:702 — the
  ///    store accepts metadata writes on a closed bead, spike-pinned).
  ///
  /// **[TerminalPath.operatorApprove]** (manual.go:62-109) — no burn:
  /// 1. [ApprovedActionWrites.terminalWrites] in order, including the
  ///    `waiting_reason` clear (manual.go:65-77) — writes FIRST here.
  /// 2. Emit `convergence.terminated` BEFORE the close (TierCritical while
  ///    the bead is still open, manual.go:78-88). No iteration event.
  /// 3. Close the root with [closeReason] ([CloseReasons.manualApprove],
  ///    manual.go:90).
  /// 4. Emit `manual_approve` AFTER the close (best-effort,
  ///    manual.go:94-102).
  /// 5. [ApprovedActionWrites.commitWrite] LAST (skipped when null,
  ///    manual.go:104-109).
  const factory ReconcilerAction.approved({
    required String convergenceBeadId,

    /// Which gc origin produced this terminal decision — selects the
    /// protocol above. The [closeReason] constants happen to correlate
    /// with the origin, but the ordering contract is selected HERE, never
    /// parsed back out of a close-reason string.
    required TerminalPath path,

    /// `terminal_actor`: `controller` (handler.go:389) or
    /// `operator:<user>` (manual.go:27).
    required String actor,

    /// gc `HandlerResult.Iteration`: the closed wisp's iteration on the
    /// handler path (handler.go:708); the derived count on operator
    /// approve (manual.go:113). Also the `convergence.iteration` event ID
    /// component (`converge:<bead>:iter:<N>:iteration`, events.go:42-46).
    required int iteration,

    /// Derived closed-wisp count (ADR-0003 invariant 4) —
    /// `TerminatedPayload.TotalIterations`.
    required int totalIterations,

    /// The value for the final `last_processed_wisp` write; null skips it.
    String? lastProcessedWisp,

    /// The gate outcome (pass) on the wisp-closed path; null on operator
    /// approve.
    GateOutcome? gateOutcome,

    /// Speculative wisp to burn first, when its id is known at reduce time
    /// (snapshot-validated `pending_next_wisp`, or phase 2's
    /// `GateEvaluatedEvent.pouredSpeculativeWispId`).
    /// [TerminalPath.handlerWispClosed] only.
    String? burnWispId,

    /// Burn the wisp produced by the [ReconcilerAction.pourSpeculative]
    /// earlier in the SAME action list (the replay path pours at 3b even
    /// when the persisted outcome is terminal, then burns —
    /// handler.go:384-387). Covers the in-list pour whose id no reduce
    /// input carries; no-op when that pour produced nothing.
    /// [TerminalPath.handlerWispClosed] only — and after termination there
    /// is no next handler entry to self-heal a leak, so skipping this burn
    /// hides the wisp forever (ADR-0003 invariant 5).
    @Default(false) bool burnPriorPour,

    /// True on the operator path, which clears `waiting_reason`
    /// (manual.go:71-73); the handler path does not.
    @Default(false) bool clearWaitingReason,

    /// The canonical close reason ([CloseReasons.handlerRoot] or
    /// [CloseReasons.manualApprove]).
    required String closeReason,

    /// Step-8 event data. [TerminalPath.handlerWispClosed]: iteration +
    /// terminated, BOTH emitted before any terminal write (protocol step
    /// 2; handler.go:662-685). [TerminalPath.operatorApprove]: terminated
    /// between the writes and the close, manual_approve after the close.
    EventEmission? events,
  }) = ApprovedAction;

  /// Terminal transition with `terminal_reason=no_convergence`: timeout with
  /// action=terminate, or max iterations without a pass (handler.go:357-368,
  /// then `terminate`).
  ///
  /// **Handler-only** — no operator path produces `no_convergence`
  /// (manual.go's terminals are `approved` and `stopped`), so the protocol
  /// is always [ReconcilerAction.approved]'s
  /// [TerminalPath.handlerWispClosed] order with reason `no_convergence`:
  /// burn ([burnWispId]/[burnPriorPour]) → BOTH events BEFORE any terminal
  /// write (handler.go:662-685) →
  /// [NoConvergenceActionWrites.terminalWrites] → close →
  /// [NoConvergenceActionWrites.commitWrite] LAST.
  const factory ReconcilerAction.noConvergence({
    required String convergenceBeadId,
    required String actor,

    /// The closed wisp's iteration (handler.go:708) — see
    /// [ApprovedAction.iteration].
    required int iteration,
    required int totalIterations,
    String? lastProcessedWisp,
    GateOutcome? gateOutcome,

    /// Reduce-time-known speculative wisp to burn first — see
    /// [ApprovedAction.burnWispId].
    String? burnWispId,

    /// Burn the in-list prior pour's wisp — see
    /// [ApprovedAction.burnPriorPour]. Reachable on a timeout-terminate
    /// replay below max iterations: 3b still pours (handler.go:254), the
    /// persisted outcome terminates, the pour burns (handler.go:384-387).
    /// The at-max case never poured (`wispIteration < maxIterations` gates
    /// 3b), so it carries neither burn field.
    @Default(false) bool burnPriorPour,
    required String closeReason,
    EventEmission? events,
  }) = NoConvergenceAction;

  /// Hold for an operator (handler.go `transitionToWaitingManual`, lines
  /// 394-475): manual mode, hybrid-without-condition, timeout-with-manual
  /// action, or sling failure.
  ///
  /// Actuator protocol: if [clearStalePending], best-effort
  /// `pending_next_wisp` ← `''` first
  /// ([WaitingManualActionWrites.stalePendingClear]) → burn [burnWispId] →
  /// emit `convergence.iteration` BEFORE the writes (handler.go:422-436) →
  /// [WaitingManualActionWrites.orderedWrites] in order (`active_wisp`
  /// cleared, `waiting_reason`, `state`, then `last_processed_wisp` LAST —
  /// handler.go:442-453) → emit `convergence.waiting_manual` after
  /// (handler.go:456-467). No close. ⚠ Does NOT clear the verdict — it must
  /// survive for the operator/hybrid decision (trap 7).
  const factory ReconcilerAction.waitingManual({
    required String convergenceBeadId,

    /// Becomes the new `last_processed_wisp`.
    required String closedWispId,
    required int iteration,
    required WaitingReason reason,

    /// Null when no gate ran (pure manual mode passes `""` —
    /// handler.go:305-306).
    GateOutcome? gateOutcome,

    /// Reduce-time-known speculative wisp to burn first: the snapshot's
    /// validated `pending_next_wisp` (manual / hybrid-no-condition holds
    /// skip the 3b pour, so only an adopted pending can exist —
    /// handler.go:300-316), or phase 2's
    /// `GateEvaluatedEvent.pouredSpeculativeWispId` (the fresh
    /// timeout-manual hold burns it, handler.go:344-352). The
    /// sling-failure hold never burns — its defining condition is that no
    /// wisp exists (handler.go:370-373).
    String? burnWispId,

    /// Burn the in-list prior pour's wisp — see
    /// [ApprovedAction.burnPriorPour]. Reachable on a
    /// timeout-with-manual-action replay: 3b pours, the persisted timeout
    /// outcome holds, the pour burns (handler.go:344-352).
    @Default(false) bool burnPriorPour,

    /// Best-effort `pending_next_wisp` ← `''` BEFORE everything else: the
    /// snapshot's pointer failed validation. gc's `validPendingNextWisp`
    /// clears a stale pointer as a side effect of validating it
    /// (handler.go:935-945) and runs on EVERY wisp-closed entry —
    /// including the hold paths that pour nothing (manual /
    /// hybrid-no-condition, handler.go:300-316, where step 3b is skipped
    /// so no [ReconcilerAction.pourSpeculative] exists to carry the
    /// clear). Without this carrier a stale pointer would survive into
    /// waiting_manual, where only operator paths — which never validate
    /// it — run next.
    @Default(false) bool clearStalePending,
    EventEmission? events,
  }) = WaitingManualAction;

  /// Hold for an external trigger (handler.go `transitionToWaitingTrigger`,
  /// lines 580-635). No successor wisp is poured (the speculative pour was
  /// skipped for trigger-gated loops — handler.go:249-253).
  ///
  /// Actuator protocol: emit `convergence.iteration` BEFORE the writes
  /// (handler.go:604-617) → [WaitingTriggerActionWrites.orderedWrites] in
  /// order (verdict clears, then `active_wisp` cleared, `state`, then
  /// `last_processed_wisp` LAST).
  ///
  /// The persisted `state=waiting_trigger` is itself the **standing**
  /// trigger-evaluation request — Track G's poller evaluates the trigger
  /// condition each tick over waiting_trigger loops, exactly like gc's
  /// `HandleTrigger` cadence (trigger.go:52-101); a pass re-enters the
  /// reducer as `ReducerEvent.triggerPassed`. There is deliberately no
  /// per-tick `evaluateTrigger` action — see
  /// [ReconcilerAction.evaluateGate].
  const factory ReconcilerAction.waitingTrigger({
    required String convergenceBeadId,
    required String closedWispId,
    required int iteration,
    GateOutcome? gateOutcome,

    /// True when the verdict was scoped to the closed wisp
    /// (handler.go:589-596).
    @Default(false) bool clearVerdict,
    EventEmission? events,
  }) = WaitingTriggerAction;

  /// Operator stop (manual.go `StopHandler`, lines 241-445): terminal with
  /// `terminal_reason=stopped`.
  ///
  /// This action is the POST-drain stop: when the snapshot shows the
  /// active wisp closed-but-unprocessed, the reducer does NOT emit it —
  /// it emits the wispClosed drain pipeline with
  /// [ReconcilerAction.requeue]`(operatorStop)` LAST instead (gc's inline
  /// drain, manual.go:272-314; see [RequeueAction]).
  ///
  /// Actuator protocol: force-close [forceCloseWispId] with
  /// [CloseReasons.manualSupersede] (manual.go:334-339) →
  /// [StoppedActionWrites.orderedWrites] in order (verdict clears
  /// manual.go:351-356, then terminal writes manual.go:369-380) → emit the
  /// synthetic iteration event (force-close only) + `terminated` BEFORE the
  /// close (manual.go:382-412) → close the root with [closeReason]
  /// ([CloseReasons.manualStop]) → `manual_stop` after (best-effort) →
  /// [StoppedActionWrites.commitWrite] LAST (manual.go:429-439).
  const factory ReconcilerAction.stopped({
    required String convergenceBeadId,

    /// `operator:<user>` (manual.go:248).
    required String actor,

    /// Derived closed-wisp count after any force-close (manual.go:342-347).
    required int totalIterations,

    /// The value for the final `last_processed_wisp` write (the force-closed
    /// wisp when one exists — manual.go:430-434); null skips it.
    String? lastProcessedWisp,

    /// Still-open active wisp to force-close first; null when none.
    String? forceCloseWispId,
    required String closeReason,

    /// Carries `gateMode` for the synthetic iteration event (defaulted to
    /// manual when the stored mode is empty, manual.go:387-389) and
    /// `priorState` for `ManualActionPayload` (manual.go:422).
    EventEmission? events,
  }) = StoppedAction;

  /// No transition. Covers gc's `skipped` returns (handler.go:174, 200;
  /// trigger.go:60, 98) AND the operator paths' idempotent no-op SUCCESSES,
  /// whose `HandlerResult` action is `approved`/`stopped` — [wire] maps
  /// [reason] accordingly.
  const factory ReconcilerAction.skipped({
    required String convergenceBeadId,

    /// The wisp the skipped event concerned, when one applies.
    String? wispId,
    required SkipReason reason,

    /// Free-text diagnostics (e.g. the compared iterations on dedup).
    String? detail,

    /// True for the already-terminated guard, where gc best-effort closes
    /// the root with [CloseReasons.handlerCleanup] (handler.go:172-173).
    @Default(false) bool closeRootBestEffort,
  }) = SkippedAction;

  /// Step-3b speculative pour (handler.go:244-275; ADR-0003 invariant 5):
  /// pour the NEXT wisp hidden BEFORE the gate runs, and make the
  /// `pending_next_wisp` recovery pointer durable immediately.
  ///
  /// Actuator protocol:
  /// 1. If [clearStalePending], best-effort `pending_next_wisp` ← `''` —
  ///    the snapshot's pointer failed validation (`validPendingNextWisp`
  ///    self-heal, handler.go:935-945).
  /// 2. If [adoptPendingWispId] is set, adopt it (a previous attempt's
  ///    pour, already valid) and skip the pour.
  /// 3. Else pour [pour] speculatively ([WispPour.speculative] mechanism)
  ///    under the find-before-pour obligation ([WispPour] — probe
  ///    findByIdempotencyKey FIRST and adopt a hit; bd never fails on a
  ///    duplicate key). On a real pour error with a probe miss, record a
  ///    **deferred** pour failure (handler.go:259-266 —
  ///    `speculativePourErr` is stashed, NOT fatal; it surfaces as
  ///    `sling_failure` only if the eventual outcome is non-terminal,
  ///    handler.go:370-373).
  /// 4. If a wisp resulted: IMMEDIATELY apply
  ///    [PourSpeculativeActionWrites.pendingNextWispWrite] — the pointer
  ///    must be durable before the gate runs (handler.go:267-274). If that
  ///    write fails: burn the wisp and hard-fail (handler.go:269-272).
  ///
  /// The pour's runtime result (the wisp id, or the deferred failure) is
  /// gc's `speculativeWispID`/`speculativePourErr` pair: a transition
  /// action LATER IN THE SAME LIST binds it via
  /// [IterateAction.adoptFromPriorPour] / `burnPriorPour` (class-doc
  /// in-list dataflow rule), and across the phase split Track G hands it
  /// back to the reducer in `GateEvaluatedEvent.pouredSpeculativeWispId` /
  /// `pourFailed` — never via a snapshot re-read.
  const factory ReconcilerAction.pourSpeculative({
    required String convergenceBeadId,
    required WispPour pour,

    /// A validated `pending_next_wisp` from a previous attempt to adopt
    /// instead of pouring (handler.go:247).
    String? adoptPendingWispId,

    /// True when the snapshot's `pending_next_wisp` pointed at a
    /// missing/mismatched/closed bead and must be cleared (self-heal).
    @Default(false) bool clearStalePending,
  }) = PourSpeculativeAction;

  /// Step-4 fresh-branch gate request (handler.go:326-327): hand the
  /// step-3a parse product [config] and the snapshot-derived [env] to the
  /// Track-D runner. The runner's completion re-enters the reducer as
  /// `ReducerEvent.gateEvaluated` — carrying the [GateResult] AND the
  /// phase-1 pour outcome — which step 5 persists and step 7 branches on.
  ///
  /// Exists so "evaluate the gate now" travels as **data**: without it the
  /// fresh-gate handoff is signalled only by the absence of a transition
  /// action, forcing Track G to re-derive everything the reducer already
  /// decided — the step-3a parse with its defaults and validation
  /// ([GateConfig]), the step-4 verdict scoping with the `block`
  /// substitute ([GateEnvInputs.agentVerdict], handler.go:317-324), and
  /// the retry budget ([GateConfig.retryBudget], handler.go:739-742).
  ///
  /// Emitted AFTER [ReconcilerAction.pourSpeculative] in the same list
  /// (step 3b precedes step 4) and never together with a transition
  /// action — the transition is phase 2's to make.
  ///
  /// There is deliberately no `evaluateTrigger` analog: gc evaluates
  /// trigger conditions on a poll tick over `waiting_trigger` loops
  /// (`HandleTrigger`, trigger.go:52-101), not in response to a handler
  /// decision — the persisted `state=waiting_trigger` is the standing
  /// request ([ReconcilerAction.waitingTrigger]), the reducer is never the
  /// cadence source, and non-pass evaluations produce no reducer input at
  /// all (trigger.go:96-99).
  const factory ReconcilerAction.evaluateGate({
    required String convergenceBeadId,

    /// The just-closed wisp — `GC_WISP_ID`, and the scope marker the
    /// outcome will be persisted under (handler.go:749, 806-807).
    required String wispId,

    /// The closed wisp's iteration — `GC_ITERATION` (handler.go:746).
    required int iteration,

    /// The step-3a `ParseGateConfig` product, defaults applied
    /// (handler.go:218-223). Mode here is condition or hybrid-with-
    /// condition only — manual and hybrid-no-condition short-circuit to
    /// waiting_manual before any gate runs (handler.go:300-316).
    required GateConfig config,

    /// Snapshot-derived `ConditionEnv` inputs (handler.go:743-760) — see
    /// [GateEnvInputs] for what Track D derives itself.
    required GateEnvInputs env,
  }) = EvaluateGateAction;

  /// Step-5 gate-outcome persistence (handler.go:776-808; ADR-0003
  /// invariant 2's **gate half**): the eight ordered writes of
  /// [PersistGateOutcomeWrites.orderedWrites], `gate_outcome_wisp` LAST.
  ///
  /// ⚠ MUST stay a transaction separate from any step-9 transition writes —
  /// **never merged** (gates-exec.md §7): gc can crash between step 5 and
  /// step 9, and recovery depends on observing
  /// gate-outcome-persisted-but-transition-unwritten. On persistence
  /// failure: burn [burnWispId], then hard-fail with NO transition
  /// (handler.go:331-338).
  const factory ReconcilerAction.persistGateOutcome({
    required String convergenceBeadId,

    /// The closed wisp the outcome is scoped to — the idempotency marker
    /// value (handler.go:806-807).
    required String wispId,
    required GateResult result,

    /// The phase-1 speculative wisp (threaded back through
    /// `GateEvaluatedEvent.pouredSpeculativeWispId`) to burn when the
    /// write sequence fails (handler.go:331-338; class-doc burn protocol).
    /// Null when phase 1 produced no wisp. Always concrete — this action
    /// only ever appears in the phase-2 reduce, where the id is event
    /// data, never an unresolved in-list pour.
    String? burnWispId,
  }) = PersistGateOutcomeAction;

  /// Step-3 iteration self-heal (handler.go:208-214; ADR-0003 invariant 4):
  /// the stored `convergence.iteration` disagrees with the derived
  /// closed-wisp count — write the derived value BEFORE any transition.
  ///
  /// Emitted by the reducer AHEAD of the transition action in the same
  /// result list; an actuator failure here BLOCKS the transition
  /// (handler.go:211-213 returns the error).
  const factory ReconcilerAction.repairIteration({
    required String convergenceBeadId,

    /// `deriveIterationCount` — the closed convergence-keyed child count.
    required int derivedIteration,

    /// The (collapsed) stored value, for diagnostics (handler.go:208).
    @Default(0) int storedIteration,
  }) = RepairIterationAction;

  /// A hard error — gc's `(HandlerResult{}, err)` return: NO transition, NO
  /// commit marker, so the same closure is safely re-processed
  /// (handler-9step.md §6). Covers step-2 hard errors (missing closing
  /// wisp / unparseable key, handler.go:177-186), gate/trigger config parse
  /// errors (handler.go:220-228), the condition-mode-without-condition
  /// misconfig (handler.go:235-242), operator precondition failures
  /// (manual.go:37-42, 133-137, 146-151, 258-263), and pour failures on the
  /// operator/trigger paths.
  const factory ReconcilerAction.failed({
    required String convergenceBeadId,

    /// gc's error message shape, for conformance binding (Track H) — e.g.
    /// `parsing iteration from wisp key "<key>"` or
    /// `cannot approve bead "<id>": state is "<s>", expected "waiting_manual"`.
    required String message,

    /// Misconfig path only: burn this valid pending speculative wisp
    /// BEFORE surfacing the error (handler.go:235-242; trap 9 — skipping
    /// the burn leaks a hidden wisp a later recovery pass adopts). Burn =
    /// post-order subtree DELETE, see the class-doc burn protocol.
    String? burnWispId,

    /// Misconfig path only: best-effort `pending_next_wisp` ← `''` BEFORE
    /// surfacing the error — the misconfig check validates the pointer
    /// (handler.go:236) and gc's `validPendingNextWisp` clears a STALE one
    /// as a side effect (handler.go:935-945) even though this path pours
    /// nothing. Mutually exclusive with [burnWispId] (a pointer is either
    /// valid → burn, or stale → clear). See
    /// [FailedActionWrites.stalePendingClear].
    @Default(false) bool clearStalePending,
  }) = FailedAction;

  /// Re-enqueue [event] BEHIND the actions emitted alongside it — the
  /// protocol carrier for gc's inline drain on operator stop
  /// (manual.go:272-314). gc's `StopHandler`, finding the active wisp
  /// closed-but-unprocessed, runs the full `HandleWispClosed` INLINE
  /// (possibly a multi-minute fresh gate evaluation), re-reads metadata,
  /// and only then decides no-op vs force-close (including the
  /// `recoverCurrentActiveWisp` NotFound fallback, manual.go:275-289). The
  /// split reducer cannot block inside `reduce`, so
  /// `reduce(operatorStop)` over a closed-but-unprocessed active wisp
  /// returns the synthesized wispClosed drain pipeline with
  /// `requeue(operatorStop)` strictly LAST: Track G executes the drain
  /// actions (including any async `evaluateGate` hop), then re-enqueues
  /// [event] behind them on the same per-bead serial queue. For an operator
  /// stop the carried [event] is `OperatorStopEvent(postDrain: true)` — the
  /// re-entry marker is on the event itself (see
  /// [ReducerEvent.operatorStop]), so Track G re-enqueues [event] as-is and
  /// must NOT strip the flag. The re-entered stop reduces over post-drain
  /// state and the reducer's idempotent skip reasons absorb it: a drain
  /// that terminated the loop skips as [SkipReason.drainTerminated] /
  /// [SkipReason.alreadyStopped] (manual.go:296-308, 251-255 — wire
  /// `stopped` both ways); a surviving loop proceeds to the normal
  /// [ReconcilerAction.stopped] force-close/terminal protocol.
  ///
  /// `postDrain` is what lets the reducer reach [SkipReason.drainTerminated]
  /// at all: on a post-drain snapshot showing `terminated` with a
  /// non-`stopped` terminal reason, gc returns the no-reason `ActionStopped`
  /// ONLY because the same call ran the drain (manual.go:303-308); a fresh
  /// stop on the same shape ERRORs (manual.go:258-263). Without the marker
  /// the reducer could not tell those two apart from the snapshot. See
  /// [ReducerEvent.operatorStop] for the full causality.
  ///
  /// Pure carrier, like [ReconcilerAction.pourSpeculative]: NO metadata
  /// writes, no gc `HandlerAction` analog ([wire] → null). Always the
  /// LAST action in its list.
  const factory ReconcilerAction.requeue({
    /// The deferred reducer input, re-enqueued as-is. For the operator-stop
    /// drain this is `OperatorStopEvent(postDrain: true)` — the re-entry
    /// marker travels inside [event]; Track G preserves it verbatim.
    required ReducerEvent event,

    /// Diagnostic — why the event was deferred (e.g. "operator stop
    /// deferred behind drain of closed active wisp gt-w2").
    required String reason,
  }) = RequeueAction;

  /// gc's `HandlerAction` wire string (handler.go:120-128), or null for
  /// the carriers that have no `HandlerAction` analog
  /// ([PourSpeculativeAction], [EvaluateGateAction],
  /// [PersistGateOutcomeAction], [RepairIterationAction], [FailedAction],
  /// [RequeueAction] — gc performs these inside `HandleWispClosed` /
  /// `StopHandler` or returns an error).
  ///
  /// [SkippedAction] maps per [SkipReason]: the operator no-ops report
  /// gc's idempotent-success actions (`approved`/`stopped`), not `skipped`.
  String? get wire => switch (this) {
    IterateAction() => 'iterate',
    ApprovedAction() => 'approved',
    NoConvergenceAction() => 'no_convergence',
    WaitingManualAction() => 'waiting_manual',
    WaitingTriggerAction() => 'waiting_trigger',
    StoppedAction() => 'stopped',
    SkippedAction(:final reason) => switch (reason) {
      SkipReason.alreadyApproved => 'approved', // manual.go:30-34
      SkipReason.alreadyStopped => 'stopped', // manual.go:251-255
      SkipReason.drainTerminated => 'stopped', // manual.go:303-307
      SkipReason.alreadyTerminated ||
      SkipReason.duplicateWisp ||
      SkipReason.notWaitingTrigger ||
      SkipReason.triggerNotSatisfied => 'skipped',
    },
    PourSpeculativeAction() ||
    EvaluateGateAction() ||
    PersistGateOutcomeAction() ||
    RepairIterationAction() ||
    FailedAction() ||
    RequeueAction() => null,
  };

  /// The convergence root this action concerns. Every variant carries it
  /// directly except [RequeueAction], which derives it from the carried
  /// event (each [ReducerEvent] names its root).
  String get convergenceBeadId => switch (this) {
    IterateAction(convergenceBeadId: final id) ||
    ApprovedAction(convergenceBeadId: final id) ||
    NoConvergenceAction(convergenceBeadId: final id) ||
    WaitingManualAction(convergenceBeadId: final id) ||
    WaitingTriggerAction(convergenceBeadId: final id) ||
    StoppedAction(convergenceBeadId: final id) ||
    SkippedAction(convergenceBeadId: final id) ||
    PourSpeculativeAction(convergenceBeadId: final id) ||
    EvaluateGateAction(convergenceBeadId: final id) ||
    PersistGateOutcomeAction(convergenceBeadId: final id) ||
    RepairIterationAction(convergenceBeadId: final id) ||
    FailedAction(convergenceBeadId: final id) => id,
    RequeueAction(:final event) => event.convergenceBeadId,
  };
}

/// Ordered writes for [IterateAction] — see the variant's per-path actuator
/// protocol.
extension IterateActionWrites on IterateAction {
  List<MetadataWrite> get _verdictClears => clearVerdict
      ? const [
          MetadataWrite(key: ConvergenceFields.agentVerdict, value: ''),
          MetadataWrite(key: ConvergenceFields.agentVerdictWisp, value: ''),
        ]
      : const [];

  /// Writes applied BEFORE the pour/adopt/activate step.
  ///
  /// Only the wisp-closed handler path clears the verdict up front
  /// (handler.go:491-498 — the clears precede the fallback pour at
  /// handler.go:500-524 and ActivateWisp at handler.go:525; clearing after
  /// activation would race the next wisp's agent, gates-exec trap 21). The
  /// operator path deliberately clears AFTER the pour (manual.go:177-187 —
  /// a failed pour preserves the verdict for retry); the trigger path never
  /// clears (the waitingTrigger transition already did, handler.go:589-596).
  List<MetadataWrite> get preWrites => switch (path) {
    IteratePath.wispClosed => _verdictClears,
    IteratePath.operatorIterate || IteratePath.triggerAdvance => const [],
  };

  /// Whether the actuator activates the poured/adopted wisp (promote
  /// [DeferredWispFields] per node, recursing over children).
  /// wispClosed: handler.go:525. triggerAdvance: trigger.go:144. The
  /// operator path NEVER activates — manual.go pours visible (manual.go:166)
  /// and `IterateHandler` has no ActivateWisp call.
  bool get activatesWisp => path != IteratePath.operatorIterate;

  /// Ordered writes AFTER the pour (and activation where applicable),
  /// ending with the path's commit marker where one exists.
  List<MetadataWrite> postPourWrites(String nextWispId) => switch (path) {
    // handler.go:555-562: active_wisp, then last_processed_wisp LAST —
    // the dedup marker (ADR-0003 invariant 2).
    IteratePath.wispClosed => [
      MetadataWrite(key: ConvergenceFields.activeWisp, value: nextWispId),
      if (closedWispId case final closed?)
        MetadataWrite(key: ConvergenceFields.lastProcessedWisp, value: closed),
    ],
    // manual.go:177-199: scoped verdict clears AFTER the pour, then
    // waiting_reason '', state active, active_wisp. NO dedup marker
    // (manual.go:121-123 — the new wisp hasn't been processed yet).
    IteratePath.operatorIterate => [
      ..._verdictClears,
      const MetadataWrite(key: ConvergenceFields.waitingReason, value: ''),
      MetadataWrite(
        key: ConvergenceFields.state,
        value: ConvergenceState.active.wire,
      ),
      MetadataWrite(key: ConvergenceFields.activeWisp, value: nextWispId),
    ],
    // trigger.go:148-156: iteration ← EncodeInt(next), active_wisp, then
    // state ← active LAST. No waiting_reason write, no dedup marker.
    IteratePath.triggerAdvance => [
      MetadataWrite(
        key: ConvergenceFields.iteration,
        value: goEncodeInt(pour.iteration),
      ),
      MetadataWrite(key: ConvergenceFields.activeWisp, value: nextWispId),
      MetadataWrite(
        key: ConvergenceFields.state,
        value: ConvergenceState.active.wire,
      ),
    ],
  };

  /// Whether to best-effort clear `pending_next_wisp` after the commit
  /// (handler.go:563-565) — only the wisp-closed path does.
  bool get clearsPendingNextWisp => path == IteratePath.wispClosed;
}

/// Ordered terminal writes for [ApprovedAction].
extension ApprovedActionWrites on ApprovedAction {
  /// handler.go:687-698 (+ manual.go:71-73 for the operator's
  /// waiting-reason clear): `terminal_reason`, `terminal_actor`,
  /// (`waiting_reason` ← ''), `state` ← terminated. The root close and the
  /// final `last_processed_wisp` write follow.
  List<MetadataWrite> get terminalWrites => [
    MetadataWrite(
      key: ConvergenceFields.terminalReason,
      value: TerminalReason.approved.wire,
    ),
    MetadataWrite(key: ConvergenceFields.terminalActor, value: actor),
    if (clearWaitingReason)
      const MetadataWrite(key: ConvergenceFields.waitingReason, value: ''),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.terminated.wire,
    ),
  ];

  /// The final `last_processed_wisp` write (LAST, after the close — the
  /// store accepts metadata writes on a closed bead, spike-pinned), or null
  /// to skip.
  MetadataWrite? get commitWrite => lastProcessedWisp == null
      ? null
      : MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: lastProcessedWisp!,
        );
}

/// Ordered terminal writes for [NoConvergenceAction] (handler.go:687-698).
extension NoConvergenceActionWrites on NoConvergenceAction {
  List<MetadataWrite> get terminalWrites => [
    MetadataWrite(
      key: ConvergenceFields.terminalReason,
      value: TerminalReason.noConvergence.wire,
    ),
    MetadataWrite(key: ConvergenceFields.terminalActor, value: actor),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.terminated.wire,
    ),
  ];

  /// The final `last_processed_wisp` write (LAST), or null to skip.
  MetadataWrite? get commitWrite => lastProcessedWisp == null
      ? null
      : MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: lastProcessedWisp!,
        );
}

/// Ordered writes for [WaitingManualAction] (handler.go:442-453).
extension WaitingManualActionWrites on WaitingManualAction {
  /// The stale-pointer self-heal clear (handler.go:941), best-effort,
  /// applied FIRST when [WaitingManualAction.clearStalePending].
  MetadataWrite get stalePendingClear =>
      const MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: '');

  List<MetadataWrite> get orderedWrites => [
    const MetadataWrite(key: ConvergenceFields.activeWisp, value: ''),
    MetadataWrite(key: ConvergenceFields.waitingReason, value: reason.wire),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.waitingManual.wire,
    ),
    MetadataWrite(
      key: ConvergenceFields.lastProcessedWisp,
      value: closedWispId,
    ),
  ];
}

/// Ordered writes for [WaitingTriggerAction] (handler.go:589-628).
extension WaitingTriggerActionWrites on WaitingTriggerAction {
  List<MetadataWrite> get orderedWrites => [
    if (clearVerdict) ...[
      const MetadataWrite(key: ConvergenceFields.agentVerdict, value: ''),
      const MetadataWrite(key: ConvergenceFields.agentVerdictWisp, value: ''),
    ],
    const MetadataWrite(key: ConvergenceFields.activeWisp, value: ''),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.waitingTrigger.wire,
    ),
    MetadataWrite(
      key: ConvergenceFields.lastProcessedWisp,
      value: closedWispId,
    ),
  ];
}

/// Ordered writes for [StoppedAction] (manual.go:351-380).
extension StoppedActionWrites on StoppedAction {
  /// Verdict clears (unconditional — manual.go:351-356) then the terminal
  /// sequence (manual.go:369-380). The root close and the final
  /// `last_processed_wisp` write follow.
  List<MetadataWrite> get orderedWrites => [
    const MetadataWrite(key: ConvergenceFields.agentVerdict, value: ''),
    const MetadataWrite(key: ConvergenceFields.agentVerdictWisp, value: ''),
    MetadataWrite(
      key: ConvergenceFields.terminalReason,
      value: TerminalReason.stopped.wire,
    ),
    MetadataWrite(key: ConvergenceFields.terminalActor, value: actor),
    const MetadataWrite(key: ConvergenceFields.waitingReason, value: ''),
    MetadataWrite(
      key: ConvergenceFields.state,
      value: ConvergenceState.terminated.wire,
    ),
  ];

  /// The final `last_processed_wisp` write (LAST), or null to skip
  /// (manual.go:435-439).
  MetadataWrite? get commitWrite => lastProcessedWisp == null
      ? null
      : MetadataWrite(
          key: ConvergenceFields.lastProcessedWisp,
          value: lastProcessedWisp!,
        );
}

/// The `pending_next_wisp` writes for [PourSpeculativeAction].
extension PourSpeculativeActionWrites on PourSpeculativeAction {
  /// `pending_next_wisp` ← the poured/adopted wisp — written IMMEDIATELY
  /// after the pour, before the gate runs (handler.go:267-274; invariant 5).
  MetadataWrite pendingNextWispWrite(String wispId) =>
      MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: wispId);

  /// The stale-pointer self-heal clear (handler.go:941), best-effort,
  /// applied first when [PourSpeculativeAction.clearStalePending].
  MetadataWrite get stalePendingClear =>
      const MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: '');
}

/// The eight ordered writes for [PersistGateOutcomeAction]
/// (handler.go:776-808; gates-exec.md §7).
extension PersistGateOutcomeWrites on PersistGateOutcomeAction {
  /// In exactly this order, aborting on first error; `gate_outcome_wisp`
  /// LAST — the gate idempotency marker (ADR-0003 invariant 2). A crash
  /// before write 8 re-runs the gate; after it, re-processing replays the
  /// persisted result (handler.go:233-234, 280-298).
  List<MetadataWrite> get orderedWrites => [
    MetadataWrite(
      key: ConvergenceFields.gateOutcome,
      value: result.outcomeWire,
    ),
    MetadataWrite(
      key: ConvergenceFields.gateExitCode,
      // "" (not "0", not absent) when nil — handler.go:780-784.
      value: result.exitCode == null ? '' : goEncodeInt(result.exitCode!),
    ),
    MetadataWrite(
      key: ConvergenceFields.gateRetryCount,
      value: goEncodeInt(result.retryCount),
    ),
    MetadataWrite(key: ConvergenceFields.gateStdout, value: result.stdout),
    MetadataWrite(key: ConvergenceFields.gateStderr, value: result.stderr),
    MetadataWrite(
      key: ConvergenceFields.gateDurationMs,
      value: result.duration.inMilliseconds.toString(),
    ),
    MetadataWrite(
      key: ConvergenceFields.gateTruncated,
      // "true" or "" — never "false" (handler.go:799-803).
      value: goEncodeBool(value: result.truncated),
    ),
    MetadataWrite(key: ConvergenceFields.gateOutcomeWisp, value: wispId),
  ];
}

/// The single repair write for [RepairIterationAction] (handler.go:211).
extension RepairIterationActionWrites on RepairIterationAction {
  MetadataWrite get write => MetadataWrite(
    key: ConvergenceFields.iteration,
    value: goEncodeInt(derivedIteration),
  );
}

/// The best-effort writes for [FailedAction]'s misconfig path.
extension FailedActionWrites on FailedAction {
  /// The stale-pointer self-heal clear (handler.go:941), best-effort,
  /// applied BEFORE surfacing the error when
  /// [FailedAction.clearStalePending].
  MetadataWrite get stalePendingClear =>
      const MetadataWrite(key: ConvergenceFields.pendingNextWisp, value: '');
}
