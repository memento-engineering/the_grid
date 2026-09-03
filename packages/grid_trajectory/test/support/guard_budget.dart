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

/// Ceiling on mean(fold append) / the machine-speed unit.
const double kMaxFoldMeanCostRatio = 4.0;

/// Ceiling on p99(fold append) / the machine-tail unit.
const double kMaxFoldP99TailRatio = 5.0;

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

  /// The MEDIAN interleaved bare round trip, in microseconds.
  final int baselineUnitMicros;

  /// The p99 interleaved bare round trip, in microseconds.
  final int baselineTailMicros;

  /// The runner's bare round-trip throughput.
  double get baselineOpsPerSecond => 1e6 / baselineUnitMicros;

  /// The drain floor this runner must clear, in appends/s.
  double get minimumDrainPerSecond =>
      baselineOpsPerSecond / kMaxFoldMeanCostRatio;

  /// The p99 ceiling this runner must stay under, in milliseconds.
  double get maximumP99Millis =>
      baselineTailMicros * kMaxFoldP99TailRatio / 1000.0;
}
