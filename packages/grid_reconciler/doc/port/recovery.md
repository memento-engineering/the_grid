# Port spec — gc convergence recovery (`reconcile.go`, startup + backstop reconciliation)

**Status:** extraction for M2 Track C (recovery / full-reconcile pass, ⊣ A, B — see
`docs/M2-BUILD-ORDER.md`); spec for ADR-0003 Decision 2 ("Recovery paths (startup +
backstop, from `reconcile.go`)").
**Source of truth (READ-ONLY, pinned on disk):**
`/Users/nico/development/com.gastownhall/gascity/internal/convergence/` — primarily
`reconcile.go` (690 lines), with the replay/recovery helpers it calls in `handler.go`,
`manual.go`, `metadata.go`, `events.go`, `template.go`, and the controller entry points
in `cmd/gc/convergence_tick.go` + `cmd/gc/convergence_store.go`. Extracted 2026-06-12.
All `file:line` references are relative to `gascity/internal/convergence/` unless
prefixed with `cmd/gc/` or `internal/beads/`.

This document is self-contained: a Dart implementer ports from it without reading the Go.
Companion docs: `handler-9step.md` (the normal-path algorithm recovery replays into),
`metadata-keys.md` (full key schema), `conformance-reconcile-tests.md` (the transliterated
test suite that proves this spec).

---

## 1. Role and report types

`Reconciler` performs **startup reconciliation** for convergence beads that were
in-progress when the controller crashed: it inspects each bead's metadata, determines
which step of the convergence algorithm was interrupted, and completes or repairs the
state so normal processing can resume (`reconcile.go:27-34`). It holds exactly one field:

```go
type Reconciler struct {
    Handler *Handler // reuse the handler's Store and Emitter
}
```

It owns **no state of its own** — every read/write goes through `Handler.Store`, every
event through `Handler.Emitter`. Replays go through `Handler.HandleWispClosed`.

### 1.1 `ReconcileDetail` (`reconcile.go:13-17`)

| Field | Type | Domain |
|---|---|---|
| `BeadID` | `string` | the root convergence bead |
| `Action` | `string` | exactly one of `completed_terminal`, `adopted_wisp`, `poured_wisp`, `repaired_state`, `no_action` (`reconcile.go:15`) |
| `Error` | `error` | `nil` on success |

⚠ A detail may carry **both** a non-`no_action` action and a non-nil error — the action
then names the path that was *in flight* when the error hit, not a completed recovery.
E.g. `{Action: "adopted_wisp", Error: "setting active_wisp: …"}` (`reconcile.go:133-138`).

### 1.2 `ReconcileReport` (`reconcile.go:20-25`) and accounting

| Field | Meaning |
|---|---|
| `Scanned` | `len(beadIDs)` — set up front (`reconcile.go:44-46`) |
| `Recovered` | count of details with `Error == nil` **and** `Action != "no_action"` |
| `Errors` | count of details with `Error != nil` (regardless of action) |
| `Details` | one entry per bead, in input order |

⚠ The accounting is an `if/else if` (`reconcile.go:51-55`): an errored detail increments
`Errors` only, never `Recovered`, even if its action label is non-`no_action`.

### 1.3 `ReconcileBeads(ctx, beadIDs) → (ReconcileReport, error)` (`reconcile.go:43-59`)

- Iterates the IDs **in order**, calling `reconcileBead` for each.
- **Errors on individual beads never abort the scan** — they are captured in the detail
  and the loop continues (`reconcile.go:40-42`).
- The function's own `error` return is **always `nil`** in the current source. Keep the
  signature (callers check it) but know nothing produces it today.
- `reconcileBead` itself "never returns an error directly — errors are captured in the
  returned ReconcileDetail" (`reconcile.go:61-63`).

### 1.4 Concurrency precondition

The reconciler inherits the handler's **single-writer-per-bead** invariant (ADR-0003
invariant 7; `handler.go:143-145`). gc guarantees it by running both startup
reconciliation and tick processing on the same controller event loop. The Dart port must
serialize `reconcileBead` with all other per-bead processing (handler reduce, operator
commands) for the same root bead.

---

## 2. Entry points and cadence (gc → grid mapping)

### 2.1 Startup full reconcile (`cmd/gc/convergence_tick.go:536-609`)

Per scope (city/HQ store + each bound rig store), `convergenceStartupReconcileScope`:

1. Lists candidate beads: `scope.store.List(beads.ListQuery{Type: "convergence"})`
   (`cmd/gc/convergence_tick.go:569`). ⚠ `ListQuery.IncludeClosed` defaults to `false`
   (`internal/beads/query.go:82`), so the scan set is **all NON-closed beads of type
   `convergence`** — both `open` and `in_progress`. The doc comment on `ReconcileBeads`
   ("typically all beads whose status is `in_progress`", `reconcile.go:37-39`) is
   *narrower than the actual caller* — port the caller's behavior.
2. If the list is non-empty, runs `ReconcileBeads(ctx, beadIDs)` over **every** ID
   (`cmd/gc/convergence_tick.go:583-585`). Closed (fully terminated) roots never appear,
   so a clean store reconciles as all-`no_action`.
3. Prints `"Convergence recovery%s: %d scanned, %d recovered, %d errors\n"` only when
   `Recovered > 0 || Errors > 0` (`cmd/gc/convergence_tick.go:593-596`).
