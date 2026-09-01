/// THE ENGINE'S READ INTERFACE onto the trajectory fold — the dual-read's
/// type seam (cut-wiring §0.2, chunk C1).
///
/// `StationJoinBridge._join` is pure and synchronous; a P1 SQL read is async.
/// The splice is therefore PRE-FETCHED state, not an inline await: the harness
/// keeps in-memory mirrors of the fold and publishes immutable, versioned
/// SNAPSHOTS, and the engine reads them through the interfaces here.
///
/// **Where the types live (B-m2).** `grid_engine` gains NO new dependency for
/// this: it declares the interfaces in its own domain layer and `grid_sdk`
/// (which already depends on both) implements them over `grid_trajectory`'s
/// fold row types. No `mysql_client` enters the engine's transitive set, and
/// nothing in this file knows SQL, a column name, or a record type.
///
/// Nothing in wave 1 CREATES a session from a fold row. These views decorate
/// what the ledger already projected; the join always iterates legacy
/// projections (§0.2's "the overlay never creates"), and the OVERLAY IDENTITY
/// RULE (§0.3) pins every merge to `P1.sessionId == legacy.sessionId` — which
/// is why [TrajectoryHeadSnapshot.bySessionId] is the overlay's only input and
/// [TrajectoryHeadSnapshot.byWorkBead] is for CLASSIFICATION alone.
library;

import 'package:meta/meta.dart';

/// P1's `outcome` ENUM, engine-side — the decision-faithful terminal
/// vocabulary verbatim, so the sdk's adapter is a name-for-name mapping and
/// the engine never imports the trajectory package to read one.
enum SessionHeadOutcome {
  succeeded,
  failed,
  cancelled,
  lost,
  escalated,
  settled,
  unknown;

  static SessionHeadOutcome fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// P1's `terminal_provenance` ENUM, engine-side.
///
/// [reconstructed] is the wave-1 cut's durable mark: this head's terminal is
/// TESTIMONY the station reconstructed, not a close it observed. The
/// `reconstructedTerminal` adjudication class reads it and serves PURE LEGACY
/// for that session — a reconstructed outcome is fold bookkeeping, never
/// decision state.
enum SessionHeadProvenance {
  observed,
  inferred,
  reconstructed;

  static SessionHeadProvenance fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// One `proj_session_head` row, as the engine reads it (P1 — §7's head
/// summary).
///
/// P1 deliberately carries NO worktree/lease/liveness fields — those are P6's
/// — and no running-round field: [round] is the RETIRED-INTO marker, written
/// by exactly one record (`attempt.round.retired`), so a never-retired head
/// carries 0 and an open row with `round > 0` IS a retired head (§0.2's
/// retirement-legible winner rule).
abstract interface class SessionHeadView {
  String get sessionId;

  /// §7: IMMUTABLE — set at mint and never re-keyed. The bd side's `#rN` /
  /// `#void-` re-key survives untouched; P1 simply declines to follow it, so
  /// retired sessions are matched by session id, never by the mutated key.
  String get workBeadId;

  /// The retired-INTO round, 0 on every live head. Never a running round.
  int get round;

  /// `status = 'open'` — the row has no terminal yet.
  bool get isOpen;

  SessionHeadOutcome? get outcome;

  /// The `held` axis — SEPARATE from [outcome] (§6 row 4): a decline sets it
  /// on an OPEN row, and an open held row is `live` on both sides.
  bool get held;
  String? get heldReason;

  /// Compare-only, never served (§0.3, r5 — J9-B2): the two sides do not
  /// carry the same fact, so this is an informational column beside the
  /// pgid/pid presence pair.
  String? get workTerminalReason;

  /// Observed as a PRESENCE PAIR by the comparator and never served: the
  /// fence identity triple stays whole on its legacy carrier, because an
  /// overlaid null would turn I-10's never-double-run-a-survivor fence
  /// fail-open (§0.3, r4 — J6-B1/J7-B1).
  int? get pgid;
  int? get pid;

  String? get attemptId;

