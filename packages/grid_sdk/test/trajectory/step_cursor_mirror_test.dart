/// THE P2 MIRROR (cut-wiring C4 / §0.2) — seed, the `byP2SessionId` index,
/// post-ACK discipline, eviction, health, and the golden equivalence with a
/// cold fold of the same log.
///
/// P1's suite pins the properties the SESSION dual read rests on; this one
/// pins the step axis's, plus the two things that are P2's own: one session
/// holds MANY rows (the two-ladder key), and closed sessions EVICT.
library;

// `StepState` exists in BOTH packages — the cursor's and the record's — so
// the engine side is imported by name. The vocabulary in this file is the
// RECORD's, because everything here drives the fold.
import 'package:grid_engine/grid_engine.dart'
    show TrajectorySnapshotHealth, collapseStepCursors;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final _boot = DateTime.utc(2026, 8, 31, 12);

var _seq = 0;

/// An envelope in the shape the appender commits — service stamps plus the
/// record's own correlation columns.
TrajectoryEnvelope _envelope(TrajectoryRecord record) {
  _seq += 1;
  final json = <String, Object?>{
    'record_id': '01STEPMIR${_seq.toString().padLeft(17, '0')}',
    'idem_key': '$_seq'.padRight(64, 'k'),
    'idem_key_text': 'step-mirror:$_seq',
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': _boot.toIso8601String(),
    'recorded_at': _boot.toIso8601String(),
    'station': 'tranquility',
    'authority_id': 'tranquility/1',
    'boot_epoch': 1,
    'provenance': TrajectoryProvenance.observed.wire,
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  };
  // §2.6 rule 7's `ck_substation`: a work_bead_id needs the service-derived
  // substation.
  if (json['work_bead_id'] != null) json['substation'] = 'tg';
  return TrajectoryEnvelope.fromJson(json);
}

StepTransition _transition(
  String stepPath, {
  required StepState state,
  String sessionId = 'tranquility-1',
  int round = 0,
  int stepRound = 0,
  int incarnation = 0,
  StepCause? cause,
}) => StepTransition(
  sessionId: sessionId,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  incarnation: incarnation,
  state: state,
  cause: cause,
);

/// Feeds [records] through the mirror the way the writer loop does: one
/// post-ACK apply per landed append, at that append's own ordinal.
List<TrajectoryEnvelope> _drive(
  StepCursorMirror mirror,
  List<TrajectoryRecord> records,
) {
  final envelopes = <TrajectoryEnvelope>[];
  var ordinal = 0;
  for (final record in records) {
    ordinal += 1;
    final envelope = _envelope(record);
    envelopes.add(envelope);
    mirror.applyAppended(envelope, seq: ordinal, decoded: record);
  }
  return envelopes;
}

StepCursorRow _row({
  String sessionId = 'tranquility-1',
  String stepPath = 'build',
  int round = 0,
  int stepRound = 0,
  String state = 'running',
}) => StepCursorRow(
  sessionId: sessionId,
  round: round,
  stepPath: stepPath,
  stepRound: stepRound,
  state: state,
  incarnation: 0,
  lastSeq: 1,
);

