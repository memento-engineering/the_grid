# M4-P1 Build-Order — the reentrant engine (ADR-0008 D4)

> **★ DRAFT — doc-before-code, ratification-pending.** This is the ADR-0008 follow-on the closing OPEN ITEM demands ("a next-build doc for the reentrant engine … must precede code — dependency-ordered tracks, per-track test-first acceptance, the four invariants re-proven AT DEPTH as mutation-tested gates, and the SAFETY rails"). It does **not** reopen ADR-0007's reconcile semantics or ADR-0008 D1–D8 — it sequences their *single-station* cluster into buildable tracks. **No code until Nico ratifies the DECISIONS NEEDED below and closes the OPEN QUESTIONS.**

**Status:** Build-order **v1 — hardened** (a 4-lens adversarial pass folded in; 3 of 4 lenses returned `holds=false / major` against the naïve recommended design — those breaks are now first-class tracks + decisions, not footnotes).

> **★ BUILT (2026-06-27) — all 10 tracks offline-green on branch `m4-p1-reentrant-engine`.** The reentrant engine is real: `Station → Substation → WorkList → WorkBead → SessionScope → FormulaScope → _FormulaChildren → CapabilityHost → Capability`, the `code` formula reproduces P0 byte-for-byte, and the **Burn passes end-to-end offline (success + failure paths)**. grid_engine **164 offline tests** (+ workspace 200/587/134/13/21/15), `melos analyze` clean. Each wave: implement → **read-only-Explore adversarial review (refute-verified)** → fold → commit. Commits: Track A `b5a82fd` · Track B `304ca6d` · D-1 `5e6c99e` · Wave 2 (C+D) `f2f557c` · Track F `49ac7cf` · Track E `1a0f4fe` · Track G `656aae8` · Track H `7c94e39` · Wave 5 (I+J) `d1aa69e`. **The first LIVE arm remains the human gate** (no live `grid run --tree`, no real `claude`/`git`/`tg`, nothing pushed).

> **★ FINISH-LINE CLEANUP LANDED (2026-06-28) — the reentrant engine is now the LIVE path; the P0 `WorkPhase` path is gone.** Executed the deferred-execution cleanup (offline, no new design): (a) `composeRunTree` swapped `DefaultEffectResolver` → `FormulaResolver(code)` + `buildCodeRegistry()` + a git `ServiceBundle`; `StationKernel.mountRoot` now provides the ambient `CapabilityRegistry` + `ServiceBundle` (stable, D-6). (b) DELETED the dead P0 path — `work_phase.dart` (`WorkPhase`/`phaseOf`), `effect_seed.dart` (`EffectSeed`), `default_extension.dart` (`Agent/Verify/LandEffectSeed` + `DefaultEffectResolver`); dropped the `grid.phase` codec (`parseWorkPhase`/`phaseCursorMetadata`/`SessionProjection.phase`) — **KEPT** the scalar `pgid/pid/token` restart fence. (c) `grid phase --advance` → `grid step --advance` (the working-agreement prompt line). (d) Migrated the P0 acceptance suite (the 4 derailment-invariant tests + PDR §7) + `station_kernel`/`join_bridge`/`session_bead`/`track_a` off `WorkPhase` onto the per-node cursor + `<sessionId>/<nodePath>` step-event names; deleted the 3 legacy test files. grid_engine **141** offline tests (164 − the 3 deleted P0 files), full workspace **200/587/134/21/13/15** green, `melos analyze` clean. **Two read-only-`Explore` adversarial reviews** (vacuousness + stray-marker/weakening) returned clean — every derailment invariant still enforced non-vacuously with live sanity controls. STILL DEFERRED: `restForOne` transitive re-keying; restoration/adopt-a-live-process; `FanOutStep`; the `the_grid` SDK package split (ADR-0008 D1). The first LIVE arm remains the human gate.

**Date:** 2026-06-27
**Gated on:** ADR-0008 D2/D3/D4/D5 (Accepted 2026-06-27) + the DECISIONS below. **Reverses nothing in ADR-0007** — it extends the P0 tree engine *below* `WorkBead` with zero change to `WorkBead` / `WorkList` / `StationKernel` / `StationJoinBridge`.
**Grounded by:** a source-recon sweep of `grid_engine/lib/src/**` (every reuse/net-new claim is file-cited) + the butane "Burn" offline ground-truth. ~60% of P1 is *generalizing proven P0 parts* (`EffectSeed` → `CapabilityHost`, `WorkPhase` cursor → per-step cursor, `RestartReconciler` per-worktree → per-node).
**Builds on:** the P0 tree engine (`grid_engine`, branch `m4-p0-tree-engine`, 76 offline tests green), the A37 split-store, the A41 `isCore` mount allow-list, the M3 runtime (`SubprocessProvider` / `process_group` / `StationBeadWriter`).

---

## DECISIONS (resolved by Nico, 2026-06-27) — build-order requirements

> **Status:** D-1…D-7 are **decided** and recorded here as **build-order requirements** — this is where decisions made *with* Nico live. (NOT ADR-0000: that is the autonomous/unwatched-subagent register, never written in a live session.) **Promoted to official ADR amendments on Nico's direction (2026-06-27):** D-1/D-3/D-4 → **ADR-0007** (Amended §); D-2/D-5/D-6/D-7 + OQ-6/OQ-7 → **ADR-0008** (D4/D7/D8 + open questions). This build-order remains the detailed source. OPEN QUESTIONS 1–7 resolved below; 8–9 stay deferred.

> Each changes a ratified shape, a shipped file's contract, or the build sequence — none is a chore. Listed worst-first.

**D-1 — the chokepoint must SERIALIZE, not only AUTHORIZE (BLOCKING; codec/invariant-2 lens, major). DECIDED (Nico, 2026-06-27).**
P0's invariant 2 was specified as *single-writer-auth*. `StationBeadWriter.update` (`station_bead_writer.dart:117-123`) delegates to `bd update --metadata`, whose merge is a **client-side read-modify-write inside the bd subprocess** with no row lock across the read and the write. P0 never raced it because the agent/verify/land frontier is *always exactly 1-wide* — one `CapabilityHost` mounted per work bead. The Burn makes concurrency **structural** (two harness sub-formulas live, parallel build/install/launch hosts, two daemons writing `ready`). Two concurrent `update`s on the **same** session bead with **disjoint flat keys** still last-writer-wins → a `grid.cursor.{path}.state` key is **lost** → `depsSatisfied()` never sees it → the barrier never opens → **silent liveness stall** at depth, in the exact case the reentrant engine exists for. Flat-per-key merge-safety is necessary but **not sufficient**. **Proposed:** add an in-process **per-target-id serialization queue** inside `StationBeadWriter` (a `Map<String,Future> _tail` chain — each `create`/`update`/`close` on an id awaits the prior op on that id). Because invariant 2 already makes the_grid the *sole process* writing `tgdog`, an in-process lock fully closes it — no SQL/cross-process locking. Re-scope the documented invariant-2 claim to "ownership/auth **AND** write-ordering." *(Touches a shipped grid_runtime file — wants ratification.)*

**D-2 — session establishment is an engine-private `SessionScope` (adopt-or-mint) above the formula fan-out (BLOCKING; lifecycle + crash lenses, major×2). NICO'S DESIGN (2026-06-27) — the async `SessionScope` (Page:Route) pattern is his.**
P0 mints the session bead lazily at *first-leaf-mount* and names the provider session **= the session-bead id**, one per work bead (`effect_seed.dart:122,130-132`). Two breaks at fan-out: (a) **double-mint** — `MultiChildBranch` mounts all frontier children in one reconcile pass; each `_run` does `await null` then `createSession`, both see `session==null` → two session beads for one work bead (the *restoration-bucket root*). (b) **fan-out collapses to one process** — concurrent `CapabilityHost`s call `provider.start(sessionId)` with the **same name** → 2nd+ throw `SessionAlreadyExists` (silently swallowed, `effect_seed.dart:147-148`); and `events.where(e=>e.name==name)` (`effect_seed.dart:131-132`) cross-fires **every** host's `_onComplete`. **Refined shape (Nico's, in conversation):** an engine-private **`SessionScope`** node — mounted by `WorkBead` ABOVE the formula subtree — **adopt-or-mints** the session bead through the chokepoint, holds local `{resolving | ready(SessionHandle) | failed}` state, and provides `InheritedSeed<SessionHandle>` so the `FormulaScope` + every `CapabilityHost` attach **only once the session is resolved** (a loading-state until then — the async establishment is a tree *state*, not a synchronous "inject the id"). *(The* Page:Route *abstraction that fits here: the session is the "Route" that resolves before its "Page"/Flow attaches — an abstraction, not a literal rename.)* Per-step provider name = `'$sessionId/$nodePath/$stepId'`. `SessionScope` owns the session lifecycle **end-to-end**: it also **closes** the session on the formula's positive terminal OR breaker-exhaustion (folding D-5's parity-fix + exhaustion-teardown into one owner). Restoration's adopt-or-mint falls out as the same `resolving → ready` transition on restart. Engine-private — no author-facing "session capability" until a need arises. *(Supersedes P0's first-leaf-mint + `EffectSeed` name=id.)*