4. **Only after** reconciliation populates the in-memory active index
   (`cmd/gc/convergence_tick.go:599-608`) — the index holds beads whose state is
   `active`, `waiting_manual`, or `waiting_trigger` (`cmd/gc/convergence_store.go:36-53`).
   Normal tick processing reads only that index, so **no tick processing can race the
   startup pass**.
5. Failure handling: a List/Reconcile/populate failure sets
   `scope.needsStartupReconcile = true` and installs an **empty** active index
   (`cmd/gc/convergence_tick.go:573-575, 589-591, 604-606`); the controller keeps
   running. `convergenceStartupReconcile` retries once immediately when the first attempt
   **panicked** (`safeTick` returns `panicked bool`, `cmd/gc/city_runtime.go:764-778`)
   and the index is still nil (`cmd/gc/convergence_tick.go:546-548`); thereafter **every
   tick** re-attempts the startup reconcile at the top of `convergenceTickScope` and
   returns without processing anything until it succeeds
   (`cmd/gc/convergence_tick.go:250-255`).

### 2.2 Mid-tick single-bead reconcile (`cmd/gc/convergence_tick.go:289-307`)

During the normal tick, when a bead in state `active` has a non-empty
`convergence.active_wisp` and `GetBead(activeWisp)` fails with an error wrapping
`beads.ErrNotFound`, the tick constructs a fresh `Reconciler{Handler: scope.handler}` and
runs `ReconcileBeads(ctx, []string{beadID})` for just that bead. Any **other** store error
just skips the bead this tick (`cmd/gc/convergence_tick.go:292-294`). This is the
**backstop** cadence: recovery is not startup-only — a stale `active_wisp` pointer
(wisp deleted out from under the loop) is repaired live.

### 2.3 Grid mapping (ADR-0003 Decision 2)

`grid_reconciler` replays exactly these paths as (a) a startup pass over the
`GraphSnapshot` and (b) a low-frequency periodic backstop. The per-path logic below is
ported verbatim; only the *detection* of candidates moves from polling to the snapshot.
The pass is a pure function over `Store` — there is no time-based logic anywhere in
`reconcile.go`, so it is safe to run at any cadence as long as §1.4 holds.

---

## 3. Dispatch: `reconcileBead` (`reconcile.go:64-107`)

1. `meta := Store.GetMetadata(beadID)`. On error → detail
   `{Action: "no_action", Error: "reading metadata: …"}` (`reconcile.go:65-68`).
2. `state := meta["convergence.state"]` (absent key reads as `""`).
3. Switch on `state` — exact literals from `metadata.go:50-56`:

| `convergence.state` | Path | Function | §  |
|---|---|---|---|
| `""` (missing/empty) | 1a — loop never started or state write lost | `reconcileMissingState` | §4 |
| `creating` | 1b — creation interrupted; terminate partial bead | `reconcileCreating` | §5 |
| `terminated` | 2 — terminal transition started, `CloseBead` not reached | `reconcileTerminatedNotClosed` | §6 |
| `waiting_manual` | 3 — re-emit hold + repair markers | `reconcileWaitingManual` | §7 |
| `waiting_trigger` | 3t — no-op unless terminal | `reconcileWaitingTrigger` | §8 |
| `active` | 4 — recover/replay/pour | `reconcileActive` | §9 |
| anything else | — | detail `{Action: "no_action", Error: fmt.Errorf("unknown convergence state %q", state)}` (`reconcile.go:101-106`) |

---

## 4. Path 1a — state `""`: adopt or pour wisp 1 (`reconcile.go:111-206`)

**Trigger:** non-closed convergence bead whose `convergence.state` is absent or empty.

**Reads:** `FindByIdempotencyKey(IdempotencyKey(beadID, 1))` where
`IdempotencyKey(beadID, 1)` = `` `converge:<beadID>:iter:1` `` (`handler.go:19-21`);
on adopt additionally `GetBead(existingID)`; on pour `meta[convergence.formula]`,
`ExtractVars(meta)` (all `var.`-prefixed keys, prefix stripped — `template.go:43-51`),
`meta[convergence.evaluate_prompt]`.

### 4.1 Branch: iter-1 wisp EXISTS → adopt (`reconcile.go:123-171`)

`GetBead(existingID)` to learn its status (any error here → detail
`{Action: "adopted_wisp", Error: …}`). Then writes, **in this order** —

⚠ **ordering** (`reconcile.go:133-157`):

| # | Store call | Key | Value |
|---|---|---|---|
| 1 | `SetMetadata` | `convergence.active_wisp` | `existingID` |
| 2 | `SetMetadata` | `convergence.iteration` | `"1"` if wisp status == `closed`, else `"0"` |
| 3 | `SetMetadata` | `convergence.state` | `active` |

The iteration asymmetry is deliberate (`reconcile.go:140-145`): `1` when closed (we
*know* iteration 1 completed), `0` when still open (`HandleWispClosed` derives the real
count when the wisp closes). State is written **last** so a half-completed adopt re-enters
Path 1a, not Path 4.

4. If the adopted wisp's status is `closed`, **replay** the transition:
   `Handler.HandleWispClosed(ctx, beadID, existingID)` (`reconcile.go:159-168`) so the
   loop doesn't stall in `active` with a dead wisp. A replay error → detail
   `{Action: "adopted_wisp", Error: "replaying wisp_closed for adopted wisp %q: …"}`.
   The handler result is discarded.
5. Success detail: `{Action: "adopted_wisp"}`.

