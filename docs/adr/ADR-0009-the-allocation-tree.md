# ADR-0009 — The Allocation Tree (the_grid's third tree on `genesis_tree`)

**Status:** **Accepted 2026-07-01** (ratified by Nico; drafted by AI from the live design
session per the ADR-0000 register rule). **Takes the reserved 0009 slot** — ADR-0007 §5 reserved
0009 as "the unified topology tree"; the Allocation Tree **is** that tree (Allocations are the
addressable topology nodes), generalized as the_grid's *third tree* on `genesis_tree`.
**Additive** — it **extends ADR-0007** (the running grid *is* a `genesis_tree`) and **ADR-0008**
(the restoration floor D6 / resource governance); it **supersedes nothing.** Forward-pointer
stamps **applied on ratification (2026-07-01)** to ADR-0007 §5 (the reserved-0009 entry) and
ADR-0008 (out-of-scope §) — never silent. Design surface: `docs/SCRATCH-allocation-tree.md`.

---

## Context

ADR-0007/0008 made the running grid a `genesis_tree`: `Seed` (config) → `Branch` (element /
lifecycle / reconcile), with capabilities as pure leaves. But the *live effects* — a spawned
`claude`, a held federation lease, a tmux session, a running app — had nowhere of their own to
live, so they got **smeared into the `Branch` layer**: `initState → unawaited(_run())`, an
`Expando` keyed by the `CapabilityContext`, `_capCtx ??= _buildCapCtx()`, hand-managed
`CancelToken` identity. Every one of those is a symptom of the same missing thing.

**The realization:** `genesis_tree` stops at `Seed`/`Branch` **on purpose.** Its job is to be
the reconcile substrate that *enables* a "third tree" (the RenderObject-analogue), not to ship
one. Flutter **bundles** its third tree — `RenderObject` (nodes) + `PipelineOwner` (owner) +
layout/paint/hit-test (protocol) + `Theme`/`MediaQuery` (affordance-scopes) — into fixed
framework. `genesis_tree` **unbundles** it: the nodes, owner, protocol, and affordance-scopes
are each the consumer's to define. `genesis_typesetting` (typeset boxes + a layout pass) and
lenny's perception (nodes + an observation pass) are the worked examples.

So **the_grid's third tree is the Allocation Tree**, and the smells above are simply that tree
jammed into the second one. This ADR names it and builds it **in the_grid** — genesis stays the
clean substrate.

## Decision 1 — the_grid's third tree is the **Allocation Tree**; a node is an **Allocation**

An **`Allocation`** is a persistent, stateful, **addressable** managed object holding a *live
effect* (agent process / federation lease / tmux session / running app) — the RenderObject
analogue (informal gloss: the "heavy" objects, vs the light config `Seed`s). Allocations are
created by **leaves AND by scopes / container branches** (`SessionScope` → the session,
`SubstationScope` → the source-control handle, a future `BudgetScope` → a meter, a leaf → its
process/lease), not leaves-only.

**Thesis:** Flutter reconciles pixels; **the_grid reconciles committed resource** — desired
state = reconciled Allocations. The layer lives **in the_grid**, on `State`'s existing
`initState` / `didUpdateWidget` / `dispose` lifecycle; `genesis_tree` is unchanged.

## Decision 2 — Relationships are **LIGHT**, plus **addressable, re-adoptable identity**

Intra-station Allocation relationships ride the **two trees we already have**: ancestor↔
descendant follow the `Branch` tree; a scope provides its Allocation handle **down** via
`InheritedSeed` (the affordance) and a leaf reads it + registers/reports **up** through it;
lateral (host↔follower) rides `SiblingView`; teardown rides the `Branch` unmount-cascade.
**the_grid needs no separate linked structure** — these carry every intra-station relationship
we have today. A Heavy/linked structure (a parent that enumerates/controls its children) is a
**legitimate third-tree shape `genesis_tree` enables** — a domain *should* build it when its
relationships genuinely require it (Decision 7 gives the test). Light is **the choice we didn't
need to exceed, not a prohibition.**

