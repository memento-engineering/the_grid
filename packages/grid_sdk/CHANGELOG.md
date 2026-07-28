## 0.1.2

- `buildStationWork` composes capability registries over its owned note appender: a `registryBuilder` callback receives a `NoteAppender` backed by the assembled `StationBeadWriter` (append-notes chokepoint), so station compositions can wire capability receipt lines to work-bead notes (#137).

## 0.1.1

- Added the command-operation seam: `grid/rework` and `grid/gate/resolve`
  run inside the resident reconcile loop, and `StationWorkRuntime.commands`
  vends the handler a station wires into its control plane (the_grid #104).
- One-shot commands route through the resident station (the_grid #120).

## 0.1.0

- Initial release: the public authoring surface of the grid — composition types driven with runGrid.
