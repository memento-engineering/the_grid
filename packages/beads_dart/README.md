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

Pinned against **bd 1.0.5** (`f9fe4ef2a`). Every decode path asserts the
envelope's `schema_version`; a mismatch fails loud rather than silently
coercing, and the SQL read path treats drift as a signal to fall back to the
bd CLI. The full contract is in the library doc (`lib/beads_dart.dart`).

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
