/// Replay support for the `proj_step_edges` molecule-pour projection.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../cli/trajectory_reader.dart' show envelopeFromRow;
import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import '../connect/trajectory_db.dart';
import 'molecule_edge_delta.dart';
import 'molecule_edge_row.dart';
import 'session_head_fold.dart' show orderForReplay;
import 'session_head_row.dart' show sqlDateTime6;

/// The first `proj_step_edges` fold shape.
const int moleculeEdgeFoldVersion = 1;

/// This fold's independent `proj_meta` row.
const String moleculeEdgeProjection = 'step_edges';

/// The exact record/version set consumed by this projection.
const Map<String, (int, int)> moleculeEdgeFoldConsumes = {
  'molecule.poured': (1, 1),
};

/// One pure edge replay's rows and bookkeeping.
@immutable
final class MoleculeEdgeFoldResult {
  const MoleculeEdgeFoldResult({
    required this.rows,
    required this.appliedSeq,
    required this.skipped,
  });

  final Map<MoleculeEdgeKey, MoleculeEdgeRow> rows;
  final int appliedSeq;
  final Map<String, int> skipped;
}

/// Folds the ordered journal into the edge projection.
///
/// Every scanned row advances [MoleculeEdgeFoldResult.appliedSeq]. Every step
/// family record/version outside [moleculeEdgeFoldConsumes] is counted in
/// `skipped` and cannot affect rows.
MoleculeEdgeFoldResult foldMoleculeEdges(Iterable<TrajectoryEnvelope> records) {
  final rows = <MoleculeEdgeKey, MoleculeEdgeRow>{};
  final skipped = <String, int>{};
  var appliedSeq = 0;
  for (final envelope in orderForReplay(records)) {
    final seq = envelope.seq ?? 0;
    if (seq > appliedSeq) appliedSeq = seq;
    if (envelope.family != TrajectoryFamily.step) continue;
    final consumedRange = moleculeEdgeFoldConsumes[envelope.recordType];
    if (consumedRange == null ||
        envelope.typeVersion < consumedRange.$1 ||
        envelope.typeVersion > consumedRange.$2) {
      _countSkipped(skipped, envelope);
      continue;
    }
    final decoded = TrajectoryCodec.decode(envelope);
    if (decoded is OpaqueRecord) {
      _countSkipped(skipped, envelope);
      continue;
    }
    final delta = moleculeEdgeDeltaFor(envelope, decoded: decoded);
    if (delta != null) applyMoleculeEdgeDelta(rows, delta);
  }
  return MoleculeEdgeFoldResult(
    rows: rows,
    appliedSeq: appliedSeq,
    skipped: skipped,
  );
}

void _countSkipped(Map<String, int> skipped, TrajectoryEnvelope envelope) {
  final key = '${envelope.recordType}@v${envelope.typeVersion}';
  skipped[key] = (skipped[key] ?? 0) + 1;
}

/// Rebuilds `proj_step_edges` and its metadata in one transaction.
Future<MoleculeEdgeFoldResult> replayMoleculeEdges(
  TrajectoryDb db, {
  DateTime Function() clock = DateTime.now,
}) async {
  final scanned = await db.execute('SELECT * FROM trajectory ORDER BY seq');
  final result = foldMoleculeEdges([
    for (final row in scanned.rows) envelopeFromRow(row),
  ]);
  try {
    await db.execute('START TRANSACTION');
    await db.execute('DELETE FROM proj_step_edges');
    for (final row in result.rows.values) {
      final params = row.toSqlParams();
      final columns = params.keys.toList(growable: false);
      await db.execute(
        'INSERT INTO proj_step_edges (${columns.join(', ')}) '
        'VALUES (${columns.map((column) => ':$column').join(', ')})',
        params,
      );
    }
    await db.execute(
      'INSERT INTO proj_meta '
      '(projection, fold_version, applied_seq, skipped, rebuilt_at) '
      'VALUES (:projection, :fold_version, :applied_seq, :skipped, '
      ':rebuilt_at) '
      'ON DUPLICATE KEY UPDATE fold_version = :fold_version, '
      'applied_seq = :applied_seq, skipped = :skipped, '
      'rebuilt_at = :rebuilt_at',
      {
        'projection': moleculeEdgeProjection,
        'fold_version': moleculeEdgeFoldVersion,
        'applied_seq': result.appliedSeq,
        'skipped': result.skipped.isEmpty ? null : jsonEncode(result.skipped),
        'rebuilt_at': sqlDateTime6(clock().toUtc()),
      },
    );
    await db.execute('COMMIT');
  } on Object {
    try {
      await db.execute('ROLLBACK');
    } on Object {
      // The transaction may already be gone; the original error is the story.
    }
    rethrow;
  }
  return result;
}
