import 'dart:math' as math;

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:state_notifier/state_notifier.dart';

import '../domain/driveable_work.dart';
import '../domain/joined_snapshot.dart';
import '../domain/substation_config.dart';
import '../kernel/station_services.dart';
import '../notifiers/joined_snapshot_notifier.dart';
import '../sdk/capability.dart';
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

  /// The substation config, as data — its [SubstationConfig.ownedSubstations] builds the ownership
  /// predicate.
  final SubstationConfig substationConfig;

  @override
  State<WorkList> createState() => _WorkListState();
}

class _WorkListState extends State<WorkList> {
  RemoveListener? _remove;
  JoinedSnapshotNotifier? _notifier;
  late JoinedSnapshot _snapshot;

  /// Bead ids whose `WorkBead` branch is mounted as of the last build — the
  /// A40 "already-mounted work is never evicted for budget reasons" invariant's
  /// OWN bookkeeping (tg-zat). `liveSession` alone misses a gap this invariant
  /// must still cover: `grid rework` re-keys a session bead's `work_bead` OFF
  /// this bead's id while it is still open (not yet closed) — so
  /// `sessionsByWorkBead[bead.id]` reads null for one-or-more snapshots while
  /// `SessionScope` schedules the close-then-re-mint transition. Without this
  /// set, that gap reclassifies the bead as a budget-gated `pending` candidate,
  /// and the concurrency governor can evict the very branch that would have
  /// closed the retired session and minted the fresh round — wedging the
  /// retired session open forever with no fresh mint. Membership tracks the
  /// BRANCH, not the session: added whenever a bead mounts, removed only on a
  /// genuine positive terminal.
  final Set<String> _mountedIds = <String>{};

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
    final ownership = BeadOwnershipPredicate(
      seed.substationConfig.ownedSubstations,
    );
    // The ambient ServiceBundle (per-`SubstationScope`, fixed-at-mount —
    // ADR-0008 D5) is depended on HERE, not just at `SessionScope`, so a
    // rooting refusal can flare through its `ExplorationTransport` (D-8) —
    // the SAME emit-only sink every other engine LOUD signal uses. This is a
    // config-axis dependency (never notifies once mounted), not the snapshot
    // pipeline — derailment-invariant 1 stays about the JOINED SNAPSHOT axis.
    final services = context.dependOnInheritedSeedOfExactType<ServiceBundle>();
    // The concurrency governor's ambient station default/ceiling (tg-42f) —
    // a config-axis lookup exactly like `ServiceBundle` above: a stable,
    // fixed-at-mount value that never notifies, so this new dependency stays
    // outside derailment-invariant 1 (the snapshot axis). Null (no
    // `StationServices` provided — the offline-test default) falls back to
    // the same generous constant `StationServices` itself defaults to.
    final stationServices = context
        .dependOnInheritedSeedOfExactType<StationServices>();
    // Two bins: `mounted` already carries a live (non-terminal) session — an
    // in-flight agent that is NEVER evicted for budget reasons (positive-
    // terminal-only unmount stays the only unmount trigger). `pending` is
    // freshly ready with no session yet — these are what the slot budget
    // below actually governs.
    final mounted = <WorkBead>[];
    final pending = <Bead>[];
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
      if (terminal) {
        _mountedIds.remove(bead.id);
        continue;
      }

      final inReady = _snapshot.graph.readyIds.contains(bead.id);
      final liveSession = session != null && !session.isTerminal;
      // A40's "already-mounted work is never evicted for budget reasons" also
      // covers a bead whose branch is ALREADY mounted even when `liveSession`
      // reads false THIS build (tg-zat): `grid rework` re-keys a session's
      // `work_bead` off this bead's id while it is still open, so
      // `sessionsByWorkBead[bead.id]` reads null for one-or-more snapshots
      // while `SessionScope` schedules its close-then-re-mint transition.
      // Falling back to `liveSession` alone here would drop the branch from
      // `mounted` and hand it to the budget gate below — evicting the very
      // SessionScope that would have closed the retired session and minted
      // the fresh round, wedging the retired session open forever.
      final staysMounted = liveSession || _mountedIds.contains(bead.id);
      // Mount if freshly ready OR still carrying/keeping a live session (the
      // latter is what keeps a transiently-unready bead's agent mounted).
      if (!inReady && !staysMounted) continue;

