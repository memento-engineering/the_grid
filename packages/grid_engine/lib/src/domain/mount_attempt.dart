/// The DURABLE remount-attempt budget (tg-zlfu) — the bound on how many times
/// one work bead may be re-derived by the frontier and remounted.
///
/// **Why this is not derived from session beads.** Every mount already mints a
/// session bead carrying the work-bead linkage, so "attempts" looks derivable
/// from a metadata-filtered count with no new type and no new writes. It is
/// not: session count means ROUNDS, not attempts. `grid rework` retires round
/// N and mints a fresh session for round N+1 of the same work bead, so a bead
/// reworked five times after five perfectly healthy mounts carries five-plus
/// sessions and ZERO crash-loop attempts. Recovering the right population would
/// mean reading every session for the bead at every mount decision and
/// classifying each by disposition — reconstructing a control input out of
/// forensic records, at the mount boundary, on every evaluation. A session bead
/// records WHAT HAPPENED; the attempt budget is a DECISION VARIABLE the mount
/// gate reads, and deriving one from the other is what couples them.
///
/// **Why DURABLE, against the convention.** OTP and Gas City both keep restart
/// counters in memory precisely so they reset when the supervisor restarts:
/// that is the right call when the supervisor's own death is the outer bound.
/// It is the WRONG call here, because launchd `KeepAlive` relaunches the
/// station aggressively — an in-memory counter yields a loop of loops, where
/// the station dies on a bad bead, is relaunched, forgets, retries, and dies
/// again. This counter therefore survives a station bounce, and that divergence
/// is deliberate rather than an oversight.
///
/// Hold the resulting tension carefully: reconcile identity stays FREE across a
/// bounce while the attempt budget deliberately does not. They are different
/// things and must stay different things — which is also why the count is never
/// folded into a reconcile key, where a moving mutable value is itself a
/// spurious-remount bug (tg-lytw).
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';

import 'mount_eligibility.dart';

/// The metadata keys carried by ONE `type=mount-attempt` bead per work bead.
///
/// Wire-identical to `StationBeadWriter`'s constants of the same name; the two
/// are duplicated rather than shared because grid_runtime cannot import
/// grid_engine (the dependency arc is one-directional), the same split the
/// molecule join keys already live under.
abstract final class MountAttemptKeys {
  /// The JOIN key: which work bead this record budgets.
  static const String workBead = 'grid.attempt.work_bead';

  /// Attempts made so far — merged in place, never one bead per attempt.
  static const String count = 'grid.attempt.count';

  /// ISO-8601 instant of the most recent attempt.
  static const String lastAt = 'grid.attempt.last_at';
}

/// The clause name a capped bead is refused under — the string that rides
/// `work.mountEligibilityRefused` so the refusal names itself in the log.
const String kMountAttemptCapClause = 'attempt-cap';

/// How many times one work bead may be mounted before the frontier stops
/// remounting it and it becomes visibly human-attention-requiring.
///
/// Deliberately LOWER than `SessionScope._maxMintAttempts` (5), which bounds a
/// different and far cheaper thing: that budget rides out a transient bd blip
/// between createSession retries, in memory, resetting each round. A remount
/// costs a whole session graph — a session bead, a molecule, a step per node, a
/// worktree, an agent — so the crash loop this bounds is expensive per turn and
/// three attempts is enough to distinguish a deterministic failure from a
/// one-off.
const int kMaxMountAttempts = 3;

/// One work bead's durable attempt record, projected out of the state store.
final class MountAttemptRecord {
  /// Creates a record for [workBeadId] at [count] attempts, carried by the
  /// state-store bead [recordId].
  const MountAttemptRecord({
    required this.recordId,
    required this.workBeadId,
    required this.count,
  });

  /// The `type=mount-attempt` bead's own id in the station's state store.
  final String recordId;

  /// The work bead this record budgets — the join key.
  final String workBeadId;

  /// Attempts made so far. Never negative; an unparseable stored value reads
  /// as 0 (fail-OPEN on a corrupt count: a bead that cannot be read must not be
  /// silently locked out of the frontier forever).
  final int count;

  /// Whether the budget is spent — the frontier stops remounting at the cap.
  bool get isExhausted => count >= kMaxMountAttempts;

  @override
  String toString() =>
      'MountAttemptRecord($recordId, $workBeadId, count: $count)';
}

/// Projects a `type=mount-attempt` [bead] into its record, or null when the
/// bead is not an attempt record or carries no join key (nothing to key on).
MountAttemptRecord? projectMountAttempt(Bead bead) {
  if (bead.issueType != GridIssueTypes.mountAttempt) return null;
  final workBeadId = '${bead.metadata[MountAttemptKeys.workBead] ?? ''}';
  if (workBeadId.isEmpty) return null;
  final raw = bead.metadata[MountAttemptKeys.count];
  final parsed = int.tryParse('${raw ?? ''}') ?? 0;
  return MountAttemptRecord(
    recordId: bead.id,
    workBeadId: workBeadId,
    count: parsed < 0 ? 0 : parsed,
  );
}

/// The attempt-cap clause, closed over the in-memory [attempts] projection.
///
/// [MountEligibilityPredicate] is SYNCHRONOUS and receives only the candidate
/// bead (tg-8900), so it cannot perform a store read: the attempt state must
/// already be projected into memory before it runs, exactly the way owned
/// sessions are. That is why this takes the projection as a value rather than a
/// reader.
MountEligibilityPredicate mountAttemptClause(
  Map<String, MountAttemptRecord> attempts,
) => (bead) {
  final record = attempts[bead.id];
  if (record == null || !record.isExhausted) {
    return const MountEligibilityDecision.eligible();
  }
  return MountEligibilityDecision.refused(
    clause:
        '$kMountAttemptCapClause: ${record.count} mount attempts, '
        'cap $kMaxMountAttempts (record ${record.recordId})',
  );
};

/// Composes the engine's own clauses with the station's composed predicate into
/// the ONE predicate the mount boundary calls.
///
/// A second mount-boundary check would duplicate — and then drift from — the
/// edge-triggered refusal/restoration flares `WorkList` already emits, so the
/// clauses compose instead. First refusal wins; [asset] is null on a station
/// that composes no eligibility assets, and then only the engine clauses apply.
MountEligibilityPredicate composeMountEligibility(
  List<MountEligibilityPredicate> engine,
  MountEligibilityPredicate? asset,
) => (bead) {
  for (final clause in [...engine, if (asset != null) asset]) {
    final decision = clause(bead);
    if (decision is MountRefused) return decision;
  }
  return const MountEligibilityDecision.eligible();
};
