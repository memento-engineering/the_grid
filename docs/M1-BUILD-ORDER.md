# M1 build order — dependency-ordered tracks

For orchestration (ultracode) decomposition. Tracks run in parallel where their inputs
allow; ⊣ marks a hard dependency. Acceptance criteria: PDR §6. Conventions: CLAUDE.md.
AI decisions made en route: ADR-0000 amendments, never silent.

## Track 0 — serial preconditions

1. **Workspace scaffold**: root `pubspec.yaml` (pub workspace), melos scripts (incl. `build_runner`), root `analysis_options.yaml` (clone lenny's), package skeletons for `grid_controller`/`grid_cli`/`grid_exploration`/`grid_devtools`. Green: `melos bootstrap` + `dart analyze`.
2. **Dolt auth spike** (day-one risk, PDR §8): `mysql_client` → `127.0.0.1:34947`, `SELECT @@tg_working`, `SELECT … FROM issues LIMIT 1` against db `tg`. Fallback `mysql1`. Outcome recorded in ADR-0000. If both fail: M1 proceeds bd-CLI-only (design unchanged).

## Parallel tracks (after Track 0.1)

- **Track A — models + codecs** *(pure)*: freezed value types (`Bead`, `BeadDependency`, enums/extension types per ADR-0001), envelope + error decoding driven by `fixtures/upstream/2026-06-11-bd-1.0.5/` (note A3: errors on stdout). Then **`GraphSnapshot` + `diffSnapshots`** with exhaustive cases (`diff(s,s)==[]`).
- **Track B — `BdCliService`**: runner (`Process.start`, timeout+kill, semaphore 4, `BD_JSON_ENVELOPE=1`), reads (`ready`, `export --include-infra` as snapshot read, `query`, multi-id `show`/`dep list`, `statuses`, `types`), mutations (`create/update/close/depAdd`, `batch`), error hierarchy.
- **Track C — `DoltQueryService`** ⊣ Track 0.2: pool (1–2 conns, reconnect-on-error vs 30s reap), snapshot SELECTs (issues+deps+labels+metadata), `@@tg_working` probe, migrations-version guard with CLI fallback.
- **Track D — reactivity core** ⊣ A, B (C optional): dirty-signal sources (`.beads` watcher, probe ticker, CLI poll fallback) → `GraphSyncInteractor` (dirty-bit + single-flight, 150ms quiet) → `BeadsRepository` (`AsyncValue<GraphSnapshot>`) → `GraphEventsTransformer` → providers. `fake_async` coalescing tests.
- **Track E — domain projections** ⊣ A, D: projection mechanism + proving domains **sessions, messages, molecules/steps** (ADR-0002, promoted A2) + metadata codecs + `ProjectionError`.
- **Track F — `grid_exploration`** ⊣ D; blocked on lenny M0 for the contract dep (until then: build the pure-Dart host against the wire shapes — handshake / get_stable_observation / tools — verified against lenny source).
- **Track G — `grid_cli` watch** ⊣ D: NDJSON `--json`, per-event reaction latency, VM-service URI banner.
- **Track H — `grid_devtools` scaffold** ⊣ F: `devtools_extensions` shell + events-timeline panel over the exploration protocol.
- **Track I — porting skill** *(independent)*: pinned versions, fixture re-capture procedure, pack-protocol/schema diffing, re-alignment steps (PDR §6.7).
- **Track J — integration + acceptance** ⊣ B, D (+C for SQL-vs-CLI equivalence): hermetic `bd init` suite, equivalence canary, the two-terminal demo with measured latencies, no-SQL-writes/no-hooks assertion tests.

## Definition of done

PDR §6 criteria 1–8, all green, latencies recorded in README; every en-route AI decision sits in ADR-0000 as pending.
