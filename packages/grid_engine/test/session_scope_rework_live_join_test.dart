// tg-zat — reproduces the live rework re-arm through the REAL
// StationJoinBridge (not the hand-rolled `_joined()` snapshots
// `session_scope_rework_test.dart` builds by hand), so the join's own
// `work_bead` re-key handling is exercised exactly as `grid rework` +
// `StationJoinBridge._join` produce it, with a genuine OPEN `type=gate`
// bead in the mix (D-7) — the piece the hand-rolled test never modeled.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(
      stepId: 'verify',
      capabilityId: 'verify',
      dependsOn: {'agent'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((flare) => flare.name == name).toList();
}

final class _ThrowingGateUpdateRunner extends RecordingBdRunner {
  _ThrowingGateUpdateRunner() : super(createdId: 'tgdog-round2');

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (args.length > 1 && args.first == 'update' && args[1] == 'gate-1') {
      throw StateError('controlled gate update failure');
    }
    return result;
  }
}

Fakes _fakesOver(RecordingBdRunner runner) {
  final provider = FakeRuntimeProvider();
  final git = RecordingGitRunner();
  final pr = FakePrOpener();
  return (
    ctx: StationServices(
      provider: provider,
      writer: StationBeadWriter(
        bd: BdCliService(runner),
        reader: runner,
        ownership: BeadOwnershipPredicate(const {stateSubstation, 'gate'}),
      ),
      stateSubstation: stateSubstation,
    ),
    runner: runner,
    provider: provider,
    git: git,
    pr: pr,
  );
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains multiple bd round-trips (`createSession`, THEN
/// `createMolecule`'s dedup-probe export + graph-apply pour — the latter a
/// REAL temp-file write, `BdCliService.applyGraph`'s plan.json) rather than
/// the flat model's single in-memory `create`, so a real-time cushion is
/// what makes waiting for round N+1's mint deterministic under load
/// (tg-eli phase 2).
Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

GraphSnapshot _state(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: const [],
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

/// A the_grid MOLECULE session bead exactly as `grid rework`'s CLI-observed
/// shape: linked to [workBead] — or, after the CLI's re-key, linked to
/// `'$originalBead#r1'` while every OTHER key is left untouched (bd's
/// `--metadata` merge, not a replace). Round 1's PER-NODE state (`agent`/
/// `verify` complete, `route` GATED — a committee park) lives on its own
/// companion `type=step` beads ([_round1Steps], tg-eli phase 2), never on
/// this bead's metadata.
Bead _round1Session(String id, {required String workBead}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    SessionBeadKeys.model: kSessionModelMolecule,
  },
);

Bead _closedRound1Session(String id, {required String workBead}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.closed,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    SessionBeadKeys.model: kSessionModelMolecule,
    SessionBeadKeys.outcome: kSessionOutcomeComplete,
  },
);

/// Round 1's per-node `type=step` beads, owned by [sessionId]: `agent`/
/// `verify` complete, `route` GATED (a committee park) — the stale gate
/// cursor `grid rework` leaves standing across the re-key (it re-keys the
/// SESSION's `work_bead` only, never these step beads).
List<Bead> _round1Steps(String sessionId) => [
  Bead(
    id: 'tgdog-step-agent',
    issueType: GridIssueTypes.step,
    status: BeadStatus.closed,
    metadata: {
      'rig': stateSubstation,
      MoleculeStepKeys.stepId: 'agent',
      MoleculeStepKeys.capability: 'agent',
      MoleculeStepKeys.kind: StepKind.job.name,
      MoleculeStepKeys.path: 'tg-1/agent',
      MoleculeStepKeys.session: sessionId,
      MoleculeStepKeys.state: StepState.complete.name,
    },
  ),
  Bead(
    id: 'tgdog-step-verify',
    issueType: GridIssueTypes.step,
    status: BeadStatus.closed,
    metadata: {
      'rig': stateSubstation,
      MoleculeStepKeys.stepId: 'verify',
      MoleculeStepKeys.capability: 'verify',
      MoleculeStepKeys.kind: StepKind.job.name,
      MoleculeStepKeys.path: 'tg-1/verify',
      MoleculeStepKeys.session: sessionId,
      MoleculeStepKeys.state: StepState.complete.name,
    },
  ),
  Bead(
    id: 'tgdog-step-route',
    issueType: GridIssueTypes.step,
    status: BeadStatus.open,
    metadata: {
      'rig': stateSubstation,
      MoleculeStepKeys.stepId: 'route',
      MoleculeStepKeys.capability: 'route',
      MoleculeStepKeys.kind: StepKind.job.name,
      MoleculeStepKeys.path: 'tg-1/route',
      MoleculeStepKeys.session: sessionId,
      MoleculeStepKeys.state: StepState.gated.name,
    },
  ),
];

/// The OPEN committee gate `grid rework` leaves standing (D-7) — it blocks
/// [sessionId] at `tg-1/route`; `grid rework` re-keys the SESSION, never this
/// bead, so it stays open across the rekey exactly like the live incident.
Bead _openGate(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: GridIssueTypes.gate,
  status: BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': sessionId, 'node': 'tg-1/route'},
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
  ExplorationTransport? transport,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: registry,
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver(rootCircuit),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'tg',
                      ownedSubstations: {'tg'},
                    ),
                  ),
                  services: ServiceBundle(transport: transport),
                  key: const ValueKey('scope.tg'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('SessionScope rework re-arm through the REAL StationJoinBridge', () {
    Future<void> runStaleGateRework({
      required RecordingBdRunner runner,
      required _RecordingTransport transport,
    }) async {
      final f = _fakesOver(runner);
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final original = _round1Session('tgdog-round1', workBead: 'tg-1');
      final gate = _openGate('gate-1', sessionId: 'tgdog-round1');
      final steps = _round1Steps('tgdog-round1');
      runner.exportBeads = [original, ...steps, gate];
      final workSrc = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final stateSrc = FakeSnapshotSource(_state([original, ...steps, gate]));
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);
      final m = _mountFull(
        joined: bridge.notifier,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();
      await _pump();

      stateSrc.push(
        _state([
          _round1Session('tgdog-round1', workBead: 'tg-1#r1'),
          ...steps,
          gate,
        ], tick: 1),
      );
      workSrc.push(
        _work(
          [bead('tg-1')],
          {'tg-1'},
          tick: DateTime.now()
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
      );
      await _pumpUntil(m.owner, () => runner.workCreates.length >= 2);
    }

    test(
      'stale session reader preserves causal close and fresh mint',
      () async {
        final runner = RecordingBdRunner(createdId: 'tgdog-round2');
        final transport = _RecordingTransport();
        await runStaleGateRework(runner: runner, transport: transport);

        expect(
          runner.callsFor('close').map((call) => call[1]),
          containsAllInOrder(['tgdog-round1', 'gate-1']),
          reason: '${transport.flares}',
        );
        expect(
          runner
              .callsFor('update')
              .singleWhere(
                (call) =>
                    call.length > 1 &&
                    call[1] == 'gate-1' &&
                    call
                        .join(' ')
                        .contains(StationBeadWriter.gateCloseCauseKey),
              )
              .join(' '),
          contains('${StationBeadWriter.gateCloseCauseKey}=superseded-round'),
        );
        expect(transport.named('gate.autoCloseFailed'), isEmpty);
        expect(
          runner.workCreates.where((call) => !call.contains('--graph')),
          hasLength(1),
        );
        expect(
          runner.workCreates.where((call) => call.contains('--graph')),
          hasLength(1),
        );
      },
    );

    test('failed retired gate cleanup cannot consume the fresh mint', () async {
      final runner = _ThrowingGateUpdateRunner();
      final transport = _RecordingTransport();
      await runStaleGateRework(runner: runner, transport: transport);

      final sessionClose = runner.calls.indexWhere(
        (call) => call.first == 'close' && call[1] == 'tgdog-round1',
      );
      final gateUpdate = runner.calls.indexWhere(
        (call) => call.first == 'update' && call[1] == 'gate-1',
      );
      expect(sessionClose, lessThan(gateUpdate));
      final failed = transport.named('gate.autoCloseFailed');
      expect(failed, hasLength(1));
      expect(failed.single.data, containsPair('sessionId', 'tgdog-round1'));
      expect(
        failed.single.data,
        containsPair('cause', GateCloseCause.supersededRound.wireValue),
      );
      expect(
        runner.workCreates.where((call) => !call.contains('--graph')),
        hasLength(1),
        reason: 'calls=${runner.calls} flares=${transport.flares}',
      );
      expect(
        runner.workCreates.where((call) => call.contains('--graph')),
        hasLength(1),
      );
    });

    test('a GATED round re-keyed by `grid rework` (leaving its gate bead OPEN, '
        'exactly as the CLI does) still closes the retired round and mints '
        'round N+1 — proving the join itself is not where the live deviation '
        'comes from', () async {
      final f = buildFakes(createdId: 'tgdog-round2');
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final transport = _RecordingTransport();

      final workSrc = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final stateSrc = FakeSnapshotSource(
        _state([
          _round1Session('tgdog-round1', workBead: 'tg-1'),
          ..._round1Steps('tgdog-round1'),
          _openGate('gate-1', sessionId: 'tgdog-round1'),
        ]),
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();
      await _pump();

      // Adopted synchronously — round 1's gated session, no mint.
      expect(f.runner.workCreates, isEmpty);

      // `grid rework tg-1`: re-keys ONLY `work_bead` on the SAME session
      // bead (bd `--metadata` merge — every other key, incl. the stale
      // `route` cursor, survives byte-identical) and leaves the gate bead
      // it never touches OPEN, exactly like the resident command rework path.
      final reworkDecisionAt = DateTime.now();
      stateSrc.push(
        _state([
          _round1Session('tgdog-round1', workBead: 'tg-1#r1'),
          ..._round1Steps('tgdog-round1'),
          _openGate('gate-1', sessionId: 'tgdog-round1'),
        ], tick: 1),
      );
      workSrc.push(
        _work(
          [bead('tg-1')],
          {'tg-1'},
          tick: reworkDecisionAt
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
      );
      await _pumpUntil(
        m.owner,
        () =>
            reg.events.contains('START agent(tgdog-round2/tg-1/agent)') &&
            f.runner.workCreates.length >= 2,
      );

      // The retired round-1 session is closed (D-2 fold).
      final closes = f.runner.callsFor('close');
      expect(closes.where((call) => call[1] == 'tgdog-round1'), hasLength(1));
      expect(
        closes.singleWhere((call) => call[1] == 'tgdog-round1').join(' '),
        contains('reworked'),
      );

      // Round 2 minted fresh — a SECOND createSession (+ its molecule pour,
      // tg-eli phase 2), a NEW id — never a reuse of tgdog-round1.
      final creates = f.runner.workCreates;
      expect(
        SessionScopeState.freshMintSnapshotGrace,
        const Duration(seconds: 90),
      );
      expect(transport.named('session.mintAbandoned'), isEmpty);
      expect(creates.where((call) => !call.contains('--graph')), hasLength(1));
      expect(creates.where((call) => call.contains('--graph')), hasLength(1));

      // The fresh round's leaf mounts under the NEW session id, from a
      // virgin cursor (never the stale `route: gated` carried over).
      expect(reg.events, contains('START agent(tgdog-round2/tg-1/agent)'));
    });

    test(
      'a re-keyed round mints on a QUIET board — no fresh work publish ever '
      'arrives (change-gated pipeline): the SESSION view, not the snapshot '
      'clock, is the staleness evidence (2026-08-07 afternoon wedge)',
      () async {
        SessionScopeState.freshMintSnapshotGrace = const Duration(
          milliseconds: 60,
        );
        addTearDown(
          () => SessionScopeState.freshMintSnapshotGrace = const Duration(
            seconds: 90,
          ),
        );
        final f = buildFakes(createdId: 'tgdog-round2');
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final transport = _RecordingTransport();

        // The work snapshot is OLD (tick 0) and will NEVER republish — the
        // exact quiet-board shape: an unchanged store's floor refresh
        // publishes nothing, so capturedAt cannot pass any decision time.
        final workSrc = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final stateSrc = FakeSnapshotSource(
          _state([_closedRound1Session('tgdog-round1', workBead: 'tg-1')]),
        );
        final bridge = StationJoinBridge(work: workSrc, state: stateSrc)
          ..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          transport: transport,
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();
        expect(f.runner.workCreates, isEmpty);

        // The operator re-keys round 1 (the ONLY store change — state side).
        stateSrc.push(
          _state([
            _closedRound1Session('tgdog-round1', workBead: 'tg-1#r1'),
          ], tick: 1),
        );
        // NO work push. Pre-fix this hung forever in
        // _awaitFreshReadySnapshot (capturedAt < decisionAt, return),
        // parking every post-rework mint on a quiet board.
        await _pumpUntil(
          m.owner,
          () =>
              reg.events.contains('START agent(tgdog-round2/tg-1/agent)') &&
              f.runner.workCreates.length >= 2,
        );

        expect(
          reg.events,
          contains('START agent(tgdog-round2/tg-1/agent)'),
          reason:
              'the joined view already shows tg-1 ready + sessionless — '
              'the mint must not wait for a publish that never comes',
        );
        expect(
          f.runner.workCreates.where((call) => !call.contains('--graph')),
          hasLength(1),
        );
        expect(
          stateSrc.current!.beads.where(
            (bead) =>
                bead.issueType == GridIssueTypes.session &&
                bead.metadata[SessionBeadKeys.workBead] == 'tg-1#r1',
          ),
          hasLength(1),
        );
        expect(transport.named('session.mintAbandoned'), isEmpty);

        stateSrc.push(
          _state([
            _closedRound1Session('tgdog-round1', workBead: 'tg-1#r1'),
          ], tick: 2),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        final creates = f.runner.workCreates;
        expect(
          creates.where((call) => !call.contains('--graph')),
          hasLength(1),
        );
        expect(creates.where((call) => call.contains('--graph')), hasLength(1));
        expect(
          f.runner.callsFor('close').where((call) => call[1] == 'tgdog-round1'),
          hasLength(1),
        );
      },
    );

    test('a CLOSED round re-keyed by `grid rework` remounts through the same '
        'owner and mints round N+1 without a restart', () async {
      final f = buildFakes(createdId: 'tgdog-round2');
      final reg = RecordingCapabilityRegistry(circuits: const {});

      final workSrc = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final stateSrc = FakeSnapshotSource(
        _state([_closedRound1Session('tgdog-round1', workBead: 'tg-1')]),
      );
      final bridge = StationJoinBridge(work: workSrc, state: stateSrc)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();
      await _pump();

      expect(f.runner.workCreates, isEmpty);

      stateSrc.push(
        _state([
          _closedRound1Session('tgdog-round1', workBead: 'tg-1#r1'),
        ], tick: 1),
      );
      workSrc.push(
        _work(
          [bead('tg-1')],
          {'tg-1'},
          tick: DateTime.now()
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        ),
      );
      await _pumpUntil(
        m.owner,
        () =>
            reg.events.contains('START agent(tgdog-round2/tg-1/agent)') &&
            f.runner.workCreates.length >= 2,
      );

      final closes = f.runner.callsFor('close');
      expect(closes.where((call) => call[1] == 'tgdog-round1'), hasLength(1));
      expect(
        closes.singleWhere((call) => call[1] == 'tgdog-round1').join(' '),
        contains('reworked'),
      );

      final creates = f.runner.workCreates;
      expect(creates.where((call) => !call.contains('--graph')), hasLength(1));
      expect(creates.where((call) => call.contains('--graph')), hasLength(1));
      expect(reg.events, contains('START agent(tgdog-round2/tg-1/agent)'));
    });
  });
}
