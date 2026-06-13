# Convergence metadata schema — `convergence.*` port spec

**Status:** extracted 2026-06-12 from pinned Go sources. This document is the
self-contained contract for the Track-A metadata codec (M2-BUILD-ORDER) and the
transition writers in `grid_reconciler`. A Dart implementer should be able to
work from this file alone.

**Sources of truth (read-only, pinned on disk):**

- gascity: `/Users/nico/development/com.gastownhall/gascity` — primary file
  `internal/convergence/metadata.go`; writers/readers across
  `create.go`, `handler.go`, `manual.go`, `trigger.go`, `gate.go`,
  `condition.go`, `hybrid.go`, `reconcile.go`, `retry.go`, `evaluate.go`,
  `events.go`, `acl.go`, `template.go`; the store adapter
  `cmd/gc/convergence_store.go`; the bd-CLI store `internal/beads/bdstore.go`.
- beads (bd 1.0.5, f9fe4ef2a): `/Users/nico/development/com.gastownhall/beads`
  — `cmd/bd/update.go` (metadata write semantics),
  `internal/storage/metadata.go` (key validation, JSON path quoting).

All `file:line` references below are relative to
`gascity/internal/convergence/` unless prefixed otherwise.

---

## 1. The TRUE complete key set — resolving the "16 keys" discrepancy

`metadata.go:12–44` defines **31** `convergence.*` field constants. The M2
build order (`docs/M2-BUILD-ORDER.md`, Track A) lists only **16** keys
(`state, iteration, max_iterations, formula, target, gate_mode,
gate_condition, gate_timeout, gate_timeout_action, active_wisp,
last_processed_wisp, agent_verdict, agent_verdict_wisp, gate_outcome,
gate_exit_code, gate_outcome_wisp`). That list is **incomplete — it is a
subset, not the schema**.

Resolution of the ADR-0003 invariant-5 question:

- `pending_next_wisp` is **a real, distinct key**, not an alias:
  `FieldPendingNextWisp = "convergence.pending_next_wisp"`
  (`metadata.go:41`). It is the crash-recovery tracker for the speculative
  pour (ADR-0003 invariant 5) and is written/read at `handler.go:236,247,268,
  565,915,941` and `reconcile.go:492,536`. The Track-A "16 keys" list simply
  omits it (and 14 others).

- **15 keys beyond the listed 16** (all must be in the codec):
  `gate_retry_count`, `terminal_reason`, `terminal_actor`, `waiting_reason`,
  `retry_source`, `city_path`, `rig`, `evaluate_prompt`, `gate_stdout`,
  `gate_stderr`, `gate_duration_ms`, `gate_truncated`, `pending_next_wisp`,
  `trigger`, `trigger_condition`.

- In addition to the 31 fixed keys there is one **open namespace**:
  `var.*` (`VarPrefix = "var."`, `metadata.go:47`) — template variables,
  copied verbatim onto the root bead at create (`create.go:124–128`) and retry
  (`retry.go:109–113`), extracted by `ExtractVars` (`template.go:43–51`,
  strips the `var.` prefix). `var.doc_path` is special-cased into the gate env
  as `GC_DOC_PATH` (`handler.go:750`, `trigger.go:116`).

- The codec must also **preserve unknown keys in a raw map** (A13 pattern per
  the build order): gc's machinery itself co-writes non-`convergence.*` keys
  on the same beads (see §8).

Total contract: **31 fixed `convergence.*` keys + the `var.*` namespace +
raw passthrough.**

---

## 2. Master key table

Notes on reading the table:

- "Writers" are `SetMetadata` call sites (every write goes through
  `Store.SetMetadata(id, key, value)` → `bd update --json <id>
  --set-metadata key=value`; see §5 for wire encoding).
- "Readers" are `meta[Field…]` accesses. External (non-package) readers are
  marked `[ext]` and live under `gascity/cmd/gc/` — they are read-only
  status/tick surfaces and define no new semantics.
- `""` in the values column means the literal empty string is written
  (clear-by-overwrite; keys are never deleted — see §6).

