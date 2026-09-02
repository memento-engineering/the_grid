---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a31-genesis-adoption-deferred-to-m3-a-the-grid-adr-0005-a-tu
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A31"
---
## A31 (2026-06-14) — genesis adoption deferred to M3 (a the_grid ADR-0005 + a TUI-inspector spike)

**Decision:** the_grid becomes a genesis *consumer-in-fact* at **M3**, not M2, via a new **the_grid ADR-0005 "genesis adoption"** + a thin spike — not now. Scope: add `genesis_typesetting` (bare-VM Stage/Box/Text → CellGrid → ANSI, ~48× byte economy, no Flutter engine) **+** its `genesis_tree` spine as **sibling-checkout path dependencies** (the same pattern the_grid already uses for lenny's `exploration_contract`), and build a small **TUI bead/convergence inspector** (`grid top`) that draws a frame into a tmux pane `grid_runtime` supervises (genesis's ratified A4: grid's tmux "owns terminal real estate", a genesis backend "draws into" it — complementary, not duplicative). This is the cheapest "consumer in fact": purely **additive** (a new surface-layer package), **downstream of the M2 engine** (reads bead snapshots, does **not** mount beads as a domain tree), and it does **not** require resolving genesis's full A7. **Deferred / conditional:** `genesis_taxonomy` as the generator for a *typed* agent-tool schema is relevant **only if/when** the exploration manifest's tools need typed JSON-Schema params (today name+prose only) — a **joint lenny+grid** decision routed through the shared `exploration_contract`, not a unilateral grid edit. `genesis_dialogue` (A2UI UI wire) and `genesis_consent` (UI-action router, currently unbuilt/0-tests) have **no fit** for the_grid's bd-mediated cross-process domain.
**Why:** the re-evaluation ([[A30]]) found `genesis_typesetting` the one genuinely attractive concrete adoption (an in-terminal inspector); a real dependency + a new render surface warrants its own ADR + spike, properly M3 (the surface/runtime milestone), not bolted onto M2.
**Affects (if promoted):** a future the_grid **ADR-0005** (genesis adoption) + `docs/M4-SCOPING.md` (the surface-layer rung). Code (M3): a new `grid_tui`-style package on `genesis_typesetting`+`genesis_tree`. Known bounds to flag going in: the single-observer `TreeOwner.onNeedsFlush` limit + typesetting's minimal-flow layout.
**Status:** pending (M3 — author ADR-0005 then; the forward bet is recorded so it isn't lost). · **Overtaken before promotion by ADR-0007 (Accepted 2026-06-24)** — A31 was *pending* (never ratified); the M4 pivot mounts the work lifecycle as a domain tree **in the engine** (ADR-0007 §6.4), so genesis is now an engine dependency, not a surface-only consumer. **ADR-0005 is retired** (Nico, 2026-06-24); the optional `grid top` TUI inspector + the tg-e28 perception rebuild take a fresh number if ever pursued.

