# SCRATCH — the async step lifecycle: how a step terminalizes

**Status: DRAFT** — the consolidated output of the 2026-07-19 process/lease/runtime audit
(governor seat, read-only). This doc *proposes*; nothing in it is ratified. Per the ADR-0000
register rule, the direction in §6 graduates to an ADR only when Nico ratifies it. Code truth
below is pinned to `main` @ `0b10f27` (tg-2mb merged, molecule the live default).

**Scope** (Nico's call, 2026-07-19): the process/lease/runtime surface only — spawn, lease
acquire/dispatch, the `RuntimeProvider` event stream, death detection, watchdogs, the
completion fence. The wider reactive engine (join bridge, snapshot diffing, drive loop,
restart reconciler, molecule pour/frontier) is a later pass.

**Why this doc exists.** "How does a step end?" is today answered across four files, five
ADRs, eight ADR-0000 amendments, and five SCRATCH docs — and the answers disagree. The cost
is not hypothetical: the tg-uad stall (pow-87e, 2026-07-19) sat undiagnosable for a session
precisely because no single document describes the terminalization path. §3 resolves tg-uad
with receipts; §4 is the defect ledger; §5 is the doc-drift ledger.

---

## 1. The one question, answered in one place

A **step** terminalizes when its host persists a terminal report from its allocation
(`grid.step.state` → `complete` / `failed` / a route disposition; the bead `status` stays
`open` until circuit completion). The allocation produces that report by **interpreting a
`RuntimeEvent`** from the process transport. So the whole question reduces to:

> **How does the terminal `RuntimeEvent` of a spawned process reach the code that is
> waiting for it?**

There are exactly two consumption shapes in the engine today, and they differ in a way that
matters (§2.3): the **flat path** holds one subscription for the process's whole life; the
**leased path** (the molecule default since tg-6gi/tg-2mb) subscribes **twice** with an
awaited bd write between the subscriptions. Everything else — lifecycle inference, the
watchdog, the completion fence — hangs off which events those subscriptions actually see.

---

## 2. The machinery today (code truth)

### 2.1 The event vocabulary

`RuntimeEvent` (grid_runtime `runtime_event.dart`) is a sealed union of **five** variants:
`SessionStarted`, `Exited(exitCode, inferred)`, `Died(reason)`, `Respawned`,
`ActivityChanged`.

- `Exited.inferred` (A49): a detached one-shot exposes no readable exit code, so its vanish
  is reported as `Exited(0, inferred: true)` — a *guess by intent*, which the completion
  fence (§2.5) proves before a `committedWorkspace` capability advances on it. An observed
  code (`inferred: false`) is evidence and is not fenced.
- ADR-0004 also declares `Attached`/`Detached`. **They were never built** (no such classes
  in grid_runtime), like the `TmuxProvider` that would emit them (§5).

### 2.2 The four "process ends" mechanisms

All four live in `SubprocessProvider` (grid_runtime `subprocess_provider.dart`); whichever
fires first wins, guarded by a per-session `exitEmitted` latch:

| # | Mechanism | Fires when | Emits |
|---|---|---|---|
| 1 | `spawned.exitCode` future | never in production — `detachedWithStdio` throws on `Process.exitCode`, so the system spawner returns null; only fakes provide it | `Exited(code)` (observed) |
| 2 | liveness poll (`_pollPeriod` 100ms, leader-pid `processAlive`) | the real death signal for every production process | `oneTurn` → `Exited(0, inferred: true)`; `longLived` → `Died('process vanished')` |
| 3 | watchdog deadline (default 2h; per-config override) | the process outlives its deadline | kills the group, then `Died('watchdog: …')` — outranks the oneTurn inference so a shot hang never reads as success |
| 4 | `stop()` | teardown / release | **emits nothing** — a stopped session is silent by design |

Two properties of this table are load-bearing and nowhere else written down:

- **Every emission is exactly-once, push-only, and unbuffered.** `_events` is a plain
  `StreamController.broadcast()`: an event emitted while no listener is subscribed is
  dropped, permanently. There is no replay, no per-session latch of "this session's
  terminal", no query for "did this session already end". The terminal *outcome of a
  process exists only as an instant on a stream*.
- **The emit disarms the watchdog.** `_emitExit` removes the session from `_sessions` and
  cancels supervision *including the deadline timer*, then emits. If that one emission is
  lost (see D1), the watchdog — the only backstop against "latched at running forever" —
  is already cancelled. The safety net is disarmed by the very event that got lost.

### 2.3 The two consumption shapes

**Flat path — `ProcessAllocation` (sdk/allocation.dart).** Subscribes once, *before*
`transport.start`, and holds `_sub` for the allocation's entire life; `_onEvent` sees
`SessionStarted` and, later, the terminal, on the same subscription. There is no window in
which a terminal can fire unheard (short of the allocation never mounting).

**Leased path — the molecule default (molecule/station_process_transport.dart).** The lease
family's two-phase contract (`sdk/lease.dart`: acquire, then dispatch) maps onto the stream
as **two independent subscriptions**:

1. `stationProcessSpawner` subscribes, provisions, `transport.start`s, resolves the
   `ProcessHandle` on `SessionStarted` (sinking `AllocationStarted` → `state=running`),
   then cancels its subscription. From the moment `started.isCompleted`, its listener
   ignores everything — including a terminal.
2. `_VendedProcessLease.acquire` then **awaits the lease-breadcrumb write**
   (`writer.update(stepBeadId, leaseBreadcrumb)`) through the `StationBeadWriter`
   chokepoint — a *serialized* queue of real bd/Dolt writes.
3. Only after that write completes does `LeaseAllocation.startOrAdopt` call `dispatchOn`,
   and `stationProcessDispatcher` subscribes *again*, waiting for the first event whose
   `interpretEvent` is non-`none`.

**The gap between step 1's effective end (SessionStarted) and step 3's `listen()` is an
unobserved window on an unbuffered stream.** Its width is the breadcrumb write's queue
latency — milliseconds when idle, *minutes* under a post-boot remount burst or a busy
committee round. Any process that exits inside the window emits its terminal to zero
listeners (§2.2). This is defect **D1**, the tg-uad root cause — proven in §3.

### 2.4 The lifecycle axis and the watchdog

`Lifecycle {oneTurn, longLived}` (RuntimeConfig) is the *interpretation* axis for a
poll-detected vanish: completion-by-intent vs crash (A38). The committee's gating lane
spawns `oneTurn` (committee.dart:665) so its vanish is `Exited(0, inferred: true)`; its
`interpretEvent` is total over terminals (`Exited → complete`, `Died → failed`), so a
watchdog kill correctly fails the step — *when the dispatcher is subscribed to hear it*.

The watchdog is an absolute-from-spawn deadline (not inactivity — `claude -p` is silent
until it finishes), default 2h, per-lane override via `RuntimeConfig.deadline`. Note the
gating lane passes **no** deadline today and rides the 2h default; a validation plan that
should finish in minutes gets the same generous backstop as a frontier build agent.

### 2.5 The completion fence (A49, "no-complete-on-faith")

Applies on **both** paths, only when `completionContract == committedWorkspace` **and** the
terminal is `Exited(inferred: true)`: the work-signal probe proves the workspace committed
(or never edited) before the circuit advances; `present` → `Failed('interrupted:
uncommitted work remains')`, probe failure → fail-closed. An observed exit code is not
fenced. Critic/validation lanes default to `CompletionContract.none` — their consumption
problem is delivery (D1), not proof.

### 2.6 Adopt and liveness — what `liveness` is *not*

`StationServices.liveness` (`AllocationLiveness`, default `neverLive`) is consulted in
exactly one place on the leased path: `proveFresh`, the adopt-across-restart proof — and
only for **daemons** (`isAdoptable ⇒ StepKind.daemon`; a job lease *always* respawns).
Liveness plays **no role in exit detection** — that is solely the provider's poll. Reading
`lease.dart`'s doc comments alone suggests otherwise; it isn't so.

---

## 3. Case study: the pow-87e stall (tg-uad), resolved

Session `houston-g4fv` (work bead pow-87e), molecule mode, 2026-07-19. Symptom: every
review step `complete` except `review/code-validation` (step bead houston-f7l6) latched at
`running`; rc file present with `0`; process dead; committee → landing seam hung; no PR.

The receipts (all times UTC):

| When | Evidence | Meaning |
|---|---|---|
| 04:43:01–04:43:08 | step beads: clear-critique, pin-diff, 3 critic lanes start | review circuit fans out |
| 04:44–04:48 | critic verdict JSONs + usage files (worktree mtimes 04:44:52–04:48:18) | LLM lanes complete normally (minutes-long — the write queue drains before they exit) |
| ~04:43–04:45 | *(inferred)* gating lane round 1 spawns, exits ~2s later — its rc write is later overwritten | first instance of the stall; board freezes at `latest=regression-risk@04:48:18` |
| 05:41:33–05:41:48 | prior-session transcript: `space down`, then `up` | the governor bounces the station onto the merged #73 |
| 05:41:58.816 | houston-f7l6 `grid.step.startedAt` | post-boot remount: a job lease never adopts → **respawn**; `SessionStarted` observed, `state=running` persisted |
| 05:42:00 | worktree mtimes: `code-validation.rc` (`0`) **and** `.dart_tool/test/incremental_kernel.*` | the plan really completed here. Measured 2026-07-19 in the same worktree, warm: **1.82s, exit 0** — the lane exits ~2s after spawn |
| ~05:42:00.1 | *(mechanism)* poll detects death within 100ms → `_emitExit`: session deregistered, **watchdog cancelled**, `Exited(0, inferred: true)` emitted | **zero listeners**: the spawner's sub is cancelled/inert; the dispatcher is still parked behind the breadcrumb write in the post-boot writer burst. The terminal is dropped |
| 05:42+ → 16:53 | step stays `running` for ~11h; no watchdog `Died` ever fires (it was cancelled at the emit) | the dispatcher subscribes moments later and waits forever, backstop-free |
| 16:53 | station down: f7l6's `grid.lease.*` keys read as the cleared sentinel (`""`) | teardown's `dispose → release` ran (stop no-op on the long-dead session, breadcrumb cleared) — while `grid.step.state` stayed `running` |

**Verdict: mode (a), emitted-but-missed** across the acquire→dispatch handoff. The
never-emitted hypothesis (mode b) is excluded by the watchdog constraint: had the exit gone
undetected, the session would have stayed registered and the 2h watchdog would have fired
`Died('watchdog: …')` at 07:41:58 into a by-then-subscribed dispatcher, failing the step.
It stayed `running`.

**Why it targets the gating lane specifically:** a warm validation plan exits in ~2s —
*inside* its own acquire's breadcrumb-write window whenever the writer queue holds more
than a couple of entries (post-boot burst; simultaneous lane fan-out). The LLM critic lanes
run minutes and never race the window. The failure is therefore near-deterministic for
fast-exiting lanes and invisible for slow ones — which is exactly the observed signature,
twice (round 1 at ~04:43, round 2 post-bounce at 05:41:58).

**The test gap that let it ship:** `station_process_transport_completion_fence_test.dart`'s
`_dispatchWith` always calls `stationProcessDispatcher(...)` *first* and emits terminals
*after* — the acquire→dispatch window is structurally unreachable by the existing suite.

---

## 4. The defect ledger

**D1 — the unobserved terminal window (P1; this is tg-uad).** The leased path's two
subscriptions + the awaited serialized breadcrumb write between them, over an unbuffered
broadcast stream (§2.3, §3). Fix direction in §6; the narrow fix is a single subscription
spanning acquire→dispatch (mirroring `ProcessAllocation`), threaded through the handle or
the request. The narrow fix alone still leaves every *future* consumer one refactor away
from the same bug — hence §6.

**D2 — the lost emit disarms the backstop.** `_emitExit` cancels the watchdog before/with an
emission that may reach nobody (§2.2). Even with D1 fixed, any dropped terminal leaves a
step latched with no time-bounded recovery. A terminal that cannot be delivered should
remain *queryable* (§6), or at minimum the watchdog should not be cancelled by an emission
with zero listeners (`_events.hasListener` is checkable — but see §6 for why holding the
state is the real fix).

**D3 — a bd write sits inside the lease's critical section.** Acquire awaits the breadcrumb
write between spawn and dispatch, so D1's window scales with *unrelated* station write load
(and tg-7ux says a >15s bd stall crashes the station outright). Direction: persist the
breadcrumb concurrently with dispatch (it serves *restart adoption*, not the live path — a
daemon that dies before its breadcrumb lands just respawns, which is today's posture
anyway), or at least start the dispatcher's subscription before awaiting the write.

**D4 — the handoff window is untested.** No test emits a terminal between `SessionStarted`
and `dispatchOn`. Any D1 fix needs exactly that regression test (a fake transport whose
lane exits during the breadcrumb await), plus a fast-exit lane test at the
`SubstationWork`/composition tier.

**D5 — the `SessionAlreadyExists` swallow can hang acquire forever.** `stationProcessSpawner`
swallows `SessionAlreadyExists` and keeps waiting for a `SessionStarted` that fired before
it subscribed — for a pre-existing live session, `started.future` never resolves and the
step hangs in acquire with `state` never reaching `running` (distinct signature from D1:
no `startedAt` stamp). The flat path degrades softer (its live subscription still catches
the eventual terminal, though it too misses the already-fired start). The comment claims
"the SessionStarted event still resolves the handle below" — untrue when the start predates
the subscription. Needs a liveness-of-claim check or a synchronous `isRunning`/pid query
fallback.

**Noted limitations (not filed as defects):**
- Poll-based death detection keys on the *leader* pid only — correct for our lanes (leader
  exit ⇒ lane over), and stdout-EOF is deliberately not trusted; pid-reuse within 100ms is
  accepted risk.
- `stop()` emitting nothing is by design, but combined with §2.2's no-replay property it
  means "stopped" is indistinguishable from "never existed" for a late-subscribing
  consumer — acceptable only while teardown and dispatch can't overlap, which D1's fix
  must keep true.
- The gating lane rides the 2h default watchdog; a per-lane deadline (minutes) would bound
  every future variant of "validation latched" — cheap hardening, worth doing with D1.

---

## 5. The doc-drift ledger (reconciled against ORG-REVIEW.md and `docs/SCRATCH-docs-debt-sweep.md`
(retired to git history — tg-8gv.8), folded into `docs/OPERATIONS.md` §4 at the
public-readiness pass, 2026-07-20)

