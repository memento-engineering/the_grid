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
