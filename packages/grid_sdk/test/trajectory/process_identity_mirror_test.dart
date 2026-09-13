import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

TrajectoryEnvelope envelope(TrajectoryRecord record) {
  final instant = DateTime.utc(2026, 9, 13);
  return TrajectoryEnvelope.fromJson({
    'record_id': '01P6MIRROR000000000000000',
    'idem_key': 'p6'.padRight(64, 'k'),
    'idem_key_text': 'p6:test',
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': instant.toIso8601String(),
    'recorded_at': instant.toIso8601String(),
    'station': 'station',
    'authority_id': 'station/1',
    'boot_epoch': 1,
    'provenance': 'observed',
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  });
}

ProcessIdentityRow row({
  required String attempt,
  required int lastSeq,
  String? worktreeState,
  String session = 's-1',
}) => ProcessIdentityRow(
  attemptId: attempt,
  sessionId: session,
  round: 0,
  stepPath: 'work/agent',
  stepRound: 0,
  incarnation: 0,
  worktreeState: worktreeState,
  lastSeq: lastSeq,
);

void main() {
  test('seed publishes typed immutable rows and session index', () {
    final mirror = ProcessIdentityMirror();
    final changed = <TrajectoryProcessIdentitySnapshot>[];
    mirror.addListener(changed.add, fireImmediately: false);
    mirror.seed(
      rows: [row(attempt: 'a-1', lastSeq: 7, worktreeState: 'live')],
      seededAt: DateTime.utc(2026, 9, 13),
      stale: false,
      foldHeadSeq: 7,
    );

    expect(mirror.snapshot.health, TrajectorySnapshotHealth.live);
    expect(mirror.snapshot.rows.single.attemptId, 'a-1');
    expect(mirror.snapshot.bySessionId('s-1').single.attemptId, 'a-1');
    expect(changed, hasLength(1));
  });

  test('the sole horizon predicate retains boundary and every live row', () {
    final mirror = ProcessIdentityMirror();
    mirror.seed(
      rows: [
        row(attempt: 'old-held', lastSeq: 0, worktreeState: 'held'),
        row(attempt: 'boundary', lastSeq: 1, worktreeState: 'reaped'),
        row(attempt: 'ancient-live', lastSeq: -999999, worktreeState: 'live'),
      ],
      seededAt: DateTime.utc(2026, 9, 13),
      stale: false,
      foldHeadSeq: kProcessIdentityRetentionHorizon + 1,
    );

    final ids = mirror.snapshot.rows.map((item) => item.attemptId).toSet();
    expect(ids, {'boundary', 'ancient-live'});
  });

  test('committed deltas update P6 and unrelated commits advance eviction', () {
    final mirror = ProcessIdentityMirror();
    mirror.seed(
      rows: [row(attempt: 'old-held', lastSeq: 0, worktreeState: 'held')],
      seededAt: DateTime.utc(2026, 9, 13),
      stale: false,
      foldHeadSeq: 0,
    );
    const started = AttemptProcessStarted(
      attemptId: '01P6ATTEMPT00000000000001',
      sessionId: 's-2',
      round: 0,
      stepPath: 'work/agent',
      stepRound: 0,
      incarnation: 0,
      pid: 41,
      pgid: 42,
    );
    mirror.applyAppended(envelope(started), seq: 1, decoded: started);
    expect(
      mirror.snapshot.rows
          .where((item) => item.attemptId == started.attemptId)
          .single
          .pgid,
      42,
    );

    const note = AttemptNote(
      sessionId: 's-1',
      body: 'unrelated',
      channel: 'test',
      noteOrdinal: 1,
    );
    mirror.applyAppended(
      envelope(note),
      seq: kProcessIdentityRetentionHorizon + 1,
      decoded: note,
    );
    expect(
      mirror.snapshot.rows.map((item) => item.attemptId),
      isNot(contains('old-held')),
    );
  });

  test('heartbeat publishes only when explicitly told a tick ran', () {
    final mirror = ProcessIdentityMirror();
    mirror.seed(
      rows: const [],
      seededAt: DateTime.utc(2026, 9, 13),
      stale: false,
      foldHeadSeq: 0,
    );
    expect(mirror.snapshot.lastTickAt, isNull);
    final tickAt = DateTime.utc(2026, 9, 13, 1);
    mirror.noteTickAt(tickAt);
    expect(mirror.snapshot.lastTickAt, tickAt);
  });

  test('health compromise latches downward', () {
    final mirror = ProcessIdentityMirror();
    mirror.seed(
      rows: const [],
      seededAt: DateTime.utc(2026, 9, 13),
      stale: false,
      foldHeadSeq: 0,
    );
    expect(mirror.latchCompromised(), isTrue);
    expect(mirror.latchCompromised(), isFalse);
    expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
  });
}
