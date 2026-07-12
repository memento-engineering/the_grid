// tg-b3k — the loop edge: a MACHINE-ACTIONABLE (`respec:`) gate is AUTO-RESOLVED
// (the round is re-keyed + the gate bead closes) with no human, while a HUMAN
// gate parks exactly as today and the round cap refuses LOUD.
//
// The route→specify respec loop is not expressible as an asset-side route
// verdict (`StepOutcome` is sealed {Ok, Failed, Gate}; a `CapabilityHost` only
// ever writes its OWN node's cursor; the D-7 re-arm alone re-reads the same
// sibling grades and re-gates). The loop edge is the ENGINE's, and `SessionScope`
// is the ONE node that already owns the gate observation, the session lifecycle,
// and the rework transition.
//
// Wiring-shaped: the REAL `StationJoinBridge` + the full `Station → … →
// SessionScope` tree. Zero I/O: fakes + the recording chokepoint + a fake
// transport.
import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// The spec circuit: `specify → route → land`. A route park is what the asset's
/// spec-route matrix produces; re-running the ROUND (not just the route node) is
/// what re-runs `specify` against the asset's on-disk guidance ledger.
const _spec = Circuit(
  id: 'spec',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'specify', capabilityId: 'specify'),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'specify'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'route'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drives the tree to a fixed point: the auto-respec chain is several scheduled
/// writes deep (re-key → the orphan-check rebuild → close-and-remint → the round-2
/// mount), so one pump/flush pair is not enough. A flush over a clean tree is a
/// no-op, so this never manufactures a rebuild the engine would not do itself —
/// a transition that needs a fresh JOIN tick still waits for one.
Future<void> _settle(TreeOwner owner) async {
  for (var i = 0; i < 6; i++) {
    await _pump();
    owner.flush();
  }
  await _pump();
}

/// The `--metadata` payloads of every `update` targeting [id], in order.
///
/// The chokepoint's `close` stamps a `closed_at` UPDATE on its own target before
/// closing it, so a raw `update` count mixes the session's writes with the gate
/// bead's close-stamp — a test that means "the writes to the SESSION bead" must
/// filter by target.
List<Map<String, dynamic>> _updatesOn(List<List<String>> calls, String id) => [
  for (final c in calls)
    if (c.isNotEmpty && c.first == 'update' && c.length > 1 && c[1] == id)
      jsonDecode(c[c.indexOf('--metadata') + 1]) as Map<String, dynamic>,
];

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

/// A session bead with `specify` complete and `route` PARKED (the spec-route
/// park), linked to [workBead].
Bead _parkedSession(String id, {required String workBead}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    ...nodeStateMetadata('tg-1/specify', StepState.complete),
    ...nodeStateMetadata('tg-1/route', StepState.gated),
  },
);

/// The gate bead the route minted — [reason] is the asset↔engine contract.
Bead _gate(
  String id, {
  required String sessionId,
  required String reason,
  bool closed = false,
}) => Bead(
  id: id,
  issueType: IssueType.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    'blocks': sessionId,
    'node': 'tg-1/route',
    'reason': reason,
  },
);

/// A RETIRED round: a closed session whose `work_bead` is `tg-1#r<N>` (what the
/// re-key leaves behind) — the join counts these into `reworkRounds`.
Bead _retiredRound(String id, int round) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.closed,
  metadata: {'rig': stateSubstation, SessionBeadKeys.workBead: 'tg-1#r$round'},
);

/// An [ExplorationTransport] that records every LOUD flare — the emit-only sink
/// the auto-respec signals fire through.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((f) => f.name == name).toList();

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

/// A [BdRunner] that FAILS the first [failUpdates] `update` calls (throwing, as
/// a live `bd` blip would) then succeeds — so a test can drive a DROPPED re-key
/// (or a dropped cap marker) and prove the next build RETRIES.
class _FailFirstUpdateRunner implements BdRunner {
  _FailFirstUpdateRunner({this.failUpdates = 1});

