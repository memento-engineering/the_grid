# Conformance spec — `reconcile_test.go` → Dart (Track H, ADR-0003 Decision 7)

**Source of truth (read-only, pinned on disk):**
`/Users/nico/development/com.gastownhall/gascity/internal/convergence/reconcile_test.go` (962 lines)
**Code under test:** `/Users/nico/development/com.gastownhall/gascity/internal/convergence/reconcile.go` (690 lines)
**Supporting Go files referenced below** (all under `gascity/internal/convergence/`):
`handler.go` (key helpers, `HandleWispClosed`), `metadata.go` (field/value constants), `events.go`
(event types, IDs, payloads), `manual.go` (`recoverCurrentActiveWisp`), `template.go` (`ExtractVars`),
`handler_test.go` (the `fakeStore`/`fakeEmitter` the Dart fakes must reproduce).

This file is the **executable spec for the startup/backstop recovery paths** (ADR-0003 Decision 2,
"Recovery paths"). gc detects nothing here by polling — `ReconcileBeads` is a pure pass over a list of
bead IDs against the `Store` interface, so every test in this file ports to offline Dart with fakes.
A Dart implementer should be able to write the entire transliterated suite from this document alone.

---

## 1. Domain constants the suite asserts (exact literals)

### 1.1 Metadata keys (`metadata.go:12-44`)

| Go constant | Literal key |
|---|---|
| `FieldState` | `convergence.state` |
| `FieldIteration` | `convergence.iteration` |
| `FieldMaxIterations` | `convergence.max_iterations` |
| `FieldFormula` | `convergence.formula` |
| `FieldTarget` | `convergence.target` |
| `FieldGateMode` | `convergence.gate_mode` |
| `FieldGateCondition` | `convergence.gate_condition` |
| `FieldGateTimeout` | `convergence.gate_timeout` |
| `FieldGateTimeoutAction` | `convergence.gate_timeout_action` |
| `FieldActiveWisp` | `convergence.active_wisp` |
| `FieldLastProcessedWisp` | `convergence.last_processed_wisp` |
| `FieldAgentVerdict` | `convergence.agent_verdict` |
| `FieldAgentVerdictWisp` | `convergence.agent_verdict_wisp` |
| `FieldGateOutcome` | `convergence.gate_outcome` |
| `FieldGateExitCode` | `convergence.gate_exit_code` |
| `FieldGateOutcomeWisp` | `convergence.gate_outcome_wisp` |
| `FieldGateRetryCount` | `convergence.gate_retry_count` |
| `FieldTerminalReason` | `convergence.terminal_reason` |
| `FieldTerminalActor` | `convergence.terminal_actor` |
| `FieldWaitingReason` | `convergence.waiting_reason` |
| `FieldRig` | `convergence.rig` |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` |
| `FieldGateStdout` | `convergence.gate_stdout` |
| `FieldGateStderr` | `convergence.gate_stderr` |
| `FieldGateDurationMs` | `convergence.gate_duration_ms` |
| `FieldGateTruncated` | `convergence.gate_truncated` |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` |
| `FieldTrigger` | `convergence.trigger` |
| `FieldTriggerCondition` | `convergence.trigger_condition` |

### 1.2 Metadata values (`metadata.go:49-102`)

| Domain | Go constant | Literal value |
|---|---|---|
| state | `StateCreating` | `creating` |
| state | `StateActive` | `active` |
| state | `StateWaitingManual` | `waiting_manual` |
| state | `StateWaitingTrigger` | `waiting_trigger` |
| state | `StateTerminated` | `terminated` |
| trigger | `TriggerNone` | `` (empty string) |
| trigger | `TriggerEvent` | `event` |
| gate_mode | `GateModeManual` | `manual` |
| gate_mode | `GateModeCondition` | `condition` |
| gate_mode | `GateModeHybrid` | `hybrid` |
| timeout_action | `TimeoutActionIterate` | `iterate` |
| timeout_action | `TimeoutActionRetry` | `retry` |
| timeout_action | `TimeoutActionManual` | `manual` |
| timeout_action | `TimeoutActionTerminate` | `terminate` |
| terminal_reason | `TerminalApproved` | `approved` |
| terminal_reason | `TerminalNoConvergence` | `no_convergence` |
| terminal_reason | `TerminalStopped` | `stopped` |
| terminal_reason | `TerminalPartialCreation` | `partial_creation` |
| gate_outcome | `GatePass` | `pass` |
| gate_outcome | `GateFail` | `fail` |
| gate_outcome | `GateTimeout` | `timeout` |
| gate_outcome | `GateError` | `error` |
| waiting_reason | `WaitManual` | `manual` |
| waiting_reason | `WaitHybridNoCondition` | `hybrid_no_condition` |
| waiting_reason | `WaitTimeout` | `timeout` |
| waiting_reason | `WaitSlingFailure` | `sling_failure` |

### 1.3 Reconcile actions (`reconcile.go:15`)

`ReconcileDetail.Action` is one of exactly: `completed_terminal`, `adopted_wisp`, `poured_wisp`,
`repaired_state`, `no_action`. **On failure the action is the *attempted* action** (e.g. a failed
pour reports `Action: "poured_wisp"` with `Error` set — `reconcile.go:180-184`); only
metadata/bead-read failures report `no_action` + error (`reconcile.go:67`, `reconcile.go:117-121`).

### 1.4 Idempotency keys (`handler.go:13-39`)

- `IdempotencyKeyPrefix(beadID)` = `converge:{beadID}:iter:` — **note trailing colon** (`handler.go:14`).
- `IdempotencyKey(beadID, N)` = `converge:{beadID}:iter:{N}` — 1-based for real iterations
  (`handler.go:19-21`), but `ParseIterationFromKey` accepts `N >= 0` (`handler.go:35`) and one test
  stores a `:iter:0` key (test 11 below).
- `ParseIterationFromKey` searches the **last** occurrence of marker `:iter:` (`handler.go:29`,
  `strings.LastIndex`), parses the suffix as int; returns `(0,false)` on non-numeric or negative.

