/// Track D — the restart respawn-or-skip reconciler (ADR-0007 §4 /
/// M4-P0-BUILD-ORDER Track D).
///
/// On a controller restart the in-memory tree is gone, **not** the work. Two
/// kinds of survivor outlive the process: the per-bead git worktrees on disk
/// and the_grid's OWN session/lifecycle beads in the state store (`tgdog`).
/// Before the kernel re-mounts the tree (which would otherwise blindly respawn
/// every worktree), this reconciler walks the survivors and:
///
///  - **SKIP a done bead** — its OWNED session reached a positive terminal, so
///    the work is complete: reap its worktree (the three-gate fail-closed
///    remover) and do **not** respawn. This fires correctly even for a FOREIGN,
///    read-only work bead the_grid could never stamp, because the outcome
///    marker lives on the_grid's OWN session bead (A40/A37), not the work
///    bead. (The v1 bug: an unwritable foreign bead could never show `done`,
///    so it was always respawned.)
///  - **RESPAWN the rest** — a live session, or a worktree with no session
///    record at all, is left in place and marked respawn-pending for the tree
///    to re-mount.
///  - **SWEEP a molecule survivor's leased groups** — a session's process
///    identity lives in vendor-owned `grid.lease.*` breadcrumbs on its step
///    beads (the ONLY process-identity carrier since tg-eli phase 2 retired
///    the flat cursor). The vendor-exposed sweep
///    (`ProcessLeaseVendor.sweepOrphanedLeases` — Nico's 2026-07-19 ruling:
///    this reconciler stays lease-schema-ignorant) kills each live group no
///    re-mount will adopt through the SAME guarded terminate path and clears
///    its breadcrumb; a completed step is untouched, and a running/pending
///    step stays with the frontier (the job lease respawns fresh —
///    respawn-or-skip, never adoption for jobs). Scope is per SESSION, not per
///    liveness: a TERMINAL session's leftovers are swept too, and because no
///    re-mount is coming for it even a live daemon whose adopt proof holds is
///    an orphan there.
///
/// **The flat fence retired (tg-eli phase 2).** The old per-node
/// `session.cursor` kill walk (+ its legacy scalar-pgid fallback), the flat
/// [AdoptProof] seam, and the zombie-`running` cursor reap are GONE — a
/// session's cursor no longer projects, so there is nothing to walk. A
/// HISTORICAL flat session bead still bearing `grid.cursor.*` (or scalar
/// `pgid`/`pid`) metadata is INERT here: it dispositions off `isTerminal`
/// alone (skip-and-reap, or respawn-pending), no key is ever parsed, and
/// nothing throws. The molecule lease sweep is the one process-identity
/// reconciliation.
///
/// **Ordering invariant:** nothing is decided on stale state. [reconcile] awaits
/// the injected [RestartReconciler.freshnessBarrier] (a COMPLETED re-query of
/// the read + state runtimes) BEFORE it lists worktrees, projects sessions, or
/// terminates anything. Respawns therefore happen only after the barrier
/// resolves.
///
/// **Honest residuals (documented, NOT "fixed" here):**
///  - *Recycled-pgid risk.* [terminateGroup] / `kill(-pgid)` cannot read the
///    session token, so `process_group` cannot fence the kill on freshness. If
///    the OS recycled the stored `pgid` onto an unrelated group between
///    incarnations, the kill would hit the wrong group. This is BOUNDED by three
///    independent guards, not eliminated: the load-bearing `pgid <= 1`/own-group
///    safety guard inside [terminateGroup] (never bypassed here), the per-bead
///    worktree isolation, and the freshness barrier that precedes every kill.
///  - *Both-markers-miss re-run.* A crash that left NO terminal session
///    (e.g. the session bead never landed) leaves the worktree respawn-pending:
///    the tree mounts, mints a fresh session, and re-runs the agent in the
///    SAME worktree. Because the agent's commit is durable (committed
///    local-first into the worktree), this is a bounded re-run, not a
///    correctness violation.
///  - *Adopt-a-live-process is DEFERRED* to a later crash-safety track — the
///    lease sweep kills-and-respawns rather than re-attaching to a survivor
///    (the vendor's adopt-liveness stays at its never-adopt default).
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_bead.dart';
import '../domain/session_head_read.dart';
import '../domain/session_projection.dart';
import '../domain/trajectory_views.dart';
import '../molecule/molecule_schema.dart' show MoleculeStepKeys;
import '../molecule/process_lease_vendor.dart'
    show
        AttemptIdBasis,
        LeaseSweepCandidate,
        ProcessLeaseVendor,
        SweptLeaseGroup,
        recoverAttemptId;

/// The no-sink default for the boot pass's molecule lease sweep — NOT a
/// silent swallow: every swept group still rides [RestartReport.sweptLeases]
/// (the same optional-but-never-silent posture as the writer-less zombie
/// reap), and the live assembly always wires a real sink.
void _reportOnlyOrphanSink(String message) {}

/// The worktree-list seam: lists the per-bead worktrees under [root], each
/// re-bound to its bead id (the dir name encodes the id). Returns `null` on a
/// probe error so the caller fails closed. Bound to the grid git service's
/// `listBeadWorktrees` by the composing extension/runtime — injected as a
/// narrow function so the engine never names the concrete VCS service
/// (ADR-0007 §1 opinion-free kernel).
typedef ListBeadWorktrees =
    Future<List<BeadWorktree>?> Function(RootCheckout root);

/// The reap seam: the three-gate fail-closed worktree remover. Bound to the
/// grid git service's `reap` by the composing extension/runtime — injected
/// narrow for the same opinion-free reason as [ListBeadWorktrees].
typedef ReapWorktree =
    Future<ReapOutcome> Function({
      required RootCheckout root,
      required BeadWorktree worktree,
    });

/// The disposition of one surviving worktree after restart reconciliation.
///
/// Since tg-eli phase 2 the per-worktree pass produces only [skipped] and
/// [respawnPending] — the flat cursor's per-node kill walk retired, so
/// process-group reconciliation now rides the molecule lease sweep
/// ([RestartReport.sweptLeases]), not a per-worktree disposition. The
/// [adopted]/[killed]/[refusedUnsafe] values survive as public API (report
/// shape compatibility) but no current pass emits them.
enum RestartDisposition {
  /// The OWNED session reached a positive terminal — the work is done. The
  /// worktree was handed to the [ReapWorktree] seam; the bead does NOT respawn.
  skipped,

  /// HISTORICAL (the flat adopt path, retired tg-eli phase 2): a live group
  /// an adopt proof accepted was left running for the re-mounted tree to
  /// reattach. No current pass emits this.
  adopted,

  /// HISTORICAL (the flat kill path, retired tg-eli phase 2): a live
  /// session's recorded orphan group was terminated pre-respawn. No current
  /// pass emits this — the molecule lease sweep kills orphans instead, and
  /// reports them on [RestartReport.sweptLeases].
  killed,

  /// HISTORICAL (the flat kill path, retired tg-eli phase 2): a recorded
  /// `pgid` the [terminateGroup] safety guard refused. No current pass emits
  /// this — the guard now runs inside the lease sweep.
  refusedUnsafe,

  /// Left in place for the tree to re-mount + respawn: a live session, or a
  /// worktree with no session record at all (the both-markers-miss residual).
  respawnPending,
}

