# SCRATCH — code as config: the grid composition model & `runGrid`

**Status: RATIFIED v3 (Nico, 2026-07-06) — decision-complete, all open questions
closed 2026-07-06. GRADUATED 2026-07-19: the durable restatement of §1–6 (incl.
Q3′, Q5–Q8) is [`CONFIG-MODEL.md`](CONFIG-MODEL.md); this SCRATCH remains as
design history, and the §7a/§8 point-in-time fossil audits (2026-07-07) remain
here as archive-only history.**
Lineage: v1 (2026-07-05) rejected — re-committed the ambience sins (root *sets*,
`defaultRoot`, a `Root` type, `stateSubstation`). v2 corrected the value model
(substation = name + ONE root; the grid has only a state store; store-lives-at-root).
**v3 (2026-07-06) reframes on Nico's ruling: *code as config*** — the tree IS the
configuration; a station is *authored as a Seed*. Configuration objects are thin and
subordinate. Rulings log: `docs/SCRATCH-docs-debt-sweep.md` (retired to git history — tg-8gv.8)
§1 (folded into `docs/OPERATIONS.md` §4 at the public-readiness pass, 2026-07-20)
+ the 2026-07-05/06 reviews.

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

## 7a. Fossil-completeness inventory — Track 0(a) audit (2026-07-07, read-only)

Swept `grid_cli` / `grid_engine` / `grid_runtime` (this repo, `packages/…`) +
`space_station` / `power_station` (sibling checkouts under `engineering.memento/`).
Tool: `rg` over `*.dart` (generated `*.g.dart`/`*.freezed.dart` excluded). `lib/…` =
the fossil to delete or rewrite; `test/…` = migrates with it (never shimmed).
**Verdict: §7's list is COMPLETE for everything it names** — every item has real code
fossils below (the one exception, item 13, is a design-only fossil: no code). **6
extensions (E1–E6) and a same-name NON-fossil set are added.** Epicenter =
`grid_cli/lib/src/station_runner.dart` (the `addStationFlags` → `StationArgs` →
`validateArming` → `discoverWorkspaces` → `buildControllers` → `buildLiveWiring` →
`composeStation` assembly) and its by-hand mirror `space_station/lib/src/up_command.dart`.

### CONFIRMED present — per kill-list item

**1. `defaultSubstation`** — grid_cli `station_runner.dart`:17(doc),651–667 (the
`buildControllers` default-key param `String defaultSubstation=''` + `work[defaultSubstation]=ws`);
space_station `up_command.dart`:149,172,252–281 (`serviceBundleMapFor`'s default-key +
its doc). Tests: space_station `service_bundle_map_test.dart`:37,49,64,79,100,117,130.

**2. `substations.first` privilege** — grid_cli `station_runner.dart`:17,411,425,480,508,1004,1009,1046
(+ doc 870,1000). space_station `up_command.dart`:149,172,186,416. Tests:
`station_status_test.dart`:205; `run_command_tree_test.dart`:945(doc),969,997,998,1014.
NOTE the `args.substations` SET itself survives (named substations); only the `.first`
"pick a default" privilege dies.

**3a. `RootSpec` type** — grid_cli `station_runner.dart`:263–318 (class + `==`/`toString`),
278–306 (`RootSpec.parse`), 323–338 (`parseWorkspaceSpec` mirrors the same grammar),
362,406,409,463,477,482. space_station `up_command.dart`:411,414. Tests:
`root_flag_test.dart` (WHOLE FILE — E5), `station_status_test.dart`:31,173,
`run_command_tree_test.dart`:267,356,462,559,560,726.

**3b. `--root` grammar** — the option: grid_cli `station_runner.dart`:146–158
(`addStationFlags`), mirrored space_station `up_command.dart`:321–333. Consumers:
`station_runner.dart`:406–425 (`StationArgs.from` parse loop), `up_command.dart`:411–425.
Tests: `root_flag_test.dart`:80,90,92,109,111,132,134; space `up_command_validation_test.dart`:96,111,126,145,147;
`up_down_status_smoke_test.dart`:274,276. NOTE the `'root':` MAP keys at
`station_control.dart`:59 and `work_list.dart`:301 are the observable/flare surface
(they fall with `metadata.grid.root`, see E2), NOT the CLI flag.

**4. `--workspace` axis** — the option: grid_cli `station_runner.dart`:166–178, mirrored
`up_command.dart`:340–347; `parseWorkspaceSpec` 321–338; `StationArgs.workspaces` parse
421–429; `discoverWorkspaces` 653–691 (the work-store fan-out). Consumers 762,819,932;
grid_cli `watch_command.dart`:74,79; `gate_command.dart`:155,224,236,242;
`rework_command.dart`:46,104,137,142,158,162,179–194. Tests: `workspace_flag_test.dart`
(WHOLE FILE — E5), `discover_workspaces_test.dart` (WHOLE FILE — E5). NOTE the
`BeadsWorkspace` beads_dart store type SURVIVES (E6); only the CLI axis + path plumbing die.

