// tg-boq — the D-7 gate re-arm, WIRING-SHAPED, through the REAL
// `StationJoinBridge` + the full `Station → … → SessionScope` tree.
//
// LIVE INCIDENT (2026-07-07, session tgdog-snp / bead tg-m2q): a space gate
// resolve CLOSED the gate bead, but the resident station NEVER re-armed the
// parked node — the cursor stayed `gated` for 30+ min, no re-arm write ever
// followed, and the operator's only recovery was a station bounce. Two
// suspects had to be ruled in/out OFFLINE:
//
//   (1) state-emission delivery — does an EXTERNAL gate-close pushed into the
//       state store re-emit and actually REBUILD the parked SessionScope?
//       → PROVEN HERE ('dynamic external gate-close'): the engine tree re-arms
//         correctly, so the deviation is NOT the join/rebuild.
//   (2) the `_ctx?.`/pre-write-latch compound — `_scheduleRearm` latched
//       `_rearmed` BEFORE a fire-and-forget write, so a DROPPED write made the
//       drop PERMANENT and SILENT.
//       → REPRODUCED HERE ('a dropped re-arm write RETRIES'): the old permanent
//         latch wedged the node forever; the fix (an in-flight guard cleared on
//         settle + a LOUD flare) retries on the next build.
//
// Plus the RESTART recovery path ('boots adopting a gated cursor …') — the
// operator's only recovery today, itself previously untested.
//
// Zero I/O: fakes + the recording chokepoint + a fake transport.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/live_frontier.dart'
    show derivedEscalation;
import 'package:grid_engine/src/molecule/molecule_codec.dart'
    show activeStepBeadsByPath, supersedesDepthByPath;
import 'package:grid_engine/src/molecule/molecule_schema.dart'
    show kValidatesParam;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'route', capabilityId: 'route'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'route'}),
  ],
);

const _terminalRaceCircuit = Circuit(
  id: 'terminal-race',
  terminalStepId: 'b',
  steps: [
    CapabilityStep(stepId: 'a', capabilityId: 'a'),
    CapabilityStep(stepId: 'b', capabilityId: 'b'),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

GraphSnapshot _state(
  List<Bead> beads, {
  List<BeadDependency> dependencies = const [],
  int tick = 0,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: dependencies,
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
);

/// A MOLECULE session bead (tg-eli phase 2: the flat cursor model is
/// retired), linked to [workBead] — its OWN parked state lives on a
/// companion `type=step` bead ([_routeStep]), never on this bead's metadata.
Bead _gatedSession(
  String id, {
  required String workBead,
  Map<String, String> results = const {},
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    SessionBeadKeys.model: kSessionModelMolecule,
    ...results,
  },
);

/// The `type=step` bead at `tg-1/route`, owned by [sessionId] — the molecule
/// model's per-node cursor slot (`MoleculeStepKeys`, tg-eli phase 2). Its own
/// bead id (never a `grid.cursor.*` key on the session bead) is what a re-arm
/// write targets.
const _routeStepId = 'tgdog-step-route';

Bead _routeStep(
  String id, {
  required String sessionId,
  required StepState state,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: 'route',
    MoleculeStepKeys.capability: 'route',
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: 'tg-1/route',
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.state: state.name,
  },
);

Bead _stepBead(
  String id, {
  required String sessionId,
  required String path,
  required StepState state,
  Map<String, String> results = const {},
}) => Bead(
  id: id,
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: path.split('/').last,
    MoleculeStepKeys.capability: path.split('/').last,
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.state: state.name,
    for (final entry in results.entries)
      ResultKeys.keyFor(path, entry.key): entry.value,
  },
);

/// The `type=gate` bead blocking [sessionId] at `tg-1/route` — OPEN parks the
/// node; CLOSED (a space gate resolve) re-arms it.
Bead _gate(String id, {required String sessionId, bool closed = false}) => Bead(
  id: id,
  issueType: GridIssueTypes.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': sessionId, 'node': 'tg-1/route'},
);

/// A CLOSED, outcome-marked (done) session — the I-10 blocking disposition
/// never reads the cursor at all, so no companion step bead is needed here.
Bead _doneGatedSession(String id, {required String workBead}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.closed,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    SessionBeadKeys.outcome: kSessionOutcomeComplete,
  },
);

List<Branch> _allBranches(Branch root) {
  final out = <Branch>[];
  void walk(Branch branch) {
    out.add(branch);
    branch.visitChildren(walk);
  }

  walk(root);
  return out;
}

/// An [ExplorationTransport] that records every LOUD flare — the emit-only sink
/// the re-arm-failed signal fires through.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

final class _DroppedAckSink implements TrajectoryAckRecordSink {
  int acknowledged = 0;

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {}

  @override
  Future<TrajectoryAppendResult> appendAcked(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    required bool decisionBearing,
  }) async {
    expect(decisionBearing, isTrue);
    acknowledged += 1;
    return const TrajectoryAppendResult.dropped();
  }
}

