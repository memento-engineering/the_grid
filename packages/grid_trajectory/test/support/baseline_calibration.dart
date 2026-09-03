/// The machine-speed probe behind the W6 guard's runner-relative budget.
library;

import 'package:grid_trajectory/grid_trajectory.dart';

/// The scratch table the probe writes; never part of the §4 schema.
const String kCalibrationTable = 'traj_calibration';

/// Creates the scratch calibration table. Idempotent.
Future<void> createCalibrationTable(TrajectoryDb db) async {
  await db.execute(
    'CREATE TABLE IF NOT EXISTS $kCalibrationTable ('
    'id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, '
    'payload VARCHAR(64) NOT NULL)',
  );
}

/// Times ONE bare INSERT + SELECT round trip and returns its wall-clock
/// cost in microseconds.
Future<int> timeBaselineRoundTrip(
  TrajectoryDb db, {
  required String path,
}) async {
  final trip = Stopwatch()..start();
  await db.execute(
    'INSERT INTO $kCalibrationTable (payload) VALUES (:payload)',
    {'payload': path},
  );
  await db.execute(
    'SELECT id FROM $kCalibrationTable ORDER BY id DESC LIMIT 1',
  );
  trip.stop();
  return trip.elapsedMicroseconds;
}