  /// The wave-1 cut columns (r6–r11): why an `unknown` head is unknown, and
  /// whether its terminal is observed truth or reconstructed testimony.
  SessionHeadProvenance? get terminalProvenance;
  String? get unknownReason;

  DateTime get startedAt;
  DateTime? get closedAt;

  /// The monotone fold-activity cursor — the acked append ordinal. It ranks
  /// closed rows in the winner rule; it is not a clock.
  int get lastSeq;
}

/// One `proj_step_cursor` row, as the engine reads it (P2 — the round-bearing
/// step cursor on the two-ladder key).
///
/// Declared here with P1 because the read INTERFACE is one seam; the P2
/// mirror, its `byP2SessionId` index, and the step-axis dual-read are C4's.
abstract interface class StepCursorView {
  String get sessionId;
  int get round;
  String get stepPath;
  int get stepRound;

  /// The §4 ENUM wire string — pending/running/ready/complete/failed/gated.
  String get state;
  int get incarnation;
  String? get attemptId;

  /// The supersedes chain, written on the PREDECESSOR row by every bump.
  int? get supersededByStepRound;
  DateTime? get cooldownUntil;
  int? get restartBudget;
  DateTime? get startedAt;
  DateTime? get readyAt;
  DateTime? get completedAt;
  String? get failureClass;
  int get lastSeq;
}

/// A snapshot's trustworthiness, wave-1 semantics (§0.2, r4 — J6-B3/J7-M3).
enum TrajectorySnapshotHealth {
  /// Seeded clean and maintained post-ACK — the only health the overlay ever
  /// engages under.
  live,

  /// LATCHED for the boot on any append drop, failure, or SUPPRESSION since
  /// boot, or on the harness leaving `live` mode. Suppression is not a drop:
  /// a fenced-out or halted harness freezes the mirror while nothing is
  /// dropped, so a drops-only latch would keep serving a frozen fold.
  compromised,

  /// The boot seed found the fold stale (past the record/age lag bound), or
  /// no seed ran at all.
  refused,
}

/// One immutable, versioned read of the P1 mirror.
///
/// Under wave 1 any non-[TrajectorySnapshotHealth.live] health simply
/// DISENGAGES the overlay for the boot: decisions ride pure legacy — which
/// remains fully written and authoritative, because wave 1 retires nothing —
/// with a loud flare and a round-summary field. There is no demotion trap.
abstract interface class TrajectoryHeadSnapshot {
  /// Bumped on every published change; a comparator reports it with each
  /// divergence so a finding names the exact state it saw.
  int get version;

  TrajectorySnapshotHealth get health;

  /// When the boot seed ran — null when none did.
  DateTime? get seededAt;

  /// The instant this station first claimed an epoch, i.e. the boundary the
  /// miss classifier splits `legacyEra` from `postEpoch` on. A session that
  /// started before it (or with a null `startedAt`) is legacy-era, and its
  /// missing head is not a defect.
  DateTime? get firstEpochClaimedAt;

  /// THE OVERLAY'S ONLY INPUT (§0.3's OVERLAY IDENTITY RULE): the PK lookup.
  /// Also what every COMPARISON uses — like row with like bead, retired rows
  /// included, which is where round parity against a `#rN` key is checked.
  SessionHeadView? bySessionId(String sessionId);

  /// The FRONTIER/CLASSIFICATION view — never the overlay's input. It exists
  /// for reads that already handle multiplicity: the cardinality sentinel,
  /// the orphan/lag classifiers, frontier-level views.
  SessionHeadWinner byWorkBead(String workBeadId);

  /// Every row, for accounting sweeps (orphan classification, counts).
  Iterable<SessionHeadView> get rows;
}

/// One immutable, versioned read of the P2 mirror (C4's; declared with P1 so
/// the read seam is one file).
abstract interface class TrajectoryStepSnapshot {
  int get version;
  TrajectorySnapshotHealth get health;
  DateTime? get seededAt;
  DateTime? get firstEpochClaimedAt;

