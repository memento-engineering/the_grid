# ADR-0011 — Federation + Asset Management (leasing resources across stations)

**Status:** **Accepted 2026-06-29** (ratified by Nico; drafted by AI from his decisions in the 2026-06-29 design session, per the ADR-0000 register rule). The forward-pointer stamp was **applied on ratification** to **ADR-0008 Decision 2** (the `Asset` definition — extended here to an umbrella, never a silent rewrite). Per the gate — doc before code — implementation proceeds via **`docs/M6-FEDERATION-BUILD-ORDER.md`**; the first LIVE cross-machine arm remains the **human gate**.
**Date:** 2026-06-29
**Deciders:** Nico Spencer (decided each call in the design session; ratifier). Drafted by AI per the register rule.
**Gates:** a federation milestone (number TBD — `docs/SCRATCH-asset-management.md` left this open). Fulfils the **ADR-0011 "Federation"** number Nico assigned (the_grid/CLAUDE.md, 2026-06-27) — per-station `Grid` views; the multi-station story ADR-0008 deliberately deferred.
**Source of record:** `docs/SCRATCH-asset-management.md` (the design surface; this ADR promotes its converged decisions and states the load-bearing ones).
**Builds on / relates to (explicit):**
- **ADR-0008** — makes its reserved **`Grid` = federation** object concrete (Decision 1) and **extends its `Asset`** from "a pack" to an umbrella with two families (Decision 2). Reuses the **pluggable-abstract-domain** meta-pattern and `Trust`.
- **ADR-0007** — the reentrant engine is the substrate: orders/leases are formula steps; capability config cascades via `InheritedSeed`; a shift re-matches through the reactive flush. No engine semantics change.
- **ADR-0012 (Observability, unwritten)** — the burn's drive channel is perception (`ext.exploration.*`), kept orthogonal to the coordination bus ("perception ⊥ observability").

---

## Context

ADR-0008 ratified the single-station authoring model and **named `Grid` as the federation object but deliberately did not design it.** A 2026-06-29 session — driven by Nico's goal of **cross-machine integration tests ("burns") that coordinate resources across two devices** — designed it.

The reframe that organizes everything: **the grid manages a portfolio of *assets*, and an agent is just one asset class.** Compute, agent slots, and humans (via HITL) are all leasable/coordinatable assets. Federation exists to **lease and coordinate assets across stations**; the core primitive is *resource leasing*, not multi-agent fan-out — a single-agent burn still needs to *lease time on the other box*.

A point-to-point lease was spiked first (`grid_federation` on branch `m6-federation`: a station offered a compute slot and a peer dispatched a command to it across the LAN — proven Studio→`linux-dashboard.local`). **That spike is de-risking input, NOT the architecture** (it is one edge, no topology/presence/resolution/reaping/bus/trust). This ADR designs the real thing, doc-before-code.

---

## Decision 1 — `Grid` = the federation object; Asset Management is the discipline

`Grid` (reserved in ADR-0008 D1) is made concrete: **each station's local view of the federation — per-station, no center.** The federation's job is **Asset Management**: declare, match, lease, coordinate, and reap assets across stations.

**Why:** centers don't fit the_grid's existing grain (single-writer-per-bead, A37 own-store writes). A per-station view with owner-authoritative truth (Decision 5) is the same grain applied to resources.

## Decision 2 — `Asset` is an umbrella with two families (extends ADR-0008 D1)

| Family | What | Status |
|---|---|---|
| **Content / capability assets** | the `*_grid_assets` packs (capabilities/formulas/rubrics/prompts) — ADR-0008's `Asset` | shipped; unchanged |
| **Resource / capacity assets** | leasable **compute**, **agent slots**, **humans (HITL)** | NEW (this ADR) |

**Asset Management** is the discipline over the whole portfolio. This **adds the second family without renaming** the shipped term — ADR-0008 stays intact; on ratification its `Asset` definition gets a one-line "see ADR-0011" stamp.

**Why:** Nico's correction — agents and HITL humans are assets/resources too, not a privileged thing; "not *just* federated *agents*." The primitives already line up: **HITL = the gate** (ADR-0008 D-7, shipped M5; `grid gate ls/resolve` is its operator surface) and **agent-spawn = a compute lease** — the burn's spike already exercised the compute case.

## Decision 3 — Contracts are domain-defined; the engine carries only seams

The **asset + lease agreement is a contract defined in the domain it belongs to** — abstract at the engine (the ADR-0008 pluggable-abstract-domain seam), concrete in the asset. The split:

- **Engine owns (abstract, kind-agnostic):** membership, the **lease lifecycle** (request → grant → use → release → reap/TTL), the **bus** transport, presence/heartbeat.
- **Asset domain owns (concrete):** what a *kind* means, the **declare-and-check capacity predicate**, **what "use" executes**, the request/result **payload schema**, and any kind-specific trust.

