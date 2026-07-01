# The Dart Runner Experience + the CLI SDK (design note)

**Status:** DESIGN — doc-before-code, from a design session with Nico (2026-07-01). **Not an ADR
and not ratified**; a design surface for Nico to react to / ratify. It refines **ADR-0008** (the
SDK split D1 + the asset model) and the CLI's role; forward-pointer stamps land on the home ADR(s)
only on ratification (never silently). Numbering is Nico's to assign.

## Why

The burn-readiness audit (2026-07-01) confirmed a long-standing Nico critique: `grid run` is an
over-opinionated monolith — `runGridTree`/`composeRunTree` weld in the `code` asset
(`FormulaResolver(_codeFormulaFor)` + `buildCodeRegistry()` + a git `ServiceBundle`), so a second
asset (the burn) can't be reached and every new asset would be a CLI edit. The fix is NOT a
`grid burn` command (more opinion in the monolith) — it's to make the CLI compose the way
everything else in the_grid composes.

## The decisions (from the session)

1. **the_grid is a FRAMEWORK, not a turnkey tool** (the Flutter model). A **station is a
   user-built, AOT-compiled Dart runner** — a `main.dart` composed against the SDK, `dart compile
   exe`'d. the_grid "shouldn't work (very) well out of the box" — by design (like `flutter` does
   nothing until you write an app).
2. **Dart-first; TOML deferred.** The TOML experience circles back later and is "dumber anyway";
   its **spec is Gas City's, not ours to change** — the only open TOML question is how we *address*
   asset packs / tool calls. **No JIT yet** — the paths are the (later) TOML CLI *or* a coded
   runner; no dev-time compose-by-address middle path. OOTB (TOML) runners can only run TOML
   setups; **dynamic code / a better experience → you code it.**
3. **There is no generic `grid run` for a coded station.** No JIT ⇒ you run *your* compiled binary,
   not a CLI flag-fest. The `code`-welded `grid run` retires.
4. **the_grid ships a CLI SDK** — reusable CLI components an author assembles into a runner:
   - asset-agnostic driving commands (watch / gate / step / observe / leonard-attach);
   - a de-opinionated **`StationRunCommand`** base that owns the live-wiring (`composeStation` +
     workspace discovery, controllers, exploration host, the barrier→restart→mount ordering,
     gating) and takes the **asset trio** (resolver / registry / services) as configuration.
5. **A `grid_asset` package exports reusable CLI components ALONGSIDE its domain components.** The
   code asset exports a configured `CodeRunCommand`; the burn asset later exports `BurnCommand`.
   This is the crux insight: an asset's *offering* = {domain components + CLI components}.
