---
status: accepted
date: 2026-09-05
decision-makers: [operator, specify]
consulted: []
informed: []
register:
  spec: 1
  slug: declared-process-session-non-results-are-infra
  surfaces:
    - "packages/grid_engine/lib/src/sdk/process_session.dart"
    - "packages/grid_engine/lib/src/sdk/allocation.dart"
    - "packages/grid_engine/lib/src/circuit/failure_policy.dart"
    - "packages/grid_engine/lib/src/circuit/capability_host.dart"
  obsoletes: []
  updates:
    - a-silent-harness-exit-is-infra-not-work
    - capability-failures-carry-a-kind-and-a-per-kind-policy
  obsoleted-by: null
  updated-by: []
  bead: tg-bqed
  legacy-id: null
---

# Declared process-session non-results are infrastructure failures

## Context and Problem Statement

A protocol adapter can recognize that a provider completed a turn without a
usable result, but `ProcessSessionUpdate.failed` previously carried only a
reason. The direct allocation channel consequently converted every session
failure to an untyped `AllocationFailed`, whose historical default is a
substantive `work` failure.

The host could infer infrastructure failure only from a fast, artifact-less
exit under `kHarnessSilenceFloor`. A provider refusal delivered after a full
turn is explicit non-result evidence, yet its elapsed-time shape prevents that
inference and routes it as ordinary work.

## Decision Outcome

`ProcessSessionUpdate.failed` may declare the existing
`CapabilityFailureKind`. Direct allocation preserves whether the protocol
supplied that kind. An absent kind and an explicit `work` kind retain the
historical untyped-work behavior; `invalidResult` remains `invalidResult`.

A protocol session’s explicit `noResult` kind is engine-owned declaration evidence and resolves to `infra` without consulting the elapsed-time floor.

An undeclared `noResult` still uses `isHarnessSilence` and
`kHarnessSilenceFloor`, preserving the existing inference for artifact-less
fast exits. All resulting classes flow through the existing
`resolveRetryPolicy`, `defaultBackoffFor`, and `defaultExhaustionFor` path.

No reason-string parser, second failure vocabulary, retry loop, or gate writer
is introduced.

### Consequences

* Good, because protocol adapters can report a recognized non-result without
  coupling the engine to provider-specific diagnostic text.
* Good, because declared non-results reuse the existing infrastructure backoff
  and exhaustion gate while inferred silence keeps its existing time floor.
* Bad, because allocation reports now retain one provenance bit in addition to
  the failure kind so the host can distinguish declarations from inference.
