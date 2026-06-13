# Conformance spec — operator commands, trigger gating, retry

**Source of truth (READ-ONLY, pinned gascity on disk, assessed 2026-06-12):**

- `gascity/internal/convergence/manual_test.go` (669 lines, 21 tests) — `ApproveHandler` / `IterateHandler` / `StopHandler`
- `gascity/internal/convergence/trigger_test.go` (345 lines, 8 tests / 11 cases) — `ParseTriggerConfig` / `TriggerConditionEnv` / `HandleTrigger` / trigger-gated `HandleWispClosed`
- `gascity/internal/convergence/retry_test.go` (296 lines, 9 tests) — `RetryHandler`

All paths below are relative to `/Users/nico/development/com.gastownhall/gascity/internal/convergence/` unless prefixed. Per **ADR-0003 Decision 7** these tests are the executable spec; this document is the transliteration contract for **Track H** (`docs/M2-BUILD-ORDER.md`). Every test below maps to ADR-0003's invariants **I1–I7** and transition-table rows **T1–T12** (numbered top-to-bottom as printed in ADR-0003 §Decision 2):

| Row | From | Trigger | Condition | To | Action |
|---|---|---|---|---|---|
| T1 | active | wisp closed | gate=pass | terminated | `approved` |
| T2 | active | wisp closed | gate=fail ∧ iter<max | active | `iterate` |
| T3 | active | wisp closed | timeout ∧ action=manual | waitingManual | `waitingManual` |
| T4 | active | wisp closed | timeout ∧ action=terminate | terminated | `noConvergence` |
| T5 | active | wisp closed | iter≥max ∧ gate≠pass | terminated | `noConvergence` |
| T6 | active | wisp closed | trigger enabled | waitingTrigger | `waitingTrigger` |
| T7 | active | wisp closed | gate_mode=manual | waitingManual | `waitingManual` |
| T8 | waitingManual | operator approve | — | terminated | `approved` |
| T9 | waitingManual | operator iterate | — | active | `iterate` |
| T10 | waitingTrigger | trigger condition passes | — | active | `iterate` |
| T11 | any | operator stop | — | terminated | `stopped` |
| T12 | creating | startup reconcile | — | terminated | partial-creation cleanup |

Invariants: **I1** monotonic dedup · **I2** write ordering (`last_processed_wisp` LAST) · **I3** idempotency keys · **I4** iteration derived from closed children · **I5** speculative pour before gate eval · **I6** terminal irreversibility · **I7** single writer per bead.

---

## 1. Shared vocabulary — exact string literals

A Dart implementer must reproduce these byte-for-byte. Every value is a metadata string (bd metadata is string→string).

