import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

final class _Head implements SessionHeadView {
  _Head({
    this.isOpen = true,
    this.outcome,
    this.pgid,
    this.pid,
    this.attemptId,
  });

  @override
  String get sessionId => 'session-1';
  @override
  String get workBeadId => 'work-1';
  @override
  final bool isOpen;
  @override
  final SessionHeadOutcome? outcome;
  @override
  final int? pgid;
  @override
  final int? pid;
  @override
  final String? attemptId;
  @override
  int get round => 0;
  @override
  bool get held => false;
  @override
  String? get heldReason => null;
  @override
  String? get workTerminalReason => null;
  @override
  SessionHeadProvenance? get terminalProvenance => null;
  @override
  String? get unknownReason => null;
  @override
  DateTime get startedAt => DateTime.utc(2026, 9, 7);
  @override
  DateTime? get closedAt => isOpen ? null : DateTime.utc(2026, 9, 7, 1);
  @override
  int get lastSeq => 1;
}

final class _HeadSnapshot implements TrajectoryHeadSnapshot {
  _HeadSnapshot(this._rows);

  final List<SessionHeadView> _rows;

  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  int get version => 7;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 9, 7);
  @override
  DateTime? get firstEpochClaimedAt => null;

  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in _rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) => sessionHeadWinnerOf([
    for (final row in _rows)
      if (row.workBeadId == workBeadId) row,
  ]);

  @override
  Iterable<SessionHeadView> get rows => _rows;
}

final class _StepRow implements StepCursorView {
  _StepRow({required this.stepState});

  @override
  String get sessionId => 'session-1';
  @override
  String get stepPath => 'build';
  @override
  final String stepState;
  @override
  int get round => 0;
  @override
  int get stepRound => 0;
  @override
  int get incarnation => 0;
  @override
  String? get attemptId => null;
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => null;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  int get lastSeq => 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  _StepSnapshot(this._rows);

  final List<StepCursorView> _rows;

  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  int get version => 8;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 9, 7);
  @override
  DateTime? get firstEpochClaimedAt => null;

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => [
    for (final row in _rows)
      if (row.sessionId == sessionId) row,
  ];
}

final class _Source implements SnapshotSource {
  _Source(this._current);

  final GraphSnapshot _current;
  final StreamController<GraphSnapshot> _controller =
      StreamController<GraphSnapshot>.broadcast();

  @override
  GraphSnapshot get current => _current;

  @override
  Stream<GraphSnapshot> get snapshots => _controller.stream;
}

GraphSnapshot _graph(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: beads.map((bead) => bead.id),
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Bead _work() => const Bead(
  id: 'work-1',
  issueType: IssueType.feature,
  status: BeadStatus.open,
);

Bead _sessionBead({bool terminal = false, bool scalarFence = true}) => Bead(
  id: 'session-1',
  issueType: GridIssueTypes.session,
  status: terminal ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'work_bead': 'work-1',
    SessionBeadKeys.model: kSessionModelMolecule,
    if (scalarFence) ...{
      SessionBeadKeys.pgid: '10',
      SessionBeadKeys.pid: '11',
      SessionBeadKeys.token: 'legacy-attempt',
    },
  },
);

Bead _stepBead(StepState state) => Bead(
  id: 'step-1',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.session: 'session-1',
    MoleculeStepKeys.path: 'build',
    MoleculeStepKeys.state: state.name,
  },
);

SessionProjection _moleculeSession({
  required StepState state,
  bool terminal = true,
  int? pgid,
  int? pid,
  String? token,
}) => SessionProjection(
  workBeadId: 'work-1',
  sessionId: 'session-1',
  isTerminal: terminal,
  isMolecule: true,
  moleculeBeads: [_stepBead(state)],
  pgid: pgid,
  pid: pid,
  token: token,
);

