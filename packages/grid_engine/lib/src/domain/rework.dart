/// The REWORK-ROUND contract — the single definition of the round cap and the
/// retired-round `work_bead` key shape (lifted from the superseded tg-b3k
/// workaround, PR #48).
///
/// THREE mechanics re-run work, and they share this cap:
///
/// - **`Rewind`** (the engine primitive, tg-o90) — an in-session re-run of a
///   sub-DAG. Its counter is the per-node `NodeCursor.rewindCount`; the
///   `CapabilityHost` refuses a rewind at [kMaxReworkRounds] and parks at a
///   human `Gate` instead.
/// - **`grid rework`** (the operator verb, tg-x1j) — retires a round by
///   re-keying its session's `work_bead` to `<beadId>#r<N>` ([reworkKeyFor]),
///   which drops it out of the join so `SessionScope` mints round N+1 in the
///   SAME workspace. Its counter is the retired-round key below.
/// - **the VOID retire** (the engine-automatic one, tg-4rw / I-10) — a session
///   somebody closed MID-FLIGHT is a DEAD KEY: `SessionScope` retires it by
///   re-keying its `work_bead` to `<beadId>#void-<deadSessionId>` ([voidKeyFor])
///   and mints a fresh round, with no human and no operator verb. It borrows
///   `grid rework`'s re-key MECHANIC but sits deliberately OUTSIDE the round
///   budget: a round nobody ran is not a round the operator spent, so a `#void-`
///   key never matches [reworkKeyPattern].
///
/// All three live here so the verbs and the engine admit exactly the same number
/// of rounds and cannot drift on the key shapes.
library;

/// The max rework rounds one work bead may accumulate before the grid REFUSES to
/// rework it again — the cap RATIFIED in `docs/M5-THE-CIRCUIT-BUILD-ORDER.md`
/// D-4 ("Bounded rework rounds (factoryskills' cap 3)").
///
/// It is a BELT: an asset's route is expected to escalate on its own policy
/// first (it reads its own `rewindCount` back through the `SiblingView`).
/// Reaching THIS cap is a fail-closed refusal — the work parks for a human,
/// LOUD. An operator who wants to grant another budget uses `grid rework` (a
/// fresh session ⇒ a fresh cursor ⇒ a fresh count).
const int kMaxReworkRounds = 3;

/// The retired-round `work_bead` value for [beadId] at [round] (`<beadId>#r<N>`)
/// — the ONE place the key shape is authored.
String reworkKeyFor(String beadId, int round) => '$beadId#r$round';

/// Matches a RETIRED round's `work_bead` value for [beadId] exactly
/// (`^<beadId>#r(\d+)$`) — anchored, so a DIFFERENT bead id that merely starts
/// with [beadId] (`tg-x1j2#r1` vs `tg-x1j`) is never mistaken for one of its
/// rounds.
RegExp reworkKeyPattern(String beadId) =>
    RegExp('^${RegExp.escape(beadId)}#r(\\d+)\$');

/// The round number encoded in [workBeadKey] for [beadId], or null when
/// [workBeadKey] is not one of [beadId]'s retired rounds.
int? reworkRoundOf(String beadId, String workBeadKey) {
  final match = reworkKeyPattern(beadId).firstMatch(workBeadKey);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// The highest retired round on record for [beadId] across [workBeadKeys] (every
/// session's `work_bead` value) — 0 when none has been retired. The next round
/// is `maxReworkRound(...) + 1`.
int maxReworkRound(String beadId, Iterable<String> workBeadKeys) {
  var highest = 0;
  for (final key in workBeadKeys) {
    final round = reworkRoundOf(beadId, key);
    if (round != null && round > highest) highest = round;
  }
  return highest;
}

/// The VOIDED-session `work_bead` value (I-10, tg-4rw) — the key a DEAD session
/// is retired to when the engine mints fresh over it
/// (`<beadId>#void-<deadSessionId>`).
///
/// Deterministic with no clock and no counter (the dead session's own id is
/// already unique), and by construction it NEVER matches [reworkKeyPattern]
/// (`^<beadId>#r(\d+)$`) — so a voided round is never counted against the
/// [kMaxReworkRounds] budget.
String voidKeyFor(String beadId, String deadSessionId) =>
    '$beadId#void-$deadSessionId';