### 1.5 Events (`events.go:11-20`, `events.go:37-81`)

| Go constant | Event type literal | Event ID format |
|---|---|---|
| `EventTerminated` | `convergence.terminated` | `converge:{beadID}:terminated` |
| `EventWaitingManual` | `convergence.waiting_manual` | `converge:{beadID}:iter:{N}:waiting_manual` |
| `EventIteration` | `convergence.iteration` | `converge:{beadID}:iter:{N}:iteration` |

Recovery events are emitted via `emitRecoveryEvent` (`reconcile.go:685-690`) with **`recovery: true`**
and payload routed through `Handler.withEventRig` (`handler.go:860-884`), which **re-reads the root
bead's metadata** and injects `meta["convergence.rig"]` into the payload's `rig` field (JSON key
`rig`, `omitempty`).

Payload shapes asserted by this suite (`events.go:124-145`):

- `TerminatedPayload`: `rig` (omitempty), `terminal_reason`, `total_iterations`, `final_status`
  (always `"closed"`), `actor`, `cumulative_duration_ms`.
- `WaitingManualPayload`: `rig` (omitempty), `iteration`, `wisp_id`, `agent_verdict`, `gate_mode`,
  `gate_outcome` (nullable), `gate_result` (nullable), `reason`, `iteration_duration_ms`,
  `cumulative_duration_ms`.

### 1.6 Close reason (`handler.go:52`)

`CloseReasonReconcileDone` = `convergence reconcile: terminated-state bead closed`
(every `CloseBead` in `reconcile.go` uses it: lines 229, 288, 583; ≥20 chars to satisfy bd's
`validation.on-close=error` validator, `handler.go:41-45`).

### 1.7 Encoding helpers (`metadata.go:140-156`)

- `EncodeInt(n)` → decimal string (`"0"`, `"1"`, …).
- `DecodeInt("")` → `(0, false)`; non-integer → `(0, false)`. **Missing iteration metadata decodes
  to 0** and that 0 flows into event IDs (`reconcile.go:315`, `reconcile.go:325`).

---

## 2. Report semantics (`reconcile.go:43-59`)

`ReconcileBeads(ctx, beadIDs) → ReconcileReport{Scanned, Recovered, Errors, Details[]}`:

- `Scanned` = `len(beadIDs)` (set up-front, includes erroring beads).
- Per bead, in **input order** (⚠ ordering — `Details` preserves the input list order):
  - `Errors++` iff `detail.Error != nil`;
  - **else** `Recovered++` iff `detail.Action != "no_action"`.
  - ⚠ An errored detail never counts as Recovered even when its `Action` label is a recovery action.
- `ReconcileBeads` itself **never returns a non-nil error** — all failures are per-detail.
- Per-bead dispatch (`reconcileBead`, `reconcile.go:64-107`) switches on `meta["convergence.state"]`:
  `""` → Path 1a, `creating` → Path 1b, `terminated` → Path 2, `waiting_manual` → Path 3,
  `waiting_trigger` → Path 3t, `active` → Path 4, anything else → `no_action` + error
  `unknown convergence state %q`. A `GetMetadata` failure → `no_action` + error wrapping
  `reading metadata:`.

---

## 3. Fake contract the Dart suite must reproduce (`handler_test.go:16-305`)

The reconcile tests run entirely against `fakeStore` + `fakeEmitter`. The Dart fakes (per project
convention: **Fakes, not mocks**) must support:

| Member | Behavior (file:line) |
|---|---|
| `addBead(id, status, parentID, idempotencyKey, meta)` | Inserts record with `CreatedAt = now − 10min`, `ClosedAt = now`, registers `id` in parent's child list when `parentID != ""` (`handler_test.go:48-71`). `meta == null` → empty map. |
| `GetBead(id)` | Returns `BeadInfo{ID, Status, ParentID, IdempotencyKey, CreatedAt, ClosedAt}`; missing → error **wrapping the typed not-found sentinel** (`beads.ErrNotFound`, `handler_test.go:81`). Overridable via `GetBeadFunc` for fault injection (`handler_test.go:33`, `:74-76`). |
| `GetMetadata(id)` | Returns a **copy** of the metadata map; missing bead → not-found error (`handler_test.go:86-99`). |
| `SetMetadata(id, key, value)` | Writes and **appends `key` to `WriteLog`** (ordering assertions; `handler_test.go:101-111`). |
| `CloseBead(id, reason)` | `status = "closed"`, `ClosedAt = now`, and stores `reason` under metadata key `close_reason` when non-empty (`handler_test.go:113-129`). |
| `DeleteBead(id)` | Removes record and de-registers from parent's child list (`handler_test.go:131-151`). |
| `Children(parentID)` | ⚠ Unknown parent returns `(nil, nil)` — **empty, no error** (`handler_test.go:156-158`); recovery code relies on this leniency. |
| `PourWisp` / `PourSpeculativeWisp` | **Idempotent on key**: if any bead already holds `idempotencyKey`, return its ID; else mint `wisp-{counter}` (counter starts at 1), status `in_progress`, registered as child of parent (`handler_test.go:169-211`). Both overridable via `PourWispFunc` / `PourSpeculativeWispFunc`. |
| `FindByIdempotencyKey(key)` | Linear scan → `(id, true, nil)` or `("", false, nil)`; overridable (`handler_test.go:213-225`). |
| `ActivateWisp(id)` | Appends to `ActivatedWispIDs`; missing bead → not-found error; overridable (`handler_test.go:227-238`). |
| `fakeEmitter.Emit(type, eventID, beadID, payload, recovery)` | Appends to an ordered list (`handler_test.go:284-294`). |
| `fakeEmitter.findEvent(type)` | First event whose `Type` matches (`handler_test.go:296-305`). |

