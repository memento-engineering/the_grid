# beads_dart

A pure-Dart client for the **beads (`bd`) issue tracker** — the M1 kernel of
the_grid, wearing its ecosystem name (D-A6; recorded in ADR-0002's
alignment amendment).

It knows **beads facts only**: the `Bead`/`GraphSnapshot` value models, the
enveloped-JSON codec, the `bd` CLI wrapper, workspace discovery
(server/embedded), the pooled Dolt SQL read path + `@@<db>_working` probe,
dirty-signal watchers, structural diff, and the typed `GraphEvent` runtime.
the_grid's own opinions on top of those facts — ownership predicates,
driveability narrowing, session-bead semantics — live in `grid_engine`, not
here.

**Seat:** the base of the workspace. `grid_engine`, `grid_runtime`,
`grid_cli`, `grid_sdk`, and `grid_exploration` all depend on it directly
(`grid_devtools` deliberately does not — it consumes the engine only,
ADR-0002 Decision 3). It is **framework-free at the package boundary**
(D-A7): **Futures for acts, Streams for observations**, a synchronous
`current` where a seed value is needed; no riverpod, no StateNotifier —
consumers build their notifiers/providers on top.

## Key entry points

- **`BdRunner`** (`src/services/bd_runner.dart`) — the single subprocess seam:
  runs one `bd` invocation under `BD_JSON_ENVELOPE=1` and returns a `BdResult`.
  Real impl `ProcessBdRunner`; tests inject a `FakeBdRunner`.
- **`BdEnvelope`** (`src/codecs/envelope.dart`) — decodes bd's `--json`
  envelope `{schema_version, data}`, asserting `schema_version == 1`; drift
  throws `BdSchemaDriftException`, malformed JSON throws `BdParseException`.
- **`BdCliService`** (`src/services/bd_cli_service.dart`) — every `bd`
  subcommand as a typed Future over a `BdRunner`. Mutations go through `bd`
  only — never SQL — and carry `--actor grid-controller`; multi-id reads are
  chunked so a large id set never becomes one spawn per id.
- **`BeadsWorkspace`** (`src/services/beads_workspace.dart`) — discovers a
  workspace: locates `.beads/`, reads `metadata.json` (mode + database) and
  `.env`, and resolves a `DoltEndpoint` in server mode (null in
  direct/embedded mode — consumers fall back to the CLI).
- **`diffSnapshots` / `GraphEvent`** (`src/diff/`) — structural diff of two
  `GraphSnapshot`s into a sealed, exhaustively-matchable event hierarchy
  (`BeadCreated`/`Updated`/`Closed`/`Reopened`, `DependencyAdded`/`Removed`,
  `ReadySetChanged`, …).
- **`GridRuntimeFactory` / `GridControllerRuntime`** (`src/reactivity/`) — the
  composed reactive runtime: a `BeadsRepository` over a `SnapshotReader`
  (`SqlSnapshotReader` preferred — ~1–5ms pooled SQL, falling back to the
  authoritative `CliSnapshotReader`'s `bd export --all` + `bd ready` on any
  SQL failure), fed by merged `DirtySignalSource`s (workspace watcher,
  working-set probe, polling ticker) through the `GraphSyncInteractor`.

`src/ready/` additionally ports beads' ready-work predicate to SELECT-only SQL
(`ReadyWorkQuery`/`ReadyWorkFilter`) with `ReadyWorkDifferential` diffing it
against the `bd ready --json` oracle (ADR-0003 Decision 5).

## Version-compat contract

Supports **bd >= 1.0.5** — a RANGE, not a pin. Verified against bd 1.0.5
(`f9fe4ef2a`, schema v50) and bd 1.1.0 (Homebrew, schema v53).

Two independent guards back that claim. Every decode path asserts the bd
envelope's `schema_version`; a mismatch fails loud rather than silently
coercing. The pooled SQL read path probes the store's actual table/column
SHAPE at connect (`DoltSchemaShape`, one `information_schema` SELECT) and
builds its dependency-target expression from the columns that are really
there — the migration version is recorded for diagnostics and never compared,
so a newer 1.x store that still carries the read path's columns just works,
and a store that genuinely drifted stands down to the bd CLI naming exactly
what it lost. The bd CLI path (`BD_JSON_ENVELOPE=1`) is the version-stable
fallback for anything the SQL path will not serve. The full contract is in the
library doc (`lib/beads_dart.dart`).

**Operator hazard — `bd doctor --fix` and cross-store edges.** bd 1.1's
`bd doctor --fix` treats a raw cross-store bead-id dependency (the ADR-0000
A44 mechanism — a foreign bead id stored in
`dependencies.depends_on_external`, which the origin store's own `is_blocked`
recompute never reads) as an ORPHAN and removes it. Never run
`bd doctor --fix` against an org store without excluding cross-store edges.
beads_dart does not inherit that interpretation: `depends_on_external` is a
REQUIRED column in the shape probe and is always COALESCE'd into the
`depends_on_id` alias, so a cross-store edge reads back as an ordinary
`BeadDependency` instead of disappearing.

## Tests

**Fakes, not mocks** (ADR-0001 Decision 7): the offline suite drives
`BdCliService` through a `FakeBdRunner` with programmed results, and the
reactivity core through `FakeSnapshotReader`/`FakeChangeProbe` (+
`fake_async`). `test/integration/` (tagged `integration`) exercises a real
`bd` binary: the SQL-vs-CLI equivalence gate and the ready-work differential
run against a live workspace (self-skipping on schema drift or a mid-read
cross-workspace write rather than flaking); the no-SQL-writes/no-hooks
invariants run in a hermetic temp workspace.

```bash
cd packages/beads_dart && dart analyze && dart test
```

## Docs

Layering and decisions live at the repo level: `docs/adr/ADR-0001` (technical
foundations — the envelope pin, bd-only writes, fakes-not-mocks),
`docs/adr/ADR-0002` (package topology: what stays here vs `grid_engine`), and
`docs/adr/ADR-0003` (the ready-work port). `docs/M1-BUILD-ORDER.md` records
the order this package was built in.
