/// THE P1 MIRROR (cut-wiring C1 / §0.2) — seed, post-ACK discipline, health,
/// the two indexes, and the golden equivalence with a cold replay.
///
/// The mirror is the only thing a decision read will ever touch on the fold
/// side (C2/C3), so the properties pinned here are the ones the whole dual-read
/// rests on: it applies EXACTLY what committed, at the ordinal that committed,
/// and it agrees with a from-scratch fold of the same log.
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final _boot = DateTime.utc(2026, 8, 31, 12);

var _seq = 0;

/// An envelope in the shape the appender commits — service stamps plus the
/// record's own correlation columns.
TrajectoryEnvelope _envelope(
  TrajectoryRecord record, {
  DateTime? occurredAt,
  TrajectoryProvenance provenance = TrajectoryProvenance.observed,
}) {
  _seq += 1;
  final stamped = occurredAt ?? _boot;
  final json = <String, Object?>{
    'record_id': '01MIRROR${_seq.toString().padLeft(18, '0')}',
    'idem_key': '$_seq'.padRight(64, 'k'),
    'idem_key_text': 'mirror:$_seq',
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': stamped.toIso8601String(),
    'recorded_at': stamped.toIso8601String(),
    'station': 'tranquility',
    'authority_id': 'tranquility/1',
    'boot_epoch': 1,
    'provenance': provenance.wire,
    if (provenance != TrajectoryProvenance.observed)
      'provenance_basis': 'test-basis',
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  };
  if (json['work_bead_id'] != null) json['substation'] = 'tg';
  return TrajectoryEnvelope.fromJson(json);
}

AttemptSessionStarted _started(String sessionId, {String bead = 'tg-9abc'}) =>
    AttemptSessionStarted(
      sessionId: sessionId,
      workBeadId: bead,
      rig: 'operator',
      model: 'molecule',
      grantId: '01J8GRANT00000000000000001',
    );

AttemptTerminal _terminal(
  String sessionId, {
  TerminalOutcome outcome = TerminalOutcome.succeeded,
  String attemptId = '01J8ATTEMPT000000000000002',
  String? unknownReason,
}) => AttemptTerminal(
  attemptId: attemptId,
  sessionId: sessionId,
  outcome: outcome,
  unknownReason: unknownReason,
);

/// Feeds [records] through the mirror the way the writer loop does: one
/// post-ACK apply per landed append, at that append's own ordinal.
List<TrajectoryEnvelope> _drive(
  SessionHeadMirror mirror,
  List<TrajectoryRecord> records, {
  TrajectoryProvenance provenance = TrajectoryProvenance.observed,
}) {
  final envelopes = <TrajectoryEnvelope>[];
  var ordinal = 0;
  for (final record in records) {
    ordinal += 1;
    final envelope = _envelope(record, provenance: provenance);
    envelopes.add(envelope);
    mirror.applyAppended(envelope, seq: ordinal, decoded: record);
  }
  return envelopes;
}

SessionHeadRow _row({
  required String sessionId,
  String workBeadId = 'tg-9abc',
  int round = 0,
  SessionHeadStatus status = SessionHeadStatus.open,
  TerminalOutcome? outcome,
  int lastSeq = 1,
  DateTime? startedAt,
}) => SessionHeadRow(
  sessionId: sessionId,
  workBeadId: workBeadId,
  round: round,
  status: status,
  outcome: outcome,
  startedAt: startedAt ?? _boot,
  headEpoch: 1,
  lastSeq: lastSeq,
);

