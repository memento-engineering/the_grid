# ADR-0008 — the authoring SDK, assets, and the reentrant engine (the_grid beyond P0)

**Status:** **Accepted 2026-06-27** (ratified by Nico; drafted by AI per Nico's decisions in the 2026-06-27 design session, per the ADR-0000 register rule). This ADR **supersedes ADR-0007 Decision 1's type *names*** (Decision 1 below) and **extends ADR-0002 Decision 1's package topology** (Decision 2). The forward-pointer stamps were **applied on ratification (2026-06-27)** to **ADR-0007 D1** + **ADR-0002 Decision 1** (one-line amendments) and **`the_grid/CLAUDE.md`** — never a silent rewrite (the A33 / ADR-0007 precedent). Per the gate: doc before code — code may now proceed on this ADR's single-station cluster (the Station/Substation rename is the first migration). **D1 rename APPLIED in code 2026-06-27** (whole-repo type + machinery + lowercase-vocab + CLI-flag rename; `melos analyze` + offline suite green; the persisted gc `metadata.rig` key + convergence byte-port schema preserved across the codec boundary; package-name renames `the_grid`/private `grid_engine`/`*_grid_assets` deferred to a later task).
**Date:** 2026-06-27
**Deciders:** Nico Spencer (decided each call in the design session; ratifier). Drafted by AI per the ADR-0000 register rule.
**Gates:** the M4 follow-on (the SDK / "build everything" authoring layer). Fulfils the scope ADR-0007 §5 reserved as **P1/ADR-0008 ("gc-TOML import")** — generalised from "import gc TOML" to the full **asset (pack-protocol) authoring model**, of which TOML configs are one half.
**Source of record:** `docs/SCRATCH-vnext-prd.md` §§0.5–4, §9 (the design surface; this ADR promotes its converged decisions and states the load-bearing ones).
**Supersedes (explicit, per the register rule — never silent):** **ADR-0007 Decision 1's type *names*** — the root `Grid`/`RigScope`/`Rig` tree is renamed (Decision 1 below); "Grid" is repurposed for the federation object. ADR-0007's reconcile *semantics* are unchanged and extended, not reversed.

---

## Context

ADR-0007 made `genesis_tree` the engine: `build(observed)` is the running system; mount = spawn, unmount = kill, phase = a reconcile transition. That settled the **P0 single-bead** dispatch core.

A 2026-06-27 design session (triggered by the original `EffectContext`-carries-git smell, then the `butane_flutter` BLE-`Burn` use case) pushed past P0 to the question ADR-0007 deferred: **how does anyone — `the_grid` itself, lenny, butane — author work for the grid without forking the engine?** The hard case throughout was the **`Burn`**: not one subprocess but *deploy two harnesses on two machines → barrier → drive a coordinator over WebSocket/mDNS → report → guaranteed teardown on every host*, with runs lasting **days**.

The session converged on a single architectural thesis that this ADR ratifies:

> **The engine is a small reconcile core that knows a handful of abstract domains in *concept*, never in *detail*. Every domain's *detail* — source control, trust, transport, and the work itself — ships as a pluggable implementation in an *asset*.** The engine carries no domain detail, only seams.

This generalises ADR-0007's domain-free engine + the original "EffectContext carries no capability collaborators" instinct all the way: the core reconciles; everything else is mounted into it.

This ADR decides the **single-station authoring + engine-extension cluster** (the build target). It deliberately does **not** decide **federation** (the multi-station story — `docs/SCRATCH-vnext-prd.md` §§5–7, §9 impls) or **observability** (§8); those graduate to their own ADRs whose **numbers Nico assigns** (they do not cleanly fit ADR-0007 §5's tentatively-reserved P2/P3). Where state restoration (Decision 6) ultimately *lives* is a genesis-side decision, deferred.

---

## Decision 1 — Nomenclature: `Station` / `Substation` / `Asset`; `Grid` repurposed (supersedes ADR-0007 D1 names)

The "full power grid" rename. Canonical:

| Term | Means | Replaces (ADR-0007 D1) |
|---|---|---|
| **`Grid`** | the **federation as a whole** — per-station, emergent, no center (git-style). A **new** first-class object: each station's local view of the federation. (Federation detail = a later ADR.) | (was: the singular system / the root Seed) |
| **`Station`** | the **machine** — one runtime, one reconcile loop, one capacity budget, one conductor. | the root **`Grid`** Seed (`Grid`(MultiChildSeed) → `Station`) |
| **`Substation`** | the **project** — an ownership + capability partition of work. Local if hosted, **virtual** if remote-owned. | **`Rig`** (`RigScope`→`SubstationScope`, `Rig`→`Substation`, `RigConfig`→`SubstationConfig`) |
| **`Asset`** | an implementation of the **(gc) pack protocol** — a mountable bundle (formulas + capabilities + services + infra) that energises a substation. the_grid's native analogue to `.gascity-pack/`. | (new) |

**Why:** the metaphor is coherent (a grid interconnects stations; substations are local distribution partitions; assets are the equipment you install) and it makes room for the federation object. ADR-0007's reconcile semantics (keyed `MultiChild`, `InheritedSeed` ancestors, observational flush isolation, `root.markNeedsRebuild` banned) are **unchanged** — only the type names move. This is a code-blast-radius migration, not a re-architecture.

---

## Decision 2 — The SDK boundary: public `the_grid`, private `grid_engine`; assets are `*_grid_assets` packs

- **Public authoring surface = a package named `the_grid`** (consumers list `the_grid:` in pubspec; `grid_sdk` is the fallback name; `grid` is squatted on pub.dev). `grid_engine` stays the **private** element layer — consumers never import it or its sealed Seeds.
- **An asset is a Dart package named `*_grid_assets`** (the pack pattern), the home for the gc-pack-protocol implementation (ADR-0007's reserved P1 scope). Reference assets:
  - **`station_grid_assets`** (the_grid's own dogfood + baseline; replaces the placeholder `the_rig`) — `SourceControl` (git impl) + the default **landing formula** + typical station operations that don't belong in the engine.
  - **`butane_grid_assets`** — the `Burn` formula, energised by a butane substation.
  - **`zero_conf_grid_assets`** — mountable mDNS-federation infra (a later-ADR concern, named here for the pattern).
  - (`leonard_grid_assets`, per the pattern, for lenny.)
- **Consumers compose, never subclass** engine Seeds — mirrors how `leonard` consumes genesis's surface, never `Branch`; protects the ADR-0007 §7 derailment-invariants by construction.

**Why:** `butane_flutter` is already a gascity rig (its committed `.gascity-pack/`); `butane_grid_assets` is the the_grid-native successor. A different-repo consumer structurally **cannot** subclass the engine's element tree without coupling to internals and inheriting every derailment footgun.

**Amended 2026-06-29 (ratified Nico, ADR-0011) — `Asset` becomes an UMBRELLA with two families:** the *content/capability* assets defined here (the `*_grid_assets` packs) **plus** a new *resource/capacity* family (leasable compute / agent slots / humans-via-HITL). "Asset Management" is the discipline over both; federation leases the resource family. This **extends — does not rename** — the `Asset` defined below. See **ADR-0011** (Federation + Asset Management).

**Amended 2026-06-28 (ratified Nico) — the asset taxonomy refines; `grid_assets` is the baseline; `power_station` is the assets repo; assets follow the Dart "Packaged AI Assets" format.**

- **`grid_assets`** is the **default, bare-bones baseline pack** — industry-standard operations (git `SourceControl` + a bare goal-oriented SDLC loop). It **supersedes the `station_grid_assets` name** above: grid assets live at **any turtle/level** of the system (not just a station), and it follows the `grid_*` pattern. (`butane_grid_assets` / `zero_conf_grid_assets` / `leonard_grid_assets` are unchanged.)
- **`power_station`** is a **new memento.engineering repo** for grid assets — it houses **"The Circuit"** (Decision 9, the SDLC coding-workflow system; the factoryskills-reborn pack) plus the language/framework packs (`dart_grid_assets` / `flutter_grid_assets` / `zero_conf_grid_assets`) and grid utilities without their own project (genesis / butane / lenny have theirs). Open-source baseline + closed-source assets ("keep the lights on"). **`grid_assets` first lives IN the_grid repo** (decided 2026-06-28) — all grid-asset code stays in the_grid for now; split-and-extract to `power_station` later, at stabilization.
- **Substation-linking is a `dart_grid_assets` capability** (forward note, Nico 2026-06-28): co-developing two substations (e.g. the_grid + `genesis_tree`) needs pubspec `dependency_overrides` path-linking between them — a **dart grid capability** should own that linking, generalizing the manual path-override↔published-dep dance (the ADR-0008 D5 "published-deps build policy" corollary). Not in The Circuit's verify-first scope; recorded for `dart_grid_assets`.
- **Asset authoring format = the Dart/Flutter "Packaged AI Assets" proposal** (`flutter.dev/go/packaged-ai-assets`, Jake MacDonald; status: implementation starting). Assets expose prompts/resources via **`extension/mcp/config.yaml`** (the `package:extension_discovery` format): files on disk, **mustache-templated** prompt args, **`visibility: public|private`** (our open/closed split), and **AI-only packages with no Dart code** explicitly blessed; consumed via the Dart MCP server. We adopt it as a **forward-looking spec** — our systems use it now and can pivot if the community standardizes on it. It dovetails with the_grid's `extension/` convention and the "extension, never plugin" rule. **Dart-first** for the dynamic half (formulas + capabilities at the existing seam); the TOML `PackInflater` is deferred (Decision 3's "TOML *or* Dart" — TOML is the lower-priority serialization).

*(The SDK package name — public `the_grid` / fallback `grid_sdk` — is unchanged by this amendment.)*

---

## Decision 3 — The authoring vocabulary: Formula · Capability · Service · Asset

| Noun | Is | Example |
|---|---|---|
| **Formula** | a **value-typed declared step-graph** (the reentrant unit the engine inflates into a subtree, Decision 4). "Energised" = mounted under a substation. | `Burn`; the default landing formula |
| **Capability** | the **opaque Dart leaf** a formula step invokes (the spawn / drive body). Sandboxed to a narrow interface — no `TreeContext`, no detection pipeline, no `markNeedsRebuild`. | "spawn a claude agent"; "drive the coordinator" |
| **Service** | a **pluggable collaborator interface** a formula/capability depends on. | `SourceControl` (git impl) |
| **Asset** | the `*_grid_assets` pack shipping the above + infra. | `butane_grid_assets` |

- **Configurations are value types** (`Substation` / `Formula` / `Order`), authored in **TOML *or* Dart** — two serializations of one freezed shape. (TOML satisfies the reserved gc-pack-import scope.)
- **Dynamic behaviour is Dart** (a `Burn`), against the narrow `Capability` interface. Like Flutter: data for static config, Dart for dynamic widgets.

**Why:** this is the original `EffectContext`-git resolution, generalised: git was never "a collaborator bolted to land" — it is a **`Service`** the landing formula depends on, shipped in an asset. The engine carries the seam, the asset carries the impl.

---

## Decision 4 — The engine is reentrant/recursive (turtles)

A capability is **not** an opaque self-orchestrating leaf — it **declares a step-graph the engine reconciles**, the same machinery at every depth. The author writes composition-of-value-types + opaque Dart leaves (never a Seed) and inherits fan-out / barrier / keyed-reconcile / guaranteed-teardown / crash-recovery **for free and uniformly**.

```
Station → Substation → WorkList → WorkBead → effect          (top level)
Burn → [HarnessA, HarnessB] → Barrier → Coordinator → finally(teardown)   (a formula subtree)
```

`agent` / `verify` / `land` are the degenerate **single-step** formulas.

**Commitment:** the ADR-0007 §7 derailment-invariants must hold **at depth** — guaranteed because the author only ever touches the declarative builder + opaque leaves, never raw Seeds. OTP framing: a formula step is a `gen_server`-like behaviour (`init`/`handle_*`/`terminate`); `terminate` *is* the guaranteed teardown; cross-station children are **monitors, not links**.

**Amended 2026-06-27 (M4-P1 build-order, ratified Nico) — the session model + inflation discipline:**
- **(D-2) session establishment is an engine-private `SessionScope`** (Nico's design), mounted by `WorkBead` ABOVE the formula subtree: it **adopt-or-mints** the session bead through the chokepoint, holds `{resolving | ready(SessionHandle) | failed}`, and provides `InheritedSeed<SessionHandle>` so the formula subtree attaches **only once the session is resolved** (the async establishment is a tree *state*, not a synchronous inject — the Page:Route abstraction, intuition not a rename). It owns the session lifecycle **end-to-end** (open AND close — on the formula's positive terminal or breaker-exhaustion). Per-step provider name `'$sessionId/$nodePath/$stepId'`. **Supersedes P0's first-leaf-mint + `EffectSeed` name=id** (which double-mint the restoration root + collapse fan-out to one process). Restoration's adopt-or-mint falls out of the same `resolving → ready` path. Engine-private (no author-facing "session capability" until a need arises).
- **(D-6) inflation discipline:** ambient providers (`ServiceBundle` / `CapabilityRegistry` / `DartEnvironment` / `InheritedSeed<SessionHandle>`) are **stable** (`updateShouldNotify => false`); formula child Seeds are built **fresh each build** (no identical-skip caching — genesis skip is identity-only, so a value-equality cache would skip a subtree across a real cursor change and stall the barrier).

---

## Decision 5 — Pluggable abstract domains: the engine knows concept, not detail

The engine depends on a small set of **abstract domains** via seams, never their implementations:

- **`SourceControl`** (git, jj, …) — Decision 3.
- **`Trust`** (local / reputation / ledger) — the admission-gate decision ("do I believe this result/peer enough to admit it?"); impls plug in (`docs/SCRATCH-vnext-prd.md` §9). Distinct from **`consent`** (`genesis_consent`, *authorization* — "may this actor act?"). Trust's interface home (the_grid vs a genesis-shared abstraction) is open.
- **The exploration transport binding** (HTTP/WS now; gRPC/MCP later) — sits *below* `perception` + `genesis_consent`, so it is a swappable binding (observability ADR).
- **The capabilities/formulas themselves** — Decision 3.

**Why:** this is what lets a tinkerer run local-trust-on-a-LAN while an enterprise plugs in a ledger, from the same engine. "Less blockchain" stops being a core-vs-not tension and becomes *which impl you mount*. The engine stays domain-free; extensibility lives entirely at the edge.

**Amended 2026-06-28 (ratified Nico) — `SourceControl` is a SUBSTATION responsibility; the station provides shared execution machinery the substation *leases*.** A project dictates its own source control: repo/root, remote, the assigned **head/base branch**, branch-naming, land-vs-commit-only, and *which VCS* (git, jj, …). So the seam is owned **per-substation**, not per-station. Two layers, previously conflated in `StationGitService`:

- **Execution machinery** — the project-agnostic thing that *runs* `git`/`gh` (the runner). The **station** owns it (shared); substations **lease** it.
- **Policy + config + impl** — root checkout, remote, assigned head, land policy, the concrete `SourceControl`. The **substation** owns it (its asset supplies the impl).

**In the tree:** `SourceControl` (the `ServiceBundle`) is provided **per-`SubstationScope`** — a `WorkBead`'s `CapabilityHost` resolves the *nearest* one (its substation's) via genesis's nearest-ancestor inherited lookup — **not** once at the station root (the P0 shape, now a wrong default for a multi-substation station). The engine still sees only the abstract `SourceControl` (concept, not detail — this Decision); the git-specific config (root/head/remote/land) lives in the **composition/asset layer**, never the engine.

**Corollaries:**
- **"Assign heads"** — each substation declares the base branch (head) its worktrees fork from; no `origin/HEAD` guess (which would silently cut from `main`). "Stacks of work" (a sequence of dependent heads) layers on later; per-substation head-assignment is the floor.
- **Published-deps build policy** — a substation's checkout resolves dependencies from the registry *unless* it is actively developing that dep, so a the_grid worktree builds against published `genesis_tree` rather than the local dev path override.

*Implementation note:* the P0/M4-P1 code provides the `ServiceBundle` at the station root (`StationKernel.mountRoot`); the per-`SubstationScope` re-homing is the pending refactor executing this amendment.

---

## Decision 6 — State restoration is the crash-recovery model (Flutter-modeled)

Crash-recovery is modeled on Flutter's state-restoration framework. the_grid is already half a restoration framework — `build(observed)` rebuilds the tree from the bd snapshot; restoration adds the missing half (Flutter's `RestorableProperty`): the minimal per-node durable state that **cannot** be re-derived. A40's "session bead carries pgid/token/cursor" was a hand-rolled `RestorationBucket` for one node; restoration generalises it into a bucket-tree mirroring the reconcile tree, serialized to the dolt state store (tgdog, A37).

- **Adopt is the floor, not the reach.** the_grid spawns **detached** processes that *survive* the controller (unlike Flutter, where the app died). On restart, restore the handle → `kill -0` + token match → **adopt** (re-open the worktree log at the restored byte-offset, keep observing); dead + done-marker → finished; dead + no marker → respawn-or-skip; ambiguous → freshness barrier + token decide.
- **Two requirements restoration imposes:** (1) detached processes write output to a **worktree log file**, not just a pipe (the pipe dies with the controller; the restored byte-offset re-attaches to a survivor's output); (2) an **identity/liveness guard** (token + freshness barrier) Flutter doesn't need, because a restored pgid could be a recycled pid / prior-incarnation orphan.
- **Discipline:** restore ONLY non-derivable external handles; everything derivable re-observes from bd. the_grid holds **no important state in memory** — it is all re-observed (bd) or restored (bucket).
- **Home (deferred):** the mechanism is domain-free tree machinery and belongs in the **genesis project** (`genesis_tree` or a sibling) like Flutter puts restoration in the framework. Path: **prototype the_grid-local against the `Burn`** (hardest case), prove the shape, then upstream via genesis's own ADR-0000 gate.

**Amended 2026-06-28 (ratified Nico) — the bucket-tree is scoped THREE ways in ONE per-station store, and is CURSOR-ONLY-DURABLE.** Generalising A40's single-node bucket to the multi-substation station (the_grid-as-substation), pressure-tested by a 3-design → judge → 2-adversarial-refuter design pass:

- **One per-station store** (tgdog, A37) — NOT a DB per substation. The bucket-*tree* gives the scoping: `station.*` ⊃ `substation.{id}.*` ⊃ `session.{workBead}.*`, mirroring `Station → Substation → WorkBead`.
- **Cursor-only-durable (Flutter's rule, taken strictly):** persist ONLY the non-derivable state — the per-node cursor + the pgid/pid/token restart fence. **Completion, escalation, and "is-this-formula-done" are DERIVED from the cursor on restart, never separately persisted.** A separate completion/escalation/restoration bucket is redundant durable state to keep consistent (two adversarial reviewers independently flagged it as a corruption surface). Everything else — live process handle, heartbeat/presence, permits — is the **ephemeral "wisp" layer**: in-memory, re-observed/re-derived, never persisted.
- **Forward-safe key prefix:** put the station id in the durable key namespace so two stations sharing the tgdog dolt server never collide on `grid.cursor.{nodePath}` (a federation pre-req, ADR-0011).
- **Enforce the split, don't just name it:** the durable/ephemeral boundary wants a type/structure barrier (a `Durable<T>` or a structural test), not a naming convention — else an ephemeral handle gets accidentally persisted.
- **Discipline (carried):** step-ids must be **dot-free** (the flat-key `lastIndexOf('.')` parse), and `StationBeadWriter.createSession`'s create-then-rig-stamp must become atomic/recoverable — a crash between the `bd create` and the rig-stamp currently orphans an unstamped session (a **banked follow-up bug**).

**Sequencing:** this is a CRASH-RECOVERY + MULTI-SUBSTATION robustness track. The FIRST live arm (one station, one substation, happy path, no crash, no federation) does **not** need it — it runs on the existing single-session model. This amendment is the design of record for when that track is built.

---

## Decision 7 — Supervision strategy + failure escalation (the circuit-breaker)

- **Per-formula supervision strategy**, author-declared: `one_for_one` default; `Burn` wants `rest_for_one` (central dies → restart it + the coordinator, not the peripheral). **Backoff** mandatory — spawns cost minutes + tokens (OTP's cheap-process economics inverted).
- **The circuit-breaker** (created by reentrant + restoration): a permanently-failing formula would re-mount forever (ready+owned → mount → crash → respawn → exhaust → session terminal, but the foreign work bead stays *ready* → re-mount loop). So:
  - the **restart count / cooldown is restorable state** (Decision 6) — survives controller restarts, so the breaker actually trips.
  - the **mount predicate reads it**: `ready ∧ owned ∧ ¬circuit-broken → mount`.
  - **scope = per-(station × work)** — a crash here trips *my* attempts; a peer with different env/capacity may still try ("decline, don't poison").
  - **exhaustion escalates to a human/operator** — a signal written to the_grid's **own** store. In a foreign-work-source world the_grid cannot mark the work dead, and silent-stop-trying is the worst failure mode. OTP "escalate to the parent," where the parent is the operator.

**Amended 2026-06-27 (M4-P1 build-order, ratified Nico) — D-5:** supervision + the restorable circuit-breaker **sequence BEFORE the Burn acceptance** (backoff-free immediate respawn is not shippable: a circuit-broken step yields an empty frontier *indistinguishable* from "formula complete" → silent forever-mount + leaked daemons + no escalation). The **failing leaf host's own `_onComplete`** is the named `restartCount`/`cooldownUntil` writer (no supervisor node → derailment-invariant 1 preserved); **`SessionScope` (D-2) closes/escalates** on exhaustion, distinguishing empty-because-broken from empty-because-complete at the source.

---

## Decision 8 — Resource governance (declare-and-check, bounded now)

- **`DartEnvironment extends InheritedSeed` = ambient config** (SDK path, pub cache, **and capacity**); it provides a live **governor** (semaphore). The **actuator** is a separate `DartProcess` leaf that resolves the environment, **acquires a permit**, then spawns. (Naming: an *environment* provides config; an *effect* actuates — not an "extension.")
- **state vs reason:** closed **state** = position in the system (exhaustively switchable); open **reason/condition** = why (observability). `awaiting-capacity` is a *reason*, not a new state (k8s phase-vs-conditions).
- **Two admission gates:** capacity gates what you **start** (intake); verification/trust gates what you **publish** (output).
- **Declaration (asset) vs capacity (station owner):** a formula declares requirements; the station owner configures machine capacities.
- **Capacity gates at two boundaries:** the *claim* (saturated → decline, federation concern) and the *leaf* (transient shortage → block, never un-claim).
- **Only leaf process-effects acquire permits** (orchestration nodes hold nothing → no parent-holds-while-child-waits deadlock).
- **A formula declares its peak aggregate requirement, checked at claim time** — never claim what the station can't fully satisfy → barrier-starvation impossible by construction. Requires the resource shape be statically inspectable (forbids unbounded dynamic permit-fan-out without a declared bound).
- **Crash-safe:** permits are in-memory, re-acquired on restart from observed running state (derived, never persisted).
- **FUTURE — dynamic planning:** a formula plans its requirement at runtime (e.g. one harness per discovered device) via **plan → reserve → execute** (the reservation, not a static declaration, becomes the deadlock guard). Start static; grow to planned.

**Amended 2026-06-27 (M4-P1 build-order, ratified Nico) — D-7:** for the P1 build, ship **`ResourceRequest` as a declared, statically-inspectable value-type field only** (on `Formula`/`CapabilityStep`); the `DartEnvironment` governor + leaf-permit acquisition are a **separate, optional track NOT in the P1 spine** (the Burn does not block on it). The declare-and-check / dynamic-planning model above is otherwise unchanged.

---

## Decision 9 — "The Circuit": the SDLC workflow + gates AND flares (verify-first)

**Decided 2026-06-28 (ratified Nico; the engine-design specifics are PROPOSED in the M5 "The Circuit" build-order, pending ratification — the M4-P1 build-order→ADR-stamp precedent).**

**The Circuit** is the_grid's SDLC coding-workflow system — factoryskills reborn, grid-themed (work flows a *circuit* of stages: **discovery → spec → review → build → review → land**). It ships as an **asset** (Decision 2/3), not engine code. Its crown jewel is the **adversarial committee**: one critic per rubric, graded **in isolation** (anti-anchoring — a critic reads only its own rubric), fanned out in parallel, then a **route** step aggregates verdicts via a deterministic matrix. This maps onto the reentrant engine (Decision 4) almost 1:1 — a committee is a **fan-out sub-formula + a join `route` step** — reusing the proven fan-out/barrier machinery, with two deltas the_grid owns: factoryskills' cadence **orders** are replaced by **reactive reconcile** (the kernel flush *is* the loop), and the work source stays **read-only** (A37) so grades/lifecycle are per-node `grid.cursor.*` / `grid.result.*` writes on the_grid's OWN session bead, never the foreign work bead.

Ratified shape:
- **Verify-first.** The **code-committee** (the post-build review: `code-validation` [gating, runs the bead's OWN Validation Plan], spec-adherence, regression-risk, test-coverage) ships first — the self-contained, highest-value upgrade that replaces the placeholder `melos test` verify. The **spec front-half** (discover/architect) and the **spec-committee** (the first review point) are **phase 2**.
- **Gates AND flares are TWO distinct primitives** (not synonyms):
  - a **gate** = a **blocking** human checkpoint — parks the formula subtree and waits for an external resolve (generalizes Decision 7's supervision escalation). For `route`'s `block` / human-ultimatum outcomes. A gate **functionally blocks via a `type=gate` bead in the_grid's OWN store (tgdog) against its own session bead — it NEVER mutates the foreign, read-only work bead's state (A37)**; the mount predicate honors `¬gated` and the operator resolves the gate to route back.
  - a **flare** = a **non-blocking** signal emitted at a transition (fire-and-continue) to the observability/exploration sink (the ADR-0012 hook). A flare-as-gate would wrongly halt the loop.
- **The engine stays opinion-free** (Decision 5 / the ADR-0007 §1 invariant): the committee, critics, rubrics, route-matrix, and the agent/verify/land opinions move OUT of `grid_engine` into `grid_assets`. The **one** engine change is a narrow, read-only **sibling-read** seam (a `ServiceCapability` route step reads its siblings' already-observed results — no new pipeline subscription, no write; the four derailment invariants hold). All else composes at the existing `CapabilityRegistry` / `FormulaResolver` / `ServiceBundle` seam (dart-first).

**Detail + the lettered design decisions (D-1…D-10) + tracks + DoD:** the **M5 "The Circuit" build-order** (`docs/M5-THE-CIRCUIT-BUILD-ORDER.md`). On ratification its lettered decisions stamp back here (the D-2/D-4/D-5/D-7 amendment pattern). The first live arm (the_grid building itself through The Circuit) remains the human gate.

---

## Consequences

**Positive.**
- The engine becomes genuinely domain-free and infinitely extensible at the edge — one core, many assets, three reference consumers (`station`/`leonard`/`butane`).
- Crash-safety for **days-long** runs is principled (restoration), not bolted on; adopt-a-surviving-process is the floor.
- The "less blockchain" debate dissolves into a pluggable `Trust` domain.
- The reentrant engine reuses ADR-0007's reconcile machinery at every depth — no second orchestration mechanism to build or debug.

**Negative / cost.**
- The Station/Substation rename is real churn across `grid_engine` and the P0 code (the root Seed + the `Rig*` triad + `RigConfig`).
- Reentrancy commits the engine to holding the derailment-invariants at depth (more surface, structurally guarded).
- Declare-and-check resource bounds add author ceremony and forbid unbounded dynamic fan-out until dynamic planning lands.

**Neutral.**
- State restoration's eventual genesis home is deferred; the the_grid-local prototype is the deciding spike.

---

## Open questions (deferred — do not block the first build)

- ~~Is "worktree layout" universal enough to stay in core `EffectContext`?~~ **RESOLVED (Nico, 2026-06-27, M4-P1):** stays core, and **renamed `worktree` → `workspace`** at the engine/context level — a git worktree is the git `SourceControl` impl *provisioning* a workspace; a remote Burn harness has a workspace, no git worktree. `workspace` = the stable home + restoration anchor; cwd defaults to it, overridable per-spawn; **no separate `pwd` cursor**.
- ~~The `Trust` *interface* home — the_grid vs a genesis-shared abstraction.~~ **RESOLVED (Nico, 2026-06-27):** lives in **the_grid (`grid_engine`)** for now — no extraction planned, but designed to be lifted (a clean, dependency-free interface so a later genesis-shared home is a move, not a rewrite).
- The genesis home for the restoration mechanism (`genesis_tree` vs sibling) — decided after the the_grid-local prototype.

---

## Out of scope (later ADRs — numbers are Nico's to assign vs ADR-0007 §5's P2/P3 reservations)

**Amended 2026-07-01 (ratified Nico) — ADR-0007 §5's reserved P2/0009 is now FILLED:**
**ADR-0009 (the Allocation Tree)** occupies it — the_grid's *third tree* on `genesis_tree`. It
**extends this ADR's Decision 6** (state restoration): adopt-a-surviving-detached-process becomes
the Allocation lifecycle's **`startOrAdopt` (reattach) + `detach`** branch. Observability (§8)
still graduates separately (**ADR-0012**); federation stays as below.

- **Federation** — `Station`/`Substation`/virtual, the per-station no-center `Grid`, the pull predicate, dolt + the inter-station bus, claim mechanics, presence/reaping, and the `Trust` *impls* (`docs/SCRATCH-vnext-prd.md` §§5–7, §9).
- **Observability** — observable-source as a first-class engine concept, OTel ⊥ perception (both sinks on the reconcile-event stream), the AOT exploration transport (`docs/SCRATCH-vnext-prd.md` §8).
- **The genesis-side restoration extraction** — genesis's own ADR-0000 gate, post-prototype.
