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

Documentation phase. Implementation is gated until ADR-0001–0004 are Accepted
(PDR §9). This repo is also a Gas City rig (`tg` issue prefix) — the factory that will
eventually build it.

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
