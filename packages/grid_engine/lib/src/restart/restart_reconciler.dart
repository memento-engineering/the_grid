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
///    read-only work bead the_grid could never stamp, because the phase cursor
///    lives on the_grid's OWN session bead (A40/A37), not the work bead. (The
///    v1 bug: an unwritable foreign bead could never show `done`, so it was
///    always respawned.)
///  - **KILL a still-alive orphan** — its session is live (non-terminal) and
///    carries a `pgid`: the prior incarnation's agent process group may still be
///    running. Terminate the group (so the respawn does not double-run), then
///    mark the worktree respawn-pending — the kernel re-mounts and respawns it
///    in the existing worktree.
///  - **RESPAWN the rest** — a live session with no kill target, or a worktree
///    with no session record at all, is left in place and marked respawn-pending
///    for the tree to re-mount.
///
/// **Ordering invariant:** nothing is decided on stale state. [reconcile] awaits
/// the injected [RestartReconciler.freshnessBarrier] (a COMPLETED re-query of
/// the read + state runtimes) BEFORE it lists worktrees, projects cursors, or
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
///    worktree isolation, and the freshness barrier that precedes every kill. A
///    `pgid <= 1` (a recycled/own-group residual) returns
///    [GroupTerminateResult.refusedUnsafe] and the bead STILL stays
///    respawn-pending — we never try to bypass the guard.
///  - *Both-markers-miss re-run.* A crash that left NEITHER a terminal session
///    NOR a live-pgid record (e.g. the session bead never got its identity
///    stamped) leaves the worktree respawn-pending: the tree mounts, mints a
///    fresh session, and re-runs the agent in the SAME worktree. Because the
///    agent's commit is durable (committed local-first into the worktree), this
///    is a bounded re-run, not a correctness violation.
///  - *Adopt-a-live-process is DEFERRED* to a later crash-safety track — this
///    reconciler kills-and-respawns rather than re-attaching to a survivor.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import '../domain/session_bead.dart';
import '../domain/session_projection.dart';
import '../sdk/cursor.dart';
import '../sdk/circuit.dart';

/// The adopt-decision seam (ADR-0009 D4, Track D): given a surviving LIVE node,
/// returns whether the reconciler should ADOPT it — leave the group running for
/// the re-mounted tree to reattach — rather than kill-and-respawn. This is the
/// composer-supplied domain half of the freshness proof (a daemon probes its
/// endpoint + checks the token echoes); the engine already supplied the
/// pgid-alive half. **No-adopt-on-faith**: the offline default is `false`, so a
/// node the composer cannot prove is killed-and-respawned, never left to leak.
/// The engine stays opinion-free — it never names the daemon or its endpoint.
typedef AdoptProof =
    Future<bool> Function(
      BeadWorktree worktree,
      SessionProjection session,
      String nodePath,
      NodeCursor node,
    );

/// The offline adopt default — no composer proof wired, so nothing is adopted
/// (respawn-or-skip, today's behavior). No-adopt-on-faith.
Future<bool> _neverAdopt(
  BeadWorktree worktree,
  SessionProjection session,
  String nodePath,
  NodeCursor node,
) async => false;

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
enum RestartDisposition {
  /// The OWNED session reached a positive terminal — the work is done. The
  /// worktree was handed to the [ReapWorktree] seam; the bead does NOT respawn.
  /// A done session's still-live groups (detached daemons) are swept (killed)
  /// first — nobody re-adopts a completed session (D4 orphan sweep).
  skipped,

  /// A live (non-terminal) session whose live group(s) the [AdoptProof] accepted
  /// — the group is LEFT RUNNING for the re-mounted tree to reattach (D4). NOT
  /// killed, NOT reaped, and NOT respawned (the tree's `startOrAdopt` reattaches
  /// it). This bucket is respawn-free.
  adopted,

  /// A live (non-terminal) session carried a usable `pgid` + leader pid and the
  /// orphan group was reconciled so the respawn cannot double-run — the bead is
  /// then respawn-pending. This bucket absorbs the `alreadyGone` outcome too (an
  /// orphan that had already exited: no signal was sent, but the no-double-run
  /// guarantee holds all the same); the exact [GroupTerminateResult] is
  /// preserved on `RestartEntry.terminateResult` for a caller that must
  /// distinguish "we signalled" from "it was already gone".
  killed,

