# Port spec — gc convergence handler (`handler.go`, the 9-step algorithm)

**Status:** extraction for M2 Track A/B/E (see `docs/M2-BUILD-ORDER.md`); spec for
ADR-0003 Decision 2 ("transition semantics and crash-safety invariants preserved verbatim").
**Source of truth (READ-ONLY, pinned on disk):**
`/Users/nico/development/com.gastownhall/gascity/internal/convergence/` — primarily
`handler.go`, with constants/helpers from `metadata.go`, `gate.go`, `hybrid.go`,
`trigger.go`, `events.go`, `template.go`, `condition.go`, and the operator terminal
paths from `manual.go`. Extracted 2026-06-12. All `file:line` references below are
relative to that directory.

This document is self-contained: a Dart implementer ports from it without reading the Go.
Where the ADR-0003 transition table or invariants 1–7 apply, the mapping is called out
inline as **[ADR row …]** / **[Inv N]**.

---

## 1. Concurrency precondition (Inv 7)

`Handler` assumes **single-writer-per-bead**: only one caller may run `HandleWispClosed`
(or any manual handler) for a given root bead at a time (`handler.go:143-145`). Metadata
is snapshot-read once at entry and treated as consistent for the whole call. Violating
this causes stale-read races. **[Inv 7: single writer per convergence bead — the
grid_reconciler event loop must serialize per-bead processing.]**

`Handler` fields (`handler.go:146-151`):

| Field | Type | Purpose |
|---|---|---|
| `Store` | `Store` | bead operations (§2) |
| `StorePath` | `string` | passed into gate `ConditionEnv.StorePath` |
| `Emitter` | `EventEmitter` | event sink; `nil` ⇒ all emits silently dropped (`handler.go:854-856`) |
| `Clock` | `func() time.Time` | injectable; defaults to `time.Now` (`handler.go:898-903`). The captured `now` is currently **unused** by every transition (parameters named `_ time.Time`) — vestigial, keep injectable for tests. |

---

## 2. The `Store` interface (`handler.go:67-114`)

```go
type Store interface {
    GetBead(id string) (BeadInfo, error)
    GetMetadata(id string) (map[string]string, error)
    SetMetadata(id, key, value string) error
    CloseBead(id, reason string) error
    DeleteBead(id string) error
    Children(parentID string) ([]BeadInfo, error)
    PourWisp(parentID, formula, idempotencyKey string, vars map[string]string, evaluatePrompt string) (string, error)
    PourSpeculativeWisp(parentID, formula, idempotencyKey string, vars map[string]string, evaluatePrompt string) (string, error)
    ActivateWisp(id string) error
    FindByIdempotencyKey(key string) (string, bool, error)
    CountActiveConvergenceLoops(targetAgent string) (int, error)
    CreateConvergenceBead(title string) (string, error)
}
```

Semantics, per method:

| Method | Semantics | Source |
|---|---|---|
| `GetBead(id)` | Returns `BeadInfo`. **Missing beads must be reported with an error that wraps `beads.ErrNotFound`** so recovery code (and `manual.go`'s `errors.Is` checks) can distinguish stale references from transient store failures. | `handler.go:70-73` |
| `GetMetadata(id)` | Returns **all** metadata of a bead as a string→string map. Absent key ⇒ absent from map (Go reads yield `""`). | `handler.go:75-76` |
| `SetMetadata(id, key, value)` | Writes a **single** key/value pair. Writing `""` is how fields are cleared. Each call is an independent durable write — the handler's write-ordering contract (Inv 2) is built on this granularity. | `handler.go:78-79` |
| `CloseBead(id, reason)` | Sets status to `"closed"` and stamps `reason` as the bead's `close_reason` metadata. **`reason` must be ≥ 20 chars** to satisfy bd's `validation.on-close=error` validator; use the `CloseReason*` constants (§4.8). | `handler.go:81-85`, `handler.go:41-55` |
| `DeleteBead(id)` | **Permanently removes** a bead. Used only to burn discarded speculative wisps so they are *not counted as completed iterations* (closing would corrupt the derived iteration count, Inv 4). | `handler.go:87-89` |
| `Children(parentID)` | Returns child beads of a parent (all statuses). | `handler.go:91-92` |
| `PourWisp(parent, formula, key, vars, evaluatePrompt)` | Creates a new convergence wisp (visible/assignable) with idempotency key `key`. **If a wisp with this key already exists, returns the existing wisp's ID** (Inv 3: idempotent re-pour). Returns the new/existing wisp ID. | `handler.go:94-96` |
| `PourSpeculativeWisp(…)` | Same, but creates a **hidden/unassigned** wisp that agents cannot pick up until `ActivateWisp` publishes it. | `handler.go:98-100` |
| `ActivateWisp(id)` | Publishes a previously speculative wisp for agent work. | `handler.go:102-103` |
| `FindByIdempotencyKey(key)` | Lookup wisp by idempotency key → `(id, found, err)`. Used as the recovery probe after a pour error (the pour may have succeeded despite the error). | `handler.go:105-106` |
| `CountActiveConvergenceLoops(targetAgent)` | Counts active convergence loops targeting `targetAgent`. Used by `CheckNestedConvergence` (`handler.go:953-967`: error only when `callingAgent == targetAgent` **and** count > 0 — self-targeting deadlock) and `CheckConcurrencyLimits` (`handler.go:976-986`: error when `count >= maxPerAgent`; city-wide `max_total` deliberately **not** enforced yet, `handler.go:971-975`). | `handler.go:108-110` |
| `CreateConvergenceBead(title)` | Creates a new convergence root bead, returns its ID. (Used by create flow, not by `HandleWispClosed`.) | `handler.go:112-113` |

`BeadInfo` (`handler.go:57-65`):

| Field | Type | Notes |
|---|---|---|
| `ID` | `string` | |
| `Status` | `string` | exactly `"open"`, `"in_progress"`, or `"closed"` |
| `ParentID` | `string` | |
| `IdempotencyKey` | `string` | |
| `CreatedAt` | `time.Time` | |
| `ClosedAt` | `time.Time` | **zero value if not closed** — Dart: nullable `DateTime?` |

`HandlerResult` (`handler.go:130-137`): `Action HandlerAction`, `Iteration int` (the
processed wisp's iteration from its key), `GateOutcome string`, `NextWispID string`
(populated only for `iterate`), `WaitingReason string` (populated only for
`waiting_manual`).

---

## 3. Idempotency keys (Inv 3)

### 3.1 `IdempotencyKeyPrefix(beadID)` (`handler.go:13-15`)

Returns the literal concatenation `` `"converge:" + beadID + ":iter:"` ``.
No escaping or validation of `beadID`.

### 3.2 `IdempotencyKey(beadID, iteration)` (`handler.go:19-21`)

Returns `` `fmt.Sprintf("converge:%s:iter:%d", beadID, iteration)` `` —
i.e. `converge:<bead-id>:iter:<N>`, `N` decimal, **1-based** (`handler.go:17-18`).
**[Inv 3: wisps poured with `converge:{beadID}:iter:{N}`.]**

### 3.3 `ParseIterationFromKey(key) → (int, bool)` (`handler.go:26-39`)

Exact rules — port these literally:

1. Find the **LAST** occurrence of the marker `` `":iter:"` `` in `key`
   (`strings.LastIndex`). Not found ⇒ return `(0, false)`.
2. Take the substring **after** that marker to end-of-string; parse with
   `strconv.Atoi` (Go base-10 integer: optional leading `+`/`-`, then digits only —
   **no whitespace, no hex, no underscores, no decimal point**).
3. Parse error **or `n < 0`** ⇒ return `(0, false)`.
4. Otherwise return `(n, true)`.

Edge cases (all load-bearing):

| Input | Result | Why |
|---|---|---|
| `converge:tg-abc:iter:3` | `(3, true)` | normal |
| `converge:a:b:c:iter:12` | `(12, true)` | bead IDs containing `:` are fine — only the **last** `:iter:` matters |
| `converge:a:iter:7:iter:3` | `(3, true)` | bead ID itself contains `:iter:7`; last marker wins |
| `foo:iter:5` | `(5, true)` | ⚠ the function does **not** verify the `converge:` prefix or the bead ID — any key containing `:iter:` parses |
| `converge:a:iter:` | `(0, false)` | empty number → Atoi error |
| `converge:a:iter:-1` | `(0, false)` | parses to −1, rejected by `n < 0` |
| `converge:a:iter:0` | `(0, true)` | ⚠ zero is **accepted** — and a 0-iteration wisp is then always skipped by dedup (§7 step 2, since `0 <= lastProcessedIteration`) |
| `converge:a:iter:+3` / `converge:a:iter:007` | `(3, true)` / `(7, true)` | Go `Atoi` accepts sign and leading zeros |
| `converge:a:iter: 3` / `converge:a:iter:0x3` / `converge:a:iter:3.0` | `(0, false)` | whitespace / hex / float all fail `Atoi` |
| no `:iter:` at all (e.g. `""`, `iter:3`) | `(0, false)` | marker requires both surrounding colons |

⚠ **Dart trap:** `int.parse`/`int.tryParse` are **not** equivalent to Go's `Atoi`:
Dart ignores leading/trailing whitespace and accepts `0x` hex prefixes. Guard with
`RegExp(r'^[+-]?[0-9]+$')` before parsing (or implement a strict digits parser) to
match Go exactly.

---

## 4. Constants and value domains

### 4.1 Metadata fields (`metadata.go:12-44`) — the `convergence.*` namespace

| Go const | Metadata key | Written by handler? |
|---|---|---|
| `FieldState` | `convergence.state` | yes (transitions) |
| `FieldIteration` | `convergence.iteration` | yes (step-3 repair; trigger advance) |
| `FieldMaxIterations` | `convergence.max_iterations` | read only |
| `FieldFormula` | `convergence.formula` | read only |
| `FieldTarget` | `convergence.target` | no (create-time) |
| `FieldGateMode` | `convergence.gate_mode` | read only |
| `FieldGateCondition` | `convergence.gate_condition` | read only |
| `FieldGateTimeout` | `convergence.gate_timeout` | read only (Go duration string, e.g. `5m`, `90s`) |
| `FieldGateTimeoutAction` | `convergence.gate_timeout_action` | read only |
| `FieldActiveWisp` | `convergence.active_wisp` | yes |
| `FieldLastProcessedWisp` | `convergence.last_processed_wisp` | yes — **the commit/dedup marker, always LAST** (Inv 2) |
| `FieldAgentVerdict` | `convergence.agent_verdict` | cleared by handler; set by the injected evaluate step |
| `FieldAgentVerdictWisp` | `convergence.agent_verdict_wisp` | cleared by handler (scopes the verdict to one wisp) |
| `FieldGateOutcome` | `convergence.gate_outcome` | yes (step 5) |
| `FieldGateExitCode` | `convergence.gate_exit_code` | yes (step 5; `""` when nil) |
| `FieldGateOutcomeWisp` | `convergence.gate_outcome_wisp` | yes — **last write of gate persistence** (Inv 2) |
| `FieldGateRetryCount` | `convergence.gate_retry_count` | yes (step 5) |
| `FieldTerminalReason` | `convergence.terminal_reason` | yes (terminal) |
| `FieldTerminalActor` | `convergence.terminal_actor` | yes (terminal) |
| `FieldWaitingReason` | `convergence.waiting_reason` | yes (waiting_manual; cleared by operator paths) |
| `FieldRetrySource` | `convergence.retry_source` | no (create-time) |
| `FieldCityPath` | `convergence.city_path` | read only (set during create) |
| `FieldRig` | `convergence.rig` | read only (event enrichment, §8.5) |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` | read only |
| `FieldGateStdout` | `convergence.gate_stdout` | yes (step 5) |
| `FieldGateStderr` | `convergence.gate_stderr` | yes (step 5) |
| `FieldGateDurationMs` | `convergence.gate_duration_ms` | yes (step 5; decimal ms) |
| `FieldGateTruncated` | `convergence.gate_truncated` | yes (step 5; `"true"` or `""`) |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` | yes (speculative-pour tracking, Inv 5) |
| `FieldTrigger` | `convergence.trigger` | read only |
| `FieldTriggerCondition` | `convergence.trigger_condition` | read only |

Plus `VarPrefix = "var."` (`metadata.go:47`): every metadata key with that prefix is a
template variable; `ExtractVars(meta)` (`template.go:43-51`) strips the prefix and
returns the map passed to pours.

### 4.2 States — `convergence.state` (`metadata.go:50-56`)

`"creating"` · `"active"` · `"waiting_manual"` · `"waiting_trigger"` · `"terminated"`
(ADR-0003 freezed enum: `creating`, `active`, `waitingManual`, `waitingTrigger`,
`terminated`).

### 4.3 Gate modes — `convergence.gate_mode` (`metadata.go:65-70`)

`"manual"` · `"condition"` · `"hybrid"`. Empty ⇒ defaults to `"manual"`
(`gate.go:45-48`); anything else ⇒ `ParseGateConfig` error.

### 4.4 Timeout actions — `convergence.gate_timeout_action` (`metadata.go:72-78`)

`"iterate"` (default, `gate.go:69`) · `"retry"` (≤ `MaxGateRetries = 3`, `gate.go:14`) ·
`"manual"` · `"terminate"`. Invalid non-empty value ⇒ `ParseGateConfig` error.
Default timeout `DefaultGateTimeout = 5m` (`gate.go:11`); configured timeout must
decode as a Go duration and be **> 0** (`gate.go:57-67`).

### 4.5 Terminal reasons — `convergence.terminal_reason` (`metadata.go:80-86`)

`"approved"` · `"no_convergence"` · `"stopped"` · `"partial_creation"` (the last is
reconcile-only, not produced by `handler.go`).

### 4.6 Gate outcomes — `convergence.gate_outcome` (`metadata.go:88-94`)

`"pass"` · `"fail"` · `"timeout"` · `"error"`.

### 4.7 Waiting reasons — `convergence.waiting_reason` (`metadata.go:96-102`)

`"manual"` · `"hybrid_no_condition"` · `"timeout"` · `"sling_failure"`.

### 4.8 Close reasons (`handler.go:46-55`) — all ≥ 20 chars by construction

| Const | Exact string | Used by |
|---|---|---|
| `CloseReasonCreateRollback` | `convergence: bead-create rollback after error` | create flow |
| `CloseReasonRetryRollback` | `convergence: retry-create rollback after error` | retry flow |
| `CloseReasonManualApprove` | `convergence: iteration closed by manual approve` | `ApproveHandler` |
| `CloseReasonManualSupersede` | `convergence: active wisp superseded during manual stop` | `StopHandler` force-close |
| `CloseReasonManualStop` | `convergence: iteration closed by manual stop` | `StopHandler` root close |
| `CloseReasonReconcileDone` | `convergence reconcile: terminated-state bead closed` | reconcile |
| `CloseReasonHandlerCleanup` | `convergence: terminated state observed; closing root` | step-1 guard |
| `CloseReasonHandlerRoot` | `convergence: workflow handler closing root after terminate` | `terminate()` |

### 4.9 Handler actions (`handler.go:120-128`)

`"iterate"` · `"approved"` · `"no_convergence"` · `"waiting_manual"` ·
`"waiting_trigger"` · `"stopped"` · `"skipped"` — exactly ADR-0003's sealed action
vocabulary.

### 4.10 Verdicts (`metadata.go:104-138`)

Normalized values: `"approve"` · `"approve-with-risks"` · `"block"`.
`NormalizeVerdict(raw)` (`metadata.go:124-138`): lowercase, trim whitespace;
empty ⇒ `"block"`; past-tense map (`metadata.go:113-119`):
`approved→approve`, `blocked→block`, `approve-with-risk→approve-with-risks`,
`approved-with-risks→approve-with-risks`, `approved-with-risk→approve-with-risks`;
the three canonical values pass through; **anything else ⇒ `"block"`**.

### 4.11 Int/duration codecs (`metadata.go:141-174`)

- `EncodeInt(n)` = decimal string. `DecodeInt(s) → (int, bool)`: empty or non-Atoi
  ⇒ `(0, false)` (⚠ same Dart `int.parse` caveats as §3.3).
- `DecodeDuration(s)`: Go `time.ParseDuration` syntax (`"300ms"`, `"5m"`, `"1h30m"`) —
  the Dart port needs a Go-duration parser, not ISO-8601.

### 4.12 Events (`events.go:11-81`)

| Event type (`event_type`) | Stable event ID | Tier |
|---|---|---|
| `convergence.created` | `converge:<bead>:created` | recoverable |
| `convergence.iteration` | `converge:<bead>:iter:<N>:iteration` (N = **the closing wisp's** iteration from its key, not the global counter, `events.go:42-46`) | critical (at-least-once; emitted before commit point, re-emitted on replay) |
| `convergence.terminated` | `converge:<bead>:terminated` | critical |
| `convergence.waiting_manual` | `converge:<bead>:iter:<N>:waiting_manual` | recoverable |
| `convergence.manual_approve` | `converge:<bead>:manual_approve` | best_effort (after close) |
| `convergence.manual_iterate` | `converge:<bead>:iter:<N>:manual_iterate` (N = **new** wisp's iteration) | recoverable |
| `convergence.manual_stop` | `converge:<bead>:manual_stop` | best_effort |
| `convergence.trigger_advance` | `converge:<bead>:iter:<N>:trigger_advance` (N = new wisp; deliberately distinct from the iteration ID to avoid collision, `events.go:74-81`) | — |

Payload structs: `events.go:84-158` (`CreatedPayload`, `GateResultPayload`,
`IterationPayload`, `TerminatedPayload`, `WaitingManualPayload`, `ManualActionPayload`).
JSON field names are in the struct tags; nullable fields use pointers
(`NullableString`, `events.go:186-191`: `nil` iff empty string).
`GateResultToPayload` (`events.go:195-206`) returns **`nil` when `Outcome == ""`**
(manual mode / no gate ran), else `{exit_code, stdout, stderr, duration_ms, truncated}`.

---

## 5. Helper algorithms (used by the 9 steps)

### 5.1 `deriveIterationCount(rootBeadID)` (`handler.go:812-825`) — **[Inv 4]**

```
children = Store.Children(root)            // error → propagate
prefix   = IdempotencyKeyPrefix(root)      // "converge:<root>:iter:"
count    = # of children where child.IdempotencyKey startsWith prefix
                               AND child.Status == "closed"
```

The count of **closed** convergence-keyed children IS the iteration number's source of
truth. Open/speculative wisps don't count; burned (deleted) wisps can't count — that is
why discarded speculative wisps are `DeleteBead`-ed, never closed (`handler.go:87-89`).
⚠ Note the asymmetry with §3.3: this check requires the full per-root prefix, while
`ParseIterationFromKey` accepts any `:iter:`-bearing key.

### 5.2 `computeDurations(rootBeadID, wispID)` (`handler.go:829-850`)

Best-effort, never errors:
- `iterDur` = `wisp.ClosedAt − wisp.CreatedAt` if `wispID != ""`, `GetBead` succeeds,
  and both timestamps are non-zero; else 0.
- `cumDur` = Σ over children with the convergence prefix, `Status == "closed"`, and
  both timestamps non-zero, of `ClosedAt − CreatedAt`. `Children` error ⇒ `(iterDur, 0)`.

### 5.3 `validPendingNextWisp(rootBeadID, nextKey, pendingID)` (`handler.go:935-945`) — **[Inv 5]**

```
if pendingID == "": return ""
info = Store.GetBead(pendingID)
if error  OR  info.ParentID != root  OR  info.IdempotencyKey != nextKey
          OR  info.Status == "closed":
    SetMetadata(root, "convergence.pending_next_wisp", "")   // best-effort self-heal
    return ""
return pendingID
```

This both validates the recorded speculative wisp **and self-heals** a stale
`pending_next_wisp` pointer by clearing it.

### 5.4 `burnSpeculativeWisp(rootBeadID, speculativeWispID)` (`handler.go:908-917`) — **[Inv 5]**

```
if speculativeWispID == "": return nil          // ⚠ no metadata clear in this case
deleteBeadSubtree(speculativeWispID)            // error → propagate
SetMetadata(root, "convergence.pending_next_wisp", "")   // best-effort, error IGNORED
```

`deleteBeadSubtree` (`handler.go:919-933`): recursive depth-first **post-order** —
delete all children's subtrees first, then `DeleteBead(id)`; any error aborts.

### 5.5 Event emission (`handler.go:853-895`)

`emitEvent(eventType, eventID, beadID, payload)`: no-op when `Emitter == nil`;
otherwise wraps `Emitter.Emit(eventType, eventID, beadID, MarshalPayload(...), false)`
(`recovery=false`). Before marshalling, `withEventRig` enriches known payload types
with `Rig` read via a **fresh `Store.GetMetadata(beadID)`** of `convergence.rig`
(`handler.go:886-895`) — one extra store read per emit; errors degrade to no rig.

---

## 6. `HandleWispClosed(ctx, rootBeadID, wispID)` — the 9-step algorithm (`handler.go:161-390`)

Inputs: `rootBeadID` (convergence root), `wispID` (the wisp that just closed).
Output: `(HandlerResult, error)`. Any non-nil error leaves
`convergence.last_processed_wisp` **unwritten**, so the same closure is re-processed on
retry/recovery — that re-processing must be safe, which is what steps 2/3b/4/5 buy.

### Step 0 — snapshot (lines 162–168)

1. `now = clock()` (currently unused downstream).
2. `meta = Store.GetMetadata(rootBeadID)`; error ⇒ return error
   (`"reading root bead metadata: …"`).
   ⚠ `meta` is the **single snapshot** used by all later reads in this call —
   transitions intentionally read the verdict from this snapshot even after clearing it
   in the store (§7.2, §7.3).

### Step 1 — guard (lines 170–175) — **[Inv 6; ADR row: any later event after terminal ⇒ `skipped`]**

- `state = meta["convergence.state"]`.
- If `state == "terminated"`:
  - best-effort `Store.CloseBead(rootBeadID, CloseReasonHandlerCleanup)` —
    **error ignored** (cleanup for a terminated-but-open root);
  - return `{Action: skipped}`, nil.

### Step 2 — monotonic dedup (lines 177–201) — **[Inv 1]**

1. `wispInfo = Store.GetBead(wispID)`; error ⇒ **hard error** (`"reading wisp info: …"`).
2. `wispIteration = ParseIterationFromKey(wispInfo.IdempotencyKey)`; not ok ⇒ **hard
   error** `"parsing iteration from wisp key %q"`.
3. `lastProcessedIteration = 0`. If `meta["convergence.last_processed_wisp"]` is
   non-empty:
   - `lpwInfo = Store.GetBead(lpw)`;
   - on **any** error: graceful degradation — keep `lastProcessedIteration = 0` so the
     loop continues instead of permanently blocking (lines 190–194);
   - else if its key parses: `lastProcessedIteration = n` (a non-parsing key also
     degrades to 0).
4. **If `wispIteration <= lastProcessedIteration` ⇒ return `{Action: skipped}`, nil.**
   Strictly monotonic: equal ⇒ duplicate delivery; lower ⇒ stale replay. This is the
   idempotency backbone: because `last_processed_wisp` is written LAST in every
   transition (Inv 2), a crash mid-transition re-enters here and is *not* skipped.

### Step 3 — derive iteration + self-healing repair (lines 203–216) — **[Inv 4]**

1. `globalIteration = deriveIterationCount(rootBeadID)` (§5.1); error ⇒ return error.
   Note: the just-closed wisp **is** closed, so it is included in this count.
2. `storedIteration, _ = DecodeInt(meta["convergence.iteration"])` (missing/invalid ⇒ 0).
3. If `globalIteration != storedIteration`: **repair** —
   `SetMetadata(root, "convergence.iteration", EncodeInt(globalIteration))`;
   error ⇒ return error. (Go logs a warning conceptually; derived value always wins.)
4. `maxIterations, _ = DecodeInt(meta["convergence.max_iterations"])` — ok-flag
   **ignored**; missing/invalid ⇒ `0` (consequences in §11 traps).

Two iteration numbers now coexist — do not conflate them:
- `wispIteration` (from the closing wisp's key) drives dedup, `nextIteration`,
  the max-iterations terminal check, and all event IDs/payloads for this iteration.
- `globalIteration` (derived count) drives the stored-field repair and
  `TerminatedPayload.TotalIterations`.

### Step 3a — config parsing, *before* any speculative work (lines 218–242)

⚠ ordering: both parses happen **before** the speculative pour so invalid config never
leaks a successor wisp (comment, lines 218–219).

1. `gateConfig = ParseGateConfig(meta)` (`gate.go:44-85`); error ⇒ return error.
2. `triggerConfig = ParseTriggerConfig(meta)` (`trigger.go:26-41`): mode
   `""` ⇒ none; `"event"` requires non-empty `convergence.trigger_condition` else
   error; any other mode ⇒ error. `Enabled() == (Mode == "event")` (`trigger.go:19-21`).
3. `nextIteration = wispIteration + 1`; `nextKey = IdempotencyKey(root, nextIteration)`.
4. `gateOutcomeWisp = meta["convergence.gate_outcome_wisp"]`;
   **`skipGateEval = (gateOutcomeWisp == wispID)`** — the gate-replay marker (Inv 2).
5. Misconfiguration check (lines 235–242): if `!skipGateEval` and
   `gateConfig.Mode == "condition"` and `gateConfig.Condition == ""`:
   - `pending = validPendingNextWisp(root, nextKey, meta["convergence.pending_next_wisp"])`;
     if non-empty, burn it (burn error is joined into the returned error);
   - return error `` `gate mode is "condition" but no condition path configured` ``.

### Step 3b — speculative pour (lines 244–275) — **[Inv 5]**

Purpose: pour the next wisp **before** gate evaluation so a crash between gate eval and
commit cannot break the chain (doc comment, lines 156–160 and 244–246).

1. `speculativeWispID = validPendingNextWisp(root, nextKey, meta["convergence.pending_next_wisp"])`
   — crash recovery: adopt a wisp poured by a previous attempt (§5.3 self-heals stale
   pointers).
2. `needsManualWithoutGate = (Mode == "manual") || (Mode == "hybrid" && HybridNeedsManual(gateConfig))`
   where `HybridNeedsManual ≡ Condition == ""` (`hybrid.go:26-28`).
3. `skipSpeculativePour = needsManualWithoutGate || triggerConfig.Enabled()` —
   manual-bound paths burn it deterministically and trigger-gated loops defer the pour
   to `HandleTrigger`, so neither pours (lines 249–253).
4. **Pour iff** `wispIteration < maxIterations && !skipSpeculativePour && speculativeWispID == ""`:
   - `formula = meta["convergence.formula"]`; `vars = ExtractVars(meta)` (§4.1);
     `evaluatePrompt = meta["convergence.evaluate_prompt"]`;
   - `speculativeWispID = Store.PourSpeculativeWisp(root, formula, nextKey, vars, evaluatePrompt)`;
   - on pour error: probe `Store.FindByIdempotencyKey(nextKey)`; if `lookupErr == nil && found`
     ⇒ adopt `existingID`; **else stash the error in `speculativePourErr` and continue**
     — the failure is deferred to step 7 (it only matters if the outcome is
     non-terminal).
5. If `speculativeWispID != ""`:
   - ⚠ ordering: **immediately** `SetMetadata(root, "convergence.pending_next_wisp", speculativeWispID)`
     — the recovery pointer must be durable before the gate runs;
   - if that write errors: burn the speculative wisp (burn error joined), return error
     (`"setting pending next wisp: …"`).

### Step 4 — gate evaluation, idempotent (lines 277–328)

**Replay branch** (`skipGateEval == true`, lines 280–298): reconstruct `GateResult`
purely from the snapshot — no re-execution:

| `GateResult` field | From metadata |
|---|---|
| `Outcome` | `convergence.gate_outcome` |
| `ExitCode` | `convergence.gate_exit_code` if non-empty **and** `DecodeInt` ok, else nil |
| `RetryCount` | `convergence.gate_retry_count` via `DecodeInt` (invalid ⇒ 0) |
| `Stdout` / `Stderr` | `convergence.gate_stdout` / `convergence.gate_stderr` |
| `Duration` | `convergence.gate_duration_ms` (if non-empty and `DecodeInt` ok) × 1ms |
| `Truncated` | `convergence.gate_truncated == "true"` (exact string compare) |

**Fresh branch** (lines 299–328), in this order:

1. **Manual mode** (`Mode == "manual"`, lines 301–307): burn speculative wisp (always
   `""` here given step 3b skip, but the call is made; burn error ⇒ return error), then
   `transitionToWaitingManual(reason = "manual", gateResult = zero, gateOutcome = "")`
   (§7.1). **[ADR row: active / wisp closed / gate_mode=manual → waitingManual]**
2. **Hybrid without condition** (lines 310–316): same, with
   `reason = "hybrid_no_condition"`. **[same ADR row — hybrid falls back to manual]**
3. **Verdict read, wisp-scoped** (lines 318–324):
   `verdict = NormalizeVerdict(meta["convergence.agent_verdict"])` **iff**
   `meta["convergence.agent_verdict_wisp"] == wispID`; otherwise
   `verdict = "block"` (no verdict, or verdict left over from another wisp).
4. `gateResult = evaluateGate(ctx, gateConfig, meta, wispID, wispIteration, verdict, rootBeadID)`
   (§8).

### Step 5 — persist gate outcome (lines 330–338) — **[Inv 2, gate half]**

Only when `!skipGateEval`. `persistGateOutcome(root, wispID, gateResult)`
(`handler.go:776-808`) writes, **in this exact order**, aborting on first error:

⚠ ordering — gate persistence sequence:
1. `convergence.gate_outcome` ← `result.Outcome`
2. `convergence.gate_exit_code` ← `EncodeInt(*ExitCode)`, or `""` if `ExitCode == nil`
3. `convergence.gate_retry_count` ← `EncodeInt(RetryCount)`
4. `convergence.gate_stdout` ← `Stdout`
5. `convergence.gate_stderr` ← `Stderr`
6. `convergence.gate_duration_ms` ← decimal `Duration.Milliseconds()`
7. `convergence.gate_truncated` ← `"true"` if `Truncated` else `""`
8. **`convergence.gate_outcome_wisp` ← `wispID` — LAST.** This is the gate idempotency
   marker: a crash before write 8 ⇒ re-processing re-runs the gate; after write 8 ⇒
   re-processing replays the persisted result (step 3a.4 / step 4 replay branch).

On any persist error: burn the speculative wisp (burn error joined) and return error
(`"persisting gate outcome: …"`).

### Step 6 — iteration note (lines 340–341)

Audit-trail note; **informational only — errors must not block control flow**. In the
current Go source this step is a comment with no operation; port as a hook point.

### Step 7 — prepare outcome (lines 343–389)

Evaluation order matters; check in this exact order:

1. **Timeout→manual** (lines 345–351): if `gateResult.Outcome == "timeout"` and
   `gateConfig.TimeoutAction == "manual"`: burn speculative wisp (error ⇒ return error),
   then `transitionToWaitingManual(reason = "timeout", gateOutcome = gateResult.Outcome)`.
   **[ADR row: active / wisp closed / timeout ∧ action=manual → waitingManual]**
2. **Terminal determination** (lines 354–368) — first match wins:
   - `Outcome == "pass"` ⇒ terminal, `terminalReason = "approved"`.
     **[ADR row: gate=pass → terminated / `approved`]**
   - `Outcome == "timeout" && TimeoutAction == "terminate"` ⇒ terminal,
     `terminalReason = "no_convergence"`.
     **[ADR row: timeout ∧ action=terminate → terminated / `noConvergence`]**
   - `wispIteration >= maxIterations` ⇒ terminal, `terminalReason = "no_convergence"`
     (any non-pass outcome at the cap, including `fail`, `error`, and `timeout` with
     action `iterate`/`retry`).
     **[ADR row: iter≥max ∧ gate≠pass → terminated / `noConvergence`]**
3. **Non-terminal** (lines 370–382), again in order:
   - `speculativePourErr != nil` ⇒ `handleSlingFailure` (`handler.go:714-726`) ⇒
     `transitionToWaitingManual(reason = "sling_failure", gateOutcome = gateResult.Outcome)`.
     ⚠ This row is **not** in ADR-0003's table — PourWisp/PourSpeculativeWisp failure is
     an extra `active → waitingManual` transition with `waiting_reason=sling_failure`.
   - `triggerConfig.Enabled()` ⇒ `transitionToWaitingTrigger` (§7.3).
     **[ADR row: trigger enabled → waitingTrigger]**
   - else ⇒ `iterate(…, speculativeWispID)` (§7.2).
     **[ADR row: gate=fail ∧ iter<max → active / `iterate`]** (also covers
     `error`, and `timeout` with action `iterate` or exhausted `retry`, below max.)
4. **Terminal** (lines 384–389): burn the speculative wisp (error ⇒ return error), then
   `terminate(root, wispID, wispIteration, gateConfig, gateResult, terminalReason,
   "controller", globalIteration, meta, now)` (§7.4).

Steps 8 (event emission) and 9 (commit point) live inside each transition subroutine —
see §7. ⚠ ordering, global rule: **step-8 events are emitted BEFORE the step-9 metadata
writes** (TierCritical at-least-once: a crash after emit but before commit re-emits the
same stable event ID on replay; consumers dedup by event ID).

---

## 7. Transition subroutines — exact write sequences (Inv 2)

Every sequence below is a strictly ordered list of store calls; abort-and-return-error
on the first failure unless marked best-effort. **`convergence.last_processed_wisp` is
written LAST in every transition — it IS the commit point [Inv 2].**

### 7.1 `transitionToWaitingManual` (`handler.go:394-475`)

Callers: manual mode (reason `manual`), hybrid-no-condition (`hybrid_no_condition`),
timeout-with-manual-action (`timeout`), sling failure (`sling_failure`). The
speculative wisp is **already burned** by every caller before entry.

1. Compute `iterDur, cumDur = computeDurations(root, wispID)`.
2. Verdict for payloads: from the **snapshot**, scoped
   (`meta["convergence.agent_verdict_wisp"] == wispID` ⇒ normalize, else `""`).
   ⚠ Note: waiting_manual does **not** clear the verdict — it must survive for the
   operator/hybrid decision.
3. **Step 8** — emit `convergence.iteration`
   (ID `converge:<root>:iter:<wispIteration>:iteration`) with
   `Action="waiting_manual"`, `WaitingReason=reason` (nullable), `GateOutcome` nullable
   (nil for pure manual/hybrid-no-condition where `gateOutcome==""`), `GateResult` via
   `GateResultToPayload` (nil when no gate ran).
4. **Step 9 — commit point, ⚠ ordering:**
   1. `convergence.active_wisp` ← `""`
   2. `convergence.waiting_reason` ← `reason`
   3. `convergence.state` ← `"waiting_manual"`
   4. `convergence.last_processed_wisp` ← `wispID` — **LAST**
5. Emit `convergence.waiting_manual`
   (ID `converge:<root>:iter:<wispIteration>:waiting_manual`) — after the commit;
   recoverable tier.
6. Return `{Action: waiting_manual, Iteration: wispIteration, GateOutcome, WaitingReason: reason}`.

### 7.2 `iterate` (`handler.go:480-573`) — **[ADR row: → active / `iterate`]**

1. **Verdict clear, wisp-scoped, ⚠ ordering:** iff
   `meta["convergence.agent_verdict_wisp"] == wispID`:
   1. `convergence.agent_verdict` ← `""`
   2. `convergence.agent_verdict_wisp` ← `""`
2. Resolve next wisp (`nextIteration = wispIteration + 1`,
   `nextKey = IdempotencyKey(root, nextIteration)`):
   - if `speculativeWispID != ""` ⇒ adopt it;
   - else **fallback pour** `Store.PourWisp(root, formula, nextKey, vars, evaluatePrompt)`
     (Go comment: "e.g., at max iterations boundary or error", `handler.go:509` —
     defensive; in the current `HandleWispClosed` flow every non-terminal,
     non-manual, non-trigger path arrives with a non-empty `speculativeWispID`,
     but the fallback must be ported because the invariant is not locally provable);
     on error probe `FindByIdempotencyKey(nextKey)` — found ⇒ adopt,
     else ⇒ `handleSlingFailure` (⇒ waiting_manual, `sling_failure`).
3. `Store.ActivateWisp(nextWispID)`; error ⇒ return error (no commit — re-processed).
4. Compute durations; verdict for the payload re-read from the **snapshot** (still
   present there even though just cleared in the store — the event reports the verdict
   that was consumed).
5. **Step 8** — emit `convergence.iteration` with `Action="iterate"`,
   `NextWispID=nextWispID`, `GateOutcome=gateResult.Outcome` (nullable).
6. **Step 9 — commit point, ⚠ ordering:**
   1. `convergence.active_wisp` ← `nextWispID`
   2. `convergence.last_processed_wisp` ← `wispID` — **the dedup marker**
   3. `convergence.pending_next_wisp` ← `""` — **AFTER** the marker, **best-effort
      (error ignored)**; if it fails, `validPendingNextWisp` self-heals on the next
      entry (the stale pointer's `IdempotencyKey` won't match the new `nextKey`).
7. Return `{Action: iterate, Iteration: wispIteration, GateOutcome, NextWispID}`.

⚠ `iterate` does **not** write `convergence.state` (stays `"active"`) and does not
touch `convergence.waiting_reason`.

### 7.3 `transitionToWaitingTrigger` (`handler.go:580-635`) — **[ADR row: trigger enabled → waitingTrigger]**

1. **Verdict clear** — identical scoped two-write sequence as §7.2 step 1 (the gate
   already consumed it; it must not leak into the wisp `HandleTrigger` pours later).
2. Durations; payload verdict from the snapshot (same stale-snapshot semantics).
3. **Step 8** — emit `convergence.iteration` with `Action="waiting_trigger"`,
   `GateOutcome` nullable.
4. **Step 9 — commit point, ⚠ ordering:**
   1. `convergence.active_wisp` ← `""`
   2. `convergence.state` ← `"waiting_trigger"`
   3. `convergence.last_processed_wisp` ← `wispID` — **LAST**
5. Return `{Action: waiting_trigger, Iteration: wispIteration, GateOutcome}`.

⚠ No `waiting_reason` write, no speculative wisp involved (step 3b skipped the pour
for trigger-gated loops), no successor pour here — `HandleTrigger`
(`trigger.go:52-180`) pours when the trigger condition passes.

### 7.4 `terminate` (`handler.go:638-711`) — **[ADR rows: → terminated / `approved` and `noConvergence`; Inv 6]**

Inputs include `reason ∈ {"approved", "no_convergence"}`, `actor = "controller"`, and
`globalIteration` (the derived count from step 3). The action string **is** the reason.

1. Durations; payload verdict from the snapshot (scoped).
2. **Step 8** — emit `convergence.iteration`
   (ID `converge:<root>:iter:<wispIteration>:iteration`, `Action=reason`).
3. Emit `convergence.terminated` (ID `converge:<root>:terminated`) with payload
   `{terminal_reason: reason, total_iterations: globalIteration, final_status: "closed",
   actor: "controller", cumulative_duration_ms}`. ⚠ Both events fire **before** any
   terminal write — TierCritical at-least-once.
4. **Step 9 — commit point, ⚠ ordering (`handler.go:687-704`):**
   1. `convergence.terminal_reason` ← `reason`
   2. `convergence.terminal_actor` ← `"controller"`
   3. `convergence.state` ← `"terminated"`
   4. `Store.CloseBead(root, CloseReasonHandlerRoot)`
      (= `convergence: workflow handler closing root after terminate`)
   5. `convergence.last_processed_wisp` ← `wispID` — **LAST, written AFTER the close**
      (the store must accept metadata writes on a closed bead).
5. Return `{Action: reason, Iteration: wispIteration, GateOutcome}`.

⚠ `terminate` does **not** clear `convergence.waiting_reason` (contrast with the
operator paths, §9) and relies on the caller's `burnSpeculativeWisp` having already
cleared `pending_next_wisp` when a speculative wisp existed.

---

## 8. Gate evaluation — invocation and consumption

### 8.1 Invocation — `evaluateGate` (`handler.go:729-771`)

Called only on the fresh (non-replay) path, only for modes `condition` and `hybrid`
(manual and hybrid-no-condition return earlier in step 4):

1. `retryBudget = 3` (`MaxGateRetries`, `gate.go:14`) iff
   `gateConfig.TimeoutAction == "retry"`, else `0`.
2. Build `ConditionEnv` (`condition.go:57-73`):

   | Field | Value |
   |---|---|
   | `BeadID` | `rootBeadID` |
   | `Iteration` | `wispIteration` (the **closing** wisp's iteration) |
   | `CityPath` | `meta["convergence.city_path"]` |
   | `StorePath` | `h.StorePath` |
   | `WispID` | `wispID` |
   | `DocPath` | `meta["var.doc_path"]` |
   | `ArtifactDir` | `ArtifactDirFor(cityPath, root, wispIteration)` = `<cityPath>/.gc/artifacts/<beadID>/iter-<N>` (`template.go:23-25`) |
   | `IterationDurationMs` / `CumulativeDurationMs` | from `computeDurations(root, wispID)` |
   | `MaxIterations` | `DecodeInt(meta["convergence.max_iterations"])` |

   These surface to the script as `GC_BEAD_ID`, `GC_ITERATION`, `GC_WISP_ID`,
   `GC_ITERATION_DURATION_MS`, `GC_CUMULATIVE_DURATION_MS`, `GC_MAX_ITERATIONS`, and
   (when non-empty) `GC_DOC_PATH`, `GC_AGENT_VERDICT`, `GC_STORE_PATH`,
   `GC_ARTIFACT_DIR`, … (`condition.go:79-131`; full env contract is gate-runner scope,
   ADR-0003 Decision 3 / M2 Track D — not re-specified here).
3. Dispatch on mode (`handler.go:762-770`):
   - `"condition"` ⇒ `RunCondition(ctx, gateConfig.Condition, env, gateConfig.Timeout, retryBudget)`
     (`condition.go:269`).
   - `"hybrid"` ⇒ `EvaluateHybrid(ctx, gateConfig, env, verdict)` (`hybrid.go:8-22`):
     sets `env.AgentVerdict = verdict` (⇒ `GC_AGENT_VERDICT`), computes the same retry
     budget, runs `RunCondition`. (Its `HybridNeedsManual` branch returning
     `GateManualResult()` = `{Outcome: "pass"}` is unreachable from the handler — that
     case already transitioned in step 4.)
   - default ⇒ `GateResult{Outcome: "error", Stderr: "unexpected gate mode: " + mode}`
     (defensive; unreachable).

### 8.2 Consumption

The resulting `GateResult` is consumed in three places, in order: persisted verbatim to
metadata (step 5, §6), branched on in step 7 (`Outcome` × `TimeoutAction` ×
`wispIteration >= maxIterations`), and embedded in every step-8 event payload via
`GateResultToPayload` / `GateOutcome`. The verdict itself is **never reinterpreted** by
the handler — it only feeds the gate env and the event payloads (ADR-0003 Decision 3).

---

## 9. Terminal transitions — the three reasons

### 9.1 `approved` (controller) — `terminate` with `reason="approved"`, §7.4
**[ADR row: active / wisp closed / gate=pass → terminated / `approved`]**

### 9.2 `no_convergence` (controller) — `terminate` with `reason="no_convergence"`, §7.4
**[ADR rows: timeout∧terminate; iter≥max ∧ gate≠pass]**

### 9.3 `approved` (operator) — `ApproveHandler` (`manual.go:20-115`)
**[ADR row: waitingManual / operator approve → terminated / `approved`]**

Precondition: state `"waiting_manual"` (else error), idempotent no-op if already
`terminated` + `terminal_reason=approved`. `actor = "operator:" + username`.
`iterationCount = deriveIterationCount(beadID)`. Event wisp = `active_wisp` if
non-empty else `last_processed_wisp`.

⚠ ordering (`manual.go:62-109`):
1. `convergence.terminal_reason` ← `"approved"`
2. `convergence.terminal_actor` ← `"operator:<username>"`
3. `convergence.waiting_reason` ← `""`
4. `convergence.state` ← `"terminated"`
5. emit `convergence.terminated` — **BEFORE** `CloseBead` (TierCritical)
6. `CloseBead(beadID, CloseReasonManualApprove)`
7. emit `convergence.manual_approve` — **AFTER** `CloseBead` (TierBestEffort)
8. `convergence.last_processed_wisp` ← previous `last_processed_wisp` (re-write of the
   same value, only when non-empty) — **LAST** [Inv 2]

### 9.4 `stopped` (operator) — `StopHandler` (`manual.go:241-445`)
**[ADR row: any / operator stop → terminated / `stopped`]**

Precondition: state ∈ {`active`, `waiting_manual`, `waiting_trigger`} (else error);
idempotent no-op if already `terminated` + `terminal_reason=stopped`.

1. **Drain** (`manual.go:272-314`): if `active_wisp` is set and resolvable (with
   `recoverCurrentActiveWisp` fallback, `manual.go:447-519`, when `GetBead` wraps
   `ErrNotFound`) and **already closed**: run it through `HandleWispClosed` first
   (never discard a completed iteration), re-read metadata; if that drained the loop to
   `terminated` ⇒ return `{stopped}` no-op.
2. **Force-close** (`manual.go:316-340`): if an active wisp is still open:
   `CloseBead(activeWisp, CloseReasonManualSupersede)`; mark `forceClosedWisp`.
3. `iterationCount = deriveIterationCount(beadID)` — **after** the force-close so the
   count includes it.
4. **Unconditional stale-verdict clear** (`manual.go:351-356`), ⚠ ordering:
   `convergence.agent_verdict` ← `""`, then `convergence.agent_verdict_wisp` ← `""`
   (no wisp-scoping here, unlike §7.2).
5. ⚠ ordering (`manual.go:367-439`):
   1. `convergence.terminal_reason` ← `"stopped"`
   2. `convergence.terminal_actor` ← `"operator:<username>"`
   3. `convergence.waiting_reason` ← `""`
   4. `convergence.state` ← `"terminated"`
   5. if force-closed: emit synthetic `convergence.iteration`
      (ID `converge:<bead>:iter:<iterationCount>:iteration`, `Action="stopped"`,
      `WispID=activeWisp`, gate mode defaulted to `"manual"` when empty) —
      **BEFORE** `CloseBead` (TierCritical)
   6. emit `convergence.terminated` (`terminal_reason="stopped"`,
      `total_iterations=iterationCount`, `actor="operator:<username>"`) —
      **BEFORE** `CloseBead`
   7. `CloseBead(beadID, CloseReasonManualStop)`
   8. emit `convergence.manual_stop` — **AFTER** `CloseBead` (TierBestEffort)
   9. `convergence.last_processed_wisp` ← force-closed wisp if any, else previous
      `last_processed_wisp` (only when non-empty) — **LAST** [Inv 2]

(For completeness: the third operator verb, `IterateHandler` `manual.go:124-217`,
is non-terminal — pour-before-mutate, verdict clear scoped to `last_processed_wisp`,
clears `waiting_reason`, sets `state=active` and `active_wisp`, emits
`convergence.manual_iterate`, and deliberately does **not** write
`last_processed_wisp` — the new wisp hasn't been processed yet. **[ADR row:
waitingManual / operator iterate → active / `iterate`]**)

---

## 10. ADR-0003 mapping summary

| ADR-0003 transition row | Implemented at |
|---|---|
| active / wisp closed / gate=pass → terminated `approved` | §6 step 7.2 case 1 + §7.4 |
| active / wisp closed / gate=fail ∧ iter<max → active `iterate` | §6 step 7.3 + §7.2 |
| active / wisp closed / timeout ∧ action=manual → waitingManual | §6 step 7.1 + §7.1 |
| active / wisp closed / timeout ∧ action=terminate → terminated `noConvergence` | §6 step 7.2 case 2 + §7.4 |
| active / wisp closed / iter≥max ∧ gate≠pass → terminated `noConvergence` | §6 step 7.2 case 3 + §7.4 |
| active / wisp closed / trigger enabled → waitingTrigger | §6 step 7.3 + §7.3 |
| active / wisp closed / gate_mode=manual → waitingManual | §6 step 4.1–4.2 + §7.1 |
| waitingManual / operator approve → terminated `approved` | §9.3 (`manual.go`) |
| waitingManual / operator iterate → active `iterate` | §9.4 note (`manual.go:124-217`) |
| waitingTrigger / trigger passes → active `iterate` | `trigger.go:52-180` (separate spec) |
| any / operator stop → terminated `stopped` | §9.4 (`manual.go`) |
| creating / startup reconcile → terminated | `reconcile.go` (separate spec) |
| (terminal guard) any later event → `skipped` | §6 step 1 [Inv 6] |
| **Not in the ADR table:** active / wisp closed / pour failure → waitingManual (`waiting_reason=sling_failure`) | §6 step 7.3 + `handler.go:714-726` |

| Invariant | Where enforced |
|---|---|
| 1 — monotonic dedup | §6 step 2 |
| 2 — write ordering (`last_processed_wisp` LAST; `gate_outcome_wisp` last in gate persistence) | §6 step 5; §7.1–§7.4 step 9; §9.3/§9.4 |
| 3 — idempotency keys, re-pour returns existing | §3; pour-error → `FindByIdempotencyKey` probes (§6 step 3b.4, §7.2.2) |
| 4 — iteration derived from closed-wisp count, self-healing | §5.1; §6 step 3 |
| 5 — speculative pour before gate eval; burn; `pending_next_wisp` | §6 step 3b; §5.3/§5.4; §7.2 step 6.3 |
| 6 — terminal irreversibility | §6 step 1; §7.4 |
| 7 — single writer per bead | §1 |

---

## Porting traps

The details most likely to be transcribed wrongly, in rough order of blast radius:

1. **`last_processed_wisp` LAST — everywhere, including after `CloseBead`.** In
   `terminate` (§7.4) the marker is written *after* the root is closed
   (`handler.go:699-704`); the store adapter must support `SetMetadata` on a closed
   bead, and a `bd batch` port must preserve this ordering inside the batch.
2. **Burn = delete, never close.** Discarded speculative wisps go through
   `DeleteBead` (subtree, post-order). Closing one silently inflates
   `deriveIterationCount` and corrupts Inv 4 forever after.
3. **Go map vs Dart map.** Every `meta[Field]` read returns `""` for a missing key in
   Go. In Dart use `meta[key] ?? ''` uniformly — a `null` leaking into a `==`
   comparison flips guard logic (e.g. `state == StateTerminated`,
   `gateOutcomeWisp == wispID`).
4. **`int.parse` ≠ `strconv.Atoi`.** Dart accepts surrounding whitespace and `0x`
   prefixes; Go does not. Both `ParseIterationFromKey` (§3.3) and `DecodeInt` (§4.11)
   need a strict `^[+-]?[0-9]+$` guard. Also: iteration `0` parses as **valid**
   (`n < 0` is the only range check) and is then always deduped away.
5. **`LastIndex`, not `indexOf`.** `ParseIterationFromKey` finds the **last**
   `:iter:` — bead IDs containing `:` or even `:iter:` must keep working. And it does
   *not* validate the `converge:` prefix, whereas `deriveIterationCount` matches the
   full per-root prefix — don't "unify" them.
6. **Stale-snapshot verdict in event payloads.** `iterate` and
   `transitionToWaitingTrigger` clear the verdict in the **store**, then build the
   event payload from the original **snapshot** — the event intentionally reports the
   consumed verdict. A port that re-reads metadata after clearing emits empty verdicts.
7. **Verdict clear ordering and scoping.** Handler paths clear
   `agent_verdict` *then* `agent_verdict_wisp`, and only when
   `agent_verdict_wisp == wispID`. `StopHandler` clears unconditionally.
   `transitionToWaitingManual` clears **nothing** (the operator needs the verdict).
   An unscoped verdict (mismatched `agent_verdict_wisp`) is read as `"block"`, not as
   its raw value.
8. **Deferred speculative-pour failure.** A pour error at step 3b does **not** abort —
   it's stashed and only matters if the outcome is non-terminal
   (`sling_failure` → waiting_manual). Terminal outcomes ignore it entirely. Failing
   fast here changes observable behavior on pass/max-iteration paths.
9. **The misconfig burn.** `condition` mode with empty condition is a hard error, but
   *first* burns any valid pending speculative wisp (`handler.go:235-242`). Skipping
   the burn leaks a hidden wisp that a later recovery pass adopts.
10. **`gate_truncated` round-trip.** Written as `"true"` or `""` (never `"false"`);
    replay tests `== "true"` exactly. `gate_exit_code` is `""` (not `"0"`, not absent)
    when `ExitCode == nil`.
11. **Replay branch skips the manual checks.** When `gate_outcome_wisp == wispID`,
    step 4 jumps straight to the persisted result — it must *not* re-enter the
    manual/hybrid-no-condition branches, and step 5 must *not* re-persist.
12. **Missing `max_iterations` ⇒ `0`.** `DecodeInt`'s ok-flag is discarded
    (`handler.go:216`): no speculative pour ever (`wispIteration < 0` is false… i.e.
    `wispIteration < maxIterations` with `max=0` is false), and every non-pass outcome
    is immediately terminal `no_convergence` via `wispIteration >= maxIterations`.
    Don't "default" it to something sensible — gc doesn't.
13. **Best-effort writes that must stay best-effort.** Step-1 guard `CloseBead`
    (error ignored); `pending_next_wisp` clear in `burnSpeculativeWisp` and at the end
    of `iterate` (errors ignored, **after** the dedup marker); `computeDurations`
    (never errors). Promoting these to hard failures breaks crash-recovery paths that
    rely on the self-heal in `validPendingNextWisp`.
14. **Graceful degradation on a missing `last_processed_wisp` bead** — `GetBead`
    failure there means "treat as iteration 0 and continue" (`handler.go:189-198`),
    while the same failure on the *closing* wisp is a hard error. Inverting these
    either bricks loops or breaks dedup.
15. **Two iteration numbers.** `wispIteration` (key-derived) drives dedup,
    `nextIteration`, the max check, and the per-iteration event IDs;
    `globalIteration` (closed-child count) drives the stored-field repair and
    `TerminatedPayload.total_iterations`. Swapping them passes most happy-path tests
    and fails exactly the gap/recovery scenarios.
16. **Events before commit, with stable IDs.** Step-8 emits precede step-9 writes
    (at-least-once); `manual_approve`/`manual_stop` are emitted **after** `CloseBead`
    (best-effort). Event IDs are the literal `converge:…` formats of §4.12 —
    `trigger_advance` exists specifically because reusing the iteration event ID
    collides.
17. **Go duration strings.** `convergence.gate_timeout` is `time.ParseDuration` syntax
    (`5m`, `300ms`, `1h30m`), must be > 0, and defaults to 5m. `gate_duration_ms` is a
    plain decimal millisecond count. Two different encodings in the same namespace.
18. **`CloseBead` reasons ≥ 20 chars.** bd's `validation.on-close=error` rejects
    shorter reasons; always use the §4.8 constants verbatim.
19. **`BeadInfo.ClosedAt` zero-value semantics.** Go uses zero `time.Time` for
    "not closed"; duration math checks `!IsZero()` on **both** timestamps. Map to
    nullable `DateTime?` and keep both null-checks.
20. **`maxIterations` boundary uses the *closing* wisp's iteration** —
    `wispIteration >= maxIterations` (not `globalIteration`), and the speculative pour
    gate is `wispIteration < maxIterations`. Off-by-one here either pours an
    over-limit wisp or terminates one iteration early.