### 1.1 Metadata keys (`metadata.go:12–44`)

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
| `FieldGateOutcomeWisp` | `convergence.gate_outcome_wisp` |
| `FieldTerminalReason` | `convergence.terminal_reason` |
| `FieldTerminalActor` | `convergence.terminal_actor` |
| `FieldWaitingReason` | `convergence.waiting_reason` |
| `FieldRetrySource` | `convergence.retry_source` |
| `FieldCityPath` | `convergence.city_path` |
| `FieldRig` | `convergence.rig` |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` |
| `FieldTrigger` | `convergence.trigger` |
| `FieldTriggerCondition` | `convergence.trigger_condition` |
| `VarPrefix` | `var.` (template variables: `var.<name>`, `metadata.go:47`) |

### 1.2 Value domains (`metadata.go:50–109`)

| Domain | Literals |
|---|---|
| `convergence.state` | `creating` · `active` · `waiting_manual` · `waiting_trigger` · `terminated` |
| `convergence.trigger` | `""` (none, `TriggerNone`) · `event` (`TriggerEvent`) — anything else is a parse error |
| `convergence.gate_mode` | `manual` · `condition` · `hybrid` (empty defaults to `manual`, `gate.go:46–48`) |
| `convergence.gate_timeout_action` | `iterate` · `retry` · `manual` · `terminate` (default `iterate`, `gate.go:69`) |
| `convergence.terminal_reason` | `approved` · `no_convergence` · `stopped` · `partial_creation` |
| gate outcome | `pass` · `fail` · `timeout` · `error` |
| `convergence.waiting_reason` | `manual` · `hybrid_no_condition` · `timeout` · `sling_failure` |
| normalized verdicts | `approve` · `approve-with-risks` · `block` (unknown/empty → `block`, `metadata.go:124–138`) |
| handler actions (`handler.go:121–127`) | `iterate` · `approved` · `no_convergence` · `waiting_manual` · `waiting_trigger` · `stopped` · `skipped` |

### 1.3 Idempotency keys (`handler.go:13–39`)

| Function | Format |
|---|---|
| `IdempotencyKeyPrefix(beadID)` | `converge:<beadID>:iter:` (trailing colon) |
| `IdempotencyKey(beadID, n)` | `converge:<beadID>:iter:<n>` (no trailing colon; 1-based) |
| `ParseIterationFromKey(key)` | finds the **last** `:iter:` substring, parses the decimal suffix; rejects negative, non-numeric, empty suffix; `0` is parseable (`handler_test.go:382–407` pins `converge:root-1:iter:0` → `(0, true)`) |

### 1.4 Event types and IDs (`events.go:11–20`, `events.go:37–81`)

| Event type literal | Stable event ID format | Tier |
|---|---|---|
| `convergence.created` | `converge:<beadID>:created` | recoverable |
| `convergence.iteration` | `converge:<beadID>:iter:<N>:iteration` | critical |
| `convergence.terminated` | `converge:<beadID>:terminated` | critical |
| `convergence.waiting_manual` | `converge:<beadID>:iter:<N>:waiting_manual` | recoverable |
| `convergence.manual_approve` | `converge:<beadID>:manual_approve` | best_effort |
| `convergence.manual_iterate` | `converge:<beadID>:iter:<N>:manual_iterate` (N = **new** wisp's iteration) | recoverable |
| `convergence.manual_stop` | `converge:<beadID>:manual_stop` | best_effort |
| `convergence.trigger_advance` | `converge:<beadID>:iter:<N>:trigger_advance` (N = **new** wisp's iteration) | — |

⚠ **ordering / collision:** `convergence.trigger_advance` must NOT share an event ID with `convergence.iteration` — both would otherwise derive `converge:<bead>:iter:<N>` forms for the same N (`events.go:74–81`, pinned by `trigger_test.go:147–159`).

### 1.5 Event payload JSON shapes (`events.go:84–158`)

`ManualActionPayload` (for `manual_approve`, `manual_iterate`, `manual_stop`, `trigger_advance`):
`{"rig"?: string, "actor": string, "prior_state": string, "new_state": string, "iteration": int, "wisp_id": string|null, "next_wisp_id": string|null}` — `wisp_id`/`next_wisp_id` use `NullableString` (`events.go:186–191`): **empty string serializes as JSON `null`, never `""`**.

`TerminatedPayload`: `{"rig"?: string, "terminal_reason": string, "total_iterations": int, "final_status": "closed", "actor": string, "cumulative_duration_ms": int}`.

`CreatedPayload`: `{"formula": string, "target": string, "rig"?: string, "gate_mode": string, "max_iterations": int, "title": string, "first_wisp_id": string, "retry_source": string|null}`.

`IterationPayload`: includes `"action"` (string form of the handler action) — see `events.go:104–121`.

Actor strings: operator commands always emit `operator:<username>` (built inside the handler, `manual.go:27`); trigger advance emits `controller` (`trigger.go:166`); the rig field is injected by `withEventRig` from the root bead's `convergence.rig` (`handler.go:860–884`).

### 1.6 Close reasons (`handler.go:46–55`)

bd's `validation.on-close=error` rejects close reasons under 20 chars; these are the canonical strings (used by tests in this file set):

- `CloseReasonRetryRollback` = `convergence: retry-create rollback after error`
- `CloseReasonManualApprove` = `convergence: iteration closed by manual approve`
- `CloseReasonManualSupersede` = `convergence: active wisp superseded during manual stop`
- `CloseReasonManualStop` = `convergence: iteration closed by manual stop`
- `CloseReasonHandlerCleanup` = `convergence: terminated state observed; closing root`

### 1.7 Error message fragments asserted by tests (conformance surface)

| Source | Fragment (substring-matched by tests) |
|---|---|
| `manual.go:38–41` | `cannot approve bead %q: state is %q, expected %q` (mentions both `waiting_manual` and current state) |
| `manual.go:134–137` | `cannot iterate bead %q: state is %q, expected %q` |
| `manual.go:147–150` | `cannot iterate bead %q: at max iterations (%d/%d)` — tests match `max iterations` |
| `manual.go:173` | `pouring next wisp for bead %q: …` — tests match `pouring next wisp` |
| `manual.go:259–262` | `cannot stop bead %q: state is %q, expected %q, %q, or %q` (active, waiting_manual, waiting_trigger) |
| `trigger.go:35` | `trigger mode "event" requires a trigger condition path` — tests match `requires a trigger condition` |
| `trigger.go:39` | `invalid trigger mode %q` — tests match `invalid trigger mode` |
| `trigger.go:90` | `trigger-gated loop %q at iteration %d exceeds max_iterations %d; refusing to advance` — tests match `exceeds max_iterations` |
| `retry.go:30–33` | `cannot retry bead %q: state is %q, expected "terminated"` — tests match `terminated` |
| `retry.go:38–40` | `cannot retry bead %q: terminal_reason is "approved" (approved loops cannot be retried)` — tests match `approved` and `cannot be retried` |
| `retry.go:64` | `source bead %q has invalid gate config: …` — tests match `invalid gate config` |
| `retry.go:119` | `pouring first wisp for retry bead %q: …` — tests match `pouring first wisp` |

---

## 2. Fake harness contract — what the Dart fake store/emitter must support

Transliterated from `handler_test.go:24–305` (the fakes are shared by all three test files).

**`FakeStore`** (implements the `Store` interface, `handler.go:69–114`):

1. `addBead(id, status, parentID, idempotencyKey, meta)` — registers a bead with `CreatedAt = now − 10min`, `ClosedAt = now` (set even when not closed; `handler_test.go:60–61`), and appends to the parent's child list **only if the parent was added first** (`handler_test.go:66–70`). ⚠ ordering: fixtures must add roots before children.
2. `getBead(id)` — returns `BeadInfo{id, status, parentID, idempotencyKey, createdAt, closedAt}`; missing bead → error wrapping a sentinel `NotFound` (Dart: a typed exception the handler can test for, mirroring `beads.ErrNotFound`).
3. `getMetadata(id)` — returns a **copy** of the metadata map.
4. `setMetadata(id, key, value)` — mutates and appends `key` to an ordered **`writeLog`** (`handler_test.go:101–111`). The write-ordering tests read this log.
5. `closeBead(id, reason)` — sets status `closed`, stamps `close_reason` into metadata (`handler_test.go:113–129`).
6. `children(parentID)` — child `BeadInfo`s in insertion order; unknown parent → empty, no error.
7. `pourWisp(parentID, formula, key, vars, evaluatePrompt)` — **idempotent**: if any bead already has `idempotencyKey == key`, return its ID; else create `wisp-<n>` (auto-increment) with status `in_progress` and register as child (`handler_test.go:183–211`). Must support an injectable failure override (`PourWispFunc`, `handler_test.go:29`) — used by `TestIterateHandler_PourWispFailure` and `TestRetryHandler_PartialCreateCleanup`.
8. `findByIdempotencyKey(key)` — `(id, found)` scan; injectable override.
9. `activateWisp(id)` — records the ID in `activatedWispIDs`; error if missing.
10. `createConvergenceBead(title)` — creates `conv-<n>`, status `in_progress`, empty metadata; title ignored by the fake (`handler_test.go:253–267`).
11. `pourSpeculativeWisp` / `deleteBead` / `countActiveConvergenceLoops` — required by the interface; only indirectly exercised here.

**`FakeEmitter`**: records `(type, eventID, beadID, payloadJson, recovery)`; `findEvent(type)` returns the **first** event of that type (`handler_test.go:296–305`).

**Log helpers** (`handler_test.go:1161–1194`):

- `extractCommitKeys(log)` filters the write log to exactly this key set: `convergence.state`, `convergence.terminal_reason`, `convergence.terminal_actor`, `convergence.last_processed_wisp`, `convergence.active_wisp`, `convergence.waiting_reason`, `convergence.iteration`, `convergence.retry_source`, `convergence.pending_next_wisp`.
- `contains(s, sub)` is plain substring matching on error strings.

**Handler construction:** `Handler{Store, Emitter, Clock: time.Now}` — Dart: injectable clock; `StorePath` only matters for `HandleTrigger`'s env (`trigger.go:93`).

---

## 3. Fixture catalog (setup helpers, exact metadata)

### F1 — `setupWaitingManualHandler` (`manual_test.go:15–46`)

Root `root-1`, status `in_progress`, metadata (then `extraMeta` overrides applied on top):

| key | value |
|---|---|
| `convergence.state` | `waiting_manual` |
| `convergence.iteration` | `1` |
| `convergence.max_iterations` | `5` |
| `convergence.formula` | `test-formula` |
| `convergence.target` | `test-agent` |
| `convergence.gate_mode` | `manual` |
| `convergence.waiting_reason` | `manual` |
| `convergence.last_processed_wisp` | `wisp-iter-1` |

Child `wisp-iter-1`, status `closed`, parent `root-1`, idempotency key `converge:root-1:iter:1`, no metadata.

### F2 — `setupTriggerHandler` (`trigger_test.go:81–104`)

Root `root-1`, status `in_progress`:

| key | value |
|---|---|
| `convergence.state` | `waiting_trigger` |
| `convergence.iteration` | `0` |
| `convergence.max_iterations` | `5` |
| `convergence.formula` | `test-formula` |
| `convergence.target` | `test-agent` |
| `convergence.gate_mode` | `condition` |
| `convergence.gate_condition` | `/gate/ignored-in-trigger-tests` (never executed by `HandleTrigger`) |
| `convergence.gate_timeout` | `60s` (bounds the **trigger** condition too, `trigger.go:73–95`) |
| `convergence.trigger` | `event` |
| `convergence.trigger_condition` | path from `writeTriggerScript` |
| `convergence.city_path` | a temp dir |

No children unless the test adds them. `writeTriggerScript(t, exitCode)` (`trigger_test.go:16–25`) writes `trigger.sh`, mode `0755`, body exactly `#!/bin/sh\nexit <N>\n`.

