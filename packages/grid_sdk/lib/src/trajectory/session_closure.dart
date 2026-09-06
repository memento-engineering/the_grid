// The LEDGER's closure answer for the external-close obligation (tg-ffl6;
// decision `wave-2-flip-scope-soak-and-kill-date`, Q6: bd remains an input to
// terminal truth). One pure function over a session bead, read off the state
// snapshot the join bridge already holds — never a bd round trip.
//
// The outcome is derived from EXACTLY the markers legacy's disposition reads
// (`sessionDispositionOf` over `projectSession`), in legacy's order, so a P1
// head healed from it dispositions under `primary` the way the bead does under
// legacy: a human marker outranks everything, the engine's own DONE marker
// outranks the void key, and anything else closed is a cancelled round. An
// `unknown` outcome would be served fail-closed as HELD under `primary` and
// would block the bead's remount where legacy voids and re-mints — which is
// why the heal never writes `unknown` when the ledger can say more.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart';

/// The closure of [bead] as the ledger records it, or null when the bead is
/// open (a live round — nothing to heal). The caller decides whether [bead] is
/// a session bead; this reads only the session-bead schema.
SessionClosure? sessionClosureOf(Bead bead) {
  if (!bead.isClosed) return null;
  final projection = projectSession(bead);
  final workBead = (bead.metadata[SessionBeadKeys.workBead] as String?) ?? '';
  final voided =
      bead.metadata.containsKey(SessionBeadKeys.voidedReason) ||
      workBead.contains('#void-');
  final TerminalOutcome outcome;
  if (projection.humanHeld) {
    // `grid.escalation` / `grid.rework_declined`: a human owns this round and
    // legacy reads it HELD — the escalated terminal is what P1 dispositions
    // as held too.
    outcome = TerminalOutcome.escalated;
  } else if (projection.completed) {
    // The engine's own positive-terminal marker (`grid.outcome`), the sole
    // DONE evidence the mount boundary has.
    outcome = TerminalOutcome.succeeded;
  } else if (voided) {
    // A dead key retired by the void re-key (I-10): never adoptable, never
    // blocking — the trajectory's `lost`.
    outcome = TerminalOutcome.lost;
  } else {
    // Closed with no station outcome: a retired rework round, a hand close,
    // a gate exit. Legacy voids it and re-mints; `cancelled` falls through
    // §0.3's table to the same arms.
    outcome = TerminalOutcome.cancelled;
  }
  // A retired rework round: the ledger closed the `#rN` bead when the next
  // round minted, but the fold models that as a ROUND BUMP on an open head —
  // "stays status='open' FOREVER, by schema design" (cut-wiring §0.2, the
  // comparator's steady state). Whether such heads should close is the
  // wave-2 schema question (worksheet E9 / Q9); the heal reports it and
  // leaves it.
  final retiredRound = !voided && RegExp(r'#r\d+$').hasMatch(workBead);
  final closeReason = bead.closeReason.trim();
  final voidedReason = (bead.metadata[SessionBeadKeys.voidedReason] as String?)
      ?.trim();
  return SessionClosure(
    closedAt: projection.closedAt ?? bead.closedAt,
    outcome: outcome,
    retiredRound: retiredRound,
    reason: closeReason.isNotEmpty
        ? 'ledger close: $closeReason'
        : (voidedReason == null || voidedReason.isEmpty
              ? null
              : 'ledger void: $voidedReason'),
  );
}
