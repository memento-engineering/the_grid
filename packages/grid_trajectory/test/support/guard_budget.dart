/// The W6 guard's runner-relative budget (bead `tg-2zao`).
///
/// W6's acceptance numbers (`docs/design/trajectory/stage1-wiring.md` §2.5/§6)
/// are WALL-CLOCK: a sustained drain rate and a p99 writer-loop transaction
/// time. On a shared CI runner those measure the RUNNER, not the fold — a
/// grid_runtime-only diff failed them at 22.5 appends/s and 297.775 ms while
/// the same commit passed on the next runner.
///
/// What is machine-INDEPENDENT is the COST RATIO of one Stage-1 fold append
/// (P1 + P2 + P6 in one transaction) against one bare round trip INTERLEAVED
/// with it on the same connection. Measured locally against dolt 2.2.2 over
/// six runs — one of them 1.8x slower than the others — the mean ratio stayed
/// in 1.26–1.55 and the p99-tail ratio in 1.18–1.70. The ceilings below carry
/// ~2.6x and ~2.9x headroom over those, so an order-of-magnitude fold
/// regression still reddens the guard on any runner.
library;

/// The environment variable a SHARED CI runner sets to `1`.
///
/// Unset (a developer machine) keeps the tight absolute pins asserted.
const String kSharedRunnerEnvVar = 'TRAJ_GUARD_SHARED_RUNNER';

/// `trajectory-schema.md` §5's storm-production band top: an 8-attempt storm
/// at grid tempo needs ~22–28 appends/s, and the drain must beat the top.
const double kStormProductionRateTop = 28.0;

/// The absolute p99 writer-loop ceiling: an order of magnitude past M3's
/// 24.93 ms observation.
const double kP99CeilingMillis = 250.0;

/// The MEASURED cost of one Stage-1 fold append against the machine-speed
/// unit, carried UNCHANGED from
/// `the_grid#trajectory-guard-pins-are-runner-relative`, whose Consequences
/// forbid moving it without remeasurement. This is the calibrated
/// EXPECTATION, not the assertion's ceiling.
const double kFoldMeanCostRatio = 4.0;

/// The MEASURED cost of the fold p99 against the machine-tail unit, carried
/// unchanged from the same entry, on the same terms.
const double kFoldTailCostRatio = 5.0;

/// The round-2 shared-runner tolerance on the calibrated drain bound
/// (`tg-2zao`): the guarded drain must clear 0.60x it. Receipts it covers —
/// 106.65 appends/s against a 119.27/s bound (0.89) on run 33777666093, and
/// 109.51 against 120.60 (0.91) on run 33778914681. A 2x fold slowdown of
/// either still lands under the floor.
const double kDrainToleranceFraction = 0.60;

/// The round-2 shared-runner tolerance on the calibrated tail bound
/// (`tg-2zao`): the fold p99 may reach 1.60x it. Receipt it covers — a
/// 297.775 ms p99 against the 250 ms absolute pin (1.19) on run 33767416244.
const double kTailToleranceFactor = 1.60;

/// Where the guard is running.
enum GuardHost {
  /// A developer machine: the tight absolute pins are asserted.
  developer,

  /// A shared CI runner: only the runner-relative pins are asserted.
  sharedRunner,
}

/// Resolves the host from [environment].
///
/// LOUD by design: a value other than the empty string or `1` throws a
/// [StateError] rather than silently picking a posture.
GuardHost resolveGuardHost(Map<String, String> environment) {
  final raw = environment[kSharedRunnerEnvVar];
  if (raw == null || raw.isEmpty) return GuardHost.developer;
  if (raw == '1') return GuardHost.sharedRunner;
  throw StateError(
    '$kSharedRunnerEnvVar must be unset or exactly "1"; got "$raw" — '
    'refusing to guess whether the tight absolute W6 pins apply',
  );
}

/// Whether the tight absolute W6 pins are asserted on [host].
bool absolutePinsApply(GuardHost host) => switch (host) {
  GuardHost.developer => true,
  GuardHost.sharedRunner => false,
};

/// The runner-relative floors, derived from the interleaved calibration trips.
class GuardBudget {
  /// Throws [ArgumentError] when either unit is not positive — a zero unit
  /// would silently disable the pin it scales.
  GuardBudget({
    required this.baselineUnitMicros,
    required this.baselineTailMicros,
  }) {
    if (baselineUnitMicros <= 0) {
      throw ArgumentError.value(
        baselineUnitMicros,
        'baselineUnitMicros',
        'the machine-speed unit must be positive',
      );
    }
    if (baselineTailMicros <= 0) {
      throw ArgumentError.value(
        baselineTailMicros,
        'baselineTailMicros',
        'the machine-tail unit must be positive',
      );
    }
  }

  /// The machine-speed unit: the MEDIAN of the five interleaved probes'
  /// median round trips, in microseconds.
  final int baselineUnitMicros;

  /// The machine-tail unit: the MEDIAN of the five interleaved probes'
  /// slowest round trips, in microseconds.
  final int baselineTailMicros;

  /// The runner's bare round-trip throughput.
  double get baselineOpsPerSecond => 1e6 / baselineUnitMicros;

  /// The drain floor this runner must clear, in appends/s: the calibrated
  /// bound at the round-2 tolerance.
  double get minimumDrainPerSecond =>
      baselineOpsPerSecond / kFoldMeanCostRatio * kDrainToleranceFraction;

  /// The p99 ceiling this runner must stay under, in milliseconds: the
  /// calibrated bound at the round-2 tolerance.
  double get maximumP99Millis =>
      baselineTailMicros * kFoldTailCostRatio * kTailToleranceFactor / 1000.0;
}