Test harness (`reconcile_test.go:16-26`): `setupReconciler` = empty `fakeStore` + `fakeEmitter` +
`Handler{Store, Emitter, Clock: time.Now}` wrapped in `Reconciler{Handler: handler}`. The Dart
equivalent: a `Reconciler` that reuses the handler's store/emitter, with injectable clock.

⚠ The Dart fake **must distinguish a typed NotFound error from a generic store failure** —
`reconcileActive` branches on exactly this (`reconcile.go:403`): NotFound → recovery chain;
any other error → report error, no mutation.

---

## 4. Test-by-test conformance checklist

27 test functions; **none are table-driven** — every entry below is one scenario.
Invariant numbers reference ADR-0003 §"Invariants" (1–7); transition rows reference the ADR-0003
state-machine + recovery tables (recovery rows quoted from ADR-0003 Decision 2).

Legend for setup column: `root(state=…, …)` is `addBead("root-1","in_progress","","",{…})` unless
stated; `wisp(id,status,iterN)` is `addBead(id, status, "root-1", IdempotencyKey("root-1",N), nil)`.

### Path 3t — `waiting_trigger` (`reconcile.go:376-385`)

**1. `TestReconcile_WaitingTrigger_NoAction`** (`reconcile_test.go:30-53`) — **must**
- Given a root in `waiting_trigger` with `convergence.trigger`=`event`,
  `convergence.trigger_condition`=`/scripts/check`, no terminal_reason; when reconciled; then the
  pass leaves trigger holds alone (the tick re-evaluates the trigger).
- Asserts: `Details.length == 1`; `Details[0].Action == "no_action"`;
  `meta["convergence.state"] == "waiting_trigger"` (state preserved).
- Invariants/rows: recovery row "`waitingTrigger` → no-op unless terminal".
- Fake needs: metadata read only.

**2. `TestReconcile_WaitingTrigger_CompletesInterruptedStop`** (`reconcile_test.go:55-77`) — **must**
- Given a root in `waiting_trigger` with `convergence.terminal_reason`=`stopped`; when reconciled;
  then the interrupted stop is completed via `completeTerminalTransition` (`reconcile.go:379-381`).
- Asserts: `Action == "completed_terminal"`; bead `Status == "closed"`.
- Side effects not asserted but performed: `terminal_actor` backfilled to `recovery` (none set),
  `convergence.terminated` event (recovery=true), `state`=`terminated` write, close reason
  `convergence reconcile: terminated-state bead closed`.
- Invariants/rows: row "any | operator stop → terminated `stopped`" (completion half); invariant 6.
- Fake needs: SetMetadata, CloseBead, Children (returns empty), Emit.

### Path 1a — missing/empty state (`reconcile.go:111-206`)

**3. `TestReconcile_MissingState_NoWisps_PoursFirst`** (`reconcile_test.go:81-121`) — **must**
- Given a root with formula/max_iterations/target but **no** `convergence.state`; when reconciled;
  then the first wisp is poured with key `converge:root-1:iter:1` and the loop is activated.
- Asserts: `Scanned == 1`, `Recovered == 1`, `Errors == 0`; `Action == "poured_wisp"`,
  `Error == nil`; `meta["convergence.state"] == "active"`; `meta["convergence.active_wisp"] != ""`.
- ⚠ ordering (`reconcile.go:186-203`): `active_wisp` → `iteration`=`"0"` → `state`=`"active"` —
  **state is written LAST** (it is the commit point that takes the bead out of Path 1a).
- ⚠ `iteration` is set to `"0"`, not `"1"` — the field counts **closed** wisps (invariant 4).
- Pour args (`reconcile.go:174-178`): `formula = meta["convergence.formula"]`,
  `vars = ExtractVars(meta)` (`var.`-prefixed keys, prefix stripped — `template.go:43-51`),
  `evaluatePrompt = meta["convergence.evaluate_prompt"]`.
- Invariants/rows: row "`\"\"` → adopt or pour wisp 1"; invariants 3, 4.
- Fake needs: FindByIdempotencyKey (miss), PourWisp (auto-ID), SetMetadata ×3.

**4. `TestReconcile_MissingState_WispExists_Adopts`** (`reconcile_test.go:123-156`) — **must**
- Given the same root plus a pre-existing **open** bead `existing-wisp` with key
  `converge:root-1:iter:1`; when reconciled; then the wisp is adopted instead of double-poured.
- Asserts: `Action == "adopted_wisp"`, `Error == nil`; `state == "active"`;
  `active_wisp == "existing-wisp"`.
- ⚠ ordering (`reconcile.go:133-157`): `active_wisp` → `iteration` (`"0"` because the wisp is open;
  would be `"1"` if closed) → `state`=`"active"`. If the adopted wisp were closed, the transition is
  **replayed** through `HandleWispClosed` (`reconcile.go:161-168`) — that branch is untested (gap G3).
- Invariants/rows: row "`\"\"` → adopt or pour wisp 1"; invariant 3 (re-pour returns existing).
- Fake needs: FindByIdempotencyKey (hit), GetBead, SetMetadata ×3.

### Path 1b — `creating` (`reconcile.go:210-236`)

**5. `TestReconcile_StateCreating_TerminatesPartialCreation`** (`reconcile_test.go:160-202`) — **must**
- Given a root with only `convergence.state`=`creating` (interrupted creation); when reconciled;
  then the partial bead is terminated and closed.
- Asserts: `Recovered == 1`, `Errors == 0`; `Action == "completed_terminal"`, `Error == nil`;
  `meta["convergence.terminal_reason"] == "partial_creation"`;
  `meta["convergence.terminal_actor"] == "recovery"`;
  `meta["convergence.state"] == "terminated"`; bead `Status == "closed"`.
- ⚠ ordering (`reconcile.go:211-229`): `terminal_reason` → `terminal_actor` → `state`=`terminated`
  → `CloseBead(id, "convergence reconcile: terminated-state bead closed")`. No event is emitted on
  this path.
- Invariants/rows: recovery row "`creating` → terminate (partial creation)".
- Fake needs: SetMetadata ×3, CloseBead.

