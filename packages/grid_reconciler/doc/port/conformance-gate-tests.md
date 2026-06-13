# Conformance checklist — gate / hybrid / condition tests (Track H, gate slice)

**Status:** port spec, extracted 2026-06-12 against gascity pinned on disk
(`~/development/com.gastownhall/gascity`, bd 1.0.5 / f9fe4ef2a era).
**Authority:** ADR-0003 Decision 7 — gc's convergence tests are the executable spec; this
file inventories three of the six conformance sources (`gate_test.go`, `hybrid_test.go`,
`condition_test.go`) as a transliteration checklist for the Dart suite (M2 Track H,
implementing Track D).
**Go sources (READ-ONLY):**

| File | Lines | Tests what |
|---|---|---|
| `internal/convergence/gate_test.go` | 1–220 | `ParseGateConfig`, `NeedsConditionExecution`, `DefaultGateTimeout`, `GateManualResult` |
| `internal/convergence/hybrid_test.go` | 1–152 | `EvaluateHybrid`, `HybridNeedsManual` |
| `internal/convergence/condition_test.go` | 1–886 | `ConditionEnv.Environ`, `conditionPATH`, `ResolveConditionPath`, `RunCondition` |
| `internal/convergence/gate.go` | 1–99 | implementation under test |
| `internal/convergence/hybrid.go` | 1–28 | implementation under test |
| `internal/convergence/condition.go` | 1–404 | implementation under test |
| `internal/convergence/capture.go` | 1–69 | `MaxOutputBytes`, `boundedBuffer`, `TruncateOutput` |
| `internal/convergence/metadata.go` | 1–182 | every string constant referenced below |

All `file:line` references below are relative to
`/Users/nico/development/com.gastownhall/gascity/internal/` unless prefixed otherwise.

This document is self-contained: §1 reproduces every constant, type shape, and algorithm the
tests assert against, so a Dart implementer ports from here and uses the Go only to settle
disputes.

---

## 1. Domain reference (everything the tests assert against)

### 1.1 String-literal domains (metadata.go)

| Go identifier | Literal value | Source |
|---|---|---|
| `FieldGateMode` | `convergence.gate_mode` | metadata.go:18 |
| `FieldGateCondition` | `convergence.gate_condition` | metadata.go:19 |
| `FieldGateTimeout` | `convergence.gate_timeout` | metadata.go:20 |
| `FieldGateTimeoutAction` | `convergence.gate_timeout_action` | metadata.go:21 |
| `GateModeManual` | `manual` | metadata.go:67 |
| `GateModeCondition` | `condition` | metadata.go:68 |
| `GateModeHybrid` | `hybrid` | metadata.go:69 |
| `TimeoutActionIterate` | `iterate` | metadata.go:74 |
| `TimeoutActionRetry` | `retry` | metadata.go:75 |
| `TimeoutActionManual` | `manual` | metadata.go:76 |
| `TimeoutActionTerminate` | `terminate` | metadata.go:77 |
| `GatePass` | `pass` | metadata.go:90 |
| `GateFail` | `fail` | metadata.go:91 |
| `GateTimeout` | `timeout` | metadata.go:92 |
| `GateError` | `error` | metadata.go:93 |
| `VerdictApprove` | `approve` | metadata.go:106 |
| `VerdictApproveWithRisks` | `approve-with-risks` | metadata.go:107 |
| `VerdictBlock` | `block` | metadata.go:108 |
| `WaitHybridNoCondition` | `hybrid_no_condition` | metadata.go:99 (waiting_reason written by the handler when hybrid falls back to manual; not asserted in these three files but the destination of `HybridNeedsManual == true`) |

### 1.2 Numeric / path constants

| Go identifier | Value | Source |
|---|---|---|
| `DefaultGateTimeout` | `5 * time.Minute` (300 s) | gate.go:11 |
| `MaxGateRetries` | `3` | gate.go:14 |
| `MaxOutputBytes` | `4096` (bytes, per stream) | capture.go:13 |
| `SafePATH` | `/usr/local/bin:/usr/bin:/bin` | condition.go:20 |
| `textFileBusyRetryAttempts` | `5` | condition.go:23 |
| `textFileBusyRetryDelay` | `25 * time.Millisecond` | condition.go:24 |
| capture buffer size | `MaxOutputBytes + utf8.UTFMax` = `4100` | condition.go:334–335 |
| `cmd.WaitDelay` | `1 s` (post-kill pipe-drain grace) | condition.go:330 |

### 1.3 Value types

`GateConfig` (gate.go:17–22): `Mode string` · `Condition string` (script path, empty = none) ·
`Timeout Duration` · `TimeoutAction string`.

`GateResult` (gate.go:25–33):

| Field | Type | Semantics |
|---|---|---|
| `Outcome` | `string` | one of `pass` / `fail` / `timeout` / `error` |
| `ExitCode` | `*int` (**nullable**) | `0` on pass, script code on fail, **nil** on timeout / error / manual |
| `RetryCount` | `int` | retries actually performed before the final result (attempts − 1 on exhausted budget; `0` when no retry happened) |
| `Stdout` / `Stderr` | `string` | captured, truncated to `MaxOutputBytes` each |
| `Duration` | `Duration` | wall clock of the **final** attempt; `0` when nothing executed (manual) |
| `Truncated` | `bool` | true if either stream was truncated/overflowed |

`GateManualResult()` (gate.go:36–40) returns exactly
`GateResult(outcome: 'pass')` — every other field at its zero value (`ExitCode` **nil**,
`RetryCount` 0, `Stdout`/`Stderr` empty, `Duration` 0, `Truncated` false). ⚠ The manual path
re-uses outcome `pass`; there is **no** `manual` outcome value.

`ConditionEnv` (condition.go:57–73): `BeadID, Iteration, CityPath, StorePath, WorkDir, WispID,
DocPath, MoleculeDir, ArtifactDir, IterationDurationMs (int64), CumulativeDurationMs (int64),
MaxIterations, AgentVerdict, AgentProvider, AgentModel`.

### 1.4 `ParseGateConfig(meta) → GateConfig | error` (gate.go:44–85)

⚠ ordering — evaluation order is observable through which error fires first:

1. `mode := meta[FieldGateMode]`; empty/absent ⇒ `manual` (gate.go:45–48).
2. Mode validated against the 3-value set; anything else ⇒ error
   `parsing gate config: invalid gate mode %q` (gate.go:50–55).
3. `timeout := DefaultGateTimeout`; **only if** the key is present **and** non-empty
   (`ok && raw != ""`, gate.go:58) parse it as a **Go duration string** via `DecodeDuration`
   (metadata.go:165–174, `time.ParseDuration` semantics: `"30s"`, `"5m"`, `"1.5h"`,
   `"100ms"`, signs allowed). Parse failure ⇒ error
   `parsing gate config: invalid gate timeout %q`. Parsed but `<= 0` ⇒ error
   `parsing gate config: gate timeout must be positive, got %v` (two **distinct** error paths).