| Go constant | Exact key string | Value type / format | Every literal value ever written (file:line) | Writers | Readers |
|---|---|---|---|---|---|
| `FieldState` | `convergence.state` | enum, §4.1 | `"creating"` create.go:98, retry.go:83 · `"active"` create.go:152, manual.go:192, reconcile.go:152, reconcile.go:198, retry.go:100, trigger.go:154 · `"waiting_manual"` handler.go:448 · `"waiting_trigger"` create.go:137, handler.go:623 · `"terminated"` create.go:92 (rollback), handler.go:696, manual.go:74, manual.go:378, reconcile.go:223, reconcile.go:574, retry.go:77 (rollback) | create/handler/manual/reconcile/retry/trigger | handler.go:171; manual.go:26,130,247,303,310; reconcile.go:70,573; retry.go:29,32; trigger.go:59; [ext] cmd/gc/convergence_store.go:46,308; cmd/gc/convergence_tick.go:267,282; cmd/gc/cmd_converge.go:173,303 |
| `FieldIteration` | `convergence.iteration` | decimal int, `EncodeInt` (§5.1) | `"0"` create.go:134 (trigger-gated entry), reconcile.go:192 · `"1"` create.go:167, retry.go:126 · `EncodeInt(adoptedIteration)` (0 or 1) reconcile.go:146 · `EncodeInt(globalIteration)` (derived repair) handler.go:211 · `EncodeInt(nextIteration)` trigger.go:148 | create, handler (repair), reconcile, retry, trigger | handler.go:208; reconcile.go:315; [ext] cmd/gc/cmd_converge.go:174,307,484 |
| `FieldMaxIterations` | `convergence.max_iterations` | decimal int > 0 | `EncodeInt(params.MaxIterations)` create.go:106 · `EncodeInt(maxIterations)` retry.go:95 | create, retry | handler.go:216,759; manual.go:145; trigger.go:89,119; [ext] cmd/gc/convergence_tick.go:502; cmd/gc/cmd_converge.go:175,308,485 |
| `FieldFormula` | `convergence.formula` | formula name (free string, required non-empty at create — create.go:46) | `params.Formula` create.go:104 · copied source value retry.go:89 | create, retry | handler.go:255,510; manual.go:162; reconcile.go:174,508; retry.go:45; trigger.go:131; [ext] cmd/gc/cmd_converge.go:177,318 |
| `FieldTarget` | `convergence.target` | agent name (free string, required non-empty at create — create.go:49) | `params.Target` create.go:105 · copied retry.go:90 | create, retry | retry.go:46; [ext] cmd/gc/convergence_store.go:48,106,309; cmd/gc/convergence_tick.go:510; cmd/gc/cmd_converge.go:178,319 |
| `FieldGateMode` | `convergence.gate_mode` | enum, §4.2 | `params.GateMode` create.go:107 (defaulted to `"manual"` when empty BEFORE write — create.go:55–57, so create always writes a concrete mode) · copied retry.go:91 | create, retry | gate.go:45 (`ParseGateConfig`); manual.go:387; reconcile.go:321; retry.go:47; [ext] cmd/gc/cmd_converge.go:176,317 |
| `FieldGateCondition` | `convergence.gate_condition` | path to executable gate script (may be `""`) | `params.GateCondition` create.go:108 · copied retry.go:92 | create, retry | gate.go:81; retry.go:48 |
| `FieldGateTimeout` | `convergence.gate_timeout` | Go duration string, §5.2 (may be `""` → default 5m) | `params.GateTimeout` create.go:109 (verbatim operator input; CLI flag default is `DefaultGateTimeout.String()` = `"5m0s"` — cmd/gc/cmd_converge.go:129) · copied retry.go:93 | create, retry | gate.go:58 (`DecodeDuration`); retry.go:49 |
| `FieldGateTimeoutAction` | `convergence.gate_timeout_action` | enum, §4.4 (may be `""` → default `iterate`) | `params.GateTimeoutAction` create.go:110 · copied retry.go:94 | create, retry | gate.go:70; retry.go:50 |
| `FieldActiveWisp` | `convergence.active_wisp` | wisp bead ID, or `""` = no wisp in flight | first wisp ID create.go:164, retry.go:123 · next wisp ID handler.go:557, manual.go:197, trigger.go:151 · `""` (clear) handler.go:442 (→waiting_manual), handler.go:620 (→waiting_trigger) · recovery repairs reconcile.go:133,186,429,530 | create, handler, manual, reconcile, retry, trigger | manual.go:51,265,311; reconcile.go:397; [ext] cmd/gc/convergence_tick.go:285; cmd/gc/cmd_converge.go:185,490 |
| `FieldLastProcessedWisp` | `convergence.last_processed_wisp` | wisp bead ID (the dedup/commit marker) | processed wisp ID handler.go:451,560,626,702; manual.go:106 (re-assert on approve), manual.go:436 (force-closed wisp on stop); reconcile.go:338 (repair to highest closed wisp), reconcile.go:595 | handler, manual, reconcile | handler.go:188; manual.go:52,156,266,312; reconcile.go:316,337,409,447; trigger.go:170 |
| `FieldAgentVerdict` | `convergence.agent_verdict` | verdict string, §4.5 — **written by the agent** via `bd meta set` per the evaluate-step prompt (evaluate.go:22–25 requires the prompt to contain literal `bd meta set` + `convergence.agent_verdict`); agent-writable without controller token (acl.go:11) | controller only ever writes `""` (clear): handler.go:492,590; manual.go:181,351 | agent (set), controller (clear) | handler.go:321,419,535,601,657 (always through `NormalizeVerdict`, always scoped by `agent_verdict_wisp`) |
| `FieldAgentVerdictWisp` | `convergence.agent_verdict_wisp` | wisp bead ID scoping the verdict; agent-writable (acl.go:12) | controller writes only `""` (clear): handler.go:495,593; manual.go:184,354 | agent (set), controller (clear) | handler.go:320,418,491,534,589,600,656; manual.go:180 |
| `FieldGateOutcome` | `convergence.gate_outcome` | enum, §4.3 | `result.Outcome` handler.go:777 — domain `"pass"`/`"fail"`/`"timeout"`/`"error"` (condition.go:351–403, gate.go:26) | handler (`persistGateOutcome`) | handler.go:282 (replay); [ext] cmd/gc/cmd_converge.go:182 |
| `FieldGateExitCode` | `convergence.gate_exit_code` | decimal int, or `""` when exit code not applicable | `EncodeInt(*result.ExitCode)` or `""` if `ExitCode == nil` (timeout / pre-exec error) — handler.go:780–784 | handler | handler.go:283–287 |
| `FieldGateOutcomeWisp` | `convergence.gate_outcome_wisp` | wisp bead ID — gate-persistence idempotency marker | processed wisp ID handler.go:807 (**LAST write** of `persistGateOutcome`) | handler | handler.go:233 (`skipGateEval` when == current wisp) |
| `FieldGateRetryCount` | `convergence.gate_retry_count` | decimal int ≥ 0 (≤ `MaxGateRetries` = 3, gate.go:14) | `EncodeInt(result.RetryCount)` handler.go:787 | handler | handler.go:288 |
| `FieldTerminalReason` | `convergence.terminal_reason` | enum, §4.6 | `"approved"` manual.go:65; handler.go:690 (via reason var, handler.go:360) · `"no_convergence"` handler.go:690 (handler.go:363,367) · `"stopped"` manual.go:369 · `"partial_creation"` reconcile.go:211 | handler, manual, reconcile | manual.go:30,251; reconcile.go:266,301,379,392,554; retry.go:37; [ext] cmd/gc/cmd_converge.go:184 |
| `FieldTerminalActor` | `convergence.terminal_actor` | actor string, §4.7 | `"controller"` handler.go:693 (literal passed at handler.go:389) · `"operator:"+username` manual.go:68,372 (built at manual.go:27,248) · `"recovery"` reconcile.go:217,608 | handler, manual, reconcile | reconcile.go:270,555,605 |
| `FieldWaitingReason` | `convergence.waiting_reason` | enum, §4.8, or `""` = not waiting | `"manual"` handler.go:445 (via handler.go:306), reconcile.go:362 (repair default) · `"hybrid_no_condition"` handler.go:445 (via handler.go:315) · `"timeout"` handler.go:445 (via handler.go:350) · `"sling_failure"` handler.go:445 (via handler.go:725) · `""` (clear) manual.go:71,189,375 | handler, manual, reconcile | reconcile.go:302; [ext] cmd/gc/cmd_converge.go:183 |
| `FieldRetrySource` | `convergence.retry_source` | source (terminated) bead ID | `sourceBeadID` retry.go:99 | retry only | **none** at this pin — write-only audit metadata (no production reader in gascity) |
| `FieldCityPath` | `convergence.city_path` | absolute city path | `params.CityPath` create.go:111 · copied retry.go:96 | create, retry | handler.go:743; retry.go:51; trigger.go:82; [ext] cmd/gc/cmd_converge.go:598 |
| `FieldRig` | `convergence.rig` | rig name, `""` = city/HQ store (create.go:27–31) | `params.Rig` create.go:112 · copied retry.go:97 | create, retry | handler.go:894 (stamps `rig` into event payloads); retry.go:52; [ext] cmd/gc/cmd_converge.go:179,309 |
| `FieldEvaluatePrompt` | `convergence.evaluate_prompt` | evaluate-prompt path (may be `""` → default `prompts/convergence/evaluate.md`, evaluate.go:18) | `params.EvaluatePrompt` create.go:113 · copied retry.go:98 | create, retry | handler.go:257,512; manual.go:164; reconcile.go:176,510; retry.go:53; trigger.go:133 |
| `FieldGateStdout` | `convergence.gate_stdout` | UTF-8 string ≤ 4096 bytes (`MaxOutputBytes`, capture.go:13; rune-boundary truncation capture.go:47–69) | `result.Stdout` handler.go:790 | handler | handler.go:291 |
| `FieldGateStderr` | `convergence.gate_stderr` | same as stdout | `result.Stderr` handler.go:793 | handler | handler.go:292 |
| `FieldGateDurationMs` | `convergence.gate_duration_ms` | decimal int64 **milliseconds**, §5.3 | `strconv.FormatInt(result.Duration.Milliseconds(), 10)` handler.go:796 | handler | handler.go:293–297 (DecodeInt → `time.Duration(ms)*time.Millisecond`) |
| `FieldGateTruncated` | `convergence.gate_truncated` | `"true"` or `""` — **never** `"false"`, §5.4 | `"true"` if truncated, else `""` — handler.go:799–803 | handler | handler.go:298 (`== "true"`) |
| `FieldPendingNextWisp` | `convergence.pending_next_wisp` | speculative wisp bead ID, or `""` | speculative wisp ID handler.go:268 · `""` (clear) handler.go:565 (post-adopt), handler.go:915 (burn), handler.go:941 (stale self-heal), reconcile.go:536 (post-adopt in recovery) | handler, reconcile | handler.go:236,247; reconcile.go:492 — always through `validPendingNextWisp` (handler.go:935–945: re-validates parent, idempotency key, not-closed; clears if stale) |
| `FieldTrigger` | `convergence.trigger` | `""` (none) or `"event"` (metadata.go:60–63) | `params.Trigger` create.go:114 | create only — **NOT copied by retry** (see traps) | trigger.go:27 (`ParseTriggerConfig`); [ext] cmd/gc/cmd_converge.go:180 |
| `FieldTriggerCondition` | `convergence.trigger_condition` | path to trigger condition script (required non-empty when trigger=`"event"`, trigger.go:33–37) | `params.TriggerCondition` create.go:115 | create only — **NOT copied by retry** | trigger.go:28; [ext] cmd/gc/cmd_converge.go:181 |
| `VarPrefix` + key | `var.<name>` | free string template variables | `params.Vars` create.go:124–128 · copied retry.go:109–113 | create, retry | `ExtractVars` template.go:43–51 (handler.go:256,511; manual.go:163; reconcile.go:175,509; retry.go:54; trigger.go:132) · `var.doc_path` handler.go:750, trigger.go:116 |

