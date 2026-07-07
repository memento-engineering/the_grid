# SCRATCH — code as config: the grid composition model & `runGrid`

**Status: PROPOSAL v3 — decision-complete (all open questions closed 2026-07-06);
awaiting Nico's ratification. NO CODE until ratified.**
Lineage: v1 (2026-07-05) rejected — re-committed the ambience sins (root *sets*,
`defaultRoot`, a `Root` type, `stateSubstation`). v2 corrected the value model
(substation = name + ONE root; the grid has only a state store; store-lives-at-root).
**v3 (2026-07-06) reframes on Nico's ruling: *code as config*** — the tree IS the
configuration; a station is *authored as a Seed*. Configuration objects are thin and
subordinate. Rulings log: `SCRATCH-docs-debt-sweep.md` §1 + the 2026-07-05/06 reviews.

## 1. The thesis: code as config

Just as the org went Dart-first before TOML, the grid goes **code-first before
configuration**. A station is not "configured" by a value the framework interprets —
it is **built**, as a tree, in Dart, by its author. Plain language features *are* the
configuration language: an `if (kDebug)` mounts a substation; a `for` fans out; a
watched value re-composes. `GridConfiguration` stays **thin** — plausibly nothing more
than the result of TOML loading, provided *into* the tree like any other value
(whether it carries aspected domains à la an app-configuration is **deliberately
deferred** until TOML work forces the question — earn it).

Consequence for the v2 delegate: the `buildServices` / `buildSources` hook split
**dies** — it was framework-owned layering where the model wants **assets mounted in
the tree at the right scope**. What survives of `GridDelegate`: lifecycle rails +
config provision + the master `build` (§4).

## 2. The canonical tree (Nico's sketch, 2026-07-06 — pseudo, load-bearing shape)

```dart
/// raw pseudo space_station; NOT A FULL IMPLEMENTATION — expect mistakes
class SpaceStationAsASeed extends SomeSeed {
  Seed build(ctx) {
    return RawAssetGrid(
      root: '/path/to/space_station',
      assets: [                                  // List<Seed>
        Nest(
          children: [
            DomainConfigurationProvider(() async {
              // HEAVY PSEUDO: async config load, provided to the tree.
              return GridConfiguration.fromToml(/* ... */)
                ..addDomain(ButaneDomainConfiguration(/* ... */));
            }),
            ZeroConfGridProvider(/* mdns parameters */),  // discovers fed'd assets
            MqttGridProvider(/* parameters */),
          ],
          child: Station(
            root: '/path/to/space_station',      // optional; defaults to grid.root
            name: 'Space Station - MBP',
            assets: [                            // List<Seed>
              Nest(
                children: [
                  ZeroConfGridAssets(/* default: mounts all */),
                  HarnessProvider(/* parameters */),
                  FlutterProvider(),
                  ButaneBurnProvider(),
                ],
                child: Substations(              // MultiChildSeed: the fan-out
                  substations: [
                    Substation(
                      name: 'the_grid',
                      root: 'path/to/the_grid',
                      assets: Nest(children: [   // SingleChildSeed
                        GitGridAssets(/* parameters */),
                        GitHubGridAssets(),
                      ]),
                    ),
                    Substation(
                      name: 'power_station',
                      root: 'path/to/power_station',
                      assets: Nest(children: [GitGridAssets(/* … */)]),
                    ),
                    ButaneDevelopmentSubstation(
                      root: 'path/to/butane_flutter',
                      assets: Nest(children: [GitGridAssets(/* … */)]),
                    ),
                    if (kDebug)                  // eating itself
                      Substation(
                        name: 'space_station',
                        root: '/path/to/space_station',
                        assets: Nest(children: [GitGridAssets(/* … */)]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// defined in butane_grid_assets — COMPOSITION, never a Substation subclass
class ButaneDevelopmentSubstation extends SomeSeed {
  const ButaneDevelopmentSubstation({String root, SingleChildSeed assets});

  Seed build(ctx) {
    final butaneConfig = GridConfiguration.of<ButaneGridConfiguration>(ctx);
    final targets = Flutter.targetsOf(ctx);   // watches available sims/devices
    return Substation(
      name: 'Butane',
      root: root,
      assets: [
        GitHubGridAssets(butaneConfig.github),
        if (butaneConfig.enableChaosBurn)
          ChaosBurnOrder(targets: targets),    // available Orders / orderable circuits
        ...assets,
      ],
    );
  }
}
```

