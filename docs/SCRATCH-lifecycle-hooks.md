# SCRATCH — the lifecycle-hooks system (deterministic dispatch · asset contributions · the git surface)

**Status: DESIGN — decision-complete (design session with Nico, 2026-07-18); awaiting
ratification.** Graduation target: **one new ADR** (the harness lifecycle-hook seam — **number
assigned by Nico 2026-07-19 (D-P7): ADR-0015**; the self-claimed 0014 went to the residency
ADR, which graduates first), cross-referencing **power_station ADR-0001**
(packaged-AI-asset skill↔command coupling — the contribution/command coupling this generalizes).
Build: **grid agents, per fully-briefed beads (§8) — not hand-written.** Beads are drafted only
after ratification and filed **deferred** (the intake convention: Nico's bless flips them open).

This doc rests on, and does not re-open, three **already-ratified** control-plane rulings in
`SCRATCH-resident-station.md`: **D-C1** (the control plane is NOT perception/exploration — that
would be a category error), **D-C4** (no mutation endpoints, by construction — the control plane
cannot be a trigger), and **D-C5** (RS-4 is a *floor*, re-homed onto a unified substrate later).
Every transport decision below is a consequence of those, not a revision of them.

---

## 0. The theme, precisely

The opening ask was narrow: "a dart asset that guarantees `dart format` ran before a commit."
It expands, because **"before a commit" names three different commit-actors in this org, and only
one is a human:**

1. **The station's build agents** — the *primary* code producers. They commit inside per-bead
   worktrees and open PRs; nothing in that path runs `dart format`/`analyze` today.
2. **Humans in a checkout** — the governor seat; anyone editing a substation directly.
3. **Claude Code agents** editing files in any seat.

The naive fix (a `dart format` git pre-commit hook) is the *worst* fit: git hooks in these repos
are owned by beads (`core.hooksPath = <root>/.beads/hooks`, a redline — never touch), and CI —
the only actor-agnostic backstop — was rejected by Nico (a bounce-to-clean roundtrip is expensive,
and CI auto-committing whitespace is ugly). So the enforcement belongs at **commit time, in the
worktree**, where the fix folds into the agent's own commit.

Generalizing from that: **space is a harness of harnesses, and a harness earns the name partly by
exposing lifecycle hooks** (Claude Code has `SessionStart`/`PreToolUse`; git has `pre-commit`; CI
has stages). So the deliverable is not "a format hook" — it is **the harness's lifecycle-hook
seam**, of which git events are one producer family. `dart format` on `pre-commit` is its first
vertical slice.

**Explicitly unchanged:** the committee/`Circuit` (the *graded* gating pipeline stays first-class —
hooks are the *lightweight, deterministic, cross-cutting* seam, never a second committee); RS-4's
read-only invariant; `ext.exploration` (the JIT debug surface); the `.beads/hooks` files (chained,
never edited); bd-CLI-only mutation.

## 1. Ground truth (scouted 2026-07-18, file:line; all repos at the umbrella checkout)

### 1a. Commit/hook firing in a station worktree — hooks DO fire; the active dir is the beads redline

| Fact | Where |
|---|---|
| `GitOps.commitAll` = `git add -A` then `git commit -m` — **no `--no-verify`, no `-c core.hooksPath=`** | `grid_runtime/lib/src/git/git_ops.dart:308-315` |
| `pushSetUpstream` = `git push -u` — also no `--no-verify` (so `pre-push` is live too) | `git_ops.dart:319-325` |
| `SystemGitRunner.run` cleans env (`includeParentEnvironment:false`); the `gitEnvBlacklist` strips `GIT_DIR`/`GIT_WORK_TREE`/… — **only fixes repo targeting, does NOT disable hooks** | `git_runner.dart:110-143`, blacklist `:70-86` |
| Build agent commits **directly** ("COMMIT your work", "Your ONE deliverable is the COMMIT"); its env (`AgentEnvAllowlist`) forwards no `GIT_*` and is **not** hook-neutralized | brief `grid_assets/lib/src/code/code_capabilities.dart:441,482`; env `grid_runtime/lib/src/runtime/subprocess_provider.dart:210-223`, `env_allowlist.dart:37-104` |
| `core.hooksPath` is stored **ABSOLUTE** = `<root>/.beads/hooks`; worktrees share `$GIT_COMMON_DIR/config`; `extensions.worktreeConfig` **unset** ⇒ a commit in `<root>/.grid/worktrees/…` resolves hooks to the parent's `.beads/hooks` and **fires them** | live `.git/config` (power_station), `git worktree` probe |
| ⇒ A hook at `<worktree>/.git/hooks/` **NEVER runs** (git consults only the absolute `.beads/hooks`) | derived from the above |
| The beads hook is one managed block (`# --- BEGIN BEADS INTEGRATION v1.0.5 ---`) running `bd hooks run <event>`; **no chaining, no `hooks.d/` drop-in**. Exit **3/124/142 swallowed → 0**; any other non-zero **aborts** | `<root>/.beads/hooks/pre-commit:1-33` |
| `WorktreeLayout`: `<root>/.grid/worktrees/<substation>/<beadId>`, branch `grid/<beadId>`, reversible (`beadIdFromName`) | `grid_runtime/lib/src/git/station_git_service.dart:152-180` |
| `provisionWorktree` sets **no** per-worktree git config today | `station_git_service.dart:312-355` |

### 1b. Beads hooksPath management — set-once; a redirect survives

| Fact | Where |
|---|---|
| `bd init` runs from the seeder, **guarded to skip existing stores** | `grid_sdk/lib/src/stores/substation_init.dart:15-16,22-39` |
| No Dart code anywhere writes `core.hooksPath` (repo-wide grep clean) | — |
| **Empirical set-once:** genesis and lenny sit redirected on `.git/hooks` despite having populated `.beads/hooks`; beads did not force them back ⇒ `bd init` sets hooksPath once and does not re-assert | live `.git/config` (genesis, lenny) |
| **The one guard:** a *re-run* of `bd init` in a store would re-point hooksPath back to `.beads/hooks` | inference from the seeder |

### 1c. The station control channel — RS-4 exists, is AOT-safe, and is read-only by construction

| Fact | Where |
|---|---|
| `StationControl` binds a plain `dart:io` loopback server: `HttpServer.bind(loopbackIPv4, port)` — **no `dart:developer`**, bound **unconditionally** at `up` (vs the VM-service host, gated JIT-only) | `grid_cli/lib/src/station_control.dart:202`; `space_station/lib/src/up_command.dart:483-496` |
| Surface = GET-only, two routes (`/healthz`, `/status`); bearer checked **before** routing; **no mutation, by construction (D-C4)** | `station_control.dart:168-176,213-223,154-166` |
| Token = 32 secure-random bytes, lives ONLY in the 0600 `station.lock` (never argv/env) | `mintControlToken()` `station_control.dart:137-142` |
| `station.lock` `StationLockRecord` carries `controlUrl` + `token` + `vmServiceUri`; path `<stateWorkspaceDir>/.grid/station.lock` | `grid_cli/lib/src/station_lock.dart:57-136,155-156` |
| A finished out-of-process client already speaks bearer HTTP to it (`space status` rides it) | `StationAttach.status()` `grid_cli/lib/src/station_attach.dart:195-217` |
| `controlPort` defaults to `0` (ephemeral) | `space_delegate.dart:319`, parsed `up_command.dart:505/485` |
| Mutation-capable loopback-HTTP precedent (Bearer + fencing tokens) — **not** what we use, but the house pattern if a mutation surface were ever wanted | `federated_grid_assets/lib/src/station_server.dart:103` |
| ADR-0012 D1 already extends RS-4 with read-only `GET /sessions` + `WS /stream` — precedent for adding read-only routes | ADR-0012 (cockpit) |

### 1d. The in-process lifecycle-event seam (for the drive-loop producer)

| Fact | Where |
|---|---|
| `GridControllerRuntime.events` = `Stream<GraphEvent>` (per store) | `beads_dart/lib/src/reactivity/grid_controller_runtime.dart:54-55` |
| `GraphEvent` sealed set: `BeadCreated`/`BeadUpdated{changedFields}`/`BeadClosed`/`BeadReopened`/`BeadDeleted`/`Dependency*`/`ReadySetChanged`/`SnapshotInitialized` | `beads_dart/lib/src/diff/graph_event.dart:19-55` |
| The JIT exploration host already taps exactly this stream (routes it to `postEvent`, JIT-only) — the AOT producer subscribes to the **same** stream, routes elsewhere | `grid_exploration/lib/src/grid_exploration_host.dart:158-161` |
| Runtimes owned by `StationWorkRuntime`; `.events` is currently **unclaimed in-process** (join bridge is the lone `.snapshots` subscriber, A39) | `grid_sdk/lib/src/work/work_assembly.dart:347,551-559` |
| Session open/gated/closed are **bd store writes** (no `onSessionClosed` callback) ⇒ lifecycle events are *derived* from `GraphEvent`s | `grid_engine/lib/src/circuit/session_scope.dart:566,637,817,885` |

### 1e. Worktree → substation → assets is derivable (no stored map needed)

| Fact | Where |
|---|---|
| Substation roots (name, **resolved absolute** root, prefix) held as `InheritedSeed<SubstationScope>` | `grid_sdk/lib/src/composition/composition.dart:197-204`; scope `scopes.dart:73-76` |
| Prefix-match gate (symlink-canonicalized) already exists | `isStrictlyUnderDir` `station_git_service.dart:191-208` |
| Live worktree enumeration | `listBeadWorktrees()` `station_git_service.dart:362-382` |
| Per-substation assets enumerable via the `CapabilityRegistry` / the `extension/mcp/config.yaml` manifest | `code_capabilities.dart:647-716`, `station_work.dart:18-72` |
| Contribution declaration would join the existing manifest kinds (rubrics/prompts/skills/resources) | `grid_assets/extension/mcp/config.yaml` |

**Net:** the only net-new abstraction is **git-event → contribution** (§2). Everything it stands on
— control channel, event stream, worktree math, asset enumeration — already exists.

## 2. The seam (D-H1…D-H5)

**D-H1 — hooks are a deterministic lifecycle-dispatch seam, not a second committee.** A hook fires
a **command**; it never renders a judgment that needs grading. The `Circuit`/committee stays the
first-class *graded* pipeline (rubrics, critics, escalation). Bright line: *"a pre-commit `dart
format` is a hook; 'does this diff meet the code-validation rubric' is a committee lane."* Blurring
them reinvents the committee badly.

**D-H2 — the event taxonomy is grouped by producer.** (Representative, not exhaustive; the full set
is a §6 open item.)
- **git** (fired by the core hook shim in a worktree): `git.pre-commit`, `git.pre-push`,
  `git.commit-msg`, `git.post-checkout`, `git.post-merge`, `git.prepare-commit-msg`.
- **drive-loop** (fired in-process as a bead advances the circuit): `session.opened`,
  `agent.completed`, `committee.gated`, `land.pre`, `land.post`, `pr.opened`, `session.closed` —
  each **derived from a `GraphEvent`** (§1d): `session.closed` ⇐ `BeadClosed`, `committee.gated` ⇐
  gate-bead write, `pr.opened`/`land.post` ⇐ `BeadUpdated{changedFields}`. Beads-native (resonates
  with the tg-pm6 "beads all the way down" track).
- **station**: `station.up`, `station.down`, `substation.provisioned`, `worktree.provisioned`.

**D-H3 — the contribution shape is a pure run-spec: `{ event, run, select, mode, timeout }`.**
Declared by an asset in its `extension/mcp/config.yaml` (a `hooks:` block — the same muscle as
`skills:`/`rubrics:`). `run` is a shell command; `select` a file selector (e.g. `staged:*.dart`);
`timeout` a hard cap. Modes:
- **`fix`** — mutate, re-stage, continue (fail only on tool error). `dart format` is `fix`.
- **`gate`** — non-zero **aborts** the operation (e.g. `dart analyze`).
- **`notify`** — fire-and-forget side effect ("on `pr.opened`, ping X"); never blocks.

**D-H4 — NO inference in the hook path, ever (Nico, explicit).** A contribution is a deterministic
command, never an LLM prompt. Rationale: a model round-trip on *every commit* is latency + cost +
the exact "same input → different output" nondeterminism that power_station ADR-0001 exists to kill
("lookup → command; judgment → the agentic half"). If a hook point ever wants agentic behavior, the
contribution's `run` *spawns* an agent as a subprocess (`claude -p …`, or a first-class future
`kind: agent` contribution that reuses the station's existing agent runtime — model-tier ladder,
env allowlist, worktree) — the dispatcher stays a deterministic command-runner; whether a `run`
shells out to a model is the *asset's* private choice, opaque to the hook system.

**D-H5 — the resolver is the shared brain; producers differ only in where execution happens.** One
station-side resolver maps `(event, context) → [contribution]` — it is the only thing that knows
the live roster and mounting. **Execution follows the producer's locus:** git contributions execute
in the *shim* (the files are in the worktree; only the shim has the staged index); drive-loop
contributions execute *in-process* on the station (it is already there). Same resolve, two execution
sites.

## 3. Transport & execution (D-T1…D-T3)

**D-T1 — git resolve rides RS-4 as a read-only GET; `ext.exploration` is never used.** A new
`GET /hooks?event=<e>&worktree=<abs>` on `StationControl` returns the resolved contribution list
(bearer-auth off the 0600 lock, exactly like `/status`). This is a **pure read** — it resolves,
it does not act — so **D-C4 holds** (the trigger is git, not the control plane), and it sits in the
same read-only-GET grain ADR-0012's cockpit already established. Because RS-4 is plain `dart:io`,
this works identically under JIT and AOT — the whole reason we are off the VM-service debug channel
(D-C1). Payload (illustrative):

```json
{ "event": "pre-commit", "worktree": "…/the_grid/.grid/worktrees/tg/tg-abc",
  "substation": "the_grid",
  "contributions": [
    { "id": "dart-fmt", "source": "dart_grid_assets",
      "run": "dart format", "select": "staged:*.dart",
      "mode": "fix", "timeout_ms": 30000 } ] }
```

**D-T2 — drive-loop events ride the in-process `GraphEvent` stream, no HTTP.** An AOT-safe
dispatcher subscribes to each store's `GridControllerRuntime.events` (§1d — the same stream the JIT
host taps, currently unclaimed in-process), maps `GraphEvent → lifecycle event`, resolves
contributions, and runs them in-process (a `notify` webhook, a `gate` that can veto an advance).

**D-T3 — degradation is clean.** No resident (dev-mode) station up ⇒ the git shim's GET fails and it
**no-ops** — the core hook has *already* run the beads hook (D-G2), so commits still work and beads
still fires; only the grid contributions are skipped. Drive-loop producers simply don't exist when
the station is down. Nico: calling these without an up station is atypical; resident-only is the
right constraint for now, not a limitation.

## 4. The git surface (D-G1…D-G3)

**D-G1 — redirect `core.hooksPath` to a grid-owned dir; never touch `.beads/hooks`.** Because the
active hooks dir is the absolute `.beads/hooks` (a redline) and beads offers no drop-in (§1a),
the station points each substation's `core.hooksPath` at `<root>/.grid/hooks` and installs static,
generic per-event core hooks there. The per-worktree specialization lives entirely in the resolver
at runtime — **there are no per-worktree hook files** (per-worktree baking was considered and
rejected as unmanageable). Install is once-per-substation (an operator command, folded into
`assets install`, and/or at `space up`), not per-worktree.

**D-G2 — each core hook CHAINS the beads hook, then calls our command.** Order: `exec` the existing
`<root>/.beads/hooks/<event>` first (preserving its exit-code contract from §1a — 3/124/142
swallowed, other non-zero aborts), then `space hook run <event>`. Invoking beads' hook is not
"touching" it; today's behavior is preserved exactly and formatting is purely additive.

**D-G3 — re-assert the redirect after any `bd init`.** The one fragility (§1b): a `bd init` re-run
snaps hooksPath back to `.beads/hooks`. The seeder already runs `bd init` for fresh substations
(and skips existing), so the fix is cheap and idempotent: re-assert `core.hooksPath = <root>/.grid/
hooks` right after any init / at `space up`. (Not source-confirmed against the `bd` Go binary, which
is not vendored — treat as a guard, not a proven trigger.)

## 5. First vertical slice (D-V1)

**D-V1 — `dart format` on `git.pre-commit`, `mode: fix`, owned by `dart_grid_assets`.** It exercises
the whole spine end-to-end: the git producer, the `fix` mode (reformat staged `.dart` → re-stage →
continue), the RS-4 read-only resolver, worktree→substation resolution, and the beads chain. Prove
the spine with one real contribution; the rest of the taxonomy is then just more producers and more
declarations. `space hook run` is the thin client (mirrors `ReloadCommand` structurally, but reads
`controlUrl` not `vmServiceUri`): read lock → GET `/hooks` → execute `fix`/`gate`/`notify` locally →
map to an exit code (0 proceed / non-zero abort).

## 6. Open questions — RESERVED, not decided here

1. **The full event taxonomy** — which drive-loop and station events are load-bearing enough to
   emit in v1 vs reserved. D-V1 needs only `git.pre-commit`.
2. **`select` grammar** — the selector vocabulary (`staged:*.dart`, `changed:`, `all:`) and whether
   the shim or the resolver owns glob expansion (leaning shim — only it has the index).
3. **Ordering & conflicts** — when multiple assets contribute to one event, the run order and
   whether a `gate` short-circuits later `fix`es.
4. **First-class `kind: agent` contribution** — whether an agentic contribution ever becomes a
   first-class kind (reusing the agent runtime) vs. always a `run` that spawns a subprocess (D-H4).
5. **Human-checkout coverage** — this design covers worktrees (the station's producers). Humans
   committing in a main checkout still hit `.beads/hooks` directly; whether/how to extend the same
   redirect to a main checkout is deferred (Nico rejected CI; the resident-only constraint means a
   human commit with no station up would no-op anyway).
6. **RS-4 → unified surfaces (D-C5)** — `GET /hooks` is built as another *floor* route; it re-homes
   behind the unified-surfaces substrate with no rework if that lands.

## 7. Relationship to existing decisions

- **`SCRATCH-resident-station.md` D-C1/D-C4/D-C5** — the control-plane rulings this obeys: not
  perception (D-C1), no mutation/trigger endpoints (D-C4 ⇒ the resolver is read-only by *mandate*),
  RS-4 as a floor (D-C5).
- **ADR-0012 D1 (cockpit)** — precedent for extending RS-4 with read-only routes; `GET /hooks` is
  the same grain.
- **power_station ADR-0001 (skill↔command coupling)** — the contribution/command coupling
  generalized from skills to git/lifecycle events; "lookup → command; judgment → agentic" is D-H4.
- **`SCRATCH-third-party-harnesses.md`** — the "harness of harnesses" framing; hooks are the
  lifecycle seam a harness exposes. (Distinct from the parked `GridHarness`/own-agent epic.)
- **tg-pm6 "beads all the way down" (`DESIGN-tg-pm6.md`)** — drive-loop events derive from
  `GraphEvent`s; lifecycle is bead-shaped.
- **the_grid ADR-0000 (register)** — this design was reached **collaboratively with Nico**, so it is
  **not** a pending autonomous amendment; it graduates to its own ADR at Nico's ratification.
- **`.beads/hooks` redline (CLAUDE.md)** — chained (invoked), never edited; hooksPath redirected
  around it.

## 8. Bead backlog (drafted; FILE DEFERRED until ratification)

Not filed (Nico's standing instruction this session + the intake convention). On ratification, file
**deferred**; Nico's bless flips them open. Homing keeps coupled work in one store where possible;
the epic lives in **the_grid** (it owns the primitive), the format contribution in **power_station**.

- **Epic (the_grid): "lifecycle-hook dispatch seam."** The resolver + the git producer spine + the
  drive-loop producer.
  - **the_grid: "`GET /hooks` resolver on `StationControl`."** Read-only route; bearer; resolves
    `(event, worktree) → [contribution]` via `SubstationScope` prefix-match + manifest enumeration.
  - **the_grid: "core git-hook install + hooksPath redirect + beads chain."** `<root>/.grid/hooks`,
    static per-event hooks, chain `.beads/hooks/<event>`, gitignored; wire into `provisionWorktree`
    / `assets install`.
  - **the_grid: "re-assert hooksPath redirect after `bd init`."** Idempotent guard in the seeder /
    at `space up` (D-G3).
  - **the_grid: "`space hook run <event>` client + local executor."** Mirrors `ReloadCommand`; reads
    `controlUrl`; executes `fix`/`gate`/`notify`; maps to exit code.
  - **the_grid: "drive-loop event producer over `GridControllerRuntime.events`."** `GraphEvent →
    lifecycle event` mapping + in-process dispatch. (May land after D-V1.)
- **power_station: "`hooks:` manifest block + resolver-side enumeration."** The contribution schema
  in `extension/mcp/config.yaml`; loader support.
- **power_station: "`dart_grid_assets` `pre-commit` format contribution."** The D-V1 slice.

Every driveable bead gets a `validation_plan` (space_station beads use the absolute-cd plan; the_grid
/ power_station beads use the relative `cd packages/<pkg> && dart pub get && dart analyze && dart
test` plan) at refinement, before any bless.
