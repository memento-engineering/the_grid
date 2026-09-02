---
status: accepted
date: 2026-07-12
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a49-no-complete-on-faith-an-inferred-one-shot-exit-is-proven
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A49"
---
## A49 (2026-07-12) — no-complete-on-faith: an INFERRED one-shot exit is PROVEN before the circuit advances (tg-uz3 / I-11)

**Context.** I-11 (observed 2026-07-03, tg-x1j r2): the operator environment restarted and KILLED an in-flight coding agent mid-edit. A DETACHED one-shot exposes no readable exit code, so `SubprocessProvider._emitExit` INFERS a clean `Exited(0)` from its vanish (A38) — and a MURDERED agent vanishes IDENTICALLY to a finished one. The engine read the murder as a completion, advanced the cursor, and mounted `verify` over a broken, uncommitted tree. The defense held (all four committee lanes independently F-ed and gated) but the station spent a full committee round grading garbage.

**Decision (AI; `grid_runtime` + `grid_engine` + `grid_sdk`):** the engine never advances a circuit on a GUESS. Four parts, each inert by default:

- **The transport declares its guess.** `RuntimeEvent.exited` gains `inferred` (`@Default(false)`): the `oneTurn`-vanish emit sets it, an exit code we actually READ does not. ADR-0004 Decision 1's rule ("providers degrade explicitly rather than silently") applied to the EVENT.
- **The capability DECLARES its completion contract.** `ProcessCapability.completionContract` (`CompletionContract.none` | `.committedWorkspace`), defaulting to `none` — unfenced, today's behavior. Only a capability whose working agreement IS "commit your work in the worktree" (a coding agent) declares the contract; a critic / `specify` / any artifact-writing one-shot finishes by leaving an UNCOMMITTED file behind *by design*, and fencing it on worktree dirtiness would fail it forever. The engine holds the CONCEPT ("what does a finished turn leave behind?"); the capability holds its own agreement (ADR-0008 D5 / D2 — compose, never subclass). The concrete VCS probe stays the composer's opinion; the engine names no VCS (the injected `WorkSignalProbe`, defaulting to `noWorkSignal` — the shape of the existing `AllocationLiveness`/`neverLive` seam). Unlike the adopt seam, this one is safe to arm ALONE: it can only WITHHOLD an unproven completion, never double-run anything.
- **The work signal EXCLUDES the grid's own runtime dir** (`.grid` — `.grid/critique/` incl. the pinned diff, `.grid/spec/`, `.grid/telemetry/`). That residue is written by the grid's OWN steps and committed by none of them. The exclusion also makes the signal SUBSTATION-INDEPENDENT: the_grid gitignores `.grid`, genesis and lenny do NOT (`git status` there returns `?? .grid/`). Without it a coding agent that CORRECTLY committed on genesis would read as INTERRUPTED, respawn into the same residue, fail identically, exhaust its restart budget, and escalate — a working completion turned into a guaranteed failure loop. `GitOps.hasUncommittedWork` takes `excluding`, defaulted to EMPTY, so **ADR-0006 D3's reap Gate 1 is byte-for-byte unchanged** — `reap` passes no exclusion (residue in a worktree it is about to REMOVE still blocks it); only the fence excludes.
- **Fail-SAFE on an unaddressable workspace; fail-CLOSED on an unreadable one.** With no ambient `SourceControl`, `SessionScope` mounts a SYNTHETIC `Workspace` (`/grid/workspaces/<beadId>`) naming no repo — the fence DISARMS (both seams must agree: a real `SourceControl` AND a real `Workspace`). It fails CLOSED (`probeError`/throw/**timeout** ⇒ `Failed`) only where the workspace is real and merely unreadable — ADR-0006 D3's ratified posture, reused read-only, not re-decided here.

**Two defects found by the adversarial review pass and fixed before landing** (both in the *dangerous* direction — a working completion turned into a failure loop, the exact wedge this amendment exists to avoid):

- **A git WARNING is not a porcelain entry.** `GitRunResult.output` is stdout+stderr COMBINED (gc's `CombinedOutput`, deliberate), and `git status --porcelain` can exit **0** while warning on stderr (`warning: could not open directory 'x/': Permission denied` — an unreadable dir in the worktree). A line-split over the combined output parses that warning AS a change, fabricating uncommitted work that does not exist: a correctly-committed agent reads as INTERRUPTED, respawns into the same warning, fails identically, and exhausts its budget. `GitRunResult` now carries `stderr` alone, and `hasUncommittedWork` fails CLOSED on a non-empty stderr — a degraded scan is "couldn't tell", never an invented answer. **The reap gate's DECISION is unchanged** (`probeError` blocks exactly as `present` did; only the — now honest — reason differs).
- **The probe is BOUNDED.** It is the only I/O the engine puts on a step's COMPLETION path; a hung `git status` (an index lock, a stalled network FS) would leave the node latched-terminal with NO report ever — a silently STUCK step supervision cannot see. It now times out (`kWorkSignalTimeout`, 30s, per-allocation overridable) into `probeError`: fail closed, respawn LOUDLY, never stall (ADR-0008 D3 — a guard is loud or it is gone).

**Known limitation (stated, not fixed):** the work signal proves *"committed OR never edited"*. An agent murdered BEFORE its first write leaves a clean tree and still reads as a proven completion. The fence closes the mid-edit murder (the observed I-11), not the write-nothing-then-die case — which is indistinguishable from a legitimate no-op turn without a richer contract (e.g. requiring a NEW commit on the branch).

**The verdict rides the EXISTING supervision path.** Interrupted ⇒ `AllocationFailed` ⇒ `restartCount` bumps, the node re-keys, the step respawns in the SAME workspace (where the half-finished work still sits); `failed` is not a positive terminal, so the frontier keeps `verify` withheld. No new cursor state, no new machinery. This is the completion-side DUAL of ADR-0009 D4/D5's **no-adopt-on-faith** ("can't prove it ⇒ respawn"), in the same shape.

**Why:** A38's own justification for inferring the exit was that "work success is judged by the commit" — but nothing ever judged it. The fence is that missing judgment, and it is the ONLY place the engine can tell a murder from a completion, because on the wire they are the same event.

**Not this:** the fence does NOT gate observed exits (an exit code we read is proof), non-completion signals (a daemon's death, a `ready`), or capabilities that never promised a commit. It adds no reap gate and changes no reap behavior. It does not re-decide fail-closed-on-`probeError` (ADR-0006 D3 already ratified that).

**Second half, out of this repo:** the three live `ProcessCapability` impls (`AgentCapability`, `CriticCapability`, `SpecifyCapability`) live in **power_station**. With `none` the default, the critics and `specify` are correct with NO change — and the fence stays INERT for `AgentCapability` until it adds `@override CompletionContract get completionContract => CompletionContract.committedWorkspace;`. That is the deliberate trade: **inert is a safe failure mode; wedging genesis and lenny is not.**

**Affects:** `grid_runtime`: `runtime/runtime_event.dart` (`Exited.inferred`), `runtime/subprocess_provider.dart` (`_emitExit`), `git/git_ops.dart` (`hasUncommittedWork({excluding})` + the porcelain residue filter + the stderr fail-closed guard), `git/git_runner.dart` (`GitRunResult.stderr`), `git/station_git_service.dart` (the public `hasUncommittedWork` probe; `reap` UNCHANGED). `grid_engine`: `sdk/capability.dart` (`CompletionContract` + `ProcessCapability.completionContract`), `sdk/allocation.dart` (`WorkSignalProbe`/`noWorkSignal`/`kWorkSignalTimeout`/`AllocationContext.workSignal`+`workSignalTimeout` + the fence in `ProcessAllocation`), `kernel/station_services.dart` (`workSignal`), `circuit/capability_host.dart` (threads it), `testing/engine_fakes.dart` (`buildFakes(workSignal:)`). `grid_sdk`: `work/work_assembly.dart` (`stationWorkSignal` + the `StationServices` binding), `dart_test.yaml` (new). New tests: `git_ops_work_signal_test.dart` (16), `completion_fence_test.dart` (20, mutation-checked — killing the fence fails 8 assertions, the stderr guard 3, the timeout 1), `completion_fence_wiring_test.dart` (4, real git), + 2 in `subprocess_provider_test.dart` and 4 in `station_git_service_test.dart`. grid_runtime **153** / grid_engine **403** / grid_sdk **75** / grid_cli 80 / grid_exploration 13 / grid_devtools 15 offline green, `dart analyze packages` clean. The landed reliability wave (tg-4rw session disposition, PR #53 orphan sweep, PR #52 zombie reap) is composed WITH, never touched (all 16 `onOrphan`/`onRefusal`/`sweepOrphans` references in `work_assembly.dart` preserved).

**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (an ADR-0004 Decision 1 amendment for `inferred`, + an ADR-0008 D5 clause for `CompletionContract`) or dispose at will.

