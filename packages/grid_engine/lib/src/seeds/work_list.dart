import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../domain/joined_snapshot.dart';
import '../domain/rig_config.dart';
import '../domain/work_phase.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import 'work_bead.dart';

/// The work axis observer and keyed-reconcile container — **the heart**.
///
/// It is the SINGLE tree node that subscribes into the snapshot pipeline (via
/// the ambient [JoinedSnapshotNotifier]); every other node is config (an
/// ancestor) or pure-config-driven (`WorkBead` / effects). On each emission
/// only THIS node marks dirty (observational isolation — derailment-invariant
/// 1); its rebuild reconciles the `WorkBead` set, so a changed bead's WorkBead
/// is force-rebuilt by *this* cascade — and is therefore excluded from
/// `TreeOwner.flush()` — never by observing the notifier itself.
///
/// `root.markNeedsRebuild()` is banned; a single over-broad observation would
/// re-create the "config built 100×" bug ADR-0007 §6.1 exists to prevent.
class WorkList extends StatefulSeed {
  /// Creates the work list under [rigConfig] (passed down as data by `Rig`;
  /// the WorkList depends on the work axis only, never on the config inherited
  /// value).
  const WorkList({required this.rigConfig, super.key});

  /// The rig config, as data — its [RigConfig.ownedRigs] builds the ownership
  /// predicate.
  final RigConfig rigConfig;

  @override
  State<WorkList> createState() => _WorkListState();
}

class _WorkListState extends State<WorkList> {
  RemoveListener? _remove;
  JoinedSnapshotNotifier? _notifier;
  late JoinedSnapshot _snapshot;

  @override
  void didChangeDependencies() {
    // Resolve the ambient work-axis notifier and subscribe. The notifier
    // instance is stable in P0; the identity guard makes a re-run (or a future
    // instance swap) idempotent.
    final notifier = context
        .dependOnInheritedSeedOfExactType<JoinedSnapshotNotifier>();
    assert(
      notifier != null,
      'WorkList requires an ambient JoinedSnapshotNotifier provided above Grid',
    );
    if (identical(notifier, _notifier)) return;
    _remove?.call();
    _notifier = notifier;
    _snapshot = notifier!.current;
    // fireImmediately:false — the baseline is read synchronously above; firing
    // during initState would setState before the first build.
    _remove = notifier.addListener(
      (snapshot) => setState(() => _snapshot = snapshot),
      fireImmediately: false,
    );
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) {
    final ownership = BeadOwnershipPredicate(seed.rigConfig.ownedRigs);
    final children = <WorkBead>[];
    for (final bead in _snapshot.graph.beadsById.values) {
      // Type exclusion BEFORE ownership (M4-P0 §3 Track A): an owned
      // type=convergence (or other M2/M3-owned infra) root mounts ZERO
      // WorkBeads — that axis is the M2 ReconcilerRuntime's exclusively, and
      // mounting an agent effect on it is a true two-writer collision.
      // Defends ADR-0007 §6.1 invariant 3 / §6.3.
      if (_isExcludedType(bead.issueType)) continue;
      if (!ownership.owns(bead)) continue;

      final session = _snapshot.sessionsByWorkBead[bead.id];

      // Positive-terminal-only unmount: the work bead `closed`, OR the owned
      // session cursor terminal. NEVER a ready-set exit — a live agent's bead
      // can transiently leave readyIds (blocked, gc-edited) mid-flight, and
      // treating that as done would kill the live agent.
      final terminal = bead.isClosed || (session?.isTerminal ?? false);
      if (terminal) continue;

      final inReady = _snapshot.graph.readyIds.contains(bead.id);
      final liveSession = session != null && !session.isTerminal;
      // Mount if freshly ready OR still carrying a live session (the latter is
      // what keeps a transiently-unready bead's agent mounted).
      if (!inReady && !liveSession) continue;

      children.add(
        WorkBead(
          bead: bead,
          phase: phaseOf(bead, session),
          key: ValueKey(bead.id),
        ),
      );
    }
    // Deterministic order by bead id — all children are keyed, so reconcile is
    // by key regardless, but a stable order keeps the tree legible.
    children.sort((a, b) => a.bead.id.compareTo(b.bead.id));
    return _WorkBeads(children);
  }

  /// Types excluded at the mount boundary. `convergence` is the M2 reconciler's
  /// axis; `session` is the_grid's OWN lifecycle type (it lives in the state
  /// store, never the read source); `agent`/`rig`/`role` ([IssueType.isInfra])
  /// are infrastructure, not dispatchable work.
  static bool _isExcludedType(IssueType type) =>
      type == IssueType.convergence ||
      type == IssueType.session ||
      type.isInfra;
}

/// The keyed-reconcile container `WorkList` builds — an impl detail of the work
/// axis (a `StatefulSeed` builds one child; this holds the many `WorkBead`s).
///
/// Each `WorkBead` is keyed by bead id, so reconcile preserves a bead's branch
/// — and its running effect — across snapshot ticks.
class _WorkBeads extends MultiChildSeed {
  _WorkBeads(List<WorkBead> beads) : super(children: beads);
}
