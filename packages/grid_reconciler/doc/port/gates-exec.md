# Port spec — gate execution (`gates-exec`)

**Scope:** M2 Track D (`docs/M2-BUILD-ORDER.md`) per ADR-0003 Decision 3 — the subprocess gate
runner ported from gc's convergence package.
**Go sources of truth (read-only, pinned on disk):** `gascity/internal/convergence/` —
`gate.go`, `condition.go`, `hybrid.go`, `retry.go`, `artifact.go`, `capture.go`, plus the
integration points in `handler.go`, `metadata.go`, `evaluate.go`, `acl.go`, `token.go`,
`template.go`, `trigger.go`, and `gascity/internal/citylayout/runtime.go`,
`gascity/internal/pathutil/pathutil.go`.
All `file:line` references below are relative to
`/Users/nico/development/com.gastownhall/gascity/` unless prefixed otherwise.
**Extracted:** 2026-06-12 against the pinned gascity working tree (convergence files dated
2026-05-31/2026-06-08).

This spec is self-contained: a Dart implementer ports from this document; the Go is the
tie-breaker, never the day-to-day reference. The conformance oracle is
`internal/convergence/{gate,condition,hybrid,capture,artifact,retry}_test.go` (ADR-0003 D7).

---

## 0. Constants and types

| Identifier | Value | Source |
|---|---|---|
| `DefaultGateTimeout` | 5 minutes | `internal/convergence/gate.go:11` |
| `MaxGateRetries` | `3` (timeout-retry cap) | `internal/convergence/gate.go:14` |
| `MaxOutputBytes` | `4096` (bytes, per stream) | `internal/convergence/capture.go:13` |
| `SafePATH` | `/usr/local/bin:/usr/bin:/bin` | `internal/convergence/condition.go:20` |
| `textFileBusyRetryAttempts` | `5` | `internal/convergence/condition.go:23` |
| `textFileBusyRetryDelay` | 25 ms | `internal/convergence/condition.go:24` |
| `TokenEnvVar` | `GC_CONTROLLER_TOKEN` | `internal/convergence/token.go:15` |

**`GateConfig`** (`gate.go:17-22`): `Mode` (`"manual"`/`"condition"`/`"hybrid"`), `Condition`
(script path, empty for manual-only), `Timeout` (duration, default 5m), `TimeoutAction`
(`"iterate"`/`"retry"`/`"manual"`/`"terminate"`).

**`GateResult`** (`gate.go:25-33`): `Outcome` (`"pass"`/`"fail"`/`"timeout"`/`"error"` —
constants `GatePass`/`GateFail`/`GateTimeout`/`GateError`, `metadata.go:89-94`), `ExitCode`
(nullable int — null for manual mode, timeout, and pre-exec error), `RetryCount` (number of
timeout retries before the final attempt), `Stdout`, `Stderr` (truncated), `Duration`
(wall-clock of the **final** attempt), `Truncated` (bool).

**`GateManualResult()`** (`gate.go:36-40`): `GateResult{Outcome: GatePass}` — pass with **null**
exit code, used for manual-mode and hybrid-no-condition short-circuits.

### Gate config parsing — `ParseGateConfig(meta)` (`gate.go:44-85`)

Input is the root convergence bead's metadata map. Key domain
(`metadata.go:18-21`):

| Metadata key | Field | Default when absent/empty | Validation |
|---|---|---|---|
| `convergence.gate_mode` | `Mode` | `"manual"` (`gate.go:46-48`) | must be `manual`/`condition`/`hybrid`, else error `invalid gate mode %q` (`gate.go:50-55`) |
| `convergence.gate_condition` | `Condition` | `""` (taken verbatim, `gate.go:81`) | none here |
| `convergence.gate_timeout` | `Timeout` | `DefaultGateTimeout` (5m) | parsed with **Go `time.ParseDuration` syntax** (`DecodeDuration`, `metadata.go:165-174`); invalid → error; `<= 0` → error `gate timeout must be positive` (`gate.go:57-67`) |
| `convergence.gate_timeout_action` | `TimeoutAction` | `"iterate"` (`gate.go:69`) | must be one of the four actions, else error `invalid gate timeout action %q` (`gate.go:70-77`) |

`NeedsConditionExecution()` (`gate.go:90-99`): `manual` → false; `condition`/`hybrid` →
`Condition != ""`; anything else → false.

⚠ **ordering** — `ParseGateConfig` runs at handler **step 3**, *before* the speculative pour
(`handler.go:218-223`), so invalid config never leaves a successor wisp behind.

---

## 1. Subprocess env contract (verbatim)

Built by `ConditionEnv.Environ()` (`condition.go:79-150`). The environment is a **whitelist
built from scratch** — the parent process env is *not* inherited; only the listed ambient
variables are read through `os.Getenv`. `GC_CONTROLLER_TOKEN` is therefore never present in a
gate script env (see also `ScrubTokenEnv`, `acl.go:30-41`).

`ConditionEnv` struct fields (`condition.go:57-73`): `BeadID`, `Iteration`, `CityPath`,
`StorePath`, `WorkDir`, `WispID`, `DocPath`, `MoleculeDir`, `ArtifactDir`,
`IterationDurationMs`, `CumulativeDurationMs`, `MaxIterations`, `AgentVerdict`,
`AgentProvider`, `AgentModel`.

### 1a. Always-present variables, in append order

