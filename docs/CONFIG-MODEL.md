# CONFIG-MODEL — code as config: the grid composition model & `runGrid`

**Status of THIS document: Proposed (drafted 2026-07-19) — awaiting Nico's
ratification.** The MODEL it restates is already ratified: the **v3
station-config model was ratified by Nico 2026-07-06** in
[`SCRATCH-station-config-model.md`](SCRATCH-station-config-model.md), from which
this document **graduated 2026-07-19** as the durable home of §1–6, including
the closed questions (Q3′, Q5–Q8). The SCRATCH remains in place as design
history — its v1/v2 lineage and its §7a/§8 point-in-time fossil audits
(2026-07-07) are archive-only and are not restated here. This is a **faithful
restatement, not new design**; where this text and the SCRATCH diverge, the
SCRATCH's ratified rulings win. Load-bearing symbols were verified against the
shipped `packages/grid_sdk` surface on 2026-07-19 (see §7).

## 1. The thesis: code as config

Just as the org went Dart-first before TOML, the grid goes **code-first before
configuration**. A station is not "configured" by a value the framework
interprets — it is **built**, as a tree, in Dart, by its author. Plain language
features *are* the configuration language: an `if (kDebug)` mounts a
substation; a `for` fans out; a watched value re-composes. `GridConfiguration`
stays **thin** — plausibly nothing more than the result of TOML loading,
provided *into* the tree like any other value (whether it carries aspected
domains à la an app-configuration is **deliberately deferred** until TOML work
forces the question — earn it).

Consequence for the v2 delegate: the `buildServices` / `buildSources` hook
split **died** — it was framework-owned layering where the model wants
**assets mounted in the tree at the right scope**. What survives of
`GridDelegate`: lifecycle rails + config provision + the master `build` (§4).

## 2. The canonical tree

The load-bearing shape (the SCRATCH §2 holds Nico's original 2026-07-06 pseudo
sketch; this is the same shape in the shipped `grid_sdk` vocabulary):

```dart
class SpaceStationDelegate extends GridDelegate {
  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    return RawAssetGrid(
      root: gridHome,                      // absolute; state store lives here
      assets: [                            // grid-scoped: serve the deployment
        Station(
          name: 'space',                   // root optional → grid root
          assets: [                        // station-scoped: serve the machine
            Nest(
              children: [StationWork(wiring: wiring)],
              child: Substations(
                substations: [             // the MultiChildSeed fan-out
                  Substation('the_grid', '../the_grid', prefix: 'tg',
                      assets: [const SubstationWork()]),
                  Substation('genesis', '../genesis',
                      assets: [const SubstationWork()]),
                  if (kDebug)              // eating itself
                    Substation('space_station', '.',
                        assets: [const SubstationWork()]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
```

A domain substation is **composition, never a `Substation` subclass**: a seed
whose `build` *returns* a `Substation` — reading config from context, watching
live state, conditionally mounting its assets (the SCRATCH §2's
`ButaneDevelopmentSubstation` is the canonical illustration).

## 3. The pieces

- **`RawAssetGrid`** — the raw root, the WidgetsApp-to-MaterialApp
  relationship: unopinionated, possibly rawer still. A batteries-included
  `Grid` analogue can layer on top later. Its `root` is the grid's home; the
  grid's **state store** lives there (the grid has no work store).
- **`assets:` slots on Grid / Station / Substation** — `List<Seed>` (Q7). An
  asset is *anything mounted into the tree at a scope* (glossary R3 made
  literal): config providers, federation discovery, harnesses, source control,
  circuits. Grid-level assets serve the deployment; station-level assets serve
  the machine; substation-level assets serve the project. **This is where
  `ServiceBundle` dissolved**: per-substation git/GitHub are just assets
  mounted under that substation.
- **`Nest`** — genesis_tree's chaining container
  (`children: List<SingleChildSeed>`, outermost-first, folded around `child`).
  The grouping idiom for asset stacks; used everywhere.
- **`Station(name, root?, assets)`** — the machine. `root` optional, defaulting
  to the ambient grid root; with neither, it refuses loud — **there is no
  default root**.
- **`Substations(substations: [...])`** — a `MultiChildSeed` owning the
  fan-out: each child `Substation` establishes its work.
- **`Substation(name, root, assets)`** — a project: ONE root; work store at the
  root. Extended by **composition**, never subclassed — composed substations
  read config from context, watch live state, and conditionally mount their
  assets.
- **`DomainConfigurationProvider`** — does not exist yet; async config loading
  AS a tree node (the tree must handle a not-yet-loaded configuration
  gracefully). Lumped into the TOML discovery.
- **`ZeroConfGridProvider` / `MqttGridProvider`** — not built yet; federation
  membership as mounted observers at grid scope: discovery events are observed
  state; membership changes reconcile (the dynamic-membership assumption made
  structural).