  final int failUpdates;
  final List<List<String>> calls = <List<String>>[];
  int _updates = 0;

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  Map<String, dynamic> metadataOfUpdate(int index) {
    final c = callsFor('update')[index];
    final i = c.indexOf('--metadata');
    return jsonDecode(c[i + 1]) as Map<String, dynamic>;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'update') {
      _updates++;
      if (_updates <= failUpdates) {
        throw StateError('fake bd update failure #$_updates (tg-b3k)');
      }
    }
    final data = switch (sub) {
      'create' => '{"id":"tgdog-sess1"}',
      _ => '{"id":"${args.length >= 2 ? args[1] : ''}"}',
    };
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":$data}',
      stderr: '',
    );
  }
}

/// A [BdRunner] that FAILS the first [failCloses] `close` calls then succeeds —
/// so a test can drive a DROPPED GATE-CLOSE (the one irreversible step) and prove
/// it FLARES and is NOT retried. `update` always succeeds, so the re-key lands
/// first.
class _FailCloseRunner implements BdRunner {
  _FailCloseRunner({this.failCloses = 1});

  final int failCloses;
  final List<List<String>> calls = <List<String>>[];
  int _closes = 0;

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  Map<String, dynamic> metadataOfUpdate(int index) {
    final c = callsFor('update')[index];
    final i = c.indexOf('--metadata');
    return jsonDecode(c[i + 1]) as Map<String, dynamic>;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'close') {
      _closes++;
      if (_closes <= failCloses) {
        throw StateError('fake bd close failure #$_closes (tg-b3k)');
      }
    }
    final data = switch (sub) {
      'create' => '{"id":"tgdog-sess2"}',
      _ => '{"id":"${args.length >= 2 ? args[1] : ''}"}',
    };
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":$data}',
      stderr: '',
    );
  }
}

/// A recording [SourceControl]: the workspace is derived from the BEAD id, so a
/// re-mint of the same bead necessarily lands in the SAME workspace (where the
/// asset's on-disk guidance ledger survives the round). Records every
/// `workspaceFor` call so a test proves both rounds asked for the same bead.
class _RecordingSourceControl implements SourceControl {
  final List<String> workspaceForCalls = [];

  @override
  String workspaceFor(String beadId) {
    workspaceForCalls.add(beadId);
    return '/ws/$beadId';
  }

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  String get baseBranch => 'main';

  @override
  bool get canLand => false;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) async {}

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {}

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async => null;
}