  /// A live session carried a `pgid` that the [terminateGroup] safety guard
  /// refused (`pgid <= 1` or the supervisor's own group) — NO signal was sent.
  /// The bead is STILL respawn-pending (a documented recycled-pgid/own-group
  /// residual); the guard is never bypassed.
  refusedUnsafe,

  /// Left in place for the tree to re-mount + respawn: either a live session
  /// with no usable kill target (no `pgid`/leader pid on record), or a worktree
  /// with no session record at all (the both-markers-miss residual).
  respawnPending,
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
class RestartReport {
  RestartReport(List<RestartEntry> entries)
    : entries = List.unmodifiable(entries),
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

  /// The total number of beads the tree must respawn on re-mount: everything
  /// except the skipped (done) beads AND the adopted (reattached) survivors.
  /// [refusedUnsafe] is included.
  int get respawnCount => entries.length - skipped.length - adopted.length;

  @override
  String toString() =>
      'RestartReport(skipped: ${skipped.length}, adopted: ${adopted.length}, '
      'killed: ${killed.length}, refusedUnsafe: ${refusedUnsafe.length}, '
      'respawnPending: ${respawnPending.length}, '
      'respawnCount: $respawnCount)';
}

/// One process group the orphan sweep walked: the node that recorded it, its
/// `pgid` + leader `pid`, and the REAL guarded [terminateGroup] outcome — so a
/// caller (and a test) can assert WHICH rung fired without scraping logs.
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

  /// The persisted-fence process groups still alive after the unmount,
  /// terminated by the sweep (in reap order).
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

/// Reconciles the restart survivors (worktrees + owned session cursors) into a
/// respawn-or-skip plan, BEFORE the kernel re-mounts the tree.
///
/// All dependencies are injected so the whole pass runs offline against fakes:
/// the [ListBeadWorktrees] + [ReapWorktree] seams (bound to the grid git
/// service's `listBeadWorktrees`/`reap` by the composing extension/runtime —
/// narrow functions so the engine never names the concrete VCS service,
/// ADR-0007 §1), the [RootCheckout] under which the worktrees live, the
/// [ProcessGroupController] (the orphan-kill seam — kept REAL via
/// [terminateGroup] so its `pgid <= 1` guard is genuinely exercised), the
/// [freshnessBarrier] (a completed re-query), and a [stateSnapshot] reader (the
/// state-store snapshot read AFTER the barrier, to project the OWNED session
/// cursors).
class RestartReconciler {
  RestartReconciler({
    required ListBeadWorktrees listWorktrees,
    required ReapWorktree reapWorktree,
    required RootCheckout workRoot,
    required ProcessGroupController groups,
    required Future<void> Function() freshnessBarrier,
    required GraphSnapshot Function() stateSnapshot,
    AdoptProof? adoptProof,
  }) : _listWorktrees = listWorktrees,
       _reapWorktree = reapWorktree,
       _workRoot = workRoot,
       _groups = groups,
       _freshnessBarrier = freshnessBarrier,
       _stateSnapshot = stateSnapshot,
       _adoptProof = adoptProof ?? _neverAdopt;

  final ListBeadWorktrees _listWorktrees;
  final ReapWorktree _reapWorktree;
  final RootCheckout _workRoot;
  final ProcessGroupController _groups;

  /// The composer-supplied adopt-decision (D4). Offline default: never adopt
  /// (respawn-or-skip). No-adopt-on-faith.
  final AdoptProof _adoptProof;

  /// A COMPLETED re-query of the read + state runtimes — awaited FIRST so no
  /// decision is made on stale state. Injected so it is fake-driveable.
  final Future<void> Function() _freshnessBarrier;

  /// The state-store snapshot reader (the owned `session` beads), read AFTER the
  /// barrier completes so the projected cursors reflect the post-barrier state.
  final GraphSnapshot Function() _stateSnapshot;

