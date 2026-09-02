---
status: accepted
date: 2026-06-14
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a30-the-grid-genesis-keep-separate-for-the-engine-consume-on
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A30"
---
## A30 (2026-06-14) — the_grid ↔ genesis: keep-separate for the engine; consume only at the surface layer

**Decision (Nico, after a full ADR re-evaluation against `engineering.memento/genesis/docs`):** **genesis** is the shared Seed/Branch/keyed-reconcile substrate that names the_grid a *consumer* — but genesis was extracted **after** the_grid and pulled the_grid's own ADR-0001 conventions up into its shared canon, so the_grid already conforms to the memento house canon (freezed sealed unions, exhaustive switch, the ADR-0000 register rule, round-trip identity, value-plain/reference-classified) — **alignment by construction.** A re-evaluation of every the_grid ADR against genesis concludes: **adopt nothing into the foundations or the convergence engine.** Specifically — **(1)** the change-detection engine **stays snapshot-diff** (`diff_snapshots.dart`): the bead graph (issues ∪ wisps) has **no keyed-tree root**, so `genesis_tree`'s keyed reconcile is NOT adopted for bead change-detection (this resolves **genesis's A7 flag** from the_grid's side — "two reconcilers at two layers, collision not duplication"). **(2)** **Riverpod 3 stays** (genesis deliberately kept its tree core Riverpod-agnostic so the_grid's 3.0 never binds it). **(3)** the convergence codec / state machine / **bd substrate** / coexistence partition stay **grid-local** — genesis is silent (a source search of all six genesis packages for `convergence`/`reduce`/`state-machine`/`gate`/`last_processed_wisp` returns **zero**; genesis's own A6 names these "stay grid-local"). **Cross-references:** the_grid's total-decode + structured-reject + fresh-read-no-cached-refs discipline (A17/A25/A27 + shadow mode) independently matches genesis's `staleUnmounted`/A8 staleness stance — confirming the shared canon; mechanism stays grid-local. genesis is consumable only at the **surface/render layer** (where a keyed tree exists), deferred to A31.
**Why:** Nico directed a re-evaluation after the genesis substrate was discovered beside the_grid; the audit found **no foundational conflict and no engine rework** — every genesis adoption is additive and downstream of the engine. Recorded deliberately (the_grid's register previously had **zero** genesis content) so the divergence "isn't silently inherited" (genesis A7's own phrasing).
**Affects:** ADR-0002 D2 + ADR-0003 D6 (genesis cross-ref notes added 2026-06-14: the engine stays snapshot-diff/grid-local by deliberate decision, not omission). `CLAUDE.md` (genesis added to the cross-repo map). Code: none (records that `diff_snapshots.dart`/`grid_reconciler` stay as built).
**Status:** **Nico's decision, 2026-06-14** — recorded; engine stays grid-local; genesis at the surface layer per A31. · **§(1) partially superseded / §(2) fully superseded / §(3) unchanged — by ADR-0007 (Accepted 2026-06-24); see ADR-0007 §6.1–6.3.** (The M4 tree-engine pivot: change-*detection* stays snapshot-diff [A30(1) retained]; keyed reconcile adopted for the work *lifecycle* downstream of detection; Riverpod→StateNotifier [A30(2)]; convergence/codec/coexistence stay grid-local [A30(3)].)

