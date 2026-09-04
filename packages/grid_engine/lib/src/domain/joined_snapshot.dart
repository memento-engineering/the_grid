import 'package:beads_dart/beads_dart.dart';

import 'mount_attempt.dart';
import 'session_projection.dart';

/// The single immutable value the tree builds from: the read-workspace work
/// graph JOINed with the_grid's owned session cursors, keyed by work bead id.
///
/// Assembled OUTSIDE the tree by the join bridge (Track B) and injected as a
/// `JoinedSnapshotNotifier` value; the tree only ever *consumes* it (A39 /
/// derailment-invariant 1) — no tree node re-detects or subscribes into a
/// pipeline.
///
/// Deliberately reference-y (like [GraphSnapshot]): change detection is the
/// bridge's job — it emits a new instance only on a real change — so this type
/// needs no deep value equality.
class JoinedSnapshot {
  /// Creates a joined value over [graph] and [sessionsByWorkBead].
  const JoinedSnapshot({
    required this.graph,
    this.sessionsByWorkBead = const {},
    this.surplusSessionsByWorkBead = const {},
    this.mountAttemptsByWorkBead = const {},
    this.frontierExclusionsByBeadId = const {},
  });

  /// An empty baseline — the notifier's seed value before the first refresh
  /// (Track B: `runtime.current` may be null immediately after a fresh start;
  /// seed empty and let the first baseline refresh fill it).
  JoinedSnapshot.empty()
    : graph = GraphSnapshot.fromParts(
        beads: const [],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      sessionsByWorkBead = const {},
      surplusSessionsByWorkBead = const {},
      mountAttemptsByWorkBead = const {},
      frontierExclusionsByBeadId = const {};

  /// The read-workspace work graph (pristine source — read-only, A37).
  final GraphSnapshot graph;

  /// The_grid's owned session cursor per work bead id (from the state store).
  ///
  /// Each [SessionProjection] carries its own model discriminator
  /// ([SessionProjection.isMolecule]) and, for a molecule-mode session, its
  /// own `type=molecule`/`type=step` beads bucketed by the join into
  /// [SessionProjection.moleculeBeads] (`DESIGN-tg-pm6.md` §10, R5a) — always
  /// empty for a flat session. [JoinedSnapshot] itself carries no new field
  /// for the molecule model: the bucket rides inside the per-session
  /// projection it already holds, so a molecule session is additive, not a
  /// second parallel join.
  final Map<String, SessionProjection> sessionsByWorkBead;

  /// The SURPLUS session rows per work bead id (tg-83k1) — every projection
  /// whose `work_bead` equals the key EXCEPT the one [sessionsByWorkBead]
  /// publishes, in `orderLinkedSessions` order (newest first).
  ///
  /// Absent for the overwhelmingly common single-row bead, and empty BY
  /// DEFAULT so a hand-built snapshot keeps its exact prior meaning:
  /// [linkedSessions] then returns just the published row.
  ///
  /// A surplus row is the raw `projectSession` projection: the molecule/gate
  /// attachments and the dual-read overlay enrich only the PUBLISHED row (the
  /// overlay identity rule keys on the published session's own id). The mount
  /// boundary reads only `isTerminal` / `sessionId` / `closedAt` / the process
  /// fences off a surplus row, so the un-enriched shape is what it needs.
  final Map<String, List<SessionProjection>> surplusSessionsByWorkBead;

  /// Every session row linked to [workBeadId] — the published row first, then
  /// its surplus. The ONE read the mount boundary joins on.
  List<SessionProjection> linkedSessions(String workBeadId) {
    final published = sessionsByWorkBead[workBeadId];
    final surplus =
        surplusSessionsByWorkBead[workBeadId] ?? const <SessionProjection>[];
    if (published == null) return surplus;
    return <SessionProjection>[published, ...surplus];
  }

  /// The DURABLE remount-attempt budget per work bead id (tg-zlfu), projected
  /// from the state store's `type=mount-attempt` records.
  ///
  /// It rides HERE, in the joined value, for one hard reason: the mount
  /// boundary's [MountEligibilityPredicate] is synchronous and receives only
  /// the candidate bead, so it cannot read the store. The budget has to already
  /// be in memory when the predicate runs — the same way owned sessions
  /// already are — and the concrete clause closes over this map.
  ///
  /// Empty for a bead the station has never attempted; absence means zero, so
  /// no record is written until the first mount.
  final Map<String, MountAttemptRecord> mountAttemptsByWorkBead;

  /// Exact join-time exclusion clause per authoritative-ready work bead
  /// removed by an active state-store cross-link.
  ///
  /// Empty means no cross-link exclusion. The join computes this once so the
  /// synchronous mount-eligibility predicate performs no store read.
  final Map<String, String> frontierExclusionsByBeadId;
}
