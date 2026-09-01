---
status: accepted
date: 2026-09-01
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: agent-seat-and-agent-disc
  surfaces:
    - ".gitignore"
    - ".grid/seats/**"
    - "**/*_grid_assets/**"
    - "docs/design/trajectory/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-4owk
  legacy-id: null
---

# Agent Seat and Agent Disc: an authored standing position and its accreted record, with no resident process

## Context and Problem Statement

The governor already exists in this shape de facto: a versioned agent definition
in the station overlay, a persistent memory home, and an accreted corpus of
named rulings with dates. It is constituted informally, and its memory home is
a harness-owned, path-mangled projects directory that the grid cannot locate,
review, or vend. The refiner work (space-4tc) and committee-precedent work
(pow-mta) need the same concepts without copying that defect.

The original four-part tuple combined two unlike lifecycles. Role definition
and wake condition are authored before occupancy; memory and precedent exist
only because turns happened. One noun would hide that distinction and invite
the further mistake of treating a standing position as a standing process.

## Considered Options

* Keep the four-part tuple under one informal agent name.
* Split the tuple into a seat and a disc, with authored and accreted
  lifecycles.
* Give each long-lived role a resident agent process.
* Keep disc content in an overlay-pack source or in a harness-owned memory
  directory.

## Decision Outcome

The tuple splits into two nouns.

An **Agent Seat** is a standing agent position: a **role definition plus a wake
condition**. An **Agent Disc** is what accretes on that position: a **memory
home plus a precedent corpus**. Both names are written in full on first
utterance; plain **seat** and **disc** are understood thereafter.

The seat is authored, vended, versioned, and reviewable. It exists whether or
not anyone occupies it. The disc is earned from what actually happened,
accreted and curated, and graduates into reviewed assets. These are two nouns
with two lifecycles: the seat can be empty while the disc survives.

### Where the four legs live

| Leg | Home and lifecycle |
|---|---|
| Role definition | An authored, versioned content asset in the seat's overlay pack; install or provision vends it. |
| Wake condition | Authored with the role definition as a predicate over projections; the resident station evaluates it on the fenced service tick. |
| Memory home | Harness-neutral, tracked state at the station grid home, `.grid/seats/<name>/`. |
| Precedent corpus | Judgement residue curated through review into a named, dated, versioned content asset and vended back to the seat. |

The station root's `.grid/` ignore policy must keep all other live-arm state
ignored while re-opening `.grid/seats/` and carrying the negation needed to
track it. Disc files are therefore reviewable and diffable station state, not
ephemeral harness state. Harness-specific projections are materialized at
install or provision time by the existing non-destructive overlay materializer
(pow-kzx); the grid-side files remain harness-neutral. The multi-harness and
flavor work (pow-99g and pow-4xm) consumes this definition rather than changing
it.

This tracked exception extends `docs/adr/ADR-0000-ai-decision-register.md` A49.
A49 says the work signal “EXCLUDES the grid's own runtime dir” and that
“`GitOps.hasUncommittedWork` takes `excluding`, defaulted to EMPTY ... only the
fence excludes.” Its premise that the_grid gitignores `.grid` is narrowed only
at the ignore-policy line: runtime state remains ignored, while
`.grid/seats/**` is tracked station state. The completion fence itself stays
broad: `stationWorkSignal` continues excluding `kGridRuntimeDirName` (`.grid`),
so a mounted coding agent keeps `CompletionContract.committedWorkspace`, but
disc writes do not count as uncommitted work and cannot by themselves make an
inferred exit interrupted. Neither the seat nor the disc declares a completion
contract, and this decision does not select `CompletionContract.none`; those
nouns name state, not process capabilities. Ordinary `git status` still exposes
tracked disc changes for review and graduation.

### Resolution and identity

Resolution consults these layers from most specific to least specific:

1. the substation's own grid-assets pack;
2. the station disc at `.grid/seats/<name>/`;
3. the reserved, unbuilt machine tier at `~/.grid/seats/<name>/`;
4. the vended precedent corpus.

Resolution is a union for inclusion: non-conflicting material from every layer
is present. On conflicting rulings, the most-specific layer wins. Seat identity
remains global across those layers: there is one governor, not a
governor-for-butane and a governor-for-lunar.

There is no substation-scoped disc tier. Substation-specific knowledge belongs
in that substation's reviewed grid-assets pack, following the existing
`swift_infer_grid_assets` and `lunar_grid_assets` pattern. A
`~/.grid/<substation>/seats/` tier would duplicate that knowledge in an
unreviewable location. The machine tier remains reserved and unbuilt because
the current evidence is thin.

### Anti-circus and wake semantics

No resident process belongs to either the seat or the disc. The station remains
the only resident. When a wake condition holds, the station event-mounts the
seat; the agent process dies at turn end. Permanence lives in state—authored
assets, disc files, and beads—never in processes.

