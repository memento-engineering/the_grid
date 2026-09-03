---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: a-silent-harness-exit-is-infra-not-work
  surfaces:
    - "packages/grid_engine/lib/src/circuit/harness_throttle.dart"
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
    - "packages/grid_engine/lib/src/sdk/allocation.dart"
    - "packages/grid_engine/lib/src/sdk/capability.dart"
    - "packages/grid_trajectory/lib/src/codec/records/step_records.dart"
    - "packages/grid_runtime/lib/src/runtime/runtime_provider.dart"
  obsoletes: []
  updates:
    - adr-0008-authoring-sdk-and-reentrant-engine
  obsoleted-by: null
  updated-by: []
  bead: tg-ilm9
  legacy-id: null
---

# A silent harness exit is infra, and its exhaustion gates the round instead of closing the session

## Context and Problem Statement

Twice on 2026-09-03 the shared model subscription window was exhausted. Every
running model step exited within ten seconds with no artifact and a zero-byte
usage-telemetry file, and each was recorded `failure_class: work` with
`cooldown_until: +10s`. The rounds sat dead for 33 minutes and 5.5 hours until a
human read the trajectory. `work` means "the agent tried and produced a bad
result"; an artifact-less exit across every concurrent step in under ten
seconds is an environment refusal.

ADR-0008 Decision 7 states that exhaustion escalates to a human/operator, and
its D-5 amendment names `SessionScope` as the escalator, which marks the session
bead and closes it. A closed session cannot be reworked, and rework is the right
exit once the model-usage window resets.

## Decision Outcome

1. The engine classifies a failure as `StepFailureClass.infra` when the effect
   reports a non-result and does so under a 30-second wall-clock floor. Both
   facts are engine-owned; neither is parsed from a reason string. Either alone
   stays `work`, so a critic that ran and graded `F` is unchanged.
2. An `infra` failure backs off on `Backoff.harnessThrottle` (+5, +15, +30
   minutes) rather than the circuit's seconds-scale schedule, because a shared
   usage window resets on a wall-clock boundary.
3. At restart-budget exhaustion an `infra` failure parks the node at a gate
   from the failing leaf host, through the same `persistRaisedEscalation`
   primitive used by a declined route. This amends ADR-0008 Decision 7's
   escalation locus for this class only: an environment refusal is transient,
   and its round must survive for rework. Every other failure class latches
   `failed` and escalates as before.
4. `RuntimeProvider.exitOutputOf` retains the bounded head of an exited
   session's transcript beside its retained terminal, with `terminalOf`'s
   release contract. This makes the harness's refusal line available to the
   flare, failure reason, and gate.

### Consequences

* Good, because a throttled round retries across the window reset and then
  lands at a gate a governor sees instead of dying silently.
* Good, because the harness's own refusal line becomes durable evidence in the
  flare and persisted failure reason.
* Bad, because the classification is a heuristic over two engine-owned facts:
  a capability that genuinely fails to write its artifact within 30 seconds is
  retried on a five-minute schedule before it gates.
* Bad, because one failure class now parks where the others latch, so a reader
  of the supervision path must know the exception.