The prior sweeps deliberately did not cover this surface: `docs/SCRATCH-docs-debt-sweep.md`
(retired to git history — tg-8gv.8) was terminology/topology ("no new code in this pass")
and ORG-REVIEW touched it only at the
TmuxProvider-not-built / `listBeadWorktrees`-no-caller level. This section *extends* them.

1. **ADR-0004 is materially stale.** `TmuxProvider` — described as the *primary* provider,
   with a full kill-sequence — was never built; `RuntimeEvent.Attached/Detached` were never
   built; `grid run --provider tmux` silently returns a `SubprocessProvider` (ORG-REVIEW
   §5.13 flags the same). Needs a supersession/reality stamp, not a rewrite.
2. **The "molecule is inert" era is over and no doc says so.** A52's remediation text,
   SCRATCH-diagnostics-projection, and DESIGN-tg-pm6's staging all describe the lease
   vendor as "uncomposed anywhere in production… fully inert / default flatCursor". Since
   then tg-h4u (real transport), tg-6gi (molecule default), and tg-2mb/#73 (vendor on the
   production seat) landed: **molecule is the live default** (`station_work.dart`
   `circuitMintMode = CircuitMintMode.molecule`; space unpinned its flat pins). A reader —
   or a subagent — following the docs concludes the opposite of reality. Needs a dated
   re-stamp on all three. *(tg-eli, 2026-07-19: superseded — `CircuitMintMode`/
   `flatCursor` are now deleted outright; molecule is the only circuit engine, so the
   mint-mode question this item raises no longer applies.)*
