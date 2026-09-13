/// The worktree-outstanding mount-eligibility clause (cut-wiring §W2.4 W2-B).
///
/// **Why the barrier exists.** Under the cut a stranded worktree has no bead
/// carrier left to betray it — the legacy inline reap is retired, so the only
/// record that a terminal session still holds a provisioned worktree lives in
/// the fold. Mount eligibility therefore reads the fold: a candidate whose
/// P6 row still says `worktree_state='live'` under a TERMINAL session is
/// refused, so the stale-adopt window the retirement opens is closed by the
/// same wave that opens it.
///
/// **The join and its multiplicity rule.** P6 (`proj_process_identity`)
/// carries no work-bead column and no index on one, so "this bead has a live
/// P6 row" is a JOIN: P6.`session_id` → P1.`session_id` → P1.`work_bead_id`,
/// served by P1's `ix_bead`. Under the accepted open-retired P1 shape one bead
/// legitimately owns MANY P1 rows across rounds, so the multiplicity rule is
/// decision-bearing and is fixed here: **every P1 row for the bead counts,
/// retired rounds INCLUDED** — a stranded worktree on a retired round is
/// exactly the class the barrier exists to catch. THE BUILD CHOICE TAKEN: the
/// join is evaluated IN-CLAUSE over the ambient mirrors, indexed once per read
/// ([WorktreeOutstandingRead] builds P1's by-bead index at construction). No
/// derived bead key was added to the P6 mirror at seed time.
///
/// **Terminality is an OR, and that is what makes the read complete at every
/// instant**: P1 `status='closed'` OR the joined projection's `isTerminal` —
/// the KEPT ledger close. During the heal grace the ledger half fires alone;
/// after the heal both do.
///
/// **Staleness fails closed only on a WEDGED harness.** The clause reads the
/// tick-stamped mirror heartbeat and refuses only after no beat for three tick
/// intervals — the same grace the heal uses. An idle-healthy station admits.
/// The heartbeat, and NOT the mirror's health enum, is the whole staleness
/// rule: a harness that leaves `live` stops beating, so a compromised mirror
/// reaches the same wedged refusal by the same grace rather than disarming the
/// barrier it is the reason for.
library;

import 'package:grid_runtime/grid_runtime.dart' show kWorktreeOutstandingClause;
import 'package:meta/meta.dart';

import 'mount_eligibility.dart';
import 'session_projection.dart';
import 'trajectory_views.dart';

// The clause name — `kWorktreeOutstandingClause`, defined ONCE beside the
// record vocabulary in grid_runtime and re-exported here, so the gate, the
// refusal record and the restoration query can never drift apart.
export 'package:grid_runtime/grid_runtime.dart' show kWorktreeOutstandingClause;

/// How many missed tick intervals make the mirror heartbeat WEDGED.
const int kWorktreeOutstandingStaleTicks = 3;

/// Three tick intervals at the shipped 30 s cadence — deliberately the same
/// 90 s the terminal-reconcile heal waits, because both answer the same
/// question: has the harness stopped, or is the station merely idle?
const Duration kWorktreeOutstandingStaleAfter = Duration(seconds: 90);

/// The P6 `worktree_state` value that means "no reap record has landed".
const String kWorktreeStateLive = 'live';

/// Why a session counted as terminal for the barrier.
enum WorktreeOutstandingBasis {
  /// P1 says `status='closed'`.
  p1Closed,

  /// The joined projection says `isTerminal` — the KEPT ledger close, which
  /// is the half that fires during the heal grace.
  ledgerTerminal,

  /// Both halves agree — the steady state after the heal.
  both;

  String get wire => switch (this) {
    WorktreeOutstandingBasis.p1Closed => 'p1-closed',
    WorktreeOutstandingBasis.ledgerTerminal => 'ledger-terminal',
    WorktreeOutstandingBasis.both => 'p1-closed+ledger-terminal',
  };
}