### Path 2 — `terminated` but not closed (`reconcile.go:240-296`)

**6. `TestReconcile_TerminatedNotClosed_CompletesClosure`** (`reconcile_test.go:206-255`) — **must**
- Given a root `in_progress` with `state`=`terminated`, `terminal_reason`=`approved`,
  `terminal_actor`=`controller`, `convergence.rig`=`prod`, plus closed `wisp-1` (key iter:1);
  when reconciled; then closure is completed and the terminated event re-emitted.
- Asserts: `Action == "completed_terminal"`, `Error == nil`; bead `Status == "closed"`;
  emitter contains an event of type `convergence.terminated` with `BeadID == "root-1"` and
  JSON payload `rig == "prod"`.
- Payload values produced (not all asserted): `terminal_reason`=`approved` (from metadata; empty
  would default to `no_convergence`, `reconcile.go:266-268`), `total_iterations`=1 (derived from
  closed children), `final_status`=`"closed"`, `actor`=`controller`,
  `cumulative_duration_ms` = Σ(closedAt−createdAt) over closed prefixed children
  (`reconcile.go:666-680`; ≈600000 with the fake's −10min createdAt).
- ⚠ ordering (`reconcile.go:255-295`): backfill actor (no-op here) → **emit `convergence.terminated`
  (recovery=true) BEFORE `CloseBead`** (at-least-once / TierCritical semantics) → close.
- Invariants/rows: recovery row "`terminated`-but-open → close + re-emit"; invariants 2 (commit
  completion), 6.
- Fake needs: GetBead, Children with prefix-keyed closed child, Emit, CloseBead;
  `withEventRig` requires a second `GetMetadata` on the root.

**7. `TestReconcile_TerminatedNotClosed_BackfillsActor`** (`reconcile_test.go:257-281`) — **must**
- Given `state`=`terminated`, `terminal_reason`=`stopped`, **no** `terminal_actor`; when reconciled;
  then the actor is backfilled before closure.
- Asserts: `Action == "completed_terminal"`;
  `meta["convergence.terminal_actor"] == "recovery"` (`backfillTerminalActor`, `reconcile.go:604-609`).
- Invariants/rows: same row as test 6.
- Fake needs: SetMetadata, CloseBead, Emit.

**8. `TestReconcile_TerminatedAlreadyClosed_NoAction`** (`reconcile_test.go:283-301`) — **must**
- Given a root already `closed` with `state`=`terminated`; when reconciled; then nothing happens.
- Asserts: `Action == "no_action"` (`reconcile.go:249-252`).
- Invariants/rows: invariant 6 (terminal irreversibility — terminated + closed is final).
- Fake needs: GetBead only.

### Path 3 — `waiting_manual` (`reconcile.go:300-372`)

**9. `TestReconcile_WaitingManual_TerminalReasonSet_CompletesTerminal`** (`reconcile_test.go:305-346`) — **must**
- Given `state`=`waiting_manual`, `waiting_reason`=`manual`, `terminal_reason`=`stopped`,
  `terminal_actor`=`operator:alice`, plus closed `wisp-1` (iter:1); when reconciled; then the
  interrupted stop is completed (Sub-path A, `reconcile.go:306-308`).
- Asserts: `Action == "completed_terminal"`, `Error == nil`; bead `Status == "closed"`;
  `meta["convergence.state"] == "terminated"`; a `convergence.terminated` event exists.
- ⚠ ordering (`completeTerminalTransition`, `reconcile.go:545-599`): backfill actor → emit
  `convergence.terminated` (recovery=true, event ID `converge:root-1:terminated`) → write
  `state`=`terminated` (only because snapshot state ≠ terminated) → `CloseBead` → **write
  `last_processed_wisp` = highest closed wisp (`wisp-1`) LAST**, errors ignored
  (`reconcile.go:590-597`). last-write-wins is invariant 2's commit point.
- Invariants/rows: rows "any | operator stop → terminated `stopped`",
  "`waitingManual` → … repair markers"; invariants 2, 6.
- Fake needs: SetMetadata, CloseBead, Children, Emit.

**10. `TestReconcile_WaitingManual_GenuineHold_NoStateChange`** (`reconcile_test.go:348-394`) — **must**
- Given a genuine hold: `state`=`waiting_manual`, `waiting_reason`=`manual`,
  `last_processed_wisp`=`wisp-1`, `gate_mode`=`manual`, `iteration`=`"1"`, `rig`=`prod`, with closed
  `wisp-1` (iter:1) being the highest closed wisp; when reconciled; then the hold is preserved and
  the waiting event re-emitted for consumers that lost it in a crash.
- Asserts: `Action == "no_action"`; `meta["convergence.state"] == "waiting_manual"`;
  a `convergence.waiting_manual` event exists with **`Recovery == true`** and payload `rig == "prod"`.
- Event detail (`reconcile.go:315-325`): event ID `converge:root-1:iter:1:waiting_manual`
  (iteration decoded from metadata), payload `iteration`=1, `wisp_id`=`wisp-1` (from
  `last_processed_wisp`), `gate_mode`=`manual`, `reason`=`manual`, cumulative duration best-effort.
- ⚠ The event is emitted **before** the repair check; a hold re-emits on **every** reconcile pass
  (TierRecoverable, dedup is the consumer's job via stable event ID).
- Invariants/rows: recovery row "`waitingManual` → re-emit hold, repair markers".
- Fake needs: Children, Emit; no writes.

**11. `TestReconcile_WaitingManual_GenuineHold_RepairsLastProcessedWisp`** (`reconcile_test.go:396-425`) — **must**
- Given a hold whose `last_processed_wisp`=`wisp-0` is stale: closed `wisp-0` (key
  `converge:root-1:iter:0`) and closed `wisp-1` (key iter:1) both exist; when reconciled; then the
  marker is repaired to the highest-iteration closed wisp.
- Asserts: `Action == "repaired_state"`;
  `meta["convergence.last_processed_wisp"] == "wisp-1"` (`reconcile.go:336-345`).
- ⚠ A `:iter:0` key is valid input — `ParseIterationFromKey` accepts 0 (`handler.go:35`).
- ⚠ The waiting_manual recovery event is still emitted first (iteration decodes to 0 here since
  `convergence.iteration` is unset → event ID `converge:root-1:iter:0:waiting_manual`); the test
  does not assert it.
- Invariants/rows: invariants 1, 2, 4 (marker repair from derived truth); row "`waitingManual` →
  re-emit hold, repair markers".
- Fake needs: Children, SetMetadata, Emit.

### Path 4 — `active` (`reconcile.go:389-539`)

**12. `TestReconcile_Active_ClosedUnprocessedWisp_Replays`** (`reconcile_test.go:429-474`) — **must**
- Given `state`=`active`, `iteration`=`"1"`, `max_iterations`=`"5"`, `active_wisp`=`wisp-iter-1`,
  `gate_mode`=`condition`, `gate_timeout`=`60s`, `gate_timeout_action`=`iterate`, and the **cached
  gate outcome** `gate_outcome_wisp`=`wisp-iter-1`, `gate_outcome`=`fail`; `wisp-iter-1` is closed
  (key iter:1) and ≠ `last_processed_wisp`; when reconciled; then the missed `wisp_closed` is
  **replayed through `HandleWispClosed`** (`reconcile.go:455-464`) and, because gate=fail with
  iter 1 < max 5, the loop iterates.
- Asserts: `Action == "repaired_state"`, `Error == nil`; `meta["convergence.active_wisp"]` is
  non-empty **and** ≠ `wisp-iter-1` (a new wisp was poured); a `convergence.iteration` event exists.
- Replay mechanics that the Dart port must reproduce (`handler.go:233-234`, `:280-298`):
  `gate_outcome_wisp == wispID` ⇒ `skipGateEval` — the persisted outcome is used; **no gate script
  runs**. Speculative pour still happens first (step 3b, `handler.go:244-275`): next wisp poured
  with key `converge:root-1:iter:2` and recorded under `pending_next_wisp` **before** outcome
  handling (invariant 5). last_processed_wisp written last (invariant 2).
- Invariants/rows: transition row "active | wisp closed | gate=fail ∧ iter<max → active, `iterate`";
  recovery row "`active` → … replay closed wisp"; invariants 1, 2, 3, 5.
- Fake needs: GetBead, Children, PourSpeculativeWisp (idempotent), SetMetadata, Emit.

**13. `TestReconcile_Active_MissingActiveWisp_ReconstructsChain`** (`reconcile_test.go:476-518`) — **must**
- Given `state`=`active` with `active_wisp`=`wisp-iter-2` pointing at a bead that **does not exist**
  (cleaned up post-crash) and `last_processed_wisp`=`wisp-iter-1` (closed, key iter:1); no iter:2
  bead exists anywhere; when reconciled; then the chain is rebuilt instead of stalling: GetBead
  yields NotFound → `recoverCurrentActiveWisp` (`manual.go:447-518`) looks for key
  `converge:root-1:iter:2`, finds nothing → `active_wisp` treated as stale/empty
  (`reconcile.go:417-421`) → fall through to derive-and-pour (`reconcile.go:477-538`).
- Asserts: `Error == nil`; `Action` ∈ {`"poured_wisp"`, `"adopted_wisp"`} (both accepted);
  `meta["convergence.active_wisp"]` non-empty **and** resolvable via `GetBead`.
- Derivation: `closedIter = deriveIterationFromChildren = 1`, `nextIter = 2`,
  `nextKey = converge:root-1:iter:2`; pours since no pending/existing wisp.
- ⚠ ordering (`reconcile.go:523-536`): pour/adopt → `ActivateWisp(wispID)` → set `active_wisp` →
  clear `pending_next_wisp` (`""`, error ignored).
- Invariants/rows: recovery row "`active` → recover active wisp / pour next"; invariants 3, 4.
- Fake needs: typed NotFound from GetBead, Children, FindByIdempotencyKey, PourWisp, ActivateWisp,
  SetMetadata.

**14. `TestReconcile_Active_MissingActiveWisp_ReplaysRecoveredClosedReplacement`** (`reconcile_test.go:520-560`) — **must**
- Given the same stale `active_wisp`=`wisp-iter-2`, `last_processed_wisp`=`wisp-iter-1` (closed,
  iter:1), plus a **closed replacement** `wisp-replacement` with key `converge:root-1:iter:2`, and
  cached gate outcome `gate_outcome_wisp`=`wisp-replacement`, `gate_outcome`=`pass`; when
  reconciled; then `recoverCurrentActiveWisp` finds the replacement by next-iteration key
  (`manual.go:467-483`), repairs `active_wisp` to it (`reconcile.go:427-435`), sees it closed and
  unprocessed, and **replays** `HandleWispClosed` → cached `pass` → terminal `approved`.
- Asserts: `Error == nil`; `Action == "repaired_state"`;
  `meta["convergence.state"] == "terminated"`;
  `meta["convergence.last_processed_wisp"] == "wisp-replacement"`.
- ⚠ Inside the replay, a speculative iter:3 wisp is poured then **burned** (subtree-deleted +
  `pending_next_wisp` cleared) before the terminal transition (`handler.go:384-387`,
  `burnSpeculativeWisp` `handler.go:908-917`) — the Dart fake must support `DeleteBead`.
- Invariants/rows: transition row "active | wisp closed | gate=pass → terminated, `approved`";
  invariants 1, 2 (lpw written last in `terminate`), 3, 5, 6.
- Fake needs: NotFound GetBead, FindByIdempotencyKey hit, GetBead, Children,
  PourSpeculativeWisp, DeleteBead, CloseBead, SetMetadata, Emit.

**15. `TestReconcile_Active_MissingActiveWisp_RepairsOpenReplacementMetadata`** (`reconcile_test.go:562-597`) — **must**
- Same as 14 but `wisp-replacement` is **`in_progress`** and there is no cached gate outcome; when
  reconciled; then the replacement is adopted as the active wisp and nothing else changes
  (`reconcile.go:436-443`: open/in_progress + recovered → `repaired_state`).
- Asserts: `Error == nil`; `Action == "repaired_state"`;
  `meta["convergence.active_wisp"] == "wisp-replacement"`.
- Invariants/rows: recovery row "`active` → recover active wisp"; invariant 3.
- Fake needs: NotFound GetBead, FindByIdempotencyKey, GetBead, SetMetadata.

**16. `TestReconcile_Active_StoreErrorReadingActiveWisp_ReportsError`** (`reconcile_test.go:599-626`) — **must**
- Given `state`=`active`, `active_wisp`=`wisp-iter-1`, and `GetBeadFunc` injected to fail with a
  **generic (non-NotFound)** error `store unavailable for {id}`; when reconciled; then the failure
  is reported, no recovery is attempted, and no state is mutated (`reconcile.go:401-408`).
- Asserts: `Details[0].Error != nil`; error text **contains**
  `store unavailable for wisp-iter-1`; `Action == "no_action"`.
- ⚠ Dart adaptation: keep the behavioral assertions (error reported, no mutation, action
  `no_action`); match the injected exception's message rather than Go's wrapped-error text. The
  load-bearing behavior is the **NotFound vs transient-failure branch** — only NotFound triggers
  the recovery chain of tests 13–15.
- Invariants/rows: error taxonomy guarding the "`active` → recover" recovery row.
- Fake needs: `GetBeadFunc`-style override hook.

**17. `TestReconcile_Active_OpenWisp_NoAction`** (`reconcile_test.go:628-649`) — **must**
- Given `state`=`active` and `active_wisp`=`wisp-iter-1` which exists and is `in_progress`
  (key iter:1); when reconciled; then nothing happens (`reconcile.go:436-443`, non-recovered arm).
- Asserts: `Action == "no_action"`.
- Invariants/rows: recovery row "`active` → no-op while wisp runs".
- Fake needs: GetBead.

**18. `TestReconcile_Active_TerminalReasonSet_CompletesStop`** (`reconcile_test.go:651-690`) — **must**
- Given `state`=`active`, `terminal_reason`=`stopped`, `terminal_actor`=`operator:bob`, closed
  `wisp-1` (iter:1); when reconciled; then Sub-path A completes the stop (`reconcile.go:392-394` →
  `completeTerminalTransition`).
- Asserts: `Action == "completed_terminal"`, `Error == nil`; bead `Status == "closed"`;
  `meta["convergence.state"] == "terminated"`; a `convergence.terminated` event exists.
- Same ⚠ ordering as test 9 (state write → close → `last_processed_wisp`=`wisp-1` LAST).
- Invariants/rows: row "any | operator stop → terminated `stopped`"; invariants 2, 6.
- Fake needs: SetMetadata, CloseBead, Children, Emit.

**19. `TestReconcile_Active_EmptyActiveWisp_PoursNext`** (`reconcile_test.go:692-721`) — **must**
- Given `state`=`active`, `active_wisp`=`""`, one closed `wisp-1` (key iter:1); when reconciled;
  then iteration is derived from children (closed=1 → next=2) and the iter:2 wisp is poured
  (`reconcile.go:477-538`).
- Asserts: `Action == "poured_wisp"`, `Error == nil`; `meta["convergence.active_wisp"] != ""`.
- Invariants/rows: recovery row "`active` → pour next"; invariants 3, 4.
- Fake needs: Children, FindByIdempotencyKey miss, PourWisp, ActivateWisp, SetMetadata.

**20. `TestReconcile_Active_EmptyActiveWisp_AdoptsExisting`** (`reconcile_test.go:723-752`) — **must**
- Same as 19 plus an existing `in_progress` `wisp-2` with key `converge:root-1:iter:2` (poured
  before the crash); when reconciled; then it is adopted, not re-poured.
- Asserts: `Action == "adopted_wisp"`; `meta["convergence.active_wisp"] == "wisp-2"`.
- ⚠ Lookup order (`reconcile.go:492-521`): `validPendingNextWisp(pending_next_wisp)` first
  (validates parent + key + not-closed, clearing the field if invalid — `handler.go:935-945`),
  then `FindByIdempotencyKey(nextKey)`, then pour. This test exercises the second.
- Invariants/rows: invariant 3 (idempotent adoption), 5 (`pending_next_wisp` recovery channel).
- Fake needs: Children, FindByIdempotencyKey hit, ActivateWisp, SetMetadata.

**21. `TestReconcile_Active_AlreadyProcessed_NoAction`** (`reconcile_test.go:756-777`) — **must**
- Given `state`=`active`, `active_wisp` == `last_processed_wisp` == `wisp-iter-1`, wisp closed
  (key iter:1); when reconciled; then the closed wisp is recognized as already committed
  (`reconcile.go:447-453`: `last_processed_wisp` set ⇒ the commit completed, because it is always
  the last write).
- Asserts: `Action == "no_action"`.
- Invariants/rows: **invariant 1 (monotonic dedup) + invariant 2 (lpw as commit marker)** — the
  central crash-safety assertion of the recovery pass.
- Fake needs: GetBead.

### Multi-bead / reporting / events

**22. `TestReconcile_MultipleBeads_ContinuesOnError`** (`reconcile_test.go:781-834`) — **must**
- Given `bead-1` (terminated-not-closed, needs recovery), `bead-2` (absent from the store),
  `bead-3` (terminated and already closed); when `ReconcileBeads(["bead-1","bead-2","bead-3"])`;
  then the scan continues past the error.
- Asserts: `Scanned == 3`, `Errors == 1`, `Recovered == 1`, `Details.length == 3`;
  `Details[0].Action == "completed_terminal"`; `Details[1].Error != nil`;
  `Details[2].Action == "no_action"`.
- ⚠ ordering: `Details` mirror input order; accounting per §2 (errored bead is not Recovered).
- Invariants/rows: invariant 7's serialized per-bead processing (sequential, isolated failures).
- Fake needs: NotFound from GetMetadata.

**23. `TestReconcile_RecoveryEventsHaveRecoveryFlag`** (`reconcile_test.go:838-880`) — **must**
- Given a terminated-not-closed bead (as test 6, minus rig) and an emitter that records the
  `recovery` flag per emit; when reconciled; then at least one event is captured and **every**
  captured event has `recovery == true` (`emitRecoveryEvent` hard-codes `true`,
  `reconcile.go:685-690`).
- Asserts: `captured.length > 0`; `∀ ev: ev.recovery == true`.
- Invariants/rows: ADR-0003 Decision 2 — recovery passes re-emit with the recovery marker so event
  consumers can distinguish replay from live traffic.
- Fake needs: emitter capture hook (Dart: a fake emitter recording `(type, recovery)` pairs).

### Pure helper functions

**24. `TestDeriveIterationFromChildren`** (`reconcile_test.go:884-896`) — **must**
- Given children `[w1 closed iter:1, w2 closed iter:2, w3 in_progress iter:3, other closed key
  "unrelated-key"]`; then `deriveIterationFromChildren(children, "root-1") == 2`
  (`reconcile.go:614-623`: count children whose key starts with `converge:root-1:iter:` AND
  status == `closed`).
- Invariants/rows: **invariant 4** (iteration = count of closed child wisps) verbatim.
- Fake needs: none (pure function over `BeadInfo` values).

**25. `TestHighestClosedWisp`** (`reconcile_test.go:898-916`) — **must**
- Given children `[w1 closed iter:1, w3 closed iter:3, w2 closed iter:2, w4 in_progress iter:4]`
  (deliberately unsorted); then `highestClosedWisp(children, "root-1")` returns
  `(best.ID == "w3", iter == 3, found == true)` — highest **closed** iteration wins; the open
  iter:4 wisp is ignored (`reconcile.go:627-652`).
- Invariants/rows: invariant 4; marker-repair source of truth for tests 9, 11, 18.
- Fake needs: none.

**26. `TestHighestClosedWisp_NoneFound`** (`reconcile_test.go:918-927`) — **must**
- Given only `[w1 in_progress iter:1]`; then `found == false`.
- Fake needs: none.

**27. `TestReconcile_EmptyList_NoOp`** (`reconcile_test.go:929-945`) — **must**
- Given a `null`/empty bead-ID list; then `Scanned == 0`, `Recovered == 0`, `Details` empty,
  no error.
- Fake needs: none.

---

## 5. Count summary

| Priority | Count | Tests |
|---|---|---|
| **must** | 27 | all of the above |
| **should** | 0 | — |
| **skip** | 0 | — |
| **Total** | **27** | 27 test functions, 0 table-driven sub-cases |

Rationale: every test in `reconcile_test.go` runs against the in-memory `fakeStore`/`fakeEmitter`
with zero gc-runtime coupling (no tmux, no scripts, no filesystem, no Dolt) — this file is exactly
the "pure domain behavior" tier, and ADR-0003 Decision 7 names it explicitly as conformance input.
Test 16 is must with one adaptation: its substring assertion on Go's wrapped error text becomes an
assertion on the Dart fake's injected exception message; the branch behavior it pins (NotFound vs
transient error) is load-bearing.

---

## 6. Coverage gaps — behaviors with NO test here that the Dart suite should add

- **G1 — Path 3 Sub-path C (orphaned `waiting_manual`)** (`reconcile.go:349-371`): state
  `waiting_manual` with **neither** `waiting_reason` nor `terminal_reason`. With closed wisps
  present → writes `waiting_reason`=`manual`, returns `repaired_state`; with none → `no_action`.
  Untested in either direction.
- **G2 — unknown state value** (`reconcile.go:101-106`): e.g. `convergence.state`=`bogus` →
  `no_action` + error `unknown convergence state "bogus"`. Untested.
- **G3 — Path 1a adopt of an already-closed iter-1 wisp** (`reconcile.go:140-168`): sets
  `iteration`=`"1"` (not `"0"`), then **replays `HandleWispClosed`** so the loop doesn't stall in
  `active` with a dead wisp. Only the open-wisp adopt (iteration `"0"`, no replay) is tested.
- **G4 — active wisp with unexpected status** (`reconcile.go:466-470`): status outside
  {`open`,`in_progress`,`closed`} → `no_action` + error `active wisp %q has unexpected status %q`.
  Untested.
- **G5 — write-order assertions via `WriteLog`**: the fake records every `SetMetadata` key
  (`handler_test.go:39`, `:109`) but no reconcile test asserts ordering. The Dart suite should pin
  the ⚠-ordering contracts directly: Path 1a `active_wisp`→`iteration`→`state`;
  Path 1b `terminal_reason`→`terminal_actor`→`state`→close;
  `completeTerminalTransition` …→close→`last_processed_wisp` LAST (invariant 2).
- **G6 — `pending_next_wisp` adoption in Path 4** (`reconcile.go:492` + `handler.go:935-945`):
  empty `active_wisp` with a valid `pending_next_wisp` should adopt it without a key lookup;
  invalid pending (wrong parent / wrong key / closed / missing) should be cleared to `""` and
  fall through. Both untested at the reconciler level.
- **G7 — empty `terminal_reason` default** (`reconcile.go:266-268`): terminated-not-closed with no
  reason → payload `terminal_reason`=`no_convergence` (metadata NOT backfilled — payload-only
  default). Untested.
- **G8 — `ActivateWisp` is called** when Path 4 pours/adopts (`reconcile.go:523`): the fake records
  `ActivatedWispIDs` but no test asserts it; also untested is the error path when activation fails.
- **G9 — recovery event ID formats**: `converge:{bead}:terminated` and
  `converge:{bead}:iter:{N}:waiting_manual` are never asserted in this file (only event *types*).
  The Dart suite should pin them — stable IDs are the consumer-side dedup key for re-emitted
  recovery events (TierRecoverable/TierCritical, `events.go:22-35`).
- **G10 — `cumulativeDuration` value** (`reconcile.go:666-680`): sums `closedAt − createdAt` over
  closed prefixed children, returns 0 on store error, skips zero timestamps. Never asserted
  numerically (the fake's fixed −10min/now timestamps make ≈600000 ms per closed wisp easy to pin).
- **G11 — `WaitingManualPayload` field fidelity in genuine-hold re-emit** (`reconcile.go:318-324`):
  only `rig` is asserted; `iteration`, `wisp_id` (sourced from `last_processed_wisp`!), `gate_mode`,
  `reason` deserve assertions.
- **G12 — mid-transition `SetMetadata`/`CloseBead` failures**: every recovery path returns the
  attempted action + wrapped error on write failure (e.g. `reconcile.go:211-234`); none are tested.
  At minimum pin: failure between `state`=`terminated` and `CloseBead` leaves a re-runnable Path 2
  bead (the idempotence that makes recovery itself crash-safe).
- **G13 — `ParseIterationFromKey` edge cases**: non-numeric suffix, negative `N`, bead IDs that
  themselves contain `:iter:` (last-index semantics, `handler.go:29`). Only well-formed keys appear
  in this file.
- **G14 — `Recovered` accounting for `repaired_state` / `adopted_wisp`**: test 22 only proves
  `completed_terminal` counts; the `else if action != "no_action"` rule (`reconcile.go:53-55`)
  should be pinned for the other action values, and for the errored-with-recovery-action-label case
  (Errors++, not Recovered++).

---

## 7. Porting traps (most likely to be transcribed wrongly)

1. **`iteration` ≠ current wisp number.** `convergence.iteration` stores the count of **closed**
   wisps. Pouring wisp 1 sets `iteration`=`"0"` (`reconcile.go:192`); adopting an open iter-1 wisp
   sets `"0"`, a closed one `"1"` (`reconcile.go:142-146`). Writing `"1"` after the first pour is
   the classic transcription bug.
2. **State/commit writes go LAST.** Path 1a writes `state`=`active` after `active_wisp` and
   `iteration`; `completeTerminalTransition` writes `last_processed_wisp` after `CloseBead`
   (errors deliberately ignored, `reconcile.go:595`). Reordering silently breaks invariant 2 and
   test 21's "lpw set ⇒ commit done" reasoning.
3. **`convergence.terminated` is emitted BEFORE the close** (`reconcile.go:285-288`,
   `:570-583`) — at-least-once. Emitting after the close flips the crash-window semantics.
4. **`Action` on errored details is the attempted action**, not `"error"` or `"no_action"` —
   except read failures (`GetMetadata`/`GetBead` guards) which report `"no_action"` + error.
   `Recovered` counts only `Error == nil && Action != "no_action"`.
5. **NotFound is a typed sentinel, not a generic failure.** `reconcileActive` runs the
   stale-wisp recovery chain only for NotFound (`errors.Is(err, beads.ErrNotFound)`,
   `reconcile.go:403`); any other `GetBead` error aborts with `no_action` + error. The Dart
   store contract needs a distinguishable not-found exception type.
6. **`IdempotencyKeyPrefix` ends with a colon** (`converge:{bead}:iter:`). Dropping it makes
   `root-1`'s prefix match wisps of a hypothetical `root-10`. `ParseIterationFromKey` uses the
   **last** `:iter:` occurrence and accepts `N == 0` but rejects negatives.
7. **Replay is a full `HandleWispClosed`, not a passive repair.** Tests 12 and 14 cause speculative
   pours, burns (subtree delete + `pending_next_wisp`=`""`), events, and terminal transitions from
   inside the "reconcile" pass. The cached-outcome guard is `gate_outcome_wisp == wispID`
   (exact wisp match, `handler.go:233-234`) — a cached outcome for a *different* wisp must not
   suppress evaluation.
8. **The genuine-hold path re-emits `convergence.waiting_manual` on every pass** with
   `recovery=true` and a stable event ID; dedup is downstream. Suppressing the re-emit "because
   nothing changed" breaks the lost-event recovery contract (`reconcile.go:311-325`).
9. **`Children()` of an unknown parent returns empty without error** (fake:
   `handler_test.go:156-158`); recovery treats "no children" and "parent unknown to child index"
   identically. A Dart fake that throws here fails multiple paths.
10. **`meta` is a one-shot snapshot.** `reconcileBead` reads metadata once and threads the map into
    helpers; `completeTerminalTransition` decides "write state?" from the **snapshot**
    (`reconcile.go:573`), and `withEventRig` does its own fresh `GetMetadata` for `rig`
    (`handler.go:886-895`). Re-reading (or not) in the wrong place changes observable writes.
11. **Pour fakes must be idempotent on key** (`handler_test.go:187-192`): returning the existing
    wisp ID for a duplicate key is invariant 3's contract; a Dart fake that always mints new IDs
    masks double-pour bugs the suite exists to catch.
12. **`terminal_actor` backfill is `"recovery"`** — metadata write only when missing
    (`reconcile.go:604-609`); the payload independently falls back to `"recovery"`
    (`reconcile.go:271-273`). `terminal_reason` empty defaults to `no_convergence` in the
    **payload only**, never written back.
13. **Close reason is a fixed ≥20-char literal**: `convergence reconcile: terminated-state bead
    closed`. bd's on-close validator rejects shorter reasons (`handler.go:41-45`) — do not
    "tidy" the string.
14. **`DecodeInt("")` → 0/absent**, and that 0 leaks into `waiting_manual` event IDs
    (`converge:{bead}:iter:0:waiting_manual`) when `convergence.iteration` is unset — reproduce,
    don't "fix", until upstream changes (per ADR-0003: semantics change only via upstream RFC).
15. **`ReconcileBeads` never throws** — top-level result is always a report; per-bead failures
    are data. A Dart port that rethrows store exceptions breaks test 22's continue-on-error scan.
