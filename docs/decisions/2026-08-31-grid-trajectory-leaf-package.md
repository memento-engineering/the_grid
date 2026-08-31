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
dependencies — it sits below the whole chain in the same *dependency
direction* as beads_dart, so grid_engine, grid_sdk, and grid_cli can all reach
it without touching any existing dependency edge.

**The beads_dart analogy holds for DEPENDENCY DIRECTION ONLY** — it is a
statement about where the arrows point, and nothing else. beads_dart is a
**client** of a standalone tool the grid does not own: bd is somebody else's
program, the ledger database is its property, and the package is a way to talk
to it. `grid_trajectory` **is** the store. It owns the DDL, the fence, the sole
appender, and the record vocabulary, grid-owned down to the promoted,
CHECK-guarded envelope columns of schema §4 (`work_bead_id`, `session_id`,
`step_path`, `attempt_id` — bd-coupled correlation keys, not general ones).
Explicitly: **this is not an independent ledger tool**, and "leaf package" must
not be read as "third-party-shaped". It owns:

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

## Long-term direction (2026-08-31, operator-ratified)

A standalone agent-trajectory ledger tool — one usable from other
orchestrators and harnesses, not only from the grid — is of **real long-term
interest**. The landscape memo (`docs/design/trajectory/landscape.md`) went
looking for an occupant and found the intersection genuinely unclaimed: typed
agent-native record vocabulary × a fenced single appender with mandatory
idempotency keys × explicit-unknown as a settleable outcome × verification
bound to immutable digests × admission decisions that read the fold. The
mechanism halves are each occupied (Temporal, DBOS, ATIF, OpenHands); the
intersection is not.

**Extraction is DEFERRED until a second consumer exists.** One consumer is not
a library, it is a subsystem with an optimistic README; the grid's own
correlation keys are load-bearing today and inventing a generic vocabulary now
would be designing against an imagined caller. Until a real second consumer
turns up, the commitment is narrower and testable: the internal
**mechanics/vocabulary import boundary is kept extraction-clean and
test-enforced** — the append client, the connection seam, and the provisioning
DDL operate on `TrajectoryRecord` / `TrajectoryEnvelope` and interface
properties on the sealed base, never on concrete record classes or record-type
string literals
(`packages/grid_trajectory/test/architecture/extraction_boundary_test.dart`).
That keeps extraction a lift rather than a rewrite, at the cost of one test.

Two constraints on the day it happens, both from the memo:

* **Do not name it "Trajectory".** Letta ships `@letta-ai/trajectory` with a
  `trajectory-v1.schema.json` and has the blog post; the name is claimed, and
  it is claimed by a format optimized for the opposite goal (token efficiency
  by dropping harness bookkeeping — precisely our payload). See landscape.md.
* **ATIF is the export format, never the ledger.** ATIF v1.8 has the adoption
  (Harbor, terminal-bench 2.0, Claude Code, Gemini CLI) and the fields that
  already match our round ladder and provenance enum. It documents no
  idempotency key, no fence, and no digest-bound verification, so it is a
  serialization we emit downstream — never the thing we append.