| # | Env var | Exact value | Provenance |
|---|---|---|---|
| 1 | `PATH` | `conditionPATH()` — see 1d | `condition.go:91` |
| 2 | `HOME` | `CityPath`; if `CityPath == ""` then `os.TempDir()` (sandboxes scripts away from the real home with `.ssh`/`.gnupg`) | `condition.go:80-86,92` |
| 3 | `TMPDIR` | `os.TempDir()` | `condition.go:93` |
| 4 | `BEADS_DIR` | `filepath.Join(storePath, ".beads")` where `storePath = StorePath`, falling back to `CityPath` when empty | `condition.go:86-89,94` |
| 5 | `GC_BEAD_ID` | `BeadID` — the **root convergence bead ID**, not the wisp (handler passes `rootBeadID`, `handler.go:745`; ralph passes the subject/attempt bead, `internal/dispatch/ralph.go:224-229,242`) | `condition.go:95` |
| 6 | `GC_ITERATION` | `strconv.Itoa(Iteration)` — handler passes the **just-closed wisp's iteration** (`handler.go:327,746`); trigger passes `nextIteration` (`trigger.go:113`) | `condition.go:96` |
| 7 | `GC_WISP_ID` | `WispID` — the just-closed wisp (`handler.go:749`); may be the empty string in non-handler callers (still emitted as `GC_WISP_ID=`) | `condition.go:97` |
| 8 | `GC_ITERATION_DURATION_MS` | `strconv.FormatInt(IterationDurationMs, 10)` — `closedAt − createdAt` of the closed wisp, ms (`handler.go:755-756`, `computeDurations` `handler.go:829-850`) | `condition.go:98` |
| 9 | `GC_CUMULATIVE_DURATION_MS` | sum of `closedAt − createdAt` over all **closed** children whose idempotency key has prefix `converge:<rootID>:iter:` (`handler.go:837-848`) | `condition.go:99` |
| 10 | `GC_MAX_ITERATIONS` | `strconv.Itoa(MaxIterations)` — from `convergence.max_iterations` (`handler.go:759-760`) | `condition.go:100` |
| 11 | `GC_CITY` | `CityPath` (cityRoot) | `internal/citylayout/runtime.go:127` via `condition.go:102` |
| 12 | `GC_CITY_PATH` | `CityPath` | `internal/citylayout/runtime.go:128` |
| 13 | `GC_CITY_RUNTIME_DIR` | runtimeDir — see 1c | `internal/citylayout/runtime.go:129` |
| 14 | `GC_CONTROL_DISPATCHER_TRACE_DEFAULT` | `<runtimeDir>/control-dispatcher-trace.log` after runtime-dir normalization (`runtime.go:38-41,207-214`) | `internal/citylayout/runtime.go:130` |

### 1b. Conditional variables (appended only when the value is non-empty), in append order

| # | Env var | Value / provenance | When non-empty in the convergence gate path |
|---|---|---|---|
| 15 | `GC_DOC_PATH` | `DocPath` = root-bead metadata `var.doc_path` (`handler.go:750`) | only if the loop has a `doc_path` template var | `condition.go:105-107` |
| 16 | `GC_AGENT_VERDICT` | `AgentVerdict` — **set only by hybrid mode** (`hybrid.go:14`); normalized verdict, see §9 | always in hybrid (normalization never yields `""` — minimum is `"block"`); **never set in pure `condition` mode** | `condition.go:108-110` |
| 17 | `GC_AGENT_PROVIDER` | `AgentProvider` | never — no production caller populates it (struct field exists, `condition.go:71`) | `condition.go:111-113` |
| 18 | `GC_AGENT_MODEL` | `AgentModel` | never — same as above (`condition.go:72`) | `condition.go:114-116` |
| 19 | `GC_WORK_DIR` | `WorkDir` | never in handler/trigger paths (only the ralph-check caller sets it, `ralph.go:246`) | `condition.go:117-119` |
| 20 | `GC_STORE_PATH` | `StorePath` = `Handler.StorePath` (`handler.go:148-149,748`) | whenever the handler's store path is set | `condition.go:120-122` |
| 21 | `GC_ARTIFACT_DIR` | `ArtifactDir` = `ArtifactDirFor(cityPath, rootBeadID, iteration)` = `<cityPath>/.gc/artifacts/<beadID>/iter-<N>` (`template.go:23-25`, `handler.go:751`) | always in handler/trigger paths (the join is never empty); omitted when empty (sling-time contract, `condition.go:66`) | `condition.go:123-125` |
| 22 | `GC_MOLECULE_DIR` | `MoleculeDir` | never in handler/trigger paths (ralph-check only, `ralph.go:240-247`) | `condition.go:126-128` |
| 23 | `GC_INTEGRATION_REAL_BD` | passthrough of ambient `os.Getenv("GC_INTEGRATION_REAL_BD")` (integration-test bd shims) | only under integration tests | `condition.go:129-131` |

### 1c. Ambient Dolt/Beads passthrough (appended last, only when set in ambient env), exact order

`condition.go:132-147` — for each key, `os.Getenv(key)`; appended as `key=value` only when
non-empty, in exactly this order:

`BEADS_DOLT_AUTO_START`, `BEADS_DOLT_SERVER_HOST`, `BEADS_DOLT_SERVER_PORT`,
`BEADS_DOLT_SERVER_USER`, `BEADS_DOLT_PASSWORD`, `GC_DOLT`, `GC_DOLT_HOST`, `GC_DOLT_PORT`,
`GC_DOLT_USER`, `GC_DOLT_PASSWORD`.

### 1d. `PATH` construction — `conditionPATH()` (`condition.go:31-53`)

Ordered, deduplicated directory list joined with `:`:

