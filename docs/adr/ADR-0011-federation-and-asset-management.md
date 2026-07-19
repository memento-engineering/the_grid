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

---

## Proposed amendment (2026-07-19, public-readiness tg-8gv.6) — AWAITING RATIFICATION

**Status of THIS text: Proposed — awaiting Nico's ratification. Nothing above this line changes.**
Provenance is mixed and stated per section: the §A engine contracts were **RULED by Nico
in-session** (2026-07-03; `docs/SCRATCH-grid-alignment.md` §7 rulings log) — those underlying
decisions are human-made and binding *as rulings* — but their promotion into this ADR's durable
record is what this amendment proposes, and that promotion has NOT been ratified. The §B multi-root
design was only ever **PROPOSED** in its SCRATCH (its §6 rulings log reads "awaiting Nico") and is
carried forward as design, never as a ruling. Decision IDs are preserved verbatim from the source
SCRATCHes. Neither SCRATCH is modified or retired by this amendment — their disposition is a
separate pass.

**Sequencing note (for the ratifier).** D-B6/OQ-A4 gated this promotion on the claim flow proving
end-to-end ("spike-before-doctrine": engine contracts graduate into ADR-0011 *once proven*). That
proof has not run. This amendment promotes the **contracts** — already load-bearing in shipped
engine code (§A.4) — while marking the bus **implementation** pending-proof (§A.5). Ratifying it
means accepting that ordering: the contracts get a durable, citable home now; the implementation
stays behind the original gate.

### §A — The office-grid engine contracts (RULED 2026-07-03; promoted from `docs/SCRATCH-grid-alignment.md`)

