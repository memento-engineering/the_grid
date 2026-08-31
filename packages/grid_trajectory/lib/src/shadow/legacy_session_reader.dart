/// The comparator's LEGACY side — an injectable, dependency-free view of one
/// ledger session bead.
///
/// This package is a leaf (zero grid_* deps, decision:
/// grid-trajectory-leaf-package), so the interface is defined HERE and the
/// implementation composes in grid_cli over beads_dart's session-bead read
/// surface. The view carries exactly the shadowable facts (§9): work bead,
/// open/closed status, the outcome-ish close markers, the round encoded in
/// the `#rN` work-bead key shape, and the human-held markers. Nothing else —
/// the §9 unshadowable list (attempt ids, digests, provenance, incarnation,
/// per-effect ordering) has no legacy counterpart and no field here.
library;

import 'package:meta/meta.dart';

/// One legacy session bead, projected to the shadow-comparable facts.
@immutable
class LegacySessionView {
  const LegacySessionView({
    required this.sessionId,
    required this.workBeadId,
    required this.closed,
    this.completed = false,
    this.held = false,
    this.heldReason,
    this.voided = false,
    this.round,
  });

  /// The session bead's own id.
  final String sessionId;

  /// The BASE work bead id — any `#rN` / `#void-<sid>` retirement suffix on
  /// the bead's `work_bead` metadata is stripped (the trajectory side never
  /// mutates its key, §1).
  final String workBeadId;

  /// The session bead's own status.
  final bool closed;

  /// The engine's durable positive-terminal marker (`grid.outcome`).
  final bool completed;

  /// The human-held markers (`grid.escalation` / `grid.rework_declined`).
  final bool held;
  final String? heldReason;

  /// True when the `work_bead` key carries the `#void-<sessionId>` dead-key
  /// shape — somebody closed the session mid-flight.
  final bool voided;

  /// The round the `#rN` key shape names — null for a live (bare-key)
  /// session, whose round the legacy model simply does not carry.
  final int? round;
}

/// The injected legacy read seam. A null view means the ledger knows no such
/// session bead.
abstract interface class LegacySessionReader {
  Future<LegacySessionView?> sessionView(String sessionId);
}
