import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

const _circuit = Circuit(
  id: 'done',
  terminalStepId: 'finish',
  steps: [CapabilityStep(stepId: 'finish', capabilityId: 'finish')],
);

class _SourceControl implements SourceControl {
  const _SourceControl();

  @override
  String get baseBranch => 'main';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  String workspaceFor(String beadId) => '/worktrees/$beadId';
}

class _RecordingReap {
  _RecordingReap(this.outcome, {this.error, this.eventLog});

  final ReapOutcome outcome;
  final Object? error;
  final List<String>? eventLog;
  final List<BeadWorktree> calls = [];

  Future<ReapOutcome> call({
    required RootCheckout root,
    required BeadWorktree worktree,
    bool dryRun = false,
    bool overrideUnsafe = false,
  }) async {
    eventLog?.add('reap');
    calls.add(worktree);
    if (error case final error?) throw error;
    return outcome;
  }
}

Future<void> _pump(TreeOwner owner) async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
    owner.flush();
  }
}

Future<void> _pumpUntil(TreeOwner owner, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

SessionProjection _projection(bool complete) => SessionProjection(
  workBeadId: 'tg-work',
  sessionId: 'tgdog-session',
  isTerminal: false,
  cursor: complete
      ? const {'tg-work/finish': NodeCursor(state: StepState.complete)}
      : const {},
);

SessionProjection _exhaustedProjection() => const SessionProjection(
  workBeadId: 'tg-work',
  sessionId: 'tgdog-session',
  isMolecule: true,
  moleculeBeads: [
    Bead(
      id: 'tgdog-finish',
      issueType: GridIssueTypes.step,
      metadata: {
        'rig': stateSubstation,
        MoleculeStepKeys.stepId: 'finish',
        MoleculeStepKeys.capability: 'finish',
        MoleculeStepKeys.kind: 'job',
        MoleculeStepKeys.path: 'tg-work/finish',
        MoleculeStepKeys.session: 'tgdog-session',
        MoleculeStepKeys.state: 'failed',
        MoleculeStepKeys.restartCount: '3',
      },
    ),
  ],
);

({TreeOwner owner, Fakes fakes, RecordingExplorationTransport transport})
_mount({
  required _RecordingReap reap,
  bool terminal = true,
  bool breakerExhausted = false,
  List<String>? eventLog,
}) {
  const beadId = 'tg-work';
  const sessionId = 'tgdog-session';
  final fakes = buildFakes(createdId: sessionId, eventLog: eventLog);
  final transport = RecordingExplorationTransport();
  final owner = TreeOwner();
  final session = breakerExhausted
      ? _exhaustedProjection()
      : _projection(false);
  final graph = GraphSnapshot.fromParts(
    beads: [bead(beadId)],
    dependencies: const [],
    readyIds: const {beadId},
    capturedAt: DateTime(2026),
  );
  final joined = JoinedSnapshotNotifier(
    JoinedSnapshot(graph: graph, sessionsByWorkBead: {beadId: session}),
  );
  owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(
              sourceControl: const _SourceControl(),
              transport: transport,
            ),
            child: InheritedSeed<CapabilityRegistry>(
              value: RecordingCapabilityRegistry(),
              child: InheritedSeed<SessionResolver>(
                value: CircuitResolver(
                  (_) => _circuit,
                  reapWorktree: reap.call,
                  workRoot: const RootCheckout(
                    path: '/root',
                    defaultBranch: 'main',
                    substation: 'tg',
                  ),
                ),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(
                      const SubstationConfig(
                        substationId: 'tg',
                        ownedSubstations: {'tg'},
                      ),
                    ),
                    services: ServiceBundle(
                      sourceControl: const _SourceControl(),
                      transport: transport,
                    ),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (terminal) {
    joined.push(
      JoinedSnapshot(
        graph: graph,
        sessionsByWorkBead: {beadId: _projection(true)},
      ),
    );
    owner.flush();
  }
  return (owner: owner, fakes: fakes, transport: transport);
}

void main() {
  test('positive terminal reaps before close', () async {
    final events = <String>[];
    final reap = _RecordingReap(ReapOutcome.removed(), eventLog: events);
    final mounted = _mount(reap: reap, eventLog: events);
    addTearDown(mounted.owner.dispose);

    await _pump(mounted.owner);

    expect(reap.calls, hasLength(1));
    expect(reap.calls.single.branch, 'grid/tg-work');
    expect(mounted.transport.named('session.worktreeReaped'), hasLength(1));
    expect(events.where((event) => event == 'reap'), hasLength(1));
    final reapIndex = events.indexOf('reap');
    final closeIndex = events.indexOf('bd:close');
    expect(reapIndex, isNonNegative);
    expect(closeIndex, isNonNegative);
    expect(reapIndex, lessThan(closeIndex));
  });

  test('breaker-exhaustion escalation never reaps the worktree', () async {
    final reap = _RecordingReap(ReapOutcome.removed());
    final mounted = _mount(reap: reap, terminal: false, breakerExhausted: true);
    addTearDown(mounted.owner.dispose);

    await _pumpUntil(mounted.owner, () {
      final escalated = mounted.fakes.runner
          .callsFor('update')
          .any((call) => call.join(' ').contains('grid.escalation'));
      final closed = mounted.fakes.runner
          .callsFor('close')
          .any((call) => call[1] == 'tgdog-session');
      return escalated && closed;
    });

    expect(
      mounted.fakes.runner
          .callsFor('update')
          .where((call) => call.join(' ').contains('grid.escalation')),
      hasLength(1),
    );
    expect(
      mounted.fakes.runner
          .callsFor('close')
          .where((call) => call[1] == 'tgdog-session'),
      hasLength(1),
    );
    expect(reap.calls, isEmpty);
    for (final flare in [
      'session.worktreeReaped',
      'session.worktreeReapHeld',
      'session.worktreeReapFailed',
    ]) {
      expect(mounted.transport.named(flare), isEmpty);
    }
  });

  test('refused reap names all three gates', () async {
    final reap = _RecordingReap(
      ReapOutcome.refused(
        uncommitted: GateOutcome.present,
        unpushed: GateOutcome.clear,
        stashed: GateOutcome.probeError,
        reason: 'uncommitted=present unpushed=clear stashes=probeError',
      ),
    );
    final mounted = _mount(reap: reap);
    addTearDown(mounted.owner.dispose);

    await _pump(mounted.owner);

    expect(reap.calls, hasLength(1));
    final flare = mounted.transport.named('session.worktreeReapHeld').first;
    expect(flare.data, containsPair('uncommitted', 'present'));
    expect(flare.data, containsPair('unpushed', 'clear'));
    expect(flare.data, containsPair('stashes', 'probeError'));
  });

  test('throwing reap flares and still closes', () async {
    final reap = _RecordingReap(
      ReapOutcome.removed(),
      error: StateError('reap failed'),
    );
    final mounted = _mount(reap: reap);
    addTearDown(mounted.owner.dispose);

    await _pump(mounted.owner);

    expect(reap.calls, hasLength(1));
    expect(mounted.transport.named('session.worktreeReapFailed'), hasLength(1));
    expect(
      mounted.fakes.runner.calls.map((call) => call.first),
      contains('close'),
    );
  });

  test('live session never reaps', () async {
    final reap = _RecordingReap(ReapOutcome.removed());
    final mounted = _mount(reap: reap, terminal: false);
    addTearDown(mounted.owner.dispose);

    await _pump(mounted.owner);

    expect(reap.calls, isEmpty);
  });
}
