/// grid_cli's side of the §9 shadow seam: the [LegacySessionReader],
/// [LegacyStepReader], and [LegacyMountAttemptReader] implemented over
/// beads_dart's read surface, plus the [ShadowCompareFactory]
/// `bin/grid.dart` hands `TrajCommand`.
///
/// grid_trajectory is a leaf (zero grid_* deps) and defines only the
/// interfaces; the beads_dart/grid_engine knowledge — `projectSession`'s
/// marker semantics, `rework.dart`'s `#rN` / `#void-` key shapes,
/// `MoleculeStepKeys`' step vocabulary, and `projectMountAttempt`'s ordinal —
/// lives HERE, reusing the exact read path the resident verbs use
/// (`resolveStateWorkspace` → exact-root state store → [BdCliService], never
/// a walk-up, never a raw SQL read of the ledger).
library;

import 'package:beads_dart/beads_dart.dart'
    show Bead, BdCliService, BdException, BeadStatus, ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart'
    show
        GridIssueTypes,
        MoleculeStepKeys,
        MountAttemptKeys,
        SessionBeadKeys,
        projectMountAttempt,
        projectSession;
import 'package:grid_trajectory/grid_trajectory.dart'
    show
        AttemptLifecycleShadow,
        CompositeShadow,
        LegacyMountAttemptReader,
        LegacySessionReader,
        LegacySessionView,
        LegacyStepReader,
        LegacyStepView,
        MountOrdinalShadow,
        ShadowCompare,
        ShadowCompareResult,
        StepTransitionShadow,
        SubjectRecords;

import 'state_workspace.dart';

/// Fetches session beads by id — [BdCliService.show]'s shape, injected so
/// tests script beads without spawning `bd`.
typedef SessionBeadFetch = Future<List<Bead>> Function(List<String> ids);

/// Fetches one session's `type=step` beads, injected for the same reason.
typedef StepBeadFetch = Future<List<Bead>> Function(String sessionId);

/// Fetches one work bead's `type=mount-attempt` beads (at most one exists).
typedef MountAttemptFetch = Future<List<Bead>> Function(String workBeadId);

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

/// Reads one session's step beads and projects them to the step-lane view.
class BdLegacyStepReader implements LegacyStepReader {
  BdLegacyStepReader(this._fetch);

  final StepBeadFetch _fetch;

  @override
  Future<List<LegacyStepView>> stepViews(String sessionId) async {
    try {
      return [
        for (final bead in await _fetch(sessionId))
          if (legacyStepViewOf(bead) case final LegacyStepView view) view,
      ];
    } on BdException {
      // "The ledger cannot answer" is not "the ledger says no steps": an
      // empty list is the reaped/absent case the lane treats as nothing to
      // compare, and a read failure must not be laundered into it. The lane
      // sees the same empty list either way, so the honest difference is
      // reported by the run's own bd failure, not invented here.
      return const [];
    }
  }
}

/// Pure projection of one `type=step` [bead] to the shadow view — the key
/// vocabulary is `MoleculeStepKeys`' (grid_engine owns that schema). Null for
/// a bead carrying no node path: without the path there is nothing to join on.
LegacyStepView? legacyStepViewOf(Bead bead) {
  final metadata = bead.metadata;
  final stepPath = '${metadata[MoleculeStepKeys.path] ?? ''}';
  if (stepPath.isEmpty) return null;
  final state = metadata[MoleculeStepKeys.state];
  final cooldown = metadata[MoleculeStepKeys.cooldownUntil];
  return LegacyStepView(
    stepPath: stepPath,
    // Absent means "no fine state yet" — honest, and the lane compares
    // nothing rather than reading bd's coarse open/closed axis as if it were
    // the six-valued one.
    state: state == null ? null : '$state',
    cooldownUntil: cooldown == null ? null : DateTime.tryParse('$cooldown'),
  );
}

/// Reads one work bead's durable remount ordinal (`grid.attempt.count`).
class BdLegacyMountAttemptReader implements LegacyMountAttemptReader {
  BdLegacyMountAttemptReader(this._fetch);

  final MountAttemptFetch _fetch;

  @override
  Future<int?> attemptCount(String workBeadId) async {
    final List<Bead> beads;
    try {
      beads = await _fetch(workBeadId);
    } on BdException {
      return null;
    }
    int? highest;
    for (final bead in beads) {
      final record = projectMountAttempt(bead);
      if (record == null || record.workBeadId != workBeadId) continue;
      if (highest == null || record.count > highest) highest = record.count;
    }
    return highest;
  }
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
/// and returns the REAL Stage-1 lane set — or, when the home carries no
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
      return CompositeShadow([
        AttemptLifecycleShadow(BdLegacySessionReader(bd.show)),
        StepTransitionShadow(BdLegacyStepReader((id) => _stepBeads(bd, id))),
        MountOrdinalShadow(
          BdLegacyMountAttemptReader((id) => _mountAttemptBeads(bd, id)),
        ),
      ]);
  }
}

/// One session's step beads, OPEN AND CLOSED. `bd list -t step` is
/// status-scoped, and a terminal step is exactly the one the step lane most
/// needs to compare — reading only the open half would silently shrink the
/// comparable set to steps still running.
Future<List<Bead>> _stepBeads(BdCliService bd, String sessionId) async {
  final fields = {MoleculeStepKeys.session: sessionId};
  final open = await bd.listScope(
    type: GridIssueTypes.step,
    metadataFields: fields,
  );
  final closed = await bd.listScope(
    type: GridIssueTypes.step,
    status: BeadStatus.closed,
    metadataFields: fields,
  );
  final byId = <String, Bead>{
    for (final bead in [...open.beads, ...closed.beads]) bead.id: bead,
  };
  return byId.values.toList(growable: false);
}

/// One work bead's mount-attempt record. The bead is a RECORD rather than
/// work and is never closed by the engine, but the closed scope is read too
/// so an operator-closed record cannot make the ordinal vanish mid-window.
Future<List<Bead>> _mountAttemptBeads(
  BdCliService bd,
  String workBeadId,
) async {
  final fields = {MountAttemptKeys.workBead: workBeadId};
  final open = await bd.listScope(
    type: GridIssueTypes.mountAttempt,
    metadataFields: fields,
  );
  final closed = await bd.listScope(
    type: GridIssueTypes.mountAttempt,
    status: BeadStatus.closed,
    metadataFields: fields,
  );
  final byId = <String, Bead>{
    for (final bead in [...open.beads, ...closed.beads]) bead.id: bead,
  };
  return byId.values.toList(growable: false);
}