1. For each tool name in order `bd`, `gc`, `dolt`, `jq`: `exec.LookPath(name)` (resolved
   against the **controller's own** PATH); on success append `filepath.Dir(path)` if unseen.
2. Then each component of `SafePATH` (`/usr/local/bin`, `/usr/bin`, `/bin`) if unseen.

Purpose: gate scripts use the same `bd`/`gc` binaries as the running controller, not whatever
older copy is in `/usr/local/bin` (`condition.go:27-30`).

### 1e. `GC_CITY_RUNTIME_DIR` resolution

`citylayout.CityRuntimeEnvForRuntimeDir(ce.CityPath, citylayout.TrustedAmbientCityRuntimeDir(ce.CityPath))`
(`condition.go:102`):

- `TrustedAmbientCityRuntimeDir(cityRoot)` (`runtime.go:194-205`): returns ambient
  `GC_CITY_RUNTIME_DIR` **only when** ambient `GC_CITY_PATH`, `GC_CITY`, or `GC_CITY_ROOT`
  resolves (`pathutil.SamePath`) to `cityRoot`; otherwise `""`.
- `CityRuntimeEnvForRuntimeDir` (`runtime.go:121-132`): trims; empty → canonical
  `<cityRoot>/.gc/runtime` (`RuntimeDataRoot = ".gc/runtime"`, `runtime.go:13`).
- The trace-default path additionally coerces a runtimeDir that is inside the city but outside
  `<city>/.gc` back to the canonical runtime dir (`normalizeRuntimeDir`, `runtime.go:207-214`).

⚠ **ordering** — the env slice order above is observable (duplicate keys would resolve
last-wins in most shells/exec environments; gc never emits duplicates because of the
whitelist). Preserve the append order anyway: it is the de-facto contract fixtures will diff
against.

---

## 2. Condition-script path resolution + containment defenses

`ResolveConditionPath(envelope, base, conditionPath)` (`condition.go:191-263`). Returns the
canonical absolute script path or an error. Exact checks, **in order**:

1. `conditionPath == ""` → error `resolving gate condition path: empty path`
   (`condition.go:192-194`).
2. `envelope == ""` → error `resolving gate condition path: empty envelope` — an empty
   envelope would silently disable the traversal check, so it is rejected
   (`condition.go:195-197`, rationale `condition.go:170-172`).
3. `base == ""` → `base = envelope` (historical single-arg behavior, `condition.go:198-200`).
4. Canonicalize both roots: `canonEnvelope = filepath.EvalSymlinks(envelope)`, falling back to
   `filepath.Clean(envelope)` on error (root may not exist yet); same for `canonBase`
   (`condition.go:206-213`). This avoids false rejections from symlinked workspace roots
   (e.g. `/tmp` → `/private/tmp` on macOS).
5. Join: absolute `conditionPath` → `filepath.Clean(conditionPath)`; relative →
   `filepath.Clean(filepath.Join(canonBase, conditionPath))` (`condition.go:215-220`).
6. **Pre-resolution containment (relative paths only):** the lexical join must satisfy
   `containedIn(absPath, canonEnvelope) || containedIn(absPath, canonBase)`; else error
   `path traversal not allowed: <conditionPath>` (`condition.go:226-230`). Rejects `../../foo`
   before any filesystem access. **Absolute paths skip this check** — imported and
   registry-installed packs live outside the city/store roots; callers vouch for absolute
   paths (`condition.go:185-190`).
7. Resolve symlinks: `resolved = filepath.EvalSymlinks(absPath)`; error → wrapped
   `resolving gate condition path: <err>` (`condition.go:234-237`). (Scripts may legitimately
   be symlinked from shared tooling dirs.)
8. **Post-resolution containment (relative paths only):** re-validate
   `containedIn(resolved, canonEnvelope) || containedIn(resolved, canonBase)`; else error
   `symlink target outside containment: <conditionPath>` (`condition.go:244-248`). Closes the
   symlink-escape gap (`base/scripts/check.sh -> /etc/passwd`). Absolute paths skip — same
   rationale as step 6.
9. `os.Stat(resolved)`: must exist (error wrapped), must be a **regular file**
   (`info.Mode().IsRegular()`, else `not a regular file: <resolved>`), and must have **any**
   exec bit (`info.Mode().Perm()&0o111 != 0`, else `file is not executable: <resolved>`)
   (`condition.go:251-260`).
10. Return `resolved` (`condition.go:262`).

`containedIn(absPath, root)` (`condition.go:156-162`): `rel = filepath.Rel(root, absPath)`;
error → false; result is `!pathutil.IsOutsideDir(rel)`.
`pathutil.IsOutsideDir(rel)` (`internal/pathutil/pathutil.go:77-80`):
`rel == ".." || (len(rel) > 2 && rel[:3] == ".."+separator)`.

**Two-root semantics** (doc block `condition.go:164-190`): `envelope` is the security
boundary (the **city path** — even for rig-scoped checks, gascity#2320); `base` is the join
base for relative paths AND a second permitted boundary (sibling rig/city layouts,
gascity#2354). `base` itself is not validated — callers must pass operator-controlled paths.

### ⚠ Where gc actually applies `ResolveConditionPath`

- The **convergence handler does NOT resolve at execution time**: `evaluateGate` passes the
  stored `convergence.gate_condition` string straight to `RunCondition`
  (`handler.go:763-766`), and create stores the operator-supplied path verbatim
  (`cmd/gc/convergence_tick.go:460` → `create.go:108`). The same applies to the trigger
  condition (`trigger.go:95`) and `gc converge test-gate` (`cmd/gc/cmd_converge.go:499-502`).
  Gate-condition paths are operator-supplied through the create surface (trusted).
- The production caller of `ResolveConditionPath` is the **ralph check** exec path
  (`internal/dispatch/ralph.go:197`), where the path comes from bead metadata
  (`gc.check_path`) — i.e. from a less-trusted surface — with envelope = cityPath, base =
  work-dir/storePath, plus an additional trusted-absolute-roots check for absolute paths
  (`ralph.go:181-204`).

The port must implement `ResolveConditionPath` 1:1 (it is the compatibility surface ADR-0003
D3 names) and preserve gc's *placement*: resolve-on-exec for metadata-sourced paths
(ralph-style), exec-as-stored for operator-created gate conditions. Tightening placement is a
semantic change → upstream RFC / ADR-0000 amendment, not a silent port decision.

---

## 3. Execution mechanics

`RunCondition(ctx, scriptPath, env, timeout, retryBudget)` (`condition.go:269-287`) →
`runOnce` (`condition.go:290-309`) → `runOnceNoPreExecRetry` (`condition.go:315-404`):

- **Direct exec, no shell:** `exec.CommandContext(execCtx, scriptPath)` — argv is exactly
  `[scriptPath]`, **zero arguments**, no `/bin/sh -c` (`condition.go:319`). Scripts are
  executed by the kernel: they need the exec bit and a shebang. All bead-derived values reach
  the script as env vars, never interpolated into a command line (`condition.go:55-56`).
- **Working directory** (`condition.go:320-326`), precedence low→high:
  `cmd.Dir = env.CityPath`; if `env.StorePath != ""` then `StorePath`; if `env.WorkDir != ""`
  then `WorkDir`. Handler path ⇒ cwd = `Handler.StorePath` (or cityPath if store path empty);
  `WorkDir` only matters for ralph checks.
- **Environment:** `cmd.Env = env.Environ()` (§1) — whitelist, not inherited
  (`condition.go:327`).
- **Timeout mechanism:** `execCtx, cancel := context.WithTimeout(ctx, timeout)`
  (`condition.go:316`); Go's `CommandContext` sends **SIGKILL** to the process on deadline.
  `cmd.WaitDelay = time.Second` (`condition.go:330`) so `Wait` returns promptly after the
  kill even if child I/O pipes are still open (grandchildren holding the pipe). Port note:
  Dart `Process.run`+timer must kill with SIGKILL and must not block on open pipes for more
  than ~1s after kill.
- **Capture:** stdout and stderr each go to a bounded buffer of capacity
  `MaxOutputBytes + utf8.UTFMax` = 4100 bytes (`condition.go:334-337`) — slightly more than
  the limit so truncation can be detected and trimmed to a rune boundary (§6).
- **Duration:** wall clock around `cmd.Run()` (`condition.go:339-341`) — per attempt; the
  returned `Duration` is the **final attempt's** only.

### 3a. "text file busy" pre-exec retry (`runOnce`, `condition.go:290-313`)

A pre-exec failure classified as `error` whose `Stderr` contains `text file busy`
(case-insensitive substring, `condition.go:311-313`) is retried up to
`textFileBusyRetryAttempts` = 5 extra times (max 6 executions) with a 25 ms delay between
attempts; a cancelled parent ctx during the delay returns the last result immediately
(`condition.go:298-306`). This handles freshly-written scripts still open for write. It is
**independent of** and **inside** the timeout-retry loop.

### 3b. Timeout retry loop (`RunCondition`, `condition.go:269-287`)

```
retries = 0
for attempt in 0..retryBudget:
    lastResult = runOnce(...)
    if lastResult.Outcome != "timeout" or attempt == retryBudget:
        lastResult.RetryCount = retries; return lastResult
    retries++
```

- Retries happen **only** on outcome `timeout` (`condition.go:277`). `fail`, `error`, `pass`
  return immediately.
- `retryBudget` is 0 unless `TimeoutAction == "retry"`, in which case it is
  `MaxGateRetries` = 3 (`handler.go:738-741`, `hybrid.go:16-19`) ⇒ at most **4 attempts**.
- `RetryCount` on the returned result = number of timed-out attempts before the final one
  (budget 3, all timeouts ⇒ final outcome `timeout`, `RetryCount == 3`).

---

## 4. Outcome mapping (exact, in evaluation order)

From `runOnceNoPreExecRetry` (`condition.go:339-403`), evaluated **in this order** after
`cmd.Run()` returns:

| # | Check | Outcome | ExitCode | Stdout/Stderr | Source |
|---|---|---|---|---|---|
| 1 | `ctx.Err() != nil` (the **parent** context is done) | `error` | null | captured (truncated) | `condition.go:350-358` |
| 2 | `execCtx.Err()` is `context.DeadlineExceeded` (per-script deadline) | `timeout` | null | captured (truncated) | `condition.go:361-369` |
| 3 | `err` is an `exec.ExitError` (process ran, exited non-zero — or was signal-killed by something other than our deadline) | `fail` | `exitErr.ExitCode()` (⚠ `-1` if signal-killed) | captured (truncated) | `condition.go:371-384` |
| 4 | any other `err` (pre-exec: script not found, permission denied, exec format error) | `error` | null | **`Stderr = err.Error()`** — the Go error string **replaces** captured stderr; `Stdout` is left empty | `condition.go:385-391` |
| 5 | `err == nil` (exit status 0) | `pass` | `0` | captured (truncated) | `condition.go:394-403` |

⚠ **ordering** — check 1 before check 2 is load-bearing: when the parent ctx is already
cancelled, the result must be `error`, not `timeout`, otherwise the retry loop would hammer an
already-cancelled parent (`condition.go:347-349`). `Truncated` is set on every branch:
`outTrunc || errTrunc || stdout.Overflowed() || stderr.Overflowed()` (`condition.go:343-345`).

---

## 5. Timeout actions — semantics in the handler

`retryBudget` derivation: `handler.go:738-741` (and identically `hybrid.go:16-19`) —
`TimeoutAction == "retry"` ⇒ budget `MaxGateRetries` (3), else 0.

Post-evaluation handling in `HandleWispClosed` step 7, **in this order**:

1. `Outcome == "timeout" && TimeoutAction == "manual"` → burn the speculative wisp →
   `transitionToWaitingManual(..., reason="timeout" (WaitTimeout), gateOutcome="timeout")`
   (`handler.go:345-351`; `WaitTimeout = "timeout"`, `metadata.go:100`). Checked **before**
   the terminal switch.
2. Terminal switch (`handler.go:353-368`):
   - `Outcome == "pass"` → terminal, `terminal_reason = "approved"`.
   - `Outcome == "timeout" && TimeoutAction == "terminate"` → terminal,
     `terminal_reason = "no_convergence"`.
   - `wispIteration >= maxIterations` (any non-pass outcome) → terminal, `"no_convergence"`.
3. Non-terminal (`handler.go:370-381`): speculative-pour error → `waiting_manual` with reason
   `"sling_failure"`; trigger-gated loop → `waiting_trigger`; otherwise **iterate**.

Consequences (port these exactly):

- `TimeoutAction == "iterate"` (the default): a timeout is treated like a fail — iterate,
  unless at max iterations (→ `no_convergence`).
- `TimeoutAction == "retry"`: the retry happens **inside** gate evaluation; if the final
  attempt still times out, the resulting `timeout` flows through step 7 where `retry` matches
  neither `manual` nor `terminate` — i.e. **retry-exhausted timeout degrades to iterate
  semantics** (or `no_convergence` at max iterations).
- Outcome `error` (pre-exec failure) is **not terminal** below max iterations — the loop
  iterates. Only max iterations terminates a persistently erroring gate.
- **The retry counter's metadata key:** `convergence.gate_retry_count`
  (`FieldGateRetryCount`, `metadata.go:29`), written during persistence (§7) with
  `EncodeInt(result.RetryCount)` (`handler.go:787`). It records retries for the processed
  wisp's evaluation; it is **not** a cross-iteration counter and is overwritten per
  evaluation.

---

## 6. stdout/stderr capture and truncation

`internal/convergence/capture.go`:

- **Limits: bytes only — there is no line-count limit.** `MaxOutputBytes = 4096` per stream
  (`capture.go:13`). Capture buffers are sized `4096 + utf8.UTFMax (4) = 4100`
  (`condition.go:334-335`).
- `boundedBuffer` (`capture.go:17-43`): stores at most `maxBytes`; once full, further writes
  are **silently discarded but reported as fully written** (`return len(p), nil`) so the
  child process never sees a write error (`capture.go:27-40`); sets `overflow` when any byte
  is dropped.
- `TruncateOutput(data, maxBytes)` (`capture.go:47-69`):
  - `maxBytes <= 0`: returns `("", false)` for empty input, `("", true)` otherwise.
  - `len(data) <= maxBytes`: `(string(data), false)`.
  - else: back off `end` from `maxBytes` (at most `utf8.UTFMax−1 = 3` bytes, while
    `end > maxBytes-utf8.UTFMax`) until `utf8.RuneStart(data[end])` — i.e. cut so a
    multi-byte UTF-8 rune is never split; binary garbage elsewhere in the slice is preserved
    as-is. Returns `(string(data[:end]), true)`.
- Final `Truncated` flag combines the rune-boundary trim and buffer overflow of either stream
  (`condition.go:345`).

**Metadata keys receiving the captures** (written by `persistGateOutcome`, §7):
`convergence.gate_stdout` ← `result.Stdout`, `convergence.gate_stderr` ← `result.Stderr`,
`convergence.gate_truncated` ← `"true"` when truncated, **empty string** otherwise
(`handler.go:799-803` — not `"false"`).

---

## 7. Gate-outcome persistence sequence

`persistGateOutcome(rootBeadID, wispID, result)` (`handler.go:776-808`) — handler step 5, runs
only when the gate was actually evaluated (`!skipGateEval`, `handler.go:331-338`). Eight
sequential `SetMetadata` writes on the **root** bead, **in exactly this order**:

| # | Key | Value |
|---|---|---|
| 1 | `convergence.gate_outcome` | `result.Outcome` (`pass`/`fail`/`timeout`/`error`) |
| 2 | `convergence.gate_exit_code` | `EncodeInt(*ExitCode)` or `""` when null |
| 3 | `convergence.gate_retry_count` | `EncodeInt(result.RetryCount)` |
| 4 | `convergence.gate_stdout` | truncated stdout |
| 5 | `convergence.gate_stderr` | truncated stderr |
| 6 | `convergence.gate_duration_ms` | `strconv.FormatInt(result.Duration.Milliseconds(), 10)` |
| 7 | `convergence.gate_truncated` | `"true"` or `""` |
| 8 | `convergence.gate_outcome_wisp` | `wispID` — **LAST: this is the idempotency marker** (`handler.go:806-807`) |

⚠ **ordering** — `gate_outcome_wisp` LAST is the crash-safety commit point for gate
evaluation (ADR-0003 invariant 2). Replay: on re-processing, `skipGateEval :=
meta["convergence.gate_outcome_wisp"] == wispID` (`handler.go:233-234`); when true, the
`GateResult` is **reconstructed from the persisted keys instead of re-running the script**
(`handler.go:280-298`; duration parsed back from ms). A crash after write 8 never re-executes
a gate script; a crash before it re-runs the script (acceptable: scripts are expected to be
re-runnable). In the_grid these eight writes go through one `bd batch` (ADR-0003 D4) — the
batch must keep this single transaction separate from the step-9 transition writes, never
merged with them, because gc can crash *between* step 5 and step 9 and recovery depends on
observing gate-outcome-persisted-but-transition-unwritten.

Surrounding write order in `HandleWispClosed` (context, ported in the handler spec, summarized
here because the gate sits inside it):

1. Step 3b — speculative pour of `converge:<rootID>:iter:<N+1>` **before** gate evaluation;
   `convergence.pending_next_wisp` set to the poured wisp (`handler.go:244-275`).
2. Step 4 — gate evaluation (§3-§5) or replay.
3. Step 5 — `persistGateOutcome` (this section). On persistence failure the speculative wisp
   is burned (`handler.go:332-337`).
4. Step 9 — transition writes; `convergence.last_processed_wisp` **LAST** in every variant
   (`handler.go:438-453` waiting_manual, `555-565` iterate, `619-628` waiting_trigger,
   `687-704` terminate — terminate writes `terminal_reason`, `terminal_actor`,
   `state=terminated`, `CloseBead(root)`, then `last_processed_wisp`).

---

## 8. Hybrid mode — exact fallback logic

`internal/convergence/hybrid.go`:

- `HybridNeedsManual(cfg)` (`hybrid.go:26-28`): `cfg.Condition == ""` — that is the entire
  test. Hybrid = "condition if a script is configured, else pass to manual".
- In the handler (authoritative path): hybrid-with-no-condition is intercepted **before** gate
  evaluation — burn the speculative wisp, then `transitionToWaitingManual` with
  `waiting_reason = "hybrid_no_condition"` (`WaitHybridNoCondition`, `metadata.go:99`;
  `handler.go:310-316`). No gate result is persisted (`GateResult{}` is passed; gateOutcome
  arg `""`). Note the speculative pour was already skipped for this shape
  (`needsManualWithoutGate`, `handler.go:249-253`), so the burn is a no-op guard.
- `EvaluateHybrid(ctx, cfg, env, verdict)` (`hybrid.go:8-22`), reached only when a condition
  is configured:
  1. `if HybridNeedsManual(cfg) → return GateManualResult()` (outcome `pass`, null exit code)
     — defensive; unreachable from the handler, reachable for direct callers.
  2. `env.AgentVerdict = verdict` — **this is the only place the verdict enters the script
     env** (`hybrid.go:14`).
  3. `retryBudget = MaxGateRetries` iff `cfg.TimeoutAction == "retry"`, else 0.
  4. `return RunCondition(ctx, cfg.Condition, env, cfg.Timeout, retryBudget)`.
- Pure `condition` mode calls `RunCondition` directly with `env.AgentVerdict` left empty
  (`handler.go:763-764`) ⇒ no `GC_AGENT_VERDICT` in the env.
- `condition` mode with an empty condition path is a **handler error**, not a transition:
  `gate mode is "condition" but no condition path configured` (`handler.go:235-241`; any
  valid pending speculative wisp is burned first). Because `last_processed_wisp` is not
  written, the wisp will be re-processed on the next event — the loop stalls loudly until the
  config is fixed.

---

## 9. The agent-verdict channel

**Keys** (`metadata.go:24-25`): `convergence.agent_verdict` (`FieldAgentVerdict`),
`convergence.agent_verdict_wisp` (`FieldAgentVerdictWisp`).

**Who writes them: the agent, via `bd meta set`, from inside the wisp.** Not the controller.

- Every poured wisp carries a controller-injected `evaluate` step (`EvaluateStepName =
  "evaluate"`, `evaluate.go:14`). Its prompt is `convergence.evaluate_prompt` if set,
  else `prompts/convergence/evaluate.md` relative to the city root
  (`DefaultEvaluatePromptPath`, `evaluate.go:18`, resolution + traversal/symlink rejection in
  `ResolveEvaluateStep`, `evaluate.go:38-69`).
- A custom evaluate prompt MUST contain the literal substrings `bd meta set` and
  `convergence.agent_verdict` (`evaluateRequiredSubstrings`, `evaluate.go:22-25`, enforced by
  `ValidateEvaluatePrompt`, `evaluate.go:74-85`) — i.e. the prompt instructs the agent to
  record its verdict (and the wisp scope) on the **root** bead with `bd meta set`.
- ACL: these are the **only two** `convergence.*` keys agents may write without the
  controller token (`agentWritableKeys`, `acl.go:10-13`); every other `convergence.*` key and
  all `var.*` keys require `GC_CONTROLLER_TOKEN` (`RequiresToken`, `acl.go:18-26`;
  `token.go:15`). Agent session envs are scrubbed of the token (`ScrubTokenEnv`,
  `acl.go:30-41`). No gascity Go code ever writes `agent_verdict_wisp` — only the constant
  exists; the value (the wisp ID the verdict applies to) comes from the agent.

**How the gate consumes it — read, not reinterpreted** (`handler.go:318-324`):

```go
verdict := ""
if meta[FieldAgentVerdictWisp] == wispID {
    verdict = NormalizeVerdict(meta[FieldAgentVerdict])
} else {
    verdict = VerdictBlock // no verdict or mismatched wisp
}
```

- **Wisp scoping:** the verdict counts only if `convergence.agent_verdict_wisp` equals the
  wisp being processed. Stale verdicts from an earlier iteration are ignored and read as
  `"block"`.
- `NormalizeVerdict(raw)` (`metadata.go:124-138`): lowercase + trim; `""` → `"block"`;
  past-tense map (`metadata.go:113-119`): `approved`→`approve`, `blocked`→`block`,
  `approve-with-risk`/`approved-with-risks`/`approved-with-risk`→`approve-with-risks`;
  canonical values `approve`/`approve-with-risks`/`block` pass through; **anything unknown →
  `"block"`** (fail-closed).
- The controller **never branches on the verdict value**. It is normalized and handed to the
  condition script as `GC_AGENT_VERDICT` (hybrid mode only, §8); the script decides pass/fail
  by its exit code. Pure condition mode never even reads it into the env; manual mode never
  runs a script. The event payloads carry the (scoped, normalized) verdict for observability
  only (`handler.go:417-420,533-536,655-658`).
- **Clearing:** on `iterate` and on the `waiting_trigger` hold, both keys are cleared
  (`SetMetadata(..., "")`) **only when scoped to the processed wisp**
  (`handler.go:491-498`, `589-596`); manual approve/iterate paths clear them likewise
  (`manual.go:180-186,351-355`).

---

## 10. Artifact directory helpers (`artifact.go`, `template.go`)

- `ArtifactDirFor(cityPath, beadID, iteration)` (`template.go:23-25`):
  `<cityPath>/.gc/artifacts/<beadID>/iter-<iteration>` — this exact string becomes
  `GC_ARTIFACT_DIR` (handler `handler.go:751`, trigger `trigger.go:117`).
- `EnsureArtifactDir(fs, cityPath, beadID, iteration)` (`artifact.go:14-20`): `MkdirAll(dir,
  0o755)`, returns the path.
- `ValidateArtifactDir(dir)` (`artifact.go:28-69`) — safety walk before gate execution:
  1. `filepath.Abs(dir)` then `filepath.EvalSymlinks` (canonical root; errors wrapped as
     `resolving artifact directory`).
  2. `filepath.WalkDir`: for each entry —
     - symlink (`type & ModeSymlink`): `EvalSymlinks(path)` (multi-hop), then
       `filepath.Rel(absDir, resolved)`; error or `pathutil.IsOutsideDir(rel)` → error
       `symlink %q points outside artifact directory: resolves to %q`.
     - regular file or directory → allowed.
     - anything else (FIFOs, device files, sockets) → error
       `unsafe file type in artifact directory: %q (mode %s)`.
- ⚠ Neither helper is called from the live convergence gate path (`handler.go` only
  *computes* the path; `molecule.EnsureArtifactDir` — a different function — serves the
  sling/ralph paths). The gate env can therefore point at a **not-yet-existing** directory;
  scripts must tolerate that (the "sling-time contract", `condition.go:66`). Port both
  helpers (they are spec'd by `artifact_test.go`), and keep the handler's compute-only
  behavior.

---

## 11. Loop retry — `RetryHandler` (`retry.go`)

Not the gate timeout-retry (§5): this creates a **new** convergence loop from a terminated
one (`gc converge retry`). `RetryHandler(ctx, sourceBeadID, _, maxIterations)`
(`retry.go:21-147`), sequence:

1. Read source metadata (`retry.go:23-26`).
2. Source `convergence.state` must be `"terminated"`, else error (`retry.go:29-34`).
3. Source `convergence.terminal_reason` must **not** be `"approved"` — approved loops cannot
   be retried (`retry.go:37-42`).
4. Copy config: `formula`, `target`, `gate_mode`, `gate_condition`, `gate_timeout`,
   `gate_timeout_action`, `city_path`, `rig`, `evaluate_prompt`, and all `var.*`
   (`ExtractVars`, `template.go:43-51`) (`retry.go:45-54`).
   4b. Re-validate the copied gate config via `ParseGateConfig` **before** creating any state
   (`retry.go:57-65`).
5. Create the new root bead, title `"Retry of <sourceBeadID>"` (`retry.go:68-71`).
   On any later failure: rollback = set `state=terminated` + `CloseBead` with
   `CloseReasonRetryRollback` = `"convergence: retry-create rollback after error"`
   (`retry.go:76-81`, `handler.go:49`).
6. `convergence.state = "creating"` first (partial-creation detection), then the metadata
   writes **in this order** (`retry.go:83-106`): `formula`, `target`, `gate_mode`,
   `gate_condition`, `gate_timeout`, `gate_timeout_action`, `max_iterations`, `city_path`,
   `rig`, `evaluate_prompt`, `retry_source` (= sourceBeadID), `state = "active"`.
7. Copy `var.*` template variables (`retry.go:109-113`).
8. Pour wisp 1 with idempotency key `converge:<newBeadID>:iter:1` (`IdempotencyKey`,
   `handler.go:19-21`; `retry.go:116-120`).
9. Set `convergence.active_wisp` = first wisp, `convergence.iteration` = `1`
   (`retry.go:123-128`).
10. Emit `ConvergenceCreated` with `RetrySource` set (`retry.go:131-140`).
11. Return `RetryResult{NewBeadID, FirstWispID, Iteration: 1}`.

⚠ **ordering** — `state` flows `creating` → (all config writes) → `active` *within* the step-6
write list (`state=StateActive` is the final pair, `retry.go:100`); the reconciler treats any
bead stuck in `creating` as a partial creation to terminate.

---

## 12. Porting traps (most likely to be transcribed wrongly)

1. **`GC_AGENT_VERDICT` is hybrid-only.** Pure `condition` mode never sets it
   (`handler.go:763-764` vs `hybrid.go:14`). And in hybrid it is *always* present, because
   normalization can never produce `""` — a missing/mismatched/unknown verdict becomes
   `"block"` (`handler.go:318-324`, `metadata.go:124-138`).
2. **Pre-exec error overwrites stderr.** On the `error` outcome from a non-exit error, the
   result's `Stderr` is the Go error string, not the captured stream, and `Stdout` is dropped
   (`condition.go:385-391`). Persisted `convergence.gate_stderr` then contains e.g.
   `fork/exec /x/y: no such file or directory`. Match the shape, not the literal Go text —
   but keep the substring `text file busy` detectable case-insensitively, or the §3a retry
   breaks.
3. **Parent-cancel ≠ timeout.** Parent-context cancellation maps to `error` and is checked
   *before* the deadline check (`condition.go:350-369`). Swapping the order turns shutdown
   into a retry storm.
4. **`error` outcome iterates.** A persistently failing-to-exec gate does not terminate or go
   manual below max iterations (§5 step 3). Don't "improve" this into terminate.
5. **Retry-exhausted timeout degrades to iterate.** `TimeoutAction == "retry"` only sets the
   in-evaluation budget; step 7 has no `retry` branch (`handler.go:345-368`).
6. **`gate_truncated` is `"true"` or `""`** — never `"false"` (`handler.go:799-803`).
   `gate_exit_code` is `""` (not absent, not `"null"`) when the exit code is null
   (`handler.go:780-784`).
7. **Truncation is bytes-only (4096/stream), rune-boundary trimmed**, with capture buffers of
   4100 bytes; the bounded buffer must *lie* to the writer (`return len(p), nil`) so the
   child never gets EPIPE-like failures mid-write (`capture.go:27-40`).
8. **Persistence order is fixed; `gate_outcome_wisp` strictly LAST** (§7). Replay
   reconstructs the `GateResult` from metadata and **must not** re-run the script
   (`handler.go:280-298`). Keep step-5 persistence and step-9 transition writes in separate
   transactions.
9. **No shell, no args.** `argv = [scriptPath]` exactly (`condition.go:319`). The exit-code
   contract (0=pass) collapses if a shell wrapper is introduced.
10. **Whitelist env, built from scratch.** Never spawn with the inherited environment; the
    sandboxing (`HOME`=cityPath, narrow `PATH`, no `GC_CONTROLLER_TOKEN`) is a security
    boundary, not a convenience (`condition.go:79-150`).
11. **`PATH` is dynamic.** Tool dirs are discovered with LookPath for `bd`,`gc`,`dolt`,`jq`
    *in that order*, deduped, then `SafePATH` appended (`condition.go:31-53`). For the Dart
    port "where `gc` lives" raises a question — resolve the equivalent grid binaries the same
    way and record the decision as an ADR-0000 amendment; don't silently hardcode.
12. **Working-dir precedence** is `WorkDir > StorePath > CityPath` (`condition.go:320-326`) —
    the assignments are sequential overrides, easy to invert.
13. **Containment checks apply to relative paths only**; absolute condition paths skip both
    the pre- and post-resolution checks by design (packs outside the city root), and an empty
    `envelope` must be rejected, not treated as "no check" (`condition.go:191-248`).
14. **`containedIn` is lexical** (`filepath.Rel` + `IsOutsideDir`); the symlink defense comes
    from EvalSymlinks'ing inputs *before* the lexical check — both the roots (step 4) and the
    candidate (step 7-8). Doing only one side reopens the gap.
15. **The gate-condition path is exec'd as stored** in the convergence handler;
    `ResolveConditionPath` guards the ralph metadata-sourced path (§2). Mirroring the checks
    onto the wrong call site changes observable behavior against gc's test suite.
16. **`GC_BEAD_ID` is the root convergence bead, `GC_WISP_ID` is the closed wisp**, and
    `GC_ITERATION` is the **closed** wisp's iteration (not the next one) in the gate path —
    but the **next** iteration in the trigger path (`handler.go:327` vs `trigger.go:83-93`).
17. **`gate_timeout` uses Go `time.ParseDuration` syntax** (`"5m"`, `"90s"`, `"1h30m"`,
    fractional + negative forms). The Dart port needs a Go-compatible duration parser, not
    `Duration.parse` (`metadata.go:165-174`).
18. **`RetryCount` semantics:** number of timed-out attempts *before* the final attempt; max 3;
    counts only timeouts (never fail/error retries) (`condition.go:269-287`).
19. **Signal-killed (non-deadline) processes are `fail` with exit code `-1`** (Go
    `ExitCode()` convention, `condition.go:371-384`) — persisted as `gate_exit_code = "-1"`.
    Deadline kills are caught earlier as `timeout` with null exit code.
20. **`GateManualResult()` is `pass` with a null exit code** — distinguishable in metadata
    from a real pass (`gate_exit_code` `""` vs `"0"`). Manual mode is intercepted before gate
    evaluation in the handler, so this result only surfaces through direct `EvaluateHybrid`
    callers (`gate.go:36-40`, `hybrid.go:8-10`).
21. **Verdict clearing is scoped:** clear `agent_verdict`/`agent_verdict_wisp` only when
    `agent_verdict_wisp == wispID` — clearing unconditionally can erase a verdict an agent
    just wrote for the *next* wisp (`handler.go:491-498`).
22. **The verdict channel is agent-written.** the_grid's reconciler must keep
    `convergence.agent_verdict` and `convergence.agent_verdict_wisp` writable by agents
    (bd-mediated) and must never compute or overwrite them itself except for the scoped
    clearing in §9 — "read, not reinterpreted" (ADR-0003 D3).
