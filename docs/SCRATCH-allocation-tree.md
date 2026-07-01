# SCRATCH — The Allocation Tree

**Status:** design surface — **GRADUATED to `docs/adr/ADR-0009-the-allocation-tree.md` (Accepted
2026-07-01, ratified Nico).** This is the design history that fed ADR-0009; **the ADR is
canonical.** Design-before-code: no code until per the ADR's build path. **M6 (federation/burn)
is PARKED behind this.**

---

## The realization — `genesis_tree` enables "third trees"; it does not impose one

Flutter **bundles** its third tree into fixed framework: `RenderObject` (nodes) +
`PipelineOwner` (owner/driver) + layout/paint/hit-test (protocol) +
`Theme`/`MediaQuery`/`Directionality` (affordance-scopes).

`genesis_tree` **unbundles** it. `Seed`/`Branch` + keyed reconcile is the shared core; the
third tree's **nodes, its owner, its protocol, and its affordance-scopes are each the
consumer's to define.** Worked examples already in the org:
- **`genesis_typesetting`** — third tree = typeset boxes; protocol = a layout pass.
- **perception (lenny)** — nodes + an observation pass.

**the_grid's third tree = the Allocation Tree.** It's built *on* genesis_tree exactly like
typesetting is — not a change *to* genesis. genesis stays the clean reconcile substrate.

> **genesis follow-up:** genesis_tree should *document* this — the four pieces (nodes / owner
> / protocol / affordance-scopes) + typesetting/perception as examples — so the next consumer
> doesn't spend a session rediscovering it.

---

## The Allocation Tree (the_grid's third tree)

- **Node = `Allocation`** — a persistent, stateful, **addressable** managed object holding a
  *live effect*: a spawned agent process, a held federation lease, a tmux session, a running
  app. The RenderObject-analogue. (Informal gloss: the "heavy" objects, vs the light config
  `Seed`s. Not the type name.)
- Created by **leaves AND scopes/container branches** — `SessionScope` → the session;
  `SubstationScope` → the source-control handle; a future `BudgetScope` → a meter; a leaf
  capability → its process/lease. Not leaves-only.
- **Thesis:** Flutter reconciles pixels; **the_grid reconciles committed resource** —
  "desired state = reconciled Allocations." ("Attention" was the wrong noun — agent/transformer
  metaphor. "Allocation" is the mechanism.)

---

## Decisions converged this session

1. **Relationships = LIGHT.** They ride the two trees we already have: the Branch tree
   (ancestor↔descendant), `InheritedSeed` (a scope provides its Allocation handle *down* as an
   affordance; a leaf reads it + registers/reports *up* through it), and `SiblingView`
   (lateral, e.g. host↔follower). Teardown rides the Branch unmount-cascade. **the_grid needs no
   separate linked structure TODAY** — but a Heavy/linked tree (parent enumerates/controls
   children) is a legit third-tree shape `genesis_tree` ENABLES; build it when a domain
   relationship genuinely needs it. **NOT a prohibition** (see guardrails for the test).
2. **PLUS addressable, re-adoptable IDENTITY.** An Allocation has stable identity *independent
   of its Branch lifecycle*, so a **surviving effect (a live process) is re-adopted** into a
   freshly-built Branch tree after a controller crash (the RenderObject-reattach move; the
   ADR-0008 restoration floor). This is the *minimum* of "Heavy" that restoration demands —
   identity + re-adoption, **not** a parent-controls-children linked tree.
3. **Lifecycle = `startOrAdopt` / update / `dispose` (kill) / `detach` (leave)** — distinct verbs (D4/D9). Update-vs-replace is a
   **domain choice** (à la RenderObject `canUpdate`/key): `claude -p` → *replace*; a tmux
   session → *update in place*. "Frozen snapshot, change = remount" is **retracted as a
   universal engine policy** — it's right for claude, wrong to impose on tmux.
