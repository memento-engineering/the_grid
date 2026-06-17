# the_grid

A Dart-native reactive orchestrator that will replace Gas City (`gc`). The long bet:
**apps are built in Flutter, Lenny debugs apps, Lenny files bugs into the grid — the grid
builds everything.**

## Read first, in order

1. `docs/PDR.md` — vision, goals, milestones, acceptance criteria, constraints, **the gate (§9)**
2. `docs/adr/ADR-0000-ai-decision-register.md` — **process-critical, see below**
3. `docs/adr/ADR-0001…0004` — ratified technical decisions (foundations, packages/projections, reconciler, runtime/tmux)
4. `docs/M1-BUILD-ORDER.md` — M1 dependency-ordered work breakdown (**M1 done — see below**)
5. `docs/M2-BUILD-ORDER.md` — M2 (reconciler) orchestration spine, maps ADR-0003 → tracks (**M2 done, merged**)
6. `docs/M3-BUILD-ORDER.md` — M3 (runtime) dependency-ordered tracks + the Friday dogfood loop (**discovery drafted 2026-06-15, pending ratification**)
7. `docs/adr/ADR-0006-dogfood-rig-and-live-write-authorization.md` — **Proposed**: M3 live-write authorization + bead-shaped ownership gate + land policy
8. `docs/M4-SCOPING.md` — usage-driven M4 decomposition + fs adoption ladder (proposal, ADR-0000 A6)
9. The `predictable-flutter` skill (installed at `.claude/skills/predictable-flutter/`) — the architecture all code follows

**M1 shipped (2026-06-11):** the reactive kernel is built, tested (183 offline + 5 integration green), and committed on branch `m1-reactive-kernel` (packages `grid_controller`/`grid_exploration`/`grid_cli`/`grid_devtools`). `grid demo` proves it. ADR-0000 A8–A14 record the en-route AI decisions (pending Nico).

**M2 built (2026-06-13) — pending ratification:** the convergence reconciler is built, tested (771 offline + 49 integration green), and committed on branch `m2-reconciler` (new pkg `grid_reconciler`). All spine tracks done — `0→A→{B,D,F}→{C,E}→G→H` (domain+codec, reducer, gates, ready-work SQL, recovery, actuator, runtime+shadow, conformance). DoD `docs/M2-BUILD-ORDER.md` §"Definition of done": 1✅2✅3✅4◐(codec fidelity + shadow *mechanism* now validated offline vs REAL gc bytes — A29; live-traffic diff half = M3 dogfood)5✅6✅. **ADR-0000 A15–A29 RATIFIED (Nico, 2026-06-14)** and promoted into their home docs — A15/A16 → ADR-0003 D4, A19 → D2, A24 → D5, A17 → ADR-0002 D2, A22/A23/A25/A26/A27 → ADR-0003 **Decision 8**, A18 → 31-key schema, A20/A21 → ADR-0001 D4/D5, A28/A29 → DoD criteria 1/4. **A30/A31 record the genesis relationship** (re-evaluation of all ADRs vs `engineering.memento/genesis`): adopt nothing into the engine — the_grid is a genesis consumer only at the surface/render layer, deferred to a future **ADR-0005** + TUI-inspector spike (**M3**). Track I codec-fidelity half **done** (A29; pinned `fixtures/upstream/2026-06-11-bd-1.0.5/convergence/`). **M2 merged to `main` (2026-06-15)**; `m2-reconciler` pushed; now on branch `m3-runtime`. Carried to M3: a **recovery actuator** (A27, Track 4b), the **Track I live-shadow** run, and **genesis adoption** (A31, future ADR-0005). **Side-finding for Nico:** a plaintext `CLAUDE_CODE_OAUTH_TOKEN` is visible on the live gascity control-dispatcher's process argv.

