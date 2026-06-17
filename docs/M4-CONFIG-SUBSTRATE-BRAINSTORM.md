# Brainstorm — the desired-state config substrate: genesis_tree authoring (stateless + stateful) + gc pack-TOML import

**Status:** Brainstorm / proposal — **doc-before-code, NOT a ratified ADR.** Nothing here is decided. This is the brainstorm rung of the gate (`brainstorm → PDR → ADR → zero open questions → code`); recommendations are for Nico to accept, redirect, or reject. Any AI sub-decision below becomes an ADR-0000 amendment (**A36+**) **only after** Nico picks a direction. **Refined by a 2026-06-16 working session — see "Where we landed" below, which supersedes the forks/recommendations in §§1–6 where they conflict.**
**Date:** 2026-06-16 (refined 2026-06-16 working session)
**Author:** Claude (for Nico)
**Relates to:** A30 (engine stays snapshot-diff), A31 (genesis at the surface/render layer, M3), A32 (M3 ownership chokepoint), M4-SCOPING M4a/M4b, ADR-0003 Decision 1 (gc runs *two* reconcilers; the_grid ported only convergence), genesis ADR-0001 (Seed/Branch spine), genesis ADR-0005 (interfaces-as-projections), genesis register A7 (two-reconcilers flag, closed to the_grid).

---

## Where we landed — working session 2026-06-16 (supersedes the forks/recommendations below where they conflict)

A live design conversation (Nico ↔ Claude) refined and in places **corrected** the fan-out's recommendations. This section is the current thinking; §§1–6 are the supporting exploration, superseded where they disagree. **Still a brainstorm — no PDR, no ADR yet.**