3. **The signal-vs-derivation fork is open and undated.** A47/A51 (`RouteVerdict
   {advance, rewind, escalate}`) are ratified *and live*; SCRATCH-declarative-routing +
   SCRATCH-beads-all-the-way-down + DESIGN-tg-pm6 R4 design its deletion ("no RouteVerdict,
   no signal — backward motion is derived"). Neither side carries a stamp saying which is
   canonical *today*. This is a Nico decision in flight (declarative-routing is marked
   DRAFT-for-ratification); until then, each doc should state "the signal model is what
   runs; the derivation model is designed, partially built, not wired."
4. **Process identity: cursor-fence vs lease.** ADR-0007 D4 / ADR-0008 D6 / M4-P1 D-4 home
   `pgid/pid/token` on the durable cursor; DESIGN-tg-pm6 homes it in vendor-owned
   `grid.lease.*`. With molecule now live, the **lease is the production home** — but the
   flat path (and its cursor fence) still exists and the older ADRs read as current. Needs
   cross-stamps ("on the molecule path, superseded by DESIGN-tg-pm6 R3").
5. **Smaller stale claims:** M4-P1's `StepState` is 5-valued (code has 6, with `gated`);
   ADR-0007 D4's "adopt is deferred net-new work" predates `startOrAdopt`/`AdoptProof`
   landing. *(Correction, 2026-07-19 debt-pass verification: an earlier draft of this
   item claimed Track G's "dissolved" smells still existed — they do not. `Expando` and
   live `_capCtx` are gone from lib (only a lineage comment at `sdk/allocation.dart:12`
   remains) and `CancelToken` is now the intended typed `StepArgs.cancel` field, not
   juggling. Track G executed.)*
6. **What the incident catalog already holds:** SCRATCH-orchestration-determinism I-9 (a
   graceful down leaked an in-flight spawn; down-path orphan sweep filed-deferred, not
   landed) and I-11 (murdered-vanish-as-completion → A49) are this surface's prior art —
   tg-uad belongs beside them as I-15-class material once this doc's findings are absorbed.

---

## 6. Direction (DRAFT — for ratification, not ratified): a terminal is state, not an event

Every defect in §4 is a special case of one modeling error, and ADR-0013 already names it:
**the terminal outcome of a process is *state*, but the engine holds it only as an
*instant* on an unbuffered stream.** A consumer that isn't listening at that instant can
never learn the outcome, and the engine cannot even answer "did this session end?" after
the fact.

Proposed shape (deliberately small; the seam already exists):

1. **The provider retains each session's terminal** (`Exited`/`Died`, with its
   inferred/observed flag and reason) from emission until an explicit acknowledge/release —
   e.g. `RuntimeProvider.terminalOf(name) → RuntimeEvent?` beside `isRunning`. The stream
   stays (push is right for the live path); the held record makes late consumers correct
   instead of deadlocked.
