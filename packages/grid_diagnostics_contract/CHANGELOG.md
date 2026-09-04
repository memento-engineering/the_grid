## 0.2.1

- Added: `StationLockRecord.phase` (`StationLifecyclePhase.acquired` / `live` / `releasing`) with `withPhase`; the field is OPTIONAL on the wire and an absent key decodes to `live`, so every existing reader keeps parsing (the_grid#station-lock-record-carries-an-optional-lifecycle-phase; tg-g3zx, #322).

## 0.2.0

- Breaking: the tree wire types (`TreeSnapshot`, `TreeNode`, `DiagnosticsProperty`,
  `DiagnosticsLevel`, `ReferenceKind`) moved to `genesis_foundation`; this package
  now exports only the grid-local `StationLockRecord` and the bearer subprotocol.
  Migrate wire-type imports to `package:genesis_foundation`.

## 0.1.2

- Retain only the grid-local `.grid/station.lock`, `StationLockRecord`, and `grid.tree.bearer.` WebSocket subprotocol contract.
- Move diagnostics tree wire-value ownership to `genesis_foundation`.

## 0.1.1

- Live tree projection: the diagnostics contract carries station tree
  snapshots through the station door (the_grid #113).

## 0.1.0

- Initial release: versioned diagnostics projection wire contract shared by reporters and cockpit consumers.
