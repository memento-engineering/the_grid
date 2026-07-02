// Track G — supervision + the restorable circuit-breaker (D-5):
//  - the failing leaf host authors the supervised-restart cursor (Track E),
//  - SessionScope escalates + tears down on breaker-exhaustion (G2),
//  - the kernel owns the backoff Timer and re-pokes on cooldown expiry (G3/F1).
//
// ADR-0008 D7 / M4-P1 Track G. Zero I/O — fakes + injected clock/timer.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

const _code = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _emptyGraph() => GraphSnapshot.fromParts(
  beads: const [],
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime(2026),
);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

/// An SessionResolver that returns a const Idle (the G3 kernel test does not need
/// real effects — it exercises the cooldown scanner, not the tree).
class _IdleResolver implements SessionResolver {
  const _IdleResolver();
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

/// A controllable Timer the kernel's scheduleTimer seam returns (no real wall
/// clock — the test fires the callback by hand).
class _FakeTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

void main() {
  group('Track G (G2) — SessionScope escalates on breaker-exhaustion (D-5)', () {
    test('an exhausted node → escalation marker written + session closed; a '
        'healthy terminal would just close', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      // agent failed AND exhausted (restartCount 3 == maxRestarts 3).
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              cursor: {
                'tg-1/agent': NodeCursor(
                  state: StepState.failed,
                  restartCount: 3,
                ),
              },
            ),
          },
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        InheritedSeed<JoinedSnapshotNotifier>(
          value: joined,
          child: InheritedSeed<StationServices>(
            value: f.ctx,
            child: InheritedSeed<CapabilityRegistry>(
              value: reg,
              child: InheritedSeed<SessionResolver>(
                value: FormulaResolver((_) => _code),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(_tgConfig),
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      await _pump();

      // SessionScope wrote the escalation marker AND closed (scheduled off build).
      final escalations = f.runner
          .callsFor('update')
          .where((c) => c.join(' ').contains('grid.escalation'));
      expect(escalations, hasLength(1));
      expect(
        f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
        hasLength(1),
      );
    });
  });

  group('Track G (G3/F1) — the kernel owns the backoff Timer + re-poke', () {
    test('a cursor cooldown arms a Timer for the right delay; firing it '
        're-emits a fresh snapshot (never root.markNeedsRebuild)', () async {
      final now = DateTime(2026);
      final timers = <({Duration delay, void Function() cb})>[];

      final work = FakeSnapshotSource(_emptyGraph());
      final state = FakeSnapshotSource(_emptyGraph());
      addTearDown(work.close);
      addTearDown(state.close);
      final bridge = StationJoinBridge(work: work, state: state);
      final f = buildFakes();

      final kernel = StationKernel(
        bridge: bridge,
        stationServices: f.ctx,
        resolver: const _IdleResolver(),
        substations: [
          SubstationScope(
            configNotifier: SubstationConfigNotifier(_tgConfig),
            key: const ValueKey('scope.tg'),
          ),
        ],
        clock: () => now,
        scheduleTimer: (delay, cb) {
          timers.add((delay: delay, cb: cb));
          return _FakeTimer();
        },
      );
      addTearDown(kernel.dispose);
      kernel.start();

      // Push a state snapshot: a session whose agent cursor is cooling down 30s.
      final sessionBead = Bead(
        id: 'tgdog-s',
        issueType: IssueType.session,
        status: BeadStatus.open,
        metadata: <String, dynamic>{
          'rig': 'tgdog',
          'work_bead': 'tg-1',
          ...nodeFailedMetadata(
            'tg-1/agent',
            restartCount: 1,
            cooldownUntil: now.add(const Duration(seconds: 30)),
          ),
        },
      );
      state.push(GraphSnapshot.fromParts(
        beads: [sessionBead],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime(2026),
      ));
      await _pump();

      // The kernel scanned the join (in its flush cycle, NO persistent listener)
      // and armed a Timer for the cooldown delay.
      expect(timers, isNotEmpty);
      expect(timers.last.delay, const Duration(seconds: 30));

      // Firing the Timer re-emits a FRESH snapshot so WorkList re-evaluates.
      var emissions = 0;
      final remove =
          bridge.notifier.addListener((_) => emissions++, fireImmediately: false);
      timers.last.cb();
      remove();
      expect(emissions, 1, reason: 'the cooldown re-poke re-emits the snapshot');
    });

    test('no cooldown in the cursor → no Timer armed', () async {
      final now = DateTime(2026);
      final timers = <({Duration delay, void Function() cb})>[];
      final work = FakeSnapshotSource(_emptyGraph());
      final state = FakeSnapshotSource(_emptyGraph());
      addTearDown(work.close);
      addTearDown(state.close);
      final bridge = StationJoinBridge(work: work, state: state);
      final f = buildFakes();
      final kernel = StationKernel(
        bridge: bridge,
        stationServices: f.ctx,
        resolver: const _IdleResolver(),
        substations: [
          SubstationScope(
            configNotifier: SubstationConfigNotifier(_tgConfig),
            key: const ValueKey('scope.tg'),
          ),
        ],
        clock: () => now,
        scheduleTimer: (delay, cb) {
          timers.add((delay: delay, cb: cb));
          return _FakeTimer();
        },
      );
      addTearDown(kernel.dispose);
      kernel.start();

      state.push(GraphSnapshot.fromParts(
        beads: [
          Bead(
            id: 'tgdog-s',
            issueType: IssueType.session,
            status: BeadStatus.open,
            metadata: const <String, dynamic>{
              'rig': 'tgdog',
              'work_bead': 'tg-1',
              'grid.cursor.tg-1/agent.state': 'running',
            },
          ),
        ],
        dependencies: const [],
        readyIds: const [],
        capturedAt: DateTime(2026),
      ));
      await _pump();

      expect(timers, isEmpty);
    });
  });
}
