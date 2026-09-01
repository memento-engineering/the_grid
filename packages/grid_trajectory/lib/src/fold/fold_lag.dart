/// The READER LAG rule and the fold GENERATION set — the two `proj_meta`
/// facts every fold reader has to consult before it trusts a projection.
///
/// **The lag rule** (schema §5's reader-staleness bound, cut-wiring's honest
/// restatement of ratified constraint 6): the appender commits its fold deltas
/// and the `applied_seq` cursor in ONE transaction on the shared `'fold'` row
/// (`trajectory_appender.dart`), so lag is structurally zero outside a
/// mid-replay boot or an out-of-contract writer. The check is cheap and it
/// guards exactly those states, so it stays. It reads the `'fold'` row ONLY —
/// the `'step_cursor'`/`'process_identity'` rows carry a replay-time
/// `applied_seq` that freezes where the rebuild left it and is not a lag
/// signal.
///
/// **The generation set** is the per-projection triple
/// `(projection, fold_version, rebuilt_at)`. The appender never writes
/// `rebuilt_at`; the three in-tree replay functions all stamp it, each on its
/// own row. So a triple that changed under a live reader means a replay ran
/// against the store — which `traj replay` refuses to be (it is quiesce-only),
/// making this the DETECTOR for an out-of-contract rebuild, never a licence
/// for one.
library;

import 'package:meta/meta.dart';

import '../cli/trajectory_reader.dart' show staleLagLimit;
import '../connect/trajectory_db.dart';
import 'session_head_row.dart' show parseSqlDateTime6;

/// The shared cursor row the appender maintains — P1's replay upserts it too;
/// P2 and P6 keep rows of their own.
const String foldCursorProjection = 'fold';

/// The lag rule's AGE half: unapplied records older than this make the fold
/// stale even when their COUNT is under [staleLagLimit].
const Duration kFoldLagAgeBound = Duration(seconds: 60);

/// One `proj_meta` row — a projection's GENERATION plus its bookkeeping.
@immutable
class ProjectionGeneration {
  const ProjectionGeneration({
    required this.projection,
    required this.foldVersion,
    required this.appliedSeq,
    this.skipped,
    this.rebuiltAt,
  });

  /// Decodes one `assoc()` row of [projectionGenerationsSql].
  factory ProjectionGeneration.fromSqlRow(Map<String, String?> row) =>
      ProjectionGeneration(
        projection: row['projection'] ?? '',
        foldVersion: int.parse(row['fold_version'] ?? '0'),
        appliedSeq: int.parse(row['applied_seq'] ?? '0'),
        skipped: row['skipped'],
        rebuiltAt: parseSqlDateTime6(row['rebuilt_at']),
      );

  final String projection;
  final int foldVersion;
  final int appliedSeq;

  /// `proj_meta.skipped` as stored (a JSON object of `<type>@v<version>`
  /// counts) — reported, never parsed here.
  final String? skipped;
  final DateTime? rebuiltAt;

  /// The reseed guard's watched triple. A reader seeds the set of these and
  /// re-reads it on its own tick; ANY difference is a re-seed trigger.
  (String, int, DateTime?) get generation =>
      (projection, foldVersion, rebuiltAt);

  @override
  bool operator ==(Object other) =>
      other is ProjectionGeneration &&
      other.projection == projection &&
      other.foldVersion == foldVersion &&
      other.appliedSeq == appliedSeq &&
      other.skipped == skipped &&
      other.rebuiltAt == rebuiltAt;

  @override
  int get hashCode =>
      Object.hash(projection, foldVersion, appliedSeq, skipped, rebuiltAt);

  @override
  String toString() =>
      'ProjectionGeneration($projection, v$foldVersion, applied=$appliedSeq, '
      'rebuilt=${rebuiltAt?.toIso8601String() ?? 'never'})';
}