4. **Sandbox DISSOLVES — it was a two-tree artifact.** No wall: the Host does tree-facing
   context resolution (its normal Element job); the Allocation is a full node that may **read the
   tree read-only**. Invariants hold by **layering + a single write-locus** — the writer lives
   ONLY in the Host (persists off-build); the effect layer is never handed a writer/notifier
   (enforced by a test), **NOT a sandbox.** **Depending on context (`dependOn`) is fine + the
   norm** (inv 1 = no *pipeline* sub, not no tree-dep): a keyed node reacts to a context change
   via **update-or-replace**. `StableInheritedSeed` for constant config; a non-registering lookup
   (genesis FR) is only an optional read-once optimization.
5. **The sync↔async interlock is an ALLOCATION responsibility.** Reconcile is synchronous and
   *schedules + addresses*; the Allocation owns its own state machine
   (`starting → live → dying → gone`, + `adopting`) and *reports out-of-band*. This is exactly
   what `_capCtx ??=` / `Expando` / the re-entry guards were hand-hacking — done properly it's
   the Allocation's internal concern behind one clean Host contract.
6. **Graduated + conveniences.** A one-shot job (run, exit, done) stays a plain leaf — no
   Allocation machinery. The Allocation layer is for **stateful / long-lived / updatable**
   effects (daemon, lease, tmux, held agent). Sensible conveniences for the common case.
7. **Keying = addressability = routing.** Same address + new params → `update`; new address →
   replace. (The router metaphor `SessionScope` already gestured at.)
8. **Adoption is a TYPE property, via one abstract engine hook.** Address = the **node path**
   (`<sessionId>/<nodePath>`), stable/reconstructible because the tree rebuilds deterministically
   from work source + cursor. The engine offers `createOrAdopt(address)` and owns *only*: the
   stable address + the rule **no adopt-on-faith** — the type must *return proof* of freshness;
   can't prove → create/respawn. Everything else (pgid, endpoint, grant, marker) is the type's.
   Adoption is a **new per-type branch beside the existing respawn-or-skip**, not a global
   mechanism:
   - **one-shot process ("shot call")** → *not* adopt = today's `RestartReconciler`
     **respawn-or-skip** (skip if completed, respawn if incomplete + idempotent).
   - **daemon process** → adopt-or-respawn (freshness: pgid alive ∧ token echoed over its endpoint).
   - **lease** → adopt-or-reacquire (freshness: ask the owner "grant X still valid + mine?").
   - **tmux / others** → own re-find + marker.

   the_grid ships the **process family (daemon / one-shot) + lease family** first.
9. **The Host↔Allocation contract** (three-tree: `Capability` description → `CapabilityHost`
   Branch → `Allocation` instance = Widget → Element → RenderObject).
   - **Host = thin *sync* driver:** compute address; mount → *kick* `startOrAdopt`
     (fire-and-forget, guarded once); ctx-change → *same address ∧ `canUpdate`* → kick `update`,
     else **replace** (reconcile re-key); unmount → kick `dispose`; give the Allocation a
     **report sink** + **cancel token**; **persist** reported transitions **off-build, latched,
     one chokepoint** (inv 2); own the guards (no double-kick, cancel-on-dispose).
   - **Allocation = async *effect* owner:** `Capability.createAllocation(ctx)` (sync mint) →
     `startOrAdopt` / `canUpdate`+`update` / `dispose` (async); owns its state machine
     (`starting → live → [ready] → dying → gone`, `adopting`) + the freshness proof; **reports
     (push)** to the sink; **holds NO writer** — it reports, the Host persists (inv 2 holds at
     this layer by construction, same sandbox as the Capability).
   - **Interlock:** Host kicks (sync) → Allocation runs (async) → Allocation reports (push,
     async) → Host persists (off-build). **Reconcile never awaits I/O.** (Formalizes today's
     `initState → unawaited(_run())` + `_onEvent → _writeX`, split onto the right objects.)
   - **`dispose` (kill) and `detach` (leave running + persist handle) are DISTINCT verbs** —
     `dispose` is not overloaded. `dispose(kill)` is the floor/default; `detach` is a per-type
     opt-in (safe-to-leave ∧ re-adoptable). `startOrAdopt` reattaches a **detached** survivor OR a
     **crash-orphan** (same path). Wins: graceful restart + cheap survivable-replace. The reaper
     catches un-re-adopted detached orphans.
   - **No-adopt-on-faith** = contract obligation + a mutation-test (an adopt path without a
     freshness assertion fails).

