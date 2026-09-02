---
status: accepted
date: 2026-07-21
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a55-where-the-state-store-s-link-set-enters-the-pipeline-and
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A55"
---
## A55 (2026-07-21) — where the state store's link set enters the pipeline, and what a malformed link means (tg-ama)

**Decision (AI; `grid_engine` + `grid_sdk`).** Implementing Nico's ratified link-bead design (a grid-state `type=link` bead carrying `grid.link.*` metadata as the cross-repo blocking edge, replacing A44's reversed raw-foreign-id dependency-row convention), three shape choices were left to the implementer and are recorded here.

- **The seam: the JOIN, not the union.** The link set enters at `StationJoinBridge._join` (`_applyCrossLinks`), not as an edge input on `FederatedSnapshotSource`. Feeding the union would give the state source's stream a second listener, so every link change would push the notifier TWICE for one operator action; the state axis already reaches the join, so folding there adds no subscription and keeps one-push-per-real-change by construction. `_attachOpenGates` is the in-file precedent (an OPEN state bead narrows what the tree sees; a CLOSED one retires the narrowing). The ENFORCEMENT is still shared — `_applyExternalDepGuard`'s body was extracted into the pure `applyBlockGuard`, which both edge sources call; callers own the FILTER, the guard owns the meaning of a block. Consequence, deliberate: the union's dep-row source keeps A44's same-store skip (the origin store's own `is_blocked` governs it), while a link bead is enforced whether or not the two ids share a prefix — no store's `is_blocked` knows about an operator-authored edge, so there is nothing to defer to.
- **A malformed link BLOCKS.** A link bead with no `grid.link.to`, or with a `grid.link.type` this engine does not implement, holds its `from` bead out of ready fail-closed and reports LOUDLY, rather than being skipped. Refusing to guess means blocking, not passing — the same posture the unresolvable-target branch already takes. (A link naming no `from` has no bead to hold out; it is reported and dropped.) The cost is that a future non-blocking link kind wedges work until this engine learns it — deliberate, and loud enough to diagnose in one line.
- **The seeded-type refusal is NOT wired into `buildStationWork`.** `crossLinkTypeRefusal` ships as a pure function for the authoring verb to call before it writes. Probing `bd types` inside `buildStationWork` would spawn a process at every arming and break offline tests that build that path over metadata-only temp stores with no `bd` binary present. It accepts both `custom_types` entry shapes (the pinned `tg-types.json` capture is a list of plain strings; `core_types`'s `{name, description}` maps are tolerated too) so a future upstream convergence of the two shapes cannot turn it into a false refusal.

**Why.** The ratified design pins the bead shape, the lifecycle, and the enforcement semantics precisely, but leaves the pipeline seam, the malformed-link posture, and the placement of the capability probe open — exactly the kind of shape decision this register exists to catch before it is silently baked in.

**Not this:** the `link` / `unlink` / `link ls` verbs and the first migration (`tg-q9k` waits-on `pow-60g`) belong to the verb bead, not this one. A44's own status line is left untouched — restating a reversal Nico authored is his call, not an AI edit to a ratified record. Optional auto-close of a link when its `to` target closes is NOT implemented: a closed target already unblocks the `from` bead on the next join, so the link bead is merely stale, not wrong, and closing it is a write into the state store that no read path needs.

**Affects (if promoted):** `beads_dart` `lib/src/models/issue_type.dart` (`IssueType.link`, non-core so the mount allow-list excludes it unchanged). `grid_engine`: new `lib/src/bridge/block_guard.dart` (`BlockEdge`, `applyBlockGuard`), new `lib/src/domain/cross_link.dart` (`CrossLinkKeys`, `kCrossLinkBlocks`, `CrossLink`, `projectCrossLinks`, `crossLinkEdges`, `crossLinkTypeRefusal`), `lib/src/bridge/federated_snapshot_source.dart` (delegation), `lib/src/bridge/station_join_bridge.dart` (`onUnresolvedCrossLink`, `_applyCrossLinks`). `grid_sdk`: `lib/src/work/work_assembly.dart` (the shared sink). Tests: new `grid_engine/test/cross_link_guard_test.dart`, `grid_sdk/test/cross_link_wiring_test.dart`; extended `beads_dart/test/models/types_test.dart`, `grid_engine/test/track_i_invariants_at_depth_test.dart`, `grid_engine/test/join_bridge_test.dart`. Docs: `docs/SUBSTATION-INIT.md` §2 step 4.

**Status:** Pending — Nico promotes or rejects.

