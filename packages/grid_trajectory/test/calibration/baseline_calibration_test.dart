import 'package:test/test.dart';

import '../support/baseline_calibration.dart';
import '../support/scripted_db.dart';

void main() {
  test('createCalibrationTable issues one idempotent CREATE', () async {
    final db = ScriptedDb();
    await createCalibrationTable(db);
    expect(db.log, hasLength(1));
    expect(
      db.log.single.sql,
      contains('CREATE TABLE IF NOT EXISTS $kCalibrationTable'),
    );
  });

  test('timeBaselineRoundTrip issues INSERT then SELECT, tagged', () async {
    final db = ScriptedDb();
    final micros = await timeBaselineRoundTrip(db, path: 'sess/7');
    expect(micros, greaterThanOrEqualTo(0));
    expect(db.log, hasLength(2));
    expect(db.log.first.sql, startsWith('INSERT INTO $kCalibrationTable'));
    expect(db.log.first.params, {'payload': 'sess/7'});
    expect(db.log.last.sql, startsWith('SELECT id FROM $kCalibrationTable'));
  });
}