4. `timeoutAction := TimeoutActionIterate`; only if present and non-empty, validate against the
   4-value set; anything else ⇒ error
   `parsing gate config: invalid gate timeout action %q` (gate.go:69–77).
5. `Condition := meta[FieldGateCondition]` — read verbatim, **no validation at parse time**
   (existence/exec checks happen later in `ResolveConditionPath`).

### 1.5 `NeedsConditionExecution()` (gate.go:90–99) and `HybridNeedsManual` (hybrid.go:26–28)

- `manual` ⇒ `false` always (even if a condition path is set).
- `condition` / `hybrid` ⇒ `Condition != ""`.
- unknown mode ⇒ `false`.
- `HybridNeedsManual(cfg) == (cfg.Condition == "")` — mode is **not** checked here; callers
  guarantee hybrid.

### 1.6 `EvaluateHybrid(ctx, cfg, env, verdict) → GateResult` (hybrid.go:8–22)

⚠ ordering:

1. `HybridNeedsManual(cfg)` first ⇒ `GateManualResult()` (verdict never inspected, nothing
   executed).
2. Else `env.AgentVerdict = verdict` — injected **verbatim**, no `NormalizeVerdict`
   (normalization happened upstream when the verdict was written; ADR-0003 D3: "read, not
   reinterpreted"). Empty verdict ⇒ `GC_AGENT_VERDICT` is **omitted** from the child env
   (optional-var rule, §1.7), so the script sees the variable unset.
3. `retryBudget = MaxGateRetries (3)` **iff** `cfg.TimeoutAction == "retry"`, else `0`.
4. Delegate to `RunCondition(ctx, cfg.Condition, env, cfg.Timeout, retryBudget)`.

### 1.7 `ConditionEnv.Environ()` — the child-process env contract (condition.go:79–150)

The env is a **whitelist built from scratch** (never the parent env). Always present:

| Var | Value | Source |
|---|---|---|
| `PATH` | `conditionPATH()` (§1.8) | condition.go:91 |
| `HOME` | `CityPath`, or `os.TempDir()` if `CityPath == ""` — **deliberate sandbox** away from the operator's `~` | condition.go:82–85, 92 |
| `TMPDIR` | `os.TempDir()` | condition.go:93 |
| `BEADS_DIR` | `join(StorePath || CityPath, ".beads")` (StorePath wins when non-empty) | condition.go:86–89, 94 |
| `GC_BEAD_ID` | `BeadID` | condition.go:95 |
| `GC_ITERATION` | decimal `Iteration` | condition.go:96 |
| `GC_WISP_ID` | `WispID` | condition.go:97 |
| `GC_ITERATION_DURATION_MS` | decimal int64 | condition.go:98 |
| `GC_CUMULATIVE_DURATION_MS` | decimal int64 | condition.go:99 |
| `GC_MAX_ITERATIONS` | decimal | condition.go:100 |
| `GC_CITY` | `CityPath` | citylayout/runtime.go:127 (via condition.go:102) |
| `GC_CITY_PATH` | `CityPath` | citylayout/runtime.go:128 |
| `GC_CITY_RUNTIME_DIR` | `<CityPath>/.gc/runtime` by default; an ambient `GC_CITY_RUNTIME_DIR` override is honored **only** when ambient `GC_CITY_PATH`/`GC_CITY`/`GC_CITY_ROOT` already anchors the same city (citylayout/runtime.go:194–205) | citylayout/runtime.go:121–132 |
| `GC_CONTROL_DISPATCHER_TRACE_DEFAULT` | derived trace path | citylayout/runtime.go:130 — emitted but never asserted in these tests; the Dart port may drop it (record as ADR-0000 amendment if dropped) |

Optional — **emitted only when the field is non-empty** (absent ≠ empty-string-valued):

| Var | Field | Source |
|---|---|---|
| `GC_DOC_PATH` | `DocPath` | condition.go:105–107 |
| `GC_AGENT_VERDICT` | `AgentVerdict` | condition.go:108–110 |
| `GC_AGENT_PROVIDER` | `AgentProvider` | condition.go:111–113 |
| `GC_AGENT_MODEL` | `AgentModel` | condition.go:114–116 |
| `GC_WORK_DIR` | `WorkDir` | condition.go:117–119 |
| `GC_STORE_PATH` | `StorePath` | condition.go:120–122 |
| `GC_ARTIFACT_DIR` | `ArtifactDir` | condition.go:123–125 |
| `GC_MOLECULE_DIR` | `MoleculeDir` | condition.go:126–128 |

Pass-through from the **parent** process env, only when set there (condition.go:129–147):
`GC_INTEGRATION_REAL_BD`, then the Dolt/Beads connection set
`BEADS_DOLT_AUTO_START`, `BEADS_DOLT_SERVER_HOST`, `BEADS_DOLT_SERVER_PORT`,
`BEADS_DOLT_SERVER_USER`, `BEADS_DOLT_PASSWORD`, `GC_DOLT`, `GC_DOLT_HOST`, `GC_DOLT_PORT`,
`GC_DOLT_USER`, `GC_DOLT_PASSWORD`.

### 1.8 `conditionPATH()` (condition.go:31–53)

Ordered, de-duplicated `:`-join of: the directories containing `bd`, `gc`, `dolt`, `jq`
(in that lookup order, resolved via `LookPath` against the **ambient** `PATH`; missing tools
silently skipped) followed by the components of `SafePATH`
(`/usr/local/bin`, `/usr/bin`, `/bin`). Purpose: gate scripts use the running city's `bd`/`gc`
binaries, not stale copies in `/usr/local/bin`.

### 1.9 `ResolveConditionPath(envelope, base, conditionPath) → canonical path | error` (condition.go:191–263)

Two containment roots: `envelope` = security boundary (the city path); `base` = join target
for relative paths AND a second permitted boundary (the rig store — sibling layouts,
gastownhall/gascity#2354). ⚠ ordering — the steps run in exactly this order:

1. `conditionPath == ""` ⇒ error `resolving gate condition path: empty path`.
2. `envelope == ""` ⇒ error `resolving gate condition path: empty envelope` (an empty envelope
   would silently disable the traversal check).
3. `base == ""` ⇒ `base = envelope` (backward-compat single-root behavior).
4. Canonicalize `envelope` and `base` via `EvalSymlinks`, falling back to `Clean` if the root
   doesn't exist (condition.go:206–213). Required so macOS `/tmp → /private/tmp` doesn't cause
   false rejections.
5. Join: absolute `conditionPath` ⇒ `Clean(conditionPath)`; relative ⇒
   `Clean(join(canonBase, conditionPath))`.
6. **Pre-resolution containment** (relative paths only): the lexical join must satisfy
   `containedIn(absPath, canonEnvelope) || containedIn(absPath, canonBase)`; otherwise error
   `resolving gate condition path: path traversal not allowed: %s`. ⚠ **Absolute paths skip
   both containment checks entirely** — callers vouch for them (imported/registry packs live
   outside the city).
7. `EvalSymlinks(absPath)` — nonexistent file errors **here** (wrapped
   `resolving gate condition path: %w`).
8. **Post-resolution containment** (relative paths only): the symlink-resolved target must
   again be inside envelope OR base; otherwise error
   `resolving gate condition path: symlink target outside containment: %s` (closes the
   symlink-escape gap: `base/scripts/check.sh -> /etc/passwd`).
9. Stat the resolved path: must be a regular file
   (`resolving gate condition path: not a regular file: %s`) with **any** exec bit
   (`perm & 0o111 != 0`, else `resolving gate condition path: file is not executable: %s`).
10. Return the **symlink-resolved** canonical path — except note the `symlink allowed` test
    (§3, condition_test.go:234–251) compares against the *link* path via
    `AssertSamePath` (testutil/path.go:20–27), which canonicalizes **both** sides
    (`NormalizePathForCompare` ≈ abs + clean + EvalSymlinks), so link and target compare
    equal. The Dart assertion helper must canonicalize both sides the same way.

`containedIn` (condition.go:156–162) is lexical: `rel = Rel(root, absPath)`; outside iff
`rel == ".."` or `rel` starts with `../` (pathutil/pathutil.go:77–79). `rel == "."` (same dir)
is contained.

### 1.10 `RunCondition(ctx, scriptPath, env, timeout, retryBudget) → GateResult` (condition.go:269–287)

Retry loop, ⚠ ordering:

- Up to `retryBudget + 1` attempts of `runOnce`.
- Retry **only** when the attempt's outcome is `timeout` and budget remains; any other outcome
  returns immediately.
- The returned result is the **final attempt's** result with `RetryCount` = retries actually
  performed.

`runOnce` (condition.go:290–309) wraps each attempt with a **pre-exec text-file-busy retry**:
if the result is `GateError` and `Stderr` contains `text file busy` (case-insensitive,
condition.go:311–313), re-run up to `textFileBusyRetryAttempts` (5) times with a
`textFileBusyRetryDelay` (25 ms) sleep; a cancelled ctx aborts the sleep and returns the busy
result. This handles the POSIX `ETXTBSY` race when a script file is still open for write.

`runOnceNoPreExecRetry` (condition.go:315–404) — single execution:

- Working directory ⚠ ordering (condition.go:320–326): `CityPath`, overridden by `StorePath`
  if non-empty, overridden by `WorkDir` if non-empty (**WorkDir > StorePath > CityPath**).
- Env = `env.Environ()` (whitelist, §1.7). Stdout/stderr each captured into a bounded buffer
  of 4100 bytes (silently discards beyond that — `boundedBuffer`, capture.go:17–43), then
  `TruncateOutput` to 4096 backing off ≤ 3 bytes to a UTF-8 rune start (capture.go:47–69).
  `Truncated = outTrunc || errTrunc || stdoutOverflowed || stderrOverflowed`.
- Outcome classification, ⚠ **strict order** (condition.go:350–403):
  1. **Parent ctx cancelled** ⇒ `error` (Stdout/Stderr/Duration/Truncated kept, ExitCode nil).
     Checked FIRST so an external shutdown is never misclassified as a gate timeout — which
     would trigger retries against a dead parent.
  2. **Per-attempt deadline exceeded** ⇒ `timeout` (ExitCode **nil** even though the process
     was killed).
  3. **Exit error** (non-zero exit) ⇒ `fail`, `ExitCode = code`.
  4. **Other error** (not found, not executable, ETXTBSY) ⇒ `error`, `Stderr = err.Error()`
     (⚠ the captured stderr is **replaced** by the launcher error text on this path),
     ExitCode nil.
  5. **Success** ⇒ `pass`, `ExitCode = 0` (**non-nil zero**).

---

## 2. Mapping keys used in the checklist

**ADR-0003 invariants** `I1`…`I7` (monotonic dedup · write ordering · idempotency keys ·
iteration derivation · speculative pour · terminal irreversibility · single writer) and
**transition-table rows** `T1`…`T12` in ADR-0003 §Decision-2 order:

| Row | From | Trigger/Condition | To | Action |
|---|---|---|---|---|
| T1 | active | wisp closed ∧ gate=pass | terminated | `approved` |
| T2 | active | wisp closed ∧ gate=fail ∧ iter<max | active | `iterate` |
| T3 | active | wisp closed ∧ timeout ∧ action=manual | waitingManual | `waitingManual` |
| T4 | active | wisp closed ∧ timeout ∧ action=terminate | terminated | `noConvergence` |
| T5 | active | wisp closed ∧ iter≥max ∧ gate≠pass | terminated | `noConvergence` |
| T6 | active | wisp closed ∧ trigger enabled | waitingTrigger | `waitingTrigger` |
| T7 | active | wisp closed ∧ gate_mode=manual | waitingManual | `waitingManual` |
| T8–T12 | (operator / trigger / stop / creating rows — not exercised by these three files) | | | |

The three files inventoried here exercise **ADR-0003 Decision 3** (the gate execution
contract) — the *input* to rows T1–T5/T7 — not the state machine itself, so most rows below
cite `D3` plus the transition rows the tested behavior **feeds**. None of I1–I7 are directly
exercised (they live in `handler_test.go` / `reconcile_test.go`, separate inventory).

**Priority legend:** `must` = pure/portable domain behavior, conformance-blocking ·
`should` = valuable but coupled to OS/runtime details; port after the musts ·
`skip` = gc-runtime-specific, reason given.

**What the Dart fake/fixture layer must support (union over all rows below):**

1. Plain `Map<String, String>` metadata maps — **no bead store is needed anywhere in these
   three files** (the gate slice is store-free by design).
2. A temp-dir fixture helper that writes executable `#!/bin/sh` scripts (mode `0755`),
   creates nested dirs, and creates symlinks (these tests run **real subprocesses** — the gate
   runner's compatibility surface is the OS, per ADR-0003 D3 "Gate conditions as Dart
   closures — rejected").
3. An injectable environment reader: Go tests use `t.Setenv` / `os.Setenv`; Dart cannot mutate
   `Platform.environment`, so `Environ`/`conditionPATH` ports must take an env map (and a
   `lookPath` seam) — see Porting traps #1.
4. A cancellation token standing in for Go's `context.Context` (parent-cancel test).
5. A path-assert helper equivalent to `AssertSamePath` (canonicalize both sides:
   abs + clean + resolve symlinks) — macOS `/tmp` vs `/private/tmp`.

---

## 3. The checklist

### 3.1 `gate_test.go`

#### `TestParseGateConfig` (gate_test.go:8–142) — 10 table rows

- **Scenario:** given a `convergence.*` metadata map, when `ParseGateConfig` runs, then the
  typed `GateConfig` carries mode/condition/timeout/timeout-action with documented defaults,
  or parsing fails.
- **Maps to:** D3 (gate config codec); feeds T1/T2/T3/T4/T7 (which gate path the handler
  takes). Also Track A's metadata codec for the 4 gate keys.
- **Fixture:** metadata map only. Pure — no IO.
- **Priority: must** (all rows).

| # | Row name (Go) | Given (metadata) | Expected |
|---|---|---|---|
| 1 | `manual mode` | `{convergence.gate_mode: manual}` | `Mode=manual`, `Condition=""`, `Timeout=5m`, `TimeoutAction=iterate` |
| 2 | `condition mode with all fields` | `{gate_mode: condition, gate_condition: /path/to/check.sh, gate_timeout: "30s", gate_timeout_action: retry}` | `Mode=condition`, `Condition=/path/to/check.sh`, `Timeout=30s`, `TimeoutAction=retry` |
| 3 | `hybrid mode` | `{gate_mode: hybrid, gate_condition: /path/to/gate.sh}` | `Mode=hybrid`, `Condition=/path/to/gate.sh`, `Timeout=5m`, `TimeoutAction=iterate` |
| 4 | `defaults when mode is empty` | `{}` | `Mode=manual`, `Timeout=5m`, `TimeoutAction=iterate` |
| 5 | `defaults from nil map` | `null` map | same as row 4 (⚠ Dart port: accept absent/empty map without throwing) |
| 6 | `invalid mode` | `{gate_mode: auto}` | error (message contains `invalid gate mode "auto"`) |
| 7 | `invalid timeout` | `{gate_mode: condition, gate_timeout: not-a-duration}` | error (`invalid gate timeout`) |
| 8 | `negative timeout` | `{gate_mode: condition, gate_timeout: "-5s"}` | error — ⚠ `-5s` **parses** as a valid Go duration; the failure is the separate positivity check (`gate timeout must be positive`) |
| 9 | `invalid timeout action` | `{gate_mode: condition, gate_timeout_action: explode}` | error (`invalid gate timeout action`) |
| 10 | `all timeout actions are valid` | `{gate_mode: condition, gate_timeout_action: terminate}` | `TimeoutAction=terminate`, `Timeout=5m` (⚠ despite the name, only `terminate` is exercised; `manual` and explicit `iterate`/`retry`-without-timeout rows are coverage gaps, §5) |

Assertion granularity: all four `GateConfig` fields compared individually (gate_test.go:128–139).

#### `TestNeedsConditionExecution` (gate_test.go:144–189) — 6 table rows

- **Scenario:** given a `GateConfig`, when `NeedsConditionExecution()` is called, then it is
  true only for condition/hybrid mode **with** a non-empty condition path.
- **Maps to:** D3; selects between the script path (T1/T2) and the manual hold (T7 /
  `waiting_reason=hybrid_no_condition`).
- **Fixture:** none. Pure.
- **Priority: must** (all rows).

| # | Row name | Config | Expected |
|---|---|---|---|
| 1 | `manual mode always false` | `{Mode: manual}` | `false` |
| 2 | `manual mode with condition still false` | `{Mode: manual, Condition: /some/script}` | `false` ⚠ condition is ignored in manual mode |
| 3 | `condition mode with condition` | `{Mode: condition, Condition: /path/to/check.sh}` | `true` |
| 4 | `condition mode without condition` | `{Mode: condition}` | `false` |
| 5 | `hybrid mode with condition` | `{Mode: hybrid, Condition: /path/to/gate.sh}` | `true` |
| 6 | `hybrid mode without condition` | `{Mode: hybrid}` | `false` |

#### `TestDefaultGateTimeoutIs5Minutes` (gate_test.go:191–195)

- **Scenario:** constant pin — `DefaultGateTimeout == 5m` (raised from a former 60 s default
  to accommodate `make check`-class gates, gate.go:8–11).
- **Assertion:** `DefaultGateTimeout == 5 * time.Minute`.
- **Maps to:** D3. **Fixture:** none. **Priority: must** (one-line constant pin; cheap drift
  alarm).

#### `TestGateManualResult` (gate_test.go:197–220)

- **Scenario:** when the gate is manual (no script), then the synthetic result is `pass` with
  every other field zero.
- **Assertions (all 7):** `Outcome == "pass"` · `ExitCode == nil` · `RetryCount == 0` ·
  `Stdout == ""` · `Stderr == ""` · `Duration == 0` · `Truncated == false`.
- **Maps to:** D3; feeds T7 (manual hold) and the `waitingManual → approved` resume (T8) where
  this result is persisted.
- **Fixture:** none. **Priority: must.**

### 3.2 `hybrid_test.go`

#### `TestEvaluateHybridWithCondition` (hybrid_test.go:12–97) — 5 subtests

- **Scenario:** hybrid gate **with** a condition script: the script is executed with
  `GC_AGENT_VERDICT` injected; the script's exit code — not the verdict itself — decides the
  outcome.
- **Shared fixture:** temp dir; script `hybrid.sh` (mode `0755`) =
  `#!/bin/sh` + `if [ "$GC_AGENT_VERDICT" = "approve" ]; then echo "approved"; exit 0; else
  echo "rejected: $GC_AGENT_VERDICT" >&2; exit 1; fi` (hybrid_test.go:17–25);
  `ConditionEnv{BeadID: bh1, CityPath: dir, WispID: wh1, ArtifactDir: dir}`;
  `GateConfig{Mode: hybrid, Condition: script, Timeout: 5s, TimeoutAction: iterate}`.
- **Maps to:** D3 (verdict channel read, not reinterpreted); feeds T1 (pass⇒approved) and
  T2 (fail⇒iterate).
- **Dart fake must support:** real subprocess execution + script fixtures (item 2, §2).
- **Priority: must** (all 5).

| # | Subtest | When | Expected |
|---|---|---|---|
| 1 | `approve and pass` (44–52) | `EvaluateHybrid(cfg, env, "approve")` | `Outcome == "pass"`; `Stdout` contains `approved` |
| 2 | `approve and fail (script rejects)` (54–67) | same verdict, script replaced by `#!/bin/sh\nexit 1` | `Outcome == "fail"` ⚠ approve verdict does NOT override the script |
| 3 | `block and pass (script approves)` (69–82) | verdict `block`, script `#!/bin/sh\nexit 0` | `Outcome == "pass"` ⚠ block verdict does NOT override the script |
| 4 | `block and fail` (84–89) | verdict `block`, verdict-checking script | `Outcome == "fail"` |
| 5 | `empty verdict` (91–96) | verdict `""`, verdict-checking script | `Outcome == "fail"` — ⚠ via the **omitted-env-var** rule: `GC_AGENT_VERDICT` is absent (not empty) in the child env, the shell comparison fails, script exits 1. `EvaluateHybrid` itself has no empty-verdict branch. |

#### `TestEvaluateHybridWithoutCondition` (hybrid_test.go:99–125)

- **Scenario:** hybrid gate with `Condition: ""` falls back to manual: nothing executes.
- **Given:** `GateConfig{Mode: hybrid, Condition: "", Timeout: 5s, TimeoutAction: iterate}`,
  env `{BeadID: bh2, WispID: wh2}` with temp city/artifact dirs; verdict `approve`.
- **Assertions:** `Outcome == "pass"` · `ExitCode == nil` · `Duration == 0` (proof no process
  ran).
- **Maps to:** D3; feeds T7 — the handler converts this manual-fallback result into
  `waiting_manual` with `waiting_reason=hybrid_no_condition` (metadata.go:99).
- **Priority: must.**

#### `TestHybridNeedsManual` (hybrid_test.go:127–152) — 2 rows

- **Scenario:** the fallback predicate is exactly "no condition configured".
- Rows: `{Mode: hybrid, Condition: /path/to/gate.sh}` ⇒ `false`;
  `{Mode: hybrid, Condition: ""}` ⇒ `true`.
- **Maps to:** D3 / T7. **Fixture:** none (pure). **Priority: must.**

### 3.3 `condition_test.go`

#### `TestConditionEnvEnviron` (condition_test.go:15–80)

- **Scenario:** a fully-populated `ConditionEnv` emits the complete whitelist env.
- **Given:** `ConditionEnv{BeadID: bead-123, Iteration: 3, CityPath: /home/test/city,
  WispID: wisp-456, DocPath: /docs/review.md,
  MoleculeDir: /home/test/city/.gc/molecules/root-xyz, ArtifactDir: /tmp/artifacts,
  IterationDurationMs: 1500, CumulativeDurationMs: 4500, MaxIterations: 10,
  AgentVerdict: approve, AgentProvider: anthropic, AgentModel: claude-3}`.
- **Assertions (exact key=value):** `PATH` = `conditionPATH()` · `BEADS_DIR` =
  `/home/test/city/.beads` · `GC_BEAD_ID=bead-123` · `GC_ITERATION=3` ·
  `GC_CITY=/home/test/city` · `GC_CITY_PATH=/home/test/city` ·
  `GC_CITY_RUNTIME_DIR=/home/test/city/.gc/runtime` · `GC_WISP_ID=wisp-456` ·
  `GC_DOC_PATH=/docs/review.md` · `GC_MOLECULE_DIR=/home/test/city/.gc/molecules/root-xyz` ·
  `GC_ARTIFACT_DIR=/tmp/artifacts` · `GC_ITERATION_DURATION_MS=1500` ·
  `GC_CUMULATIVE_DURATION_MS=4500` · `GC_MAX_ITERATIONS=10` · `GC_AGENT_VERDICT=approve` ·
  `GC_AGENT_PROVIDER=anthropic` · `GC_AGENT_MODEL=claude-3`; plus `HOME` and `TMPDIR`
  present (values not pinned here — but see §5 gap 7).
- **Maps to:** D3 env contract verbatim (the M2 DoD item 3). No transition rows.
- **Dart fake must support:** injectable env reader (the test environment must control what
  `conditionPATH` resolves).
- **Priority: must.**

#### `TestConditionEnvEnvironOptionalEmpty` (condition_test.go:82–116)

- **Scenario:** empty optional fields are **omitted**, not emitted as empty strings.
- **Given:** `{BeadID: bead-789, Iteration: 1, CityPath: /city, WispID: wisp-abc}` — all
  optionals empty.
- **Assertions:** `GC_DOC_PATH`, `GC_AGENT_VERDICT`, `GC_AGENT_PROVIDER`, `GC_AGENT_MODEL`,
  `GC_MOLECULE_DIR`, `GC_ARTIFACT_DIR` are **absent** (key not present at all); `GC_BEAD_ID`
  and `PATH` still present. (Comment at 100–102 pins the rationale: matches the sling-time
  contract — a non-molecule bead gets neither var.)
- **Maps to:** D3. **Priority: must** — the absent-vs-empty distinction is what the hybrid
  `empty verdict` subtest depends on.

#### `TestConditionEnvEnvironPreservesIntegrationRealBD` (condition_test.go:118–141)

- **Scenario:** when the **parent** env has `GC_INTEGRATION_REAL_BD=/tmp/test-real-bd`
  (`t.Setenv`), the child env carries it through verbatim.
- **Maps to:** gc's Go integration harness (bd shim redirection). No ADR mapping.
- **Priority: skip** — the passthrough exists solely so gc's integration tests can shim `bd`;
  the_grid's test seam is the fake actuator/process-runner (CLAUDE.md: Fakes, not mocks). If
  the Dart port drops the variable, record it as an ADR-0000 amendment; if it keeps it, the
  test ports trivially alongside the Dolt passthrough test below.

#### `TestConditionEnvEnvironUsesStorePathForBeadsDir` (condition_test.go:143–169)

- **Scenario:** rig-scoped convergence: `StorePath` (the rig) overrides `CityPath` for
  `BEADS_DIR`, while `GC_CITY` keeps pointing at the city.
- **Given:** `{BeadID: bead-store, Iteration: 1, CityPath: /city, StorePath: /rig}`.
- **Assertions:** `BEADS_DIR == /rig/.beads` · `GC_STORE_PATH == /rig` · `GC_CITY == /city`.
- **Maps to:** D3; D6 coexistence (rig-scoped stores are the partition unit). **Priority:
  must.**

#### `TestConditionEnvEnvironPreservesDoltConnection` (condition_test.go:171–200)

- **Scenario:** Dolt server-mode connection vars flow from parent to gate script.
- **Given (parent env via `t.Setenv`):** `BEADS_DOLT_SERVER_PORT=33061`,
  `GC_DOLT_HOST=127.0.0.1`, `GC_DOLT_PASSWORD=secret`.
- **Assertions:** all three present with exactly those values in the child env.
- **Maps to:** D3; environment facts (the_grid runs Dolt server mode — this passthrough is
  load-bearing for any gate that shells out to `bd`). **Priority: must** (with the injected
  env-reader seam).

#### `TestResolveConditionPath` (condition_test.go:202–523) — 14 subtests

- **Scenario family:** path resolution + the traversal/symlink containment defenses
  (D3: "Path resolution keeps the traversal/symlink containment defenses").
- **Fixture:** temp dirs, scripts mode `0755`, symlinks; assertion helper canonicalizes both
  sides (§1.9 step 10).
- **Maps to:** D3. No transition rows.

| # | Subtest (line) | Given / When | Expected | Priority |
|---|---|---|---|---|
| 1 | `absolute path` (203) | existing executable script; `ResolveConditionPath("/some/city", "/some/city", <abs script>)` — envelope/base unrelated to the script | resolves to the script (⚠ absolute paths skip containment; envelope needn't exist) | must |
| 2 | `relative path` (217) | script at `<dir>/gates/check.sh`; call `(dir, dir, "gates/check.sh")` | resolves to the script | must |
| 3 | `symlink allowed` (234) | `link.sh → real.sh`, both under root; call `(dir, dir, "link.sh")` | resolves; compares equal to the **link** path after canonicalization of both sides | must |
| 4 | `path traversal rejection` (253) | script outside the root; call `(dir, dir, "../outside.sh")` | error; message contains `traversal` | must |
| 5 | `empty path` (272) | `(city, city, "")` | error (`empty path`) | must |
| 6 | `nonexistent file` (279) | `(city, city, "/nonexistent/file.sh")` | error (fails at `EvalSymlinks`, step 7) | must |
| 7 | `rig-scoped: relative path escapes base but stays inside envelope` (293) | envelope=`city`, base=`city/frontend` (rig subtree), script at `city/scripts/check.sh`; path `../scripts/check.sh` | resolves — pins gastownhall/gascity#2320 (the envelope/base split; single-root logic would wrongly reject) | must |
| 8 | `rig-scoped: traversal outside envelope and base rejected` (321) | same layout; path `../../outside.sh` to a script above the city | error containing `traversal` | must |
| 9 | `sibling layout: relative path under base stays inside base` (351) | envelope=`parent/city`, base=`parent/rig` (siblings); script `rig/assets/pack/scripts/check.sh`; path `assets/pack/scripts/check.sh` | resolves — pins gastownhall/gascity#2354 (base is a second permitted root even outside envelope) | must |
| 10 | `sibling layout: traversal outside both envelope and base rejected` (376) | siblings; path `../evil.sh` to `parent/evil.sh` | error containing `traversal` | must |
| 11 | `symlink under base targeting outside both roots is rejected` (407) | `rig/scripts/check.sh → parent/outside.sh`; path `scripts/check.sh` (passes the **pre**-check) | error containing `symlink target outside containment` (the **post**-EvalSymlinks check). Go skips on Windows | must |
| 12 | `empty base falls back to envelope` (443) | `(dir, "", "gates/check.sh")` | resolves (base := envelope) | must |
| 13 | `sibling layout: relative path under base stays inside base` (467) | byte-identical duplicate of #9 (Go dedups the name as `…#01`) | — | skip — duplicate of #9; port once |
| 14 | `sibling layout: traversal outside both envelope and base rejected` (499) | byte-identical duplicate of #10 | — | skip — duplicate of #10; port once |

#### `TestRunConditionPass` (condition_test.go:525–552)

- **Scenario:** script exits 0 ⇒ pass with captured stdout.
- **Given:** `pass.sh` = `#!/bin/sh\necho ok`; env `{BeadID: b1, CityPath: dir, WispID: w1,
  ArtifactDir: dir}`; `RunCondition(ctx, script, env, 5s, retryBudget: 0)`.
- **Assertions:** `Outcome == "pass"` · `ExitCode != nil && *ExitCode == 0` ⚠ non-nil zero ·
  `Stdout` contains `ok` · `Duration > 0`.
- **Maps to:** D3 exit-code contract; feeds T1. **Priority: must.**

#### `TestRunConditionFail` (condition_test.go:554–578)

- **Scenario:** script exits 1 ⇒ fail with captured stderr.
- **Given:** `fail.sh` = `#!/bin/sh\necho failing >&2\nexit 1`.
- **Assertions:** `Outcome == "fail"` · `*ExitCode == 1` · `Stderr` contains `failing`.
- **Maps to:** D3; feeds T2/T5. **Priority: must.**

#### `TestRunConditionRetriesTextFileBusy` (condition_test.go:580–613)

- **Scenario:** the script file is held open for write (POSIX `ETXTBSY` on exec); a goroutine
  closes it after 50 ms; the pre-exec retry loop (≤5 × 25 ms) eventually executes it.
- **Assertions:** `Outcome == "pass"` · `trim(Stdout) == "ok"`. (Go skips on Windows.)
- **Maps to:** D3 robustness (the gate file is often freshly written by a pack install).
- **Priority: should** — OS-specific launch-failure classification; whether Dart's
  `ProcessException` surfaces `Text file busy` in its message must be verified on macOS/Linux
  before transliterating the string match (see Porting traps #10).

#### `TestRunConditionUsesWorkDir` (condition_test.go:615–652)

- **Scenario:** `WorkDir` set ⇒ the script's cwd is `WorkDir` while `BEADS_DIR` still derives
  from `CityPath`.
- **Given:** `workDir = <city>/work` containing `target.txt` (`ok`); script prints `pwd`,
  `$BEADS_DIR`, and `cat target.txt`; env `{CityPath: city, WorkDir: workDir, …}`.
- **Assertions:** pass · `Stdout` contains `workDir` (the pwd) · contains `<city>/.beads` ·
  contains `ok` (relative read proves cwd).
- **Maps to:** D3 (cwd precedence, §1.10). **Priority: must.**

#### `TestRunConditionUsesStorePathAsDefaultWorkDir` (condition_test.go:654–686)

- **Scenario:** no `WorkDir`, `StorePath` set ⇒ cwd = `StorePath` and `BEADS_DIR` =
  `<StorePath>/.beads`.
- **Assertions:** pass · `Stdout` contains the store dir (pwd) · contains
  `<storeDir>/.beads` · contains `ok`.
- **Maps to:** D3; D6 (rig-scoped store). **Priority: must.**

#### `TestConditionPATHUsesResolvedToolDirs` (condition_test.go:688–709)

- **Scenario:** with fake `bd` and `gc` executables in a temp dir prepended to the ambient
  `PATH`, `conditionPATH()` puts that tool dir **first**.
- **Assertions:** result starts with `toolDir + ":"` (or equals `toolDir`).
- **Maps to:** D3 (gates must call the live city's `bd`/`gc`).
- **Priority: should** — the behavior is must-have for Track D, but the test mutates the
  ambient process `PATH`; the Dart port must instead inject the env map + lookPath seam, so
  the test is a rewrite, not a transliteration.

#### `TestRunConditionTimeout` (condition_test.go:711–732)

- **Scenario:** `sleep 60` script with a 100 ms timeout, budget 0.
- **Assertions:** `Outcome == "timeout"` · `ExitCode == nil` ⚠ (the process was SIGKILLed, but
  timeout reports nil, not the kill code).
- **Maps to:** D3 deadline contract; feeds T3/T4 (timeout-action rows). **Priority: must.**

#### `TestRunConditionTimeoutRetry` (condition_test.go:734–755)

- **Scenario:** same slow script, 100 ms timeout, `retryBudget: 2` ⇒ 3 attempts, all timeout.
- **Assertions:** `Outcome == "timeout"` · `RetryCount == 2` (retries, not attempts).
- **Maps to:** D3 timeout-action `retry` (≤ `MaxGateRetries`=3 when driven from
  `EvaluateHybrid`/handler); feeds T3/T4. **Priority: must.**

#### `TestRunConditionNotFound` (condition_test.go:757–769)

- **Scenario:** script path `/nonexistent/script.sh` ⇒ launch failure.
- **Assertions:** `Outcome == "error"` (pre-exec failure class, NOT `fail`).
- **Maps to:** D3 (`pre-exec=error`). **Priority: must.**

#### `TestRunConditionOutputCapture` (condition_test.go:771–796)

- **Scenario:** script writes `stdout-data` to stdout and `stderr-data` to stderr.
- **Assertions:** `Stdout` contains `stdout-data` · `Stderr` contains `stderr-data` ·
  `Truncated == false`.
- **Maps to:** D3 (stdout/stderr captured into metadata `convergence.gate_stdout`/`gate_stderr`
  downstream). **Priority: must.**

#### `TestRunConditionOutputTruncation` (condition_test.go:798–825)

- **Scenario:** script emits 5096 bytes (`printf '%0*d' 5096 0`) > `MaxOutputBytes` (4096).
- **Assertions:** `Outcome == "pass"` · `len(Stdout) <= 4096` · `Truncated == true`.
- **Maps to:** D3 (truncate into metadata). **Priority: must.**

#### `TestRunConditionParentContextCancelled` (condition_test.go:827–854)

- **Scenario:** the parent context is cancelled **before** the call; slow script, 5 s timeout,
  `retryBudget: 2`.
- **Assertions:** `Outcome == "error"` (NOT `timeout` — classification order §1.10) ·
  `RetryCount == 0` (no retries against a dead parent).
- **Maps to:** D3; reconciler shutdown safety (Track G teardown must not spin the retry loop).
- **Priority: should** — the rule is mandatory but the mechanism maps to whatever cancellation
  primitive the Dart gate runner adopts (no `context.Context` in Dart); transliterate once
  Track D pins its cancellation seam.

#### `TestRunConditionEnvVarsAvailable` (condition_test.go:856–886)

- **Scenario:** end-to-end: the child process actually observes the whitelist env.
- **Given:** script prints `BEAD=$GC_BEAD_ID`, `ITER=$GC_ITERATION`, `PATH=$PATH`;
  env `{BeadID: bead-env-test, Iteration: 7, …}`.
- **Assertions:** pass · `Stdout` contains `BEAD=bead-env-test` · contains `ITER=7` ·
  contains `PATH=` + `conditionPATH()` (the exact resolved value).
- **Maps to:** D3 (DoD item 3: "env … verified"). **Priority: must.**

---

## 4. Count summary

| File | Test functions | Conformance cases (incl. table rows / subtests) | must | should | skip |
|---|---|---|---|---|---|
| `gate_test.go` | 4 | 18 | 18 | 0 | 0 |
| `hybrid_test.go` | 3 | 8 | 8 | 0 | 0 |
| `condition_test.go` | 19 | 32 | 26 | 3 | 3 |
| **Total** | **26** | **58** | **52** | **3** | **3** |

skip = `TestConditionEnvEnvironPreservesIntegrationRealBD` (gc Go-integration bd shim) + the
two byte-identical duplicate `ResolveConditionPath` subtests (port once each).
should = `RetriesTextFileBusy`, `ConditionPATHUsesResolvedToolDirs`,
`ParentContextCancelled` (OS/launcher/cancellation-seam coupled — behavior required, test
shape needs adaptation).

---

## 5. Coverage gaps — behaviors NO test covers; the Dart suite should add

1. **`ParseGateConfig` present-but-empty values**: `{gate_timeout: ""}` and
   `{gate_timeout_action: ""}` must yield the defaults, not errors (`ok && raw != ""` guards,
   gate.go:58, 70). One transcription slip turns these into hard failures on real metadata.
2. **`ParseGateConfig` timeout actions `manual` and explicit `iterate`/`retry`-with-timeout**:
   the "all timeout actions are valid" row only exercises `terminate`. Add rows for all four.
3. **`EvaluateHybrid` retry budget wiring**: no test proves
   `TimeoutAction == retry ⇒ retryBudget == MaxGateRetries (3)` (hybrid.go:16–19). Add: hybrid
   + sleeping script + `retry` ⇒ `RetryCount == 3`; and + `iterate` ⇒ `RetryCount == 0`.
4. **Retry-then-success**: `RunCondition` with a script that times out once then passes
   (e.g. a marker file flips behavior). Expect `Outcome == pass`, `RetryCount == 1` — pins
   "retry only on timeout, return first non-timeout result" (condition.go:277).
5. **Non-0/1 exit codes**: `exit 42` ⇒ `fail`, `*ExitCode == 42`. Also a signal-killed script
   (no timeout) — Go reports `ExitCode() == -1` ⇒ `fail` with `-1`; decide and pin the Dart
   equivalent (Dart `Process` reports negative exit codes for signals too).
6. **`ResolveConditionPath` absolute path OUTSIDE both roots is accepted** (the
   "callers vouch" contract, condition.go:226, 244) — only the inside case is tested. Also:
   resolved path is a directory ⇒ `not a regular file`; mode `0644` ⇒
   `file is not executable` (condition.go:255–260).
7. **`HOME` sandbox value**: tests assert `HOME` exists but never that
   `HOME == CityPath` (and `os.TempDir()` when CityPath is empty) — the sandbox rationale
   (condition.go:80–85) deserves a pin.
8. **`GC_WORK_DIR` emission**: `WorkDir` is asserted via cwd, never via the env var
   (condition.go:117–119). One assert closes it.
9. **cwd precedence with all three set**: CityPath + StorePath + WorkDir together ⇒ WorkDir
   wins (condition.go:320–326). Tests cover only pairwise cases.
10. **Truncation corner cases** (the unit tests live in `capture_test.go`, outside this
    inventory — Track H must pick them up or re-derive): stderr-only overflow sets
    `Truncated`; UTF-8 rune-boundary backoff (≤3 bytes, capture.go:61–67); buffer overflow
    beyond 4100 silently discards while `cmd` keeps writing (capture.go:27–40); `maxBytes<=0`
    edge (capture.go:48–53).
11. **Timeout with partial output**: a script that prints then sleeps past the deadline —
    pins that `timeout` results still carry captured `Stdout`/`Stderr`
    (condition.go:362–368).
12. **Verdict variants through hybrid**: `approve-with-risks` (and the past-tense forms
    handled by `NormalizeVerdict`, metadata.go:113–138 — normalization is upstream of
    `EvaluateHybrid`, but the Dart suite should pin where it does/doesn't happen).
13. **`conditionPATH` de-duplication** (a tool dir that is also in `SafePATH` appears once,
    condition.go:34–43) and the missing-tool fallback (no `bd`/`gc`/`dolt`/`jq` on PATH ⇒
    result == `SafePATH`).
14. **Error-path stderr replacement**: on `error` outcomes the launcher error text replaces
    captured stderr (condition.go:385–391) — observable, untested, easy to port wrongly.

---

## Porting traps

1. **Ambient-env reads are buried in pure-looking functions.** `Environ()` calls `os.Getenv`
   for the passthrough set and `os.TempDir()`; `conditionPATH()` calls `exec.LookPath` against
   ambient `PATH` (condition.go:31–53, 93, 129–147). Dart cannot `setenv`. Port both as
   functions over an injected `Map<String, String> environment` (+ a lookPath seam), or the
   five env tests are untestable and `grid_reconciler` grows hidden global state.
2. **Absent ≠ empty.** Optional env vars are omitted entirely when the field is empty
   (condition.go:104–128). Emitting `GC_AGENT_VERDICT=""` instead of omitting it silently
   flips the hybrid `empty verdict` subtest (the shell `[ "$GC_AGENT_VERDICT" = "approve" ]`
   sees empty either way, but real gate scripts using `${VAR+set}` / `-z` distinguish). Same
   for `ParseGateConfig`: present-but-empty `gate_timeout` ⇒ default, not error.
3. **`ExitCode` is nullable and `pass` carries a non-nil 0.** pass ⇒ `0` (non-nil); fail ⇒
   code; timeout/error/manual ⇒ null (gate.go:27, condition.go:351–403). Modeling it as
   `int exitCode = 0` or making pass null breaks three tests and the
   `convergence.gate_exit_code` metadata write downstream.
4. **There is no `manual` gate outcome.** Manual and hybrid-fallback both return outcome
   `pass` with everything else zero (gate.go:36–40). Inventing a `manual` outcome value
   corrupts the gate-persistence metadata domain (`convergence.gate_outcome` ∈
   {`pass`,`fail`,`timeout`,`error`} only).
5. **⚠ Classification order in the runner** (condition.go:350–403): parent-cancel → `error`
   (RetryCount 0, never retried) BEFORE deadline → `timeout` BEFORE exit-code → `fail`/`pass`.
   Swapping the first two turns reconciler shutdown into a 3×-timeout retry storm — the exact
   bug the Go comment warns about. And only `timeout` is retried (condition.go:277); retrying
   `error` re-runs missing scripts forever.
6. **`RetryCount` counts retries, not attempts** (budget 2 ⇒ 3 executions, `RetryCount == 2`),
   and is stamped on the final attempt's result only (condition.go:271–286).
7. **Go duration strings.** `gate_timeout` metadata uses `time.ParseDuration` grammar
   (`"30s"`, `"5m"`, `"1.5h"`, `"-5s"` parses fine). Dart must implement a Go-compatible
   parser; `Duration.parse` does not exist and ISO-8601 parsing will reject every fixture.
   Negative is a *positivity* error, not a parse error — two distinct messages
   (gate.go:59–66).
8. **⚠ `ResolveConditionPath` check order and the relative-only rule**: canonicalize
   envelope/base FIRST (EvalSymlinks, with Clean fallback for nonexistent roots) → lexical
   pre-check → EvalSymlinks of the candidate → post-check → regular-file + exec-bit stat.
   Both containment checks apply **only to relative** `conditionPath`; absolute paths bypass
   containment by contract (condition.go:216–248). Applying containment to absolute paths
   breaks imported-pack gates; skipping the post-check reopens the symlink escape.
9. **macOS `/tmp` symlink.** Skipping root canonicalization makes every temp-dir containment
   test fail on macOS (`/tmp` → `/private/tmp`, condition.go:202–213); equally, the Dart
   `AssertSamePath` equivalent must canonicalize BOTH sides (testutil/path.go:15–27) or the
   `symlink allowed` subtest fails spuriously.
10. **`text file busy` is a *pre-exec* retry inside `runOnce`, separate from the timeout
    retry in `RunCondition`** — 5 attempts × 25 ms, triggered by case-insensitive substring
    `text file busy` in stderr of an `error` result (condition.go:290–313). In Dart the
    launcher failure is a thrown `ProcessException`, not a result — the port must map it into
    the `error` result first, and must verify the platform message actually contains that
    substring.
11. **Bounded capture is two-stage**: buffers accept `4096 + 4` bytes then silently discard
    (returning success so the child's pipe never breaks, capture.go:31); `TruncateOutput`
    trims to 4096 backing off ≤3 bytes to a rune start; `Truncated` ORs four flags
    (condition.go:334–345). Naive "read all then substring" changes both the byte count and
    the blocking behavior of chatty scripts.
12. **Working-dir precedence is WorkDir > StorePath > CityPath** (condition.go:320–326) while
    `BEADS_DIR` ignores `WorkDir` and uses StorePath > CityPath (condition.go:86–94). Two
    different fallback chains over the same three fields — easy to unify wrongly.
13. **`HybridNeedsManual` ignores `Mode`** (hybrid.go:26–28) — it's only meaningful for
    hybrid configs, and `NeedsConditionExecution` is the mode-aware predicate; manual mode
    with a configured condition still never executes (gate_test.go:155–159).
14. **Duplicate Go subtest names** in `TestResolveConditionPath` (condition_test.go:351≡467,
    376≡499 — Go auto-suffixes `#01`). Port each behavior once; blindly transliterating all
    14 produces duplicate-name failures or dead weight in `package:test`.
15. **`GateConfig.Condition` is unvalidated at parse time** (gate.go:81) — existence/exec
    checks happen at evaluation via `ResolveConditionPath`. Validating the path inside the
    Dart `ParseGateConfig` port changes when (and which) error surfaces and breaks the
    `condition mode with all fields` row (the path `/path/to/check.sh` doesn't exist).
16. **`GC_CITY_RUNTIME_DIR` default is `<CityPath>/.gc/runtime`** (citylayout/runtime.go:23–25,
    121–132) and the ambient override is trusted only when the ambient env already anchors the
    same city (runtime.go:194–205). The extra `GC_CONTROL_DISPATCHER_TRACE_DEFAULT` var rides
    along in gc; dropping or keeping it in the Dart port is an ADR-0000-recordable decision —
    no test pins it.