/// One ZOMBIE running-node a flat-model restart pass reaped.
///
/// HISTORICAL (tg-eli phase 2): the zombie-`running` cursor reap retired with
/// the flat `grid.cursor.*` model — a molecule step's liveness is the lease
/// vendor's concern, and its `running` marker is reconciled by the frontier's
/// own bd-status fallback, not a boot-time cursor rewrite. The type survives
/// as public API ([RestartReport.reaped] is part of the report shape, and
/// `grid_sdk` re-exports it); the list is now always empty.
class ZombieReap {
  /// Records the reap of [nodePath] on [sessionId], carrying the dead
  /// incarnation's [pgid]/[pid] and the [reapCount] the re-mount write bumped
  /// to. [failure] is null when the cursor write landed.
  const ZombieReap({
    required this.sessionId,
    required this.nodePath,
    required this.reapCount,
    this.pgid,
    this.pid,
    this.failure,
  });

  /// The_grid's OWN session bead the reaped cursor lives on — NEVER the foreign,
  /// read-only work bead (A37).
  final String sessionId;

  /// The reaped node's full cursor path (`<beadId>/<stepId>`).
  final String nodePath;

  /// The bumped ADOPTION-reap count this write recorded (the dead incarnation's
  /// `reapCount + 1`). Capture-only — it is NOT the supervised-restart budget,
  /// NOT the rework belt, and NOT in the reconcile key (A47), so a bounce stays
  /// FREE. It exists to make a crash-LOOPING station visible.
  final int reapCount;

  /// The dead group's recorded pgid (diagnostics; null when none was stamped).
  final int? pgid;

  /// The recorded leader pid the liveness probe refuted — null for a `running`
  /// marker that carried NO pid at all (unprovable, so reaped fail-closed).
  final int? pid;

  /// Why the reap WRITE was dropped, or null when it landed — a transient bd
  /// blip, an ownership refusal, or NO chokepoint wired at all.
  final String? failure;

  /// Whether the reap's cursor write landed.
  bool get isWritten => failure == null;

  @override
  String toString() =>
      'ZombieReap($sessionId/$nodePath, pid: $pid, reapCount: $reapCount'
      '${failure == null ? '' : ', DROPPED: $failure'})';
}

/// One row of the [RestartReport]: the worktree, its disposition, and the
/// mechanism outcome that produced it (so a caller/test can assert WHY without
/// scraping logs).
class RestartEntry {
  const RestartEntry({
    required this.worktree,
    required this.disposition,
    this.sessionId,
    this.reapOutcome,
    this.terminateResult,
  });

  /// The surviving worktree this entry reconciled.
  final BeadWorktree worktree;

  /// What happened to it.
  final RestartDisposition disposition;

  /// The OWNED session bead id that drove the decision, when one was found
  /// (null for the both-markers-miss fresh case).
  final String? sessionId;

  /// The reap mechanism outcome — present iff [disposition] is
  /// [RestartDisposition.skipped].
  final ReapOutcome? reapOutcome;

  /// The terminate-group mechanism outcome — present iff [disposition] is
  /// [RestartDisposition.killed] or [RestartDisposition.refusedUnsafe].
  final GroupTerminateResult? terminateResult;

  /// The work bead this worktree carries (the dir-name-encoded id).
  String get beadId => worktree.beadId;
}

/// The immutable outcome of one [RestartReconciler.reconcile] pass — lists of
/// entries bucketed by disposition, enough to assert in a test and to log a
/// one-line restart summary.
/// One session the teardown replay considered (tg-tlea).
class TeardownReplayEntry {
  /// Records [sessionId]'s disposition and what the replay did about it.
  const TeardownReplayEntry({
    required this.sessionId,
    required this.disposition,
    required this.replayed,
    this.workBeadId,
    this.reapedWorktree = false,
    this.failures = const [],
  });

  /// The state-store session bead whose teardown was outstanding.
  final String sessionId;

  /// Its derived disposition. Open sessions are replayed only when `done`;
  /// closed sessions may be replayed solely to collect live graph children.
  final GateSweepSessionDisposition disposition;

  /// Whether teardown work was replayed, including closed-session molecule
  /// collection (false for an open HELD or VOIDED session).
  final bool replayed;

  /// The work bead the session drove, when its join key survived.
  final String? workBeadId;

  /// Whether a surviving worktree was found and reaped. False is the W3 shape
  /// — the window no worktree-driven pass can see.
  final bool reapedWorktree;

  /// Which replayed steps threw. Non-empty is LOUD but never fatal.
  final List<String> failures;

  @override
  String toString() =>
      'TeardownReplayEntry($sessionId, ${disposition.name}, '
      'replayed: $replayed, failures: $failures)';
}

/// What one boot's teardown replay did (tg-tlea).
class TeardownReplayReport {
  /// Wraps [entries], one per session whose teardown was outstanding.
  const TeardownReplayReport(this.entries);

  /// Every session the trigger query returned, replayed or skipped.
  final List<TeardownReplayEntry> entries;

  /// The sessions whose tail was actually re-run.
  Iterable<TeardownReplayEntry> get replayed =>
      entries.where((e) => e.replayed);

  /// Sessions carrying a human hold. A closed held session may still be
  /// replayed solely to collect molecule children while preserving worktrees.
  Iterable<TeardownReplayEntry> get held =>
      entries.where((e) => e.disposition == GateSweepSessionDisposition.held);
}

class RestartReport {
  RestartReport(
    List<RestartEntry> entries, {
    List<ZombieReap> reaped = const [],
    List<SweptLeaseGroup> sweptLeases = const [],
    List<WorkTerminalSettlementReport> workTerminalSettlements = const [],
  }) : entries = List.unmodifiable(entries),
       reaped = List.unmodifiable(reaped),
       sweptLeases = List.unmodifiable(sweptLeases),
       workTerminalSettlements = List.unmodifiable(workTerminalSettlements),
       skipped = List.unmodifiable(
         entries.where((e) => e.disposition == RestartDisposition.skipped),
       ),
       adopted = List.unmodifiable(
         entries.where((e) => e.disposition == RestartDisposition.adopted),
       ),
       killed = List.unmodifiable(
         entries.where((e) => e.disposition == RestartDisposition.killed),
       ),
       refusedUnsafe = List.unmodifiable(
         entries.where(
           (e) => e.disposition == RestartDisposition.refusedUnsafe,
         ),
       ),
       respawnPending = List.unmodifiable(
         entries.where(
           (e) => e.disposition == RestartDisposition.respawnPending,
         ),
       );

  /// Every reconciled worktree, in worktree-list order.
  final List<RestartEntry> entries;

  /// Done beads whose worktree was reaped (no respawn).
  final List<RestartEntry> skipped;

  /// Live survivors LEFT RUNNING for the re-mounted tree to reattach (D4) — not
  /// killed, not reaped, not respawned.
  final List<RestartEntry> adopted;

  /// Orphans whose live process group was terminated (then respawn-pending).
  final List<RestartEntry> killed;

  /// Live sessions whose `pgid` failed the safety guard (then respawn-pending).
  final List<RestartEntry> refusedUnsafe;

  /// Worktrees left for the tree to re-mount + respawn (this INCLUDES the
  /// [refusedUnsafe] beads — they are respawn-pending too; this list is the
  /// "respawn-pending and nothing else happened" bucket).
  final List<RestartEntry> respawnPending;