      // v3 single-root: a substation names ONE root, and an owned bead's root
      // IS its substation's root (resolved bead → substation → root). There is
      // no per-bead `metadata.grid.root` selector and no registered-root gate —
      // an owned, dispatchable, ready bead mounts.
      if (staysMounted) {
        _mountedIds.add(bead.id);
        mounted.add(
          WorkBead(bead: bead, session: session, key: ValueKey(bead.id)),
        );
      } else {
        pending.add(bead);
      }
    }

    // The concurrency governor (tg-42f, declare-and-check — ADR-0008 D8's
    // general per-leaf `DartEnvironment` permit governor is a separate,
    // deferred track): a substation cap ABOVE which freshly-ready beads stay
    // ready-unmounted — no session minted, no spawn, no cost — and mount on
    // the natural reconcile once a slot frees (a mounted session closes and
    // the positive-terminal unmount above drops it from `mounted` next tick).
    // Already-mounted work (`mounted`, live session) is NEVER evicted for
    // budget reasons — only `pending` candidates are gated.
    //
    // `stationCap` is null when no `StationServices` is ambient (an offline
    // test that never wires the governor) — every REAL run always composes
    // one (`buildLiveWiring`/`StationKernel`), so the station-wide ceiling
    // below is only ever skipped by a test that doesn't care about it. A
    // substation's own override still applies either way, defaulting to
    // [kDefaultMaxConcurrentWork] when nothing is configured at all.
    final stationCap = stationServices?.maxConcurrentWork;
    final substationCap =
        seed.substationConfig.maxConcurrentWork ??
        stationCap ??
        kDefaultMaxConcurrentWork;
    final substationSlots = math.max(0, substationCap - mounted.length);
    final int slotsAvailable;
    if (stationCap == null) {
      slotsAvailable = substationSlots;
    } else {
      // The station-wide total (tg-42f "and a station-wide cap above it"):
      // every non-terminal session in the shared `JoinedSnapshot` — global
      // across every substation this station mounts, read at zero extra cost
      // since `_snapshot` is already the ambient value this node observes.
      // This is a snapshot of the LAST SETTLED state (accurate across
      // flushes); two substations deciding to admit in the SAME flush can
      // transiently overshoot by however many substations raced —
      // declare-and-check, not a distributed lock — and self-corrects once
      // the newly-minted sessions land in the next snapshot.
      final stationWideLive = _snapshot.sessionsByWorkBead.values
          .where((s) => !s.isTerminal)
          .length;
      final stationSlots = math.max(0, stationCap - stationWideLive);
      slotsAvailable = math.min(substationSlots, stationSlots);
    }

    // Deterministic admission order (lowest bead id first) — same tie-break
    // the final sort below applies, so which beads get in is reproducible.
    pending.sort((a, b) => a.id.compareTo(b.id));
    final admitted = pending.take(slotsAvailable);
    final waiting = pending.skip(slotsAvailable).toList();
    for (final bead in admitted) {
      _mountedIds.add(bead.id);
      mounted.add(WorkBead(bead: bead, key: ValueKey(bead.id)));
    }
    if (waiting.isNotEmpty) {
      _reportThrottled(services, waiting);
    }

    // Deterministic order by bead id — all children are keyed, so reconcile is
    // by key regardless, but a stable order keeps the tree legible.
    mounted.sort((a, b) => a.bead.id.compareTo(b.bead.id));
    return _WorkBeads(mounted);
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

  /// Emits ONE LOUD line (tg-42f) when the concurrency governor holds
  /// [waiting] beads ready-unmounted for lack of a slot — count + which beads
  /// wait, through the same reserved emit-only [ExplorationTransport] (D-8)
  /// every other engine LOUD signal uses. ONE flare per build (never one per
  /// throttled bead) so a wide backlog doesn't flood the sink. A null
  /// [services]/`transport` is the offline/no-op default; a throwing
  /// transport never breaks the mount reconcile.
  static void _reportThrottled(ServiceBundle? services, List<Bead> waiting) {
    try {
      services?.transport?.flare('work.throttled', {
        'count': '${waiting.length}',
        'beadIds': waiting.map((b) => b.id).join(','),
      });
    } catch (_) {
      // A throwing transport never breaks the mount reconcile — swallow.
    }
  }
}

/// The keyed-reconcile container `WorkList` builds — an impl detail of the work
/// axis (a `StatefulSeed` builds one child; this holds the many `WorkBead`s).
///
/// Each `WorkBead` is keyed by bead id, so reconcile preserves a bead's branch
/// — and its running effect — across snapshot ticks.
class _WorkBeads extends MultiChildSeed {
  _WorkBeads(List<WorkBead> beads) : super(children: beads);
}
