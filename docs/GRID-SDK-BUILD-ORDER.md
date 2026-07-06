# Build order — the code-as-config rebuild (the birth of `grid_sdk`)

**Status: DRAFT for Nico's shaping (2026-07-06).** Executes the ratified
`SCRATCH-station-config-model.md` v3 (decision-complete 2026-07-06). Beads are filed
**deferred** once this order is blessed, then undefer track-by-track (I-8 discipline:
create deferred → wire deps → undefer). **The first LIVE arm of the new runner is the
human gate**, as always.

## The unit in one line

A station is authored as a Seed: `runGrid(GridDelegate)` over
`RawAssetGrid → Station → Substations → Substation(name, root, assets)`, stores at
roots (`.beads/` = work, `<grid.root>/.grid/` = state), assets mounted at scope,
beads unstamped (references inflated at brief-build), fossils deleted — landing in the
new **`grid_sdk`** package; every runner implements the model, no shims.

## Tracks (dependency-ordered)

**Track 0 — the audits (read-only; no code).**
(a) Fossil audit: confirm SCRATCH §7's kill-list is complete (`.first`, sentinels,
fallback chains, compat aliases, `grid.root` reads) across grid_cli / grid_engine /
grid_runtime / space_station / power_station assets.
(b) Brief-inflation audit: every place prompt/brief building reads `metadata.grid.root`
or any stamped path (Q3′ requirement).
Output: findings appended to the SCRATCH doc; feeds E and H scope. *Gate for H.*

**Track A — `grid_sdk` is born.**
Workspace member, README, exports skeleton, lints. The public surface over private
`grid_engine` (ADR-0008 D2; consumers never import the engine). *No deps; parallel
with 0.*

**Track B — the composition Seeds (pure, offline).**
`RawAssetGrid(root, assets)` (raw layer, low-level services injectable) ·
`Station(root?, name, assets)` (root defaults to grid.root) · `Substations`
(MultiChildSeed fan-out; each child establishes its WorkList) ·
`Substation(name, root, assets)` (ONE root; validation in the types — an invalid
composition cannot be constructed). Asset slots as `List<Seed>`/`Seed` (Q7).
*Depends: A. The load-bearing core — candidate for central authorship per house
precedent.*

**Track C — `runGrid` + `GridDelegate`.**
The observable (`StateNotifier<GridConfiguration>`, plain value per Q6), lifecycle
rails (`didLaunch` / `initGrid` / `onReady` / `onTeardown`, errors captured +
attributed + loud), the master `build(ctx, conf)` default returning the §2 tree.
*Depends: B.*

**Track D — stores at roots + substation init.**
Grid state store under `<grid.root>/.grid/…` (Q5a; lock colocates); substation work
store discovered at `<root>/.beads` — uniformly; **the substation initialization
flow** (seed a new substation's store at its root, adopt its prefix, mount it) as
code + a documented first-class process (Q-mig). *Depends: B.*

**Track E — reference inflation.**
Brief/prompt building resolves everything from the activation (bead → substation →
root → paths); no stamped paths read from beads. Scope from Track 0(b). *Depends: 0;
parallel with B–D (touches grid_assets prompt building + runtime).*

**Track F — assets replace ServiceBundle.**
`GitGridAssets` / `GitHubGridAssets` as substation-scoped assets; harness provision as
a station-scoped asset; `ServiceBundle` + `serviceBundleMapFor` deleted; the circuit
provider/scope shape (Q8) established for circuit-mounting assets. *Depends: B.
power_station repo.*

**Track G — the runners.**
`space` = a `GridDelegate` subclass + its own CLI (the hand-mirror dies — absorbs
tg-da7); `grid_cli`'s verbs re-seated on the same model (watch/gate/rework/demo);
**no backporting, no shimming** — the station-runner pieces are replaced, tests
migrated. *Depends: C, D, F.*

**Track H — fossil deletion.**
The SCRATCH §7 kill-list, informed by Track 0(a): defaultSubstation, `substations.
first`, RootSpec/`--root`, the `--workspace` axis, `--state-*` flags,
`metadata.grid.root`, shims, sentinels, cwd discovery, the workRoot fallback chain
(subsumes tg-d7z's remit — restart walks substations now). Tests migrated, never
shimmed. *Depends: G. The unit is not done while a fossil breathes.*

**Track I — store migration (operational).**
Seed `.beads` stores at power_station/space_station roots via Track D's init flow;
migrate the open foreign-root beads out of `tg`; document the process as performed.
*Depends: D, G landed. bd-ops + Nico-adjacent.*

**Track J — acceptance + the gate.**
Derailment invariants re-anchored on the new composition (mutation-resistant, at
depth); full offline suite green; dry-run smoke over the real tree; **the LIVE arm
held for Nico**.

```
0 ──────────────┬────────────► E ─┐
A ──► B ──┬──► C ─┬───────────────┤
          ├──► D ─┤               ├──► G ──► H ──► J(gate)
          └──► F ─┘               │
                    D+G ──► I ────┘
```

## Deferred-bead reconciliation (the existing queue)

- **Absorbed by this unit:** tg-da7 (mirror audit — dies with G), tg-d7z (workRoot
  fan-out — dies with H).
- **Unaffected, still valid:** tg-uz3 (vanish heuristic), tg-4rw (mint wedge),
  tg-gpg (down orphan), tg-8p9 (mounted count), tg-a76/tg-5wb (preflights — re-home
  as delegate/type validation in C/D era), tg-irs/tg-dbd (freezed boundary),
  tg-cxw (symbol renames), tg-ghg (receipt compose), tg-wcy (superseded in shape by
  H — verify then close), tg-qkc, tg-3vq.

## Definition of done

1. A station authors its tree in Dart per the v3 sketch; `melos analyze` + full
   offline suites green in all three repos.
2. Zero fossils: Track 0(a)'s list fully deleted, no shims, tests migrated.
3. No bead carries a root stamp; briefs inflate references (0(b) verified empty).
4. `.beads/` = work store uniformly; grid state under `<grid.root>/.grid/`;
   substation-init documented and exercised (Track I performed with it).
5. The four derailment invariants enforced non-vacuously on the new composition.
6. The old boot path is gone from every runner (no `grid run`-era pieces reachable).
