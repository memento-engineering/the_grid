# ADR-0014 — The resident station (residency · control plane · arbitration)

**Status:** **Accepted — ratified by Nico, 2026-07-19.** (Underlying decisions Nico-ratified
2026-07-02; the ratification gate — remove the flat cursor from code and documentation — was
met the same day via tg-eli phases 1+2.)

**Source of record:** this document. It graduated
[docs/SCRATCH-resident-station.md](../SCRATCH-resident-station.md) (RATIFIED Nico 2026-07-02,
amendments in its §3/§6/§9 — now design history; its per-incident forensics remain there). The number **0014** was assigned by Nico 2026-07-19
(**D-P7**) — the "next free is 0013" originally claimed in the SCRATCH was consumed by
[ADR-0013](ADR-0013-state-holding-value-types.md).

**Date:** 2026-07-19 · **Deciders:** Nico (underlying decisions, 2026-07-02) · **Relates:**
ADR-0006 (live-arm authorization — see Supersessions), ADR-0008 D1/D8/D9, ADR-0009 D4,
ADR-0012 (reserved — explicitly NOT this, per D-C1), ADR-0000 A32/A37/A41.

---

## Context

ADR-0008 D1 promises the model: **`Station` — the machine — one runtime, one reconcile loop, one
capacity budget, one conductor.** The pre-residency reality was a **runtime per invocation**:
every `run` cold-booted its own world, two concurrent invocations were two unarbitrated writers,
and no second command could observe or address a running station.

The load-bearing surprise from the ground-truth pass: **the reactive resident posture already
existed.** The drive loop's default branch runs forever parked on a SIGINT completer, and the
controller stays fresh push-based (file watch + 1 s SQL probe + 150 ms debounce) — "the kernel
flush **is** the loop" (ADR-0008 D9). gc is resident *cadence-driven*; the grid's resident is
*reactive*. Residency therefore changes **who keeps the process alive and how others reach it**,
never the loop. The gap decomposes into exactly three axes — **residency** (the always-on posture
was unmanaged: SIGINT-only shutdown, no single-instance guard, no supervision story), **the
control plane** (no way to observe or gracefully stop a running station), and **arbitration**
(no station lock existed anywhere; the ADR-0008 D8 governor is designed-but-deferred, D-7).

**Explicitly unchanged:** the reactive core (snapshot → tree → keyed reconcile), the A32/A37
write chokepoint + split store, the derailment invariants, bd-CLI-only mutation, coexistence
safety, and the ADR-0006 fail-closed ownership gates. Residency hardens the shell around the
engine; it does not touch the engine.

## Decisions

### Residency (D-R1 … D-R4)

