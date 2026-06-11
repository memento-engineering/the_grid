# PDR — the_grid: a reactive work-graph orchestrator in Dart

**Status:** Draft for review
**Date:** 2026-06-11
**Author:** Nico Spencer (with Claude)

## 1. Problem

Gas City (`gc`) orchestrates multi-agent work over a beads issue graph, but:

- Its control loop is a **~10s polling patrol** (`cmd/gc/city_runtime.go`), not reactive. State changes are sampled, not observed. Latency between "work became ready" and "agent dispatched" is bounded below by the patrol interval.
- It is **343k lines of Go** in a stack whose owner works in Dart/Flutter. Every interaction is a context switch; none of the owner's tooling, debugging instincts, or architecture patterns apply.
- Its runtime state is **opaque while running**. There is no equivalent of attaching a debugger, inspecting live state, or letting an agent introspect the orchestrator the way Lenny does with Flutter apps via the Dart VM service.

The valuable ideas — a declarative work graph (beads) reconciled by a controller — are sound and proven. The implementation substrate is the mismatch.

## 2. Vision

This is a long-term bet on **Dart as a full-stack agentic software development platform**:

> Apps are built in Flutter. Lenny drives and debugs the apps. Lenny files bugs as beads
> into the grid. **The grid builds everything.**

One language, one architecture, one debugging surface (the Dart VM service) from the app
under test all the way up to the orchestrator dispatching the work. the_grid closes the
loop: the same exploration protocol Lenny uses to introspect a Flutter app introspects
the orchestrator itself.

Mechanically, that means replacing `gc` with a Dart-native orchestrator built as a
**genuinely reactive** system: change signals push through a single-flight re-query into
a structural diff, which emits typed graph events that drive reconciliation — observable
end-to-end by humans (DevTools) and agents attached to the live process.

beads (`bd` + Dolt) remains the substrate — it is infrastructure, like Postgres, not
code we write. Everything above it is Dart.

## 3. Goals

- **G1 — Reactivity:** local `bd` mutations reflected as typed events in ≤500ms; cross-workspace mutations (other rigs writing the same Dolt database) in ≤2s.
- **G2 — One language, one architecture:** all code follows predictable-flutter's layered architecture (services → repositories → interactors/selectors → view), Riverpod 3, Lenny's workspace/lint conventions.
- **G3 — Agent-grade observability:** the running orchestrator speaks Lenny's exploration protocol (handshake / stable observation / namespaced tools), so exploration_cli, exploration_devtools, and the exploration agent attach to it with zero bespoke tooling.
- **G4 — Replacement trajectory:** each milestone's outputs are the next milestone's inputs; nothing is throwaway on the path to retiring `gc` for the owner's projects.
- **G5 — Cheap reads:** the hot read path costs ~1–5ms (pooled Dolt SQL), not ~70–140ms per `bd` spawn; bd usage prefers batch/bulk forms (`bd batch`, `bd export`, `bd query`) over per-issue spawns.
- **G6 — Typed domains, reactively:** every grid domain — agents, agent sessions, rigs, roles, convoys, molecules, gates, merge-requests, specs, convergences, steps — is exposed as reactive typed views/transformations projected over the work graph, never ad-hoc bead filtering at call sites (ADR-0002).

## 4. Non-goals

- Porting beads/`bd`/Dolt to Dart. The work-graph store stays Go-infrastructure.
- Re-implementing gc's full surface (70+ CLI commands, HTTP+SSE API, tmux/k8s providers, packs). We port the irreducible core (~4k LOC of domain logic), not the projection layers.
- Bypassing `bd` for mutations. Writes always go through the CLI — it owns validation, audit events, gc hooks, and Dolt commit semantics.
- Feature parity with gc before M1 ships. The kernel earns the right to grow.

## 5. Milestones

