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

/// The station-wide trajectory write/read discipline.
///
/// [shadow] preserves the pre-cut posture selected by [TrajectoryConfig.mode]
/// and [TrajectoryConfig.dualRead]. [cut] is the single cut lever: it resolves
/// those fields to [TrajectoryConfigMode.required] and [DualReadMode.primary]
/// so no caller can observe a cut config with a weaker posture.
enum TrajectoryDiscipline {
  /// Legacy writes remain authoritative while trajectory evidence shadows
  /// them.
  shadow,

  /// The station has crossed the cut and requires the trajectory-primary
  /// posture.
  cut,
}

/// A cut boot whose explicitly requested posture contradicts the cut.
///
/// This is a boot refusal rather than a trajectory-harness failure: harness
/// failures remain non-fatal, while allowing a cut station to boot with a
/// retired carrier would violate the cut's single-lever invariant.
@immutable
final class CutPostureRefused implements Exception {
  const CutPostureRefused._({
    required this.requestedMode,
    required this.resolvedMode,
    required this.requestedDualRead,
    required this.resolvedDualRead,
  });

  /// The caller's explicit mode request, or null when it was omitted.
  final TrajectoryConfigMode? requestedMode;

  /// The mode implied by the cut.
  final TrajectoryConfigMode resolvedMode;

  /// The caller's explicit dual-read request, or null when it was omitted.
  final DualReadMode? requestedDualRead;

  /// The dual-read posture implied by the cut.
  final DualReadMode resolvedDualRead;

