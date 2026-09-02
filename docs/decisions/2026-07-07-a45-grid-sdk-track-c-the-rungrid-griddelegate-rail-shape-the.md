---
status: accepted
date: 2026-07-07
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a45-grid-sdk-track-c-the-rungrid-griddelegate-rail-shape-the
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A45"
---
## A45 (2026-07-07) — `grid_sdk` Track C: the `runGrid`/`GridDelegate` rail shape the ratified v3 model left to the implementer (tg-tv3)

**Decision (AI; `grid_sdk` only):** built Track C of `GRID-SDK-BUILD-ORDER.md` (v3 §4) — `GridDelegate extends StateNotifier<GridConfiguration>` (the observable), the four lifecycle rails, the master `build(context, configuration)`, and `runGrid(delegate)` mounting *delegate provision → configuration provision → build* and returning a `GridHandle`. The ratified model (`SCRATCH-station-config-model.md` §4, Q6) pins the surface and the "captured/attributed/loud" posture but leaves four shape choices open; recorded here:
- **The rails' temporal ordering + the terminal/non-terminal failure split.** §4's semicolon list (`didLaunch` pre-tree; `initGrid` post-mount async, unawaited; `onReady`; `onTeardown`) does not pin `onReady`'s relation to `initGrid`. Chose: `didLaunch` (sync, pre-tree) → mount → `initGrid` (async kickoff, **unawaited** by the caller) → `onReady` fires **only when `initGrid` resolves successfully** (they are a kickoff→done pair) → `onTeardown` at `GridHandle.teardown`. A `didLaunch` failure is **terminal** (the tree never mounts) so it is *thrown*; the three post-mount rails cannot throw to a caller, so their failures route through `runGrid`'s error sink and the running grid stands (non-aborting). `onTeardown` failure is loud but teardown still unmounts + disposes.
- **The named-refusal channel.** A single `GridHookError(hook, delegateType, cause, causeStackTrace)` (an `Error`) is the guard-principle vehicle for "attributed + loud". `didLaunch` **throws** it from `runGrid`; the post-mount rails hand it to `runGrid`'s optional `onError` sink, whose **default rethrows into the current zone** (`Zone.current.handleUncaughtError`) so an unhandled refusal is never swallowed. `didLaunch` deliberately does **not** also go through `onError` (the throw is the loud channel — no double-report).
- **The default `build` shape + no-default-root.** The base `build` returns the §2 **root** — `RawAssetGrid(root, assets)` — where `root` is a **throwing getter** (v3 §0: there is no default root — a loud refusal, proven by the "bare delegate refuses LOUD" test) and `assets` an empty-default `List<Seed>`. These two are the ONLY compose hooks the base ships; the v1 docs-debt-sweep §3.2a `build*(context, child)`-on-rails / `@mustCallSuper` chain stays **dead** per v3 §4 ("convenience hooks earned, not designed up front"). A full station (§2's `SpaceStationAsASeed`) overrides `build` wholesale and never touches `root`.
- **`GridConfiguration` carries an opaque `settings` map** (the TOML-load-result placeholder), deep-compared so an equal re-emission does not churn the tree — rather than an empty marker; **no `of<T>` aspect machinery** (the §2 pseudo's `GridConfiguration.of<ButaneGridConfiguration>` stays aspirational per Q6). `runGrid` owns the `TreeOwner` + a coalesced-microtask flush loop (mirroring `StationKernel`) so a watched configuration **re-composes** (v3 §1); `state_notifier` is re-exported from the barrel (one import authors a station).
**Why:** the model fixes the delegate's three surviving responsibilities and the loud-refusal posture, but leaves the rail sequencing, the throw-vs-sink split, the base `build`/`root` default, and the config value's shape to the implementer — the kind of API-shape decision ADR-0000 exists to surface before it is silently baked in. No framework service/source layering was added (the v2 `buildServices`/`buildSources` split is dead — assets mount in the tree at scope, Track B).
**Not this:** the concrete `space` delegate + its CLI (Track G), asset types replacing `ServiceBundle` (Track F), and the store-at-root wiring (Track D) are later tracks — Track C is the pure, offline SDK entry + rails only. No engine coupling (grid_sdk depends on the Track-B composition Seeds, not `grid_engine`'s `Station`/`WorkList`).
**Affects:** `grid_sdk` only — new `lib/src/run/{configuration,grid_delegate,run_grid}.dart` (+ `configuration.freezed.dart`), the barrel exports, a `state_notifier: ^1.0.0` dep, and `test/track_c_run_grid_test.dart` (13 tests). `melos analyze` clean; grid_sdk 25 offline tests + the full workspace offline suite green. No other package consumes `grid_sdk` yet (Track G wires it) — the change is isolated.
**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (an ADR-0002 `grid_sdk` row / an ADR-0008 D1–D2 amendment) or dispose at will.

