---
status: accepted
date: 2026-07-07
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a46-grid-cli-track-g-cli-half-the-four-generic-verbs-bind-to
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A46"
---
## A46 (2026-07-07) — `grid_cli` Track G (cli-half): the four generic verbs bind to the store-at-roots model by **root**, not by harvesting a delegate (tg-hsh)

**Decision (AI; `grid_cli` only):** re-seated the four generic verbs (`watch` / `gate` / `rework` / `demo`) on the v3 store model (`GRID-SDK-BUILD-ORDER.md` Track G, cli-half; `SCRATCH-station-config-model.md`) — the `--workspace` / `--state-workspace` / `--state-substation` / `BeadsWorkspace.discover()` (cwd walk-up) axis is **replaced, not shimmed**. The ratified order fixes the direction ("re-seat on the runGrid/GridDelegate model; tests construct delegates over fakes") but leaves the *binding mechanism* to the implementer; recorded here:
- **The verbs bind by ROOT, not by reading a `GridDelegate`.** The model's operator-facing currency is the **root** (an absolute path a delegate authored), because neither delegate-facing accessor is usable for a verb: (a) `GridDelegate.root` is a throwing getter that a wholesale-`build` station (§2's `SpaceStationAsASeed`, A45) never overrides, so it is *not* a reliable station→grid-root accessor; (b) the substation roster is **not harvestable** from a mounted delegate — genesis_tree hides `InheritedBranchBase` from its exports, so a tree-walk cannot read the `SubstationScope` values out of an arbitrary delegate's composition. So state-store verbs take the **grid root** (`--grid-root` → `GridStateStore.forGridRoot`) and work-store verbs take a **substation root** (`watch <root>` / `rework --note-root` → `SubstationWorkStore.forRoot`). A composed runner (`space`) supplies the roots it authored; the standalone reference bin takes them explicitly. Tests construct the model's store values over fakes (the interpretation of "delegates over fakes" — the store-at-roots model, not a literal `GridDelegate` instance the verbs cannot mine).
- **A hard no-walk-up existence gate** (`packages/grid_cli/lib/src/station_stores.dart` — `openStateStore` / `openWorkStore`): each opener gates existence through the pure `StoreLocator` (Track D) BEFORE `BeadsWorkspace.discover(start:)`, so discovery matches at the exact root on the first iteration and can never walk up into a parent — critically, the grid state store at `<grid.root>/.grid/.beads/` can never be confused for the grid root's own `.beads/` WORK store one level up (A37). Absence is a LOUD `StoreRefusal`, never a silent default.
- **The ownership prefix is a supplied VALUE, not a flag.** `--state-substation` (+ its `tgdog` default) dies with the rebuild (Q5a: the tgdog home dies); the state-store ownership prefix survives as `--prefix` (required for the `resolve` / `rework` writes — a fail-closed write never runs without a named owner). `gate ls` (read-only, lists all open gates) takes no prefix. The engine-side re-sourcing of the session/gate `metadata.rig` stamp from the station/grid identity (SCRATCH E3) is **not** in this half — it stays Track H (fossil deletion).
**Why:** the store binding is the one shape the ratified order leaves open, and the two "obvious" delegate-facing bindings are both structurally blocked (a throwing `root`, a hidden `InheritedBranchBase`) — a naming/semantic decision ADR-0000 exists to surface before it is baked in. Binding by root keeps the verbs self-contained CLI-SDK Commands (`space` assembles them no-arg, unchanged) while killing every discovery fossil they carried.
**Not this:** the `station_runner.dart` assembly (`addStationFlags`/`discoverWorkspaces`/`buildControllers`/`composeStation`) and the `space` runner's own verbs (`up`/`down`/`status`) are the space-half + Track H's remit — untouched here. `ServiceBundle` dissolution (Track F) is untouched (the four verbs never consumed it). No engine change; no `GridDelegate` API change (A45's surface stands).
**Affects:** `grid_cli` — a `grid_sdk` dep; new `lib/src/station_stores.dart`; `watch`/`gate`/`rework`/`demo` re-seated; `test/{gate,rework}_command_test.dart` migrated to construct stores over fakes (+ CLI-wiring fail-closed proofs that the retired flags are GONE). `melos analyze` clean; grid_cli 184 offline tests + the full workspace offline suite green. No other package changed.
**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (an ADR-0002 `grid_cli` row / an ADR-0008 D2 amendment) or dispose at will.

