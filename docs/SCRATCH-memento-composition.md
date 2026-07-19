# SCRATCH — memento composition (space_station is memento's grid instance)

**Status: DESIGN — decision-complete (session with Nico, 2026-07-10). Both forks
RESOLVED (§3); anchor bead filed deferred (`space-6ds`).** Graduation target:
a space_station bead (the anchor of `space`'s backlog) + likely an ADR-0008 D1
amendment (the "grid instance" is authored, not flag-injected). Filed only after the
forks resolve; per intake, **deferred** until Nico blesses.

This surface was written while Nico stepped away mid-decision. It records the settled
context and my recommended defaults so the forks can be answered in one line, and logs
the one authorized action taken (the `tg-fc6` re-home). Nothing here is ratified.

---

## 0. The decision, precisely

**space_station is memento's grid instance. The entire `memento-engineering` org composes
into it as *coded* substations — authored in `SpaceDelegate.build()`, not injected via
`--substation <name>=<root>` flags at arm time** (Nico, 2026-07-10).

Today (`space up`, post-`runGrid` bridge — see §2) the substation roster arrives as
`--substation <name>=<root>` flag pairs, with **no default** (up refuses to arm with none:
"v3 §0: there is no default root and no default substation"). Per the ratified v3
code-as-config model (`SCRATCH-station-config-model.md` §2: *the tree is the config; `if`
mounts a substation, `for` fans out*), the roster belongs authored in `build()`. Flag
injection of the roster is the transitional shortcut this bead retires.

## 1. The substation roster (memento-engineering, buildable backlogs)

Scanned 2026-07-10. **Five** memento-engineering repos have bead stores with real work
(all confirmed via `gh` — `origin` is `memento-engineering/<repo>`):

| Substation | Store / prefix | Open | Kind | Note |
|---|---|---|---|---|
| **genesis** | `genesis/.beads` · `genesis` | 2 | substrate | driven in the first live arm today; not yet standing |
| **the_grid** | `the_grid/.beads` (Dolt **server** `tg`) | 24 | the framework — **self-host** | shared server w/ gc → coexistence, §4 |
| **power_station** | `power_station/.beads` · `pow` | 3 (+1 re-homed today) | the asset packs — **self-host** | embedded Dolt |
| **space_station** | `space_station/.beads` · `space` | ~0 | the runner — **self-host** | embedded Dolt; this bead lands here |
| **lenny** | `lenny/.beads` | 50 | the debug harness | **memento-engineering** (`origin`=`memento-engineering/lenny`); **relocated 2026-07-10** from its prior personal-checkout home → `engineering.memento/lenny`, so the coded `../lenny` root now resolves |

So composing "the entire memento-engineering" means the grid **self-hosts** its own three
construction repos, drives the substrate (genesis), and drives the debug harness (lenny).
Out of roster:

- `decisions/`, `expression/` — no bead store yet (add a literal `Substation()` when they gain one).
- `genesis-grid` — the stale June-16 dogfood clone (retired `grid run --workspace` path).
- `archive-tgdog-20260708` — the retired state store, archived at the `houston` cutover.

The runtime **state store** is `houston` (`space_station/.grid/.beads`, ex-`tgdog`) — not a
substation; it holds session/lifecycle beads (A37 split).

## 2. Why this is unblocked now — the runGrid→engine bridge landed

The attachment mechanism is live as of two days ago (space_station `b666b04` Track J1 /
`fb99968` tg-r81). `space up` no longer uses the transitional `composeStation` ladder — it
**arms the real tree via `runGrid(SpaceDelegate)`** over stores-at-roots, with an armed
`StationWork`/`SubstationWork` seat the engine's `WorkList` binds into. So authoring the
roster in `build()` drops straight into a working live-drive path; this bead is roster
authorship + flag retirement, not new plumbing.

## 3. The forks — RESOLVED (Nico, 2026-07-10)

**Fork A — roster form: LITERAL, HARDCODED `Substation()` instantiation.** Not a manifest,
not a `for`-loop, not filesystem discovery. Each memento repo is a direct `Substation(...)`
call in `build()`, with **sibling-relative roots** (`../genesis`, `../the_grid`, …) that
bake in the opinion that the org repos sit **side-by-side** in the umbrella checkout —
space_station *is* memento's grid instance and knows its siblings by name. (My
"coded manifest" recommendation was wrong; "coded into the tree" meant *hardcoded*.)

```dart
Substations(substations: [
  Substation(name: 'genesis',       root: '../genesis',       assets: [...]),
  Substation(name: 'the_grid',      root: '../the_grid',      assets: [...]),
  Substation(name: 'power_station', root: '../power_station', assets: [...]),
  Substation(name: 'space_station', root: '../space_station', assets: [...]),
  Substation(name: 'lenny',         root: '../lenny',         assets: [...]),
]),
```

