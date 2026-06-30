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

## Federation design — decisions so far (Nico, 2026-06-29)

- **Contracts are DOMAIN-DEFINED.** The asset + lease agreement is a contract owned
  by the domain it belongs to: abstract at the engine (ADR-0008
  pluggable-abstract-domain seam), concrete in the asset. The engine never hardcodes
  a generic lease/lessor; a station composes only the asset domains it serves. (This
  retires the mis-framed "standalone lessor" finding — see Spike findings #2.)
- **Membership = STATIC this round** — each station's config lists its peers
  (addresses/keys/token). Deterministic, no-center, works today; grow by editing
  config. Design the membership seam so discovery drops in behind it.
- **Dynamic discovery is a LATER ASSET: `zero_conf_grid_assets`** (zeroconf/mDNS) —
  NOT engine code. This is itself the proof of the domain-contract rule: discovery
  is an asset in its own domain, not baked into the engine.

### Capability composition (the burn drove this out — Nico, 2026-06-29)

- **Capabilities are composable, cascading config — and the cascade IS the tree.**
  Config nodes are ancestors of work nodes (M4 `InheritedSeed`, nearest-wins).
  Composing extensions/asset-domains in order stacks config ancestors; an **order**
  reads its *effective* capability profile by lookup. No new cascade machinery.
- **Derived defaults kill the redundancy:** `flutter-target ⟸ dart-target ⟸
  system-os` — inherit the nearest value unless overridden; only divergence (a
  cross-compile / multi-target host) is restated.
- **Per-fact composition semantics, declared by the fact's DOMAIN:** scalar facts
  override (nearest `system-os` wins); **set** facts accumulate (`radio` unions;
  **targets are SET-valued** — `flutter-target={linux,android}`).
- **Matching = generalized declare-and-check, by CONTAINMENT** (`station.facts ⊨
  order.requires`): scalar ⇒ equality, set ⇒ membership/⊆. The resource went from a
  scalar count to a **capability-profiled slot** — that is what "federated
  resources" means (heterogeneous, matched by capability).
- **PROBED + DYNAMIC for `system-os` / `dart-target` / `flutter-target`** (probe the
  `dart`/`flutter` toolchain; targets are sets); other facts static now,
  probe-capable later. **GOAL: prove out dynamic/shifting configurations** — a
  probed capability is a `StateNotifier`, the cascade is `InheritedSeed`, so a shift
  → re-match → the engine reconciles. Dynamic config is where the reactive engine
  earns its keep.
- **Shift-revocation depth = re-validate at TTL renewal (#2).** A shift re-places
  *pending* orders immediately (the reactive cascade); an *active* lease re-checks
  its match at each TTL renewal, so a station that LOST a required capability fails
  renewal → the lease lapses → the order re-places on another match. Bounded by the
  TTL, reuses the existing lease mechanism — no continuous-watch / live-migration.
  (Continuous park/migrate is a later depth once migration is real.)
- **Vocabulary lives in the domain assets** — os/dart/flutter/radio each own their
  facts + probes; a station's profile is the union of the asset domains it composes.

### Truth + coordination (Nico, 2026-06-29)

- **Ownership-partitioned, owner-authoritative.** The resource-owning station is the
  single authoritative writer for its slots + capability profile (its dolt = truth);
  peers only cache/observe. Conflicts: **owner wins** for real state;
  **heartbeat-timestamp, last-known-from-owner wins** for gossiped liveness. The
  owner's own declare-and-check at grant time is the serialization point → **no
  double-grant, no consensus protocol.** Same principle the_grid already lives by:
  single-writer-per-bead (bd/gc coexistence) + A37 (write only your own store).
- **Future topologies — allowed, NOT designed now:** two stations co-owning a
  pooled asset (one machine's resources mirrored on both); peer-to-peer / 1:1; a
  peer bridging another peer's assets into a federation as its own. Owner-authority
  is the floor; richer topologies layer on later. (Flagged so the model doesn't
  preclude them — the flexibility is the point.)

### The burn — host↔follower coordination (Nico, 2026-06-29)

The burn = a formula (in `butane_grid_assets`) that pours two capability-scoped
orders and wires a drive channel between them:

- **`burn-follower`** — requires `{system-os=linux, flutter-target=linux,
  radio=ble}` → leased to a matching peer. Its execution: provision the
  app-under-test from the **butane substation**, build for the target, **launch it
  exposing `ext.exploration.*`** (the app embeds `leonard_flutter`), **publish its
  VM-service/exploration endpoint**, and tear it down on release.
- **`burn-host`** — requires `{system-os=macos, agent, radio=ble}` → local. Awaits
  the endpoint, attaches **`leonard_drive`** (credential-free, zero-model; proven in
  A40/tg-e28), runs the scenario, asserts, collects a (domain-defined) TestReport.

**Two orthogonal channels (the key structural call):**
- **Federation bus = rendezvous + lifecycle** (lossy): lease → grant → the follower
  *publishes its endpoint* → release/teardown. Low-frequency.
- **Drive = direct perception**: `leonard_drive` ↔ the follower app's
  `ext.exploration.*` over its VM service, point-to-point on the LAN. High-frequency,
  ordered, live — **NOT tunneled through the bus.** Matches ADR-0012 perception ⊥
  observability: the bus coordinates *resources*; lenny/perception is the channel for
  the *actual test*.

**Engine/domain separation (Nico):** the engine provides primitives (lease, bus,
rendezvous); **butane owns persist/maintain/execute** for its domain (build, launch,
expose, teardown), pulling whatever primitives + dependent domains it needs.

- **Drive = SCRIPTED** via `leonard_drive` (zero model — no inference on either box;
  a real regression). **FUTURE formula (not now):** an **agent-to-agent burn** that
  simulates two users communicating over BLE — higher-level, more assets to lease +
  coordinate (the Dashboard's `llama-server` can power that driver once it's
  provider-pluggable).
- **App lifecycle = the follower's execution** (build/launch/expose/teardown).
- **Trust = LAN-trust now;** authentication/authorization are extensions for another
  day (pluggable `Trust`, not this pass).
- **Heads-up:** the burn's app-under-test is the live `butane_flutter` (it just
  updated) — its current state matters at the follower's BUILD time, not to this
  design.

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

## Spike results — POINT-TO-POINT, not federation (DONE 2026-06-29, parked)

A `grid_federation` package + `grid serve`/`grid lease` were built and the
**cross-machine lease was proven live**: from the Studio (macOS) a slot was leased
on `linux-dashboard.local` (Linux) and `uname -a`/`hostname` were dispatched + their
output returned (`Linux linux-dashboard … x86_64`, `linux-dashboard`), full
lifecycle (presence→lease→dispatch→result→release) twice. Branch `m6-federation`
(pushed to origin + a bare repo on the Dashboard). **This is ONE leasable edge — a
de-risking SPIKE, explicitly NOT federation** (no topology, presence/gossip,
claim-resolution, reaping, bus, or Trust). Nico's course-correction: **design
federation before building it.** The spike is INPUT, not the architecture.

**Findings that must shape the design:**
1. **Deployment / the bus is federation-native git.** The Dashboard has no GitHub
   access and no own SSH keys; only Studio→Dashboard SSH works. So the working
   channel is a **LAN git remote** (Studio pushes to a bare repo on the peer) —
   which IS the "stations as git peers" idea. The auto-mode classifier blocks
   `rsync` to a non-remote host (exfiltration); git-to-a-configured-remote is the
   sanctioned path. → the federation transport/sync story should lean on git over
   the LAN, not ad-hoc copies.
2. **Build hygiene, NOT a federation rule (Nico, 2026-06-29).** The
   `grid_devtools`→Flutter break was a *symptom* of running the lessor through the
   whole workspace, not grounds to mandate a "standalone lessor." The real
   principle: **the asset + lease agreement is a CONTRACT defined in the domain it
   belongs to** — abstract at the engine (the ADR-0008 pluggable-abstract-domain
   seam), concrete in the asset. A station composes ONLY the asset domains it
   actually serves, so a compute-only station never pulls Flutter/devtools; the
   "standalone-ness" falls out of domain-scoping — it is not a separate rule.
3. **The Dashboard already runs local inference** (`llama-server` on :8080). Its
   "own local coding agent" is closer than assumed → reinforces making the coding
   capability **generic / provider-pluggable**, not claude-specific.
4. **Validated primitives** (reusable by the design): the transport SEAM
   (`StationClient`), the lease lifecycle, declare-and-check capacity + TTL, and a
   shared-secret token (LAN trust). HTTP is impl #1; the real bus (MQTT/pub-sub) is
   the design's call.

## Homes (proposed)

- Asset taxonomy + resource governance → **ADR-0008 amendment**.
- Federation / cross-substation leasing → **ADR-0011** (currently parked/unwritten).
- Observability of assets/leases → **ADR-0012** (the flare/perception seam).
