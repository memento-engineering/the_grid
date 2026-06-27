# ADR-0007 — the running grid *is* a genesis_tree (the engine pivot + the A30/A31/Riverpod supersession)

**Status:** **Accepted 2026-06-24** (ratified by Nico; drafted by AI per the ADR-0000 register rule). This ADR **supersedes prior ratified/recorded decisions** — **ADR-0001 Decision 3** (the *ratified* Riverpod-3/never-StateNotifier primitive), A30 (in part), A31 *[pending]*, A39's no-engine-change rider *[pending]*, and a `CLAUDE.md` convention. The forward-pointer stamps in §6 were **applied on ratification (2026-06-24)** to ADR-0000 (A30/A31/A39/A6 status lines, append-only), ADR-0001 D3 + ADR-0002 D2 (one-line amendments), `CLAUDE.md`, and `docs/M4-SCOPING.md` (superseded banner) — never a silent rewrite (A33 precedent).
**Date:** 2026-06-24
**Deciders:** Nico Spencer (ratifier; decided the pivot 2026-06-24); drafted by AI per the ADR-0000 register rule.
**Gates:** M4. This is the **gating ratification** for M4 — code waits on it (the gate: doc before code). It is followed by a P0 build-order doc, then code.
**Source of record:** `docs/M4-PDR.md` (the decided, review-corrected design). This ADR promotes that PDR's §8 into this Proposed ADR and writes the load-bearing argument (§6.1) the PDR flagged as "must be written, not assumed."

**Backed by:**
- A working throwaway spike (`/tmp/grid_tree_spike`) that ran `implement → gate → land` as keyed-reconcile transitions on real `genesis_tree`, with sibling work untouched across each transition (`■ STOP agent` + `▶ START gate`; the other bead's Branch never rebuilt).
- A 5-lens adversarial review that caught two real over-claims in the first draft — the crash-safety "not that hard" claim (no process reference is persisted in M3) and the A30 "has-a-root" escape (sophistry) — both corrected below and in the PDR.
- A *second* 5-lens adversarial pass over **this ADR draft** (22 findings; 19 confirmed/partial) that hardened the supersession: it added the ratified ADR-0001 D3 quote-and-supersede (§6.6); disentangled **genesis A7** (closed, deferred to this ADR) from the_grid's **Failure-mode B** and from the gc-coexistence A7→ADR-0003 D6 (§6.1); corrected the pgid/token fence scope (Decision 4 / §6.1 inv 4); split A39's rider (§6.7); and flagged the A6 ADR-numbering collision (numbering note).

---

## Context

M1–M3 built a reactive orchestrator that **felt procedural**. The reducer/actuator design (M2 `grid_reconciler`, M3 `grid_runtime` dispatch) ported gc's *hand-rolled* reconcile loop into a `reduce → PhaseAction → actuator` machine: a `DesiredState` value, a topology reducer, and an actuator that applies a computed plan. That is a hand-reimplementation of a keyed-reconcile element tree — the exact thing **genesis ships as a general-purpose engine** (`genesis_tree`: Flutter's element/reconcile model extracted to pure Dart — `Seed`/`Branch`/`TreeOwner`/keyed `MultiChild` reconcile/`InheritedSeed`).

The_grid had the general reconciler sitting unused (as a deferred surface-layer dependency, per A30/A31) while hand-rolling the same algorithm in its engine. gc's "reactivity masked under Go" *is* a reconcile loop; reconcile *is* a keyed element tree. The design conclusion (Nico, 2026-06-24): **make `genesis_tree` the engine.** `build(observed)` is the desired running system; keyed reconcile + `Branch` lifecycle is the work lifecycle (mount = spawn, unmount = kill, phase = a reconcile transition). The reducer/actuator/value-hop dissolve.

This reverses one **ratified** decision and several derived/recorded positions: **ADR-0001 Decision 3** (the ratified reactive-primitive decision — "Riverpod 3 `Notifier` … **Not** `StateNotifier`"), echoed by **A30(2)** and the **`CLAUDE.md`** convention; **A30(1)** in part (§6.1); **A31** (the genesis-as-surface-only / "no domain tree" bet — *pending*, never ratified); and **A39's** "no engine change / Riverpod stays" rider (*pending*). Reversing recorded decisions is itself an ADR-0000-class act; per the register rule each must be **explicit (quote-and-supersede), never silent** — §6 does exactly that, including the heaviest (ratified ADR-0001 D3) in §6.6, not only its echoes.