**D-R1 — `space up` is THE verb; `run` is transitional scaffolding, then removed.** There is no
permanent scripted arm. A resident station with a per-invocation trigger verb beside it is a door
left open for chaos: a drive-list flag is a **trigger** — it would be used by misbehaving agents
doing the wrong thing or would confuse humans (Nico's ruling). `up` = the run-forever posture +
the station lock (D-A1) + the control surface (D-C2) + resident arming (D-R4). **`up` takes no
`--bead` flag, ever** — not even as a restriction filter. Foreground-resident (launchd-friendly;
no self-daemonization, no double-fork — the supervisor owns backgrounding). `run` survives only
while `up` is built (dev/dry-run testing and the then-staged live arm); once the first live `up`
arm is proven, `run` is retired (RS-8) — dev/testing folds into `up --dry-run` + `--for-seconds`.

**D-R2 — full signal contract.** SIGTERM joins SIGINT on the same graceful path (complete the
interrupt → `shutdown()` → control-surface + host dispose → controller dispose → lock release).
A hard prerequisite for supervision: a bare `kill`/`launchctl stop` previously bypassed the
spawned-group kill and leaked agent process groups. SIGHUP: treat as TERM for now — a reload
semantics on the signal contract is not earned yet. *(The later `space reload` dev-mode seat is
an explicit VM-service trigger, not a SIGHUP semantics — see Build state.)*

**D-R3 — supervision = launchd, recipe-first.** A `LaunchAgent` plist template ships in
space_station (`KeepAlive`, `RunAtLoad`, stdout/err to log files, `WorkingDirectory`) + a README
runbook. A generated `space install` command is deliberately **later** — a template earns
automation after it's been operated. The crash story is **unchanged and load-bearing**: process
dies → launchd relaunches → freshness barrier → `RestartReconciler` → kernel mount. Graceful
zero-downtime restart (detach-all → reattach-all, ADR-0009 D4) is the ceiling, explicitly
**not** in this pass.

**D-R4 — the store is the sole bless surface: when a bead is ready, it's in.** (Nico,
2026-07-02: "when the bead enters the system, it's in.") Two dependency layers, both
pre-existing: **inter-bead** — bd dependency edges gate the ready frontier (a discovery bead's
dependents are not ready until it closes; closing it flips them ready, the dirty signal fires
within ~1 s, and the station mounts the newly-ready work — pipelines are dep chains in the
store, no new mechanism); **intra-bead** — the circuit's step-graph gates steps by the frontier
predicate over per-node step state — `grid.step.*` on per-step beads (molecule is the only
circuit engine as of tg-eli phase 2; `grid.cursor.*` / the flat-cursor path no longer exist).
The drive set under `up` = the ready frontier of
the owned substation through the existing fail-closed gates, all unchanged: the A41
`IssueType.isCore` allow-list, `OwnsSubstations`, convergence-never-mounts, the A32 chokepoint
re-check, default-dry-run, and the operator being the only bd writer on the store. Every other
arming input is unchanged (`--root`, `--state-workspace`, explicit `--no-dry-run`, operator env
token channel). **This supersedes ADR-0006's "≥1 `--bead`" drive-list clause — stamp at
ratification, never silent** (see Supersessions). *A41 refinement (flagged from the filing
catch): resident all-ready arming needs an explicit **driveable-work boundary** — task/bug/
feature/chore mount; epic/milestone/decision never do under resident (A41 retains them in
`isCore`, so the RS epic itself surfaced in `bd ready`). Scoped tightening on the mount gate;
the existing gates stay untouched.*

### The control plane (D-C1 … D-C5)

**D-C1 — the control plane does NOT ride perception/exploration (Nico's ruling).** The
perception tree is the **debugging** surface — it tunes its desired state and tool list to the
context of the running app; it is a fancy logger + tool calls for a debugger, and lenny is a dev
tool. Using it as the control plane is a category error. Consequences: `GridExplorationHost`
stays exactly as-is — the dev-mode (JIT, `--enable-vm-service`) leonard attach; no transport
seam, no host changes in this pass. **ADR-0012's reserved scope** (observability, the AOT
exploration transport under perception + consent) is **untouched** — it remains the future
debug/observability story, not the control plane. This is ADR-0012's boundary.

**D-C2 — `StationControl`: a dedicated, read-only HTTP surface, loopback by default.** Owned
by the runner shell (grid_cli), started under `up`, disposed on the graceful path. `GET
/healthz` — cheap liveness; `GET /status` — identity (station, substation, state store, work
root, dry/live), process (pid, uptime, version), and counts (ready, mounted, live sessions,
last sync time). Binds **127.0.0.1 by default**; binding a LAN interface is a deliberate,
explicit composition choice (Nico, 2026-07-19 ratification review — LAN access is a wanted
posture, consistent with the LAN cockpit in ADR-0012 D1), never a silent default. The bearer
token — minted per boot, living only in the 0600 lock file (never argv — the ADR-0006
precedent), endpoint advertised via the lock (D-A1) — is required on **every** endpoint
including `/healthz` (the landed tightening, adopted here: no unauthenticated probe is exactly
what makes a LAN bind sane). **No mutation endpoints, by construction** — the control plane
cannot be a trigger.