void main() {
  group('the boot seed', () {
    test('an unseeded mirror REFUSES — nothing may be served from a mirror '
        'that never read the fold', () {
      final mirror = StepCursorMirror();
      expect(mirror.isSeeded, isFalse);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
      expect(mirror.snapshot.byP2SessionId('tranquility-1'), isEmpty);
    });

    test('a clean seed lifts health to live and indexes by session', () {
      final mirror = StepCursorMirror()
        ..seed(
          rows: [
            _row(stepPath: 'build'),
            _row(stepPath: 'review', state: 'pending'),
            _row(sessionId: 'tranquility-2', stepPath: 'build'),
          ],
          seededAt: _boot,
          stale: false,
          firstEpochClaimedAt: _boot,
        );
      final snapshot = mirror.snapshot as StepCursorSnapshot;
      expect(snapshot.health, TrajectorySnapshotHealth.live);
      expect(snapshot.length, 3);
      expect(snapshot.sessions, 2);
      expect(snapshot.byP2SessionId('tranquility-1'), hasLength(2));
      expect(snapshot.byP2SessionId('tranquility-2'), hasLength(1));
      expect(snapshot.firstEpochClaimedAt, _boot);
    });

    test('a STALE seed refuses for the boot — legacy stays primary', () {
      final mirror = StepCursorMirror()
        ..seed(rows: [_row()], seededAt: _boot, stale: true);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
      // The rows are still there; what is refused is SERVING them.
      expect((mirror.snapshot as StepCursorSnapshot).length, 1);
    });

    test(
      'ONE session holds MANY rows — the two-ladder key, not the session',
      () {
        final mirror = StepCursorMirror()
          ..seed(
            rows: [
              _row(stepPath: 'build', state: 'complete'),
              _row(stepPath: 'build', stepRound: 1, state: 'pending'),
              _row(stepPath: 'build', round: 1, state: 'running'),
            ],
            seededAt: _boot,
            stale: false,
          );
        final rows = mirror.snapshot.byP2SessionId('tranquility-1');
        expect(rows, hasLength(3));
        // The COLLAPSE is the engine's, not the mirror's — and it picks the
        // greatest (round, step_round).
        final collapsed = collapseStepCursors(rows);
        expect(collapsed['build']!.round, 1);
        expect(collapsed['build']!.stepState, 'running');
      },
    );
  });

  group('post-ACK maintenance', () {
    test(
      'a landed transition BIRTHS the cursor row — P2 has no mint record',
      () {
        final mirror = StepCursorMirror()
          ..seed(rows: const [], seededAt: _boot, stale: false);
        _drive(mirror, [_transition('build', state: StepState.running)]);
        final rows = mirror.snapshot.byP2SessionId('tranquility-1');
        expect(rows, hasLength(1));
        expect(rows.single.stepState, 'running');
        expect(rows.single.lastSeq, 1);
      },
    );

    test('a later transition ADVANCES exactly the carried columns', () {
      final mirror = StepCursorMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [
        _transition('build', state: StepState.running),
        _transition('build', state: StepState.complete),
      ]);
      final rows = mirror.snapshot.byP2SessionId('tranquility-1');
      expect(rows, hasLength(1), reason: 'same two-ladder key = same row');
      expect(rows.single.stepState, 'complete');
      expect(rows.single.lastSeq, 2);
    });

    test(
      'a gate-cleared REARM births the new rung and links the predecessor',
      () {
        final mirror = StepCursorMirror()
          ..seed(rows: const [], seededAt: _boot, stale: false);
        _drive(mirror, [
          _transition('build', state: StepState.gated),
          _transition(
            'build',
            state: StepState.pending,
            stepRound: 1,
            cause: StepCause.gateCleared,
          ),
        ]);
        final rows = mirror.snapshot.byP2SessionId('tranquility-1').toList();
        expect(rows, hasLength(2));
        final predecessor = rows.firstWhere((r) => r.stepRound == 0);
        expect(
          predecessor.supersededByStepRound,
          1,
          reason: 'the chain has no holes — the bump writes the PREDECESSOR',
        );
        // And the collapse serves the new rung, which is what stops the I-14
        // stale-join loop from reading `gated` forever.
        expect(collapseStepCursors(rows)['build']!.stepState, 'pending');
      },
    );

    test('a NON-step record applies nothing', () {
      final mirror = StepCursorMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      final before = mirror.snapshot.version;
      _drive(mirror, [
        const AttemptSessionStarted(
          sessionId: 'tranquility-1',
          workBeadId: 'tg-9abc',
          rig: 'operator',
          model: 'molecule',
          grantId: '01J8GRANT00000000000000001',
        ),
      ]);
      expect(mirror.snapshot.version, before, reason: 'no publish, no delta');
    });

    test('the mirror equals a COLD FOLD of the same record stream', () {
      // The golden invariant: mirror == SQL fold == replay. A drift here is
      // the dual read reading one thing while `traj replay` rebuilds another.
      final mirror = StepCursorMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      final records = <TrajectoryRecord>[
        _transition('build', state: StepState.running),
        _transition('build', state: StepState.complete),
        _transition('review', state: StepState.running),
        _transition(
          'review',
          state: StepState.pending,
          stepRound: 1,
          cause: StepCause.gateCleared,
        ),
        _transition(
          'build',
          state: StepState.running,
          sessionId: 'tranquility-2',
        ),
      ];
      final envelopes = _drive(mirror, records);
      final withSeq = <TrajectoryEnvelope>[
        for (var i = 0; i < envelopes.length; i++)
          TrajectoryEnvelope.fromJson({...envelopes[i].toJson(), 'seq': i + 1}),
      ];

      final cold = foldStepCursors(withSeq);

      final mirrored = <StepCursorKey, String>{
        for (final session in ['tranquility-1', 'tranquility-2'])
          for (final row in mirror.snapshot.byP2SessionId(session))
            (
              sessionId: row.sessionId,
              round: row.round,
              stepPath: row.stepPath,
              stepRound: row.stepRound,
            ): '${row.stepState}/${row.supersededByStepRound}/${row.lastSeq}',
      };
      final folded = <StepCursorKey, String>{
        for (final entry in cold.rows.entries)
          entry.key:
              '${entry.value.state}/${entry.value.supersededByStepRound}/'
              '${entry.value.lastSeq}',
      };
      expect(mirrored, folded);
    });
  });

  group('eviction (§0.2\'s memory bound)', () {
    test('rows for sessions CLOSED in P1 go; live sessions stay', () {
      final mirror = StepCursorMirror()
        ..seed(
          rows: [
            _row(stepPath: 'build'),
            _row(stepPath: 'review'),
            _row(sessionId: 'tranquility-2', stepPath: 'build'),
          ],
          seededAt: _boot,
          stale: false,
        );
      expect(mirror.evictClosedSessions({'tranquility-1'}), 2);
      expect(mirror.snapshot.byP2SessionId('tranquility-1'), isEmpty);
      expect(mirror.snapshot.byP2SessionId('tranquility-2'), hasLength(1));
    });

    test('an empty closed set is a no-op that does not even publish', () {
      final mirror = StepCursorMirror()
        ..seed(rows: [_row()], seededAt: _boot, stale: false);
      final version = mirror.snapshot.version;
      expect(mirror.evictClosedSessions(const <String>{}), 0);
      expect(mirror.snapshot.version, version);
    });

    test('evicting a session the mirror does not hold publishes nothing', () {
      final mirror = StepCursorMirror()
        ..seed(rows: [_row()], seededAt: _boot, stale: false);
      final version = mirror.snapshot.version;
      expect(mirror.evictClosedSessions({'tranquility-9'}), 0);
      expect(mirror.snapshot.version, version);
    });
  });

  group('health and the change seam', () {
    test('the compromised latch fires ONCE and never lifts', () {
      final mirror = StepCursorMirror()
        ..seed(rows: [_row()], seededAt: _boot, stale: false);
      expect(mirror.latchCompromised(), isTrue);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
      expect(mirror.latchCompromised(), isFalse);
      // A reseed is a re-read, not absolution.
      mirror.reseed(rows: [_row()], seededAt: _boot);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
    });

    test('a listener sees every publication and the remover works', () {
      final seen = <int>[];
      final mirror = StepCursorMirror();
      final remove = mirror.addListener((s) => seen.add(s.version));
      mirror.seed(rows: [_row()], seededAt: _boot, stale: false);
      remove();
      mirror.reseed(rows: const [], seededAt: _boot);
      expect(seen, [0, 1], reason: 'fireImmediately, then the seed; not after');
    });

    test('a THROWING listener never breaks the writer loop that published', () {
      final mirror = StepCursorMirror()
        ..addListener((_) => throw StateError('bad subscriber'));
      expect(
        () => mirror.seed(rows: [_row()], seededAt: _boot, stale: false),
        returnsNormally,
      );
    });
  });
}
