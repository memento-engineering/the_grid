# SCRATCH — Federated Asset Management + Cross-Substation Coordination

> **Status: DESIGN BRAINSTORM (doc-before-code).** Not ratified. Nico ratifies
> explicitly; homes are ADR-0011 (federation) + ADR-0008 amendments (asset
> taxonomy / resource governance) + a milestone build-order. No code until the open
> questions are closed.

## Thesis

The grid manages a **portfolio of assets**, and **an agent is just one asset
class**. Federation exists to **lease and coordinate assets across stations** — the
core primitive is *resource leasing*, not multi-agent fan-out. A single-agent Burn
still needs to *lease time on the other box* to run.

## Vocabulary (SETTLED — Nico, 2026-06-29)

**`Asset`** is the umbrella for everything the grid manages, in two families:

| Family | What | Status |
|---|---|---|
| **Content / capability assets** | the `*_grid_assets` packs — capabilities, formulas, rubrics, prompts (ADR-0008 `Asset`) | shipped; unchanged |
| **Resource / capacity assets** | leasable **compute** (a box/processor), **agent slots**, **humans via HITL** | NEW — this milestone |

**Asset Management** = the discipline over the whole portfolio. This taxonomy adds
the second family *without* renaming the shipped term (ADR-0008 stays intact).

## What we already have (the primitives line up)

- **HITL = a human-attention lease.** The **gate** primitive (ADR-0008 D-7, shipped
  M5) parks work until a human acts — that IS leasing a human asset. (`grid gate
  ls/resolve`, just built, is its operator surface.)
- **Agent spawn = a compute lease.** Today implicit + local; federation makes it
  explicit + remote.
- **Burn = lease remote compute, run the agent/tests there, collect the result.**
- **Lease ≈ a Capability in the reentrant engine** — mount = acquire, unmount =
  release; leases reconcile like every other node. Keeps the model uniform.

## The resource-asset model (DRAFT — open)

A resource asset plausibly carries: `id`, `kind {compute | agent-slot | human}`,
`station` (where it lives), `capacity`/availability, and a **lease lifecycle**:
`request → grant|deny → hold (with a TTL/heartbeat) → release|reap`. Open: the exact
shape, who owns lease state (lessee vs lessor store), and TTL/heartbeat semantics
(see ADR-0011 claim-in-own-store + presence/heartbeat).

## Cross-substation coordination (DRAFT — open)

Needs: **presence/discovery** (which stations exist, what each offers), **lease
negotiation** (request/grant/release across the wire), **failure handling**
(timeout, disconnect → reap leases). Maps onto ADR-0011's parked design (per-station
views, lossy inter-station bus + dolt-truth, claim-in-own-store, presence/heartbeat
+ disconnect-gossip, reaping). The transport is an OPEN question (reuse the
`ext.exploration.*` WS seam? a dedicated bus? shared-dolt truth?).

## Coexistence / safety carried forward

A37 (read-only foreign work source; own state in own store), the codec boundary,
gc-coexistence, the chokepoint-only writer — all hold. A remote lease must not let a
station write another's store except through the agreed federation protocol.

## OPEN QUESTIONS (for Nico — drive the design)

1. **MVP / minimal first cut ("mvo").** Smallest useful slice? (e.g. local asset
   declaration+accounting → two-station presence → ONE remote compute lease running
   one agent.)
2. **Lease state ownership + transport.** Where lease state lives; what carries the
   negotiation (exploration WS / dedicated bus / shared dolt).
3. **Resource-asset schema.** The concrete value-type(s) + how a station declares
   its assets (TOML? a config asset? `DartEnvironment`/governor extension?).
4. **HITL formalization.** Generalize the gate into a typed human-asset lease now,
   or keep gate as-is and add it later?
5. **Doc/milestone home.** New milestone (M6?) + its own PRD, or fold into ADR-0011
   + an ADR-0008 amendment for the asset taxonomy?

## MVP — the loopback thin slice (SETTLED scope, Nico 2026-06-29; design = PROPOSAL)

**Goal:** Station A *leases a compute slot from* Station B and dispatches a **GENERIC
command** (a build/test/shell step — **NO inference on B this pass**, per Nico) to run
there, collects the result, releases. **Loopback first** (two `grid` procs on this
box) to de-risk the protocol, then **cross-machine to the real Dashboard =
`linux-dashboard.local`** (on the LAN) — the **EOD deliverable**. The remote work
being a generic `ProcessCapability` (not `claude`) doubles as the start of "make the
coding capability generic" + "integration tests across two devices."

**Two roles:**
- **B = lessor** (`grid serve`, NEW): declares offered capacity (e.g.
  `--offer compute:1`), accepts lease requests, grants/denies by declare-and-check,
  EXECUTES the dispatched command (a **generic process — NO claude/inference this
  pass**) in its own space, streams status + result, frees the slot on release/TTL.
- **A = lessee**: has a work bead needing an agent but, instead of spawning locally,
  **leases a slot from B** (configured peer, e.g. `--peer localhost:PORT`) and
  dispatches the agent there.

**Lease lifecycle (value model, DRAFT):**
`LeaseRequest{lessee, kind:agent-slot, spec}` → B declare-and-check →
`LeaseGrant{leaseId, ttl, station:B}` | `LeaseDenied{reason}` → A dispatches the
agent spec → B runs it, streams events → result (commit ref/outcome) → A releases →
B frees. TTL/heartbeat reaps an abandoned lease.

**Engine modeling:** the lease is a **Capability on A** (mount = acquire+dispatch,
unmount = release) — a "remote agent" is just a capability that runs elsewhere. B
runs its own engine to execute the leased work. Both sides stay uniform with the
reentrant model.

**State ownership (ADR-0011 claim-in-own-store):** A records its lease *claim* in A's
store; B records the *grant* + the running session in B's store. Per-station dolt =
truth; the wire is the lossy bus carrying negotiation + events. (Loopback = two
separate state stores on one box.)

**Transport — DECIDED (Nico 2026-06-29): HTTP/WS this pass, behind a pluggable
*bus* seam.** Per-station dolt = truth (ADR-0011); HTTP/WS carries the lossy bus now.
A true pub/sub bus with channels (MQTT) is the likely long-run impl — so the bus is
an **abstract seam** (ADR-0008 pluggable-transport meta-pattern) with HTTP/WS as
impl #1, MQTT droppable in later with no rework.

**Acceptance (loopback, offline):** start B `--offer agent-slot:1`; A drives a bead
→ requests → B grants → B spawns the agent → A receives the result (a commit in B's
space) → A releases → B's slot frees. Plus: deny-when-no-capacity; TTL reaps an
abandoned lease. Coexistence-safe (A never writes B's store except via the lease
protocol; chokepoint discipline per side; gc untouched).

## Homes (proposed)

- Asset taxonomy + resource governance → **ADR-0008 amendment**.
- Federation / cross-substation leasing → **ADR-0011** (currently parked/unwritten).
- Observability of assets/leases → **ADR-0012** (the flare/perception seam).
