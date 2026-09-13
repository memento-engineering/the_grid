---
status: accepted
date: 2026-09-13
decision-makers:
  - "governor (agent seat)"
consulted: []
informed: []
register:
  spec: 1
  slug: mount-attempt-rearm-resets-in-place
  surfaces:
    - "packages/grid_sdk/lib/src/command/command_operation.dart"
    - "packages/grid_sdk/lib/src/command/station_command_handler.dart"
    - "packages/grid_cli/lib/src/bead_command.dart"
    - "packages/grid_cli/lib/src/station_control.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-2msz
  legacy-id: null
---

# Mount-attempt rearm resets the existing record

## Context and Problem Statement

The station has two independent retry caps. Verdict rework is bounded by
`kMaxReworkRounds` and has an attributed `--beyond-cap` exit, but that exit
requires a linked session. Mount failures are instead counted durably on the
singleton mount-attempt record by `grid.attempt.count`; at
`kMaxMountAttempts`, the `attempt-cap` clause refuses the work before a session
exists. That cap had no operator exit, so restoring eligibility required an
unguarded raw metadata write.

The existing record is explicitly a per-work-bead counter whose attempts are
merged in place, never one bead per attempt. Session rework and void mechanics
re-key per-round session records and therefore do not supply an identity model
for this bead-shaped singleton. A production hand reset on 2026-09-05 already
proved that zeroing the count restores mount eligibility while preserving the
record and its last-attempt timestamp.

## Considered Options

* Reset the singleton mount-attempt record in place and preserve its accrued
  evidence on that record.
* Retire the exhausted record and mint a replacement record for the same work
  bead.

## Decision Outcome

Rearming a mount attempt updates the one existing open mount-attempt record in
place. It sets only `grid.attempt.count` to `0`, preserves the record id and
`grid.attempt.last_at`, and appends a receipt to that record containing the
actor, work bead id, prior count, reason, and UTC time. The supplied reason is
preserved after validation that it is nonblank.

The operation requires exactly one open record for the named work bead and
requires that record to be exhausted. It requires no linked session and never
creates, closes, retires, or re-keys a record. Both cap values and all behavior
that counts mount attempts remain unchanged.

This applies the existing single-writer and state-store decisions in
`the_grid#adr-0006-dogfood-rig-and-live-write-authorization` and
`the_grid#a37-session-bead-write-target-b-a-separate-the-grid-owned-st`, the
resident one-shot and wire decisions in
`the_grid#adr-0014-the-resident-station` and
`the_grid#station-control-is-the-operator-and-ui-wire`, the noun-command and
resident bead-door decisions in `the_grid#cli-subcommands-lead-with-a-noun`
and `the_grid#bead-read-verbs-ride-the-resident-door`, and the append semantics
in `the_grid#bd-silent-success-guardrails`. None is amended or replaced.

### Consequences

* Good, because an exhausted bead has an attributable, ownership-checked
  resident exit even when no session exists.
* Good, because prior attempts remain evidence on the same durable record and
  the last-attempt timestamp remains intact.
* Bad, because the mutable count alone no longer communicates lifetime attempt
  volume; operators must read the appended receipts for pre-reset history.