| Milestone | Deliverable | Proves |
|---|---|---|
| **M0** | `exploration_contract` extraction in lenny (pure-Dart plugin contract), preceded by the repo-wide `ext.exploration.*` prefix rename (see §9 Q1) | Prerequisite for G3 |
| **M1** | Reactive beads controller across packages `grid_controller` (sdk) / `grid_cli` (mgmt) / `grid_exploration` (lenny plugin) + `grid_devtools` scaffold (ADR-0002): services (bd CLI + Dolt SQL) → snapshot repository → diff interactor → typed `GraphEvent` stream → Riverpod providers → domain-projection mechanism (agents, sessions, rigs as proving domains) → `grid watch` CLI → `GridControllerPlugin` speaking the exploration protocol. Plus the **porting skill**: a skill documenting how to track upstream gascity/beads releases, pull pack-protocol changes, and stay aligned while the port matures | The bet: Dart + Riverpod beats the polling loop; the process is live-debuggable; upstream drift is managed, not accidental |
| **M2** | Reconciler skeleton: `DesiredState` + state machine consuming events/snapshots, emitting typed actions through bd mutations. Differential-tested ready-work SQL (removes `bd ready` from the hot path) | gc's convergence core works as a Dart state machine |
| **M3** | Runtime providers: **tmux provider** (gc's default and ours — see §7a scope) + plain subprocess provider; spawn/supervise coding-agent sessions per ready bead, lifecycle tracked as beads | the_grid dispatches real work into attachable tmux sessions |
| **M4** | Declarative topology (city-config equivalent) + orders/triggers | gc replacement proper |

Deferred deliverable (post-M1, no milestone assigned yet): an **upstream RFC document** for
pushing the_grid's ideas (reactive controller, exploration-protocol observability) back to
Gas City.

## 6. M1 acceptance criteria

1. Two-terminal demo: `dart run --enable-vm-service grid_cli:grid watch` in terminal A; `bd create "tron lives" -t molecule -p 1` in terminal B → A prints `BeadCreated` + `ReadySetChanged` with measured reaction latency ≤500ms.
2. A mutation made from a *different* workspace routed into the `tg` database appears as events within ≤2s (Dolt working-set probe).
3. exploration_devtools and exploration_cli attach to the running `grid watch` process via its VM service URI; handshake succeeds; `observe()` returns graph state; at least one grid tool (e.g. `requery`) is invocable.
4. SQL-vs-CLI equivalence test passes: snapshots composed via the Dolt read path and the bd CLI path are identical.
5. Unit suite green offline (no bd, no Dolt); tagged integration suite green against a hermetic `bd init` workspace.
6. No writes ever issued over SQL; no files under `.beads/hooks/` touched (verified by test).
7. The porting skill exists in-repo and covers: pinned upstream versions (gascity, beads), how to diff pack-protocol / `bd --json` schema changes against our fixtures, and the procedure for re-aligning when upstream moves.
8. Domain projections prove out: `agentsProvider` / `sessionsProvider` / `rigsProvider` expose freezed domain values projected from real city beads (metadata mappings validated against fixtures captured from the live city).

## 7. Constraints & environment facts

- the_grid's beads runs **Dolt server mode**: database `tg` at `127.0.0.1:34947`, data in `~/gascity/.beads/dolt/tg/`; creds via `GC_DOLT_USER`/`GC_DOLT_PASSWORD`; `GT_ROOT` from `.beads/.env`.
- The Dolt server **reaps idle connections at 30s** (`wait_timeout: 30`) — pools must reconnect; per-call client pileup is a documented past incident (200–460 sleeping connections).
- `bd` writes `.beads/last-touched` on nearly all local mutating commands (and on `bd show` — a read that dirties the signal; the re-query path must never call it).
- Cross-workspace writes are routine (`.beads/routes.jsonl`): a workspace file-watch alone is insufficient; the SQL probe (`SELECT @@tg_working`) is the authoritative change signal.
- beads' schema migrates frequently and is not a stable public interface: SQL reads are guarded by a migrations-version check with automatic fallback to bd CLI.
- gc continues to run during M1–M3; the_grid coexists (read + bd-mediated writes only).

### 7a. tmux provider scope (M3 input, assessed 2026-06-11)

gc's tmux provider is its default runtime and the_grid will need one. Assessment of
`gascity/internal/runtime/tmux/` (~5.9k LOC production, ~8.1k LOC tests):

- **No magic**: pure subprocess invocation of the `tmux` binary (no Go library, no control
  mode) — 23 verbs, all portable to Dart `Process.run` directly. Per-city server isolation
  via `tmux -L <socket>`.
- **Tiered port**: MVP ≈ 1.5–2k LOC (new-session / kill-session / send-keys with
  literal-mode + retry / capture-pane / list-sessions / has-session / display-message
  queries). Production robustness adds: copy-mode cancellation before every send, poke
  activity discounting, nudge serialization (per-session mutex + 30s timed lock), paste-
  buffer path for >8KB, process-tree walking for clean kills (SIGTERM→grace→SIGKILL,
  reparented-process collection), respawn-pane recovery, and agent-specific quirks
  (Escape semantics and paste debounce differ across claude/codex/gemini/kimi).
- **Deferrable**: approval-prompt detection/response, startup-dialog dismissal, state
  caching, hooks, themes.
- The hard part is not tmux — it's the timing/retry heuristics around interactive agent
  TUIs. gc's test suite for these is the porting spec. Full decisions belong to an M3 ADR.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Dart MySQL client can't complete Dolt's auth handshake | Day-one spike; bd-CLI-only fallback keeps M1 shippable (slower probe, same design) |
| beads schema drift breaks SQL reads | Version guard + CLI fallback + equivalence test as canary |
| Lenny contract extraction stalls | Protocol is small; the_grid can mirror the three wire extensions temporarily without lenny changes |
| Diff misses a change class (e.g. label-only edits) | Diff operates on full value equality of all fetched fields; integration tests enumerate mutation types |
| Reactivity claim doesn't hold under load | `grid watch` prints measured latency per event; M1 acceptance is quantitative |
| tmux provider heuristics (M3) regress vs gc | Tiered port (MVP verbs first); gc's 8.1k-LOC tmux test suite is the executable spec; agent-quirk table ported verbatim |
| Upstream gascity/beads drift while we port | M1 porting skill: pinned versions, fixture diffing, re-alignment procedure |

## 9. Open questions

*(Gate: this section must be empty AND ADR-0001 through ADR-0004 must be **Accepted** before implementation starts — per Nico, the chain runs all the way through the M3/tmux ADR.)*

1. ~~**Protocol naming:**~~ **Resolved 2026-06-11:** rename upstream in lenny to `ext.exploration.*` as a precursor to M0 (lenny bead lenny-wisp-41rdl, blocks lenny-wisp-9h557). `ext.flutter.*` is the framework's reserved namespace; registration is via `dart:developer.registerExtension`, so the `flutter` segment was hand-written, and a pure-Dart host advertising it would mislead Flutter-detection tooling. All consumers (agent/CLI/DevTools) live in lenny's monorepo and land in lockstep. See ADR-0001 Decision 6 (amended).
2. ~~**M0 scoping:**~~ **Resolved 2026-06-11:** no lenny-side ADR for now (Nico will author one later); the work is tracked by the defined lenny beads (lenny-wisp-41rdl → lenny-wisp-9h557). the_grid consumes `exploration_contract` as a path dependency during development.
3. ~~**Package names:**~~ **Resolved 2026-06-11:** `grid_controller` (sdk) / `grid_cli` (mgmt) / `grid_exploration` (lenny plugin) / `grid_devtools` (DevTools), plus planned `grid_reconciler` (M2) and `grid_runtime` (M3). Set by Nico; topology in ADR-0002 Decision 1.