Source: the 2026-07-03 realignment session ("the office grid" — stations on ~every machine, not
configured identically, credentials station-local: "no credentials leaked, just work assigned"),
which superseded the remote half of `docs/SCRATCH-multi-root-federation.md` and reframed federation
as **assignment-federation, never observation-federation** (D-A2): a remote substation is NEVER a
snapshot member of my station; work reaches it by assignment over the bus. D-A1 (stations host
substations; hosting = store + clone + roots = the right to DRIVE locally, configuration never
travels) and D-A5 (the bus carries coordination; dolt stays truth; git carries the code —
reaffirming Decision 7's two-channel split) are the frame the contracts below sit in.

#### §A.1 — The claim→lease assignment flow (D-A3, D-A4)

- **D-A3 — The claim flow** (the whiteboard, 2026-07-03). A station minting new work tries to
  **claim it first, locally**. Whatever is still unclaimed **at the end of a reconciliation phase
  is broadcast** for pickup by any station that fulfills the requirements. Claims are
  **per-requirement (capability slots), never per-bead** — one bead can fan out (the Burn:
  `Req macOS+BLE` claimed locally, `Req Linux+BLE` broadcast, claimed by `dashboard.local`).
  Requirements are grid-runner configuration, asset-based — exactly `CapabilityFacts` containment
  matching (Decision 6, shipped with `ToolchainProbe`); a public/private key exchange with the
  public key riding the durable bead is an admissible `Trust` variant (Decision 8's seam).
- **D-A4 — Claim → lease is two-phase.** The claim bus does *assignment*; the already-designed
  lease machinery (Decision 7 + the hazards table: owner-authoritative arbitration, monotonic
  fencing token, heartbeat, owner-clock reaping) does *execution*. "Federation + Leasing." This
  *extends* Decisions 5/7 above; it changes neither.

#### §A.2 — The bus shape (D-B1, D-B2, D-B3) + the mesh/GridHub topology rulings

- **D-B1 — Decentralized MQTT as the primitive shape.** Every station **publishes only on its own
  broker** and subscribes to others per topology. The publish-own rule maps claim-in-own-store onto
  the wire: presence = your broker's liveness (+ LWT); advertisement = retained messages on your
  own broker; claims = notifications on your own broker; arbitration = deterministic at the work's
  owner. Federation primitives are PRIMITIVES — **topology is the implementer's choice**, and the
  topology opinion ships in `zero_conf_grid_assets`:
  - **mesh** — everyone subscribes to everyone (O(N²) connections; the office runs this, N=5);
  - **GridHub** — spokes subscribe only to a hub; the hub is *just a station running nothing but
    federation assets*, doling claimable work off its own broker (the ADR-0008 "optional downstream
    product" slot). Same binary, same primitive, topology by configuration.
- **D-B2 — Broker IN-PROCESS, single-writer.** No external daemon. `federated_grid_assets` defines
  its **own abstract broker interface** to shield the dependency: vet the existing pub.dev brokers
  behind the seam first; write a bounded single-writer subset (CONNECT/SUB/PUB, QoS 0–1, retained,
  will, ping) only if they fail. The publish-own rule makes each broker single-writer — a
  retained-topic map + subscriber fan-out + LWT, no fan-in races. Lifecycle unity is correctness:
  your broker IS your presence (station-dark = broker-dark; no zombie retained ads from an
  out-of-process broker outliving its station). MQTT being wire-standard keeps mosquitto as the
  escape hatch behind the same seam.
- **D-B3 — Bus schema: ACP-shaped, MQTT-carried.** ACP = Zed's Agent Client Protocol
  (agentclientprotocol.com), the dialect the harness seam already speaks — NOT IBM's retired ACP;
  MCP is NOT being introduced now (RULED). Borrow the JSON-RPC 2.0 envelope + method namespacing +
  initialize-time capability negotiation; carry it as MQTT messages: broadcast-unclaimed = a
  *notification* on your own broker; claim-resp/confirm = request/response pairs correlated by id
  across two brokers. The concrete method surface (claims + presence + advertisement, versioned)
  extends the protocol contracts, not the engine.
- (**D-B4** — A2A parked until model/agent routing — recorded for completeness; it rules nothing
  in. Its agent-card shape overlaps `Presence`/`CapabilityFacts`; revisit there.)

#### §A.3 — The boundary: NO MQTT IN THE ENGINE, EVER (D-B5)

The engine-level federation surface is **transport-free contracts only**:
1. **the unclaimed-frontier hook** — the engine exposes "the unclaimed requirement set at the end
   of a reconciliation phase" for an asset claim capability to consume (the D-A3 broadcast trigger
   is engine-observable, asset-actioned);
2. **requirement-slot resolution at the `EffectResolver` seam** — a step requirement the local
   station cannot fulfill resolves to an asset-provided claim+lease capability instead of a local
   spawn (local-vs-remote is a resolver decision; the remote impl is the asset's);
3. **the SDK value types + seams** ruled by D-A9 — `Presence`/`CapabilityFacts`, claim/lease
   protocol contracts, the transport-agnostic bus seam;
4. **durable claim recording** rides the existing bd write chokepoint (claim-in-own-store).
ALL bus machinery — the in-process broker + its shielding interface, MQTT bindings, topic layout,
the ACP-shaped wire impl, topology — lives in power_station's `federated_grid_assets`
(+ `zero_conf_grid_assets` for discovery/topology opinions). Nothing else touches the engine.

#### §A.4 — Already load-bearing in shipped code (verified 2026-07-19)

These contracts are not aspirational; the engine already cites the SCRATCH as its authority — the
citation needs a home that is not a SCRATCH:
- `packages/grid_engine/lib/src/sdk/claim.dart` — header: "the honesty-pass D-A3/D-B5,
  `docs/SCRATCH-grid-alignment.md`". `unclaimedSteps` is the pure per-circuit claim predicate over
  the eligible frontier (containment per Decision 6); `UnclaimedStep` is the broadcast unit. Zero
  I/O, engine-observable only — what an asset does with one is its own affair (D-B5 honored).
- `packages/grid_engine/lib/src/bridge/federated_snapshot_source.dart` — header cites the D-A2
  rescope ("a remote substation is never a snapshot member") and the multi-root SCRATCH's
  D-F3/D-Z3/D-Z4 for its per-member freshness vector.
- The SDK directory also carries `capability_facts.dart`, `lease.dart`, `federation_protocol.dart`
  — the D-A9 concepts→SDK dissolution of `grid_federation`, observable on disk.

#### §A.5 — Implementation status: PENDING-PROOF (per the SCRATCH's own gate)

The bus **implementation** — broker vet, the in-process broker, the ACP-shaped wire, topology
opinions, discovery (alignment ladder AL-6/AL-7) — is NOT ratified by this amendment and remains
behind the spike-before-doctrine gate: the claim flow must prove end-to-end before implementation
doctrine is written. **This amendment ratifies contracts, not an implementation.**

### §B — Multi-root design carried forward (D-M1..M7; bead tg-7gm) — design-carried-forward, unbuilt as-designed

From `docs/SCRATCH-multi-root-federation.md` §3, PROPOSED there and never ruled — folded forward so
the unbuilt design has a durable home:
- **D-M1** — root granularity = per-substation (the scope), not per-bead; a bead inherits its root
  from the scope it mounts under. *Amended* by the alignment SCRATCH's §6 discovery (operator-made
  while taking DAG ownership, NOT a Nico ruling): substation↔repo is 1:N for the tg store, so
  per-substation stays the DEFAULT but tg-7gm must also deliver a **per-bead root selector** —
  roots register by name, a bead selects one via its envelope (e.g. `grid.root: power_station`),
  and an unregistered selection is an arming-class LOUD skip, never a gate.
- **D-M2** — symmetric pairing grammar: repeatable `--root <substation>=<path>[@<head>]`; bare
  `--root <path>` as single-substation shorthand; global `--head` refused when >1 root.
- **D-M3** — one scope per substation, `ownedSubstations: {itself}`; overlapping owned-sets refused
  LOUD (the double-mount guard: one bead, one agent). The writer's allow-set stays the union.
- **D-M4** — rooting is a DRIVEN-SET obligation: a live arm refuses at arming when any OWNED work
  substation lacks a registered root; an observed-not-owned member needs no root.
- **D-M5** — `devRoot` (pub-link absolutization) resolves per scope, not as a station-wide
  constructor bake.
- **D-M6** — ONE `RestartReconciler` fanning out over N roots (list+reap per root; one freshness
  barrier; one pass in the pinned start ordering).
- **D-M7** — roots multiply; the state store and lock do not (N work roots, ONE state store, ONE
  session partition, ONE lock).

**Build status (verified 2026-07-19, for the ratifier's calibration).** The v3 SDK rail has since
delivered part of this intent by a different route: `buildStationWork`
(`packages/grid_sdk/lib/src/work/work_assembly.dart`) registers one root per `SubstationWorkSpec`
with fail-closed name/prefix disjointness (the D-M1/D-M3 intent), and the per-substation status
breakdown shipped (`packages/grid_cli/lib/src/station_control.dart`, stamped tg-7gm). D-M2's
`--root` pairing grammar was superseded by the `--substation <name>@<prefix>=<path>` surface.
Explicitly UNBUILT: **D-M6** (the code says so — `RestartReconciler` takes "THE single-root
consumer's root … the FIRST substation's; the D-M6 restart fan-out across N substations stays
deferred", `work_assembly.dart`), the **per-bead root override**, and **D-M5**, whose target
machinery (`devRoot` pub-link absolutization) no longer exists in the current tree — its premise
must be re-checked before any build. Whether the remainder survives as beads is a refinement
decision, not this amendment's.

The **already-promoted D-F/D-Z half** (federated work sources, tg-nsj — `FederatedSnapshotSource`,
the `--workspace` grammar, staleness/removal semantics, the cross-store block guard) lives in
**ADR-0000 A44 (2026-07-03)** — referenced here, not duplicated.

### §C — Where the opinion half lives (D-B6)

Per **D-B6** (RULED 2026-07-03): the bus/asset **opinion** half — which broker, deployment,
topology opinions, MQTT bindings, discovery — belongs to **power_station's own ADR line** (it stops
riding the_grid's, which stays engine-scoped); that document is filed separately in that repo, not
here.