({StationJoinBridge bridge, DualReadAccounting accounting}) _bridge({
  required DualReadMode mode,
  required TrajectoryHeadSnapshot head,
  required TrajectoryStepSnapshot steps,
  StepState legacyState = StepState.running,
  bool terminal = false,
  bool scalarFence = true,
}) {
  final accounting = DualReadAccounting();
  final stepObserver = DualReadStepObserver(mode: mode, accounting: accounting);
  final bridge = StationJoinBridge(
    work: _Source(_graph([_work()])),
    state: _Source(
      _graph([
        _sessionBead(terminal: terminal, scalarFence: scalarFence),
        _stepBead(legacyState),
      ]),
    ),
    headSnapshot: () => head,
    stepSnapshot: () => steps,
    dualRead: DualReadSessionObserver(
      mode: mode,
      accounting: accounting,
      stepAxisEngaged: () => stepObserver.stepAxisEngaged,
    ),
    stepDualRead: stepObserver,
  );
  return (bridge: bridge, accounting: accounting);
}

void main() {
  test('off and observe keep the raw molecule cursor', () {
    for (final mode in [DualReadMode.off, DualReadMode.observe]) {
      final joined = _bridge(
        mode: mode,
        head: _HeadSnapshot([
          _Head(isOpen: false, outcome: SessionHeadOutcome.failed),
        ]),
        steps: _StepSnapshot([_StepRow(stepState: 'complete')]),
        legacyState: StepState.complete,
        terminal: true,
        scalarFence: false,
      );
      addTearDown(joined.bridge.dispose);
      final session = joined.bridge.latest.sessionsByWorkBead['work-1']!;
      expect(session.trajCursor, isNull, reason: mode.name);
      expect(session.cursor, isEmpty, reason: mode.name);
      expect(session.moleculeBeads, isNotEmpty, reason: mode.name);
      expect(
        sessionDispositionOf(session),
        isA<VoidedSession>(),
        reason: mode.name,
      );
      expect(staleFences(session), isEmpty, reason: mode.name);
    }
  });

  test('primary reads P2 and P1 for disposition and fences', () {
    final terminalHead = _Head(
      isOpen: false,
      outcome: SessionHeadOutcome.failed,
      pgid: 41,
      pid: 42,
      attemptId: 'attempt-fold',
    );
    final done = _bridge(
      mode: DualReadMode.primary,
      head: _HeadSnapshot([terminalHead]),
      steps: _StepSnapshot([_StepRow(stepState: 'complete')]),
    );
    addTearDown(done.bridge.dispose);
    final doneSession = done.bridge.latest.sessionsByWorkBead['work-1']!;
    expect(doneSession.trajCursor!['build']!.state, StepState.complete);
    expect(doneSession.trajPgid, 41);
    expect(doneSession.trajPid, 42);
    expect(doneSession.trajAttemptId, 'attempt-fold');
    expect(sessionDispositionOf(doneSession), isA<DoneSession>());

    final runningHead = _Head(pgid: 51, pid: 52, attemptId: 'attempt-running');
    final running = _bridge(
      mode: DualReadMode.primary,
      head: _HeadSnapshot([runningHead]),
      steps: _StepSnapshot([_StepRow(stepState: 'running')]),
    );
    addTearDown(running.bridge.dispose);
    final runningSession = running.bridge.latest.sessionsByWorkBead['work-1']!;
    expect(runningSession.cursor, isEmpty);
    final fence = staleFences(runningSession).single;
    expect((fence.pgid, fence.pid, fence.token), (51, 52, 'attempt-running'));
    expect(staleFences(runningSession.copyWith(trajPid: null)), isEmpty);
  });

  test('primary missing P2 counts one legacy fallback', () {
    final head = _Head(
      isOpen: false,
      outcome: SessionHeadOutcome.failed,
      pgid: 51,
      pid: 52,
      attemptId: 'attempt-running',
    );
    final p2Gap = _bridge(
      mode: DualReadMode.primary,
      head: _HeadSnapshot([head]),
      steps: _StepSnapshot(const []),
      terminal: true,
    );
    addTearDown(p2Gap.bridge.dispose);
    final legacy = p2Gap.bridge.latest.sessionsByWorkBead['work-1']!;
    expect(legacy.trajCursor, isNull);
    expect(legacy.trajPgid, isNull);
    expect(sessionDispositionOf(legacy), isA<VoidedSession>());
    final legacyFence = staleFences(legacy).single;
    expect(
      (legacyFence.pgid, legacyFence.pid, legacyFence.token),
      (10, 11, 'legacy-attempt'),
    );
    expect(p2Gap.accounting.stepFallbacks, 1);
    expect(p2Gap.accounting.fallbacks, 1);

    final p1Gap = _bridge(
      mode: DualReadMode.primary,
      head: _HeadSnapshot(const []),
      steps: _StepSnapshot([_StepRow(stepState: 'running')]),
      terminal: true,
    );
    addTearDown(p1Gap.bridge.dispose);
    expect(
      p1Gap.bridge.latest.sessionsByWorkBead['work-1']!.trajCursor,
      isNull,
    );
    expect(p1Gap.accounting.stepFallbacks, 1);
    expect(p1Gap.accounting.fallbacks, 1);
  });

  test('empty cursor rule follows the literal fold cursor', () {
    final emptyFold = _moleculeSession(
      state: StepState.complete,
    ).copyWith(trajCursor: const {});
    expect(emptyFold.moleculeBeads, isNotEmpty);
    expect(sessionDispositionOf(emptyFold), isA<VoidedSession>());

    const foldedComplete = SessionProjection(
      workBeadId: 'work-1',
      sessionId: 'session-1',
      isTerminal: true,
      isMolecule: true,
      trajCursor: {'build': NodeCursor(state: StepState.complete)},
    );
    expect(foldedComplete.moleculeBeads, isEmpty);
    expect(sessionDispositionOf(foldedComplete), isA<DoneSession>());
  });

  test('observe compares fold-backed mount facts', () {
    final flares = <(String, Map<String, String>)>[];
    final observer = DualReadSessionObserver(
      mode: DualReadMode.observe,
      onFlare: (name, data) => flares.add((name, data)),
    );
    final head = _Head(
      isOpen: false,
      outcome: SessionHeadOutcome.failed,
      pgid: 20,
      pid: 21,
      attemptId: 'fold-attempt',
    );
    observer.observe(
      {
        'work-1': _moleculeSession(
          state: StepState.running,
          pgid: 10,
          pid: 11,
          token: 'legacy-attempt',
        ),
      },
      _HeadSnapshot([head]),
      steps: _StepSnapshot([_StepRow(stepState: 'complete')]),
    );

    final mountFlares = [
      for (final (name, data) in flares)
        if (name == kDualReadDivergenceFlare &&
            data['cause'] == 'fold-backed-mount-facts')
          data,
    ];
    expect(
      mountFlares.map((flare) => flare['field']),
      unorderedEquals(['sessionDisposition', 'staleFences']),
    );
    expect(observer.accounting.foldBackedMountFactDivergences, 2);
    final json = observer.accounting.toJson(
      mode: DualReadMode.observe,
      health: TrajectorySnapshotHealth.live,
      snapshotVersion: 7,
    );
    expect(json['fold_backed_mount_fact_divergences'], 2);
    expect(
      (json['counter_semantics']!
          as Map<String, String>)['fold_backed_mount_fact_divergences'],
      'cumulative',
    );

    final agreeingFlares = <(String, Map<String, String>)>[];
    final agreeing = DualReadSessionObserver(
      mode: DualReadMode.observe,
      onFlare: (name, data) => agreeingFlares.add((name, data)),
    );
    agreeing.observe(
      {
        'work-1':
            _moleculeSession(
              state: StepState.running,
              pgid: 20,
              pid: 21,
              token: 'fold-attempt',
            ).copyWith(
              cursor: const {
                'build': NodeCursor(
                  state: StepState.running,
                  pgid: 20,
                  pid: 21,
                  token: 'fold-attempt',
                ),
              },
            ),
      },
      _HeadSnapshot([head]),
      steps: _StepSnapshot([_StepRow(stepState: 'running')]),
    );
    expect(agreeing.accounting.foldBackedMountFactDivergences, 0);
    expect(
      agreeingFlares.where(
        (event) => event.$2['cause'] == 'fold-backed-mount-facts',
      ),
      isEmpty,
    );
  });
}
