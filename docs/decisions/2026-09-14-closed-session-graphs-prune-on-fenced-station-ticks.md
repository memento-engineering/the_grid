---
status: accepted
date: 2026-09-14
decision-makers:
  - "Nico Spencer"
consulted: []
informed: []
register:
  spec: 1
  slug: closed-session-graphs-prune-on-fenced-station-ticks
  surfaces:
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/grid_engine/lib/src/domain/state_store_prune.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
    - "packages/grid_sdk/lib/src/stores/state_store_pruner.dart"
    - "packages/grid_sdk/lib/src/trajectory/state_store_prune_obligation.dart"
    - "packages/grid_sdk/lib/src/trajectory/trajectory_config.dart"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-96sz
  legacy-id: null
---

# Closed session graphs prune on fenced station ticks

## Context and Problem Statement

Closing a completed session molecule leaves its issue and dependency rows in the
state store. Each successful round therefore adds roughly thirty closed step
beads and eighty dependency rows. The fleet `bd` binary's cycle checks scan the
dependency table per edge, so normal completed work makes later graph pours
progressively more expensive. Manual three-day prunes restored pour performance,
but a recurring classifier-gated operator action is not a durable station
behavior.

The reclaim must remain inside the station-owned state store and preserve the
exposure rule: an open session or a closed session whose work bead remains open
must never be deleted. Gates, cursor and lock beads, mount attempts, unrelated
records, and incomplete or young graphs must remain protected as well.

## Considered Options

* Periodically prune old, exposure-cleared closed session graphs from the state
  store on the station's existing fenced tick.
* Hard-delete each session's step graph as soon as the session becomes terminal.

## Decision Outcome

The resident station periodically prunes the station-owned state store on its
existing fenced, non-stacking tick. The retention age is a station configuration
value whose default is three days. Eligibility uses a strict cutoff and requires
an already-closed session graph: the session and every molecule and step in its
graph are non-ephemeral, closed, and older than the cutoff.

The session's work link is exposure-cleared only when it directly names a closed
work bead, names the base of a closed rework work bead, or has the exact
`<base-work-id>#void-<session-id>` form. The exact void form remains eligible
when the detached base bead is no longer present. An open or missing direct work
link, a malformed void key, or any open, young, ephemeral, or missing-close-time
member protects the whole session graph.

The void exception applies
`the_grid#a48-a-closed-session-is-dispositioned-done-held-voided-not-b`:
“A DEAD KEY: never adoptable AND never blocking. The bead MOUNTS;
`SessionScope` RETIRES the dead key” by re-keying its `work_bead` to
`<base-work-id>#void-<dead-session-id>`, while a fresh round mounts on the same
original work-bead id. That retired pointer no longer exposes the live work
bead, so—unlike direct and rework links—the exact void branch does not require
the detached base bead to remain present or closed.

Before deletion, the writer creates or reuses one owned, open, non-ephemeral
state-store protection-shield chore and replaces its description with every
state bead id outside the eligible graph union. It verifies the shield by a
fresh scoped read, then composes exactly one `bd prune --older-than <N>d --force`
operation through the station writer chokepoint. A crash after verification can
only leave an open shield that over-protects records. The operation is
idempotent.

Every fenced run emits exactly one receipt containing beads removed, dependency
rows removed, and duration. An unreachable state or work store, snapshot or
planning failure, or writer failure skips the run and emits a sanitized skipped
receipt rather than failing the station tick. A run with no eligible graph emits
a completed zero-removal receipt without invoking the destructive verb.

Terminal hard deletion is rejected here. It would couple reclamation to every
terminal transition and would not repair the already-accreted closed backlog.

This decision departs narrowly from
`the_grid#a58-molecule-reap-follows-the-complete-intra-graph-dependenc`, which
states: “The reap never passes `--force`: bd's refusal protects graph meaning
when a blocker remains open.” `reapMolecule` remains unchanged and still never
passes `--force` to a close, dependency, or update call. This periodic operation
closes nothing: `bd prune --force` is the non-interactive confirmation for
deleting already-closed, exposure-cleared selected records, not an override of
an open blocker.

### Consequences

* Good, because successful work no longer makes graph-pour cost grow without
  bound and the same station behavior also reclaims the existing closed backlog.
* Good, because a fail-closed protection shield keeps all non-eligible state
  records and all graphs exposed by open work outside the bulk prune.
* Good, because the implementation reuses bd's bulk prune semantics instead of
  implementing deletion or looping over record ids locally.
* Bad, because each fenced maintenance tick performs fresh state and work reads,
  shield verification writes, and potentially one additional bd process.
* Bad, because reclaim is delayed by the retention age rather than occurring at
  terminal close.

### Confirmation

The composing station's touched-surface roster returned A48 for the governed
package paths. `the_grid#the-grid-is-a-beads-controller` was read separately as
conceptual support for composing bd's existing prune primitive; it was not
returned for these touched surfaces and is not claimed as a roster-selected
governing decision.
