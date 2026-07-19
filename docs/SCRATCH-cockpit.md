# SCRATCH — the grid activity cockpit + its LAN observability server

**Status:** design surface — **decisions ratified by Nico 2026-07-11; zero open questions.** Not yet filed as beads. Ready to graduate to ADR-0012 + a build order and be decomposed.
**Date:** 2026-07-11.
**Relation to ratified scope:** this is the **LAN-only, watch-only subset of ADR-0012 (observability, reserved/parked)** materialized early. It re-homes `StationControl` (RS-4, `SCRATCH-resident-station.md` §3, ratified 2026-07-02) per its own D-C5 note ("a floor — re-homed onto the unified-surfaces substrate later"). It is **not** perception (D-C1: perception is the AI-debugging surface, `GridExplorationHost`, deliberately untouched here).

---

## 1. Goal (the actual need)

Nico's only visibility into the running factory today is watching his own Claude session-window token burn and asking the assistant. The station runs resident (`space up --no-dry-run --land`, 3 substations) and there is **no operator view of what it is building**. The one live signal — the session ledger — is written but unread.

**Deliver:** a Flutter cockpit that answers, at a glance and grid-wide, *is anything being built right now, what, how far along, at what cost, and did it land or get gated* — reachable over the LAN, not just the station's own machine.

## 2. Non-goals (v1)

- **No feeding/acting.** Watch-only. No gate-resolve, rework, or frontier-bless from the UI (deferred; the mutation seam is `StationBeadWriter`, coexistence-sensitive).
- **No perception / leonard / DevTools.** Separate surface, separate concern.
- **No public/internet reach.** LAN only. No genesis `consent` layer yet (a static token stands in — §8).
- **No metrics export (OTel/VictoriaMetrics).** That's the other half of ADR-0012; the cockpit reads the ledger, it doesn't emit spans.

## 3. Shape (one paragraph)

A **separate server** (bound to the LAN) reads the session ledger reactively and serves a projected, grid-wide activity feed to **thin Flutter clients** over HTTP (snapshot) + WebSocket (deltas). The client renders; it holds no `beads_dart`/Dolt. The server is the re-homed, LAN-bound, feed-extended `StationControl`.

## 4. Architecture / topology

