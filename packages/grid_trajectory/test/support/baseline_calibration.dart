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

/// How many bare round trips ONE interleaved probe times.
///
/// `kProbeCount * kProbeTrips == 520` — exactly the number of round trips the
/// per-append calibration already spent (40 sessions x 13 records), so the
/// re-shaped sampling costs the hermetic database nothing new.
const int kProbeTrips = 104;

/// How many probes a calibrated run interleaves (`tg-2zao` round 2): one
/// before the storm, three between its quarters, one after.
const int kProbeCount = 5;

/// One interleaved calibration probe: [kProbeTrips] back-to-back bare round
/// trips, held as their measured wall-clock costs.
class BaselineProbe {
  /// Throws [ArgumentError] on an empty sample: a probe with no trip has
  /// neither a median nor a slowest trip, and would silently disable the pin
  /// it scales.
  BaselineProbe(List<int> tripMicros)
    : _sorted = (List<int>.of(tripMicros)..sort()) {
    if (_sorted.isEmpty) {
      throw ArgumentError.value(
        tripMicros,
        'tripMicros',
        'a calibration probe must carry at least one round trip',
      );
    }
  }

  final List<int> _sorted;

  /// How many round trips this probe timed.
  int get trips => _sorted.length;

  /// This probe's CENTRAL round trip — its machine-speed sample.
  int get medianMicros => _sorted[(_sorted.length - 1) ~/ 2];

  /// This probe's SLOWEST round trip — its machine-tail sample. The tail is
  /// sampled PER PROBE rather than pooled so that one stalled window moves
  /// one sample, not the aggregate.
  int get slowestMicros => _sorted.last;
}

/// Times one probe: [trips] back-to-back bare round trips tagged with [label].
Future<BaselineProbe> runBaselineProbe(
  TrajectoryDb db, {
  required String label,
  int trips = kProbeTrips,
}) async {
  final micros = <int>[];
  for (var trip = 0; trip < trips; trip++) {
    micros.add(await timeBaselineRoundTrip(db, path: '$label/$trip'));
  }
  return BaselineProbe(micros);
}

/// A run's interleaved probes, aggregated by MEDIAN on BOTH sides
/// (`tg-2zao` round 2).
class BaselineCalibration {
  /// Throws [ArgumentError] unless exactly [kProbeCount] probes are supplied:
  /// the band is DEFINED as the median of five, and a short or even list has
  /// no unique median, so it would quietly widen or narrow both pins.
  BaselineCalibration(this.probes) {
    if (probes.length != kProbeCount) {
      throw ArgumentError.value(
        probes.length,
        'probes',
        'the calibration is the median of exactly $kProbeCount probes',
      );
    }
  }

  /// The five interleaved probes, in the order they ran.
  final List<BaselineProbe> probes;

  /// The machine-speed unit: the median of the probes' median trips.
  int get unitMicros => _median(probes.map((probe) => probe.medianMicros));

  /// The machine-tail unit: the median of the probes' slowest trips.
  int get tailMicros => _median(probes.map((probe) => probe.slowestMicros));

  static int _median(Iterable<int> values) {
    final sorted = values.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }
}