**M3 discovery drafted + ADR-0006 RATIFIED (Nico, 2026-06-15):** `docs/M3-BUILD-ORDER.md` (runtime tracks + the Friday dogfood loop) and **ADR-0006** (dogfood rig + live-write authorization + ownership gate + land policy) are written and **ADR-0006 is Accepted**. **A32** (bead-shaped ownership predicate + shared rig allow-set + single bd write chokepoint — M2's `OwnsRigs(Convergence)` is structurally uncallable on a ready work `Bead`) and **A33** (`plugins`→`extensions` exploration wire-key rename so a stock leonard attaches to the_grid's Dart VM) are **ratified**; **A34** (tmux → **`genesis_tmux`**, a zero-dep genesis package consumed as a path dep; handoff at `genesis/packages/tmux/HANDOFF.md`) and **A35** (ratified dogfood inputs) recorded. **Ratified inputs:** rig `tgdog`; root checkout `engineering.memento/lenny-tgdog` (explicit registration); agent token via operator env + allowlist (`includeParentEnvironment:false`, never argv); pre-granted agent perms; leonard `--extensions grid`. **The dogfood goal: by Fri 2026-06-19, the_grid BUILDS lenny (spawns Claude Code agents per ready bead) and leonard DEBUGS the_grid's pure-Dart VM directly via `ext.exploration.*`.** **M3 build DELIVERED to the live-arm threshold (2026-06-15)** — Tracks 2–7 built across the new `grid_runtime` pkg (+ `grid_cli` `grid run`); **951 offline tests green, 0 failures, `melos analyze` clean** across all 6 packages; nothing live touched (fakes + temp repos + `sh` stubs + `grid run --dry-run`). Uncommitted on branch `m3-runtime` (27 paths). Off the Friday path: Track 1 tmux = **`genesis_tmux`** (handoff staged, build not started), Track 4b recovery actuator (deferred). **The one human gate held for Nico: the first LIVE arm** — creating the `lenny-tgdog` clone + the first real bd writes beside the running gc + spawning agents that open lenny PRs — **and blessing the 2 specific lenny work beads** (deferred to that gate).

**M3 LIVE ARM PROVEN (2026-06-17) — the_grid BUILT genesis, autonomously.** Nico re-targeted arm #1 from lenny to the **genesis** backlog (A36): thinner, owned (embedded `genesis` DB, no gc nearby), and the two real beads bootstrap the_grid's own M4 substrate. The live arm ran and **the_grid spawned coding agents per ready bead that built both features** — `feat(tree): MultiChildSeed/MultiChildBranch` (genesis-7r9) + `feat(tree)!: first-class Key type` (genesis-q8h) — committed local-first into per-bead worktrees off a `genesis-grid` clone, **genesis never written to**. Session/lifecycle beads go to a **separate the_grid-owned `tgdog` state DB** (A37 = the resolved "session beads where?" sub-decision; genesis stays a pristine work source — it can't even adopt the_grid's `session` type). `grid run` grew `--workspace` (read a side-car'd repo), `--bead` (the blessed drive-list), `--state-workspace`/`--state-rig` (split read/write). **Fixes en route (A38, incl. an adversarial-review pass):** the `oneTurn` exit fix (detached spawn → no exit code → a *successful* one-shot agent was quarantined; now a `oneTurn` vanish → `Exited(0)`/clean close, confirmed live: session `tgdog-2xk` closed `crash_count=0`); a fail-closed guard so a live run refuses to default sessions into the read workspace; `_dispatch` conservative unwind (reap orphan worktree + close orphan session on a post-provision failure); per-bead failures reported, never crash the controller. **951→ M3 offline tests + these (147 in the two touched pkgs) green, `melos analyze` clean.** Agent auth: spawned `claude` authenticates via the macOS keychain (no token env needed — proven by probe). **Carried (A38, not blocking):** leonard-debugs-the_grid is wired (`ext.exploration.*` host + a live VM URI each run) but **unexercised**; non-Anthropic backend (swift-infer) needs a coding-harness/provider shim (parked by Nico); orphan-recovery across a controller restart (`listBeadWorktrees` sweep) has no caller; the `land()`→PR step is a deliberate human follow-up. **lenny remains arm #2** (where tg-coexistence + the "grid builds lenny" headline are taken on).

## Process rules (non-negotiable)

- **The gate: OPEN as of 2026-06-11** (ADR-0001–0004 Accepted, ADR-0000 A1–A7 promoted, PDR §9 empty). The rule persists for new scope: doc before code; Nico ratifies explicitly.
- **ADR-0000 rule:** any decision made by AI goes into ADR-0000 as an amendment and stays there until Nico promotes it or shoots it down. Never write AI decisions directly into ADR-0001+ or silently change ratified docs to match your conclusions.
- Brainstorm → PDR → ADR → zero open questions → code. New scope gets a doc before it gets code.
- Fixtures are version-pinned (`fixtures/upstream/<date>-bd-<version>/`); re-capture via the porting skill's procedure, never edit by hand.