### F3 — `setupTerminatedHandler` (`retry_test.go:14–53`)

Root `source-1`, status `closed`:

| key | value |
|---|---|
| `convergence.state` | `terminated` |
| `convergence.iteration` | `3` |
| `convergence.max_iterations` | `5` |
| `convergence.formula` | `test-formula` |
| `convergence.target` | `test-agent` |
| `convergence.gate_mode` | `condition` |
| `convergence.gate_condition` | `/path/to/gate.sh` |
| `convergence.gate_timeout` | `30s` |
| `convergence.gate_timeout_action` | `iterate` |
| `convergence.terminal_reason` | (parameter) |
| `convergence.terminal_actor` | `controller` |
| `convergence.city_path` | `/home/test/city` |
| `convergence.evaluate_prompt` | `check the code` |
| `convergence.last_processed_wisp` | `wisp-iter-3` |
| `var.doc_path` | `/docs/readme.md` |
| `var.branch` | `feature-x` |

Child `wisp-iter-3`, status `closed`, key `converge:source-1:iter:3`.

### F4 — `setupBasicHandler` (`handler_test.go:347–378`; used by `TestHandleWispClosed_TriggerGatesIteration`)

Root `root-1`, status `in_progress`: `state=active`, `iteration=1`, `max_iterations=5`, `formula=test-formula`, `target=test-agent`, `gate_mode=condition`, `gate_timeout=60s`, `gate_timeout_action=iterate` (note: **no** `gate_condition`, **no** `last_processed_wisp`). Child `wisp-iter-1`, `closed`, key `converge:root-1:iter:1`.

---

## 4. Inventory — `manual_test.go`

Code under test: `manual.go` (`ApproveHandler` 20–115, `IterateHandler` 124–217, `StopHandler` 241–445).

### M1. `TestApproveHandler_HappyPath` — `manual_test.go:50`
- **Scenario:** Given F1 (waiting_manual, 1 closed wisp); when `ApproveHandler(ctx, "root-1", "alice", "looks good")`; then loop terminates approved and root closes.
- **Assertions:** `result.Action == "approved"`; `result.Iteration == 1`; meta `convergence.state == "terminated"`, `convergence.terminal_reason == "approved"`, `convergence.terminal_actor == "operator:alice"`, `convergence.waiting_reason == ""` (cleared); root bead status `closed`; events `convergence.manual_approve` AND `convergence.terminated` both emitted.
- **Invariants/rows:** T8; I4 (Iteration = derived closed-children count, not stored field).
- **Fixture:** F1. | **Priority: must.**

### M2. `TestApproveHandler_WrongState_Active` — `manual_test.go:94`
- **Scenario:** F1 with `state=active`; approve must fail.
- **Assertions:** error non-nil; message contains `waiting_manual` AND `active`.
- **Invariants/rows:** T8 precondition guard. | **Fixture:** F1 + `{state: active}`. | **Priority: must.**

### M3. `TestApproveHandler_WrongState_Terminated` — `manual_test.go:111`
- **Scenario:** F1 with `state=terminated`, `terminal_reason=no_convergence`; approve fails (terminated-for-a-different-reason is NOT idempotent).
- **Assertions:** error non-nil; message contains `waiting_manual`.
- **Invariants/rows:** I6. | **Fixture:** F1 + overrides. | **Priority: must.**

### M4. `TestApproveHandler_Idempotent_AlreadyApproved` — `manual_test.go:126`
- **Scenario:** F1 with `state=terminated`, `terminal_reason=approved`, `terminal_actor=operator:bob`; re-approve by alice is a silent no-op.
- **Assertions:** no error; `result.Action == "approved"`; **no** `convergence.manual_approve` event emitted.
- **Invariants/rows:** I6 (idempotent terminal re-entry). | **Fixture:** F1 + overrides. | **Priority: must.**

### M5. `TestApproveHandler_WriteOrdering` — `manual_test.go:148` ⚠ ordering
- **Scenario:** F1; approve; verify the metadata commit protocol.
- **Assertions:** (a) the **very last** entry of the raw `writeLog` (all `setMetadata` calls) is `convergence.last_processed_wisp`; (b) among `extractCommitKeys`, the first occurrence of `convergence.terminal_reason` AND of `convergence.terminal_actor` both come strictly before the first `convergence.state`.
- **Source order being pinned** (`manual.go:62–109`): `terminal_reason` → `terminal_actor` → clear `waiting_reason` → `state=terminated` → emit `convergence.terminated` (TierCritical, **before** `closeBead`) → `closeBead(root, CloseReasonManualApprove)` → emit `convergence.manual_approve` (TierBestEffort, **after** close) → `last_processed_wisp` **LAST** (only if non-empty).
- **Invariants/rows:** I2; T8. | **Fixture:** F1. | **Priority: must.**

