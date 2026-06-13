# Port spec: operator commands, approval token, ACL, waiting_manual, trigger, evaluate

**Scope.** The operator-command + trigger surface of gc's convergence engine, ported for
`grid_reconciler` (M2, ADR-0003). Covers `manual.go`, `trigger.go`, `token.go`, `acl.go`,
`evaluate.go` plus the wire/transport layer in `cmd/gc` that the_grid must **emulate** (to
issue commands) and **detect** (from metadata-change `GraphEvent`s).

**Sources of truth** (pinned on disk, read-only; all `file:line` refs below are into these):

| Abbrev | Path |
|---|---|
| `manual.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/manual.go` |
| `trigger.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/trigger.go` |
| `token.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/token.go` |
| `acl.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/acl.go` |
| `evaluate.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/evaluate.go` |
| `metadata.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/metadata.go` |
| `events.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/events.go` |
| `handler.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/handler.go` |
| `reconcile.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/reconcile.go` |
| `condition.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/condition.go` |
| `gate.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/gate.go` |
| `formula.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/formula.go` |
| `template.go` | `/Users/nico/development/com.gastownhall/gascity/internal/convergence/template.go` |
| `tick.go` (cmd) | `/Users/nico/development/com.gastownhall/gascity/cmd/gc/convergence_tick.go` |
| `store.go` (cmd) | `/Users/nico/development/com.gastownhall/gascity/cmd/gc/convergence_store.go` |
| `controller.go` (cmd) | `/Users/nico/development/com.gastownhall/gascity/cmd/gc/controller.go` |
| `cmd_converge.go` | `/Users/nico/development/com.gastownhall/gascity/cmd/gc/cmd_converge.go` |

All metadata keys live on the **convergence root bead** unless stated otherwise. "Wisp" =
a child bead poured from the loop's formula, one per iteration, carrying an
`idempotency_key` metadata entry.

---

## 0. Shared constants (verbatim)

### 0.1 Metadata keys (metadata.go:12–47)

| Go const | Key string |
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
| `FieldRetrySource` | `convergence.retry_source` |
| `FieldCityPath` | `convergence.city_path` |
| `FieldRig` | `convergence.rig` |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` |
| `FieldGateStdout` | `convergence.gate_stdout` |
| `FieldGateStderr` | `convergence.gate_stderr` |
| `FieldGateDurationMs` | `convergence.gate_duration_ms` |
| `FieldGateTruncated` | `convergence.gate_truncated` |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` |
| `FieldTrigger` | `convergence.trigger` |
| `FieldTriggerCondition` | `convergence.trigger_condition` |
| `VarPrefix` | `var.` |

### 0.2 Value domains (metadata.go:50–109)

| Domain | Values (exact strings) |
|---|---|
| `convergence.state` | `creating`, `active`, `waiting_manual`, `waiting_trigger`, `terminated` |
| `convergence.trigger` | `` (empty = none), `event` |
| `convergence.gate_mode` | `manual`, `condition`, `hybrid` |
| `convergence.gate_timeout_action` | `iterate`, `retry`, `manual`, `terminate` |
| `convergence.terminal_reason` | `approved`, `no_convergence`, `stopped`, `partial_creation` |
| gate outcome (`convergence.gate_outcome`) | `pass`, `fail`, `timeout`, `error` |
| `convergence.waiting_reason` | `manual`, `hybrid_no_condition`, `timeout`, `sling_failure` |
| verdict (normalized) | `approve`, `approve-with-risks`, `block` |

Integers are stored as decimal strings (`EncodeInt`/`DecodeInt`, metadata.go:141–156).
Durations are stored as **Go duration strings** (`"5m0s"` style; `EncodeDuration`/
`DecodeDuration`, metadata.go:159–174) — not milliseconds.

### 0.3 Idempotency keys (handler.go:13–39)

- Prefix for a root: `IdempotencyKeyPrefix(beadID)` = `"converge:" + beadID + ":iter:"` (handler.go:13–15).
- Per-iteration key: `IdempotencyKey(beadID, n)` = `converge:<beadID>:iter:<n>` — **1-based** (handler.go:19–21).
- Stored on the wisp as plain metadata key `idempotency_key` (store.go (cmd):265,338).
- `ParseIterationFromKey` parses the number after the **last** `:iter:` marker; rejects
  negatives and non-integers (handler.go:26–39).
- `deriveIterationCount(root)` = the **count of CLOSED children** whose `idempotency_key`
  has the prefix — a count, not a max (handler.go:812–825).

### 0.4 Close reasons (handler.go:47–55)

bd's `validation.on-close=error` validator rejects `close_reason` < 20 chars; every close
uses one of these exact strings (written as metadata key `close_reason` **before** the
close call — store.go (cmd):116–131):

| Go const | String |
|---|---|
| `CloseReasonCreateRollback` | `convergence: bead-create rollback after error` |
| `CloseReasonRetryRollback` | `convergence: retry-create rollback after error` |
| `CloseReasonManualApprove` | `convergence: iteration closed by manual approve` |
| `CloseReasonManualSupersede` | `convergence: active wisp superseded during manual stop` |
| `CloseReasonManualStop` | `convergence: iteration closed by manual stop` |
| `CloseReasonReconcileDone` | `convergence reconcile: terminated-state bead closed` |
| `CloseReasonHandlerCleanup` | `convergence: terminated state observed; closing root` |
| `CloseReasonHandlerRoot` | `convergence: workflow handler closing root after terminate` |

### 0.5 Handler actions (handler.go:120–128)

`iterate`, `approved`, `no_convergence`, `waiting_manual`, `waiting_trigger`, `stopped`,
`skipped` (the `HandlerAction` string values).

### 0.6 Events (events.go:11–81)

