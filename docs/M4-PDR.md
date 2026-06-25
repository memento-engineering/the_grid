# M4 PDR — the running grid *is* a tree

**Status:** PDR draft — **doc-before-code.** The design is decided (Nico, 2026-06-24); the **gating ratification** is ADR-0007 (§8), which explicitly supersedes A30/A31 and the Riverpod convention. Then a P0 build-order doc, then code.
**Date:** 2026-06-24 (the tree-model pivot, hardened by a 5-lens adversarial review).
**Supersedes:** the reducer/actuator draft (2026-06-18) and the first tree draft (2026-06-24a). This is the honest, review-corrected version.
**Backed by:** a working spike (`/tmp/grid_tree_spike`) that ran `implement→gate→land` as keyed-reconcile transitions with sibling work untouched; and a 5-reviewer adversarial pass that caught two real over-claims (crash-safety, the A30 escape) — both corrected below.

---

## 1. The pivot — why

gc's reconcile loop (build desired, observe actual, converge: mount what's missing, kill what's extra) **is** a keyed-reconcile element tree. The prior design ported gc's *hand-rolled* reconciler into a `reduce → PhaseAction → actuator` machine — i.e. reimplemented the element tree by hand, with a `DesiredState` value + reducer + actuator as procedural sediment. genesis ships the *general* reconciler. This PDR makes it the engine: **the running grid is a `genesis_tree`; `build(observed)` is the desired running system; keyed reconcile + `Branch` lifecycle is the work lifecycle.** The reducer/actuator/value-hop dissolve.

## 2. The model

