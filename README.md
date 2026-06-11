# the_grid

A Dart-native reactive orchestrator for multi-agent software development, built to
replace [Gas City](https://docs.gascityhall.com) over a [beads](https://github.com/steveyegge/beads)
work graph. Part of a long-term bet on Dart as a full-stack agentic platform:

> Apps are built in Flutter. Lenny drives and debugs the apps. Lenny files bugs as beads
> into the grid. **The grid builds everything.**

Where Gas City samples its world on a ~10s patrol loop, the_grid observes it: change
signals → single-flight re-query → structural diff → typed graph events → Riverpod
providers — with the live process inspectable by humans (DevTools) and agents over the
Dart VM service exploration protocol.

## Status

**M1 in progress** — the gate is open (ADR-0001–0004 Accepted, 2026-06-11). The reactive
kernel is built and demonstrated end-to-end: a `bd` mutation in one terminal surfaces as a
typed event in `grid watch` in another.

```
$ grid watch                       # in the_grid (or any beads workspace)
grid watch — workspace: /…/grid_demo
read path: cli  (direct mode, db demo)
VM service: ws://127.0.0.1:…/ws    ·  attach exploration_cli/devtools here
————————————————————————————————————————————————————————————————
06:48:25.375  SnapshotInitialized — 0 beads, 0 ready
06:48:28.793  BeadCreated     demo-3iu "tron lives" [molecule] (reacted 659ms)
06:48:31.597  BeadClosed      demo-3iu (reacted 590ms)

# meanwhile, in another terminal:
$ bd create "tron lives" -t molecule -p 1
$ bd close demo-3iu --reason "end of line"
```

**Measured reaction latency** (dirty signal → typed event, hermetic `bd init` workspace,
macOS): ~590–660ms on the **bd-CLI fallback path** (two `bd` spawns per refresh + the 150ms
quiet period + FSEvents watcher latency). The **pooled-SQL path** (~1–5ms reads) is the one
that targets the PDR §6.1 ≤500ms budget; it self-skips without `GC_DOLT_PASSWORD` and falls
back to CLI. Latency is printed per event so the reactivity claim stays quantitative.

### Packages

| Package | Role |
|---|---|
| `grid_controller` | the SDK: bd-CLI + Dolt-SQL services → snapshot repository → structural diff → typed `GraphEvent` stream → Riverpod providers → domain projections |
| `grid_exploration` | exploration-protocol host (`ext.exploration.*`): handshake / stable observation / `grid` tools, over `dart:developer` |
| `grid_cli` | `grid watch` — stream typed events with measured latency; `--json` for NDJSON |
| `grid_devtools` | DevTools extension over the exploration protocol (no SDK dependency) |

`melos bootstrap` then `melos test` / `melos analyze`. Integration tests are tagged
`integration` (require `bd` on `PATH`); the unit suite runs fully offline.

This repo is also a Gas City rig (`tg` issue prefix) — the factory that will eventually
build it.

## Reading order

| Doc | What |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Session contract: process rules, conventions, environment facts |
| [`docs/PDR.md`](docs/PDR.md) | Vision, goals, milestones M0–M4, acceptance criteria, the gate |
| [`docs/adr/ADR-0000…`](docs/adr/ADR-0000-ai-decision-register.md) | **AI decision register** — pending AI decisions live here until promoted or rejected |
| [`docs/adr/ADR-0001…0004`](docs/adr/) | Ratified decisions: foundations · packages + domain projections · reconciler · runtime/tmux |
| [`docs/M1-BUILD-ORDER.md`](docs/M1-BUILD-ORDER.md) | Dependency-ordered build tracks for milestone 1 |
| [`docs/M4-SCOPING.md`](docs/M4-SCOPING.md) | Usage-driven M4 decomposition + the fs adoption ladder |
| [`fixtures/upstream/`](fixtures/upstream/) | Version-pinned bd/gc fixtures (currently bd 1.0.5) |