**5. `--state-workspace` / `--state-substation`** —
*`--state-workspace` / `stateWorkspacePath` / `stateWorkspace`:* grid_cli
`station_runner.dart`:181–185,380,441,519,614–619 (live guard),656,682–687,706,729,819,932,1314,1316,1350,1354;
`station_control.dart`:251; `station_lock.dart`:10,101,113–129 (`stateWorkspaceDir` — re-source not delete, E4);
`gate_command.dart`:54,59,94,114,117,138,151,163,167,216,220,232,242,245;
`rework_command.dart`:31,53,82,105,131,138,143,154,156,162–174. space_station
`up_command.dart`:150,349–353,432; `attach_support.dart`:3–69 (`resolveStateWorkspace`,
whole helper); `down_command.dart`:21,37,45; `status_command.dart`:32,67,77,136. Tests:
`rework_command_test.dart`, `gate_command_test.dart`, `discover_workspaces_test.dart`,
`run_command_tree_test.dart`:256,269,276,358,607,695,727, `station_lock_test.dart`,
`station_attach_test.dart`, `station_control_wiring_test.dart`:324, space
`up_command_validation_test.dart`, `up_down_status_smoke_test.dart`.
*`--state-substation` / `stateSubstation`:* grid_cli `station_runner.dart`:188–192,381,442–444,522,619,923,926,1044–1046,1317;
`gate_command.dart`:13,27,42,54,66,95,139,152,213,221,265,292;
`rework_command.dart`:60,106,139,265; space `up_command.dart`:356,433–435. **Engine-deep
(→ E3):** grid_engine `station_services.dart`:12,25,30,46 (`StationServices.stateSubstation`),
consumed `capability_host.dart`:348 + `session_scope.dart`:169 to stamp `'rig':
stateSubstation` on session beads. Test constant `stateSubstation='tgdog'`:
`engine_fakes.dart`:441(+463,473,505) + ~30 grid_engine/grid_cli test refs; power_station
`asset_fakes.dart`:85, acceptance tests.

