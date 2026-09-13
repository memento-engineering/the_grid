---
status: accepted
date: 2026-09-13
decision-makers: ["Nico Spencer"]
consulted: ["governor (agent seat)"]
informed: []
register:
  spec: 1
  slug: capability-edges-are-bd-native-and-link-is-sugar
  surfaces:
    - "packages/beads_dart/lib/src/models/capability.dart"
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/grid_engine/lib/src/domain/external_dep.dart"
    - "packages/grid_engine/lib/src/bridge/federated_snapshot_source.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
    - "packages/grid_sdk/lib/src/work/work_assembly.dart"
    - "packages/grid_cli/lib/src/link_command.dart"
  obsoletes:
    - "cross-store-dep-rows-are-refused-not-honoured"
  updates:
    - "the-grid-is-a-beads-controller"
    - "a55-where-the-state-store-s-link-set-enters-the-pipeline-and"
  obsoleted-by: null
  updated-by: []
  bead: tg-xh5d
  legacy-id: null
---

# The frontier honours bd's external dependencies, and `link` is sugar

## Context and Problem Statement

`the-grid-is-a-beads-controller` moved cross-store blocking onto `bd`'s native
`external:<project>:<capability>` dependency rows and deliberately left three
things open, to be decided where they are built: whether a capability bead is a
driveable type or one that closes when its blockers clear, what the `link` verb
becomes once it no longer mints edges, and how existing authored link beads
migrate.

Building the frontier half forces the first two. It also forces a question that
entry did not raise: what a capability is CALLED. Two builders wiring the same
edge from different ends must produce the same token, or the consumer's row and
the provider's label never meet — and a capability that never resolves blocks
silently and forever, which is the exact failure class that entry exists to
end.

`cross-store-dep-rows-are-refused-not-honoured` is the standing rule this
reverses. Its Option B — classify a cross-store dependency row on both identity
axes and use the classification only to REFUSE, authoring no edge — was chosen
because honouring RAW foreign bead-id rows resurrects a wiring convention A44's
own reversal called unacceptable (`bd doctor --fix` severs such rows as orphaned
dependencies). That reasoning survives intact and is the reason this entry
honours `external:` rows and ONLY `external:` rows.

## Decision Outcome

**Nico's rulings, 2026-09-13.**

1. **A capability bead is a CONTAINER.** It closes when its blockers clear and
   is never driven, exactly as an epic is never driven. There is no new
   driveable type and no station-side export registry.
2. **The `link` verb is CONVENIENCE ONLY** — sugar over
   `bd dep add <from> external:<project>:<capability>`. It performs nothing
   `bd dep` does not, and mints nothing.
3. **HARD CUT.** No coexistence window: the migration of authored link beads
   lands with the deletion of link-bead enforcement, as its own bead
   (`tg-6t0h`), immediately after this one.

**The naming convention, decided here so two builders converge.** The default
capability name for a cross-store edge is the TARGET BEAD'S OWN ID: the target
carries `export:<target-id>`, the consumer carries
`external:<project>:<target-id>`. A NAMED capability is the fan-in form only —
one local container bead labelled `export:<name>` whose own blockers are the
prerequisites, per the previous entry's fan-in rule.

**What the engine adds — only what `bd` lacks.**

* **The frontier honours `external:` rows.** `FederatedSnapshotSource` resolves
  `<project>` by ROSTER NAME and holds the consumer out of ready until that
  member's store holds a CLOSED bead labelled `provides:<capability>` — the fact
  `bd ship` writes. An armed-but-unshipped capability blocks SILENTLY, because
  an unfinished prerequisite is the ordinary state of a blocker, not a
  diagnosis. Closed-ness is re-checked at the frontier rather than trusted from
  the label alone, so a `bd ship --force` against an open issue does not admit
  work behind it.
* **A project the roster does not arm is the LOUD hard refusal**, and it BLOCKS:
  an edge naming a store this station is not arming must never pass as
  satisfied. One line per authored row, rising-edge, naming both ends and the
  armed roster — the loudness guarantee the obsoleted entry established, kept,
  and now backed by an edge that also blocks.
* **A RAW foreign bead-id row is not an edge and not a refusal.** It is left to
  the origin store's own `bd ready`, exactly as a same-store row is. Reporting
  it was only ever a pointer at the `link` verb, and the verb no longer authors
  the thing it pointed at.
