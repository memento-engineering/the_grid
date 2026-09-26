import 'package:grid_runtime/grid_runtime.dart';

import '../sdk/allocation.dart';
import 'admission_barrier.dart';
import 'state_store_write_governor.dart';
import 'station_admission_authority.dart';
import 'trajectory_scope.dart';

/// The STATION-level ambient services a node resolves from the tree in one
/// inherited lookup (ADR-0009 D2/D3 — the MediaQuery pattern: related ambient
/// data, one lookup, scoped to the *station*).
///
/// The kernel provides exactly one of these via an `InheritedSeed<StationServices>`
/// at the tree root, so every mounted node reaches the machine's process
/// transport ([provider]), the single bd write chokepoint ([writer]), the owned
/// state substation ([stateSubstation]), and the optional adopt-liveness seam
/// ([liveness]) — all genuinely per-machine. **Nothing substation-scoped lives
/// here** (ADR-0008 D5): the workspace/branch layout + source control are the
/// per-`SubstationScope` `SourceControl`'s (`ServiceBundle`), not the station's —
/// so a non-git / non-source effect is expressible and the engine holds no
/// worktree-layout opinion (ADR-0007 §1).
///
/// A station-lifetime owner and handle to long-lived collaborators. A node
/// captures it in `didChangeDependencies` and uses the captured reference
/// across async gaps so it never touches the `TreeContext` (which throws
/// post-unmount) for I/O.
class StationServices {
  /// Bundles the station's process transport [provider], the bd write [writer],
  /// the owned [stateSubstation], the optional adopt-liveness seam [liveness],
  /// and the concurrency-governor station default/ceiling [maxConcurrentWork].
  StationServices({
    required this.provider,
    required this.writer,
    required this.stateSubstation,
    this.liveness,
    this.workSignal,
    this.deliveryGate,
    this.trajectoryAdmissionHalt,
    this.admissionBarrier,
    this.g2EmissionMode = G2EmissionMode.off,
    StationTrajectoryRecorder? trajectoryRecorder,
    this.maxConcurrentWork = kDefaultMaxConcurrentWork,
    DateTime Function()? clock,
    StateStoreWriteGovernor? terminalWrites,
    StateStoreWriteGovernor? mountAttemptWrites,
  }) : terminalWrites =
           terminalWrites ??
           StateStoreWriteGovernor(
             bound: kTerminalWriteConcurrency,
             lane: 'terminal-gate-close',
           ),
       admission = StationAdmissionAuthority(
         writer: writer,
         provider: provider,
         stateSubstation: stateSubstation,
         maxConcurrentWork: maxConcurrentWork,
         liveness: liveness,
         trajectoryAdmissionHalt: trajectoryAdmissionHalt,
         admissionBarrier: admissionBarrier,
         g2EmissionMode: g2EmissionMode,
         trajectoryRecorder: trajectoryRecorder,
         clock: clock,
         mountAttemptWrites:
             mountAttemptWrites ??
             StateStoreWriteGovernor(
               bound: kMountAttemptWriteConcurrency,
               lane: 'mount-attempt-record',
             ),
       );

  /// The process transport — spawn (`start`), kill (`stop`), and the broadcast
  /// lifecycle [RuntimeProvider.events] stream the effect subscribes to.
  final RuntimeProvider provider;

  /// The single bd write chokepoint — the ONLY path session/lifecycle beads are
  /// written through (`createSession` / `update` / `close`), bd-only,
  /// `--actor grid-controller`, fail-closed on ownership (ADR-0006 Decision 2).
  final StationBeadWriter writer;

  /// The_grid's OWNED state substation (`tgdog`) — the partition session beads are
  /// minted into, kept separate from the read-only work source (A37).
  final String stateSubstation;

  /// The engine pgid-liveness half of the daemon adopt-freshness proof
  /// (ADR-0009 D4) — the Host threads it into each `AllocationInputs.liveness`.
  /// Null (the default) ⇒ [neverLive] ⇒ the Host never adopts at mount (P1
  /// offline). **All-or-nothing** with the `RestartReconciler`'s `adoptProof`:
  /// the composer wires BOTH (from a real `ProcessGroupController`) at the live
  /// arm, or leaves both off — wiring one alone double-runs. This makes the two
  /// adopt halves symmetrically wireable (closing the adversarial-review footgun).
  final AllocationLiveness? liveness;

