/// The Fake trajectory database `traj certify`'s tests certify against —
/// seeded boots, seeded seats, and the round-summary bodies §W2.5 reads.
library;

import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';

import '../support/scripted_reader.dart';

/// The roster substation each ruling seat resolves to.
const Map<String, String> seatSubstations = {
  'lenny': 'lenny',
  'butane': 'butane_flutter',
};

/// A CLEAN §W2.5 body: mode primary, overlay engaged, health live with no
/// transition, the epoch anchor set, and every gating counter zero —
/// deliberately the WHOLE table, so a row this verb stops gating shows up as a
/// test that no longer fails. [overrides] dirties exactly one thing at a time.
Map<String, Object?> summaryBody({
  int passes = 12,
  String scope = 'session-terminal',
  Map<String, Object?> overrides = const {},
}) => <String, Object?>{
  'channel': 'dual-read-round-summary',
  'axis': 'session+step',
  'scope': scope,
  'mode': 'primary',
  'health': 'live',
  // The producer's HEALTHY shape, not an empty list: `_noteHealth` records
  // the first health it observes as a bare state name, so every real boot
  // carries exactly this (`dual_read_pass.dart`).
  'health_transitions': <String>['live'],
  'overlay_engaged': true,
  'overlay_disengaged_for_boot': false,
  'step_axis_engaged': true,
  'passes': passes,
  'soak_window_epoch': 50,
  'miss_post_epoch': 0,
  'miss_post_epoch_total': 0,
  'miss_legacy_era': 0,
  'null_started_at': 0,
  'fallbacks': 0,
  'p1_orphan': 0,
  'p2_miss': 0,
  'p2_miss_total': 0,
  'unexplained_divergences_in_window': 0,
  'step_unexplained_divergences_in_window': 0,
  'cardinality_breaches_in_window': 0,
  'terminal_lag_open_in_window': 0,
  'retirement_lag_open_in_window': 0,
  'step_lag_open': 0,
  'append_drops': 0,
  'append_suppressed': 0,
  'append_refused_testimony': 0,
  'append_ack_p99_ms': 31,
  'first_epoch_claimed_at': '2026-09-06T00:00:00.000Z',
  ...overrides,
};

/// One round on [seat] in [epoch]: the session's own record (which carries the
/// substation the seat is read from) plus its durable round-summary note.
List<TrajectoryEnvelope> seededRound({
  required int epoch,
  required int seq,
  required String seat,
  Map<String, Object?>? body,
}) {
  final sessionId = 'tranquility-$epoch-$seat';
  return [
    envelope(
      recordType: 'attempt.session.started',
      family: TrajectoryFamily.attempt,
      seq: seq,
      bootEpoch: epoch,
      sessionId: sessionId,
      workBeadId: '$seat-1',
      substation: seatSubstations[seat] ?? seat,
      attemptId: 'attempt-$epoch-$seat',
    ),
    summaryNote(
      seq: seq + 1,
      epoch: epoch,
      sessionId: sessionId,
      body: body ?? summaryBody(),
    ),
  ];
}

/// A round whose session was MOUNTED in [startedEpoch] and whose summary note
/// landed in [epoch] — the bounce-mid-round shape. The window over [epoch]
/// holds the note and nothing that names the seat, so only a read of the
/// session's own history can attribute it.
List<TrajectoryEnvelope> seededCarriedRound({
  required int startedEpoch,
  required int epoch,
  required int seq,
  required String seat,
  Map<String, Object?>? body,
}) {
  final sessionId = 'tranquility-$startedEpoch-$seat-carried';
  return [
    envelope(
      recordType: 'attempt.session.started',
      family: TrajectoryFamily.attempt,
      seq: seq,
      bootEpoch: startedEpoch,
      sessionId: sessionId,
      workBeadId: '$seat-carried',
      substation: seatSubstations[seat] ?? seat,
      attemptId: 'attempt-$startedEpoch-$seat-carried',
    ),
    summaryNote(
      seq: seq + 1,
      epoch: epoch,
      sessionId: sessionId,
      body: body ?? summaryBody(),
    ),
  ];
}

/// A `dual-read-round-summary` note carrying [body].
TrajectoryEnvelope summaryNote({
  required int seq,
  required int epoch,
  required String sessionId,
  required Map<String, Object?> body,
}) => envelope(
  recordType: 'attempt.note',
  family: TrajectoryFamily.attempt,
  seq: seq,
  bootEpoch: epoch,
  sessionId: sessionId,
  payload: <String, Object?>{
    'body': jsonEncode(body),
    'channel': kRoundSummaryNoteChannel,
    'note_ordinal': seq,
  },
);

/// Three consecutive boots, each with one lenny round and one butane round,
/// every counter clean. [dirty] replaces the body of the LAST round of the
/// epoch it names — the governing note.
List<TrajectoryEnvelope> seededBoots({
  List<int> epochs = const [50, 51, 52],
  Map<int, Map<String, Object?>> dirty = const {},
}) {
  final rows = <TrajectoryEnvelope>[];
  var seq = 1;
  for (final epoch in epochs) {
    rows.addAll(seededRound(epoch: epoch, seq: seq, seat: 'lenny'));
    seq += 2;
    rows.addAll(
      seededRound(
        epoch: epoch,
        seq: seq,
        seat: 'butane',
        body: dirty[epoch] == null
            ? null
            : summaryBody(overrides: dirty[epoch]!),
      ),
    );
    seq += 2;
  }
  return rows;
}

/// The ledger those boots claimed.
List<EpochClaim> seededClaims(List<int> epochs) => [
  for (final epoch in epochs)
    EpochClaim(station: 'lunar', epoch: epoch, records: 4),
];