---

## 3. Who is allowed to write what (ACL)

`acl.go`:

- `ProtectedPrefix = "convergence."` (acl.go:6). Writing any `convergence.*`
  key requires the controller token **except** the two agent-writable keys
  `convergence.agent_verdict` and `convergence.agent_verdict_wisp`
  (acl.go:10–13, `RequiresToken` acl.go:18–26).
- `var.*` keys ALSO require the token (acl.go:19–21).
- Token: 32-byte hex in `.gc/controller.token`, env `GC_CONTROLLER_TOKEN`
  (token.go:12–15); scrubbed from agent session env (acl.go:30–41).

The agent-side write channel: the injected `evaluate` step's prompt instructs
the agent to run `bd meta set` on `convergence.agent_verdict` (+ wisp scope).
A custom evaluate prompt is rejected unless it contains the literal substrings
`bd meta set` and `convergence.agent_verdict` (evaluate.go:22–25,74–85).

---

## 4. Value-domain tables (exact wire strings)

### 4.1 `convergence.state` (metadata.go:50–56)

| Constant | Wire string | Meaning |
|---|---|---|
| `StateCreating` | `creating` | set immediately after bead creation; reconciler terminates partial creations |
| `StateActive` | `active` | wisp in flight (or being repaired) |
| `StateWaitingManual` | `waiting_manual` | held for operator approve/iterate/stop |
| `StateWaitingTrigger` | `waiting_trigger` | entry/iteration gated on external trigger condition |
| `StateTerminated` | `terminated` | terminal; root bead is (being) closed |
| — | `` (absent/empty) | recovery path 1a: created but loop never started (reconcile.go:73–76) |