The engine never knows what "compute" or "burn" *is*; a station composes only the asset domains it serves. A **lease is modeled as a Capability** (mount = acquire, unmount = release) so it reconciles in the tree like every other node (ADR-0007). (This **retires** the spike's mis-framed "standalone lessor must" finding: a compute-only station never pulls Flutter because it never composes that domain — standalone-ness *falls out of* domain-scoping, it is not a rule. Nico: *"butane chooses if/how to persist, maintain, execute its own domain."*)

**Why:** prevents the engine from accreting domain detail (ADR-0007/0008's whole thesis); lets new asset kinds (burn, HITL, GPU…) ship without engine changes.

## Decision 4 — Membership is static this round; discovery is a later asset

Each station's config lists its peers (address/key/token). Deterministic, no-center, works today; grow by editing config. The membership seam is designed so **dynamic discovery drops in behind it as `zero_conf_grid_assets`** (zeroconf/mDNS) — itself the proof of Decision 3 (discovery is an asset in its own domain, not engine code).

## Decision 5 — Truth is ownership-partitioned and owner-authoritative

The **resource-owning station is the single authoritative writer** for its slots + capability profile (its dolt = truth); peers only cache/observe. Conflicts: **owner wins** for real state; **heartbeat-timestamp, last-known-from-owner wins** for gossiped liveness. The owner's own declare-and-check at grant time is the serialization point → **no double-grant, no consensus protocol.** Same principle the_grid already lives by: single-writer-per-bead + A37.

**Allowed but NOT designed now (don't preclude):** two stations co-owning a pooled asset; peer-to-peer / 1:1; a peer bridging another's assets into a federation as its own. Owner-authority is the floor; richer topologies layer later — the flexibility is the point.

## Decision 6 — Capabilities are composable, cascading config; matching is by containment

- **The cascade IS the tree.** Config nodes are ancestors of work nodes (ADR-0007 `InheritedSeed`, nearest-wins). Composing extensions/asset-domains in order stacks config ancestors; an **order** reads its effective capability profile by lookup. No new cascade machinery.
- **Derived defaults** kill redundancy: `flutter-target ⟸ dart-target ⟸ system-os`; only divergence (cross-compile/multi-target) is restated.
- **Per-fact composition, declared by the fact's domain:** scalar facts override (nearest `system-os` wins); **set** facts accumulate (`radio` unions; **targets are set-valued**).
- **Matching = generalized declare-and-check, by CONTAINMENT** (`station.facts ⊨ order.requires`: scalar ⇒ equality, set ⇒ membership). The resource is a **capability-profiled slot**, not a scalar count — that is what "federated resources" means.
- **Probed + dynamic** for `system-os`/`dart-target`/`flutter-target` (probe the dart/flutter toolchain; targets are sets); other facts static now, probe-capable later. A probed capability is a `StateNotifier`; the cascade is `InheritedSeed`; a shift → re-match → reconcile. **Dynamic/shifting config is a first-class goal** — where the reactive engine earns its keep.
- **Shift-revocation = re-validate at TTL renewal (depth #2):** a shift re-places *pending* orders immediately; an active lease re-checks its match at each TTL renewal, so a lost capability lapses the lease at the boundary and the order re-places. Bounded by the TTL; reuses the existing mechanism. (Continuous park/migrate is a later depth, once migration is real.)
- **Vocabulary lives in the domain assets** — os/dart/flutter/radio each own their facts + probes; a station's profile is the union of the domains it composes.

## Decision 7 — Leasing over a pluggable bus

The lease lifecycle (request → grant|deny → use → release → reap/TTL) rides an **abstract bus seam** (`StationClient`). **HTTP/WS is impl #1** (the spike); a true pub/sub bus with channels (**MQTT**) is the likely long-run impl and drops in behind the seam with no rework. Capability-durable / capacity-ephemeral: a station's *capabilities* are durable truth; its *available capacity* is ephemeral and gossiped.

Separately (spike finding #1): **git over the LAN is the federation-native code/asset distribution channel** — a station pushes to a peer's bare repo over SSH ("stations as git peers"); ad-hoc `rsync` is correctly blocked as exfiltration. **Code/asset *sync* rides git; the lease *bus* rides HTTP/WS** (then MQTT) — two distinct channels.

## Decision 8 — Trust is LAN-trust now, pluggable later

A shared secret/token over the LAN this pass. Real authentication/authorization are **pluggable `Trust` extensions for another day** (ADR-0008's pluggable `Trust`).

## Decision 9 — The burn = two capability-scoped orders + two orthogonal channels

The burn (in `butane_grid_assets`) is a formula that pours two orders and wires a drive channel:

- **`burn-follower`** — requires `{system-os=linux, flutter-target=linux, radio=ble}` → leased to a matching peer. Execution: provision the app-under-test from the butane substation, build for the target, **launch it exposing `ext.exploration.*`** (the app embeds `leonard_flutter`), publish its VM-service endpoint, tear down on release.
- **`burn-host`** — requires `{system-os=macos, agent, radio=ble}` → local. Awaits the endpoint, attaches **`leonard_drive`** (credential-free, zero-model; proven A40/tg-e28), runs the scenario, asserts, collects a (domain-defined) TestReport.

**Two orthogonal channels (load-bearing):**
- **Federation bus = rendezvous + lifecycle** (lossy, low-frequency): lease → grant → the follower *publishes its endpoint* → release/teardown.
- **Drive = direct perception**: `leonard_drive` ↔ the follower app's `ext.exploration.*` over its VM service, point-to-point on the LAN, **NOT tunneled through the bus** (perception ⊥ observability, ADR-0012).

**This pass: scripted** drive (zero inference on either box — a real regression). **Later formula (not now):** an **agent-to-agent burn** simulating two users over BLE — higher-level, more assets to lease + coordinate (the Dashboard already runs `llama-server`, so it can power that driver once the coding/driver capability is **generic / provider-pluggable**, not claude-specific).

**Why:** the burn is the headline ("integration tests across two devices, coordinating resources") and it is where federation, lenny/perception, and the butane substation converge: *the grid leases + rendezvouses the devices; lenny drives the app across them.*

---

## Hazards / hard-earned lessons (prior-art-informed)

This design is **cluster-scheduler-shaped** — prior art to mine: k8s (labels/affinity/taints + `Lease` + heartbeats), Nomad (dynamic node **fingerprinting** = our probes), Mesos (**resource offers** = owner-authoritative lease), SLURM/Borg (**gang scheduling** + fair-share/preemption), DHCP (lease/renew/expire), Chubby + Kleppmann (**fencing tokens**), SWIM/Serf (gossip membership). The known hazards + how M6 handles each (minimal, not fair-share):

- **Starvation** — owner-authoritative first-come + TTL *renewal* lets an incumbent renew forever / a greedy lessee monopolize. **M6: a max lease lifetime (caps total renewal) + a FIFO wait-queue at the owner.** Priority/aging deferred.
- **Lease fencing (zombie / partition)** — a reaped-then-reissued slot could be double-used by a still-running prior holder. **M6: a monotonic fencing token in the lease; the owner rejects dispatch/release from a stale token.**
- **Clock skew** — cross-machine timestamp math is fragile. **Rule: the owner reaps by its OWN clock; gossip freshness by the owner's monotonic sequence/version, never wall-time.**
- **Lossy-bus idempotency** — dup/dropped messages → double-grant. **M6: a client idempotency key on lease/dispatch; the owner dedups.**
- **Orphaned work on the lessor** — a dead lessee leaves the launched app running. **M6: reuse the M4 `terminateGroup`/pgid reaper on lease reap.**
- **Multi-asset deadlock (gang)** — a formula needing N assets can partial-acquire and deadlock. **Moot for this burn** (host is local; only the follower is leased) — **gang scheduling deferred** to when multiple roles are remote/contended.
- **Arbitrary-command RCE** — raw command dispatch is RCE-as-a-service. LAN-trust + token holds it now; the **domain contract bounds "use"** (a constrained execution, not raw shell); real sandboxing/authz = deferred `Trust`.

## Non-goals / deferred (explicit)

- Dynamic discovery (`zero_conf_grid_assets`); the MQTT bus (HTTP first); auth/authz (`Trust` impls).
- Co-ownership/pooling, P2P-bridging topologies (Decision 5).
- Continuous lease migration (Decision 6 depth #3).
- The agent-to-agent BLE burn (Decision 9).
- The point-to-point spike is **not** merged as "federation" — it is input.

## Coexistence / safety (carried forward)

The codec boundary, **gc-coexistence** (single-writer-per-bead; never reconcile/mutate beads gc owns), the **chokepoint-only** writer, and **A37** (write only your own store) all hold. A remote lease must **never** write another station's store except through the agreed federation protocol — the bus carries coordination, not cross-store writes.

## Still open (to close in the build-order or a follow-up)

- **Resource-asset schema** — the concrete value-type(s) for a leasable asset + how a station declares them (scratch Q3).
- **HITL formalization** — generalize the shipped gate into a typed human-asset lease now, or later (scratch Q4). D2 names `human` as a family; the *formalization* is deferred.

## Build target (the build-order, after ratification)

Pins the remaining mechanical items: presence/heartbeat + reaping specifics; the bus wire + endpoint handoff; the **lessor-as-domain-artifact packaging** (the compute domain — not the engine — owns the spike's command/result payload types); the capability cascade + dart/flutter probes + TTL re-validation; git-over-LAN asset/code sync; the burn formula in `butane_grid_assets`.

The first proof slice (settled scope): the **loopback thin slice** (two `grid` procs on one box: presence → lease → dispatch → result → release) → then **cross-machine to `linux-dashboard.local`**, with **no inference on the lessor** (a generic command). Acceptance: deny-when-no-capacity; TTL reaps an abandoned lease; coexistence-safe. **No code until this ADR is ratified.**
