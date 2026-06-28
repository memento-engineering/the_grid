# M5 Build-Order — the live coding station: "the grid builds the rest"

> **★ DRAFT — doc-before-code, ratification-pending.** Federation (ADR-0011) is
> PARKED. M5's bet: get the_grid's coding/build loop live enough that **the_grid
> builds the remaining work itself** (the SDK split, butane as a substation, the
> asset packs) instead of us hand-building it. **No code until Nico resolves the
> DECISIONS below.** Decisions made *with* Nico land here as build-order
> requirements (or get promoted to an ADR) — NOT in ADR-0000.

**Date:** 2026-06-28
**Status:** scoping draft, grounded by a 6-way read-only source recon (every claim file-cited).
**Builds on (all ratified/built):** ADR-0006 (dogfood rig + live-write authorization + the ownership gate + land policy), ADR-0007 (the tree engine + crash-safety: freshness barrier, respawn-or-skip), ADR-0008 (the authoring SDK + reentrant engine + the `*_grid_assets` asset model), the M3 runtime (the entire live-seam stack), and the M4-P0/P1 tree engine (offline-green, 141 tests; the WorkPhase path retired 2026-06-28).
**Supersedes nothing.** It sequences the deferred "live arm" + the vNext build backlog into tracks.

---

## ★ DECISIONS RESOLVED (Nico, 2026-06-28) — these govern; the draft recommendations in the body below are reconciled to them

