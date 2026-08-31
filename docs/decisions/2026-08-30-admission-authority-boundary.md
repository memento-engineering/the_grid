---
status: accepted
date: 2026-08-30
decision-makers: [nico, agent]
consulted: [external-architecture-auditor]
informed: []
register:
  spec: 1
  slug: admission-authority-boundary
  surfaces:
    - "packages/grid_engine/lib/src/bridge/**"
    - "packages/grid_engine/lib/src/kernel/**"
    - "packages/grid_sdk/lib/src/work/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-y4fd
  legacy-id: null
---

# Admission and durable transitions consult one owned authority; the tree remains the execution surface

## Context and Problem Statement

The 2026-08 external orchestrator architecture review found that "may this
attempt start now?" has no single owner — `WorkList` admission over observed
snapshots, an inert cross-store dependency guard (tg-mspw), unfenced lock
ownership (tg-o2fy), and a flush-recovery fix living only in dead code
(tg-um8k). Its proposed remedy was a durable `StationScheduler` with the
composition tree demoted to a projector — a rebuild of the engine and a vote
against the stack's core bet (orchestration as a reconciled tree, circuits
and steps mounted as seeds). The governor's response identified three
coherent end-states; the auditor's follow-up amended its recommendation to
option B; the operator ratified it 2026-08-30.

## Considered Options

* **A — tree-authoritative, holes patched.** Land the P0/P1 fixes locally;
  keep admission distributed.
* **B — tree consults one owned authority.** Admission and durable
  transitions move behind a single `StationAdmissionAuthority`; seeds remain
  the execution surface.
* **C — full projector pivot.** Tree renders; a durable workflow engine owns
  execution.

## Decision Outcome

**Option B.** One `StationAdmissionAuthority` answers whether a particular
attempt may start, and issues its reservation and fence. Circuits and steps
continue to execute as mounted seeds. Concretely:

* the committee produces durable validation evidence and grades;
* the mount gate remains the canonical *pure eligibility policy* over bead
  state — the authority evaluates it, absorbs nothing, replaces nothing;
* the authority evaluates that policy against a **versioned snapshot** and
  emits an **attempt grant** recording its decision basis (bead revision,
  plan/approval evidence, dependency revisions) plus reservation id, fencing
  token, authority identity, and expiry — a stale basis refuses or reissues;
* the tree consumes the grant and remains the execution surface;
* durable state changes ride a fenced transition service rather than being
  minted independently by branches.

**Federation contract (ratified with this decision): owner-scoped and
hierarchical.** One admission authority per work store, owned by the store's
owner; stations acquire leased grants. The contract is an idempotent
admission request and a leased grant carrying `authorityId`,
`reservationId`, `fencingToken`, expiry, owner/member identity, and
decision-basis revisions. Local maps, callbacks, timers, and `TreeContext`
are implementation details and never enter the contract. Federated semantics
are defined now and deployed in-process first.

A is rejected because it leaves in place the property that produced this bug
class (edge-triggered, eventually-consistent admission), documented across
operations as frozen projections, stranded boards, and a stall alarm riding
the flush it supervises. C is rejected *for now* as premature: its remaining
delta over B buys exactly-once execution semantics not needed at current
concurrency, at the price of the product thesis. B is the common prefix of
both a permanently tree-authoritative system and a later federated scheduler.

### Consequences

* Good, because tg-wu5a (first implementation child), tg-zfek, tg-8kye,
  tg-718q/pow-gc1, and tg-nidl converge on one boundary instead of unrelated
  local fixes.
* Good, because the one-grid-per-machine constraint dissolves by design once
  owner-scoped authorities exist — the double-mount failure mode is an
  admission race between unfenced peers.
* Bad, because converted admission paths must thread grant identity through
  layers that today pass booleans.
* Bad, because until every mint site rides the fenced transition service,
  the system runs with two write disciplines.

### Confirmation

The falsifiable target ratified with this decision: option B must sustain
8 concurrent attempts across 7 substations locally, and 3 stations × 8
attempts federated, through 100,000 attempt transitions plus a 72-hour
fault-injected soak — with zero capacity overshoot, zero duplicate durable
attempts, zero unresolved-dependency admissions, zero silently stranded
work, zero surviving descendant processes; every attempt reaching an
explicit terminal/lost state; bounded recovery; convergent replay; and a
correlated durable event for every decision. **Tripwire:** if passing
requires reconstructing `WorkList`/`SessionScope` state outside the tree,
option B has become an accidental option C and this decision reopens.

## Review log

* 2026-08-30 — decided by **nico** + **agent** (governor seat) in direct-mode design; recorded accepted, bead tg-y4fd closed binding-on-write.
