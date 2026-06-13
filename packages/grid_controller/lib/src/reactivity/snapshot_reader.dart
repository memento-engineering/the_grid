import '../models/graph_snapshot.dart';

/// Composes a full [GraphSnapshot] from the underlying store. The reactivity
/// core depends on this abstraction, not on the bd-CLI or Dolt-SQL services
/// directly (predictable-flutter: the repository owns one source behind an
/// interface). Integration wires a concrete reader:
///
/// * the SQL path: `DoltQueryService.snapshotParts()` + `bd ready` for the
///   ready set, with a schema-drift fallback to the CLI path;
/// * the CLI fallback: `bd export --all` + `bd ready`.
///
/// **Snapshot semantics (both paths, identically):** the COMPLETE graph —
/// issues ∪ wisps, all statuses, including infra/template/gate-typed beads.
/// Ephemeral beads live in separate `wisps` tables (beads
/// internal/storage/dolt/ephemeral_routing.go) and `bd export` excludes them
/// without `--all` (cmd/bd/export.go), so anything narrower silently drops
/// poured wisps. Filtering is the consumer's job (projections/selectors).
abstract interface class SnapshotReader {
  Future<GraphSnapshot> read();
}

/// A near-free change probe (`SELECT @@<db>_working`). Implemented by the Dolt
/// query service; used by the working-set dirty-signal source. Distinct from
/// [SnapshotReader] so the probe can run on its own cadence without composing a
/// full snapshot.
abstract interface class ChangeProbe {
  /// Returns an opaque token (the working-set hash) that changes whenever any
  /// data in the database changes, from any workspace.
  Future<String> probe();
}
