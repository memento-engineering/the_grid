# GLOSSARY — the grid, its components, and its flows

**Status: descriptive index, NOT a ratified doc.** Authored by Fable (2026-07-04) as the
opening artifact of the docs pass, from an 8-surface research sweep (all ADRs, PDR +
milestone build orders, all SCRATCH surfaces, the code surfaces of all four repos, and the
org seams) plus a conflict audit and a completeness critique. **Corrected 2026-07-05 per
Nico's review** — rulings R1–R17 in `docs/SCRATCH-docs-debt-sweep.md` (retired to git history —
tg-8gv.8) §1, which also carries the detailed drift analysis this index only summarizes (folded
into `docs/OPERATIONS.md` §4 at the public-readiness pass, 2026-07-20). It records **the system as it
is** — including where docs and code disagree. Nothing here ratifies anything; where a term
is contested, §12 says so instead of smoothing it over.

Scope: `the_grid`, `power_station`, `space_station`, `tgdog` (retired 2026-07-08 —
`SUBSTATION-INIT.md` §4), plus the genesis/lenny seams the_grid touches. Each entry carries a **status tag**:

- `ratified` — defined in an Accepted ADR or a Nico-ratified surface, and code agrees
- `proposed` — designed/written but not ratified, or ratified but not yet built
- `superseded` — explicitly replaced; kept for reading older docs
- `legacy-residue` — old vocabulary still visible in prose/symbols after a ratified rename
- `code-only` — exists and is load-bearing in code but defined in no doc
- `conflicted` — two live, incompatible meanings; see §12

---

## 1. The org in one breath

> Apps are built in Flutter. Lenny drives and debugs the apps. Lenny files bugs as beads
> into the grid. **The grid builds everything.**

| Repo | Role |
|---|---|
| `genesis` | The substrate: `Seed`→`Branch` keyed-reconcile engine (Flutter's element model as pure Dart) + tree/tmux/perception/consent/typesetting/taxonomy/dialogue |
| `the_grid` | The orchestrator: observes bead stores, mounts work as a reconciled tree, spawns a coding agent per ready bead, lands the result |
| `power_station` | The asset packs: the code circuit, committee, landing, agent harnesses, compute/lease, federation, zero-conf |
| `space_station` | The composed station runner: the `space` binary and its resident-station verbs |
| `tgdog` | **Retired** — archived read-only as `archive-tgdog-20260708` (`SUBSTATION-INIT.md` §4). The former separate state DB; the A37 split lives on, with the state store now the grid home's own `.grid/.beads/` (prefix `houston`) |
| `lenny` (external) | The **org's** debugging arm — a genesis sibling, not a grid component: attaches to a running Dart VM over `ext.exploration.*`. The grid and lenny share genesis patterns but deliberately avoid coupling to each other (R1) |

---

## 2. The core model (the machine and its partitions)

**Station** `ratified · ADR-0008 D1` — The machine: one runtime, one reconcile loop, one
capacity budget, one conductor. The root Seed of the running tree. Renamed from the old
root-`Grid` Seed (ADR-0007); applied in code whole-repo 2026-06-27.

**Substation** `ratified · ADR-0008 D1` — The project: an ownership + capability partition
of work, local if hosted here, remote if owned elsewhere. Renames the old **Rig**
vocabulary (classes, flags, prose). Substation↔repo is **1:N** (D-M1 as amended): one
substation's work may span several repos via named roots.

**Grid** `ratified · ADR-0008 D1, ADR-0011; widened R2` — **A deployment / an instance**
of the system: one station or many. Federated, it is each station's own view of the
others — per-station and centerless (git-style); unfederated, a single-station deployment
is still "a grid." The running machine itself is a Station; "the grid" as ADR-0007's
singular root Seed is the superseded meaning. As a proper noun, **"the grid"** names the
framework as a concept (R9: "I'm running the grid"); **`grid_sdk`** is the framework as
concrete code.

**Rig** `superseded · ADR-0008 D1` — Old name for Substation. Two deliberate survivals that
are **law, not residue**: the persisted gc codec key stays `metadata.rig`
(`StationBeadWriter.rigKey = 'rig'`), and gc's convergence byte-port schema + bd's
`IssueType.rig` are unchanged — only the_grid's own vocabulary moved. (Prose residue in
engine doc-comments is a separate cleanup item — §12.)