**D-3 — the cursor schema generalizes `grid.phase` (3-enum, one key) → `grid.cursor.{path}.*` (per-step keys); `WorkPhase` likely retires (major; all lenses touch it).**
A reentrant formula's progress is a step-graph position, not a 3-value enum. This is **not** zero-wire-change: it touches `session_bead.dart` (`SessionBeadKeys`), `session_projection.dart`, `work_phase.dart` + `phaseOf`, the `StationJoinBridge` READ side, **and** `RestartReconciler` (which reads `grid.phase` to decide respawn-or-skip). They MUST migrate in lockstep, plus `grid_cli`'s `grid phase --advance`. The change is **confined to the_grid-internal `grid.`-namespaced metadata on `tgdog` session beads** — the codec boundary is untouched (`rigKey='rig'`, `IssueType.rig`, `type=convergence`, `kGridNamespace='grid'`, the M2 convergence byte-port all stay external contracts). **Proposed:** ship the linear formula with stepIds `{agent,verify,land}` + a compat `grid.phase → grid.cursor` projection for one transition, then retire `WorkPhase`. *(Wants ratification: the schema change + whether to keep a compat shim.)* **SessionScope reshape (D-2):** the "does a session exist for this work bead?" half of the old `phaseOf` JOIN moves INTO `SessionScope`'s adopt-or-mint resolution; `FormulaScope` only reads the per-node `grid.cursor.{path}.*`. The cursor root is the session bead `SessionScope` establishes.
**DECIDED (Nico, 2026-06-27): generalize the schema, retire `WorkPhase`, NO compat shim.** `grid.phase` is **the_grid-internal** metadata on the_grid's own `tgdog` session beads — *not* a gc contract (A37: gc never reads `tgdog`). `tgdog` is the disposable dogfood DB with **no real users**, so we just **migrate/rebuild it**. A shim would only be warranted for a gc/external contract — there is none here. (If a future schema change *does* touch a gc-read key, that one needs a shim.)