**Plus** each Allocation has **stable, addressable identity independent of its `Branch`
lifecycle** — so a *surviving effect* is **re-adopted** into a freshly-built tree (Decision 4).

## Decision 3 — The "sandbox" **dissolves**; invariants hold by *layering + a single write-locus*, not a wall

The capability "sandbox" was an artifact of the two-tree world — a lonely, stateless
`Capability` leaf, walled off from context and handed a frozen snapshot because it had nowhere
to live. The third tree removes the need for the wall:

- the **Host** (`Branch`/Element) is the tree-facing layer; reading inherited context and
  configuring its Allocation is its **normal Element job**;
- the **Allocation** is a full node — it may **depend on** the tree (read), directly, to draw on
  ancestor affordances;
- the **Capability** stays pure config.

So there is **no special sandbox**. The invariants are preserved by *where things live*:

- **invariant 2** (only the chokepoint writes) holds because **the writer lives only in the
  Host**, which persists **off-build**; the effect layer (Allocation/Capability) is **never
  handed a writer/notifier** — a structural fact enforced by a test, *not* a sandbox;
- **invariant 1** (no *pipeline* subscription) forbids subscribing to the bd mutation stream /
  re-query (the lone `StationJoinBridge`), **not** depending on the tree.

**Depending on context (`dependOnInheritedSeedOfExactType`) is the norm** — a keyed/addressable
node whose context changes *should* rebuild, and the rebuild resolves coherently via
**update-or-replace** (D4/D5): `update()` in place if the type supports it, else re-key →
replace (exactly Flutter's `dependOn` → `updateRenderObject`). The old frozen-`_capCtx` /
staleness / "config built 100×" worries were symptoms of a leaf that *couldn't* react; the
Allocation *can*, so a context-change rebuild is useful, not churn.

Read primitives: **`dependOnInheritedSeedOfExactType`** (registering) is the **primary**;
**`StableInheritedSeed`** for genuinely constant config (never notifies); a **non-registering
lookup** (genesis FR, optional) is only for read-once-and-ignore. This **retires** any
`ResourceBag` / parallel engine container — *the tree is the bag.*

**Amended 2026-07-02 (ratified Nico; ADR-0008 Decisions 3/4 amendments + `docs/SCRATCH-agent-scope.md`
D-F/D-G):** the FR **landed** — genesis_tree 0.1.4 ships `getInheritedSeedOfExactType` (non-binding,
callable outside build, `StateError` on an unmounted branch) — and is **upgraded from optional
optimization to the EFFECT verb**: `dependOn*` = the tree/build verb (branches always watch), `get*`
= the effect verb (+ `initState` initial reads, teardown). **`StableInheritedSeed` is DELETED** (its
provider-side-hack role is obsolete with the consumer-side read landed; genesis's default identity
check already covers the stable-handle case — ADR-0008 D-6's 2026-07-02 supersession).

## Decision 4 — Lifecycle: **`startOrAdopt` / `update` / `dispose` / `detach`** — all TYPE properties

`Capability.createAllocation(ctx)` mints the Allocation (sync, cheap). The Allocation then owns,
async:

- **`startOrAdopt(ctx)`** — spawn fresh **or** prove-and-adopt a survivor at the **address**
  (= the node path `<sessionId>/<nodePath>`, reconstructible because the tree rebuilds
  deterministically from work source + cursor). Reattaches to **any** survivor — a **crash-orphan**
  *or* a **detached** effect. The engine owns **only** the stable address + **no-adopt-on-faith**
  (the type must *return proof* of freshness; can't prove → create/respawn).
- **`canUpdate(old,next)` + `update(ctx)`** — in-place mutate, or decline → the Host replaces.
  Update-vs-replace is a **domain choice** (à la RenderObject `canUpdate`/key): `claude -p` →
  *replace*; a tmux session → *update in place*.
- **`dispose()` = KILL** — the effect is done/invalidated; kill/release. **The default / floor.**
- **`detach()` = LEAVE RUNNING + persist the handle** — a *distinct verb*, **not** an overloaded
  `dispose`. A **per-type opt-in** for a *safe-to-leave-running ∧ re-adoptable* effect, so a later
  `startOrAdopt` reattaches it. Clearest wins: **graceful controller restart** (detach-all →
  restart → reattach-all, no downtime) and the *deliberate twin* of crash-orphan recovery; it
  also makes a **replace cheap** where the effect genuinely survives. The **reaper catches a
  detached effect nobody re-adopts** (the orphan sweep).

**Per-family defaults** (adoption is a new per-type branch beside the existing respawn-or-skip):

- **one-shot process ("shot call")** → not adopt, not detach = today's `RestartReconciler`
  **respawn-or-skip** (skip if completed, respawn if incomplete + idempotent);
- **daemon process** → adopt-or-respawn (freshness: pgid alive ∧ token echoed over its endpoint);
  detach-capable (graceful restart);
- **lease** → adopt-or-reacquire (freshness: ask the owner "grant X still valid + mine?");
- **tmux / others** → own re-find + marker.

the_grid ships the **process family (daemon / one-shot) + lease family** first.

## Decision 5 — The Host↔Allocation contract: **thin sync driver / async effect owner**

Three-tree mapping: `Capability` (description) → `CapabilityHost` (`Branch`) → `Allocation`
(instance) = Widget → Element → RenderObject.

- **Host = thin *sync* driver.** Computes the address; on mount **kicks** `startOrAdopt`
  (fire-and-forget, guarded once); on ctx-change *same address ∧ `canUpdate`* → kicks `update`,
  else **replace** (reconcile re-key); on unmount kicks **`dispose` (kill)** *or* **`detach`
  (leave)** per the scenario + type; gives the Allocation a **report sink** + a **cancel token**;
  **persists** reported transitions **off-build, latched, through the one chokepoint**
  (invariant 2); owns the guards (no double-kick, cancel-on-dispose).
- **Allocation = async *effect* owner.** Owns its state machine
  (`starting → live → [ready] → dying → gone`, `adopting`) + the freshness proof; **reports
  (push)** to the sink; **holds NO writer** — it reports, the Host persists (invariant 2 holds at
  this layer by construction, the same layering as the Capability).
- **Interlock:** Host kicks (sync) → Allocation runs (async) → Allocation reports (push, async)
  → Host persists (off-build). **Reconcile never awaits I/O.** (This formalizes today's
  `unawaited(_run())` + `_onEvent → _writeX`, split onto the right objects.)
- **No-adopt-on-faith** is a **contract obligation + a mutation-test** (an adopt path without a
  freshness assertion fails), not an engine mechanism.

## Decision 6 — Graduated conveniences

A one-shot leaf must not pay for the full lifecycle. **`JobAllocation`** = start-runs, no
`update`, no adopt, no detach, **respawn-or-skip** (literally today's behavior). The full
**`Allocation`** = daemon / lease (adopt, update, detach, push-report). Maps onto the current
split: a one-shot `ServiceCapability` → `JobAllocation`; a daemon/lease → full `Allocation`.

## Decision 7 — Scope fence (what this ADR does **not** decide)

- **No Heavy linked tree is *built* here — because the_grid's current relationships don't need
  one** (`Branch` + `InheritedSeed` + `SiblingView` carry them; only restoration needs identity).
  It is **NOT forbidden.** `genesis_tree` enables arbitrary third-tree shapes; **build Heavy the
  moment you can name a relationship the Light mechanisms can't carry** — a parent that must
  enumerate, meter, or re-parent its children directly. Earn it from a concrete domain problem;
  don't contort to avoid it, and don't build it for Flutter-symmetry either.
- **No engine-level protocol** flowing through the tree — governance-as-layout ("capacity down,
  demand up") was **rejected as universal**; leasing may run a capacity pass locally, in its own
  domain, without it being the tree's law.
- **No federation re-modeling** (M6 is parked separately).
- **Observability:** this ADR **provides** the addressable topology (it fills the reserved
  "unified topology tree" slot); the observability *sinks* over it are deferred to **ADR-0012**.

---

## Consequences

- **Dissolves the smells that started this:** the `Expando<_FollowerHold>`, `_capCtx ??=`, and
  hand-managed `CancelToken` become plain **Allocation instance fields**.
- **The restoration floor becomes "one more branch on the reaper"** — `RestartReconciler`
  respawn-or-skip generalizes to respawn-or-**adopt** per type; **`detach` + reattach** adds
  **graceful controller restart** and cheap survivable-replace, over the *same* reattach path.
- **The M6 burn-follower becomes the first full-`Allocation` client** (a daemon: adopt / update /
  detach / dispose). The daemon bug that opened this session — a `daemon` `ServiceCapability`
  reaching `complete` and being reaped before the host drives it — **dissolves** (the follower is
  a daemon Allocation held for its mounted lifetime, not a step written to `complete`).
- **Effects become first-class addressable / inspectable / restorable nodes** → the substrate
  for observability (ADR-0012) + crash-recovery, instead of invisible `Expando` side-channels.

## Alternatives considered (explored and rejected this session)

- **A new `Ready` `StepOutcome`** — overloads step state; the daemon-hold belongs in a
  scope/Allocation, not a fourth terminal state.
- **`ResourceBag` / a generic typed engine registry** — a parallel container *next to* the tree;
  once the sandbox dissolves (D3), the tree *is* the bag.
- **`LeaseScope` + an agreement-gate** as the burn fix — solved a problem this reframing removes.
- **A Heavy linked allocation tree** — *not rejected, just not needed by the_grid's current
  relationships*; a domain builds it when its relationships require parent-enumeration (D7).
- **`StableInheritedSeed` as the permanent read mechanism** — a provider-side hack for a missing
  consumer-side non-registering read → the optional FR below; the *primary* read is the existing
  registering `dependOn`.
- **Overloading `dispose` with a `kill|detach` flag** — rejected; `dispose` (kill) and `detach`
  (leave) are **distinct verbs**, kept unambiguous.

## Follow-ups (genesis — separate repo)

1. **FR (OPTIONAL — not load-bearing): a non-registering inherited lookup** —
   `getInheritedSeedOfExactType` (mirrors Flutter's `getInheritedWidgetOfExactType`), a minor
   read-once-and-ignore optimization. The **primary** read is the existing registering `dependOn`;
   `StableInheritedSeed` covers constant config. Genesis is **not blocked on this**.
   **✅ DONE (Nico, published 2026-07-02 — genesis_tree 0.1.4)** and upgraded to the EFFECT verb
   (see the Decision 3 amendment above); `StableInheritedSeed` deleted with it.
2. **Doc: the third-tree pattern in `genesis_tree`** — the four pieces (nodes / owner / protocol
   / affordance-scopes) + typesetting/perception as worked examples.

## Relationship to other ADRs / numbering

- **Occupies the reserved 0009 slot** — "the unified topology tree" (ADR-0007 §5 P2). The
  Allocation Tree **is** that tree: Allocations are the addressable topology nodes (config scopes
  + effect leaves), inspectable and restorable.
- **Extends ADR-0007** (tree-is-engine) and **ADR-0008** (restoration floor D6; resource
  governance). Additive; no supersession. **Feeds ADR-0012** (observability — the sinks over the
  topology).

## Build path (after ratification)

1. the_grid: `Allocation` + `JobAllocation`; the **process family** (daemon adopt-or-respawn +
   detach / one-shot respawn-or-skip) + the **lease family**.
2. Refactor `CapabilityHost` to the thin-driver contract (D5); delete the `Expando` / `_capCtx
   ??=` / `CancelToken`-juggling; wire adoption + detach into `RestartReconciler` as
   respawn-or-**adopt** + reattach-a-**detached** survivor.
3. `dependOn` reads now; `StableInheritedSeed` for constant config; the non-registering lookup is
   an optional later optimization.
4. **Unpark M6** behind this: the burn-follower as a daemon `Allocation` is the first client.