Note the status comparison is **exactly** `== "closed"`; `open` and `in_progress` are
both "still live, don't replay".

### 4.2 Branch: NO iter-1 wisp → pour first wisp (`reconcile.go:173-205`)

⚠ **ordering** (`reconcile.go:178-203`):

| # | Store call | Args / Key | Value |
|---|---|---|---|
| 1 | `PourWisp` | `(beadID, formula, "converge:<beadID>:iter:1", vars, evaluatePrompt)` | → `wispID` |
| 2 | `SetMetadata` | `convergence.active_wisp` | `wispID` |
| 3 | `SetMetadata` | `convergence.iteration` | `"0"` |
| 4 | `SetMetadata` | `convergence.state` | `active` |

⚠ Iteration is `"0"` — **not** 1 — because `convergence.iteration` counts *closed* wisps
(ADR-0003 invariant 4). Action: `poured_wisp` (also the action label on any error in this
branch). Note this pour uses `PourWisp` (visible immediately), **not**
`PourSpeculativeWisp`, and there is **no** `ActivateWisp` call here.

**Idempotency:** re-running lands in the adopt branch (the key lookup finds the wisp
poured last time); `PourWisp` itself returns the existing wisp on key collision
(`handler.go:94-96`). All metadata writes are absolute values, so repeats are no-ops.

**Events:** none emitted directly; the closed-wisp replay emits whatever
`HandleWispClosed` normally emits (**recovery flag = false** — see §11).

---

## 5. Path 1b — state `creating`: terminate partial creation (`reconcile.go:210-236`)

**Trigger:** `convergence.state == "creating"` — the create flow stamps `creating`
immediately after bead creation and flips to `active` only when fully wired
(`metadata.go:51`); seeing `creating` at reconcile time means creation was interrupted.

**Reads:** none beyond the dispatch metadata.

⚠ **ordering** (`reconcile.go:211-234`):

| # | Store call | Key / Arg | Value |
|---|---|---|---|
| 1 | `SetMetadata` | `convergence.terminal_reason` | `partial_creation` (`metadata.go:85`) |
| 2 | `SetMetadata` | `convergence.terminal_actor` | `recovery` |
| 3 | `SetMetadata` | `convergence.state` | `terminated` |
| 4 | `CloseBead` | reason = `convergence reconcile: terminated-state bead closed` (`CloseReasonReconcileDone`, `handler.go:52`) | |

Action: `completed_terminal` (success and every error in this path).

**Idempotency:** the write order makes a crash at any point recoverable: crash before
step 3 re-enters Path 1b (state still `creating`, rewrites identical values); crash after
step 3 but before step 4 re-enters **Path 2** (state `terminated`, bead open), which
finishes the close. After step 4 the bead is closed and falls out of the startup scan.

**Events:** none. (⚠ Unlike Path 2 / `completeTerminalTransition`, this path emits **no**
`convergence.terminated` event — a partial creation never announced itself, so there is
nothing to re-announce. If a crash lands it in Path 2 on the next pass, *that* path will
emit one with reason `partial_creation` read from metadata.)

---

## 6. Path 2 — state `terminated` but bead not closed (`reconcile.go:240-296`)

**Trigger:** `convergence.state == "terminated"` on a bead the scan still sees — the
terminal transition (handler `terminate`, stop flow, or Path 1b) wrote `state=terminated`
but crashed before `CloseBead`.

**Reads → guard:** `GetBead(beadID)` (error → `{Action: "no_action", Error: …}`). If
`Status == "closed"` → already fully terminated → `{Action: "no_action"}`, **no writes,
no events** (`reconcile.go:241-252`). This guard exists because the mid-tick entry (§2.2)
can hand the reconciler any bead and because the scan list may be stale.

Then, ⚠ **ordering** (`reconcile.go:254-295`):

| # | Operation | Detail |
|---|---|---|
| 1 | `backfillTerminalActor` (§10.2) | `SetMetadata(beadID, "convergence.terminal_actor", "recovery")` **only if** the metadata snapshot's value is empty; otherwise no write |
| 2 | derive `totalIterations` | `deriveIterationFromChildrenViaStore` (§10.3); its error is **discarded** (`_`), yielding 0 |
| 3 | resolve payload fields | `reason := meta[convergence.terminal_reason]`, defaulting to `no_convergence` if empty (`reconcile.go:266-269`); `actor := meta[convergence.terminal_actor]`, defaulting to `"recovery"` if empty (the just-backfilled value is *not* re-read — the snapshot is used) |
| 4 | `cumulativeDuration(beadID)` (§10.5) | best-effort, 0 on error |
| 5 | **EMIT** `convergence.terminated`, event ID `converge:<beadID>:terminated`, **recovery = true** | payload §11 |
| 6 | `CloseBead(beadID, CloseReasonReconcileDone)` | error → `{Action: "completed_terminal", Error: "closing bead: …"}` |

⚠ The event is emitted **before** the close — at-least-once delivery (TierCritical,
`events.go:24-27`): a crash between 5 and 6 re-emits on the next pass with the **same
stable event ID**, and consumers dedup on that ID. Do not reorder.

⚠ Note what this path does **not** write: no `state` write (already `terminated`), no
`last_processed_wisp` repair (contrast with `completeTerminalTransition`, §10.1).

Action: `completed_terminal`. **Idempotency:** once closed, the guard short-circuits to
`no_action` forever.

---

