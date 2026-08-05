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
