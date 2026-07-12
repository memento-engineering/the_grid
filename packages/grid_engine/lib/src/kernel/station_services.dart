import 'package:grid_runtime/grid_runtime.dart';

import '../sdk/allocation.dart';

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
/// Immutable and value-light: a handle to long-lived collaborators, not state. A
/// node captures it once in `didChangeDependencies` and uses the captured
/// reference across async gaps so it never touches the `TreeContext` (which
/// throws post-unmount) for I/O.
class StationServices {
  /// Bundles the station's process transport [provider], the bd write [writer],
  /// the owned [stateSubstation], the optional adopt-liveness seam [liveness],
  /// and the concurrency-governor station default/ceiling [maxConcurrentWork].
  const StationServices({
    required this.provider,
    required this.writer,
    required this.stateSubstation,
    this.liveness,
    this.workSignal,
    this.maxConcurrentWork = kDefaultMaxConcurrentWork,
  });

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
  /// (ADR-0009 D4) — the Host threads it into each `AllocationContext.liveness`.
  /// Null (the default) ⇒ [neverLive] ⇒ the Host never adopts at mount (P1
  /// offline). **All-or-nothing** with the `RestartReconciler`'s `adoptProof`:
  /// the composer wires BOTH (from a real `ProcessGroupController`) at the live
  /// arm, or leaves both off — wiring one alone double-runs. This makes the two
  /// adopt halves symmetrically wireable (closing the adversarial-review footgun).
  final AllocationLiveness? liveness;

  /// The station's work-signal probe — the COMPLETION FENCE's binding. The Host
  /// threads it into each `AllocationContext.workSignal`. Null (the default) ⇒
  /// [noWorkSignal] ⇒ the fence is INERT and an inferred one-shot exit is taken at
  /// face value (today's behavior). The live composer binds it to its own
  /// source-control service's uncommitted-work probe, EXCLUDING the grid's own
  /// runtime dir (`grid_sdk`'s `stationWorkSignal`) — that impl is the composer's
  /// opinion, never the engine's (ADR-0008 D5). Unlike the adopt seam, this one is
  /// safe to arm ALONE: it can only WITHHOLD an unproven completion, never
  /// double-run anything.
  final WorkSignalProbe? workSignal;

  /// The concurrency governor's STATION-WIDE default/ceiling (tg-42f,
  /// declare-and-check — ADR-0008 D8 defers the general per-leaf
  /// `DartEnvironment` permit governor; this is the narrower, cheaper
  /// work-bead slot budget the mount boundary checks). Serves two roles: the
  /// DEFAULT a substation's own `SubstationConfig.maxConcurrentWork` falls back
  /// to when unset, AND the hard TOTAL ceiling across every substation
  /// `WorkList` mounts under this station — a substation override only narrows
  /// within that ceiling, never raises it. Threaded from `--max-agents`
  /// (`StationArgs.maxAgents`); defaults to [kDefaultMaxConcurrentWork] so a
  /// single-bead flow is unchanged.
  final int maxConcurrentWork;
}

/// The concurrency governor's generous default station cap (tg-42f) — chosen
/// so ordinary single/few-bead dev and dry-run flows never throttle.
const int kDefaultMaxConcurrentWork = 4;
