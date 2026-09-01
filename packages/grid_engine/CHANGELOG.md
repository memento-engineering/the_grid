## 0.3.0-rc.9

- The trajectory dual-read surfaces (tg-zfek, cut-wiring C1–C4): `trajectory_views` declares the fold READ interfaces and the winner rule in the engine's own domain layer — grid_sdk implements them over grid_trajectory's row types, so the engine gains no dependency and no SQL client enters its transitive set. Adds the session-axis pass (`dual_read_pass`: the overlay and its monotone guard, the comparator, lag/adjudication, the one escalation rule) and the step-axis pass (`step_dual_read_pass`: the collapse rule, the shared `effectiveStepCursor`, the three step-axis protections), plus the `trajectory_scope` ambient value (#245, #250).
- `ProcessSession`: a protocol-neutral session contract over lease-produced allocations, so a supervised long-lived process is driven by bytes and its outcome derived from structured updates; the legacy dispatcher is retained for one-turn capabilities (#246).
- Gate-rearm observation: successor step rounds are derived from durable closed-gate history and scoped to their structural step incarnation, and a missing running transition is reconstructed when successful completion proves the in-process attempt ran (#247).
- Historical sessions are fenced with an explicit legacy outcome on the completed-disposition latch; unmarked dead-key recovery is preserved (#232).

## 0.3.0-rc.8

- `CompletionContract.artifactDurability`: a capability declaring it is not complete — cached, leased, or live — until its artifact is durably present; an artifactless completion is UNRESOLVED, never 'finished' (#226).
- Rework's replacement mint is decoupled from gate cleanup: supersession is applied before the superseded round's gate auto-close, and a failed close flares without eating the fresh round (#227).

## 0.3.0-rc.7

- `ServiceBundle.derive()`: a total derivation factory with an all-required private constructor — adding a bundle field is now a compile error at every derivation site instead of a silently dropped field (#217).
- `WedgeMonitor.pollSnapshot` exposes the wedge classification over one captured join for coherent status projection (#221).
- Live sessions settle when their work bead closes (#215); molecule reap participates in topological ordering (#216).

## 0.3.0-rc.6

- A dropped state-persist now gets a bounded, durable consequence: the failure
  routes into the supervised-restart writer (persisted restartCount + backoff
  cooldown; circuit-break + escalation at exhaustion). Kills the unbounded
  1 Hz re-derive that grew one store by gigabytes (#207).
- Molecule step graphs are collected before session close, and externally
  closed sessions replay their teardown at boot (#206, #208).
- An exhausted successor mint parks a gate instead of abandoning the molecule
  (#209); every post-retire abandoned mint flares, LOUD or GONE (#210).
- `up` warns at boot when the state store's `types.custom` is missing engine
  types — the misconfiguration that silently stranded three molecules (#211).
- Floors tightened for train coherence: `grid_runtime ^0.2.0-rc.4`,
  `beads_dart ^0.2.0-rc.4`.

## 0.3.0-rc.5

- Fixes 0.3.0-rc.4, which DOES NOT COMPILE against its own declared
  dependencies. rc.4 allowed `grid_runtime: ^0.2.0-rc.1`, but its
  `SessionScope`/`WorkList` reference `StationBeadWriter.closeOpenGatesForTerminal`,
  `GateCloseCause` and `GateSweepSessionDisposition`, which first ship in
  grid_runtime 0.2.0-rc.3. The constraint is tightened to `^0.2.0-rc.3`.
  Do not use 0.3.0-rc.4.

## 0.3.0-rc.4

- Breaking: `operatorRulingMetadata` gains a REQUIRED `evidenceSession` named
  parameter. Migration: pass the session id whose artifacts the ruling is
  evidenced by — `operatorRulingMetadata(nodePath, grade: g, rationale: r,
  evidenceSession: sessionId)`. Rulings are now scoped to the generation they
  addressed, so a prior round's ruling can no longer merge into a fresh round's
  identical node path (tg-04tj).
- The rework cap counts only rounds that reached a VERDICT: a spec-readiness
  HOLD, where no specify agent ran and no committee graded, no longer spends
  budget (tg-04tj, completing tg-9q58).
- `MountEligibilityPredicate` / `MountEligibilityDecision` (`MountEligible` /
  `MountRefused`): an injectable predicate consulted at the mount boundary,
  with edge-triggered `work.mountEligibilityRefused` / `work.mountEligibilityRestored`
  flares naming the refused clause. `ServiceBundle` gains `mountEligibility`.
  The engine supplies the SEAM only — concrete clauses come from the composing
  assets pack (tg-8900).
- Route verdicts persist through `CapabilityHostState._persistAdvance` /
  `_persistEscalate` so a round's verdict evidence is durable (tg-04tj).

## 0.3.0-rc.3

- Breaking: the `kMaxReworkRounds` budget now counts only rounds that reached a
  durable verdict; verdict-less infrastructure losses retain history but do not
  spend rework budget (tg-9q58).
- Breaking (tg-1fa2.5): the provider layer — `Provider<T>` is a MOUNTED seed
  (`SingleChildStatefulSeed`): `create:` runs once per mount (tree-owned,
  tree-disposed), `.value` adopts without ownership; `ProviderScope` is the
  availability registry (a `watch<T>()` miss parks the dependent and a later
  provider mount rebuilds it); `read<T>()` never registers. Kind is fixed for
  a branch's lifetime — both create/value flips throw.
## 0.3.0-rc.2

- A failed molecule pour FLARES (`session.moleculePourFailed`) and parks the
  session at a durable gate (tg-aec) — both the fresh-mint and adopted-orphan
  paths; the silent inert-session class is closed.
- `FederatedSnapshotSource` judges ready-staleness by AGE (`readyStaleAge`)
  from the live source heartbeat, with rising-edge
  `sync.memberStaleByAge`/`sync.memberRecovered` flares (tg-zd4v).
- The wedge alarm samples LAST and ALWAYS in `StationDriver.afterFlush` — a
  throwing scan can no longer silence the stall detector (tg-60n).
- A throwing rebuild no longer decapitates the flush tick (tg-60n, #154).

## 0.3.0-rc.1

- Breaking: tracks beads_dart 0.2.0-rc.1 and grid_runtime 0.2.0-rc.1 — the
  `bd export` retirement and `StationBeadWriter(reader:)`. No engine API change of
  its own; the constraint bump is the breaking part for resolvers.
- Changed: lifecycle reads are observed through the probe-reader seam.

## 0.2.0

- Breaking: diagnostics ride the `genesis_foundation` substrate — the local
  `Diagnosable` mixin and `DiagnosticsBuilder` class are retired in favor of
  foundation's `Diagnosticable`/`DiagnosticsBuilder` (a `GridDiagnosticable`
  marker and the typed `addTyped` adapter remain). Seed hooks override
  `debugFillProperties(DiagnosticsBuilder)`.
- State-owned cross-repo link beads gate the ready frontier (fail-closed).

## 0.1.2

- Family coherence release: step results filter by active incarnation (live route joins, the_grid#139); current session-scope surface.

## 0.1.1

- Every circuit step now mounts as a tree node (the_grid #105).
- Fixed: rework mint gated on fresh readiness; rework remint eligibility
  derived from snapshots; circuit round threaded into capability args;
  derived rework caps parked at the route gate (the_grid #107, #116, #118,
  #119).

## 0.1.0

- Initial release: genesis_tree-based tree engine reconciling the running system (build(observed), mount = spawn, unmount = kill).
