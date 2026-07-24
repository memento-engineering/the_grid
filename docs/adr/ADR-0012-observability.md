# ADR-0012 — Observability (perception ⊥ telemetry; the LAN activity cockpit)

**Status:** **Proposed — PARTIAL / UNRESOLVED.** This ADR is *opened*, not settled. Two slices are now ratified: **Decision 1 (the LAN activity cockpit — a read-only observability transport over the session ledger; Nico 2026-07-11)** and **Decision 2 (the engine-tree diagnostics projection — a self-describing, pull-free walk of the live `genesis_tree` carried out over pluggable reporters; Nico 2026-07-18, through the `tg-0ds` decomposition).** Observability at large — OTel export, perception co-emission, cross-federation health, the unified-surfaces substrate, `consent` — remains **reserved/open** (see § Open questions). Fulfils the **ADR-0012 "Observability"** number Nico assigned (`the_grid/CLAUDE.md`, 2026-06-27); it does **not** close it.

*[2026-07-20 — tg-8gv.8 (public-readiness): citation-form edits only in this document — retired SCRATCH design filenames re-annotated to their git-history fate. No decision text altered. Review: the flip commit's diff.]*
**Date:** 2026-07-11
**Deciders:** Nico Spencer (ratified Decision 1's calls in the 2026-07-11 design session). Drafted by AI per the register rule; the balance of this ADR is undecided and awaits future design.
**Source of record:** `docs/SCRATCH-cockpit.md` (the cockpit design surface — full wire contract + the ratified decisions); `docs/SCRATCH-diagnostics-projection.md` (the engine-tree diagnostics design surface — Decision 2's full model, mechanism, transport seam, and wire contract; ratified through decomposition 2026-07-18); `docs/SCRATCH-vnext-prd.md` (retired to git history — tg-8gv.8) §8 (the original observability framing).
**Builds on / relates to (explicit):**
- **ADR-0008 (perception + consent)** — observability is a *sink* under the same perception/consent posture; the cockpit's static-token auth is the seam genesis `consent` later replaces.
- **ADR-0011 (Federation)** — restates **perception ⊥ observability**; the federation *bus* (HTTP/WS impl #1, MQTT long-run, **D-B5 "no MQTT in the engine"**) and the observability *transport* are distinct channels that may later share one unified substrate.
- **ADR-0007 / ADR-0009** — the session ledger (per-node reentrant cursor + `grid.result.*`) and the Allocation tree are the observed sources this reads; a mount→unmount is co-emittable as a span AND a perception delta.
- **`docs/SCRATCH-diagnostics-projection.md` (ratified through decomposition 2026-07-18; beads `tg-0ds.1`–`.8`)** — the engine-tree diagnostics projection Decision 2 records. **ADR-0009 §5's "Feeds ADR-0012 (observability — the sinks over the topology)" IS this seam:** the Allocation tree is projected as host-node *properties*, never as Branch nodes.
- **RS-4 `StationControl` / `SCRATCH-resident-station.md` D-C5** — the read-only loopback control surface this decision re-homes onto the LAN ("a floor — re-homed onto the unified-surfaces substrate later").

---

## Context

`docs/SCRATCH-vnext-prd.md` (retired to git history — tg-8gv.8) §8 framed observability as: **observable-source is a first-class engine primitive** (bd, runtime lifecycle, timers, governors — one shape, projected into observed state a Seed reconciles against), and **OTel ⊥ perception are two sinks on one reconcile-event stream** — a WorkBead mount→unmount *is* a span AND a perception-tree delta; they fight only if one becomes the *source* of the other. OTel = AOT, system-wide, cross-federation prod health. **That whole design is unbuilt and unresolved** — except the tree-projection slice, now settled in **Decision 2**.

*[Corrected 2026-07-18 — Decision 2: the original draft closed the sentence above with "perception = machine-to-AI, per-station, JIT," which conflated a **projection** with a **transport**. Perception (genesis's reactive `serializePerceptionFragment` model) and the engine-tree diagnostics projection (Decision 2) are two **distinct projections**, both sinks — perception ⊥ the tree projection. "JIT" vs "AOT" is a **transport** axis orthogonal to either: the pull-free, AOT-safe tree projection rides the JIT VM-service wire AND an AOT LAN socket with the **same payload**. A projection is not defined by the transport that carries it.]*

What forced an early slice: the operator has **no view of the running factory** — the only live signal is watching his own Claude session-window token burn and asking the assistant. The session ledger (`space_station/.grid/.beads/`, the `type=session` beads) already records every unit of work + its per-node phase, cost, tokens, grades, and PR — grid-wide across substations — but nothing reads it. A **watch-only operator cockpit** over that ledger is high-value and low-risk, and it is the LAN/watch corner of this ADR. It is designed in full in `SCRATCH-cockpit.md`; this ADR promotes only its load-bearing decisions and leaves the rest of observability open.

## Decision 1 — the LAN activity cockpit (RATIFIED, Nico 2026-07-11)

A **read-only observability transport over the session ledger** + a thin Flutter client. The load-bearing, ratified calls (full contract + rationale in `SCRATCH-cockpit.md`):

- **Scope** — watch-only, grid-wide (all owned substations). No acting/feeding (deferred). Not perception, not DevTools, not OTel.
- **Server = in-station**, extending RS-4 `StationControl` (already owns the live reactive runtime + every work store), bound to the **LAN** (not loopback). Read-only, no mutation endpoints by construction.
- **Transport = HTTP + WebSocket** — `GET /status` (kept), `GET /sessions` (snapshot), `WS /stream` (deltas). The **same "impl #1" HTTP/WS grain federation uses** behind its bus seam (ADR-0011); SSE and MQTT-now were considered and rejected for v1 (MQTT is asset-layer + unbuilt even for the bus; D-B5). If a unified substrate incl. an MQTT face (the D-C5 "want") lands later, the cockpit re-homes behind its contract with no rework.
- **Wire contract** — superseded by Decision 2’s shared `grid_diagnostics_contract` tree-projection payload; the cockpit derives its UI-side session, node, and circuit view-models from that payload.
- **Auth = a static, operator-provisioned bearer token** (LAN trust); genesis **`consent`** is the deferred replacement.
- **Discovery = mDNS** (`_grid-cockpit._tcp`) + a manual `host:port` fallback.
- **Prereq** — persist the resolved `harness`+`model` per node at the `StationBeadWriter` chokepoint (capture-only), so cost/tokens gain model attribution.

This decision **does not touch the engine** (asset-agnostic contract; the server is runner-shell, not engine — consistent with "no bus/telemetry machinery in the engine").

## Decision 2 — the engine-tree diagnostics projection (RATIFIED, Nico 2026-07-18)

Observability's **second ratified slice: the running engine tree describes itself, and one or more pluggable reporters carry that description out.** Ratified through the `tg-0ds` decomposition (Nico, 2026-07-18); the full design surface is `docs/SCRATCH-diagnostics-projection.md` (§2–§6), decomposed into beads `tg-0ds.1`–`.8`. This decision records its load-bearing calls. It is **distinct from Decision 1's ledger transport**: Decision 2 reads the **live `genesis_tree`** (the desired running system), not the session-bead store.

- **Model — pull-free projection, not a snapshot-serialize.** The running grid IS a `genesis_tree`; its *desired state* is projected by walking the **live tree, pull-free** (A39 / genesis ADR-0006). A full re-walk per flush yields a complete `TreeSnapshot`; nodes never emit deltas from `build`. This is projection, not perception: it runs **beside** perception, never through it (`serializePerceptionFragment` needs a perception `NodeElement` root; engine Branches serialize empty — ruled out, SCRATCH §2/§4).
- **Mechanism — self-describing, Flutter-faithful (SCRATCH §4).** A **`Diagnosable` mixin** on the engine's own Seeds and States: each overrides `debugFillProperties(builder)` and `super`-chains typed property objects (`StringProperty`, `EnumProperty<T>`, `DurationProperty`, `ReferenceProperty`, …). A **walker** harvests the live tree, calling the hook where the mixin is present; **non-`Diagnosable` nodes are transparent** (recursed through, their `Diagnosable` descendants hoisted — plumbing `InheritedSeed`s and container branches vanish). No registry, no describe table, no inventory. This is the engine's *internal* introspection mixin — ADR-0008 D2's "compose, never subclass" governs the *consumer* boundary, not this.
- **Engine-first structure (SCRATCH §3).** Every circuit step mounts as a tree node; the effect child (`CapabilityHost`) mounts beneath its step node only while the step is on the frontier. The pipeline IS `children` — no cursor-as-properties bridge enters the contract. `tg-0ds.1` is the engine prerequisite, behind the flat-cursor retirement `tg-eli`.
- **Transport seam — observable source (SCRATCH §5).** `TreeProjector` is an **optional kernel-owned seam** (null = zero cost). `StationKernel` retains the root `Branch` and calls `projector.afterFlush(root)` in the flush microtask; the projector re-walks **once** per flush and exposes `latest` (connect-time replay) + a **broadcast `Stream<TreeSnapshot>`**; `projectedAt` is stamped from an injected clock, never inside the pure walk.
- **Reporters — pluggable, same payload.** Reporters compose **beside** the kernel and subscribe; the kernel never learns what transports exist. Two bindings, **one payload**: **(a) the VM-service exploration wire** (JIT dev loop — DevTools + leonard; `tg-0ds.5`) and **(b) a LAN WS/HTTP socket** (AOT builds + the cockpit; `tg-wisp-5xa` C-3). This is the **same "impl #1" HTTP/WS grain** Decision 1's cockpit and ADR-0011's federation bus use — one payload over many transports, the correction Decision 2 makes concrete against the Context conflation above.
- **Wire contract — typed, sealed (SCRATCH §6).** `grid_diagnostics_contract` carries `TreeSnapshot { contractVersion, projectedAt, root }` + `TreeNode { seedType, id, key, properties, children }` + a **sealed freezed `DiagnosticsProperty` union** (`string | int | double | flag | enumValue | duration | timestamp | reference | object`), each carrying `name` + `level`. Consumers **switch exhaustively**. Adding a **property** is data; adding a property **kind** is a `contractVersion` bump. This IS `tg-wisp-5xa`'s C-1; it **supersedes** `SCRATCH-cockpit.md`'s `SessionView`/`NodeView`/`CircuitTopology` wire types (now UI-side view-models over the tree).

Like Decision 1, this **touches the engine only at an optional seam** — the `TreeProjector` hook is null by default; the projection is pure/AOT-safe; the reporters and the wire contract live outside the engine core. **Extraction of the `Diagnosable`/walker to genesis is deferred** (the org dependency arc, cf `genesis_tmux`); the projection is grid-local for now.

## Open questions — RESERVED, not decided by this ADR

1. **OTel export half** — AOT-native metrics/logs/traces → an OTLP sink (VictoriaMetrics/Logs, as gc already does in Go): the cross-federation prod-health view. The cockpit *reads* the ledger; it does not emit spans. Undesigned.
2. **Perception co-emission** — whether/how one reconcile event co-emits as an OTel span AND a perception delta from a single stream (§8). Undesigned.
3. **Cross-federation health** — a multi-station observability view over ADR-0011's bus. Out of scope of the LAN/single-station cockpit.
4. **The unified-surfaces substrate** — whether perception / control-plane / MQTT / CLI+RPC collapse onto one substrate (RS-4 D-C5). The cockpit is built as a *floor* on the assumption they might; the substrate itself is undecided.
5. **`consent`** — the genesis authorization layer that replaces the static token. A separate genesis thread.
6. **Observable-source as an engine primitive** — the §8 claim that bd/runtime/timers/governors are one projected shape. **Decision 2 realizes ONE instance** of this primitive — the *tree projection* as an observable source (the `TreeProjector` seam) — but the broad §8 unification (bd/runtime/timers/governors as one projected shape) stays aspirational and unbuilt.

**Status remains Proposed.** Decisions 1 and 2 are ratified; resolving this ADR means designing the remaining open questions 1–6.
</content>