  @override
  String toString() {
    final disagreements = <String>[
      if (requestedDualRead != null && requestedDualRead != resolvedDualRead)
        'requested dualRead=${requestedDualRead!.name}, '
            'resolved dualRead=${resolvedDualRead.name}',
      if (requestedMode != null && requestedMode != resolvedMode)
        'requested mode=${requestedMode!.name}, '
            'resolved mode=${resolvedMode.name}',
    ];
    return 'CutPostureRefused(${disagreements.join('; ')})';
  }
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
    this.discipline = TrajectoryDiscipline.shadow,
    TrajectoryConfigMode? mode,
    this.tickInterval = kDefaultTickInterval,
    this.obligationQueryExtensions = const <ObligationQuery>[],
    this.gcInterval = kDefaultTrajectoryGcInterval,
    this.commitCadence = const Duration(seconds: 30),
    this.queueBound = kDefaultTrajectoryQueueBound,
    this.livenessThreshold = kDefaultLivenessThreshold,
    this.pulseCoalesce = kDefaultPulseCoalesce,
    this.shutdownDrainTimeout = kDefaultShutdownDrainTimeout,
    DualReadMode? dualRead,
    this.soakWindowEpoch = 0,
    this.reconcileLedgerCloses = true,
  }) : assert(soakWindowEpoch >= 0),
       _requestedMode = mode,
       _requestedDualRead = dualRead,
       mode = discipline == TrajectoryDiscipline.cut
           ? TrajectoryConfigMode.required
           : mode ?? TrajectoryConfigMode.auto,
       dualRead = discipline == TrajectoryDiscipline.cut
           ? DualReadMode.primary
           : dualRead ?? DualReadMode.off;

  TrajectoryConfig._disabledFrom(TrajectoryConfig source)
    : discipline = source.discipline,
      mode = TrajectoryConfigMode.disabled,
      _requestedMode = source._requestedMode,
      tickInterval = source.tickInterval,
      obligationQueryExtensions = source.obligationQueryExtensions,
      gcInterval = source.gcInterval,
      commitCadence = source.commitCadence,
      queueBound = source.queueBound,
      livenessThreshold = source.livenessThreshold,
      pulseCoalesce = source.pulseCoalesce,
      shutdownDrainTimeout = source.shutdownDrainTimeout,
      dualRead = source.dualRead,
      _requestedDualRead = source._requestedDualRead,
      soakWindowEpoch = source.soakWindowEpoch,
      reconcileLedgerCloses = source.reconcileLedgerCloses;

  TrajectoryConfig._withAppendedObligationQueries(
    TrajectoryConfig source,
    Iterable<ObligationQuery> extensions,
  ) : discipline = source.discipline,
      mode = source.mode,
      _requestedMode = source._requestedMode,
      tickInterval = source.tickInterval,
      obligationQueryExtensions = List<ObligationQuery>.unmodifiable(
        <ObligationQuery>[...source.obligationQueryExtensions, ...extensions],
      ),
      gcInterval = source.gcInterval,
      commitCadence = source.commitCadence,
      queueBound = source.queueBound,
      livenessThreshold = source.livenessThreshold,
      pulseCoalesce = source.pulseCoalesce,
      shutdownDrainTimeout = source.shutdownDrainTimeout,
      dualRead = source.dualRead,
      _requestedDualRead = source._requestedDualRead,
      soakWindowEpoch = source.soakWindowEpoch,
      reconcileLedgerCloses = source.reconcileLedgerCloses;

  /// The single trajectory cut lever.
  final TrajectoryDiscipline discipline;

  final TrajectoryConfigMode mode;

  final TrajectoryConfigMode? _requestedMode;

  /// THE DUAL-READ POSTURE (cut-wiring C2/C3), stated per posture so the
  /// rollback claim is honest about WRITES as well as decisions.
  ///
  /// **THE DEFAULT IS [DualReadMode.off] (r13).** Wave 1 lands on main as
  /// INERT PLUMBING: every grid_sdk consumer that does not ask for a posture
  /// gets a station byte-equivalent to pre-cut mainline. The soak posture is
  /// ARMED EXPLICITLY BY THE RUNNER, never inherited from a default — see the
  /// runner surface below.
  ///
  /// [DualReadMode.off] — THE ROLLBACK, and the default. Byte-identical to
  /// pre-cut mainline, on the LOG as well as on decisions:
  ///   * no comparator pass on either axis or in the restart reconciler;
  ///   * no P1/P2 mirror SEEDING, no fold-generation re-read on the tick, and
  ///     no post-ACK mirror apply on the append path;
  ///   * no acked-envelope handback subscriptions and no mirror push sources
  ///     on the join bridge (so no extra `notifier.push` and no new
  ///     mount-frontier evaluation cadence);
  ///   * no boot reshape probe — an EXISTING home upgrading with `off` arms
  ///     exactly as it does on main, so the rollback is a rollback for the
  ///     population that most needs one;
  ///   * NONE of the comparator-driven observer appends.
  ///
  /// TWO THINGS `off` DOES ARM, since tg-ffl6 (decision
  /// `wave-2-flip-scope-soak-and-kill-date`, Q6 — bd remains an input to
  /// terminal truth at every posture): the external-close terminal obligation
  /// on the Stage-1 tick, which appends a reconstructed `attempt.terminal` for
  /// a session the LEDGER closed and the fold never saw end; and, because such
  /// records now exist at `off`, the appender's resolving pre-read — one
  /// in-transaction SELECT per session terminal — so a late real terminal
  /// converts the reconstructed row instead of hitting the guard's PK. `off`
  /// is therefore byte-equivalent to main on DECISIONS, not on the log.
  ///
  /// THE ONE EXCEPTION, adjudicated and deliberate: C8a's flare delivery. The
  /// state-store writer's `onFlare` was null-sunk on main — `session.minted`,
  /// `gate.autoClosed`, and `session.workTerminal` never reached the transport
  /// at all — and the fix is UNGATED because it is a reviewed BUG FIX, not a
  /// posture. `off` is byte-equivalent to main EXCEPT C8a's flare delivery.
  ///
  /// **THE RUNNER SURFACE — how the soak arms `observe`.** The posture is a
  /// the_grid VALUE; the flag and env that feed it are the runner's
  /// (space_station's `up`, stage1-wiring §1.1), exactly like
  /// `--trajectory` / `--no-trajectory` feed [mode]. The runner reads
  /// `--dual-read=<off|observe|primary>`, defaulting to `GRID_DUAL_READ` when
  /// the flag is absent and to [DualReadMode.off] when neither is set, and
  /// hands the result here. A station that arms nothing arms `off`.
  ///
  /// **THE DOWNGRADE CAVEAT IS RETIRED (tg-ffl6).** It existed because the
  /// resolving pre-read did not run at `off`; it runs at every posture now, so
  /// a reconstructed head carried out of an `observe` soak converts on the
  /// late real terminal exactly as it would under `observe`. Downgrade freely.
  ///
  /// [DualReadMode.observe] — C2's whole scope, and the posture the soak runs
  /// in. DECISIONS STAY LEGACY, but this is NOT a read-only posture and must
  /// not be described as one. Armed here:
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
  /// actually served. It is never a default anywhere; the flip is a separable
  /// one-line runner change attached to C2's gate evidence.
  ///
  /// Rollback is this one line at any posture, and it is instant — wave 1
  /// retires nothing, so legacy stays fully written and authoritative
  /// underneath whatever this says. (Read the downgrade caveat above before
  /// rolling a SOAKED home back to `off`.)
  ///
  /// **OPERATOR RUNBOOK — arming wave 1 on an EXISTING grid home.** The cut
  /// widened `proj_session_head`, and the migration is a named quiesced step,
  /// never a boot-time auto-migrate. Arming a posture ABOVE `off` on a home
  /// provisioned before this cut makes the harness REFUSE the live arm (mode
  /// `degraded`, cause naming the missing columns) rather than drop every
  /// terminal append on an unknown column. The fix, with the station DOWN:
  /// `traj replay` — it reshapes the projection and rebuilds it from the log,
  /// stamping the bumped `fold_version`. Then arm normally. A fresh home needs
  /// none of this: the schema bootstrap creates the cut shape. At `off` the
  /// probe does not run at all: an existing home upgrading to this code and
  /// arming nothing boots exactly as it did on main.
  final DualReadMode dualRead;

  final DualReadMode? _requestedDualRead;

  /// The named refusal for an explicit request that contradicts [discipline].
  ///
  /// Omitted posture arguments accept the cut's implications. The resolved
  /// public fields always remain `required`/`primary`, even when this reports
  /// a contradiction.
  CutPostureRefused? get cutPostureRefusal {
    if (discipline != TrajectoryDiscipline.cut) return null;
    const resolvedMode = TrajectoryConfigMode.required;
    const resolvedDualRead = DualReadMode.primary;
    final dualReadDisagrees =
        _requestedDualRead != null && _requestedDualRead != resolvedDualRead;
    final modeDisagrees =
        _requestedMode != null && _requestedMode != resolvedMode;
    if (!dualReadDisagrees && !modeDisagrees) return null;
    return CutPostureRefused._(
      requestedMode: _requestedMode,
      resolvedMode: resolvedMode,
      requestedDualRead: _requestedDualRead,
      resolvedDualRead: resolvedDualRead,
    );
  }

  /// The first trajectory head epoch admitted to the current soak window.
  ///
  /// Zero is the compatibility sentinel: every observed head is in-window,
  /// so scoped accounting preserves the pre-window behavior exactly. A live
  /// soak sets this to the first epoch where all required producers were
  /// deployed on the home. This labels evidence only; it never changes the
  /// dual-read posture or any served decision.
  final int soakWindowEpoch;

  /// THE LEDGER-CLOSE RECONCILE (tg-ffl6; decision
  /// `wave-2-flip-scope-soak-and-kill-date`, Q6). ON by default at EVERY
  /// posture: the external-close obligation reads the state snapshot and
  /// appends a reconstructed terminal for a session the ledger closed and the
  /// fold never saw end, and the appender's resolving pre-read runs so that
  /// testimony yields to observation. `false` is the rollback line r13's
  /// `off` used to be for this class: no ledger read, no reconstructed
  /// append, the pre-read back to posture-keyed. Retired rework rounds
  /// (`#rN` keys) are never reconciled either way — their fate is the
  /// wave-2 schema question (worksheet E9 / Q9), not a heal.
  final bool reconcileLedgerCloses;

  /// The service tick's interval (§1.2 step 2; Stage-0 default 30 s).
  final Duration tickInterval;

  /// Station-authored standing queries appended after the rollout stage's
  /// obligation set, in registration order. Empty leaves that set unchanged.
  final List<ObligationQuery> obligationQueryExtensions;

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

  /// The same config with trajectory writes disabled for dry-run under both
  /// disciplines, retaining the source cut-implied [dualRead] posture and the
  /// caller requests captured by the public constructor.
  TrajectoryConfig get asDisabled => TrajectoryConfig._disabledFrom(this);

  /// Returns an immutable config with [extensions] appended after every
  /// station-authored obligation query, preserving caller order and all
  /// requested and resolved posture fields.
  TrajectoryConfig withAppendedObligationQueries(
    Iterable<ObligationQuery> extensions,
  ) => TrajectoryConfig._withAppendedObligationQueries(this, extensions);
}