Unknown state strings are a reconcile error (reconcile.go:101–106).

### 4.2 `convergence.gate_mode` (metadata.go:66–70)

| Constant | Wire string |
|---|---|
| `GateModeManual` | `manual` |
| `GateModeCondition` | `condition` |
| `GateModeHybrid` | `hybrid` |

`""`/absent parses as `manual` (gate.go:46–48). Any other string is a parse
error (gate.go:54). `condition` mode with empty `gate_condition` is a hard
handler error (handler.go:235–242). `hybrid` with empty condition falls back
to manual-wait (`HybridNeedsManual`, hybrid.go:26–28).

### 4.3 `convergence.gate_outcome` (metadata.go:89–94)

| Constant | Wire string | Produced when |
|---|---|---|
| `GatePass` | `pass` | script exit 0 (condition.go:394–403); also the synthetic manual result `GateManualResult()` (gate.go:36–40, hybrid fallback — never persisted, see traps) |
| `GateFail` | `fail` | script non-zero exit (condition.go:371–384) |
| `GateTimeout` | `timeout` | per-script deadline exceeded (condition.go:361–369) |
| `GateError` | `error` | pre-exec failure (script not found, perms), parent ctx canceled, or unexpected mode (condition.go:350–358,385–392; handler.go:769) |

### 4.4 `convergence.gate_timeout_action` (metadata.go:73–78)

| Constant | Wire string | Behavior on `timeout` outcome |
|---|---|---|
| `TimeoutActionIterate` | `iterate` | treat as non-pass → iterate (default when `""`/absent, gate.go:69) |
| `TimeoutActionRetry` | `retry` | retry the script, budget `MaxGateRetries = 3` (gate.go:14; handler.go:738–741; condition.go:269–287 — retries ONLY on `timeout` outcomes) |
| `TimeoutActionManual` | `manual` | → `waiting_manual` with `waiting_reason=timeout` (handler.go:345–351) |
| `TimeoutActionTerminate` | `terminate` | → terminated, `terminal_reason=no_convergence` (handler.go:361–363) |

Any other non-empty string is a parse error (gate.go:75).

### 4.5 `convergence.agent_verdict` — normalization (metadata.go:104–138)

Canonical wire strings (what `NormalizeVerdict` returns; raw agent input may
be anything):

| Constant | Wire string |
|---|---|
| `VerdictApprove` | `approve` |
| `VerdictApproveWithRisks` | `approve-with-risks` |
| `VerdictBlock` | `block` |

`NormalizeVerdict(raw)` (metadata.go:124–138): lowercase → trim whitespace →
empty → `block`; past-tense map (metadata.go:113–119): `approved`→`approve`,
`blocked`→`block`, `approve-with-risk` / `approved-with-risks` /
`approved-with-risk` → `approve-with-risks`; the three canonical values pass
through; **anything else → `block`**. Normalization happens on READ only —
the stored value is whatever the agent wrote. A verdict is consumed only if
`convergence.agent_verdict_wisp == <the wisp being processed>`; otherwise the
effective verdict is `block` (handler.go:319–324).

### 4.6 `convergence.terminal_reason` (metadata.go:81–86)

| Constant | Wire string | Written by |
|---|---|---|
| `TerminalApproved` | `approved` | gate pass (handler.go:360) or operator approve (manual.go:65) |
| `TerminalNoConvergence` | `no_convergence` | max-iterations exhausted or timeout+terminate (handler.go:363,367); also recovery's safe default when re-emitting a terminated event with empty reason (reconcile.go:266–269 — event-only, not written back) |
| `TerminalStopped` | `stopped` | operator stop (manual.go:369) |
| `TerminalPartialCreation` | `partial_creation` | reconciler terminating a `creating` bead (reconcile.go:211) |

### 4.7 `convergence.terminal_actor`

Free string with exactly three producers: `controller` (handler.go:389→693),
`operator:<username>` (manual.go:27,248 → 68/372), `recovery`
(reconcile.go:217,608 — also backfilled if missing during terminal-transition
completion, reconcile.go:604–609).

### 4.8 `convergence.waiting_reason` (metadata.go:97–102)

| Constant | Wire string | Cause |
|---|---|---|
| `WaitManual` | `manual` | gate_mode=manual (handler.go:306); also the repair default for orphaned waiting_manual (reconcile.go:362) |
| `WaitHybridNoCondition` | `hybrid_no_condition` | hybrid mode, no condition script (handler.go:315) |
| `WaitTimeout` | `timeout` | gate timeout + timeout_action=manual (handler.go:350) |
| `WaitSlingFailure` | `sling_failure` | PourWisp failed and idempotency lookup found nothing (handler.go:725) |

### 4.9 `convergence.trigger` (metadata.go:60–63)

| Constant | Wire string |
|---|---|
| `TriggerNone` | `` (empty string) — default, wisp-close-driven iteration |
| `TriggerEvent` | `event` — iterations gated on trigger condition |

`event` requires non-empty `trigger_condition` (trigger.go:33–37); any other
non-empty mode is a parse error (trigger.go:38–40).

---

## 5. Encodings — the exact strings gc writes

### 5.1 Integers — `EncodeInt` / `DecodeInt` (metadata.go:141–156)

- Write: `strconv.Itoa(n)` — plain base-10, no padding, no sign for ≥0.
- Read: `strconv.Atoi`; empty string or invalid → `(0, false)`. **Every
  caller in the package uses `value, _ := DecodeInt(...)` or checks `ok`** —
  i.e. garbage decodes to 0 and the loop self-heals from derived counts.