## 3. The pieces

- **`RawAssetGrid`** — the raw root, the WidgetsApp-to-MaterialApp relationship:
  unopinionated, possibly rawer still (inject the dolt services and the low-level
  machinery directly). A batteries-included `Grid` analogue can layer on top later.
  Its `root` is the grid's home; the grid's **state store** lives there (the grid has
  no work store).
- **`assets:` slots on Grid / Station / Substation** — `List<Seed>` (Substation's is a
  `SingleChildSeed` chain in the sketch). An asset is *anything mounted into the tree
  at a scope* (glossary R3 made literal): config providers, federation discovery,
  harnesses, source control, orders. Grid-level assets serve the deployment;
  station-level assets serve the machine; substation-level assets serve the project.
  **This is where ServiceBundle actually dissolves**: per-substation git/GitHub are
  just assets mounted under that substation.
- **`Nest`** — genesis_tree's chaining container (`children: List<SingleChildSeed>`,
  outermost-first, folded around `child`; a null child is supplied by an enclosing
  Nest). The grouping idiom for asset stacks; used everywhere.
- **`Station(root?, name, assets)`** — the machine. `root` optional, defaulting to
  `grid.root`.
- **`Substations(substations: [...])`** — a `MultiChildSeed` owning the fan-out: each
  child `Substation` establishes its `WorkList`.
- **`Substation(name, root, assets)`** — a project: ONE root; work store at the root.
  Extended by **composition** (`ButaneDevelopmentSubstation` *builds* a `Substation`),
  never subclassed — composed substations read config from context, watch live state
  (`Flutter.targetsOf`), and conditionally mount their assets/orders.
- **`DomainConfigurationProvider`** — doesn't exist yet; async config loading AS a
  tree node (the tree must handle a not-yet-loaded configuration gracefully). Lumped
  into the TOML discovery.
- **`ZeroConfGridProvider` / `MqttGridProvider`** — federation membership as mounted
  observers at grid scope: discovery events are observed state; membership changes
  reconcile (the dynamic-membership assumption made structural).
- **Circuit provider / circuit scope** (Q8 closed) — what the sketch's
  `ChaosBurnOrder` actually is: an asset that mounts a circuit into a substation's
  scope, making it available for that substation's work (the resolver seam, asset-
  shaped). The word **Order** was wires-crossed lineage: in gc, an *Order* pairs a
  trigger with a formula — the **when** axis over the formula's **what**
  (gc `docs/tutorials/07-orders.md`), fired by the controller's 30-second tick. A grid
  analogue of the *when* axis, if it ever earns its way in, is a separate future
  design — and must respect the no-clock posture (the engine is event-driven; triggers
  would be observed state, never a tick).

## 4. `GridDelegate`, re-scoped (rails, not layers)

The delegate keeps: **being the observable** (`StateNotifier<GridConfiguration>`,
thin), the **lifecycle rails** (`didLaunch` pre-tree; `initGrid` post-mount async
kickoff, unawaited; `onReady`; `onTeardown`; hook errors captured/attributed/loud),
and the **master `build(ctx, conf)`** returning the station tree (§2's
`SpaceStationAsASeed.build` is exactly that method in delegate clothing). It loses:
any framework-owned service/source layering — those are assets in the tree.
Convenience build hooks may be added later as sugar over asset mounting, derived from
real usage — earned, not designed up front. `runGrid(delegate)` mounts: delegate
provision → configuration provision → `build`. Every runner — `space`, `grid_cli`'s
verbs, anything composed — implements this model; **no backporting, no shimming**.

## 5. Closed questions (Nico, 2026-07-06)

