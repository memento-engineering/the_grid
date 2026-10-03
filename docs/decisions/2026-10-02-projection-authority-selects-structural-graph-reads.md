---
status: accepted
date: 2026-10-02
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: projection-authority-selects-structural-graph-reads
  surfaces:
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
    - "packages/grid_engine/lib/src/circuit/session_scope.dart"
    - "packages/grid_engine/lib/src/domain/projection_graph_read.dart"
  obsoletes: []
  updates:
    - "trajectory-decision-bearing-awaits-are-cut-only"
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Projection authority selects structural graph reads

## Context and Problem Statement

`trajectory-decision-bearing-awaits-are-cut-only` requires the trajectory
discipline switch to remain inside `TrajectoryHarness`. It says neither
`capability_host.dart` nor `session_scope.dart` receives the discipline or
branches on it, so shadow and cut differ in append acknowledgement policy
without duplicating engine control flow.

Stage 2 must move frontier and status reads from legacy graph beads to P2,
projected semantic edges, and projected attempt leases before those legacy
writers retire. During shadow both sources exist, while cut makes the
projection graph authoritative. The engine therefore needs an immutable
read-source signal even though it must not receive or interpret the trajectory
discipline.

## Decision Outcome

`ProjectionGraphRead.isAuthoritative` is the structural graph read-source
selector. It is distinct from `TrajectoryDiscipline`: assembly resolves the
G2 posture once and publishes an immutable projection graph view, while
`SessionScope` selects projected structural depth, spent-result count,
validation targets, blockers, and lease breadcrumbs only when that view is
authoritative. Otherwise it retains every legacy graph source.

This is a narrow carve-out from the earlier entry's statement that
`session_scope.dart` does not branch on the discipline. `SessionScope` may
branch on projection authority to select structural read data; it still never
receives `TrajectoryDiscipline`, never changes recorder await behavior, and
keeps one recorder call at each decision-bearing append site.

`CapabilityHost` receives neither the discipline nor the authority flag. It
consumes the exact projected lease value already selected into
`InheritedCircuit`, including an authoritative absence, and never falls back
to legacy bead metadata. Its recorder call and await/breaker behavior remain
unchanged.

### Consequences

* Good, because the Stage 2 read migration can complete before legacy graph
  writers retire without moving the cut/shadow append policy into the engine.
* Good, because shadow retains the legacy graph as an observable oracle while
  cut has one structural read source.
* Bad, because `SessionScope` now has a second assembly-resolved policy bit to
  honor, so authority propagation requires failure-sensitive bridge and scope
  tests.
