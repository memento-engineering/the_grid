---
status: proposed
date: 2026-08-30
decision-makers: [nico, agent]
consulted: [external-architecture-auditor]
informed: []
register:
  spec: 1
  slug: trajectory-ledger-split
  surfaces:
    - "packages/grid_engine/lib/src/**"
    - "packages/grid_sdk/lib/src/work/**"
    - "packages/beads_dart/lib/src/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-5l4p
  legacy-id: null
---

# bd is the work ledger; machine-tempo execution rides append-only trajectory records

## Context and Problem Statement

The state store conflates two tempos. Work beads move at human tempo — filed,
refined, approved, closed — and the issue-tracker model fits them. Sessions,
steps, and molecule graphs move at machine tempo — dozens of transitions per
round — and today each transition is a mutation of a bd issue in a dolt
database that versions every row write as a commit.

The operational record of this mismatch, accumulated over one month of
resident operation:

* 81% of state-store dolt commits were twelve wedged steps retrying; `dolt gc`
  reclaims none of it. History is paid for twice: dolt versions rows treated
  as mutable scratch, and the versions are noise.
* Reconstructing what actually happened is archaeology, performed twice at
  operator cost: the legacy-session era backfill (A59) rebuilt outcomes from
  mutated state; a notes clobber was recovered by replaying `bd history`.
* Mutable-field pathologies recur as a class: frozen round projections,
  boards stranded until an unrelated store write nudges a sync, silently
  corrupted text writes, manual close of molecule graphs layer-by-layer to a
  fixpoint after any abnormal end.
* Dolt commit history cannot serve as the trajectory. Batched auto-commit
  collapses N logical transitions into one commit; the history interleaves
  every bead and actor; intent must be reverse-engineered from row diffs.

The 2026-08 orchestrator review reached the same seam from the outside: its
worker-protocol and causal-journal findings were accepted in the governor
response as "extend session beads and the flare stream," which stops short of
naming the storage discipline. The admission-authority decision
(2026-08-30, tg-y4fd) already introduces immutable attempt grants and a
fenced transition service. Independently, a bd maintainer's published
reliability contract for agent factories separates the **work ledger**
(durable facts: identity, claims, outcomes) from the **procedure layer**
(ordering, waits, retries, acknowledgements), and specifies provenance as
append-only, typed, observer-written records with backfill markers —
explicitly distinct from field-change audit trails.

Step and molecule beads are procedure-layer state stored in the work ledger.
That is the defect.

## Considered Options

* **A — status quo, patched.** Keep sessions/steps/molecules as bd issues;
  batch writes harder; keep reaping.
* **B — the trajectory/ledger split.** bd keeps the work graph and every
  human-tempo record. Machine-tempo execution becomes typed, append-only,
  observer-written trajectory records in grid-owned tables; current state is
  a rebuildable fold; the tg-y4fd fenced transition service is the sole
  appender.
* **C — full event-sourcing.** Work beads become events too; bd becomes a
  projection.

## Decision Outcome (proposed)

**Option B.**

* **What stays bd, unchanged in kind:** work beads, gate beads (human-facing
  work items), circuit-minted work products (rework rounds, follow-up beads,
  re-files), refinement/approval flow, deps, `grid.approved`. Circuits keep
  producing work items; they stop storing their execution trace as work
  items.
* **What becomes trajectory:** attempt lifecycle (started / heartbeat /
  terminal with explicit succeeded, failed, cancelled, lost), admission
  grants and their consumption (tg-y4fd), verification bindings to immutable
  commit digests, effect intent/acknowledgement with an explicit `unknown`
  outcome, and step/molecule transitions. Records are typed, append-only,
  written by the observer (never self-reported by the agent), carry
  correlation keys (bead / session / step / attempt / worktree / commit /
  delivery receipt), and admit backfill markers distinguishing observed from
  reconstructed facts.
* **Current state is a fold.** Ready-frontier, dependency, and status queries
  are served by projection tables materialized from the trajectory and
  rebuildable from it. The log is truth; projections are disposable.
* **One appender.** The fenced transition service introduced by tg-y4fd is
  the only writer of trajectory records. Session beads slim to a head
  summary maintained by that service alone; step/molecule issue-type beads
  retire.
* **Storage default:** grid-owned tables in the same dolt database
  (append-affinity, one backup and sync domain), confirmed or overturned by
  the companion spike (tg-hnlt).

A is rejected on the operational record above. C is rejected for now: bd's
issue model is the correct shape for human-tempo work, is how its maintainers
use it, and nothing at current scale needs work beads to be events.

### Consequences

* Good, because the trajectory answers the auditor's worker-protocol and
  causal-journal findings in one mechanism, on the storage discipline the
  ecosystem's own reliability contract prescribes.
* Good, because store growth stops encoding retry churn; the reap retires
  (append-only lifecycle has nothing to close layer-by-layer).
* Good, because attempt granularity (auditor follow-up Q3) resolves without a
  new bead type: an attempt is a trajectory record; fences reference it
  directly.
* Bad, because two storage disciplines coexist during migration, and every
  reader of session/step beads must move to projections.
* Bad, because the fold is new machinery: projection rebuild, schema
  versioning, and replay correctness become real obligations.

### Confirmation

The spike (tg-hnlt) delivers schema, fold, migration, and the storage call.
Ratification gates tg-zfek: atomic lifecycle transitions are implemented as
the trajectory's sole appender, not as hardening of the mutable shape. The
decision is falsified if the fold cannot serve today's frontier/status
queries from projections, or if append-only lifecycle fails to retire the
reap and the stranded-board class it exists to clean.