  /// The step axis's identity-matched lookup — the same rule as P1's
  /// [TrajectoryHeadSnapshot.bySessionId], distinctly named because the two
  /// mirrors are separate (r7 — V1-M5).
  Iterable<StepCursorView> byP2SessionId(String sessionId);
}

/// What [TrajectoryHeadSnapshot.byWorkBead] resolved to.
@immutable
sealed class SessionHeadWinner {
  const SessionHeadWinner();
}

/// Exactly one row wins the bead — partition case (1) or (3).
final class SessionHeadWon extends SessionHeadWinner {
  const SessionHeadWon(this.row, {required this.fromClosedLadder});

  final SessionHeadView row;

  /// True when the bead had NO current-open row and the winner came off the
  /// closed ladder (case 3) — the classifiers care which case they are in.
  final bool fromClosedLadder;
}

/// No row is servable for this bead — either the mirror holds none, or the
/// bead's only open rows are RETIRED (the rework window, successor not yet
/// minted). The legacy side has no base-key projection there either, so this
/// matches rather than diverges.
final class SessionHeadNone extends SessionHeadWinner {
  const SessionHeadNone({required this.retiredOpenRows});

  /// Retired-open rows seen — non-zero says "rework window", not "unknown".
  final int retiredOpenRows;
}

/// Partition case (2): more than one CURRENT open row on one bead — a genuine
/// double-mount, never a rework, because retired rows are excluded from the
/// decision partition. Serve NO row, flare
/// `trajectory.dualReadDivergence{field:'cardinality'}`, count `fallback`.
final class SessionHeadCardinalityBreach extends SessionHeadWinner {
  const SessionHeadCardinalityBreach(this.rows);

  final List<SessionHeadView> rows;
}

/// THE WINNER RULE (§0.2, r3 form), pure and total over one bead's rows.
///
/// The mechanical facts it rests on, all verified in-tree: P1's `round` column
/// is written by exactly one record (`attempt.round.retired`, whose
/// `newRound = oldRound + 1 >= 1`), a never-retired head carries the DDL
/// default 0, and the engine's retire path closes the bd bead while emitting
/// ONLY `roundRetired` — so a retired session's P1 row stays `status='open'`
/// FOREVER, by schema design. Retirement is therefore LEGIBLE in the fold, and
/// the partition can exclude retired heads from the decision:
///
///   1. exactly one CURRENT (`round == 0`) open row ⇒ it wins;
///   2. more than one ⇒ [SessionHeadCardinalityBreach] — a real double-mount;
///   3. zero ⇒ the CLOSED row with the highest `last_seq`, ties by latest
///      `started_at`. Both are real fold columns whose mirror copies are
///      byte-identical to the SQL fold under the post-ACK seam. (r2's
///      "highest round" tie-break dies with the round-semantics correction:
///      `round` is the retired-INTO marker, so it cannot rank closed rows.)
///
/// A bead with only retired-open rows serves nothing — [SessionHeadNone].
SessionHeadWinner sessionHeadWinnerOf(Iterable<SessionHeadView> rows) {
  final current = <SessionHeadView>[];
  final closed = <SessionHeadView>[];
  var retiredOpen = 0;
  for (final row in rows) {
    if (!row.isOpen) {
      closed.add(row);
      continue;
    }
    if (row.round > 0) {
      retiredOpen += 1;
      continue;
    }
    current.add(row);
  }
  if (current.length == 1) {
    return SessionHeadWon(current.single, fromClosedLadder: false);
  }
  if (current.length > 1) {
    return SessionHeadCardinalityBreach(List.unmodifiable(current));
  }
  if (closed.isEmpty) {
    return SessionHeadNone(retiredOpenRows: retiredOpen);
  }
  var winner = closed.first;
  for (final row in closed.skip(1)) {
    if (row.lastSeq > winner.lastSeq ||
        (row.lastSeq == winner.lastSeq &&
            row.startedAt.isAfter(winner.startedAt))) {
      winner = row;
    }
  }
  return SessionHeadWon(winner, fromClosedLadder: true);
}