- **D1 — `grid run` BECOMES the tree engine (tree-as-default).** The M2/M3 reducer/dispatcher path retires. **Phased, not a blind delete:** the tree path reuses all of `grid_runtime`; the M2 **convergence reconciler** is a *separate* question (gc still owns `type=convergence`), so the retirement scope is its own design step / ADR touch (executing ADR-0007's supersession). Track 1 is now "tree-as-default", not a `--tree` flag.
- **SDK package name = `grid_sdk`** (NOT `the_grid` — that is the **repo** name). `grid_sdk` is the public authoring surface over the private `grid_engine`. **This REVISES ADR-0008 D1** (which named the public SDK `the_grid`) — it needs a one-line forward-pointer stamp on ADR-0008 D1 from Nico (never silently edited here).
- **Stations: The Studio (`studio.local`) + The Dashboard (`dashboard.local`)** are the two federation peers (federation parked). **This machine is The Studio** — the coding/builder station; The Dashboard is the peer (the testing/observability/burn side).
- **CODERS BEFORE BURNS** — the M5 focus is the coding-agent infra in THIS repo (Track 1–3 + the coding half of Track 4). **butane-as-substation + the Burn (Track 4b — the "testing agents" half) are DEFERRED** until the coders work.
- **We build by hand until the station builds itself.** "the grid builds itself" is the destination; the coding-station infra (tree-as-default, the `grid_sdk` split) is bootstrapped by us first (D4 = we build the structural infra; the_grid dogfoods on coding work once live).
- **D2 — the `grid step --advance` shim is DEFERRED** (rely on the process-exit cursor write); revisit only if a live arm shows lost exits.

---

## The north star

> **Apps are built in Flutter. Lenny debugs the apps. Lenny files bugs into the grid. The grid builds everything.** (the org bet)

M5 makes the "**the grid builds everything**" clause real for the first time on the M4 tree engine: a live `grid run --tree` that, given an owned backlog, spawns a coding agent per ready bead through the reentrant `code` formula, supervises it, advances the per-node cursor on completion, and closes the session — local-first, nothing pushed. Then we **feed it its own roadmap** as beads.

The dependency arc M5 closes:

```
the tree engine (M4, offline-green)
   └─ + the M3 live-seam stack (controller/provider/git/chokepoint/root/state-store/arming)
        └─ runGridTree()  ······· Track 1 (the ONLY missing wiring — the unlock)
             └─ first LIVE arm ··· Track 3 (the human gate)
                  └─ the_grid builds: SDK split · butane substation · asset packs ··· Track 4
```

---

## Current state (the recon, file-cited)

**What already exists (the live arm is ~90% built):**
- The tree-engine composition — `composeRunTree` (pure, offline) + `TreeRunWiring` (kernel + restart reconciler): `run_tree_command.dart:26-149`. The `RuntimeSnapshotSource` adapter (`GridControllerRuntime → SnapshotSource`): `runtime_snapshot_source.dart:15-26`.
- The **entire M3 live-seam stack**, reusable verbatim: `runGrid` (the live orchestrator pattern, `run_command.dart:488-719`), `GridRuntimeFactory` (M1 controller), `SubprocessProvider`, `StationGitService` (registerRootCheckout/listBeadWorktrees/reap + `GhPrOpener`, `run_command.dart:460`), the `StationBeadWriter` chokepoint (`run_command.dart:329`), `SystemProcessGroupController` (`process_group.dart:114-142`).
- The **safety rails**, all ratified + built (ADR-0006): `--dry-run` SAFE DEFAULT + `--no-dry-run`+`--root` arming gate (reject non-dry w/o root, exit 64); `BeadOwnershipPredicate` fail-closed; the `AgentEnvAllowlist` (token via env, never argv, `includeParentEnvironment:false`); `--bead` blessed drive-list; `--state-workspace`/`--state-substation` split store (A36/A37 — the work source stays read-only); the agent config (full-bead prompt, pre-granted perms, local-first/no-push working agreement).
- The engine's **durable-completion**: the `CapabilityHost` advances the cursor from the agent's observed process `Exited(0)` itself (`interpretEvent → complete → chokepoint write`) — so the process-exit path already drives progress.
- **butane_flutter EXISTS**: `/Users/nico/development/com.nicospencer/butane_flutter` — a Flutter repo, currently a **gascity** rig (`.beads` + `.gascity-pack/pack.toml`).

**The gaps (what M5 builds):**
1. **No `runGridTree()` + no `grid run --tree` command.** `composeRunTree` is only ever called from offline tests; nothing wires it to the live M3 seams (a live work+state `RuntimeSnapshotSource`, a live `EffectContext`, a freshness barrier, `SubstationConfig`s from flags, the CLI command + arming). This is the unlock — and it is small (it mirrors `runGrid`).
2. **No `grid step --advance` shim** (a belt-and-suspenders durable-completion fallback for *detached* spawns whose exit is lost — the M3 oneTurn-vanish lesson). Not on the critical path if the exit is observed.
3. **The vNext build backlog is unbuilt**: the SDK split (`the_grid` over private `grid_engine`, ADR-0008 D1), butane wired as a the_grid substation + `butane_grid_assets` (the Burn), and the asset model (`station_grid_assets` generalizing the hand-compiled `code` extension; TOML `PackInflater` deferred).

---

## Tracks (dependency-ordered)

### Track 1 — `grid run --tree` goes live (the unlock; **we** build)
Build `runGridTree()` mirroring `runGrid` (`run_command.dart:488-719`): discover the workspace → build the M1 controller (`GridRuntimeFactory`) for work + a second for the state store → wrap each in `RuntimeSnapshotSource` (the work axis + the state axis) → build a **live `EffectContext`** (`SubprocessProvider`, the `StationBeadWriter` over the split state store, `gitOps`/`prOpener` from `StationGitService`/`GhPrOpener`, `worktreeRoot` from the registered `RootCheckout`) → build `SubstationConfig`s from the allow-set → build the **freshness barrier** (one completed re-query of both runtimes — ADR-0007 D4) → `composeRunTree` → `TreeRunWiring.start()`. Reuse M3's arming gate verbatim (`--dry-run` default, `--no-dry-run`+`--root`, `--state-workspace` required for a live run, `--bead` drive-list, the shared allow-set).
**Acceptance:** `grid run --tree --dry-run` composes + observes (zero writes, zero spawns); an offline live-wiring composition test (fakes) proves the seam shape, alongside the existing `run_command_tree_test.dart`. `melos analyze` clean.

### Track 2 — durable completion (defer-able)
The cursor already advances from the observed `Exited(0)`. The `grid step --advance` shim (a `grid step` subcommand reading `GRID_SESSION_ID`/`GRID_STEP_PATH` + the workspace, writing `nodeStateMetadata(stepPath, complete)` through the chokepoint) is the **fallback for detached spawns** whose exit is lost. **Build only if Track 3 shows lost exits.**
**Acceptance (if built):** an agent in a worktree with `GRID_*` env runs `grid step --advance` → the chokepoint records `grid.cursor.{path}.state=complete` on the owned session bead; fail-closed if not owned.

### Track 3 — the first LIVE arm (**the human gate** — Nico present)
`grid run --tree --no-dry-run --root … --state-workspace … --bead …` against a **small owned backlog**, split state store (`tgdog`), local-first/no-push. Prove one real bead builds end-to-end via the tree engine: mint session → spawn `claude` → it commits on the throwaway branch → the cursor advances on exit → the session closes. Inspect the commit; nothing pushed.
**Acceptance:** a real session bead in `tgdog` shows the full cursor progression; a real commit exists in the per-bead worktree; the foreign/owned work source is untouched (A37); zero pushes.

### Track 4 — the_grid builds the rest (the dogfood backlog)
Once Track 3 holds, file beads and drive them. The candidate backlog (DECISION 4 — who builds which):
- **(a) the SDK split** — `the_grid` public package over private `grid_engine` (ADR-0008 D1): move `lib/src/sdk/` + `capability.dart` into `the_grid`; mark the kernel/seeds/formula-internals engine-private; split `grid_cli` imports.
- **(b) butane as a substation** — wire `butane_flutter` (the existing gc-managed Flutter repo) as a the_grid substation (an owned prefix + a read-only side-car'd work source, exactly the genesis arm shape) + author `butane_grid_assets` (the Burn formula + Harness/Coordinator/Report capabilities).
- **(c) the asset model** — `station_grid_assets` generalizing the hand-compiled `code` extension (`code_capabilities.dart`) into a composable Dart-package asset that exports a registry builder; the TOML `PackInflater` stays deferred.
**Acceptance:** per-bead — the_grid builds it, the offline suite for the touched package is green, `melos analyze` clean; a human reviews the local commit before any land.

---

## DECISIONS NEEDED (Nico) — gate the build

1. **Command surface.** `grid run --tree` (a flag on `run`), `grid tree run` (a subcommand), or **make the tree engine the default `grid run`** and retire the M2/M3 dispatch path? *(Recommend: a `--tree` flag now so both run side-by-side during transition; promote tree-to-default once the live arm proves out and the M2/M3 dispatcher is provably redundant.)*
2. **Step-advance shim (Track 2).** Defer (rely on the process-exit cursor write for arm #1) or build it minimal now? *(Recommend: defer; revisit only if Track 3 shows detached spawns losing their exit.)*
3. **Arm #1 target (Track 3).** Which owned backlog does the_grid build first — genesis again (the proven arm #1 shape), a fresh throwaway owned rig, or straight to butane? And which beads get blessed? *(Recommend: 1-2 beads on a small owned rig or genesis — a low-stakes prove-out, NOT the_grid's own package surgery.)*
4. **Who builds the SDK split — the_grid or us?** The split is delicate self-surgery (moving the_grid's own package surface) — risky to hand to a spawned agent on an early arm; the **headline dogfood is better proven on butane feature work + the Burn**, not on the_grid refactoring itself. *(Recommend: WE do the SDK split + the first asset extraction by hand; the_grid dogfoods on butane/feature work.)*
5. **butane substation.** The `substationId` string (`butane`?); where `butane_grid_assets` lives (the_grid `packages/` vs a sibling in `com.nicospencer` next to `butane_flutter`); and how `butane_flutter` (currently a **gascity** rig — gc may still own it) coexists as a read-only the_grid work source. *(Recommend: `substationId: 'butane'`; `butane_grid_assets` as a sibling alongside `butane_flutter`; treat `butane_flutter`'s `.beads` as a read-only side-car'd work source like genesis — never written by the_grid; confirm gc isn't actively reconciling it.)*
6. **First asset shape.** Is the first asset a plain Dart package exporting a registry builder (no TOML), or do we build the TOML `PackInflater` now? *(Recommend: Dart-package asset first; TOML `PackInflater` deferred to when a non-Dart author needs it.)*
7. **Milestone doc home.** Is this M5? Does it need its own PDR, or do this build-order + ADR-0006/0007/0008 suffice? *(Recommend: this build-order + the ratified ADRs suffice; a decision above only needs an ADR if it changes a ratified shape — e.g. tree-as-default `grid run`.)*

---

## Safety rails (unchanged — reused from M3 / ADR-0006)
`--dry-run` is the safe default; a live run requires `--no-dry-run` + `--root` + `--state-workspace`. The chokepoint is the sole writer, fail-closed on the shared allow-set; the work source is read-only (A37); the agent token rides the env allowlist (never argv); spawns are local-first (commit on a throwaway branch, **no push, no PR** — land is a deliberate human follow-up). The first live arm is the human gate. Deferred and **non-blocking**: adopt-a-live-process, `restForOne` transitive re-keying, the swift-infer backend shim, automatic land→PR.