final class _AckedSink implements TrajectoryAckRecordSink {
  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {}

  @override
  Future<TrajectoryAppendResult> appendAcked(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    required bool decisionBearing,
  }) async => const TrajectoryAppendResult.acked();
}

final class _AckAfterCloseSink implements TrajectoryAckRecordSink {
  _AckAfterCloseSink(this.closeEntered);

  final Future<void> closeEntered;
  final Completer<void> rearmAcknowledged = Completer<void>();

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {}

  @override
  Future<TrajectoryAppendResult> appendAcked(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    required bool decisionBearing,
  }) async {
    expect(decisionBearing, isTrue);
    await closeEntered;
    if (!rearmAcknowledged.isCompleted) rearmAcknowledged.complete();
    return const TrajectoryAppendResult.acked();
  }
}

class _RulingAwareRoute extends RouteCapability {
  const _RulingAwareRoute(this.lane, this.log);

  final String lane;
  final List<String> log;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final result = siblings.resultOf(lane);
    final grade = result[ResultKeys.grade] ?? 'F';
    final transport = result[ResultKeys.transport] ?? 'missing';
    log.add('$lane:$grade:$transport');
    return grade == 'A'
        ? Advance({ResultKeys.grade: grade, ResultKeys.transport: transport})
        : Escalate('$lane graded $grade via $transport');
  }
}

class _RulingAwareRegistry implements CapabilityRegistry {
  const _RulingAwareRegistry(this.route);

  final _RulingAwareRoute route;

  @override
  Circuit? circuit(String circuitId) => null;

  @override
  Seed host(StepMount mount) => mount.step.capabilityId == 'route'
      ? CapabilityHost(capability: route, mount: mount, key: mount.key)
      : const Idle();

  @override
  DateTime now() => DateTime(2026);
}

const _reviewResumeRoot = Circuit(
  id: 'resume-root',
  terminalStepId: 'later',
  steps: [
    SubCircuitStep(stepId: 'review', circuitId: 'resume-review'),
    CapabilityStep(
      stepId: 'deliver',
      capabilityId: 'deliver',
      dependsOn: {'review'},
    ),
    SubCircuitStep(stepId: 'later', circuitId: 'later-review'),
  ],
);

const _reviewResumeCircuit = Circuit(
  id: 'resume-review',
  terminalStepId: 'critic',
  steps: [
    CapabilityStep(stepId: 'route', capabilityId: 'route'),
    CapabilityStep(
      stepId: 'critic',
      capabilityId: 'critic',
      dependsOn: {'route'},
      params: {kValidatesParam: 'route'},
    ),
  ],
);

const _laterReviewCircuit = Circuit(
  id: 'later-review',
  terminalStepId: 'later-route',
  steps: [
    CapabilityStep(stepId: 'target', capabilityId: 'target'),
    CapabilityStep(
      stepId: 'later-route',
      capabilityId: 'later-route',
      dependsOn: {'target'},
      params: {kValidatesParam: 'target'},
    ),
  ],
);

class _ResumeRoute extends RouteCapability {
  int runs = 0;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    runs += 1;
    final siblings =
        context.getInheritedSeedOfExactType<SiblingView>() ??
        const SiblingView();
    final ruling = siblings.resultOf('tg-1/review/critic');
    return ruling[ResultKeys.grade] == 'A'
        ? Advance({
            ResultKeys.grade: 'A',
            ResultKeys.transport:
                ruling[ResultKeys.transport] ?? kOperatorRulingTransport,
          })
        : const Escalate('critic still invalidates review route');
  }
}

class _CountingSuccess extends ServiceCapability {
  int runs = 0;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    runs += 1;
    return const Ok();
  }
}

