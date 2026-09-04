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
/// in 1.26–1.55 and the p99-tail ratio in 1.18–1.70. The calibrated ratios
/// below carry ~2.6x and ~2.9x headroom over those; the shared-runner
/// tolerances (`tg-shry`) widen the ASSERTED ceilings to 13.33x and 12.5x a
/// bare round trip, so against the slowest measured base a fold regression of
/// ~8.6x or more still reddens the guard on a shared runner, while ordinary
/// runner swing no longer does.
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

/// The shared-runner tolerance on the calibrated drain bound (`tg-shry`): the
/// guarded drain must clear 0.30x it.
///
/// `tg-2zao`'s 0.60 was read off ratios measured against the ROUND-1 baseline
/// — one bare probe per append: 22.5 against 28 (0.80), 106.65 against 119.27
/// (0.89) — and then applied to a DIFFERENT distribution, the median of five
/// bare probes, whose ratio to the sustained drain is 0.60. The floor landed
/// ON the observation: run 33818055118 (PR #297, rerun 23:37Z 2026-09-03)
/// failed at 120.69804320618569 against a 120.77294685990339 floor, a 0.5996
/// drain/bound ratio, and PRs #296 and #299 failed the same job. 0.30 is half
/// that observed ratio — a 2x fold slowdown of that receipt still lands under
/// the floor, and runner swing no longer does.
const double kDrainToleranceFraction = 0.30;

/// The shared-runner tolerance on the calibrated tail bound (`tg-shry`): the
/// fold p99 may reach 2.50x it — double-plus the observed shared-runner
/// ratio, on the same terms as [kDrainToleranceFraction]. Receipt it covers —
/// a 297.775 ms p99 against the 250 ms absolute pin (1.19) on run
/// 33767416244.
const double kTailToleranceFactor = 2.50;

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

  /// The calibrated throughput BOUND, in appends/s: what the fold is expected
  /// to sustain at [kFoldMeanCostRatio]. [minimumDrainPerSecond] is this
  /// bound at [kDrainToleranceFraction], so drain-over-this-bound is the ONLY
  /// ratio a re-tune of that tolerance may be measured against.
  double get calibratedDrainBound => baselineOpsPerSecond / kFoldMeanCostRatio;

  /// The calibrated latency BOUND, in milliseconds: what the fold p99 is
  /// expected to hold at [kFoldTailCostRatio]. [maximumP99Millis] is this
  /// bound at [kTailToleranceFactor], on the same terms.
  double get calibratedP99BoundMillis =>
      baselineTailMicros * kFoldTailCostRatio / 1000.0;

  /// The drain floor this runner must clear, in appends/s: the calibrated
  /// bound at the `tg-shry` shared-runner tolerance.
  double get minimumDrainPerSecond =>
      baselineOpsPerSecond / kFoldMeanCostRatio * kDrainToleranceFraction;

  /// The p99 ceiling this runner must stay under, in milliseconds: the
  /// calibrated bound at the `tg-shry` shared-runner tolerance.
  double get maximumP99Millis =>
      baselineTailMicros * kFoldTailCostRatio * kTailToleranceFactor / 1000.0;
}

/// The W6 drain-leg failure message: expected, actual, and the OBSERVED
/// RATIOS the band must be re-tuned against.
///
/// `drain/probe-rate` is the raw machine-independent reading — its reciprocal
/// is the fold's cost in bare round trips, the number [kFoldMeanCostRatio] is
/// calibrated against. `drain/calibrated-bound` is the number
/// [kDrainToleranceFraction] is literally set against; `tg-2zao` set 0.60 from
/// a ratio measured on a different baseline, which is why both are printed.
String drainFailureMessage({
  required GuardBudget budget,
  required double drainRate,
}) =>
    'W6 drain leg FAILED. expected: greater than '
    '${budget.minimumDrainPerSecond.toStringAsFixed(3)} appends/s (the '
    '${budget.calibratedDrainBound.toStringAsFixed(3)}/s calibrated bound at '
    'the ${kDrainToleranceFraction}x tg-shry shared-runner tolerance); '
    'actual: ${drainRate.toStringAsFixed(3)} appends/s. OBSERVED RATIOS: '
    'drain/probe-rate '
    '${(drainRate / budget.baselineOpsPerSecond).toStringAsFixed(4)} (bare '
    'probe rate ${budget.baselineOpsPerSecond.toStringAsFixed(1)} ops/s, '
    'machine-speed unit '
    '${(budget.baselineUnitMicros / 1000).toStringAsFixed(3)} ms), '
    'drain/calibrated-bound '
    '${(drainRate / budget.calibratedDrainBound).toStringAsFixed(4)} — '
    're-tune $kDrainToleranceFraction against THIS ratio, never against one '
    'measured on another baseline.';

/// The W6 tail-leg failure message, on the same terms as
/// [drainFailureMessage]: `p99/probe-latency` against the machine-tail unit,
/// `p99/calibrated-bound` against the number [kTailToleranceFactor] is set
/// against.
String tailFailureMessage({
  required GuardBudget budget,
  required double p99Millis,
}) =>
    'W6 tail leg FAILED. expected: less than '
    '${budget.maximumP99Millis.toStringAsFixed(3)} ms (the '
    '${budget.calibratedP99BoundMillis.toStringAsFixed(3)} ms calibrated '
    'bound at the ${kTailToleranceFactor}x tg-shry shared-runner tolerance); '
    'actual: ${p99Millis.toStringAsFixed(3)} ms. OBSERVED RATIOS: '
    'p99/probe-latency '
    '${(p99Millis * 1000 / budget.baselineTailMicros).toStringAsFixed(4)} '
    '(machine-tail unit '
    '${(budget.baselineTailMicros / 1000).toStringAsFixed(3)} ms), '
    'p99/calibrated-bound '
    '${(p99Millis / budget.calibratedP99BoundMillis).toStringAsFixed(4)} — '
    're-tune $kTailToleranceFactor against THIS ratio, never against one '
    'measured on another baseline.';
