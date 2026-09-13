---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: ["governor (agent seat)"]
informed: []
register:
  spec: 1
  slug: link-beads-retire-in-one-hard-cut
  surfaces:
    - "packages/grid_cli/lib/src/link_command.dart"
    - "packages/grid_engine/lib/src/bridge/station_join_bridge.dart"
    - "packages/grid_engine/lib/src/domain/mount_eligibility.dart"
    - "packages/grid_engine/lib/src/domain/joined_snapshot.dart"
    - "packages/grid_engine/lib/src/domain/eligibility_basis_revision.dart"
    - "packages/grid_engine/lib/src/domain/bd_type_discovery.dart"
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
    - "packages/grid_sdk/lib/src/command/bead_board.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
  obsoletes:
    - "target-close-makes-open-cross-link-inert"
  updates:
    - "the-grid-is-a-beads-controller"
  obsoleted-by: null
  updated-by: []
  bead: tg-6t0h
  legacy-id: null
---

# Link beads retire in one pass, with no coexistence window

## Context and Problem Statement

`capability-edges-are-bd-native-and-link-is-sugar` moved cross-store blocking
onto bd's native `external:<project>:<capability>` dependency rows and left the
old reader running beside it, because authored link beads still existed and
still carried real edges. Two readers for one fact is precisely the condition
this register has already called a defect, so it was accepted only as a window
that a named follow-on would close.

MEASURED 2026-09-13 on the `tranquility` state store: 107 OPEN link beads and 4
closed. Every open one is `<from> blocked by <to>` across two armed
substations. That is a bounded, uniform set — small enough to convert in one
pass, and uniform enough that the conversion needs no judgement per row.

The alternative on the table was a coexistence window: keep both readers, let
new edges land as rows, let old link beads age out as their targets closed.
Nico's ruling closed it: "We're not doing this dumb ADR dance again. No one is
using these tools/packages except us and we keep slowing ourselves down to
migrate when we should just be hard cutting and moving forward."

## Decision Outcome

**HARD CUT, one landing.** A one-shot operator verb converts every authored
link bead, and the same change deletes the reader. There is no release in which
both mechanisms are live.

**The verb.** `grid link migrate --grid-root <home>` reads every OPEN
`type=link` bead in the state store and, per bead, in this order: labels the
target `export:<to>` in its own store; writes `bd dep add <from>
external:<project>:<to>` in the consumer's store, `<project>` being the
target substation's ROSTER NAME; runs `bd ship <to>` when the target is already
CLOSED, so the consumer unblocks exactly as the retired edge would have let it;
and closes the link bead with a reason naming the row it became. `--dry-run`
prints that plan and writes nothing. The order is deliberate: an interrupted
pass leaves the link bead OPEN, and every step is idempotent — bd's label add
is a set union, the row is written only when the consumer's store does not
already carry it, and `bd ship` re-adds a label the target may already hold —
so re-running finishes the work rather than doubling it. A second run over a
converted store reports zero links and writes nothing.

**A same-store link becomes a plain local row.** `external:` exists for what bd
cannot resolve inside one store; a self-referential capability is a row no
store could satisfy. The pass writes `bd dep add <from> <to>` and no
capability at all.

**Refusals leave the receipt OPEN.** A link with malformed metadata, an edge
kind no engine ever implemented, an endpoint outside the roster, or a target
the provider store cannot observe is reported LOUDLY, left OPEN, and the verb
exits non-zero. Closing such a receipt would erase the last record of an edge
that nothing enforces any more — a silent drop is the one outcome a hard cut
must not produce.

**What the landing DELETES.** The `cross_link` library and its
`projectCrossLinks`/`crossLinkEdges`/`crossLinkTypeRefusal` surface; the
`block_guard` shared enforcement, whose only edge source it was; the join's
`_applyCrossLinks` fold, its `onUnresolvedCrossLink` sink, and the
`crossLink.targetClosed` flare family; `JoinedSnapshot.frontierExclusionsByBeadId`
and the two mount-eligibility clauses that read it
(`crossLinkExclusionClause` and `freshCrossLinkReadClause` — approval no longer
races a STATE-axis read, because a cross-store blocker now rides the consumer's
own WORK bead); the board's link-bead read and `projectBoard`'s
`linkBlockersByBeadId`; `StationBeadWriter.createLink`; and the `unlink` verb,
which existed only to close a link bead. `configuredBdTypeNames` survives the
deletion of its host library in `domain/bd_type_discovery.dart`: it is bd type
discovery, which every type-scoped read needs and which was never about links.

**The `link` issue type survives as a READ.** It is already absent from
`GridIssueTypes.customTypes`, so no fresh store seeds it, and the migration
verb needs it to read the receipts out of a store that still holds them. A link
bead in a state store after this landing is inert data.

**This closes the three questions `the-grid-is-a-beads-controller` deliberately
left open**, which is what amends it: a capability bead is a CONTAINER that
closes when its blockers clear and is never driven; the `link` verb is
CONVENIENCE ONLY, sugar over `bd dep add`, minting nothing; and the migration
of existing authored link beads is ONE PASS with a HARD CUT, not a window. It
also obsoletes `target-close-makes-open-cross-link-inert` outright: that entry
governs the lifecycle of an open link bead whose target has closed, and after
this landing no open link bead has a lifecycle at all.

### Consequences

* Good, because one fact has exactly one representation from the moment this
  lands. The window in which the frontier could take two different readings of
  "is this bead blocked" never opens.
* Good, because the conversion is a verb rather than a hand-run script, so it is
  testable, re-runnable, dry-runnable, and reviewable — and the receipts it
  closes name the rows they became, so the conversion is auditable afterwards
  from the store itself.
* Good, because deleting `frontierExclusionsByBeadId` removes a carrier that
  would otherwise have stayed wired from the join to the mount boundary with no
  producer, which is the shape that later reads as a live seam.
* Bad, because the pass is operator-run with the station DOWN, so a store whose
  operator does not run it keeps blocking nothing while its beads still look
  wired. The refusals are LOUD and the verb is idempotent, but nothing forces
  the run.
* Bad, because `unlink` disappears without a replacement verb. Retiring an edge
  is now `bd dep remove`, which is correct — the grid adds only what bd lacks —
  but it is a surface an operator has to relearn.
* Bad, because a same-store link bead (none were measured) converts to a shape
  the `link` verb itself refuses to author. The migration is faithful to the
  edge rather than to the verb, which is the right trade for a one-shot pass
  and a discrepancy someone could reasonably read as an inconsistency.
