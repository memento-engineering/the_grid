/// A [TrajectoryLogReader] over a fixed row set, plus envelope builders — so
/// the verbs' rendering and exit codes are drivable without a socket.
library;

import 'package:grid_trajectory/grid_trajectory.dart';

class ScriptedReader implements TrajectoryLogReader {
  ScriptedReader(this.rows, {this.staleness, this.truncateCompleteReadsAt});

  final List<TrajectoryEnvelope> rows;
  final FoldStaleness? staleness;

  /// Forces [allRecordsForSubject] to report a CUT stream at this many rows —
  /// the reader-side truncation the §9 comparator must refuse to fold.
  final int? truncateCompleteReadsAt;

  bool closed = false;

  @override
  Future<FoldStaleness?> foldStaleness() async => staleness;

  List<TrajectoryEnvelope> _forSubject(String subject) => rows
      .where(
        (row) =>
            row.workBeadId == subject ||
            row.sessionId == subject ||
            row.attemptId == subject,
      )
      .toList();

  @override
  Future<List<TrajectoryEnvelope>> rowsForSubject(
    String subject, {
    int limit = defaultReadLimit,
  }) async => _forSubject(subject).take(limit).toList();

  @override
  Future<SubjectRecords> allRecordsForSubject(
    String subject, {
    int ceiling = completeReadCeiling,
  }) async {
    final matched = _forSubject(subject);
    final cut = truncateCompleteReadsAt ?? ceiling;
    if (matched.length > cut) {
      return SubjectRecords(
        records: matched.take(cut).toList(),
        truncatedAt: cut,
      );
    }
    return SubjectRecords(records: matched);
  }

  @override
  Future<SubjectRecords> recordsInWindow({
    DateTime? since,
    int? bootEpoch,
    int ceiling = completeReadCeiling,
  }) async {
    final matched = rows
        .where(
          (row) =>
              (since == null || !row.occurredAt.isBefore(since)) &&
              (bootEpoch == null || row.bootEpoch == bootEpoch),
        )
        .toList();
    final cut = truncateCompleteReadsAt ?? ceiling;
    if (matched.length > cut) {
      return SubjectRecords(
        records: matched.take(cut).toList(),
        truncatedAt: cut,
      );
    }
    return SubjectRecords(records: matched);
  }

  @override
  Future<List<String>> sessions({int limit = defaultReadLimit}) async => {
    for (final row in rows)
      if (row.sessionId case final String id) id,
  }.take(limit).toList();

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// An opener that always yields [open].
TrajectoryOpener openerFor(TrajectoryOpen open) =>
    (_) async => open;

/// A minimally-populated envelope — every column the §4 CHECKs demand, and
/// nothing else unless the caller asks.
TrajectoryEnvelope envelope({
  required String recordType,
  required TrajectoryFamily family,
  int seq = 1,
  int typeVersion = 1,
  Map<String, Object?> payload = const {},
  String? sessionId,
  String? workBeadId,
  String? attemptId,
  String? grantId,
  int? round,
  String? stepPath,
  int? stepRound,
  int? incarnation,
  String? mountAttemptId,
  String? gateId,
  String? worktree,
  String? branch,
  String? commitSha,
  TerminalOutcome? outcome,
  String? unknownReason,
  String? resolvesRecordId,
  DateTime? occurredAt,
  int bootEpoch = 1,
  TrajectoryProvenance provenance = TrajectoryProvenance.observed,
}) => TrajectoryEnvelope(
  seq: seq,
  epochSeq: seq,
  recordId: '01JAAAAAAAAAAAAAAAAAAAAA${seq.toString().padLeft(2, '0')}',
  idemKey: 'f' * 64,
  idemKeyText: '$recordType|$seq',
  family: family,
  recordType: recordType,
  typeVersion: typeVersion,
  occurredAt: occurredAt ?? DateTime.utc(2026, 8, 31, 9, 14, 2, 123),
  recordedAt: DateTime.utc(2026, 8, 31, 9, 14, 2, 456),
  station: 'lunar',
  substation: workBeadId == null ? null : 'the_grid',
  authorityId: 'lunar/$bootEpoch',
  bootEpoch: bootEpoch,
  provenance: provenance,
  provenanceBasis: provenance == TrajectoryProvenance.observed
      ? null
      : 'test-basis',
  source: 'test',
  resolvesRecordId: resolvesRecordId,
  workBeadId: workBeadId,
  sessionId: sessionId,
  attemptId: attemptId,
  grantId: grantId,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  incarnation: incarnation,
  mountAttemptId: mountAttemptId,
  gateId: gateId,
  worktree: worktree,
  branch: branch,
  commitSha: commitSha,
  outcome: outcome,
  unknownReason: unknownReason,
  payload: payload,
);