### M6. `TestApproveHandler_EventPayloads` — `manual_test.go:195`
- **Scenario:** F1; approve; verify both event envelopes and payloads.
- **Assertions:** `manual_approve` event: `eventID == "converge:root-1:manual_approve"`, `beadID == "root-1"`; payload `actor == "operator:alice"`, `prior_state == "waiting_manual"`, `new_state == "terminated"`. `terminated` event payload: `terminal_reason == "approved"`, `actor == "operator:alice"`, `final_status == "closed"`.
- **Invariants/rows:** T8; event contract §1.4–1.5. | **Fixture:** F1. | **Priority: must.**

### M7. `TestIterateHandler_HappyPath` — `manual_test.go:252`
- **Scenario:** F1; operator iterates; loop pours wisp 2 and goes active.
- **Assertions:** `result.Action == "iterate"`; `result.NextWispID != ""`; `result.Iteration == 2` (derived 1 + 1); meta `state == "active"`, `waiting_reason == ""`, `active_wisp == result.NextWispID`; `convergence.manual_iterate` event emitted.
- **Invariants/rows:** T9; I3 (new wisp keyed `converge:root-1:iter:2`); I4. | **Fixture:** F1. | **Priority: must.**

### M8. `TestIterateHandler_WrongState_Active` — `manual_test.go:287`
- **Assertions:** error contains `waiting_manual`. | T9 guard. | F1 + `{state: active}`. | **must.**

### M9. `TestIterateHandler_WrongState_Terminated` — `manual_test.go:301`
- **Assertions:** error contains `waiting_manual`. Iterate has **no** idempotent terminal path (unlike approve/stop). | I6. | F1 + `{state: terminated}`. | **must.**

### M10. `TestIterateHandler_AtMaxIterations` — `manual_test.go:315`
- **Scenario:** F1 with `max_iterations=1` while one closed child exists (derived count 1).
- **Assertions:** error contains `max iterations` (full text: `at max iterations (1/1)`).
- **Invariants/rows:** I4 — the ceiling check is `derivedCount >= max` (`manual.go:141–151`), NOT the stored `convergence.iteration`. | F1 + override. | **must.**

### M11. `TestIterateHandler_ClearsVerdictScopedToLastWisp` — `manual_test.go:329` ⚠ ordering
- **Scenario:** F1 + `agent_verdict=block`, `agent_verdict_wisp=wisp-iter-1` (matches `last_processed_wisp`); iterate.
- **Assertions:** `result.Action == "iterate"`; after success both `convergence.agent_verdict == ""` and `convergence.agent_verdict_wisp == ""`.
- **⚠ ordering:** verdict is cleared only **after** `pourWisp` succeeds (`manual.go:158–187`) so a failed pour preserves the verdict for retry. | D3 verdict channel. | **must.**

### M12. `TestIterateHandler_PreservesVerdictScopedToOtherWisp` — `manual_test.go:353`
- **Scenario:** F1 + `agent_verdict=approve`, `agent_verdict_wisp=wisp-other` (≠ `last_processed_wisp`).
- **Assertions:** after iterate, `convergence.agent_verdict == "approve"` (NOT cleared — clearing is scoped: only when `agent_verdict_wisp == last_processed_wisp`, `manual.go:180`). | **must.**

### M13. `TestIterateHandler_EventPayloads` — `manual_test.go:374`
- **Assertions:** `manual_iterate` event `eventID == "converge:root-1:iter:2:manual_iterate"` (N = **new** iteration 2); payload `actor == "operator:alice"`, `prior_state == "waiting_manual"`, `new_state == "active"`, `next_wisp_id` non-null and `== result.NextWispID`.
- **Note:** payload `wisp_id` is the **prior** wisp (`last_processed_wisp`), untested here. | T9. | F1. | **must.**

### M14. `TestIterateHandler_PourWispFailure` — `manual_test.go:408`
- **Scenario:** F1-equivalent fixture built inline; `PourWispFunc` returns error `sling failure`; `findByIdempotencyKey` finds nothing.
- **Assertions:** error contains `pouring next wisp`. (Implicit contract: bead remains `waiting_manual`; no state mutated before pour — `manual.go:158–177`.)
- **Fixture needs:** injectable pour failure. | T9 failure path. | **must.**

### M15. `TestStopHandler_HappyPath_WaitingManual` — `manual_test.go:443`
- **Scenario:** F1; `StopHandler(ctx, "root-1", "alice", "shutting down")`.
- **Assertions:** `result.Action == "stopped"`; `result.Iteration == 1`; meta `state == "terminated"`, `terminal_reason == "stopped"`, `terminal_actor == "operator:alice"`, `waiting_reason == ""`; root closed; events `convergence.manual_stop` AND `convergence.terminated`.
- **Invariants/rows:** T11; I4. | F1. | **must.**

### M16. `TestStopHandler_HappyPath_Active` — `manual_test.go:487`
- **Scenario:** F1 + `{state: active}` (note: `active_wisp` empty so no drain/force-close branch runs).
- **Assertions:** `result.Action == "stopped"`; `state == "terminated"`; `terminal_reason == "stopped"`. | T11 (from active). | **must.**

