# SCRATCH — the resident station (residency · control plane · arbitration)

**Status: RATIFIED (Nico, 2026-07-02), with amendments recorded in §3/§6/§9. GRADUATED
(2026-07-19): [ADR-0014](adr/ADR-0014-the-resident-station.md) is ratified and canonical —
this doc is design history (its per-incident forensics stay here).** Graduation
target: **one new ADR** (residency + control plane + arbitration; **number assigned by Nico
2026-07-19 (D-P7): ADR-0014** — the "next free is 0013" originally claimed here was consumed
by state-holding-value-types). **ADR-0012 stays fully reserved** — the control plane
deliberately does NOT ride the exploration/perception layer (§3, Nico's ruling). Build:
**grid agents, per fully-briefed beads (§8) — not hand-written.**

---

## 0. The gap, precisely

ADR-0008 D1 already promises the model:

> **`Station`** — the **machine** — one runtime, one reconcile loop, one capacity budget, one
> conductor.

Today's reality is a **runtime per invocation**: every `space run` cold-boots its own world
(controllers, kernel, dolt pool), and two concurrent invocations are two unarbitrated writers.
There is no attach — a second command cannot observe or address a running station.

The surprise from the ground-truth pass (§1): **the reactive resident posture already exists.**
`driveStation`'s default branch runs forever, parked on a SIGINT completer, and the controller
stays fresh push-based (file watch + 1 s SQL probe + 150 ms debounce) with no bespoke loop.
gc is resident *cadence-driven*; the grid's resident is *reactive* — "the kernel flush **is**
the loop" (ADR-0008 D9). Residency changes **who keeps the process alive and how others reach
it**, never the loop.

So the gap decomposes into exactly three axes:

1. **Residency** — the always-on posture is unmanaged: SIGINT-only shutdown, no single-instance
   guard, no supervision (launchd) story, `space up` doesn't exist.
2. **The control plane** — no way to observe or gracefully stop a running station; the shipped
   `space` binary is AOT, so even the dev-mode VM-service attach doesn't exist in the shipped
   artifact.
3. **Arbitration** — no station lock exists anywhere in the repo; the D8 governor is
   designed-but-deferred (D-7: `ResourceRequest` value-type only).

**Explicitly unchanged:** the reactive core (snapshot → tree → keyed reconcile), the A32/A37
write chokepoint + split store, the derailment invariants, bd-CLI-only mutation, coexistence
safety, and the ADR-0006 fail-closed ownership gates. Residency hardens the shell around the
engine; it does not touch the engine.

## 1. Ground truth (scouted 2026-07-02, file:line)

| Fact | Where |
|---|---|
| `driveStation` default = run forever on a SIGINT completer; only `--for-seconds` or `runForever:false` drain-and-exit | `grid_cli/lib/src/station_runner.dart:705-785` |
| **Only SIGINT is handled — no SIGTERM anywhere** for the orchestrator; `kill`/launchd stop bypasses `shutdown()` → host dispose → spawned-group kill | `station_runner.dart:776-781`; grep clean elsewhere |
| Reactivity is push-based: breadcrumb file watch (event-driven) + `SELECT @@tg_working` 1 s probe + 5 s CLI backstop, 150 ms trailing debounce, single-flight | `grid_controller/lib/src/reactivity/grid_runtime_factory.dart:59-89`, `graph_sync_interactor.dart:72` |
| **No single-instance mechanism exists** (no pidfile/flock/exclusive-create, repo-wide) | grep clean |
| Crash fence = session-bead metadata (`pgid`/`pid`/`token`, per-node `grid.cursor.*`), reconciled at boot; `AdoptProof` defaults to never-adopt | `grid_engine/lib/src/domain/session_bead.dart`, `restart/restart_reconciler.dart:69-84` |
| Exploration host transport is hard-bound to `dart:developer` — VM-service (JIT) only; the dev/debug attach surface, **not** a control plane | `grid_exploration/lib/src/grid_exploration_host.dart:78-117` |
| leonard's client is likewise `package:vm_service`-bound and pull-based — a dev tool attaching in dev mode | lenny `leonard_agent/lib/src/vm_service_client.dart:80-100` |
| space_station: thin app over `buildRunner()`; `run` = power_station's `CodeRunCommand`; **no exploration host mounted**; **AOT (`dart compile exe`) is the documented shipping model**; no launchd/install anything; no own `.beads/` | space_station `lib/space_station.dart:33-112`, `README.md` |
| Arming today (ADR-0006 + composition inversion): live requires `--root`, `--state-workspace`, **≥1 `--bead`** (the drive-list); dry-ness lives in the seams, never the loop | `station_runner.dart:257-298`, `:37-41` |
| Graceful restart = "detach-all → restart → reattach-all, no downtime"; daemon family = adopt-or-respawn, detach-capable | ADR-0009 D4 (:103-122) |
| Governor/permits deferred: D-7 ships `ResourceRequest` as declared value-type only | ADR-0008 D8 (:182) |

## 2. Residency (D-R1…D-R4 — shaped by Nico's rulings, §9)

**D-R1 — `space up` is THE verb; `run` is transitional scaffolding, then removed.**
There is no permanent scripted arm. A resident station with a per-invocation trigger verb
beside it is a door left open for chaos: a drive-list flag is a **trigger** — it would be used
by misbehaving agents doing the wrong thing or would confuse humans (Nico's ruling). So:

- `up` = the existing `driveStation` run-forever posture + the station lock (D-A1) + the
  control surface (D-C2) + resident arming (D-R4). **`up` takes no `--bead` flag, ever** —
  not even as a restriction filter. Foreground-resident (launchd-friendly; no
  self-daemonization, no double-fork — the supervisor owns backgrounding).
- `run` survives **only while `up` is being built**: it remains the vehicle for the
  already-staged tg-9fl live arm and for dev/dry-run testing. Once the first live `up` arm is
  proven, **`run` is retired (RS-8)** — dev/testing needs are covered by `up --dry-run` +
  `--for-seconds`.

**D-R2 — full signal contract.** SIGTERM joins SIGINT on the same graceful path
(complete the interrupt → `shutdown()` → control-surface + host dispose → controller dispose →
lock release). This is a hard prerequisite for supervision: today `launchctl stop`/`kill`
bypasses the spawned-group kill and leaks agent process groups. (SIGHUP: treat as TERM for
now; a reload semantics is not earned yet.)

**D-R3 — supervision = launchd, recipe-first.** A `LaunchAgent` plist template ships in
space_station (`KeepAlive`, `RunAtLoad`, stdout/err to log files, `WorkingDirectory`) + a
README runbook. A generated `space install` command is deliberately **later** — a template
earns automation after it's been operated. The crash story is **unchanged and load-bearing**:
process dies → launchd relaunches → freshness barrier → `RestartReconciler` (respawn-or-skip
today; adopt once tg-9fl lands) → kernel mount. Graceful zero-downtime restart (detach-all →
reattach-all, ADR-0009 D4) is the ceiling, explicitly **not** in this pass.

**D-R4 — the store is the sole bless surface: when a bead is ready, it's in.**
(Nico, 2026-07-02: "when the bead enters the system, it's in.") The flow has two dependency
layers, and both already exist:

1. **Inter-bead — bd dependency edges gate the ready frontier.** A discovery bead's
   dependents are not ready until it closes; closing it flips them ready, the dirty signal
   fires within ~1 s, and the station mounts the newly-ready work. Pipelines (discovery →
   spec → build → …) are expressed as dep chains in the store — no new mechanism.
2. **Intra-bead — the circuit's step-graph gates steps.** Inside a mounted work bead, the
   circuit (né formula, §6) advances by the frontier predicate over the per-node
   `grid.cursor.*` — fan-out, barriers, verify-before-land.

The drive set under `up` = the ready frontier of the owned substation through the existing
fail-closed gates, all unchanged: A41 `IssueType.isCore` allow-list, `OwnsSubstations`,
convergence-never-mounts, the A32 chokepoint re-check, default-dry-run, and the operator
being the only bd writer on the store. Every other arming input is unchanged (`--root`,
`--state-workspace`, explicit `--no-dry-run`, operator env token channel). **This supersedes
ADR-0006's "≥1 `--bead`" drive-list clause** — stamp at graduation, never silent.

## 3. The control plane (D-C1…D-C4 — v2: dedicated, minimal, read-only)

**D-C1 — the control plane does NOT ride perception/exploration (Nico's ruling).** The
perception tree is the **debugging** surface — it tunes its desired state and tool list to
the context of the running app; it's a fancy logger + tool calls for a debugger, and lenny is
a dev tool. Using it as the control plane is a category error. Consequences:

- `GridExplorationHost` stays **exactly as-is**: the dev-mode (JIT, `--enable-vm-service`)
  leonard attach. No transport seam, no host changes in this pass.
- ADR-0012's reserved scope (observability, the AOT exploration transport under
  perception+consent) is **untouched** — it remains the future *debug/observability* story,
  not the control plane.

**D-C2 — `StationControl`: a dedicated, read-only, loopback HTTP surface.** Owned by the
runner shell (grid_cli), started by `driveStation` under `up`, disposed on the graceful path:

- `GET /healthz` — cheap liveness (200 + `{ok:true}`).
- `GET /status` — identity (station, substation, state store, work root, dry/live), process
  (pid, uptime, version), and counts (ready, mounted, live sessions, last sync time).
- Bind **127.0.0.1 only**; bearer token minted per boot, living only in the 0600 lock file
  (never argv — the ADR-0006 precedent). Endpoint advertised via the lock (D-A1).
- **No mutation endpoints, by construction.** The control plane cannot be a trigger.

**D-C3 — lifecycle rides OS signals, not HTTP.**
- `space down` — read the lock → SIGTERM the pid (graceful via D-R2) → wait for exit +
  lock release → report.
- `space status` — read the lock → attach `GET /status` → render; no lock or dead endpoint →
  fall back to a direct read-only store view, clearly labeled `(station: down)`.

**D-C4 — work intake needs NO control plane.** The store **is** the intake: operator bd
writes (prep/bless/close) wake the resident station through the existing dirty signals within
~1 s. Net posture: **bd is the only mutation surface, signals are the only lifecycle surface,
HTTP is read-only observation.** One trigger surface in the whole system: a bead going ready
in the owned store.

**D-C5 — the unified-surfaces future (Nico, 2026-07-02 — documented want, deliberately NOT
solved now).** Nothing stops the grid from having its **own artifact tree** that provides
this surface without muddying lenny's perception. The want: **perception / control plane /
MCP / CLI+RPC all operate the same way under the hood and differ only as surfaces** — one
substrate, many faces — and **an MQTT surface is wanted** on that same substrate. Recorded so
the `StationControl` floor (D-C2) is built knowing it gets re-homed onto that substrate
later; it is a floor, not the end-state.

## 4. Arbitration (D-A1; ceiling pointed-at, not designed)

**D-A1 — the station lock, scoped per STATION state store (confirmed by Nico).** One
`space up` per station state store (`tgdog`) — substations are partitions *inside* the
station's store and get no locks of their own. Named invariant: **one supervisor per state
store** — two stations over the same session store double-spawn agents and double-write
session beads. Concrete failure story: two `space up` invocations against `tgdog` each
observe the same ready bead and both spawn a `claude` at it. Mechanism: exclusive-create
`<state-workspace>/.grid/station.lock` (JSON: `pid`, `pgid`, `startedAt`, `controlUrl`,
`token`); acquired in `driveStation` after `validateArming`, before `sources.start()`;
released on the graceful path. Stale detection: pid-liveness probe — dead holder → steal +
log; live holder → `StationRefusal` naming the pid and the `space status` attach hint. LOUD
when violated, per the guard principle. **Best practice (doc'd, not enforced): one grid per
machine** — one agentic fabric across the station's assets; spin containers if you want
multiples.

**The ceiling (later, separate passes):** the D8 `DartEnvironment` governor + leaf permits
(designed, D-7-deferred) for capacity, and leasing-is-core (`SCRATCH-dart-runner-and-cli-sdk.md`)
for substation attention-scheduling. This doc deliberately builds neither — the lock is the
only arbitration a single-machine dogfood needs.

## 5. Supersede/stamp ledger (applied only on ratification, never silent)

- **ADR-0006** — the "live arm requires ≥1 `--bead`" clause and "Disarming = stop `grid run`"
  get forward stamps: superseded by `up` + store-bless (D-R1/D-R4); `run` transitional →
  retired (RS-8).
- **ADR-0012 (reserved)** — untouched. Explicit note at graduation: the control plane is a
  dedicated surface, NOT ADR-0012's exploration transport (D-C1).
- **ADR-0008 D1** — no supersede; this doc *executes* D1's "one conductor" (cite-only stamp).
- **ADR-0009 D4** — no supersede; graceful-restart ceiling explicitly deferred-to (cite-only).
- **The Circuit rename (§6)** — forward stamps on ADR-0008's Formula vocabulary (D4 etc.) at
  graduation.

## 6. Vocabulary rulings (Nico, 2026-07-02 — decided with Nico, interactive)

- **`Formula` → `Circuit`**, and the inflation verb is **"energize"** (Nico's canonical;
  "electrify" is an accepted synonym — both should trigger the same context). Ripples
  through the grid_engine SDK types (`Formula`/`FormulaStep`/`FormulaScope`/`FormulaResolver`/
  `_FormulaChildren`, the `code` formula → **the code circuit**), power_station's assets, and
  the docs. Same discipline as the Station/Substation rename: **persisted/wire keys hold**
  (`grid.cursor.*`, step-event names, `kGridNamespace`, the gc codec boundary) — only the
  type/vocab layer moves. Executes as its own bead (RS-7), parallel to the residency work.
- **`Order` → `Demand Response`** — debated, **NOT decided** ("might be getting silly").
  `Order` stays until Nico says otherwise.

## 7. Non-goals (this pass)

Federation/bus (parked, `m6-federation`); the D8 governor + permits; leasing/scheduling;
zero-downtime graceful restart (detach-all/reattach-all); the AOT exploration transport +
`genesis_consent` (ADR-0012, reserved); any exploration-host or leonard change; control-plane
mutation endpoints (never — D-C4); Windows/systemd; multi-station-per-machine; any
engine-core change.

## 8. The bead ladder (filed with full briefs after ratification)

Each bead gets the tg-9fl-grade brief (description / design / acceptance criteria /
validation_plan in metadata) at filing time. Grid agents build; the operator preps, blesses,
arms, reviews. All offline-testable except RS-6's runbook proof and RS-8's live gate.

| # | Bead | Scope (pkg) | Depends on |
|---|---|---|---|
| RS-1 | SIGTERM/SIGHUP join the graceful shutdown path | `grid_cli` (`driveStation`) | — |
| RS-2 | The station lock: exclusive-create, stale-steal, `StationRefusal` on live holder, release-on-shutdown | `grid_cli` | RS-1 (release path) |
| RS-3 | Resident arming: ready-frontier drive set (no `--bead`), `validateArming` variant behind the resident mode | `grid_cli` | ratification (D-R4) |
| RS-4 | `StationControl`: read-only loopback HTTP (`/healthz`, `/status`), bearer token, lock-advertised, ephemeral-port tests | `grid_cli` | RS-2 |
| RS-5 | `space up` / `space down` / `space status`: compose lock + resident arming + control surface + attach-if-up client with store fallback | space_station + `grid_cli` | RS-2, RS-3, RS-4 |
| RS-6 | launchd plist template + operator runbook | space_station | RS-5 |
| RS-7 | The Circuit rename: `Formula`→`Circuit`, "energize" verb, whole-repo vocab; wire/persisted keys held; power_station migration sequenced behind it | `grid_engine` + assets + docs | — (parallel) |
| RS-8 | Retire `run`: delete the verb once the first live `up` arm is proven; dev/testing folds into `up --dry-run`/`--for-seconds` | `grid_cli` + space_station | RS-5 + the live proof |

First proof: `space up --dry-run` under launchd; `space status` attaching over the control
surface against the **AOT** binary; a bead blessed in-store picked up with no restart;
`launchctl stop` shutting down clean (no leaked agent groups); `kill -9` + relaunch
recovering through the barrier; a second `space up` refused LOUD by the lock.

**✅ FIRST PROOF PASSED 8/8 (2026-07-02, operator-run, Nico installed the LaunchAgent):**
AOT `space up` resident (lock + 0600 token + controlUrl) · AOT `status` attach over HTTP ·
second `up` refused exit-64 naming pid+invariant · resident arming = the driveable owned
frontier (epic excluded at the true mount gate; the `/status mounted` display over-count is
filed as tg-8p9) · store bless reflected live in ~4s, no restart · `kill -9` under launchd →
unattended relaunch + LOUD stale-lock steal · `space down` = graceful stop, lock released,
labeled fallback, **no KeepAlive bounce** (`SuccessfulExit=false` composing with RS-1's
exit-0). The ladder RS-1…RS-7b is fully landed (16 beads, all agent-built). **Remaining at
the live gate:** the first LIVE `space up` (no drive-list — the blessed frontier IS the
drive set), then RS-8 files (retire `run`), then the graduation ADR.

## 9. Rulings log (Nico, 2026-07-02)

- **OQ-1 (bless surface)** → ready-in-owned-store confirmed: "when the bead enters the
  system, it's in"; dep order gates the pipeline (discovery closes first). No `grid.armed`
  second key. Plus the renames (§6).
- **OQ-2 (lock scope)** → per **station** state store (not substation); one grid per machine
  as best practice; containers for multiples.
- **OQ-3 (graduation)** → follows from the above: one new ADR for residency + control plane +
  arbitration; ADR-0012 untouched (control plane ≠ exploration). Number assigned by Nico at
  graduation.
- **OQ-4 (verbs)** → `up`/`down`/`status` confirmed.
- **`run`** → not a keeper: transitional while `up` is built (incl. the staged tg-9fl arm),
  dry-run/dev only otherwise, retired at the end (RS-8). `--bead` on the resident verb
  rejected as a trigger surface.
- **Control plane** → must not ride perception/exploration (that's the debugging surface);
  dedicated read-only HTTP + signals instead.

**Ratification amendments (Nico, 2026-07-02, "Ratified with above amendment. Let's roll."):**
- The unified-surfaces future + the MQTT surface want → recorded as D-C5 (documented, not
  solved now; the grid may grow its own artifact tree for this without muddying lenny's
  perception).
- The verb is **energize**, not electrify (both trigger the same context) → §6 corrected.

**Remaining open:** the ADR number (at graduation); whether transitional `run` should be
hard-constrained (e.g. refuse `--no-dry-run` after the tg-9fl arm lands) or just left until
RS-8 deletes it. RS-8 itself is **not filed** until the first live `up` arm is proven — filing
it earlier would make it auto-ready under the very resident station it retires the scaffold
of.

**Filing catch (operator, 2026-07-02):** the RS **epic** itself surfaces in `bd ready` (A41
retains epic/milestone/decision in `isCore`) — so resident all-ready arming needs an explicit
**driveable-work boundary** (task/bug/feature/chore mount; epic/milestone/decision never do,
under resident). Recorded on the RS-3 bead as a scoped tightening (the existing gates stay
untouched); flag for the graduation ADR as an A41 refinement. Ladder filed as **tg-3s8**
(epic) + **tg-3s8.1–.9** (RS-1…RS-7b), blocking deps wired, frontier verified =
{RS-1, RS-7}.
