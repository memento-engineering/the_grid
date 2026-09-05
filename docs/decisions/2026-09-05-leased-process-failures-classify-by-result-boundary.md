---
status: accepted
date: 2026-09-05
decision-makers: [operator, specify]
consulted: []
informed: []
register:
  spec: 1
  slug: leased-process-failures-classify-by-result-boundary
  surfaces:
    - "packages/grid_engine/lib/src/molecule/station_process_transport.dart"
  obsoletes: []
  updates:
    - capability-failures-carry-a-kind-and-a-per-kind-policy
  obsoleted-by: null
  updated-by: []
  bead: tg-cg94
  legacy-id: null
---

# Leased process failures classify by the result boundary

## Context and Problem Statement

`capability-failures-carry-a-kind-and-a-per-kind-policy` made exhaustion of a
non-result failure park at a gate, while preserving `Failed(reason)` and
untyped capability throws as substantive `work` failures by default. The live
leased-process dispatcher still mapped both a failed process signal and an
exception reading a completed process's result through those defaults. Neither
failure could therefore reach the host-owned non-result exhaustion policy.

The leased dispatcher is a narrower boundary than a capability body: it knows
whether the process produced a usable terminal result. That evidence is enough
to classify the failure without changing the capability API or the direct
`ProcessAllocation` path.

## Decision Outcome

At the live leased-process `stationProcessDispatcher` boundary:

1. `StepSignal.failed` means the process produced no usable result and becomes
   `Failed.noResult('the spawned process failed')`.
2. An untyped exception from `ProcessCapability.result()` means the completed
   process produced an invalid result and becomes
   `Failed.invalidResult('result threw: $e')`.
3. Both cases retain their existing diagnostic strings. A named
   `CapabilityFailure` retains its declared kind.
4. Direct `ProcessAllocation` behavior is unchanged: an untyped result
   exception remains `work`. The default `Failed(reason)` constructor also
   remains a substantive `work` failure.

These classifications deliberately activate the existing host-owned retry and
`parkAtGate` exhaustion policy. They do not add a second gate or escalation
path at the transport boundary.

### Consequences

* Good, because an exhausted leased process that produced no usable result is
  durably parked and observable through the existing gate and flare path.
* Good, because malformed leased results follow the same non-result recovery
  policy without changing direct allocations or capability-authored failures.
* Bad, because the same untyped `result()` exception has a different kind at
  the leased boundary than it does through a direct `ProcessAllocation`; the
  distinction is intentional and must remain pinned by tests.
