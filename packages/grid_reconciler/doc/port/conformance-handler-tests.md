# Conformance spec — `handler_test.go` → Dart (Track H)

**Source of truth:** `gascity/internal/convergence/handler_test.go` (1533 lines, pinned on disk at
`/Users/nico/development/com.gastownhall/gascity/internal/convergence/handler_test.go`).
**Behavior under test:** `handler.go` (986 lines, same dir) plus `metadata.go`, `events.go`,
`gate.go`, `hybrid.go`, `reconcile.go`, `manual.go`, `trigger.go`, `template.go`.
**Mandate:** ADR-0003 Decision 7 — gc's tests are the executable spec; this file is the
transliteration checklist for the Dart suite in `grid_reconciler`. ADR-0003 Decision 2 defines
the invariants (1–7) and the transition table referenced below.

This spec is self-contained: every identifier, literal, and ordering contract a Dart implementer
needs is reproduced here with `file:line` provenance. Line numbers refer to the pinned sources
above (assessed 2026-06-12 against gascity HEAD, bd 1.0.5 pin per CLAUDE.md).

Priorities: **must** = pure domain behavior, port verbatim · **should** = valuable but
runtime-coupled · **skip** = gc-runtime-specific (reason given).

---

## 1. Value domains (exact literals)

All metadata lives under the `convergence.*` namespace on the **root** convergence bead.

### 1.1 Metadata keys (`metadata.go:12–44`)

| Go constant | Literal key | Used by handler tests |
|---|---|---|
| `FieldState` | `convergence.state` | yes |
| `FieldIteration` | `convergence.iteration` | yes |
| `FieldMaxIterations` | `convergence.max_iterations` | yes |
| `FieldFormula` | `convergence.formula` | yes |
| `FieldTarget` | `convergence.target` | yes (concurrency checks) |
| `FieldGateMode` | `convergence.gate_mode` | yes |
| `FieldGateCondition` | `convergence.gate_condition` | yes |
| `FieldGateTimeout` | `convergence.gate_timeout` | yes (`"60s"` Go duration string) |
| `FieldGateTimeoutAction` | `convergence.gate_timeout_action` | yes |
| `FieldActiveWisp` | `convergence.active_wisp` | yes |
| `FieldLastProcessedWisp` | `convergence.last_processed_wisp` | yes — THE dedup/commit marker |
| `FieldAgentVerdict` | `convergence.agent_verdict` | yes |
| `FieldAgentVerdictWisp` | `convergence.agent_verdict_wisp` | yes |
| `FieldGateOutcome` | `convergence.gate_outcome` | yes |
| `FieldGateExitCode` | `convergence.gate_exit_code` | yes |
| `FieldGateOutcomeWisp` | `convergence.gate_outcome_wisp` | yes — gate replay marker |
| `FieldGateRetryCount` | `convergence.gate_retry_count` | yes |
| `FieldTerminalReason` | `convergence.terminal_reason` | yes |
| `FieldTerminalActor` | `convergence.terminal_actor` | yes |
| `FieldWaitingReason` | `convergence.waiting_reason` | yes |
| `FieldRetrySource` | `convergence.retry_source` | only via commit-key filter |
| `FieldCityPath` | `convergence.city_path` | gate env only |
| `FieldRig` | `convergence.rig` | yes (event rig stamping) |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` | pour args |
| `FieldGateStdout` | `convergence.gate_stdout` | replay persistence |
| `FieldGateStderr` | `convergence.gate_stderr` | replay persistence |
| `FieldGateDurationMs` | `convergence.gate_duration_ms` | replay persistence |
| `FieldGateTruncated` | `convergence.gate_truncated` | replay persistence (`"true"` or `""`) |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` | yes — speculative-pour marker |
| `FieldTrigger` | `convergence.trigger` | parsed, not exercised here |
| `FieldTriggerCondition` | `convergence.trigger_condition` | parsed, not exercised here |
| `VarPrefix` | `var.` (prefix) | `ExtractVars` strips it (`template.go:43–51`) |

### 1.2 States (`metadata.go:50–56`)

| Constant | Literal |
|---|---|
| `StateCreating` | `creating` |
| `StateActive` | `active` |
| `StateWaitingManual` | `waiting_manual` |
| `StateWaitingTrigger` | `waiting_trigger` |
| `StateTerminated` | `terminated` |

### 1.3 Gate modes / timeout actions / outcomes / reasons (`metadata.go:65–102`)

| Domain | Constants → literals |
|---|---|
| Gate mode | `GateModeManual`=`manual` · `GateModeCondition`=`condition` · `GateModeHybrid`=`hybrid` |
| Timeout action | `TimeoutActionIterate`=`iterate` · `TimeoutActionRetry`=`retry` · `TimeoutActionManual`=`manual` · `TimeoutActionTerminate`=`terminate` |
| Gate outcome | `GatePass`=`pass` · `GateFail`=`fail` · `GateTimeout`=`timeout` · `GateError`=`error` |
| Terminal reason | `TerminalApproved`=`approved` · `TerminalNoConvergence`=`no_convergence` · `TerminalStopped`=`stopped` · `TerminalPartialCreation`=`partial_creation` |
| Waiting reason | `WaitManual`=`manual` · `WaitHybridNoCondition`=`hybrid_no_condition` · `WaitTimeout`=`timeout` · `WaitSlingFailure`=`sling_failure` |
| Verdict (normalized) | `VerdictApprove`=`approve` · `VerdictApproveWithRisks`=`approve-with-risks` · `VerdictBlock`=`block`; unknown/empty → `block`; past-tense map `metadata.go:113–119` |
| Trigger mode | `TriggerNone`=`""` · `TriggerEvent`=`event` |

Gate defaults (`gate.go:8–14, 44–85`): missing `gate_mode` → `manual`; missing/empty
`gate_timeout` → `DefaultGateTimeout` = 5 minutes; missing `gate_timeout_action` → `iterate`;
invalid mode/timeout/action → parse **error**. `MaxGateRetries` = 3.

### 1.4 Handler actions (`handler.go:120–128`)

`ActionIterate`=`iterate` · `ActionApproved`=`approved` · `ActionNoConvergence`=`no_convergence`
· `ActionWaitingManual`=`waiting_manual` · `ActionWaitingTrigger`=`waiting_trigger` ·
`ActionStopped`=`stopped` · `ActionSkipped`=`skipped`.