- Used by: `iteration`, `max_iterations`, `gate_exit_code`,
  `gate_retry_count`, and the read side of `gate_duration_ms`.
- `gate_exit_code` may legitimately encode `-1` (Go `ExitCode()` for
  signal-killed processes) — `strconv.Itoa(-1)` = `"-1"`.

### 5.2 Durations — `gate_timeout` only

- Read: `DecodeDuration` = `time.ParseDuration` (metadata.go:165–174) —
  Go duration syntax (`"300ms"`, `"90s"`, `"5m"`, `"1h30m"`). Empty/absent →
  default `DefaultGateTimeout = 5m` (gate.go:11,57–67). Non-positive parsed
  values are a config error (gate.go:63–65).
- Write: gc **never encodes** this field itself — `EncodeDuration`
  (`d.String()`, metadata.go:159–161) exists but has **zero production
  callers**. The stored value is the verbatim operator-supplied string from
  `gc converge` (CLI default literal: `"5m0s"`, i.e.
  `(5*time.Minute).String()` — gascity/cmd/gc/cmd_converge.go:129).
- The Dart port must therefore PARSE Go duration syntax but only ever
  round-trip the original string (copy on retry, retry.go:49,93).

### 5.3 Milliseconds — `gate_duration_ms`

- Write: `strconv.FormatInt(result.Duration.Milliseconds(), 10)`
  (handler.go:796) — decimal integer count of **milliseconds**, NOT a Go
  duration string.
- Read: `DecodeInt` then `time.Duration(ms) * time.Millisecond`
  (handler.go:293–297).

### 5.4 Booleans — `gate_truncated`

- Write: `"true"` when truncated, otherwise the **empty string** `""` —
  never `"false"` (handler.go:799–803).
- Read: strict equality `meta[FieldGateTruncated] == "true"`
  (handler.go:298). Any other value (including `"false"`, `"TRUE"`, `"1"`)
  reads as not-truncated.

### 5.5 Timestamps

**No `convergence.*` key stores a timestamp.** Durations in events are
computed from bead `created_at` / `closed_at`. The store adapter parses the
bd-owned metadata key `closed_at` with layout `time.RFC3339Nano`
(gascity/cmd/gc/convergence_store.go:340–344); a closed bead missing
`closed_at` falls back to `CreatedAt` (zero duration,
convergence_store.go:346–350). The Dart port needs RFC3339-with-nanoseconds
parsing for that adapter concern only.

### 5.6 ⚠ Wire-level coercion through bd (the JSON metadata column)

Writes go through `bd update --json <id> --set-metadata key=value`
(gascity/internal/beads/bdstore.go:1347–1357). bd 1.0.5 does **type
inference** on the value (beads/cmd/bd/update.go:619–638, `toJSONValue`):

- `"null"` → JSON `null`; `"true"`/`"false"` → JSON booleans;
- anything `fmt.Sscanf(s, "%f")`-parsable AND `json.Valid` → JSON **number**
  (so `convergence.iteration=3` is stored as `3`, not `"3"`; `gate_truncated=
  true` is stored as boolean `true`; `gate_duration_ms=1042` as number);
- everything else (including `""`) → JSON string.

gc reads it back through a tolerant decoder, `StringMap`
(gascity/internal/beads/bdstore.go:497–522): values that aren't JSON strings
are coerced to their raw JSON text (`true` → `"true"`, `42` → `"42"`). The
Dart codec MUST replicate this tolerance: **every metadata value read from bd
may arrive as JSON string, number, bool, or null, and must be coerced to its
literal text form before decoding.**

Key validation (write side): keys must match `[a-zA-Z_][a-zA-Z0-9_.]*`
(beads/internal/storage/metadata.go:215–219). Dotted keys are quoted in
JSON paths as `$."convergence.state"` — NOT nested objects
(beads/internal/storage/metadata.go:226–231). The metadata column is a flat
one-level JSON object.

---

## 6. Absent-vs-empty semantics per key

Mechanics first:

- gc never deletes a metadata key. "Clearing" is always
  `SetMetadata(id, key, "")` — the key remains present with JSON `""`.
  (`bd update --unset-metadata` exists — beads/cmd/bd/update.go:602–608 —
  but the convergence machinery never uses it.)
- Every read in the package uses Go's map zero-value (`meta[key]` → `""`
  when absent). `MetadataPresent` (metadata.go:176–182) can distinguish
  absent from empty but has **zero callers** — so at this pin, **absent and
  empty string are semantically identical for every key**. (gate.go:58,70 use
  the two-value form `raw, ok := meta[...]` but immediately AND with
  `raw != ""`, collapsing the distinction.)

Per-key "unset" meaning (what `""`/absent is treated as):

