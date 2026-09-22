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
    show
        Bead,
        BeadDependency,
        BdCliService,
        BdException,
        BeadStatus,
        DependencyType,
        ProcessBdRunner;
import 'package:grid_engine/grid_engine.dart'
    show
        DualReadMode,
        DualReadStepObserver,
        G2GraphEdgeObservation,
        G2GraphObservation,
        G2MoleculeObservation,
        G2SuccessorObservation,
        GridIssueTypes,
        MoleculeStepKeys,
        MountAttemptKeys,
        SessionBeadKeys,
        projectMountAttempt,
        projectSession;
import 'package:grid_sdk/grid_sdk.dart' show G2ShadowRoundAdapter;
import 'package:grid_trajectory/grid_trajectory.dart'
    show
        AttemptLifecycleShadow,
        CompositeShadow,
        LegacyG2EdgeView,
        LegacyG2GraphView,
        LegacyG2Reader,
        LegacyG2SuccessorView,
        LegacyMountAttemptReader,
        LegacySessionReader,
        LegacySessionView,
        LegacyStepReader,
        LegacyStepView,
        MountOrdinalShadow,
        ShadowCompare,
        ShadowCompareResult,
        ShadowCorroboration,
        MoleculePoured,
        StepSuperseded,
        StepTransitionShadow,
        SubjectRecords,
        TrajectoryCodec;

import 'state_workspace.dart';

/// Fetches session beads by id — [BdCliService.show]'s shape, injected so
/// tests script beads without spawning `bd`.
typedef SessionBeadFetch = Future<List<Bead>> Function(List<String> ids);

/// Fetches one session's `type=step` beads, injected for the same reason.
typedef StepBeadFetch = Future<List<Bead>> Function(String sessionId);

/// Fetches one work bead's `type=mount-attempt` beads (at most one exists).
typedef MountAttemptFetch = Future<List<Bead>> Function(String workBeadId);

/// Fetches the complete molecule/step graph for one session.
typedef G2GraphFetch =
    Future<({List<Bead> beads, List<BeadDependency> dependencies})> Function(
      String sessionId,
    );

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

/// Reads and normalizes the G2 legacy molecule and successor oracles.
class BdLegacyG2Reader implements LegacyG2Reader {
  BdLegacyG2Reader(BdCliService bd) : this.fromFetch((id) => _g2Graph(bd, id));

  BdLegacyG2Reader.fromFetch(this._fetch);

  final G2GraphFetch _fetch;

  @override
  Future<LegacyG2GraphView?> graphView(String sessionId) async {
    final graph = await _read(sessionId);
    final pathById = <String, String>{};
    for (final bead in graph.beads) {
      final path = bead.metadata[MoleculeStepKeys.path];
      if (bead.issueType == GridIssueTypes.step &&
          path is String &&
          path.isNotEmpty) {
        pathById[bead.id] = path;
      }
    }
    if (pathById.isEmpty) return null;
    final edges = <LegacyG2EdgeView>[];
    for (final dependency in graph.dependencies) {
      if (dependency.type != DependencyType.blocks &&
          dependency.type != DependencyType.validates) {
        continue;
      }
      final fromPath = pathById[dependency.issueId];
      final toPath = pathById[dependency.dependsOnId];
      if (fromPath == null || toPath == null) continue;
      edges.add(
        LegacyG2EdgeView(
          fromPath: fromPath,
          toPath: toPath,
          kind: dependency.type.wire,
        ),
      );
    }
    return LegacyG2GraphView(nodes: pathById.values, edges: edges);
  }