class _ResumeRegistry implements CapabilityRegistry {
  _ResumeRegistry({required this.route, required this.deliver});

  final _ResumeRoute route;
  final _CountingSuccess deliver;

  @override
  Circuit? circuit(String circuitId) => switch (circuitId) {
    'resume-review' => _reviewResumeCircuit,
    'later-review' => _laterReviewCircuit,
    _ => null,
  };

  @override
  Seed host(StepMount mount) => switch (mount.step.capabilityId) {
    'route' => CapabilityHost(capability: route, mount: mount, key: mount.key),
    'deliver' => CapabilityHost(
      capability: deliver,
      mount: mount,
      key: mount.key,
    ),
    _ => const Idle(),
  };

  @override
  DateTime now() => DateTime(2026);
}

BeadDependency _supersedes(String successor, String prior) => BeadDependency(
  issueId: successor,
  dependsOnId: prior,
  type: DependencyType.supersedes,
);

/// A [BdRunner] that FAILS the first [failUpdates] `update` calls (throwing, as
/// a live `bd` blip would) then succeeds — so a test can drive a DROPPED re-arm
/// write and prove the next build retries. Records every argv in order.
class _FailFirstUpdateRunner extends RecordingBdRunner {
  _FailFirstUpdateRunner({this.failUpdates = 1});

  final int failUpdates;
  int _updates = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'update') {
      _updates++;
      if (_updates <= failUpdates) {
        throw StateError('fake bd update failure #$_updates (tg-boq)');
      }
    }
    return result;
  }
}

final class _GatedSessionCloseRunner extends RecordingBdRunner {
  _GatedSessionCloseRunner({required this.sessionId});

  final String sessionId;
  final Completer<void> closeEntered = Completer<void>();
  final Completer<void> releaseClose = Completer<void>();
  bool _holdingFirstClose = true;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final holdsSessionClose =
        _holdingFirstClose &&
        args.length > 1 &&
        args.first == 'close' &&
        args[1] == sessionId;
    if (!holdsSessionClose) {
      return super.run(args, timeout: timeout, stdin: stdin);
    }
    _holdingFirstClose = false;
    final result = super.run(args, timeout: timeout, stdin: stdin);
    closeEntered.complete();
    await releaseClose.future;
    return result;
  }
}

