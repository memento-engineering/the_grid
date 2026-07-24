import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

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
  _RecordingReap(this.outcome, {this.error});

  final ReapOutcome outcome;
  final Object? error;
  final List<BeadWorktree> calls = [];

  Future<ReapOutcome> call({
    required RootCheckout root,
    required BeadWorktree worktree,
  }) async {
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

SessionProjection _projection(bool complete) => SessionProjection(
  workBeadId: 'tg-work',
  sessionId: 'tgdog-session',
  isTerminal: false,
  cursor: complete
      ? const {'tg-work/finish': NodeCursor(state: StepState.complete)}
      : const {},
);

({TreeOwner owner, Fakes fakes, RecordingExplorationTransport transport})
_mount({required _RecordingReap reap, bool terminal = true}) {
  const beadId = 'tg-work';
  const sessionId = 'tgdog-session';
  final fakes = buildFakes(createdId: sessionId);
  final transport = RecordingExplorationTransport();
  final owner = TreeOwner();
  final session = _projection(false);
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
    InheritedSeed<JoinedSnapshotNotifier>(
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
    final reap = _RecordingReap(ReapOutcome.removed());
    final mounted = _mount(reap: reap);
    addTearDown(mounted.owner.dispose);

    await _pump(mounted.owner);

    expect(reap.calls, hasLength(1));
    expect(reap.calls.single.branch, 'grid/tg-work');
    expect(mounted.transport.named('session.worktreeReaped'), hasLength(1));
    final commands = mounted.fakes.runner.calls.map((call) => call.first);
    expect(commands, containsAllInOrder(<String>['update', 'close']));
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