## 7. Path 3 — state `waiting_manual` (`reconcile.go:300-372`)

**Trigger:** `convergence.state == "waiting_manual"`. Dispatch on two metadata fields,
**in this priority order**:

### 7.1 Sub-path A — `convergence.terminal_reason` non-empty (`reconcile.go:306-308`)

A stop was requested while holding but the terminal transition didn't complete →
delegate to `completeTerminalTransition` (§10.1). Checked **before** `waiting_reason`.

### 7.2 Sub-path B — `convergence.waiting_reason` non-empty, no terminal reason (`reconcile.go:310-347`)

Genuine hold. Two jobs: re-announce the hold, then repair the dedup marker.

1. **Re-emit** `convergence.waiting_manual` (TierRecoverable — re-emitted on recovery so
   consumers learn of the hold even if the original event was lost, `reconcile.go:312-325`):
   - `iteration, _ := DecodeInt(meta["convergence.iteration"])` — ⚠ failure ignored;
     missing/invalid → `0` (`metadata.go:147-156`).
   - event ID `converge:<beadID>:iter:<iteration>:waiting_manual`
     (`events.go:49-51`), **recovery = true**.
   - payload (`WaitingManualPayload`, `events.go:134-145`): `Iteration` = decoded value;
     `WispID` = `meta["convergence.last_processed_wisp"]` — ⚠ the **pre-repair** value;
     `GateMode` = `meta["convergence.gate_mode"]`; `Reason` =
     `meta["convergence.waiting_reason"]`; `CumulativeDurationMs` =
     `cumulativeDuration(beadID)`. All other fields (`AgentVerdict`, `GateOutcome`,
     `GateResult`, `IterationDurationMs`) stay zero/null — recovery does **not**
     reconstruct them from the persisted gate metadata.
2. **Repair `last_processed_wisp`** (`reconcile.go:327-346`): `Children(beadID)` (error →
   `{Action: "no_action", Error: "listing children: …"}` — ⚠ but the event above was
   already emitted); `highestClosedWisp` (§10.4); if found **and**
   `meta["convergence.last_processed_wisp"] != highestWisp.ID` →
   `SetMetadata(beadID, "convergence.last_processed_wisp", highestWisp.ID)` →
   `{Action: "repaired_state"}`. Otherwise `{Action: "no_action"}`.

⚠ The event fires on **every** pass through sub-path B, even when the final action is
`no_action`. Its event ID is stable, so downstream dedup absorbs the repeats. Re-running
is otherwise idempotent: the repair converges after one write.

### 7.3 Sub-path C — neither field set: orphaned state (`reconcile.go:349-371`)

`Children(beadID)` (error → `{Action: "no_action", Error: …}`); if `highestClosedWisp`
finds any closed wisp → `SetMetadata(beadID, "convergence.waiting_reason", "manual")`
(`WaitManual`, `metadata.go:98`) → `{Action: "repaired_state"}` — putting the loop in a
known state so operator commands (`approve`/`iterate`/`stop`) behave. No closed wisps →
`{Action: "no_action"}`. **No event** in sub-path C.

**Interaction with normal processing:** a bead in `waiting_manual` is in the active index
but the tick skips it (`cmd/gc/convergence_tick.go:281-283` — only `active` beads with an
active wisp are processed; `waiting_manual` is indexed for `CountActiveConvergenceLoops`
only). The hold is exited solely by operator commands (`manual.go`), which is why the
repaired `last_processed_wisp` matters: `IterateHandler`/`ApproveHandler` key off it.

---

## 8. Path 3t — state `waiting_trigger` (`reconcile.go:376-385`)

**Trigger:** `convergence.state == "waiting_trigger"`.

- `meta["convergence.terminal_reason"]` non-empty → a stop requested while waiting
  crashed mid-transition → `completeTerminalTransition` (§10.1).
- Otherwise → `{Action: "no_action"}`, **no reads, no writes, no events**.

Rationale (`reconcile.go:92-94, 382-384`): while waiting on the trigger **no wisp is in
flight**, so there is nothing to recover; the controller tick re-evaluates the trigger
condition (`HandleTrigger`, `trigger.go:52-102`) every pass and pours the next wisp
itself when the condition exits 0 (its pour is crash-safe via the same idempotency key,
`trigger.go:125-143`). The reconciler must **never** pour a wisp for a trigger-gated
loop — that would bypass the trigger gate.

---

## 9. Path 4 — state `active` (`reconcile.go:389-539`)

**Trigger:** `convergence.state == "active"`.

### 9.1 Sub-path A — interrupted stop (`reconcile.go:392-394`)

`meta["convergence.terminal_reason"]` non-empty → `completeTerminalTransition` (§10.1).
Checked first, before any wisp inspection.

### 9.2 Sub-path B — `convergence.active_wisp` non-empty (`reconcile.go:396-473`)

1. `wispInfo := GetBead(activeWispID)`.
   - Error **not** wrapping `beads.ErrNotFound` → `{Action: "no_action", Error: …}` —
     transient store failures are *not* treated as a missing wisp (`reconcile.go:402-408`).
   - Error wrapping `ErrNotFound` (wisp deleted under the loop) → attempt
     `Handler.recoverCurrentActiveWisp(beadID, meta["convergence.last_processed_wisp"])`
     (§10.6, `manual.go:447-519`):
     - recover error → `{Action: "no_action", Error: …}`;
     - not found → set local `activeWispID = ""` and **fall through to §9.3** (rebuild
       the chain from surviving children — "stale recovery state",
       `reconcile.go:416-421`);
     - found → `activeWispID`/`wispInfo` become the recovered wisp;
       `recoveredActiveWisp = true`.
