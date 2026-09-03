---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: watch-until-predicates-are-transitions
  surfaces:
    - "packages/grid_cli/lib/src/watch_predicate.dart"
    - "packages/grid_cli/lib/src/watch_command.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-u5xt
  legacy-id: null
---

# `grid watch --until` predicates are TRANSITIONS over the typed event stream, never standing states

## Context and Problem Statement

`--until` blocks an operator seat on a station condition instead of polling.
Two readings of "the condition holds" were available: a STANDING STATE read
against the graph at attach time, or a TRANSITION observed in the event stream
the watch already decodes. The two disagree for four of the five predicates in
the closed set.

## Decision Outcome

Every `--until` predicate is a TRANSITION, resolved only from the
`GraphEvent`s the watch decodes. `GraphEvent.snapshotInitialized` "carries
counts only — it does not enumerate a `BeadCreated` per existing bead", so a
bead-shaped standing state is not readable from this stream at all; and a
standing-state `gate-closed` or `session-terminal` would fire on any
historical closed gate or session in the graph, which answers nothing. The one
baseline fact the stream DOES carry is the ready count, and `ready-count=0`
honours it: a baseline of zero satisfies immediately.

Two sub-decisions ride the same rule:

* `bead-status=<status>` refuses a status outside `BeadStatus.builtIns` at
  PARSE time. A custom workspace status still decodes on the read path — the
  extension-type model is untouched — but a typo passed to `--until` would
  otherwise run to the deadline and exit 2, the "gave up" answer the exit
  contract exists to distinguish from a real one.
* `gate-open`/`gate-closed` are the session-agnostic form of the park
  predicate: an OPEN `type=gate` bead whose `blocks` metadata NAMES a session,
  quantified existentially instead of against one session id. A hard delete of
  an open gate satisfies `gate-closed`, because existence is what the park
  decision makes the evidence.

### Consequences

* Good, because an operator arms the watch, triggers the action, and blocks —
  the ordering the flag is for, with no ambiguity about pre-existing state.
* Good, because the five predicates need no read path the watch does not
  already have: no new door, no change to `/stream`.
* Bad, because a condition that ALREADY holds when the watch attaches is not
  detected and the invocation runs to its deadline. An operator checks a
  standing state with `bd`/`grid status` and uses `--until` for the wait.

## Not this

A liveness predicate (`station-down`) is explicitly NOT decided here: no
liveness signal exists in the `GraphEvent` union, and inventing a channel to
carry one would contradict this change's own non-goals. A bead-id-scoped
`bead-status=<id>=<status>` is likewise outside the closed set.
