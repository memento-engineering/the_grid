---
status: accepted
date: 2026-09-03
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: trajectory-journal-column-migration
  surfaces:
    - "packages/grid_trajectory/lib/src/ddl/trajectory_schema.dart"
    - "packages/grid_trajectory/lib/src/cli/traj_replay_command.dart"
    - "packages/grid_sdk/lib/src/trajectory/trajectory_harness.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-j1zn
  legacy-id: null
---

# The journal migrates in place by ALTER, and a stale journal refuses the arm at every posture

## Context and Problem Statement

`the_grid#agent-seat-and-agent-disc` reserves `seat` for an Agent Seat, so the
trajectory journal's store-ownership column becomes `substation` (tg-j1zn).
Two rules in the tree do not answer how: projections "migrate by DROP +
re-CREATE + full replay, never ALTER" (`trajectory_schema.dart:29-33`), and
§2.6 says "the log is never migrated". The first is written about `proj_%`;
the second is about payload `type_version` evolution. Neither governs renaming
a promoted envelope column on the journal, and the journal is the one table in
the schema that is dolt-versioned truth rather than rebuildable state.

## Considered Options

* DROP + re-CREATE the journal, in the P1 shape.
* An in-place ALTER as a named migration step.
* No migration: change the DDL and let un-provisioned homes sort themselves out.
* Gate the boot on the stale shape only under `dualRead` (the P1 posture).

## Decision Outcome

The journal rename is an **in-place ALTER**, shipped as the named step
`renameJournalSubstationColumn` with the probe `journalNeedsSubstationRename`,
run from the already-quiesce-fenced `traj replay` ahead of every projection
replay. The P1 DROP rule is not extended to the journal: `proj_%` is
`dolt_ignore`'d and replayable, the journal is not, and dropping it would
destroy the only copy of every recorded fact. §2.6's "the log is never
migrated" is untouched — no record's payload or `type_version` changes.
Verified against dolt 2.2.2: `DROP CHECK`, `RENAME COLUMN` and
`ADD CONSTRAINT` all apply and the re-added CHECK refuses by its new name.

The boot refusal is **unconditional**, unlike the r12 stale-fold refusal it
sits beside. That one is `dualRead`-gated because it protects the FOLD, and at
`off` there is no fold to protect. The substation column is written by every
append at every posture, so an un-migrated home would lose the whole log to an
unknown column behind a rate-limited flare — the exact silent death the r12
refusal exists to prevent.

The step lands inside the Stage-1 shadow window
(`docs/design/trajectory/trajectory-schema.md` §9 ladder), where the legacy
beads remain authoritative and the journal is re-derivable, so the migration is
cheap now and expensive after the cut.

## Consequences

* Good: an existing home upgrades with one quiesced operator step, and a
  station that skips it refuses loudly instead of dying silently.
* Good: the schema keeps exactly one migration home (`traj replay`); no second
  verb.
* Cost: the tree now has an ALTER path, which the P1 note said was
  deliberately not built. It is scoped to the journal and to this rename.
* Constraint: `journalColumnsSql` is a table-literal statement, not
  `projSessionHeadColumnsSql`'s parameterized form, so fakes and log readers
  can tell the two probes apart by text.

## Review log

* 2026-09-03 — authored by **agent** at the tg-j1zn specify stage; recorded
  accepted and binding on write.
