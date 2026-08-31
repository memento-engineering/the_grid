/// The REPLAY application mode for P6 (§5 Rebuild): fold a record stream into
/// in-memory `proj_process_identity` rows, then write them — truncate, insert
/// the folded rows, and drive this projection's `proj_meta` row in one SQL
/// transaction. Same posture as `session_head_fold`: station DOWN, log never
/// migrated, fold_version bump + truncate + replay is the only migration.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../cli/trajectory_reader.dart' show envelopeFromRow;
import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import '../connect/trajectory_db.dart';
import 'process_identity_delta.dart';
import 'process_identity_row.dart';
import 'session_head_fold.dart' show orderForReplay;
import 'session_head_row.dart' show sqlDateTime6;

/// P6's fold version (§5: bumped with any projection-shape change, which
/// forces truncate + replay).
const int processIdentityFoldVersion = 1;

/// P6's own `proj_meta` row — per-projection bookkeeping (the appender's
/// step-5 `'fold'` row stays the global applied_seq cursor).
const String processIdentityProjection = 'process_identity';

/// §2.6 rule 5: the `(record_type, min_version, max_version)` set this fold
/// CONSUMES. Family-1 types absent here are deliberately not consumed by P6
/// (session lifecycle is P1's, mint outcomes P3's, liveness traj_pulse's).
const Map<String, (int, int)> processIdentityFoldConsumes = {
  'attempt.process.started': (1, 1),
  'attempt.process.exited': (1, 1),
  'attempt.lease.acquired': (1, 1),
  'attempt.lease.released': (1, 1),
  'attempt.lease.swept': (1, 1),
  'worktree.provisioned': (1, 1),
  'worktree.reaped': (1, 1),
  'worktree.held': (1, 1),
};

/// One replay's outcome: the folded rows plus the `proj_meta` bookkeeping.
@immutable
class ProcessIdentityFoldResult {
  const ProcessIdentityFoldResult({
    required this.rows,
    required this.appliedSeq,
    required this.skipped,
  });

  /// Folded P6 rows keyed by attempt_id.
  final Map<String, ProcessIdentityRow> rows;

  /// The highest `seq` SCANNED (not merely applied).
  final int appliedSeq;

  /// §2.6 rule 3: attempt-family rows that decoded to [OpaqueRecord], counted
  /// per `<type>@v<version>` for `proj_meta.skipped`.
  final Map<String, int> skipped;
}

/// Folds [records] into P6 rows — deterministic, pure, no I/O. Ordering is
/// §5's rebuild rule via [orderForReplay] (shared with every fold).
ProcessIdentityFoldResult foldProcessIdentities(
  Iterable<TrajectoryEnvelope> records,
) {
  final ordered = orderForReplay(records);
  final rows = <String, ProcessIdentityRow>{};
  final skipped = <String, int>{};
  var appliedSeq = 0;
  for (final envelope in ordered) {
    final seq = envelope.seq ?? 0;
    if (seq > appliedSeq) appliedSeq = seq;
    if (envelope.family != TrajectoryFamily.attempt) continue;
    final record = TrajectoryCodec.decode(envelope);
    if (record is OpaqueRecord) {
      final key = '${envelope.recordType}@v${envelope.typeVersion}';
      skipped[key] = (skipped[key] ?? 0) + 1;
      continue;
    }
    final delta = processIdentityDeltaFor(envelope, decoded: record);
    if (delta == null) continue;
    applyProcessIdentityDelta(rows, delta, lastSeq: seq);
  }
  return ProcessIdentityFoldResult(
    rows: rows,
    appliedSeq: appliedSeq,
    skipped: skipped,
  );
}

/// Truncate-and-replay against a live `USE trajectory` session (§5 Rebuild).
/// Run with the station DOWN; the projections are dolt_ignore'd working-set
/// state, so nothing here stages or commits dolt history.
Future<ProcessIdentityFoldResult> replayProcessIdentities(
  TrajectoryDb db, {
  DateTime Function() clock = DateTime.now,
}) async {
  final scanned = await db.execute('SELECT * FROM trajectory ORDER BY seq');
  final result = foldProcessIdentities([
    for (final row in scanned.rows) envelopeFromRow(row),
  ]);
  try {
    await db.execute('START TRANSACTION');
    await db.execute('DELETE FROM proj_process_identity');
    for (final row in result.rows.values) {
      final params = row.toSqlParams();
      final columns = params.keys.toList();
      await db.execute(
        'INSERT INTO proj_process_identity (${columns.join(', ')}) '
        'VALUES (${columns.map((c) => ':$c').join(', ')})',
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
        'projection': processIdentityProjection,
        'fold_version': processIdentityFoldVersion,
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
