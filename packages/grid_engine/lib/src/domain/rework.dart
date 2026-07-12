/// The REWORK-ROUND contract — the single definition of the round cap and the
/// retired-round `work_bead` key shape (lifted from the superseded tg-b3k
/// workaround, PR #48).
///
/// TWO mechanics bound rework, and they share this cap:
///
/// - **`Rewind`** (the engine primitive, tg-o90) — an in-session re-run of a
///   sub-DAG. Its counter is the per-node `NodeCursor.rewindCount`; the
///   `CapabilityHost` refuses a rewind at [kMaxReworkRounds] and parks at a
///   human `Gate` instead.
/// - **`grid rework`** (the operator verb, tg-x1j) — retires a round by
///   re-keying its session's `work_bead` to `<beadId>#r<N>`, which drops it out
///   of the join so `SessionScope` mints round N+1 in the SAME workspace. Its
///   counter is the retired-round key below.
///
/// Both live here so the verb and the engine admit exactly the same number of
/// rounds and cannot drift on the key shape.
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
