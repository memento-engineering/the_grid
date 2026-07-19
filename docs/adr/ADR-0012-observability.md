# ADR-0012 — Observability (perception ⊥ telemetry; the LAN activity cockpit)

**Status:** **Proposed — PARTIAL / UNRESOLVED.** This ADR is *opened*, not settled. Exactly **one slice is ratified: Decision 1 (the LAN activity cockpit — a read-only observability transport over the session ledger), Nico 2026-07-11.** Observability at large — OTel export, perception co-emission, cross-federation health, the unified-surfaces substrate, `consent` — remains **reserved/open** (see § Open questions). Fulfils the **ADR-0012 "Observability"** number Nico assigned (`the_grid/CLAUDE.md`, 2026-06-27); it does **not** close it.
**Date:** 2026-07-11
**Deciders:** Nico Spencer (ratified Decision 1's calls in the 2026-07-11 design session). Drafted by AI per the register rule; the balance of this ADR is undecided and awaits future design.
**Source of record:** `docs/SCRATCH-cockpit.md` (the cockpit design surface — full wire contract + the ratified decisions); `docs/SCRATCH-vnext-prd.md` §8 (the original observability framing).
**Builds on / relates to (explicit):**
- **ADR-0008 (perception + consent)** — observability is a *sink* under the same perception/consent posture; the cockpit's static-token auth is the seam genesis `consent` later replaces.
- **ADR-0011 (Federation)** — restates **perception ⊥ observability**; the federation *bus* (HTTP/WS impl #1, MQTT long-run, **D-B5 "no MQTT in the engine"**) and the observability *transport* are distinct channels that may later share one unified substrate.
- **ADR-0007 / ADR-0009** — the session ledger (per-node reentrant cursor + `grid.result.*`) and the Allocation tree are the observed sources this reads; a mount→unmount is co-emittable as a span AND a perception delta.
- **RS-4 `StationControl` / `SCRATCH-resident-station.md` D-C5** — the read-only loopback control surface this decision re-homes onto the LAN ("a floor — re-homed onto the unified-surfaces substrate later").

---

## Context

`SCRATCH-vnext-prd.md` §8 framed observability as: **observable-source is a first-class engine primitive** (bd, runtime lifecycle, timers, governors — one shape, projected into observed state a Seed reconciles against), and **OTel ⊥ perception are two sinks on one reconcile-event stream** — a WorkBead mount→unmount *is* a span AND a perception-tree delta; they fight only if one becomes the *source* of the other. OTel = AOT, system-wide, cross-federation prod health; perception = machine-to-AI, per-station, JIT. **That whole design is unbuilt and unresolved.**

What forced an early slice: the operator has **no view of the running factory** — the only live signal is watching his own Claude session-window token burn and asking the assistant. The session ledger (`space_station/.grid/.beads/`, the `type=session` beads) already records every unit of work + its per-node phase, cost, tokens, grades, and PR — grid-wide across substations — but nothing reads it. A **watch-only operator cockpit** over that ledger is high-value and low-risk, and it is the LAN/watch corner of this ADR. It is designed in full in `SCRATCH-cockpit.md`; this ADR promotes only its load-bearing decisions and leaves the rest of observability open.

## Decision 1 — the LAN activity cockpit (RATIFIED, Nico 2026-07-11)

A **read-only observability transport over the session ledger** + a thin Flutter client. The load-bearing, ratified calls (full contract + rationale in `SCRATCH-cockpit.md`):

- **Scope** — watch-only, grid-wide (all owned substations). No acting/feeding (deferred). Not perception, not DevTools, not OTel.
- **Server = in-station**, extending RS-4 `StationControl` (already owns the live reactive runtime + every work store), bound to the **LAN** (not loopback). Read-only, no mutation endpoints by construction.
- **Transport = HTTP + WebSocket** — `GET /status` (kept), `GET /sessions` (snapshot), `WS /stream` (deltas). The **same "impl #1" HTTP/WS grain federation uses** behind its bus seam (ADR-0011); SSE and MQTT-now were considered and rejected for v1 (MQTT is asset-layer + unbuilt even for the bus; D-B5). If a unified substrate incl. an MQTT face (the D-C5 "want") lands later, the cockpit re-homes behind its contract with no rework.
- **Wire contract** — a freezed `grid_cockpit_contract` serializing the existing `SessionProjection`/`NodeCursor`/`StepState` + `grid.result.*` + `StationStatus`, plus the **circuit topology** (client renders a generic pipeline for whatever formula runs — asset-agnostic).
- **Auth = a static, operator-provisioned bearer token** (LAN trust); genesis **`consent`** is the deferred replacement.
- **Discovery = mDNS** (`_grid-cockpit._tcp`) + a manual `host:port` fallback.
- **Prereq** — persist the resolved `harness`+`model` per node at the `StationBeadWriter` chokepoint (capture-only), so cost/tokens gain model attribution.

This decision **does not touch the engine** (asset-agnostic contract; the server is runner-shell, not engine — consistent with "no bus/telemetry machinery in the engine").

## Open questions — RESERVED, not decided by this ADR

1. **OTel export half** — AOT-native metrics/logs/traces → an OTLP sink (VictoriaMetrics/Logs, as gc already does in Go): the cross-federation prod-health view. The cockpit *reads* the ledger; it does not emit spans. Undesigned.
2. **Perception co-emission** — whether/how one reconcile event co-emits as an OTel span AND a perception delta from a single stream (§8). Undesigned.
3. **Cross-federation health** — a multi-station observability view over ADR-0011's bus. Out of scope of the LAN/single-station cockpit.
4. **The unified-surfaces substrate** — whether perception / control-plane / MQTT / CLI+RPC collapse onto one substrate (RS-4 D-C5). The cockpit is built as a *floor* on the assumption they might; the substrate itself is undecided.
5. **`consent`** — the genesis authorization layer that replaces the static token. A separate genesis thread.
6. **Observable-source as an engine primitive** — the §8 claim that bd/runtime/timers/governors are one projected shape. Aspirational; unbuilt.

**Status remains Proposed.** Only Decision 1 is ratified; resolving this ADR means designing 1–6.
</content>