**D-4 — per-node respawn-or-skip; promote pgid/pid/token from flat `SessionProjection` to per-`NodeCursor` (major; crash lens, break 1).**
`RestartReconciler._killOrphanThenRespawn` reads **scalar** `session.pgid`/`session.pid` (`restart_reconciler.dart:315-316`) — safe only because the 1-wide frontier means one live process per work bead. A Burn has **many** concurrent live groups (peripheral daemon + central daemon + advertisers + coordinator). On a mid-Burn controller restart the reconciler kills **at most one** pgid, leaves the rest alive, then the tree re-mounts and respawns them → the exact double-run respawn-or-skip exists to prevent, reintroduced at depth. **Proposed:** promote `pgid/pid/token` into per-`NodeCursor` (`grid.cursor.{path}.{pgid,pid,token}`); `RestartReconciler` iterates **every** `NodeCursor` whose state ∈ `{running,ready}` with a recorded pgid, calling the REAL guarded `terminateGroup` on each (per-node token = the recycled-pgid freshness fence at depth) before marking respawn-pending. Worktree reap stays per-bead. *(Generalizes A40's hand-rolled bucket — wants ratification.)* **SessionScope reshape (D-2):** runs UNDER `SessionScope`'s adopt-on-restart — `SessionScope` adopts the session first, then per-`NodeCursor` it is respawn / skip / adopt-live.
**DECIDED (Nico, 2026-06-27): as specified.**

**D-5 — supervision + the restorable circuit-breaker (ADR-0008 D7) sequences BEFORE the Burn acceptance; the FAILING LEAF HOST is the named restart writer (major; lifecycle + crash lenses).**
The recommended design wanted D7 deferred and shipped "backoff-free immediate respawn" as the MVP. The adversarial pass calls that **not-shippable**: (a) a circuit-broken step yields an *empty frontier identical in shape to "formula complete"* → the terminal step never closed → session never terminal → `WorkList`'s unmount predicate (`work_list.dart:97` `bead.isClosed || session.isTerminal`) never fires → the WorkBead stays **mounted with an empty subtree forever**, sibling daemons leak, **no escalation ever fires** — a silent stall, directly contradicting D7's "never a re-mount-forever loop; exhaustion escalates to a human." (b) Restart-in-place is *unexpressible*: the eligibility predicate excludes `state==failed`, and the only writer is a leaf host while `FormulaScope` is a pure `StatelessSeed` — **there is no node positioned to author the `restartCount` bump**. **Proposed:** (1) sequence D7 before the Burn (Track G before Track J). (2) The **failing leaf host's own `_onComplete`** writes `{state, restartCount+1, cooldownUntil}` atomically through the chokepoint; the predicate becomes `state==pending OR (state==failed AND restartCount<max AND now>=cooldownUntil)`. (3) An **empty-because-broken** frontier is distinguished from **empty-because-complete** (terminalStep complete) and drives an unmount/escalation — never an indefinitely-mounted empty subtree. *(Wants ratification: the sequencing + the named writer under invariant 1.)* **SessionScope reshape (D-2):** the session CLOSE (positive-terminal OR exhaustion+escalation) is owned by `SessionScope` (ONE lifecycle owner), not the terminal step's host — that is what distinguishes empty-because-broken from empty-because-complete at the source. The failing leaf host still authors `restartCount`/`cooldownUntil`; `SessionScope` observes terminal/exhaustion and closes/escalates.
**DECIDED (Nico, 2026-06-27): as specified** — supervision + the restorable breaker sequence before the Burn (Track G before Track J).

**D-6 — stable ambient providers declared `updateShouldNotify => false`; NO identical-skip caching of formula child Seeds (minor→major-in-spirit; invariant-1 lens, B2/B3).**
`FormulaScope.build` resolves `CapabilityRegistry`/`ServiceBundle` via `dependOnInheritedSeedOfExactType` at **every** formula node at **every** depth. If a P1/TOML reload ever swaps that `InheritedSeed` *value in place*, every `FormulaScope` force-rebuilds simultaneously — invariant 1's *letter* holds (not a pipeline subscription) but its *spirit* breaks (the "config built 100×" failure). **Proposed:** declare `CapabilityRegistry`/`ServiceBundle`/`DartEnvironment` STABLE (`updateShouldNotify => false`, matching the `EffectContext`/`EffectResolver` stability P0 relies on); model dynamic reload as a **new run / subtree remount**, never an in-place swap. Separately: keep formula child-Seed construction **FRESH each build** (no identical-skip caching) as the default — genesis identical-skip is *identity-only* (`branch.dart` `identical(child._seed,newSeed)`, never `Seed.==`), so a value-equality cache that returns identical instances across a real cursor change would SKIP the subtree and **stall the barrier** (deadlock). *(Wants ratification as a standing rule.)* **SessionScope reshape (D-2):** the rule extends to `InheritedSeed<SessionHandle>` — stable post-resolution (`updateShouldNotify => false`); the `resolving → ready` transition is a *structural child appearance* (the `FormulaScope` mounts), never an in-place value swap, so it does not fan-rebuild.
**DECIDED (Nico, 2026-06-27): as specified.**

**D-7 — ADR-0008 D8 resource-governance scope for THIS build.** ADR-0008 lists D8 (declare-and-check, bounded) as P1-in-scope; the recommended design defers the governor and ships only the `ResourceRequest` value-type declaration. The Burn's RESOURCE-15/16 (peak aggregate checked at claim, only-leaves-acquire-permits) is real but the 2-device bounded Burn does not strictly need it. **Proposed:** ship `ResourceRequest` as a *declared-now, statically-inspectable* value-type field on `Formula`/`CapabilityStep`, and build the `DartEnvironment`/governor + leaf-permit acquisition as a **separate, optional Track** (Track F-adjacent) that the Burn acceptance does NOT block on. **DECIDED (Nico, 2026-06-27): declaration only.** Ship `ResourceRequest` as a declared, statically-inspectable value-type field on `Formula`/`CapabilityStep`. The `DartEnvironment` governor + leaf-permit acquisition are a **separate, optional track NOT in the P1 spine** — the Burn does not block on it.

---

## OPEN QUESTIONS

> **1–7 RESOLVED (Nico, 2026-06-27)** — answers inline. 8–9 stay deferred (post-prototype / federation scope). None blocked the spine.

1. **`StepKind` member naming.** The grafted lifetime enum is `{job, daemon}` (Design-2's `service` renamed to `daemon` to avoid colliding with the pluggable `Service` seam / `ServiceCapability`). Confirm `daemon`, or pick another word (`resident`? `longLived`?). → **`daemon` (Nico).**
2. **`FanOutStep` — sugar or core?** The 2-device Burn uses two explicit `SubFormulaStep`s, so dynamic keyed `FanOutStep` (with a `declaredBound` for D8 static inspectability) is *optional sugar* in P1. Build it now, or fence it to dynamic-planning-future? → **Deferred to dynamic planning (Nico)** — not in P1; the 2-device Burn uses explicit `SubFormulaStep`s.
3. **`StationKernel.dispose` teardown drain (lifecycle lens).** Today `dispose()` does `_owner.dispose()` then returns *without awaiting* any `provider.stop`/`teardown` future (`station_kernel.dart:86-91`), so on graceful shutdown teardown microtasks may never flush before process exit. Should `dispose` collect every dispose's stop/teardown future and await them with a **bounded timeout** (converting "guaranteed-initiated" → "guaranteed-initiated-and-drained-on-graceful-shutdown")? Lean: yes. → **Yes (Nico)** — `StationKernel.dispose` collects every dispose's stop/teardown future and awaits with a bounded timeout.
4. **Detached side-process reach (lifecycle lens, TEARDOWN-12).** `provider.stop` kills only the managed group via `kill(-pgid)`; the mDNS advertiser is spawned `detachedWithStdio` into its **own** session/group (`subprocess_provider.dart:80-88`) so `kill(-pgid)` cannot reach it. Put the advertiser **inside** the harness pgid (spawn non-detached / same `setpgid` target), or keep it detached and reach it with a **per-role unique token** `pkill -f <token>` (never bare `pkill -x butane_harness`, which nukes the sibling role)? Lean: in-group where possible, token-`pkill` for ssh hosts. → **In-group where possible; per-role token `pkill -f <token>` for ssh hosts (Nico).** Accepted constraint (Nico, explicit): this **couples the_grid's process control to POSIX-like systems** (pgid / `kill` / `pkill`) — documented; non-POSIX hosts are out of scope for now (a future host/transport abstraction could lift it — "design to be lifted").
5. **Daemon liveness re-check (lifecycle lens).** A daemon writes `ready` and stays mounted; if its process later dies the cursor stays `ready` (edge-triggered) and the coordinator connects to a dead endpoint. Add an explicit **daemon-liveness terminal** (a daemon's `Exited`/`Died` writes a *non-positive* cursor so `FormulaScope` re-closes the barrier and withholds/unmounts the coordinator) — distinct from the job `complete`? Lean: yes (folds into D-5). → **Yes (Nico)** — an explicit daemon-liveness terminal; folds into D-5.
6. **Worktree layout home (ADR-0008 OQ1).** Stays in core `EffectContext`, or moves to a process-capability base? (Relevant because restoration's detached-process LOG FILE needs a stable worktree-log location.) Lean: stays core. → **RESOLVED + RENAMED (Nico, 2026-06-27): `worktree` → `workspace` at the engine/context level; stays core.** It currently *is* literally a git worktree (`git worktree add`), but that is the **git `SourceControl` impl's** way of *provisioning* a workspace — the **engine concept is `workspace`** (the stable home dir a capability runs in; a Burn harness on a remote device has a workspace but **no** git worktree). "git worktree" stays only inside the git `SourceControl` asset. **`workspace` = the stable home + the restoration anchor** (where the detached-process log file lives). **cwd ≠ workspace:** a process's working directory **defaults to `workspace`** and is overridable per-spawn via `RuntimeConfig.workingDirectory` (spawn config, not engine state); we do **NOT** keep a separate `pwd` cursor (cwd is transient/derivable — restoration restores only the `workspace` home, not a moving cwd). **No pwd cursor — confirmed (Nico, 2026-06-27).**
7. **`Trust` interface home (ADR-0008 OQ2).** the_grid vs a genesis-shared abstraction. Not load-bearing for the Burn's BLE path; part of the `ServiceBundle` seam set. Lean: the_grid. → **the_grid (`grid_engine`) for now (Nico)** — no extraction planned, but **designed to be lifted**: keep the `Trust` interface clean and dependency-free so a later genesis-shared home is a move, not a rewrite.
8. **Restoration mechanism's genesis home (ADR-0008 OQ3).** `genesis_tree` itself vs a sibling — decided ONLY after the the_grid-local Burn prototype proves the shape. Spike before doctrine.
9. **N-escalation dedup (federation residue).** When every capable station's breaker trips for the same work, who dedups the N operator escalations? Out of single-station scope (ADR-0011), but the escalation marker shape written in Track G should not preclude it.

---

## 0. Decided inputs (from ADR-0008, the recommended design)

1. **Reentrancy drops in BELOW `WorkBead` at the existing seam, ZERO change above it.** `WorkBead.build` already does one `dependOnInheritedSeedOfExactType<EffectResolver>()` then `resolver.effectFor(...)` (`work_bead.dart:40-48`), and `EffectResolver.effectFor` is **already typed `Seed`, not `EffectSeed`** (`effect_resolver.dart:26`) — so it can root a subtree *today* with no structural change. The new resolver returns an engine-private **`SessionScope`** (D-2: adopt-or-mints the session, holds `{resolving|ready(SessionHandle)|failed}`, and on `ready` provides `InheritedSeed<SessionHandle>` + builds the `FormulaScope` — a pure `StatelessSeed`; `const Idle()` while resolving) instead of a single effect leaf.
2. **The author touches ONLY value-types + opaque `Capability` leaves — never a `Seed`** (ADR-0008 D2/D4). This is what holds the four derailment-invariants AT DEPTH *by construction*. Engine Seeds (`FormulaScope`/`_FormulaChildren`/`CapabilityHost`) stay private and are never subclassed by an asset.
3. **The spine = a pure inflater + a generic container + an engine-private carrier** (recommended Design 3): `FormulaScope extends StatelessSeed` (the inflater, the depth-analogue of `WorkList`+`EffectResolver`, ZERO subscription) → `_FormulaChildren extends MultiChildSeed` (the one generic container kind) → `CapabilityHost extends StatefulSeed` (today's `EffectSeed` generalized off the 3-enum `WorkPhase` onto an arbitrary `nodePath`/`stepId`) → opaque `Capability` leaf.
4. **Grafted mechanics:** an explicit `StepKind {job, daemon}` lifetime enum (Design 2) and a **flat per-key merge-safe cursor** that doubles as the restoration bucket-tree (Design 2, now hardened by **D-1**).
5. **Session lifecycle owner (D-2):** `SessionScope` opens (adopt-or-mint) AND **closes** the session — on the formula's positive terminal (terminal step `complete`) OR breaker-exhaustion — NOT the terminal step's host, NOT a synthetic done-leaf. One owner for open+close. The observable close still lands when the terminal step completes (same trace as P0's land-closes-directly path, modulo the observing node). Pinned by a mutation test.
6. **agent/verify/land = a 3-step linear `Formula`** whose always-1-wide frontier reproduces P0 **byte-for-byte**. The Burn is the multi-step fan-out + barrier + long-lived-coordinator + guaranteed-teardown stress case.
7. **Restoration (D6), the genesis extraction, federation (ADR-0011), observability (ADR-0012)** are designed as compatible SEAMS and explicitly **NOT built** (§11).

---

## 1. What P1 is, and the acceptance gate

P1 is **the reentrant engine, for real**: a value-typed `Formula` step-graph that the engine inflates into a reconciled subtree using the SAME `genesis_tree` machinery at every depth — `Station → Substation → WorkList → WorkBead → SessionScope → FormulaScope → _FormulaChildren → CapabilityHost → Capability` — with fan-out, an await-all barrier, supervised restart, and guaranteed teardown inherited for free. The author writes composition-of-value-types + opaque `Capability` leaves and never a `Seed`.

**Acceptance (the gate, all offline):**
- agent/verify/land run as a **constant linear `Formula`** whose 1-wide frontier reproduces P0 behavior **byte-for-byte** (the no-behavior-change proof, §6);
- a multi-step `Formula` **fans out** keyed children, **honors intra-set ordering edges** (peripheral-before-central), and **gates a downstream step on a barrier** (positive-terminal-only — a half-up rig never mounts the coordinator);
- **guaranteed teardown** runs on every exit path (success / partial-failure / crash / cancel) and reaches **detached** side-processes;
- a **supervised** failed step re-keys + remounts with backoff; **exhaustion** escalates to the_grid's own store and tears the subtree down (never an indefinitely-mounted empty subtree);
- a controller **restart** respawn-or-skips **per node** (no double-work across N concurrent groups);
- **N concurrent cursor writes (disjoint keys) lose no key** (the D-1 serialization gate);
- the **four derailment-invariants hold AT DEPTH** as mutation-tested gates;
- the **Burn** (`butane_grid_assets`, offline, fakes) passes end-to-end as the integration test;
- offline-green + `melos analyze` clean across all packages.

---

## 2. Wave 0 — package + dependency setup

- No new engine package — P1 grows `grid_engine` (the renamed Station engine). Acyclic graph unchanged (`grid_engine → {grid_controller, grid_runtime}`).
- The **public `the_grid` SDK package** (ADR-0008 D2) over the now-private `grid_engine` and the **`*_grid_assets`** packages (`station_grid_assets`, `butane_grid_assets`) are the *package-name migration* — **deferred per ADR-0008 D1** (the type/machinery rename already landed). P1 builds the SDK *surface* (the value-types + the `Capability`/`Service` interfaces + the registry) inside `grid_engine` behind a clear `lib/src/sdk/` fence; the package split is a follow-on.
- `genesis_tree` stays the pinned dep + sibling override (the composition layer is still EXPERIMENTAL; the_grid is the triggering 2nd consumer). **No genesis change required** — the recommended design uses only existing primitives (`StatelessSeed`, `MultiChildSeed`, `StatefulSeed`+`State`, `InheritedSeed`, keyed `updateChildren`). The genesis Sprout/`useEffect` shape is **REJECTED** for author leaves (it still hands the leaf a `dependOn`/`markNeedsRebuild` handle → does not satisfy "no `TreeContext`").
- `freezed` + `json_serializable` for the value-types (TOML- and Dart-authorable: two serializations of one freezed shape).
- Touched in `grid_cli`: `composeRunTree` → `compose([DefaultExtension()/station_grid_assets, …])`; `grid phase --advance` → `grid step --advance <path>` (the D-3 cursor generalization).

---

## 3. The API sketch (the gating surface — freezed value-types + opaque interfaces)

> **Value-types (author surface; freezed + `json_serializable`; TOML or Dart).** This is the wire the author writes — they never see a `Seed`.

```
// The reentrant unit: a declared step-graph.
Formula {
  String id;
  List<FormulaStep> steps;
  String terminalStepId;                 // its host closes the session (parity fix)
  SupervisionStrategy supervision = oneForOne;   // Burn = restForOne (D-5)
  Backoff backoff;                                // mandatory; spawns cost minutes+tokens
  ResourceRequest? peak;                          // D8 declared-now (D-7)
}

sealed FormulaStep:
  CapabilityStep {
    String stepId;
    String capabilityId;                 // resolved via the CapabilityRegistry
    Map<String,String> params;
    Set<String> dependsOn;               // the barrier IS multiple deps
    StepKind kind = job;                 // job | daemon  (OQ-1)
    ResourceRequest? resources;          // per-leaf permit (D8/D-7)
  }
  | SubFormulaStep {                     // REENTRANCY: inflated by the SAME FormulaScope one level down
      String stepId;
      String formulaId;
      Map<String,String> params;
      Set<String> dependsOn;
    }
  | FanOutStep {                         // keyed dynamic-but-bounded (OQ-2; optional sugar)
      String stepId;
      String overSelectorParam;
      FormulaStep template;
      int declaredBound;                 // statically inspectable for D8
      Set<String> dependsOn;
    }

enum StepKind { job, daemon }           // job = runs-to-completion-then-retires;
                                        // daemon = stays-mounted-after-ready (harness, advertiser)
enum StepState { pending, running, ready, complete, failed }
                                        // ready AND complete are POSITIVE TERMINALS that satisfy a dependsOn;
                                        // a daemon satisfies on ready while staying mounted;
                                        // a job satisfies on complete then is pruned.
enum SupervisionStrategy { oneForOne, restForOne, oneForAll }
Backoff { Duration min, max; double factor; }
ResourceRequest { int builds; int processes; }   // declared-now, honored-later
```

> **The restorable cursor (D-3) — FLAT per-key, merge-safe, the restoration bucket-tree.**

```
FormulaCursor = Map<String /*nodePath*/, NodeCursor>;
NodeCursor {
  StepState state;
  int? pgid; int? pid; String? token;   // per-node respawn fence (D-4)
  int restartCount;                      // restorable; gates the predicate (D-5)
  DateTime? cooldownUntil;               // backoff (D-5)
  int? logOffset;                        // restoration adopt seam (deferred, §11)
}
```
Persisted as flat `grid.cursor.{nodePath}.{state,pgid,pid,token,restartCount,cooldownUntil}` keys on the_grid's OWN `tgdog` session bead — **never** the foreign work bead (A37). The codec boundary (`rigKey='rig'`, `IssueType.rig`, `type=convergence`, `kGridNamespace='grid'`) is untouched; the change is confined to `grid.`-namespaced metadata.

> **The opaque `Capability` interfaces (author leaves; NEVER a `Seed`).** Two flavors mirror the two carriers P0 already has — both carry `teardown`.

```
abstract interface ProcessCapability {              // generalizes AgentEffectSeed/VerifyEffectSeed
  RuntimeConfig spawn(CapabilityContext);           // PURE — describe what to run; the host owns provider.start/stop
  StepSignal interpretEvent(RuntimeEvent);          // map a runtime event → ready/complete/failed
  Future<void> teardown(CapabilityContext);         // idempotent belt-and-braces kill (TEARDOWN-11/12)
}
abstract interface ServiceCapability {              // generalizes LandEffectSeed
  Future<StepOutcome> run(CapabilityContext);       // async body driving Services (git/PR, the Burn coordinator)
  Future<void> teardown(CapabilityContext);
}

enum StepSignal { none, ready, complete, failed }
sealed StepOutcome { Ok(payload?) | Failed }

// The narrow, sandboxed projection a leaf gets — NO TreeContext, NO notifier,
// NO writer, NO markNeedsRebuild. A sanitized read-only slice of EffectContext.
CapabilityContext {
  Map<String,String> params;
  String beadId; String worktreeDir; String branch; String baseBranch;
  ServiceBundle services;                // typed accessors; no pipeline handle
  CancelToken cancel;
  String? logFile;                       // restoration seam (deferred)
}
```

> **The `Service` seam (pluggable collaborators; impls ship in assets — ADR-0008 D5).** Provided as **ONE `InheritedSeed<ServiceBundle>`** above `Station` (a single concrete type sidesteps genesis's exact-type-only `dependOnInheritedSeedOfExactType` — you cannot provide `<GitSourceControl>` and look up `<SourceControl>`). The bundle is a stable handle → `updateShouldNotify => false` (D-6) → resolving it is a benign dependency, never a rebuild.

```
ServiceBundle {
  SourceControl? sourceControl;          // first Service; today's gitOps/prOpener migrate IN
  Trust? trust;                          // reserved (OQ-7); distinct from genesis_consent
  ExplorationTransport? transport;       // outbound sink only — no inbound pipeline handle
}
abstract interface SourceControl {
  Future<void> commitAll(String workDir, String message);
  Future<void> push(String workDir, String remote, String branch);
  Future<PrRef?> openPr(String workDir, String branch, String baseBranch, String title);
}
```
Core `EffectContext` shrinks to `{ provider, writer, stateSubstation, worktree layout, ServiceBundle services }`; `gitOps`/`prOpener` (`effect_context.dart:56-60`) migrate OUT into a `GitSourceControl` (today's `StationGitService`) shipped in `station_grid_assets`.

> **Engine-private types (never subclassed by an asset):** `SessionScope extends StatefulSeed { String workBeadId; }` + `SessionScopeState extends State` (the adopt-or-mint session lifecycle owner, D-2) holding `{resolving|ready(SessionHandle)|failed}`; `SessionHandle { String sessionId; }` provided via a stable `InheritedSeed<SessionHandle>` (`updateShouldNotify => false`) · `FormulaScope extends StatelessSeed { Formula formula; FormulaCursor cursor; String nodePath; }` · `_FormulaChildren extends MultiChildSeed` (the one generic container kind) · `CapabilityHost extends StatefulSeed` + `CapabilityHostState extends State` (the carrier) · the resolver (`implements EffectResolver`, returns `SessionScope`) · `CapabilityRegistry` (capabilityId/formulaId → impl, stable, `updateShouldNotify => false`).

---

## 4. The inflation mechanism (one new node, at exactly the existing seam)

The resolver returns a `SessionScope(workBeadId: bead.id, key: ValueKey('${beadId}:session'))` — the engine-private node that **adopt-or-mints** the session (D-2), holds `{resolving|ready(SessionHandle)|failed}`, builds `const Idle()` while resolving, and on `ready` builds `InheritedSeed<SessionHandle>(child: FormulaScope(formula: formulaFor(bead), cursor: session.cursor ?? empty, nodePath: bead.id, key: ValueKey('${beadId}:formula')))`. `FormulaScope.build(context)` is **PURE** (A39 — no store re-query, no subscription) and inflates in four steps:

1. **Read** the cursor slice for `nodePath` from the **injected** `cursor` field (config, threaded down from `WorkList`'s reconcile cascade — NOT a subscription).
2. **Compute** the eligible frontier with a pure predicate:
   `eligible = steps.where(depsSatisfied(s) ∧ ¬retired(s) ∧ ¬circuitBroken(s))` where
   - `depsSatisfied(s)` = every `d ∈ s.dependsOn` has `cursorState(resolvePath(d)) ∈ {ready, complete}` (a `SubFormula` dep resolves to its `'{path}/{terminalStepId}'` descendant entry — **positive-terminal-only**, never satisfied by a vanished/failed step);
   - `retired(s)` = `s.kind==job ∧ state==complete`;
   - `circuitBroken` = the D-5 hook (the failed-and-exhausted term).
3. **Map** each eligible step to a child Seed keyed `ValueKey('${beadId}:${nodePath}/${stepId}#${incarnation}')` (incarnation = `NodeCursor.restartCount`, so a supervised restart **changes the key** → keyed reconcile unmounts the old + mounts the new): `CapabilityStep → CapabilityHost(...)`; `SubFormulaStep → nested FormulaScope(registry.resolve(formulaId), cursor, nodePath:'{nodePath}/{stepId}')`; `FanOutStep → one keyed child per resolved selector`.
4. **Return** `_FormulaChildren(children)`.

**Genesis mapping:** `FormulaScope` compiles to a `ComponentBranch` (single child) → mounts exactly one `_FormulaChildren`; `_FormulaChildren` → `MultiChildBranch` whose `performRebuild = updateChildren(old, new)` is keyed reconcile. A step whose key persists keeps its `CapabilityHost` Branch+State (no respawn, only the `const Idle()` build re-runs); a step entering the frontier mounts (`initState`=spawn); a step leaving (job complete, or supervised re-key) unmounts (`dispose`=kill). This **generalizes the P0 phase-swap from one keyed child to N**, mirroring the proven `WorkList`(StatefulSeed) → `_WorkBeads`(MultiChildSeed) topology exactly.

**Rejected:** a `FormulaSeed extends MultiChildSeed` *as the inflater* (Design 1) — it forces **eager recursive inflation** of nested sub-formulas inside a factory at `WorkBead.build` time. The `StatelessSeed`-inflater + separate generic container gives every formula depth its own `build()` that re-runs only when its cursor slice changes.

---

## 5. Lifecycle / teardown / barrier semantics

**`CapabilityHost` = `EffectSeed` generalized, not rewritten** (`effect_seed.dart` is the pinned source). `initState` → `_token = newInstanceToken(); unawaited(_run())`. `didChangeDependencies` → capture `_ctx = of<EffectContext>()`, `_services = of<ServiceBundle>()`, `_registry = of<CapabilityRegistry>()` (ONE lookup each, into fields). `_run` → `await null` (yield so captures land — the genesis `initState`-then-`didChangeDependencies` ordering, `effect_seed.dart:112-118`), guard `_cancelled || !context.mounted`, resolve the session id **from injected config** (D-2 — no mint here), guard again:
- **ProcessCapability path:** subscribe `_ctx.provider.events.where(e => e.name == _stepName)` where `_stepName = '$sessionId/$nodePath/$stepId'` (D-2); `config = cap.spawn(capCtx).copyWith(env: {…, GRID_BEAD_ID, GRID_INSTANCE_TOKEN: _token, GRID_STEP_PATH: nodePath})`; `_started=true`; `await _ctx.provider.start(_stepName, config)`.
- **ServiceCapability path:** run `cap.run(capCtx)` behind the guards; map `StepOutcome → cursor write`.

`_onEvent` switch: `SessionStarted` → persist identity to `grid.cursor.{path}.{pgid,pid,token}` (D-4); `Exited`/`Died` → `cap.interpretEvent(e) → StepSignal` → write `grid.cursor.{path}.state` through the chokepoint (a **daemon** writes `ready` and STAYS mounted; a job writes `complete`/`failed`; a daemon's later death writes a *non-positive* cursor — OQ-5). The three load-bearing guards live ENTIRELY in the host (`effect_seed.dart:185,205-212`): `_cancelled` set FIRST in `dispose`; `context.mounted` probed after every await; captured `_ctx` used across gaps; plus the `_completed` once-only latch and `_started` (kill only if spawn was reached). `dispose` → `_cancelled=true`, cancel `_sub`, `if(_started) _ctx.provider.stop(name)`, `unawaited(cap.teardown(_capCtx))`. `build()` → `const Idle()` (A39).

**Session close (D-2 — owned by `SessionScope`):** `SessionScope` observes (via the injected cursor) the formula reaching its positive terminal (terminal step `complete`) OR breaker-exhaustion, and writes `writer.close(sessionId)` — ONE owner for session open+close, not the terminal step's host, not a synthetic done-leaf. The observable close still lands when the terminal step completes (same trace as P0's `LandEffectSeed`-closes-directly path, `default_extension.dart:194`, modulo the observing node). Pinned by a mutation test.

**Barrier** = a step with multiple `dependsOn` edges. There is NO barrier node and NO cross-node lookup (genesis has no `GlobalKey`/registry by design). "await-all" = "`FormulaScope.build` does not yet include the downstream child": the coordinator with `dependsOn {harnessPeripheral, harnessCentral}` is withheld from `eligible` until BOTH deps' terminal-descendant cursor entries read `ready`/`complete`. Satisfaction is OBSERVED OUT-OF-BAND (A39): leaf hosts write through the chokepoint → `StationJoinBridge` (the lone subscription) → `JoinedSnapshotNotifier` → `WorkList` (the sole observer) → `FormulaScope` re-inflation re-evaluates the predicate. `FormulaScope` subscribes NOTHING. **Positive-terminal-only:** a failed/never-ready harness leaves the coordinator un-mounted and routes the failed step to supervision — it can never run against a half-up rig.

**Teardown** = the unmount cascade (OTP `terminate` == genesis `dispose`, structural, guaranteed on EVERY exit path). Three triggers converge: (a) `terminalStepId` complete → frontier empties, daemons retire to `_FormulaChildren([])`; (b) the `WorkBead` leaving `WorkList`'s child-set (bead closed / session terminal); (c) `StationKernel.dispose`. `MultiChildBranch.unmount` reconciles children to `const []` depth-first, so every live `CapabilityHost.dispose` runs → `provider.stop` kills the process GROUP by pgid + `cap.teardown` fires the belt-and-braces kill (local + ssh `pkill` by token — OQ-4). **Honest caveats (all designs agree, stated not hidden):** (1) `dispose()` is synchronous `void` → async teardown is fire-and-forget; teardown is guaranteed-INITIATED, not guaranteed-COMPLETED (mitigated by the bounded drain — OQ-3). (2) No inter-sibling teardown ordering beyond child-list order; `restForOne` ordered teardown is built atop, deferred. (3) Controller death mid-dispose → teardown never runs; closed only by restoration's adopt-and-kill (deferred, §11). Mitigation: **idempotent belt-and-braces** (pre-launch `pkill` inside `cap.spawn` AND post-run `teardown`) + adopt-on-restart.

---

## 6. agent / verify / land → single-step formulas (NO behavior change)

agent/verify/land become the constant linear:
```
Formula(id:'code', terminalStepId:'land', supervision:oneForOne, steps:[
  CapabilityStep('agent',  capabilityId:'agent',  kind:job, dependsOn:{}),
  CapabilityStep('verify', capabilityId:'verify', kind:job, dependsOn:{'agent'}),
  CapabilityStep('land',   capabilityId:'land',   kind:job, dependsOn:{'verify'}),
])
```
Its frontier is **always exactly 1-wide** (agent has empty deps; verify withheld until agent=complete; land until verify=complete), so `FormulaScope` mounts one `CapabilityHost` at a time and the keyed-reconcile swap on each cursor advance reproduces P0's `EffectSeed` behavior **byte-for-byte** — because `CapabilityHost` is `EffectSeed` *generalized*, not rewritten. Today's `AgentEffectSeed`/`VerifyEffectSeed`/`LandEffectSeed` (`default_extension.dart:36,63,100`) become three `Capability` impls under capabilityIds `agent`/`verify`/`land` and migrate OUT to `station_grid_assets` (ADR-0008 D2); the `CapabilityHost` carrier stays engine-private. The **1-wide frontier structurally cannot exercise** the concurrency races (D-1/D-2/D-4) — which is *why* the Burn (§9) must be a first-class acceptance, not a P0 regression check.

**Acceptance (the no-behavior-change proof):** run the `'code'` formula offline over the P0 fakes; assert the exact P0 `FakeEffect` start/stop trace (`[START agent, STOP agent + START verify, STOP verify + START land, close session]`), the same single-1-wide-frontier flush behavior (`flush()` returns `[WorkList]` only), and the same restart respawn-or-skip dispositions. A mutation test asserts the terminal step (`land`) closes the session **directly** (parity fix), not via a done-leaf.

---

## 7. Tracks (dependency-ordered waves)

> Each track: **build** · **reuse** (file-cited) · **net-new** · **acceptance (TEST-FIRST, offline)**. 10 tracks across 5 waves.

### Wave 1 — Track A: the value-types (pure; zero I/O) · Track B: the cursor-schema migration (the shared contract)

**Track A — build:** the freezed `Formula`/`FormulaStep` sealed union/`StepKind`/`StepState`/`SupervisionStrategy`/`Backoff`/`ResourceRequest` (§3) + the pure eligibility predicate (`depsSatisfied`/`retired`/`circuitBroken`) as a free function over `(Formula, FormulaCursor, nodePath)`.
- **Net-new:** all of §3's value-types; the predicate.
- **Acceptance (no I/O):** golden frontier computations — linear (1-wide at each cursor), fan-out-with-ordering (peripheral before central), barrier (coordinator withheld until both deps terminal), positive-terminal-only (a `failed` dep never satisfies), retired-job-pruned. TOML↔Dart round-trip of one `Formula` (two serializations of one shape).

**Track B — build (D-3, lockstep):** generalize `grid.phase` (3-enum, one key) → `grid.cursor.{nodePath}.*` (per-step keys). Migrate `session_bead.dart` (`SessionBeadKeys` → per-node keys), `session_projection.dart` (`SessionProjection` → carries a `FormulaCursor`), `work_phase.dart`+`phaseOf` (retire `WorkPhase`; `phaseOf`→`cursorOf` JOIN), the `StationJoinBridge` read side, and `RestartReconciler`'s `grid.phase` read.
- **Reuse:** the single-schema-definition discipline (`session_bead.dart:23` `SessionBeadKeys` is already the one read/write definition) — extend it, don't fork it.
- **Net-new:** the per-node key codec; the compat `grid.phase → grid.cursor` projection for one transition (D-3).
- **Acceptance:** round-trip a `FormulaCursor` through the metadata codec; the compat shim reads a legacy `grid.phase` bead as `grid.cursor.{agent|verify|land}`; the codec boundary keys (`rigKey='rig'`, `work_bead`) are untouched (asserted).

### Wave 2 — Track C: the chokepoint serialization + the `SessionScope` adopt-or-mint (D-1, D-2) · Track D: `FormulaScope` + `_FormulaChildren` + the resolver  *(D depends on A,B; C is foundation)*

**Track C — build (gates everything concurrent):** (1) **D-1** — add the per-target-id serialization queue inside `StationBeadWriter` (`Map<String,Future> _tail`; each `create`/`update`/`close`/`delete` on an id chains after the prior op on that id). (2) **D-2** — the engine-private **`SessionScope`** node (mounted by `WorkBead`, above the formula): `initState` kicks off **adopt-or-mint** (read the injected snapshot for an existing owned session for `workBeadId` → adopt; else `createSession` through the chokepoint), `setState` → `ready(SessionHandle)`; `build` returns `const Idle()` while resolving, else `InheritedSeed<SessionHandle>(child: FormulaScope(...))`. Per-step provider name `'$sessionId/$nodePath/$stepId'`. `SessionScope` also closes the session on terminal/exhaustion (D-5).
- **Reuse:** `StationBeadWriter` (`station_bead_writer.dart` — `createSession:88`, `update:117`, `_assertOwned:152`); the ownership fail-closed guard stays verbatim.
- **Net-new:** the `_tail` chain; the `SessionScope` node + `SessionHandle` + `InheritedSeed<SessionHandle>` (adopt-or-mint — the restoration-adopt seam falls out of the same path).
- **Acceptance (TEST-FIRST, the race gate):** fire **N concurrent `update`s with disjoint flat keys** at one session bead → assert **no key is lost** (fails on today's un-serialized writer). Mount two concurrent fan-out children under one session → assert exactly **one** `createSession` and **both** `provider.start` calls succeed with **disjoint** event routing.

**Track D — build:** `FormulaScope extends StatelessSeed` (the pure inflater, §4) + `_FormulaChildren extends MultiChildSeed` (the one generic container kind) + the resolver (`implements EffectResolver`) returning a `SessionScope` (Track C), which builds `FormulaScope` on `ready`. The incarnation-keyed children (`#${restartCount}`).
- **Reuse:** the `EffectResolver` seam **unchanged** (`effect_resolver.dart:26` already typed `Seed`); `WorkBead.build` **unchanged** (`work_bead.dart:40-48`); genesis keyed `updateChildren`; the `WorkList → _WorkBeads` topology as the exemplar (`work_list.dart:137-139`).
- **Net-new:** the three engine-private classes; the `CapabilityRegistry`.
- **Acceptance (no spawn — fake `CapabilityHost`):** a linear formula inflates a 1-wide frontier; advancing the injected cursor re-inflates with the next step keyed-swapped (old unmounts, new mounts), the `FormulaScope` branch identity preserved; a fan-out formula inflates N keyed children honoring ordering; `flush()` after a cursor change returns **exactly `[WorkList]`** (the inflater + children are force-rebuilt by the cascade, excluded from the drain — the invariant-1 guardrail, written FIRST, mirroring P0 Track A).

### Wave 3 — Track E: `CapabilityHost` + the `Capability`/`Service` interfaces · Track F: per-node respawn-or-skip (D-4) + the resource governor (D-7, optional)  *(depend on C,D)*

**Track E — build:** `CapabilityHost extends StatefulSeed` (§5 — `EffectSeed` generalized off `WorkPhase` onto `nodePath`/`stepId`); the `ProcessCapability`/`ServiceCapability`/`CapabilityContext`/`ServiceBundle`/`SourceControl`/`StepSignal`/`StepOutcome` surface (§3); the `InheritedSeed<ServiceBundle>` provided above `Station` in `StationKernel.mountRoot` (alongside the existing three providers, `station_kernel.dart:61-72`), with `updateShouldNotify => false` (D-6).
- **Reuse (verbatim):** the `EffectSeed` lifecycle + guards (`effect_seed.dart` — the whole `EffectSeedState`); `SubprocessProvider`/`process_group`; `StationBeadWriter` (now serialized, Track C); `TreeContext.mounted`.
- **Net-new:** the sandbox boundary (`CapabilityContext` exposes no `TreeContext`/notifier/writer/`markNeedsRebuild`); the per-step name; `cap.teardown` wiring; the `StationKernel.dispose` bounded drain (OQ-3).
- **Acceptance:** mount=spawn / dispose=kill at depth, sibling Branch never rebuilt; a completion to an unmounted Branch → no `StateError`, write lands-if-fresh / dropped-if-stale; **structural sandbox test** (modeled on the P0 `lib/src/extension/` opinion-fence): no `Capability` impl imports `genesis_tree`/`StationBeadWriter`/`JoinedSnapshotNotifier`, and `CapabilityContext`/`ServiceBundle` expose no `Stream`/notifier surface; `ServiceBundle`/`CapabilityRegistry`/`DartEnvironment` `updateShouldNotify` is always `false`.

**Track F — build (D-4):** generalize `RestartReconciler` from per-worktree scalar pgid to **per-node**: iterate every `NodeCursor` whose `state ∈ {running,ready}` with a recorded pgid, calling the REAL guarded `terminateGroup` on each (per-node token fence) before respawn-pending; worktree reap stays per-bead.
- **Reuse:** `RestartReconciler` (`restart_reconciler.dart` — the freshness barrier, the `terminateGroup` guard, the SKIP-for-foreign-bead logic at `:283`); `ListBeadWorktrees`/`ReapWorktree` seams.
- **Net-new:** the per-node iteration; the `NodeCursor` projection (Track B).
- **(Optional, D-7) the resource governor:** `DartEnvironment extends InheritedSeed` + a leaf-only permit acquired wrapping `provider.start`; `Formula.peak` checked at claim time (statically inspectable). Only leaf hosts acquire — orchestration nodes hold nothing (no deadlock). Permits in-memory, re-derived on restart.
- **Acceptance (simulated mid-Burn restart, fakes, FOREIGN-rig arm):** a session with **N live node-cursors** → `terminateGroup` called on **each** pgid before any respawn (fails on today's single-pgid reconciler); a terminal session → SKIP + reap even for a foreign unwritable work bead; a `pgid<=1` → `refusedUnsafe`, still respawn-pending.

### Wave 4 — Track G: supervision + the restorable circuit-breaker (D-5) · Track H: agent/verify/land migration (§6)  *(G depends on E,F; sequenced BEFORE the Burn)*

**Track G — build (D-5):** per-formula `SupervisionStrategy` (`oneForOne` default; `restForOne` = re-key the failed step ∪ its transitive dependents); mandatory `Backoff`; the **failing leaf host's `_onComplete`** authors `{state:failed, restartCount+1, cooldownUntil}` atomically through the chokepoint (the named restart writer — no supervisor node, invariant 1 preserved); the predicate `state==pending OR (state==failed AND restartCount<max AND now>=cooldownUntil)`; **exhaustion** writes a human-escalation marker to `tgdog` AND drives an **unmount/teardown** of the subtree (distinguishing empty-because-broken from empty-because-complete). The **cooldown-expiry re-poke (D-6/F1):** the **kernel** (an orchestrator, not a Seed) owns the backoff `Timer`; on expiry it triggers a **bridge re-emit** (`notifier.push` of the current snapshot) so `WorkList` stays the only dirtier and the cascade re-runs the predicate — **never** a Seed-owned Timer, **never** `root.markNeedsRebuild`.
- **Reuse:** the chokepoint; the `JoinedSnapshotNotifier` re-emit path; the `_completed` latch pattern.
- **Net-new:** the supervision strategies; the restorable `restartCount`/`cooldownUntil`; the kernel backoff Timer + re-emit; the escalation marker.
- **Acceptance:** a failed-then-eligible step re-keys (incarnation bump) and remounts; exhaustion drops it from the frontier, writes the escalation marker, and tears the subtree down (no indefinitely-mounted empty subtree); a cooldown expiry re-mounts **only via a notifier emission** (mutation test: no deep-node dirty, no `root.markNeedsRebuild`).

**Track H — build (§6):** the `'code'` formula + the `agent`/`verify`/`land` `Capability` impls (migrated from `default_extension.dart`); `composeRunTree` wires `station_grid_assets`.
- **Acceptance:** the byte-for-byte no-behavior-change proof (§6); the structural test that the kernel/effect core references no capability — only the asset does.

### Wave 5 — Track I: the four derailment-invariants as MUTATION-TESTED gates AT DEPTH · Track J: the Burn integration acceptance  *(depend on all)*

**Track I — §8.** **Track J — §9.**

---

## 8. The four derailment-invariants as MUTATION-TESTED gates AT DEPTH

> All four must hold **inside every formula subtree**, not just at the top — guaranteed *by construction* because the author touches only value-types + opaque leaves (never a `Seed`) and `CapabilityHost` is never subclassed by an asset (ADR-0008 D2). Each gate is **mutation-tested** (a deliberate break must make the test fail).

- **Invariant 1 — single change-detector at depth:** the formula subtree adds **ZERO** new pipeline subscriptions. `FormulaScope` is a pure `StatelessSeed` (build reads only the injected cursor); `_FormulaChildren` is a passive container; `CapabilityHost` subscribes only its **own** `provider.events` (a different axis from the snapshot pipeline — it observes its own process, never the notifier) and never `setState`s. `WorkList` remains the sole pipeline observer; `root.markNeedsRebuild` stays banned; flush isolation stays observational. **Gates:** (a) a work tick → `flush()` returns exactly `[WorkList]`, config ancestors + the inflater + leaves ABSENT from the drain; (b) no genesis `Seed` in any formula subtree owns a `Timer`/`Stream` that calls `markNeedsRebuild`; (c) a cooldown expiry (D-5) re-mounts **only via a notifier emission** (F1); (d) the stability gate — `ServiceBundle`/`CapabilityRegistry`/`DartEnvironment` `updateShouldNotify` is always `false` (F2).
- **Invariant 2 — single write chokepoint AND serialization at depth (re-scoped per D-1):** only `CapabilityHost`/`SessionScope` writes, via the captured `EffectContext.writer`, onto the_grid's own session bead; `CapabilityContext` has no writer → no leaf/service/capability writes a bead directly; no writes in `build()`. **Gates:** (a) inject a recording writer over a `BdRunner` that THROWS on any direct call; drive a full Burn; assert every write is the writer, zero bypass; (b) the **N-concurrent-disjoint-key** race gate (Track C) — no key lost.
- **Invariant 3 — convergence never mounts at depth:** a formula only ever roots under a `WorkBead`, and `WorkBead` mounts only under `WorkList`'s fail-closed `type.isCore` allow-list (`work_list.dart:88,129`, A41) which excludes `type=convergence` and all custom/session types; `CapabilityStep`/`SubFormulaStep`/`FanOutStep` select devices/steps, never beads-by-type. **Gate:** a ready set with an owned `type=convergence` root mounts **zero** subtree nodes for it (a plain owned bead in the same set still mounts a full formula).
- **Invariant 4 / A37 — read-only foreign source at depth:** the cursor, identity handles, restoration buckets, breaker state, the Burn report, and any escalation signal all land via the chokepoint on the_grid's OWN `tgdog` session bead — never the foreign work bead (fail-closed twice: cursor targets the owned id, and `_assertOwned`/`prefixOf` refuses a foreign id — `station_bead_writer.dart:152`). `build()` stays PURE (A39) at every depth. **Gate:** inject a recording `BdRunner` over the read/work workspace that THROWS on any write; drive a full Burn + a restart; assert **zero** writes reach the foreign source.

---

## 9. The Burn as the integration acceptance test (`butane_grid_assets`, offline)

The Burn is the hardest case — multi-step, multi-host fan-out + multi-layer barrier + a long-lived coordinator + guaranteed teardown of detached processes, running for days. Mounted as ONE `isCore`-typed work bead's `FormulaScope`; the cursor lives entirely on the_grid's `tgdog` session bead, **never** butane's read-only `.beads` (A37).

```
Formula(id:'burn', terminalStepId:'report', supervision:restForOne, peak:ResourceRequest(builds:2, processes:3), steps:[
  SubFormulaStep('harnessPeripheral', formulaId:'deploy', params:{role:peripheral, selector:'mdns:pi-a'}, dependsOn:{}),
  SubFormulaStep('harnessCentral',    formulaId:'deploy', params:{role:central,    selector:'udid:...'}, dependsOn:{'harnessPeripheral'}),  // ordering barrier
  CapabilityStep('coordinator', capabilityId:'butane.coord',  kind:job, dependsOn:{'harnessPeripheral','harnessCentral'}),                 // await-all barrier
  CapabilityStep('report',      capabilityId:'butane.report', kind:job, dependsOn:{'coordinator'}),
])
deploy = Formula(id:'deploy', terminalStepId:'waitWS', steps:[
  CapabilityStep('build',   kind:job,    dependsOn:{}),
  CapabilityStep('install', kind:job,    dependsOn:{'build'}),
  CapabilityStep('launch',  kind:daemon, dependsOn:{'install'}),   // stays mounted; writes ready on WS-port up
  CapabilityStep('waitWS',  kind:job,    dependsOn:{'launch'}),
])
```

**TRACE (offline, fakes/`sh`-stubs):** t0 `WorkBead(burn, isCore)` → `SessionScope` adopt-or-mints the session (D-2), resolves `ready` → provides `SessionHandle` → `FormulaScope(burn)`; frontier=`{harnessPeripheral}` (central withheld = ordering barrier) → nested `FormulaScope(deploy)`; its frontier=`{build}` → `CapabilityHost` spawns. t1 build `complete` → cursor write → bridge → `WorkList` → re-inflate; build (job, complete) pruned, install spawns; → launch (daemon) spawns + STAYS mounted, writes `ready`. t2 waitWS `complete` → peripheral's SubFormula satisfied (terminal descendant complete) → central's dep met → `FormulaScope(deploy,'harnessCentral')` runs its own build→install→launch→waitWS; peripheral's daemon stays up. t3 central/waitWS `complete` → coordinator's barrier (both terminals ready) satisfied → `CapabilityHost(butane.coord, ServiceCapability)` mounts, connects both WS endpoints (subscribed in its OWN State — the only subscriber in its leaf, never the snapshot pipeline), drives the scripted scenario; both daemons stay up. t4 coordinator pass/fail → `complete` → report mounts → writes the result THROUGH the chokepoint into `tgdog` (invariants 2+4) → `complete`; `report==terminalStepId` complete → `SessionScope` (the lifecycle owner, D-2) writes `close(sessionId)`. t5 session terminal → `WorkList` unmounts the `WorkBead` → cascade reconciles to `[]` → coordinator dispose (WS disconnect); both launch daemons dispose → `provider.stop` kills each pgid AND `cap.teardown` `pkill`s the detached advertiser by token (local + ssh).

**FAILURE PATH:** central never powers on → coordinator never enters the frontier (positive-terminal-only holds); central's `failed` step routes to supervision (D-5: backoff → re-key → remount; exhaustion → escalate + tear the subtree down so the peripheral + its detached advertiser are killed — never a leaked half-up rig).

**Acceptance:** the full trace passes offline; the failure path escalates+tears down (no leak); invariants 8.1–8.4 hold throughout; the report write is `tgdog`-only.

---

## 10. SAFETY rails (non-negotiable)

- **OFFLINE.** Every track's acceptance runs against **fakes / temp repos / `sh`-stubs** — no live `grid run --tree`, no real `claude`/`git`/`gh`, no live `tg`/`gc`/`bd`, never touch `.beads/hooks/`.
- **Never push / open a PR.** `land`/`butane.report` drive **injected fake** `SourceControl`/`PrOpener` offline; the real arm is the human gate.
- **The first LIVE arm is the human gate** (M3 precedent) — creating real subprocesses / writing real `tgdog` beads / driving real devices is held for Nico, after ratification + green offline conformance.
- **The codec boundary is law** — `rigKey='rig'`, `IssueType.rig`, `type=convergence`, the M2 convergence byte-port schema, `kGridNamespace='grid'` are external contracts; the D-3 cursor change is confined to the_grid-internal `grid.`-namespaced metadata on `tgdog` session beads.
- `melos analyze` clean across all packages; the four invariants are mutation-tested gates before the Burn track is allowed to land.

---

## 11. Deferred — explicit, not dropped

- **Restoration / adopt-a-live-process (ADR-0008 D6):** the `NodeCursor` schema + `CapabilityContext.logFile` + the `_run` adopt branch are **designed as seams** (D-3 carries `logOffset`); only **respawn-or-skip** ships. The bucket-tree → dolt serialization, the byte-offset log re-attach, and the token+freshness adopt guard are a later crash-safety track. The genesis-side extraction is **post-prototype** (passes genesis's own ADR-0000 gate — OQ-8).
- **Dynamic fan-out / `FanOutStep` (OQ-2)** beyond a `declaredBound`; **dynamic resource planning** (plan→reserve→execute) — D8 is bounded-now (D-7).
- **Federation (ADR-0011):** per-station `Grid` views, the pull predicate, claim/resolution, presence/heartbeat/reaping, `Trust` impls, cross-station children as monitors-not-links.
- **Observability (ADR-0012):** observable-source as first-class, OTel ⊥ perception, the AOT exploration transport.
- **Package-name migration:** public `the_grid` / private `grid_engine` / `*_grid_assets` (ADR-0008 D1 deferred) — P1 builds the SDK *surface* behind `lib/src/sdk/`; the split is a follow-on.
- **The M2 convergence-as-subtree** stays reserved (ADR-0007 §5 P3/ADR-0010); invariant 3 keeps it out of the tree at every depth.

---

## 12. Definition of Done

- All 10 tracks' acceptance tests **green, offline**; `melos analyze` clean across all packages.
- The **four invariants** enforced as **mutation-tested** gates AT DEPTH (Track I), including the **N-concurrent-disjoint-key** race gate (the Burn's case P0's 1-wide frontier structurally cannot exercise).
- agent/verify/land prove **no behavior change** (§6, byte-for-byte + the parity-fix mutation test).
- The **Burn** passes end-to-end offline (§9), success and failure paths.
- **D-1 … D-7 ratified** as ADR-0000 amendments (or rejected); **ADR-0002** amended if the SDK surface warrants a row.

---

## 13. Build approach

**Workflow waves 1 → 5**, each **implement → adversarial-verify → fix**. **Wave 1 Track A runs first and alone** (pure value-types + the predicate, zero I/O — the model proven before anything inflates). Track C (the D-1/D-2 chokepoint+mint fixes) is a **foundation gate** — nothing concurrent lands until the race gate is green. **D-5 (supervision) sequences BEFORE the Burn** (the adversarial pass ruled backoff-free respawn not-shippable). The Burn (Track J) is the integration capstone — the deciding spike for where restoration ultimately lives (OQ-8).

> **Terminology:** "done" is **not** a bd status — the terminal *status* is `closed`; here it means a *positive terminal* (the work bead `closed`, or the owned session cursor's terminal step `complete` → `close`). An empty frontier is "done" ONLY when the terminal step completed — an **empty-because-circuit-broken** frontier is an escalation, never "done" (D-5).