  /// The station's work-signal probe — the COMPLETION FENCE's binding. The Host
  /// threads it into each `AllocationInputs.workSignal`. Null (the default) ⇒
  /// [noWorkSignal] ⇒ the fence is INERT and an inferred one-shot exit is taken at
  /// face value (today's behavior). The live composer binds it to its own
  /// source-control service's uncommitted-work probe, EXCLUDING the grid's own
  /// runtime dir (`grid_sdk`'s `stationWorkSignal`) — that impl is the composer's
  /// opinion, never the engine's (ADR-0008 D5). Unlike the adopt seam, this one is
  /// safe to arm ALONE: it can only WITHHOLD an unproven completion, never
  /// double-run anything.
  final WorkSignalProbe? workSignal;

  /// The FRESH-status delivery gate (tg-b1t8) — the root circuit's terminal
  /// advance asks it with the WORK bead's id IMMEDIATELY before it actuates
  /// the substation's bound [DeliveryMethod] (the push + pull request), and
  /// refuses the delivery when the bead is no longer open and driveable. The
  /// ambient `Bead` a route holds is the MOUNT-TIME snapshot; the zombie this
  /// exists to stop (genesis-xc2, PR #9) was open when its round started, so
  /// only a read performed at call time can see it was parked. Asking the
  /// gate IS that read.
  ///
  /// INJECTED, like [workSignal]: the live composer (grid_sdk's
  /// `assembleStationWork`) builds it over the store readers it holds; the
  /// engine owns no store-routing opinion. Null (the default) ⇒ the gate is
  /// INERT and delivery runs exactly as before. A gate that THROWS fails
  /// CLOSED — the delivery does not happen and the failure routes to
  /// supervision, whose bounded restart re-asks (a transient store error is
  /// retried, never silently delivered past).
  final WorkBeadLandGate? deliveryGate;

  /// The concurrency governor's fresh-authority boot value (tg-42f,
  /// declare-and-check — ADR-0008 D8 defers the general per-leaf
  /// `DartEnvironment` permit governor; this is the narrower, cheaper
  /// work-bead slot budget the mount boundary checks). At construction it
  /// serves two roles: the
  /// DEFAULT a substation's own `SubstationConfig.maxConcurrentWork` falls back
  /// to when unset, AND the hard TOTAL ceiling across every substation
  /// `WorkList` mounts under this station — a substation override only narrows
  /// within that ceiling, never raises it. Threaded from `--max-agents`
  /// (`StationArgs.maxAgents`); defaults to [kDefaultMaxConcurrentWork] so a
  /// single-bead flow is unchanged. Live control mutates [admission]'s resolved
  /// ceiling, not this value; a freshly constructed authority starts here.
  final int maxConcurrentWork;

  /// The cut-only admission breaker shared with trajectory call sites.
  final TrajectoryAdmissionHalt? trajectoryAdmissionHalt;

  /// The worktree-outstanding barrier's observer (§W2.4 W2-B) — the SAME
  /// instance the ambient [TrajectoryRecorderScope] carries, so the authority
  /// path and the offline path count onto one bookkeeper.
  final AdmissionBarrier? admissionBarrier;

  /// The once-resolved Stage-2 emitter posture. Defaults inert.
  final G2EmissionMode g2EmissionMode;

  /// The single station-owned admission and durable attempt-transition owner.
  final StationAdmissionAuthority admission;

  /// THE STATION-WIDE terminal-write bound (tg-66w8): the one governor every
  /// substation `WorkList` drains its terminal gate closes and work-terminal
  /// settlements through, admitting at most [kTerminalWriteConcurrency] at a
  /// time across the WHOLE station. It lives here rather than on the WorkList
  /// precisely so the count cannot scale with the roster.
  final StateStoreWriteGovernor terminalWrites;

  /// Disposes the station admission owner. Idempotent.
  void dispose() => admission.dispose();
}

/// The concurrency governor's generous default station cap (tg-42f) — chosen
/// so ordinary single/few-bead dev and dry-run flows never throttle.
const int kDefaultMaxConcurrentWork = 4;

/// How many terminal-session gate writes the whole STATION drains at once at
/// boot (tg-gxp6, made station-wide by tg-66w8). The restart sweep used to fire
/// one unawaited write per closed session simultaneously; on a store with
/// hundreds of them the tail of that burst blew `DoltQueryService.queryTimeout`,
/// and the failed gate closes cancelled the first mint of every ready bead.
/// Bounded, the same sweep still completes but never saturates the state store.
///
/// The bound is STATION-WIDE: `StationServices.terminalWrites` is one
/// [StateStoreWriteGovernor] shared by every substation `WorkList`, so this
/// number is the ceiling however many substations hold terminal sessions. It
/// used to be per WorkList, which multiplied it by the roster — lunar's
/// thirteen substations re-formed the burst at up to twenty-six simultaneous
/// writes and every session-terminal close of epoch 98 died at the deadline.
/// Two, not four: dolt serialises commits.
const int kTerminalWriteConcurrency = 2;