`HandlerResult` (`handler.go:131–137`): `Action`, `Iteration` (int, from the closed wisp's key),
`GateOutcome` (string), `NextWispID` (set only for `iterate`), `WaitingReason` (set only for
`waiting_manual`).

### 1.5 Idempotency keys (`handler.go:11–39`)

- Prefix: `converge:<beadID>:iter:` (`IdempotencyKeyPrefix`, `handler.go:13–15`).
- Key: `converge:<beadID>:iter:<N>`, N is **1-based** (`IdempotencyKey`, `handler.go:19–21`).
- `ParseIterationFromKey` (`handler.go:26–39`): finds **last** occurrence of `:iter:`, parses the
  suffix as int; rejects negatives; returns `(0, false)` on no marker / empty / non-numeric.
  `:iter:0` parses to `(0, true)` — zero is a *valid parse* even though real keys start at 1.

### 1.6 Event types & IDs (`events.go:11–81`)

| Event constant | `event_type` literal | Event-ID formula (exact) |
|---|---|---|
| `EventCreated` | `convergence.created` | `converge:<beadID>:created` |
| `EventIteration` | `convergence.iteration` | `converge:<beadID>:iter:<N>:iteration` |
| `EventWaitingManual` | `convergence.waiting_manual` | `converge:<beadID>:iter:<N>:waiting_manual` |
| `EventTerminated` | `convergence.terminated` | `converge:<beadID>:terminated` |
| `EventManualApprove` | `convergence.manual_approve` | `converge:<beadID>:manual_approve` |
| `EventManualIterate` | `convergence.manual_iterate` | `converge:<beadID>:iter:<N>:manual_iterate` (N = NEW wisp's iteration) |
| `EventManualStop` | `convergence.manual_stop` | `converge:<beadID>:manual_stop` |
| `EventTriggerAdvance` | `convergence.trigger_advance` | `converge:<beadID>:iter:<N>:trigger_advance` (N = NEW wisp; deliberately distinct from the iteration ID — `events.go:74–81`) |

Payload JSON shapes (`events.go:84–158`) — field names the Dart codecs must emit:

- `IterationPayload`: `rig` (omit-empty), `iteration`, `wisp_id`, `agent_verdict`, `gate_mode`,
  `gate_outcome` (nullable), `gate_result` (nullable object), `gate_retry_count`, `action`
  (one of `iterate|approved|no_convergence|waiting_manual|waiting_trigger|stopped`),
  `waiting_reason` (nullable, only waiting_manual), `next_wisp_id` (nullable, only iterate),
  `iteration_duration_ms`, `cumulative_duration_ms`, `iteration_tokens` (nullable),
  `cumulative_tokens` (nullable).
- `TerminatedPayload`: `rig` (omit-empty), `terminal_reason`, `total_iterations`,
  `final_status` (always `"closed"`), `actor` (`controller` or `operator:<username>` or
  `recovery`), `cumulative_duration_ms`.
- `WaitingManualPayload`: `rig`, `iteration`, `wisp_id`, `agent_verdict`, `gate_mode`,
  `gate_outcome` (nullable), `gate_result` (nullable), `reason`
  (`manual|hybrid_no_condition|timeout|sling_failure`), `iteration_duration_ms`,
  `cumulative_duration_ms`.
- `GateResultPayload`: `exit_code` (nullable), `stdout`, `stderr`, `duration_ms`, `truncated`.
- `CreatedPayload` / `ManualActionPayload`: see `events.go:84–93, 150–158` (rig-stamped too).

Null-vs-empty: `NullableString` (`events.go:186–191`) — `""` → JSON `null`, otherwise the
string. `GateResultToPayload` (`events.go:195–206`) returns `null` when `Outcome == ""`
(pure-manual path), otherwise the full object with `duration_ms = Duration.Milliseconds()`.

### 1.7 Close reasons (`handler.go:47–55`)

bd's `validation.on-close=error` rejects `close_reason` < 20 chars; every close uses a canonical
constant. The ones handler tests can observe:

| Constant | Literal |
|---|---|
| `CloseReasonHandlerCleanup` | `convergence: terminated state observed; closing root` |
| `CloseReasonHandlerRoot` | `convergence: workflow handler closing root after terminate` |
| `CloseReasonReconcileDone` | `convergence reconcile: terminated-state bead closed` |

(The other five — create/retry rollback, manual approve/supersede/stop — belong to
`create_test.go` / `manual_test.go` scope.)

### 1.8 Error message literals asserted by substring

| Site | Literal (format expanded) |
|---|---|
| `CheckNestedConvergence` (`handler.go:962–964`) | `cannot create convergence loop targeting "<agent>": agent is currently executing a convergence wisp. Self-targeting convergence would deadlock` — tests match substring **`deadlock`** |
| `CheckConcurrencyLimits` (`handler.go:982–983`) | `cannot create convergence loop targeting "<agent>": per-agent limit reached (<n>/<max> active loops)` — tests match substring **`per-agent limit`** |
| Missing condition (`handler.go:241`) | `gate mode is "condition" but no condition path configured` |

---

## 2. The 9-step algorithm and its write-ordering contracts

`HandleWispClosed(ctx, rootBeadID, wispID)` (`handler.go:161–390`). Order of operations the
tests pin down:

1. **Guard** (`handler.go:170–175`): `state == terminated` → best-effort
   `CloseBead(root, CloseReasonHandlerCleanup)`, return `ActionSkipped`. Invariant 6.
2. **Dedup, monotonic** (`handler.go:177–201`): parse iteration from the closed wisp's OWN
   idempotency key; read `last_processed_wisp`, `GetBead` it, parse ITS key; missing/corrupt →
   treat as iteration 0 (graceful degradation, `handler.go:188–198`); skip iff
   `wispIteration <= lastProcessedIteration`. Invariant 1.
3. **Derive iteration** (`handler.go:203–214`): count closed children whose key starts with
   `converge:<root>:iter:`; if it disagrees with stored `convergence.iteration`, write the
   derived value (repair). Invariant 4.
   **3 validation** (`handler.go:222–241`): `ParseGateConfig` / `ParseTriggerConfig` errors abort
   BEFORE any speculative pour; condition mode + empty condition + *not replaying* → error (and
   any *valid* pending wisp is burned first, an invalid one is only un-marked).
   **Step 3b — speculative pour** (`handler.go:244–275`): if `wispIteration < maxIterations` and
   the gate is not manual-without-condition and no trigger is enabled and there is no valid
   `pending_next_wisp` already: `PourSpeculativeWisp(root, formula, converge:<root>:iter:<N+1>,
   vars, evaluatePrompt)`; on success write `convergence.pending_next_wisp = <id>`; on pour error
   try `FindByIdempotencyKey(nextKey)` — found → adopt; else stash `speculativePourErr` (do NOT
   fail yet). Invariants 3, 5.
4. **Gate evaluation, idempotent** (`handler.go:277–328`): if
   `convergence.gate_outcome_wisp == wispID` → **replay** from persisted metadata
   (outcome/exit_code/retry_count/stdout/stderr/duration_ms/truncated) and skip evaluation
   entirely. Otherwise: manual mode → burn speculative wisp, go waiting_manual(`manual`);
   hybrid with empty condition → burn, waiting_manual(`hybrid_no_condition`); else read the
   verdict (only if `agent_verdict_wisp == wispID`, else treat as `block`) and run the gate.
   Invariant 2 (second clause).
5. **Persist gate outcome** (`handler.go:330–338`, `persistGateOutcome` 776–808): writes, in
   order: `gate_outcome`, `gate_exit_code`, `gate_retry_count`, `gate_stdout`, `gate_stderr`,
   `gate_duration_ms`, `gate_truncated`, then **`gate_outcome_wisp` LAST** (replay marker).
   Skipped on replay.
6. Iteration note — informational, never blocks (`handler.go:340–341`). Not asserted.
7. **Outcome** (`handler.go:343–389`), in **this evaluation order**:
   a. `outcome == timeout && timeoutAction == manual` → burn → waiting_manual(`timeout`).
      ⚠ ordering: this check precedes the max-iterations terminal check.
   b. terminal? `pass` → `approved`; `timeout && action == terminate` → `no_convergence`;
      `wispIteration >= maxIterations` (non-pass) → `no_convergence`.
   c. non-terminal: `speculativePourErr != nil` → `handleSlingFailure` →
      waiting_manual(`sling_failure`); trigger enabled → waiting_trigger; else **iterate**.
   d. terminal: burn speculative wisp, then `terminate(..., actor="controller")`.
8. **Emit events BEFORE commit** (at-least-once / TierCritical). See per-path ordering below.
9. **Commit point — metadata writes.** Per-path write order (⚠ all load-bearing):

| Path | Write order (`SetMetadata` keys on root) |
|---|---|
| iterate (`handler.go:555–565`) | [verdict clears if scoped] → *(ActivateWisp — a call, not a write)* → `convergence.active_wisp`=nextWisp → **`convergence.last_processed_wisp`=wisp (dedup marker)** → `convergence.pending_next_wisp`=`""` (best-effort cleanup AFTER the marker) |
| waiting_manual (`handler.go:438–453`) | `active_wisp`=`""` → `waiting_reason`=reason → `state`=`waiting_manual` → **`last_processed_wisp` LAST**; then emit `convergence.waiting_manual` event (post-commit) |
| waiting_trigger (`handler.go:619–628`) | `active_wisp`=`""` → `state`=`waiting_trigger` → **`last_processed_wisp` LAST** |
| terminate (`handler.go:687–704`) | `terminal_reason` → `terminal_actor` → `state`=`terminated` → `CloseBead(root, CloseReasonHandlerRoot)` → **`last_processed_wisp` LAST** |

⚠ ordering: `last_processed_wisp` IS the commit point in every path (invariant 2). A crash
before it ⇒ recovery re-processes the wisp; the replay marker (`gate_outcome_wisp`) and
idempotency keys make that re-processing safe.

⚠ ordering: `convergence.iteration` event (`EventIteration`) is emitted BEFORE the step-9
writes in every path; `EventWaitingManual` is emitted AFTER the waiting_manual commit;
`EventTerminated` is emitted BEFORE the terminate commit (`handler.go:675–685`).

---

## 3. Fake contracts the Dart suite must reproduce

### 3.1 Fake store (`handler_test.go:18–267`)

A Dart `FakeConvergenceStore` must implement the `Store` port (`handler.go:69–114`) with:

- **Record** per bead: `BeadInfo{ID, Status, ParentID, IdempotencyKey, CreatedAt, ClosedAt}` +
  `metadata: Map<String,String>` + ordered `children: List<String>`.
- `addBead(id, status, parentID, idempotencyKey, meta)` (`:48–71`): sets
  `CreatedAt = now − 10 minutes` and `ClosedAt = now` **unconditionally** (even for open beads —
  duration math depends on both being non-zero); registers as child of parent **only if the
  parent was added first** (insertion order matters).
- `GetBead` (`:73–84`): missing → error wrapping `beads.ErrNotFound` (Dart: a typed
  `NotFoundException` the reconciler can distinguish from transient failures —
  `handler.go:71–73` requires it). Overridable via `GetBeadFunc` hook.
- `GetMetadata` (`:86–99`): returns a **copy** (handler snapshot semantics — later writes must
  not mutate the snapshot the handler read at entry).
- `SetMetadata` (`:101–111`): appends **the key only** to an ordered `WriteLog` —
  the write-ordering oracle. Log is global across beads.
- `CloseBead` (`:113–129`): sets status `closed`, refreshes `ClosedAt`, stores reason under
  metadata key `close_reason` **directly** (NOT via `SetMetadata` — must NOT enter `WriteLog`).
- `DeleteBead` (`:131–151`): removes the bead and unlinks it from its parent's children.
- `Children` (`:153–167`): children's `BeadInfo` in insertion order; unknown parent → empty.
- `PourWisp` / `PourSpeculativeWisp` (`:169–211`): both share `pourWisp` — **idempotent**: if any
  bead already has the key, return its ID; else mint `wisp-<n>` (auto-increment counter),
  status `in_progress`, `CreatedAt = now`, parent-linked. Overridable via `PourWispFunc` /
  `PourSpeculativeWispFunc` hooks (used to simulate sling failures).
- `FindByIdempotencyKey` (`:213–225`): linear scan; overridable via hook (used to assert it is
  NOT called — H40).
- `ActivateWisp` (`:227–238`): missing → not-found error; records ID into ordered
  `ActivatedWispIDs`; overridable hook.
- `CountActiveConvergenceLoops(agent)` (`:240–251`): counts beads where
  `metadata["convergence.target"] == agent && metadata["convergence.state"] == "active"`.
- `CreateConvergenceBead` (`:253–267`): mints `conv-<n>` (same counter), status `in_progress`.

### 3.2 Fake emitter (`handler_test.go:269–305`)

Records `{Type, EventID, BeadID, Payload(raw JSON), Recovery(bool)}` in order; helper
`findEvent(type)` returns the first event of a type.

### 3.3 Baseline fixture `setupBasicHandler` (`handler_test.go:347–378`)

Root bead `root-1` (status `in_progress`, no parent, no key) with metadata — overridden per test
by merging the test's map on top:

| Key | Value |
|---|---|
| `convergence.state` | `active` |
| `convergence.iteration` | `1` |
| `convergence.max_iterations` | `5` |
| `convergence.formula` | `test-formula` |
| `convergence.target` | `test-agent` |
| `convergence.gate_mode` | `condition` |
| `convergence.gate_timeout` | `60s` |
| `convergence.gate_timeout_action` | `iterate` |

Plus a closed wisp `wisp-iter-1` (status `closed`, parent `root-1`, idempotency key
`converge:root-1:iter:1`, empty metadata). Handler wired with the fake store, fake emitter, and
`Clock: time.Now` (a few tests construct the handler without Clock — `clock()` must default to
now, `handler.go:898–903`).

### 3.4 `extractCommitKeys` (`handler_test.go:1159–1180`)

Filters `WriteLog` to the 9 step-9/commit keys: `convergence.state`,
`convergence.terminal_reason`, `convergence.terminal_actor`, `convergence.last_processed_wisp`,
`convergence.active_wisp`, `convergence.waiting_reason`, `convergence.iteration`,
`convergence.retry_source`, `convergence.pending_next_wisp`. NOTE: `gate_outcome_wisp` and the
other gate-persistence keys are deliberately filtered OUT.

---

## 4. Test inventory

Conventions: **Row Tn** = ADR-0003 D2 transition-table row, numbered top-to-bottom
(T1 pass→approved, T2 fail∧iter<max→iterate, T3 timeout∧manual, T4 timeout∧terminate,
T5 iter≥max, T6 trigger→waitingTrigger, T7 gate_mode=manual→waitingManual, T8 operator approve,
T9 operator iterate, T10 trigger passes, T11 operator stop, T12 creating cleanup). **Inv n** =
ADR-0003 D2 invariant. "baseline" = §3.3 fixture; "+{...}" = metadata merged on top.
"replay fail/pass/timeout" = `gate_outcome_wisp=wisp-iter-1` + `gate_outcome=<x>` (gate is never
executed; ParseGateConfig's missing-condition check is bypassed on replay).

### H01 `TestWithEventRigPopulatesEveryRigPayload` — `handler_test.go:307` · 5 sub-cases

- **Scenario:** Given root `root-1` with `convergence.rig=prod`; when `withEventRig` wraps each
  payload type; then the JSON-roundtripped payload carries `rig`.
- **Sub-cases (table):** `created`→`CreatedPayload{}` · `iteration`→`IterationPayload{}` ·
  `terminated`→`TerminatedPayload{}` · `waiting manual`→`WaitingManualPayload{}` ·
  `manual action`→`ManualActionPayload{}`.
- **Assertions:** for every payload type: `json["rig"] == "prod"`.
- **Invariants/rows:** event contract (D2 events); no transition row.
- **Fixture:** store with one bead `root-1` + `convergence.rig=prod`; handler with Store only
  (no emitter needed). Behavior under test: `handler.go:860–895` (type switch over all 5 payload
  types; empty rig → payload unchanged).
- **Priority:** must — Dart payload union must stamp `rig` on every variant.

### H02 `TestParseIterationFromKey` — `handler_test.go:382` · 7 table rows

- **Scenario:** pure parse of `converge:<id>:iter:<N>` keys.
- **Rows (key → want iter, want ok):** `converge:root-1:iter:1`→(1,true) ·
  `converge:root-1:iter:5`→(5,true) · `converge:root-1:iter:0`→(0,**true**) ·
  `converge:root-1:iter:abc`→(0,false) · `converge:root-1:iter:`→(0,false) ·
  `no-iter-marker`→(0,false) · `""`→(0,false).
- **Invariants/rows:** Inv 3 (key shape).
- **Fixture:** none (pure function).
- **Priority:** must.

### H03 `TestIdempotencyKey` — `handler_test.go:409`

- **Scenario:** key formula + round trip.
- **Assertions:** `IdempotencyKey("bead-42", 3) == "converge:bead-42:iter:3"`;
  `ParseIterationFromKey` of it → (3, true).
- **Invariants/rows:** Inv 3.
- **Fixture:** none.
- **Priority:** must.

### H04 `TestHandleWispClosed_GuardCheck_Terminated` — `handler_test.go:422`

- **Scenario:** Given root state `terminated`; when its closed wisp is processed; then skipped.
- **Assertions:** no error; `result.Action == "skipped"`.
- **Invariants/rows:** Inv 6 (terminal irreversibility).
- **Fixture:** baseline + `{convergence.state: terminated}`.
- **Priority:** must. Note: gc also best-effort-closes the root with
  `convergence: terminated state observed; closing root` (`handler.go:173`) — unasserted here
  (see coverage gaps).

### H05 `TestHandleWispClosed_DedupCheck_AlreadyProcessed` — `handler_test.go:436`

- **Scenario:** Given `last_processed_wisp=wisp-iter-1`; when `wisp-iter-1` closes again; skip.
- **Assertions:** no error; `result.Action == "skipped"`.
- **Invariants/rows:** Inv 1 (monotonic dedup; equality is "already processed").
- **Fixture:** baseline + `{convergence.last_processed_wisp: wisp-iter-1}`.
- **Priority:** must.

### H06 `TestHandleWispClosed_CorruptedLastProcessedWisp_GracefulDegradation` — `handler_test.go:454`

- **Scenario:** Given `last_processed_wisp=deleted-wisp` (no such bead) and `gate_mode=manual`;
  when `wisp-iter-1` closes; then it is processed, not skipped.
- **Assertions:** no error; `result.Action != "skipped"` (manual mode ⇒ it will actually be
  `waiting_manual`).
- **Invariants/rows:** Inv 1 — missing/corrupt marker degrades to iteration 0
  (`handler.go:188–198`); loop must never permanently block.
- **Fixture:** baseline + `{last_processed_wisp: deleted-wisp, gate_mode: manual}`.
- **Priority:** must.

### H07 `TestHandleWispClosed_ManualGate_WaitingManual` — `handler_test.go:476`

- **Scenario:** Given `gate_mode=manual`; wisp closes; loop holds for the operator.
- **Assertions:** `Action == "waiting_manual"`; `WaitingReason == "manual"`; metadata
  `convergence.state == "waiting_manual"` and `convergence.waiting_reason == "manual"`; an
  event of type `convergence.iteration` AND one of type `convergence.waiting_manual` emitted.
- **Invariants/rows:** Row T7.
- **Fixture:** baseline + `{gate_mode: manual}`.
- **Priority:** must.

### H08 `TestHandleWispClosed_HybridNoCondition_WaitingManual` — `handler_test.go:511`

- **Scenario:** `gate_mode=hybrid` with empty `gate_condition` falls back to manual hold
  (`HybridNeedsManual`, `hybrid.go:26–28`).
- **Assertions:** `Action == "waiting_manual"`; `WaitingReason == "hybrid_no_condition"`.
- **Invariants/rows:** Row T7 (hybrid fallback variant); D3 hybrid contract.
- **Fixture:** baseline + `{gate_mode: hybrid, gate_condition: ""}`.
- **Priority:** must.

### H09 `TestHandleWispClosed_GateReplay_SkipsReEvaluation` — `handler_test.go:530`

- **Scenario:** Given a persisted gate outcome scoped to this wisp
  (`gate_outcome_wisp=wisp-iter-1`, `gate_outcome=fail`, `gate_retry_count=0`); when the wisp
  closes (again); then the cached outcome drives the transition — no re-evaluation, despite the
  condition path being absent.
- **Assertions:** `Action == "iterate"`; `result.GateOutcome == "fail"`.
- **Invariants/rows:** Inv 2 (replay marker), Row T2. ⚠ replay bypasses the
  missing-condition validation (`handler.go:234–241` — `skipGateEval` short-circuits it).
- **Fixture:** baseline + `{gate_outcome_wisp: wisp-iter-1, gate_outcome: fail,
  gate_retry_count: "0"}`.
- **Priority:** must.

### H10 `TestHandleWispClosed_GatePassApproved` — `handler_test.go:551`

- **Scenario:** Replay pass → terminal approval.
- **Assertions:** `Action == "approved"`; metadata `state == "terminated"`,
  `terminal_reason == "approved"`, `terminal_actor == "controller"`; root bead status
  `"closed"`; events `convergence.iteration` AND `convergence.terminated` both emitted.
- **Invariants/rows:** Row T1; Inv 6.
- **Fixture:** baseline + replay pass.
- **Priority:** must.

### H11 `TestHandleWispClosed_GateFailIterate` — `handler_test.go:593`

- **Scenario:** Replay fail, iteration 1 < max 5 → pour/adopt next wisp and continue.
- **Assertions:** `Action == "iterate"`; `NextWispID != ""`; metadata
  `convergence.active_wisp == result.NextWispID`; `convergence.iteration` event payload has
  `next_wisp_id == result.NextWispID` (non-null) and `action == "iterate"`.
- **Invariants/rows:** Row T2; Inv 3, 5.
- **Fixture:** baseline + replay fail.
- **Priority:** must.

### H12 `TestHandleWispClosed_MaxIterationsReached_NoConvergence` — `handler_test.go:634`

- **Scenario:** `max_iterations=1`, replay fail at iteration 1 → budget exhausted.
- **Assertions:** `Action == "no_convergence"`; metadata
  `terminal_reason == "no_convergence"`; a `convergence.terminated` event emitted.
- **Invariants/rows:** Row T5 (`iter >= max ∧ gate ≠ pass`; note `>=`).
- **Fixture:** baseline + `{max_iterations: "1"}` + replay fail.
- **Priority:** must.

### H13 `TestHandleWispClosed_TimeoutTerminate` — `handler_test.go:660`

- **Scenario:** Replay `timeout` with `gate_timeout_action=terminate`.
- **Assertions:** `Action == "no_convergence"`; `terminal_reason == "no_convergence"`.
- **Invariants/rows:** Row T4.
- **Fixture:** baseline + `{gate_timeout_action: terminate}` + replay timeout.
- **Priority:** must.

### H14 `TestHandleWispClosed_TimeoutManual` — `handler_test.go:682`

- **Scenario:** Replay `timeout` with `gate_timeout_action=manual`.
- **Assertions:** `Action == "waiting_manual"`; `WaitingReason == "timeout"`.
- **Invariants/rows:** Row T3. ⚠ ordering: this check runs BEFORE the terminal switch
  (`handler.go:345–351`) — timeout+manual wins even at max iterations.
- **Fixture:** baseline + `{gate_timeout_action: manual}` + replay timeout.
- **Priority:** must.

### H15 `TestHandleWispClosed_SlingFailure_WaitingManual` — `handler_test.go:702`

- **Scenario:** Replay fail (non-terminal) but `PourSpeculativeWisp` throws
  (`sling failure: connection refused`) and the iter-2 key lookup finds nothing → the loop
  parks for the operator instead of erroring.
- **Assertions:** no error; `Action == "waiting_manual"`; `WaitingReason == "sling_failure"`;
  metadata `convergence.waiting_reason == "sling_failure"`.
- **Invariants/rows:** Inv 5 (pour-failure containment); degraded Row T2 → waitingManual
  (`handleSlingFailure`, `handler.go:713–726`). Not in the D2 table — extra-table behavior.
- **Fixture:** hand-built (baseline-equivalent metadata) + replay fail +
  `PourSpeculativeWispFunc` → error. Handler constructed WITHOUT Clock (default must work).
- **Priority:** must.

### H16 `TestHandleWispClosed_VerdictClearedOnIterate` — `handler_test.go:747`

- **Scenario:** Replay fail with `agent_verdict=block`, `agent_verdict_wisp=wisp-iter-1`
  (scoped to THIS wisp); on iterate the verdict is consumed.
- **Assertions:** `Action == "iterate"`; metadata `convergence.agent_verdict == ""` and
  `convergence.agent_verdict_wisp == ""` afterwards.
- **Invariants/rows:** Row T2; D3 verdict channel (clear only when scoped —
  `handler.go:490–498`).
- **Fixture:** baseline + replay fail + `{agent_verdict: block, agent_verdict_wisp: wisp-iter-1}`.
- **Priority:** must.

### H17 `TestHandleWispClosed_VerdictPreservedForLaterWisp` — `handler_test.go:773`

- **Scenario:** Same as H16 but `agent_verdict_wisp=wisp-iter-2` (a LATER wisp).
- **Assertions:** `Action == "iterate"`; `convergence.agent_verdict == "approve"` preserved.
- **Invariants/rows:** Row T2; verdict-scoping rule.
- **Fixture:** baseline + replay fail + `{agent_verdict: approve, agent_verdict_wisp:
  wisp-iter-2}`.
- **Priority:** must.

### H18 `TestHandleWispClosed_WriteOrdering_TerminalReasonBeforeState` — `handler_test.go:796`

- **Scenario:** Replay pass → terminate; verify the terminal commit sequence.
- **Assertions:** `Action == "approved"`; metadata `terminal_reason == "approved"`,
  `terminal_actor == "controller"`, `state == "terminated"`; in the FULL `WriteLog` the very
  last key is `convergence.last_processed_wisp`; among commit keys (§3.4 filter), index of
  `terminal_reason` < index of `state` AND `terminal_actor` < `state`; at least 4 commit keys.
- **Invariants/rows:** Inv 2; Row T1. ⚠ ordering: `terminal_reason` → `terminal_actor` →
  `state=terminated` → (CloseBead — not a metadata write) → `last_processed_wisp` LAST
  (`handler.go:687–704`). Expected commit-key log for this fixture:
  `[pending_next_wisp(set), pending_next_wisp(clear via burn), terminal_reason, terminal_actor,
  state, last_processed_wisp]`.
- **Fixture:** hand-built baseline-equivalent (no `convergence.target`!) + replay pass; handler
  without Clock.
- **Priority:** must.

### H19 `TestHandleWispClosed_WriteOrdering_IterateLastProcessedBeforePendingCleanup` — `handler_test.go:876`

- **Scenario:** Replay fail (+ `gate_exit_code=1`) → iterate; verify the iterate commit tail.
- **Assertions:** `Action == "iterate"`; in commit keys: second-to-last ==
  `convergence.last_processed_wisp`, last == `convergence.pending_next_wisp` (the best-effort
  post-commit cleanup).
- **Invariants/rows:** Inv 2, 5; Row T2. ⚠ ordering: `active_wisp` → `last_processed_wisp` →
  `pending_next_wisp=""` (`handler.go:555–565`). Cleanup failure must be swallowed
  (`validPendingNextWisp` self-heals next entry).
- **Fixture:** hand-built + replay fail + `{gate_exit_code: "1"}`.
- **Priority:** must.

### H20 `TestHandleWispClosed_WriteOrdering_WaitingManualLastProcessedWispLast` — `handler_test.go:919`

- **Scenario:** `gate_mode=manual`, `gate_timeout_action=manual` → waiting_manual commit tail.
- **Assertions:** `Action == "waiting_manual"`; the very last key in the full `WriteLog` is
  `convergence.last_processed_wisp`.
- **Invariants/rows:** Inv 2; Row T7. ⚠ ordering: `active_wisp=""` → `waiting_reason` →
  `state=waiting_manual` → `last_processed_wisp` LAST (`handler.go:438–453`).
- **Fixture:** hand-built + `{gate_mode: manual, gate_timeout_action: manual}`.
- **Priority:** must.

### H21 `TestHandleWispClosed_EventPayloads` — `handler_test.go:953`

- **Scenario:** Replay pass with a scoped `approve` verdict; verify both event envelopes and
  payloads field-by-field.
- **Assertions:** `convergence.iteration` event: `EventID == "converge:root-1:iter:1:iteration"`;
  payload `iteration == 1`, `wisp_id == "wisp-iter-1"`, `action == "approved"`,
  `agent_verdict == "approve"`. `convergence.terminated` event:
  `EventID == "converge:root-1:terminated"`; payload `terminal_reason == "approved"`,
  `final_status == "closed"`, `actor == "controller"`.
- **Invariants/rows:** Row T1; event contract (D2).
- **Fixture:** baseline + replay pass + `{agent_verdict: approve, agent_verdict_wisp:
  wisp-iter-1}`.
- **Priority:** must.

### H22 `TestCheckNestedConvergence_Blocked` — `handler_test.go:1017`

- **Scenario:** agent-a already runs an active loop targeting agent-a; agent-a tries to create
  another loop targeting itself → self-deadlock refused.
- **Assertions:** error non-nil; message contains `deadlock` (full literal in §1.8).
- **Invariants/rows:** creation guard (no row); supports Inv 7's single-writer discipline.
- **Fixture:** one bead with `{convergence.target: agent-a, convergence.state: active}`;
  `CheckNestedConvergence(store, "agent-a", "agent-a")`. Fake must implement
  `CountActiveConvergenceLoops` per §3.1.
- **Priority:** must.

### H23 `TestCheckNestedConvergence_Allowed_DifferentAgent` — `handler_test.go:1033`

- **Scenario:** agent-b targets agent-a (cross-agent) → always allowed, store not even
  consulted (`handler.go:953–956` returns nil before counting).
- **Assertions:** error nil for `CheckNestedConvergence(store, "agent-b", "agent-a")`.
- **Invariants/rows:** creation guard.
- **Fixture:** same store as H22.
- **Priority:** must.

### H24 `TestCheckNestedConvergence_CrossAgent_TargetHasActiveLoops` — `handler_test.go:1047`

- **Scenario:** identical inputs and assertion to H23 (duplicate emphasising that the TARGET
  having active loops doesn't matter cross-agent).
- **Assertions:** error nil.
- **Invariants/rows:** creation guard.
- **Fixture:** as H22.
- **Priority:** must (trivial; may merge with H23 in Dart, keep both names in comments).

### H25 `TestCheckConcurrencyLimits_Exceeded` — `handler_test.go:1062`

- **Scenario:** two active loops target agent-a; per-agent max 2 → refused.
- **Assertions:** error non-nil; contains `per-agent limit`. ⚠ boundary: refusal at
  `count >= max` (`handler.go:981`), i.e. 2/2 is already over.
- **Fixture:** two beads with `{target: agent-a, state: active}`;
  `CheckConcurrencyLimits(store, "agent-a", 2)`.
- **Priority:** must.

### H26 `TestCheckConcurrencyLimits_OK` — `handler_test.go:1082`

- **Scenario:** one active loop, max 2 → allowed.
- **Assertions:** error nil.
- **Fixture:** one bead `{target: agent-a, state: active}`.
- **Priority:** must.

### H27 `TestEventIDFormulas` — `handler_test.go:1095` · 7 table rows

- **Scenario:** stable event-ID formulas for bead `gc-conv-42`.
- **Rows (exact strings):** created→`converge:gc-conv-42:created` ·
  iteration(3)→`converge:gc-conv-42:iter:3:iteration` ·
  waiting_manual(3)→`converge:gc-conv-42:iter:3:waiting_manual` ·
  terminated→`converge:gc-conv-42:terminated` ·
  manual_approve→`converge:gc-conv-42:manual_approve` ·
  manual_iterate(4)→`converge:gc-conv-42:iter:4:manual_iterate` ·
  manual_stop→`converge:gc-conv-42:manual_stop`.
- **Invariants/rows:** event contract. NOTE: `trigger_advance` formula NOT covered (gap).
- **Fixture:** none.
- **Priority:** must.

### H28 `TestNullableString` — `handler_test.go:1118`

- **Scenario:** `""` → null pointer; `"hello"` → pointer to value.
- **Assertions:** `NullableString("") == nil`; `*NullableString("hello") == "hello"`.
- **Invariants/rows:** event payload null-vs-empty contract (gate_outcome / next_wisp_id /
  waiting_reason fields).
- **Fixture:** none.
- **Priority:** must — in Dart this becomes the `String? nullableString(String)` helper or the
  codec rule "empty string serializes as JSON null" — keep it pinned by a test either way.

### H29 `TestGateResultToPayload` — `handler_test.go:1127`

- **Scenario:** payload conversion of `GateResult`.
- **Assertions:** empty `Outcome` → returns null (manual mode). Non-empty
  (`Outcome=fail, ExitCode=1, Stdout="output", Stderr="error", Duration=5s, Truncated=true`)
  → payload with `exit_code == 1` (non-null), `duration_ms == 5000`, `truncated == true`.
- **Invariants/rows:** event contract (`events.go:195–206`).
- **Fixture:** none.
- **Priority:** must.

### H30 `TestHandleWispClosed_SpeculativePour_WispExistsBeforeGateEval` — `handler_test.go:1198`

- **Scenario:** Replay fail → iterate; the speculative wisp poured in step 3b is adopted as the
  next active wisp and the pending marker is cleared.
- **Assertions:** `Action == "iterate"`; `NextWispID != ""`; metadata
  `active_wisp == NextWispID`; `pending_next_wisp == ""`.
- **Invariants/rows:** Inv 5; Row T2.
- **Fixture:** baseline + replay fail.
- **Priority:** must.

### H31 `TestHandleWispClosed_SpeculativePourFailureStillAllowsTerminalGate` — `handler_test.go:1227`

- **Scenario:** A REAL gate script (`pass.sh` = `#!/bin/sh\nexit 0`, mode 0755, in a temp dir)
  is configured as `gate_condition`; the speculative pour fails (hook throws
  `transient speculative pour failure`); the gate evaluates → pass; the pour failure must NOT
  derail the terminal transition.
- **Assertions:** no error; `Action == "approved"`; `state == "terminated"`;
  `waiting_reason != "sling_failure"` (pour error is only consulted on NON-terminal outcomes —
  `handler.go:370–374`).
- **Invariants/rows:** Inv 5; Row T1; D3 gate execution (exit 0 → `pass`).
- **Fixture:** baseline + `{gate_condition: <tmp>/pass.sh}` + failing
  `PourSpeculativeWispFunc`. Executes a subprocess via `RunCondition`.
- **Priority:** **should** — the only handler test that shells out (filesystem + process;
  Track D dependency). Port once the Dart gate runner exists, or inject a fake condition runner
  at the Track-D seam; ALSO add a pure variant (replay pass + failing pour) — see coverage gaps.

### H32 `TestHandleWispClosed_InvalidConditionDoesNotBurnUnvalidatedPendingWisp` — `handler_test.go:1258`

- **Scenario:** `pending_next_wisp=other-wisp` points at a wisp belonging to a DIFFERENT root
  (`other-root`, key `converge:other-root:iter:2`); gate mode `condition` with no condition and
  no replay → handler errors, but must not delete a wisp it doesn't own.
- **Assertions:** error non-nil (missing condition, literal in §1.8); bead `other-wisp` still
  exists; root-1's `pending_next_wisp == ""` (self-healed/un-marked by `validPendingNextWisp`,
  `handler.go:935–945`: invalid = wrong parent OR wrong key OR status closed OR missing).
- **Invariants/rows:** Inv 5 (pending validation); config-validation-before-pour
  (`handler.go:222–241`).
- **Fixture:** baseline + `{pending_next_wisp: other-wisp}`; extra beads `other-root`
  (in_progress) and `other-wisp` (in_progress, parent `other-root`, key
  `converge:other-root:iter:2`).
- **Priority:** must.

### H33 `TestHandleWispClosed_SpeculativePourDeletedOnTerminal` — `handler_test.go:1280`

- **Scenario:** Replay pass → terminal; the step-3b speculative wisp must be burned
  (subtree-deleted), not left as a phantom iteration.
- **Assertions:** `Action == "approved"`; `FindByIdempotencyKey("converge:root-1:iter:2")` →
  not found; `pending_next_wisp == ""`.
- **Invariants/rows:** Inv 5 (burn on terminal); Row T1; Inv 3 (lookup by key).
- **Fixture:** baseline + replay pass.
- **Priority:** must.

### H34 `TestHandleWispClosed_IterateActivatesSpeculativeWispBeforeCommit` — `handler_test.go:1306`

- **Scenario:** Replay fail → iterate; the speculative wisp is ACTIVATED (published) before the
  commit writes land.
- **Assertions:** `Action == "iterate"`; `ActivatedWispIDs == [NextWispID]` (exactly one
  activation); commit keys: `[-2] == last_processed_wisp`, `[-1] == pending_next_wisp`.
- **Invariants/rows:** Inv 2, 5; Row T2. ⚠ ordering: `ActivateWisp(next)` precedes
  `SetMetadata(active_wisp)` (`handler.go:525–527` then `557`).
- **Fixture:** baseline + replay fail.
- **Priority:** must.

### H35 `TestHandleWispClosed_NoSpeculativePourOnWaitingManual` — `handler_test.go:1335`

- **Scenario:** Pure manual gate; no successor wisp may be created while waiting.
- **Assertions:** `Action == "waiting_manual"`; `FindByIdempotencyKey("converge:root-1:iter:2")`
  → not found.
- **Invariants/rows:** Inv 5 (`skipSpeculativePour` for manual-without-gate,
  `handler.go:249–254`); Row T7.
- **Fixture:** baseline + `{gate_mode: manual}`.
- **Priority:** must.

### H36 `TestHandleWispClosed_ManualThenIterateUsesNextSequentialIteration` — `handler_test.go:1355`

- **Scenario:** Manual hold, then operator iterate (`IterateHandler(ctx, "root-1", "operator",
  "")`, `manual.go:124`); the new wisp gets the NEXT sequential key.
- **Assertions:** first call: `Action == "waiting_manual"`. Second call:
  `result.Iteration == 2`; the poured wisp's idempotency key == `converge:root-1:iter:2`.
- **Invariants/rows:** Rows T7 then T9; Inv 3 (sequential 1-based keys).
- **Fixture:** baseline + `{gate_mode: manual}`. Requires the manual-handler port
  (`manual_test.go` scope) — keep this one in the handler suite as the seam test.
- **Priority:** must.

### H37 `TestHandleWispClosed_NoSpeculativePourAtMaxIterations` — `handler_test.go:1384`

- **Scenario:** `max_iterations=1`, replay fail at iteration 1 → no_convergence; no speculative
  pour may even be attempted at the budget boundary (`wispIteration < maxIterations` guard,
  `handler.go:254`).
- **Assertions:** `Action == "no_convergence"`; `FindByIdempotencyKey("converge:root-1:iter:2")`
  → not found.
- **Invariants/rows:** Inv 5; Row T5.
- **Fixture:** baseline + `{max_iterations: "1"}` + replay fail.
- **Priority:** must.

### H38 `TestCrashAfterSpeculativePour_ReconcilerRecoversChain` — `handler_test.go:1406`

- **Scenario:** Crash simulation: manual-mode loop died after pouring the speculative wisp —
  `active_wisp=wisp-iter-1` (closed, unprocessed: no `last_processed_wisp`),
  `pending_next_wisp=wisp-iter-2` (in_progress). `Reconciler.ReconcileBeads(["root-1"])`
  replays the closed wisp (`reconcile.go:445–464`), which (manual mode) burns the pending wisp
  and parks the loop.
- **Assertions:** no reconciliation error; `report.Errors == 0`; final
  `convergence.state == "waiting_manual"`.
- **Invariants/rows:** D2 recovery path `active`; Inv 1, 5; ends in Row T7.
- **Fixture:** hand-built: root meta `{state: active, iteration: "1", max_iterations: "5",
  formula: test-formula, target: test-agent, gate_mode: manual, active_wisp: wisp-iter-1,
  pending_next_wisp: wisp-iter-2}`; `wisp-iter-1` closed with key iter:1; `wisp-iter-2`
  in_progress with key iter:2. `Reconciler{Handler}` reusing the handler's store/emitter.
  Report shape: `ReconcileReport{Scanned, Recovered, Errors, Details[{BeadID, Action, Error}]}`
  with detail actions `completed_terminal|adopted_wisp|poured_wisp|repaired_state|no_action`
  (`reconcile.go:12–25`).
- **Priority:** must.

### H39 `TestCrashAfterSpeculativePour_NoActiveWisp_ReconcilerAdoptsSpeculative` — `handler_test.go:1450`

- **Scenario:** Crash AFTER the commit (`last_processed_wisp=wisp-iter-1` set, `active_wisp=""`)
  but before adopting the speculative wisp. Reconcile must adopt `pending_next_wisp` as the new
  active wisp without re-processing.
- **Assertions:** `report.Errors == 0`; metadata `active_wisp == "wisp-iter-2"`;
  `state == "active"` (unchanged).
- **Invariants/rows:** recovery path `active` fall-through (`reconcile.go:475–538`): derive
  closed iteration (=1) → nextKey iter:2 → `validPendingNextWisp` hit → `ActivateWisp` →
  set `active_wisp` → clear `pending_next_wisp`. Inv 4, 5.
- **Fixture:** as H38 but `{gate_mode: manual, active_wisp: "", last_processed_wisp:
  wisp-iter-1, pending_next_wisp: wisp-iter-2}`.
- **Priority:** must.

### H40 `TestCrashAfterSpeculativePour_ReconcilerUsesPendingNextWispBeforeLookup` — `handler_test.go:1491`

- **Scenario:** Same recovery as H39 (gate_mode `condition`), but `FindByIdempotencyKey` is
  rigged to FAIL if called — proving the pending marker is consulted FIRST.
- **Assertions:** `report.Errors == 0`; `active_wisp == "wisp-iter-2"`;
  `ActivatedWispIDs == ["wisp-iter-2"]`.
- **Invariants/rows:** Inv 5. ⚠ evaluation order: `validPendingNextWisp(...)` BEFORE
  `FindByIdempotencyKey(nextKey)` (`reconcile.go:492–496`).
- **Fixture:** as H39 with `{gate_mode: condition}` + erroring `FindByIdempotencyKeyFunc`.
- **Priority:** must.

---

## 5. Count summary

| Metric | Count |
|---|---|
| Go test functions | **40** |
| Table-driven sub-cases | 19 (H01: 5, H02: 7, H27: 7) |
| Total conformance cases (functions w/o tables + sub-cases) | **56** (37 + 19) |
| **must** | 39 functions / 55 cases |
| **should** | 1 function / 1 case (H31 — real subprocess gate; port at/after Track D, or fake the runner) |
| **skip** | 0 — nothing in this file is gc-runtime-specific; everything runs against the fake store |

---

## 6. Coverage gaps — behaviors the Dart suite should ADD

Behaviors implemented in `handler.go` (and required by ADR-0003) that NO test in
`handler_test.go` exercises. Some are covered by sibling Go suites (noted); the rest are genuine
holes worth closing in Dart.

1. **Gate-persistence write ordering (Inv 2, second clause).** `persistGateOutcome`
   (`handler.go:776–808`) writes 7 gate keys then `gate_outcome_wisp` **LAST**, and
   `extractCommitKeys` filters all of them out — the ordering is asserted nowhere. Add a
   WriteLog test that the replay marker is the final gate-persistence write.
2. **Replay payload fidelity.** The replay branch reconstructs the full `GateResult` from
   persisted `gate_stdout`/`gate_stderr`/`gate_duration_ms`/`gate_truncated`
   (`handler.go:280–298`); tests only check `Outcome`. Assert the reconstructed
   `gate_result` event payload matches the persisted values.
3. **Iteration-derivation repair (Inv 4).** Stored `convergence.iteration` disagreeing with the
   derived closed-child count triggers a repair write (`handler.go:209–214`) — never asserted.
   Add: stored `"7"`, one closed child → expect `SetMetadata(iteration, "1")` in the log.
4. **`gate_outcome=error` path.** No test seeds outcome `error`; it is non-terminal below max
   (→ iterate) and terminal at max (→ no_convergence). Pin both.
5. **Timeout with `gate_timeout_action=iterate` (the default) and `retry`.** Only `manual` and
   `terminate` are covered here (retry budget `MaxGateRetries=3` lives in
   `condition.go`/`retry_test.go`). Add timeout→iterate at minimum.
6. **Timeout+manual at max iterations precedence.** ⚠ ordering `handler.go:345–351`: the
   timeout-manual check precedes the `iter >= max` terminal check — waiting_manual must win.
   Untested; easy to transcribe wrongly.
7. **Speculative pour error rescued by key lookup** (`handler.go:260–266`): pour throws but
   `FindByIdempotencyKey(nextKey)` finds an existing wisp → adopt, NO sling failure. Untested.
8. **Pure variant of H31:** replay pass + failing speculative pour → approved (no subprocess
   needed). Closes the must-tier hole left by H31 being runtime-coupled.
9. **Guard-check side effect:** state `terminated` → best-effort
   `CloseBead(root, "convergence: terminated state observed; closing root")`
   (`handler.go:173`) — only the skip is asserted, not the close or its reason literal.
10. **Strictly-older wisp dedup:** only equality (`wispIteration == lastProcessed`) is tested;
    add `wispIteration < lastProcessed` (a stale iter-1 event arriving after iter-2 committed).
11. **Verdict semantics divergence:** mismatched `agent_verdict_wisp` ⇒ gate sees `block`
    (`handler.go:319–324`) but event payloads carry `""` (`handler.go:417–420, 533–535`); and
    `NormalizeVerdict` past-tense/unknown mapping (`metadata.go:124–138`) — covered by
    `metadata_test.go`, but the handler-level block-on-mismatch is unasserted anywhere.
12. **Trigger-gated rows (T6, T10):** `transitionToWaitingTrigger` (`handler.go:575–635`) —
    skip of speculative pour, write order `active_wisp=""` → `state=waiting_trigger` →
    `last_processed_wisp`, and the `EventIDTriggerAdvance` formula
    `converge:<bead>:iter:<N>:trigger_advance` (absent from H27). Covered by `trigger_test.go`
    (separate Track-H item) — keep at least the event-ID formula in the Dart handler suite.
13. **`burnSpeculativeWisp` subtree recursion** (`handler.go:908–933`): speculative wisps with
    children are deleted depth-first; fakes never give the wisp children. Add one.
14. **Duration math:** `computeDurations` (`handler.go:829–850`) — per-iteration and cumulative
    sums over closed children; payload duration values are never numerically asserted (the fake
    pins CreatedAt=now−10m/ClosedAt=now precisely so they COULD be).
15. **`withEventRig` pass-through:** empty/missing `convergence.rig` or metadata read error →
    payload unchanged, no `rig` key (`handler.go:860–895`); only the populated case is tested.
16. **bd close_reason length contract:** the Dart fake should assert every `CloseBead` reason is
    ≥ 20 chars (`handler.go:80–85` doc contract) so a wrong/abbreviated literal fails fast.

---

## 7. Porting traps

The details most likely to be transcribed wrongly, in rough order of blast radius:

1. **`last_processed_wisp` is the commit point — and it is a DIFFERENT key per concern.**
   Three "written LAST" contracts coexist: `convergence.last_processed_wisp` last in every
   step-9 commit; `convergence.gate_outcome_wisp` last in step-5 gate persistence; and in the
   iterate path the best-effort `pending_next_wisp=""` cleanup comes AFTER
   `last_processed_wisp` (so the *load-bearing* last write is second-to-last in the raw log).
   Get any of these swapped and crash recovery double-processes or skips iterations.
2. **`CloseBead` must not pollute the write log.** gc's fake records only `SetMetadata` keys;
   `CloseBead` stores `close_reason` directly. If the Dart fake routes close through
   `setMetadata`, H18's "last write is `last_processed_wisp`" assertion breaks falsely
   (terminate calls CloseBead BETWEEN `state` and `last_processed_wisp`).
3. **Replay bypasses config validation.** When `gate_outcome_wisp == wispID`, the
   condition-mode-without-condition error (`handler.go:235`) does NOT fire — most replay
   fixtures in this suite have NO `gate_condition` and rely on this. A Dart port that validates
   gate config unconditionally will error on half the suite.
4. **Iteration arithmetic:** keys are 1-based; the dedup compares against the iteration parsed
   from the last-processed wisp's OWN key (a store read), not a stored counter; the next key is
   `wispIteration + 1` (from the closed wisp's key), not derived/stored iteration + 1; and
   `iter >= max` (not `>`) is terminal. `ParseIterationFromKey` uses the LAST `:iter:`
   occurrence and accepts 0.
5. **Events fire BEFORE the commit writes** (`EventIteration` always; `EventTerminated` too) —
   except `EventWaitingManual`, which fires AFTER the waiting_manual commit
   (`handler.go:436` vs `467`). At-least-once means a crash mid-commit re-emits with the same
   stable event ID; consumers dedup by ID — do not "fix" this to emit-after-commit.
6. **Speculative pour error is deferred, not raised.** A failed step-3b pour is stashed
   (`speculativePourErr`) and only matters if the outcome is NON-terminal → sling-failure hold.
   On terminal outcomes it is ignored entirely (H31). Pour error also tries an idempotency-key
   rescue before being stashed.
7. **`validPendingNextWisp` validates ownership** — wrong parent, wrong expected key, closed
   status, or missing bead ⇒ clear the marker but DO NOT delete the bead (H32). Burning is
   reserved for wisps that validated as ours.
8. **Burn order:** the speculative wisp is burned BEFORE entering waiting_manual or terminate
   (subtree delete + clear marker), and burning is skipped when ID is empty. Manual/trigger
   modes never pour in the first place (`skipSpeculativePour`, `handler.go:249–253`); neither
   does `wispIteration >= maxIterations`.
9. **Timeout-action precedence:** `timeout && action==manual` is checked BEFORE the terminal
   switch; `timeout && action==terminate` is terminal `no_convergence` (not `stopped`); the
   `pass` case wins over max-iterations.
10. **Verdict scoping is two different defaults:** for GATE evaluation a mismatched/missing
    `agent_verdict_wisp` means `block`; for EVENT payloads it means `""`. Clearing happens only
    on iterate/waiting_trigger and only when the verdict belongs to the closed wisp.
11. **Null-vs-empty in payloads:** `gate_outcome`, `gate_result`, `next_wisp_id`,
    `waiting_reason`, `exit_code` are JSON `null` (not `""`/`0`) when absent; `rig` is
    omit-empty; `final_status` is the literal `closed`; `actor` is the literal `controller`
    for handler-driven terminals (`recovery` for reconciler backfills, `operator:<username>`
    for manual actions).
12. **Go duration strings:** `convergence.gate_timeout` holds Go syntax (`60s`, `5m`); Dart must
    parse/emit that format, not ISO-8601. Default 5 minutes, must be > 0; invalid → parse error.
13. **Fake-store snapshot semantics:** `GetMetadata` returns a copy; the handler reads the root
    metadata ONCE at entry and consults that snapshot throughout (mid-flight `SetMetadata`
    calls don't change decisions). A Dart fake returning a live map alters behavior.
14. **Fake timestamps:** `addBead` sets `CreatedAt = now − 10m` AND `ClosedAt = now` for every
    bead regardless of status; duration math treats zero timestamps as "skip". Reproduce this
    or duration assertions added later will differ.
15. **Error taxonomy:** missing beads must be distinguishable as not-found (gc wraps
    `beads.ErrNotFound`); the reconciler's active-wisp recovery branches on it
    (`reconcile.go:401–426`). A generic exception breaks recovery paths.
16. **Single writer (Inv 7) is an assumption, not code:** `handler.go:144–146` documents that
    only one caller may process a given root at a time — the Dart reconciler loop must
    serialize per-bead (and ADR-0003 D6: never run against beads gc owns).
17. **`CheckConcurrencyLimits` boundary is `>=`** — a limit of 2 with 2 active loops refuses.
    `CheckNestedConvergence` only ever blocks SELF-targeting; it returns nil for cross-agent
    before touching the store.
