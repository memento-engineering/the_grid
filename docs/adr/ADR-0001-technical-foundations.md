# ADR-0001 — Technical foundations for the_grid

**Status:** Proposed
**Date:** 2026-06-11
**Deciders:** Nico Spencer
**Context:** PDR §1–5 ([docs/PDR.md](../PDR.md)). This ADR fixes the technical requirements for M1 and the conventions that bind all later milestones.

---

## Decision 1 — Language, workspace, conventions

Dart (SDK `^3.11.0`), pub workspace + melos, cloning Lenny's root `pubspec.yaml` shape and `analysis_options.yaml` (lints/recommended + `strict-casts`, `strict-inference`, `strict-raw-types`, `prefer_single_quotes`, `sort_pub_dependencies`, `unawaited_futures`, `avoid_print`). Hand-written models and codecs — no codegen (`freezed`/`json_serializable`) in M1; revisit if value-type boilerplate becomes a tax.

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
- **Snapshot reads: pooled MySQL-protocol connection** (1–2 connections) to the Dolt server (`127.0.0.1:34947`, db `tg`, discovered via `.beads/metadata.json` + `.beads/.env` → `$GT_ROOT/.gc/runtime/packs/dolt/dolt-config.yaml`). `SELECT`-only by construction. Client: `mysql_client`, with `mysql1` as fallback; auth handshake is the day-one spike.
- **Schema-drift guard:** on connect, read the migrations version; unknown/newer ⇒ disable SQL reads, fall back to `BdCliService` reads, log loudly. An SQL-vs-CLI snapshot equivalence test is the drift canary in CI.
- **Connection hygiene:** reconnect-on-error (server reaps idle at 30s); the ~1s probe doubles as keepalive. Never more than the pool's 1–2 connections (documented pileup incident).

## Decision 5 — Reactivity: sufficient signals, authoritative diff

Change detection is layered; signals only need to be *sufficient*, the structural diff is the only truth:

1. `.beads/` file watcher (filtered to `last-touched`, `hooks.log`, `interactions.jsonl`) — sub-second push for local mutations. The re-query path never calls `bd show` (it writes `last-touched` — feedback loop).
2. `SELECT @@tg_working` probe every ~1s over the pool — catches all writes including cross-workspace, ~1ms each.
3. bd-CLI polling backstop (5s) — active only when SQL is unavailable (embedded mode, server down).

All signals funnel to `GraphSyncInteractor`: dirty-bit + single-flight (signals during a refresh schedule exactly one follow-up), 150ms quiet period. Refresh composes the snapshot (issues + dependencies + labels via SQL or CLI fallback; ready set via `bd ready`). `GraphEvent` is a sealed hierarchy: `SnapshotInitialized`, `BeadCreated/Updated(changedFields)/Closed/Reopened`, `DependencyAdded/Removed`, `ReadySetChanged(entered, exited)`.

## Decision 6 — Observability: the Lenny exploration protocol, exclusively

the_grid's process exposes exactly the exploration protocol — no bespoke `ext.grid.*` namespace:

- `ext.flutter.exploration.core.handshake` → `{protocolVersion, plugins: [{namespace: "grid", tools: [...]}]}`
- `ext.flutter.exploration.core.get_stable_observation` → observation envelope with empty `semantics`/`routes`, grid state under `plugins.grid`, `stability` reflecting in-flight refreshes
- `ext.flutter.exploration.grid.<tool>` → tools: `requery`, `snapshot`, `ready`, `events` (ring buffer, 256), `stats` (read-path in use, signal counts per source, refresh latency)

Prerequisite (M0, in lenny's repo): extract the pure-Dart **`exploration_contract`** package (plugin.dart, types.dart, registry.dart, de-Fluttered plugin_context.dart with `registerFrameCallback` optional), repoint exploration_flutter and plugins at it. the_grid consumes it (path dep during development) and ships `GridControllerPlugin` + a minimal pure-Dart host that registers the three extensions via `dart:developer`. Extension method names keep the `ext.flutter.exploration.` prefix verbatim — the agent/CLI/DevTools require those names today; renaming is cosmetic debt tracked in lenny.

**Consequence:** exploration_cli, exploration_devtools, and the exploration agent attach to the running orchestrator on day one; humans and agents share one debugging surface (PDR G3).

## Decision 7 — Testing requirements

- Unit tests run fully offline: `FakeBdRunner`, fake services, `fake_async` for quiet-period/coalescing; exhaustive `diffSnapshots` cases including `diff(s, s) == []`; pool reconnect-after-idle.
- Codec fixtures captured from real `bd --json` output, checked in with the bd version recorded.
- Tagged integration suite: hermetic `bd init` temp workspace, real mutations, ordered typed events, ≤2s budget each, latencies printed.
- SQL-vs-CLI equivalence test (tagged) as the schema-drift canary.
- A test asserts no SQL writes and no `.beads/hooks/` modifications (PDR §6.6).

---

## Alternatives considered

- **Full gascity port** — rejected: 343k LOC, mostly projection layers (CLI/HTTP/providers); the domain core is ~4k LOC and the loop it serves is the thing being replaced.
- **Direct SQL writes** — rejected: bypasses bd validation, audit trail, gc hooks, Dolt commit semantics.
- **`StateNotifier` literal** — rejected in favor of Riverpod 3 `Notifier` (Decision 3).
- **Bespoke `ext.grid.*` observability namespace** — rejected: the exploration protocol gives three working consumers for free (Decision 6).
- **bd-CLI-only reads** — kept as the fallback path, not primary: ~70–140ms/spawn vs ~1–5ms pooled SQL, and the per-call-client pileup incident argues against spawn-per-read at scale.
- **Installing `.beads/hooks/` for push signals** — rejected: gc owns and restamps those files.
