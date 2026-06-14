# ADR-0001 — Technical foundations for the_grid

**Status:** Accepted 2026-06-11 (Nico)
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** PDR §1–5 ([docs/PDR.md](../PDR.md)). This ADR fixes the technical requirements for M1 and the conventions that bind all later milestones.

---

## Decision 1 — Language, workspace, conventions

Dart (SDK `^3.11.0`), pub workspace + melos, cloning Lenny's root `pubspec.yaml` shape and `analysis_options.yaml` (lints/recommended + `strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_single_quotes`, `sort_pub_dependencies`, `unawaited_futures`, `avoid_print`). Value types and unions are **freezed** (sealed unions) with `json_serializable`-backed codecs; consumers lean heavily on Dart pattern matching — exhaustive `switch` expressions over the sealed hierarchies (`GraphEvent`, gate outcomes, reconciler transitions) are the house style, compiler-checked. `build_runner` is wired into the melos scripts. *(Amended 2026-06-11: reverses the original hand-written-models call.)*

**Consequence:** any Dart developer (or agent) moving between lenny and the_grid sees one set of rules.

## Decision 2 — Architecture: predictable-flutter layering

All packages follow the predictable-flutter skill (layers by longevity, unidirectional reactive push, dependency direction toward stability):

| Layer | the_grid components |
|---|---|
| **Services** (stateless I/O) | `BdCliService` — one-shot `bd` subprocess + JSON envelope decoding. `DoltQueryService` — pooled MySQL-protocol reads + working-set probe. Dirty-signal sources (`.beads` file watcher, probe ticker) are service-layer *streams*. |
| **Repositories** (own one data source, emit state) | `BeadsRepository` — owns the `GraphSnapshot` cache; `AsyncValue.loading → data/error` emission; executes the single-flight re-query. |
| **Interactors / Selectors / Transformers** | `GraphSyncInteractor` — subscribes to dirty-signal streams, debounces (150ms quiet period, dirty-bit + single-flight), triggers `repository.refresh()`. `GraphEventsTransformer` — pure `diffSnapshots(before, after)` → typed `GraphEvent`s. `ReadyWorkSelector`, `BeadSelector` (per-id). |
| **View** | `grid watch` CLI renderer (NDJSON with `--json`); later Flutter dashboards consume the same providers. |

Naming: reference types carry classifiers (`BdCliService`, `BeadsRepository`, `GraphSyncInteractor`); value types are plain (`Bead`, `GraphSnapshot`, `GraphEvent`). Files snake_case under `lib/src/`, public API via the package barrel only.

**Consequence:** the diff engine and all coordination logic are pure or fake-able; tests follow predictable-flutter's patterns (Fakes, not mocks; state-transition assertions).

## Decision 3 — Reactive primitive: Riverpod 3 Notifier