  /// Walks the restart survivors and produces the respawn-or-skip plan.
  ///
  /// 1. Await the freshness barrier (nothing is decided on stale state).
  /// 2. List the per-bead worktrees (fail closed: a null probe ⇒ no worktrees
  ///    reconciled this pass).
  /// 3. Project the OWNED session cursors from the post-barrier state snapshot,
  ///    keyed by `work_bead` (so SKIP fires for a foreign work bead).
  /// 4. For each worktree: SKIP-and-reap a terminal session; KILL-and-respawn a
  ///    live orphan with a usable kill target; else leave it respawn-pending.
  Future<RestartReport> reconcile() async {
    // 1. The barrier — respawns happen only after this completes.
    await _freshnessBarrier();

    // 2. List survivors. Fail closed on a probe error (do NOT assume "none").
    final worktrees = await _listWorktrees(_workRoot) ?? const [];

    // 3. Build the cursor lookup from the OWNED state store, AFTER the barrier.
    final cursorByWorkBead = _projectOwnedCursors();

    final entries = <RestartEntry>[];
    for (final wt in worktrees) {
      final session = cursorByWorkBead[wt.beadId];
      entries.add(await _reconcileWorktree(wt, session));
    }
    return RestartReport(entries);
  }

  /// Projects the OWNED session cursors from the post-barrier state snapshot,
  /// keyed by the `work_bead` they drive. Only `type=session` beads are
  /// projected; a session with an empty `work_bead` is skipped (it joins to no
  /// worktree). A later session for the same work bead wins (last writer in
  /// iteration order) — the state store holds one live session per work bead.
  Map<String, SessionProjection> _projectOwnedCursors() {
    final out = <String, SessionProjection>{};
    for (final bead in _stateSnapshot().beadsById.values) {
      if (bead.issueType != IssueType.session) continue;
      final projection = projectSession(bead);
      if (projection.workBeadId.isEmpty) continue;
      out[projection.workBeadId] = projection;
    }
    return out;
  }

  /// Reconciles a single [wt] against its OWNED [session] cursor (null when the
  /// work bead has no session in the state store).
  Future<RestartEntry> _reconcileWorktree(
    BeadWorktree wt,
    SessionProjection? session,
  ) async {
    // SKIP (done): the OWNED session reached a positive terminal. First SWEEP
    // any still-live groups it left running (a detached daemon on a completed
    // session — nobody re-adopts it, D4 orphan sweep), THEN reap the worktree;
    // do not respawn. Fires even for a FOREIGN wt.beadId because the cursor is on
    // the_grid's own session bead (A40/A37).
    if (session != null && session.isTerminal) {
      await _sweepLiveGroups(session);
      final outcome = await _reapWorktree(root: _workRoot, worktree: wt);
      return RestartEntry(
        worktree: wt,
        disposition: RestartDisposition.skipped,
        sessionId: session.sessionId,
        reapOutcome: outcome,
      );
    }

    // KILL orphan + respawn-pending: a live (non-terminal) session. If it
    // carries a usable kill target, terminate the prior group so the respawn
    // does not double-run.
    if (session != null) {
      return _killOrphanThenRespawn(wt, session);
    }

    // No record ⇒ respawn-pending (fresh / both-markers-miss): can't kill (no
    // pgid on record). Leave the worktree; the tree mounts, mints a fresh
    // session, and respawns in the existing worktree.
    return RestartEntry(
      worktree: wt,
      disposition: RestartDisposition.respawnPending,
    );
  }