/// One terminal session of the candidate bead that still holds a worktree.
@immutable
final class OutstandingWorktree {
  const OutstandingWorktree({
    required this.sessionId,
    required this.worktree,
    required this.basis,
  });

  final String sessionId;
  final String worktree;
  final WorktreeOutstandingBasis basis;

  @override
  String toString() =>
      'OutstandingWorktree($sessionId, $worktree, ${basis.wire})';
}

/// The per-pass read the clause joins over: the ambient P6 and P1 mirrors,
/// plus the heartbeat rule.
///
/// Immutable and pre-indexed: P1's rows are grouped by `work_bead_id` ONCE
/// (the in-memory stand-in for `ix_bead`) so the clause stays a synchronous
/// per-candidate lookup rather than a scan per candidate.
@immutable
final class WorktreeOutstandingRead {
  /// Builds the read over the two ambient mirrors.
  ///
  /// A null P6 mirror is the ONLY thing that disarms the read: an offline or
  /// trajectory-less composition has no fold to consult, and a clause with no
  /// fold refuses nothing.
  ///
  /// **A non-`live` mirror health does NOT disarm** — that would be a
  /// fail-OPEN on exactly the case the barrier exists for. Nothing else gates
  /// admission on mirror health: the compromised latch
  /// (`_latchMirrorCompromised`) is reached from the mode latch, the fence-out,
  /// the halt and the degrade WITHOUT `_haltAdmission`, which only a
  /// decision-bearing drop or suppression reaches, so a harness that latches
  /// its mirrors compromised on an empty append queue leaves
  /// `TrajectoryAdmissionHalt` unlatched. If health disarmed the barrier, that
  /// harness would re-mount every stranded worktree under the cut.
  ///
  /// The rule the bead fixes is the HEARTBEAT rule, and it covers this case by
  /// construction: a harness that leaves `live` mode returns before
  /// `noteTickAt` (grid_sdk `trajectory_harness.dart`, the mode latch in
  /// `_onTickPass`), so the beat freezes and the read goes wedged after three
  /// tick intervals — fail-CLOSED, after the same grace the heal uses.
  factory WorktreeOutstandingRead({
    TrajectoryProcessIdentitySnapshot? processIdentities,
    TrajectoryHeadSnapshot? heads,
    Duration staleAfter = kWorktreeOutstandingStaleAfter,
  }) {
    if (processIdentities == null) {
      return const WorktreeOutstandingRead.disarmed();
    }
    final headsByWorkBead = <String, List<SessionHeadView>>{};
    if (heads != null) {
      for (final row in heads.rows) {
        (headsByWorkBead[row.workBeadId] ??= <SessionHeadView>[]).add(row);
      }
    }
    return WorktreeOutstandingRead._(
      processIdentities: processIdentities,
      headsByWorkBead: headsByWorkBead,
      // Published only after a tick pass actually RAN — a skipped pass (busy,
      // fenced out, halted, disposed) publishes no beat, which is why three
      // skipped intervals fail closed rather than pretending the fold is
      // fresh. The seed instant is the boot's first beat, so a freshly seeded
      // mirror is healthy rather than wedged.
      heartbeatAt: processIdentities.lastTickAt ?? processIdentities.seededAt,
      health: processIdentities.health,
      staleAfter: staleAfter,
    );
  }

  const WorktreeOutstandingRead._({
    required TrajectoryProcessIdentitySnapshot? processIdentities,
    required Map<String, List<SessionHeadView>> headsByWorkBead,
    required this.heartbeatAt,
    required this.health,
    required this.staleAfter,
  }) : _processIdentities = processIdentities,
       _headsByWorkBead = headsByWorkBead;

  /// The read a composition with no P6 mirror gets: the clause evaluates to
  /// eligible for every candidate and never reports a staleness refusal.
  const WorktreeOutstandingRead.disarmed()
    : this._(
        processIdentities: null,
        headsByWorkBead: const <String, List<SessionHeadView>>{},
        heartbeatAt: null,
        health: null,
        staleAfter: kWorktreeOutstandingStaleAfter,
      );

