---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: capability-failures-carry-a-kind-and-a-per-kind-policy
  surfaces:
    - "packages/grid_engine/lib/src/sdk/capability_failure.dart"
    - "packages/grid_engine/lib/src/sdk/supervision_policy.dart"
    - "packages/grid_engine/lib/src/sdk/capability.dart"
    - "packages/grid_engine/lib/src/sdk/allocation.dart"
    - "packages/grid_engine/lib/src/circuit/failure_policy.dart"
    - "packages/grid_engine/lib/src/circuit/harness_throttle.dart"
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
    - "packages/grid_engine/lib/src/molecule/station_process_transport.dart"
    - "packages/grid_trajectory/lib/src/codec/records/step_records.dart"
  obsoletes: []
  updates:
    - a-silent-harness-exit-is-infra-not-work
    - adr-0008-authoring-sdk-and-reentrant-engine
  obsoleted-by: null
  updated-by: []
  bead: tg-b5ep
  legacy-id: null
---

# A capability failure carries a typed kind, and retry policy is declared per kind

## Context and Problem Statement

`a-silent-harness-exit-is-infra-not-work` split ONE artifact-less case out of
`work` with a transitional boolean and a wall-clock floor. Three facts still
share one arm: a capability that ran and produced a valid negative result, a
capability that produced nothing, and a capability that produced something
that violates its own declared contract. All three were supervised by the
owning circuit's single backoff and budget, so tightening the retries of one
malformed lane meant tightening every lane in the circuit.

## Decision Outcome

1. `StepOutcome` stays `{Ok, Failed}`. The failure arm carries an engine-owned
   `CapabilityFailureKind` — `work`, `noResult`, `invalidResult` — replacing the
   transitional boolean. A capability may THROW a `CapabilityFailure` carrying
   only that kind and a reason bounded at construction; an untyped throw stays
   `work`. `storeUnavailable` remains a host observation and is never emitted
   by a capability.
2. The host maps the reported kind plus its OWN evidence into the durable
   class. A fast `noResult` still specializes to `infra` on the same 30-second
   floor. Only `work` counts as substantive failed work.
3. Retry policy is DECLARED separately from the error, by
   `Capability.supervisionPolicy(StepArgs)`, per kind. The failure object
   carries no policy hint, so nothing an agent wrote can steer supervision.
   Because the declaration reads the step's params, one capability declares
   different policies per seat. The declaration may only TIGHTEN the budget: the
   pure frontier predicate reads `Circuit.maxRestarts`, so a larger declared
   budget is clamped.
4. Exhaustion of a NON-RESULT kind parks the node at a gate from the failing
   leaf host, generalizing that entry's clause 3 from `infra` to every kind
   that produced nothing gradeable. `work` keeps ADR-0008 Decision 7's
   latch-and-escalate. This is the amendment: that entry scoped the gate
   exception to `infra` alone.

### Consequences

* Good, because a malformed verdict is retried on its own schedule instead of
  being graded as a substantive F, and a lane can be tightened without
  tightening its siblings.
* Good, because no failure that produced nothing gradeable can end its budget
  without a gate a governor sees.
* Bad, because one more class now parks where `work` latches, so a reader of
  the supervision path must know two exceptions rather than one.
* Bad, because a declared budget larger than the circuit's is silently clamped
  rather than refused; the clamp is documented on the field and pinned by test.