| Event type string | Stable event-ID format | Tier |
|---|---|---|
| `convergence.created` | `converge:<bead>:created` | recoverable |
| `convergence.iteration` | `converge:<bead>:iter:<N>:iteration` | **critical** |
| `convergence.terminated` | `converge:<bead>:terminated` | **critical** |
| `convergence.waiting_manual` | `converge:<bead>:iter:<N>:waiting_manual` | recoverable |
| `convergence.manual_approve` | `converge:<bead>:manual_approve` | best_effort |
| `convergence.manual_iterate` | `converge:<bead>:iter:<N>:manual_iterate` | recoverable |
| `convergence.manual_stop` | `converge:<bead>:manual_stop` | best_effort |
| `convergence.trigger_advance` | `converge:<bead>:iter:<N>:trigger_advance` | (controller-driven; mirrors manual_iterate) |

Tier strings: `critical` (at-least-once, emitted **before** commit point), `recoverable`
(best-effort + reconciliation re-emit), `best_effort` (after durable state, never
re-emitted) — events.go:22–35.

For `manual_iterate` and `trigger_advance`, `<N>` is the iteration of the **NEW** wisp
being poured (events.go:63–67, 74–81). `trigger_advance` deliberately uses a distinct
suffix so it cannot collide with the `iteration` event the same wisp later emits
(events.go:76–78).

`ManualActionPayload` (events.go:150–158), JSON field names exact:

```json
{
  "rig": "<omitted when empty>",
  "actor": "operator:<username> | controller",
  "prior_state": "...",
  "new_state": "...",
  "iteration": 0,
  "wisp_id": null,
  "next_wisp_id": null
}
```

`wisp_id`/`next_wisp_id` are `null` when the corresponding string is empty
(`NullableString`, events.go:186–191); `next_wisp_id` is always null for approve/stop.

`TerminatedPayload` (events.go:124–131): `rig` (omitempty), `terminal_reason`,
`total_iterations`, `final_status` (always `"closed"`), `actor`,
`cumulative_duration_ms`.

`IterationPayload` (events.go:105–121): `rig` (omitempty), `iteration`, `wisp_id`,
`agent_verdict`, `gate_mode`, `gate_outcome` (nullable), `gate_result` (nullable),
`gate_retry_count`, `action`, `waiting_reason` (nullable), `next_wisp_id` (nullable),
`iteration_duration_ms`, `cumulative_duration_ms`, `iteration_tokens` (nullable),
`cumulative_tokens` (nullable).

`WaitingManualPayload` (events.go:134–145): `rig` (omitempty), `iteration`, `wisp_id`,
`agent_verdict`, `gate_mode`, `gate_outcome` (nullable), `gate_result` (nullable),
`reason`, `iteration_duration_ms`, `cumulative_duration_ms`.

**Rig injection:** before emitting, the handler re-reads root metadata and stamps
`convergence.rig` into the payload's `Rig` field (handler.go:860–895).

**Emission sink reality check:** the production emitter discards the stable event ID and
the recovery flag — it records `events.Event{Type, Actor: "convergence", Subject: beadID,
Message: <payload JSON>}` (store.go (cmd):375–383). Tiers and event IDs are contracts for
consumers' dedup, not enforced by the recorder.

---

## 1. Wire protocol: how operator commands arrive

**Operator commands are NOT metadata writes and NOT bd commands.** They travel over the
controller's **Unix domain socket** as a one-line text command, and the controller's
in-process handlers then perform the metadata writes described in §4–§6.

### 1.1 Transport

- Socket path: `<cityPath>/.gc/controller.sock`; if the canonicalized path would exceed
  the platform Unix-socket limit, fallback
  `/tmp/gascity-controller/<hex of first 16 bytes of sha256(canonical cityPath)>.sock`
  (controller.go (cmd):91–100).
- Line protocol: client writes one line `converge:{json}\n`; server replies one JSON line
  (controller.go (cmd):215–216, 471–492, 504–548). Client timeouts: dial 2s, write 5s,
  read 95s (controller.go (cmd):507–513). Server: 30s to enqueue onto the event loop,
  60s for the loop's reply, connection deadline 95s (controller.go (cmd):170, 479–491).
- No authentication beyond filesystem permissions on the socket. The username is
  **self-reported by the client** for audit attribution only (see §3).

### 1.2 Request JSON (`convergenceRequest`, tick.go (cmd):19–25)

```json
{"command":"approve","bead_id":"<root-bead-id>","user":"<os-username>","params":{"rig":""}}
```

- `command` ∈ `create`, `approve`, `iterate`, `stop`, `retry` (tick.go (cmd):20, 376–389).
- `user` is resolved client-side via the OS user (`currentUsername()`, tick.go
  (cmd):637–643; returns `unknown` on error). Server falls back to the daemon's user only
  when `user` is empty (tick.go (cmd):371–374).
- `params["rig"]` is **always present** for approve/iterate/stop (possibly `""` = city/HQ
  scope) — it selects which bead store's handler runs (cmd_converge.go:727–743,
  tick.go (cmd):380–384). An unknown/unbound rig is a hard error, not a fallback
  (tick.go (cmd):172–204).

### 1.3 Reply JSON (`convergenceReply`, tick.go (cmd):28–31)

```json
{"result":{...}}            // success
{"error":"<message>"}       // failure
```

⚠ For approve/iterate/stop, `result` is the Go `HandlerResult` marshaled **without json
tags** — field names are capitalized exactly:
`{"Action":"approved","Iteration":3,"GateOutcome":"","NextWispID":"","WaitingReason":""}`
(handler.go:131–137; marshalReply tick.go (cmd):629–635).

### 1.4 CLI veneer

`gc converge approve|iterate|stop <bead-id> [--json]` builds the request above and sends
it (cmd_converge.go:225–265, 727–772). There is no out-of-band path: pressing "approve"
anywhere ends up as this socket line.

### 1.5 Processing serialization & cadence

