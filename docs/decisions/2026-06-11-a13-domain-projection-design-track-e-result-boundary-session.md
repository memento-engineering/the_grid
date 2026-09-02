---
status: accepted
date: 2026-06-11
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a13-domain-projection-design-track-e-result-boundary-session
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A13"
---
## A13 (2026-06-11) — Domain-projection design (Track E): result boundary, session state, step/needs composition

**Decision:** the M1 projections (ADR-0002 D2 trio) adopt these shapes: (a) every `project()` factory returns a sealed `ProjectionResult<T>` (`ProjectionOk` | `ProjectionFailed(ProjectionError)`) — decode is total, never throws past the projector, never silently drops (a type mismatch is a typed failure); unknown metadata keys are preserved in a `raw` map. (b) `AgentSession.state` is a binary `{open, closed}` derived from bead **status** (durable identity per ADR-0002 D2); gc's finer lifecycle string (`drained`/`detached`/…) is preserved verbatim on `SessionMetadata.lifecycleState` but not promoted to a typed enum the_grid doesn't yet own. (c) `Molecule` resolves child steps from `parent-child` edges and `Step.needs` from blocking edges between sibling steps; `isWisp = bead.ephemeral || metadata.wisp_type present`; `threadProvider` groups by the `thread:<id>` label (not `replies-to` edges).
**Why:** ADR-0002 D2 names the projections and composition rules but leaves the boundary/error shape and several mappings to implementation. **Validated against fixtures:** session (hq-session-sample ga-dvt2), message (hq-message-sample), molecule metadata + `isWisp` (hq-molecule-sample ga-dda). **NOT yet validated:** step/`needs` composition and the `wisp_type` metadata key — the pinned set contains **zero** step beads and zero molecule dependencies, so the edge direction/semantics are tested only synthetically. A follow-up capture of a real molecule+step+needs subgraph should pin these before the M2 reconciler consumes `runnableSteps`.
**Affects (if promoted):** ADR-0002 D2 (projection boundary + composition specifics); a new pinned fixture (molecule+step+needs). Code: `packages/grid_controller/lib/src/projections/`.
**Status:** pending.

