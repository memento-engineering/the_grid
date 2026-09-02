---
status: accepted
date: 2026-06-16
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a36-first-live-arm-side-cars-genesis-not-lenny-real-beads-di
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A36"
---
## A36 (2026-06-16) — first live-arm side-cars **genesis**, not lenny (real beads dispatched directly, owned embedded DB, zero gc-coexistence)

**Decision (Nico, 2026-06-16):** the **first** dogfood live arm side-cars the **genesis** backlog, superseding the lenny target named in A35 / ADR-0006's ratified inputs **for arm #1 only**. The grid drives the two real, ready, pure-Dart feature beads **`genesis-q8h`** (first-class `Key`/`ValueKey<T>`/`ObjectKey`) and **`genesis-7r9`** (multi-child keyed list-reconcile) — *exactly the genesis_tree capabilities the_grid's own M4 config-substrate will consume* (self-bootstrapping flywheel). **lenny becomes the second dogfood target**, where tg-coexistence and the "grid builds lenny" headline are deliberately taken on *after* arm #1 is proven.
**Why genesis is the safer arm #1:** (1) genesis's DB is `genesis`, **embedded**, **solely the_grid-owned** — no gc reconciler is anywhere near it, so the entire disjoint-rig/coexistence apparatus (ADR-0003 D6, the tgdog partition) is **moot** for arm #1. (2) The real beads already exist with the `genesis-` prefix, so the `BeadOwnershipPredicate` owns them under allow-set **`{genesis}`** with **zero code change** (prefix axis) — no mirror-bead minting (contrast ADR-0006 D1's "work beads minted into the dogfood rig by Nico's procedure"). (3) Two independent ready beads → the grid dispatches **both concurrently** = a genuine multi-bead demo. The **leonard-debugs-the_grid half is unaffected** — it always uses lenny's leonard (`--extensions grid`) regardless of which backlog is built.
**Mechanical consequence — one open sub-decision (held for the arming gate).** `runGrid` currently uses **one** `BeadsWorkspace` for *both* ready-work reads and session-bead writes (`ProcessBdRunner(workspaceRoot: workspace.root)`). Reading genesis is a small `--workspace <path>` flag exposing the existing `runGrid(workspaceOverride:)` hook. But **where the_grid's own `type=session` lifecycle beads land** is Nico's call: **(a)** *in genesis* (single owned embedded store, minimal code — runtime lifecycle beads appear in genesis's real backlog), or **(b)** *a separate the_grid-owned dogfood DB* (A21 spirit — keeps genesis's backlog clean, needs split read/write wiring). The **read-only `grid run --dry-run`** writes **no** session beads, so it sidesteps (a)/(b) entirely and is the safe first step; the write-target is decided when writes are actually armed.
**Built (2026-06-16, dry-run plumbing — read-only, no new write paths).** Two `grid run` flags + a dispatch gate, ratified-inputs aside: **`--workspace <path>`** (read another repo's `.beads/`; defaults to cwd discovery) and **`--bead <id>` (repeatable)** — an **operational drive-list** layered ON TOP of the ownership allow-set: when non-empty, a bead must be **both owned AND listed** to dispatch; owned-but-unlisted beads are observed read-only. The drive-list surfaced from the first dry-run: because `{genesis}` owns the **whole** `genesis-` prefix, ownership alone would dispatch all 6 ready genesis beads (incl. judgement/research tasks). The drive-list is the **mechanical form of A35's "bless the 2 specific work beads" gate** — `--bead genesis-q8h --bead genesis-7r9` scopes arm #1 to exactly the two targets. Verified by a scoped `grid run --dry-run` (only the 2 would-dispatch; the other 4 observed read-only; zero writes/spawns) + 3 new `DispatchInteractor` tests. `DispatchInteractor` empty-drive-list default preserves the original `tgdog` behaviour.
**Affects:** **ADR-0006** ratified-inputs block + Decision 1/3 (arm #1 reads genesis, allow-set `{genesis}`, root checkout becomes a `genesis` clone not `lenny-tgdog`; no mirror-bead minting) — one-line amendment once Nico confirms the sub-decision; **A35** (lenny inputs apply to arm #2). Code (shipped, dry-run-only): `grid run` `--workspace`/`--bead`; `DispatchInteractor` drive-list gate (`grid_cli`/`grid_runtime`, 139 tests green, analyze clean). Still pending: allow-set seed for live writes, the session-bead write-target per the sub-decision, the genesis root checkout.
**Status:** **Nico's decision (side-car genesis), 2026-06-16** — recorded; dry-run plumbing built + verified. The **session-bead write-target** sub-decision + the live-arm go-ahead remain with Nico at the gate.