  final TrajectoryProcessIdentitySnapshot? _processIdentities;
  final Map<String, List<SessionHeadView>> _headsByWorkBead;

  /// The tick-stamped mirror heartbeat — `lastTickAt`, or the seed instant
  /// before the first tick pass has run.
  final DateTime? heartbeatAt;

  /// The P6 mirror's health, REPORTED in the wedged detail and never a gate of
  /// its own: health decides nothing here, the heartbeat does.
  final TrajectorySnapshotHealth? health;

  /// How long without a beat before the clause calls the harness wedged.
  final Duration staleAfter;

  /// Whether the barrier has a fold to read at all.
  bool get armed => _processIdentities != null;

  /// Every P1 row for [workBeadId] — retired rounds INCLUDED (the multiplicity
  /// rule). `work_bead_id` is immutable in P1, so a `#rN` re-key on the bd
  /// side never moves a retired round out of this list.
  List<SessionHeadView> headsFor(String workBeadId) =>
      _headsByWorkBead[workBeadId] ?? const <SessionHeadView>[];

  /// The live worktree paths P6 still holds for [sessionId].
  ///
  /// A `live` row with no path has no worktree to strand — the same predicate
  /// the reaped-backfill obligation uses (`worktree IS NOT NULL`).
  List<String> liveWorktreesFor(String sessionId) {
    final identities = _processIdentities;
    if (identities == null) return const <String>[];
    final paths = <String>[];
    for (final row in identities.bySessionId(sessionId)) {
      if (row.worktreeState != kWorktreeStateLive) continue;
      final worktree = row.worktree;
      if (worktree == null || worktree.isEmpty) continue;
      paths.add(worktree);
    }
    return paths;
  }

  /// Whether the heartbeat says the harness is wedged at [now].
  bool isWedgedAt(DateTime now) {
    if (!armed) return false;
    final beat = heartbeatAt;
    if (beat == null) return true;
    return now.toUtc().difference(beat.toUtc()) > staleAfter;
  }
}

/// What the barrier found for one candidate — the value both the eligibility
/// verdict and the observe-form counter are derived from.
@immutable
final class WorktreeOutstandingFinding {
  const WorktreeOutstandingFinding({
    required this.workBeadId,
    required this.refuse,
    this.detail,
    this.snapshotRev,
    this.wedged = false,
    this.outstanding = const <OutstandingWorktree>[],
  });

  /// The clean finding — nothing outstanding, nothing to refuse.
  const WorktreeOutstandingFinding.clear(
    String workBeadId, {
    String? snapshotRev,
  }) : this(workBeadId: workBeadId, refuse: false, snapshotRev: snapshotRev);

  final String workBeadId;

  /// The predicate's verdict. Under the observe form the verdict is COUNTED
  /// and eligibility is left alone; the finding itself is identical.
  final bool refuse;

  /// The clause detail string — `worktree-outstanding: …`, whose prefix before
  /// the first colon is the clause NAME the refusal is reported under.
  final String? detail;

  /// The bead-scoped eligibility basis revision this evaluation read, or null
  /// when no revision is exposed (the refusal record does not arm without it).
  final String? snapshotRev;

  /// The refusal came from the wedged-harness rule, not from a real row.
  final bool wedged;

  /// The (session, worktree) pairs that made the finding, sorted.
  final List<OutstandingWorktree> outstanding;

  /// The clause NAME — the `<clause>` hole of the ratified refusal key.
  String get clause => kWorktreeOutstandingClause;
}

