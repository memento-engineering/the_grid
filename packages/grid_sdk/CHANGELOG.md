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
