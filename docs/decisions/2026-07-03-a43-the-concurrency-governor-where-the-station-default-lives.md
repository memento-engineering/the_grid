---
status: accepted
date: 2026-07-03
decision-makers: ["agent"]
consulted: []
informed: []
register:
  spec: 1
  slug: a43-the-concurrency-governor-where-the-station-default-lives
  surfaces:
    - "packages/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: "A43"
---
## A43 (2026-07-03) — the concurrency governor: where the station default lives, the station-wide ceiling's scope, and admission order (tg-42f)

**Decision (AI; `grid_engine` + `grid_cli`):** built the engine-level concurrent-work slot budget per Nico's brief (tg-42f) — `WorkList` mounts at most N work beads per substation, with a station-wide cap above it; a bead beyond the budget stays ready-unmounted (no session, no spawn, no cost) and mounts on the natural reconcile once a slot frees; one LOUD flare per throttled build. Three shape choices were left to the implementer and are recorded here:
- **Where the "station default" ambient lives.** The brief's own phrasing ("mounted by the asset runner via wrapRoot/InheritedSeed") describes the `AgentConfig`-style pattern by analogy, not a hard requirement. Rather than invent a new bespoke `InheritedSeed<ConcurrencyConfig>` wired through `wrapRoot`, the default/ceiling landed as a new field on the EXISTING `StationServices` (`kernel/station_services.dart`) — the engine's own "MediaQuery pattern" ambient already documented as the home for "genuinely per-machine" values, already provided once at the kernel root, and already the shape `WorkList` mirrors for its `ServiceBundle` dependency. `wrapRoot`/asset-composed `InheritedSeed`s stay reserved for genuinely asset-owned config (`AgentConfig` and kin).
- **The station-wide ceiling only binds when `StationServices` is actually ambient.** Every REAL run composes one (`buildLiveWiring` → `composeStation` → `StationKernel`), so this is not a live-arm gap — but a great many EXISTING offline tests (fakes-only, `StatefulSeed` trees built by hand) never provide `StationServices` at all. Treating its absence as "station cap = the generous default (4)" would have silently throttled every such test with more than 4 concurrently-ready beads in one substation — real pre-existing tests do exist at 7 and 9 beads (`track_a_reconcile_test.dart`, `run_command_tree_test.dart`), now given an explicit generous `maxConcurrentWork` override since they exercise the type-gate/reconcile predicate, not the governor. So: `stationCap == null` (no ambient `StationServices`) ⇒ only the substation's own cap applies, unconstrained above it; `stationCap` present ⇒ it is a hard ceiling a substation override can narrow within but never exceed (`min(substationSlots, stationSlots)`).
- **Admission order + the station-wide read.** Among "pending" candidates (freshly ready, no live session — the only bin the budget gates; a bead already carrying a live session is NEVER evicted for budget reasons, positive-terminal-only unmount stays the only unmount trigger), admission is deterministic lowest-bead-id-first. The station-wide live count is read directly off the shared `JoinedSnapshot.sessionsByWorkBead` (already ambient to every substation's `WorkList`, zero extra lookup) rather than a dedicated cross-substation counter — an intentional declare-and-check approximation: it reflects the last SETTLED state, so two substations admitting in the SAME flush can transiently overshoot by however many substations raced, self-correcting once the newly-minted sessions land in the next snapshot. Not a distributed lock, per the brief's "declare-and-check only" scope.
**Why:** the brief specified the mount-boundary behavior and the CLI surface (`--max-agents`, default generous) precisely, but left the exact ambient wiring, the station-wide-vs-offline-test interaction, and the tie-break order unspecified — all three are the kind of shape decision ADR-0000 exists to catch before it's silently baked in.
**Not this:** the general per-leaf `DartEnvironment`/`ResourceRequest` permit governor (ADR-0008 D8, explicitly deferred by the M4-P1 build order as "a separate, optional track NOT in the P1 spine") is a DIFFERENT, broader mechanism (per-formula-step declared resource requests + a live semaphore governor). This amendment's slot budget is narrower and orthogonal — it gates WHICH work beads mount at all, not what a mounted leaf may request.
**Affects:** `grid_engine`: `kernel/station_services.dart` (`maxConcurrentWork` field + `kDefaultMaxConcurrentWork = 4`), `domain/substation_config.dart` (nullable `maxConcurrentWork` override), `seeds/work_list.dart` (the governor at the mount boundary + `work.throttled` flare). `grid_cli`: `station_runner.dart` (`--max-agents` flag → `StationArgs.maxAgents` → threaded into `StationServices.maxConcurrentWork` in `buildLiveWiring`). New tests: `grid_engine/test/track_a_concurrency_governor_test.dart`, `grid_cli/test/max_agents_flag_test.dart`. Existing tests widened with an explicit generous override (unrelated to the governor): `grid_engine/test/track_a_reconcile_test.dart`, `grid_cli/test/run_command_tree_test.dart`.
**Status:** **AI decision, pending Nico** — recorded per the ADR-0000 rule; promote into a home ADR (ADR-0008 amendment, or its own line in ADR-0002's package table) or dispose at will.

