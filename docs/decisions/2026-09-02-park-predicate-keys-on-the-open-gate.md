---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: []
register:
  spec: 1
  slug: park-predicate-keys-on-the-open-gate
  surfaces:
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
    - "packages/grid_sdk/test/station_command_handler_test.dart"
    - "docs/OPERATIONS.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-xpgx
  legacy-id: null
---

# `grid rework`'s park predicate keys on the open gate naming the session, never on cursor absence

## Context and Problem Statement

`SessionScope._parkFailedMoleculePour` parks a failed molecule pour by minting
an open gate bead whose `blocks` names the session and whose `node` is the bare
work-bead id. `StationCommandHandler._rework` decided "is this session parked?"
from the SESSION's projected cursor, accepting the pour shape only when
`cursor.isEmpty` held.

That conjunct describes one of two pour shapes. `createMolecule` pours the whole
graph in one `applyGraph` call and only then stamps crumbs one `bd update` at a
time, so a pour that dies in the stamping loop leaves every molecule and step
bead PERSISTED. Their projected cursor is full of `pending` nodes, none `gated`,
so the session was refused as "open and not parked at a gate" while an open gate
named it. Observed live 2026-08-25 (5 molecules, 28 steps): the session was
simultaneously not driving and not reworkable, and the only exit was
hand-closing the session and the gate with `bd` — hand-editing lifecycle beads
to escape a state the operator tooling created, which is what the single write
chokepoint exists to prevent.

## Decision Outcome

The park predicate keys on the EXISTENCE of an open `type=gate` bead whose
`blocks` metadata equals the session id. Cursor state is not consulted to prove
a park. The gate mint is the invariant that establishes the park, so the gate is
the evidence — the same rule A48 already ratified on the disposition axis ("the
MARKER, not the cursor, is the `done` evidence. Cursor shape alone cannot carry
it"), applied to the park axis.

The widening is bounded by two clauses that stay exactly as they were. A
`running` step still REFUSES, gate or no gate: a settled park has nothing
running by construction, so a live runner beside an open gate means the retire
would race it. And `StepState.gated` remains an independent accept arm, so a
gated step with no gate bead is accepted as before. Net: exactly one input flips
from refuse to accept — an open gate naming the session, a non-empty cursor,
nothing running, nothing gated.

### Consequences

* Good, because both pour shapes and any future one reach the same sanctioned
  exit: `grid rework` per OPERATIONS §2.3, with no hand-closed lifecycle bead.
* Good, because the retire's existing `reapMolecule` call now actually collects
  a partial pour's persisted graph (in A58's reverse-topological order), so the
  orphan molecule and step beads a partial pour leaves are cleaned by the
  operator's normal exit rather than accumulating.
* Neutral, because the refusal code and message (`session_not_parked`) and the
  committee park's behaviour are unchanged.
* Bad, because a stale open gate left against a still-open, idle session would
  now admit a retire that the `cursor.isEmpty` conjunct happened to block. The
  `running` clause is the guard that keeps this from touching a live round, and
  OPERATIONS §2.3 already treats a stale open gate as a leak to sweep.

## Not this

Pour transactionality and pour resumability are explicitly NOT decided here. The
2026-08-25 repro's 15s `BdTimeoutException` came from an EMBEDDED dolt station
store, an unsupported station-store posture, so it is not evidence for a
rollback-or-resume redesign of the pour engine (governor ruling, tg-xpgx). The
tg-ehht never-reaped-bloat diagnosis is a third, distinct cause and is not
applied here either.