6. **An app assembles the Commands it wants into its own `CommandRunner` `main.dart`** and
   AOT-compiles. That app is `space_station` (memento's grid application + config).
7. **Self-hosting framing (Nico's, over mine):** a running **the_grid instance builds and debugs
   *itself* and *the_grid*.** Weak today (build half proven; the leonard-debug half proven but
   unexercised — A40); it "comes to life" once bug-reporting domains exist. The Dart experience is
   the on-ramp.

## The three repos (target)

| Repo | Role |
|---|---|
| `memento_engineering/the_grid` | the kernel + SDK + core toolchain (engine / controller / runtime / reconciler / exploration / devtools / federation) + the **CLI SDK** + (later) the TOML PackInflater |
| `memento_engineering/power_station` | first-party `*_grid_assets` packages (the `code` asset, the burn, compute, dart/flutter packs, "the factory") — each exporting **domain + CLI components** |
| `memento_engineering/space_station` | memento's grid **application + configuration** — its assembled runner `main.dart` + config |

The **physical repo split is a later mechanical move**; the *seams* (CLI SDK vs asset-exported
Commands vs an assembled runner) land first, inside the current `the_grid` workspace.

## The shapes

```dart
// the_grid · CLI SDK — the de-opinionated base (owns the live-wiring)
abstract class StationRunCommand extends Command<int> {
  StationRunCommand({
    required String name,
    required this.resolver,       // bead → formula
    required this.registry,       // capabilities + formulas
    required this.servicesFor,    // (config) → ServiceBundle (per-substation)
  }) { /* common flags: --substation/--state-workspace/--bead/--dry-run/--root/--head … */ }
  final FormulaResolver resolver;
  final CapabilityRegistry registry;
  final ServiceBundle Function(RunConfig) servicesFor;
  @override
  Future<int> run() => runStation(/* composeStation(resolver, registry, servicesFor, …) */);
}
```
```dart
// power_station · grid_assets (code) — beside buildCodeRegistry() / kCodeFormula
class CodeRunCommand extends StationRunCommand {
  CodeRunCommand() : super(
    name: 'run',
    resolver: const FormulaResolver(_codeFormulaFor),
    registry: buildCodeRegistry(),
    servicesFor: (cfg) => ServiceBundle(sourceControl: GitSourceControl(/*…*/)),
  );
  // + code-specific flags (--land, …)
}
```
```dart
// space_station · bin/space.dart — memento's assembled runner
Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('space', "memento's grid station")
    ..addCommand(CodeRunCommand())   // power_station (code asset)
    ..addCommand(WatchCommand())     // the_grid CLI SDK (generic)
    ..addCommand(GateCommand());
  exitCode = await runner.run(args) ?? 0;
}
// dart compile exe bin/space.dart -o space  →  ./space run --substation tg --bead tg-… --land
```

## What moves (from today's code)

- `runGridTree` + `RunCommand` (code-welded, in `grid_cli`) **split**:
  - the reusable live-wiring + composition → **`composeStation` + `StationRunCommand`** in the CLI
    SDK **lib (hosted in `grid_cli`)** — de-opinionated; uses the U4
    `composeRunTree(resolver:, registry:, services:)` seam already in place;
  - the code trio + code flags → **`CodeRunCommand`** in the code asset (`grid_assets`).
- generic commands (watch / gate / step / observe / leonard-attach, and **`serve` / `lease`** —
  leasing is core) → stay in the CLI SDK lib.
- **`grid_cli` becomes the reference app** — its `bin/` assembles `CodeRunCommand` + the generic
  commands (consuming framework + shared assets + app code), replacing the retired code-welded
  `grid run`. `space_station` is later the same shape, memento's.
- the burn later exports **`BurnCommand`** the same way (its live-arm pieces — a real
  `FollowerLauncher`, a `serve --kind burn` handler, a `ProcessLeonardDrive` adapter, a provisioned
  follower box — remain the **human gate**).

## Build order

- **Step 1 (next):** carve `StationRunCommand` + `composeStation` into the CLI SDK lib (in
  `grid_cli`, de-opinionated) + `CodeRunCommand` in the code asset + `grid_cli`'s `bin/` as the
  reference app; retire the code-welded `grid run`. Offline-green; everything stays inside
  `the_grid`.
- **Leasing → core (this session, "all now"):** un-seal `Capability`; add the transport-agnostic
  **`LeaseCapability<H>` / `LeaseAllocation<H>`** to `grid_engine` (hooks: `acquire` / `dispatchOn`
  / `proveFresh` / `release` / `adoptable`); rewrite the compute `LeaseCapability` →
  **`ComputeLeaseCapability`** + the burn's **`BurnFollowerCapability`** as `LeaseCapability<H>`
  impls wiring the bus; delete the U2 asset-side `LeasePlan` mixin. `grid_federation` stays
  standalone. Offline-green + adversarial review.
- **Step 2:** the burn as `BurnCommand` (+ the live-arm pieces, human gate).
- **Later:** the physical `power_station` / `space_station` repo split; the OOTB TOML PackInflater
  CLI; how we address asset packs / tool calls.

## Review resolutions (Nico, 2026-07-01)

1. **serve / lease stay GENERIC (core), NOT asset-exported.** The "compute asset exports the
   Commands" shape smells — because **leasing is a core function, not an asset concern** (below).
   serve/lease are core CLI-SDK commands; only the compute *dispatch handler* is the asset part
   they're parameterized by.
2. **The CLI SDK lives in `grid_cli` (reshaped to expose a lib), and `grid_cli` IS the reference
   app** — "like an app, it consumes the framework + shared assets + app code" and assembles the
   runner. NOT a new package. It sits over the framework (`the_grid` / `grid_sdk`) + the assets;
   `space_station` is the same shape, memento's.
3. **Names confirmed** — `StationRunCommand` / `CodeRunCommand` / `composeStation` / `RunConfig`.

## Leasing is core (a related realization — Nico, 2026-07-01)

**Leasing is a CORE function, not an asset concern.** Even a single station must **lease time to
its substations** — leasing is the core scheduling / attention-allocation primitive (the earlier
"leasing = attention-allocation; scheduler = harness = orchestrator" reframe). So the generic lease
machinery sits LOW, with the domain specialization on top:

- the abstract **`LeaseCapability` / `LeasePlan` / `LeaseAllocation`** relocate DOWN out of
  `grid_assets` — into **federation or lower (core)** — as a first-class family;
- **`ComputeLeaseCapability`** (today's compute `LeaseCapability`) and the burn's
  **`BurnFollowerCapability`** ride ON TOP as asset specializations.

This **revisits the U2 placement** (I put `LeaseAllocation` in `grid_assets` to keep
`grid_federation` standalone) and **converges with the approved un-sealing of `Capability`**:
un-seal `Capability` → **`LeaseCapability` becomes a first-class CORE capability family** (not an
asset-side mixin on `ServiceCapability`), with Compute / Burn extending it.

**Resolved (Nico "all now", 2026-07-01):** the lease family goes to **core (`grid_engine`)**,
**transport-agnostic**. Un-seal `Capability`; add a first-class **`LeaseCapability<H>`** (extends
`Capability`) + **`LeaseAllocation<H>`** parameterized over an OPAQUE handle `H`. Core owns the
orchestration (acquire → dispatch → `ready`/`complete`; adopt-or-reacquire via a `proveFresh` hook;
`dispose` = release; `detach` = keep) through capability hooks — `acquire` / `dispatchOn` /
`proveFresh` / `release` / `adoptable` — and names **no transport**. `grid_federation` stays
standalone (protocol types stay put); **`ComputeLeaseCapability`** (`H = (StationClient,
LeaseGrant)`) + the burn's **`BurnFollowerCapability`** wire the bus INSIDE the hooks. A
single-station local lease is then just another impl (handle = a local `LeaseManager`, no bus).
This retires the U2 asset-side `LeasePlan` mixin + the sealed-`Capability` workaround, and folds in
the already-approved un-sealing.

## Safety rails (carried)

Offline (fakes / dry-run; no live `claude`/`git`/`bd`/network); the live burn arm stays the human
gate; coexistence (`tg` read-only, sessions → `tgdog`); doc-before-code; **Nico ratifies**.
