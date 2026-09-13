---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: ["refiner (agent seat)"]
informed: ["governor (agent seat)"]
register:
  spec: 1
  slug: the-grid-is-a-beads-controller
  surfaces:
    - "packages/grid_engine/lib/src/domain/cross_link.dart"
    - "packages/grid_engine/lib/src/bridge/block_guard.dart"
    - "packages/grid_cli/lib/src/link_command.dart"
    - "packages/beads_dart/lib/beads_dart.dart"
  obsoletes: []
  updates:
    - "target-close-makes-open-cross-link-inert"
  obsoleted-by: null
  updated-by: []
  bead: tg-6vfb
  legacy-id: null
---

# the_grid is a beads controller

## Context and Problem Statement

The grid does not own its work store. It controls `bd`. Where that relationship
has been forgotten, the grid has authored a second structure beside a primitive
`bd` already carries, and has then had to keep the two reconciled. Cross-store
blocking is the clearest instance, and it has cost real rounds.

**Two representations of one fact.** A cross-store blocker exists today as a
grid-authored link bead in the state store. The *intent* to be blocked exists
separately, as prose in a bead description, recognised by a declaration grammar:
a segment must OPEN with `Blocked by`, `Blocked on` or `Depends on`, and a token
inside it counts as an id when its prefix is already known or its tail carries a
digit. The filing contract exists in large part to compare those two
representations and report the gap.

**The parse is spelling-sensitive, and its failure is indistinguishable from
absence.** On 2026-09-13 a refiner wrote `Blocked-by: pow-q6bq` — a hyphen where
the grammar requires a space. Nothing declared; the dependency row reported `no
local blockers named`, which is also exactly what a bead with no blockers
reports. On the strength of that reading the seat minted a duplicate link bead
for an edge an open link bead already carried, then filed and approved a P1 bug
against the filing verb for a defect that did not exist. All three were
withdrawn. `filing-and-approve-share-one-state-root-seam` in the power_station
register records the same trap claiming an earlier victim: a bug report refused
because its own receipt quoted `DEPENDS ON:` mid-sentence.

**bd already had the primitive.** `bd dep add <issue> external:<project>:<capability>`
is a native cross-project dependency. A bead carries `export:<capability>`;
`bd ship <capability>` validates that issue closed and adds `provides:<capability>`;
the dependency resolves when the target project has a closed issue carrying that
label. None of that needed authoring here, and the grid authored a parallel
mechanism anyway.

## Decision Outcome

**When `bd` already carries a primitive for a fact the grid needs, the grid uses
that primitive and adds only what `bd` lacks.** A parallel structure the
controller must then reconcile is refused, because every such structure creates a
desync class, and a desync class eventually gets a grammar, and a grammar
eventually gets a spelling bug that reads as absence.

What the grid legitimately adds is what `bd` has no notion of: the resident
engine, the circuits, the frontier, the seats, and the roster that resolves which
projects exist. Those are controller concerns. A second way to say "this bead is
blocked" is not.

**First application, and the reason this entry exists now: cross-store blocking
moves onto `bd`'s native external dependencies, and the frontier honours them
directly.** Authored link beads retire as the *wiring* mechanism. The prose
declaration grammar retires with them — a blocker becomes a declaration `bd`
holds, not a sentence a regex recognises, and `bd dep list` becomes the single
typed view of blockers, local and cross-store alike.

**Fan-in is expressed in `bd`'s grammar, not in a grid registry.** Where several
beads must land before a capability exists, the capability is ONE local bead
carrying `export:<capability>` whose own blockers are those prerequisites. It
unblocks when they close, and shipping it publishes `provides:<capability>` to
every external consumer. An earlier proposal to let many beads export one
capability, with the station owning the export set, is REJECTED by this entry's
own principle: `bd ship` resolves one capability to one issue, and a station-side
export registry is exactly the parallel structure named above.

**Deliberately left open**, to be decided where they are built rather than
pre-empted here: whether a capability bead is a driveable type or one that closes
when its blockers clear; what the link verb becomes once it no longer mints edges;
and how existing authored link beads migrate. Until that migration lands, authored
link beads remain authoritative and `target-close-makes-open-cross-link-inert`
continues to govern them unchanged.

### Consequences

* Good, because one fact has one representation, so the class of bug where intent
  and wiring disagree — and the grammar written to detect that disagreement —
  both stop existing rather than being made more robust.
* Good, because a capability edge survives the re-filing of the beads that
  implement it. A bead-id edge breaks when its target is split, superseded, or
  capped and re-filed, which is common enough here to have its own protocol.
* Good, because prerequisites become cheap same-store edges and only consumers
  hold cross-store ones. Blocking-edge count is a measured cost here, not a
  tidiness argument: the pour timeout was traced to roughly 130ms per blocking
  edge through an un-indexed cycle query, multiplied by chain depth.
* Bad, because cross-store blocking then rests on two `bd` label conventions and
  one dependency form, in a tool this org does not own and does not pin. The
  exposure is thin — conventions, not internals — but it is real.
* Bad, because the migration of existing authored link beads is unscoped here,
  so two mechanisms coexist until it lands.
* Bad, because "bd already has a primitive for this" is a judgement at the
  margin. Contorting a grid concept to fit a `bd` primitive that nearly matches
  is its own failure, and this entry does not draw that line — it only refuses
  the case where the primitive plainly exists and was ignored.
