import '../errors/bd_exception.dart';
import '../models/graph_snapshot.dart';
import '../services/bd_cli_service.dart';
import '../services/dolt_query_service.dart';
import 'snapshot_reader.dart';

/// Composes a snapshot entirely from the bd CLI: `bd export --all` for the
/// complete bead/dependency graph (issues ∪ wisps — see [SnapshotReader] for
/// the unified inclusion semantics) and `bd ready` for the ready set. The
/// guaranteed-correct path (and the SQL path's fallback). Two bd spawns per
/// refresh.
class CliSnapshotReader implements SnapshotReader {
  CliSnapshotReader(this._bd, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final BdCliService _bd;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    final export = await _bd.exportAll();
    final ready = await _bd.ready();
    return GraphSnapshot.fromParts(
      beads: export.beads,
      dependencies: export.dependencies,
      readyIds: ready.map((bead) => bead.id),
      capturedAt: _clock(),
    );
  }
}

/// Composes a snapshot from pooled Dolt SQL (issues ∪ wisps, plus both label
/// and dependency tables — see [SnapshotReader] for the unified inclusion
/// semantics) plus `bd ready` for the ready set (authoritative in M1; M2 ports
/// ready-work to SQL, differential-tested). One bd spawn per refresh instead
/// of two, and the heavy read is ~1–5ms SQL instead of a ~70–140ms `bd export`
/// spawn.
///
/// Any failure — schema drift ([BdSchemaDriftException]), a reaped connection,
/// or any other SQL error — falls back to [fallback] (the CLI reader) so a
/// refresh never fails because the optimization path did. The SQL-vs-CLI
/// equivalence test (ADR-0001 D7) guards that the two paths agree.
class SqlSnapshotReader implements SnapshotReader {
  SqlSnapshotReader({
    required DoltQueryService dolt,
    required BdCliService bd,
    required SnapshotReader fallback,
    DateTime Function()? clock,
  }) : _dolt = dolt,
       _bd = bd,
       _fallback = fallback,
       _clock = clock ?? DateTime.now;

  final DoltQueryService _dolt;
  final BdCliService _bd;
  final SnapshotReader _fallback;
  final DateTime Function() _clock;

  @override
  Future<GraphSnapshot> read() async {
    try {
      final parts = await _dolt.snapshotParts();
      final ready = await _bd.ready();
      return GraphSnapshot.fromParts(
        beads: parts.beads,
        dependencies: parts.dependencies,
        readyIds: ready.map((bead) => bead.id),
        capturedAt: _clock(),
      );
    } on Object {
      // Drift / connection loss / any SQL error → the authoritative CLI path.
      return _fallback.read();
    }
  }
}

/// Adapts [DoltQueryService.probe] to the [ChangeProbe] seam consumed by the
/// working-set dirty-signal source.
class DoltChangeProbe implements ChangeProbe {
  DoltChangeProbe(this._dolt);
  final DoltQueryService _dolt;

  @override
  Future<String> probe() => _dolt.probe();
}
