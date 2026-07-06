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