/// A [StationServices] whose chokepoint writes through [runner] (a recording
/// fake), owning [stateSubstation].
StationServices _ctxOver(BdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  ServiceBundle services = const ServiceBundle(),
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<SessionResolver>(
            value: CircuitResolver((_) => _spec),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(
                  const SubstationConfig(
                    substationId: 'tg',
                    ownedSubstations: {'tg'},
                  ),
                ),
                services: services,
                key: const ValueKey('scope.tg'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('auto-respec: the loop edge (tg-b3k)', () {
    test('the join projects the gate id, reason and retired-round count', () async {
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _parkedSession('tgdog-r1', workBead: 'tg-1'),
          _gate(
            'tgdog-g1',
            sessionId: 'tgdog-r1',
            reason: 'respec: round=1 lane=adr-alignment grade=D',
          ),
          _retiredRound('tgdog-old', 1),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final projection = bridge.latest.sessionsByWorkBead['tg-1']!;
      final gate = projection.openGates['tg-1/route']!;
      expect(gate.gateId, 'tgdog-g1');
      expect(gate.nodePath, 'tg-1/route');
      expect(
        gate.reason,
        startsWith(kRespecGatePrefix),
        reason: 'the asset↔engine contract token reaches the tree pull-free',
      );
      expect(
        projection.openGateNodes,
        {'tg-1/route'},
        reason: 'the D-7 re-arm signal is DERIVED from the gate records',
      );
      expect(
        projection.reworkRounds,
        1,
        reason: 'the join counts the retired `tg-1#r1` round',
      );
    });

    test('auto-resolves a respec gate: re-key THEN close, no human', () async {
      final runner = RecordingBdRunner();
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _parkedSession('tgdog-r1', workBead: 'tg-1'),
          _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=1'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // EXACTLY two writes on the two beads, in this order: the SESSION is
      // re-keyed, then the GATE bead closes.
      expect(_updatesOn(runner.calls, 'tgdog-r1'), [
        {'work_bead': 'tg-1#r1'},
      ]);
      expect(runner.callsFor('close'), hasLength(1));
      expect(runner.callsFor('close').single[1], 'tgdog-g1');
      final rekeyAt = runner.calls.indexWhere(
        (c) => c.first == 'update' && c[1] == 'tgdog-r1',
      );
      final closeAt = runner.calls.indexWhere((c) => c.first == 'close');
      expect(
        rekeyAt < closeAt,
        isTrue,
        reason:
            'the re-key COMMITS before the gate closes — the reverse order lets '
            'the D-7 re-arm fire over a still-gated cursor and wedges the scope '
            'into the rework-decline path',
      );
      // The chokepoint stayed pristine (never `bd show`, never SQL).
      expect(runner.neverShowOrSql, isTrue);

      final flare = transport.named('gate.autoRespec').single;
      expect(flare.data['round'], '1');
      expect(flare.data['gateId'], 'tgdog-g1');
    });

    test('mints round 2 in the SAME workspace and re-runs specify', () async {
      final runner = RecordingBdRunner();
      final ctx = _ctxOver(runner);
      final sourceControl = _RecordingSourceControl();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _parkedSession('tgdog-r1', workBead: 'tg-1'),
          _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=1'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(sourceControl: sourceControl),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // The store now reflects the auto-respec's writes: the session is RETIRED
      // (re-keyed off `tg-1`) and the gate bead is CLOSED.
      state.push(
        _state([
          Bead(
            id: 'tgdog-r1',
            issueType: IssueType.session,
            status: BeadStatus.open,
            metadata: {
              'rig': stateSubstation,
              SessionBeadKeys.workBead: 'tg-1#r1',
              ...nodeStateMetadata('tg-1/specify', StepState.complete),
              ...nodeStateMetadata('tg-1/route', StepState.gated),
            },
          ),
          _gate(
            'tgdog-g1',
            sessionId: 'tgdog-r1',
            reason: 'respec: round=1',
            closed: true,
          ),
        ], tick: 1),
      );
      await _settle(m.owner);

      // The retired round closed and round 2 minted — the EXISTING rework
      // transition, triggered by the re-key alone.
      expect(
        runner.callsFor('close').map((c) => c[1]),
        contains('tgdog-r1'),
        reason: 'the retired round is closed by the existing rework transition',
      );
      expect(runner.callsFor('close').last, contains('reworked'));
      expect(runner.callsFor('create'), hasLength(1));

      // A VIRGIN cursor: `specify` re-runs (the round-1 `route: gated` cursor is
      // gone) — the whole point of a fresh round over a bare D-7 re-arm.
      expect(
        reg.events,
        contains('START specify(tgdog-sess1/tg-1/specify)'),
        reason: 'round 2 re-runs specify against the asset guidance ledger',
      );

      // The SAME workspace across both rounds — it is derived from the bead id,
      // which is invariant across rounds, so the ledger survives.
      expect(sourceControl.workspaceForCalls, isNotEmpty);
      expect(sourceControl.workspaceForCalls.toSet(), {'tg-1'});
    });

    test('a HUMAN gate parks exactly as today (non-regression)', () async {
      final runner = RecordingBdRunner();
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _parkedSession('tgdog-r1', workBead: 'tg-1'),
          _gate(
            'tgdog-g1',
            sessionId: 'tgdog-r1',
            reason: 'needs human sign-off',
          ),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      expect(
        runner.calls,
        isEmpty,
        reason: 'a human gate parks: no re-key, no gate close, no marker',
      );
      expect(
        transport.flares,
        isEmpty,
        reason: 'nothing to signal — the node simply parks (ADR-0008 D9)',
      );
    });

    test('the cap refuses LOUD past kMaxReworkRounds', () async {
      final runner = RecordingBdRunner();
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _parkedSession('tgdog-r1', workBead: 'tg-1'),
          _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=4'),
          _retiredRound('tgdog-o1', 1),
          _retiredRound('tgdog-o2', 2),
          _retiredRound('tgdog-o3', 3),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // NO re-key, NO gate close — past the cap a human decides.
      expect(runner.callsFor('close'), isEmpty);
      final writes = _updatesOn(runner.calls, 'tgdog-r1');
      expect(writes, hasLength(1));
      final marked = writes.single;
      expect(marked['grid.respec_capped'], 'true');
      expect(marked['grid.respec_capped_reason'], isNotEmpty);
      expect(
        marked.containsKey('work_bead'),
        isFalse,
        reason: 'the round is NOT retired past the cap',
      );

      final flare = transport.named('gate.respecCapped').single;
      expect(flare.data['rounds'], '3');
      expect(flare.data['cap'], '3');
    });

    test('a dropped re-key RETRIES on the next build and FLARES', () async {
      final runner = _FailFirstUpdateRunner(failUpdates: 1);
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final parked = [
        _parkedSession('tgdog-r1', workBead: 'tg-1'),
        _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=1'),
      ];
      final state = FakeSnapshotSource(_state(parked));
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // Attempt #1 DROPPED: loud, and the gate is NOT closed (the close only ever
      // follows a landed re-key).
      expect(
        transport.named('gate.autoRespecFailed'),
        hasLength(1),
        reason: 'a dropped re-key must flare (LOUD or GONE)',
      );
      expect(runner.callsFor('close'), isEmpty);

      // A second (identical) store tick — the cleared latch lets the predicate
      // re-fire, and the retry SUCCEEDS.
      state.push(_state(parked, tick: 1));
      await _settle(m.owner);

      final writes = _updatesOn(runner.calls, 'tgdog-r1');
      expect(
        writes,
        hasLength(2),
        reason: 'attempt #1 dropped + attempt #2 retried — never latched off',
      );
      expect(writes.last, {'work_bead': 'tg-1#r1'});
      expect(runner.callsFor('close').single[1], 'tgdog-g1');
    });

    test('a dropped gate CLOSE flares LOUD and is not retried', () async {
      final runner = _FailCloseRunner(failCloses: 1);
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final parked = [
        _parkedSession('tgdog-r1', workBead: 'tg-1'),
        _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=1'),
      ];
      final state = FakeSnapshotSource(_state(parked));
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // The re-key LANDED (the round IS retired) — only the close dropped.
      expect(_updatesOn(runner.calls, 'tgdog-r1'), [
        {'work_bead': 'tg-1#r1'},
      ]);
      final failed = transport.named('gate.autoRespecFailed').single;
      expect(failed.data['reason'], startsWith('gate close failed:'));
      expect(failed.data['gateId'], 'tgdog-g1');

      // A second (identical, still-keyed-at-`tg-1`) tick: the close is NOT
      // retried — the session has already left this bead's join key, so the
      // predicate can never re-fire. The gate dangles OPEN against the RETIRED
      // session: inert (nothing mounts the `tg-1#r1` projection) and visible to a
      // human. Never silent.
      state.push(_state(parked, tick: 1));
      await _settle(m.owner);

      expect(
        runner.callsFor('close').where((c) => c[1] == 'tgdog-g1'),
        hasLength(1),
        reason: 'the one irreversible step is never retried — it flared instead',
      );
    });

    test('a dropped cap marker retries and flares', () async {
      final runner = _FailFirstUpdateRunner(failUpdates: 1);
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final capped = [
        _parkedSession('tgdog-r1', workBead: 'tg-1'),
        _gate('tgdog-g1', sessionId: 'tgdog-r1', reason: 'respec: round=4'),
        _retiredRound('tgdog-o1', 1),
        _retiredRound('tgdog-o2', 2),
        _retiredRound('tgdog-o3', 3),
      ];
      final state = FakeSnapshotSource(_state(capped));
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final m = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(m.owner.dispose);
      await _settle(m.owner);

      // The LIVE half of the refusal fired regardless of the dropped write.
      expect(transport.named('gate.respecCapped'), isNotEmpty);
      final failed = transport.named('gate.autoRespecFailed').single;
      expect(
        failed.data['reason'],
        startsWith('respec-cap marker write failed:'),
      );

      // The DURABLE half retries on the next build.
      state.push(_state(capped, tick: 1));
      await _settle(m.owner);

      final writes = _updatesOn(runner.calls, 'tgdog-r1');
      expect(writes, hasLength(2));
      expect(writes.last['grid.respec_capped'], 'true');
      expect(
        writes.every((w) => !w.containsKey('work_bead')),
        isTrue,
        reason: 'past the cap the round is never retired',
      );
      expect(
        runner.callsFor('close'),
        isEmpty,
        reason: 'past the cap nothing is retired and no gate is closed',
      );
    });
  });
}