2. **The leased dispatcher checks-then-awaits:** consult the held terminal first, then
   subscribe — the standard state-then-stream pattern. D1 and D2 dissolve (a lost emission
   no longer loses the outcome; the watchdog-cancel-at-emit becomes harmless).
3. **One subscription per incarnation as defense-in-depth:** acquire opens it before
   `transport.start` and hands it to dispatch through the request/handle (mirroring
   `ProcessAllocation`), so the live path never depends on the recovery path.
4. **The breadcrumb write leaves the critical section** (D3): dispatch may begin while the
   adopt breadcrumb persists concurrently — it serves restarts, not the live path.

This also converges the two consumption shapes: flat and leased both become
"subscribe-early + held-terminal", differing only in who owns the subscription — a
prerequisite for ever retiring the flat path (tg-eli) without re-learning this bug.

What would graduate to an ADR: the held-terminal contract on `RuntimeProvider` (point 1)
and the single-subscription lease contract (point 3). Points 2 and 4 are implementation.

---

## 7. Where the findings went

- **tg-uad** (the_grid, P1, deferred) — updated with the §3 root-cause resolution; it is
  the fix bead for D1 (+D2/D3 as one coherent change, per §6).
- New deferred beads filed alongside it for D4 (the handoff-window regression test), D5
  (the `SessionAlreadyExists` acquire hang), and the §5 doc re-stamps (one chore bead).
- §5.3 (signal-vs-derivation) deliberately gets **no bead**: it is an in-flight Nico
  ratification (SCRATCH-declarative-routing), not backlog.