**Fork B — the flag/config is an APPEND/MERGE layer, not a replacement.** The hardcoded set
is the base/default. **Parameterized configs — `--substation` now, TOML eventually —
append onto or merge into** that base (add new substations; merge overrides onto a coded one
by name). Neither retired nor a subset-filter. So the composition layers:
`hardcoded coded roster (base)  ⊕  parameterized flags  ⊕  TOML (future)`.

## 4. Sub-decisions (spec-level, not blocking)

- **genesis root — direct vs clone.** Point the genesis substation at `genesis/` directly
  (worktrees cut under `genesis/.grid/worktrees/`, gitignored; `genesis/` main untouched
  since worktrees are isolated branches) vs. a clone (the genesis-grid pattern, extra
  isolation). Recommend **direct** — the A37 pristine concern is the *bead store* (never
  write foreign work beads; session beads go to `houston`), which stores-at-roots already
  honors. Clone only if we want `genesis/` itself free of `.grid/`.
- **the_grid coexistence.** `tg` is the shared Dolt **server** (gc lives there too on `ga-*`).
  Driving the_grid reads `tg`'s ready frontier (its own `tg-*` beads) while session beads
  write to `houston` — the A37 split already fences this. No new coexistence risk beyond
  the standing rules (single writer per bead; never touch gc's beads/hooks).
- **Mainline-reconcile before arming (from `tg-fc6`/`pow-*` today).** 4/6 genesis beads
  were stale (already shipped) at arm time. The composition should pair with an intake
  discipline: reconcile a substation's ready frontier against mainline before it's armed,
  so the station never drives already-landed work. (Enforcement is the re-homed committee
  bug; the *discipline* is a backlog-refinement rule — §6.)

## 5. The anchor bead — FILED (`space`, deferred)

> **space: hardcode the memento substations in `SpaceDelegate.build()`; parameterized/TOML
> config appends onto the coded base.** Author genesis + the_grid + power_station +
> space_station + lenny as **literal `Substation()` instantiations** (Fork A) with
> sibling-relative roots; the `--substation` flag (and future TOML) **appends/merges** onto
> that base (Fork B), never replaces it. `space up` with no flags arms memento's grid
> instance. Coexistence-aware per §4. Acceptance: no-flag `space up` mounts all five coded
> substations; each resolves its `../<repo>` root + per-substation git assets; `--substation`
> appends a new one / merges an override by name; dry-run smoke; the_grid reads `tg` while
> sessions write `houston`. Store: `space`. Type: feature. Deferred until blessed.

## 6. How this anchors the backlog refinement (the wider task)

Composition defines *which backlogs the station drives*, so the refinement runs per store:

- **`space` (runner):** the anchor bead above; then the runGrid follow-ups, `space install`
  (launchd automation), the OP arming ladder, the multi-substation live-arm hardening.
- **`genesis` (driven substation):** currently 2 open — populate with buildable work so the
  self-firing station has genesis work queued; apply the mainline-reconcile intake (§4).
- **`tg` (station/self-host):** structure the 24-item flat pile into themes
  (engine/session correctness · runtime supervision · arming ladder · consistency sweeps ·
  docs), wire deps, close the **RS epic `tg-3s8`** (ladder RS-1..RS-8 all shipped —
  closeable pending its ADR-0013 graduation, Nico's to write).
- **`pow` (assets):** structure the 3 + the re-homed `tg-fc6`; queue the parked
  third-party-harness ladder (A-1…B-4, `SCRATCH-third-party-harnesses.md`) once ratified.

## 7. Actions log (this session)

- **Re-homed `tg-fc6` → `pow` (authorized "re-home now", 2026-07-10).** Live-arm committee
  bug (critics graded pre-existing mainline as the bead's diff). Now **`pow-6wo`** (deferred,
  bug, p2); `tg-fc6` closed with a pointer. It belongs in power_station (committee lives in
  `grid_assets`).
- **`tg-qkc` held in `tg`** (NOT blindly re-homed) — genuinely ambiguous: the
  `Lease/ServeCommand` *adapters* are CLI-surface (station), but the *logic* may extract
  into `federated_grid_assets` (substation). Decide at execution / re-audit; a no-op close
  is a valid outcome per the bead.
- **`tg-3s8` (RS epic) left open** — the whole ladder is shipped, so it's closeable, but its
  design still owes a graduation to **ADR-0013** (Nico's numbering/call). Flagged, not closed.
