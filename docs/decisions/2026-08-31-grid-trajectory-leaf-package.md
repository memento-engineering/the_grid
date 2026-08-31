---
status: accepted
date: 2026-08-31
decision-makers: [agent]
consulted: []
informed: [nico]
register:
  spec: 1
  slug: grid-trajectory-leaf-package
  surfaces:
    - "packages/grid_trajectory/**"
    - "pubspec.yaml"
    - ".github/workflows/ci.yml"
    - "packages/grid_sdk/lib/src/work/**"
    - "packages/grid_cli/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: tg-39rg
  legacy-id: null
---

# grid_trajectory is a leaf workspace package owning the codec, the fenced appender, the tick skeleton, and the traj verbs

## Context and Problem Statement

Stage 0 of the trajectory split (tg-zfek; contract:
`docs/design/trajectory/trajectory-schema.md` §9) needs a home for the record
codec, the fenced append client, the service tick, and the `traj show` /
`traj shadow-diff` verbs. Candidate homes: grid_runtime (beside
StationBeadWriter), grid_engine, grid_cli (for the verbs), or a new package.

## Considered Options

* Fold the service into grid_runtime and the verbs into grid_cli.
* A new leaf package owning all four concerns, with thin composition edits
  elsewhere.

## Decision Outcome

A new **leaf** package, `packages/grid_trajectory`, with **zero grid_\***
dependencies — it sits below the whole chain exactly as beads_dart does, so
grid_engine, grid_sdk, and grid_cli can all reach it without touching any
existing dependency edge. It owns:

* the sealed `TrajectoryRecord` codec, `(record_type, type_version)` registry,
  idem-key grammar, and golden fixtures (schema §2.6) — hand-written sealed
  classes, not freezed: the keep-old-decoders-forever rule does not map onto
  single-current-shape codegen;
* the write-capable fenced append client (schema §5: counter-CAS fence,
  1213 / 1105-branched / corruption-halt error contract), a sibling in shape
  to `DoltQueryService` but deliberately not reusing it
  ([[trajectory-direct-sql-scope]]);
* the tick skeleton, modeled on WedgeMonitor's injected-timer shape, with no
  obligation queries wired in Stage 0;
* `TrajCommand` and its subcommands — domain-owned verbs live beside the
  domain (the dart_grid_assets precedent), not in grid_cli.

Composition stays explicit and additive: grid_cli's dev binary and (later, a
separate manual edit) station runners add `TrajCommand`; grid_sdk gains a
small additive boot hook in a later stage. `StationBeadWriter` and the Seed
tree are untouched in Stage 0, per the migration plan's own staging.
