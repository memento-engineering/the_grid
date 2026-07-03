import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../domain/driveable_work.dart';
import '../domain/joined_snapshot.dart';
import '../domain/substation_config.dart';
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
  /// Creates the work list under [substationConfig] (passed down as data by `Substation`;
  /// the WorkList depends on the work axis only, never on the config inherited
  /// value).
  const WorkList({required this.substationConfig, super.key});

  /// The rig config, as data — its [SubstationConfig.ownedSubstations] builds the ownership
  /// predicate.
  final SubstationConfig substationConfig;

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
      'WorkList requires an ambient JoinedSnapshotNotifier provided above Station',
    );
    if (identical(notifier, _notifier)) return;
    _remove?.call();
    _notifier = notifier;
    // The initial read IS the subscription (D-H rule 2: never a sync accessor
    // that dodges `@protected state`): fireImmediately delivers the baseline
    // synchronously into the listener — assigned directly (setState during the
    // build phase is illegal); every later fire goes through setState.
    var first = true;
    _remove = notifier!.addListener((snapshot) {
      if (first) {
        first = false;
        _snapshot = snapshot;
        return;
      }
      setState(() => _snapshot = snapshot);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) {
    final ownership = BeadOwnershipPredicate(seed.substationConfig.ownedSubstations);
    final children = <WorkBead>[];
    for (final bead in _snapshot.graph.beadsById.values) {
      // Dispatchable-type gate BEFORE ownership, as an ALLOW-list (fail-closed):
      // only plain coding-work types mount a WorkBead + spawn an agent. A
      // deny-list would have to enumerate every non-work type, and `bd ready`
      // leaks the_grid's orchestration/coordination customs — its ready_work
      // query narrows only {merge-request,gate,molecule,message,agent,role,rig},
      // never convergence/convoy/event/step/spec. An allow-list of core work
      // types excludes convergence (the M2 two-writer axis), `session`
      // (the_grid's own lifecycle), every gc orchestration noun, and infra
      // (agent/rig/role) by construction; an unknown custom type does NOT mount.
      // (A41 — refines A40's mount-boundary type gate; the live-arm blessed-bead
      // drive-list remains a SEPARATE gate, ADR-0006.)
      if (!_isDispatchableWork(
        bead.issueType,
        resident: seed.substationConfig.resident,
      )) {
        continue;
      }
      if (!ownership.owns(bead)) continue;

      // Blessed-bead drive-list gate (ADR-0006): when a drive-list is configured
      // (a live arm blesses specific beads via `--bead`), ONLY those beads mount.
      // Empty = no per-bead restriction (dev/dry-run observes all owned work); a
      // live run refuses an empty drive-list upstream, so when armed this gate is
      // always active. Independent of the type/ownership allow-lists above — it
      // narrows further, never widens.
      final driveList = seed.substationConfig.driveList;
      if (driveList.isNotEmpty && !driveList.contains(bead.id)) continue;

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
        WorkBead(bead: bead, session: session, key: ValueKey(bead.id)),
      );
    }
    // Deterministic order by bead id — all children are keyed, so reconcile is
    // by key regardless, but a stable order keeps the tree legible.
    children.sort((a, b) => a.bead.id.compareTo(b.bead.id));
    return _WorkBeads(children);
  }

  /// The ALLOW-list: only plain, coding-dispatchable work mounts. `isCore` =
  /// {task, bug, feature, chore, epic, decision, spike, story, milestone} — the
  /// upstream built-in work types; every the_grid custom type (convergence /
  /// session / convoy / event / step / spec / gate / molecule / message /
  /// merge-request / agent / rig / role) is non-core and excluded. Fail-closed:
  /// an unrecognised custom type does NOT mount. (A41, ratified Nico
  /// 2026-06-25 — `isCore` stands; the epic / milestone / decision narrowing
  /// was considered and left in scope.)
  ///
  /// Under [resident] arming (RS-3/D-R4) the allow-list narrows FURTHER to
  /// the DRIVEABLE-WORK boundary ([IssueTypeDriveability.isDriveable]) — a
  /// resident station's ready frontier IS the drive set, so an organizational core
  /// type (epic/milestone/decision/spike/story) must never auto-mount just
  /// because it surfaced ready (the filing-time CATCH on RS-3; a scoped
  /// refinement of A41, flagged for the graduation ADR, never a weakening of
  /// the gates themselves).
  static bool _isDispatchableWork(IssueType type, {required bool resident}) =>
      type.isCore && (!resident || type.isDriveable);
}

/// The keyed-reconcile container `WorkList` builds — an impl detail of the work
/// axis (a `StatefulSeed` builds one child; this holds the many `WorkBead`s).
///
/// Each `WorkBead` is keyed by bead id, so reconcile preserves a bead's branch
/// — and its running effect — across snapshot ticks.
class _WorkBeads extends MultiChildSeed {
  _WorkBeads(List<WorkBead> beads) : super(children: beads);
}
