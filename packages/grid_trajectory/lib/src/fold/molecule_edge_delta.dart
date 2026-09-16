/// The shared `molecule.poured` delta for incremental and replay application.
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'molecule_edge_row.dart';
import 'session_head_delta.dart' show SqlStatement;

/// One pour's valid `blocks` and `validates` edge rows.
@immutable
final class MoleculeEdgeDelta {
  /// Snapshots one pour's valid edge rows.
  MoleculeEdgeDelta(Iterable<MoleculeEdgeRow> rows)
    : rows = List<MoleculeEdgeRow>.unmodifiable(rows);

  /// The complete immutable row set rendered by either applier.
  final List<MoleculeEdgeRow> rows;
}

/// Maps one `molecule.poured` record to its semantic edge rows.
///
/// Malformed graph entries and unsupported edge kinds are ignored so the
/// projection's existing enum can never receive an out-of-vocabulary value.
MoleculeEdgeDelta? moleculeEdgeDeltaFor(
  TrajectoryEnvelope envelope, {
  TrajectoryRecord? decoded,
}) {
  if (envelope.family != TrajectoryFamily.step) return null;
  final record = decoded ?? TrajectoryCodec.decode(envelope);
  if (record is! MoleculePoured) return null;
  final rawEdges = record.graph['edges'];
  if (rawEdges is! Iterable<Object?>) return MoleculeEdgeDelta(const []);
  final rows = <MoleculeEdgeRow>[];
  for (final rawEdge in rawEdges) {
    if (rawEdge is! Map<Object?, Object?>) continue;
    final fromPath = rawEdge['from_path'];
    final toPath = rawEdge['to_path'];
    final kind = rawEdge['kind'];
    if (fromPath is! String || toPath is! String || kind is! String) continue;
    if (kind != 'blocks' && kind != 'validates') continue;
    rows.add(
      MoleculeEdgeRow(
        sessionId: record.sessionId,
        round: record.round,
        fromPath: fromPath,
        toPath: toPath,
        kind: kind,
      ),
    );
  }
  return MoleculeEdgeDelta(rows);
}

/// Renders one idempotent insert per row for the live append transaction.
List<SqlStatement> moleculeEdgeSqlFor(MoleculeEdgeDelta delta) => [
  for (final row in delta.rows)
    (
      sql:
          'INSERT INTO proj_step_edges '
          '(session_id, round, from_path, to_path, kind) '
          'VALUES (:session_id, :round, :from_path, :to_path, :kind) '
          'ON DUPLICATE KEY UPDATE kind = :kind',
      params: row.toSqlParams(),
    ),
];

/// Applies [delta] with the same insert-or-preserve set semantics as SQL.
void applyMoleculeEdgeDelta(
  Map<MoleculeEdgeKey, MoleculeEdgeRow> rows,
  MoleculeEdgeDelta delta,
) {
  for (final row in delta.rows) {
    rows.putIfAbsent(row.key, () => row);
  }
}
