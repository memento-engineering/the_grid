/// A [TrajectoryLogReader] over a fixed row set, plus envelope builders — so
/// the verbs' rendering and exit codes are drivable without a socket.
library;

import 'package:grid_trajectory/grid_trajectory.dart';

class ScriptedReader implements TrajectoryLogReader {
  ScriptedReader(this.rows);

  final List<TrajectoryEnvelope> rows;
  bool closed = false;

  @override
  Future<List<TrajectoryEnvelope>> rowsForSubject(
    String subject, {
    int limit = defaultReadLimit,
  }) async => rows
      .where(
        (row) =>
            row.workBeadId == subject ||
            row.sessionId == subject ||
            row.attemptId == subject,
      )
      .take(limit)
      .toList();

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
  TerminalOutcome? outcome,
  String? unknownReason,
}) => TrajectoryEnvelope(
  seq: seq,
  epochSeq: seq,
  recordId: '01JAAAAAAAAAAAAAAAAAAAAA${seq.toString().padLeft(2, '0')}',
  idemKey: 'f' * 64,
  idemKeyText: '$recordType|$seq',
  family: family,
  recordType: recordType,
  typeVersion: typeVersion,
  occurredAt: DateTime.utc(2026, 8, 31, 9, 14, 2, 123),
  recordedAt: DateTime.utc(2026, 8, 31, 9, 14, 2, 456),
  station: 'lunar',
  seat: workBeadId == null ? null : 'the_grid',
  authorityId: 'lunar/1',
  bootEpoch: 1,
  source: 'test',
  workBeadId: workBeadId,
  sessionId: sessionId,
  attemptId: attemptId,
  grantId: grantId,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  outcome: outcome,
  unknownReason: unknownReason,
  payload: payload,
);
