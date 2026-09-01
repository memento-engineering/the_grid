/// The trajectory harness's config surface (stage1-wiring §1.3) — how a
/// station arms, or declines to arm, the trajectory beside its legacy stores.
///
/// The parameter is a the_grid value; the flag surface and banner that feed it
/// (`--trajectory` / `--no-trajectory` on `up`) are space_station edits
/// (stage1-wiring §1.1) — a runner constructs one of these and hands it to
/// `assembleStationWork`.
library;

import 'package:grid_engine/grid_engine.dart' show DualReadMode;
import 'package:grid_runtime/grid_runtime.dart'
    show kDefaultLivenessThreshold, kDefaultPulseCoalesce;
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:meta/meta.dart';

/// §1.3's arming mode. Whatever the mode, a trajectory failure NEVER blocks
/// the boot — the mode only decides whether the harness tries, and how loud a
/// degradation is.
enum TrajectoryConfigMode {
  /// No connection, no claim; the harness is a silent no-op. A station can
  /// always arm without the trajectory.
  disabled,

  /// Enabled iff the provisioning artifact exists
  /// (`.grid/trajectory/trajectory.secret`). An unprovisioned home boots
  /// legacy-only with a one-line notice, not a warning storm.
  auto,

  /// A failed connect/claim still never blocks the boot, but the degradation
  /// is loud: `/status` shows `trajectory: DEGRADED` and the banner warns.
  required,
}

/// The gc cadence (stage1-wiring §1.2 / M2): `CALL DOLT_GC()` every 5 minutes
/// caps the working set; online, no quiesced window, never bd's proxy.
const Duration kDefaultTrajectoryGcInterval = Duration(minutes: 5);

/// §2.5's append-queue bound: past it an incoming append is dropped and
/// counted, never blocked on.
const int kDefaultTrajectoryQueueBound = 4096;

/// The bound on the clean-down drain (r2 major 9, hardened): "trajectory
/// shutdown NEVER blocks sources shutdown" covers hangs as well as throws — a
/// dead/half-open dolt socket can wedge the drain's SQL awaits forever, and an
/// unbounded `await` there would hold `down` hostage. On expiry the remainder
/// is counted + flared and shutdown proceeds to dispose; the successor boot's
/// shadow-diff attributes the loss as the named non-atomic class.
const Duration kDefaultShutdownDrainTimeout = Duration(seconds: 30);

/// The one parameter `assembleStationWork` gains at Stage 1 (§1.3).
@immutable
final class TrajectoryConfig {
  const TrajectoryConfig({
    this.mode = TrajectoryConfigMode.auto,
    this.tickInterval = kDefaultTickInterval,
    this.gcInterval = kDefaultTrajectoryGcInterval,
    this.commitCadence = const Duration(seconds: 30),
    this.queueBound = kDefaultTrajectoryQueueBound,
    this.livenessThreshold = kDefaultLivenessThreshold,
    this.pulseCoalesce = kDefaultPulseCoalesce,
    this.shutdownDrainTimeout = kDefaultShutdownDrainTimeout,
    this.dualRead = DualReadMode.observe,
  });

  final TrajectoryConfigMode mode;

  /// THE DUAL-READ POSTURE (cut-wiring C2/C3), stated per posture so the
  /// rollback claim is honest about WRITES as well as decisions.
  ///
  /// [DualReadMode.off] — THE ROLLBACK. Byte-identical to pre-cut mainline:
  /// no comparator pass on either axis or in the restart reconciler, no mirror
  /// subscriptions on the join bridge (so no extra `notifier.push` and no new
  /// mount-frontier evaluation cadence), and NONE of the new observer appends.
  ///
  /// [DualReadMode.observe] — wave 1's default and C2's whole scope, and the
  /// posture the soak runs in. DECISIONS STAY LEGACY, but this is NOT a
  /// read-only posture and must not be described as one. Armed here:
  ///   * the comparator on both axes, its flares, and the durable
  ///     `dual-read-round-summary` note per session terminal + one per boot;
  ///   * the `terminal-reconcile` HEAL append — reconstructed testimony for a
  ///     head whose terminal record dropped;
  ///   * the restart reconciler's teardown-replay observer append;
  ///   * the P1/P2 mirror subscriptions, which re-join and push on every
  ///     append that yields a delta.
  /// The first two permanently mark `proj_session_head.terminal_provenance`
  /// as `reconstructed`, which excludes that head from settlement until an
  /// observed terminal settles it. That is the designed C2 scope — it is what
  /// keeps a replayed teardown from leaving an unhealable open head — but it
  /// is a change to the LOG, so `observe` is not the rollback; `off` is.
  ///
  /// [DualReadMode.primary] — C3's flip, where the certified overlay is
  /// actually served. The default stays `observe` even in C3's PR, and the
  /// flip is a separable one-line commit attached to C2's gate evidence.
  ///
  /// Rollback is this one line at any posture, and it is instant — wave 1
  /// retires nothing, so legacy stays fully written and authoritative
  /// underneath whatever this says.
  ///
  /// **OPERATOR RUNBOOK — arming wave 1 on an EXISTING grid home.** The cut
  /// widened `proj_session_head`, and the migration is a named quiesced step,
  /// never a boot-time auto-migrate. On a home provisioned before this cut the
  /// harness REFUSES the live arm (mode `degraded`, cause naming the missing
  /// columns) rather than dropping every terminal append on an unknown column.
  /// The fix, with the station DOWN: `traj replay` — it reshapes the
  /// projection and rebuilds it from the log, stamping the bumped
  /// `fold_version`. Then arm normally. A fresh home needs none of this: the
  /// schema bootstrap creates the cut shape.
  final DualReadMode dualRead;

  /// The service tick's interval (§1.2 step 2; Stage-0 default 30 s).
  final Duration tickInterval;

  /// The `CALL DOLT_GC()` cadence the harness owns (§1.2 / M2).
  final Duration gcInterval;

  /// The appender's dolt-commit cadence (Stage-0 default; the hard 10 s
  /// minimum interval and the 512-row threshold stay appender-owned).
  final Duration commitCadence;

  /// The bounded append queue's capacity (§2.5).
  final int queueBound;

  /// How stale a subject's last beat must be before the tick's liveness
  /// detector calls it lost (§2.4 obligation 3). The unknown rule is NOT a
  /// knob: no beat observed under the current epoch always reads `unknown`.
  final Duration livenessThreshold;

  /// The per-subject beat coalescing window (schema §4: `traj_pulse` is
  /// `≥30s per subject`).
  final Duration pulseCoalesce;

  /// The bound on shutdown's drain-to-fixpoint (and each subsequent guarded
  /// teardown step) — see [kDefaultShutdownDrainTimeout].
  final Duration shutdownDrainTimeout;

  /// The same config with [mode] forced to [TrajectoryConfigMode.disabled] —
  /// how dry-run forces the no-write posture (§1.3: a dry arm must not claim
  /// an epoch or write anything).
  TrajectoryConfig get asDisabled => TrajectoryConfig(
    mode: TrajectoryConfigMode.disabled,
    tickInterval: tickInterval,
    gcInterval: gcInterval,
    commitCadence: commitCadence,
    queueBound: queueBound,
    livenessThreshold: livenessThreshold,
    pulseCoalesce: pulseCoalesce,
    shutdownDrainTimeout: shutdownDrainTimeout,
    dualRead: dualRead,
  );
}
