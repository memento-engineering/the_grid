## 0.2.0-rc.3

- `StationBeadWriter.closeOpenGatesForTerminal` plus the `GateCloseCause` and
  `GateSweepSessionDisposition` enums: the gate auto-close sweep a terminal
  session runs, returning `GateAutoCloseReceipt`s. Consumed by grid_engine's
  `SessionScope` and `WorkList` (tg-3eeg).
- Guarded-write capability negotiation on the bd chokepoint (tg-j0o0 groundwork).

NOTE: 0.2.0-rc.2 was published BEFORE this API landed, and the package kept
accumulating source without a version bump — so the hosted rc.2 archive and the
in-repo rc.2 sources differ. grid_engine 0.3.0-rc.4 shipped against the in-repo
sources and does not compile against hosted rc.2; grid_engine 0.3.0-rc.5 tightens
its constraint to `^0.2.0-rc.3`.

## 0.2.0-rc.2

- `StationBeadWriter.parkSessionAtGate` — the session-lifecycle park distinct
  from the router's gate mint (tg-aec).
- `reapMolecule` degrades to per-bead closes on proxied-server stores, where
  `bd batch` is unsupported — the reap silently threw on EVERY session close
  there, the mechanism behind 9,389 orphaned step beads (tg-ehht).

## 0.2.0-rc.1

- Breaking: `StationBeadWriter`'s constructor now requires `reader:`, a
  `BeadProbeReader`. Its seven lifecycle probes read through that seam instead of
  `BdCliService.exportAll`, which is gone (see beads_dart 0.2.0-rc.1). Migration:
  pass `CliBeadProbeReader(bd, lifecycleTypes: …)` or the SQL reader.
- Fixed: the best-effort catches around those probes no longer convert a refused
  `bd export` into a silent no-op — the reason `reapMolecule` never reaped and the
  gate mint-dedup probe always read empty.

## 0.1.2

- Family coherence release: `StationBeadWriter` current surface (`onFlare`, `writeSpecifyAuthoredSpec`/marker-gated clear the_grid#136, `BeadOwnershipPredicate.ownedPrefixOf`).

## 0.1.1

- Fixed bead-prefix matching to permit hyphens after an owned prefix
  (the_grid #117).

## 0.1.0

- Initial release: runtime providers that spawn and supervise a coding agent per ready bead, isolating each bead's work in a git worktree.