The server needs the **live session cursors** (the state store) AND **work-bead titles/types** (each substation's work store) to render "building `tg-6nf`: _<title>_". The resident station already holds both — it composes the reactive `GridControllerRuntime` over the state store and drives every work store.

**DECIDED (Nico, 2026-07-11) — server lives IN the station process** (extend `StationControl`), because it already owns the live reactive state; a sidecar would re-open the state store + all N work stores and duplicate the read stack.

- **Rejected alternative — standalone sidecar.** Upside was independent lifecycle + serving *history* while the station is down. But "station down" is exactly when *nothing is building*, so the client just shows `offline` (failed connect / stale lock); history-while-down isn't worth the duplicated read stack for v1.
- **Read-only, no mutation endpoints by construction** (RS-4 invariant preserved).

## 5. The read model + wire contract (the core deliverable)

Everything below is a projection over types that already exist: `SessionProjection` / `CircuitCursor` / `NodeCursor` / `StepState` (`grid_engine/lib/src/domain/session_bead.dart` + `sdk/circuit.dart`), the per-node `grid.result.*` payloads, and `StationStatus` (`grid_cli/lib/src/station_control.dart`). A shared **freezed contract package** defines the wire types so server and client can't drift.

### 5a. `CircuitTopology` (sent per circuit, in the snapshot)
The station runs **more than one circuit** — the `specify` circuit (`specify` → `spec_review/{acceptance-testability, adr-alignment, coherence, plan-completeness}`) AND the `code` circuit (`kCodeCircuit` → `code_review` → `landing`); a given session belongs to one stage. Each is `{id, nodes:[{path,label,dependsOn[]}], terminal}`; the snapshot carries the topologies in play and each `SessionView` names its `circuitId`. Sending topology keeps the **client asset-agnostic** — it renders a generic pipeline for whatever formula(s) the station runs (matches "the grid is a framework"), not a hard-coded code-only view. Sourced from the mounted circuits, not the UI.

### 5b. `SessionView` (one per open + recent-closed session)
```
sessionId, workBeadId, substation,          // substation from session `rig` key / bead prefix
title,                                       // joined from the work bead
status: open | closed,
phase,                                       // derived: the active (running/ready/gated) node, or terminal
verdict,                                     // route.verdict when closed (advance | gated:<reason>)
startedAt, closedAt, elapsedMs,
nodes: [ NodeView ],
totals: { costUsd, tokensIn, tokensOut, prUrl }   // summed across nodes; pr from land
NodeView = { path, label, state,             // state ∈ pending|running|ready|complete|failed|gated
             startedAt, finishedAt, durationMs, failureReason,
             grade?, transport?, rationale?,         // committee lanes
             costUsd?, numTurns?, tokensIn?, tokensOut?, harnessDurationMs?,  // FT-2, claude harness only
             model? }                                // §9 prereq — else null
```

### 5c. Messages (server → client)
- **`snapshot`** (on connect): `{ station: StationStatus, topology: CircuitTopology, sessions: [SessionView], contractVersion }` — full current state.
- **`delta`** (push): `sessionOpened{SessionView}` · `nodeChanged{sessionId, node: NodeView}` · `sessionClosed{sessionId, verdict, totals}` · `gateOpened{sessionId, workBeadId, node, reason}` · `statusTick{StationStatus}` (header/ready-count refresh) · `serverClosing`.
- The delta feed is driven by the runtime's existing reactive stream (`runtime.events` / `runtime.snapshots`, the `.beads/` FS-watcher, sub-second) — no new polling loop.

## 6. Transport

**DECIDED (Nico, 2026-07-11) — HTTP + WebSocket** on the same `dart:io` `HttpServer` `StationControl` already uses:
- `GET /status` — the existing `StationStatus` (kept, unchanged).
- `GET /sessions` — the `snapshot` payload (poll fallback / cold read).
- `WS /stream` — the `delta` feed (a WebSocket upgrade on the same server).
- SSE (one-way, simpler) and **MQTT** were the alternatives; WS chosen. It's the **same "impl #1" HTTP/WS grain federation uses** behind its bus seam (ADR-0011:75) — MQTT is a federation-bus/asset-layer concern that isn't built even there (`InMemoryBroker` ships; MQTT is future; **"no MQTT in the engine, ever"** D-B5). If a unified-surfaces substrate incl. an MQTT face (the D-C5 "want") ever lands, the cockpit re-homes behind this contract with no rework. Cheap to revisit.

## 7. Discovery on the LAN

The client can no longer read the 0600 `station.lock` (it's on another box).
**DECIDED (Nico, 2026-07-11) — mDNS/Bonjour advertisement** (`_grid-cockpit._tcp`, service TXT carrying `contractVersion`), with a **manual `host:port` fallback** in the client. Org precedent: the whiteboard Pi discovery is mDNS. The station keeps writing `station.lock` for the local `space status` path.

## 8. Auth / consent on the LAN

Loopback used a per-boot token in the 0600 lock (unreadable off-box).
**DECIDED (Nico, 2026-07-11) — a static, operator-provisioned bearer token** (station reads it from `--cockpit-token`/config or a `~/.grid/` file; operator pastes the same token into the client once). Keeps RS-4's "auth before routing, no unauthenticated liveness" posture; binds to LAN interfaces, never `0.0.0.0`-to-internet.

- **Deferred — genesis `consent`.** The real ADR-0012 story ("consent gates exposure") replaces the static token later. Out of scope now; the token is the seam it slots into.

## 9. Prerequisite instrumentation — persist the model per node

Today the ledger records cost/tokens/duration but **not which model produced them** (only `harnessDurationMs`). The coder-vs-committee model+cost split matters (RS-3: Sonnet critics ≈ 2.6× cost story). Small add: write the resolved `AgentConfig.harness` + `model`/`ModelTarget` into `grid.result.<node>.{harness,model}` at spawn (capture-only, alongside the FT-2 usage merge). Then `NodeView.model` is real. **DECIDED (Nico, 2026-07-11) — folded in as a prereq bead** (C-0; a one-field write at the existing chokepoint).

## 10. Package layout (proposed)

- **`grid_cockpit_contract`** — freezed wire types (`SessionView`, `NodeView`, `CircuitTopology`, messages). Pure Dart, shared by server + client. (Home: the_grid repo, next to `grid_engine`.)
- **Server** — extend `grid_cli`'s `StationControl` (or a new `grid_cockpit_server` lib it composes); the projection lives here (`projectSession` → `SessionView`, joined against work beads).
- **`grid_cockpit`** — the Flutter client app (predictable-flutter: Services→Repositories→Interactors→View, `StateNotifier`+freezed). Its one Service is a WS/HTTP client to the server; no `beads_dart`.

## 11. Decisions (ratified — Nico, 2026-07-11)

1. **Server topology** — **in-station** (extend `StationControl`). Sidecar rejected.
2. **Auth** — **static operator-provisioned bearer token** for v1; genesis `consent` deferred.
3. **Discovery** — **mDNS advertise + manual `host:port` fallback**.
4. **Transport** — **HTTP + WebSocket** (SSE rejected).
5. **Model instrumentation** — **folded in** as prereq C-0 (`grid.result.<node>.{harness,model}`).

Settled earlier: separate LAN server, thin Flutter client (no `beads_dart`), watch-only v1, grid-wide, the §5 wire contract. **Zero open questions.**

## 12. Rough build order (for Fable to decompose, post-ratification)

- **C-0 (prereq):** persist `harness`+`model` per node at the chokepoint (§9).
- **C-1:** `grid_cockpit_contract` — the freezed wire types + `contractVersion`.
- **C-2:** the server projection — `SessionView`/`CircuitTopology` from `projectSession` + work-bead join; unit-tested against fixture session beads.
- **C-3:** transport — `GET /sessions` + `WS /stream` on the station's server, LAN bind + static-token auth; the reactive runtime → delta bridge.
- **C-4:** discovery — mDNS advertise + client resolve + manual fallback.
- **C-5:** the Flutter client — now-building strip, recent-activity feed, rollups (burn/pass-rate), filters (substation/phase/verdict).
</content>
</invoke>