This ADR decides only the **P0 engine + the supersession.** It deliberately does *not* decide gc-TOML import (P1/ADR-0008), the unified topology tree (P2/ADR-0009), or convergence-as-subtree (P3/ADR-0010). Those are scoped in §5 and deferred to their own ADRs.

---

## Decision 1 — The running grid is one `genesis_tree`; `build(observed)` is the desired state

The orchestrator's running state is a single mounted `genesis_tree` rooted at `Grid`. There is no separate `DesiredState` value, no topology reducer, no actuator-applies-a-plan step. The mounted tree **is** the desired running system, continuously reconciled against the observed bead snapshot.

- **Topology (config nodes are ANCESTORS of work nodes — never siblings).** `InheritedSeed` only walks *up*, so configuration that work nodes must read is mounted **above** them:
  ```
  Grid                       root
  └─ RigScope<RigConfig>     InheritedSeed — provides config DOWN to the subtree
     └─ Rig                  StatefulSeed — observes a CONFIG StateNotifier (rebuilds rarely)
        └─ WorkList          StatefulSeed — observes the SNAPSHOT StateNotifier
           ├─ WorkBead<id>   StatelessSeed — reads RigScope.of(ctx) ↑; builds to its phase effect
           └─ …
  ```
- **`WorkBead` keyed by bead id.** Each ready/owned bead is one keyed child (`ValueKey(beadId)`). Its `Branch` **persists across the bead's phase changes** (one bead identity = one Branch). `build()` switches on the observed phase → that phase's effect Seed. Advancing a phase is a rebuild → a keyed reconcile that swaps the effect Branch (unmount old effect, mount new).
- **Effect-Seeds ARE capabilities; effects live in the `Branch` lifecycle, never in `build()`.** `Branch.mount` (`State.initState`) = **start** the effect (spawn the detached process / run the gate); `unmount` (`State.dispose`) = **stop** it (kill the process group). `update` = re-attach. `build()` stays **pure** (genesis ADR-0006 / A39: synchronous build, out-of-band watch — preserved exactly).
- **Dynamic / TOML capabilities use a generic carrier `EffectSeed`**, keyed `ValueKey('$beadId.$capId')` so a capability swap changes the key → unmount+mount, with a single `runtimeType`. A **registry** resolves `capId → impl`. (Compiled capabilities may use real `EffectSeed` subtypes or the carrier; both reconcile identically. "Capabilities are Seeds" is literally true for the compiled set; TOML contributes `id + config` consumed by the carrier.)
- **Write-back is OUT-OF-BAND and stays controller-mediated (A32 chokepoint).** A detached agent's completion has no exit code (M3 spawns detached for whole-tree kill — A38); completion arrives later on the provider's event stream, to a `Branch` that may already have unmounted. The effect-Branch's `State` subscribes (in `initState`) to its session's completion event and, on completion, routes the bead write through an injected `GridBeadWriter` (the A32 ownership chokepoint, resolved via `InheritedSeed`). **The write does not relocate into the Branch** — it is triggered by the out-of-band event, not by `mount`/`build`, and goes through the same single bd-CLI writer M3 uses. No-write-in-`build` holds.
- **Change-detection stays snapshot-diff (the retained half of A30(1)).** The existing bead pipeline (file-watch + `@@tg_working` probe → single-flight re-query → `GraphSnapshot`) is unchanged. Its emitted `GraphSnapshot` is the value the tree builds from. The tree **never re-detects bead change** — it consumes the snapshot value. (This is the crux of the §6.1 argument.)