| Key | `""`/absent means |
|---|---|
| `state` | recovery path 1a "loop never started" — adopt/pour wisp 1 (reconcile.go:73) |
| `iteration` | 0 (`DecodeInt` false branch); advisory anyway — truth is closed-children count |
| `max_iterations` | 0 → effectively "always at/over max" in `wispIteration >= maxIterations` (handler.go:364) and "skip speculative pour" (handler.go:254); create rejects `<= 0` so this only arises on corrupt data |
| `formula`, `target` | invalid at create (create.go:46–51); downstream code passes `""` through (PourWisp would fail) |
| `gate_mode` | `manual` (gate.go:46–48) |
| `gate_condition` | no script; condition mode → error, hybrid → manual fallback |
| `gate_timeout` | default `5m` (gate.go:57–67) |
| `gate_timeout_action` | default `iterate` (gate.go:69–77) |
| `active_wisp` | no wisp in flight; reconciler derives next from children (reconcile.go:475–538) |
| `last_processed_wisp` | nothing processed yet → dedup baseline iteration 0 (handler.go:187–198) |
| `agent_verdict` | normalized to `block` IF the wisp scope matches; with empty `agent_verdict_wisp` the scope check fails first and verdict is `block` anyway |
| `agent_verdict_wisp` | verdict (if any) is unscoped → ignored, treated as `block` (handler.go:320–324) |
| `gate_outcome` | no gate persisted; replay (`skipGateEval`) only triggers off `gate_outcome_wisp`, so an empty outcome with a matching marker yields `GateResult.Outcome == ""` — `GateResultToPayload` then returns nil (events.go:195–198) |
| `gate_exit_code` | no exit code (nil pointer on replay, handler.go:283–287) |
| `gate_outcome_wisp` | gate not yet evaluated for any wisp → evaluate fresh |
| `gate_retry_count` | 0 |
| `terminal_reason` | not terminated / no stop pending; recovery's event fallback is `no_convergence` (reconcile.go:266–269) |
| `terminal_actor` | unknown → backfilled with `recovery` (reconcile.go:270–273,604–609) |
| `waiting_reason` | not waiting (cleared on approve/iterate/stop); for a waiting_manual bead, empty = orphaned state → repaired to `manual` if closed wisps exist (reconcile.go:349–369) |
| `retry_source` | not a retry |
| `city_path` | no city context — gate env `HOME` falls back to `os.TempDir()` (condition.go:82–85); `ArtifactDirFor("")` produces a relative path |
| `rig` | city/HQ store owns the loop (create.go:27–31); event payloads omit `rig` (handler.go:860–895, `omitempty`) |
| `evaluate_prompt` | default prompt `prompts/convergence/evaluate.md` under city root (evaluate.go:14–18,33–69) |
| `gate_stdout` / `gate_stderr` | no output captured |
| `gate_duration_ms` | duration 0 on replay (handler.go:293–297) |
| `gate_truncated` | not truncated |
| `pending_next_wisp` | no speculative wisp outstanding (`validPendingNextWisp` returns `""` immediately, handler.go:936–938) |
| `trigger` | no trigger — default wisp-close iteration semantic (`TriggerNone`, metadata.go:60–63) |
| `trigger_condition` | none; only an error when `trigger == "event"` (trigger.go:33–37) |

---

## 7. ⚠ Ordering contracts (every one is load-bearing)

### 7.1 Gate persistence — `persistGateOutcome` (handler.go:776–808)

Write order, single wisp-scoped batch:

1. `gate_outcome`
2. `gate_exit_code` (`""` if nil)
3. `gate_retry_count`
4. `gate_stdout`
5. `gate_stderr`
6. `gate_duration_ms`
7. `gate_truncated` (`""` or `"true"`)
8. **`gate_outcome_wisp` LAST** — it is the idempotency marker. A crash
   before (8) ⇒ the gate re-runs on replay; a crash after ⇒ replay uses the
   persisted result verbatim (handler.go:280–298). Writing (8) before (1–7)
   would replay a half-written result.

### 7.2 Transition commits — `last_processed_wisp` is ALWAYS the final write

`last_processed_wisp` is the dedup/commit marker; if the process crashes
before it, recovery re-processes the wisp (safe, idempotent); after it, the
wisp is skipped (handler.go:438–441).

- **→ waiting_manual** (handler.go:442–451): `active_wisp=""` →
  `waiting_reason=<reason>` → `state=waiting_manual` →
  **`last_processed_wisp=<wisp>`**.
- **→ iterate** (handler.go:555–565): clear verdict pair first if scoped
  (handler.go:491–498: `agent_verdict=""` then `agent_verdict_wisp=""`) →
  `ActivateWisp(next)` → `active_wisp=<next>` →
  **`last_processed_wisp=<wisp>`** → best-effort `pending_next_wisp=""`
  (AFTER the marker; failure self-heals via `validPendingNextWisp`).
- **→ waiting_trigger** (handler.go:619–628): clear verdict pair →
  `active_wisp=""` → `state=waiting_trigger` →
  **`last_processed_wisp=<wisp>`**.
- **→ terminated, handler path** (handler.go:687–704): `terminal_reason` →
  `terminal_actor` → `state=terminated` → `CloseBead(root)` →
  **`last_processed_wisp=<wisp>`**. Note `terminal_reason`/`terminal_actor`
  BEFORE `state=terminated` — recovery keys off the reason being present.

### 7.3 Speculative pour — step 3b before gate eval (handler.go:244–275)

Pour next wisp (or adopt valid `pending_next_wisp`) → **then** write
`pending_next_wisp=<id>` (handler.go:268; on write failure the wisp is
burned) → then gate evaluation → then either adopt (7.2 iterate) or burn.
Burn = delete the wisp subtree FIRST, then clear `pending_next_wisp`
(handler.go:908–917). Pour is skipped when gate mode is manual /
hybrid-no-condition, when a trigger is enabled, or at max iterations
(handler.go:249–254).

### 7.4 Create (create.go:84–169)

`CreateConvergenceBead` (type=`convergence`, status=`in_progress`,
convergence_store.go:317–327) → `state=creating` → 12 config keys **in this
order**: `formula, target, max_iterations, gate_mode, gate_condition,
gate_timeout, gate_timeout_action, city_path, rig, evaluate_prompt, trigger,
trigger_condition` (create.go:103–121) → `var.*` (create.go:124–128) → then:

- trigger-gated: `iteration="0"` → `state=waiting_trigger` (no wisp poured);
- otherwise: `state=active` → pour wisp 1 (key `converge:<bead>:iter:1`) →
  `active_wisp` → `iteration="1"`.

Any failure rolls back via `state=terminated` + close (create.go:91–95).
`state=creating` must be written BEFORE the config keys — it is what lets the
reconciler classify a partial creation (reconcile.go:78–80,210–236).

### 7.5 Operator approve (manual.go:64–109)

