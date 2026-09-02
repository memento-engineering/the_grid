---
status: accepted
date: 2026-09-02
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: burn-primitive-argv-pins-cascade
  surfaces:
    - "packages/beads_dart/lib/src/services/bd_cli_service.dart"
    - "packages/beads_dart/test/services/bd_cli_service_actuator_test.dart"
    - "packages/grid_runtime/lib/src/lifecycle/station_bead_writer.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-1liv
  legacy-id: null
---

# The burn primitive pins `--cascade` so a subtree delete stays a subtree delete

## Context and Problem Statement

ADR-0003 Decision 8 (promoted from ADR-0000 A26, Nico 2026-06-14) records
`delete(id)` → `bd delete <id> --force` (the burn primitive) and `burn = bd
delete natural post-order, only speculative wisps`. A26 pinned that argv after
two adversarial lenses, so changing it is an EXTENSION of a ratified decision
and is recorded, never silent.

At bd 1.3.0-rc.1, `bd delete <parent> --force` deletes the parent and leaves its
child orphaned. The previous implicit cascade is no longer part of that argv.

## Considered Options

* Leave `--force` alone and accept orphaned dependents on bd 1.3.
* Branch the argv on a negotiated bd version.
* Pin `--cascade` unconditionally.

## Decision Outcome

The third. Observed at rc.1, `bd delete <parent> --force` deletes the parent and
leaves the child; `--cascade --force` deletes both. The fleet binary
HEAD-a45199a accepts `--cascade` and cascades identically, so ONE argv serves
every supported bd: no version branch and no dual model, per the
no-legacy-support posture.

What A26 fixed is PRESERVED: the same verb, the same `--actor`, the same
burn-vs-close distinction (a stopped active wisp is still closed, never
deleted), and the post-order caller contract. A cascade over an already-empty
subtree is a no-op. Only the default bd 1.3 withdrew is restored explicitly.

The argv is pinned in `bd_cli_service_actuator_test.dart`'s existing
burn-primitive test, migrated in place rather than duplicated, so a future edit
cannot silently drop it.

## Review log

* 2026-09-02 — authored by **agent** (specify stage of tg-1liv).