2. If a recovery happened: ⚠ `SetMetadata(beadID, "convergence.active_wisp",
   activeWispID)` is written **immediately, before** inspecting the wisp's status
   (`reconcile.go:428-435`); error → `{Action: "repaired_state", Error: …}`.
3. Switch on `wispInfo.Status` (`reconcile.go:436-471`):

| Status | Behavior |
|---|---|
| `open` or `in_progress` | Wisp still running — nothing to do. Action `no_action`, or `repaired_state` if the pointer was just recovered. |
| `closed` | If `meta["convergence.last_processed_wisp"] == activeWispID` (exact string equality) → already processed; the commit completed **because `last_processed_wisp` is always the last write** of every handler transition (write-ordering contract, `handler.go:438-441`) → `{Action: "no_action"}`. Otherwise → **replay**: `Handler.HandleWispClosed(ctx, beadID, activeWispID)`; error → `{Action: "repaired_state", Error: "replaying wisp_closed for %q: …"}`; success → `{Action: "repaired_state"}` (the `HandlerResult` is discarded). |
| anything else | `{Action: "no_action", Error: fmt.Errorf("active wisp %q has unexpected status %q", …)}` |

### 9.3 Sub-path B′ — `active_wisp` empty (or stale-and-unrecoverable): pour or adopt next (`reconcile.go:475-538`)

A handler transition cleared `active_wisp` (or it was stale) but crashed before pointing
it at the next wisp.

**Reads:** `Children(beadID)` (error → `{Action: "no_action", Error: …}`);
`closedIter := deriveIterationFromChildren(children, beadID)` (§10.3);
`nextIter := closedIter + 1`; `nextKey := IdempotencyKey(beadID, nextIter)` =
`` `converge:<beadID>:iter:<nextIter>` ``.

**Wisp selection — three-way, in priority order** (`reconcile.go:489-521`):

