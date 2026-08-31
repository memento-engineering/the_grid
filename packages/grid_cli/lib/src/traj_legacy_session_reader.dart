/// grid_cli's side of the §9 shadow seam: the [LegacySessionReader]
/// implemented over beads_dart's session-bead read surface, plus the
/// [ShadowCompareFactory] `bin/grid.dart` hands `TrajCommand`.
///
/// grid_trajectory is a leaf (zero grid_* deps) and defines only the
/// interface; the beads_dart/grid_engine knowledge — `projectSession`'s
/// marker semantics and `rework.dart`'s `#rN` / `#void-` key shapes — lives
/// HERE, reusing the exact read path the resident verbs use
/// (`resolveStateWorkspace` → exact-root state store → `bd show` through
/// [BdCliService], never a walk-up, never a raw SQL read of the ledger).
library;

import 'package:beads_dart/beads_dart.dart'
    show Bead, BdCliService, BdException, ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart'
    show SessionBeadKeys, projectSession;
import 'package:grid_trajectory/grid_trajectory.dart'
    show
        AttemptLifecycleShadow,
        LegacySessionReader,
        LegacySessionView,
        ShadowCompare,
        ShadowCompareResult,
        SubjectRecords;

import 'state_workspace.dart';

/// Fetches session beads by id — [BdCliService.show]'s shape, injected so
/// tests script beads without spawning `bd`.
typedef SessionBeadFetch = Future<List<Bead>> Function(List<String> ids);

/// Reads one session bead and projects it to the shadow-comparable view.
class BdLegacySessionReader implements LegacySessionReader {
  BdLegacySessionReader(this._fetch);

  final SessionBeadFetch _fetch;

  @override
  Future<LegacySessionView?> sessionView(String sessionId) async {
    final List<Bead> beads;
    try {
      beads = await _fetch([sessionId]);
    } on BdException {
      // An unknown id is "the ledger knows no such session", not a crash —
      // the comparator reports it as a presence mismatch.
      return null;
    }
    for (final bead in beads) {
      if (bead.id == sessionId) return legacySessionViewOf(bead);
    }
    return null;
  }
}

/// The retired-round key shape `rework.dart` writes (`<beadId>#r<N>`),
/// matched generically: at read time the base id is unknown, so the anchored
/// per-bead pattern (`reworkKeyPattern`) cannot be used — this is its
/// inverse, and the greedy base group keeps a base id containing `#r` digits
/// from truncating early.
final RegExp _reworkKeyShape = RegExp(r'^(.*)#r(\d+)$');

/// The dead-key shape `rework.dart`'s `voidKeyFor` writes
/// (`<beadId>#void-<deadSessionId>`).
final RegExp _voidKeyShape = RegExp(r'^(.*)#void-.+$');

/// Pure projection of one session [bead] to the shadow view — the marker
/// semantics are `projectSession`'s (grid_engine owns that schema), the key
/// shapes `rework.dart`'s.
LegacySessionView legacySessionViewOf(Bead bead) {
  final projection = projectSession(bead);
  final rawKey = projection.workBeadId;
  final rework = _reworkKeyShape.firstMatch(rawKey);
  final voided = rework == null ? _voidKeyShape.firstMatch(rawKey) : null;
  final metadata = bead.metadata;
  final heldReason =
      metadata[SessionBeadKeys.escalationReason] as String? ??
      metadata[SessionBeadKeys.reworkDeclinedReason] as String?;
  return LegacySessionView(
    sessionId: bead.id,
    workBeadId: rework?.group(1) ?? voided?.group(1) ?? rawKey,
    closed: projection.isTerminal,
    completed: projection.completed,
    held: projection.humanHeld,
    heldReason: heldReason,
    voided: voided != null,
    round: rework == null ? null : int.parse(rework.group(2)!),
  );
}

/// A grid home whose LEGACY ledger could not be opened: the §9 window has no
/// oracle there, and the verb must say so instead of minting a clean run.
class LegacyStoreUnavailableShadow implements ShadowCompare {
  const LegacyStoreUnavailableShadow(this.reason);

  final String reason;

  @override
  Set<String> get comparableFields => const {};

  @override
  String get unavailableReason => reason;

  @override
  Future<ShadowCompareResult> compare({
    required String sessionId,
    required SubjectRecords records,
    int? round,
  }) async => const ShadowCompareResult([]);
}

/// The [ShadowCompareFactory] `bin/grid.dart` composes into `TrajCommand`:
/// opens the grid home's state store on the resident verbs' exact-root rule
/// and returns the REAL Family-1 comparator — or, when the home carries no
/// readable ledger, a strategy that degrades gracefully with the refusal as
/// its reason.
Future<ShadowCompare> legacyShadowCompareFor(String gridHome) async {
  final resolved = resolveStateWorkspace(
    stationName: 'grid',
    verb: 'traj shadow-diff',
    stateWorkspacePath: gridHome,
  );
  switch (resolved) {
    case StateWorkspaceRefusal(:final message):
      return LegacyStoreUnavailableShadow(message);
    case StateWorkspaceFound(:final workspace):
      final bd = BdCliService(ProcessBdRunner(workspaceRoot: workspace.root));
      return AttemptLifecycleShadow(BdLegacySessionReader(bd.show));
  }
}