Pure-Dart `riverpod ^3.0.0`. State containers are `Notifier`/`AsyncNotifier` subclasses exposed via `NotifierProvider`/`AsyncNotifierProvider`; event streams via `StreamProvider`; derived state via providers with `select`. **Not** `StateNotifier` — predictable-flutter's *architecture* is adopted; its Riverpod-2-era primitive is translated to Riverpod 3's. (predictable-flutter's references should be updated to take a Riverpod 3 position; tracked there, not here.)

Divergence note: lenny is on flutter_riverpod 2.6. The workspaces are independent; flag if packages are ever shared.

## Decision 4 — beads substrate: bd CLI writes, pooled Dolt SQL reads

- **Mutations and ready-work: always `bd` CLI** (`BD_JSON_ENVELOPE=1`, `--actor grid-controller`, 15s timeout with kill, max 4 concurrent). bd owns validation, audit events, gc hooks, and Dolt commit semantics — SQL writes would bypass all four. Ready-work is never reimplemented in M1 (`bd ready --json` is authoritative; M2 ports it differential-tested).
- **Error channel** *(promoted from ADR-0000 A3, 2026-06-11)*: under envelope mode, bd emits errors **enveloped on stdout** (`{"data": {"error": …}, "schema_version": 1}`) with empty stderr and exit ≠ 0 — `BdException` parsing reads stdout first, falls back to stderr, then raw text. Fixture: `fixtures/upstream/2026-06-11-bd-1.0.5/tg-error-stdout.json`.
- **`bd list` never surfaces infra-typed beads** *(promoted from ADR-0000 A5, 2026-06-11)*: regardless of `--all`, agent/rig/role records do not appear in `list`; snapshot composition and domain sampling on the CLI path use `bd export --include-infra` exclusively.
- **Batch and bulk bd forms, never per-issue loops** *(added 2026-06-11)*: mutations that move together go through **`bd batch`** — one line-oriented script, one dolt transaction, one `DOLT_COMMIT` (atomic rollback-on-error, no write amplification, and one dirty signal instead of N). Bulk/filtered reads prefer one-spawn forms: **`bd export --include-infra`** (full-graph JSONL in a single spawn — also the CLI-fallback snapshot read; `--include-infra` pulls the agent/rig/role/message infrastructure beads the domain projections need), **`bd query "<expr>"`** for filtered reads, and multi-id **`bd show id1 id2 …`** / **`bd dep list <ids…>`**. Spawning bd per issue inside a loop is forbidden.
- **Snapshot reads: pooled MySQL-protocol connection** (1–2 connections) to the Dolt server (`127.0.0.1:34947`, db `tg`, discovered via `.beads/metadata.json` + `.beads/.env` → `$GT_ROOT/.gc/runtime/packs/dolt/dolt-config.yaml`). `SELECT`-only by construction. Client: `mysql_client`, with `mysql1` as fallback; auth handshake is the day-one spike.
- **Schema-drift guard:** on connect, read the migrations version; unknown/newer ⇒ disable SQL reads, fall back to `BdCliService` reads, log loudly. An SQL-vs-CLI snapshot equivalence test is the drift canary in CI.
- **Connection hygiene:** reconnect-on-error (server reaps idle at 30s); the ~1s probe doubles as keepalive. Never more than the pool's 1–2 connections (documented pileup incident).
- **Snapshot is the complete graph** *(amended per ADR-0000 A20, accepted 2026-06-14)*: both capture paths compose **issues ∪ wisps** (all statuses, incl. infra/template/gate-typed beads) — **filtering is the consumer's job** (projections/selectors), not the read layer's. The **SQL path UNIONs** `wisps`/`wisp_dependencies`/`wisp_labels` into the issues/dependencies/labels reads (issues∪wisps merged by column *name*, not a positional `UNION` — `is_blocked` reached the two tables via different migration tracks). The **CLI path uses `bd export --all`** (superseding `--include-infra` for snapshot composition in the two bullets above), which lifts the default infra/template/ephemeral exclusions. This **closed a latent M1 divergence**: beads migration 0035 moved infra beads (agent/rig/role/message) into the `wisps` table + deleted them from `issues`, so the prior `issues`-only SQL read silently missed infra on any post-0035 db while the CLI (`--include-infra`) path saw them.

## Decision 5 — Reactivity: sufficient signals, authoritative diff

Change detection is layered; signals only need to be *sufficient*, the structural diff is the only truth:

1. `.beads/` file watcher (filtered to `last-touched`, `hooks.log`, `interactions.jsonl`) — sub-second push for local mutations. The re-query path never calls `bd show` (it writes `last-touched` — feedback loop).
2. `SELECT @@tg_working` probe every ~1s over the pool — catches all writes including cross-workspace, ~1ms each.
3. bd-CLI polling backstop (5s) — active only when SQL is unavailable (embedded mode, server down).

All signals funnel to `GraphSyncInteractor`: dirty-bit + single-flight (signals during a refresh schedule exactly one follow-up), 150ms quiet period. Refresh composes the snapshot — issues + dependencies + labels + **metadata** (domain projections need it, ADR-0002) including infrastructure beads — via SQL, or via a single `bd export --all` spawn on the CLI fallback path (ADR-0000 A20); ready set via `bd ready`. `GraphEvent` is a sealed (freezed) hierarchy: `SnapshotInitialized`, `BeadCreated/Updated(changedFields)/Closed/Reopened`, `DependencyAdded/Removed`, `ReadySetChanged(entered, exited)`.

**The `@@<db>_working` probe is sufficient for the dolt-IGNORED wisp tables too** *(amended per ADR-0000 A21, accepted 2026-06-14)*: dolt's *working* root is content-addressed over **all** tables in the working set — including ignored ones (only the *staged*/commit root excludes them; dolt #10698, reproduced embedded + cross-session). So the probe flips on writes to the ignored `wisps`/`wisp_*` tables, and the SQL probe alone catches gc's **cross-workspace wisp closes** that the `.beads/` file-watcher provably cannot. Consistent with "signals need only be sufficient": a pour-then-burn between two ticks returns the hash to prior (harmless — the diff is authority), and a flip is not attributable to a specific table (fine for a wake nudge). No wisp-specific augmentation is needed.

## Decision 6 — Observability: the Lenny exploration protocol, exclusively

the_grid's process exposes exactly the exploration protocol — no bespoke `ext.grid.*` namespace:

- `ext.exploration.core.handshake` → `{protocolVersion, plugins: [{namespace: "grid", tools: [...]}]}`
- `ext.exploration.core.get_stable_observation` → observation envelope with empty `semantics`/`routes`, grid state under `plugins.grid`, `stability` reflecting in-flight refreshes
- `ext.exploration.grid.<tool>` → tools: `requery`, `snapshot`, `ready`, `events` (ring buffer, 256), `stats` (read-path in use, signal counts per source, refresh latency)

Prerequisite (M0, in lenny's repo): extract the pure-Dart **`exploration_contract`** package (plugin.dart, types.dart, registry.dart, de-Fluttered plugin_context.dart with `registerFrameCallback` optional), repoint exploration_flutter and plugins at it. the_grid consumes it (path dep during development) and ships `GridControllerPlugin` + a minimal pure-Dart host that registers the three extensions via `dart:developer`. Extension method names use the `ext.exploration.` prefix: the historical `ext.flutter.exploration.` prefix squatted the Flutter framework's reserved namespace (registration is via `dart:developer.registerExtension`, so the `flutter` segment was never framework-imposed) and would mislead Flutter-detection tooling once a pure-Dart host advertises it. Lenny renames repo-wide (agent/CLI/DevTools land in lockstep, bead lenny-wisp-41rdl) as a precursor to the extraction (bead lenny-wisp-9h557). *(Amended 2026-06-11: this reverses the original "keep verbatim" call, resolving PDR §9 Q1.)*

**Consequence:** exploration_cli, exploration_devtools, and the exploration agent attach to the running orchestrator on day one; humans and agents share one debugging surface (PDR G3).

## Decision 7 — Testing requirements

- Unit tests run fully offline: `FakeBdRunner`, fake services, `fake_async` for quiet-period/coalescing; exhaustive `diffSnapshots` cases including `diff(s, s) == []`; pool reconnect-after-idle.
- Codec fixtures captured from real `bd --json` output, checked in with the bd version recorded. *(Promoted from ADR-0000 A1, 2026-06-11:)* fixtures live at `fixtures/upstream/<date>-bd-<version>/`, captured under `BD_JSON_ENVELOPE=1` — empty-workspace cases + `statuses`/`types` from the_grid, per-domain samples extracted from the HQ `bd export --include-infra` JSONL (never from `bd list`), a raw export sample, and an error-shape fixture. Re-capture only via the porting skill's procedure; never hand-edit.
- Tagged integration suite: hermetic `bd init` temp workspace, real mutations, ordered typed events, ≤2s budget each, latencies printed.
- SQL-vs-CLI equivalence test (tagged) as the schema-drift canary.
- A test asserts no SQL writes and no `.beads/hooks/` modifications (PDR §6.6).

## Decision 8 — Onboarding artifacts *(promoted from ADR-0000 A4, 2026-06-11)*

Context survives compaction and reaches subagents through repo artifacts, not conversation history: `CLAUDE.md` (session contract — read-first chain, the gate, process rules including the ADR-0000 register, conventions, bd rules, environment facts, upstream pins) and `docs/M1-BUILD-ORDER.md` (dependency-ordered work breakdown for orchestration). `README.md` carries the public reading order. These are maintained as decisions evolve.

---

## Alternatives considered

- **Full gascity port** — rejected: 343k LOC, mostly projection layers (CLI/HTTP/providers); the domain core is ~4k LOC and the loop it serves is the thing being replaced.
- **Direct SQL writes** — rejected: bypasses bd validation, audit trail, gc hooks, Dolt commit semantics.
- **`StateNotifier` literal** — rejected in favor of Riverpod 3 `Notifier` (Decision 3).
- **Bespoke `ext.grid.*` observability namespace** — rejected: the exploration protocol gives three working consumers for free (Decision 6).
- **bd-CLI-only reads** — kept as the fallback path, not primary: ~70–140ms/spawn vs ~1–5ms pooled SQL, and the per-call-client pileup incident argues against spawn-per-read at scale.
- **Installing `.beads/hooks/` for push signals** — rejected: gc owns and restamps those files.