/// A [StationServices] whose chokepoint writes through [runner] (a recording
/// fake), owning [stateSubstation] — the same shape [buildFakes] builds, but
/// over a caller-supplied runner so a test can assert against it directly.
StationServices _ctxOver(BdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: const EmptyBeadProbeReader(),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  ServiceBundle services = const ServiceBundle(),
  TrajectoryRecorderScope? trajectoryScope,
  SessionResolver? circuitResolver,
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
              value: circuitResolver ?? CircuitResolver((_) => _code),
              child: InheritedSeed<TrajectoryRecorderScope>(
                value: trajectoryScope ?? TrajectoryRecorderScope.disabled,
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
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('D-7 gate re-arm, wiring-shaped (tg-boq)', () {
    test(
      'SUSPECT 1 — a dynamic external gate-close pushed into the STATE source '
      're-arms the parked node (the join/rebuild is NOT where the incident '
      'came from)',
      () async {
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            _gate('gate-1', sessionId: 'tgdog-s'),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(joined: bridge.notifier, ctx: ctx, registry: reg);
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // OPEN gate → parked, no re-arm.
        expect(
          runner.callsFor('update'),
          isEmpty,
          reason: 'an open gate leaves the node parked',
        );

        // The space resolves the gate — an EXTERNAL writer CLOSES the gate bead
        // in the state store. Push the new state snapshot.
        state.push(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        final updates = runner.callsFor('update');
        expect(
          updates,
          hasLength(1),
          reason: 'the resolved gate flips the parked node back to pending',
        );
        // The write targets the STEP bead (tg-eli phase 2: molecule is the
        // only circuit engine — no `grid.cursor.*` on the session bead).
        expect(updates.single[1], _routeStepId);
        expect(runner.metadataOfUpdate(0), {MoleculeStepKeys.state: 'pending'});
        // The chokepoint stayed pristine (never `bd show`, never SQL).
        expect(runner.neverShowOrSql, isTrue);
      },
    );

    test(
      'a CLOSED done session whose gate resolves does not re-arm and its scope '
      'unmounts',
      () async {
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            _gate('gate-1', sessionId: 'tgdog-s'),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(joined: bridge.notifier, ctx: ctx, registry: reg);
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        expect(
          _allBranches(m.root).where((b) => b.seed is SessionScope),
          isNotEmpty,
          reason: 'the live gated session starts mounted',
        );
        expect(runner.callsFor('update'), isEmpty);

        state.push(
          _state([
            _doneGatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        expect(
          runner.callsFor('update'),
          isEmpty,
          reason: 'closing the gate must not flip a closed session to pending',
        );
        expect(
          _allBranches(m.root).where((b) => b.seed is SessionScope),
          isEmpty,
          reason:
              'WorkList blocks done sessions and unmounts the session scope',
        );
        expect(runner.neverShowOrSql, isTrue);
      },
    );

    test(
      'RESTART recovery — a station that BOOTS adopting a gated cursor whose '
      'gate is ALREADY closed re-arms on adopt (the operator\'s only recovery '
      'path today: a station bounce)',
      () async {
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        // Boot state: the cursor is gated AND the gate bead is already CLOSED
        // (resolved while the prior station was down) — openGateNodes is empty
        // from the very first join.
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(joined: bridge.notifier, ctx: ctx, registry: reg);
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        final updates = runner.callsFor('update');
        expect(
          updates,
          hasLength(1),
          reason:
              'adopt sees the already-resolved gate and re-arms immediately',
        );
        expect(updates.single[1], _routeStepId);
        expect(runner.metadataOfUpdate(0), {MoleculeStepKeys.state: 'pending'});
      },
    );

    test(
      'a resolved gate re-arms and advances its route from an operator ruling',
      () async {
        const lane = 'tg-1/review/test-coverage';
        final log = <String>[];
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final ruling = operatorRulingMetadata(
          lane,
          grade: 'A',
          rationale: 'operator inspected the lane',
          evidenceSession: 'tgdog-session',
        );
        final critic = _stepBead(
          'critic-step',
          sessionId: 'tgdog-s',
          path: lane,
          state: StepState.complete,
          results: const {
            ResultKeys.grade: 'F',
            ResultKeys.transport: 'reported',
            ResultKeys.rationale: 'critic transport failed',
          },
        );
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1', results: ruling),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            critic,
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: _RulingAwareRegistry(_RulingAwareRoute(lane, log)),
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        expect(runner.callsFor('update'), hasLength(1));
        expect(runner.metadataOfUpdate(0), {
          MoleculeStepKeys.state: StepState.pending.name,
        });
        expect(log, isEmpty, reason: 'the gated route only re-arms this tick');

        state.push(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1', results: ruling),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.pending,
            ),
            critic,
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        expect(log, ['$lane:A:$kOperatorRulingTransport']);
        expect(runner.callsFor('update'), hasLength(2));
        final completion = runner.metadataOfUpdate(1);
        expect(completion[MoleculeStepKeys.state], StepState.complete.name);
        expect(
          completion.keys.where((key) => key.startsWith('grid.rework.')),
          isEmpty,
        );
        expect(runner.callsFor('create'), isEmpty);
      },
    );

    test(
      'unrelated re-arm ack does not unlatch a terminal close in flight',
      () async {
        const sessionId = 'tgdog-s';
        const nodeAPath = 'tg-1/a';
        const nodeAId = 'tgdog-step-a';
        const nodeBPath = 'tg-1/b';

        List<Bead> stateBeads({required StepState nodeAState}) => [
          _gatedSession(sessionId, workBead: 'tg-1'),
          _stepBead(
            nodeAId,
            sessionId: sessionId,
            path: nodeAPath,
            state: nodeAState,
          ),
          _stepBead(
            'tgdog-step-b',
            sessionId: sessionId,
            path: nodeBPath,
            state: StepState.complete,
          ),
          Bead(
            id: 'tgdog-gate-a',
            issueType: GridIssueTypes.gate,
            status: BeadStatus.closed,
            metadata: const {
              'rig': stateSubstation,
              'blocks': sessionId,
              'node': nodeAPath,
            },
          ),
        ];

        final runner = _GatedSessionCloseRunner(sessionId: sessionId);
        final sink = _AckAfterCloseSink(runner.closeEntered.future);
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state(stateBeads(nodeAState: StepState.gated)),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);
        final mounted = _mountFull(
          joined: bridge.notifier,
          ctx: _ctxOver(runner),
          registry: RecordingCapabilityRegistry(circuits: const {}),
          circuitResolver: CircuitResolver((_) => _terminalRaceCircuit),
          trajectoryScope: TrajectoryRecorderScope(
            StationTrajectoryRecorder(
              sink: sink,
              substationPrefixes: const {stateSubstation},
              clock: () => DateTime(2026),
            ),
          ),
        );
        addTearDown(mounted.owner.dispose);

        await _pump();
        mounted.owner.flush();
        await runner.closeEntered.future;
        await sink.rearmAcknowledged.future;
        await _pump();

        expect(
          runner.callsFor('close').where((call) => call[1] == sessionId),
          hasLength(1),
          reason: 'node B owns one positive close held in flight',
        );

        state.push(_state(stateBeads(nodeAState: StepState.complete), tick: 1));
        await _pump();
        mounted.owner.flush();
        await _pump();

        runner.releaseClose.complete();
        await _pump();
        mounted.owner.flush();
        await _pump();

        expect(
          runner.callsFor('close').where((call) => call[1] == sessionId),
          hasLength(1),
          reason:
              'the unrelated node A acknowledgment cannot admit a second '
              'close while node B terminal completion is in flight',
        );
        var terminalOutcomeWrites = 0;
        for (var index = 0; index < runner.workUpdates.length; index++) {
          final call = runner.workUpdates[index];
          if (call.length > 1 &&
              call[1] == sessionId &&
              runner
                  .metadataOfUpdate(index)
                  .containsKey(SessionBeadKeys.outcome)) {
            terminalOutcomeWrites += 1;
          }
        }
        expect(
          terminalOutcomeWrites,
          1,
          reason: 'the terminal outcome is persisted exactly once',
        );
      },
    );

    test(
      'resolved derivation gate re-arms before terminal scheduling resumes',
      () async {
        const sessionId = 'tgdog-s';
        const routePath = 'tg-1/review/route';
        const criticPath = 'tg-1/review/critic';
        const deliverPath = 'tg-1/deliver';
        const laterTargetPath = 'tg-1/later/target';
        const laterRoutePath = 'tg-1/later/later-route';
        final dependencies = <BeadDependency>[
          _supersedes('tgdog-review-route-1', 'tgdog-review-route-0'),
          _supersedes('tgdog-review-route-2', 'tgdog-review-route-1'),
          _supersedes('tgdog-review-route-3', 'tgdog-review-route-2'),
          _supersedes('tgdog-review-critic-1', 'tgdog-review-critic-0'),
          _supersedes('tgdog-review-critic-2', 'tgdog-review-critic-1'),
          _supersedes('tgdog-review-critic-3', 'tgdog-review-critic-2'),
          _supersedes('tgdog-later-target-1', 'tgdog-later-target-0'),
          _supersedes('tgdog-later-target-2', 'tgdog-later-target-1'),
          _supersedes('tgdog-later-target-3', 'tgdog-later-target-2'),
          _supersedes('tgdog-later-route-1', 'tgdog-later-route-0'),
          _supersedes('tgdog-later-route-2', 'tgdog-later-route-1'),
          _supersedes('tgdog-later-route-3', 'tgdog-later-route-2'),
        ];
        final ruling = operatorRulingMetadata(
          criticPath,
          grade: 'A',
          rationale: 'operator accepted the pre-existing finding',
          evidenceSession: sessionId,
        );

        List<Bead> stateBeads({
          required bool gateClosed,
          Map<String, String> sessionResults = const {},
          StepState routeState = StepState.gated,
          Map<String, String> routeResults = const {},
          StepState laterRouteState = StepState.pending,
          Map<String, String> laterRouteResults = const {},
        }) => [
          _gatedSession(sessionId, workBead: 'tg-1', results: sessionResults),
          _stepBead(
            'tgdog-review-root',
            sessionId: sessionId,
            path: 'tg-1/review',
            state: StepState.pending,
          ),
          for (var generation = 0; generation < kMaxReworkRounds; generation++)
            _stepBead(
              'tgdog-review-route-$generation',
              sessionId: sessionId,
              path: routePath,
              state: StepState.complete,
              results: const {ResultKeys.grade: 'B'},
            ),
          _stepBead(
            'tgdog-review-route-3',
            sessionId: sessionId,
            path: routePath,
            state: routeState,
            results: routeResults,
          ),
          for (var generation = 0; generation < kMaxReworkRounds; generation++)
            _stepBead(
              'tgdog-review-critic-$generation',
              sessionId: sessionId,
              path: criticPath,
              state: StepState.complete,
              results: const {ResultKeys.grade: 'B'},
            ),
          _stepBead(
            'tgdog-review-critic-3',
            sessionId: sessionId,
            path: criticPath,
            state: StepState.complete,
            results: const {ResultKeys.grade: 'F'},
          ),
          _stepBead(
            'tgdog-deliver-step',
            sessionId: sessionId,
            path: deliverPath,
            state: StepState.pending,
          ),
          _stepBead(
            'tgdog-later-root',
            sessionId: sessionId,
            path: 'tg-1/later',
            state: StepState.pending,
          ),
          for (var generation = 0; generation < kMaxReworkRounds; generation++)
            _stepBead(
              'tgdog-later-target-$generation',
              sessionId: sessionId,
              path: laterTargetPath,
              state: StepState.complete,
              results: const {ResultKeys.grade: 'B'},
            ),
          _stepBead(
            'tgdog-later-target-3',
            sessionId: sessionId,
            path: laterTargetPath,
            state: StepState.complete,
          ),
          for (var generation = 0; generation < kMaxReworkRounds; generation++)
            _stepBead(
              'tgdog-later-route-$generation',
              sessionId: sessionId,
              path: laterRoutePath,
              state: StepState.complete,
              results: const {ResultKeys.grade: 'B'},
            ),
          _stepBead(
            'tgdog-later-route-3',
            sessionId: sessionId,
            path: laterRoutePath,
            state: laterRouteState,
            results: laterRouteResults,
          ),
          Bead(
            id: 'tgdog-review-gate',
            issueType: GridIssueTypes.gate,
            status: gateClosed ? BeadStatus.closed : BeadStatus.open,
            metadata: const {
              'rig': stateSubstation,
              'blocks': sessionId,
              'node': routePath,
            },
          ),
        ];

        final runner = RecordingBdRunner(createdId: 'derived-gate');
        final ctx = _ctxOver(runner);
        final route = _ResumeRoute();
        final deliver = _CountingSuccess();
        final registry = _ResumeRegistry(route: route, deliver: deliver);
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state(stateBeads(gateClosed: false), dependencies: dependencies),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);
        final mounted = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: registry,
          circuitResolver: CircuitResolver((_) => _reviewResumeRoot),
          trajectoryScope: TrajectoryRecorderScope(
            StationTrajectoryRecorder(
              sink: _AckedSink(),
              substationPrefixes: const {'tgdog'},
              clock: () => DateTime(2026),
            ),
          ),
        );
        addTearDown(mounted.owner.dispose);

        Future<void> settle() async {
          await _pump();
          mounted.owner.flush();
          await _pump();
        }

        int pendingRouteWrites() {
          var count = 0;
          for (
            var index = 0;
            index < runner.callsFor('update').length;
            index++
          ) {
            final call = runner.callsFor('update')[index];
            if (call.length > 1 &&
                call[1] == 'tgdog-review-route-3' &&
                runner.metadataOfUpdate(index)[MoleculeStepKeys.state] ==
                    StepState.pending.name) {
              count += 1;
            }
          }
          return count;
        }

        int gateCreates() => runner
            .callsFor('create')
            .where(
              (call) =>
                  call.contains('--type') &&
                  call.contains(GridIssueTypes.gate.wire),
            )
            .length;

        await settle();
        final firstCycleGateCreates = gateCreates();
        expect(firstCycleGateCreates, greaterThanOrEqualTo(1));
        expect(pendingRouteWrites(), 0);

        state.push(
          _state(
            stateBeads(gateClosed: true),
            dependencies: dependencies,
            tick: 1,
          ),
        );
        await settle();
        expect(
          pendingRouteWrites(),
          0,
          reason: 'a closed gate alone remains held by the critic F stamp',
        );

        state.push(
          _state(
            stateBeads(gateClosed: true, sessionResults: ruling),
            dependencies: dependencies,
            tick: 2,
          ),
        );
        await settle();
        expect(pendingRouteWrites(), 1);

        final secondCycleBeads = stateBeads(
          gateClosed: true,
          sessionResults: ruling,
          routeState: StepState.pending,
          laterRouteState: StepState.complete,
          laterRouteResults: const {ResultKeys.grade: 'F'},
        );
        final projected = projectMoleculeCursor(
          secondCycleBeads,
          dependencies: dependencies,
        );
        final activeResults = <String, Map<String, String>>{};
        for (final step in activeStepBeadsByPath(
          secondCycleBeads,
          dependencies,
        ).values) {
          activeResults.addAll(projectCircuitResults(step));
        }
        expect(
          derivedEscalation(
            _reviewResumeRoot,
            projected.cursor,
            mergeOperatorRulings(
              activeResults,
              projectCircuitResults(secondCycleBeads.first),
            ),
            'tg-1',
            circuitById: registry.circuit,
            supersedesDepthByPath: supersedesDepthByPath(
              secondCycleBeads,
              dependencies,
            ),
            spentReworkRoundsByPath: supersedesVerdictCountByPath(
              secondCycleBeads,
              dependencies,
            ),
          )?.path,
          laterTargetPath,
        );
        state.push(
          _state(secondCycleBeads, dependencies: dependencies, tick: 3),
        );
        await settle();
        expect(route.runs, 1);
        expect(
          gateCreates(),
          greaterThan(firstCycleGateCreates),
          reason:
              'the acknowledged re-arm clears the terminal latch so a later '
              'derived escalation can mint its own gate',
        );

        state.push(
          _state(
            stateBeads(
              gateClosed: true,
              sessionResults: ruling,
              routeState: StepState.complete,
              routeResults: const {
                ResultKeys.grade: 'A',
                ResultKeys.transport: kOperatorRulingTransport,
              },
              laterRouteState: StepState.complete,
              laterRouteResults: const {ResultKeys.grade: 'F'},
            ),
            dependencies: dependencies,
            tick: 4,
          ),
        );
        await settle();
        expect(
          deliver.runs,
          1,
          reason: 'deliver starts on the second post-ruling state tick',
        );
      },
    );

    test('SUSPECT 2 — a DROPPED re-arm write RETRIES on the next build (never a '
        'permanent silent latch) and FLARES loud', () async {
      final runner = _FailFirstUpdateRunner(failUpdates: 1);
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s'),
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
      await _pump();
      m.owner.flush();
      await _pump();

      // First resolve → re-arm attempt #1, which DROPS (the runner throws).
      state.push(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s', closed: true),
        ], tick: 1),
      );
      await _pump();
      m.owner.flush();
      await _pump();

      // The drop is LOUD — a flare fired — and NOT silent-swallowed.
      expect(
        transport.flares.map((f) => f.name),
        contains('gate.rearmFailed'),
        reason: 'a dropped re-arm write must flare (LOUD or GONE)',
      );
      expect(transport.flares.single.data['nodePath'], 'tg-1/route');

      // A SECOND store tick (still the resolved gate) — with the OLD permanent
      // latch this build would be a no-op (the node stays wedged `gated`
      // forever). With the in-flight guard cleared on failure, D-7 re-fires
      // and the retry SUCCEEDS.
      state.push(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s', closed: true),
        ], tick: 2),
      );
      await _pump();
      m.owner.flush();
      await _pump();

      final updates = runner.callsFor('update');
      expect(
        updates,
        hasLength(2),
        reason: 'attempt #1 dropped + attempt #2 retried — never latched off',
      );
      // Both attempts targeted the STEP bead and carry the same pending
      // flip; #2 (index 1) succeeded.
      expect(updates[1][1], _routeStepId);
      expect(runner.metadataOfUpdate(1), {MoleculeStepKeys.state: 'pending'});
      // Exactly ONE flare — the retry succeeded, so it did not re-flare.
      expect(
        transport.flares.where((f) => f.name == 'gate.rearmFailed'),
        hasLength(1),
      );
    });

    test('cut re-arm failure halts admission, gates the open route, and keeps '
        'the in-flight guard instead of flaring or retrying', () async {
      final runner = _FailFirstUpdateRunner(failUpdates: 1);
      runner.exportBeads = [_gatedSession('tgdog-s', workBead: 'tg-1')];
      final writer = StationBeadWriter(
        bd: BdCliService(runner),
        reader: runner,
        ownership: BeadOwnershipPredicate(const {stateSubstation}),
      );
      final halt = TrajectoryAdmissionHalt(
        writer: writer,
        stateSubstation: stateSubstation,
        bootEpoch: () => 7,
      );
      final ctx = StationServices(
        provider: FakeRuntimeProvider(),
        writer: writer,
        stateSubstation: stateSubstation,
        trajectoryAdmissionHalt: halt,
      );
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
      final state = FakeSnapshotSource(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s'),
        ]),
      );
      final bridge = StationJoinBridge(work: work, state: state)..start();
      addTearDown(bridge.dispose);

      final mounted = _mountFull(
        joined: bridge.notifier,
        ctx: ctx,
        registry: reg,
        services: ServiceBundle(transport: transport),
      );
      addTearDown(mounted.owner.dispose);
      await _pump();
      mounted.owner.flush();
      await _pump();

      state.push(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s', closed: true),
        ], tick: 1),
      );
      await _pump();
      mounted.owner.flush();
      await _pump();

      expect(halt.halted, isTrue);
      expect(
        transport.flares.map((flare) => flare.name),
        isNot(contains('gate.rearmFailed')),
      );
      expect(runner.callsFor('create'), hasLength(1));
      expect(runner.callsFor('update'), hasLength(1));
      expect(runner.metadataOfUpdate(0), containsPair('blocks', 'tgdog-s'));
      expect(runner.metadataOfUpdate(0), containsPair('node', 'tg-1/route'));

      state.push(
        _state([
          _gatedSession('tgdog-s', workBead: 'tg-1'),
          _routeStep(
            _routeStepId,
            sessionId: 'tgdog-s',
            state: StepState.gated,
          ),
          _gate('gate-1', sessionId: 'tgdog-s', closed: true),
        ], tick: 2),
      );
      await _pump();
      mounted.owner.flush();
      await _pump();
      expect(
        runner.callsFor('update'),
        hasLength(1),
        reason: 'cut keeps the guard latched and schedules no retry',
      );
    });

    test(
      'cut keeps the re-arm guard when the decision append is dropped',
      () async {
        final runner = RecordingBdRunner();
        runner.exportBeads = [_gatedSession('tgdog-s', workBead: 'tg-1')];
        final writer = StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        );
        final halt = TrajectoryAdmissionHalt(
          writer: writer,
          stateSubstation: stateSubstation,
          bootEpoch: () => 8,
        );
        final ctx = StationServices(
          provider: FakeRuntimeProvider(),
          writer: writer,
          stateSubstation: stateSubstation,
          trajectoryAdmissionHalt: halt,
        );
        final sink = _DroppedAckSink();
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _routeStep(
              _routeStepId,
              sessionId: 'tgdog-s',
              state: StepState.gated,
            ),
            _gate('gate-1', sessionId: 'tgdog-s'),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);
        final mounted = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: RecordingCapabilityRegistry(circuits: const {}),
          trajectoryScope: TrajectoryRecorderScope(
            StationTrajectoryRecorder(
              sink: sink,
              substationPrefixes: const {stateSubstation},
            ),
            admissionHalt: halt,
          ),
        );
        addTearDown(mounted.owner.dispose);
        await _pump();
        mounted.owner.flush();

        void publish(int tick) {
          state.push(
            _state([
              _gatedSession('tgdog-s', workBead: 'tg-1'),
              _routeStep(
                _routeStepId,
                sessionId: 'tgdog-s',
                state: StepState.gated,
              ),
              _gate('gate-1', sessionId: 'tgdog-s', closed: true),
            ], tick: tick),
          );
        }

        publish(1);
        await _pump();
        mounted.owner.flush();
        await _pump();
        expect(sink.acknowledged, 1);
        expect(halt.halted, isTrue);
        expect(runner.callsFor('create'), hasLength(1));
        expect(runner.callsFor('update'), hasLength(1));

        publish(2);
        await _pump();
        mounted.owner.flush();
        await _pump();
        expect(sink.acknowledged, 1);
        expect(
          runner.callsFor('update'),
          hasLength(1),
          reason: 'the dropped decision append schedules no second re-arm',
        );
      },
    );
  });
}
