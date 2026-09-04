## 0.3.0-rc.13

- `bead board` renders cross-store LINK blockers in its BLOCKED-BY column (previously only same-store `blocks` edges), and the station join bridge threads block observations into the joined snapshot (tg-vdt0, #311).
- Floors tightened to `beads_dart ^0.2.0-rc.8`, `grid_engine ^0.3.0-rc.16`.

## 0.3.0-rc.12

- Re-exports `CacheTokenTotals` and `LandedDeliveryTotals` (tg-mws0, #307); the trajectory-harness reshape message names the current projection shape (tg-0zop, #306).
- Floors tightened to `grid_engine ^0.3.0-rc.14`, `grid_trajectory ^0.2.0-rc.3`.

## 0.3.0-rc.11

- Added: the neutral typed asset registry contract — const inert asset definitions, stable logical and artifact identities, and validated pack and station registries, exported publicly and proven composition- and dependency-neutral (tg-1w3m, #301).
- Added: `bead_board` and `bead_round` — deterministic board and round projections over resident snapshots and trajectory verdicts, store-free, with unreadable stores and missing rounds surfaced as typed outcomes (tg-wk3j, #304).
- Trajectory and Dolt store handles are retained until their close is confirmed, and trajectory sessions are vended through the ordered resident shutdown locus, so an evicted or timed-out state-server socket stays reachable for a later close attempt (tg-gmkt, #296).
- Adopts the grid_runtime 0.2.0-rc.11 GitOps work-tree-root guard in the work assembly (tg-amwa, #302).
- Floors tightened to `grid_runtime ^0.2.0-rc.11`, `grid_engine ^0.3.0-rc.13`, `grid_trajectory ^0.2.0-rc.2`.

## 0.3.0-rc.10

- Silent, artifact-less harness exits (a usage window running out, a network refusal) classify as `infra`: the restart budget is spent with backoff, then the round opens a gate naming the throttle and flares `harness.throttled` with the tail of the agent's output — never a gateless `failed` strand (tg-mbeh, #294; shipped in this rc after the tag was cut from main).
- Breaking: process groups are supervised as groups and exit status is preserved — `SessionOrphaned` is a new `RuntimeEvent` variant (emitted once, NOT terminal: the group stays supervised until it empties or the bounded grace elapses and it is signalled), so exhaustive switches over `RuntimeEvent` need an arm (tg-8kye, #290; sdk consumes the new event). Migration: add `SessionOrphaned()` to every `switch (event)`; power_station#195 is the consumer fix.
- `trajectory.appendDropped` carries sessionId and stepPath; the harness never drops a terminal for an oversized reason (tg-kzvs, #288).
- Floors tightened to `grid_runtime ^0.2.0-rc.10`, `grid_engine ^0.3.0-rc.12`, `grid_trajectory ^0.2.0-rc.1`.

## 0.3.0-rc.9

- Breaking: `StationKernel` is deleted; `runGrid` is the station's single flush coordinator and now carries the tg-60n fail-closed flush guard (#284). Migration: nothing constructs `StationKernel` in the org — drop any import of it and call `runGrid` (grid_sdk `run_grid.dart`); see decisions/2026-09-02-run-grid-is-the-single-flush-coordinator.
- `grid rework` accepts a gate-parked PARTIAL molecule pour (an open gate naming the session) as parked, not only an empty cursor (#277).
- Dry-run `NoOpBdRunner` mints under the owning store prefix (tg-czsf, #278).
- Foreign dependency rows refused loudly (tg-mspw, #283); resident unwind closes store sockets (tg-46q1, #285).
- Floors tightened to `beads_dart ^0.2.0-rc.7`, `grid_runtime ^0.2.0-rc.9`, `grid_engine ^0.3.0-rc.11`, `grid_trajectory ^0.1.2`.

## 0.3.0-rc.8

- Breaking: adopts genesis_tree 0.3.0 and grid_engine 0.3.0-rc.10; `FakeTreeContext` and the SDK's tree overrides forward `{Object? aspect}` (#260). Migration: bump `genesis_tree` to `^0.3.0`; consumers that override `addDependent` add the parameter.

## 0.3.0-rc.7

- The trajectory harness's dual-read posture (tg-zfek, cut-wiring C1–C4): `TrajectoryConfig.dualRead` selects `DualReadMode.off` (THE DEFAULT and the rollback — byte-identical to no harness), `observe`, or `primary`. The harness implements grid_engine's fold read interfaces over grid_trajectory's rows (#245, #250).
- The P1/P2 mirrors (`SessionHeadMirror`, `StepCursorMirror`): versioned in-memory read surfaces so each dual-read is served from pre-fetched state rather than a synchronous query on the join path (#250).
- Terminal-reconcile heal: a session the ledger closed with no terminal record gets one appended, reporting `appended` / `skippedGuard` / `skippedUnavailable` / `failed` rather than failing the caller (#250).
- gc disables itself on a privilege denial — the latch is checked at arm AND at fire, and the transition flares `trajectory.gcDisabled` (#250).
- Boot refuses to start when dual-read is armed and the session-head projection needs a reshape, naming the fix instead of seeding clean and reading `live` from an un-reshaped home (#250).
- `grid rework` publishes both resident mutation rails after the durable session re-key, so the joined engine sees a fresh ready snapshot and mints the successor before the command completes (#231).

## 0.3.0-rc.6

- The station work transport overlay derives its ServiceBundle via `ServiceBundle.derive()` — new bundle fields can no longer be dropped by the hand-copied overlay (#217).
- `StationView`/`StationWorkRuntime` gain `wedgeFor`, backing the one-snapshot status projection (#221).
- Session settlement on work-bead close (#215).

## 0.3.0-rc.5

- `SubstationWork`'s transport overlay is a total derivation:
  `ServiceBundle.mountEligibility` now reaches `WorkList`, so a composed
  mount gate actually enforces (#212). Previously the overlay hand-copied
  six fields and silently dropped the predicate — the gate tested green in
  the seat and did nothing in the live arm.
- Floors tightened for train coherence: `grid_engine ^0.3.0-rc.6`,
  `grid_runtime ^0.2.0-rc.4`, `beads_dart ^0.2.0-rc.4`.

## 0.3.0-rc.4

- Verdict-based rework cap accounting and the readiness-hold exclusion
  (tg-04tj); `station_command_handler` reads verdict evidence from existing
  `grid.result.*` metadata.

  NOTE: the previous version was published and the package then kept accruing
  source without a bump, so the hosted archive and the in-repo sources at that
  version differed. Local builds passed on path overrides while hosted
  resolves got stale code. This release re-syncs them.

## 0.3.0-rc.3

- Breaking (tg-at3r): grid_cli's old `ResidentGridDelegate` contract is
  folded into `GridDelegate` — ONE delegate class. Absorbed hooks:
  `stationView`, `commandHandler`, `afterFlush`, `sweepOrphans`,
  `treeProjector`, `armRoster` (+ the non-virtual `resolveArmedRoster`),
  and `stalenessPosture`. `stationView` and `commandHandler` are now
  NULLABLE with null defaults — absence is a rendered posture (docs/STYLE.md
  rule 3): the shell banner and `/status` report what they can without a
  view, and the control surface refuses commands with a clear message when
  no handler is vended. Migration for delegate subclasses (space_station /
  lunar_station / power_station): extend `GridDelegate` directly and drop
  the `Resident` prefix from overridden names; supporting types moved here —
  `StationView` (was grid_cli `ResidentStationView`), the `StalenessPosture`
  family, `StationRefusal`, and `SubstationConfig`.
- Breaking (tg-at3r): the command extension's `ResidentGridCommandHandler` /
  `ResidentWorkCommandStore` are renamed `StationCommandHandler` /
  `WorkCommandStore` (now `src/command/station_command_handler.dart`);
  construction signatures are unchanged.

## 0.3.0-rc.2

- `runGrid` gains the `treeProjector` seam; completed flushes feed the
  diagnostics reporter (tg-j4ym); the `dart:developer` log side channel is
  retired — the VM service stays a debug surface, never a diagnostics
  dependency.
- `buildStationWork` threads `syncFloorInterval`, arms the federation's
  freshness + flare wiring, and exposes `syncStats`/`workFreshness`.
- `grid rework` reaps the retired round's molecule, accepts pour-parked
  sessions, appends the operator note BEFORE housekeeping, and reports a reap
  failure LOUD in the result (tg-ehht).

## 0.3.0-rc.1

- Breaking: tracks beads_dart 0.2.0-rc.1, grid_runtime 0.2.0-rc.1 and
  grid_engine 0.3.0-rc.1. No SDK API change of its own; the constraint bump is the
  breaking part for resolvers.
- Changed: work assembly wires a probe reader beside each write chokepoint.

## 0.2.0

- Breaking: rides `grid_engine` 0.2.0's foundation diagnostics substrate.
- Fix: registry notes route to the owning store.

## 0.1.3

- Constraint coherence: requires grid_runtime ^0.1.2 / grid_engine ^0.1.2 / beads_dart ^0.1.1 (fixes hosted 0.1.2 resolving against grid_runtime 0.1.1, which lacks `onFlare`/`ownedPrefixOf`).

## 0.1.2

- `buildStationWork` composes capability registries over its owned note appender: a `registryBuilder` callback receives a `NoteAppender` backed by the assembled `StationBeadWriter` (append-notes chokepoint), so station compositions can wire capability receipt lines to work-bead notes (#137).

## 0.1.1

- Added the command-operation seam: `grid/rework` and `grid/gate/resolve`
  run inside the resident reconcile loop, and `StationWorkRuntime.commands`
  vends the handler a station wires into its control plane (the_grid #104).
- One-shot commands route through the resident station (the_grid #120).

## 0.1.0

- Initial release: the public authoring surface of the grid — composition types driven with runGrid.