Requests are processed on the controller's single event loop, either between ticks
(low-latency channel receive) or drained inside `tick()` via
`processConvergenceRequests` (city_runtime.go (cmd):725–735; tick.go (cmd):328–341).
Single-writer-per-root-bead is the loop's guarantee (handler.go:143–145). The patrol tick
defaults to **30s** (`[daemon] patrol_interval`, config.go:2137–2138, default at
config.go:4694), with event-driven pokes in between.

### 1.6 What the_grid must EMULATE and DETECT

- **Emulate (issue a command):** while gc is running, shell out to
  `gc converge approve|iterate|stop <bead-id>` (or speak the socket line protocol of
  §1.1–1.3 directly). Do **not** perform the §4–§6 metadata writes yourself against a
  loop gc owns — single-writer-per-bead (CLAUDE.md / ADR-0003 Decision 6). Once
  the_grid owns a loop, the_grid's reconciler IS the handler and performs §4–§6 itself
  via bd (`--actor grid-controller`, `bd batch` for the grouped writes).
- **Detect (from metadata-change GraphEvents):** there is no command artifact to watch;
  detect the handler's *effects*. Signature write-sets:

| Command | Detection signature on the root bead |
|---|---|
| approve | `convergence.terminal_reason=approved` ∧ `convergence.terminal_actor=operator:<user>` ∧ `convergence.state=terminated`; root closed with `close_reason` = `convergence: iteration closed by manual approve` |
| iterate | `convergence.state`: `waiting_manual` → `active`; `convergence.waiting_reason` cleared; `convergence.active_wisp` = new wisp whose `idempotency_key` = `converge:<root>:iter:<N+1>` |
| stop | `convergence.terminal_reason=stopped` ∧ `convergence.terminal_actor=operator:<user>`; root `close_reason` = `convergence: iteration closed by manual stop`; possibly a force-closed wisp with `close_reason` = `convergence: active wisp superseded during manual stop` |
| trigger advance (controller, not operator) | `convergence.state`: `waiting_trigger` → `active`; `convergence.iteration` incremented; `convergence.active_wisp` set; **no** `terminal_*` writes; event actor `controller` |

⚠ ordering: in every terminal path `convergence.last_processed_wisp` is the **final**
write — observing it change means the transition committed; observing `terminal_reason`
without a state/close change means the handler crashed mid-transition (the reconciler's
repair paths in §7 then apply).

---

## 2. Approval token (token.go)

There is no per-approval token. The "controller token" is a per-controller-process ACL
secret intended to gate `convergence.*` metadata writes (see §3).

- Filename: `controller.token` inside `.gc/` → full path `<cityPath>/.gc/controller.token`
  (`TokenFile`, token.go:12; ReadToken token.go:63–70).
- Env var name: `GC_CONTROLLER_TOKEN` (`TokenEnvVar`, token.go:15) — used only for
  **scrubbing** from agent environments in the pinned version (§3.3).
- Format: 32 random bytes (`crypto/rand`) hex-encoded → **64 lowercase hex chars**
  (`GenerateToken`, token.go:18–24).
- Write: atomic temp-file (`.token-*.tmp` in `.gc/`) + chmod `0600` + fsync + rename
  (`WriteToken`, token.go:28–60).
- Lifecycle: generated at controller start, written to disk, **kept in memory only —
  never put in `os.Environ()`**; removed on shutdown (`RemoveToken`, token.go:73–79;
  controller.go (cmd):1260–1276).

⚠ **Verification is not wired in the pinned version.** controller.go (cmd):1271 is
literally `_ = controllerToken // available for future waves via function parameters`.
`RequiresToken` (§3) has **no production caller** — the declared design is "writes to
protected keys must present the token", but bd does not check it today. Port the
constants and the read/write/scrub helpers; treat enforcement as future scope, not as an
invariant you can rely on for detection.

---

## 3. ACL (acl.go)

### 3.1 Key protection matrix (`RequiresToken`, acl.go:18–26)

| Key pattern | Requires controller token? |
|---|---|
| `var.*` (prefix `var.`) | **yes** |
| `convergence.agent_verdict` | **no** (agent-writable, acl.go:10–13) |
| `convergence.agent_verdict_wisp` | **no** (agent-writable) |
| any other `convergence.*` (prefix `convergence.`, `ProtectedPrefix` acl.go:6) | **yes** |
| everything else | no |

⚠ evaluation order matters: the `var.` prefix check runs **first** (acl.go:19–21), then
non-`convergence.` keys return false, then the agent-writable allowlist is consulted.
A hypothetical key `var.convergence.x` requires a token because of rule 1.

### 3.2 Who may approve / identity

Approve/iterate/stop authorization is **possession of socket access**, period. Identity
is the client-supplied `user` field (OS username), used only to build the audit actor
string `"operator:" + username` (manual.go:27,153,248). The daemon's own username is the
fallback (tick.go (cmd):371–374). There is no operator allowlist, no signature, and no
token check on the command path.

Actor string domain (for `convergence.terminal_actor` and event payloads):
`operator:<username>` (manual commands), `controller` (gate/trigger-driven transitions,
handler.go:389; trigger.go:166), `recovery` (reconciler backfill, reconcile.go:217,272,557,608).

### 3.3 Token scrubbing (`ScrubTokenEnv`, acl.go:30–41)

When spawning agent sessions, the merged env map has `GC_CONTROLLER_TOKEN` removed
(template_resolve.go (cmd):419). Port rule: the_grid must never propagate its own
controller secret into agent/wisp environments.

---

## 4. ApproveHandler (manual.go:20–115)

Signature: `ApproveHandler(ctx, beadID, username, _ string)` — the 4th parameter is
unused in all three manual handlers.

Preconditions and behavior:

1. Read all root metadata (manual.go:21).
2. **Idempotent no-op:** if `state == terminated` ∧ `terminal_reason == approved`,
   return `Action: approved` with no writes (manual.go:30–34).