/// Evaluates the barrier for ONE candidate bead — the whole predicate, with no
/// I/O and no store read.
WorktreeOutstandingFinding evaluateWorktreeOutstanding({
  required WorktreeOutstandingRead read,
  required String workBeadId,
  required Iterable<SessionProjection> linkedSessions,
  required DateTime now,
  String? snapshotRev,
}) {
  if (!read.armed) {
    return WorktreeOutstandingFinding.clear(
      workBeadId,
      snapshotRev: snapshotRev,
    );
  }
  if (read.isWedgedAt(now)) {
    final beat = read.heartbeatAt;
    return WorktreeOutstandingFinding(
      workBeadId: workBeadId,
      refuse: true,
      wedged: true,
      snapshotRev: snapshotRev,
      detail:
          '$kWorktreeOutstandingClause: the P6 mirror has not beaten for '
          '$kWorktreeOutstandingStaleTicks tick intervals '
          '(${read.staleAfter.inSeconds}s; last beat '
          '${beat == null ? 'never' : beat.toUtc().toIso8601String()}; '
          'mirror health ${read.health?.name ?? 'unknown'}) — '
          'a wedged harness cannot prove this bead has no outstanding worktree',
    );
  }

  // THE JOIN, both directions of terminality unioned by session id.
  final basisBySession = <String, WorktreeOutstandingBasis>{};
  for (final head in read.headsFor(workBeadId)) {
    if (head.isOpen) continue;
    basisBySession[head.sessionId] = WorktreeOutstandingBasis.p1Closed;
  }
  for (final session in linkedSessions) {
    final sessionId = session.sessionId;
    if (sessionId == null || sessionId.isEmpty || !session.isTerminal) continue;
    basisBySession[sessionId] = basisBySession.containsKey(sessionId)
        ? WorktreeOutstandingBasis.both
        : WorktreeOutstandingBasis.ledgerTerminal;
  }

  final outstanding = <OutstandingWorktree>[];
  for (final entry in basisBySession.entries) {
    for (final worktree in read.liveWorktreesFor(entry.key)) {
      outstanding.add(
        OutstandingWorktree(
          sessionId: entry.key,
          worktree: worktree,
          basis: entry.value,
        ),
      );
    }
  }
  if (outstanding.isEmpty) {
    return WorktreeOutstandingFinding.clear(
      workBeadId,
      snapshotRev: snapshotRev,
    );
  }
  outstanding.sort((left, right) {
    final bySession = left.sessionId.compareTo(right.sessionId);
    return bySession != 0 ? bySession : left.worktree.compareTo(right.worktree);
  });
  final first = outstanding.first;
  return WorktreeOutstandingFinding(
    workBeadId: workBeadId,
    refuse: true,
    snapshotRev: snapshotRev,
    outstanding: List<OutstandingWorktree>.unmodifiable(outstanding),
    detail:
        '$kWorktreeOutstandingClause: session ${first.sessionId} is terminal '
        '(${first.basis.wire}) and still holds worktree ${first.worktree}'
        '${outstanding.length > 1 ? ' (+${outstanding.length - 1} more)' : ''}',
  );
}

/// The clause, closed over the per-pass [read].
///
/// [observeForm] is the shadow posture: the clause IS composed and DOES
/// evaluate, its findings reach [onFinding] (which counts them), and
/// eligibility changes NOT AT ALL. That is what makes the flip boot the
/// clause's SECOND execution rather than its first.
///
/// [linkedSessionsOf] is the joined snapshot's own per-bead session list —
/// published row plus surplus — so the ledger half reads exactly what a mount
/// decision reads.
MountEligibilityPredicate worktreeOutstandingClause({
  required WorktreeOutstandingRead read,
  required Iterable<SessionProjection> Function(String workBeadId)
  linkedSessionsOf,
  bool observeForm = true,
  String? Function(String workBeadId)? snapshotRevOf,
  void Function(WorktreeOutstandingFinding finding)? onFinding,
  DateTime Function()? clock,
}) {
  final now = clock ?? DateTime.now;
  return (bead) {
    final finding = evaluateWorktreeOutstanding(
      read: read,
      workBeadId: bead.id,
      linkedSessions: linkedSessionsOf(bead.id),
      now: now(),
      snapshotRev: snapshotRevOf?.call(bead.id),
    );
    onFinding?.call(finding);
    if (!finding.refuse || observeForm) {
      return const MountEligibilityDecision.eligible();
    }
    return MountEligibilityDecision.refused(clause: finding.detail!);
  };
}