  /// A live, non-terminal [session]: for EVERY live group it carries (D-4 —
  /// per-node, not a single scalar pgid), either ADOPT it (leave it running for
  /// the re-mounted tree to reattach — [AdoptProof] accepted it) or terminate it
  /// (the crash-orphan case, so the respawn does not double-run).
  ///
  /// A reentrant Burn has MANY concurrent live groups (peripheral + central
  /// daemons, advertisers, the coordinator). The per-node cursor records each
  /// one's `pgid`/`pid`/`token`; this consults the composer's [AdoptProof] per
  /// live node (the domain freshness half — offline default: never, so every
  /// live group is killed, today's respawn-or-skip), then runs the REAL guarded
  /// [terminateGroup] on each NON-adopted group. The legacy single-process path
  /// (a scalar `pgid` on the session) is the fallback when no per-node target is
  /// recorded. Worktree reap stays per-bead.
  ///
  /// Aggregation: ANY group killed ⇒ `killed` (or `refusedUnsafe` if all kills
  /// were guard-refused) → respawn-pending; else every live group was adopted ⇒
  /// `adopted` (respawn-free — the tree reattaches).
  Future<RestartEntry> _killOrphanThenRespawn(
    BeadWorktree wt,
    SessionProjection session,
  ) async {
    final targets = _liveGroups(session);

    // No usable kill target anywhere (no pgid+leader-pid on any live node, nor a
    // scalar): we cannot run the guarded terminate. Leave it respawn-pending —
    // the agent's commit is durable, so a bounded re-run is not a correctness
    // violation (the both-markers-partial residual).
    if (targets.isEmpty) {
      return RestartEntry(
        worktree: wt,
        disposition: RestartDisposition.respawnPending,
        sessionId: session.sessionId,
      );
    }

    // Per live group: ADOPT (leave) if the composer proves it fresh; else run
    // the REAL guarded terminate — never bypassing the `pgid <= 1`/own-group
    // safety guard. No-adopt-on-faith: an unproven group is always killed, never
    // left to leak.
    final killResults = <GroupTerminateResult>[];
    for (final t in targets) {
      if (await _adoptProof(wt, session, t.nodePath, t.node)) {
        continue; // ADOPT: leave this group running for the tree to reattach.
      }
      killResults.add(
        await terminateGroup(
          controller: _groups,
          pgid: t.pgid,
          leaderPid: t.pid,
        ),
      );
    }

    // Any kill ⇒ the worktree respawns (killed, or refusedUnsafe if every kill
    // was guard-refused). The representative result is the first non-refusal (or
    // the refusal when all refused) — single-target entries keep their exact
    // result.
    if (killResults.isNotEmpty) {
      final firstSignalled = killResults
          .where((r) => r != GroupTerminateResult.refusedUnsafe)
          .firstOrNull;
      final disposition = firstSignalled != null
          ? RestartDisposition.killed
          : RestartDisposition.refusedUnsafe;
      return RestartEntry(
        worktree: wt,
        disposition: disposition,
        sessionId: session.sessionId,
        terminateResult: firstSignalled ?? GroupTerminateResult.refusedUnsafe,
      );
    }

    // No kills — every live group was ADOPTED (left running for the tree to
    // reattach). Respawn-free.
    return RestartEntry(
      worktree: wt,
      disposition: RestartDisposition.adopted,
      sessionId: session.sessionId,
    );
  }

  /// Terminates EVERY live group a [session] left running — **the orphan
  /// sweep** (D4). A done session is never adopted, so every live group is a
  /// leak; each is reaped with the REAL guarded [terminateGroup] (a `pgid <= 1`/
  /// own-group group is left, the guard never bypassed — a bounded residual).
  ///
  /// THE shared mechanism of both sweep moments: the boot pass runs it over a
  /// TERMINAL session (a detached daemon nobody re-adopts) and ignores the
  /// result; [sweepOrphans] runs it over the OWN NON-terminal sessions at
  /// teardown and reports each outcome LOUD. Returns the per-group outcomes so
  /// the two can never drift.
  Future<List<SweptGroup>> _sweepLiveGroups(SessionProjection session) async {
    final swept = <SweptGroup>[];
    for (final t in _liveGroups(session)) {
      final result = await terminateGroup(
        controller: _groups,
        pgid: t.pgid,
        leaderPid: t.pid,
      );
      swept.add((
        nodePath: t.nodePath,
        pgid: t.pgid,
        pid: t.pid,
        result: result,
      ));
    }
    return swept;
  }

  /// The live process groups of [session] — the per-node cursor's live groups
  /// (D-4), or the legacy scalar pgid when no per-node target is recorded. A
  /// group needs BOTH a `pgid` and a leader `pid` (the liveness fence); a pgid
  /// without a pid is skipped (no usable target). Deduped by pgid. Each carries
  /// its `nodePath` + `NodeCursor` so the [AdoptProof] can probe it.
  List<({String nodePath, NodeCursor node, int pgid, int pid})> _liveGroups(
    SessionProjection session,
  ) {
    final out = <({String nodePath, NodeCursor node, int pgid, int pid})>[];
    final seen = <int>{};
    session.cursor.forEach((path, node) {
      final live =
          node.state == StepState.running || node.state == StepState.ready;
      final pgid = node.pgid;
      final pid = node.pid;
      if (live && pgid != null && pid != null && seen.add(pgid)) {
        out.add((nodePath: path, node: node, pgid: pgid, pid: pid));
      }
    });
    // Legacy single-process fallback (the pre-Track-H carrier) — only when the
    // per-node cursor recorded no live target.
    if (out.isEmpty) {
      final pgid = session.pgid;
      final pid = session.pid;
      if (pgid != null && pid != null) {
        out.add((
          nodePath: '',
          node: NodeCursor(pgid: pgid, pid: pid, token: session.token),
          pgid: pgid,
          pid: pid,
        ));
      }
    }
    return out;
  }
}
