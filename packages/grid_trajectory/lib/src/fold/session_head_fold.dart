/// The REPLAY application mode (§5 Rebuild): fold a record stream into
/// in-memory P1 rows, then write them — truncate `proj_session_head`, insert
/// the folded rows, and drive `proj_meta.applied_seq` + `fold_version` in one
/// SQL transaction.
///
/// Replay quiescence is the §5 minor-fix rule: this runs with the station
/// DOWN (the Stage-0 posture; the shadow-rebuild-and-swap variant arrives
/// with live Stage-1 readers). Projection schema migration is only ever
/// fold_version bump + truncate + replay — the log is never migrated.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../cli/trajectory_reader.dart' show envelopeFromRow;
import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import '../connect/trajectory_db.dart';
import 'session_head_delta.dart';
import 'session_head_row.dart';

/// P1's fold version (§5: bumped with any projection-shape change, which
/// forces truncate + replay).
const int sessionHeadFoldVersion = 1;

/// §2.6 rule 5: the `(record_type, min_version, max_version)` set this fold
/// CONSUMES — the boot check's declaration. Family-1 types absent here are
/// deliberately not consumed by P1 (their facts are P6/P3's).
const Map<String, (int, int)> sessionHeadFoldConsumes = {
  'attempt.session.started': (1, 1),
  'attempt.terminal': (1, 1),
  'attempt.round.retired': (1, 1),
  'attempt.rework_declined': (1, 1),
  'attempt.process.started': (1, 1),
  'attempt.process.exited': (1, 1),
};

/// One replay's outcome: the folded rows plus the `proj_meta` bookkeeping.
@immutable
class SessionHeadFoldResult {
  const SessionHeadFoldResult({
    required this.rows,
    required this.appliedSeq,
    required this.skipped,
  });

  /// Folded P1 rows keyed by session_id.
  final Map<String, SessionHeadRow> rows;

  /// The highest `seq` SCANNED (not merely applied): the fold has seen the
  /// whole log up to here even where a record produced no delta.
  final int appliedSeq;

  /// §2.6 rule 3: attempt-family rows that decoded to [OpaqueRecord]
  /// (unknown `(type, version)` or a refusing decoder), counted per
  /// `<type>@v<version>` for `proj_meta.skipped`.
  final Map<String, int> skipped;
}

/// Folds [records] into P1 rows — deterministic, pure, no I/O.
///
/// Ordering is §5's rebuild rule: `(station, boot_epoch, epoch_seq)` order,
/// with the RECONSTRUCTED rows re-sorted by `occurred_at` among themselves
/// (§8 Q18 — a backfill import's append order is not testimony; its
/// occurred_at is). The re-sort swaps reconstructed rows across the slots
/// they already occupy, so observed/inferred rows never move.
SessionHeadFoldResult foldSessionHeads(Iterable<TrajectoryEnvelope> records) {
  final ordered = orderForReplay(records);
  final rows = <String, SessionHeadRow>{};
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
    final delta = sessionHeadDeltaFor(envelope, decoded: record);
    if (delta == null) continue;
    applySessionHeadDelta(rows, delta, lastSeq: seq);
  }
  return SessionHeadFoldResult(
    rows: rows,
    appliedSeq: appliedSeq,
    skipped: skipped,
  );
}

/// §5's replay order, exposed for tests: primary sort
/// `(station, boot_epoch, epoch_seq)` (seq as the tiebreak), then the
/// reconstructed subset re-sorted by `occurred_at` in place.
List<TrajectoryEnvelope> orderForReplay(Iterable<TrajectoryEnvelope> records) {
  final ordered = records.toList()
    ..sort((a, b) {
      final station = a.station.compareTo(b.station);
      if (station != 0) return station;
      final epoch = a.bootEpoch.compareTo(b.bootEpoch);
      if (epoch != 0) return epoch;
      final epochSeq = (a.epochSeq ?? 0).compareTo(b.epochSeq ?? 0);
      if (epochSeq != 0) return epochSeq;
      return (a.seq ?? 0).compareTo(b.seq ?? 0);
    });
  final slots = <int>[
    for (var i = 0; i < ordered.length; i++)
      if (ordered[i].provenance == TrajectoryProvenance.reconstructed) i,
  ];
  if (slots.length < 2) return ordered;
  final reconstructed = [for (final i in slots) ordered[i]]
    ..sort((a, b) {
      final at = a.occurredAt.compareTo(b.occurredAt);
      if (at != 0) return at;
      return (a.seq ?? 0).compareTo(b.seq ?? 0);
    });
  for (var i = 0; i < slots.length; i++) {
    ordered[slots[i]] = reconstructed[i];
  }
  return ordered;
}

/// Truncate-and-replay against a live `USE trajectory` session (§5 Rebuild).
///
/// Reads the WHOLE log in `seq` order, folds, then in one SQL transaction:
/// `DELETE FROM proj_session_head`, re-insert every folded row, and upsert
/// `proj_meta` (`fold_version`, `applied_seq`, `skipped`, `rebuilt_at`). The
/// projections are dolt_ignore'd working-set state, so nothing here stages
/// or commits dolt history. Run with the station DOWN.
Future<SessionHeadFoldResult> replaySessionHeads(
  TrajectoryDb db, {
  DateTime Function() clock = DateTime.now,
}) async {
  final scanned = await db.execute('SELECT * FROM trajectory ORDER BY seq');
  final result = foldSessionHeads([
    for (final row in scanned.rows) envelopeFromRow(row),
  ]);
  try {
    await db.execute('START TRANSACTION');
    await db.execute('DELETE FROM proj_session_head');
    for (final row in result.rows.values) {
      final params = row.toSqlParams();
      final columns = params.keys.toList();
      await db.execute(
        'INSERT INTO proj_session_head (${columns.join(', ')}) '
        'VALUES (${columns.map((c) => ':$c').join(', ')})',
        params,
      );
    }
    await db.execute(
      'INSERT INTO proj_meta '
      '(projection, fold_version, applied_seq, skipped, rebuilt_at) '
      "VALUES ('fold', :fold_version, :applied_seq, :skipped, :rebuilt_at) "
      'ON DUPLICATE KEY UPDATE fold_version = :fold_version, '
      'applied_seq = :applied_seq, skipped = :skipped, '
      'rebuilt_at = :rebuilt_at',
      {
        'fold_version': sessionHeadFoldVersion,
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