---

## What this dissolves (the smells that started it)

- `Expando<_FollowerHold>` (keyed by ctx) → **Allocation instance fields.**
- `_capCtx ??= _buildCapCtx()` → the **Allocation persists**; the Host *updates* it.
- `CancelToken` juggling → an **Allocation field.**
- `ResourceBag` / `ServiceBundle`-anxiety → **dropped.** The tree *is* the bag; read via the
  lookup.
- The `Ready` StepOutcome / `LeaseScope` / agreement-gate detours → **retired** (they were
  solving problems this reframing removes).
- "effect smeared into the Element via `initState → _run()`" → the **Allocation is the
  third-tree node**, not something jammed into the Branch.

---

## Open questions (next design threads)

- ~~The Host↔Allocation contract~~ — **RESOLVED (decision 9):** thin sync Host driver / async
  Allocation owner; push reports, Host persists off-build; `dispose` (kill) + `detach` (leave) as distinct verbs.
- ~~The ADDRESSING scheme~~ — **RESOLVED (decision 8):** address = node path (reconstructible);
  re-find via the type's own handle (process = pgid/token fence in the own-store; lease = grant
  id); adoption is per-type; engine owns address + no-adopt-on-faith.
- ~~Async coordination mechanics~~ — **RESOLVED (decision 9):** Host kicks (sync) → Allocation
  runs + reports (push, async) → Host persists (off-build, latched, one chokepoint).
- **Where the layer LIVES** ← **ACTIVE** — the_grid, on `State`'s existing `initState` /
  `didUpdateWidget` / `dispose` lifecycle, with genesis clean. Lean: **pure the_grid**; genesis
  stays the substrate; the genesis FR (non-registering lookup) is an independent nicety.
- **Graduated conveniences** — a one-shot leaf shouldn't pay for the full lifecycle. Lean: a
  thin `JobAllocation` (start=run, no `update`, no adopt, respawn-or-skip) vs the full
  `Allocation` (daemon/lease). *(the `update` door schedules its I/O off-band — not sync in reconcile.)*
- **Observability tie-in** — Allocations as first-class addressable/inspectable nodes → likely
  the reserved "unified topology tree" (ADR-0008 P2) + the observability ADR (0012).

---

## Follow-ups / dependencies

- **genesis FR (OPTIONAL — not load-bearing)** — a non-registering inherited lookup
  (`getInheritedSeedOfExactType`, mirroring Flutter's `getInheritedWidgetOfExactType`); a minor
  read-once-and-ignore optimization. The **primary** read is the existing registering `dependOn`
  (react via update/replace); `StableInheritedSeed` covers constant config. **Genesis is not
  blocked on this.** File against genesis `packages/tree` when convenient.
- **genesis_tree doc** — the third-tree pattern (four pieces + typesetting/perception).
- **M6 parked behind this.** The burn's follower becomes the **first Allocation client** — an
  addressable, held, re-adoptable Allocation — so the burn *falls out* of this design instead
  of being bolted onto the `Expando`/frozen-snapshot model.

---

## Guardrails held (so we don't over-build)

- **Earn each of the four pieces from a concrete need** — don't rebuild Flutter's RenderObject
  slab for symmetry. Concrete needs so far: kill the `Expando` (leaf instance state),
  adopt-a-live-process (restoration), hold a process/lease/tmux with update-or-replace.
- **Keep the general third-tree pattern domain-free** — "Allocation" is the_grid's flavor,
  like "typeset box" is typesetting's. No genesis-level universal node name.
- **Retired this session:** `Ready` StepState, `ResourceBag`, governance-as-universal-layout-protocol.
  *(A Heavy/linked tree is NOT retired — it's not-needed-now; a domain builds it when it can name
  a relationship the Light mechanisms can't carry.)*