1. **Seeds all the way down — one composition model.** `Grid → Rig → {Order, Formula, Step}`, each a `Seed`, each multi-child, each inflatable from TOML. `Step` is a leaf `Seed` (projects one desired bead); `Workflow`/`Formula`/`Rig`/`Grid` are container Seeds. There is **no separate `Plan`/`Step` value algebra** — the only value type is the harvested **`DesiredState`** projection the reconciler consumes (genesis ADR-0005's projection move). Composition = Seed nesting, exactly like widgets (sub-workflows are child Seeds; reuse via const constructors; fan-out via keyed loops; ambient via `InheritedSeed`).

2. **Workflows are PURE FUNCTIONS, not mounted state machines (corrects §2.2's "keep mounted").** A workflow is `observed beads → the whole current plan` (all pending steps present, not a single-step cursor). It branches by reading **typed results off the beads**, not via hidden `setState`. That makes it **crash-safe / rehydratable by construction** (re-evaluate over observed beads → identical plan) and keeps it to **one reconcile** (avoids the second keyed-reconcile a long-lived mounted tree would add — the genesis-A7 smell). The `StatefulSeed`+`setState` framing is wrong for the work plan; genuinely-mutable `State` only earns its keep for *ephemeral* coordination you can lose on restart.

3. **Typed handoff rides the beads.** A step's typed result is written onto **its step bead** (one source of truth, crash-safe). A `StepResultRepository` reads it off the observed graph and emits a typed `Stream<StepResult>`, **injected** into the tree (`Watch`/`InheritedSeed`) — never a bead-subscription from inside the tree (preserves the A30 coherence invariant). Handoff lives in the repo/service layers, not the tree. The bd round-trip per handoff is **accepted** (optimize later if it bites).

4. **The reconciler is NOT replaced — it's completed + doubled.** Its role is unchanged: `diff(desired, observed) → actuate via the A32 chokepoint`. The tree finally gives it the **desired-state input** ADR-0003 D1 deferred to M4. A **second** topology/workflow reconciler is added (gc runs two; the_grid ported only convergence as M2); **M2 convergence stays as-is** (built, conformance-green) and is recognized as the *first* stateful-workflow pattern (iterate-until-gate = Check/Retry). The diff is **desired-vs-observed** (observed is the only truth that survives a crash).

5. **`DesiredState` is heterogeneous + ownership-partitioned.** Per-facet sub-states — `desiredRigs` / `desiredTriggers` / `desiredBeads` — each diffed vs observed and actuated by its own handler through the **one** chokepoint. A `Rig`'s ownership marker propagates via `InheritedSeed` (`RigScope.of`), so every desired bead is stamped with its rig and the **coexistence guard falls out of the tree structure** (a `Grid` building an unowned `Rig` produces state the chokepoint refuses).

6. **Orders are live reactions, not a ledger or a table.** Port gc's **pure** `CheckTrigger(order, now, lastRun)` (`internal/orders/triggers.go`: cooldown `elapsed ≥ interval`; cron minute-match **with catch-up**). Triggers enter as **injected signals** (a clock stream for cron, a condition stream for events) — time is injection, A30-coherent. The only durable state is **one `lastRun` cursor per order** — a per-order cursor bead (through the chokepoint) or derived from the order's poured beads (always-pour orders). No per-fire tags; no new Dolt table. (If grid-private non-bead state is ever needed, it goes in a **separate** the_grid DB, never `tg` — A21 working-set entanglement.)

7. **Hot-reload is DEV-ONLY (corrects §1's reactivity framing).** Hot-reload is the **authoring** loop; it is **not** the dispatch mechanism (dispatch = the reconciler reacting to observed beads + injected signals). Same tree, two modes — the Flutter split: **dev = hot-reload; prod = AOT grid binary deployed to a Linux VM.** Dev edit semantics: keyed reconcile preserves in-flight rig/step identity; a removed node → **drain by default** (force-kill behind a flag); a re-added same-keyed node re-attaches to its in-flight beads (identity = bead identity). Prod structural change = a **versioned deploy**, not a live mutation.

8. **Keys + composition gaps → genesis feature requests (FILED).** `Seed.key` is already `Object?` (not String) → use a **typed `StepId`**, not bare strings. In-scope `needs` resolve via `InheritedStep.of(ctx, id)` / a `StepScope`; cross-tree refs **pass handles through the parent** (no GlobalKey). Filed against genesis: **`genesis-7r9`** (multi-child `Branch`/`Seed` keyed list-reconcile) and **`genesis-q8h`** (a first-class `Key` type — LocalKey/ValueKey, deliberately no GlobalKey).

9. **TOML inflation = two front doors, one Seed tree.** `Grid.fromToml` / `Rig.fromToml` / … build the *same* Seeds you'd author by hand; a central **`PackInflater`** owns gc's override/patch tri-state + replace-vs-append merge + V2 imports/overlay as explicit Seed-merge operators. Stateless inflates losslessly (round-trips to TOML, gc `configedit` compat); Dart-authored *branching* workflows have **no** TOML form (the honest asymmetry).

10. **Genesis composition-layer "second consumer" worry — dropped.** genesis is Nico's package (shared with lenny); the_grid just **uses and co-evolves** it. No vendoring/freezing anxiety.

**Open / next (when this graduates past brainstorm):** the exact `DesiredState`/`Plan` freezed shape + the projection-harvest contract; the `Formula` vs `Step` boundary; the `needs` cross-subtree discipline detail; the ADR renumber (M4-SCOPING maps M4a→ADR-0005 / M4b→ADR-0006, both taken → ADR-0007+); then `brainstorm → PDR → ADR` per the gate.

---

## 1. The idea and the motivation

Today the_grid has actuation hands (M3: dispatcher, worktree isolation, the `GridBeadWriter` chokepoint) but **no authored desired-state object**. M3 drives dispatch off observed `bd ready` work, not off a config plan. The thing that *says what the city should be* — gc's `cmd/gc/build_desired_state.go`, which turns `config.City` (city → imports/packs → rigs → agents/named_sessions/orders) into a `DesiredStateResult{State: map[sessionName]TemplateParams}` — was explicitly deferred to M4b (ADR-0003 Decision 1; M4-SCOPING).

**The proposal:** author the_grid's desired-state topology/config as a **`genesis_tree`** — the bare-VM Flutter-element/reconcile model (Seed = immutable config ≈ Widget; Branch = mounted keyed-reconcile node ≈ Element; StatelessSeed ≈ StatelessWidget; StatefulSeed + State + `Watch<T>`/`Sprout` ≈ StatefulWidget; InheritedSeed ≈ InheritedWidget). Support **both**:

- **(a) Stateless configs** — static declarative descriptions. A `StatelessSeed` subtree whose `build()` composes purely from its own immutable fields. This is the gc-pack-TOML analogue, and it is also the **import target**: gc pack TOML decodes to a `StatelessSeed` subtree.
- **(b) Stateful configs that run logic** — config nodes that hold state and react. A `StatefulSeed` whose `build()` returns a *different* child subtree as live state changes (e.g. a rig that scales its agent count off live backlog via `Watch<int>`/`useStream` over a backlog signal). This is the StatefulWidget analogue, and it is the **native, debuggable replacement** for the place gc already smuggles logic into config: the `scale_check` shell-command-template-over-stdout, `work_query`/`sling_query` templated `bd` strings, `on_boot`/`on_death` hooks, order condition-triggers, and formula `Range`/`Loop` arithmetic.

**Why this is worth a doc:**

1. **Flutter-dev-at-home authoring.** The PDR's thesis is one language / one architecture / one debugging surface. A Flutter dev authoring their grid as a Seed/Branch tree with `build()`, `setState`, `Watch<T>` and InheritedSeed is authoring with the exact model they already know — and the same VM-service debugging surface (G2/G3) reaches the live authoring tree.
2. **gc pack-TOML compat without freezing expressiveness.** gc's own thesis is "any orchestration pack is pure config" (examples/gastown/city.toml). That declarative config maps 1:1 onto `const StatelessSeed`s, so imported cities keep working — *and* a dev can drop into Dart logic exactly where gc had to reach for a shell string. One subtree, two front doors.
3. **It fills an empty slot, it does not contest an occupied one.** The M2 reducer takes only `(Convergence, ReducerEvent, GraphSnapshot)` — it has **no desired-state input parameter** (a grep for `desired` across `grid_reconciler/lib/src/convergence/` and `reducer/` returns zero). The config tree is the missing producer of the desired plan the deferred M4b topology reconciler converges toward — *not a duplicate of any existing machinery.*

---

## 2. Architecture

### 2.1 The pipeline (one direction, two trees, one meeting point)

```
   AUTHORING (desired)                 |   OBSERVED (reality)
                                       |
   CitySeed                            |   bd graph (issues ∪ wisps)
     └─ PackSeed (keyed)               |     — no keyed-tree root (A30)
         └─ RigSeed (keyed)            |     — stays snapshot-diff
             ├─ AgentSeed (keyed)      |        (diff_snapshots.dart)
             ├─ StatefulSeed(Watch<backlog>)→ N AgentSeed
             ├─ OrderSeed              |
             └─ FormulaSeed            |
   [genesis_tree: keyed reconcile]     |   [GraphSnapshot]
            │                          |          │
            ▼ TreeOwner.flush()        |          │
   PROJECTION / HARVEST                |          │
   (walk mounted Branch tree)          |          │
            │                          |          │
            ▼                          |          │
   DesiredState (freezed value) ───────┴──────────┘
                       │
                       ▼
        M4b topology reconciler:  diff(DesiredState, GraphSnapshot)
                       │
                       ▼
        actions → DispatchInteractor / RuntimeActuator.spawnSession
                       │
                       ▼
        GridBeadWriter chokepoint (A32: fail-closed ownership re-check)
```

The two trees never share a node identity space. The genesis keyed-reconcile runs **only over config Seeds** to compute the desired plan; it **never** reconciles a bead. The snapshot-diff engine runs **only over observed beads** (A30, unchanged). They meet at exactly one place: a plain **`DesiredState` value** consumed by the M4b reducer, and all writes funnel through the single A32 chokepoint.

### 2.2 Adopt the spine, treat composition as experimental

The survey confirms two tiers in genesis_tree:

- **The spine — stable in shape.** `Seed` (immutable config, `createBranch()`/`key`/`canUpdate`), `Branch` (mounted persistent node, `branchId`, mount/update/unmount, dirtiness, one `performRebuild()` hook — deliberately **not** implementing TreeContext, shedding Flutter's Element≡BuildContext original sin), `TreeContext` (a capability handle that throws `StateError` after unmount), `TreeOwner` (root + dirty-set + synchronous depth-ordered `flush()`). Keyed reconcile is by identity (key for keyed children, positional cursor for unkeyed), with an `identical(old, new)` subtree-prune fast path that **never consults `Seed.operator==`** — so config Seeds are free to carry freezed value-equality for wire diffing without changing reconcile semantics.

- **The composition layer — EXPERIMENTAL.** `StatelessSeed`, `StatefulSeed`+`State`, `InheritedSeed`, `Watch<T>`, `Sprout` (hooks: `useState`/`useStream`/`useEffect`/`useMemo`) all carry the library banner "EXPERIMENTAL: this API may change before 1.0; it freezes only after a **second consumer beyond perception** adopts it." **the_grid adopting composition for config authoring would BE that second consumer** — it both *drives the freeze* and *absorbs the pre-1.0 churn.* This is a real, recorded exposure (genesis ADR-0001 Decision 3, two-consumer rule).

**Recommendation:** adopt the spine for config authoring; record the composition-layer exposure as an ADR-0000 amendment; pin genesis as a sibling-checkout path dependency (the A31/A34 pattern). This is a **deeper** adoption than A31 (which uses genesis only at the render *surface*); see §5.

### 2.3 the_grid must supply its own domain Seeds + a projection step

Two things genesis deliberately does **not** ship, that the_grid must add:

1. **Multi-child container Seeds.** A `ComponentBranch.build()` returns a *single* child Seed (composition is single-child; `updateChild` reconciles `_child` at slot 0). Fan-out (city → N packs → M rigs) needs a **non-component container** Branch that overrides `performRebuild` to call `updateChildren` — exactly the `Node`/`NodeBranch` **test fixture** that is *intentionally excluded* from the tree lib ("tree core is artifact-agnostic; container primitives with domain meaning live with their domains"). So the_grid authors `CitySeed`/`PackSeed`/`RigSeed`/… as its own domain container Seeds. This is the genesis ADR-0005 partition: *genesis projects a tree; the_grid projects a domain.*

2. **A projection / harvest pass.** The mounted Branch tree is the *output*, not the plan. After each `TreeOwner.flush()` (which conveniently **returns the list of branches it actually rebuilt** — depth-ordered, drained dirty set), a projection walks the mounted tree via `visitChildren` and emits the freezed `DesiredState` plan. This is genesis ADR-0005's "interfaces-as-projections" move applied on the **expression/authoring** axis — the same shape `perception` uses to harvest measurements over a mounted tree. Because `flush()` returns exactly the rebuilt branches, the harvest can be incremental.

### 2.4 How a stateful config node produces a reactive plan

The canonical case ("a rig that scales agent count off live backlog") is, today in gc, the `scale_check` shell-command-template whose stdout reports unassigned-session demand, fed into `ComputePoolDesiredStatesTraced`. In the_grid it becomes a `StatefulSeed`/`Sprout` whose `build()` does `useStream(backlogStream)` and emits N `AgentSeed` children. `Watch<int>`/`useStream` subscribes in `initState`, funnels each event through `setState` → `markNeedsRebuild`, cancels on `dispose`. Keyed reconcile diffs old-vs-new `AgentSeed` set → desired-state delta → the M4b reducer scales sessions. The shell-out is replaced by an **in-process Dart `Stream<int>`** that is first-class, typed, and live-debuggable.

**The one hard invariant for coherence (see §5):** the backlog signal the StatefulSeed watches must arrive as an **explicitly injected Stream input**, never by the config tree subscribing *into* the observed snapshot-diff pipeline. If the config tree starts observing beads, it becomes a second change-detector over reality and re-creates the very collision A30/A7 warn about.

### 2.5 gc pack-TOML import as a stateless Seed subtree

gc pack loading is a **pure function of files** (no live state): parse → validate `schema=2` → expand `includes`/`imports` (diamond-dedup + cycle detection) → stamp binding-qualified names → convention-discover agents/orders/formulas → apply the three-layer override merge → flat City. The_grid mirrors this loader as a **TOML → StatelessSeed transformer** with no runtime coupling. const-canonicalize where possible so the `identical`-skip fast path prunes unchanged pack subtrees at reconcile time.

The **hardest fidelity detail** is the override/patch system: pointer **tri-state** (`nil`=inherit / clear / set) plus replace-vs-append duals (`Args` replace; `pre_start` vs `pre_start_append`; `Env` merge + `EnvRemove` subtract; `InjectFragments` null=no-op) across three layers (pack `agent_defaults` → pack `[patches.agent]` → city `[patches.*]` → rig overrides). These must be modeled as **explicit Seed-merge operators with sentinel/optional fields**, not naive field overwrites, or imported cities silently diverge.

---

## 3. Side-by-side sketch — a Dart-authored stateful rig vs the equivalent gc pack TOML

**Stateful Dart authoring (the upgrade):** a rig that scales its `claude` exec pool off live backlog.

```dart
// grid_topology — domain Seeds on the genesis_tree spine.
class ElasticRig extends StatefulSeed {
  const ElasticRig({
    required super.key,           // = rig id, the reconcile identity
    required this.path,
    required this.backlog,        // INJECTED Stream<int> — never read from the snapshot-diff pipeline
    this.min = 0,
    this.max = 8,
    this.itemsPerAgent = 4,
  });
  final String path;
  final Stream<int> backlog;
  final int min, max, itemsPerAgent;

  @override
  State<ElasticRig> createState() => _ElasticRigState();
}

class _ElasticRigState extends State<ElasticRig> {
  // Sprout-style equivalent: final depth = ctx.useStream(seed.backlog, initial: 0);
  late int _depth = 0;
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = seed.backlog.listen((d) => setState(() => _depth = d));
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Seed build(TreeContext context) {
    final n = (_depth / seed.itemsPerAgent).ceil().clamp(seed.min, seed.max);
    return Rig(key: seed.key, path: seed.path, children: [
      for (var i = 0; i < n; i++)
        Agent(key: '${seed.key}-exec-$i', processNames: const ['claude'], nudge: 'Check your hook.'),
    ]);
  }
}
```

**Equivalent gc pack TOML (the import target / 1:1 escape hatch):** the same elasticity, expressed as gc does it today — an opaque shell command.

```toml
# agents/exec/agent.toml
scope                = "rig"
min_active_sessions  = 0
max_active_sessions  = 8
process_names        = ["claude"]
nudge                = "Check your hook."
# logic-in-config, gc-style: stdout reports new unassigned demand, evaluated each tick
scale_check          = "bd ready --rig {{.Rig}} --json | jq '[.[]] | length / 4 | ceil'"
```

Import maps that TOML to `const Agent(scope: Scope.rig, min: 0, max: 8, processNames: ['claude'], nudge: 'Check your hook.')` plus a stateless wrapper preserving the raw `scale_check` string (gc-parity, inert in the_grid runtime) — **or**, on the author's choice, the `ElasticRig` above (the native, reactive, debuggable form). Same effect; one is an opaque subprocess, the other is first-class state + rebuild.

---

## 4. The central forks (recommendations, not ratifications)

### Fork 1 — Evaluation model: compile-once vs kept-mounted
**Recommend: keep the tree MOUNTED as a live reactive controller** (one `TreeOwner` inside the new package), with compile-once as the *degenerate special case* when a subtree is all-stateless (no `Watch`). A one-shot compile cannot react to backlog, so stateful config — the whole point of (b) — is impossible without a mounted tree. Cost: a live object graph + one stream-subscription set per stateful node + a flush loop. The mounted tree's `onNeedsFlush` produces a *new* `DesiredState` value on each settle; the M4b reducer treats it exactly like a new `GraphSnapshot` — the two loops are **decoupled by a value (the plan)**, neither calls the other. **Known bound (A31):** `TreeOwner.onNeedsFlush` is single-observer — fine for one topology owner per grid process.

### Fork 2 — What `build()` yields: raw Seeds vs a domain projection
**Recommend: `build()` composes Seeds (the authoring surface), but the externally-consumed output is a typed freezed `DesiredState` PLAN projection** (`Set<DesiredSession>`, `Set<DesiredOrder>`, pool floors/ceilings), **not** the raw Branch graph. The M4b reconciler must **not** depend on genesis_tree internals — keep genesis a leaf dep and the plan the stable contract (genesis ADR-0005 "Context = the projection"; the_grid ADR-0002 "reactive domain projections"). A `PlanProjection` walks the mounted leaf Branches and emits the freezed value — the tree's analogue of a genesis render backend over a mounted tree.

### Fork 3 — TOML bridge: parse-to-Seed-subtree vs parallel importer
**Recommend: TOML parses to a stateless Seed subtree at load (one model, not a parallel importer).** gc's pack TOML is already declarative, so it maps onto `const StatelessSeed`s; a parallel importer would fork the desired-state representation and double the reconciler's input surface. **Round-trip asymmetry to flag explicitly:** a pure-stateless subtree serializes *back* to TOML losslessly (it is data — `gc configedit` compat scoped here); a **stateful Dart subtree cannot round-trip to TOML** (logic has no TOML form). Rule: TOML-sourced subtrees stay stateless and round-trippable; Dart-authored stateful nodes are Dart-only, and editing them is editing code.

### Fork 4 — Package home: new the_grid package vs in genesis
**Recommend: a new the_grid package (`grid_topology`) depending on `genesis_tree` as a sibling-checkout path dep — NOT in genesis.** genesis is domain-free; `City`/`Pack`/`Rig`/`Agent`/`Order` are the_grid **domain** nouns and belong in the_grid (genesis ADR-0005 Decision 5: "grid projects a domain; genesis projects a tree"). Precedent: A31 (`grid_tui` on `genesis_tree`), A34 (`genesis_tmux` as a path dep). **Caveat to record:** this consumes genesis_tree's *spine* for desired-state, a deeper adoption than A31's render-only surface use — it must be ratified on its own, not folded silently into the A31 ADR-0005.

### Fork 5 — Stateful-config safety / blast radius
**Frame, with a recommended four-invariant guardrail (all already supported by the spine):**
- **(a) `build()` is pure, no I/O.** Sprout already asserts no `setState` during build; demand probes (backlog, clocks) are async Stream sources subscribed *outside* build via `Watch`/`useStream`, so build stays synchronous and side-effect-free.
- **(b) Per-flush timeout / quarantine.** A stateful node whose `build()` throws or whose stream errors is quarantined to its last-good subtree (the gc session-quarantine analogue), so one bad rig-formula cannot freeze the whole desired-state recompute.
- **(c) The tree NEVER mutates beads.** Its only output is the `DesiredState` value; *all* bead writes go through the A32 `GridBeadWriter` chokepoint, which re-checks ownership fail-closed. A stateful node that "wants" 999 agents in an unowned rig produces a plan the chokepoint simply refuses — it stays inside the ownership partition **by construction.**
- **(d) Branch purity (genesis A31).** Lifecycle stays off the spine; any the_grid action seam is additive on a domain Branch subclass, never on the genesis base.

**Open within Fork 5 (for Nico):** failure semantics — when a probe stream errors or `build()` throws, is the policy "hold last-good subtree" (recommended; conservative) or "drop the rig from the plan" (risks an unwanted scale-to-zero)? Either way needs an operator-visible signal.

---

## 5. A30/A31 coherence verdict

**Verdict: coherent. The config-authoring axis is a genuinely NEW, third adoption axis that does NOT conflict with A30, provided one invariant holds. It sits BESIDE A30/A31 — it does not amend their substance — and warrants its own ratified the_grid ADR (it is a deeper adoption than A31).**

The rigorous argument:

1. **A30 and genesis-A7 are scoped to the OBSERVED side only.** genesis A7 asks "does grid mount its bead **domains** as genesis tree nodes?" — about observed beads. A30 answers *no for change-detection*, and its **sole grounds** are "the bead graph (issues ∪ wisps) has **no keyed-tree root.**" Both reason exclusively about change-detection over observed reality.

2. **The proposed axis is the opposite side.** The desired/authoring topology (city → packs → rigs → agents/orders) is a single-root hierarchy with stable per-node identity at every level (binding name, dir, agent name — gc's `QualifiedName`, collision-as-hard-error). It **genuinely has the keyed-tree root the observed graph lacks.** A30's disqualifying fact (*no root*) is **absent** on the desired side, so A30's rejection does not transfer — this is not a reversal of A30, it is a region A30 never adjudicated.

3. **The two-reconcilers collision requires the SAME tree reconciled twice. Here each reconciler owns a distinct tree at a distinct stage.** genesis keyed-reconcile runs over **config Seeds** to produce the plan; snapshot-diff runs over **beads** to detect observed change; the M4b topology reducer diffs *plan vs snapshot*. No bead node is ever reconciled by a genesis key; no config node is ever snapshot-diffed. The collision genesis-A7 / the_grid-A7 flagged fires only if one structure is reconciled twice — which this explicitly does not do. The axis is **additive: one pipeline, two stages** (author → projected plan → M2/M4b converges observed toward plan).

4. **It is the input to a reconciler the_grid was always going to need.** ADR-0003 Decision 1 records that gc runs *two* orthogonal reconcilers per tick — work-convergence (ported as M2) and session/topology (`build_desired_state.go`, deferred to M3/M4). "The desired-state plan a reconciler converges toward" is **not new scope invented here** — it is the deferred topology reconciler's missing input. So this is M4b's authoring substrate, not a fourth reconciler.

5. **A31 covered RENDER; this covers AUTHORING — two non-overlapping consumption points of one substrate.** A31 mounts genesis at the *render edge* (a TUI inspector over **observed** state, `grid top`). This mounts genesis at the *authoring edge* (the **desired** config). Same substrate, opposite surfaces. The single-observer `TreeOwner.onNeedsFlush` limit (flagged in A31) is satisfied **per-tree**: a desired-side TreeOwner and a render-side TreeOwner are independent owners with independent roots and observers — they share the package, never the owner. This actually *strengthens* the case: the_grid becomes a genesis consumer at **both** surface layers without the engine adopting it.

**The conditions for coherence (strict, and the failure modes to guard):**
- **One-way data flow:** config-tree → `DesiredState` value → M4b reducer → bd writes via the A32 chokepoint. The config tree must **never read observed beads to drive its own reconcile.** Any live signal a `Watch` reacts to arrives as an **explicitly injected Stream**, not the config tree subscribing into the snapshot-diff pipeline. *(Failure mode A: config tree observes beads → becomes a second change-detector over reality → re-creates genesis-A7's collision on the observed side and contradicts A30.)*
- **Value boundary:** the seam is a plain freezed `DesiredState`, not a live Branch/TreeContext handle. *(Failure mode B: the snapshot-diff engine or M4b reducer reaches back into the config tree's Branch state → binds engine convergence to a keyed reconcile → also contradicts A30.)*
- **A test/lint invariant should assert** the config tree imports no observed-bead repository and the reconciler imports no genesis_tree `Branch` type. Two distinct `TreeOwner`s if both authoring and the A31 render inspector adopt genesis.

**Does it amend or sit beside A30/A31?** It **sits beside** them. A30's substance (engine stays snapshot-diff) and A31's substance (genesis at render, M3) are both **unchanged**. The right paperwork is: a new ADR-0000 amendment (the config-authoring axis), and a **one-line cross-ref appended to A30 and A31** noting the new axis sits beside them and does not revise their engine/render scope. genesis already **closed its A7 to "the_grid's own ADRs"** (2026-06-14) — so the genesis side has blessed this; the remaining gate is purely the_grid-side ratification.

---

## 6. Impact on M4 / M4-SCOPING

This is the authoring substrate for two existing M4 rungs:

- **M4a (config model)** — "city.toml progressive activation, packs/imports/overrides, rig registry." The TOML → StatelessSeed transformer + the domain Seed set (City/Pack/Rig/Agent/Order/Formula/Provider/Session + the override/patch merge operators) **is** the M4a config model. This proposal *extends* M4a from "a config model" to "a config model expressed as a genesis_tree, with a stateful authoring option on top of the stateless import."
- **M4b (topology reconciler)** — "desired sessions from config (`build_desired_state`), pool demand, ephemeral workers." The mounted tree's `PlanProjection` feeds the M4b reducer; M4b diffs `DesiredState` vs the observed snapshot and actuates through M3's `RuntimeActuator`/`GridBeadWriter`. This proposal supplies M4b's **input** (the authored plan) — it does not change M4b's actuation spine.

**ADR-numbering correction the doc surfaces (load-bearing):** M4-SCOPING's table maps M4a→ADR-0005 and M4b→ADR-0006. **Both numbers are now taken** — A31 reserves **ADR-0005** for genesis adoption, and **M3 shipped as ADR-0006** (A32–A35). So M4-SCOPING's ADR column is stale: M4a/M4b need **renumbering (ADR-0007+)**. This proposal does **not** supersede M4-SCOPING's strategy (usage-driven, just-in-time ADRs, cutover-as-acceptance); it **slots into M4a/M4b** and flags the renumber.

**Coexistence (M4-SCOPING hard invariant + A32):** the desired-state plan must be partitioned by the **same ownership allow-set** the A32 chokepoint enforces (`{tgdog}` at dogfood). gc's own `build_desired_state.go` runs over the same city.toml and the same session beads gc owns — so the_grid's topology tree must drive **only** the owned rig, or it is a two-writers hazard on session beads (the topology analogue of the convergence single-writer rule).

---

## 7. Open questions for Nico

(See the structured `openQuestions` list. The central one: §4 Fork 1 / §5 — whether the desired tree runs *live* reactive (stateful rigs watching real-time backlog, pulling a live signal into the authoring layer) or evaluates to a *static* `DesiredState` snapshot per authoring change. The live form is the whole point of (b) but carries the leakage risk §5 guards against; the static form is purely-pure but loses the "config that runs logic" autonomy.)

---

**Process note:** none of the above is decided. If Nico picks a direction on any fork, that pick becomes an ADR-0000 amendment (**A36+**, pending) until promoted — the config-authoring axis is the natural first amendment, then per-fork sub-decisions. Per the gate, the ratified M4a/M4b ADRs (renumbered) come after zero open questions, then code.