  @override
  Future<List<LegacyG2SuccessorView>> successorViews(String sessionId) async {
    final graph = await _read(sessionId);
    final byId = {for (final bead in graph.beads) bead.id: bead};
    final depths = _supersedesDepths(graph.beads, graph.dependencies);
    final successors = <LegacyG2SuccessorView>[];
    for (final dependency in graph.dependencies) {
      if (dependency.type != DependencyType.supersedes) continue;
      final successor = byId[dependency.issueId];
      final predecessor = byId[dependency.dependsOnId];
      if (successor == null || predecessor == null) continue;
      final path = successor.metadata[MoleculeStepKeys.path];
      if (path is! String ||
          predecessor.metadata[MoleculeStepKeys.path] != path) {
        continue;
      }
      successors.add(
        LegacyG2SuccessorView(
          stepPath: path,
          successorId: successor.id,
          supersedesId: predecessor.id,
          depth: depths[successor.id] ?? 0,
        ),
      );
    }
    return successors;
  }

  Future<({List<Bead> beads, List<BeadDependency> dependencies})> _read(
    String sessionId,
  ) async {
    try {
      return await _fetch(sessionId);
    } on BdException {
      return (beads: const <Bead>[], dependencies: const <BeadDependency>[]);
    }
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
    ShadowCorroboration corroboration = const ShadowCorroboration.none(),
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
      final g2Reader = BdLegacyG2Reader(bd);
      final g2Observer = DualReadStepObserver(mode: DualReadMode.observe);
      final g2Adapter = G2ShadowRoundAdapter(
        observer: g2Observer,
        appendDivergences: () => 0,
        flare: (_, _) {},
      );
      return CompositeShadow(
        [
          AttemptLifecycleShadow(BdLegacySessionReader(bd.show)),
          StepTransitionShadow(BdLegacyStepReader((id) => _stepBeads(bd, id))),
          MountOrdinalShadow(
            BdLegacyMountAttemptReader((id) => _mountAttemptBeads(bd, id)),
          ),
        ],
        g2Compare:
            ({
              required sessionId,
              required records,
              round,
              required corroboration,
            }) => _compareG2Round(
              reader: g2Reader,
              adapter: g2Adapter,
              sessionId: sessionId,
              records: records,
              round: round,
              corroboration: corroboration,
            ),
      );
  }
}

Future<ShadowCompareResult> _compareG2Round({
  required LegacyG2Reader reader,
  required G2ShadowRoundAdapter adapter,
  required String sessionId,
  required SubjectRecords records,
  required int? round,
  required ShadowCorroboration corroboration,
}) async {
  final decoded = [
    for (final envelope in records.records) TrajectoryCodec.decode(envelope),
  ];
  final pours = decoded.whereType<MoleculePoured>().where(
    (record) => round == null || record.round == round,
  );
  final pour = pours.isEmpty ? null : pours.last;
  final legacyGraph = await reader.graphView(sessionId);
  final legacySuccessors = await reader.successorViews(sessionId);
  final molecule = pour == null
      ? null
      : G2MoleculeObservation(
          sessionId: sessionId,
          round: pour.round,
          recordGraph: _recordGraph(pour),
          legacyGraph: _legacyGraph(legacyGraph),
          // G2-1 makes the apply-plan rendering an adapter from this exact
          // canonical record value. Keeping it as a separate oracle catches
          // a later adapter drift without deriving a second source graph.
          appliedPlanGraph: _recordGraph(pour),
        );
  final successorRecords = decoded.whereType<StepSuperseded>().where(
    (record) => round == null || record.round == round,
  );
  return adapter.compare(
    sessionId: sessionId,
    round: round ?? pour?.round ?? 0,
    headEpoch: records.records.isEmpty ? 0 : records.records.last.bootEpoch,
    molecule: molecule,
    successors: [
      for (final record in successorRecords)
        _successorObservation(record, legacySuccessors),
    ],
    foldComplete: records.isComplete,
    legacyWritePresent: legacyGraph != null,
    appendPresent: pour != null,
    attemptIds: {
      for (final envelope in records.records)
        if (envelope.attemptId case final String id) id,
    },
    epochs: {for (final envelope in records.records) envelope.bootEpoch},
    corroboration: corroboration,
  );
}