- **Q3′ CLOSED — beads carry no root stamp.** Kill `metadata.grid.root`. Beads hold
  **references**; anything an agent needs (repo path, worktree location) is resolved
  at **brief/prompt inflation time** from the activation — the bead's substation → its
  root — never read from a stamp on the bead. Rebuild-unit requirement: the
  brief-building step inflates references; verify current prompts against this before
  deleting the stamp.
- **Q-mig CLOSED — yes.** The rebuild unit creates **and documents** the substation
  initialization process (seeding a new substation's store at its root, adopting its
  work, registering it in the tree). New-substation-init becomes a first-class,
  documented flow.
- **Q1/Q2/Q4 (from v2):** BOTH TOML and Dart; `runGrid(GridDelegate)` +
  `GridConfiguration`; home = **`grid_sdk`** (the unit births the package).

## 6. Open questions — ALL CLOSED (Nico, 2026-07-06)

- **Q5 CLOSED — (a).** The grid state store lives under the runtime dir,
  `<grid.root>/.grid/…`; **`.beads/` means *work store*, uniformly, everywhere.** The
  dual-role repo (implementation instance + self-substation under development) holds
  its grid state under `.grid/` and its work store at `.beads/` with no collision.
  The separate tgdog-style home directory dies with the rebuild.
- **Q6 CLOSED — plain values for now.** `GridConfiguration` is a plain value (e.g. the
  TOML-load result). No domain/aspect machinery until something real demands it.
- **Q7 CLOSED — open parameters for now.** Asset slots are `List<Seed>` or `Seed`;
  no dedicated wrapper type yet. Naming rule: **`Raw` prefixes for cumbersome
  object names/constructors** (the `RawAssetGrid` pattern — raw layer explicit,
  friendly layer earns its name later).
- **Q8 CLOSED — it's a Circuit provider/scope** (see §3). "Order" was crossed wires;
  gc's Order (trigger→formula, the *when* axis — gc `docs/tutorials/07-orders.md`)
  stays gc-compat vocabulary; any grid when-axis is a separate future design, clockless.

## 7. What dies (unchanged from v2, plus)

`defaultSubstation` · `substations.first` · `RootSpec`/`--root` grammar · the
`--workspace` axis · `--state-workspace`/`--state-substation` · `metadata.grid.root`
(Q3′ closed: killed, replaced by reference inflation) · `rootPath`/`workspacePath`
shims · `''` sentinels · cwd discovery under arming · `serviceBundleMapFor` +
`ServiceBundle` (dissolved into substation-scoped assets) · the hand-mirrored flag
surface · the `workRoot` fallback chain · **the v2 delegate's buildServices/
buildSources hook split** (assets in the tree, not framework layers).

## 8. Track 0(b) — brief-inflation audit (findings, tg-7t7, 2026-07-07)

READ-ONLY audit per `GRID-SDK-BUILD-ORDER.md` Track 0(b): *every place brief/prompt
building reads `metadata.grid.root` or any stamped path off a bead* (Q3′ requirement).
Scope swept: `grid_engine` / `grid_runtime` / `grid_cli` (the_grid) · `grid_assets` /
`dart_grid_assets` (power_station) · `space_station`. Lib code only (tests excluded).
Two independent read-only traces (the grid_runtime provider chain; the power_station
agent capability) corroborate the direct read.

### 8.1 Headline verdict — Q3′ is ALREADY structurally satisfied on the brief path

**No brief/prompt builder anywhere reads a resolved filesystem path off a bead.** There
are exactly **two** brief builders in the whole org, both `(Bead, Workspace)` →
`AgentBrief`, both in power_station:

- `buildAgentBrief(bead, workspace)` — `grid_assets/lib/src/code/code_capabilities.dart:182`
  (the coding-agent brief; called from `AgentCapability.spawn:121`).
- `buildCriticPrompt(bead, rubric, nodePath)` — `grid_assets/lib/src/code/committee.dart:405`
  (the critic brief; wrapped as `AgentBrief(task: …)` at `committee.dart:284`).