**Amended 2026-06-27 (ADR-0008 Decision 1, ratified — the "full power grid" rename):** the type *names* in this decision's topology are superseded — root `Grid` → **`Station`**; `RigScope`/`Rig`/`RigConfig` → **`SubstationScope`/`Substation`/`SubstationConfig`**; **`Grid` is repurposed** for the federation object (per-station, no center). The reconcile *semantics* here (config-ancestors, keyed `WorkBead`, effects-in-`Branch`-lifecycle, out-of-band write-back, snapshot-diff detection) are **unchanged**. **Applied in code 2026-06-27** (ADR-0008's first migration; whole-repo, `melos analyze` + offline suite green). The persisted gc key `metadata.rig` and the M2 convergence byte-port schema (`convergence.rig`/`FieldRig`/`eventRig`) are preserved across the codec boundary — only the_grid's own types/vocab moved.

## Decision 2 — Flush isolation is OBSERVATIONAL, not structural; `root.markNeedsRebuild()` is banned

Reconcile cost is contained by *which node observes which notifier*, not by tree shape:

- A **work tick** fires the snapshot `StateNotifier` → only `WorkList` (its sole observer) marks dirty → `flush()` rebuilds `WorkList` and keyed-reconciles its `WorkBead`s. The config ancestors are **never** in the dirty set; their `build()` does not run.
- A **config change** fires a config `StateNotifier` → `Rig` rebuilds → `InheritedSeed` dependency tracking marks exactly the `WorkBead`s that read that config.
- **`root.markNeedsRebuild()` is prohibited.** It was the spike's shortcut and is precisely what caused the reviewer's "config built 100× under work-churn" finding. Targeted, per-branch observation replaces it. (This is a hard rule, not a guideline — a root-level rebuild dissolves the entire isolation guarantee.)

## Decision 3 — Reactive values are `StateNotifier`, not Riverpod

the_grid drops Riverpod entirely for the standalone `state_notifier` package + freezed. A `StateNotifier<T>` service is provided via `InheritedSeed<T>`; a `StatefulSeed` locates it (`dependOnInheritedSeedOfExactType`) and observes it in `initState` (`addListener`/stream → `markNeedsRebuild`), cancelling in `dispose`. `GraphSnapshot` is carried by a `StateNotifier<GraphSnapshot>` observed by `WorkList`.

**Why (un-divergence, not preference-churn):** predictable-flutter and lenny — Nico's own stack, the house style the_grid is meant to share — are **StateNotifier + freezed**. the_grid had drifted to "Riverpod 3, never StateNotifier" (an autonomous choice made in isolation; ADR-0001 / `CLAUDE.md`). This reversal re-aligns the_grid with its siblings and removes the one stack the rest of the org doesn't use. A future genesis-native notifier (`genesis_state_notifier`) is plausible but **not required** by this ADR.

## Decision 4 — Crash-safety is **respawn-or-skip** (P0); adopt-a-live-process is **deferred** net-new work

The mounted tree is in-memory; a controller restart loses the tree, **not the work** (the work is durable in the bead store + git worktrees). On restart, rebuild the tree from the observed snapshot; each effect-Branch's `mount`:

- **SKIPS** if the bead's observed phase shows the work already finished (reconcile straight to the next phase); else
- **RESPAWNS** fresh.

