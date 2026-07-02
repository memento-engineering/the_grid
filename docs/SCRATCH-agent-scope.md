# SCRATCH — the agent scope + the composition inversion + the context rip-out

**Status: design surface (proposed — nothing here is ratified until Nico stamps
it).** Sessions 2026-07-01/02. **ADR home (Nico's call): UPDATES into existing
ADRs (ADR-0008 primarily), no new ADR number** unless a genuinely new decision
falls out.

The trigger: the agentic-harness seam (how the agent step parameterizes over
{claude, pi, opencode, the grid's own agent}, where harness config lives, how
inference targets llama.cpp / swift-infer without re-rolling lenny's provider).
En route, the design dissolves accumulated wall-residue: the `servicesFor`
callback seam, the `StationRunCommand` subclass base, the `StableInheritedSeed`
guard type, the `CapabilityContext` grab-bag, the "sandbox" SDK language — and
(2026-07-02) the **services-in-the-tree anti-pattern** D-H names.

**Naming (Nico's calls):** "Agent", not "Coding" (the seam is a space for an
agent to turn work in; the committee's critics ride the same harness).
"Harness" = a turn/tool harness — memento-engineering builds harness/
orchestration/federation solutions, so the word is load-bearing and enters the
working glossary. The grid's own harness is named **`GridHarness`** (core grid
harness — never named after its implementation language) but is **PARKED as
its own epic** (Nico, 2026-07-02; D-B′): this pass brings the EXISTING
harnesses online — **claude, copilot, pi, opencode**.

**The unlock: genesis_tree 0.1.4 (published, verified).**
`getInheritedSeedOfExactType<T>` — non-binding, exact-type, callable outside
build, throws `StateError` on an unmounted branch ("async-gap protection,
executable"), `mounted` stays the cooperative probe. Plus `SingleChildSeed` +
`Nest` (vertical chaining — what asset `main()`s use to mount provider stacks).

---

## D-A · The composition inversion — assets own `main()`

**Problem.** `runGridTree` is a framework-owned mega-function; the
de-opinionation pass (dc4542b) stripped its asset opinions but kept the
monolith, so the asset interposes through a callback (`servicesFor`) and
through inheritance (`CodeRunCommand extends StationRunCommand`) — the latter
against ADR-0008 D1's ratified "consumers compose, never subclass".

**Decision (proposed).** Finish the Flutter-app inversion:

- Decompose `runGridTree` into library pieces the asset calls:
  `discoverWorkspaces(...)`, `buildControllers(...)`, `driveStation(wiring)`.
  `composeStation` stays pure composition.
- The asset's `main()` constructs its live wiring, builds its `ServiceBundle`
  itself, mounts its own providers (D-B), and calls `driveStation`.
- **Delete**: `AssetWiring`, `AssetServicesBuilder`, `servicesFor`,
  `StationRunCommand`. The arming/gating checks (`--dry-run` default, `--land`
  requires `--no-dry-run`, A36/A37 state-store guards) move into the library
  pieces — inherited by calling through, not by subclassing.

## D-B · The agent scope — config is a VALUE; impls are DI

**(Rewritten 2026-07-02 after Nico flagged the anti-pattern in v1: deriving
the harness out of a *service* looked up in the tree. Config rides the tree as
a value type; implementations are DI, reached at the effect boundary. See
D-H.)**

The tree carries **`AgentConfig`** — a pure value type (freezed), provided via
plain `InheritedSeed<AgentConfig>`, **watched** (`dependOn*`) by any branch
that reads it:

```dart
class AgentConfig {                 // value type — no behavior, no impls
  final String harness;             // registry id: 'claude'|'copilot'|'pi'|'opencode'
  final ModelTarget target;         // where inference runs (D-E)
  final Map<String, String> params; // harness-opaque tuning
}

abstract interface class AgentHarness {   // pure description (delegate-class)
  RuntimeConfig spawnFor(AgentConfig config, AgentBrief brief, StepArgs args);
  StepSignal interpret(RuntimeEvent event);
}
```

- **Impl resolution is DI, not tree lookup of behavior:** the asset's `main()`
  wires a harness registry (id → `AgentHarness`) alongside the capability
  registry; the effect boundary maps `config.harness` → impl. Impls (this
  pass): `ClaudeHarness` (today's spawn body verbatim), `CopilotHarness`,
  `PiHarness`, `OpencodeHarness`. The grid's own harness is parked (D-B′);
  the registry keeps it purely additive later.
- **Policy stays asset-owned:** `buildAgentPrompt` renders the **`AgentBrief`**
  (OQ-a resolved: task sections + working agreement + extra context — the
  harness-agnostic *work content*). Model/parameters are NOT brief — they are
  `AgentConfig` (invocation config). Consequence: one brief replays across
  harnesses (supervision may retry the same work on a different harness
  without re-rendering policy).
- **Transport is harness-owned** (OQ-a): each impl picks its native transport
  for the brief — argv (claude today), stdin, or a workspace file — fixing
  ARG_MAX/ps-visibility per harness without touching policy.
- The engine learns none of this vocabulary — `AgentConfig`/`AgentBrief`/
  `AgentHarness` are SDK/asset surface (home: D-B″).

### D-B′ · The grid's own harness — PARKED (Nico, 2026-07-02)

**An epic of its own; not designed here.** This pass ships the four external
harnesses only. What IS carried forward from the discussion, recorded for the
future epic so it isn't re-litigated:

- All agentic work is a **spawned process** (OQ-b confirmed): completion stays
  observed-not-declared (tg-p9q), pgid supervision/respawn/adopt uniform.
- **"No inference dep in the engine" is a hard confirm** (Nico). Whatever
  shape the own-harness epic takes, the inference dep lives in the spawned
  program, never the engine/SDK.
- **leonard/lenny is a DEV TOOL — never in the production-code path** (Nico,
  2026-07-02). The epic does NOT consume lenny's `ModelProvider` for production
  coding agents; if a shared model-provider layer is wanted, CENTRALIZE it
  (maybe) — a home question for the epic. Topic closed until then.
- The name `GridHarness` is reserved; the harness registry makes the whole
  epic additive (a new id + impl, zero seam changes).

### D-B″ · Homes (OQ-d resolved for this pass)

- The harness seam (`AgentHarness`/`AgentConfig`/`AgentBrief`/`ModelTarget`) +
  the four spawner impls (all dependency-free `RuntimeConfig` mappers) belong
  to the **`the_grid` SDK package** — the split ADR-0008 D1 already ratified
  ("grid_sdk" = that package; no NEW package beyond it). Interim, until D1
  executes: they stay in `grid_assets/src/code/` (where the capabilities live
  today). `dart_grid_assets` is the wrong spot (Nico).
- Noted (Nico, 2026-07-02): the `grid_federation` package split is regretted
  ("a mistake") — M6 is parked on `m6-federation` behind ADR-0009; fold-back
  is a candidate when M6 unparks. No action this pass.

## D-C · Where config lives — the override ladder

Config nodes are ancestors of work nodes (ADR-0007). All rungs are VALUE
merges (never service derivation):

1. **Station default** — the asset's `main()` mounts `InheritedSeed<AgentConfig>`
   above `Station` (per-machine posture: swift-infer here, llama.cpp on the
   dashboard).
2. **Per-substation** — an override provider under `SubstationScope`.
3. **Per-bead** — the `grid.agent` **domain envelope** on the work bead,
   decoded fail-closed by the existing `dart_grid_assets` envelope machinery.
4. **Per-step** — `CapabilityStep.params` via `StepArgs.params`; highest
   precedence.

The effective config is computed at the effect boundary as a pure merge:
ambient `AgentConfig` ⊕ bead envelope ⊕ step params.

## D-D · How values reach a capability — context + args

The host passes its own stable `TreeContext` (`Branch.context`) into the
capability; the capability reads ambient values with the non-binding
`getInheritedSeedOfExactType` (snapshot-at-read — correct for an effect):

- Ambient: `Bead` (mounted by `WorkBead`), `ServiceBundle` (stays ONE concrete
  bundle — exact-type lookup can't resolve an abstract), `SessionHandle`,
  `Workspace` {workspaceDir, branch, baseBranch} (mounted by `SessionScope`),
  `SiblingView` (mounted by the session/fan-out container), `AgentConfig`, and
  any asset-owned value the asset mounted itself.
- Per-step: `StepArgs {params, nodePath, cancel}` (+ deferred `logFile`).

```dart
RuntimeConfig spawn(TreeContext context, StepArgs args);          // Process
Future<Map<String,String>?> result(TreeContext context, StepArgs args);
Future<StepOutcome> run(TreeContext context, StepArgs args);      // Service
```

**`CapabilityContext` is deleted**; `AllocationContext` keeps the host-computed
drive kit and carries `(context, args)` in place of `capContext`. The
extensions-bag idea (v1 D-D Option A) is dead — assets mount and read their
own types directly.

## D-E · Inference targets

```dart
sealed class ModelTarget {}          // exhaustive-switch house style
class ProviderManaged extends ModelTarget {}   // the tool owns auth/routing:
                                               // claude (keychain, A38), copilot (gh auth)
class OpenAiCompatible extends ModelTarget { final Uri base; }  // llama.cpp server
class SwiftInfer extends ModelTarget { final Uri base; }
```

Each harness maps the target into its own env/flags; the grid never speaks
inference. `ProviderManaged` generalizes v2's claude-specific
`AnthropicKeychain`: copilot's auth rides GitHub (`gh`), claude's the macOS
keychain — for managed tools, model *selection* is an `AgentConfig.params`
entry (`model: ...`), not a target. llama.cpp = `OpenAiCompatible`.

**Legality (OQ-c RESOLVED — Nico, 2026-07-02): two-moment validation.**
(1) Composition root, eager: the asset's `main()` validates its
station-default `AgentConfig` + registry coverage at boot — a misconfigured
machine fails loud before any work mounts. (2) Per-work resolution, contained:
an illegal combo arriving via bead envelope / step params resolves to `Failed`
for THAT work (supervision → gate/escalation) — one bad bead never crashes the
station. Mirrors the envelope's fail-closed precedent: refuse whole, never
partial.

## D-F · Guard policy — delete `StableInheritedSeed` (reverses ADR-0008 D-6)

genesis's default `updateShouldNotify => value != oldSeed.value`
(`inherited.dart:28`) is an identity check for `ServiceBundle`; the bundle is
built once, so the fan-rebuild D-6 guards against cannot occur. The type's only
added behavior is making an in-place swap **silently inert** — worse than the
benign rebuild it prevents. Delete at all three sites; quote-and-supersede
stamp in ADR-0008 D-6 on ratification.

**The guard principle (proposed doctrine):** a guard exists only if it
protects a named invariant with a concrete failure story and is LOUD when
violated — else it's ceremony and gets deleted.

## D-G · One lookup system, two verbs

- **`dependOn*`** — the TREE verb. Branches ALWAYS watch (D-H rule 1); a
  dependency registration keeps the reactive graph true.
- **`get*`** — the EFFECT verb (+ `initState` initial reads and teardown, per
  the genesis 0.1.4 doc). Snapshot-at-read; LOUD on unmounted (`StateError`);
  `mounted` is the cooperative probe after awaits, alongside cancel guards.

The "sandbox" framing in `capability.dart`/`allocation.dart` is purged
(ADR-0009 alignment). Stated once, honestly: with capabilities able to reach
the tree, invariant 1 + the write-locus move from "unreachable by construction"
to "enforced by the existing mutation-verified gates," extended to
capability-land (no `dependOn*`, no `addListener`, chokepoint-only writes).

## D-H · The genesis_tree consumption doctrine (Nico, 2026-07-02) + audit

The rules (to be drilled into every genesis_tree consumer — propagation:
predictable-flutter skill + genesis docs; Nico owns where):

1. **Always watch dependencies.** Assume every reference can change. Initial
   read in `initState` is fine, but the `dependencyChanged` path (genesis's
   `didChangeDependencies` analogue) must re-run the read — **never `??=`-cache
   a dependency.**
2. **Never sync-read a reactive object without subscribing** — the reason
   `StateNotifier.state` is `@protected`. Leaking public synchronous accessors
   that mirror state invites chaos.
3. **No service-layer access in seeds/branches** except configuring DI, the
   app, and its data/domain layers. Branches touch **value types** and
   **reactive domain objects**; pure delegate-classes (description-only) are
   acceptable in build; I/O services flow through untouched to the effect
   boundary, never driven from build.
4. No-frills declarative architecture — predictable-flutter layering applies
   to the tree exactly as to a Flutter app.

**Audit of `grid_engine` against the rules (2026-07-02):**

- **Violations — fix in Wave 1:**
  - `??=`-cached dependencies (rule 1): `capability_host.dart:88`
    (`_ctx ??= …StationServices`), `capability_host.dart:95`
    (`_registry ??= …CapabilityRegistry`), `session_scope.dart:97`
    (`_ctx ??= …StationServices`).
  - Public sync state mirrors (rule 2): `SubstationConfigNotifier` and
    `JoinedSnapshotNotifier` self-subscribe to mirror `state` into a public
    field (`notifiers/*.dart`) — exists only to dodge `@protected state`.
    Delete the mirrors; initial reads use `addListener(fireImmediately: true)`
    (`substation_scope.dart:64`'s `.current` read migrates).
- **Pass-throughs — keep, but name the rule at the site (rule 3's DI clause):**
  `ServiceBundle`/`StationServices` read by `CapabilityHost`/`SessionScope`
  solely to hand to the allocation/chokepoint (the effect boundary; the writer
  stays host-owned, off-build — ADR-0009). `CapabilityRegistry`/
  `SessionResolver` are DI registries/delegates consumed as description.
- **Correct today:** `SubstationConfig` (value, watched, `substation.dart:30`);
  `JoinedSnapshotNotifier` (reference watched + state subscribed,
  `work_list.dart:48,59`); `SessionHandle` (value handle).

---

## The rip-out plan (waves; deletions bolded)

**Wave 0 — the genesis gate. ✅ CLEARED (0.1.4 on pub.dev, verified 2026-07-02):**
non-binding + outside-build + loud-on-unmounted all confirmed; `^0.1.3` caret
resolves 0.1.4 with no pubspec change.

**Wave 1 — engine rip-out (`grid_engine`, offline).**
- New SDK signatures (D-D): `spawn`/`run`/`result` take `(TreeContext,
  StepArgs)`; add `StepArgs`; `interpretEvent` unchanged.
- Ambient mounts: `InheritedSeed<Bead>` (WorkBead), `Workspace` (SessionScope),
  `SiblingView` (session/fan-out container).
- Host passes `context` + `StepArgs`; `AllocationContext` slims.
- **Delete `CapabilityContext`**, **the SiblingView threading plumbing**,
  **`StableInheritedSeed`** (three sites, D-F).
- D-H fixes: **de-`??=`** the three cached dependencies; **delete the notifier
  sync mirrors** (fireImmediately initial reads).
- Extend the derailment gates to capability-land (D-G): no `dependOn*`, no
  `addListener`, chokepoint-only writes — mutation-verified.
- Sandbox-language purge; migrate engine fakes + tests.

**Wave 2 — the cli inversion (`grid_cli`, D-A).**
- Decompose `runGridTree`; arming/gating checks move into the pieces.
- **Delete `servicesFor`/`AssetWiring`/`AssetServicesBuilder`/
  `StationRunCommand`.**

**Wave 3 — power_station (the agent scope, D-B/C/E).**
- `AgentConfig`/`AgentBrief`/`AgentHarness` + the four impls
  (Claude/Copilot/Pi/Opencode); the code asset's real `main()` mounts
  `InheritedSeed<AgentConfig>` + its `ServiceBundle` (via `Nest`), validates
  boot-eager (OQ-c moment 1), and calls `driveStation`.
- `grid.agent` envelope layer; effective-config merge + per-work fail-closed
  resolution (OQ-c moment 2) at the effect boundary.
- Migrate ALL capability impls across the packs (code/compute) to
  `(context, args)`. **Carved out (2026-07-02):** `butane_grid_assets` moved
  home to `butane_flutter/packages` (a gc-owned rig — power_station
  `eea6a2b`); its burn-capability migration is a WITH-NICO follow-up, not this
  pass's edit.

**Docs (woven through, doc-before-code).** On ratification: ADR-0008 updates
with quote-and-supersede stamps — D1 (finished by D-A), D-5 (SiblingView →
ambient), D-6 (deleted, D-F), the M4-P1 §3 sandbox language (→ D-G/D-D), + the
ADR-0009 stamp for the two-verb story, + D-H's doctrine propagation
(predictable-flutter, genesis docs — Nico owns where it lands).

---

## Open questions

All design OQs are resolved (OQ-a/b/c/d above; the own-harness questions ride
the parked D-B′ epic). Remaining trivia, defaulted unless Nico objects:

- **OQ-f · `StepArgs`** stands as the name for the per-step remainder.
  Glossary entry, proposed: *harness — the thing that holds an agent while it
  runs: renders a brief + config into one tool's invocation and interprets its
  runtime events. lenny's usage (the debugging harness) is the same word at
  system scale.*

**The gate: this surface is decision-complete. On Nico's ratification the
ADR-0008 update stamps land and Wave 1 starts.**