  /// The ZOMBIE running-nodes this pass reaped — ALWAYS EMPTY since tg-eli
  /// phase 2 retired the flat-cursor zombie reap (see [ZombieReap]). Kept so
  /// the report shape (and `droppedReapReports` in grid_sdk) is unchanged.
  final List<ZombieReap> reaped;

  /// The MOLECULE lease groups this pass's vendor sweep acted on (or
  /// deliberately preserved) — killed orphans, guard-refused residuals, and
  /// adoptable daemons left running. Empty when no vendor was wired or no
  /// molecule survivor carried a live breadcrumb. Every kill was already
  /// reported LOUD by the sweep itself; this list is the assertable record.
  final List<SweptLeaseGroup> sweptLeases;

  final List<WorkTerminalSettlementReport> workTerminalSettlements;

  /// The total number of beads the tree must respawn on re-mount: everything
  /// except the skipped (done) beads AND the adopted (reattached) survivors.
  /// [refusedUnsafe] is included.
  int get respawnCount => entries.length - skipped.length - adopted.length;

  @override
  String toString() =>
      'RestartReport(skipped: ${skipped.length}, adopted: ${adopted.length}, '
      'killed: ${killed.length}, refusedUnsafe: ${refusedUnsafe.length}, '
      'respawnPending: ${respawnPending.length}, reaped: ${reaped.length}, '
      'sweptLeases: ${sweptLeases.length}, respawnCount: $respawnCount)';
}

typedef WorkTerminalSettlementReport = ({
  String sessionId,
  String workBeadId,
  String terminalReason,
  String? failure,
});

/// One process group a flat-model fence sweep walked: the node that recorded
/// it, its `pgid` + leader `pid`, and the guarded [terminateGroup] outcome.
///
/// HISTORICAL (tg-eli phase 2): the teardown sweep's fence half retired with
/// the flat cursor, so no pass produces these any more —
/// [OrphanSweepReport.terminatedGroups] is always empty. The type survives as
/// public API (`grid_sdk` re-exports it; the report shape is unchanged).
typedef SweptGroup = ({
  String nodePath,
  int pgid,
  int pid,
  GroupTerminateResult result,
});

/// The immutable outcome of one [RestartReconciler.sweepOrphans] pass — enough
/// to assert in a test and to log a one-line teardown summary.
class OrphanSweepReport {
  /// Bundles the transport sessions [stoppedSessions] and the fence groups
  /// [terminatedGroups] this sweep reaped, and whether the station went quiet
  /// within the settle window ([settled]).
  OrphanSweepReport({
    required List<String> stoppedSessions,
    required List<SweptGroup> terminatedGroups,
    required this.settled,
  }) : stoppedSessions = List.unmodifiable(stoppedSessions),
       terminatedGroups = List.unmodifiable(terminatedGroups);

  /// The transport session names still held after the unmount, stopped by the
  /// sweep (in reap order).
  final List<String> stoppedSessions;

  /// The persisted-fence process groups terminated by the sweep — ALWAYS
  /// EMPTY since tg-eli phase 2 retired the flat fence half (see
  /// [SweptGroup]). Kept so the report shape is unchanged.
  final List<SweptGroup> terminatedGroups;

  /// Whether the sweep reached its quiet threshold before the settle window
  /// closed. False ⇒ the window closed with effects still landing (reported
  /// LOUD — never a silent give-up).
  final bool settled;

  /// Whether the sweep reaped nothing — the clean teardown (the norm).
  bool get isClean => stoppedSessions.isEmpty && terminatedGroups.isEmpty;

  @override
  String toString() =>
      'OrphanSweepReport(stopped: $stoppedSessions, '
      'terminated: ${terminatedGroups.map((g) => g.pgid).toList()}, '
      'settled: $settled)';
}

/// Reconciles the restart survivors (worktrees + owned session beads) into a
/// respawn-or-skip plan, BEFORE the kernel re-mounts the tree.
///
/// All dependencies are injected so the whole pass runs offline against fakes:
/// the [ListBeadWorktrees] + [ReapWorktree] seams (bound to the grid git
/// service's `listBeadWorktrees`/`reap` by the composing extension/runtime —
/// narrow functions so the engine never names the concrete VCS service,
/// ADR-0007 §1), the [RootCheckout] under which the worktrees live, the
/// [ProcessGroupController] (the orphan-kill seam the molecule lease sweep
/// binds — kept REAL via [terminateGroup] so its `pgid <= 1` guard is
/// genuinely exercised), the [freshnessBarrier] (a completed re-query), and a
/// [stateSnapshot] reader (the state-store snapshot read AFTER the barrier,
/// to project the OWNED sessions).
class RestartReconciler {
  RestartReconciler({
    required ListBeadWorktrees listWorktrees,
    required ReapWorktree reapWorktree,
    RootCheckout? workRoot,
    List<RootCheckout> workRoots = const <RootCheckout>[],
    required ProcessGroupController groups,
    required Future<void> Function() freshnessBarrier,
    required GraphSnapshot Function() stateSnapshot,
    GraphSnapshot Function()? workSnapshot,
    StationBeadWriter? writer,
    ProcessLeaseVendor? leaseVendor,
    void Function(String message)? onOrphan,
    StationTrajectoryRecorder? recorder,
    TrajectoryHeadSnapshot Function()? headSnapshot,
    DualReadAccounting? dualReadAccounting,
    void Function(String name, Map<String, String> data)? onFlare,
  }) : assert(workRoot != null || workRoots.isNotEmpty),
       _recorder = recorder ?? StationTrajectoryRecorder.disabled(),
       _headSnapshot = headSnapshot,
       _dualRead = dualReadAccounting,
       _onFlare = onFlare,
       _listWorktrees = listWorktrees,
       _reapWorktree = reapWorktree,
       _workRoots = List<RootCheckout>.unmodifiable(
         workRoots.isEmpty ? <RootCheckout>[workRoot!] : workRoots,
       ),
       _groups = groups,
       _writer = writer,
       _freshnessBarrier = freshnessBarrier,
       _stateSnapshot = stateSnapshot,
       _workSnapshot = workSnapshot ?? _emptySnapshot,
       _leaseVendor = leaseVendor,
       _onOrphan = onOrphan ?? _reportOnlyOrphanSink;

  final ListBeadWorktrees _listWorktrees;
  final ReapWorktree _reapWorktree;
  final List<RootCheckout> _workRoots;
  final ProcessGroupController _groups;

  /// The SINGLE bd write chokepoint (invariant 2) — OPTIONAL for the same
  /// CROSS-REPO-ctor reason as [_leaseVendor] (a sibling repo's asset
  /// guardrail suites construct this reconciler with no writer, and a
  /// required param would darken them with a compile error). Since tg-eli
  /// phase 2 retired the zombie-cursor reap this pass issues no writes of its
  /// own except work-terminal survivor settlement; [hasChokepoint] proves the
  /// chokepoint reached the boot pass.
  final StationBeadWriter? _writer;

  /// The molecule model's process-lease vendor — the ONLY `grid.lease.*`
  /// touchpoint this reconciler has (Nico's 2026-07-19 ruling: the vendor owns
  /// the lease schema; this pass hands it candidate step-bead metadata and the
  /// guarded kill seam, and never parses a lease key itself). OPTIONAL for the
  /// same cross-repo-ctor reason as [_writer]: a composition without it (a
  /// sibling repo's guardrail suites) simply has no molecule sweep — the flat
  /// pass is unchanged.
  final ProcessLeaseVendor? _leaseVendor;

