# SCRATCH — engine-tree diagnostics projection (design surface)

**Status:** Design **RATIFIED through decomposition (Nico, 2026-07-18)**. This version
**supersedes the 2026-07-15 harvested PRD** that previously lived here: that draft
over-specified mechanism (a `runtimeType`-keyed describe hook, a hand-maintained node
inventory, an undecided transport interface); the ratified design replaces all three.
The retired node inventory is deliberately **not** carried forward — the tree
self-describes (§4), so no inventory is load-bearing.
**Beads:** `tg-0ds` (this epic, decomposed → `.1`–`.8`, staged/deferred 2026-07-25) ·
`tg-wisp-5xa` (the standalone LAN cockpit; its C-1/C-2 are delivered here).
**Relates:** ADR-0007 §5 P2 "unified topology tree" (this IS it) · ADR-0012
(Observability, PARTIAL — amendment = `tg-0ds.8`) · ADR-0013 (no side-channels) ·
ADR-0009 (the Allocation tree) · genesis ADR-0006 (pull-free) · `docs/SCRATCH-cockpit.md`.

**Reality stamp (2026-07-19, public-readiness pass):** §3's era-claim that molecule
mode is "currently inert (default `flatCursor`; no `ProcessLeaseVendor` ever
constructed)" is obsolete. As of `tg-h4u` (drive `ProcessLeaseVendor`, #62),
`tg-6gi` (arm live molecule mint mode, #70) and `tg-2mb` (mount the vendor on the
production work seat, #73), molecule is the **live default at the production work
seat** — `grid_sdk`'s `SubstationWork` (`station_work.dart`) defaults
`CircuitMintMode.molecule` — and `StationProcessLeaseVendor` is composed on the
production path. The engine-level `SubstationConfig.circuitMintMode` default
remains `flatCursor` as a fallback; its retirement stays staged under `tg-eli`
(flat-path retirement), per the plan below.

**Further reality stamp (tg-eli, 2026-07-19):** flat-path retirement above is now
complete — `CircuitMintMode`/`flatCursor` are deleted; molecule is the only
circuit engine, no mint-mode switch remains.

## 1. The want (one sentence)

**Observe the running grid: the tree describes itself, and one or more reporters —
the VM-service wire, WS/HTTP, whatever a station selects — carry that description
out.** Everything below is subordinate detail.

## 2. Ratified model (2026-07-15, unchanged)

The running grid IS a `genesis_tree`; project its **desired state** by walking the
**live tree, pull-free** (A39 / genesis ADR-0006). Not a snapshot-serialize of the
observed input, not a registry hand-off, not a ledger read. Full re-walk per flush →
a complete `TreeSnapshot`; the kernel provides the post-flush signal; nodes never
emit deltas from `build`. Diagnosticable-style introspection **beside** perception,
never through it (`serializePerceptionFragment` requires a perception `NodeElement`
root; engine Branches serialize empty — verified, ruled out).

## 3. Engine-first: the whole session/work graph is tree structure (RATIFIED 2026-07-18)

The 2026-07-18 re-map (against the post-rewrite engine) found the tree spine
**unchanged** and the molecule rewrite (tg-pm6) to be a **persistence-substrate**
change only: a molecule-mode circuit is one `type=molecule` + per-step `type=step`
bead in the **state store**, re-projected by `SessionScope.build` into the same flat
`CircuitCursor` feeding the same `CircuitScope` (`session_scope.dart:875`). Molecule
mode is currently **inert** (default `flatCursor`; no `ProcessLeaseVendor` ever
constructed; backward-motion derivation unwired pending A52). The tree mounts only
the **eligible frontier** — the full circuit lives in a `Map<String, NodeCursor>`
threaded as config: the same field-jammed-structure smell ADR-0009 named for
`Allocation`. (The re-map's "molecule mode inert / backward motion unwired pending
A52" note is already stale: **A52 was resolved (a2) and implemented the same day** —
`tg-43o`, PR #61 — rework rounds are **successor incarnation beads on a `supersedes`
chain**; `derivedGeneration` = chain depth, derived from the snapshot; history is
graph structure, never a mutable counter.)

**Ratified: fix the engine, not the projection** (`tg-0ds.1`, the prerequisite):

- **Every circuit step mounts as a node.** The **effect child** (`CapabilityHost`)
  mounts beneath its step node **only while the step is on the frontier** —
  mount=spawn moves one level down and stays true.
- **The step node keys on the stable circuit path; the effect child keys on the
  CURRENT INCARNATION — the supersedes-chain head bead id** (A52-a2 / `tg-43o` — a
  reversal is a newly minted successor bead; the derived state rolls the frontier
  back; no mutable counter). Restart (crash respawn) stays its own axis. Rework
  history reads as graph on a stable step node instead of identity churn.
- **Single-model by design (Nico, 2026-07-18): no legacy support.** Nothing is
  public — superseded paths are removed, not accommodated. The flat-cursor path
  (A47 `Rewind`, the persisted `rewindCount`, the `path#restart.rewind` key,
  `circuitMintMode`) is slated for retirement: **`tg-eli`** (P1), behind the
  **pre-existing** chain **`tg-h4u`** (drive `ProcessLeaseVendor` — once flat
  persistence dies, `grid.lease.*` is the only home for pid/pgid/token) →
  **`tg-6gi`** (the live molecule-arm proof; don't delete flat before molecule is
  proven end-to-end). `tg-0ds.1` depends on the retirement.
- Sub-decision folded into `.1`'s design: whether **queued** (undispatched) work
  beads also mount as passive nodes under `WorkList`.
- Consequence for this epic: **the pipeline is `children`.** No cursor-as-properties
  bridge ever enters the contract (the bridge option was considered and rejected —
  it bakes in a shape we already intended to obsolete).

## 4. The mechanism — self-describing, Flutter-faithful (REWORKED + RATIFIED 2026-07-18)

Supersedes the harvested draft's `runtimeType`-keyed hook. Flutter's actual model:
the class itself overrides `debugFillProperties(builder)` and adds typed property
objects, calling `super` so each level contributes its detail.

- A **`Diagnosable` mixin** on the engine's **own** Seeds and States (we own them —
  this is not SDK-consumer subclassing; ADR-0008 D2's "compose, never subclass"
  governs the consumer boundary, not the engine's internal introspection mixin).
- Each override adds **typed property objects** (`StringProperty`,
  `EnumProperty<T>`, `DurationProperty`, `ReferenceProperty`, …) via the builder,
  `super`-chained. Seed (config) and State (mutable) properties merge into one node.
- **The walker** harvests the live tree: it calls the hook wherever the mixin is
  present; **non-`Diagnosable` nodes are transparent** — recursed through, their
  `Diagnosable` descendants hoisted (plumbing `InheritedSeed`s, `_WorkBeads`,
  `_CircuitChildren`, `Idle` vanish). A semantic tree, not the raw element tree.
- No registry, no describe table, no inventory. `@protected branch.state` access:
  the the_grid-local walker uses genesis's own test-pattern ignore; the later
  genesis extraction replaces it with a public seam.
- **Extraction to genesis is deferred** (the org dependency arc, cf `genesis_tmux`);
  the genesis-side design thread is Nico's genesis register.

## 5. The transport seam — observable source (RATIFIED 2026-07-18)

- **`TreeProjector`** is an **optional kernel-owned seam** (null = zero cost — the
  registry/`ProcessLeaseVendor` idiom). `StationKernel` retains the root `Branch`
  (`mountRoot`'s return, today discarded at `station_kernel.dart:167`) and calls
  `projector.afterFlush(root)` in the flush microtask beside `driver.afterFlush()`.
- The projector re-walks **once** per flush and exposes **`latest`** (connect-time
  replay) + a **broadcast `Stream<TreeSnapshot>`**. `projectedAt` is stamped from
  the injected clock, never inside the pure walk.
- **Reporters compose BESIDE the kernel** (as the exploration host does today) and
  subscribe; the kernel never learns what transports exist. One walk serves all.
- Bindings: **(a) VM-service exploration wire** — JIT dev loop, DevTools + leonard
  (`tg-0ds.5`, the reference reporter); **(b) LAN WS/HTTP** — AOT builds + the
  cockpit, **same payload**, delivered as `tg-wisp-5xa` C-3 on this same seam.
- Rejected: a kernel-held sink roster (transport awareness in the kernel, per-sink
  replay duplication); per-binding pull-on-demand (N walks, drifts from §2).

## 6. The wire contract (RATIFIED 2026-07-18) — `tg-wisp-5xa`'s C-1

The serialized form of the property objects (Flutter's `toJsonMap` analog):

```
TreeSnapshot { contractVersion: int, projectedAt: String, root: TreeNode }
TreeNode {
  seedType:   String,                    // renderer discriminator
  id:         String,                    // branchId — stable identity
  key:        String?,                   // genesis Key — semantic identity
  properties: List<DiagnosticsProperty>, // sealed freezed union
  children:   List<TreeNode>,            // the REAL tree — pipeline included (§3)
}
sealed DiagnosticsProperty { name: String, level: fine|info|warning|error }
  = string | int | double | flag
  | enumValue(value, enumType)           // StepState, AllocationState, disposition…
  | duration | timestamp
  | reference(kind: bead|session|substation|pid, value)   // linkable, not printable
  | object(properties)                   // nested group, e.g. Allocation on its host
```

- Consumers **switch exhaustively**. Adding a **property** is just data; adding a
  property **kind** is a `contractVersion` bump — the right place for that cost.
- v1 message = the full `TreeSnapshot` on connect + per flush; `TreeDelta` reserved.
- Station meta = the root node's properties.
- **Supersedes** `SCRATCH-cockpit.md` §5b/5c's `SessionView`/`NodeView`/
  `CircuitTopology` wire types — those become **UI-side view-models** derived from
  the tree.

## 7. Consumers

- **`grid_devtools`** injects the VM-wire source and renders — proving ground #1.
  **Ratified host shape (Nico, 2026-07-18): two new tabs** — **Station** (the
  operator flow: Overview → tap substation → WorkList → tap bead → Pipeline +
  Cost) + **Inspector** (the debug flow: projected-tree explorer with the
  inspector as detail pane); the existing work-axis event list **kept** as a third
  tab (a different observation — the event stream, not the projection; not legacy).
- **leonard** reads the projection headless over the exploration wire (`tg-e28`
  precedent) — the AI-debugs-the_grid pitch; no standalone viewer. Concretely
  (`tg-0ds.7`): no leonard-side product code — the deliverable is a non-skipping
  `grid_exploration` integration test (attach → handshake → latest snapshot →
  mutate → observe the new snapshot: the reactivity proof).
- **`grid_cockpit`** (later, `tg-wisp-5xa`) injects the LAN socket source.
- **`grid_cockpit_ui`**: `flutter` + contract types only; view-models over an
  injected abstract Live/Replay source (the `leonard_devtools` `TimelineSource`
  pattern). **Ratified v1 view inventory (Nico, 2026-07-18):**
  `StationOverviewView` (is anything being built) · `WorkListView`/`WorkBeadTile`
  (what — disposition badges) · `CircuitPipelineView` (**flagship**: the step-node
  subtree as a state-colored pipeline — step state, incarnation depth from the
  supersedes chain, durations, nested sub-circuits) · `DiagnosticsInspectorView`
  (the generic backstop: typed properties, severity coloring, reference-chips
  navigating bead → session → pid) · `CostTile` (prop-tolerant). Timeline/history
  views deferred (snapshot retention; `TreeDelta` reserved).

## 8. What a walk does NOT see (recorded, deliberate)

Off-tree machinery is invisible to the projection by design: `StationDriver`,
`WedgeMonitor` (wedge state), the join bridge/notifiers, `RestartReconciler`, and
`Allocation` objects (described as **properties of their host**, per ADR-0009 —
the Allocation tree is held by reference, not as Branches). If wedge/driver state
ever needs surfacing, the candidate is root-node properties fed by the kernel — a
future amendment, not designed here.

## 9. Decomposition (filed 2026-07-18; staged — `.1`–`.5`/`.8` deferred 2026-07-25, `.6`/`.7` kept deferred 2026-08-08 per Nico)

| Bead | What | Depends on |
|---|---|---|
| `tg-0ds.1` | engine: every circuit step is a tree node — effect child only on the frontier | `tg-eli` (flat retirement, ← `tg-h4u` lease drive + `tg-6gi` molecule proof) |
| `tg-0ds.2` | diagnostics wire contract — TreeSnapshot + sealed property union (5xa C-1) | — |
| `tg-0ds.3` | `Diagnosable` mixin + `debugFillProperties` + the tree walker | .2 |
| `tg-0ds.4` | `TreeProjector` — the kernel's observable projection seam | .3 |
| `tg-0ds.5` | VM-wire reporter — the exploration host publishes TreeSnapshots | .4 |
| `tg-0ds.6` | **EPIC** (retyped 2026-07-18): `grid_cockpit_ui` + the `grid_devtools` proving ground | .2 .5 .1 |
| — `tg-0ds.6.1` | foundation — `TreeSource` (Live/Replay), view-models, primitives | .2 |
| — `tg-0ds.6.2` | the five v1 views (Pipeline flagship) | .6.1 |
| — `tg-0ds.6.3` | `grid_devtools` Station + Inspector tabs (events tab kept) | .6.2 .5 |
| `tg-0ds.7` | leonard reads the projection headless (proving ground #2) — the `tg-e28`-pattern reactivity test, no leonard-side product code | .5 |
| `tg-0ds.8` | ADR-0012 amendment — record the decisions, fix perception=JIT | — |

Blessing into the ready frontier is Nico's lever; nothing here is armed.

## 10. Follow-ups (outside this epic)

- The **genesis-side design thread** for the `Diagnosable`/walker extraction
  (Nico's genesis register).
- `tg-wisp-5xa` C-3/C-5 build against this contract + seam once delivered.