The wake condition adds no scheduler, daemon, timer, or side loop. It is a
level-triggered predicate over projections, re-evaluated by the ratified fenced
service tick in `docs/design/trajectory/trajectory-schema.md` section 5. That
tick already runs derived obligations to a fixpoint and already re-evaluates
`admission.refused` / `admission.restored` when their evaluated basis changes.
A wake condition rides that machinery; this decision proposes no new runtime
machinery.

### A disc is not trajectory

A disc can never be a trajectory record. The ratified trajectory/ledger split
(tg-5l4p, `the_grid#trajectory-ledger-split`) requires trajectory records to
be “written by the observer (never self-reported by the agent).” Disc content
is agent-authored by definition, so it remains asset-plane or ledger-plane
state.

The schema produced by tg-hnlt already draws the equivalent boundary for critic
artifacts: they remain agent I/O while the service copies their facts into
observer-written records. An observer may likewise record evidence about a
disc-backed ruling, but the disc itself does not enter the trajectory.

### Graduation is the load-bearing mechanism

Graduation, not the storage directory or its current volume, makes the disc
durable in the useful sense:

1. A mounted turn accretes a judgement grounded in an actual outcome into the
   station disc.
2. Later turns establish cross-bead survival and attach durable evidence,
   including `verify.verdict.recorded` and `verify.route.verdict` receipts
   and operator adjudications.
3. Review distills the surviving judgement into a named, dated ruling in a
   versioned precedent corpus.
4. The overlay path vends that reviewed corpus back to every future occupant of
   the seat.

The current de facto governor disc contains roughly 65 memories, about a dozen
of which are hand-maintained substitutes for missing observability: retry-loop
growth, worktree-mtime dead-session detection, frozen projections, store-sync
waits, stale readiness, and timeout forensics. Those items evaporate into the
trajectory fold and other reviewed assets when their owning mechanisms land.
What should survive is judgement residue. The disc is not sized or designed
around today's accidental pile, and this decision creates no promote verb.

### Relations and boundaries

The ratified bases are tg-5l4p (trajectory/ledger split), tg-y4fd (the owned
admission authority), and tg-hnlt (trajectory schema and fenced service tick).
space-4tc instantiates the refiner seat. pow-mta instantiates committee
precedent corpora and can curate them against durable trajectory receipts.
space-5rp frees the word `seat` by renaming the existing code symbols.

pow-i3i owns the pipe from one refinement conversation onto the bead its build
agent reads. This decision owns the store for judgement that outlives any one
bead. Single-bead context belongs on the bead; cross-bead judgement belongs on
the disc. Neither supersedes the other and they share no machinery.

The public-name tail is deliberately guarded. If seat/disc tooling gains a real
second consumer outside the organization, revisit the Tron-derived name.
Until then, org normative text must carry a binding definition before relying
on the name, and private-station names must not escape into org documentation.

## Consequences

* Good: role definitions can ship and be reviewed independently of accumulated
  judgement.
* Good: earned judgement survives an empty seat and has an explicit path into
  reviewed, portable assets.
* Good: harness projections no longer own the source of disc truth.
* Cost: tracked disc residue can dirty the station tree, so review discipline
  matters; the graduation rule keeps the durable residue small.
* Constraint: the inferred-exit work signal continues to exclude all of
  `.grid`, including tracked disc residue; ordinary Git review, not the
  completion fence, governs that residue.
* Constraint: consumers may instantiate seats and corpora, but may not add
  resident agents or a second wake mechanism.

## Non-goals

No resident daemon or per-seat supervisor; no new tick, scheduler, or runtime
machinery; no implementation of the reserved machine tier; no promote verb; no
implementation change to space-4tc or pow-mta; no public product naming
decision. This entry ratifies the tracked `.grid/seats/` policy but does not
edit the root ignore file, change `stationWorkSignal` or `CompletionContract`,
or build harness projections.

## Review log

* 2026-08-25 — filed by **agent** from the Yegge model-welfare,
  shape-of-things, and fences-not-sandboxes conversation.
* 2026-08-26 — refined by **nico** + **agent** in the first governor session;
  the original ADR-0000 delivery plan was retained at that point.
* 2026-08-31 — refined by **nico** + **agent** in the second governor session
  and re-read against tg-5l4p and the tg-hnlt schema; the two-noun split,
  trajectory boundary, wake reuse, and decisions-register target were fixed.
* 2026-09-01 — **agent**, on Nico's instruction to finish the refinement,
  resolved the four remaining items; the tracked-disc call was taken without
  Nico in the room and is explicitly reversible at the ignore-policy line.
  Recorded accepted and binding on write with decision-makers nico + agent.
* 2026-09-01 — spec-readiness rework cited ADR-0000 A49 and fixed the completion
  boundary: tracked disc files stay outside the inferred-exit work signal, and
  neither the seat nor the disc selects a completion contract.