* **Ship on close, on TWO rails, through ONE chokepoint.** The station writer
  runs `bd ship <capability>` once per owed `export:<capability>` label, reading
  the bead's CURRENT labels — driven by the closed STATE, not by a close event.
  Rail one is `StationBeadWriter.close`, which ships whatever the station itself
  closes. Rail two is the POST-FLUSH SETTLE
  (`StationCommandHandler.settleCapabilityExports`, on the same `onFlushed` rail
  as the roster drain settle): it reads each work store's resident snapshot,
  takes the CLOSED beads that carry an `export:` with no matching `provides:`,
  and ships them through that same writer. That rail is what makes "a bead
  closed by an operator BY HAND is shipped the next time the station observes
  the close" true of the running station rather than of a method nobody calls —
  agents close their own work beads in their worktrees, so without it the
  capability would have no automated producer at all. Rising-edge, like the
  refusal log: one `bd ship` per observed owing bead, the key dropped as soon as
  the snapshot stops reporting it owed. A capability the bead already provides,
  and a bead carrying no `export:` label, spawn no process.
* **`link` is sugar.** `link <from> --blocked-by <to>` resolves `<to>`'s store
  from the roster, adds `export:<to>` to `<to>` if absent, and runs
  `bd dep add <from> external:<project>:<to>`. It mints no bead and never
  touches the station's own state store. `--prefix`, `--grid-root`, `--reason`
  and `--actor` retire with the link bead that carried them: the roster resolves
  prefixes, and `bd` owns the audit trail. `link ls` lists external rows, and it
  reads SHIPPED exactly as the frontier does — a LABEL scan for a CLOSED bead
  carrying `provides:<capability>`, never a bead-id lookup — so the verb and the
  engine can never disagree about one edge, including the fan-in form where the
  capability is not any bead's id.
* **A SAME-store pair is refused**, pointing at `bd dep add <from> <to>`. A
  self-referential `external:` row resolves in no store, and a same-store
  blocker needs nothing this verb adds.
* **The two project maps are one roster.** The station resolves `<project>` by
  roster name; `bd` resolves the same token through its own `external_projects`
  config. A store whose config omits the project is reported LOUDLY when the
  verb writes the row, never skipped — the row is still written, because the
  grid frontier blocks on it by roster name either way.

### Consequences

* Good, because a cross-store blocker is now one fact in one place, in the tool
  that owns dependency resolution, and `bd dep list` is its typed view.
* Good, because a capability edge survives the re-filing of the bead that
  implements it when the fan-in form is used, and the default id form fails
  LOUDLY rather than silently when it does not.
* Good, because the unarmed-project case both blocks and reports. Under the
  obsoleted entry it reported and blocked nothing, which is a false negative an
  operator had to read a log to discover.
* Bad, because two mechanisms — authored link beads and `external:` rows — are
  both live until `tg-6t0h` lands. That window is deliberate and is measured in
  one bead, not in a release.
* Bad, because the frontier's satisfaction test now reads bd LABELS, so a store
  whose labels are stale reads as unshipped. Fail-closed is the right direction
  for that error, but it is a new way to be wrong.
* Bad, because the post-flush settle is a bd WRITE on the flush rail. It is
  bounded by the rising edge and by the owed set being empty in steady state
  (the common flush spawns nothing), it rides the handler's serialized tail like
  every other resident write, and a failure is reported through the refusal sink
  without stopping the flush — but it is the first write the flush rail makes on
  its own initiative.
* Bad, because `grid_cli`'s `LinkCommand`/`LinkEndpointStore` constructors
  change shape (`stateStorePrefix` and the bare `prefix` endpoint go; the roster
  `name` arrives). The hard cut forbids a shim, so every composer adopts on the
  next `grid_cli` version — `space_station_assets`'s `buildSpaceLinkCommands` is
  the one that exists today.

### What this obsoletes and updates

* **OBSOLETES `cross-store-dep-rows-are-refused-not-honoured`.** Its decision —
  refuse every cross-store dependency row, author no edge — is reversed for
  `external:` rows and retired for raw foreign-id rows. Its ANALYSIS is kept and
  applied: raw foreign bead-id edges stay unsupported, which is why only the
  `external:` form blocks. Its ownership fix (classify on both identity axes)
  outlived the guard it served; project resolution is by roster NAME here, and
  the bead-id prefix now only labels the armed roster in a refusal.
* **UPDATES `the-grid-is-a-beads-controller`.** Two of its three deliberately
  open questions are answered above (the capability bead is a container; the
  link verb becomes sugar). The third — how authored link beads migrate — stays
  open and is `tg-6t0h`'s. Its statement that authored link beads remain
  authoritative until the migration lands is unchanged.
* **UPDATES `a55-where-the-state-store-s-link-set-enters-the-pipeline-and`.**
  Its parenthetical about the union's dep-row source is superseded a second
  time: the union no longer refuses those rows, it enforces the `external:` ones
  and ignores the rest. A55's load-bearing choices — the JOIN as the link seam,
  a malformed link BLOCKS fail-closed, the unwired seeded-type refusal — are
  untouched, and govern authored link beads until they are deleted.
* **Not amended, APPLIED:** `target-close-makes-open-cross-link-inert`
  continues to govern authored link beads unchanged.