**D-C3 — lifecycle rides OS signals, not HTTP.** `space down` — read the lock → SIGTERM the pid
(graceful via D-R2) → wait for exit + lock release → report. `space status` — read the lock →
attach `GET /status` → render; no lock or dead endpoint → fall back to a direct read-only store
view, clearly labeled `(station: down)`.

**D-C4 — work intake needs NO control plane.** The store **is** the intake: operator bd writes
(prep/bless/close) wake the resident station through the existing dirty signals within ~1 s.
Net posture: **bd is the only mutation surface, signals are the only lifecycle surface, HTTP is
read-only observation.** One trigger surface in the whole system: a bead going ready in the
owned store.

**D-C5 — the unified-surfaces future (Nico, 2026-07-02 — documented want, deliberately NOT
solved now).** Nothing stops the grid from having its **own artifact tree** that provides this
surface without muddying lenny's perception. The want: **perception / control plane / MCP /
CLI+RPC all operate the same way under the hood and differ only as surfaces** — one substrate,
many faces — and **an MQTT surface is wanted** on that same substrate. Recorded so the
`StationControl` floor (D-C2) is built knowing it gets re-homed onto that substrate later; it is
a floor, not the end-state.

### Arbitration (D-A1)

**D-A1 — the station lock, scoped per STATION state store (confirmed by Nico, OQ-2).** One
`space up` per station state store. Store vocabulary (Nico, 2026-07-19 ratification review):
the **station** owns exactly one **state store** (session/lifecycle beads, at the grid home);
each **substation** contributes its own **work store** (the work source — read-only to the
station, per the A37 split) and gets no lock of its own; the session-side of every substation
lives as partitions *inside* the station's one state store. A dual-role repo (e.g.
space_station: the grid home AND a substation of its own running station) holds both — the
lock belongs to its station role, never its substation role. Named invariant: **one supervisor
per state store** — two stations over the same session store observe the same ready bead,
double-spawn agents at it, and double-write session beads. Mechanism: exclusive-create
`<grid home>/.grid/station.lock` (the grid home being the root that holds the state store; the
`--state-workspace` flag names the same root)
(JSON: `pid`, `pgid`, `startedAt`, `controlUrl`, `token`); acquired after arming validation,
before sources start; released on the graceful path. Stale detection: pid-liveness probe — dead
holder → steal + LOUD log; live holder → `StationRefusal` naming the pid and the `space status`
attach hint. LOUD when violated, per the guard principle. **Best practice (documented, not
enforced): one grid per machine** — one agentic fabric across the station's assets; spin
containers for multiples. **The ceiling (later, separate passes):** the ADR-0008 D8
`DartEnvironment` governor + leaf permits (designed, D-7-deferred) for capacity, and
leasing-is-core for substation attention-scheduling — this ADR deliberately builds neither; the
lock is the only arbitration a single-machine dogfood needs.

## Supersessions (APPLIED at ratification, 2026-07-19)

Carried from the SCRATCH's §5 ledger; the forward stamps below were applied to their targets
on ratification day — never silent.

- **ADR-0006** — the "live arm requires ≥1 `--bead`" drive-list clause and "Disarming = stop
  `grid run`" get forward stamps: superseded by `up` + store-bless (D-R1/D-R4); `run`
  transitional → retired (RS-8).
- **ADR-0012 (reserved)** — untouched. Explicit note: the control plane is a dedicated surface,
  NOT ADR-0012's exploration transport (D-C1).
- **ADR-0008 D1** — no supersede; this ADR *executes* D1's "one conductor" (cite-only stamp).
- **ADR-0009 D4** — no supersede; the graceful-restart ceiling is explicitly deferred-to
  (cite-only).
- **The Circuit rename** (SCRATCH §6, ruled with Nico 2026-07-02: `Formula` → `Circuit`,
  inflation verb **"energize"**, "electrify" an accepted synonym; persisted/wire keys hold) —
  forward stamps on ADR-0008's Formula vocabulary at ratification. (`Order` → `Demand Response`
  was debated and **NOT decided** — `Order` stays.)

