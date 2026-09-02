---
status: accepted
date: 2026-06-17
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a39-the-grid-adheres-to-genesis-adr-0006-perception-is-pull
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A39"
---
## A39 (2026-06-17) — the_grid adheres to **genesis ADR-0006 (perception is pull-free)**; two conversations converged on the same discipline

**Decision (Nico-prompted, AI-recorded, pending):** the_grid **adopts genesis ADR-0006 — "Perception is pull-free: synchronous build, out-of-band watch"** (Accepted 2026-06-17, surfaced from lenny `lenny-9kni`) as the governing discipline for its genesis-consumption surfaces. Its rule: `build()` is **never async**; the observed source is **watched out-of-band** (a `StatefulPerception`/`PerceptionState` opens the subscription, the change callback schedules a harvest via `perceived()`→`markNeedsHarvest`→`flushHarvest`, `dispose` tears it down); the watcher feeds a live snapshot and build stays **pure/synchronous** over it. The async-I/O litmus (a tmux process via `capture-pane`) fits the sync contract unchanged.
**The convergence (why "same conclusion"):** it is the **same substrate** (`genesis_tree`/`genesis_perception`'s `Seed`+`Branch`+`Watch`, ADR-0005 Attention) and the **same discipline**, reached from two directions —
- **Already true in the_grid's kernel (independent, pre-dates the ADR):** `grid_controller` watches bd **out-of-band** (file-watch + the `@@tg_working` SQL probe → single-flight re-query → `GraphSnapshot`) and computes **pure** `diffSnapshots`. Observation latency never lives in a build.
- **`grid_exploration` IS a genesis-style perception of the_grid** (read-only `grid.{requery,snapshot,ready,events,stats}` over `ext.exploration.*`) — and it is exactly the `lenny-9kni` forcing case (a non-Flutter Dart program perceived over the same surface). The **leonard-debugs-the_grid half (tg-e28)** is therefore built as a `StatefulPerception` watching the controller out-of-band — pure ADR-0006.
- **The M4 config-substrate brainstorm converged on it** (conclusion #5/#12): a stateful config node watches a live signal via `Watch`/`useStream` (`initState`-subscribe → setState → `dispose`) and `build()` stays pure over the snapshot.
**The_grid's one strictness delta (a guard, not a conflict — the A30 coherence invariant):** genesis perception only *observes*, so it may watch any source. the_grid's **desired-state-authoring** tree must never become a *second change-detector over reality*, so a `Watch` may react **only to an explicitly injected `Stream`**, never the config tree subscribing *into* the bead snapshot-diff pipeline. Same pull-free contract; plus a constraint on *which* source is watchable.
**Affects:** feeds the future **the_grid ADR-0005** (genesis adoption at the surface/render layer, deferred per A30/A31) — genesis ADR-0006 is now the named discipline for tg-e28 (leonard-debug perception) and, if M4 graduates, the config-authoring tree. No engine change (snapshot-diff + Riverpod + gc-fidelity codec stay; A30 unchanged).
**Status:** **Ratified (Nico, 2026-07-12, ADR interview) — HYBRID.** The POLICY (adopt genesis ADR-0006 "perception is pull-free: synchronous build, out-of-band watch" as the_grid's governing perception discipline) is Nico-PROMPTED — already his call. The AUTONOMOUS content ratified: the convergence analysis (the_grid already conforms by construction, from two directions) + the STRICTNESS-DELTA GUARD (a `Watch` reacts only to an explicitly injected `Stream`, never the config tree subscribing into the bead snapshot-diff pipeline — the A30 coherence invariant). This pull-free discipline is the through-line of the 2026-07-12 reactive architecture (hot-restart reconcile / tg-zts; route-as-standalone-app / tg-tkm; hold-state-don't-probe / ADR-0013). Promote into the future the_grid ADR-0005 at will. · **ADR-0007 (Accepted 2026-06-24) keeps A39's pull-free contract + injected-Stream-only guard** (relied on in ADR-0007 §6.1 inv 1); A39's "Riverpod stays / no engine change / A30 unchanged" rider (on its Affects line) is **overtaken for the dispatch core** — snapshot-diff *detection* + the gc codec stay (ADR-0007 §6.6–6.7). A39's body is left intact; its tg-e28 perception home moved with the retired ADR-0005.

