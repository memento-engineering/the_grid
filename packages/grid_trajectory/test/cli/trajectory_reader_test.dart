/// The read seam: the one subject query, and row → envelope decoding.
library;

import 'dart:convert';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

Map<String, String?> _row({
  String recordType = 'attempt.session.started',
  Map<String, Object?> payload = const {'rig': 'operator', 'model': 'molecule'},
  Map<String, String?> overrides = const {},
}) => {
  'seq': '12',
  'boot_epoch': '3',
  'epoch_seq': '7',
  'record_id': '01J8RECORD000000000000001',
  'idem_key': 'f' * 64,
  'idem_key_text': 'session-started:tranquility-5xk',
  'family': 'attempt',
  'record_type': recordType,
  'type_version': '1',
  'occurred_at': '2026-08-31 09:14:02.123456',
  'recorded_at': '2026-08-31 09:14:02.456789',
  'station': 'lunar',
  'seat': 'the_grid',
  'authority_id': 'lunar/3',
  'provenance': 'observed',
  'source': 'test',
  'work_bead_id': 'tg-9abc',
  'session_id': 'tranquility-5xk',
  'grant_id': '01J8GRANT00000000000000001',
  'round': '2',
  'payload': jsonEncode(payload),
  ...overrides,
};

void main() {
  group('subject query', () {
    test(
      'matches bead, session, and attempt on one bound id, seq-ordered',
      () async {
        final db = ScriptedDb();
        await SqlTrajectoryLogReader(db).rowsForSubject('tg-9abc', limit: 25);
        final call = db.log.single;
        expect(call.sql, contains('work_bead_id = :id'));
        expect(call.sql, contains('session_id = :id'));
        expect(call.sql, contains('attempt_id = :id'));
        expect(call.sql, contains('ORDER BY seq'));
        expect(call.params, {'id': 'tg-9abc', 'limit': 25});
      },
    );

    test('the reader never writes', () async {
      final db = ScriptedDb();
      final reader = SqlTrajectoryLogReader(db);
      await reader.rowsForSubject('tg-9abc');
      await reader.sessions();
      await reader.foldStaleness();
      for (final call in db.log) {
        expect(call.sql, startsWith('SELECT '));
      }
    });

    test(
      'foldStaleness reads the log head against the fold frontier',
      () async {
        final db = ScriptedDb()
          ..on(
            'AS max_seq',
            result: const SqlResult(
              rows: [
                {'max_seq': '900', 'applied_seq': '300'},
              ],
            ),
          );
        final staleness = await SqlTrajectoryLogReader(db).foldStaleness();
        expect(staleness!.maxSeq, 900);
        expect(staleness.appliedSeq, 300);
        expect(staleness.lag, 600);
      },
    );

    test('foldStaleness is null on an empty log', () async {
      final db = ScriptedDb()
        ..on(
          'AS max_seq',
          result: const SqlResult(
            rows: [
              {'max_seq': null, 'applied_seq': null},
            ],
          ),
        );
      expect(await SqlTrajectoryLogReader(db).foldStaleness(), isNull);
    });

    test('sessions are distinct and ordered by first appearance', () async {
      final db = ScriptedDb()
        ..on(
          'GROUP BY session_id',
          result: const SqlResult(
            rows: [
              {'session_id': 'tranquility-5xk', 'first_seq': '1'},
              {'session_id': 'tg-b', 'first_seq': '4'},
            ],
          ),
        );
      expect(await SqlTrajectoryLogReader(db).sessions(), [
        'tranquility-5xk',
        'tg-b',
      ]);
      expect(db.log.single.sql, contains('ORDER BY first_seq'));
    });

    test('closing the reader closes its session', () async {
      final db = ScriptedDb();
      await SqlTrajectoryLogReader(db).close();
      expect(db.closed, isTrue);
    });
  });

  group('envelopeFromRow', () {
    test('types the numeric columns and decodes the payload', () {
      final envelope = envelopeFromRow(_row());
      expect(envelope.seq, 12);
      expect(envelope.bootEpoch, 3);
      expect(envelope.epochSeq, 7);
      expect(envelope.round, 2);
      expect(envelope.typeVersion, 1);
      expect(envelope.family, TrajectoryFamily.attempt);
      expect(envelope.payload, {'rig': 'operator', 'model': 'molecule'});
    });

    test('re-reads DATETIME(6) columns as the UTC the appender wrote', () {
      final envelope = envelopeFromRow(_row());
      expect(envelope.occurredAt.isUtc, isTrue);
      expect(
        envelope.occurredAt,
        DateTime.utc(2026, 8, 31, 9, 14, 2, 123, 456),
      );
    });

    test('a decoded row round-trips through the codec', () {
      final record = TrajectoryCodec.decode(envelopeFromRow(_row()));
      expect(record, isA<AttemptSessionStarted>());
      expect((record as AttemptSessionStarted).rig, 'operator');
    });

    test('an unregistered type decodes opaque rather than throwing', () {
      final record = TrajectoryCodec.decode(
        envelopeFromRow(
          _row(overrides: const {'record_type': 'attempt.future.thing'}),
        ),
      );
      expect(record, isA<OpaqueRecord>());
    });
  });
}
