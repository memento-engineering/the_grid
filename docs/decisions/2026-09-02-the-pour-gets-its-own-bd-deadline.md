---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: the-pour-gets-its-own-bd-deadline
  surfaces:
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/beads_dart/test/support/fake_bd_runner.dart"
    - "packages/beads_dart/test/services/bd_cli_service_actuator_test.dart"
  obsoletes: []
  updates:
    - adr-0001-technical-foundations
  obsoleted-by: null
  updated-by: []
  bead: tg-336w
  legacy-id: null
---

# The molecule pour gets its own bd deadline

## Context and Problem Statement

ADR-0001 Decision 4 (Accepted 2026-06-11, Nico) fixes one deadline for the
whole bd surface: "Mutations and ready-work: always `bd` CLI
(`BD_JSON_ENVELOPE=1`, `--actor grid-controller`, 15s timeout with kill, max 4
concurrent)." `ProcessBdRunner.defaultTimeout` implements it literally, and
`BdCliService` never overrides it.

Measured on the live tranquility store 2026-09-03 (tg-336w receipts): a
molecule pour (`bd create --graph`) is not a peer of a single-row update. It
pays bd's per-edge dependency-cycle check, whose reachability CTE joins each
recursion hop against a derived, un-indexed UNION of `dependencies` and
`wisp_dependencies`, so the cost is (blocking rows in the union) x (chain depth
from the edge's target): 109.6ms for one deep edge versus 2.8ms against a
single indexed table. A 28-step molecule chains its steps, so a pour costs
~0.05s per node plus ~130ms per blocking edge. Proxy-side pour durations:
median 9.3s over 46 pours (boot11); 14.9s and 14.7s on the two boot12 pours
that died at the deadline. The failures are the tail of one distribution, not a
second mechanism — the pour is SLOW, not blocked.

A60 (2026-09-01) scoped the fork cycle deliberately and recorded "No timeout
increase, dependency-table pruning, terminal-bead deletion, cross-process lock,
admission gate, upstream issue, or upstream pull request is introduced." That
sentence bounded A60's own change; the measurement that justifies a deadline
landed after it.

## Considered Options

* Raise `ProcessBdRunner.defaultTimeout` for every bd call.
* Retry a timed-out pour.
* Give `applyGraph` its own named deadline and leave the default alone.

## Decision Outcome

The third. `BdCliService.pourTimeout = Duration(seconds: 60)` — 6x the measured
live median — is passed explicitly by `applyGraph` and by nothing else; every
other bd call keeps `ProcessBdRunner.defaultTimeout` (15s), so ADR-0001 D4
holds unchanged for the whole surface but this one named, measured exception.
The exception is pinned by a test that asserts BOTH sides.

Raising the global default was rejected: it would hide a genuinely wedged
single-row update behind a minute of silence, which is the failure ADR-0001 D4's
kill exists to prevent. Retry was rejected because the failure is not transient
— a retry re-pays the whole ~10s — and because it would double the window in
which a pour holds the store-wide pour serialization in
`StationBeadWriter._serializedStorePour`.

The pour stays ATOMIC. `bd create --graph` is one transaction and one
`DOLT_COMMIT`; killing the process rolls it back, so a deadline still yields
zero rows and the existing partial-mint disposition is untouched.

This deadline treats the SYMPTOM. The cause is the query shape inside bd, whose
fix lands on the fork lineage A60 selected (`nicholasspencer/beads`,
`grid-v1.0.5-graph-apply-parent-cycle-skip.1`) and never upstream; tg-336w files
that follow-up bead citing this entry.

### Consequences

* Good, because the measured 9.3s-median pour stops competing with a 15s budget
  sized for sub-second calls, and the two boot12 deadline failures fall inside
  the new budget with 4x headroom.
* Good, because the exception is named and tested rather than a global loosening
  — a future reader sees exactly one call with a non-default deadline and why.
* Bad, because a genuinely wedged pour now holds a `ProcessBdRunner` concurrency
  permit and the store-wide pour serialization for up to 60s instead of 15s.
  Accepted: the pour is already serialized store-wide, and tg-kuux owns the
  flare that makes a non-landing pour audible rather than silent.
* Bad, because it does not shrink the per-edge cost, so a molecule roughly 3x
  today's 28 steps would exhaust 60s too. The fork-lineage query-shape fix and
  tg-ehht's step-graph reaping are the durable cures.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-336w).
