---
status: accepted
date: 2026-08-22
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a58-molecule-reap-follows-the-complete-intra-graph-dependenc
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A58"
---
## A58 (2026-08-22) — molecule reap follows the complete intra-graph dependency order (tg-nlwo)

**Decision (AI; pending Nico promotion).** `StationBeadWriter.reapMolecule` closes a session-owned graph in deterministic reverse topological order over the union of in-graph parent-child, hard-blocking, and supersedes edges. A bead is closed only after every in-graph bead that must precede its close: children before their parent, blockers before the issue they block, and superseding incarnations before the beads they supersede. The dependency set is fetched once with multi-id `bd dep list`; mutations remain one line-oriented `bd batch`, with the existing ordered per-bead fallback preserving the same precomputed order.

**Cycle and force policy.** A cycle is detected before the first write and raised as `StateError('molecule reap dependency cycle: <sorted ids>')`. Engine boundaries translate that named failure into their existing `session.moleculeReapFailed` flare and continue closing the session or replaying boot. The reap never passes `--force`: bd's refusal protects graph meaning when a blocker remains open.

**Supersedes prior policy.** This decision supersedes `docs/SCRATCH-bd-repin.md` Phase B B5 / tg-f9h0's “leaves-first close ordering ... or explicit `--force`” policy. Parent-child leaves-first remains one constraint inside the complete order, but is insufficient for sibling blocking edges; the force alternative is rejected because it would hide an invalid close order.

**Not this.** No second ordering helper is introduced, no engine boundary changes its loud non-fatal posture, and no production algorithm is rewritten in the SDK consumer-coverage round that records this decision.

**Affects (if promoted).** `packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart` (`StationBeadWriter.reapMolecule`, `_moleculeReapOrder`); `packages/grid_engine/lib/src/circuit/session_scope.dart`; `packages/grid_engine/lib/src/restart/restart_reconciler.dart`; `packages/grid_sdk/lib/src/command/station_command_handler.dart`; supersedes `docs/SCRATCH-bd-repin.md` Phase B B5 / tg-f9h0.

**Status:** Pending — Nico promotes or rejects.