`terminal_reason=approved` → `terminal_actor=operator:<u>` →
`waiting_reason=""` → `state=terminated` → emit Terminated (BEFORE close;
TierCritical) → `CloseBead` → emit ManualApprove (after close;
TierBestEffort) → **re-assert `last_processed_wisp` LAST** (only if it was
non-empty).

### 7.6 Operator iterate (manual.go:158–199)

**Pour BEFORE any state mutation** (failure leaves the bead safely in
waiting_manual) → clear verdict pair (only if scoped to last processed wisp)
→ `waiting_reason=""` → `state=active` → `active_wisp=<next>`.
`last_processed_wisp` is deliberately NOT written (the new wisp hasn't been
processed; manual.go:121–123).

### 7.7 Operator stop (manual.go:241–445)

Drain (if active wisp already closed, run `HandleWispClosed` first and
re-read metadata; terminated ⇒ no-op) → force-close still-open active wisp →
derive iteration count → clear BOTH verdict keys unconditionally
(manual.go:351–356) → `terminal_reason=stopped` → `terminal_actor` →
`waiting_reason=""` → `state=terminated` → synthetic iteration event (if
force-closed; before close) → Terminated event (before close) → `CloseBead` →
ManualStop event → **`last_processed_wisp` LAST** (= force-closed wisp if one
was force-closed, else prior value; manual.go:429–439).

### 7.8 Trigger advance (trigger.go:129–173)

Pour+activate next wisp FIRST (idempotency key makes re-pour crash-safe) →
`iteration=EncodeInt(next)` → `active_wisp=<next>` → `state=active` → emit
TriggerAdvance. No `last_processed_wisp` write (same rationale as 7.6).

### 7.9 Retry (retry.go:67–129)

New bead → `state=creating` → 12 keys in order: `formula, target, gate_mode,
gate_condition, gate_timeout, gate_timeout_action, max_iterations, city_path,
rig, evaluate_prompt, retry_source, state=active` (retry.go:88–106 — note
`state=active` is set via the batch here, unlike create) → copy `var.*` →
pour wisp 1 → `active_wisp` → `iteration="1"`.

### 7.10 Reconciler repairs (reconcile.go)

- creating → `terminal_reason=partial_creation` → `terminal_actor=recovery`
  → `state=terminated` → close (reconcile.go:210–236).
- terminal-transition completion: backfill `terminal_actor` → emit recovery
  Terminated → `state=terminated` (if needed) → close →
  **`last_processed_wisp` last, best-effort** (reconcile.go:545–600).
- missing state: adopt/pour wisp 1 → `active_wisp` → `iteration` ("0" or
  "1") → `state=active` → replay close if wisp already closed
  (reconcile.go:111–206).
- active with empty/stale `active_wisp`: adopt `pending_next_wisp` if valid,
  else find-by-key, else pour → activate → `active_wisp` → clear
  `pending_next_wisp` (reconcile.go:475–538).

### 7.11 Evaluation-order guards in `HandleWispClosed` (handler.go:161–390)

1. `state==terminated` ⇒ best-effort close + `skipped` (handler.go:171–175).
2. Monotonic dedup: wisp iteration (parsed from idempotency key
   `converge:<bead>:iter:<N>`, handler.go:19–39) `<=` last-processed wisp's
   iteration ⇒ `skipped`. Missing/corrupt last-processed wisp degrades to
   iteration 0 (handler.go:187–201).
3. Iteration repair: derived count (closed children with key prefix,
   handler.go:812–825) wins over stored `iteration`; disagreement triggers a
   metadata repair write (handler.go:208–214).
4. Gate config parsed BEFORE the speculative pour so invalid config can't
   leak a successor wisp (handler.go:218–242).
5. `skipGateEval` (replay) is decided from `gate_outcome_wisp == wispID`
   BEFORE anything else touches gate state (handler.go:233–234).
6. Timeout+manual is checked BEFORE the terminal switch (handler.go:344–351).

---

## 8. Adjacent (non-`convergence.*`) keys the port will encounter

These are co-resident on the same beads and must survive round-trips (raw
map preservation):

| Key | Owner | Use |
|---|---|---|
| `idempotency_key` | molecule pour | wisp identity `converge:<bead-id>:iter:<N>` (convergence_store.go:265,338) |
| `close_reason` | store adapter | stamped before every close with one of the `CloseReason*` constants (handler.go:46–55; convergence_store.go:116–123); bd's validation.on-close=error rejects reasons < 20 chars |
| `closed_at` | bd | RFC3339Nano close timestamp (convergence_store.go:340–344) |
| `gc.routed_to`, `gc.execution_routed_to` | gc routing | re-asserted on `ActivateWisp` (convergence_store.go:204–246) |
| `gc.deferred_assignee`, `gc.deferred_routed_to`, `gc.deferred_execution_routed_to`, `gc.deferred_type` | molecule | speculative-wisp deferred-activation markers (gascity/internal/molecule/molecule.go:60–73) |

---

## Porting traps

The details most likely to be transcribed wrongly, in rough order of damage:

1. **The schema is 31 keys, not 16.** The M2 build order's Track-A list is a
   subset. `convergence.pending_next_wisp` (`metadata.go:41`) is a real key
   and is load-bearing for crash recovery (ADR-0003 invariant 5); 14 further
   keys (`gate_retry_count`, `terminal_*`, `waiting_reason`, `retry_source`,
   `city_path`, `rig`, `evaluate_prompt`, `gate_stdout/err`,
   `gate_duration_ms`, `gate_truncated`, `trigger`, `trigger_condition`) plus
   the `var.*` namespace are equally part of the contract.

2. **bd type-coerces metadata values.** `--set-metadata convergence.iteration=3`
   stores JSON number `3`; `gate_truncated=true` stores boolean `true`;
   `"null"` stores `null` (beads/cmd/bd/update.go:619–638). gc reads through
   a tolerant `StringMap` that coerces non-strings back to literal text
   (bdstore.go:497–522). A Dart codec that assumes
   `Map<String, String>` straight from JSON will throw on real data.

