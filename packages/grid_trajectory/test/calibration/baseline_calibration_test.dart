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

  test('runBaselineProbe issues one INSERT + SELECT pair per trip', () async {
    final db = ScriptedDb();
    final probe = await runBaselineProbe(db, label: 'w6-probe0', trips: 3);
    expect(probe.trips, 3);
    expect(db.log, hasLength(6));
    expect(db.log.first.params, {'payload': 'w6-probe0/0'});
    expect(db.log[4].params, {'payload': 'w6-probe0/2'});
  });

  test('BaselineProbe reports its central and slowest trip', () {
    final probe = BaselineProbe([9000, 1000, 5000, 3000, 7000]);
    expect(probe.medianMicros, 5000);
    expect(probe.slowestMicros, 9000);
  });

  test('an empty probe is refused LOUDLY', () {
    expect(() => BaselineProbe(const []), throwsA(isA<ArgumentError>()));
  });

  test('BaselineCalibration takes the median of five on BOTH sides', () {
    final calibration = BaselineCalibration([
      BaselineProbe([1000, 1000, 40000]),
      BaselineProbe([3000, 3000, 90000]),
      BaselineProbe([2000, 2000, 60000]),
      BaselineProbe([5000, 5000, 20000]),
      BaselineProbe([4000, 4000, 70000]),
    ]);
    expect(calibration.unitMicros, 3000);
    expect(calibration.tailMicros, 60000);
  });

  test('one stalled probe cannot move either unit', () {
    final steady = [
      for (var i = 0; i < 4; i++) BaselineProbe([2000, 2000, 8000]),
    ];
    final calibration = BaselineCalibration([
      ...steady,
      BaselineProbe([900000, 900000, 900000]),
    ]);
    expect(calibration.unitMicros, 2000);
    expect(calibration.tailMicros, 8000);
  });

  test('any probe count other than five is refused LOUDLY', () {
    final probe = BaselineProbe(const [1000]);
    expect(
      () => BaselineCalibration([probe, probe, probe, probe]),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => BaselineCalibration([probe, probe, probe, probe, probe, probe]),
      throwsA(isA<ArgumentError>()),
    );
  });
}
