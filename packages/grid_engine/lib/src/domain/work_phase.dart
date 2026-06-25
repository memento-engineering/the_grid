/// The work lifecycle axis (ADR-0007; M4-P0-BUILD-ORDER §0.5, A40).
library;

import 'package:grid_controller/grid_controller.dart';

import 'session_projection.dart';

/// The three live work phases a mounted work node passes through.
///
/// A phase is a *reconcile transition*: mount = spawn the implement agent, a
/// phase advance = swap the effect child, unmount = a positive terminal.
/// `verify` (deliberately not `gate`) avoids colliding with the M2 convergence
/// gate-eval — a different axis, on `type=convergence` beads.
///
/// "done" is NOT a phase. It is the *absence* of a mount: the work bead
/// `closed`, or the_grid's owned session cursor reaching terminal. A bead
/// merely leaving the ready-set is never "done" (A40).
enum WorkPhase {
  /// Spawn and supervise the coding agent.
  implement,

  /// Run the verification check (a process effect — NOT the M2 gate).
  verify,

  /// Commit → push → open the PR, then record the result on the session bead.
  land;

  /// The capability id this phase resolves to — the `capId` half of an
  /// effect Seed's `'<beadId>.<capId>'` key.
  ///
  /// The key embeds the capId so a phase advance *swaps* the effect child
  /// (unmount the old capability → its `dispose` kills; mount the new → its
  /// `initState` spawns) while the owning work node keeps its branch identity.
  String get capId => switch (this) {
    WorkPhase.implement => 'agent',
    WorkPhase.verify => 'verify',
    WorkPhase.land => 'land',
  };
}

/// Derives the live [WorkPhase] of [workBead] by JOINing it with its linked
/// session cursor [session] (A40) — never read off the work bead itself, which
/// lives in a pristine, read-only work source (A37).
///
/// - no session cursor (a bead freshly entering the ready-set) ⇒
///   [WorkPhase.implement] (spawn a fresh agent);
/// - otherwise, the session cursor's phase.
///
/// The *terminal* decision (unmount) is **not** expressed here — it is the
/// work-list child-set predicate's job (a positive terminal removes the bead
/// from the child set). `phaseOf` only ever names a *live* phase, so a caller
/// must have already excluded terminal sessions.
WorkPhase phaseOf(Bead workBead, SessionProjection? session) {
  if (session == null) return WorkPhase.implement;
  return session.phase;
}
