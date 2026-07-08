# Stores at roots + the substation initialization process

**Status: the documented first-class process for Q5a + Q-mig** (executes
`SCRATCH-station-config-model.md` v3, ratified 2026-07-06; delivered in
`grid_sdk` Track D, tg-y1b). This is an *operational/how-to* doc, not an ADR — it
documents ratified decisions, it does not make new ones.

## 1. The one rule: a store lives at a root

Under v3 there is exactly one place a store can be, and one meaning for the
`.beads/` directory:

| Store | Where | What lives there |
|---|---|---|
| **Substation work store** | `<root>/.beads/` | the project's work beads (the read-only work source) |
| **Grid state store** | `<grid.root>/.grid/.beads/` | the_grid's OWN session / cursor / gate lifecycle beads |
| **Station lock** | `<grid.root>/.grid/station.lock` | one-supervisor-per-station arbitration (colocated) |

**`.beads/` at a root means *work store*, uniformly, everywhere** (Q5a). The
grid's state store is *not* a `.beads/` at a root — it nests one level under the
runtime dir `.grid/`, so the **dual-role repo** (a grid whose own root is also a
substation under development, e.g. `space_station` eating itself) holds its work
store at `<root>/.beads/` and its state store at `<root>/.grid/.beads/` with **no
collision** and **no special case** in the types.

Discovery is **exact at the root** — there is no walk-up. The old cwd/parent
search (`BeadsWorkspace.discover` climbing 12 levels) is the ambience the v3
model kills (SCRATCH §7 item 9). A substation names its ONE root; its store is
there, or its absence is a **LOUD boot refusal** (`StoreRefusal`) telling the
operator to run the init process below (or fix the root) — never a silent
upward search that binds the wrong store.

### The SDK surface (`grid_sdk`)

```dart
// Locations derive from a root, or from the Track B scopes:
GridStateStore.forGridRoot('/home/space_station').beadsDir;   // …/.grid/.beads
SubstationWorkStore.forRoot('/work/the_grid').beadsDir;        // …/.beads
gridRootScope.stateStore;                                      // from GridRoot
substationScope.workStore;                                     // from SubstationScope

// Discovery — exact-at-root, LOUD refusal if absent:
final store = StoreLocator().locateWorkStore(
  root: '/work/the_grid',
  substationName: 'the_grid',
);   // throws StoreRefusal when /work/the_grid/.beads is missing (no walk-up)
```

## 2. The substation initialization process (Q-mig)

Onboarding a new project into a station is a **first-class, three-step process**.
It ships as code (`SubstationInitializer`) *and* as this documented procedure.

> **Seed a new store at the root → adopt its prefix → mount it in the tree.**

### Step 1 — Seed the store at the root

A substation's **name and its store's id-prefix are SEPARATE axes** (Nico,
2026-07-08 — correcting this doc's earlier name-is-prefix conflation, which was
never ratified): the name is the `metadata.rig` marker and the tree identity;
the prefix is the short id shape (`tg` precedent). Seeding is
`bd init --prefix <prefix>` in the substation's root:

```bash
cd /work/power_station
bd init --prefix pow               # creates /work/power_station/.beads, ids pow-…
```

`SubstationInitializer` does this behind an injected `BeadStoreSeeder` seam (the
default shells out to exactly the command above), so the flow is offline-testable
and the real `bd init` is a one-line swap.

### Step 2 — Adopt the prefix

There is nothing extra to "adopt": because the name **is** the prefix, seeding
with `--prefix <name>` *is* the adoption. Every bead minted in the new store
carries the `<name>-…` id, and the_grid's ownership predicate recognizes the
project by that prefix (and by the `metadata.rig == <name>` marker).

The flow enforces the prefix contract up front — a substation name must be a
single token (no whitespace, no path separators), refused LOUD before any seed.

### Step 3 — Mount it in the tree

Add the substation to the station's `Substations` fan-out. The init result hands
you the Track B `Substation` seed directly:

```dart
final result = await SubstationInitializer().initSubstation(
  root: '/work/the_grid',
  name: 'the_grid',
);
// ... then, in the station author's build():
Substations(
  substations: [
    result.toSeed(assets: [GitGridAssets(/* … */)]),   // == Substation(name:'the_grid', root:'/work/the_grid', …)
    // … the station's other substations …
  ],
)
```

`toSeed()` is the same `Substation(name, root, assets)` an author writes by hand —
initialization does not create a special node type, it just guarantees the store
exists first.

### The guards (LOUD, never silent)

- **No clobber.** A root that already holds a `.beads/` store is refused — init is
  for a *new* substation; re-seeding an existing store is not this flow's job.
- **Post-seed verify.** After seeding, the store must exist; a seeder that
  silently no-op'd is caught here, not later at the mount boundary.
- **Absolute root.** A cwd-relative root is refused (the ambience fossil).

## 3. A37, restated — no pseudo-substation

**Sessions and cursors write ONLY to the grid state store, through the single bd
write chokepoint** (`StationBeadWriter`) — never to a substation work store (a
work source is read-only; A37). Under v3 this needs **no pseudo-substation**: the
old separate `tgdog`-style state DB (a fake substation the_grid minted its own
beads into) is gone. The grid's state store is simply the grid's own store at
`<grid.root>/.grid/.beads/`.

The type system reflects it: `GridStateStore` is a distinct type at a distinct
location; it is **never** a `Substation`, never appears in the `Substations`
fan-out, and carries no work. The chokepoint's fail-closed ownership check still
holds — every session/cursor/gate write is asserted owned before it lands. The
foreign work stores stay pristine (invariant: the_grid never mutates the work
source it reads).

*(The engine's `StationServices.stateSubstation` string — the last residue of the
`--state-substation` flag — is re-sourced from the grid identity rather than a
flag in Track E/H; this doc records the target shape, Q5a. The location and the
"no pseudo-substation" posture are settled here.)*

## 4. As performed — Track I (tg-rh3, 2026-07-08)

Executed live by the operator (station quiesced, frontier empty):

| Store | Root | Prefix | How |
|---|---|---|---|
| power_station work | `power_station/.beads/` | `pow` | `bd init --prefix pow` |
| space_station work | `space_station/.beads/` | `space` | `bd init --prefix space` |
| grid state | `space_station/.grid/.beads/` | `houston` | `bd init --prefix houston` (see finding below) |

- **Naming (Nico):** names ≠ prefixes (§2 corrected); state-store prefix =
  **houston**. `SubstationInitializer` still conflates them — follow-up bead
  gives it a `prefix:` parameter.
- **FINDING — bd-init walk-up vs the nested state store:** `bd init` inside
  `.grid/` walks UP, finds the root's work store, and refuses ("already
  initialized"). The dual-role layout is fine at *runtime* (our discovery is
  exact-at-root) but seeding the nested store needs a bridge: temporarily
  `mv .beads .beads-hold` → init in `.grid/` → restore. The follow-up
  initializer bead should own this (or upstream a no-walk-up init flag).
- **Migration:** the three open `grid.root: power_station` beads moved:
  tg-2dp→pow-ff4 · tg-r3l→pow-efv · tg-ghg→pow-yny (stamps stripped,
  `migrated_from` provenance kept; originals closed in `tg` with pointers).
  `tg` remains the_grid's own work store (city dolt, gc coexistence unchanged).
- **tgdog retired:** archived read-only to `archive-tgdog-20260708` (~$750 of
  session telemetry queryable until Nico deletes it). Nothing may ever be
  named tgdog again.
