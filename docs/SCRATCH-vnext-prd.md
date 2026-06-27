# the_grid vNext — SCRATCH PRD

> **Status: SCRATCH / working surface. NOT a decision record.** Nothing here is
> ratified or "decided." This is a shared whiteboard for an in-progress design
> conversation (Nico + Claude), captured so it isn't lost between sessions.
>
> - This is **not** ADR-0000 and **not** an ADR. No item here carries a "Nico's
>   decision" stamp. When a thread firms up, Nico decides, and *then* it graduates
>   to its home doc (mostly **ADR-0008** + a future federation ADR) through the
>   normal gate.
> - "Working lean" = the current direction of the riff, explicitly non-binding.
> - "Open fork" = a real unresolved choice still on the table.
>
> Editable by both of us. Reorder/delete/scribble freely.

---

## 0. The through-line

Surfaced from a long design session + a web-research thread on decentralized
compute/orchestration (Prime Intellect / DiLoCo / TOPLOC, Stanford DeLM, Gas
City's "Wasteland"). The recurring shape across every system in that space:

> **autonomous workers + a shared verified substrate + an admission gate.**

And the invariant that falls out: **decentralizing the conductor always reduces to
designing a substrate that's safe to write to concurrently — the hard part
everywhere is the admission gate, not the orchestrator's intelligence.**

the_grid already has the bones: a reconcile tree whose input is *observed state*
(not in-flight RPCs), a single durable substrate (bd/dolt), and a write chokepoint
(A32) + ownership partition (A37). The vNext work is recognizing those bones are
**scale-free** — effect → capability → substation → station → federation is the same
`build(observed)` turtle at every altitude — and not over-coupling the forward
seams to bd-as-heartbeat.

Trust posture (Nico): **"less blockchain."** Participants are semi-trusted (your
own machines / known orgs), so federation-on-a-versioned-DB with reputation, **not**
DAO/consensus/slashing (too slow/pricey for this). This is exactly the Wasteland's
bet, reconcile-native.

---

## 0.5 Nomenclature — "full power grid" (AUTHORITATIVE; supersedes prior grid/rig terms)

Disruptive rename (Nico). The power-grid metaphor, canonical. **Older sections below
may still read `Grid`/`Rig`; this table is authoritative and gets propagated as forks
are worked.**

| Term | Means | Replaces | Code blast radius (vNext migration, not now) |
|---|---|---|---|
| **`Grid` / "the grid" / `the_grid`** | the **federation** — but **per-station, emergent, NO CENTER** (git-style; **requirement**, §7). Each station holds its own `Grid` object (a local view of discovered peers + their capabilities/capacities + virtual substations); "the Grid" is emergent from overlapping views. A central **"GridHub"** is an optional downstream product (a Grid of virtual stations + its own auth), never core. | (was: the singular system / the root Seed) | new `Grid` object (per-station view); brand keeps `the_grid` |
| **`Station` / "my station"** | the **machine** — one runtime, one reconcile loop, one capacity budget, one conductor. | the per-node **`Grid`** (root Seed) | `grid_engine`: root `Grid`(MultiChildSeed) → `Station` |
| **`Substation` / "the butane substation"** | the **project** — an ownership+capability partition of work. Actuated if local, **virtual** if remote. | **`Rig`** | `RigScope`→`SubstationScope`, `Rig`→`Substation`, `RigConfig`→`SubstationConfig`, `BeadOwnershipPredicate` per-substation |
| **`Asset` / "grid asset" / "assets"** | an **implementation of the (gc) pack protocol** — a mountable bundle shipping formulas + capabilities + services + infra that energizes a substation. the_grid's native analogue to a `.gascity-pack/`. | (new — the deployable unit; the authored Dart package) | `*_rig` → **`*_grid_assets`** (the pack) |

**RESOLVED (Nico): package = asset, named `*_grid_assets`** (the pack pattern). An
asset is a mountable pack shipping **formulas + capabilities + services + infra**.
Named so far:
- **`station_grid_assets`** (replaces `the_rig`) — baseline + dogfood: `SourceControl`
  (git impl) + the default **landing formula** + typical station operations/resources
  that don't belong in the engine. **This is the pack pattern in our system.**
- **`butane_grid_assets`** — the **`Burn` formula**, energized by a butane substation.
- **`zero_conf_grid_assets`** — mountable infra enabling local mDNS federation.
- (`leonard_grid_assets` by the same pattern, TBD.)

A **substation** is the logical project an asset energizes (the partition); the
**asset** is the installable implementation.

**Comms (corrected — not 1:1 with GC mail):** GC's "mail" only *exemplifies* that such
systems carry interprocess comms. the_grid likely needs **two channels**: (1) an
**inter-station bus** (federation: presence, capability+capacity ads, claims,
delegation) and (2) **inter-agent comms** (our own solution; GC mail is the rough
analogue). They may **ride the same protocol/transport** — two logical channels, one
wire.

---

## 1. The consumer authoring model (→ candidate home: ADR-0008)

**Context.** `butane_flutter` is already a gascity rig (committed `.gascity-pack/`).
The vNext successor is a *the_grid-native* consumer package. This is the first real
third-party consumer and it pins the SDK shape.

**Working lean:**
- Public authoring surface = a package consumers list in their pubspec. Name lean:
  **`the_grid`** ("punchier"; `grid` is squatted on pub.dev, `grid_sdk` the
  fallback). `grid_engine` stays the **private** element layer; consumers never
  import its sealed Seeds.
- An **asset is a Dart package** (`*_grid_assets` — the pack pattern), like Flutter:
  codify your grid in Dart when you want dynamic capabilities. Reference assets:
  **`station_grid_assets`** (replaces `the_rig` — `SourceControl`/git + default landing
  formula + typical station ops; baseline + dogfood), **`butane_grid_assets`** (the
  `Burn` formula), **`zero_conf_grid_assets`** (mountable mDNS-federation infra),
  `leonard_grid_assets` (per pattern, TBD).
- **Configurations are value types** (`Substation`/`Formula`/`Order`) — TOML *or* Dart,
  two serializations of one freezed shape.
- **Capabilities are Dart** — implemented against a narrow interface; dynamic
  behavior (a `burn`) is real code.
- **Consumers compose, never subclass** engine Seeds (mirrors how `leonard`
  consumes genesis's surface, never `Branch`). Protects the ADR-0007 §7
  derailment-invariants by construction.

**Open forks:**
- `the_grid` vs `grid_sdk` final name (lean: `the_grid`).
- Does `the_rig` fully replace tgdog's ad-hoc wiring, or wrap it?

---

## 2. EffectContext core ⊥ capability split (→ ADR-0008)

**Context.** P0 `EffectContext` carries land-specific git handles
(`gitOps`/`prOpener`/`baseBranch`) in the core, "because land needs them."

**RESOLVED (superseded by the `Service` abstraction, §3 / §9 meta-pattern):** the engine
carries **no capability collaborators** — and, generalized, **no domain detail at all,
only seams.** Land's git stopped being "a collaborator bolted to the land capability"
and became a **`Service`** (`SourceControl`, git impl) the **default landing formula**
depends on, shipped in `station_grid_assets`. End state: the engine ships **no
capabilities** — even `agent`/`verify`/`land` migrate out of
`grid_engine/lib/src/extension/` into `station_grid_assets`, where `Burn` lives in
`butane_grid_assets`. Core `EffectContext` → {transport, chokepoint, owned substation,
worktree layout}.

**Open fork:** is "worktree layout" itself universal, or does even that belong to a
process-capability base? (Lean: universal enough to stay core for now.)

---

## 3. Formula (declared step-graph) + Capability (leaf) + Service — REENTRANT engine (→ ADR-0008)

**Context.** A `Burn` is not one subprocess: probe selectors → deploy 2 harnesses on
2 machines (SSH/git-push, `ios-deploy`/`devicectl`, tmux) → barrier → drive
`butane_coordinator` over WebSocket/mDNS → report → post back to bd → **guaranteed
teardown on every host, even on failure.** It breaks the P0
one-capId→one-effect→one-process model on every axis.

**DECIDED (Nico): the engine is reentrant/recursive.** A capability is NOT an opaque
self-orchestrating leaf — it **declares a step-graph the engine reconciles**, turtles
all the way down. The author writes composition-of-value-types + opaque Dart leaves,
never a Seed; and gets fan-out / barrier / keyed-reconcile / guaranteed-teardown /
crash-recovery **for free and uniformly**. Fractal: top is
`Station→Substation→WorkList→WorkBead→effect`; a burn is
`Burn→[HarnessA,HarnessB]→Barrier→Coordinator→finally(teardown)` — same machinery,
mounted as a subtree under the same `TreeOwner`/flush. **Commitment:** the
derailment-invariants (ADR-0007 §7) must hold **at depth** — guaranteed because the
author only ever touches the declarative builder + opaque leaves, never raw Seeds.

**The vocabulary this unlocks (proposed read — confirm/correct):**
- **Formula** = a **value-typed declared step-graph** (the reentrant unit the engine
  inflates into a subtree). `Burn`; the default **landing formula**. "Energized" =
  mounted under a substation.
- **Capability** = the **opaque Dart leaf** a formula step invokes (the actual process
  spawn / drive body). Sandboxed to a narrow interface; no `TreeContext`, pipeline, or
  `markNeedsRebuild`.
- **Service** = a **pluggable collaborator interface** a formula/capability depends on.
  `SourceControl` (git is one impl, shipped in `station_grid_assets`) — so the landing
  formula depends on `SourceControl`, not git directly. **This is the A42 "capability
  carries its own collaborators" made concrete:** services ride in the asset, not the
  engine. (Settles the original `EffectContext`-git smell.)
- **Asset** = the `*_grid_assets` pack shipping formulas + capabilities + services +
  infra (§0.5).

**OTP framing that fits:** a formula step is a `gen_server`-ish behavior —
`init`/`handle_*`/`terminate`; `terminate/2` *is* the guaranteed teardown.
Cross-station children are **monitors, not links** (a child crash must not kill the
parent).

**Open forks (consequences of committing reentrant):**
- **Crash recovery for a reentrant subtree** — RESOLVED via **state restoration**
  (§3a, Flutter-modeled): each node is `Restorable`; recovery is a uniform
  `restoreState`; **adopt is the floor** for surviving processes, cold-teardown the
  fallback.
- **Supervision strategy + failure escalation** — RESOLVED (§3b): per-formula strategy
  + backoff; the circuit-breaker is restorable state gating the mount predicate;
  per-(station × work) scope; exhaustion escalates to a human in the owned store.
- **Reentrancy × resource governors (§4)** — a formula subtree's leaves acquire permits;
  nested acquisition must not deadlock (a formula holding a permit while its child waits
  on the same pool).

---

## 3a. State restoration — the crash-recovery model (Flutter-modeled; → genesis once proven)

**DECIDED (Nico): model crash-recovery on Flutter's state-restoration framework.**
the_grid is already half a restoration framework — `build(observed)` rebuilds the tree
from the bd snapshot; restoration adds the missing half (Flutter's
`RestorableProperty`): the minimal per-node durable state you **can't** re-derive.
A40's "session bead carries pgid/token/cursor" was a hand-rolled `RestorationBucket`
for one node; restoration generalizes it into a bucket-tree mirroring the reconcile
tree.

**Home (Nico): the genesis project — but EXTRACT AFTER it's proven here.** It's
domain-free tree machinery (Flutter puts restoration in the framework, not the app),
so it belongs in genesis — **possibly `genesis_tree` itself, possibly a sibling genesis
package (TBD).** Path: **prototype the_grid-local against the `Burn`** (the hardest case
— days-long, multi-host, adopt), prove the primitive's shape, *then* upstream the
domain-free part to genesis. Spike before doctrine; keep genesis clean until the shape
is known.

| Flutter | the_grid |
|---|---|
| `RestorationMixin` on a `State` | a Formula/Capability `State` owning durable runtime facts |
| `restorationId` | the node's **key** (`ValueKey('<beadId>.<capId>')`) — already restart-stable |
| `RestorableProperty<T>` | `RestorableProcess` (pgid+token), `RestorableCursor` (phase), `RestorableInt` (log offset) |
| `RestorationBucket` tree → `Map` | a bucket-tree serialized to the **dolt state store** (tgdog, A37) |
| `restoreState(oldBucket, initialRestore)` | rehydrate handles → adopt / respawn / teardown |
| platform persists the bucket | dolt persists it |

**Adopt is the floor, not the reach.** the_grid spawns **detached** processes that
*survive* the controller (unlike Flutter, where the app died) — so on restart you
restore the handle, check liveness, and **re-attach**. Uniform per node:
`{pgid, token, worktree, logOffset, cursor}` → `kill -0` + token match → **adopt**
(re-open log at offset, keep observing); dead + done-marker → finished; dead + no
marker → respawn-or-skip (supervision strategy); ambiguous → freshness barrier + token.

**Two requirements restoration imposes (divergences from Flutter):**
1. **Detached processes write output to a worktree log FILE, not just a pipe.** The
   pipe dies with the controller; the file + a restored byte-offset (`RestorableInt`)
   is how you re-attach to a survivor's output.
2. **Identity/liveness guard (Flutter doesn't need it).** A restored pgid could be a
   recycled pid / prior-incarnation orphan, so restoration = Flutter's + the token +
   freshness barrier (already built). The one thing layered on top.

**Discipline:** restore ONLY the non-derivable external handles (the bridge between the
tree and the live processes it spawned); everything derivable from the bd snapshot
**re-observes**. Small surface → no "stale restored state fights fresh observed state"
bugs. Corollary of the session's through-line: **the_grid holds no important state in
memory — it's all re-observed (bd) or restored (bucket).**

**Open:** the exact genesis home (`genesis_tree` vs a sibling) — deferred until the
the_grid-local prototype proves the shape.

---

## 3b. Supervision strategy + failure escalation (the circuit-breaker)

**Supervision strategy (per-formula, author-declared):** `one_for_one` default; `Burn`
wants `rest_for_one` (central dies → restart it + the coordinator, not the peripheral);
`one_for_all` rare. **Backoff** mandatory — spawns cost minutes + tokens (OTP's
cheap-process economics inverted).

**The circuit-breaker problem (created by reentrant + restoration):** a permanently-
failing formula re-mounts forever — ready+owned → mount → crash → respawn → exhaust →
session terminal, BUT the work bead is foreign/read-only (A37) so it stays *ready* →
next reconcile re-mounts → infinite loop across reconciles. "Give up" must **gate the
mount predicate**, not just terminate the session.

**DECIDED (Nico):**
- The **restart count / cooldown is RESTORABLE state** (`RestorableInt restartCount`,
  `cooldownUntil`) in the bead's bucket (§3a) — so the breaker **survives controller
  restarts** (else every station restart resets it and it never trips).
- The **mount predicate reads it:** `ready ∧ owned ∧ ¬circuit-broken → mount`. A
  tripped breaker keeps the bead unmounted **on this station**.
- **Breaker scope = per-(station × work)** *(Nico)*. My breaker trips *my* attempts; a
  peer with different capacity/env can still claim it (crashes are often
  env/capacity-specific — "decline, don't poison"). A genuinely-broken bead is
  re-attempted once per station before the federation collectively gives up.
- **Exhaustion escalates to a human/operator** *(Nico)* — a signal/bead written to
  the_grid's **own** store ("work X exhausted retries on station Y"). The real terminal:
  in a foreign-work-source world the_grid **cannot** mark the work dead, and
  silent-stop-trying is the worst failure mode (looks like nothing's wrong). OTP
  "escalate to the parent," where the parent is the operator.

**Consequence for federation (§6/§7):** the per-station breaker is *why* decline +
re-routing is safe — a crash here isn't a verdict on the work, just on this station's
fit. **Open:** collective give-up = every capable station's breaker tripped → N
operator escalations for the same work → **dedup at the operator / `Grid` level** (§7).

---

## 4. Resource governance (→ ADR-0008, or its own doc)

**Context.** A laptop supports ~10 `dart analyze` instances; two aggressive agents
can kill the machine. The owner must be able to configure their system's limits.

**Working lean:**
- `DartEnvironment extends InheritedSeed` = **ambient config**, not the actuator
  ("extension" wrongly smuggled the runner in). It carries `DartEnvironmentConfig`
  (SDK path, pub cache, **and analyzer capacity**) and provides the live **governor**
  (a semaphore) derived from that capacity. The **actuator** is a separate
  `DartProcess` effect that resolves the environment, **acquires a permit**, reads
  config, then spawns. Theme/MediaQuery (ambient) vs a widget that does work.
- **The value is a governor, not a number.** A freed permit is an *event* the blocked
  effects observe (observational isolation; never `root.markNeedsRebuild`) → it's an
  observable source (§8).
- **state vs reason** (don't overload): closed **state** = position in the system
  (exhaustively switchable, drives control flow); open **reason/condition** = why
  (observability payload). `awaiting-capacity` is `state:<not-started>` +
  `reason: blocked-on-capacity(analyzer)` — *not* a new state. This is k8s
  phase-vs-conditions. Feeds OTel directly (reason → span attributes).
- **Two admission gates, clean symmetry:** capacity gates what you **start**
  (intake); verification gates what you **publish** (output, the DeLM/TOPLOC gate).
- **Declaration (asset) vs capacity (station):** a formula/capability *declares*
  requirements ("verify acquires 1×analyzer + 1×test"); the **station owner configures
  capacities** for the machine ("analyzer=10" here, "=40" on the Mac Studio). Portable
  requirement (value type) matched to machine-local capacity (value type) → governor.
- **Crash-safe:** permits are in-memory; on restart the reconciler re-acquires for
  processes re-derived from `listBeadWorktrees`. The counter is *derived from observed
  running state*, never persisted → a leaked permit can't outlive a restart.

**DECIDED (Nico): capacity gates at two boundaries + declare-and-check (bounded now,
dynamic planning later).**
- **Claim boundary (cross-station, §6):** capacity gates the *claim* — saturated →
  **decline**, leave it on the board. Never over-claim.
- **Leaf boundary (within a claimed formula):** leaves acquire permits as they mount; a
  transient shortage → the leaf **blocks** (`awaiting-capacity`), never un-claims.
  Decline *outside*, mount-then-block *inside*.
- **Only leaf process-effects acquire permits** — formula/barrier/coordinator nodes are
  orchestration, hold nothing → kills the parent-holds-while-child-waits deadlock.
- **A formula declares its peak aggregate requirement, checked at claim time** — "this
  `Burn` peaks at 2 concurrent `ble-radio` + 2 `dart`." The claim predicate checks
  **peak vs station capacity**, so you never claim a formula the station can't fully
  satisfy → barrier-starvation (A waits on a capacity-1 pool B already holds, barrier
  never completes) is **impossible by construction**: don't start what you can't finish.
  Requires the formula's resource shape to be **statically inspectable from the
  declaration** (fine for the declarative step-graph; forbids unbounded dynamic fan-out
  of permit-holders without a declared bound).
- **FUTURE — dynamic planning** *(Nico wants this later)*: a formula plans its
  requirement at runtime (e.g. one harness per *discovered* device) via a
  **plan → reserve → execute** phase — atomically reserve the planned aggregate (the
  *reservation*, not static declaration, becomes the deadlock guard; degrade/re-plan if
  unreservable). Rhymes with DeLM's runtime `GENERATESUBTASKS` / dependency-aware queue
  refill: the reentrant formula gains a planning step that expands the step-graph from
  observed state, gated by reservation. **Start static; grow to planned.**

---

## 5. Station vs substation + virtual substations (→ future federation ADR)

**Context.** The burn spans machines; multiple agents fighting over one BLE radio
won't work. Nico's instinct: a **station per machine**, each configured with its
**substation(s)**, advertising/claiming by capability **and** capacity.

**Working lean — draw the line as *where* vs *what* (terms per §0.5):**

| | **Station** | **Substation** |
|---|---|---|
| is a | node / runtime / **conductor** | ownership + **capability** partition of work |
| boundary | a machine (one reconcile loop, one capacity budget) | a project / work-domain |
| relationship | **hosts** substations (actuates), **observes** virtual substations (remote) | actuated if local; **virtual** if another station owns it |
| cardinality | one per machine | many per station |

- A **virtual substation is how a station sees another station's project** — a proxy
  that observes the remote's published state, **observe-only, never actuates**.
  Recursion (turtles) *without* nested reconcile loops.
- Actuate-vs-observe is **per-resource**, not per-substation. `gas_city` is the proof:
  the_grid **actuates gc's lifecycle** (when it runs) but **observes gc's work beads**
  (gc owns those; opaque Go internals). Per-resource ownership handles the hybrid.
- This is the Wasteland's **"federated across towns, centralized within a town"**:
  town = **station** (one conductor/Mayor), substation = the work partition. The
  **`Grid`** (the new federation object, §0.5) is the interconnection of stations.

---

## 6. The pull predicate (→ federation ADR)

**Working lean.** A station claims work iff **capability** (I host a substation that
handles it) ∧ **ownership** (in my partition / I'm eligible) ∧ **capacity** (peak
requirement fits free permits, §4) → **claim** → **actuate**.

- **Saturated-but-capable → decline** (Nico's reactive preference). Elegant
  consequence: **the substrate is the queue.** Declining = leave it on the board;
  dolt holds the backlog; no station-local queue, no hoarding.
- Self-balancing with **zero consensus** — capacity is local, instant, objective,
  un-Sybil-able (physics, not reputation).
- **Scarcity-aware (RESOLVED via the `Grid` view, §7):** the station's local `Grid`
  view tells it whether *another* capable peer exists. **Sole-capable → claim-and-hold**
  (you're the only box with the radio / signing cert — holding beats starving);
  **a capable peer exists → decline** when saturated (let it route there). Both decisions
  are local reads of the (eventually-consistent) `Grid` view; a wrong guess is just a
  claim race (§7), resolved deterministically.

---

## 7. Federation substrate — dolt + an inter-station bus (→ federation ADR)

**Context (Nico's reframe — corrects earlier over-engineering).** Don't be religious
about exact global state. Dolt is a *versioned* DB with git semantics — built to
absorb divergence and reconcile by merge.

**Working lean:**
- **Dolt = the chaos-handling durable substrate** (system of record). A37 partition
  means stations mostly write their *own* beads, so real conflicts are rare; the
  occasional overlap is a **merge** (deterministic rule), not a consensus problem.
  (Kills the earlier "atomic-claim race" worry — dolt's versioning *is* the
  resolution.)
- **Inter-station bus = federation liveness**, and it can be **lossy/best-effort**
  because dolt is the source of truth. It's the *fast push signal* so you don't poll
  dolt — i.e. the **federation-scale analogue of the local dirty-signal pair**
  (working-set probe = durable detection; last-touched watch = fast push). One level
  up: dolt remotes (durable) + the bus (fast push). Same fractal, and a dirty signal
  only needs to be *sufficient* (the diff is truth), so the bus gets to be simple.
- **Capability = durable, capacity = ephemeral** *(Nico)*. Opposite lifetimes:
  capability ("I host `butane_grid_assets`, I have a radio") is near-static → published
  to the station's **own dolt store**, read by peers via dolt remotes. Capacity ("3/10
  permits free now") changes on every acquire/release → **ephemeral** bus announce /
  on-demand query, **never persisted** (staleness fine; a stale "free" is just a claim
  race, resolved by the claim mechanics below).
- **`Grid` = a per-station emergent view — NO CENTER (REQUIREMENT, Nico).**
  Decentralized by default, **git-style**. Each station maintains its own `Grid` object:
  a local model of the discovered federation (peer stations + their durable capabilities
  + ephemeral capacities + observed virtual substations), itself an **observable source**
  built from dolt-remotes + bus. No node holds the global view; "the Grid" is *emergent*
  from overlapping local views; §6 routing reads the *local* view. A **"GridHub"** (a
  centralized hub — a well-known Grid of virtual stations with its own auth model on top)
  is a legitimate *downstream product*, like GitHub on git — **never in the core, never
  required.**
- **Two comms channels (NOT 1:1 with GC mail — §0.5).** (1) **inter-station bus**:
  presence/announce, capability+capacity advertisement, "claiming B," delegation
  (burn central→peripheral). (2) **inter-agent comms**: our own solution (GC mail is
  the rough analogue). Both best-effort; dolt backstops the durable truth. They may
  share one transport, two logical channels.
- **Three ways a station observes a peer, layered:** dolt remote (durable state) +
  inter-station bus (live coordination) for routine federation; **perception**
  (§8) reserved for AI-driven debugging.
- **Zero-conf + concrete transport ship as a SEPARATE asset** (`zero_conf_grid_assets`)
  — core stays transport-agnostic (the message *protocol* is an interface). "Same
  protocol, different virtualizations." Home setup: machines together, a station each,
  they zeroconf and get to work — an opt-in asset, not a core dep.

**Event flow (Nico's sequence diagram — `IMG_1090`):** the bus is a **pub/sub** spine;
**all stations are symmetric `Sink + Sub` primitives** (no fixed roles — the Wasteland's
"any station posts/claims/validates"); **the bus access impl is NOT prescribed** (transport-
agnostic; `zero_conf_grid_assets` is one impl).
- A **New Work Event** is published → **each subscriber station recalculates** (`Repeat
  on each subscriber`) — i.e. a federation event is a **dirty signal**, and "recalculate"
  is `build(observed)` one tier up. **The federation is reactive the same way a station
  is** — no special federation scheduler; the bus is just another observable source (§8).
- Per station: **Capacity? → Yes:** publish a **Claim Event**; **No:** don't claim (work
  stays available to other subscribers). The reconcile *output* is claim-or-decline.
- **Capacity republished on change only** ("Station republishes if capacity [changed]; not
  if it did not change") — the ephemeral-capacity announce is itself dirty-signal-on-change.

**DECIDED (Nico):**
- **Claim** lives in the claiming station's **own store** (A37 — can't write the foreign
  work bead); peers observe via dolt remotes + bus; **deterministic resolution** =
  earliest claim-commit, **station-id tiebreak**. Worst case is **wasted work, never
  corruption** (read-only source + per-worktree isolation + the restoration token §3a).
- **Presence events = online + heartbeat (+ absence).** For **n-to-n**, a station also
  **broadcasts peer (virtual-station) disconnections** it observes (gossip), since not
  every station directly heartbeats every other; **peers do what they want with it**
  (advisory, not authoritative — centerless, no canonical reaper).
- **Dead-station reaping** = heartbeat-timeout → **any capable peer may re-claim**;
  partition false-positives are wasted-work (token disambiguates results §3a).

**Still open:**
- The exact wire **envelope** for each event (NewWork / Claim / Presence / Disconnect).
- Dedup of **N operator escalations** for the same work when every capable station's
  breaker trips (§3b) — at the per-station `Grid` view, or a convention.

---

## 8. Observability — observable-source first-class; OTel ⊥ perception (→ likely its own ADR)

**Decided-in-principle (Nico): "observable source" is a first-class concept in the
engine.** It's the unifying primitive — bd, runtime lifecycle, timers, resource
governors (§4), and virtual-substation/peer state (§5/§7) are *all* the same shape: a source
that projects into observed state a Seed reconciles against. bd stops being the
heartbeat (it's the **system of record**, privileged only for write-discipline); the
reconcile loop is the heartbeat.

**Working lean on OTel vs perception (corrects an earlier overreach — lenny is NOT
load-bearing for prod health):**
- the_grid wants **AOT** compilation. VM-service perception (`ext.exploration.*`) is
  JIT-only → **cannot** be the production system-wide view.
- **OTel = production system-wide observability.** AOT-native (libs + OTLP exporter,
  no VM service), standard, durable, aggregatable across grids. *This* is the
  cross-federation health view.
- **Perception = machine-to-AI** (agent-output observability, AI driving/inspecting a
  live system) — a great prod use, but for AOT it needs the exploration **contract
  bound to a non-VM-service transport** (a hosted endpoint the AOT binary serves).
  Contract stable; rebind transport.
- **Not fighting — both are *sinks* on the same reconcile-event stream.** A WorkBead
  mount→unmount *is* a span *and* a perception-tree delta; co-emit. The only way they
  fight is if you make one the *source* for the other (perception's live `observe()`
  is not a metrics pipeline; OTel is not interactive).

**DECIDED (Nico):**
- **Perception ≠ the bus — distinct channels.** Exploration is **point-to-point** (a
  debugger ↔ one station, RPC + server-push stream); the bus is **pub/sub** (station ↔
  station). Same reconcile-event *source*, separate sinks/channels (they may reuse the
  same transport tech, not the same wire). lenny attaches **per-station**;
  cross-federation perception (follow virtual-substation edges) is a debugging nicety,
  **not infra** — OTel is the cross-federation view.
- **Start with HTTP/WS** (RPC over HTTP, event-stream over WS; AOT-trivial,
  language-agnostic, same tech the burn coordinator speaks).
- **Transport is a swappable binding** because **`perception`** (the abstract
  observe/invoke/`tools` contract) + **`consent`** (the permission/authorization layer)
  sit **above** it — both genesis layers. So adding/switching to **gRPC or MCP** later is
  trivial: a new binding under the same perception+consent contract. (Surfacing
  perception's tools as **MCP** would let any MCP client drive a station; `consent` gates
  what's exposed/allowed.) This is where the_grid finally consumes genesis at the surface
  (the deferred perception rebuild).

**Note — `consent` is a new thread.** The genesis authorization layer; gates what an
attached AI may observe/invoke — and likely **generalizes** beyond exploration (what a
*peer station* may claim/delegate; the auth model a **"GridHub"** layers on, §7). Flag,
don't over-scope yet.

---

## 9. Trust — a pluggable abstract domain (→ federation ADR)

**DECIDED (Nico): trust is an abstract domain the engine knows in *concept*, not
*detail*.** Same move as `SourceControl` (§3, git vs jj) and the transport binding (§8,
HTTP/WS vs MCP): the engine has the **seam** (an admission decision happens here) and
defers the **how** to a pluggable impl. This keeps **the distributed-ledger option open**
(for those who need auditing / formal verifiability) *and* **"local trust"** (for
hackers/tinkerers/prototypers) — without the engine ever committing to either. Resolves
"less blockchain" as **less-blockchain-by-default, ledger-available-as-a-plugin** (the
git/GridHub move again: cheap core, heavyweight option layered on).

**The seam.** Trust = the **admission-gate** decision the web chat kept circling
("autonomous workers + shared verified substrate + **admission gate**; the hard part is
pooling trust"). The engine invokes a `Trust` decision at the admission seams —
**admit a peer's result** into my state, **trust a contribution** to the shared
substrate (DeLM verified-before-admission), **believe a re-claim** (§7). It knows
*that* a decision is needed, never *how* it's made.

**Trust ≠ consent (distinct, composable):**
- **`consent` (`genesis_consent`, a genesis layer)** = **authorization** — "*may* this
  actor perform this action?" Gates *actions* (what lenny may observe/invoke; what a peer
  may claim/delegate; §8). General; genesis-homed.
- **`trust` (a the_grid abstract domain)** = **credence/admission** — "do I *believe*
  this result/peer enough to admit it?" Gates *contributions/beliefs*. Orchestration-
  domain; pluggable impls.
  At the federation boundary they compose: consent says "you're *allowed* to claim X";
  trust says "I *believe* your result for X is good enough to admit."

**The impls (a spectrum, plugged in — not baked into the engine):**
- **LocalTrust (default — tinkerers):** trust by possession (ocap, `GRID_INSTANCE_TOKEN`)
  / by being on my LAN. Zero ceremony.
- **ReputationTrust:** local reputation scalar per peer + **optimistic-verify** (keep the
  verify phase; accept optimistically, re-check, a verify failure *is* the fault — a rep
  ding + wasted work, no bond). Capacity-routing (§6) is the un-gameable cousin.
- **LedgerTrust (auditing / adversarial):** distributed ledger — provenance/attestation
  chains (SLSA/in-toto/sigstore; "who built which bead" is valuable for "the grid builds
  everything"), optional staking/slashing. The heavyweight end, for those who need it.

**Open:** home of the `Trust` *interface* — the_grid (orchestration-domain) vs a
genesis-shared abstraction like `consent` (TBD; lean the_grid for now). Where impls ship
(an asset, e.g. `ledger_grid_assets`, same pattern as `SourceControl` in
`station_grid_assets`).

---

## 10. Graduation status

- **✅ GRADUATED + RATIFIED → `docs/adr/ADR-0008-authoring-sdk-and-reentrant-engine.md`
  (Accepted, Nico 2026-06-27).** The single-station / authoring cluster: §0.5
  nomenclature, §1 SDK boundary, §2 (resolved → `Service`), §3 reentrant +
  Formula/Capability/Service, §3a restoration, §3b supervision, §4 resources,
  §5-meta-pattern. Forward-pointer stamps applied to ADR-0007 D1 + ADR-0002 D1 +
  `the_grid/CLAUDE.md`. (Fulfils ADR-0007 §5's reserved P1 "gc-TOML import" —
  generalised to the asset model.) **✅ D1 rename APPLIED in code 2026-06-27** —
  whole-repo (types + `Station*` machinery + the_grid lowercase vocab → `substation`
  + CLI flags `--substation`/`--state-substation`); `melos analyze` + offline suite
  green; **codec boundary held** (persisted gc `metadata.rig` key + convergence
  byte-port schema + `kGridNamespace='grid'` preserved); package-name renames
  (`the_grid`/private `grid_engine`/`*_grid_assets`) deferred to a later task.
- **🔢 ADR NUMBERS ASSIGNED (Nico, 2026-06-27): append.** Federation = **ADR-0011**,
  Observability = **ADR-0012**. ADR-0007 §5's reserved P2/ADR-0009 "unified topology tree"
  + P3/ADR-0010 "convergence-as-subtree" **stay reserved as-is** (not reclaimed) — these two
  new ADRs append after them. (Both still UNWRITTEN — parked until Nico wants them drafted.)
  - **Federation ADR (0011)** — §5 (station/substation/virtual), §6 (pull predicate), §7 (dolt
    + inter-station bus + zero-conf asset), §9 (`Trust` *impls*).
  - **Observability ADR (0012)** — §8 (observable-source first-class, OTel ⊥ perception, AOT
    transport).
- **⏳ genesis-side extraction** — §3a restoration: prove the_grid-local against the
  `Burn`, then upstream via genesis's own ADR-0000 gate (genesis decision, post-prototype).
- **ADR-0007** stays the engine's spine; nothing here reopens it — these sit *above* the
  reconcile core or *beside* it (transport/observation/authoring).

When the deferred threads are ready: Nico assigns numbers + decides → home ADR (his
call) or ADR-0000 amendment (AI-made detail) → through the gate. Not before.