/// Where the appender's fold cursor stands against the log head.
@immutable
class FoldLag {
  const FoldLag({
    required this.appliedSeq,
    required this.maxSeq,
    required this.age,
    this.oldestUnappliedAt,
  });

  /// The rule applied to already-read values — pure, so both the verb and a
  /// reader's boot seed compute staleness the same way.
  factory FoldLag.from({
    required int appliedSeq,
    required int maxSeq,
    required DateTime now,
    DateTime? oldestUnappliedAt,
  }) => FoldLag(
    appliedSeq: appliedSeq,
    maxSeq: maxSeq,
    oldestUnappliedAt: oldestUnappliedAt,
    age: oldestUnappliedAt == null
        ? Duration.zero
        // Clamped at zero: a server clock marginally ahead of ours must not
        // read as negative age (and never as staleness).
        : _atLeastZero(now.toUtc().difference(oldestUnappliedAt.toUtc())),
  );

  final int appliedSeq;
  final int maxSeq;

  /// `recorded_at` of the OLDEST record the fold has not applied — null when
  /// there is none, which is the healthy steady state.
  final DateTime? oldestUnappliedAt;

  /// How long the oldest unapplied record has been waiting.
  final Duration age;

  /// Records the fold is behind the log head.
  int get records => maxSeq - appliedSeq;

  /// The refusal predicate: more than [staleLagLimit] records behind, or the
  /// oldest unapplied record older than [kFoldLagAgeBound].
  bool get isStale => records > staleLagLimit || age > kFoldLagAgeBound;

  @override
  String toString() =>
      'FoldLag(applied=$appliedSeq, head=$maxSeq, records=$records, '
      'age=${age.inMilliseconds}ms, stale=$isStale)';
}

Duration _atLeastZero(Duration value) =>
    value.isNegative ? Duration.zero : value;

/// Every `proj_meta` row, projection-ordered — the FULL generation set the
/// reseed guard watches (not just the `'fold'` row).
const String projectionGenerationsSql =
    'SELECT projection, fold_version, applied_seq, skipped, rebuilt_at '
    'FROM proj_meta ORDER BY projection';

const String _foldLagSql =
    'SELECT (SELECT COALESCE(MAX(seq), 0) FROM trajectory) AS max_seq, '
    '(SELECT COALESCE(MAX(applied_seq), 0) FROM proj_meta '
    "WHERE projection = '$foldCursorProjection') AS applied_seq";

const String _oldestUnappliedSql =
    'SELECT MIN(recorded_at) AS oldest FROM trajectory WHERE seq > :applied';

/// Reads the whole `proj_meta` generation set from [db].
Future<List<ProjectionGeneration>> readProjectionGenerations(
  TrajectoryDb db,
) async {
  final result = await db.execute(projectionGenerationsSql);
  return [for (final row in result.rows) ProjectionGeneration.fromSqlRow(row)];
}

/// Reads the appender cursor's lag from [db] — the `'fold'` row against
/// `MAX(seq)`, plus the age of the oldest record it has not applied.
Future<FoldLag> readFoldLag(
  TrajectoryDb db, {
  DateTime Function() clock = DateTime.now,
}) async {
  final head = await db.execute(_foldLagSql);
  final row = head.rows.isEmpty ? const <String, String?>{} : head.rows.first;
  final maxSeq = int.parse(row['max_seq'] ?? '0');
  final appliedSeq = int.parse(row['applied_seq'] ?? '0');
  DateTime? oldest;
  if (maxSeq > appliedSeq) {
    final behind = await db.execute(_oldestUnappliedSql, {
      'applied': appliedSeq,
    });
    oldest = behind.rows.isEmpty
        ? null
        : parseSqlDateTime6(behind.rows.first['oldest']);
  }
  return FoldLag.from(
    appliedSeq: appliedSeq,
    maxSeq: maxSeq,
    oldestUnappliedAt: oldest,
    now: clock().toUtc(),
  );
}
