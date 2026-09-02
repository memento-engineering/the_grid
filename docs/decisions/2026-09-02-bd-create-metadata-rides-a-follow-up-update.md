---
status: accepted
date: 2026-09-02
decision-makers: [governor, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: bd-create-metadata-rides-a-follow-up-update
  surfaces:
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/beads_dart/test/services/bd_cli_service_test.dart"
  obsoletes: []
  updates: ["a16-bd-batch-cannot-carry-metadata-or-mol-wisp-convergence-t"]
  obsoleted-by: null
  updated-by: []
  bead: tg-l3kq
  legacy-id: null
---

# `bd create` metadata rides an unconditional follow-up per-key update, never a whole-object `--metadata`

## Context and Problem Statement

`BdCliService.create()` had no metadata channel, so an intake caller filed a
bead and then hand-built its own `bd update` argv. bd offers two ways to close
that gap and they are not equivalent: `bd create --metadata <json>` sets the
whole map in the create itself, and `bd update --set-metadata k=v` merges named
keys server-side while preserving absent ones. The fleet `bd` (and 1.3.0-rc.1)
has NO `create --set-metadata`, so the per-key form cannot ride the create argv
at all.

## Decision Outcome

`BdCliService.create()` writes `setMetadata` by an unconditional create-then-
update: one `bd create` (never carrying a metadata flag), then, when the map is
non-empty, one `bd update <id> --set-metadata k=v …`. There is no capability
probe, no version branch and no fallback path — unlike the guarded-write
negotiation on `update`'s `--if-assignee`/`--if-status`, which exists because
those flags have no substitute. `BdCliService` exposes NO whole-object
`--metadata` parameter on any verb: a bead routinely carries keys written by
different actors (a `validation_plan` gate line, a `grid.approved_*` stamp),
and the replace semantics would silently drop the ones this writer did not
name. This amends A16, whose recorded mechanism for transition metadata was
`bd update <id> --metadata <json>`; the per-key `--set-metadata` channel and
the write-ordering invariant that A16 rests on are what remain in force.

### Consequences

* Good, because the sequence is identical on every bd from the 1.0.5 floor
  through 1.3, and no probe state has to be reset between tests or processes.
* Good, because a concurrent writer's keys on the same bead survive a create.
* Bad, because a metadata-bearing create costs two bd spawns instead of one,
  and the pair is not atomic — a failed follow-up leaves a bead without its
  metadata. The `--external-ref` stamped on the create argv keeps that bead
  findable, so the caller's dedupe read recovers rather than double-filing.
