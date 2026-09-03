/// tg-j1zn — the substation identity, pinned by name at every spelling.
///
/// The word `seat` is reserved for an Agent Seat (decision:
/// agent-seat-and-agent-disc). The trajectory plane's store-ownership column
/// is `substation` in the journal DDL, in P1, in the CHECK name, and on the
/// envelope wire — and the journal's rename ships as a named migration step
/// beside the wave-1 P1 reshape.
library;

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_db.dart';

/// A minimal, valid envelope — [workBeadId] plus [substation] is the pair
/// `ck_substation` governs.
TrajectoryEnvelope _envelope({String? workBeadId, String? substation}) =>
    TrajectoryEnvelope(
      recordId: '01J0000000000000000000000A',
      idemKey: 'a' * 64,
      idemKeyText: 'attempt.note|tg-j1zn',
      family: TrajectoryFamily.attempt,
      recordType: 'attempt.note',
      occurredAt: DateTime.utc(2026, 9, 3),
      recordedAt: DateTime.utc(2026, 9, 3),
      station: 'the_grid',
      authorityId: 'the_grid/1',
      bootEpoch: 1,
      source: 'substation_column_test',
      payload: const {'note': 'pin'},
      workBeadId: workBeadId,
      substation: substation,
    );

void main() {
  group('the DDL names the column `substation`', () {
    test('the journal carries `substation` and `ck_substation`', () {
      final journal = trajectoryTableDdl[2];
      expect(journal, contains('CREATE TABLE IF NOT EXISTS trajectory'));
      expect(
        journal,
        matches(RegExp(r'\n\s*substation\s+VARCHAR\(64\)\s+NULL,')),
      );
      expect(
        journal,
        contains(
          'CONSTRAINT ck_substation CHECK (work_bead_id IS NULL OR '
          'substation IS NOT NULL)',
        ),
      );
      expect(journal, isNot(contains('seat')));
    });

    test('P1 carries `substation`', () {
      expect(projSessionHeadDdl, contains('substation VARCHAR(64) NULL'));
      expect(projSessionHeadDdl, isNot(contains('seat')));
    });

    test('the stage-0 seven-guard set still numbers seven, with '
        'ck_substation in it', () {
      final journal = trajectoryTableDdl[2];
      for (final constraint in const [
        'ck_prov',
        'ck_terminal',
        'ck_unknown',
        'ck_provision',
        'ck_grant',
        'ck_grant_link',
        'ck_substation',
      ]) {
        expect(journal, contains('CONSTRAINT $constraint'));
      }
    });
  });

  group('the envelope wire key is `substation`', () {
    test('toJson emits `substation`, never `seat`', () {
      final json = _envelope(workBeadId: 'tg-j1zn', substation: 'tg').toJson();
      expect(json['substation'], 'tg');
      expect(json.containsKey('seat'), isFalse);
    });

    test('fromJson reads `substation` — a round trip preserves it', () {
      final json = _envelope(workBeadId: 'tg-j1zn', substation: 'tg').toJson();
      expect(TrajectoryEnvelope.fromJson(json).substation, 'tg');
    });

    test('ck_substation refuses a work bead with no substation, LOUDLY and '
        'by the new name', () {
      expect(
        () => _envelope(workBeadId: 'tg-j1zn'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('ck_substation'), contains('substation')),
          ),
        ),
      );
    });
  });

  group('the journal migration (tg-j1zn)', () {
    test('a journal still carrying `seat` needs the rename', () async {
      final stale = ScriptedDb()
        ..on(
          'information_schema.columns',
          result: const SqlResult(
            rows: [
              {'name': 'record_id'},
              {'name': 'SEAT'},
            ],
          ),
        );
      expect(
        await journalNeedsSubstationRename(stale),
        isTrue,
        reason: 'servers case column names differently; the check does not',
      );
      expect(stale.log.single.sql, journalColumnsSql);
      expect(
        stale.log.single.sql,
        contains("table_name = 'trajectory'"),
        reason: 'the journal probe is distinguishable from P1\'s by text',
      );
    });

    test('a renamed journal, and an absent one, need nothing', () async {
      final current = ScriptedDb()
        ..on(
          'information_schema.columns',
          result: const SqlResult(
            rows: [
              {'name': 'substation'},
            ],
          ),
        );
      expect(await journalNeedsSubstationRename(current), isFalse);
      expect(await journalNeedsSubstationRename(ScriptedDb()), isFalse);
    });

    test('the rename is an in-place ALTER — never a DROP, never in a '
        'transaction', () async {
      final db = ScriptedDb();
      await renameJournalSubstationColumn(db);
      expect(db.log.map((call) => call.sql), [
        'ALTER TABLE trajectory DROP CHECK ck_seat',
        'ALTER TABLE trajectory RENAME COLUMN seat TO substation',
        'ALTER TABLE trajectory ADD CONSTRAINT ck_substation '
            'CHECK (work_bead_id IS NULL OR substation IS NOT NULL)',
      ]);
      expect(db.matching('DROP TABLE'), isEmpty);
      expect(db.matching('START TRANSACTION'), isEmpty);
    });
  });
}