void main() {
  setUp(() => _seq = 0);

  group('the boot seed', () {
    test('an unseeded mirror REFUSES: nothing may be served from a fold it '
        'never read', () {
      final mirror = SessionHeadMirror();
      expect(mirror.isSeeded, isFalse);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
      expect(mirror.snapshot.rows, isEmpty);
      expect(mirror.snapshot.seededAt, isNull);
    });

    test('a clean seed goes LIVE and carries the era boundary', () {
      final mirror = SessionHeadMirror()
        ..seed(
          rows: [_row(sessionId: 's-1')],
          seededAt: _boot,
          stale: false,
          firstEpochClaimedAt: DateTime.utc(2026, 8, 1),
        );
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.live);
      expect(mirror.snapshot.seededAt, _boot);
      expect(mirror.snapshot.firstEpochClaimedAt, DateTime.utc(2026, 8, 1));
      expect(mirror.snapshot.bySessionId('s-1'), isNotNull);
    });

    test('a STALE seed refuses for the boot — loud, never boot-blocking, and '
        'the rows are still held (they are simply not trusted)', () {
      final mirror = SessionHeadMirror()
        ..seed(
          rows: [_row(sessionId: 's-1')],
          seededAt: _boot,
          stale: true,
        );
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
      expect(mirror.snapshot.bySessionId('s-1'), isNotNull);
    });

    test('a stale seed stays refused for the BOOT — a later clean re-read '
        'never upgrades health', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: true);
      mirror.seed(rows: const [], seededAt: _boot, stale: false);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
    });

    test('a seed never CLEARS a latch: a drop before the seed keeps the '
        'snapshot compromised', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      expect(mirror.latchCompromised(), isTrue);
      mirror.seed(rows: const [], seededAt: _boot, stale: false);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
    });
  });

  group('post-ACK discipline (B-B7)', () {
    test('a landed append applies the delta at ITS ordinal', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [_started('s-1')]);

      final row = mirror.snapshot.bySessionId('s-1')!;
      expect(row.workBeadId, 'tg-9abc');
      expect(row.isOpen, isTrue);
      expect(row.round, 0);
      expect(row.lastSeq, 1);
    });

    test('a record with no P1 effect publishes nothing at all', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      final before = mirror.snapshot.version;
      final note = AttemptNote(
        sessionId: 's-1',
        body: 'observed',
        channel: 'ops',
        noteOrdinal: 1,
      );
      mirror.applyAppended(_envelope(note), seq: 9, decoded: note);
      expect(mirror.snapshot.version, before, reason: 'no delta, no publish');
    });

    test('an update for an absent session invents no row — the mirror never '
        'creates a head from a mid-life record', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [_terminal('ghost')]);
      expect(mirror.snapshot.rows, isEmpty);
    });

    test('the snapshot is IMMUTABLE and versioned — an older read never sees '
        'a later append', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [_started('s-1')]);
      final first = mirror.snapshot;
      _drive(mirror, [_started('s-2', bead: 'tg-other')]);

      expect(first.bySessionId('s-2'), isNull);
      expect(mirror.snapshot.bySessionId('s-2'), isNotNull);
      expect(mirror.snapshot.version, greaterThan(first.version));
    });

    test('listeners fire on publication and the remover works', () {
      final mirror = SessionHeadMirror();
      final seen = <int>[];
      final remove = mirror.addListener(
        (snapshot) => seen.add(snapshot.version),
        fireImmediately: false,
      );
      mirror.seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [_started('s-1')]);
      remove();
      _drive(mirror, [_started('s-2', bead: 'tg-other')]);

      expect(seen, hasLength(2), reason: 'seed + one applied delta');
      expect(seen, orderedEquals([seen.first, seen.last]));
    });
  });

  group('the two indexes', () {
    test('bySessionId is total over the mirror — the PK, retired rows '
        'included, which is what makes retired-bead comparison possible', () {
      final mirror = SessionHeadMirror()
        ..seed(
          rows: [
            _row(sessionId: 's-1', round: 2),
            _row(sessionId: 's-2'),
          ],
          seededAt: _boot,
          stale: false,
        );
      expect(mirror.snapshot.bySessionId('s-1')!.round, 2);
      expect(mirror.snapshot.bySessionId('s-2')!.round, 0);
      expect(mirror.snapshot.bySessionId('nope'), isNull);
    });

    test('byWorkBead applies the partitioned winner rule — a retired head '
        'never competes with its successor', () {
      final mirror = SessionHeadMirror()
        ..seed(
          rows: [
            _row(sessionId: 's-1', round: 1),
            _row(sessionId: 's-2'),
          ],
          seededAt: _boot,
          stale: false,
        );
      final winner = mirror.snapshot.byWorkBead('tg-9abc');
      expect((winner as SessionHeadWon).row.sessionId, 's-2');
    });

    test('two CURRENT open rows on one bead breach; a different bead is '
        'unaffected', () {
      final mirror = SessionHeadMirror()
        ..seed(
          rows: [
            _row(sessionId: 's-1'),
            _row(sessionId: 's-2'),
            _row(sessionId: 's-3', workBeadId: 'tg-other'),
          ],
          seededAt: _boot,
          stale: false,
        );
      expect(
        mirror.snapshot.byWorkBead('tg-9abc'),
        isA<SessionHeadCardinalityBreach>(),
      );
      expect(mirror.snapshot.byWorkBead('tg-other'), isA<SessionHeadWon>());
      expect(mirror.snapshot.byWorkBead('tg-absent'), isA<SessionHeadNone>());
    });
  });

  group('health', () {
    test('the COMPROMISED latch transitions exactly once', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      expect(mirror.latchCompromised(), isTrue);
      expect(mirror.latchCompromised(), isFalse, reason: 'latched, so quiet');
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
    });

    test('a refused snapshot does not later latch compromised — it is already '
        'disengaged, and one reason per boot is enough', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: true);
      expect(mirror.latchCompromised(), isFalse);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.refused);
    });

    test('a reseed re-reads the rows and leaves the latch alone', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      mirror.latchCompromised();
      mirror.reseed(
        rows: [_row(sessionId: 's-9')],
        seededAt: _boot.add(const Duration(minutes: 1)),
      );
      expect(mirror.snapshot.bySessionId('s-9'), isNotNull);
      expect(mirror.snapshot.health, TrajectorySnapshotHealth.compromised);
      expect(mirror.snapshot.seededAt, _boot.add(const Duration(minutes: 1)));
    });
  });

  group('the golden equivalence: mirror == cold replay', () {
    /// The full rework storm, then a terminal — the shape the winner rule and
    /// the comparator both have to survive.
    List<TrajectoryRecord> storm() => [
      _started('s-1'),
      const AttemptProcessStarted(
        attemptId: '01J8ATTEMPT000000000000002',
        sessionId: 's-1',
        incarnation: 0,
        pid: 4242,
        pgid: 4242,
      ),
      const AttemptRoundRetired(
        sessionId: 's-1',
        oldRound: 0,
        newRound: 1,
        cause: RoundRetireCause.rework,
      ),
      _started('s-2'),
      const AttemptReworkDeclined(
        sessionId: 's-2',
        round: 0,
        reason: 'operator says no',
      ),
      _terminal(
        's-2',
        outcome: TerminalOutcome.escalated,
        attemptId: '01J8ATTEMPT000000000000003',
      ),
    ];

    test('seed-then-apply == a cold replay of the SAME log', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      final envelopes = _drive(mirror, storm());

      // The cold replay reads the log itself — envelopes carrying their
      // committed `seq`, exactly as `traj replay` would scan them.
      final replayed = foldSessionHeads([
        for (var i = 0; i < envelopes.length; i++)
          TrajectoryEnvelope.fromJson({
            ...envelopes[i].toJson(),
            'seq': i + 1,
            'epoch_seq': i + 1,
          }),
      ]);

      expect(replayed.rows.keys.toSet(), {'s-1', 's-2'});
      for (final entry in replayed.rows.entries) {
        final mirrored = mirror.snapshot.bySessionId(entry.key)!;
        expect(mirrored.round, entry.value.round);
        expect(mirrored.isOpen, entry.value.status == SessionHeadStatus.open);
        expect(mirrored.outcome?.wire, entry.value.outcome?.wire);
        expect(mirrored.held, entry.value.held);
        expect(mirrored.pgid, entry.value.pgid);
        expect(mirrored.lastSeq, entry.value.lastSeq);
        expect(mirrored.startedAt, entry.value.startedAt);
        expect(mirrored.closedAt, entry.value.closedAt);
      }
    });

    test('the storm resolves per the partition at EVERY intermediate state '
        'and never breaches', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      var ordinal = 0;
      for (final record in storm()) {
        ordinal += 1;
        mirror.applyAppended(_envelope(record), seq: ordinal, decoded: record);
        expect(
          mirror.snapshot.byWorkBead('tg-9abc'),
          isNot(isA<SessionHeadCardinalityBreach>()),
          reason:
              'a rework is never a double-mount (after ${record.recordType})',
        );
      }
      // The retired row's `round` equals the round its `#rN` key would name.
      expect(mirror.snapshot.bySessionId('s-1')!.round, 1);
      final winner = mirror.snapshot.byWorkBead('tg-9abc');
      expect((winner as SessionHeadWon).row.sessionId, 's-2');
      expect(winner.fromClosedLadder, isTrue, reason: 's-2 closed escalated');
    });

    test('the reconstructed MARK survives into the view — the suppressor '
        'reads the durable column, never process memory', () {
      final mirror = SessionHeadMirror()
        ..seed(rows: const [], seededAt: _boot, stale: false);
      _drive(mirror, [_started('s-1')]);
      final testimony = _terminal(
        's-1',
        outcome: TerminalOutcome.unknown,
        unknownReason: 'teardown-replay',
      );
      mirror.applyAppended(
        _envelope(testimony, provenance: TrajectoryProvenance.reconstructed),
        seq: 2,
        decoded: testimony,
      );

      final row = mirror.snapshot.bySessionId('s-1')!;
      expect(row.outcome, SessionHeadOutcome.unknown);
      expect(row.terminalProvenance, SessionHeadProvenance.reconstructed);
      expect(row.unknownReason, 'teardown-replay');
      expect(row.isOpen, isFalse);
    });
  });
}
