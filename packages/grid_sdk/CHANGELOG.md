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