**6. `metadata.grid.root` (Q3′ — killed, replaced by reference-inflation)** — the READ:
grid_runtime `bead_ownership.dart`:94–100 (`metadata['grid.root']`). Resolution/use:
grid_engine `work_list.dart`:184–195,296–301 (targetRoot + `registeredRoots` gate +
flare stamp), `session_scope.dart`:406, `capability.dart`:306,324,337 + `allocation.dart`:504,519
(rootName selector), `substation_config.dart`:44. Doc/comments: `station_runner.dart`:153,262,468,879,1132,1183;
space `up_command.dart`:167,193,256,328. Tests: `run_command_tree_test.dart`:513,516,528,533;
`compose_station_disjoint_ownership_test.dart`:60; grid_engine `track_a_root_selector_test.dart`:158,164,197,234,
`track_a_allocation_test.dart`:360,376,400. (Brief-side reads are Track 0(b)'s remit.)

**7. `rootPath` / `workspacePath` shims** —
*`rootPath` (StationArgs deprecated alias):* grid_cli `station_runner.dart`:365–370,392,464,471–488,504;
tests `root_flag_test.dart`:144–193, `workspace_flag_test.dart`:118. NON-fossil same
name (E6): grid_runtime `station_git_service.dart`:157–166 `WorktreeLayout.worktreePath(String rootPath,…)`
is a plain param (+ its tests).
*`workspacePath` (StationArgs deprecated alias):* grid_cli `station_runner.dart`:375–379,394,494,500–516;
space `up_command.dart`:431; `rework_command.dart`:104,137,183,187; tests `workspace_flag_test.dart`:117–145.

**8. `''` sentinels** — all trace to items 1/2 (the "no substation → empty string"
fallback): grid_cli `station_runner.dart`:411,425,480,508,1007,1009,1044–1046; grid_engine
`work_list.dart`:301 (`'root': targetRoot ?? ''`); space `up_command.dart`:416. (The
`args.isNotEmpty ? args.first : ''` / `?? ''` at `station_runner.dart`:1591–1594, in
projections, `subprocess_provider.dart`:174,225, and power_station committee/landing are
ordinary arg-parse / JSON-default guards — NOT store sentinels.)

**9. cwd store discovery under arming** — grid_cli `station_runner.dart`:660,663
(`BeadsWorkspace.discover()` no-arg + `Directory.current.path` refusal);
`watch_command.dart`:79,82; `gate_command.dart`:167, `rework_command.dart`:187
(`?? Directory.current.path`); space `status_command.dart`:145; help text "Defaults to
discovery from the cwd" at `station_runner.dart`:177 / `up_command.dart`:345. NON-fossil
(E6): power_station `asset_loader.dart`:169,179 cwd walk-up is ASSET-PACK (TOML)
discovery; `dart_command.dart`:112 is a capability workdir; `Directory.current` walk-ups
in `*_test.dart`/`structural_test.dart`/`fixtures.dart` are test-infra locators.

**10. `serviceBundleMapFor` + `ServiceBundle`** —
*`serviceBundleMapFor`:* ONLY space_station `up_command.dart`:171,262(def)–288 + test
`service_bundle_map_test.dart` (WHOLE FILE — E5). grid_cli passes `services:` directly.
*`ServiceBundle` TYPE (large, central — Track F):* DEFINED grid_engine `capability.dart`:310
(with the root selector 305–344, → E2). It is the engine's per-`SubstationScope` DI seam
(ADR-0008 D5): `substation_scope.dart`:16–91 provides `InheritedSeed<ServiceBundle>`;
consumed `work_list.dart`:102–108, `capability_host.dart`:69,115, `session_scope.dart`:413,
`allocation.dart`:506; declared in `station_kernel.dart`:128, `station_services.dart`:15,
`grid_engine.dart`:63. grid_cli `station_runner.dart`:24,29,846,876,1149,1171,1197 (the
`services` map) + `grid_cli.dart`:12. power_station `code_capabilities.dart`:258,
`landing.dart`:87,140. Test surface (migrates with F): ~34 files — grid_engine 20
(incl. `service_bundle_root_test.dart` whole-file, `track_a_*`, `track_e_capability_host_test.dart`),
grid_cli `run_command_tree_test.dart`, power_station 6 (`substation_service_bundle_test.dart`,
acceptance). Dissolving the type = replacing the `InheritedSeed<ServiceBundle>` DI with
per-substation git/GitHub ASSETS mounted at substation scope (§3).

**11. hand-mirrored flag surface** — CONCRETE: space_station `up_command.dart`:301
`_addResidentStationFlags` byte-duplicates grid_cli `station_runner.dart`:126
`addStationFlags` (its own doc, `up_command.dart`:294–300, admits "Kept in lockstep with
`addStationFlags` by hand"); `up_command.dart`:405 `_residentStationArgsFrom` mirrors
`StationArgs.from` (`station_runner.dart`:400). Dies with Track G (absorbs tg-da7).

**12. `workRoot` fallback chain** — the chain: grid_cli `station_runner.dart`:1003–1010
(`roots[substations.first] ?? roots.values.first ?? RootCheckout(path:'')`), consumed 1054;
the status projection `station_control.dart`:252–254 (`args.roots.isEmpty ? null : …`).
The single-root CONSUMER = grid_engine `restart_reconciler.dart`:250–336 (`_workRoot`;
"restart walks substations" D-M6 deferred → Track H subsumes tg-d7z). Fields/threading:
`station_runner.dart`:34(doc),852,872,1166,1208; `station_control.dart`:73,95,137;
space `up_command.dart`:173,201,205,264,286; `signal_smoke_target.dart`:34; space
`status_command.dart`:114 (the lone `station['workRoot']` display CONSUMER of
`station_control`'s emitted `'workRoot'` projection field at :137 — added round 2). Tests: many
(grid_cli `station_lock_test`/`station_status_test`/`station_control_wiring_test`/`station_signals_test`/`station_attach_test`/`run_command_tree_test`/`compose_station_disjoint_ownership_test`;
grid_engine `restart_reconciler_test.dart` ×13, `track_d_reconciler_adopt_test.dart`;
power_station acceptance). NON-fossil (E6): the `RootCheckout` type (grid_runtime
`station_git_service.dart`:19) survives — it becomes per-substation/plural, not the
singular default.

**13. v2 delegate `buildServices`/`buildSources` split** — **NO code fossil.** Zero hits
for either symbol: the v2 delegate was never implemented. The framework-owned layering it
names is instead the CURRENT station-runner assembly `discoverWorkspaces` (`station_runner.dart`:653)
→ `buildControllers` (761) → `buildLiveWiring` (910) → `composeStation` (1160, + `wrapRoot`).
Track G swaps that whole assembly for `runGrid(GridDelegate)` + composition Seeds; DoD #6
removes the old boot path. (Recorded here so a §7-driven grep doesn't chase a phantom symbol.)

### Extensions to §7 (fold into H / E / F / G scope)

- **E1 — the `--head` flag.** A rider on the `--root <name>=<path>[@head]` grammar; dies
  WITH `--root`. `station_runner.dart`:159–165; space `up_command.dart`:334–339;
  `StationArgs.head` 430.
- **E2 — the root-SELECTOR subsystem falls entirely with `metadata.grid.root` (Q3′).**
  `ServiceBundle.sourceControlsByRoot` / `sourceControlFor(rootName)` (`capability.dart`:305–344),
  `SubstationConfig.registeredRoots` (`substation_config.dart`:53) + the `WorkList`
  targetRoot gate / `_reportRootMissing` (`work_list.dart`:117,184–195) + its flare `'root'`
  stamp (301) + `StationControl`'s `'root'` field (`station_control.dart`:59) + the multi-`--root
  <name>=<path>` grammar + `sourceControlsByRoot` builder (space `up_command.dart`:270–288).
  ONE root per substation (v3) ⇒ the selector, the extra-roots map, and the registeredRoots
  gate all vanish. Tests: `service_bundle_root_test.dart` (whole file), `track_a_root_selector_test.dart`.
- **E3 — `StationServices.stateSubstation` + the `'rig': stateSubstation` session stamp.**
  The session-ownership prefix currently derives from the killed `--state-substation` flag;
  in v3 it must derive from the station/grid identity (Q5a). Engine-deep — survives in
  CONCEPT but is re-sourced (not a blind delete). `station_services.dart`:46;
  `capability_host.dart`:348; `session_scope.dart`:169.
- **E4 — `station_lock.dart` input.** The lock ALREADY writes `<dir>/.grid/station.lock`
  (matches Q5a); only its input `stateWorkspaceDir` (from `--state-workspace`) re-sources to
  `<grid.root>`. A rename, not a delete (`station_lock.dart`:113–129; also
  `station_attach.dart`:178–268).
- **E5 — whole-file test fossils (delete, don't migrate).** grid_cli
  `test/root_flag_test.dart`, `test/workspace_flag_test.dart`, `test/discover_workspaces_test.dart`;
  space_station `test/service_bundle_map_test.dart`; grid_engine `test/service_bundle_root_test.dart`
  (dies with E2/F).
- **E6 — same-name NON-fossils to PRESERVE (don't delete on a blind grep).** `BeadsWorkspace`
  (beads_dart store type); `RootCheckout` (grid_runtime `station_git_service.dart`:19 — becomes
  plural/per-substation); `WorktreeLayout.worktreePath(String rootPath,…)` param; power_station
  `asset_loader.dart` cwd walk-up (asset-pack discovery); the `--substation` / `--owner` /
  `--bead` flags (all survive).

### Round-2 verification (2026-07-07, read-only)

The round-1 inventory was independently re-swept file-by-file: every sampled
file:line citation across all 5 packages was confirmed ACCURATE at the exact lines
(items 1–12, E1–E6 spot-checked against the live source). One genuine completeness
gap was found and closed — item 12 now lists the `space_station/status_command.dart`:114
`station['workRoot']` display consumer (the only read of the `'workRoot'` projection
field besides its `station_control.dart`:137 emit site). Two same-name matches were
re-confirmed as NON-fossils and left excluded: `git_ops.dart`'s `head`
(git-HEAD/worktree parsing, not the `--head` flag — E1) and the surviving
`substation`/`stateStore`/`dryRun` status-projection reads. No other lib-level fossil
site was missing. §7's list stands COMPLETE.

**Gate for Track H:** with the above, the fossil-deletion track has its full file:line
worklist. The two structurally-large items are **10/E2** (dissolving the `ServiceBundle`
DI seam + root selector across grid_engine's SubstationScope/CapabilityHost/WorkList/
SessionScope + power_station code assets — Track F) and **11** (the space_station
hand-mirror — Track G); the rest are flag/shim/sentinel deletions.

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

### 8.6 Round-2 re-verification (2026-07-07)

Every citation above was re-checked line-by-line against the current HEAD of all three
repos; all still exact. Spot-confirmed: the four `grid.root` reads (`bead_ownership.dart:100`,
`session_scope.dart:416`, `allocation.dart:524`, `work_list.dart:192`); the two — and only two
— brief builders org-wide (`buildAgentBrief`/`buildCriticPrompt`, both power_station
`grid_assets`); `AgentBrief` carries no path-typed field; all five harness `spawnFor`s source
`workDir` from `workspace.workspaceDir`; the working-agreement interpolation and the
`.grid/critique/<rubric>.json` critic path are workspace-derived, never bead-derived; the
`runtime_actuator.dart:120-121` `worktree`/`branch` stamp has no non-test caller and is never
read back; `dart_grid_assets` and `space_station` carry no `grid.root` read (space_station's
mentions are comments) and no brief builder. **No findings changed.**