- **Circuit provider / circuit scope** (Q8) — an asset that mounts a circuit
  into a substation's scope, making it available for that substation's work
  (the resolver seam, asset-shaped). The word "Order" in the original sketch
  was wires-crossed lineage: in gc, an *Order* pairs a trigger with a formula —
  the **when** axis over the formula's **what** — fired by the controller's
  30-second tick. A grid analogue of the *when* axis, if it ever earns its way
  in, is a separate future design — and must respect the no-clock posture (the
  engine is event-driven; triggers would be observed state, never a tick).

## 4. `GridDelegate`, re-scoped (rails, not layers)

The delegate keeps: **being the observable**
(`StateNotifier<GridConfiguration>`, thin), the **lifecycle rails**
(`didLaunch` pre-tree; `initGrid` post-mount async kickoff, unawaited;
`onReady`; `onTeardown`; hook errors captured/attributed/loud — the shipped
`GridHookError`), and the **master `build(context, configuration)`** returning
the station tree (§2's build IS that method). It loses: any framework-owned
service/source layering — those are assets in the tree. Convenience build
hooks may be added later as sugar over asset mounting, derived from real
usage — earned, not designed up front. `runGrid(delegate)` mounts: delegate
provision → configuration provision → `build`. Every runner — `space`,
`grid_cli`'s verbs, anything composed — implements this model; **no
backporting, no shimming**.

## 5. Closed questions (Nico, 2026-07-06)

- **Q3′ CLOSED — beads carry no root stamp.** Kill `metadata.grid.root`. Beads
  hold **references**; anything an agent needs (repo path, worktree location)
  is resolved at **brief/prompt inflation time** from the activation — the
  bead's substation → its root — never read from a stamp on the bead.
  Rebuild-unit requirement: the brief-building step inflates references (the
  SCRATCH §8 audit verified the brief path already holds this).
- **Q-mig CLOSED — yes.** The rebuild unit creates **and documents** the
  substation initialization process (seeding a new substation's store at its
  root, adopting its work, registering it in the tree).
  New-substation-init is a first-class, documented flow (shipped:
  [`SUBSTATION-INIT.md`](SUBSTATION-INIT.md)).
- **Q1/Q2/Q4 (from v2):** BOTH TOML and Dart; `runGrid(GridDelegate)` +
  `GridConfiguration`; home = **`grid_sdk`** (the unit births the package).

## 6. Open questions — ALL CLOSED (Nico, 2026-07-06)

- **Q5 CLOSED — (a).** The grid state store lives under the runtime dir,
  `<grid.root>/.grid/…`; **`.beads/` means *work store*, uniformly,
  everywhere.** The dual-role repo (implementation instance + self-substation
  under development) holds its grid state under `.grid/` and its work store at
  `.beads/` with no collision. The separate tgdog-style home directory dies
  with the rebuild.
- **Q6 CLOSED — plain values for now.** `GridConfiguration` is a plain value
  (e.g. the TOML-load result). No domain/aspect machinery until something real
  demands it.
- **Q7 CLOSED — open parameters for now.** Asset slots are `List<Seed>` or
  `Seed`; no dedicated wrapper type yet. Naming rule: **`Raw` prefixes for
  cumbersome object names/constructors** (the `RawAssetGrid` pattern — raw
  layer explicit, friendly layer earns its name later). The shipped surface
  settled on `List<Seed>` uniformly.
- **Q8 CLOSED — it's a Circuit provider/scope** (§3). "Order" was crossed
  wires; gc's Order (trigger→formula, the *when* axis) stays gc-compat
  vocabulary; any grid when-axis is a separate future design, clockless.

## 7. Shipped surface (verified 2026-07-19, `packages/grid_sdk`)

The model above is implemented and landed: `runGrid`/`GridHandle`
(`lib/src/run/run_grid.dart`), `GridDelegate` + `GridHookError`
(`lib/src/run/grid_delegate.dart`), `GridConfiguration`
(`lib/src/run/configuration.dart`), `RawAssetGrid` / `Station` /
`Substations` / `Substation` (`lib/src/composition/composition.dart`), the
ambient scope values `GridRoot` / `StationScope` / `SubstationScope`
(`lib/src/composition/scopes.dart`); `Nest` is re-exported from
`genesis_tree` by the barrel. Two shipped refinements post-date v3 and are
ratified elsewhere, not here: `Substation` carries a **`prefix`** identity
axis defaulting to `name` (Nico, 2026-07-08 — `SUBSTATION-INIT.md` §2), and a
substation root may be authored **grid-root-relative**, resolved against the
ambient `GridRoot` at build (`tg-32r`). The package tour is
[`packages/grid_sdk/README.md`](../packages/grid_sdk/README.md); the build
breakdown is [`GRID-SDK-BUILD-ORDER.md`](GRID-SDK-BUILD-ORDER.md).