Every filesystem path that reaches a spawned agent — the process cwd AND the path
interpolated into the brief text — comes from the ambient **`Workspace`** inherited
seed (`workspace.workspaceDir` / `.branch` / `.baseBranch`), **never a bead field**.
`AgentBrief` (`agent_harness.dart:161`) has no path-typed field: only `task` /
`workingAgreement` / `context`. All five harness `spawnFor`s set
`RuntimeConfig(workDir: workspace.workspaceDir)` (`agent_harness.dart:327/349/403/442/481`).

The one path *interpolated into brief text* is the working agreement's
`${workspace.workspaceDir}` + `${workspace.branch}` (`code_capabilities.dart:207-208`) —
from the seed, not the bead. The critic prompt's only path is the workspace-relative
**constant** `.grid/critique/<rubric>.json` (`committee.dart:406`, `_critiqueDir` =
`committee.dart:102`).

### 8.2 What `metadata.grid.root` actually is — a SELECTOR (root NAME), never a path

`grid.root` is a *registered-root name* a bead opts into (e.g. a `tg`-owned bead building
`power_station` stamps `grid.root: power_station`), NOT a resolved path. The path is
computed downstream from `RootCheckout.path` + substation + beadId. Every read:

| # | file:line | code | what it reads | class |
|---|---|---|---|---|
| 1 | `grid_runtime/…/lifecycle/bead_ownership.dart:100` | `final root = metadata['grid.root'];` (the `rootOf` accessor) | selector name | **SELECTOR** — the ONE direct read; every consumer goes through this |
| 2 | `grid_engine/…/circuit/session_scope.dart:416` | `services.sourceControlFor(BeadOwnershipPredicate.rootOf(seed.bead.metadata))` | name → `SourceControl`; then `sc.workspaceFor(beadId)` builds `Workspace.workspaceDir` (`:420`) | **REFERENCE** — the ONE inflation point (session-mount) |
| 3 | `grid_engine/…/sdk/allocation.dart:524` | `services.sourceControlFor(… rootOf(bead.metadata) …)` then `sc.provisionWorkspace(beadId, workspace.workspaceDir)` (`:531-534`) | same name → SourceControl; provisions the worktree | **REFERENCE** — must match #2's SourceControl (split-brain wedged tg-rm5/tg-043) |
| 4 | `grid_engine/…/seeds/work_list.dart:192` | `rootOf(bead.metadata) ?? ownership.substationOf(bead)` gated vs `registeredRoots` | selector name (defaulting to substation) | **SELECTOR** — mount-boundary name gate, no path |

No `rootOf` / `metadata['grid.root']` read exists in `grid_assets`, `dart_grid_assets`,
or `space_station` — the selector is consumed only in the_grid, and only to *pick a
`SourceControl`*, never to read a path.

### 8.3 Where the path is actually produced — config, keyed by beadId (no bead stamp)

The name→path binding lives in CLI/substation config, not on any bead:

- `SourceControl.workspaceFor(beadId)` is the beadId→path map (`capability.dart:359`); the
  git impl computes `WorktreeLayout.worktreePath(root.path, root.substation, beadId)`
  (`station_git_service.dart:165`; power_station's `GitSourceControl.workspaceFor` at
  `code_capabilities.dart:404-415`) — **RootCheckout config + beadId, no bead field.**
- `RootCheckout.path` originates from the CLI `--root name=path` flags →
  `git.registerRootCheckout(path: …, substation: …)` (`station_runner.dart:978`;
  space_station `serviceBundleMapFor` at `up_command.dart:262`). Registration is
  reference-based root config; `ServiceBundle.sourceControlFor(name)` (`capability.dart:343`)
  resolves the selector against it.
- `SessionScope` (`session_scope.dart:419-423`) mounts the resulting `Workspace` seed;
  the capabilities/brief-builders/harnesses consume it (`code_capabilities.dart:99`,
  `committee.dart:251`, `landing.dart:89/143`).