## Conventions

- Dart `^3.11.0`, pub workspace + melos (scripts: `bootstrap`, `test`, `analyze`, `format`), lints cloned from lenny (strict-casts/inference/raw-types, `prefer_single_quotes`, `unawaited_futures`, …).
- **freezed** sealed unions + `json_serializable` codecs; consume with exhaustive `switch` expressions. `build_runner` via melos.
- **Riverpod 3** `Notifier`/`AsyncNotifier` (never `StateNotifier`); streams via `StreamProvider`; derived state via `select`.
- predictable-flutter layering: Services (stateless I/O) → Repositories (own one source, emit state) → Interactors/Selectors/Transformers → View. Reference types carry classifiers (`BdCliService`); value types are plain (`Bead`).
- Tests use **Fakes, not mocks**; pure logic (diff, projections, transitions) is tested before any IO is wired.
- APIs: **Futures for acts, Streams for observations.**

## bd / beads rules

- Always `BD_JSON_ENVELOPE=1`; assert `schema_version == 1`. Errors arrive **enveloped on stdout** with exit ≠ 0 (ADR-0001 Decision 4).
- Mutations: bd CLI only, `--actor grid-controller`. **Never SQL writes. Never touch `.beads/hooks/` (gc owns them).**
- Grouped mutations: `bd batch` (one transaction, one DOLT_COMMIT). Bulk reads: `bd export --include-infra` / `bd query` / multi-id `bd show`. **Never spawn bd per issue in a loop.**
- **Never call `bd show` from a re-query/controller path** — it writes `.beads/last-touched` and self-triggers the watcher.
- `bd list` does not surface infra-typed beads (agent/rig/role) — use export for those (ADR-0001 Decision 4).
- **Coexistence safety (ADR-0003 Decision 6):** gc's convergence handler assumes a single writer per bead. Never reconcile or mutate beads gc's reconciler owns; any shadow/conformance experiment against live convergence traffic is strictly read-only.

## Environment facts

- Dolt **server mode**: db `tg` at `127.0.0.1:34947`; local `.beads/dolt/` is empty. Creds `GC_DOLT_USER`/`GC_DOLT_PASSWORD`; `GT_ROOT=/Users/nico/gascity` (from `.beads/.env`). Server reaps idle connections at **30s** — pools must reconnect; keep ≤2 pooled connections.
- Cross-workspace writes into `tg` are routine (`.beads/routes.jsonl`) — `SELECT @@tg_working` (~1ms) is the authoritative change probe.
- gc keeps running during M1–M3; the_grid coexists (reads + bd-mediated writes only).
- Pinned upstream: **bd 1.0.5 (f9fe4ef2a)**. Sources on disk: gascity `~/development/com.gastownhall/gascity`, beads `~/development/com.gastownhall/beads`, lenny `~/development/com.nicospencer/lenny`, predictable-flutter `~/development/com.nicospencer/predictable-flutter`, **genesis** `~/development/engineering.memento/genesis` (the shared Seed/Branch/keyed-reconcile substrate; the_grid is a *future surface-layer consumer* only — **ADR-0000 A30**: the engine stays snapshot-diff + Riverpod + the gc-fidelity codec, genesis adopted only at the render edge in M3 per A31).
- Lenny M0 prerequisite (`ext.exploration.*` rename → `exploration_contract` extraction) is tracked as lenny beads `lenny-wisp-41rdl` → `lenny-wisp-9h557`; the_grid consumes `exploration_contract` as a **path dependency** during development. Only `grid_exploration` is blocked on it.

## Packages (ADR-0002)

`grid_controller` (sdk) · `grid_cli` (mgmt) · `grid_exploration` (lenny plugin) · `grid_devtools` (DevTools, only Flutter pkg, exploration-protocol-only) · `grid_reconciler` (M2) · `grid_runtime` (M3) · `tmux` (standalone general-purpose client, zero grid deps).
