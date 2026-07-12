/// The REWORK-ROUND contract (tg-b3k) — the single definition of the
/// retired-round `work_bead` key shape, the round cap, and the
/// machine-actionable-gate predicate.
///
/// A rework round is expressed on the_grid's OWN session bead: retiring round N
/// re-keys its `work_bead` from `<beadId>` to `<beadId>#r<N>`, which drops it
/// out of the join at `<beadId>`. `SessionScope` observes the orphan, closes the
/// retired round, and mints round N+1 in the SAME workspace (the workspace is
/// derived from the bead id, so it is invariant across rounds). The read-only
/// work source is never touched (A37).
///
/// BOTH actuators of that mechanic live off this module so they cannot drift:
/// the operator verb (`grid rework`, grid_cli) and the engine's own auto-respec
/// (`SessionScope`, tg-b3k).
library;

import '../sdk/capability.dart';
import '../sdk/circuit.dart';
import 'session_projection.dart';

/// The max rework rounds one work bead may accumulate before the grid REFUSES to
/// retire another — the cap RATIFIED in `docs/M5-THE-CIRCUIT-BUILD-ORDER.md` D-4
/// ("Bounded rework rounds (factoryskills' cap 3)").
///
/// It is a BELT: an asset's own respec policy is expected to escalate first (a
/// route step caps its automated respecs lower). Reaching THIS cap is a
/// fail-closed refusal — the gate stays parked for a human, LOUD. Both actuators
/// compare it as `retiredRounds >= kMaxReworkRounds`, so the verb and the engine
/// admit exactly the same rounds.
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

/// The single OPEN, MACHINE-ACTIONABLE gate parking [session] (tg-b3k), or null
/// when none does — the pure auto-respec predicate `SessionScope` reads on build.
///
/// A gate qualifies only when BOTH halves hold: its node is CURRENTLY parked
/// (`cursor[nodePath].state == StepState.gated`) and its reason carries the
/// [kRespecGatePrefix] contract token. A human gate (any other reason) yields
/// null and parks exactly as before — the non-regression fence. Ties (more than
/// one qualifying gate — a shape today's single-route circuits never produce)
/// break by the LOWEST nodePath, so the transition is deterministic.
OpenGate? machineActionableGate(SessionProjection session) {
  final paths = session.openGates.keys.toList()..sort();
  for (final nodePath in paths) {
    final gate = session.openGates[nodePath]!;
    if (session.cursor[nodePath]?.state != StepState.gated) continue;
    if (!isRespecGate(gate.reason)) continue;
    return gate;
  }
  return null;
}
