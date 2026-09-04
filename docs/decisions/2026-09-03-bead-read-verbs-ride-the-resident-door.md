---
status: accepted
date: 2026-09-03
decision-makers:
  - "specify"
consulted: []
informed: ["nico"]
register:
  spec: 1
  slug: bead-read-verbs-ride-the-resident-door
  surfaces:
    - "packages/grid_cli/lib/src/bead_command.dart"
    - "packages/grid_sdk/lib/src/command/**"
    - "packages/grid_trajectory/lib/src/cli/bead_round_fold.dart"
  obsoletes: []
  updates:
    - "committee-report-reads-step-transition"
  obsoleted-by: null
  updated-by: []
  bead: tg-64bn
  legacy-id: null
---

# Bead read verbs ride the resident door

## Context and Problem Statement

Operators repeatedly reshape the same work-bead JSON to see open work across
the station roster and the lane verdicts for one bead's current round. The
resident already holds every attached work store open, while the trajectory
reader already owns verification-log access. The work-bead approval and
validation metadata keys are authored by the code asset, which depends on the
SDK and therefore cannot be imported back into it.

## Considered Options

* Open work and state stores directly from the CLI verbs.
* Serve bead facts from the resident command door and read verdicts through
  the existing trajectory reader.
* Reuse the committee report's `step.transition` recovery adapter in the
  current-round view, or read only dedicated Family-3 verdict records.
* Import the asset-owned metadata constants into the SDK, or mirror their wire
  names once at the projection boundary.

## Decision Outcome

`bead board` and the bead-context half of `bead round` are read-only resident
command operations. The CLI opens no work or state store. `bead round` reads
lane verdicts through the existing trajectory reader and folds only dedicated
`verify.verdict.recorded`, `verify.verdict.recovered`, and
`verify.route.verdict` records. The committee report remains the sole owner of
the two-source dedicated-record/`step.transition` recovery precedence. The SDK
mirrors `grid.approved_by`, `grid.approved_at`, `grid.approved_rev`, and
`validation_plan` in one `WorkBeadKeys` type rather than importing the
downstream asset package.

### Consequences

* Good, because both verbs reuse stores already held by the resident and cannot
  introduce a competing CLI-side store path.
* Good, because an unreadable roster member and a bead between rounds remain
  typed, visible outcomes instead of silent omissions or errors.
* Good, because the committee report's recovery precedence stays centralized
  while the current-round view reports exactly what dedicated trajectory
  records support.
* Bad, because the round view has no lanes until dedicated verdict writers have
  emitted records, even when a `step.transition` adapter could infer them.
* Bad, because asset-owned metadata key renames must be mirrored manually in
  `WorkBeadKeys`.
