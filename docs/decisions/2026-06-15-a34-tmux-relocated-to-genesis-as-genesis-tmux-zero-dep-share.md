---
status: accepted
date: 2026-06-15
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a34-tmux-relocated-to-genesis-as-genesis-tmux-zero-dep-share
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A34"
---
## A34 (2026-06-15) — `tmux` relocated to genesis as `genesis_tmux` (zero-dep shared primitive)

**Decision (Nico, 2026-06-15):** the standalone tmux client planned as a the_grid package (ADR-0002 topology) is **relocated to the genesis pub workspace as `genesis_tmux`** — a zero-dependency, general-purpose tmux client (only `meta`), pub.dev candidate. the_grid's `grid_runtime` `TmuxProvider` consumes it as a **sibling-checkout path dependency** (the same pattern the_grid uses for lenny's `exploration_contract`). It is a faithful port of gc's `internal/runtime/tmux`, **broadened** by a reference survey (libtmux / tmux control-mode / iTerm2 / the tmux(1) man page) before the build. Build handoff staged at `genesis/packages/tmux/HANDOFF.md`. Fits genesis's ratified **A4** (tmux = the terminal-real-estate primitive a genesis backend "draws into").
**Why:** a zero-dep tmux client is a shared-substrate primitive, not a the_grid-private concern; genesis is its natural home and already names tmux in its own canon. Keeps the_grid's package set focused on the orchestrator.
**Affects:** **ADR-0002** (package topology — `tmux` moves out of the_grid; the_grid consumes `genesis_tmux` as a path dep) gets a one-line amendment; genesis gains `packages/tmux`. Off the M3 Friday critical path (the dogfood is `SubprocessProvider`-only; `TmuxProvider` is the gc-compatible alternative).
**Status:** **Nico's decision, 2026-06-15** — recorded; build proceeds in genesis (reference survey first, per Nico).