## Non-goals (this pass)

Federation/bus (parked, `m6-federation`); the D8 governor + permits; leasing/scheduling;
zero-downtime graceful restart (detach-all/reattach-all); the AOT exploration transport +
`genesis_consent` (ADR-0012, reserved); any exploration-host or leonard change; control-plane
mutation endpoints (never — D-C4); Windows/systemd; multi-station-per-machine; any engine-core
change.

## Build state (2026-07-19)

The RS ladder (SCRATCH §8) was filed as epic **tg-3s8** + rungs tg-3s8.1–.9 and **RS-1…RS-7b is
fully landed** — 16 beads, all agent-built; the eight-point first proof passed operator-run
2026-07-02 (AOT resident `up`, `status` attach over HTTP, second `up` refused LOUD, in-store
bless picked up live, `kill -9` relaunch through the barrier, clean `down`). **Still pending at
the live gate:** the first LIVE `space up` arm; **RS-8** (retire `run`) — deliberately unfiled
until that proof, because filing it earlier would make it auto-ready under the very resident
station whose scaffold it retires; and this text's ratification. Epic **tg-3s8** remains open
until those close. Also open from the SCRATCH: whether transitional `run` should be
hard-constrained in the interim or just left until RS-8 deletes it.

The surfaces live in `grid_cli` and are exported from `packages/grid_cli/lib/grid_cli.dart`,
**deliberately with no `CommandRunner` registration in the SDK** — the scope fence: the asset
runner composes the verbs (space_station's `space`, RS-5b), so grid_cli ships clients and
Commands, never a binding:

- `packages/grid_cli/lib/src/station_lock.dart` — `StationLockService` / `StationLockRecord` /
  `StationLockHandle` / `StationRefusal` (D-A1; RS-2).
- `packages/grid_cli/lib/src/station_control.dart` — `StationControl` / `StationStatus` /
  `SubstationStatus` (D-C2; RS-4). *The landed surface requires the bearer on `/healthz` too —
  one posture, no unauthenticated liveness probe. **Adopted into D-C2** (Nico, 2026-07-19
  ratification review), where it also underwrites the LAN-bindable posture.*
- `packages/grid_cli/lib/src/station_attach.dart` — `StationAttach` + sealed
  `AttachResult`/`StopResult` (D-C3's client; RS-5a).
- `packages/grid_cli/lib/src/station_reload.dart` + `reload_command.dart` — `StationReload` /
  `ReloadCommand`: the explicit JIT dev-mode hot-reload seat. Postdates the ladder; rides the
  same lock contract; never touches the GET-only HTTP surface and never signals the process —
  consistent with D-R2/D-C3 (it is a VM-service dev tool, not a lifecycle or SIGHUP semantics).

One drift note for ratification: the transitional `run` assembly (`station_runner.dart`)
has since been **deleted** from grid_cli — the boot path moved to the asset's own runner +
`runGrid` — but RS-8's formal filing/close-out is a store question, not settled by this text.
*(The second drift note — `<state-workspace>` vs `<grid-home>` lock-path naming — was resolved
in the 2026-07-19 ratification review: canonical is `<grid home>/.grid/station.lock`, the grid
home being the root that holds the state store; see D-A1's store vocabulary.)*

## Consequences

- One trigger surface system-wide (a bead going ready in the owned store), one supervisor per
  state store, one conductor (ADR-0008 D1, executed). The shell is now supervisable: signals
  are the whole lifecycle, the lock is the whole arbitration, HTTP is observation only.
- The control plane and the debugging surface stay categorically distinct (D-C1) — ADR-0012's
  reserved scope survives residency untouched, and D-C5 records where both eventually re-home.
- The engine is untouched by construction: every fail-closed gate ADR-0006 ratified still holds
  under `up`; what changed is who keeps the process alive and how others reach it.