3. **`gate_truncated` is `"true"` or `""` — never `"false"`.** Writing
   `"false"` is harmless on read (strict `== "true"`) but breaks byte-level
   conformance diffs; and through bd it would be stored as boolean `false`.

4. **`gate_duration_ms` is a decimal millisecond count; `gate_timeout` is a
   Go duration string.** Two different encodings for two duration-ish keys.
   The port must parse Go duration syntax (`"5m"`, `"1h30m"`, `"5m0s"` — the
   CLI default literal is `"5m0s"`, not `"5m"`) but never re-encode it:
   `EncodeDuration` has zero production callers; retry copies the original
   string verbatim.

5. **Clears are empty-string overwrites, not deletes.** Keys persist forever
   once written. Absent == `""` for every reader at this pin
   (`MetadataPresent` is dead code). A port that deletes keys (or that
   distinguishes null from `""`) will diverge in snapshots/diff tests.

6. **Two idempotency markers, two scopes.** `gate_outcome_wisp` commits gate
   persistence (last write of `persistGateOutcome`, handler.go:807);
   `last_processed_wisp` commits the whole transition (last write of every
   commit sequence). Swapping the order, or writing either early, silently
   breaks crash-replay: gates re-run with half-written results or completed
   iterations get re-processed/skipped.

7. **`pending_next_wisp` is cleared AFTER `last_processed_wisp` in the
   iterate path** (handler.go:560 then 565), and the clear is best-effort
   (`_ =`). The self-heal lives in `validPendingNextWisp`
   (handler.go:935–945): stale entries (wrong parent, wrong idempotency key,
   or closed) are cleared on next entry. Don't "fix" the ordering.

8. **Verdicts are scoped, normalized on read, and default to `block`.**
   The stored `agent_verdict` is raw agent text; `NormalizeVerdict` runs at
   read time; a verdict only counts when `agent_verdict_wisp` equals the wisp
   being processed; unknown/empty/mismatched ⇒ `block`
   (metadata.go:124–138; handler.go:319–324). The canonical
   approve-with-risks string is hyphenated **`approve-with-risks`** —
   note `approve-with-risk` (singular) is an accepted INPUT alias, not a
   canonical output.

9. **`iteration` is advisory.** Source of truth is the count of CLOSED child
   wisps whose `idempotency_key` starts with `converge:<bead>:iter:`
   (handler.go:812–825). The stored field is repaired when it disagrees
   (handler.go:208–214) and is `"0"` in two legitimate states (trigger-gated
   entry; recovery re-pour). Never drive transitions off the stored value.

10. **RetryHandler does NOT copy `trigger` / `trigger_condition`**
    (retry.go:88–101 — the copy list stops at `retry_source`). A retried
    trigger-gated loop silently becomes a plain wisp-close loop. Faithful
    port = reproduce the omission; flag it upstream rather than fixing it.

11. **`gate_outcome` is never written for pure-manual or hybrid-no-condition
    holds** — those paths return before step 5 (handler.go:300–316), so a
    waiting_manual bead can have an empty outcome plus `waiting_reason=
    manual|hybrid_no_condition`. But timeout-with-manual-action DOES persist
    `gate_outcome=timeout` before transitioning (persist at handler.go:331,
    transition at 345–351). `GateManualResult()` (`pass`) is an in-memory
    value for hybrid fallback, never persisted.

12. **`gate_exit_code` may be `""` (nil) or `"-1"`.** Nil for timeout and
    pre-exec error outcomes; `-1` from Go's `ExitCode()` on signal death.
    Model it as `int?`, encode `""` for null — not `"0"`.

13. **State writes have direction-dependent companions.** `state=terminated`
    must be PRECEDED by `terminal_reason` (+`terminal_actor`); the reconciler
    classifies an interrupted stop by `terminal_reason != ""` on a
    non-terminated state (reconcile.go:306,379,392). Writing state first
    creates an unclassifiable bead.

14. **`creating` is written before the config keys** (create.go:98 before
    103–121). Reordering breaks partial-creation detection: the reconciler
    terminates any `creating` bead unconditionally (reconcile.go:78–80).

15. **Retry's key order differs from create's** (`max_iterations` comes
    AFTER the gate keys, and `state=active` rides in the same write list,
    retry.go:88–101 vs create.go:103–116 where state transitions are
    separate). If the port batches via `bd batch`, conformance diffs against
    gc's per-key write sequence must account for both orders.

16. **`bd update --metadata` and `--set-metadata` are mutually exclusive**
    (beads/cmd/bd/update.go:274–277), and metadata keys must match
    `[a-zA-Z_][a-zA-Z0-9_.]*` (beads/internal/storage/metadata.go:215–219).
    Dotted keys are flat — JSON path `$."convergence.state"`, never nested
    objects (beads/internal/storage/metadata.go:226–231).

17. **`close_reason` must be ≥ 20 characters** (bd's validation.on-close
    validator; handler.go:41–55). Use gc's exact `CloseReason*` strings —
    shortening them makes closes fail.

18. **`agent_verdict` / `agent_verdict_wisp` are the ONLY agent-writable
    `convergence.*` keys; `var.*` is token-protected too** (acl.go:10–26).
    A port that lets agents (or the_grid's own non-reconciler paths) write
    other keys violates gc's single-writer assumption — see ADR-0003
    Decision 6 coexistence rules.

19. **Stdout/stderr truncation is byte-capped at 4096 with UTF-8
    rune-boundary backoff** (capture.go:13,47–69), and the truncated flag
    also trips on buffer overflow during capture (condition.go:334–345).
    Replicating "4096 chars" instead of "≤4096 bytes ending on a rune
    boundary" breaks replay fidelity diffs.
