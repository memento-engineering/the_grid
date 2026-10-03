/// One in-memory image of a `proj_step_edges` row.
library;

import 'package:meta/meta.dart';

import '../connect/trajectory_db.dart';

/// The existing projection's complete primary key.
typedef MoleculeEdgeKey = ({
  String sessionId,
  int round,
  String fromPath,
  String toPath,
  String kind,
});

/// One immutable semantic edge from a poured molecule.
@immutable
final class MoleculeEdgeRow {
  /// Creates one row in the existing semantic edge projection.
  const MoleculeEdgeRow({
    required this.sessionId,
    required this.round,
    required this.fromPath,
    required this.toPath,
    required this.kind,
  });

  /// Decodes one `proj_step_edges` row from SQL or an in-memory row map.
  factory MoleculeEdgeRow.fromSqlRow(Map<String, Object?> row) {
    String text(String column) => '${row[column] ?? ''}';
    int number(String column) => int.parse(text(column));

    final kind = text('kind');
    if (kind != 'blocks' && kind != 'validates') {
      throw StateError('unsupported proj_step_edges kind "$kind"');
    }
    return MoleculeEdgeRow(
      sessionId: text('session_id'),
      round: number('round'),
      fromPath: text('from_path'),
      toPath: text('to_path'),
      kind: kind,
    );
  }

  /// The owning session correlation.
  final String sessionId;

  /// The owning session round.
  final int round;

  /// The graph path whose dependency row is authored.
  final String fromPath;

  /// The graph path [fromPath] depends on or validates.
  final String toPath;

  /// The exact DDL enum wire (`blocks` or `validates`).
  final String kind;

  MoleculeEdgeKey get key => (
    sessionId: sessionId,
    round: round,
    fromPath: fromPath,
    toPath: toPath,
    kind: kind,
  );

  /// The exact DDL column map used by both incremental and replay inserts.
  Map<String, Object?> toSqlParams() => {
    'session_id': sessionId,
    'round': round,
    'from_path': fromPath,
    'to_path': toPath,
    'kind': kind,
  };

  @override
  bool operator ==(Object other) =>
      other is MoleculeEdgeRow && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'MoleculeEdgeRow(${toSqlParams()})';
}

/// The whole semantic edge projection in deterministic primary-key order.
const String scanMoleculeEdgesSql =
    'SELECT * FROM proj_step_edges '
    'ORDER BY session_id, round, from_path, to_path, kind';

/// Reads every projected molecule edge through the caller's serialized lane.
Future<List<MoleculeEdgeRow>> scanMoleculeEdges(TrajectoryDb db) async {
  final result = await db.execute(scanMoleculeEdgesSql);
  return [for (final row in result.rows) MoleculeEdgeRow.fromSqlRow(row)];
}