**Rebuild-track nuance:** Q3′ says "resolve at brief/prompt inflation time." Resolution
today happens one layer UP, at `SessionScope` mount, not inside brief-building — but it is
already config-derived and `grid.root` is already only a *name*, so there is **no
bead-stamped path to strip from the brief path.** Track E's brief-side work is verification
+ (optionally) moving the resolution seam down to inflation; the substantive change is
Track H killing the `grid.root` *selector* and the multi-root machinery
(`sourceControlsByRoot` / `sourceControlFor`): once each Substation has ONE root and a
bead's substation determines its root, reads #2–#4 collapse to "bead → its substation → its
root."

### 8.4 Adjacent stamped-path surfaces (NOT brief-inflation, flagged for Track E/H)

These are the only places a resolved path is written *onto* a bead, or a second
bead-carried-path surface exists — none is read to build a brief or a cwd:

- **`runtime_actuator.dart:120-121`** — `spawnSession` stamps a resolved `'worktree'`
  path (+ `'branch'`) onto the_grid's OWN **session** bead (via `StationBeadWriter
  .createSession`'s `…metadata` passthrough). **STAMP**, but: M3-era API with **no
  non-test caller**, and `metadata['worktree']`/`['branch']` are **never read back** in
  lib code (write-only telemetry). A fossil — dies with the M3 grid_runtime path; the
  live M4-P1 engine never constructs `RuntimeActuator`.
- **The M4-P1 restart fence** (`AllocationStarted`/`AdoptFence`, `allocation.dart:132-143`)
  persists `pgid`/`pid`/`token` + `state` onto the session bead — **identity, NOT a path**;
  the worktree is re-inflated from `SourceControl`+beadId on restart. No path stamp.
- **`StationBeadWriter.createSession`/`createGate`** (`station_bead_writer.dart:135-190`)
  write only NAMES/IDS (`rig`=substation, `work_bead`, `blocks`, `node`, `started_at`) —
  no path, and never `grid.root`. (`grid.root` is never *written* anywhere — purely
  inbound selector.)
- **The `grid.dart` pub-linkage envelope** (`code_capabilities.dart:142-156` `_linkWorkspace`
  → `DartLinkService.applySync` → `pub_links.dart`) — the ONE place a bead carries declared
  paths (per-package `devPath`s). But: (a) they are pub dependency-link paths, not the
  agent's cwd/repo root; (b) they never touch brief/prompt text — written into
  `pubspec_overrides.yaml` in the worktree; (c) relative values are absolutized against
  `devRoot` = `RootCheckout.path` (config, threaded via `AgentCapability(devRoot:)`,
  `code_capabilities.dart:517`), fail-closed refused without one (`pub_links.dart:222-237`).
  A **second, independent bead-carried-path surface** — orthogonal to `grid.root`, but the
  rebuild should decide whether these `devPath`s stay bead-declared or move to
  substation/asset config (out of Q3′'s narrow "root stamp" remit, in Track E/H's spirit).

### 8.5 Bead reads in brief-building, exhaustive (all REFERENCE / content — none a path)

| file:line | code | reads | class |
|---|---|---|---|
| `code_capabilities.dart:184` | `bead.metadata['rig']` → `(substation \`$substation\`)` (`:190`) | substation NAME | **REFERENCE** (name) |
| `code_capabilities.dart:183/201-204` | `bead.title/.description/.design/.acceptanceCriteria/.notes` | brief content | content, no path |
| `committee.dart:579-595` (`_beadBlock`) · `asset_loader.dart:84-97` (`beadBlock`, `{{bead}}`) | same six content fields | critic/rubric content | content, no path |
| `code_capabilities.dart:115` · `committee.dart:278` | `resolveAgentConfig(beadMetadata: bead.metadata …)` | `grid.agent` config envelope (harness/model/params) | **REFERENCE** (config, no path) |
| `committee.dart:564` · `landing.dart:247` | `bead.metadata['validation_plan']` | gating `sh -c` command string | not brief text, not a path |

**Conclusion:** DoD §3's "briefs inflate references (0(b) verified empty)" holds *today* for
the brief path — no brief/prompt reads a stamped path off a bead. The residual work is
Track H's deletion of the `grid.root` *selector* + multi-root resolution (reads #2–#4) and
the fossil `worktree`/`branch` session-bead stamp, plus a Track E/H call on the `grid.dart`
`devPath` surface (§8.4).
