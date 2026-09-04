---
status: accepted
date: 2026-09-04
decision-makers: ["nico", "agent"]
consulted: []
informed: ["researcher"]
register:
  spec: 1
  slug: light-dag-deferred-bodies-and-two-tier-change-signals
  surfaces:
    - "packages/beads_dart/**"
    - "packages/grid_engine/**"
    - "packages/grid_sdk/**"
    - "packages/grid_runtime/**"
  obsoletes: []
  updates:
    - "adr-0001-technical-foundations"
  obsoleted-by: null
  updated-by: []
  bead: tg-185.1
  legacy-id: null
---

# The resident graph is a light DAG; bead bodies are deferred and change signaling is two-tier

## Context and Problem Statement

The resident station currently retains the full `Bead` value for every node
because field-by-field equality is its diff baseline. The 2026-07-14 consumer
audit found that `description`, `design`, `acceptanceCriteria`, `notes`,
and `closeReason` are read only at the five per-bead `grid_assets` brief and
PR sites: `code_capabilities.dart`, `committee.dart`, `readiness.dart`,
`specify.dart`, and `pr_composition.dart`. It found zero prose reads in
`grid_engine`, `grid_sdk`, or `grid_runtime`. In contrast, `metadata`
has 25 hot-path reads for routing, `grid.agent`, and `validation_plan`.
Keeping all bodies resident therefore pays a large memory and transfer cost for
data the reactive core does not consume.

This entry ratifies the design reached collaboratively with Nico on 2026-07-14
in the researcher role, dictated by Nico. Nico finalized the change signal and
the readiness projection on 2026-09-04 after readiness hold
`tranquility-7po5fu`. This is the accepted, binding-on-write record; it is not
an ADR-0000 pending amendment.

## Decision Outcome

### Decision 1 — Exact field partition

LIGHT (resident), exact: `id`, `status`, `priority`, `issueType`,
`ephemeral`, `deferUntil`, `dueAt`, `assignee`, `owner`, `createdAt`,
`updatedAt`, `startedAt`, `closedAt`, `dependencyCount`,
`dependentCount`, `commentCount`, `labels`, `metadata`,
`hasDescription`; the snapshot also retains dependency edges and the
`ready` flag.

DEFERRED (inflate per bead), exact: `description`, `design`,
`acceptanceCriteria`, `notes`, `closeReason`, `closedBySession`,
`specId`, `externalRef`, `sourceSystem`.

The lists are closed: no unlisted field is implicitly resident or deferred.
The placements are grounded as follows.

| Field or graph fact | Placement rationale |
|---|---|
| `id` | LIGHT: identity keys every node, edge, lookup, and event. |
| `status` | LIGHT: dependency resolution and lifecycle transitions require it. |
| `priority` | LIGHT: ready-frontier ordering reads it. |
| `issueType` | LIGHT: routing and work-type exclusion read it. |
| `ephemeral` | LIGHT: ready filtering and retention policy read it. |
| `deferUntil` | LIGHT: readiness changes when deferral expires. |
| `dueAt` | LIGHT: scheduling and routing may order or filter on it without body inflation. |
| `assignee` | LIGHT: ownership and dispatch selection read it. |
| `owner` | LIGHT: ownership projections read it. |
| `createdAt` | LIGHT: lifecycle ordering does not require a body. |
| `updatedAt` | LIGHT: it is the current per-bead version/change key used for attribution. |
| `startedAt` | LIGHT: lifecycle state and elapsed-time projections read it. |
| `closedAt` | LIGHT: terminal lifecycle and retention decisions read it. |
| `dependencyCount` | LIGHT: graph and blocker projections read it. |
| `dependentCount` | LIGHT: graph projections and terminal-retention eligibility read it. |
| `commentCount` | LIGHT: it signals comment activity without retaining comments. |
| `labels` | LIGHT: routing and selection read them in the hot path. |
| `metadata` | LIGHT: the audit counted 25 hot-path reads in routing, `grid.agent`, and validation. Deferring it would move repeated hot-path work to inflation. |
| dependency edges | LIGHT: they are the DAG and are independently diffed for dependency transitions. |
| `ready` | LIGHT: ready-frontier transitions are independently diffed and drive the station. |
| `hasDescription` | LIGHT: this cheap boolean replaces readiness's hot-path `description.isEmpty` check, avoiding body inflation during intake. |
| `description` | DEFERRED: audited reads are per-bead brief/spec/PR reads; readiness uses `hasDescription`. |
| `design` | DEFERRED: audited reads occur only while preparing one bead's specification or review brief. |
| `acceptanceCriteria` | DEFERRED: audited reads occur only while preparing one bead's specification, review, or PR material. |
| `notes` | DEFERRED: audited reads occur only in per-bead brief/PR composition. |
| `closeReason` | DEFERRED: it is cold terminal prose consumed with one inflated bead, not by dependency resolution. |
| `closedBySession` | DEFERRED: the audit found no reactive-core or routing read; a per-bead consumer can fetch it with the body. |
| `specId` | DEFERRED: the audit found no hot-path consumer; it is a cold per-bead reference. |
| `externalRef` | DEFERRED: the audit found no hot-path consumer; it is a cold per-bead reference. |
| `sourceSystem` | DEFERRED: the audit found no hot-path consumer; it is a cold per-bead reference. |