  /// The LOUD sink the molecule lease sweep reports every kill through
  /// (`docs/OPERATIONS.md` §2.4 — an orphan is an invariant violation, never
  /// reaped quietly). OPTIONAL but never silent: with no sink wired, the swept
  /// groups still ride [RestartReport.sweptLeases] for the caller to report;
  /// the live assembly (`assembleStationWork`) always wires it.
  final void Function(String message) _onOrphan;

  /// The Stage-1 derivation layer (stage1-wiring §2.3's settled-terminal row).
  /// Every record this pass derives is `provenance='inferred'`: the pass
  /// settles a PRIOR boot's sessions from evidence on disk, and it was never
  /// there to observe the transition it is recording. Absent (the default) it
  /// is a counting no-op.
  final StationTrajectoryRecorder _recorder;

  /// The DUAL READ's third input on this pass (cut-wiring C2) — the SAME
  /// pre-fetched P1 mirror the join bridge reads, injected as a getter so the
  /// reconciler stays synchronous and store-free. Null off-tree; then the
  /// comparison simply does not run and this pass is byte-identical to before.
  final TrajectoryHeadSnapshot Function()? _headSnapshot;

  /// Shared with the bridge's observer so ONE boot has ONE set of counters —
  /// the round summary must not report two different truths for one boot.
  final DualReadAccounting? _dualRead;

  final void Function(String name, Map<String, String> data)? _onFlare;

  /// Whether the ONE bd chokepoint reached this pass — a wiring proof for the
  /// composition (the assembly's own test asserts it). A capability query on
  /// an off-tree machine, not an accessor over reactive state (D-H rule 2).
  bool get hasChokepoint => _writer != null;

  /// Whether the MOLECULE lease sweep is armed (a vendor reached this pass) —
  /// [hasChokepoint]'s twin for the molecule axis, same posture. Armed means
  /// ARMED: the sweep's kill gate is bound to THIS reconciler's own
  /// [ProcessGroupController] at call time (`processAlive` over the recorded
  /// leader pid — the flat path's exact kill evidence), never to a
  /// separately-wired liveness seam, so a wired vendor can never be silently
  /// inert.
  bool get hasLeaseSweep => _leaseVendor != null;

  /// A COMPLETED re-query of the read + state runtimes — awaited FIRST so no
  /// decision is made on stale state. Injected so it is fake-driveable.
  final Future<void> Function() _freshnessBarrier;

  /// The state-store snapshot reader (the owned `session` beads), read AFTER the
  /// barrier completes so the projected cursors reflect the post-barrier state.
  final GraphSnapshot Function() _stateSnapshot;
  final GraphSnapshot Function() _workSnapshot;