3. Otherwise `state` must be exactly `waiting_manual`, else error
   `cannot approve bead %q: state is %q, expected %q` (manual.go:37–42).
4. `iterationCount` = closed-children count (§0.3) (manual.go:45).
5. Event wisp reference: `eventWispID = last_processed_wisp`, overridden by
   `active_wisp` when non-empty (manual.go:51–57).

### Write/emit sequence — ⚠ ordering is the contract (manual.go:64–109)

| # | Operation | Key / event | Value |
|---|---|---|---|
| 1 | SetMetadata | `convergence.terminal_reason` | `approved` |
| 2 | SetMetadata | `convergence.terminal_actor` | `operator:<username>` |
| 3 | SetMetadata | `convergence.waiting_reason` | `` (cleared) |
| 4 | SetMetadata | `convergence.state` | `terminated` |
| 5 | Emit | `convergence.terminated`, ID `converge:<bead>:terminated` | `TerminatedPayload{terminal_reason: "approved", total_iterations: N, final_status: "closed", actor, cumulative_duration_ms}` |
| 6 | CloseBead(root) | `close_reason` = `convergence: iteration closed by manual approve` | |
| 7 | Emit | `convergence.manual_approve`, ID `converge:<bead>:manual_approve` | `ManualActionPayload{actor, prior_state: "waiting_manual", new_state: "terminated", iteration: N, wisp_id: eventWispID‖null, next_wisp_id: null}` |
| 8 | SetMetadata (only if `last_processed_wisp != ""`) | `convergence.last_processed_wisp` | re-written to its own prior value — the dedup-marker "commit" write, **LAST** |

⚠ `convergence.terminated` is emitted **before** CloseBead (TierCritical: must be
re-emittable by reconciliation replay while the bead is still open, manual.go:78–80);
`convergence.manual_approve` is emitted **after** CloseBead (TierBestEffort,
manual.go:94).

⚠ Approve does **not** clear `convergence.agent_verdict` / `agent_verdict_wisp` (contrast
iterate §5 step 3 and stop §6 step 5).

Result: `HandlerResult{Action: approved, Iteration: N}`.

---

## 5. IterateHandler (manual.go:124–217)

Preconditions:

1. `state` must be exactly `waiting_manual` (manual.go:133–138). **Not idempotent** — a
   second iterate on an already-active loop errors.
2. `iterationCount < max_iterations` (derived count vs `DecodeInt(max_iterations)`),
   else error `cannot iterate bead %q: at max iterations (%d/%d)` (manual.go:145–151).

### Sequence — ⚠ pour BEFORE any state mutation (manual.go:158–210)

| # | Operation | Detail |
|---|---|---|
| 1 | PourWisp | `nextIteration = iterationCount + 1`; key `converge:<bead>:iter:<nextIteration>`; args = (`convergence.formula`, key, `ExtractVars(meta)` = all `var.*` with prefix stripped (template.go:43–51), `convergence.evaluate_prompt`). If the pour errors, recover via `FindByIdempotencyKey(nextKey)`; only fail if that also misses (manual.go:166–175). If PourWisp fails outright the bead **stays** `waiting_manual` — safe retry (manual.go:158–159). |
| 2 | (conditional) clear verdict | only if `last_processed_wisp != ""` ∧ `convergence.agent_verdict_wisp == last_processed_wisp`: SetMetadata `convergence.agent_verdict` = `` then `convergence.agent_verdict_wisp` = `` (manual.go:180–187). ⚠ deliberately after the pour so a failed pour preserves the verdict for retry (manual.go:178–179). |
| 3 | SetMetadata | `convergence.waiting_reason` = `` |
| 4 | SetMetadata | `convergence.state` = `active` |
| 5 | SetMetadata | `convergence.active_wisp` = `<nextWispID>` |
| 6 | Emit | `convergence.manual_iterate`, ID `converge:<bead>:iter:<nextIteration>:manual_iterate`, `ManualActionPayload{actor: "operator:<user>", prior_state: "waiting_manual", new_state: "active", iteration: nextIteration, wisp_id: lastProcessedWisp‖null, next_wisp_id: nextWispID}` |

⚠ `last_processed_wisp` is **NOT written** by iterate — the new wisp hasn't been
processed; it is stamped when that wisp closes (manual.go:121–123).

⚠ `convergence.iteration` is **NOT updated** by manual iterate (contrast trigger advance
§8.4 which does write it).

Result: `HandlerResult{Action: iterate, Iteration: nextIteration, NextWispID: nextWispID}`.

---

## 6. StopHandler (manual.go:241–445)

Allowed prior states: `active`, `waiting_manual`, or `waiting_trigger` (manual.go:258–263).
Idempotent: `terminated` + `terminal_reason == stopped` → no-op `Action: stopped`
(manual.go:251–255).

The 10-step enhanced stop (comments manual.go:223–235):

