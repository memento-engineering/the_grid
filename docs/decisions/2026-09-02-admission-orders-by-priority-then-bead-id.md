---
status: accepted
date: 2026-09-02
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: admission-orders-by-priority-then-bead-id
  surfaces:
    - "packages/grid_engine/lib/src/seeds/work_list.dart"
    - "packages/grid_engine/test/track_a_concurrency_governor_test.dart"
  obsoletes: []
  updates: ["a43-the-concurrency-governor-where-the-station-default-lives"]
  obsoleted-by: null
  updated-by: []
  bead: tg-lohr
  legacy-id: null
---

# Admission orders by priority, then bead id

## Context and Problem Statement

A43 (accepted 2026-07-03) recorded, as one of three implementer shape choices:
"admission is deterministic lowest-bead-id-first". A48 (ratified by Nico
2026-07-12) preserved it verbatim while changing only the pending bin's element
type.

Bead ids carry a random-ish suffix, so id-first order is arbitrary in every
respect except reproducibility. `Bead.priority` therefore had no effect at the
mount boundary: a P0 filed as `tg-zzzz` lost its slot to a P4 filed as
`tg-aaaa` on every reconcile until a slot happened to free with nothing
alphabetically earlier pending.

The operator complaint behind tg-lohr (2026-09-02) is the cost: the grid can
express within-store blocking (`bd dep add`) and cross-store blocking (link
beads, shipped as tg-hof7), but not ORDERING WITHOUT BLOCKING. The absence
forces either a semantically wrong hard blocker — which strands the dependent
if the blocker stalls or is closed stale — or an ordering held in an operator's
head and hand-approved in sequence.

## Considered Options

* Keep lowest-bead-id-first and express ordering as hard blockers.
* Add a new operator-facing rung (a mount-order field or flag) beside priority.
* Order the pending bin by priority, keeping bead id as the tie-break within a
  priority.

## Decision Outcome

The third. Among "pending" candidates the governor now admits
highest-priority-first — bd priority is ascending-urgent, so a plain ascending
`compareTo` on the int, matching beads_dart's own `ORDER BY priority ASC` — and
falls back to lowest bead id WITHIN one priority.

What A43 fixed is otherwise PRESERVED, clause by clause: the pending bin is
still the only bin the budget gates; a bead carrying a live session is still
NEVER evicted for budget reasons, and a higher-priority bead waits for a
natural slot rather than displacing a live one; positive-terminal-only unmount
stays the only unmount trigger; the station-wide read stays the same
declare-and-check approximation over `JoinedSnapshot.sessionsByWorkBead`; the
`min(substationSlots, stationSlots)` arithmetic and the one-flare-per-throttled
build contract are unchanged. Only the ORDER within the pending bin moves, and
A43's stated purpose for that order — reproducibility across reconciles — is
carried by the id tie-break.

The second option is rejected because priority is already on every bead and
already the field operators reach for; a second rung would need its own
authoring verb, its own drift, and its own answer for what happens when the two
disagree.

Ordering stays PER-SUBSTATION: each substation's `WorkList` sorts only its own
pending bin, so this decision introduces no cross-substation fairness or
weighting.

## Review log

* 2026-09-02 — directed by the operator in tg-lohr's own text (bead approved
  `grid.approved` 2026-09-03) and recorded by the specify stage of tg-lohr.