### M17. `TestStopHandler_WrongState_Terminated_NotStopped` — `manual_test.go:513`
- **Scenario:** F1 + `state=terminated`, `terminal_reason=approved`; stop fails.
- **Assertions:** error mentions `active` AND `waiting_manual` (full message also lists `waiting_trigger`, `manual.go:259–262` — stop's accepted states are all three). | I6. | **must.**

### M18. `TestStopHandler_Idempotent_AlreadyStopped` — `manual_test.go:531`
- **Scenario:** F1 + `state=terminated`, `terminal_reason=stopped`, `terminal_actor=operator:bob`.
- **Assertions:** no error; `result.Action == "stopped"`; **no** `convergence.manual_stop` event. | I6. | **must.**

### M19. `TestStopHandler_WriteOrdering` — `manual_test.go:553` ⚠ ordering
- **Assertions:** identical protocol to M5: raw `writeLog` ends with `convergence.last_processed_wisp`; among commit keys, `terminal_reason` and `terminal_actor` precede `state`.
- **Source order** (`manual.go:349–439`, 10-step stop): clear `agent_verdict` + `agent_verdict_wisp` (unconditional) → `terminal_reason` → `terminal_actor` → clear `waiting_reason` → `state=terminated` → (synthetic `convergence.iteration` for a force-closed wisp, if any) → `convergence.terminated` (before close) → `closeBead(root, CloseReasonManualStop)` → `convergence.manual_stop` (after close) → `last_processed_wisp` LAST (force-closed wisp ID wins over the prior value, `manual.go:430–434`). | I2; T11. | **must.**

### M20. `TestStopHandler_EventPayloads` — `manual_test.go:597`
- **Assertions:** `manual_stop` `eventID == "converge:root-1:manual_stop"`; payload `actor == "operator:alice"`, `prior_state == "waiting_manual"`, `new_state == "terminated"`. `terminated` payload `terminal_reason == "stopped"`, `actor == "operator:alice"`. | T11. | F1. | **must.**

### M21. `TestStopHandler_StopFromActive_PriorStateInEvent` — `manual_test.go:646`
- **Scenario:** F1 + `{state: active}`; stop.
- **Assertions:** `manual_stop` payload `prior_state == "active"` — the payload reflects the **actual** pre-stop state, never hardcoded `waiting_manual` (`manual.go:420–426` uses the possibly-refreshed `state` local). | T11. | **must.**

---

## 5. Inventory — `trigger_test.go`

Code under test: `trigger.go` (config 13–41, `HandleTrigger` 52–102, `TriggerConditionEnv` 110–123, `advanceFromTrigger` 129–180) and `handler.go:580–635` (`transitionToWaitingTrigger`).

### TR1. `TestParseTriggerConfig` — `trigger_test.go:27` (table, 4 rows)

| Row name | Input meta | Expected |
|---|---|---|
| `no trigger (default)` | `{}` | `Mode == ""`, `Enabled() == false`, no error |
| `event with condition` | `{convergence.trigger: event, convergence.trigger_condition: /path/to/check}` | `Mode == "event"`, `Enabled() == true` |
| `event without condition` | `{convergence.trigger: event}` | error contains `requires a trigger condition` |
| `invalid mode` | `{convergence.trigger: cron}` | error contains `invalid trigger mode` |

- **Invariants/rows:** T6/T10 config gate; pure parse. | **Fixture:** raw maps. | **Priority: must.**

### TR2. `TestHandleTrigger_EntryPoursFirstWispOnPass` — `trigger_test.go:106` ⚠ event-ID collision
- **Scenario:** F2 (waiting_trigger, iteration 0, no children), trigger script `exit 0`; `HandleTrigger(ctx, "root-1")` advances the **entry-gated first** iteration.
- **Assertions:** `result.Action == "iterate"`; `result.Iteration == 1`; `result.NextWispID != ""`; meta `state == "active"`, `active_wisp == NextWispID`, `convergence.iteration == "1"` (⚠ trigger advance **does** write the stored counter, `trigger.go:148` — unlike `IterateHandler`); poured wisp's idempotency key `== "converge:root-1:iter:1"`; **no** `convergence.iteration` event emitted; a `convergence.trigger_advance` event exists with `eventID == "converge:root-1:iter:1:trigger_advance"` and `eventID != EventIDIteration("root-1", 1)`; payload `iteration == 1`, `wisp_id == null` (JSON null — no prior wisp on entry), `next_wisp_id == NextWispID`.
- **Invariants/rows:** T10 (entry variant); I3; §1.4 collision rule.
- **Fixture:** F2 + real `/bin/sh` script (trivial, exit 0). Subprocess execution is ratified domain surface per ADR-0003 D3 (scripts via `Process`), not gc-runtime coupling; the Dart port may additionally run a faked-condition-runner variant offline. | **Priority: must.**

### TR3. `TestTriggerConditionEnv_MirrorsNextIteration` — `trigger_test.go:177`
- **Scenario:** Pure: `TriggerConditionEnv(meta{convergence.max_iterations: "5", var.doc_path: "/docs/spec.md"}, "root-9", "/city", "/store", 3)`.
- **Assertions:** `env.Iteration == 3` — the **caller-passed next iteration** (closed + 1), NOT the stored `convergence.iteration`; `env.ArtifactDir == ArtifactDirFor("/city", "root-9", 3)` = `/city/.gc/artifacts/root-9/iter-3` (`template.go:23–25`, format `<cityPath>/.gc/artifacts/<beadID>/iter-<N>`); `env.MaxIterations == 5`; `env.DocPath == "/docs/spec.md"` (sourced from `var.doc_path`); `env.BeadID == "root-9"`, `env.CityPath == "/city"`, `env.StorePath == "/store"`.
- **Why it matters:** this is the shared env builder for live `HandleTrigger` and the `gc converge test-trigger` dry-run; it feeds the `GC_*` env contract (`condition.go:90–128`: `GC_BEAD_ID`, `GC_ITERATION`, `GC_MAX_ITERATIONS`, `GC_DOC_PATH`, `GC_ARTIFACT_DIR`, `GC_STORE_PATH`, …; `GC_ARTIFACT_DIR` omitted when empty).
- **Invariants/rows:** D3 env contract; I4 (iteration source). | **Priority: must.**

### TR4. `TestHandleTrigger_WaitsWhenConditionFails` — `trigger_test.go:207`
- **Scenario:** F2, script `exit 1`.
- **Assertions:** no error; `result.Action == "skipped"`; meta `state == "waiting_trigger"` (unchanged); `active_wisp == ""`; `children("root-1")` count `== 0` — **no wisp poured** on a failing trigger.
- **Invariants/rows:** T10 negative; non-pass outcome (fail/timeout/error all behave the same, `trigger.go:95–99`) keeps waiting. | F2 + script. | **must.**

### TR5. `TestHandleTrigger_IterationGateAdvance` — `trigger_test.go:232`
- **Scenario:** F2 + `{convergence.iteration: 1, convergence.last_processed_wisp: wisp-iter-1}` + closed child `wisp-iter-1` (key `converge:root-1:iter:1`); script `exit 0`.
- **Assertions:** `result.Action == "iterate"`; `result.Iteration == 2` (derived 1 closed + 1); new wisp key `== "converge:root-1:iter:2"`; meta `state == "active"`.
- **Invariants/rows:** T10 (mid-loop variant); I3; I4. | **must.**

### TR6. `TestHandleTrigger_SkipsWhenNotWaiting` — `trigger_test.go:263`
- **Scenario:** F2 + `{state: active}`.
- **Assertions:** no error; `result.Action == "skipped"`. State guard returns before any parse or script execution (`trigger.go:59–61`) — pure. | T10 guard. | **must.**

### TR7. `TestHandleTrigger_RefusesToExceedMaxIterations` — `trigger_test.go:276` ⚠ ordering
- **Scenario:** Corrupt state: F2 + `{max_iterations: 1, iteration: 1, last_processed_wisp: wisp-iter-1}` + closed child iter-1; loop is in `waiting_trigger` though already at max.
- **Assertions:** error contains `exceeds max_iterations`; children count remains `1` — no over-limit pour.
- **⚠ ordering:** the max guard (`trigger.go:89–91`, condition `maxIter > 0 && nextIteration > maxIter`) is evaluated **before** the trigger condition runs (`trigger.go:95`) — the script never executes; this row is pure despite the script fixture. Note the `maxIter > 0` guard: an absent/unparseable max **disables** this defense. | T10 defense-in-depth; I4. | **must.**

### TR8. `TestHandleWispClosed_TriggerGatesIteration` — `trigger_test.go:299` ⚠ ordering
- **Scenario:** F4 (active) + `{convergence.gate_outcome_wisp: wisp-iter-1, convergence.gate_outcome: fail, convergence.trigger: event, convergence.trigger_condition: /some/trigger/check}`; `HandleWispClosed(ctx, "root-1", "wisp-iter-1")`. The cached gate outcome (`gate_outcome_wisp == wispID` ⇒ replay, `handler.go:233–234, 280–298`) says fail/iterate, but the trigger gates the loop, so it holds instead of pouring.
- **Assertions:** `result.Action == "waiting_trigger"`; meta `state == "waiting_trigger"`, `active_wisp == ""`, `last_processed_wisp == "wisp-iter-1"`; children count `== 1` — **no speculative/next wisp poured** (speculative pour skipped for trigger-gated loops, `handler.go:249–254`); a `convergence.iteration` event exists with payload `action == "waiting_trigger"`.
- **⚠ ordering** (`handler.go:619–628`): commit sequence is `active_wisp=""` → `state=waiting_trigger` → `last_processed_wisp=<wispID>` **LAST**.
- **Pure:** neither the gate script (cached replay) nor the trigger script (deferred to `HandleTrigger`) executes — the bogus paths `/gate/...`/`/some/trigger/check` prove it.
- **Invariants/rows:** T6; I2; I5 (pour-skip rule). | F4 + overrides. | **must.**

---

## 6. Inventory — `retry_test.go`

Code under test: `retry.go:21–147` (`RetryHandler(ctx, sourceBeadID, username, maxIterations) → RetryResult{NewBeadID, FirstWispID, Iteration}`).

### R1. `TestRetryHandler_CarriesRigForward` — `retry_test.go:55`
- **Scenario:** F3(`terminal_reason=stopped`) + `{convergence.rig: gascity-prod}`; `RetryHandler(ctx, "source-1", "alice", 10)`.
- **Assertions:** new bead meta `convergence.rig == "gascity-prod"`. | Coexistence-relevant (ADR-0003 D6 rig partition). | **must.**

### R2. `TestRetryHandler_Success` — `retry_test.go:69`
- **Scenario:** F3(stopped); retry with `maxIterations=10`.
- **Assertions:** `NewBeadID != ""`; `FirstWispID != ""`; `result.Iteration == 1`; new bead meta: `state == "active"`, `formula == "test-formula"`, `active_wisp == FirstWispID`, `max_iterations == "10"` (⚠ from the **operator argument**, NOT copied from the source's `5`), `iteration == "1"`.
- **Invariants/rows:** new-loop bootstrap; I3 (first wisp keyed `converge:<NewBeadID>:iter:1`, `retry.go:116`). | F3. | **must.**

### R3. `TestRetryHandler_PartialCreateCleanup` — `retry_test.go:105` ⚠ ordering
- **Scenario:** F3(stopped); `PourWispFunc` returns error `simulated PourWisp failure`.
- **Assertions:** error contains `pouring first wisp`; some bead other than `source-1` exists with status `closed` AND meta `state == "terminated"` — the orphan root was rolled back (`closeBead` callback, `retry.go:76–82`: set `state=terminated` then `closeBead(id, "convergence: retry-create rollback after error")`).
- **Invariants/rows:** T12-adjacent (the `creating` marker written at `retry.go:83–85` is what lets the startup reconciler terminate partial creations). | F3 + injectable pour failure. | **must.**

### R4. `TestRetryHandler_InvalidGateConfig` — `retry_test.go:133` ⚠ ordering
- **Scenario:** F3(stopped) + `{convergence.gate_mode: invalid-mode}`.
- **Assertions:** error contains `invalid gate config`; **no new bead created** — only `source-1` and `wisp-iter-3` exist in the store.
- **⚠ ordering:** gate config is validated (`ParseGateConfig`, `gate.go:44–85`) **before** `createConvergenceBead` (`retry.go:56–65` precede `:69`) — validation failure must leave zero side effects. | **must.**

### R5. `TestRetryHandler_SourceNotTerminated` — `retry_test.go:154`
- **Scenario:** Fresh store; bead `active-1` `in_progress` with `{state: active, target: test-agent}`.
- **Assertions:** error contains `terminated`. | Retry precondition. | **must.**

### R6. `TestRetryHandler_SourceApproved` — `retry_test.go:173`
- **Scenario:** F3(`terminal_reason=approved`).
- **Assertions:** error contains `approved` AND `cannot be retried`. | I6 (approved is final — no resurrection). | **must.**

### R7. `TestRetryHandler_CopiesConfig` — `retry_test.go:188`
- **Scenario:** F3(`no_convergence`) + `{var.extra_var: extra_value}`; retry with max 10.
- **Assertions (new bead meta, exact values):** `formula == "test-formula"`; `target == "test-agent"`; `gate_mode == "condition"`; `gate_condition == "/path/to/gate.sh"`; `gate_timeout == "30s"`; `gate_timeout_action == "iterate"`; `city_path == "/home/test/city"`; `evaluate_prompt == "check the code"`; `max_iterations == "10"`; vars copied with prefix re-applied: `var.doc_path == "/docs/readme.md"`, `var.branch == "feature-x"`, `var.extra_var == "extra_value"` (`ExtractVars` strips `var.`, copy re-adds it — `template.go:43–51`, `retry.go:108–113`).
- **Note what is NOT copied:** `state`/`iteration`/`active_wisp`/`last_processed_wisp`/`terminal_*`/`gate_outcome*`/`agent_verdict*`. | **must.**

### R8. `TestRetryHandler_SetsRetrySource` — `retry_test.go:241`
- **Assertions:** new bead meta `convergence.retry_source == "source-1"`. | Lineage marker. | **must.**

### R9. `TestRetryHandler_EmitsCreatedEvent` — `retry_test.go:255`
- **Assertions:** `convergence.created` event with `beadID == NewBeadID`, `eventID == "converge:<NewBeadID>:created"`; payload: `formula == "test-formula"`, `target == "test-agent"`, `gate_mode == "condition"`, `max_iterations == 10` (int, from arg), `first_wisp_id == FirstWispID`, `retry_source` non-null `== "source-1"`.
- **Untested payload fields:** `title` (`"Retry of source-1"`, `retry.go:68`) and `rig`. | **must.**

**Retry write order for reference (gap RW-1 below; `retry.go:67–128`):** `createConvergenceBead` → `state=creating` → fixed metaWrites in slice order (`formula`, `target`, `gate_mode`, `gate_condition`, `gate_timeout`, `gate_timeout_action`, `max_iterations`, `city_path`, `rig`, `evaluate_prompt`, `retry_source`, `state=active`) → copy `var.*` → pour first wisp → `active_wisp` → `iteration=1` → emit `convergence.created`. ⚠ `state=active` lands **before** `active_wisp`/`iteration` — there is a crash window where state is active without an active wisp; gc's startup reconciler recovers it (ADR-0003 §recovery, `active → recover active wisp`).

---

## 7. Count summary

| File | Test functions | Cases (incl. table rows) | must | should | skip |
|---|---|---|---|---|---|
| `manual_test.go` | 21 | 21 | 21 | 0 | 0 |
| `trigger_test.go` | 8 | 11 (`TestParseTriggerConfig` = 4 rows) | 8 (11 cases) | 0 | 0 |
| `retry_test.go` | 9 | 9 | 9 | 0 | 0 |
| **Total** | **38** | **41** | **38 (41 cases)** | **0** | **0** |

Zero `should`/`skip` is deliberate: all 38 tests run against the in-memory fake store and fake emitter; none touches tmux, the controller loop, dolt, or real bd. The only external surface is `/bin/sh exit N` scripts in TR2/TR4/TR5 — that subprocess contract is itself ratified ported scope (ADR-0003 D3 "gates are user-authored scripts; the subprocess contract is the compatibility surface"), trivially portable via `Process.run`, so it does not demote those tests.

---

## 8. Coverage gaps — behaviors with NO test in these three files

The Dart suite should add tests for these (verify against `stop_test.go` / `reconcile_test.go` / `handler_test.go` before writing duplicates — items marked *(likely elsewhere)* may be covered there):

1. **G-APPROVE-1:** `ApproveHandler` with a non-empty `active_wisp` — event `wisp_id` prefers `active_wisp` over `last_processed_wisp` (`manual.go:51–57`); also approve's `iteration`/duration when active wisp is open.
2. **G-APPROVE-2 / G-STOP-1:** approve/stop with **empty** `last_processed_wisp` — the final dedup write is skipped entirely (`manual.go:105–109`, `manual.go:435–439`); write-ordering assertions need a variant for this path.
3. **G-STOP-2** *(likely elsewhere: `stop_test.go`)*: stop's drain path — active wisp already closed ⇒ routed through `HandleWispClosed` first; if drain terminates the loop, stop returns no-op `stopped` (`manual.go:271–314`).
4. **G-STOP-3** *(likely elsewhere)*: stop's force-close path — open active wisp force-closed with `CloseReasonManualSupersede`, synthetic `convergence.iteration` event (action `stopped`, TierCritical, before root close, `manual.go:382–399`), and `last_processed_wisp` repointed to the force-closed wisp (`manual.go:430–434`).
5. **G-STOP-4:** stop from `waiting_trigger` — accepted by the state guard (`manual.go:258`) but never exercised; the ADR T11 row says "any".
6. **G-STOP-5:** stop's unconditional verdict clear (Step 5, `manual.go:349–356`) is never asserted.
7. **G-STOP-6 / G-MAN-1:** missing/stale `active_wisp` recovery via `recoverCurrentActiveWisp` (`manual.go:447–519`) — `findByIdempotencyKey(lastIter+1)` path and best-open/best-closed scan path.
8. **G-ITER-1:** `IterateHandler` pour failure where the wisp WAS created — `findByIdempotencyKey` adoption recovery (`manual.go:168–175`). Same recovery in `advanceFromTrigger` (`trigger.go:136–143`).
9. **G-TRIG-1:** `HandleTrigger` on `waiting_trigger` with NO trigger configured — error `is in waiting_trigger but has no trigger configured` (`trigger.go:67–69`).
10. **G-TRIG-2:** trigger condition `timeout`/`error` outcomes (only exit 0/1 are tested); all non-`pass` outcomes must yield `skipped` + keep waiting (`trigger.go:96–99`).
11. **G-TRIG-3:** `trigger_advance` payload `actor == "controller"` (`trigger.go:166`) is never asserted; neither is `ActivateWisp` being called for the trigger-poured wisp (`trigger.go:144–146`) nor its failure path.
12. **G-TRIG-4:** `ParseTriggerConfig` with `trigger_condition` set but mode empty → valid `TriggerNone` (condition silently ignored).
13. **G-TRIG-5:** `TriggerConditionEnv` with absent/invalid `max_iterations` (→ `MaxIterations == 0`).
14. **G-RETRY-1 (RW-1):** retry write ordering (`state=creating` first; `state=active` before `active_wisp`/`iteration`) has no `writeLog` test, unlike approve/stop.
15. **G-RETRY-2:** `CreatedPayload.title == "Retry of <sourceBeadID>"` and `rig` propagation into the created event payload.
16. **G-RETRY-3:** retry of a retry — `retry_source` chaining (new bead points at the immediate source, not the original).
17. **G-ERR-1:** all handlers with a missing root bead (`getMetadata` → NotFound) — error wrapping contract.
18. **G-EVT-1:** emission **order** relative to `closeBead` (terminated before close; manual_approve/manual_stop after close) is a documented contract (`manual.go:78–102`) but tests only assert presence — the Dart suite should assert order.
19. **G-INV-7:** single-writer serialization (I7) is assumed by every handler (`handler.go:142–145`) and tested nowhere — the Dart reconciler loop needs its own per-bead serialization test.

---

## 9. Porting traps

The details most likely to be transcribed wrongly, ranked roughly by blast radius:

1. **`last_processed_wisp` is the commit point and is written LAST — but only by approve/stop/wisp-closed, NEVER by `IterateHandler`.** Iterate intentionally does not touch it (the new wisp hasn't been processed yet, `manual.go:117–123`). Adding the write "for symmetry" breaks I1 dedup. Also: the write is skipped when the value would be empty.
2. **Two different "iteration" meanings in results/events.** Approve/stop report the **current** derived count; iterate/trigger-advance report **next** (count + 1) and bake it into the event ID (`converge:<bead>:iter:<N>:manual_iterate` / `:trigger_advance`). Off-by-one here silently corrupts event dedup downstream.
3. **`IterateHandler` does NOT write `convergence.iteration`; `advanceFromTrigger` DOES** (`trigger.go:148`). This asymmetry is real and pinned by TR2 (`iteration == "1"` after trigger advance). The stored counter is self-healed later by `HandleWispClosed` step 3 (I4) — do not "fix" the asymmetry.
4. **`NullableString`: empty string → JSON `null`.** TR2 explicitly fails if `wisp_id` is `""` instead of null. In Dart use `String?` and map `''` → `null` at the payload boundary.
5. **Idempotent no-op vs wrong-state error both occur in `terminated`.** Approve on `terminated+approved` → silent no-op, NO event; approve on `terminated+<anything else>` → error. Same pattern for stop with `stopped`. Iterate has no no-op path at all.
6. **Verdict clearing has three different scoping rules:** iterate clears only when `agent_verdict_wisp == last_processed_wisp` and only AFTER a successful pour; stop clears unconditionally; `transitionToWaitingTrigger` clears when scoped to the closing wisp (`handler.go:587–596`). Collapsing these to one rule breaks M11/M12.
7. **Max-iteration checks use the DERIVED closed-children count** (`deriveIterationCount`, `handler.go:812–825`: children whose idempotency key starts with `converge:<root>:iter:` AND status `closed`), never the stored field. And `HandleTrigger`'s guard is `maxIter > 0 && next > maxIter` — max `0`/absent **disables** it (`trigger.go:89`).
8. **Trigger-gated loops skip the speculative pour entirely** (`handler.go:253`) — they don't pour-then-burn. TR8's `children == 1` assertion distinguishes these (a burn would still pass with a counting bug elsewhere; a pour-without-burn fails).
9. **The guard order in `HandleTrigger` is observable:** state guard → trigger parse → gate parse → derive count → max guard → env build → run condition. TR7 passes only because the max guard precedes script execution; reordering makes the test spawn a process and (worse) could pour an over-limit wisp on a fast `exit 0`.
10. **Cached gate replay (`gate_outcome_wisp == wispID`) bypasses the "condition mode requires a condition path" check** (`handler.go:233–242`). F4 has `gate_mode=condition` with no `gate_condition`; TR8 still succeeds. Validating gate config eagerly in the replay path breaks it.
11. **`ParseGateConfig` defaults** (`gate.go:44–85`): empty mode → `manual`; timeout default **5m** (`DefaultGateTimeout`); action default `iterate`; the **gate** timeout bounds the **trigger** condition too. Durations are Go duration strings (`30s`, `60s`) — Dart needs a Go-compatible duration parser for `DecodeDuration` (`metadata.go:165–174`).
12. **Retry: `max_iterations` comes from the operator argument, everything else from the source.** Copying the source's max (or taking formula/gate from args) inverts R2/R7. Gate config is validated **before** any bead is created (R4: zero side effects on invalid config).
13. **Retry rollback closes the orphan with `state=terminated` set FIRST**, then `closeBead` with the ≥20-char reason `convergence: retry-create rollback after error` — R3 checks both the status and the metadata state.
14. **Event emission straddles `closeBead`:** `convergence.terminated` BEFORE close (TierCritical, must be re-emittable on crash replay), `manual_approve`/`manual_stop` AFTER close (TierBestEffort). The Go tests only check presence; keep the order anyway — it is the crash-safety contract (I2's event half).
15. **`extractCommitKeys` filters the write log to a fixed 9-key set** (§2) while the "very last write" assertion runs against the RAW log. Mixing these up makes M5/M19 pass vacuously (e.g. a stray trailing `gate_*` write would escape the filtered check but must fail the raw last-write check).
16. **Fake-store semantics the tests silently rely on:** pour idempotency by key scan (otherwise I3 tests pass vacuously); children in insertion order with parent-added-first registration; `closeBead` stamping `close_reason` metadata; `getBead` errors wrapping a NotFound sentinel the handler can type-check (stop's recovery branches dispatch on it, `manual.go:273–288`); `findEvent` returning the FIRST match of a type.
17. **Error strings are conformance surface.** Tests substring-match exact fragments (§1.7) — keep wording, including `%q` quoting style around IDs/states if you want byte-identical messages, or at minimum preserve the asserted fragments.
18. **Actor formatting:** `operator:` + username concatenation happens inside the handlers — pass the bare username through APIs. Trigger advance is `controller`. The terminated payload's `final_status` is the literal `closed` always.
19. **`ParseIterationFromKey` uses the LAST `:iter:` occurrence** and accepts `0` — bead IDs containing `:iter:` are handled by the last-index rule; a first-index implementation diverges.
20. **`ArtifactDirFor` is a pure path join:** `<cityPath>/.gc/artifacts/<beadID>/iter-<N>` — no trailing slash guarantees; build with `path.join`, not string interpolation with separators.
