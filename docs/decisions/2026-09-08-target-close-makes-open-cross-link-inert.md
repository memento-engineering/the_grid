---
status: accepted
date: 2026-09-08
decision-makers: ["Nico Spencer"]
consulted: ["governor (agent seat)"]
informed: []
register:
  spec: 1
  slug: target-close-makes-open-cross-link-inert
  surfaces:
    - "packages/grid_engine/lib/src/bridge/block_guard.dart"
    - "packages/grid_engine/lib/src/domain/cross_link.dart"
    - "packages/grid_engine/lib/src/bridge/station_join_bridge.dart"
    - "packages/grid_cli/lib/src/link_command.dart"
  obsoletes: []
  updates:
    - "a55-where-the-state-store-s-link-set-enters-the-pipeline-and"
  obsoleted-by: null
  updated-by: []
  bead: tg-93u9
  legacy-id: null
---

# A closed target makes an open cross-link inert

## Context and Problem Statement

The `pow-q7t5 / tg-bqed` incident on 2026-09-05 exposed a lifecycle transition
that the engine enforced but did not surface: a consumer mounted after the
target bead closed even though the state store's link bead remained open. The
operator discovered only later that the consumer had built against the old
release. Governor memory incorrectly said the link bead's close controlled the
transition, but the implementation and accepted A55 decision say otherwise.

A55 deliberately does not auto-close a link when its `to` target closes. The
closed target already unblocks `from` on the next join, and the still-open link
is a stale receipt rather than an active edge. Reversing that rule here would
make link-bead closure control admission and would contradict A55. Teaching the
pure guard about releases would instead add version-aware I/O to the shared
enforcement function.

## Decision Outcome

Reaffirm A55: an open link blocks only while its target bead is open or
unobserved. When the joined work snapshot observes the target closed, the edge
becomes inert without auto-closing its link bead. The join emits one
`crossLink.targetClosed` LOUD line per `(link bead, target)` pair for the life
of that bridge, and `grid link ls` marks the open receipt `INERT (target
closed)` in human and JSON output. Both the refusal text and link-command help
state the rule directly: the edge lifts when the TARGET bead closes, not when
the link bead closes.

`applyBlockGuard` remains the one pure enforcement implementation, with its
blocking decisions unchanged. The new bridge-owned set remembers only whether
an emit-only lifecycle line has already been sent; it is not another admission
source under `admission-authority-boundary` and does not enter
`JoinedSnapshot`. In particular, it is distinct from the session mechanism
ratified by
`the-frontier-demotes-surplus-linked-sessions`: `orderLinkedSessions` still
selects the one published session row and
`JoinedSnapshot.surplusSessionsByWorkBead` still carries the rest. Cross-link
observation neither selects nor demotes a session, and the mount gate remains
the canonical pure eligibility policy.

Release-keyed blocking is outside this decision. If added, it is an
operator-authored condition of the link verb, not network or version I/O in
the guard.

### Consequences

- Good, because the operator receives an immediate, identifier-complete signal
  when an authored edge becomes inert instead of inferring it after a wrong
  build.
- Good, because a resident bridge reports a link-target pair only once while a
  metadata retarget is observable as a new pair.
- Good, because human and JSON link listings expose the same state using
  endpoint status the verb already reads.
- Bad, because the open link receipt remains stale until an operator closes it,
  and after the once-only line scrolls past the operator must consult the link
  listing to rediscover it.