Map<String, int> _supersedesDepths(
  Iterable<Bead> beads,
  Iterable<BeadDependency> dependencies,
) {
  final stepIds = {
    for (final bead in beads)
      if (bead.issueType == GridIssueTypes.step) bead.id,
  };
  final priorBySuccessor = <String, String>{
    for (final dependency in dependencies)
      if (dependency.type == DependencyType.supersedes &&
          stepIds.contains(dependency.issueId) &&
          stepIds.contains(dependency.dependsOnId))
        dependency.issueId: dependency.dependsOnId,
  };
  final depths = <String, int>{};
  int depthOf(String id, Set<String> visiting) {
    final cached = depths[id];
    if (cached != null) return cached;
    final predecessor = priorBySuccessor[id];
    if (predecessor == null || !visiting.add(id)) return depths[id] = 0;
    final depth = 1 + depthOf(predecessor, visiting);
    visiting.remove(id);
    return depths[id] = depth;
  }

  for (final id in stepIds) {
    depthOf(id, <String>{});
  }
  return depths;
}

G2GraphObservation _recordGraph(MoleculePoured record) {
  final nodes = switch (record.graph['nodes']) {
    final Iterable<Object?> values => values.whereType<String>(),
    _ => const <String>[],
  };
  final edges = <G2GraphEdgeObservation>[];
  if (record.graph['edges'] case final Iterable<Object?> values) {
    for (final value in values) {
      if (value is! Map<Object?, Object?>) continue;
      final fromPath = value['from_path'];
      final toPath = value['to_path'];
      final kind = value['kind'];
      if (fromPath is String && toPath is String && kind is String) {
        edges.add(
          G2GraphEdgeObservation(
            fromPath: fromPath,
            toPath: toPath,
            kind: kind,
          ),
        );
      }
    }
  }
  return G2GraphObservation(nodes: nodes, edges: edges);
}

G2GraphObservation _legacyGraph(LegacyG2GraphView? graph) => G2GraphObservation(
  nodes: graph?.nodes ?? const {},
  edges: [
    for (final edge in graph?.edges ?? const <LegacyG2EdgeView>[])
      G2GraphEdgeObservation(
        fromPath: edge.fromPath,
        toPath: edge.toPath,
        kind: edge.kind,
      ),
  ],
);

G2SuccessorObservation _successorObservation(
  StepSuperseded record,
  List<LegacyG2SuccessorView> legacy,
) {
  LegacyG2SuccessorView? match;
  for (final candidate in legacy) {
    if (candidate.stepPath == record.stepPath &&
        candidate.depth == record.newStepRound) {
      match = candidate;
      break;
    }
  }
  return G2SuccessorObservation(
    sessionId: record.sessionId,
    round: record.round,
    stepPath: record.stepPath,
    newStepRound: record.newStepRound,
    recordPresent: true,
    legacyPresent: match != null,
    recordSupersedes: '${record.stepPath}:${record.oldStepRound}',
    legacySupersedes: match == null
        ? null
        : '${match.stepPath}:${match.depth - 1}',
    recordDepth: record.newStepRound,
    legacyDepth: match?.depth,
  );
}

Future<({List<Bead> beads, List<BeadDependency> dependencies})> _g2Graph(
  BdCliService bd,
  String sessionId,
) async {
  final molecule = await bd.listScope(
    type: GridIssueTypes.molecule,
    metadataFields: {'grid.circuit.session': sessionId},
    includeClosed: true,
  );
  final steps = await bd.listScope(
    type: GridIssueTypes.step,
    metadataFields: {MoleculeStepKeys.session: sessionId},
    includeClosed: true,
  );
  final dependencies = <String, BeadDependency>{
    for (final dependency in [...molecule.dependencies, ...steps.dependencies])
      dependency.edgeKey: dependency,
  };
  return (
    beads: [...molecule.beads, ...steps.beads],
    dependencies: dependencies.values.toList(growable: false),
  );
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