This requires **two cheap persists** (the honest cost — it is *not* zero-persistence, correcting the first draft's over-claim):

1. **Durable completion** — the agent advances its bead phase through the A32 chokepoint **as its last act**, so a restart can distinguish "done" from "died mid-work." (Without it, a finished one-shot agent gets a *second* agent on restart — the A38 double-work bug, across a restart boundary.)
2. **pgid + instance-token at spawn** — persist the process-group id so respawn can **kill a still-alive orphan group** before starting fresh. **Honest fence scope:** the kill primitive is `signalGroup(pgid)` (= `kill(-pgid)`), which does *not* read the token; distinguishing a *recycled* pgid from a genuine surviving orphan requires reading the live process's `GRID_INSTANCE_TOKEN` from its environ — the same process-table scan the **deferred ADOPT** track owns. So P0's kill is fenced by the pgid safety-guard (`pgid<=1`/own-group) + the freshness barrier + the per-bead worktree (two agents can't usefully fight over one worktree), and accepts the rare recycled-pgid risk; the token's P0 role is fencing **stale async write-back delivery** (a late completion from a prior incarnation), *not* the kill.

Plus a **freshness barrier**: gate the first post-restart reconcile on one observed `@@tg_working` advance / a completed re-query before mounting any spawning effect, so a stale snapshot cannot double-spawn. And the **async-spawn-vs-unmount race** is handled by a `Completer`/cancel-flag in the effect-Branch `State` (M3's `_Session.stopping` pattern): `initState` fires the spawn `Future`; a `dispose` during an in-flight spawn flips `cancelled` and chains kill-on-resolve.

**DEFERRED (a separate later track) — ADOPT:** re-attach to and *supervise* a live detached process across a restart (no exit code) needs a persisted pid + a reconstructed liveness poll + the fence — **net-new work M3 never built** (M3 persisted no process reference at all; P0's persist #2 adds only a minimal pgid-to-*kill*, not a pid-to-*supervise*). P0 ships respawn-or-skip only. `tg-9fl` (the `listBeadWorktrees` rebind/reap sweep that has no caller — A38) is a *worktree* rebind, **not** process adoption; respawn-or-skip uses it to find the worktree, then starts fresh.

## Decision 5 — Scope fence: what this ADR does NOT decide

To keep the supersession honest and bounded, ADR-0007 decides the **P0 engine + the stack reversal + the supersession argument** and nothing downstream:

- **gc-TOML import / `PackInflater`** (capture-users-without-rewrite) → **P1 / ADR-0008.**
- **The unified topology tree** (config nodes `Rig`/pool/`Order` as ancestors; elastic rigs; ownership stamped by `RigScope`) → **P2 / ADR-0009.**
- **Convergence-as-subtree + retiring the M2 byte-port coexistence shim per-rig** → **P3 / ADR-0010.** Until then the `ConvergenceReducer` byte-port is **retained intact** as a coexistence shim (the shadow/diff harness consumes the *reducer*, not a serialized plan), and it retires **per-rig** as each gc-owned rig converts — never globally until the last rig (gc assumes one writer per bead; ADR-0003 D6).

### Note on ADR numbering (a Nico decision — flagged, not resolved)

A6 / `docs/M4-SCOPING.md` (ratified 2026-06-11) **provisionally** reserved ADR-0005–0010 for the just-in-time M4a–M4f decomposition (config / topology-reducer / orders / sling / patrol / cutover). That decomposition assumed the **reducer/actuator** engine this pivot supersedes, and the numbers were explicitly provisional ("just-in-time"; M4-PDR §10 "Provisional until ratified") — so re-pointing them is a **re-targeting, not a supersession of a ratified technical decision**. This ADR uses the tree-engine sequence: **0007** = tree engine (this), **0008** = gc-TOML import, **0009** = topology tree, **0010** = convergence-as-subtree. **ADR-0005 is RETIRED (Nico, 2026-06-24).** It was double-booked — A6 (ratified) = the M4a *config model*; A31 (pending) = *genesis adoption*; A39 also routed the tg-e28 perception there. ADR-0007 folds the config-model *engine* sense into P0, adopts genesis into the engine (so no separate "genesis adoption" ADR is needed), and the config-model *import* sense becomes ADR-0008 (gc-TOML). The optional `grid top` TUI inspector + the tg-e28 perception rebuild, if ever pursued, take a fresh number then. **Applied on ratification:** `docs/M4-SCOPING.md` carries a superseded banner re-pointing 0005–0010 to the tree sequence; ADR-0000 A6 is stamped.

## Decision 6 — The explicit supersession (the quote-and-supersede, with the load-bearing argument)

This is the ADR-0000-class act. Each superseded clause is quoted and its disposition stated. **The forward-pointer stamps are applied to A30/A31 in ADR-0000 _on Nico's ratification of this ADR_, not before** (A33 precedent).

### 6.1 — A30(1) — "change-detection stays snapshot-diff; `genesis_tree`'s keyed reconcile is NOT adopted for bead change-detection" → **partially reversed (honestly)**

> A30(1), verbatim: *"the change-detection engine **stays snapshot-diff** (`diff_snapshots.dart`): the bead graph (issues ∪ wisps) has **no keyed-tree root**, so `genesis_tree`'s keyed reconcile is NOT adopted for bead change-detection (this resolves **genesis's A7 flag** … 'two reconcilers at two layers, collision not duplication')."*

**Disposition — the conflated two halves split:**

- **RETAINED:** change-**detection** over the bead graph stays snapshot-diff. The tree does **not** detect bead change; it is a pure function of an injected immutable `GraphSnapshot`. There is exactly **one** change-detector — snapshot-diff — and the tree is its *consumer*. A30(1)'s core fear (a *second change-detector*) does not obtain.
- **REVERSED:** keyed reconcile **is** adopted for the work **lifecycle** — *downstream* of detection — keyed by bead id, to map observed bead-presence/phase onto effect mount/unmount/swap. A30(1) conflated "don't use keyed reconcile *for change-detection*" (kept) with "don't use keyed reconcile *anywhere in the engine*" (reversed).

**The load-bearing argument** (the PDR §9 risk #1: this must be written, not assumed). Two distinct concerns must be defeated, and the first draft conflated them — they are separated here:

- **genesis A7** (genesis ADR-0000, a *flag, not a decision*) asks only whether the_grid keeps structural snapshot-diff as a separate layer **or** mounts its bead domains as keyed-reconcile tree nodes. It was **closed by Nico (2026-06-14) as out-of-scope for genesis — explicitly "the_grid's own decision, recorded in the_grid's own ADRs if/when it consumes genesis." This ADR *is* that decision.** (The "two reconcilers at two layers, collision not duplication" phrasing belongs to genesis **ADR-0004 D6**, quoted via A30(1) above — not to A7's own text.)
- **Failure-mode B** is the_grid's **own** coinage (`docs/M4-CONFIG-SUBSTRATE-BRAINSTORM.md` §5, *not* ratified; the PDR §8 names it "the brainstorm's Failure-mode B guard"): a tree's internal `Branch`/`State` leaking back out as a *second source of truth* that fights the snapshot.

Four invariants defeat both — **genesis A7** by #1 + #4 (one detector, one reconciler-consumer); **Failure-mode B** by #4; and the *separate* **gc-coexistence** concern (the_grid's own A7 → ADR-0003 D6) by #3:

1. **Single change-detector.** Only snapshot-diff detects bead change. The tree consumes an immutable value (`GraphSnapshot`) injected via a `StateNotifier`; it never subscribes into the detection pipeline. (This is exactly A39's already-recorded guard: *"a `Watch` may react **only** to an explicitly injected `Stream`, never the config tree subscribing into the bead snapshot-diff pipeline."* — preserved, not weakened.)
2. **One-directional dataflow, no cycle of authority.**
   ```
   bd store (the only authority)
     → file-watch + @@tg_working probe → single-flight re-query
     → snapshot-diff → GraphSnapshot (immutable) → StateNotifier
     → tree.build(observed) → keyed reconcile → effect mount/unmount
     → effect completion (out-of-band event)
     → GridBeadWriter chokepoint (A32, bd CLI, single writer)
     → bd store
   ```
   The loop closes **only** through the bead store via the single A32 writer. The tree → reality coupling is *the chokepoint write and nothing else.*
3. **Exactly one reconciler inside the_grid; gc-coexistence is a *separate* partition concern.** The work tree's children **are** keyed by bead id — the same id-space as the bead set; we do **not** claim a different key-space (the first draft's "has-a-root" escape was sophistry and is withdrawn). genesis A7's worry — *two* reconcilers over one structure **inside the_grid** — does not arise: there is exactly **one** change-detector (snapshot-diff, #1) and exactly **one** reconciler (the tree, a downstream consumer, #1+#4). **Separately**, the gc-vs-the_grid single-writer concern — the_grid's **own** A7, promoted to **ADR-0003 D6** (a *different* "A7" from genesis's) — is handled by the ownership partition (ADR-0003 D6 + the A32 gate): the_grid only ever mounts/writes beads it **owns**; gc never reconciles a the_grid-owned bead, and vice-versa. **This coexistence half is *transitional*, not architectural:** the_grid's endgame is to *replace* gc — a standalone the_grid (or any greenfield rig with no foreign reconciler, e.g. the proven genesis live arm) has **no second writer at all**, so the partition guard is simply **inert** (every bead in the_grid's rigs is its own). §6.1's *declarative* argument — invariants 1, 2, 4 and the *one-reconciler-inside-the_grid* half of #3 — does **not** depend on gc existing; only the coexistence guard does, and it retires per-rig as gc is replaced (Decision 5 / §6.3). Two different threats, two different defeaters — not one conflated argument. *(This is exactly the conflation the second review caught: invariant 3 originally pinned genesis-A7's collision onto the gc/the_grid axis — answering the wrong threat.)*
4. **No second source of truth (Failure-mode B blocked structurally).** The tree **never exposes `Branch`/`State` to the engine.** A Branch holds an in-memory, non-authoritative spawn `Completer`/cancel-flag and a *durable kill-fence handle* (the persisted pgid + `GRID_INSTANCE_TOKEN`, Decision 4). **Neither is a source of truth about what work exists or its phase** — that authority is **always** the bead store, re-observed via snapshot-diff. The persisted pgid is read at restart only to fence/kill a still-alive orphan (a side-effect), **never** to decide work state. So there is no path by which Branch state becomes a competing truth — the_grid's brainstorm Failure-mode B, blocked.

Conclusion: A30(1)'s detection invariant is **kept**; what is added is a *consumer* reconciler over the effect lifecycle, downstream of a single detector, inside one ownership partition, with the only tree→reality coupling being the audited A32 write. genesis A7 is respected, not violated.

### 6.2 — A30(2) — "Riverpod 3 stays" → **fully reversed**

> A30(2), verbatim: *"**Riverpod 3 stays** (genesis deliberately kept its tree core Riverpod-agnostic so the_grid's 3.0 never binds it)."*

**Disposition — fully reversed** → `StateNotifier` for reactive values, `genesis_tree` for structure (Decision 3). The genesis observation that "the tree core is Riverpod-agnostic" is *why this is clean*: dropping Riverpod binds nothing in genesis. See also §6.5 (the `CLAUDE.md` convention).

### 6.3 — A30(3) — "convergence / codec / state-machine / bd-substrate / coexistence stay grid-local" → **UNCHANGED by this ADR (revision scheduled, not enacted)**

> A30(3), verbatim: *"the convergence codec / state machine / **bd substrate** / coexistence partition stay **grid-local**."*

**Disposition — explicitly UNCHANGED here.** ADR-0007 does **not** touch convergence. The byte-port `ConvergenceReducer` and the coexistence partition remain grid-local and intact (Decision 5). Convergence-as-a-tree-subtree is **scheduled** for P3 / ADR-0010 and retires the shim **per-rig**; it is not decided by this ADR. (Stated explicitly so the supersession is bounded and A30(3) is not silently swept along.)

### 6.4 — A31 — "genesis adoption is surface-layer-only; reads bead snapshots, does **not** mount beads as a domain tree" → **overtaken before promotion** (A31 is *pending*, never ratified)

> A31, verbatim: *"purely **additive** (a new surface-layer package), **downstream of the M2 engine** (reads bead snapshots, does **not** mount beads as a domain tree)."*

**Disposition — overtaken before promotion.** A31 is a *pending* amendment (register Status "pending" — never promoted by Nico), so this ADR does not reverse a decision *in force*; it withdraws/overtakes the forward-bet A31 recorded before it could be promoted. The pivot mounts the work lifecycle **as a domain tree in the engine**, on its own merits (crash-safe lifecycle symmetry, sibling isolation, one-language-with-the-house-stack); genesis becomes an **engine dependency** (`genesis_tree` as a sibling-checkout path dep), not merely a deferred surface-layer consumer. A31's framing — genesis enters only at the render/inspector edge and never as a domain tree — no longer holds. **What A31 reserved is *not* "absorbed" — it is net-new vs this ADR:** A31's reserved scope was surface-layer-only (the `grid top` TUI inspector, explicitly "does not mount beads as a domain tree"), and A39 routed *two* surfaces into that reserved future ADR — the TUI inspector **and** the leonard-debug perception's literal genesis `StatefulPerception` rebuild (tg-e28). ADR-0007 adopts genesis into the **engine** (net-new) and absorbs only A39's *config-authoring-tree* clause; the two surface-layer items A31/A39 reserved are left untouched. **Their ADR number is a Nico decision — see the numbering note under Decision 5** (A6 reserved ADR-0005 for the M4a *config model*; A31 reserved the same number for *genesis adoption* — a double-booking this ADR cannot unilaterally resolve).

### 6.5 — `CLAUDE.md` convention — "Riverpod 3 `Notifier`/`AsyncNotifier` (never `StateNotifier`)" → **reversed**

> `the_grid/CLAUDE.md`, Conventions, verbatim: *"**Riverpod 3** `Notifier`/`AsyncNotifier` (never `StateNotifier`); streams via `StreamProvider`; derived state via `select`."*

**Disposition — reversed** (Decision 3). On ratification, this `CLAUDE.md` line is replaced with the StateNotifier convention. (The `CLAUDE.md` edit lands **on ratification**, like the A30/A31 stamps — not before.)

### 6.6 — ADR-0001 Decision 3 — "Reactive primitive: Riverpod 3 `Notifier` (**Not** `StateNotifier`)" → **fully reversed** (the ratified source)

This is the **heaviest** artifact the pivot reverses — a *ratified* Decision (ADR-0001 **Accepted 2026-06-11, Nico**), and the true source from which the lighter A30(2) and `CLAUDE.md` echoes derive. The first draft gave it only a forward-stamp while quote-and-superseding its echoes — inverting this ADR's own **A33 precedent** (which named ratified ADR-0001 **D6** prominently when superseding it). Corrected: the ratified source gets the full quote-and-supersede.

> ADR-0001 D3, verbatim: *"Reactive primitive: Riverpod 3 `Notifier`. … State containers are `Notifier`/`AsyncNotifier`. **Not** `StateNotifier`…"* and its Alternatives: *"**`StateNotifier` literal** — rejected in favor of Riverpod 3 `Notifier` (Decision 3)."*

**Disposition — fully reversed** → the_grid adopts `StateNotifier` + freezed (Decision 3). ADR-0001 D3's "Not `StateNotifier`" and its Alternatives "StateNotifier literal — rejected" line become **historical**; **A30(2) and §6.5's `CLAUDE.md` line are its echoes.** **ADR-0002 D2's** projection table — specified as Riverpod providers (`sessionsProvider`, `convergencesProvider`, `convergencesByStateProvider`, `activeWispProvider`, …) — is restated as `StateNotifier` services: the table's *shape* is unchanged, only the reactive primitive flips. (ADR-0002 **D1**'s `grid_reconciler` convergence state machine is **retained intact** per §5/§6.3 — *not* reversed.) The ADR-0001 D3 + ADR-0002 D2 one-line amendments land **on ratification** (not-silently-edited rule, A33 precedent).

### 6.7 — A39 — "No engine change (snapshot-diff + Riverpod + gc-fidelity codec stay; A30 unchanged)" → **split: pull-free contract PRESERVED, the rider REVERSED** (A39 is *pending*)

A39 is itself a *pending* amendment; its "no engine change" rider is **not** incidental — it is the premise that scoped A39 as a surface-only adoption.

> A39 rider, verbatim (on its *Affects* line): *"No engine change (snapshot-diff + Riverpod + gc-fidelity codec stay; A30 unchanged)."*

- **PRESERVED — and depended on:** A39's pull-free contract (synchronous `build`, out-of-band watch) and its **injected-Stream-only guard** are kept and are *load-bearing* in §6.1 invariant 1.
- **REVERSED:** "Riverpod stays" (§6.2/§6.6); and "no engine change / A30 unchanged" — the M2/M3 **dispatch core** is rewritten to `genesis_tree` and A30(1)/(2) are superseded. **Precise:** snapshot-diff *detection* is **kept** (§6.1 inv 1) and the gc-fidelity codec is **unchanged** (§6.3) — it is the reducer/actuator *dispatch core*, not the whole engine, that is rewritten.

---

## Forward-pointer stamps (APPLIED 2026-06-24 on Nico's ratification)

On Nico's ratification (2026-06-24) the following were applied — append-only to each target (never a rewrite of an entry's body; the register is append-only history):

- **A30** Status line gains: *"§(1) partially superseded / §(2) fully superseded / §(3) unchanged by **ADR-0007** (Accepted ⟨date⟩) — see §6.1–6.3."*
- **A31** Status line gains: *"overtaken before promotion by **ADR-0007** (Accepted ⟨date⟩) — A31 was *pending*; this ADR reverses the forward-bet it recorded, mounting the work lifecycle as a domain tree in the engine (§6.4). ADR-0007 adopts genesis into the engine; whether/how to still write an ADR for the optional `grid top` TUI surface + the tg-e28 perception that A31/A39 reserved is left to Nico (see numbering note)."*
- **A39** Status line gains an **append-only** note (A39's body left intact): *"ADR-0007 keeps A39's pull-free contract + injected-Stream-only guard (relied on in §6.1 inv 1); A39's 'Riverpod stays / no engine change / A30 unchanged' rider (on its Affects line) is overtaken for the dispatch core — snapshot-diff detection + the gc codec stay — see §6.6–6.7. ADR-0007 absorbs A39's config-authoring-tree clause; A39's tg-e28 leonard-debug perception home is left to ADR-0005's disposition."*
- **A6** Status line gains: *"the M4a–M4f ADR-number reservations (0005–0010) are re-pointed by the M4 pivot — see ADR-0007's numbering note; update `docs/M4-SCOPING.md`'s table on ratification."*
- **ADR-0001 Decision 3** — fully superseded by **ADR-0007 §6.6**; one-line amendment to the StateNotifier stack on ratification (not-silently-edited rule, A33 precedent). **ADR-0002 D2's** providers → restated as `StateNotifier` services under the same stamp (shape unchanged; D1 retained). **`CLAUDE.md`** convention line → the StateNotifier convention (§6.5).

## Consequences

- **Positive.** One engine, not two (the general reconciler replaces the hand-rolled reducer/actuator); lifecycle symmetry (mount=spawn / unmount=kill) is structural, not procedural; sibling isolation is free (keyed reconcile); the stack re-aligns with predictable-flutter + lenny; `build()` purity + the A32 single-writer + A39 pull-free discipline all survive intact.
- **Cost.** A real `genesis_tree` engine rewrite of the M2/M3 dispatch core; two cheap persists for crash-safety (Decision 4); the M2 byte-port lives on as a coexistence shim through the whole migration (Decision 5); adopt-a-live-process is net-new deferred work.
- **Risks carried (from PDR §9, folded):** (1) this §6.1 argument is load-bearing — if it is wrong, the pivot is wrong; (2) adopt is deferred, not solved; (3) per-rig shim retirement is long-lived; (4) stale-post-restart double-spawn — mitigated by the freshness barrier + idempotent mount, must be verified; (5) spawn-in-flight-vs-unmount — the `Completer`/cancel-flag contract, verified against M3's `stopping` guard; (6) a genesis opt-in `==`-reconcile feature request would simplify config-pruning + dynamic capabilities — *not* a flip of the global identity-skip; filed separately against the genesis backlog.

## Build path (after ratification)

1. ~~This ADR → Accepted (Nico) + the §6 stamps applied.~~ ✅ **Done 2026-06-24.**
2. **`docs/M4-P0-BUILD-ORDER.md`** — the dependency-ordered P0 breakdown (`Grid → Rig → WorkList → WorkBead → EffectSeed` on `genesis_tree`; `StateNotifier<GraphSnapshot>`; real detached processes; respawn-or-skip; opinion-light kernel + `DefaultExtension`; landing as an `EffectSeed` retiring M3's hardcoded `GridGitService.land`).
3. **Build P0** (Workflow waves + adversarial verify, the pattern that built M1–M3).

**Acceptance (P0, from PDR §7):** a bead runs `implement→gate→land` as reconcile transitions; sibling work untouched across a transition; **config `build()` does not run on a work tick** (targeted observation); a controller restart **respawn-or-skips correctly** (no double-work, no orphan); the engine holds **no** landing/VCS/provider opinion; offline-green + `melos analyze` clean across all packages.