| Step | What happens | Refs |
|---|---|---|
| 1 | Validate state (above) | 247–263 |
| 2 | **Drain**: if `active_wisp` exists and is already `closed`, run the full `HandleWispClosed` on it first (a legitimate completed iteration must not be discarded). Re-read metadata afterwards; if the drain terminated the loop (gate passed / max iterations), stop is a no-op returning `stopped`. Stale `active_wisp` (NotFound) is repaired via `recoverCurrentActiveWisp` (§6.1). | 272–314 |
| 3 | **Force-close**: if the (possibly recovered) active wisp is still open, `CloseBead(wisp, "convergence: active wisp superseded during manual stop")`; set `forceClosedWisp = true`. | 317–340 |
| 4 | `iterationCount` = derived count — **after** force-close so the count includes it. | 344–347 |
| 5 | **Unconditionally** clear `convergence.agent_verdict` = `` then `convergence.agent_verdict_wisp` = `` (interrupted wisp's verdict must not leak into a retry loop). | 351–356 |
| 6 | Terminal metadata, in order: `convergence.terminal_reason` = `stopped`; `convergence.terminal_actor` = `operator:<user>`; `convergence.waiting_reason` = ``; `convergence.state` = `terminated`. | 369–380 |
| 7a | If `forceClosedWisp`: emit a **synthetic** `convergence.iteration` event, ID `converge:<bead>:iter:<iterationCount>:iteration`, payload `IterationPayload{iteration: iterationCount, wisp_id: activeWisp, action: "stopped", gate_mode: meta gate_mode or "manual" if empty, iteration_duration_ms, cumulative_duration_ms}` — **before** CloseBead (TierCritical). | 384–400 |
| 7b | Emit `convergence.terminated` (ID `converge:<bead>:terminated`), `TerminatedPayload{terminal_reason: "stopped", total_iterations: iterationCount, final_status: "closed", actor, cumulative_duration_ms}` — **before** CloseBead. | 405–412 |
| 8 | `CloseBead(root, "convergence: iteration closed by manual stop")`. | 415–417 |
| 9 | Emit `convergence.manual_stop` (ID `converge:<bead>:manual_stop`), `ManualActionPayload{actor, prior_state: <state at entry/after drain>, new_state: "terminated", iteration: iterationCount, wisp_id: eventWispID‖null, next_wisp_id: null}` — **after** CloseBead (TierBestEffort). | 420–427 |
| 10 | `convergence.last_processed_wisp` **LAST**: `finalLPW = lastProcessedWisp`, but if a wisp was force-closed, `finalLPW = activeWisp` (the force-closed wisp is now the highest closed). Skipped entirely when `finalLPW == ""`. | 431–439 |

`eventWispID` = `last_processed_wisp` overridden by `active_wisp` when non-empty
(manual.go:359–362).

### 6.1 `recoverCurrentActiveWisp` (manual.go:447–519)

Used when `active_wisp` points at a missing bead (stop and reconcile paths). Strategy:

1. If `last_processed_wisp` exists and parses, look up
   `converge:<root>:iter:<lastIter+1>` via idempotency key; adopt if found, else "not
   found" (manual.go:455–484).
2. Otherwise scan children with the key prefix: prefer the **highest-iteration open or
   in_progress** wisp; fall back to the highest-iteration closed wisp; else not found
   (manual.go:486–518).

---

## 7. waiting_manual: hold writes, re-emit, repair markers

### 7.1 What is written when a loop goes on hold (`transitionToWaitingManual`, handler.go:394–475)

Reached from `HandleWispClosed` for: gate_mode `manual`; hybrid with no condition
(`waiting_reason` `hybrid_no_condition`); gate timeout with action `manual`
(`waiting_reason` `timeout`); pour failure (`waiting_reason` `sling_failure`,
handler.go:713–726).

Sequence:

1. Emit `convergence.iteration` (ID `converge:<bead>:iter:<N>:iteration`) with
   `action: "waiting_manual"`, `waiting_reason: <reason>`, verdict (only if
   `agent_verdict_wisp == wispID`, normalized), gate outcome/result if any
   (handler.go:422–436). **Before** the state writes (TierCritical).
2. ⚠ Commit writes, in order (handler.go:442–453):
   - `convergence.active_wisp` = ``
   - `convergence.waiting_reason` = `<reason>`
   - `convergence.state` = `waiting_manual`
   - `convergence.last_processed_wisp` = `<wispID>` — **LAST** (dedup marker; crash
     before this write ⇒ recovery re-processes the wisp instead of skipping it,
     handler.go:439–441).
3. Emit `convergence.waiting_manual` (ID `converge:<bead>:iter:<N>:waiting_manual`),
   `WaitingManualPayload{iteration, wisp_id, agent_verdict, gate_mode, gate_outcome,
   gate_result, reason, iteration_duration_ms, cumulative_duration_ms}` —
   after the commit (TierRecoverable; reconciliation re-emits if lost).

⚠ The verdict is **not** cleared on the manual hold — it stays scoped to
`last_processed_wisp` so the operator's later `iterate` can clear it (§5 step 2).

### 7.2 Reconciler hold re-emit + repair markers (`reconcileWaitingManual`, reconcile.go:300–372)

For an in-progress root with `state == waiting_manual`:

- **Sub-path A — interrupted stop:** `terminal_reason != ""` ⇒ run
  `completeTerminalTransition` (reconcile.go:545–600): backfill
  `convergence.terminal_actor` = `recovery` if missing; emit `convergence.terminated`
  with **recovery=true** (actor from metadata, `recovery` if empty; reason falls back to
  `no_convergence` only in the terminated-not-closed path reconcile.go:266–268); write
  `convergence.state` = `terminated` if not already; `CloseBead(root, "convergence
  reconcile: terminated-state bead closed")`; finally (⚠ always last)
  `convergence.last_processed_wisp` = highest closed wisp if one exists.
- **Sub-path B — genuine hold (`waiting_reason != ""`):**
  1. **Re-emit** `convergence.waiting_manual` with **recovery=true**, ID
     `converge:<bead>:iter:<N>:waiting_manual` where `N = DecodeInt(convergence.iteration)`,
     payload `{iteration, wisp_id: <last_processed_wisp>, gate_mode: <convergence.gate_mode>,
     reason: <waiting_reason>, cumulative_duration_ms}` — ⚠ note: no agent_verdict, no
     gate_outcome/gate_result, no iteration_duration_ms in the recovery re-emit
     (reconcile.go:315–325).
  2. **Repair marker:** if the highest-iteration closed wisp ≠
     `convergence.last_processed_wisp`, rewrite `convergence.last_processed_wisp` to that
     wisp's ID → detail action `repaired_state` (reconcile.go:329–345). Otherwise
     `no_action`.
- **Sub-path C — orphaned hold (no `waiting_reason`, no `terminal_reason`):** if any
  closed wisp exists, write the default `convergence.waiting_reason` = `manual` →
  `repaired_state`; else `no_action` (reconcile.go:349–371).

Recovery emissions go through `emitRecoveryEvent` which passes `recovery=true`
(reconcile.go:685–690) — the production recorder currently ignores the flag (§0.6).

---

## 8. Trigger (trigger.go)

### 8.1 Declaration

Two root metadata keys, written at create (create.go:72–73,113–115):

| Key | Value |
|---|---|
| `convergence.trigger` | `` (none) or `event` |
| `convergence.trigger_condition` | path to an executable script, **required** when trigger = `event` |

`ParseTriggerConfig` (trigger.go:26–41): empty mode ⇒ `{Mode: ""}` valid; `event`
without a condition ⇒ error `trigger mode "event" requires a trigger condition path`;
any other mode ⇒ error `invalid trigger mode %q`. `Enabled()` ⇔ mode == `event`
(trigger.go:19–21).

Semantics: a trigger gates **when iterations are poured** — entry (iteration 1, the loop
is created directly into `waiting_trigger` with `convergence.iteration` = `0`,
create.go:134–137) and every subsequent iteration (after a non-terminal gate outcome the
loop holds in `waiting_trigger` instead of pouring, handler.go:375–379; the speculative
pour of step 3b is **skipped** for trigger-gated loops, handler.go:249–253).

### 8.2 waiting_trigger hold (handler.go:580–635, for completeness)

On non-terminal gate outcome with trigger enabled: clear verdict if scoped to this wisp
(`agent_verdict` = `` then `agent_verdict_wisp` = ``); emit `convergence.iteration` with
`action: "waiting_trigger"`; then ⚠ commit order: `convergence.active_wisp` = ``,
`convergence.state` = `waiting_trigger`, `convergence.last_processed_wisp` = wispID
**LAST**. ⚠ Unlike the manual hold, `waiting_reason` is **not** set for trigger holds,
and the verdict **is** cleared (handler.go:587–596) because the next wisp is poured fresh
by `HandleTrigger`.

### 8.3 Evaluation: cadence, env, exit-code mapping (`HandleTrigger`, trigger.go:52–102)

**Cadence:** every controller tick, for each indexed loop whose state is
`waiting_trigger` (tick.go (cmd):267–279). Tick = patrol timer (default **30s**) plus
event-driven pokes. A non-pass result returns `Action: skipped` and is simply
re-evaluated next tick (trigger.go:96–99) — no backoff, no metadata writes on failure.

Guards, in order:

1. `state != waiting_trigger` ⇒ `Action: skipped` (trigger.go:59–61).
2. Trigger config must parse and be enabled, else error (`bead %q is in waiting_trigger
   but has no trigger configured`) (trigger.go:63–69).
3. Gate config is parsed **only to borrow its timeout** (`convergence.gate_timeout` or
   the 5-minute `DefaultGateTimeout`, gate.go:11) (trigger.go:73–76).
4. `closedIterations` = derived count; `nextIteration = closedIterations + 1`
   (trigger.go:77–83).
5. ⚠ Defense in depth: if `max_iterations` decodes > 0 and
   `nextIteration > maxIterations`, refuse loudly (error, not skip) (trigger.go:89–91).

**Environment** (`TriggerConditionEnv`, trigger.go:110–123): builds a `ConditionEnv` with
`Iteration = nextIteration` (the iteration being gated, **not** the last closed one),
`DocPath = meta["var.doc_path"]`, `ArtifactDir = <cityPath>/.gc/artifacts/<beadID>/iter-<nextIteration>`
(`ArtifactDirFor`, template.go:23–25), `MaxIterations` when decodable. `gc converge
test-trigger` calls the same function so dry-run cannot drift (trigger.go:104–109;
cmd_converge.go:587–602).

Execution: `RunCondition(ctx, conditionPath, env, gateTimeout, 0)` — ⚠ **retryBudget 0**
for triggers (trigger.go:95); only gates with `gate_timeout_action=retry` get
`MaxGateRetries = 3` (gate.go:14).

Env vars passed to the script (`ConditionEnv.Environ`, condition.go:79–150) — whitelist,
never interpolated into the command line:

| Var | Value | Always? |
|---|---|---|
| `PATH` | dirs of resolved `bd`,`gc`,`dolt`,`jq` binaries + `/usr/local/bin:/usr/bin:/bin` (`SafePATH`, condition.go:20,31–53) | yes |
| `HOME` | cityPath (sandbox; `os.TempDir()` if empty) | yes |
| `TMPDIR` | `os.TempDir()` | yes |
| `BEADS_DIR` | `<storePath>/.beads` | yes |
| `GC_BEAD_ID` | root bead ID | yes |
| `GC_ITERATION` | nextIteration (trigger) / current iteration (gate) | yes |
| `GC_WISP_ID` | wisp ID — ⚠ **empty string for triggers** (no wisp in flight) but still present | yes |
| `GC_ITERATION_DURATION_MS` / `GC_CUMULATIVE_DURATION_MS` | durations (0 for triggers — not populated) | yes |
| `GC_MAX_ITERATIONS` | max iterations (0 if absent) | yes |
| `GC_DOC_PATH` | `var.doc_path` | only if non-empty |
| `GC_AGENT_VERDICT` | normalized verdict (hybrid gates only) | only if non-empty |
| `GC_AGENT_PROVIDER` / `GC_AGENT_MODEL` | agent info | only if non-empty |
| `GC_WORK_DIR` / `GC_STORE_PATH` / `GC_ARTIFACT_DIR` / `GC_MOLECULE_DIR` | paths | only if non-empty |
| `GC_INTEGRATION_REAL_BD` + Dolt/Beads connection vars (`BEADS_DOLT_AUTO_START`, `BEADS_DOLT_SERVER_HOST`, `BEADS_DOLT_SERVER_PORT`, `BEADS_DOLT_SERVER_USER`, `BEADS_DOLT_PASSWORD`, `GC_DOLT`, `GC_DOLT_HOST`, `GC_DOLT_PORT`, `GC_DOLT_USER`, `GC_DOLT_PASSWORD`) | passthrough from controller env | only if set |

Working directory precedence: `CityPath`, overridden by `StorePath`, overridden by
`WorkDir` (condition.go:320–326).

**Exit-code → outcome mapping** (`runOnceNoPreExecRetry`, condition.go:315–404), ⚠
checked in this order:

| Condition | Outcome | ExitCode |
|---|---|---|
| parent ctx already done | `error` | nil |
| per-script deadline exceeded | `timeout` | nil |
| process exited non-zero | `fail` | the code |
| pre-exec error (not found, perms, …) | `error` | nil (stderr = error text) |
| exited 0 | `pass` | 0 |

Retries: only `timeout` outcomes consume retry budget (`RunCondition`,
condition.go:269–287). A `text file busy` pre-exec error is retried internally up to 5
times, 25ms apart (condition.go:22–25, 290–309). stdout/stderr are captured bounded and
truncated to `MaxOutputBytes` = 4096 bytes each, at a UTF-8 rune boundary, with a
`Truncated` flag (capture.go:13, condition.go:334–345).

The trigger advances **only** on outcome `pass` (trigger.go:96–99) — `fail`, `timeout`,
and `error` all just keep waiting.

### 8.4 The next-iteration pour on pass (`advanceFromTrigger`, trigger.go:129–180)

⚠ ordering, key by key:

| # | Operation | Key / event | Value |
|---|---|---|---|
| 1 | PourWisp | — | parent = root; formula = `convergence.formula`; key = `converge:<root>:iter:<nextIteration>`; vars = `ExtractVars(meta)`; evaluatePrompt = `convergence.evaluate_prompt`. On error, recover via `FindByIdempotencyKey(nextKey)` (crash-safe re-pour returns the existing wisp). |
| 2 | ActivateWisp(nextWispID) | — | publishes deferred assignees/route metadata so agents see it (store.go (cmd):204–246). |
| 3 | SetMetadata | `convergence.iteration` | `EncodeInt(nextIteration)` — ⚠ trigger advance **does** write the iteration counter (manual iterate does not). |
| 4 | SetMetadata | `convergence.active_wisp` | `<nextWispID>` |
| 5 | SetMetadata | `convergence.state` | `active` |
| 6 | Emit | `convergence.trigger_advance`, ID `converge:<root>:iter:<nextIteration>:trigger_advance` | `ManualActionPayload{actor: "controller", prior_state: "waiting_trigger", new_state: "active", iteration: nextIteration, wisp_id: <last_processed_wisp>‖null (null on the entry-gated first iteration), next_wisp_id: nextWispID}` |

`last_processed_wisp` is **not** touched. Result:
`HandlerResult{Action: iterate, Iteration: nextIteration, NextWispID: nextWispID}`.

Reconciler note: `waiting_trigger` recovery only completes an interrupted stop
(`terminal_reason != ""`); otherwise no repair — the next tick just re-evaluates
(reconcile.go:376–385).

---

## 9. Evaluate (evaluate.go): how `agent_verdict` is produced and stamped

### 9.1 The injected evaluate step — declared contract

- Reserved step name: `evaluate` (`EvaluateStepName`, evaluate.go:14). Formulas used for
  convergence must NOT declare a step with this name (`ValidateForConvergence`,
  formula.go:32–35), must carry `Convergence: true`, and their evaluate prompt (custom or
  default) must contain both literal substrings `bd meta set` and
  `convergence.agent_verdict` (`evaluateRequiredSubstrings`, evaluate.go:22–25;
  `ValidateEvaluatePrompt`, evaluate.go:74–85 — error:
  `evaluate prompt missing required substrings: ...`).
- Default prompt path: `prompts/convergence/evaluate.md` relative to city root
  (`DefaultEvaluatePromptPath`, evaluate.go:18). A formula's `EvaluatePrompt` overrides
  it. `ResolveEvaluateStep` (evaluate.go:38–69) canonicalizes cityPath via
  `EvalSymlinks`, joins, and rejects (a) any resolved path escaping cityPath
  (`evaluate prompt path escapes city directory`) and (b) any path containing symlinks
  (`evaluate prompt path contains symlinks`).

⚠ **Wiring honesty (pinned bd 1.0.5 / gascity on disk):** `ValidateForConvergence`,
`ResolveEvaluateStep`, and `ValidateEvaluatePrompt` have **no production callers** —
only the convergence package and its tests reference them. The operational mechanism is
narrower: the create command stores `--evaluate-prompt` into `convergence.evaluate_prompt`
(create.go:113), and every pour (create, iterate, trigger advance, speculative,
reconciler) threads that value into the molecule cook as plain cook-var
`evaluate_prompt` (store.go (cmd):177–184, `cookVars["evaluate_prompt"]`). The formula's
own templates render it. Port the validation functions and treat their enforcement as the
spec'd behavior, but don't expect to observe a literal injected step named `evaluate` in
live data.

### 9.2 How the verdict is physically stamped

The agent (inside the wisp), instructed by the evaluate prompt, runs **bd CLI**
mutations against the **root** bead — this is the one place where the wire protocol IS
metadata writes:

```
bd meta set <root-bead-id> convergence.agent_verdict <verdict>
bd meta set <root-bead-id> convergence.agent_verdict_wisp <wisp-id>
```

These two keys are exactly the agent-writable allowlist of acl.go:10–13. **No gascity Go
code ever writes a non-empty `convergence.agent_verdict_wisp`** — handlers only read it
and clear it. The wisp-scoping stamp comes entirely from the agent side.

### 9.3 How the verdict is consumed

- Scoping read (handler.go:318–324): the verdict counts only when
  `convergence.agent_verdict_wisp == <closed wisp ID>`; otherwise the effective verdict
  is `block`.
- Normalization (`NormalizeVerdict`, metadata.go:124–138): lowercase + trim; past-tense
  map `approved`→`approve`, `blocked`→`block`, `approve-with-risk`/`approved-with-risks`/
  `approved-with-risk`→`approve-with-risks`; canonical values pass through; **anything
  else (including empty) → `block`**.
- Hybrid gates export it to the condition script as `GC_AGENT_VERDICT` (hybrid.go:8–22);
  the gate script decides pass/fail — the controller never reinterprets the verdict
  directly.
- Clearing points (always `agent_verdict` first, then `agent_verdict_wisp`):
  - on iterate, scoped to the just-processed wisp (handler.go:491–498; manual.go:180–187);
  - on the waiting_trigger hold, scoped (handler.go:589–596);
  - on stop, **unconditionally** (manual.go:351–356).
  - ⚠ never cleared by approve or by the manual hold.

---

## 10. Porting traps

1. **`HandlerResult` JSON is PascalCase.** The socket reply's `result` object uses Go's
   default field names (`Action`, `Iteration`, `NextWispID`, …) because `HandlerResult`
   has no json tags (handler.go:131–137). Don't "fix" it to snake_case when emulating or
   parsing.
2. **`last_processed_wisp` is the commit marker and is always written LAST** — in
   approve, stop, every `HandleWispClosed` commit, and the reconciler's terminal
   completion. Approve re-writes it to its **existing** value (a pure marker write,
   manual.go:104–109). Iterate and trigger-advance do **not** write it at all.
3. **Iteration counters are counts of closed wisps, not maxima.** `deriveIterationCount`
   counts closed children with the key prefix; a deleted/burned wisp changes the count.
   Manual iterate validates `count < max`, then pours `count + 1` — but the **event ID**
   for manual_iterate uses the NEW iteration, while approve/stop events use the count.
4. **`convergence.iteration` divergence:** trigger advance writes it
   (trigger.go:148–150); manual iterate does not. After a manual iterate the stored
   `iteration` is stale until the next wisp closes (HandleWispClosed repairs it,
   handler.go:208–214). Detection logic must not rely on `convergence.iteration` alone.
5. **Critical events fire BEFORE the writes they describe become durable**
   (`convergence.terminated` before CloseBead; `convergence.iteration` before the state
   commit). A consumer can see a `terminated` event for a bead still open, and may see
   the same critical event **twice** (replay on recovery). Dedup by the stable event ID —
   but note the production recorder drops the event ID (store.go (cmd):375–383), so gc's
   recorded stream has no dedup key; the_grid should keep its own.
6. **Stop's drain can flip the result.** `gc converge stop` on a loop whose active wisp
   already closed may end up `approved`/`no_convergence` (drain ran HandleWispClosed and
   it terminated) and stop returns a no-op `stopped`. Don't assert
   `terminal_reason == stopped` after issuing stop.
7. **Verdict clearing is asymmetric** (§9.3): unconditional on stop, scoped on
   iterate/waiting_trigger, absent on approve and the manual hold. Transcribing one rule
   for all four is the easy mistake.
8. **`waiting_reason` is for manual holds only.** `waiting_trigger` never sets it, and
   the trigger-hold commit writes only `active_wisp`, `state`, `last_processed_wisp`.
9. **Trigger evaluation runs with `GC_ITERATION` = NEXT iteration and an empty
   `GC_WISP_ID`** (still exported), with retry budget 0 even when
   `gate_timeout_action=retry`, and borrows `convergence.gate_timeout` (default 5m).
   Non-pass writes nothing — there is no `trigger_outcome` metadata to observe.
10. **`agent_verdict_wisp` is agent-authored.** No controller code stamps it; if the_grid
    expects the controller to scope verdicts it will mis-port. Conversely both
    `agent_verdict*` keys are exempt from the (future) token ACL, and `var.*` keys ARE
    protected — the `var.` check precedes the `convergence.` prefix check.
11. **The token is not yet enforced.** `.gc/controller.token` (64 hex chars, 0600,
    atomic write) exists and is scrubbed from agent envs, but `RequiresToken` is dead
    code in the pinned version. Don't build detection on token failures.
12. **Operator identity is unauthenticated.** `user` in the socket JSON is client-trusted;
    `terminal_actor` = `operator:<that string>`. Treat it as audit data, not authz.
13. **Stop accepts `waiting_trigger`**, not just active/waiting_manual — and the
    state-mismatch error strings differ per handler (approve/iterate name only
    `waiting_manual`).
14. **Close reasons are load-bearing** (≥20 chars for bd's on-close validator) and are
    written as plain metadata `close_reason` **before** the close call, best-effort.
    Reuse the exact strings in §0.4; inventing shorter ones breaks closes under
    `validation.on-close=error`.
15. **Durations are Go duration strings** in metadata (`gate_timeout`), milliseconds in
    event payloads, and `gate_duration_ms` metadata is a decimal-ms string. Three
    encodings for one concept.
16. **Synthetic iteration event on stop reuses the normal iteration event ID**
    (`converge:<bead>:iter:<N>:iteration`) for the force-closed wisp — it is NOT a
    distinct type. Only trigger_advance got a collision-proof suffix.
17. **`gate_truncated` is written as `"true"` or `""`** (empty for false), never
    `"false"` (handler.go:799–803). Parse accordingly.
18. **Rig scoping:** approve/iterate/stop run against the bead store selected by
    `params["rig"]`; the same bead ID in the wrong scope errors. The grid's emulation
    must carry the rig context, and detection must remember `convergence.rig` is also
    injected into every event payload when set.
