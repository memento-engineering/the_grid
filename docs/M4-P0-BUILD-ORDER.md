# M4 P0 Build-Order — the `genesis_tree` engine

**Status:** Build-order **v2 — hardened** (doc-before-code). Gated on **ADR-0007 (Accepted 2026-06-24)** — satisfied. The WorkPhase axis (§0.5 / A40) was corrected after a 5-lens adversarial pass (30 findings, all confirmed) caught that the v1 "`grid.phase` on the work bead" shape was incompatible with the proven A37 split-store topology; **Nico ratified the corrected shape 2026-06-24** (cursor on the_grid's own session bead, `phaseOf` by join). Then code.
**Date:** 2026-06-24
**Grounded by:** a 7-track source-recon sweep + a 5-lens hardening pass — every reuse / net-new claim is file-cited. ~70% of P0 is *rewiring proven M1/M3 parts*.
**Builds on:** ADR-0007 (the engine + the supersession), PDR §7 (P0 acceptance), the M1 kernel (`grid_controller`), the M3 runtime (`grid_runtime`), the **A36/A37 split-store** topology (the proven live arm).

---

## 0. Decided inputs (Nico, 2026-06-24)

1. **Engine package = a new `grid_engine`** (not a `grid_runtime` layer). Amends **ADR-0002** topology. Acyclic: `grid_engine → {grid_controller, grid_runtime}`. The engine's **minimal import surface is itself the enforcement** of derailment-invariant 1. *(The CLI/composition changes — `composeRun`, `buildAgentConfig` — land in `grid_cli`, the top wiring package, not in `grid_engine`.)*
2. **Durable completion = belt-and-suspenders** — the agent advances its terminal phase **and** the controller writes a done-marker on observed clean completion. **Both write the SAME `grid.phase` key+value on the SAME session bead through the SAME A32 chokepoint** (an idempotent metadata merge — re-applying either is a confirming no-op; no precedence question, no second writer). The agent's advance is **chokepoint-mediated** (a controller-provided `grid phase --advance` shim against the state store under the actor allowlist) — **never** a free-form `bd` call inside the worktree (that would be the real single-writer violation).
3. **Riverpod = bridge-only in P0; the full purge is in the M4 DoD** (§5).
4. **Extension scope = minimal** — landing-as-an-EffectSeed + a compiled `DefaultExtension`. TOML `PackInflater` / full `GridExtension` = **P1 / ADR-0008**.
5. **WorkPhase axis — corrected & ratified (A40, Nico 2026-06-24).** The phase cursor lives on **the_grid's OWN session/lifecycle bead in the state store** (`tgdog`) — which the A32 chokepoint already owns and which already carries `metadata.work_bead == <workBeadId>`. The work source stays **pristine / read-only** (A37). Phase values: **`implement | verify | land`** (`verify`, *not* `gate` — avoids colliding with the M2 convergence gate-eval, which is a different axis on `type=convergence` beads). **`phaseOf` is derived by a JOIN**, not read off the work bead:
   - `phaseOf(workBead)` = read the linked session bead (`work_bead == workBead.id`) from the state-store snapshot → project its `grid.phase` cursor;
   - **no session cursor + the bead is freshly entering the ready-set ⇒ `implement`** (spawn a fresh agent);
   - **a positive terminal signal ⇒ done** (the WorkBead unmounts): the work bead's `status == closed`, **or** the session cursor reached terminal. **Never** ready-set exit (the_grid never marks a bead in-progress, so a bead leaves `readyIds` for non-done reasons — blocked, gc-edited — *while its agent is mid-flight*; treating that as done would kill a live agent).

---

## 1. What P0 is, and the acceptance gate

P0 is **the tree engine, for real** (PDR §7): `Grid → RigScope → Rig → WorkList → WorkBead → EffectSeed` on `genesis_tree`; the tree observes an injected immutable value joined from the read-workspace snapshot + the state-store session snapshot; **real detached processes**; **respawn-or-skip**; an opinion-light kernel + a compiled `DefaultExtension`; **landing as an EffectSeed**.

**Acceptance (the gate, all offline):**
- a bead runs `implement → verify → land` as **reconcile transitions** (driven by the session cursor);
- **sibling work untouched** across a transition;
- **config `build()` does NOT run on a work tick** (targeted observation);
- a **`ready → blocked` transition of a bead with a live agent does NOT unmount/kill it** (positive-terminal-only unmount);
- a controller **restart respawn-or-skips correctly** (no double-work, no orphan) — *including for a foreign read-only work bead*, because the cursor is read from the_grid's own store;
- the engine holds **no** landing / VCS / provider opinion;
- **no write of any kind reaches the read/work workspace** (A37 pristine-source conformance);
- offline-green + `melos analyze` clean across all packages.

---

## 2. Wave 0 — package + dependency setup

- New `packages/grid_engine/` + root workspace member.
- **`genesis_tree`** as a **pinned pub version dep** (`^0.1.3`) **+** a sibling-checkout `dependency_overrides` path dep during dev (A34 / `genesis_tmux` precedent; genesis ADR-0001 D8). Pin it — the composition layer is **EXPERIMENTAL** and the_grid is its triggering 2nd consumer (freezes the API).
- **`state_notifier`** (the standalone package — predictable-flutter's architecture; lenny uses it). *Not over-claimed as a "house primitive"; it's the chosen reactive value type for the §6.6 reversal.*
- `grid_engine` deps: `grid_controller` (`GraphSnapshot`/`Bead`/`IssueType`) and `grid_runtime` (`SubprocessProvider`, `RuntimeActuator`, `GridBeadWriter`, `GridGitService`, `BeadOwnershipPredicate`, `process_group`, `IncarnationEnv`). **Verified acyclic.** *(Note: `grid_engine` does NOT depend on `grid_reconciler` — the M2 gate machinery is P3-fenced; the P0 `verify` phase runs its own check process via `SubprocessProvider`, Track E/F.)*
- Touched in `grid_cli` (already the top wiring package): `composeRun` → `compose([DefaultExtension(), …])`; `buildAgentConfig` → the agent's chokepoint-mediated phase-advance instruction.

---

## 3. Tracks (dependency-ordered waves)

> Each track: **build** · **reuse** (file-cited) · **net-new** · **acceptance** (offline).

### Wave 1 — Track A: the Seeds (pure; the heart)

**Build:** `Grid`(MultiChildSeed) → `RigScope` = `InheritedSeed<RigConfig>(value:…, child: Rig(…))` (read via `context.dependOnInheritedSeedOfExactType<RigConfig>()`, optionally a `RigConfig.of(ctx)` helper — there is no `GlobalKey`/`.of` magic, `InheritedSeed<T>` is a concrete generic) → `Rig`(StatefulSeed obs a config notifier) → `WorkList`(StatefulSeed obs the injected joined snapshot notifier) → `WorkBead`(StatelessSeed; `build()` switches `phaseOf(workBead, sessionCursor)` → that phase's effect Seed).

**WorkList child-set (the corrected predicate):** mount a `WorkBead` for a bead that is
`(owned ∧ plain-work-type ∧ in readyIds)` **∪** `(owned ∧ has a live non-terminal session ∧ still present in beadsById)`.
- **Type gate BEFORE ownership — a fail-closed ALLOW-list (A41, hardened):** mount a `WorkBead` only for `IssueType.isCore` work types. *(Built as a deny-list first; the Track A hardening pass empirically proved that unsafe — `bd ready` leaks the_grid's orchestration customs `convoy`/`event`/`step`/`spec`/`convergence` (its `ready_work` narrows only `{merge-request,gate,molecule,message,agent,role,rig}`), so a deny-list listing only `{convergence,session,infra}` would spawn an agent on an owned, ready `convoy`/`spec`. An allow-list excludes every non-core type by construction — `type=convergence` (the M2 `ReconcilerRuntime`'s `convergence.state` axis — a true two-writer collision), `session` (the_grid's own lifecycle), all gc orchestration nouns, all infra — and fail-closes an unknown custom type.)* This also closes the latent gap in shipped M3 `dispatch_interactor.dart`. The live-arm blessed-bead drive-list (`--bead`) stays a **separate** gate (ADR-0006), not a P0 concern.
- The `∪ live-non-terminal-session` clause is what lets a bead that **transiently left `readyIds`** (blocked, edited) keep its agent mounted — unmount is driven by a **positive terminal signal only**.

**Reuse:** `genesis_tree` primitives (verified — `MultiChildSeed` docstring literally shows `class Grid extends MultiChildSeed`); `GraphSnapshot` (immutable); `BeadOwnershipPredicate` (the ownership axis); per-branch `markNeedsRebuild` (`branch.dart:74`, the observational-isolation primitive).

**Net-new:** the Seed classes; **`RigConfig`** (freezed; distinct from `RuntimeConfig`); **`WorkPhase` + the join-based `phaseOf`** (A40 — takes the work `Bead` **plus** its session-bead cursor projection, not work-bead metadata). The fake harness (a `FakeJoinedSnapshotNotifier` + a `FakeEffect` recording start/stop — genesis ships the pattern at `tree/test/stateful_test.dart`).

**Acceptance (no I/O):** mount over a fake joined-snapshot notifier with two ready beads (no session cursor) → two `WorkBead`s each START a `FakeEffect`. Advance bead-1's **session cursor** `implement → verify` →
- `owner.flush()` returns **exactly `[WorkList]`** (the lone observing node). **`WorkBead<1>` is force-rebuilt by `WorkList`'s reconcile cascade and is correctly EXCLUDED from the drained list** (genesis_tree contract: a child force-rebuilt by a parent cascade clears its dirty flag before the drain — `tree_owner.dart` flush() doc + `flush_returns_rebuilt_test.dart`; **asserting a WorkBead *in* the flush list would require it to observe the notifier itself = a derailment-invariant-1 violation**).
- The phase swap is proven **separately**: `FakeEffect` records `[STOP agent(1), START verify(1)]`, and `WorkBead<1>`'s **Branch identity persists** (same branchId) while its effect-child swaps `agent → verify`.
- Assert **config ancestors (Grid/RigScope/Rig) and sibling `WorkBead<2>` are ABSENT** from the flush list (they were never dirtied — ancestors observe a *config* notifier, not the snapshot notifier). This is derailment-invariant 1's guardrail — **written FIRST** (`root.markNeedsRebuild()` is banned; a single over-broad observation re-creates the "config built 100×" bug).
- **The positive-terminal test:** a `ready → blocked` (`is_blocked=1`) transition of bead-1 *with a live agent* → **no unmount, no `terminateGroup`** (the EffectSeed stays mounted). Only a positive terminal (`status closed` **or** session cursor terminal) unmounts + STOPs.

### Wave 2 — Track B: the join bridge · Track C: EffectSeed + real processes  *(depend on A)*

**Track B — build:** the bridge joins **two** observed inputs into the single immutable value the tree builds from, **outside the tree**: (1) `GridControllerRuntime.snapshots` (the read-workspace `GraphSnapshot`) and (2) the **state-store session snapshot** (a second `GridControllerRuntime`/reader over the `--state-workspace`, keyed by `work_bead`). The bridge emits a `StateNotifier<JoinedSnapshot>` (`{graph, sessionCursorsByWorkBead}`) that `WorkList` observes. **This is the only subscription into the pipelines** (A39's injected-Stream guard); the tree consumes the joined value, never re-detects.
- **Reuse:** `GridControllerRuntime.snapshots` (already a plain `Stream<GraphSnapshot>`), `GraphSyncInteractor`, the dirty sources — all untouched; a second runtime over the state store is the same machinery.
- **Net-new:** the join layer + `state_notifier`. **Seed-null handling:** `runtime.current` may be `null` immediately after a fresh start (the broadcast stream doesn't replay) — seed the notifier with an empty `JoinedSnapshot` and let the first baseline refresh fill it (replicate the existing `graphSnapshotProvider` seed-then-follow).
- **Acceptance:** a late subscriber reads the baseline; one bead/cursor change → exactly one notifier update; a no-op refresh → no update; the join correctly pairs a work bead with its `work_bead`-linked session cursor.

**Track C — build:** `EffectSeed` — a carrier StatefulSeed keyed `ValueKey('$beadId.$capId')`. `State`: `initState` = `provider.start(name, config)` (spawn) guarded by a `Completer`/`_cancelled` flag (M3 `_Session.stopping`); subscribe `provider.events.where(e => e.name == sessionName)` for the **out-of-band** completion; `dispose` = `provider.stop`; **on completion** → guard `context.mounted` + **session-name-keyed token freshness** → route the cursor write through the `InheritedSeed`-resolved `GridBeadWriter` **(to the session bead in the state store)**. `build()` = pure idle leaf.
- **Reuse (verbatim):** `SubprocessProvider`, `process_group` (`terminateGroup` + the pgid safety guard), `GridBeadWriter` (chokepoint → state store), `TreeContext.mounted` (the async-gap probe), `genesis_tree`'s `Watch` (the inject-and-observe shape).
- **Net-new / corrected:** completion events carry **only `name`**, not a token — so the freshness fence keys on the **session name**, and the **engine mints + injects `GRID_INSTANCE_TOKEN`** via `config.env` (last-wins over the provider's internal mint) and **persists it at `SessionStarted`** (it is *not* on the event today; only `pgid`/`pid` are). Inject `RuntimeProvider.events` via `InheritedSeed` (A39 invariant 1).
- **Key risk:** the out-of-band completion arriving at an **already-unmounted Branch**. Mitigation: (1) guard `context.mounted`; (2) capture writer + sessionName + token into the `State`'s fields at `initState`; (3) the session-name + token fence drops a stale prior-incarnation completion.
- **Acceptance:** mount = spawn; phase swap = old `dispose`(kill) + new spawn, **sibling Branch never rebuilt**; a completion to an unmounted Branch → no `StateError`, write lands-if-fresh / dropped-if-stale, **never a raw bd write**, **never to the read workspace**.

### Wave 3 — Track D: respawn-or-skip · Track E/F: opinion-light kernel + landing-as-EffectSeed  *(depend on C)*

**Track D — build (all writes on the OWNED session bead, one store):**
- **Persist #2:** stamp `pgid` (already on `SessionStarted`) **+ `GRID_INSTANCE_TOKEN`** (engine-minted/injected per Track C — *not* on the event today) **+ `pid`** onto the **session bead** at `SessionStarted` via the chokepoint (`_onStarted` currently discards the pgid). Same store as the cursor → restart reads **one** bead.
- **Persist #1 (belt-and-suspenders, §0.2):** the agent advances the **session cursor** as its last act (a chokepoint-mediated `grid phase --advance`, *not* a worktree `bd` call) **and** the controller writes the same cursor value on observed clean completion. Same key+value, idempotent merge.
- **Restart-reconcile** (first production caller of `listBeadWorktrees` — exists, tested, no caller): await the **freshness barrier** (a *completed* re-query via `GraphSyncInteractor.refreshNow()` — ADR-0007 D4 allows "a completed re-query") → per bead: read the **owned session cursor** → **SKIP** if terminal (reconcile to done, reap worktree) **else** read the persisted pgid → `terminateGroup` (kill a still-alive orphan) → **RESPAWN** in the existing worktree. *Because the cursor is on the_grid's own bead, SKIP fires even for a foreign read-only work bead* (the v1 bug: an unwritable foreign bead could never show done → always respawned).
- **Honest recycled-pgid acceptance (do NOT "fix"):** `signalGroup(pgid)` = `kill(-pgid)` can't read the token (`process_group.dart:135-138`); the environ-scan is the **deferred ADOPT** track. P0 fences with the pgid-safety-guard + freshness barrier + per-bead worktree, and **documents the rare recycled-pgid acceptance**.
- **Honest residual (stated, not hidden):** if the controller dies *after* the agent exits but *before either* durable marker is written, restart respawns — a **re-run in the same worktree** (bounded, idempotent-ish: the agent's commit is durable), not a correctness violation. The agent-as-last-act is primary; the controller marker is the belt.
- **Acceptance (simulated restart, fakes only, FOREIGN-rig arm):** the work source is read-only/unowned, sessions in a separate owned store. Bead A `{owned session cursor = terminal}` → **SKIPPED** (0 spawns, worktree reaped) *even though the foreign bead was never stamped*; bead B `{alive orphan pgid}` → `terminateGroup(pgid)` **before** respawn; bead C `{pgid<=1}` → `refusedUnsafe`, still respawns; spawns mount **only after** `refreshNow` completes; a stale-token completion → dropped.

**Track E/F — build:** the **opinion-light kernel** + a compiled **`DefaultExtension`** contributing `AgentEffectSeed` (wraps `provider.start/stop`), **`VerifyEffectSeed`** (runs a **check command** — the spike's `verify: melos test` — as a process effect via the **same `SubprocessProvider` transport** as the agent; **net-new body, no `grid_reconciler` dep** — this is *not* the M2 convergence gate), `LandEffectSeed` (the **retired** `GridGitService.land` orchestration: `commitAll → pushSetUpstream → PrOpener.open → record pr_url on the SESSION bead via the chokepoint`).
- **The cut line:** `land()` **orchestration** → `LandEffectSeed`; the git **infrastructure** (`provisionWorktree`/`reap`/3-gate/`GIT_*` blacklist/`GitOps`/`PrOpener`) **STAYS**. Capability = **EffectSeed** (the brainstorm's pure-planner is superseded).
- `composeRun` (in **`grid_cli`**) → `compose([DefaultExtension(), …])`.
- **Acceptance:** `land` mounts a `LandEffectSeed` calling injected fake `GitOps`/`PrOpener`, records `pr_url` on the session bead via the fake chokepoint. **Structural test:** no file under `grid_engine/lib/src/kernel/` references `GhPrOpener`/`SubprocessProvider`/`'claude'`/`GridGitService.land` — only `DefaultExtension` does. A second binding (fake `GitlabMrLander`) via `InheritedSeed`-scoped capId override resolves through the registry.

### Wave 4 — Track G: acceptance suite + the derailment-invariants as tests  *(depends on all)*

- **Invariant 1 — no tree node subscribes into a pipeline:** a **behavioral** test (not a naïve import-grep — `grid_controller` has a single public barrel that re-exports its reactivity internals): mount the tree over a fake notifier, assert **zero pipeline subscriptions are attributable to tree nodes** (the only subscription is the bridge, outside the tree) **and** the engine only ever *receives* the immutable `JoinedSnapshot` value; plus the runtime test — a work tick → `flush()` returns exactly `[WorkList]`, config ancestors absent.
- **Invariant 2 — only the chokepoint writes:** inject a recording `GridBeadWriter` over a `BdRunner` that **throws** on any direct call; drive a full cycle; assert every write is the writer, zero bypass, zero writes inside `build()`.
- **Invariant 3 (new) — convergence beads never mount:** a ready set containing an *owned* `type=convergence` root mounts **zero** WorkBeads for it (a plain owned bead in the same set still mounts). Defends ADR-0007 §6.1 inv 3 / §6.3.
- **A37 conformance (new) — pristine source:** inject a recording `BdRunner` over the **read/work workspace** that **throws on any write**; drive `implement → verify → land → done` + a restart; assert **zero writes** reach the read/work workspace (every write is the state-store chokepoint). Catches the v1 masking (ownership passing on a genesis-prefixed write while the store is wrong).
- The full **PDR §7 acceptance suite**.

---

## 4. Crash-safety — the honest version (respawn-or-skip; adopt deferred)

On restart the in-memory tree is gone, **not the work**. Rebuild from the joined snapshot; each `EffectSeed.mount` **SKIPS** if the **owned session cursor** is terminal, else **RESPAWNS** (killing a fenced orphan first). Two cheap persists (cursor + pgid/token, **both on the owned session bead**), a freshness barrier, and a `Completer`/cancel-flag handle the races. **The recycled-pgid risk and the both-markers-miss residual are accepted, not solved**, in P0 (§3 Track D). **Adopt-a-live-process** is **net-new deferred work**.

---

## 5. Definition of Done

- All track acceptance tests **green, offline**; `melos analyze` clean across all packages — the M3 bar.
- The **four invariants** enforced as tests (Wave 4: no-pipeline-subscription, only-the-chokepoint-writes, convergence-never-mounts, A37-pristine-source).
- **In-DoD, beyond the P0 engine gate (Nico's Riverpod call):** the **full Riverpod purge** of `grid_controller`'s 9 internal `AsyncValue` files. P0 bridges only; the purge is **in-scope for the entire M4 work, tracked here, not dropped**.
- **ADR-0002 amended** (a new `grid_engine` row); **A40 ratified** (the corrected WorkPhase axis).

---

## 6. Deferred — explicit, not dropped

- **Adopt-a-live-process** (§4) — a later crash-safety track.
- **TOML `PackInflater` / full `GridExtension`** — **P1 / ADR-0008**.
- **genesis opt-in `==`-reconcile** feature request (file vs the genesis backlog; PDR §9.6).
- **Full Riverpod purge** — in the M4 DoD (§5).
- **The M2 convergence gate / `gateEvaluated` machinery** stays **grid-local and P3** (ADR-0010); P0's `verify` phase is a plain check process, a different axis.

---

## 7. Build approach

**Workflow waves 1 → 4**, each: **implement → adversarial-verify → fix**. **Wave 1 (Track A) runs first and alone** — it proves the model with **zero I/O** and writes derailment-invariant 1's guardrail *before anything spawns*. Waves 2–3 fan out (B∥C, then D∥E/F). Wave 4 is the conformance gate.

> **Terminology:** "done" is **not** a bd status — the terminal *status* is `closed`; "done" here means a *positive terminal phase* (the work bead `closed`, or the owned session cursor reached terminal). Leaving `readyIds` is **never** "done."
