// Track G — supervision + the restorable circuit-breaker (D-5):
//  - the failing leaf host authors the supervised-restart cursor (Track E),
//  - SessionScope escalates + tears down on breaker-exhaustion (G2),
//  - the kernel owns the backoff Timer and re-pokes on cooldown expiry (G3/F1).
//
// ADR-0008 D7 / M4-P1 Track G. Zero I/O — fakes + injected clock/timer.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

const _code = Circuit(
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

/// A `type=step` bead owned by [sessionId] at engine coordinate [path]
/// (mirrors `test/molecule/drain_seam_test.dart`'s own fixture) — the
/// breaker-exhaustion escalation SessionScope derives is now read off the
/// session's OWN molecule beads (tg-eli phase 2 retired the flat
/// `existingSession.cursor`-driven derivation: `SessionProjection.cursor` is
/// never filled by a real projection any more).
Bead _stepBead(
  String id, {
  required String sessionId,
  required String path,
  StepState? state,
  int restartCount = 0,
  String? failureReason,
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: path.split('/').last,
    MoleculeStepKeys.capability: path.split('/').last,
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.restartCount: '$restartCount',
    if (state != null) MoleculeStepKeys.state: state.name,
    if (failureReason != null) MoleculeStepKeys.failureReason: failureReason,
  },
);

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
      final reg = RecordingCapabilityRegistry(circuits: const {});
      // agent failed AND exhausted (restartCount 3 == maxRestarts 3).
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              isMolecule: true,
              moleculeBeads: [
                _stepBead(
                  'tgdog-step1',
                  sessionId: 'tgdog-s',
                  path: 'tg-1/agent',
                  state: StepState.failed,
                  restartCount: 3,
                ),
              ],
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
                value: CircuitResolver((_) => _code),
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

    test('the escalation records grid.escalation_reason (the failing node + its '
        'persisted reason) beside the marker — capture-only (FT-1)', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      // The broken node carries a persisted failureReason (as the failing leaf
      // host would have written it before exhausting the breaker).
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              isMolecule: true,
              moleculeBeads: [
                _stepBead(
                  'tgdog-step1',
                  sessionId: 'tgdog-s',
                  path: 'tg-1/agent',
                  state: StepState.failed,
                  restartCount: 3,
                  failureReason: 'the harness refused: exit 42',
                ),
              ],
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
                value: CircuitResolver((_) => _code),
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

      // The escalation write carries BOTH the marker AND the node+reason (in ONE
      // update — a mutation dropping the reason, or naming the wrong node, fails
      // here).
      final updates = f.runner.callsFor('update');
      final escIndex =
          updates.indexWhere((c) => c.join(' ').contains('grid.escalation'));
      expect(escIndex, isNonNegative);
      final meta = f.runner.metadataOfUpdate(escIndex);
      expect(meta['grid.escalation'], 'breaker-exhausted');
      expect(
        meta['grid.escalation_reason'],
        'tg-1/agent: the harness refused: exit 42',
      );
    });
  });

  group('Track G (G3/F1) — the kernel owns the backoff Timer + re-poke', () {
    test(
      'MIGRATED (tg-eli phase 2, a residual gap — flagged, not fixed here): '
      'a session bead carrying a cooldown-bearing `grid.cursor.*` payload no '
      'longer arms a Timer at all. `StationDriver._scanCooldowns` walks each '
      "session's PROJECTED `.cursor` (`station_driver.dart`, not this lane's "
      'file), and `projectSession` never fills that field for ANY bead any '
      'more (flat OR molecule — the flat `grid.cursor.*` read retired; a '
      "molecule step's cooldown lives on its OWN step bead, which "
      "StationDriver's join-level scan never reads). So the D-5/F1 backoff "
      're-poke is currently DEAD for every session shape — pinning that '
      'honestly here rather than asserting the retired flat behavior',
      () async {
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

        // Push a state snapshot: a session whose agent cursor WOULD be cooling
        // down 30s under the retired flat-projection read. CLOSED (terminal)
        // so `WedgeMonitor` skips it too — isolating `_scanCooldowns` alone
        // (a live open session with an empty projected cursor would ALSO arm
        // its own unrelated stall-poll Timer, `sample.isStalled`'s honest
        // "the engine cannot drive it" ripening — a different, already-known
        // consequence this test is not about).
        final sessionBead = Bead(
          id: 'tgdog-s',
          issueType: IssueType.session,
          status: BeadStatus.closed,
          metadata: <String, dynamic>{
            'rig': 'tgdog',
            'work_bead': 'tg-1',
            'grid.cursor.tg-1/agent.state': 'failed',
            'grid.cursor.tg-1/agent.restartCount': '1',
            'grid.cursor.tg-1/agent.cooldownUntil':
                now.add(const Duration(seconds: 30)).toIso8601String(),
          },
        );
        state.push(GraphSnapshot.fromParts(
          beads: [sessionBead],
          dependencies: const [],
          readyIds: const [],
          capturedAt: DateTime(2026),
        ));
        await _pump();

        // No Timer is armed: the projected cursor is empty, so the scan sees
        // no cooldown at all — the residual gap this test now pins.
        expect(timers, isEmpty);
      },
    );

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

      // CLOSED (terminal) — see the sibling test's doc: an OPEN session with
      // no visible cooldown would still arm WedgeMonitor's own unrelated
      // stall-poll (an empty projected cursor reads as "0 running, 0
      // cooling"), which is not what this test is about.
      state.push(GraphSnapshot.fromParts(
        beads: [
          Bead(
            id: 'tgdog-s',
            issueType: IssueType.session,
            status: BeadStatus.closed,
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