- **One tree, one root** (`Grid`). The mounted tree **is** the desired state, continuously — no separate `DesiredState` value, no separate topology reducer.
- **Config nodes are ANCESTORS of work nodes** (not siblings — siblings can't see config; `InheritedSeed` only walks *up*):
  ```
  Grid
  └─ RigScope<RigConfig>     InheritedSeed — provides config DOWN
     └─ Rig                  StatefulSeed — observes a CONFIG notifier (rebuilds rarely)
        └─ WorkList          StatefulSeed — observes the SNAPSHOT notifier
           ├─ WorkBead<id>   reads RigScope.of(ctx) ↑ for config; builds to its phase effect
           └─ …
  ```
- **Reactive values = `StateNotifier`, NOT Riverpod** (§6). A `StateNotifier<T>` service is provided via `InheritedSeed<T>`; a `StatefulSeed` locates it (`dependOnInheritedSeedOfExactType`) and observes it in `initState` (`addListener`/stream → `markNeedsRebuild`), cancels in `dispose`. A39-clean: build sync, observation out-of-band.
- **Flush isolation is OBSERVATIONAL, not structural.** `markNeedsRebuild` is per-branch — never `root.markNeedsRebuild()`. A **work tick** fires the snapshot `StateNotifier` → only `WorkList` (its observer) marks dirty → `flush()` rebuilds just `WorkList` + keyed-reconciles its `WorkBead`s. The config ancestors are never in the dirty set, so their `build()` never runs. A **config change** fires the config notifier → `Rig` rebuilds → `InheritedSeed` dependency tracking marks exactly the `WorkBead`s that read it. (This dissolves the reviewer's "config built 100× under work-churn" finding — that was the spike's `root.markNeedsRebuild()` shortcut, replaced by targeted observation.)
- **Effect-Seeds ARE capabilities.** `Branch.mount` = start (spawn/run), `unmount` = stop (kill), `update` = re-attach. Effects live in the Branch lifecycle (`initState`/`dispose`), never in `build()` (which stays pure — A39). An extension contributes effect-Seed types.
  - **Dynamic / TOML capabilities** use a generic carrier `EffectSeed` whose reconcile identity carries the capability id — keyed `ValueKey('$beadId.$capId')`, so a phase swap (capId change) changes the key → unmount+mount, with **one** runtimeType. A **registry** resolves `capId → impl`. (Compiled `DefaultExtension` may use real subtypes or the carrier; both work. "Capabilities are Seeds" is literally true only for the compiled set; TOML contributes ids+config to the carrier.)
- **Phases = reconcile transitions.** `WorkBead.build()` switches on the bead's observed phase → that phase's effect Seed. Advance = a rebuild = keyed reconcile swaps the effect Branch. *(Spike-proven: `implement→gate` = `■ STOP agent` + `▶ START gate`; sibling bead untouched.)*
- **The bead is the cursor; writes go through the A32 chokepoint; write-back is OUT-OF-BAND.** A detached agent's completion has no exit code — it arrives later on the provider's event stream (M3's liveness poll), to a Branch that may already have unmounted. So the effect-Branch's `State` subscribes (in `initState`) to its session's completion event; on completion it routes the bead write through an injected `GridBeadWriter` (the A32 chokepoint, resolved via `InheritedSeed`) — *triggered by the out-of-band event, not by `mount`/`build`*. The write does NOT relocate into the Branch; it stays controller-mediated, exactly as M3. No-write-in-build holds because the write is in the completion handler, not build.
- **Observe stays snapshot-diff** (the surviving piece of A30): the bead pipeline (file-watch + `@@tg_working` probe → single-flight re-query → `GraphSnapshot`) is the `StateNotifier<GraphSnapshot>` the tree watches. The tree consumes its emitted value; it never re-detects bead change.

## 3. Crash-safety — respawn-or-skip (P0); adopt deferred

The mounted tree is in-memory; restart loses it, not the work. On restart, rebuild from the observed snapshot; each effect-Branch's `mount`:
- **SKIPS** if the bead's phase shows the work already finished (reconcile straight to the next phase);
- else **RESPAWNS** fresh.

This needs two **cheap** persists (the honest cost — it is *not* zero-persistence):
1. **Durable completion** — the agent advances its phase through the chokepoint *as its last act*, so restart can tell "done" from "died mid-work" (else a finished one-shot gets a second agent — the A38 double-work bug, across restart).
2. **pgid + instance-token at spawn** — so respawn can **kill a still-alive orphan group** before starting fresh (otherwise two agents fight over one worktree). *Honest fence:* the kill is `kill(-pgid)`, which doesn't read the token — telling a *recycled* pgid from a real orphan needs the environ-scan the deferred ADOPT track owns, so P0 fences the kill by the pgid safety-guard + the freshness barrier + the per-bead worktree; `GRID_INSTANCE_TOKEN`'s P0 job is fencing stale async write-back delivery, not the kill.

Plus a **freshness barrier**: gate the first post-restart reconcile on one observed `@@tg_working` advance / a re-query before mounting any spawning effect, so a stale snapshot can't double-spawn. And the **async-spawn-vs-unmount race** is handled by a Completer/cancel-flag in the effect-Branch `State` (M3's `_Session.stopping` pattern): `initState` fires the spawn Future; a `dispose` during an in-flight spawn flips cancelled + chains kill-on-resolve.

**DEFERRED — a separate later track: ADOPT** (re-attach to and *supervise* a live detached process across restart with no exit code — needs persisted pid + a reconstructed liveness poll + the fence). The PDR no longer bills this as "graduate the spike." `tg-9fl` is a worktree rebind/reap sweep — it is *not* process adoption; respawn-or-skip uses it to find the worktree, then starts fresh.

## 4. What survives / what moves (review-honest)

- **build() purity + no-write: survive** (verified — effects in `initState`/`dispose`, never build).
- **Sibling isolation, lifecycle symmetry: real** (keyed reconcile).
- **DI splits, it does not "dissolve":** `InheritedSeed` scopes *which capId / which read-handle* is in scope for a subtree; a **registry** still resolves `capId → impl`. Two mechanisms. The win is real but narrower than claimed.
- **Opinion-light kernel + extensions + `TomlPackExtension` + gc-TOML import + two-front-doors + no-write invariant: all survive**, reframed onto Seeds.

## 5. M2 convergence — demoted, retired per-rig

- **(i) New work runs as a tree** — `iterate-until-gate` is a `ConvergenceSeed` subtree that rebuilds through iterations (Check/Retry = a phase looping on its gate result). The gate phase-split stays (the tree is synchronous: a `GateSeed` spawns in `initState`, re-enters via the next snapshot — the same `gateEvaluated` plumbing); ordered-write fidelity is emitted via the A32 chokepoint.
- **(ii) The byte-port `ConvergenceReducer` is retained as a sealed coexistence shim** (the shadow/diff harness consumes the *reducer*, not a serialized plan — it survives the pivot intact). It retires **per-rig**, as each gc-owned rig converts — never globally until the last rig (gc assumes one writer per bead). The shim persists through the whole migration.

## 6. The stack reversal — Riverpod OUT → StateNotifier

the_grid drops Riverpod entirely for plain `StateNotifier` (the standalone `state_notifier` package) + freezed — which **un-diverges it from its own house style** (predictable-flutter and lenny are StateNotifier+freezed; the_grid's CLAUDE.md literally said "Riverpod 3, never StateNotifier"). `StateNotifier`s are provided via `InheritedSeed`, located + observed by `StatefulSeed`s. A future `genesis_state_notifier` (a genesis-native notifier) is plausible, not required. The migration rides the M4 pivot.

## 7. Phases

- **P0 — the tree engine, for real.** `Grid → Rig → WorkList → WorkBead → EffectSeed` on `genesis_tree`; `StateNotifier<GraphSnapshot>` observed by `WorkList`; **real detached processes**; **respawn-or-skip** crash-safety (durable completion + pgid/token + freshness barrier + the spawn/unmount Completer); opinion-light kernel + `DefaultExtension`; **landing as an EffectSeed** (retires M3's hardcoded `GridGitService.land`). *Acceptance:* a bead runs `implement→gate→land` as reconcile transitions; sibling work untouched across a transition; **config build() does not run on a work tick** (targeted observation); a controller restart **respawn-or-skips correctly** (no double-work, no orphan); the engine holds no landing/VCS/provider opinion; offline-green + `melos analyze` clean.
- **P1 — gc-TOML import** → a config Seed subtree + the `PackInflater` (override/patch tri-state). Capture-users-without-rewrite.
- **P2 — the unified topology tree.** Config nodes (`Rig`/pool/`Order`) as ancestors of work; elastic rigs via `Watch` on an injected backlog notifier; ownership stamped by `RigScope` `InheritedSeed`.
- **P3 — convergence-as-subtree**; retire the coexistence shim per-rig; dev hot-reload (authoring only; prod = AOT binary, structural change = versioned deploy).

## 8. ADR-0007 — the explicit supersession (the gating ratification)

A30 has **three** clauses; A31 and a CLAUDE.md convention are also touched. ADR-0007 must quote-and-supersede, never silently edit, with forward-pointers stamped on A30/A31:

- **A30(1) — "snapshot-diff only; keyed reconcile NOT adopted for bead change-detection":** *partially reversed, honestly.* Change-**detection** over the bead graph **stays snapshot-diff** (it emits the `GraphSnapshot` value the tree builds from). The work **lifecycle** tree **does** adopt keyed-reconcile keyed by bead id — downstream of detection, to map known bead-presence onto effect mount/unmount. This is **not** genesis-A7's "two keyed reconcilers over one structure" collision: the loop is **one-directional** (snapshot-diff → value → tree → chokepoint writes → bead store → snapshot-diff), and the tree never exposes Branch state to the engine (the brainstorm's **Failure-mode B** guard is preserved — coupling is the chokepoint write only). ADR-0007 must make this argument, not assume it.
- **A30(2) — "Riverpod is the engine":** *fully reversed* → StateNotifier for values, genesis_tree for structure (§6).
- **A30(3) — "convergence stays grid-local":** *scheduled for revision* (P3 / ADR-0010): convergence becomes a tree subtree; the shim retires per-rig.
- **A31 — "genesis does NOT mount beads as a domain tree":** *superseded* — the pivot mounts the work lifecycle as a domain tree, justified on its merits (crash-safe lifecycle, sibling isolation, one-language-with-our-own-stack). A31's render-inspector use becomes one tree-consumer among several.
- **CLAUDE.md "Riverpod 3 / never StateNotifier":** *reversed* (§6).

## 9. Open risks (review findings, folded)

1. **ADR-0007's two-reconcilers argument** (§8) must be written, not assumed — it is load-bearing.
2. **Adopt-a-live-process is deferred net-new work** — P0 ships respawn-or-skip only.
3. **Per-rig shim retirement** — the byte-port lives through the whole migration.
4. **Stale-post-restart double-spawn** — mitigated by the freshness barrier + idempotent mount; verify.
5. **Spawn-in-flight vs unmount** — the Completer/cancel-flag contract (§3); verify against M3's `stopping` guard.
6. **genesis opt-in `==`-reconcile** — file a feature request (check genesis backlog first): an opt-in value-equality reconcile would let a freezed `EffectSeed(capId, config)` handle both prune and swap with no key gymnastics, and unifies the config-pruning + dynamic-capability threads. *Not* a flip of the global identity-skip (Flutter/genesis chose it deliberately). Until then: targeted observation (config pruning) + capId-in-key (dynamic capabilities) cover it with no genesis change.

## 10. ADR map

**ADR-0007** = the tree engine + the A30/A31/Riverpod supersession (P0, gating). **ADR-0008** = gc-TOML import / `PackInflater` (P1). **ADR-0009** = the unified topology tree (P2). **ADR-0010** = convergence-as-subtree + retire the shim (P3). Provisional until ratified.

---

**Process note:** the gating step is **ADR-0007** (promote §8 into a ratified ADR, stamp A30/A31 superseded), then a **P0 build-order doc**, then code. The spike proved the *feel*; P0 proves respawn-or-skip crash-safety at real-process scale. Per the gate.