| Priority | Source | Action label |
|---|---|---|
| 1 | `Handler.validPendingNextWisp(beadID, nextKey, meta["convergence.pending_next_wisp"])` — the speculative wisp poured at handler step 3b. Valid iff `GetBead(pendingID)` succeeds **and** `ParentID == beadID` **and** `IdempotencyKey == nextKey` **and** `Status != "closed"`; an invalid pending value is **self-healed by clearing the metadata field** (`SetMetadata(beadID, "convergence.pending_next_wisp", "")`, error ignored) during the check (`handler.go:935-945`). ⚠ A "read" with a write side effect. | `adopted_wisp` |
| 2 | `FindByIdempotencyKey(nextKey)` — a wisp for the next iteration already exists (e.g. crash after pour, before `pending_next_wisp` was recorded). Lookup error → `{Action: "no_action", Error: "looking up next wisp: …"}`. | `adopted_wisp` |
| 3 | `PourWisp(beadID, meta[convergence.formula], nextKey, ExtractVars(meta), meta[convergence.evaluate_prompt])`. Pour error → `{Action: "poured_wisp", Error: "pouring wisp for iter %d: …"}` (⚠ no `FindByIdempotencyKey` retry here, unlike the handler's pour fallback). | `poured_wisp` |

Then, ⚠ **ordering** (`reconcile.go:523-536`):

| # | Store call | Key | Value |
|---|---|---|---|
| 1 | `ActivateWisp(wispID)` | — | publish (idempotent: may already be active when adopted via priority 2/3) |
| 2 | `SetMetadata` | `convergence.active_wisp` | `wispID` |
| 3 | `SetMetadata` | `convergence.pending_next_wisp` | `""` — **best-effort, error explicitly discarded** (`_ =`, `reconcile.go:536`) |

⚠ What this branch does **not** write: `convergence.iteration` is *not* updated (it
self-heals at handler step 3 on the next close), `convergence.state` is *not* rewritten
(already `active`), and `last_processed_wisp` is untouched.

**Idempotency of the whole path:** the closed-wisp replay is guarded twice — by the
`last_processed_wisp == activeWispID` short-circuit here and by `HandleWispClosed`'s own
monotonic dedup (step 2) plus the `gate_outcome_wisp` cached-gate replay (step 4); the
pour is guarded by the idempotency key (re-pour returns the existing wisp) and the
pending-wisp validation. Activating and pointing are absolute writes.

**Events:** none emitted directly; a replay emits the handler's normal events
(**recovery = false**).

---

## 10. Shared helpers

### 10.1 `completeTerminalTransition(beadID, meta)` (`reconcile.go:545-600`)

Finishes an interrupted terminal transition. Called by Path 3A (`waiting_manual` +
terminal reason), Path 3t (`waiting_trigger` + terminal reason), and Path 4A (`active` +
terminal reason). Always returns action `completed_terminal`.

⚠ **ordering** — this is the single most order-sensitive function in the file:

| # | Operation | Detail |
|---|---|---|
| 1 | `backfillTerminalActor` (§10.2) | write `convergence.terminal_actor` = `recovery` only if snapshot value empty |
| 2 | resolve payload | `reason := meta[convergence.terminal_reason]` (non-empty by precondition — **no** default applied here, unlike Path 2); `actor := meta[convergence.terminal_actor]` defaulting to `"recovery"` |
| 3 | `deriveIterationFromChildrenViaStore` (error discarded → 0) and `cumulativeDuration` | |
| 4 | **EMIT** `convergence.terminated`, ID `converge:<beadID>:terminated`, **recovery = true** | payload §11 |
| 5 | `SetMetadata` `convergence.state` = `terminated` — **only if** `meta[convergence.state] != "terminated"` (snapshot check, `reconcile.go:573-580`) | |
| 6 | `CloseBead(beadID, "convergence reconcile: terminated-state bead closed")` | |
| 7 | `SetMetadata` `convergence.last_processed_wisp` = `highestClosedWisp(Children(beadID)).ID` — only if `Children` succeeds and a closed wisp exists; **both errors discarded** (`reconcile.go:592-597`). Comment: "write ordering: always last". | |

⚠ `last_processed_wisp` after `CloseBead` mirrors the handler's `terminate`
(`handler.go:687-704`): the dedup marker is the final write of every terminal transition.
⚠ Event-before-state/close = at-least-once (same argument as §6). A crash after step 5
re-enters as **Path 2** on the next pass (state now `terminated`), which finishes the
close — that is why Path 2 exists.

### 10.2 `backfillTerminalActor(beadID, meta)` (`reconcile.go:604-609`)

If `meta["convergence.terminal_actor"] != ""` → no-op, return nil. Else
`SetMetadata(beadID, "convergence.terminal_actor", "recovery")`. ⚠ Never overwrites an
existing actor; and callers build payloads from the **snapshot**, so the freshly
backfilled value is not re-read (the payload fallback `actor = "recovery"` covers it).

### 10.3 `deriveIterationFromChildren(children, beadID)` (`reconcile.go:614-623`) / `…ViaStore` (`reconcile.go:656-662`)

Count of children where `strings.HasPrefix(child.IdempotencyKey,
"converge:<beadID>:iter:")` **and** `child.Status == "closed"`. ⚠ Prefix check only — no
iteration parse; same logic as `Handler.deriveIterationCount` (`handler.go:812-825`).
Burned speculative wisps were *deleted* (not closed) precisely so they never inflate this
count. `…ViaStore` fetches `Children` first and propagates its error (which every caller
in this file then discards).

### 10.4 `highestClosedWisp(children, beadID) → (BeadInfo, int, bool)` (`reconcile.go:627-652`)

Among children: keep those with the idempotency-key prefix, `Status == "closed"`, **and**
a parseable iteration (`ParseIterationFromKey` — last `":iter:"` marker, base-10, `n ≥ 0`;
see `handler-9step.md` §3.3). Return the one with the **highest** iteration, its
iteration, and `found`. Strictly-greater comparison from `bestIter = -1`, so iteration 0
keys are eligible and first-wins on (impossible-by-key-uniqueness) ties.

### 10.5 `cumulativeDuration(beadID) → int64` ms (`reconcile.go:666-680`)

`Children(beadID)`; on error return 0 (best-effort). Sum `ClosedAt − CreatedAt` in
milliseconds over children with the key prefix, `Status == "closed"`, **and both**
timestamps non-zero. No iteration parse.

### 10.6 `Handler.recoverCurrentActiveWisp(beadID, lastProcessedWisp)` (`manual.go:447-519`)

Finds the wisp that *should* be active when `active_wisp` points at a deleted bead.
Returns `(BeadInfo, found bool, err error)`.

1. `Children(beadID)` — error propagates.
2. If `lastProcessedWisp != ""`: `GetBead(lastProcessedWisp)`. Error wrapping
   `ErrNotFound` is tolerated (treated as "no anchor"); any other error propagates. If
   read and its key parses → `nextIter = iter + 1`, `haveNextIter = true`.
3. **Anchored search** (`haveNextIter`): `FindByIdempotencyKey(converge:<beadID>:iter:<nextIter>)`;
   found → `GetBead(candidateID)` (`ErrNotFound` → `(_, false, nil)`; other error
   propagates) → return `(info, true, nil)`. Not found → `(_, false, nil)`.
   ⚠ The anchored search returns **only** the `lastProcessed+1` wisp — it does not fall
   back to the child scan.
4. **Unanchored scan** (no usable `lastProcessedWisp`): over prefix-matching,
   key-parseable children, track the highest-iteration `open`/`in_progress` wisp and the
   highest-iteration `closed` wisp separately. ⚠ Prefer the best **open** wisp; only if
   none, return the best **closed** one (which §9.2 will then replay); none at all →
   `(_, false, nil)`.

### 10.7 `emitRecoveryEvent(eventType, eventID, beadID, payload)` (`reconcile.go:685-690`)

If `Handler.Emitter == nil` → silently drop. Else
`Emitter.Emit(eventType, eventID, beadID, MarshalPayload(Handler.withEventRig(beadID, payload)), true)`
— the trailing `true` is the **recovery flag**. ⚠ `withEventRig` (`handler.go:860-895`)
performs an **extra `GetMetadata(beadID)`** per emit to stamp `convergence.rig` into the
payload's `rig` field (omitted when empty); a metadata read error degrades to no rig.
`MarshalPayload` returns `nil` on marshal error (`events.go:161-167`).

---

## 11. Events emitted by recovery — complete inventory

Only **two** call sites in `reconcile.go` emit, both with `recovery = true`:

| Where | Event type | Event ID | Payload struct | Fields populated |
|---|---|---|---|---|
| Path 2 (`reconcile.go:278-285`) and `completeTerminalTransition` (`reconcile.go:563-570`) | `convergence.terminated` | `converge:<beadID>:terminated` | `TerminatedPayload` (`events.go:124-131`) | `terminal_reason` (Path 2 defaults `no_convergence`; §10.1 uses meta verbatim), `total_iterations` (derived from closed children, 0 on error), `final_status` = `"closed"` always, `actor` (meta value or `"recovery"`), `cumulative_duration_ms`; `rig` via `withEventRig` |
| Path 3B (`reconcile.go:318-325`) | `convergence.waiting_manual` | `converge:<beadID>:iter:<N>:waiting_manual`, `N` = decoded `convergence.iteration` (0 on decode failure) | `WaitingManualPayload` (`events.go:134-145`) | `iteration`, `wisp_id` = pre-repair `last_processed_wisp`, `gate_mode`, `reason` = `waiting_reason`, `cumulative_duration_ms`; `rig` via `withEventRig`. `agent_verdict` `""`, `gate_outcome`/`gate_result` null, `iteration_duration_ms` 0 |

Every other path emits nothing directly. Paths 1a (closed adopt) and 4 (closed replay)
emit **indirectly** through `HandleWispClosed`, whose `emitEvent` passes
`recovery = false` (`handler.go:853-858`) — replayed iteration/terminated/waiting events
look like normal operation but carry the same stable event IDs, so consumers dedup.

Delivery-tier rationale (`events.go:22-35`): `terminated` is TierCritical (emit before
commit point, re-emit on replay); `waiting_manual` is TierRecoverable (best-effort with
reconciliation — Path 3B *is* that reconciliation). `created`, `manual_*`, and
`trigger_advance` events are never re-emitted by recovery.

⚠ gc's production emitter (`cmd/gc/convergence_store.go:368-383`) **ignores both the
event ID and the recovery flag** — it records `{Type, Actor: "convergence", Subject:
beadID, Message: <payload JSON>}`; the ID is "used for deduplication by consumers, not
the recorder". The Dart port should keep ID + recovery flag in its emitter interface
(`EventEmitter.Emit(eventType, eventID, beadID, payload, recovery)`, `events.go:171-173`)
even if the first sink drops them.

---

## 12. Why re-running is safe — the contract with `handler.go`

The recovery paths are safe to re-run *because* the normal path maintains these
invariants (full detail in `handler-9step.md`):

1. **`last_processed_wisp` is the last write of every transition** (`handler.go:438-441,
   555-556, 619, 687-689`; `manual.go:429-439`). Recovery reads it as "the commit
   completed" (§9.2) and repairs it as the final act of terminal completion (§10.1).
2. **Monotonic dedup**: `HandleWispClosed` step 2 skips any wisp whose iteration ≤
   `last_processed_wisp`'s iteration (`handler.go:177-201`) — so a replay of an
   already-committed wisp is `ActionSkipped`, harmless.
3. **Terminal guard**: `HandleWispClosed` step 1 short-circuits when state is
   `terminated` (with a best-effort `CloseBead(…, CloseReasonHandlerCleanup)`,
   `handler.go:170-175`) — replays cannot resurrect a terminated loop (invariant 6).
4. **Gate replay marker**: `gate_outcome_wisp == wispID` makes a replayed gate use the
   persisted outcome instead of re-executing the condition script (`handler.go:233-234,
   280-298`; written last in `persistGateOutcome`, `handler.go:806-807`) — recovery
   replays do not re-run side-effectful gates.
5. **Idempotency keys**: every pour is keyed `converge:<beadID>:iter:<N>`; `PourWisp`
   returns the existing wisp on collision (invariant 3).
6. **Speculative-pour tracking**: `pending_next_wisp` written at handler step 3b
   (`handler.go:244-275`) is exactly what §9.3 priority-1 adopts; `validPendingNextWisp`
   self-heals stale values on both sides.
7. **Iteration derivation**: the count of closed keyed children is the source of truth
   (invariant 4); recovery writes `iteration` only in Path 1a and otherwise lets handler
   step 3 self-heal (`handler.go:203-214`).

Scheduling interaction in gc: startup reconcile runs to completion **before** the active
index exists (§2.1), and both reconcile and tick run on the one event loop — so recovery
never interleaves with `HandleWispClosed`/`HandleTrigger`/manual handlers for the same
bead. The grid runtime (M2 Track G) must reproduce that serialization around its
snapshot-driven full-reconcile pass.

Coexistence (ADR-0003 Decision 6): these are **mutating** paths — never run them against
a convergence bead gc's reconciler owns. Shadow mode computes the would-be
`ReconcileDetail`s and diffs; it performs no `Store` writes.

---

## 13. Dart porting sketch (Track C seams)

- `reconcileBead` is a pure-ish orchestration over the `Store` + `Emitter` seams — port
  it as a class taking the same two collaborators as the handler; conformance tests
  (`conformance-reconcile-tests.md`) drive it entirely with fakes.
- `beads.ErrNotFound` distinction (§9.2, §10.6): the Dart `Store.getBead` must expose
  not-found as a typed condition (sealed result or dedicated exception type), never a
  generic error — two recovery branches depend on telling it apart from transient
  failures.
- Action strings and the `Recovered`/`Errors` accounting are asserted verbatim by the
  conformance suite — keep them as exact literals.

---

## Porting traps

1. **Path 1a iteration asymmetry** — adopt writes `iteration = 1` for a *closed* wisp but
   `0` for an open one (`reconcile.go:142-145`); the pour branch writes `0` even though
   wisp 1 now exists (`reconcile.go:192`). Writing `1` everywhere corrupts the
   closed-children invariant.
2. **State written last in Path 1a** (`active_wisp` → `iteration` → `state`,
   `reconcile.go:133-157, 186-203`) and **`CloseBead` after `state=terminated` in Path
   1b** (`reconcile.go:211-234`) — each ordering makes a mid-sequence crash land in a
   path that finishes the job. Reordering silently breaks crash-resume.
3. **Emit before close** in Path 2 and `completeTerminalTransition`
   (`reconcile.go:285-288, 570-583`): the `terminated` event precedes `CloseBead`
   (at-least-once). Moving it after the close converts a crash into a lost event.
4. **`last_processed_wisp` is written after `CloseBead`** and is the final write of
   `completeTerminalTransition` (`reconcile.go:590-597`), with both the `Children` error
   and the `SetMetadata` error discarded. It is "always last" by contract — and
   absent from Path 2 entirely.
5. **Path 2's reason default is `no_convergence`; §10.1 applies no default** —
   `completeTerminalTransition` is only reached when `terminal_reason` is already
   non-empty (`reconcile.go:266-269` vs `reconcile.go:554`). Both default `actor` to
   `"recovery"` from the *snapshot*, not the backfilled store value.
6. **`backfillTerminalActor` never overwrites** (`reconcile.go:604-609`) — it writes
   `recovery` only when the snapshot value is empty.
7. **Path 3B emits even when the outcome is `no_action`**, uses the **pre-repair**
   `last_processed_wisp` as the payload `wisp_id`, decodes `iteration` with
   silent-zero fallback, and leaves verdict/gate fields zero/null — do not "helpfully"
   reconstruct them from `convergence.gate_*` metadata.
8. **Sub-path precedence**: in `waiting_manual`, `waiting_trigger`, and `active`,
   `terminal_reason` is checked **first** (`reconcile.go:306, 379, 392`); a bead with
   both a terminal reason and a live wisp terminates, it does not iterate.
9. **`ErrNotFound` vs other errors** (`reconcile.go:402-408`; `manual.go:456-460`): only
   a not-found error triggers stale-wisp recovery; any other `GetBead` failure must
   abort with `no_action` + error. Conflating them deletes live loops' pointers on a
   flaky store.
10. **`recoverCurrentActiveWisp` prefers open over closed** in the unanchored scan and,
    when anchored by `last_processed_wisp`, looks **only** at iteration `lpw+1` with no
    fallback scan (`manual.go:467-518`).
11. **The recovered pointer is persisted before the status switch**
    (`reconcile.go:428-435`) — even an `open` recovered wisp produces a metadata write
    (and action `repaired_state`).
12. **`validPendingNextWisp` mutates during a read**: an invalid `pending_next_wisp` is
    cleared (write, error ignored) inside the validation (`handler.go:935-945`). Its
    validity test is four-way: bead readable ∧ `ParentID == root` ∧ key == `nextKey` ∧
    status ≠ `closed`.
13. **§9.3's pour has no `FindByIdempotencyKey` recovery retry** after a pour error —
    unlike `HandleWispClosed`'s pour fallback (`handler.go:260-266, 516-523`). The
    reconciler just errors with action `poured_wisp`; the next pass's priority-2 lookup
    absorbs a pour that "failed" after creating the wisp.
14. **§9.3 writes neither `iteration` nor `state`**, and clears `pending_next_wisp`
    best-effort (`_ =`, `reconcile.go:536`). `ActivateWisp` precedes the `active_wisp`
    pointer write and must be idempotent (the adopted wisp may already be active).
15. **`deriveIterationFromChildren` counts prefix+closed only** (no key parse,
    `reconcile.go:614-623`) while **`highestClosedWisp` additionally requires a
    parseable key** (`reconcile.go:640-643`) — two subtly different filters; port both.
16. **`cumulativeDuration` requires both timestamps non-zero** (`reconcile.go:674-676`)
    and returns 0 (not an error) when `Children` fails. Dart: `ClosedAt` zero-value maps
    to `null`.
17. **Report accounting is `if/else if`** (`reconcile.go:51-55`): an errored bead never
    counts as recovered even when its action label says otherwise; and `ReconcileBeads`
    itself currently always returns a nil error.
18. **The startup scan is "non-closed `type == convergence`"**, not "in_progress with
    convergence metadata" — the `reconcile.go:37-39` doc comment understates the caller
    (`cmd/gc/convergence_tick.go:569`; `IncludeClosed` defaults false,
    `internal/beads/query.go:82`). `open`-status roots (e.g. freshly created, never
    started) do reach Path 1a.
19. **Replays through `HandleWispClosed` emit with `recovery = false`** — only the two
    direct emits in §11 carry `recovery = true`. And gc's production emitter then drops
    both the event ID and the flag (`cmd/gc/convergence_store.go:375-383`); keep them in
    the port's emitter contract anyway.
20. **`withEventRig` costs an extra `GetMetadata` per emit** (`handler.go:860-895`) —
    a fake-store conformance test that asserts call counts must account for it.
21. **The unknown-state branch is an error, not a silent skip**
    (`reconcile.go:101-106`): `unknown convergence state %q` with action `no_action` —
    it increments `Errors`, surfacing schema drift loudly.
