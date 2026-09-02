---
status: accepted
date: 2026-06-13
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a26-track-e-actuator-the-only-writer-bd-verb-surface-persist
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A26"
---
## A26 (2026-06-13) — Track E actuator: the only writer — bd verb surface, persistent pour, and burn-vs-close

**Decision:** Track E (built; grid_controller bd surface +`lib/src/actuator/`, ~235 tests; passed both adversarial lenses with no fix round) is the_grid's **only writer**. Surface: an `Actuator` seam `apply(ReduceResult, Convergence) → ActuationResult{pouredWispId, requeue}` + `BdActuator` + `FakeActuator`; `apply()` walks the ordered action list, threading the in-list pour result (`priorPourWispId`/`priorPourFailed` = gc's `speculativeWispID`/`speculativePourErr` locals). **grid_controller bd extensions (additive — existing signatures unchanged):** `update(id, {metadata, type, assignee, …})` → `bd update --metadata <json>` (merge; works on closed beads; type/assignee = the deferred-activation channel); `applyGraph(GraphApplyPlan, {ephemeral = false})` → `bd create --graph <tempfile> [--ephemeral]` returning key→id (**default PERSISTENT** per [[A15]]; plan serialized to a temp file); `cook(formula, {mode:'runtime', vars})` → `bd cook --mode=runtime --json` (resolve; **no** `--actor`, no `--persist`); `delete(id)` → `bd delete <id> --force` (the burn primitive). `GraphApplyPlan`/`GraphNode`/`GraphEdge` are plain classes. **Live idempotency probe** = `DoltQueryService.findWispByIdempotencyKey(parentId, key)`: a **SELECT-only** query over the parent-child edge JOIN `issues ∪ wisps` filtered by `JSON_EXTRACT(metadata,'$.idempotency_key')`, inside `runReadTransaction` — **not** `bd show`, run live immediately before a pour ([[A17]]). **Two corrections pinned: (a) burn order is `Wisp.subtreeIds` in NATURAL order** (children-first, root last) — `subtreeIds` is *already* post-order, so the Wave-3 brief's "reversed" was wrong; one `bd delete` per id, then best-effort `pending_next_wisp ← ''`. **(b) force-close ≠ burn:** `StoppedAction.forceCloseWispId` executes via **`bd close`** (reason `manualSupersede`), never `bd delete` — **only speculative wisps are burned** (deleted); a stopped active wisp is *closed*. Step-8 convergence **bus-event emission is out of actuator scope** — deferred to Track G's exec site (it needs the event bus + a live metadata re-read).
**Why:** ADR-0003 D4 + A15/A16/A17 fix the verbs and ordering; turning them into code surfaced the burn-order and burn-vs-close distinctions (both verified against gc handler.go/manual.go) and the temp-file mechanics of `bd create --graph`. As the sole writer, E was given two adversarial lenses — bd-sequence fidelity (no stray `--ephemeral`; correct verb/order) and write-safety/partition (no live writes, `--actor grid-controller`, no `bd show`, SELECT-only probe) — both passed first time.
**Affects (if promoted):** ADR-0003 D4 (the actuation verb surface + burn-vs-close). Code: `grid_controller` `BdCliService`/`DoltQueryService`/`graph_apply_plan.dart`; `grid_reconciler/lib/src/actuator/`.
**Status:** **promoted → ADR-0003 Decision 8 (Nico, 2026-06-14)**.