**Asset** `ratified · ADR-0008 D2, ADR-0011 D2; widened R3` — Broadly: **any component of
the system** — stations, substations, circuits, capabilities, scopes, nodes, and a node's
own assets (Nico's working usage). The formal ADR taxonomy is a subset of this: the
mountable pack (circuits + capabilities + services + infra; the_grid's form of the gc
pack protocol), widened by ADR-0011 into **content/capability assets** (the
`*_grid_assets` packs) and **resource/capacity assets** (leasable compute, agent slots,
humans via HITL — including remote stations observed as assets, R10). **Asset
Management** is the discipline over the portfolio.

**`*_grid_assets`** `ratified · ADR-0008 D1` — The pack naming convention. On disk today
(all in `power_station/packages/`): `grid_assets` (the station baseline: code circuit,
committee, landing, agent scope, compute/lease), `dart_grid_assets` (Dart toolchain),
`federated_grid_assets` (broker/claim/lease/serve), `zero_conf_grid_assets` (mDNS
membership).

**Work source vs state store (the A37 split)** `ratified · ADR-0000 A36/A37; model R-2026-07-05` —
**One store per station; one store per substation.** A station writes its
session/lifecycle beads to its own single state store (the grid home's nested
`.grid/.beads/`, prefix `houston`; the former separate `tgdog` DB is retired —
`SUBSTATION-INIT.md` §§3–4) and reads work from one
store per owned substation (today's lived shape is one substation → one work store,
`tg`; the N-substation union from tg-nsj is built, its arms deferred). A foreign work
source is never written; a live run refuses to default sessions into a read store
(fail-closed guard). This is why the cursor lives on the_grid's **own session bead**,
never on a foreign work bead (A40-corrected).

**Workspace** `superseded-in-direction · R4` — A `.beads/` root a station reads,
currently registered as its own flag axis (`--workspace <substation>=<path>`). Ruled
redundant: a **substation registration should carry its store path** — "workspace" as a
separate term/axis dissolves in the config redesign. Still distinct from a *root* (a git
checkout) and a *worktree* (a per-bead checkout).

**Root / named root** `ratified · tg-7gm` — A registered git checkout worktrees are cut
from: `--root <name>=<path>[@head]`. A bead opts into a non-default root via
`metadata.grid.root`; its worktree lands at `<root>/.grid/worktrees/<root-name>/<bead>`.
An owned ready bead whose selected root isn't registered is a **loud per-bead skip** at the
mount boundary, never a station-wide refusal.

**Worktree** `ratified · ADR-0006` — The per-bead isolated checkout, branch
`grid/<bead-id>` (the branch name is *derived* from the bead id; branch names never appear
in bead data). The agent works here; the landing circuit lands from here.

**Resident station** `ratified · D-R4; qualifier retired R5` — **The only operating model**
(`grid run` is deleted): a station stays up and treats **the ready frontier of its owned
substations as the drive set** (D-R4). No `--bead` drive-list exists — you bless work by
making it ready in the store. Foreground-resident by design; the supervisor (launchd)
owns backgrounding. "Resident" stops being special vocabulary — a station simply *is*
this.

**Station lock** `ratified · RS-2` — The one-supervisor-per-state-store guard:
`<state-store>/.grid/station.lock`, mode 0600, holding
`{pid, pgid, startedAt, controlUrl, token}`. The control token lives **only** here — never
argv, never env. Stale detection is a `kill -0` liveness probe; a dead holder's lock is
loudly stolen. Flow in §13-F10.

**defaultSubstation / `substations.first`** `ruled out · R14` — "Not a concept that
should exist" (Nico, 2026-07-05). The ambient "first owned substation" currently keys the
implicit store, the default root, the state-substation fallback, and space_station's
ServiceBundle map — positional privilege plus substation-ids and root-names sharing a
namespace. Dies in the config redesign (`docs/CONFIG-MODEL.md`).

---

## 3. The tree engine

**genesis_tree / Seed / Branch** `ratified · ADR-0007` — The substrate: `Seed` (immutable
config, like a Widget) → `Branch` (live identity, like an Element), reconciled by key.
`build(observed)` *is* the running system: keyed reconcile + Branch lifecycle = the work
lifecycle (mount=spawn, unmount=kill, phase=a reconcile transition).

**The artifact layer / "third tree"** `ratified · genesis README, ADR-0009` —
genesis_tree deliberately stops at Seed→Branch; *what a live identity spawns and owns* is
each consumer's to define. The canonical third trees: genesis_typesetting's render tree,
genesis_perception's observation tree, and the_grid's **Allocation Tree**.

**Allocation / the Allocation Tree** `ratified · ADR-0009` — the_grid's third tree:
persistent, addressable managed objects holding a live effect (process, lease, tmux
session, app) — the RenderObject-analogue. Lifecycle is **four distinct verbs**:
`startOrAdopt` (spawn, or reattach a detached survivor / crash-orphan), `update`,
`dispose` (kill), `detach` (leave running). Update-vs-replace, adoptability, and detach are
per-type (`claude` replaces; tmux updates; a daemon adopts+detaches; a one-shot
respawns-or-skips). Relationships stay **light** (Branch + InheritedSeed + SiblingView).

**The composition primitives** `ratified · genesis_tree` — `TreeContext` (the build/effect
capability handle — never the Branch itself), `TreeOwner` (the scheduler),
`StatelessSeed`/`StatefulSeed`/`State`, `InheritedSeed`, `MultiChildSeed`, first-class
`Key`. The **two-verb lookup story** (ADR-0008 D3): `dependOnInheritedSeed` is the
tree/build verb (subscribes); `getInheritedSeedOfExactType` is the effect verb
(non-binding, loud `StateError` on unmounted). the_grid built `MultiChildSeed` and `Key`
*into* genesis during its own live arm (genesis-7r9, genesis-q8h).

**The tree shape** `ratified · ADR-0007/0008, M4-P1` —
`Station → SubstationScope → WorkList → WorkBead → SessionScope → CircuitScope →
CapabilityHost → Capability`, with config nodes as **ancestors** of work nodes
(Theme-of-context) and effects only at the leaves.

**StationKernel** `ratified · M4-P0` — The opinion-light engine host: owns the microtask
flush loop, mounts the root with ambient `CapabilityRegistry` + `ServiceBundle`s, owns the
circuit-breaker backoff Timer + re-poke. Never calls `root.markNeedsRebuild()` — flush
isolation is observational (only the node observing a changed notifier dirties).

**StationJoinBridge** `ratified · A39, M4-P0` — The **lone pipeline subscription**: joins
the work SnapshotSource(s) + the state source into the observed input the tree builds
from. Everything else reads ambient state from the tree; nothing else subscribes to the
pipeline (derailment invariant 1).

**StationBeadWriter (the chokepoint)** `ratified · A32, M4-P1 D-1` — The **single bd write
locus**. Every mutation goes through it (bd CLI, `--actor grid-controller`), serialized
per target id (the same-key write-race fix). "Only the chokepoint writes" is derailment
invariant 2; the write locus lives in the Host, off-build.

**Mount boundary** `ratified · A40/A41` — The narrowing WorkList applies before a bead
becomes a work node: `IssueType.isCore` **allow-list** (task/bug/feature/chore drive;
epic/milestone/decision are retained but not driveable; fail-closed against custom types),
`type=convergence` excluded (gc's), root-registration check (loud skip), and the
governor's slot budget.

**Derailment invariants** `ratified · M4-P0` — The four mutation-verified guardrails:
(1) no pipeline subscription outside the bridge; (2) only the chokepoint writes beads;
(3) convergence never mounts; (4) the A37 pristine-source split holds. Enforced as
mutation-resistant tests at depth, with live sanity controls against vacuousness.

**The guard principle** `ratified · ADR-0008 (agent-scope updates)` — A guard exists only
if it protects a **named invariant** with a concrete failure story, and it is **LOUD**
when violated. Otherwise it is deleted ("loud or gone"). Killed `StableInheritedSeed`.

**genesis_tree consumption doctrine (D-H)** `ratified · ADR-0008` — Always *watch*
dependencies (never `??=`-cache them); no public sync accessors over reactive state; no
services in branches except DI; **config = values in the tree, impls = DI**.

---

## 4. Work and its lifecycle

**Bead** `ratified · ADR-0001` — One issue in a Dolt-backed `bd` store; the unit of work,
identity, and audit. Everything the grid does is bead-shaped.

**Ready frontier** `ratified · D-R4` — The set of open, unblocked, undeferred, driveable
beads in owned substations. Under a resident station, **ready = blessed = will be driven**.
Consequently the intake discipline is **create deferred → wire deps → undefer** (I-8), so
a bead never surfaces mid-wiring.

**Session** `ratified framing · R7` — **The activation around a bead in the tree**: the
scopes and capabilities that bring the work to life. The **session bead** is the durable,
crash-tracked *record* of one activation, written to the state store: `work_bead`
(re-keyed `<bead>#rN` per rework round), `crash_count`, the spawn fence scalars. The
activation is the thing; the bead is its ledger entry.

**SessionScope** `ratified · M4-P1 Track C` — The Seed that adopt-or-mints the session bead
**once above the fan-out**, provides a stable `SessionHandle`, owns the positive-terminal
close, and escalates breaker exhaustion to a human. A retired (re-keyed) session is
auto-closed and a fresh one minted (the rework mechanic's engine half, tg-zat).

**Cursor** `ratified · M4-P1 D-3` — Per-node progress metadata on the **session bead**,
advanced at completion through the chokepoint. Step events are named
`<sessionId>/<nodePath>`. (The v1 "phase on the work bead" shape was A40-corrected — a
foreign work source is read-only.) *(tg-eli, 2026-07-19: the flat-cursor persistence form
this entry originally described — `grid.cursor.<nodePath>.*` — has been removed; molecule's
per-step `grid.step.*` metadata is now the only circuit engine.)*

**Spawn fence** `ratified · M4-P0` — The persisted `pgid`/`pid`/`token` scalars that make
respawn decisions honest across restarts: liveness is probed against the fence, never
guessed. Read by the RestartReconciler; distinct from the cursor.

**Freshness barrier** `ratified · ADR-0007 (crash-safety P0)` — On boot, state older than
the barrier can't drive kills/respawns until re-verified — the stale-snapshot guard.

**Respawn-or-skip** `ratified · ADR-0007 P0, M4-P1 D-4` — The per-node crash-recovery
posture: on restart, a node whose fence proves its process died either respawns (own,
writable) or skips loudly (foreign/unwritable). **Adopt-a-live-process** is the deferred
stronger form — ADR-0009's `startOrAdopt` is its ratified future (D-6 floor: adopt a
surviving detached process).

**RestartReconciler** `ratified · M4-P0` — The boot-time sweep implementing
respawn-or-skip against the fence + freshness barrier. Currently single-root; the fan-out
over `registeredRoots` is open work (tg-d7z, D-M6).

**Circuit breaker / supervision** `ratified · ADR-0008 D-5` — Per-(station × work)
restorable breaker: the failing leaf authors the restart cursor, SessionScope
escalates + tears down on exhaustion, the kernel owns backoff. A throwing effect body in
*any* allocation family routes to supervision as `Failed` — per-work fail-closed, never a
crashed controller.

**Rework** `ratified · space rework` — The one-command gated-round recovery:
`space rework <bead> --note <…>` re-keys the session's `work_bead` to `<bead>#rN`, the
engine closes the retired session and mints a fresh round live, the note rides into the
next agent brief. Flow in §13-F4.

**Quarantine** `ratified · M3` — Where a session lands when supervision can't classify an
exit as clean; distinguishes "crashed" from "completed" pending discrimination.

**oneTurn vanish** `ratified, hardening open · A38, I-11` — A one-shot (`oneTurn`) agent
that detaches and vanishes is read as `Exited(0)`/clean close. The heuristic is honest for
the happy path but reads a *murdered* agent as completion (I-11); fence-based vanish
discrimination is filed (tg-uz3).

**Governor** `ratified · tg-42f` — The station-wide concurrency budget enforced at the
WorkList mount boundary: `StationServices.maxConcurrentWork` (default 4), lowest-id
admission, **live sessions are never evicted** by re-ranking.

---

## 5. The circuit (authoring model, committee, landing)

**Circuit** `ratified · RS-7; formerly Formula (ADR-0008)` — The value-typed step-graph
the engine **energizes**: `Circuit(id, steps, terminalStepId)`. **The rename is applied
in code (0 occurrences of Formula in grid_engine) but ADR-0008's stamps are still owed**
(§12 item 3). Older docs' *Formula/FormulaStep/FormulaScope* = today's
*Circuit/CircuitStep/CircuitScope*.

**Reentrant engine** `ratified · ADR-0008` — A circuit's step-graph inflates into a
reconciled **subtree** under the same engine (`CircuitScope` → children → `CapabilityHost`
leaves) — steps are nodes, not calls, so supervision/restart/cursor semantics apply at
every depth.

**CircuitStep** `ratified · grid_engine sdk/circuit.dart` — Sealed:
`CircuitStep.capability` (an opaque leaf, with `requires: CapabilityFacts` for the claim
seam, plus `Backoff`/`ResourceRequest` knobs) and `CircuitStep.subCircuit` (inflate a
named sub-circuit — how `code` embeds `landing`). `FanOutStep` (dynamic planning) is
deferred.

**Capability** `ratified · ADR-0008` — An opaque executable leaf. Takes
`(TreeContext, StepArgs)` and reads its world ambiently (Bead, Workspace, SiblingView,
ServiceBundle) — the `CapabilityContext` sandbox was ripped out (ADR-0008 D3 superseded by
the two-verb story). **ServiceCapability** = a capability whose body is a pluggable
collaborator (Service).

**Service / ServiceBundle** `ratified · ADR-0008 D5` — Stateless pluggable collaborators,
bundled **per substation** (the asset's own bundle); `sourceControlFor` resolves a bead's
`grid.root` to the right `SourceControl`. Provided ambiently by the kernel's mountRoot.

**SourceControl** `ratified · ADR-0008 (pluggable-abstract-domains)` — The engine knows
source control in *concept* (provision worktree, commit, push, open PR), never in detail;
`GitSourceControl` ships in assets. Same meta-pattern as `Trust` and transport.

**EffectResolver / CircuitResolver** `ratified · M4-P1` — The seam that maps a mounted
work bead to the effect subtree that drives it (`effectFor({bead, session})`).
`CircuitResolver` (né FormulaResolver) is the sole implementation; the resolver is where
an asset's circuits meet the engine.

**The code circuit** `ratified · grid_assets` — The shipped work-delivery circuit:
**agent** (harness spawns a coder in the worktree) → **review** (the committee) →
**gate** → **land** (the landing sub-circuit). Critics ride the same harness as coders.

**Committee** `ratified · grid_assets code/committee.dart` — Independent critique lanes,
one critic per rubric (shipped lanes: code-validation, test-coverage, regression-risk,
spec-adherence), each grading A–F in isolation against its named rubric; a **route rule**
(shipped: `all-approve`) folds grades into pass/gate. Verdicts transport via
`.grid/critique/<lane>.json` files with an **envelope fallback** (verdict-in-stdout,
tg-291) and a **fail-closed default** (no parseable verdict ⇒ F). Transport hardening —
round-start clears, freshness stamps, transport provenance, review-after-durable-completion
— is tg-bns (PR open).

**Gate / false gate / failure discrimination** `ratified · OPERATIONS.md` —
A gate is the committee refusing to land. The discrimination ladder: a validation plan
that *cannot run* in the worktree = **environment** failure (arming-class); *no parseable
verdict* = **transport** failure (fail-closed F with no rationale); only *ran-and-failed*
is a **true F**. A false gate is a transport/staleness artifact gating a green round.

**Landing circuit** `ratified · tg-rm5, kLandingCircuit` — `rebase` (onto the current
base) → `revalidate` (re-run the bead's **own** validation plan against the rebased tree)
→ `land` (commit → push → open PR). Gates loudly on conflict or revalidation failure —
never silently forces. Closes the **stale-base hole**: with N parallel beads landing on
one repo, the second was validated against a `main` that has since moved.

**Receipt** `ratified · buildCircuitReceipt` — The PR-body provenance block: committee
grades/route + rebase/revalidate outcomes, read from the SiblingView. Threaded via the
stopgap `ReceiptCapableSourceControl` because engine `SourceControl.openPr` has no `body`
param yet; composing (rather than replacing) an agent-authored PR body is open (tg-ghg).

**Stacking (`stacks-on`)** `ratified ruling · 2026-07-03` — There is **no `grid.base`
metadata and none planned**: hard `dependsOn` suffices (a dependent's worktree is cut from
a head that already contains its landed parent). If stacking ever earns its way in, it is
a **typed dependency edge** `stacks-on:<bead>` consumed by the landing circuit — never
metadata, and branch names never appear in bead data.

---

## 6. Agents and harnesses

**Agent** `ratified in-repo · R6` — In the grid: an external **coding subprocess**
(e.g. `claude`) the station spawns and supervises per work bead. The word means other
things elsewhere in the industry (and in lenny); that homonym is English, not a conflict
the org manages.

**The agent scope** `ratified · ADR-0008 Decision 10` — The harness-agnostic agent
surface: **AgentConfig** (a VALUE, resolved down the **D-C ladder**: station `main()` →
substation → fail-closed `grid.agent` envelope → step params), **AgentBrief** (work
content, transport harness-owned), **AgentHarness** + **AgentHarnessRegistry** (DI) over
claude / copilot / pi / opencode, **ModelTarget** sealed
{ProviderManaged, OpenAiCompatible (llama.cpp), SwiftInfer}. Two-moment validation:
boot-eager for the station default, per-work `Failed` for step overrides. Critics ride the
same harness. Exact third-party CLI flags are confirmed at their live arm.

**RuntimeProvider** `ratified · ADR-0004` — Process **transport**, never inference:
`SubprocessProvider` (detached spawn, pgid fencing) and `TmuxProvider` (session-visible).
the_grid does not call LLMs; it shells out to harnesses.

**genesis_tmux vocabulary** `ratified · ADR-0004, A34` — The zero-dep tmux client
(genesis-homed): isolated server socket `-L grid-<workspace-hash>`, `session:^.0` pane
addressing, `pipe-pane` into a FIFO for push-based transcripts, typed argv verbs, the
Tier-3 kill sequence (pane pid → descendant walk → SIGTERM → grace → SIGKILL →
kill-session). Control mode (`-CC`) rejected for v1.

**leonard / lenny as dev tool** `ratified · agent-scope epic bounds` — leonard is a
**development/debugging tool, never the production-code path**; no inference dependency
ever enters engine or SDK. The grid's own agent ("GridHarness") is a parked epic.

---

## 7. Federation

**Assignment-federation** `ratified · SCRATCH-grid-alignment D-A2` — The model: stations
**host** substations and federate by **assigning work**, never by observing each other's
state. "Nice split: no credentials leaked, just work assigned." A remote substation is
**never** a snapshot member of my station. This killed observation-federation (D-Z7 dead).

**Virtual substation** `dropped · R10` — Dead term (was the observation-federation proxy
from the vNext design, superseded by D-A2). The replacement needs no new vocabulary:
remote stations this system observes are simply **stations observed as assets**.

**The claim flow** `ratified design · D-B1..B6; built offline` — Work minted at a station
is **claimed-first-locally**; still-unclaimed work at the end of a reconcile phase is
**broadcast** to the network; remote stations **capability-match** (their
`CapabilityFacts` vs the step's `requires`: OS, system reqs, agent slots, has-dart…,
optionally a public key riding the durable bead) and claim; claim → **lease** is
two-phase, claim recorded in the claimant's own store with deterministic resolution.
Engine got **contracts only** (D-B5): `unclaimedSteps`/`stationUnclaimedFrontier`, the
kernel's post-flush `onUnclaimedFrontier` hook, `claimCapabilityFor`, SDK value types.
**No MQTT in the engine, ever** — bus implementations live in `federated_grid_assets`.
Unproven live; the cross-station claim proof is ADR-0011's graduation gate.

**Broker** `ratified design · in-process ruling` — The message bus seam. In-process, behind
our own abstract interfaces (shielding the dependency); each station **publishes only on
its own broker** and subscribes to others'. `InMemoryBroker` ships; MQTT is a future impl.

**GridHub** `ratified concept` — An optional topology: a station with *only* federation
assets that doles out claimable work. A product built on the model, not the model.

**ACP envelope** `ratified scoping` — agentclientprotocol.com's **messaging schema**
adopted for bus payloads (its transport rejected). No MCP at this layer; A2A becomes
relevant at model/agent routing.

**Zero-conf membership** `built offline · zero_conf_grid_assets` — Dynamic federation
membership: mDNS advertiser/browser, `station_ad`, mesh/GridHub topologies, `trust_gate`,
`ZeroConfMembership`. The standing assumption: federation configuration is **dynamic** —
no static remote-station lists.

**Trust vs consent** `ratified · ADR-0008` — `Trust` = the pluggable federation-identity
domain (local / reputation / ledger; "less-blockchain-by-default, ledger-as-plugin").
Distinct from **consent** (`genesis_consent`) = authorization.

**serve / lease** `ratified · ADR-0011 D3` — "Leasing is core": generic `ServeCommand`/
`LeaseCommand` in the CLI surface; the **compute asset** owns the *use* (bounded dispatch
+ payload/result codec). `LeaseManager`, `StationServer`, `HttpStationClient`,
`GitSyncService` ship in `federated_grid_assets`.

---

## 8. Operations

**`space`** `ratified · space_station` — The composed AOT station runner. Verbs: `up`
(resident boot), `down` (graceful stop via the lock's pid), `status`, `rework`, `gate`,
`watch`, `dart`, `demo`, plus generic `serve`/`lease`. the_grid is a **framework, not a
turnkey CLI** — composed runners like `space` are how stations ship (the Flutter-app
model); `grid` itself stays generic (`watch`/`gate`/`rework`/`demo`).

**The station-runner pieces** `ratified · ADR-0008 (rip-out)` — The composition spine every
runner assembles: `addStationFlags`/`StationArgs` → `validateArming` →
`discoverWorkspaces` → `buildControllers` → `buildLiveWiring` → the asset's own
`ServiceBundle`s → `composeStation` + `wrapRoot` → `driveStation`.

**StationRefusal / the arming ladder** `ratified · ADR-0006` — Boot-time fail-closed:
dry-run is the default; a live run requires `--root` + `--state-workspace`; a resident run
refuses any drive-list; `--adopt` refuses dry-run. Refusals are named errors, not stack
traces. (OP-1/OP-2 extend the ladder: validation-plan preflight, substrate-health
preflight — filed.)

**The hand-mirror** `ratified, drift-prone · space_station` — `space up` re-declares
grid_cli's station flags minus `--bead` by hand (ArgParser can't subtract an option; the
flag must not *exist* on a resident verb). Three lockstep-drift casualties so far; the
full mirror audit + drift-catch test is tg-da7.

**Operator bridge** `transitional` — Hand pre-creating a foreign-root bead's worktree at
`<root>/.grid/worktrees/<root-name>/<bead>` (+ absolute-path `pubspec_overrides.yaml`) so
the adopt probe finds it — the workaround for the provision split-brain. Obsolete once
tg-8tn merges (PR #27).

**Machine-local glue** `convention` — `pubspec_overrides.yaml` files (gitignored,
operator-maintained) linking cross-repo path deps; bd harness scaffolding
(`.claude/settings.json` etc.) regenerates in worktrees and is never committed.

**launchd arming** `ratified · RS-3/RS-6` — Supervision is launchd, recipe-first: a
LaunchAgent plist template (`KeepAlive` with `SuccessfulExit=false` so a graceful
`space down` does **not** bounce; only a crash relaunches), `RunAtLoad`, logs to files.
No `space install` yet — a template earns automation by being hand-operated.

**The incident catalog (I-1…I-11)** `ratified · OPERATIONS.md` — The
numbered determinism incidents and their disciplines. Load-bearing ones: **I-8**
create-then-dep race → create deferred/wire/undefer; **I-9** teardown-vs-spawn orphan
window on `down` (tg-gpg); **I-10** closed-session-with-running-cursor mint wedge
(tg-4rw); **I-11** vanish-reads-as-completion (tg-uz3).

**Monitor** `session convention` — The operator-side watcher (e.g. `governor_watch.py`)
emitting session/grade/gate/terminal/PR events. Not a product surface (ADR-0012
observability is parked).

---

## 9. beads / bd / Dolt (the substrate)

**bd** `ratified · ADR-0001` — The beads CLI over Dolt; pinned upstream **bd 1.0.5
(f9fe4ef2a)**. Always `BD_JSON_ENVELOPE=1`, assert `schema_version == 1`; errors arrive
enveloped on stdout with exit ≠ 0.

**The write rules** `ratified · ADR-0001/0003` — Mutations via bd CLI only, with
`--actor`; **never SQL writes; never touch `.beads/hooks/`** (gc owns them). Grouped
mutations via `bd batch` (one transaction, one DOLT_COMMIT, one dirty signal). **Never
`bd show` from a re-query/controller path** — it writes `.beads/last-touched` and
self-triggers the watcher. Never spawn bd per issue in a loop.

**The read surface** `ratified` — `bd export --include-infra` (full-graph JSONL; `bd list`
never surfaces infra types), `bd query`, `bd ready`, multi-id `bd show`. `bd dep add` is
broken against the server store ("Field 'id' doesn't have a default value") — use
`bd batch` with `dep add <blocked> <blocker>` lines.

**Dolt server mode** `environment fact` — db `tg` at `127.0.0.1:34947`; local
`.beads/dolt/` empty; creds `GC_DOLT_USER`/`GC_DOLT_PASSWORD`; idle connections reaped at
**30s** (pools reconnect, keep ≤2); cross-workspace writes route via `.beads/routes.jsonl`.

**`@@tg_working`** `ratified · A21` — The authoritative ~1ms change probe: Dolt's working
root is content-addressed over **all** tables including dolt-ignored ones, so it catches
gc's cross-workspace wisp closes that a file watcher provably cannot.

**Coexistence** `ratified · ADR-0003 D6` — A live Gas City still runs and assumes a single
writer per bead. Never reconcile or mutate beads gc owns; shadow/conformance work against
live convergence traffic is strictly read-only. Process kills are scoped to our own
worktree/session pgids — never broad pkills.

**Convergence** `ratified · ADR-0003` — gc's work-convergence engine, byte-ported as
`ConvergenceReducer` and retained as a **coexistence shim** (excluded at the mount
boundary, A41); retires per-substation as gc rigs convert (reserved ADR-0010). The
`grid_reconciler` *package* is deleted; the shim lives on in the engine's exclusion rules
and the codec.

**Operator footguns** `recorded` — `bd update` with an *empty* id resolves last-touched;
bd routes by CWD (never mix state-store (`houston`) and work-store mutations in one
compound command; `tgdog` itself is retired — `SUBSTATION-INIT.md` §4);
zsh aborts a whole command on a failed glob; piping analyze output can swallow its rc.

---

## 10. Exploration / observability

**extension (never "plugin")** `ratified · A21/A33` — The org seam word; the wire key is
`extensions`. "Plugin" survives only in third-party ecosystems' own names — and in known
residue (§12 item 7).

**The exploration protocol** `ratified · A33/A39/A40` — The dev/debug wire a running
station exposes: handshake + stable observation + the five `grid.*` tools, with
**pull-free** reactivity (A39) over an out-of-band event stream. Detail lives in
`docs/DEBUGGING.md` (a tooling doc, deliberately out of the core set — R1/R17).

**GridExplorationHost** `ratified · grid_exploration` — The host the station registers so
any exploration-conforming client can attach (`kGridNamespace = 'grid'`). Model-free by
design; proven live (tg-e28/A40).

**Host** `ratified, clean` — The server surface inside a target process that registers
`ext.exploration.*` — the one exploration seam word used consistently across the org.

**ADR-0012 (observability)** `reserved/parked` — Observable-source first-class; OTel and
perception as co-emitted sinks; the AOT HTTP/WS exploration transport under
perception+consent.

---

## 11. Process vocabulary

**ADR-0000 / the register** `ratified` — The AI-decision register: decisions an agent makes
**unattended** land as `A<n>` amendments, Status: pending, until Nico promotes or rejects.
Never written during an interactive session; decisions made *with* Nico go to an official
ADR or build-order directly. Ratified docs change only by **quote-and-supersede stamps,
never silently**.

**The gate / doc-before-code** `ratified · PDR §9` — Brainstorm → PDR → ADR → zero open
questions → code. New scope gets a doc before it gets code; Nico ratifies explicitly.

**SCRATCH surface** `convention` — A design doc where a unit's decisions accumulate
(`D-<x>` ids) before/while being ratified; carries header stamps
(ratified / superseded-in-part). The alignment unit's surface is
`SCRATCH-grid-alignment.md`.

**Build order / tracks / waves** `convention` — The dependency-ordered implementation plan
a milestone executes (`M<k>-BUILD-ORDER.md`); RS-n = resident-station ladder rungs.

**The human gate / live arm** `ratified · ADR-0006 precedent` — The standing boundary:
first *live* contact of new machinery (real writes beside gc, real spawns, LaunchAgent
edits, pushes to main, grade edits) is Nico's to fire. Delivery inside the ratified unit
is delegated (Nico owns *what + requirements*; the delivery DAG is Fable's).

**The house set** `ratified · genesis ADR-0001 D7` — Dart ^3.11, melos workspace, freezed
sealed unions + json_serializable, exhaustive switches, **Fakes not mocks**, Futures for
acts / Streams for observations, doc comments on public API, no print, shared strict
lints. **The freezed boundary (2026-07-04):** grid packages use freezed **always**;
`beads_dart` uses it **never** (minimal-dep, hand-coded value types) — tg-irs / tg-dbd.

**beads_dart** `ratified · D-A6/D-A7` — The renamed, framework-free beads client
(ex-`grid_controller`): Streams for observations, Futures for acts, pinned against bd
1.0.5, `publish_to: none` until the_grid publishes. Symbol renames
(`GridControllerRuntime` → beads-native) are open (tg-cxw).

---

## 12. Drift ledger (rulings applied 2026-07-05; details in `docs/SCRATCH-docs-debt-sweep.md`
(retired to git history — tg-8gv.8) §2, folded into `docs/OPERATIONS.md` §4 at the
public-readiness pass, 2026-07-20)

1. ~~agent~~ — **Not managed** (R6). The lenny/industry homonym is English; no org
   resolution attempted.
2. **session** — **Reframed** (R7): session = the activation around a bead in the tree;
   the session bead is its durable record. Docs updated; symbols already align.
3. **Formula → Circuit** — **Ruled** (R8): Circuit everywhere; "formula" survives only in
   gc-transition/compat prose. ADR-0008's supersession stamp is sweep item W2.
4. **`the_grid` vs `grid_sdk`** — **Resolved** (R9): "the grid" = the framework as
   concept; `grid_sdk` = the framework as concrete code (the core package). The physical
   package split remains future work; ADR-0002 amendment drafted as W6.
5. **Virtual substation** — **Term dropped** (R10): observed remote stations are stations
   observed as assets. vnext-prd §5 supersession banner is W3.
6. **rig prose residue** — **Ruled** (R11): rig survives only in gc-compat prose;
   otherwise Substation. Engine doc-comment sweep is W4 (the `metadata.rig` codec key
   stays — law, not residue).
7. **plugin / GridController\* residue** — **Ruled** (R12): extensions org-wide unless
   building literal Flutter Plugins. Symbol renames fold into a widened tg-cxw (W7);
   coding-lane work, not this pass.
8. **Emptied package stubs** — **Deleted** (R13, 2026-07-05). ADR-0002 topology
   amendment drafted as W6.
9. **defaultSubstation / `substations.first`** — **Ruled out of existence** (R14). The
   config-layer D-M5 disease; dies in the config-model redesign
   (`docs/CONFIG-MODEL.md`), which also collapses the separate "workspace" axis
   (R4), retires the resident qualifier (R5), targets the `runGrid(delegate)` boot shape
   (R15), and dissolves ServiceBundle (R16).

---

## 13. Flows

**F1 · Boot.** *(As-built; ruled "entirely too free-form, library-level" — R15. Target
shape: `runGrid(delegate)` — a final root driven by an observable delegate with ordered
default-implemented hooks; the pattern is documented in `docs/CONFIG-MODEL.md`.)*
`space up --substation … --workspace … --state-workspace … --state-substation …
--root <name>=<path>… [--no-dry-run]` → acquire the station lock →
`validateArming` (refusal ladder) → `discoverWorkspaces` (work stores + state store) →
`buildControllers` (Dolt/bd snapshot sources) → `buildLiveWiring` (roots, writer
chokepoint, runtime provider — no land flag: the `--land` arming seam is retired; delivery
is a per-substation `DeliveryMethod` bound on the substation's `ServiceBundle`, and binding
none is the commit-only posture — tg-6gn, pinned by
`grid_sdk/test/land_seam_retired_test.dart`) → asset `ServiceBundle`s (on notice,
R16) → `composeStation` + `wrapRoot` (ambient AgentConfig/HarnessRegistry) →
`driveStation` (kernel mounts, flush loop runs, control surface binds, lock gains
controlUrl/token).

**F2 · Change detection.** `@@tg_working` probe / watcher fires → requery → snapshot →
diff → typed GraphEvents → StationJoinBridge re-push → tree reconciles → mounts/unmounts/
step-advances happen as Branch lifecycle.

**F3 · One bead, end to end.** Create **deferred** → wire deps (`bd batch`) → undefer
(= bless; enters the ready frontier) → WorkList mount boundary (isCore ∧ root registered ∧
governor slot) → WorkBead mounts → SessionScope adopt-or-mints the session bead (state
store) → worktree provisioned at the bead's root (branch `grid/<bead>`) → **code
circuit**: agent step (harness spawns coder; fence persisted) → committee lanes grade →
route rule → pass ⇒ **landing circuit**: rebase → revalidate → land (PR + receipt) →
positive terminal → cursor advances, session closes → unmount (dispose kills the
allocation).

**F4 · Gated round → rework.** Route rule gates ⇒ session parks gated →
operator/`space gate` review discriminates (env / transport / true F) →
`space rework <bead> --note …` re-keys `work_bead=<bead>#rN` → engine auto-closes the
retired session, mints a fresh one → next round's brief carries the note + critiques.

**F5 · Crash / restart.** Station dies → launchd KeepAlive relaunches (`SuccessfulExit=
false` spares graceful downs) → new boot steals the dead lock → freshness barrier →
RestartReconciler walks fences: own+writable ⇒ respawn; foreign/unwritable ⇒ loud skip.
(Adopt-a-survivor is the ratified future: `startOrAdopt`.)

**F6 · Graceful down.** `space down` reads the lock → SIGTERM to the holder →
teardown disposes allocations (scoped pgid kills) → lock released. Known hole: the
teardown-vs-spawn window can orphan a just-spawned agent (I-9, tg-gpg).

**F7 · Claim → lease (built, unproven live).** Work minted → claim-first-local →
reconcile-phase end: unclaimed frontier broadcast on own broker → remote stations
capability-match `requires` vs their `CapabilityFacts` → claim in claimant's own store →
deterministic resolution → lease → assigned work drives at the winning station. Live
cross-station proof = ADR-0011's graduation gate.

**F8 · Attach / observe.** Debug tooling, not a core flow — relocating to the
testing/debugging doc (R17/W5). Short form: an exploration client attaches to the
station's VM service, handshakes the `grid` namespace, observes/invokes, and subscribes
the out-of-band event stream.

**F9 · Lock acquisition / steal.** `up` reads any existing lock → `kill -0` the recorded
pid → alive ⇒ refuse (one supervisor per state store); dead/torn ⇒ **loud steal** →
write fresh record (0600) → `down`/signals ride the pid, never HTTP (control surface is
GET-only).

**F10 · Receipt provenance.** On land: `buildCircuitReceipt(beadId, siblings)` reads the
committee's per-lane grades + route and the rebase/revalidate outcomes from the
SiblingView → composes the PR body → threads through `ReceiptCapableSourceControl` into
`gh pr create --body` (engine `openPr` lacks a body param — the known stopgap).
