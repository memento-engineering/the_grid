---
status: accepted
date: 2026-09-03
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: the-frontier-demotes-surplus-linked-sessions
  surfaces:
    - "packages/grid_engine/lib/src/domain/linked_sessions.dart"
    - "packages/grid_engine/lib/src/domain/joined_snapshot.dart"
    - "packages/grid_engine/lib/src/bridge/station_join_bridge.dart"
    - "packages/grid_engine/lib/src/seeds/work_list.dart"
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
  obsoletes: []
  updates: ["a48-a-closed-session-is-dispositioned-done-held-voided-not-b"]
  obsoleted-by: null
  updated-by: []
  bead: tg-83k1
  legacy-id: null
---

# The frontier demotes a work bead's surplus session rows

## Context and Problem Statement

A48 ruled the multi-row pick out of scope: "the join bridge's /
`RestartReconciler`'s last-writer-wins pick among multiple sessions per work
bead is left as-is (the retire preserves the single-key invariant that makes it
moot)". The retire preserves that invariant only for rows the retire itself
creates. Twin mints, operator hand-closes and usage-window strands accumulate
rows outside it. The published row is then map-order dependent, a `done`/`held`
twin can outrank a `voided` one, and a ready approved bead sits in the frontier
forever: the engine counts it ready, the mount boundary refuses it, store-write
nudges are no-ops, and nothing says why. Observed live on 2026-09-03 across six
approved beads; the only cure was a station bounce.

## Decision Outcome

`orderLinkedSessions` + `linkedSessionVerdictOf` (`domain/linked_sessions.dart`)
are the ONE rule for a work bead's many linked rows. The join publishes
`orderLinkedSessions(...).first` and carries the rest as
`JoinedSnapshot.surplusSessionsByWorkBead`. When every linked row is a terminal,
NON-BLOCKING dead key, `WorkList` re-keys the surplus rows off the bead through
the SAME `voidRetireMetadata` payload and `voidKeyFor` shape `SessionScope`
already writes, so the join goes single-valued and A48's retire-then-mint path
runs unchanged. `done` and `held` keep blocking, and every blocking skip now
flares `work.terminalSkip` naming the bead, the session and which terminal it
was — replacing `work.held`, which covered only one of the two. `grid rework`
counts OPEN rows only; two or more open rows still refuse `session_ambiguous`.

The open-session park predicate remains exactly the one ratified by
`park-predicate-keys-on-the-open-gate`: an open `type=gate` bead whose `blocks`
metadata names the selected session proves the park, a `running` step still
refuses even when that gate exists, and `StepState.gated` remains an independent
accept arm. Session selection changes here; the predicate below it does not.

Fail-closed at the surplus: a surplus row whose recorded process fences still
probe ALIVE is not demoted and its bead does not mount, which extends A48's
liveness clause to the rows `SessionScope` never sees.

This introduces NO second admission path. The mount gate remains the canonical
pure eligibility policy; a re-minted bead re-enters the same budget-gated
pending bin and waits its turn by priority then bead id.

`RestartReconciler._projectOwnedSessions` keeps its own last-writer-wins pick:
its `incumbentAdjudication` dual-read class is defined by that incumbent being
non-deterministic, so changing it would reclassify a certified comparison.

### Consequences

* Good, because a ready bead with mint history recovers without a station
  bounce, and the trap state is never inferred from an absence.
* Good, because one ordering rule serves the join, the mount boundary and the
  operator verb, so they cannot disagree about which round is current.
* Bad, because the joined value grows a second session map, and a surplus row
  carries the un-enriched projection (the molecule/gate attachments and the
  dual-read overlay enrich only the published row).
