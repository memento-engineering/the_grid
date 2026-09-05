---
status: accepted
date: 2026-09-04
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: admission-authority-in-process-cut
  surfaces:
    - "packages/grid_engine/lib/src/kernel/station_admission_authority.dart"
    - "packages/grid_engine/lib/src/kernel/station_services.dart"
    - "packages/grid_engine/lib/src/seeds/work_list.dart"
    - "packages/grid_engine/lib/src/circuit/session_scope.dart"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
  obsoletes: []
  updates: ["the_grid#admission-authority-boundary"]
  obsoleted-by: null
  updated-by: []
  bead: tg-1u3c
  legacy-id: null
---

# Admission authority lands as an in-process ownership cut

## Context and Problem Statement

The admission-authority boundary selected option B: the tree remains the
execution surface, while one owned authority answers whether an attempt may
start and owns its durable transitions. The trajectory is armed at Stage 1 and
the quiesced Stage 3 record cut has not begun, so moving the ownership and
moving the durable medium cannot be the same deployment.

## Decision Outcome

`StationServices` constructs one `StationAdmissionAuthority` for the station.
Every substation `WorkList` asks that object with a settled `JoinedSnapshot`,
its `SubstationConfig`, its vended `ServiceBundle`, and structural candidates.
The authority reserves station and substation capacity synchronously, orders
pending work by ascending priority then bead id, and evaluates the existing
composed mount-eligibility predicate and trust guard. `SessionScope` asks the
same object for attempt transitions while retaining tree-owned circuit and
step execution.

This cut keeps the existing bead-backed `recordMountAttempt` representation,
the `_mountedIds` membership and every refusal/recheck/latch name as private
in-process authority state. It composes the existing `voidKeyFor` and
`voidRetireMetadata` shape, including `grid.voided_reason`, and makes a raw
post-session mint timeout void and close that session before capacity is
released. No admission trajectory record is appended by this cut.

The quiesced Stage 3 switch belongs exclusively to tg-lt0s: wiring the existing
`AdmissionGrantIssued`, `AdmissionGrantConsumed`, `AdmissionGrantClosed`,
`AdmissionRefused`, and `AdmissionRestored` codec; grant identity and admission
family trajectory appends; fencing tokens; leases; expiry; authority-owned
eligibility ticks; session slimming; and retirement of mount-attempt beads,
`_mountedIds`, and the latch sets. Those changes must not land while Stage 2
has not started.

### Consequences

* A same-flush boot burst cannot exceed the station ceiling because every
  pending mount consumes an in-process reservation before writer I/O starts.
* A work bead with one live durable session is adopted; two live rows refuse
  fail-closed before any new session is created.
* Local callbacks and timers remain implementation details. Admission request
  and result values expose no tree context, mutable collection, timer,
  lifecycle state, or capacity accessor.
* This is one-process authority only. Federation semantics remain deferred to
  the parent decision's later deployment.

## Decision Alignment

This cut explicitly retires A43's ambient-absence branch, where
`stationCap == null` (no ambient `StationServices`) meant only the
substation-local cap applied. A `WorkList` can now mount only when composed
with the station-owned `StationServices`; offline compositions provide the
same fake-backed ambient instead of falling back to local admission logic.
This preserves A43's substation and station ceilings while replacing its
same-flush declare-and-check approximation with synchronous reservations.

The `dry-bd-seam-mints-under-the-owning-prefix` decision remains unchanged.
`StationWorkRuntime` continues to use the existing per-substation
`NoOpBdRunner` seams, whose returned ids follow the owning prefix. Moving the
chokepoint's durable attempt writes behind `StationAdmissionAuthority` does
not create or migrate a second dry-run id discipline; the seam's id shape
follows that chokepoint unchanged.

## Review log

* 2026-09-04 — accepted by **nico** + **agent** as the in-process implementation amendment.