  static GraphSnapshot _emptySnapshot() => GraphSnapshot.fromParts(
    beads: const <Bead>[],
    dependencies: const <BeadDependency>[],
    readyIds: const <String>[],
    capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Walks the restart survivors and produces the respawn-or-skip plan.
  ///
  /// 1. Await the freshness barrier (nothing is decided on stale state).
  /// 2. List the per-bead worktrees (fail closed: a null probe ⇒ no worktrees
  ///    reconciled this pass).
  /// 3. Project the OWNED sessions from the post-barrier state snapshot,
  ///    keyed by `work_bead` (so SKIP fires for a foreign work bead).
  /// 4. For each worktree: SKIP-and-reap a terminal session; else leave it
  ///    respawn-pending.
  /// 5. SWEEP the molecule survivors' leased groups through the vendor — the
  ///    ONE process-identity reconciliation (a session's process identity is
  ///    the vendor's `grid.lease.*` breadcrumb on its step beads; the flat
  ///    cursor fence retired, tg-eli phase 2).
  /// **The TEARDOWN REPLAY** (tg-tlea) — the session-driven boot pass beside
  /// the worktree-driven [reconcile].
  ///
  /// A station killed mid-teardown strands the work its exit path had already
  /// begun cleaning up. The positive-terminal close is a four-step tail —
  /// stamp `grid.outcome=complete`, reap the molecule, reap the worktree,
  /// close (then sweep the terminal gates) — and steps 2 onward are
  /// LOUD-but-never-fatal, so a crash between any two of them leaves no retry
  /// anywhere. Worktrees, gates and process leases each already got a
  /// boot-time retry; molecule collection is the one teardown step that never
  /// did. That gap is the mechanism behind the pour-timeout cliff: the rework
  /// exit path shipped without the reap and left 9,389 orphans across 307
  /// closed sessions.
  ///
  /// The trigger set is the marker the exit path ALREADY writes first: a
  /// session still OPEN while carrying `grid.outcome=complete` is, by
  /// construction, a teardown that did not finish. No new durable state, no
  /// schema at mint, no exit path taught anything.
  ///
  /// **Complementary to [reconcile], never a replacement.** That walk still
  /// catches a survivor this query structurally cannot see — a worktree on
  /// disk with no session record at all. Conversely this catches the window
  /// that walk cannot: a station that died AFTER the worktree reap but before
  /// the close leaves an open, complete-marked session with no surviving
  /// worktree, and a worktree-driven pass has nothing left to find it by. The
  /// overlap is harmless precisely because every replayed step is idempotent
  /// (re-verified rather than assumed: [StationBeadWriter.reapMolecule]
  /// returns immediately on an empty open molecule/step set, the worktree reap
  /// no-ops on an already-removed tree, and gate close is idempotent).
  ///
  /// Open HELD sessions are excluded. A closed HELD session retains its
  /// worktree but no longer owns live molecule/step children. Externally
  /// closed owners are projected from the post-barrier snapshot and merged
  /// with the marker-filtered open crash-window query.
  ///
  /// Every step is LOUD and non-fatal: a replay failure must never stop a
  /// station from booting.
  Future<TeardownReplayReport> replayTeardownTail() async {
    final writer = _writer;
    if (writer == null) return const TeardownReplayReport([]);
    // The same barrier discipline as [reconcile] — nothing is decided on
    // stale state.
    await _freshnessBarrier();
    final snapshot = _stateSnapshot();
    var openCandidates = const <Bead>[];
    try {
      openCandidates = await writer.sessionsAwaitingTeardown();
    } on Object catch (error) {
      _onOrphan(
        'teardown replay: could not read the outstanding-teardown set — $error',
      );
    }
    final candidatesById = <String, Bead>{
      for (final session in openCandidates) session.id: session,
      for (final session in _closedSessionsWithOpenMolecules(snapshot))
        session.id: session,
    };
    final candidates = candidatesById.values.toList(growable: false);
    if (candidates.isEmpty) return const TeardownReplayReport([]);
    // Reused for the worktree step: a session whose worktree is already gone
    // (the window nothing else can see) finds nothing here and goes straight
    // to the close.
    // Rebase reconciliation: main's lazy-scan guard (skip the worktree walk
    // when no candidate needs replay) over this branch's multi-root shape
    // (worktreesByRoot rides into _replayOne).
    final needsWorktreeReplay = candidates.any(
      (session) =>
          session.status != BeadStatus.closed &&
          sessionDispositionOfMetadata(session.metadata) ==
              GateSweepSessionDisposition.done,
    );
    final worktreesByRoot = <RootCheckout, List<BeadWorktree>>{};
    if (needsWorktreeReplay) {
      for (final root in _workRoots) {
        worktreesByRoot[root] =
            await _listWorktrees(root) ?? const <BeadWorktree>[];
      }
    }
    final worktrees = [for (final trees in worktreesByRoot.values) ...trees];
    final worktreeByBeadId = <String, BeadWorktree>{
      for (final wt in worktrees) wt.beadId: wt,
    };
    final entries = <TeardownReplayEntry>[];
    for (final session in candidates) {
      final disposition = sessionDispositionOfMetadata(session.metadata);
      if (session.status != BeadStatus.closed &&
          disposition != GateSweepSessionDisposition.done) {
        entries.add(
          TeardownReplayEntry(
            sessionId: session.id,
            disposition: disposition,
            replayed: false,
          ),
        );
        continue;
      }
      entries.add(
        await _replayOne(writer, session, worktreeByBeadId, worktreesByRoot),
      );
    }
    return TeardownReplayReport(entries);
  }

  /// Re-runs ONE session's teardown tail: reap the molecule, reap the
  /// worktree, CLOSE, then sweep the terminal gates.
  ///
  /// The close precedes the gate sweep because
  /// [StationBeadWriter.closeOpenGatesForTerminal] REFUSES a `done` sweep
  /// whose session is not already closed (`gate auto-close refused: live
  /// session`) — so gates-then-close cannot work on a still-open session,
  /// whatever order a reading of the tail might suggest.
  Future<TeardownReplayEntry> _replayOne(
    StationBeadWriter writer,
    Bead session,
    Map<String, BeadWorktree> worktreeByBeadId,
    Map<RootCheckout, List<BeadWorktree>> worktreesByRoot,
  ) async {
    if (session.status == BeadStatus.closed) {
      final failures = <String>[];
      try {
        await writer.reapMolecule(sessionId: session.id);
      } on Object catch (error) {
        failures.add('molecule');
        _onOrphan(
          'teardown replay ${session.id}: closed-session molecule reap failed '
          '(closeReason=externally-closed) — $error',
        );
      }
      final workBeadId = '${session.metadata[SessionBeadKeys.workBead] ?? ''}';
      return TeardownReplayEntry(
        sessionId: session.id,
        disposition: sessionDispositionOfMetadata(session.metadata),
        replayed: true,
        workBeadId: workBeadId.isEmpty ? null : workBeadId,
        failures: failures,
      );
    }
    final failures = <String>[];
    // The ATTEMPT ID is recovered BEFORE the close, off the same post-barrier
    // state snapshot everything else in this pass projects from: the observer
    // append below needs it, and no id is ever minted for it.
    String? recoveredAttemptId;
    try {
      recoveredAttemptId = _recoverSessionAttemptId(session.id);
    } on Object {
      recoveredAttemptId = null;
    }
    try {
      await writer.reapMolecule(sessionId: session.id);
    } on Object catch (error) {
      failures.add('molecule');
      _onOrphan('teardown replay ${session.id}: molecule reap failed — $error');
    }
    final workBeadId = '${session.metadata['work_bead'] ?? ''}';
    final worktree = worktreeByBeadId[workBeadId];
    if (worktree != null) {
      try {
        final root = worktreesByRoot.entries
            .firstWhere((entry) => entry.value.contains(worktree))
            .key;
        await _reapWorktree(root: root, worktree: worktree);
      } on Object catch (error) {
        failures.add('worktree');
        _onOrphan(
          'teardown replay ${session.id}: worktree reap failed — $error',
        );
      }
    }
    var closed = false;
    try {
      await writer.close(session.id);
      closed = true;
    } on Object catch (error) {
      failures.add('close');
      _onOrphan('teardown replay ${session.id}: close failed — $error');
    }
    // THE TEARDOWN-REPLAY OBSERVER APPEND (cut-wiring §C2, r5 form).
    //
    // SCOPE, stated as a RULE rather than left to the control flow: the append
    // rides ONLY this arm — the closed-an-OPEN-session branch, after ITS
    // successful `writer.close`. The closed-session early-return above appends
    // NOTHING: an already-closed session had its terminal, and that terminal's
    // absence from P1 is not this arm's to invent. (The candidate set really
    // does hold both shapes — `sessionsAwaitingTeardown` plus
    // `_closedSessionsWithOpenMolecules` — so the split is load-bearing, not
    // decorative: a settled-outcome append with a minted id here would sit one
    // refactor away from overwriting an `escalated`/`lost` head.)
    //
    // Without it every teardown replay leaves a permanent P1-open /
    // legacy-terminal head: an UNHEALABLE `terminalLag` that escalates and
    // makes the C2/C3 zero-divergence gates unsatisfiable.
    //
    // It is an OBSERVER APPEND — a new record ABOUT a bd write that already
    // happens today. The bd write itself is byte-identical, so wave 1's
    // zero-bd-write-changes invariant is untouched.
    if (closed) {
      if (recoveredAttemptId == null) {
        // NO FABRICATED ATTEMPT ID. A missing record is a visible lag; a
        // minted-id record is an immutable lie `revert` cannot remove and
        // every `traj replay` reproduces.
        _dualRead?.reconstructedTerminalSkipped += 1;
        _onFlare?.call(kReconstructedTerminalSkippedFlare, {
          'session_id': session.id,
          'work_bead': workBeadId,
          // The vendor owns the breadcrumb SCHEMA (Nico's 2026-07-19 ruling);
          // this pass names only the recovery's OUTCOME, never its key.
          'reason': 'no attempt id recoverable for the session',
          'basis': 'restart-reconciler',
        });
        _onOrphan(
          'teardown replay ${session.id}: reconstructed terminal SKIPPED — no '
          'attempt id was recoverable; the P1 head stays open (a visible lag) '
          'rather than taking a minted id',
        );
      } else {
        _dualRead?.teardownReplayAppends += 1;
        _recorder.sessionTeardownReplayed(
          sessionId: session.id,
          attemptId: recoveredAttemptId,
          workBeadId: workBeadId.isEmpty ? null : workBeadId,
          reason:
              'teardown replay closed an open session bead; the attempt was '
              'never observed by this pass',
        );
      }
    }
    try {
      await writer.closeOpenGatesForTerminal(
        sessionId: session.id,
        trigger: GateCloseCause.sessionTerminal,
        disposition: GateSweepSessionDisposition.done,
      );
    } on Object catch (error) {
      failures.add('gates');
      _onOrphan('teardown replay ${session.id}: gate sweep failed — $error');
    }
    _onOrphan(
      'teardown replay ${session.id}: replayed the positive-terminal tail '
      '(work bead ${workBeadId.isEmpty ? 'unknown' : workBeadId}'
      '${worktree == null ? ', no surviving worktree' : ''})'
      '${failures.isEmpty ? '' : ' — failed: ${failures.join(', ')}'}',
    );
    return TeardownReplayEntry(
      sessionId: session.id,
      disposition: GateSweepSessionDisposition.done,
      replayed: true,
      workBeadId: workBeadId.isEmpty ? null : workBeadId,
      reapedWorktree: worktree != null,
      failures: failures,
    );
  }

  List<Bead> _closedSessionsWithOpenMolecules(GraphSnapshot snapshot) {
    final ownerIds = <String>{};
    for (final bead in snapshot.beadsById.values) {
      if (bead.status == BeadStatus.closed) continue;
      final sessionId = switch (bead.issueType) {
        GridIssueTypes.molecule => bead.metadata['grid.circuit.session'],
        GridIssueTypes.step => bead.metadata[MoleculeStepKeys.session],
        _ => null,
      };
      if (sessionId is String && sessionId.isNotEmpty) {
        ownerIds.add(sessionId);
      }
    }
    return [
      for (final bead in snapshot.beadsById.values)
        if (bead.issueType == GridIssueTypes.session &&
            bead.status == BeadStatus.closed &&
            ownerIds.contains(bead.id))
          bead,
    ];
  }

  Future<RestartReport> reconcile() async {
    // 1. The barrier — respawns happen only after this completes.
    await _freshnessBarrier();

    // 2. List survivors. Fail closed on a probe error (do NOT assume "none").
    final rootedWorktrees = <({RootCheckout root, BeadWorktree worktree})>[];
    for (final root in _workRoots) {
      final worktrees = await _listWorktrees(root) ?? const <BeadWorktree>[];
      rootedWorktrees.addAll([
        for (final worktree in worktrees) (root: root, worktree: worktree),
      ]);
    }

    // 3. Build the session lookup from the OWNED state store, AFTER the
    //    barrier.
    final sessionByWorkBead = _projectOwnedSessions();
    final workBeads = _workSnapshot().beadsById;

    // 4. Reconcile each surviving worktree, collecting the sessions that BACK
    //    one. Only these are swept below: a session with no surviving worktree
    //    has nothing to re-mount into, and walking every owned session in the
    //    state store would turn a large backlog into an unbounded boot pass.
    final entries = <RestartEntry>[];
    final backed = <SessionProjection>[];
    final terminalBacked = <String>{};
    final terminalPairs = <({SessionProjection session, Bead workBead})>[];
    for (final rooted in rootedWorktrees) {
      final wt = rooted.worktree;
      final session = sessionByWorkBead[wt.beadId];
      var workTerminal = false;
      if (session != null) {
        backed.add(session);
        final workBead = workBeads[wt.beadId];
        if (!session.isTerminal && workBead != null && workBead.isClosed) {
          workTerminal = true;
          final sessionId = session.sessionId;
          if (sessionId != null && terminalBacked.add(sessionId)) {
            terminalPairs.add((session: session, workBead: workBead));
          }
        }
      }
      entries.add(
        await _reconcileWorktree(
          rooted.root,
          wt,
          workTerminal ? session!.copyWith(isTerminal: true) : session,
        ),
      );
    }

    // 5. SWEEP the molecule survivors' leased groups (tg-eli phase 1): the
    //    vendor owns every lease-key read and every clearing write; this pass
    //    only projects the candidates and binds the SAME guarded terminate
    //    path.
    final sweptLeases = await _sweepMoleculeLeases(
      backed,
      noRemountSessionIds: terminalBacked,
    );
    final settlements = <WorkTerminalSettlementReport>[];
    for (final pair in terminalPairs) {
      final sessionId = pair.session.sessionId!;
      String? failure;
      var settled = false;
      try {
        final writer = _writer;
        if (writer == null) {
          throw StateError('no station bead writer is wired');
        }
        await writer.settleSessionForTerminalWork(
          sessionId: sessionId,
          terminalWorkBead: pair.workBead,
        );
        settled = true;
      } on Object catch (error) {
        failure = '$error';
        _onOrphan(
          'restart work-terminal settlement $sessionId/${pair.workBead.id} '
          '(${StationBeadWriter.workTerminalReasonWorkBeadClosed}) failed — '
          '$error',
        );
      }
      if (settled) {
        // §2.3's `attempt.terminal(settled)` row at its INFERRED caller —
        // OUTSIDE the legacy settle's try, under its own guard: the binding
        // constraint says an append failure NEVER fails the legacy path, and
        // a derivation throw inside that try would report a settlement that
        // already COMMITTED as an orphan failure. The attempt id is RECOVERED
        // from the session's own `grid.lease.*` breadcrumb (§2.1's bounce
        // rule), so the record joins the P1 attempt row a prior boot's
        // `.started` genuinely appended and its `terminal:<attempt_id>` idem
        // key dedupes against it. A session that predates Stage 1 carries no
        // such key: it settles under a reconciler-minted id, payload-marked,
        // and sits outside the shadow window's comparable set by
        // construction. A recovery throw degrades to exactly that marked
        // mint — never to a reported failure.
        String? recovered;
        try {
          recovered = _recoverSessionAttemptId(sessionId);
        } on Object {
          recovered = null;
        }
        _recorder.sessionSettled(
          sessionId: sessionId,
          workBeadId: pair.workBead.id,
          attemptId: recovered,
          workTerminalReason:
              StationBeadWriter.workTerminalReasonWorkBeadClosed,
          reconcilerOriginated: true,
        );
      }
      settlements.add((
        sessionId: sessionId,
        workBeadId: pair.workBead.id,
        terminalReason: StationBeadWriter.workTerminalReasonWorkBeadClosed,
        failure: failure,
      ));
    }
    return RestartReport(
      entries,
      sweptLeases: sweptLeases,
      workTerminalSettlements: settlements,
    );
  }

  /// **The MOLECULE crash-recovery pass** (tg-eli phase 1 — since phase 2 the
  /// ONE process-identity reconciliation).
  ///
  /// Bounded-boot scope: every MOLECULE session that BACKS a surviving
  /// worktree is swept — TERMINAL ones included. A session with no surviving
  /// worktree stays out of scope: there is nothing to re-mount into, and
  /// walking the whole state store would make a large backlog an unbounded
  /// boot pass.
  ///
  /// Terminal and non-terminal sessions differ in ONE fact, stated per
  /// candidate: [LeaseSweepCandidate.willRemount]. A NON-terminal session will
  /// be driven again, so a live daemon its adopt proof vouches for is
  /// preserved for that re-mount. A TERMINAL session will never be driven
  /// again — no `startOrAdopt` is coming — so every live group it left is an
  /// orphan, daemon or job, and the vendor kills it through the same guarded
  /// path. A latched step (`complete`/`failed`/`gated`) is untouched either
  /// way: that skip lives in the vendor and this pass does not widen it.
  ///
  /// The candidates are projected from the SAME post-barrier state snapshot
  /// the session projection reads (no new bd query, no subscription — A39):
  /// every `type=step` bead stamped with an in-scope session's id, its
  /// metadata handed to the vendor VERBATIM. This reconciler never parses a
  /// lease key — the vendor decides completed-skip / dead-skip / adoptable /
  /// orphan, kills through the bound [terminateGroup] (the guard is never
  /// bypassed), clears its own breadcrumbs, and reports each kill LOUD.
  /// The attempt id a prior boot left on [sessionId]'s step beads (§2.1's
  /// bounce rule), read off the SAME post-barrier state snapshot everything
  /// else in this pass projects from — no new bd query, no subscription (A39).
  ///
  /// The recovery rides the VENDOR's `recoverAttemptId`, handed whole step-bead
  /// metadata — this pass stays lease-schema-ignorant (Nico's 2026-07-19
  /// ruling, structurally pinned): it names no breadcrumb key, and reads the
  /// answer off the returned BASIS instead. That helper takes the key directly
  /// rather than through the adopt parse, because settling needs the attempt's
  /// NAME, not a re-addressable identity: a breadcrumb whose pgid was lost
  /// still names a real attempt row.
  ///
  /// Null when no step bead of this session carries one at all — the caller
  /// then lets the recorder mint and MARK it, which is the honest account for
  /// a session that predates Stage 1.
  String? _recoverSessionAttemptId(String sessionId) {
    for (final bead in _stateSnapshot().beadsById.values) {
      if (bead.issueType != GridIssueTypes.step) continue;
      if (bead.metadata[MoleculeStepKeys.session] != sessionId) continue;
      final recovered = recoverAttemptId({
        for (final entry in bead.metadata.entries)
          if (entry.value != null) entry.key: '${entry.value}',
      });
      if (recovered.basis == AttemptIdBasis.breadcrumb) {
        return recovered.attemptId;
      }
    }
    return null;
  }

  Future<List<SweptLeaseGroup>> _sweepMoleculeLeases(
    Iterable<SessionProjection> sessions, {
    Set<String> noRemountSessionIds = const <String>{},
  }) async {
    final vendor = _leaseVendor;
    if (vendor == null) return const [];
    // Every MOLECULE session backing a surviving worktree, mapped to whether a
    // tree re-mount is still coming for it.
    final remountBySession = <String, bool>{};
    for (final session in sessions) {
      final id = session.sessionId;
      if (id == null || !session.isMolecule) continue;
      remountBySession[id] =
          !session.isTerminal && !noRemountSessionIds.contains(id);
    }
    if (remountBySession.isEmpty) return const [];

    final candidates = <LeaseSweepCandidate>[];
    for (final bead in _stateSnapshot().beadsById.values) {
      if (bead.issueType != GridIssueTypes.step) continue;
      final owner = bead.metadata[MoleculeStepKeys.session];
      if (owner is! String) continue;
      final willRemount = remountBySession[owner];
      if (willRemount == null) continue;
      candidates.add((
        stepBeadId: bead.id,
        willRemount: willRemount,
        // bd metadata is Map<String, dynamic> off the wire; the vendor's
        // breadcrumb codec reads flat strings.
        metadata: {
          for (final entry in bead.metadata.entries)
            if (entry.value != null) entry.key: '${entry.value}',
        },
      ));
    }
    if (candidates.isEmpty) return const [];

    return vendor.sweepOrphanedLeases(
      candidates: candidates,
      // The KILL GATE rides this reconciler's OWN real controller — the SAME
      // leader-pid evidence terminateGroup uses — so the sweep is armed
      // wherever the reconciler is. The vendor's adopt-liveness stays its own
      // deliberate D4 all-or-nothing wire and never gates a kill.
      alive: ({required int pgid, required int leaderPid}) =>
          _groups.processAlive(leaderPid),
      // The SAME guarded kill every other rung of this reconciler uses — the
      // `pgid <= 1`/own-group guard runs inside terminateGroup, never here.
      terminate: ({required int pgid, required int leaderPid}) =>
          terminateGroup(controller: _groups, pgid: pgid, leaderPid: leaderPid),
      onOrphan: _onOrphan,
    );
  }

  /// **The TEARDOWN orphan sweep** — the twin of [reconcile]: the boot pass
  /// reconciles SURVIVORS, this one reconciles STRAGGLERS.
  ///
  /// Call it AFTER the tree unmounted (`TreeOwner.dispose()` returned), which
  /// `GridHandle.teardown()` does. Unmount = kill, but the kill chain is
  /// FIRE-AND-FORGET (`unawaited(allocation.dispose())` →
  /// `unawaited(transport.stop(...))`), so on return the kills are merely IN
  /// FLIGHT: a runner that exits there sends no SIGTERM at all. This pass
  /// reconciles the station against ZERO-EXPECTED on the TRANSPORT's
  /// evidence: [RuntimeProvider.listRunning] under [sessionPrefix] — nothing
  /// may still be held once the tree unmounted; each straggler is
  /// [RuntimeProvider.stop]ped, and the stop is AWAITED.
  ///
  /// **The fence half retired (tg-eli phase 2).** The old second evidence
  /// kind — per-node `pgid`/`pid` cursor fences on the OWN non-terminal
  /// session beads — died with the flat cursor: a session's process identity
  /// is now the lease vendor's `grid.lease.*` breadcrumb, reconciled by the
  /// BOOT pass's molecule lease sweep on the next arm.
  /// [OrphanSweepReport.terminatedGroups] is therefore always empty.
  ///
  /// It RE-PASSES until [quietPasses] consecutive passes reap nothing, so an
  /// effect landing mid-sweep is still caught — bounded by [settleWindow]: a
  /// window that closes with work still landing is reported LOUD and
  /// `settled: false`, never a silent give-up.
  ///
  /// **Every reap is LOUD** ([onOrphan], required — there is no silent default):
  /// an orphan is an invariant violation with a concrete failure story (a leaked
  /// agent burning tokens against a worktree nobody owns), so it is never reaped
  /// quietly (the ADR-0008 D-6 guard principle). A clean teardown logs NOTHING.
  ///
  /// **Kills are SCOPED, never broad** (ADR-0006 coexistence — a live gc spawns
  /// its own agents beside us): only names the transport itself holds under
  /// [sessionPrefix] are stopped.
  ///
  /// *Detach is out of scope.* Zero-expected is exactly true today because
  /// nothing calls `Allocation.detach()` on unmount — the host's floor is
  /// `dispose` (KILL, ADR-0009 D4). A station that later arms detach must
  /// exclude its detached addresses; the LOUD log is what will surface it (a
  /// detached daemon would be reported reaped, by name).
  ///
  /// The transport + the owned prefix are parameters of THIS pass, not of the
  /// reconciler: the boot pass reconciles worktrees and sessions and owns no
  /// transport, and a caller cannot reach the sweep without naming both — so
  /// there is no silently-unwired transport half.
  Future<OrphanSweepReport> sweepOrphans({
    required RuntimeProvider transport,
    required String sessionPrefix,
    required void Function(String message) onOrphan,
    Duration pollInterval = const Duration(milliseconds: 50),
    Duration settleWindow = const Duration(seconds: 5),
    int quietPasses = 2,
  }) async {
    final stopped = <String>[];
    final terminated = <SweptGroup>[];
    final deadline = DateTime.now().add(settleWindow);
    var quiet = 0;

    while (quiet < quietPasses) {
      final reaped = await _sweepPass(
        transport: transport,
        sessionPrefix: sessionPrefix,
        onOrphan: onOrphan,
        stopped: stopped,
      );
      // A reap proves the station was still landing effects — start the quiet
      // count over, so a spawn that lands mid-sweep is never the last word.
      quiet = reaped ? 0 : quiet + 1;
      if (quiet >= quietPasses) break;

      if (!DateTime.now().isBefore(deadline)) {
        final report = OrphanSweepReport(
          stoppedSessions: stopped,
          terminatedGroups: terminated,
          settled: false,
        );
        onOrphan(
          'orphan sweep: the settle window (${settleWindow.inMilliseconds}ms) '
          'closed before the station went quiet — effects are still landing '
          'after the unmount. $report',
        );
        return report;
      }
      await Future<void>.delayed(pollInterval);
    }

    final report = OrphanSweepReport(
      stoppedSessions: stopped,
      terminatedGroups: terminated,
      settled: true,
    );
    if (!report.isClean) onOrphan('orphan sweep: teardown reaped $report');
    return report;
  }

  /// ONE reconcile-against-zero-expected pass over the TRANSPORT's evidence.
  /// Returns whether it reaped anything (a reap resets the quiet counter).
  Future<bool> _sweepPass({
    required RuntimeProvider transport,
    required String sessionPrefix,
    required void Function(String message) onOrphan,
    required List<String> stopped,
  }) async {
    var reaped = false;

    // ZERO sessions are expected once the tree unmounted. Anything the
    // transport still holds under our OWN prefix either spawned into the
    // teardown window or had its fire-and-forget `stop` never complete. Stop
    // it — and AWAIT the stop, unlike the unmount's `unawaited(...)` chain.
    for (final name in transport.listRunning(sessionPrefix)) {
      onOrphan(
        'orphan sweep: session "$name" SURVIVED the unmount — stopping its '
        'process group',
      );
      await transport.stop(name);
      stopped.add(name);
      reaped = true;
    }
    return reaped;
  }

  /// Projects the OWNED sessions from the post-barrier state snapshot,
  /// keyed by the `work_bead` they drive. Only `type=session` beads are
  /// projected; a session with an empty `work_bead` is skipped (it joins to no
  /// worktree). A later session for the same work bead wins (last writer in
  /// iteration order) — the state store holds one live session per work bead.
  Map<String, SessionProjection> _projectOwnedSessions() {
    final out = <String, SessionProjection>{};
    // How many session beads this pass saw per work-bead key — the
    // `incumbentAdjudication` trigger below. The map itself keeps only the
    // last writer, so the count is the only place the multiplicity survives.
    final beadsPerKey = <String, int>{};
    for (final bead in _stateSnapshot().beadsById.values) {
      if (bead.issueType != GridIssueTypes.session) continue;
      final projection = projectSession(bead);
      if (projection.workBeadId.isEmpty) continue;
      beadsPerKey[projection.workBeadId] =
          (beadsPerKey[projection.workBeadId] ?? 0) + 1;
      out[projection.workBeadId] = projection;
    }
    _observeDualRead(out, beadsPerKey);
    return out;
  }

  /// The reconciler's half of the session-axis dual read (cut-wiring C2) — the
  /// SAME comparator the bridge runs, over the SAME identity rule, folding
  /// into the SAME accounting.
  ///
  /// One class is this pass's alone: when two same-bead sessions coexist, the
  /// legacy incumbent picks its winner by MAP ITERATION ORDER (the doc on
  /// [_projectOwnedSessions] says so in as many words). A mismatch there is
  /// `incumbentAdjudication` — logged with both identities and ADJUDICATED,
  /// never auto-presumed against the fold, because the incumbent rule ("the
  /// fold is presumed wrong") only applies where the incumbent is
  /// DETERMINISTIC. Everything else classifies exactly as it does in the
  /// bridge.
  ///
  /// Read-only and non-fatal by construction: it counts and flares, and no
  /// disposition anywhere in this pass consults it.
  void _observeDualRead(
    Map<String, SessionProjection> sessions,
    Map<String, int> beadsPerKey,
  ) {
    final accounting = _dualRead;
    final snapshot = _headSnapshot?.call();
    if (accounting == null || snapshot == null) return;
    if (snapshot.health != TrajectorySnapshotHealth.live) {
      accounting.fallbacks += sessions.length;
      return;
    }
    for (final entry in sessions.entries) {
      final legacy = entry.value;
      final sessionId = legacy.sessionId;
      if (sessionId == null || sessionId.isEmpty) continue;
      final head = snapshot.bySessionId(sessionId);
      if (head == null) {
        accounting.fallbacks += 1;
        final miss = classifyDualReadMiss(legacy, snapshot.firstEpochClaimedAt);
        if (miss.nullStartedAt) accounting.nullStartedAt += 1;
        switch (miss.era) {
          case DualReadMissClass.postEpoch:
            accounting.missPostEpoch += 1;
          case DualReadMissClass.legacyEra:
            accounting.missLegacyEra += 1;
        }
        continue;
      }
      accounting.hits += 1;
      final comparison = compareHeadToProjection(legacy, head);
      // ORDER-DEPENDENT INCUMBENT: more than one session bead landed on this
      // work-bead key, so `out[key] = projection` discarded some of them by
      // iteration order. Any mismatch here is adjudicated, not counted.
      if ((beadsPerKey[entry.key] ?? 0) > 1) {
        if (comparison.classification == DualReadClass.match) continue;
        accounting.record(
          DualReadComparison(
            sessionId: comparison.sessionId,
            workBeadId: comparison.workBeadId,
            classification: DualReadClass.incumbentAdjudication,
            mismatches: comparison.mismatches,
          ),
        );
        _onOrphan(
          'dual-read incumbent adjudication ${entry.key}: legacy kept session '
          '$sessionId by map iteration order over '
          '${beadsPerKey[entry.key]} candidates; fold reads '
          '${comparison.mismatches.join(', ')}',
        );
        continue;
      }
      if (accounting.record(comparison) && comparison.isDivergence) {
        for (final mismatch in comparison.mismatches) {
          _onFlare?.call(kDualReadDivergenceFlare, {
            'axis': 'session',
            'scope': 'restart-reconciler',
            'work_bead': comparison.workBeadId,
            'session_id': comparison.sessionId,
            'field': mismatch.field,
            'fold_value': mismatch.foldValue,
            'legacy_value': mismatch.legacyValue,
            'snapshot_version': '${snapshot.version}',
          });
        }
      }
    }
  }

  /// Reconciles a single [wt] against its OWNED [session] (null when the
  /// work bead has no session in the state store).
  Future<RestartEntry> _reconcileWorktree(
    RootCheckout root,
    BeadWorktree wt,
    SessionProjection? session,
  ) async {
    // SKIP (done): the OWNED session reached a positive terminal — reap the
    // worktree; do not respawn. Fires even for a FOREIGN wt.beadId because
    // the outcome marker is on the_grid's own session bead (A40/A37). Any
    // leased groups a terminal MOLECULE session left are swept in step 5
    // (see [_sweepMoleculeLeases]) — the reap runs first and the kill is
    // keyed by pgid, not by the directory just removed; a HISTORICAL flat
    // session's recorded groups are inert metadata this pass never parses.
    if (session != null && session.isTerminal) {
      final outcome = await _reapWorktree(root: root, worktree: wt);
      return RestartEntry(
        worktree: wt,
        disposition: RestartDisposition.skipped,
        sessionId: session.sessionId,
        reapOutcome: outcome,
      );
    }

    // A live (non-terminal) session — respawn-pending. Its process identity,
    // if any survived, is the lease vendor's breadcrumb; the molecule lease
    // sweep (reconcile step 5) terminates any orphan group so the respawn
    // cannot double-run. The agent's commit is durable (committed local-first
    // into the worktree), so a bounded re-run is not a correctness violation.
    if (session != null) {
      return RestartEntry(
        worktree: wt,
        disposition: RestartDisposition.respawnPending,
        sessionId: session.sessionId,
      );
    }

    // No record ⇒ respawn-pending (fresh / both-markers-miss). Leave the
    // worktree; the tree mounts, mints a fresh session, and respawns in the
    // existing worktree.
    return RestartEntry(
      worktree: wt,
      disposition: RestartDisposition.respawnPending,
    );
  }
}