### Decision 2 — Two-tier change signal

Trigger granularity: per store. `SELECT @@<db>_working`, already about 1 ms
through `ChangeProbe`, answers only “did anything in this store change?” If
the token is unchanged, no snapshot or body is re-read. ADR-0001's local
workspace nudge and CLI polling backstop remain wake/fallback mechanisms; they
do not become attribution mechanisms.

Attribution granularity: per bead. When the store token changes, re-read the
light snapshot and compare each bead's `version`/`updatedAt` change column
to identify changed beads. `updatedAt` is the current LIGHT representation of
that change key. Sanctioned bead-row mutations advance it, so status and
metadata transitions remain attributable. Dependency edges continue to diff by
edge identity and `ready` continues to diff by ready-set membership; neither
depends on a bead-row timestamp. The station therefore continues to detect
status, ready-set, dependency-edge, and metadata transitions.

No content hash is computed: hashing requires the full row whose body this
decision removes from the resident/read path. No field-by-field value diff is
performed: the per-bead change key attributes bead-row changes, while the
separate edge and ready-set diffs attribute graph transitions.

The change classes no longer detected for free are field-level BODY edits to
`description`, `design`, `acceptanceCriteria`, `notes`,
`closeReason`, `closedBySession`, `specId`, `externalRef`, or
`sourceSystem` when that edit does not advance `version`/`updatedAt`.
Even when the key advances, the light engine reports the bead change without
identifying which BODY field changed. This is acceptable because the
2026-07-14 audit found no hot-path or reactive-core consumer of prose and no
current consumer of field-level body-change events.

### Decision 3 — Terminal-node retention

A terminal bead does not stay in the resident DAG indefinitely. Retain it only
as a LIGHT status witness while at least one unresolved dependent needs that
status for dependency resolution. Never retain or inflate its body for that
purpose. Once all dependents resolve and no retained dependency relationship
needs the witness, remove the terminal node from the resident light DAG.

### Decision 4 — Body-change consumers and channel

No current consumer needs field-level body-change events. The five audited
`grid_assets` sites inflate one bead at brief/spec/review/PR time and consume
its current body; the cockpit and existing projections do not subscribe to
body-field diffs.

If a future cockpit or projection requires continuing body-change events, it
must opt in to an explicit per-bead body-change channel keyed by store, bead id,
and `version`/`updatedAt`. That subscriber inflates the affected bead and,
if it needs field names, owns comparison of its own prior body. A consumer that
only needs current prose inflates on demand. Neither case permits the engine to
hold every body as a universal diff baseline. This entry names the channel
contract but adds no channel implementation.

## Relationship to Existing Decisions

This entry updates `the_grid#adr-0001-technical-foundations` Decision 4 only
for resident terminal retention: capture may observe the store's complete graph,
but the resident `GraphSnapshot` no longer keeps an unreferenced terminal
node. It updates Decision 5 by retaining structural authority for the LIGHT
snapshot, edges, and ready set while replacing full-`Bead` field comparison
and BODY `changedFields` with the two-tier trigger and attribution above.

It preserves `the_grid#a21-db-working-reflects-writes-to-dolt-ignored-wisp-tables-t`:
the working root still covers ignored wisp tables and remains a sufficient
store-level trigger. It preserves
`the_grid#adr-0002-package-topology-and-domain-projections`: `metadata`
remains resident and raw metadata is not lost.

## Consequences

- The resident graph and its diff baseline carry graph-driving data rather than
  per-bead prose, reducing steady-state and refresh double-buffer memory.
- The CLI path may parse then discard deferred fields; the SQL path can avoid
  transferring them. Both produce the same LIGHT snapshot.
- Readiness remains hot-path-only through `hasDescription`.
- Consumers pay body inflation only for the bead whose prose they use.
- The body-inflation cache bound and single-flight mechanics are outside these
  four decisions and remain work for the body-loader implementation bead.

## Ratification Provenance

The field partition, terminal retention, and body-consumer conclusions ratify
the collaborative researcher/Nico design of 2026-07-14. Nico dictated the final
two-tier signal and `hasDescription` addendum on 2026-09-04. Decision-makers
for this accepted register entry are `nico` and `agent`.
