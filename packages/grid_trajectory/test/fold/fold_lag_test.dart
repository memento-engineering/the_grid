/// The reader LAG rule and the `proj_meta` GENERATION set — the two facts a
/// fold reader consults before it trusts a projection.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);

  group('the lag rule (constraint 6, honest form)', () {
    test('a caught-up fold is never stale', () {
      final lag = FoldLag.from(appliedSeq: 900, maxSeq: 900, now: now);
      expect(lag.records, 0);
      expect(lag.age, Duration.zero);
      expect(lag.isStale, isFalse);
    });

    test('the RECORD bound is the shared §5 reader bound, exclusive at the '
        'edge', () {
      FoldLag behind(int records) =>
          FoldLag.from(appliedSeq: 0, maxSeq: records, now: now);
      expect(behind(staleLagLimit).isStale, isFalse);
      expect(behind(staleLagLimit + 1).isStale, isTrue);
    });

    test('the AGE bound stales a SHORT lag whose oldest record is old', () {
      FoldLag aged(Duration age) => FoldLag.from(
        appliedSeq: 0,
        maxSeq: 1,
        oldestUnappliedAt: now.subtract(age),
        now: now,
      );
      expect(aged(kFoldLagAgeBound).isStale, isFalse);
      expect(
        aged(kFoldLagAgeBound + const Duration(seconds: 1)).isStale,
        isTrue,
      );
    });

    test(
      'a server clock marginally ahead reads as zero age, never negative',
      () {
        final lag = FoldLag.from(
          appliedSeq: 0,
          maxSeq: 1,
          oldestUnappliedAt: now.add(const Duration(seconds: 5)),
          now: now,
        );
        expect(lag.age, Duration.zero);
        expect(lag.isStale, isFalse);
      },
    );

    test('readFoldLag reads the SHARED fold row and skips the age query when '
        'there is nothing behind', () async {
      final db = ScriptedDb()
        ..on(
          'AS max_seq',
          result: const SqlResult(
            rows: [
              {'max_seq': '42', 'applied_seq': '42'},
            ],
          ),
        );
      final lag = await readFoldLag(db, clock: () => now);
      expect(lag.records, 0);
      expect(db.matching('MIN(recorded_at)'), isEmpty);
      // The cursor row is the appender's, NOT a per-projection replay row.
      expect(db.log.single.sql, contains("projection = 'fold'"));
    });

    test(
      'readFoldLag dates the lag from the OLDEST unapplied record',
      () async {
        final db = ScriptedDb()
          ..on(
            'AS max_seq',
            result: const SqlResult(
              rows: [
                {'max_seq': '50', 'applied_seq': '10'},
              ],
            ),
          )
          ..on(
            'MIN(recorded_at)',
            result: const SqlResult(
              rows: [
                {'oldest': '2026-09-01 11:58:00.000000'},
              ],
            ),
          );
        final lag = await readFoldLag(db, clock: () => now);
        expect(lag.records, 40);
        expect(lag.age, const Duration(minutes: 2));
        expect(lag.isStale, isTrue, reason: 'past the 60s age bound');
        expect(db.matching('MIN(recorded_at)').single.params!['applied'], 10);
      },
    );

    test('an empty log folds to zero rather than throwing', () async {
      final db = ScriptedDb();
      final lag = await readFoldLag(db, clock: () => now);
      expect(lag.maxSeq, 0);
      expect(lag.appliedSeq, 0);
      expect(lag.isStale, isFalse);
    });
  });

  group('the generation set (the reseed guard\'s watched triples)', () {
    test('reads EVERY proj_meta row, not just the cursor row', () async {
      final db = ScriptedDb()
        ..on(
          'FROM proj_meta ORDER BY projection',
          result: const SqlResult(
            rows: [
              {
                'projection': 'fold',
                'fold_version': '2',
                'applied_seq': '900',
                'skipped': null,
                'rebuilt_at': '2026-09-01 10:00:00.000000',
              },
              {
                'projection': 'process_identity',
                'fold_version': '1',
                'applied_seq': '880',
                'skipped': '{"worktree.held@v2":1}',
                'rebuilt_at': null,
              },
            ],
          ),
        );
      final generations = await readProjectionGenerations(db);
      expect(generations.map((g) => g.projection), [
        foldCursorProjection,
        processIdentityProjection,
      ]);
      expect(generations.first.generation, (
        'fold',
        2,
        DateTime.utc(2026, 9, 1, 10),
      ));
      expect(
        generations.first.rebuiltAt!.isUtc,
        isTrue,
        reason: 'DATETIME(6) carries no zone; every writer here writes UTC',
      );
      expect(generations.last.rebuiltAt, isNull);
      expect(generations.last.skipped, '{"worktree.held@v2":1}');
    });

    test('a rebuilt_at change is a DIFFERENT generation — that is the whole '
        'signal', () {
      const projection = 'step_cursor';
      final before = ProjectionGeneration(
        projection: projection,
        foldVersion: 1,
        appliedSeq: 10,
        rebuiltAt: DateTime.utc(2026, 9, 1, 10),
      );
      final replayed = ProjectionGeneration(
        projection: projection,
        foldVersion: 1,
        appliedSeq: 10,
        rebuiltAt: DateTime.utc(2026, 9, 1, 11),
      );
      expect(replayed.generation, isNot(before.generation));
      expect(replayed, isNot(before));
    });
  });

  test('parseSqlDateTime6 inverts sqlDateTime6 through UTC', () {
    final value = DateTime.utc(2026, 9, 1, 12, 34, 56, 789, 123);
    expect(parseSqlDateTime6(sqlDateTime6(value)), value);
    expect(parseSqlDateTime6(null), isNull);
    expect(parseSqlDateTime6('  '), isNull);
  });
}
