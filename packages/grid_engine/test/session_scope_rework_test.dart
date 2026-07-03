// tg-x1j v2 — the gate-resolve REWORK transition: a latched-gated
// SessionScope observes `grid rework`'s re-key (the adopted session vanishing
// from the join while this branch stays mounted, A40) and re-arms IN PLACE —
// closes the retired round, mints round N+1 — with no station restart. Also
// covers the guard-principle decline: a session that vanishes WITHOUT ever
// having been observed gated is never silently abandoned. Zero I/O: fakes +
// the recording chokepoint.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

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

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

Bead _task(String id, {BeadStatus status = BeadStatus.open}) =>
    Bead(id: id, issueType: IssueType.task, status: status);

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
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
            value: CircuitResolver(rootCircuit),
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
  return (owner: owner, root: root);
}

void main() {
  group('SessionScope rework re-arm (tg-x1j v2) — the gated case re-mints', () {
    test('a GATED round whose session vanishes from the join closes the '
        'retired round and mints round N+1, in place (no restart)', () async {
      final f = buildFakes(createdId: 'tgdog-round2');
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // Adopted synchronously — round 1's gated session, no mint.
      expect(f.runner.callsFor('create'), isEmpty);

      // `grid rework` re-keys round 1's `work_bead` off `tg-1` — the join no
      // longer resolves a session for this bead (exactly what
      // StationJoinBridge._join produces from that write), but the bead stays
      // in `ready` so WorkList keeps the branch MOUNTED (A40: never a
      // ready-set exit).
      joined.push(_joined(beads: [_task('tg-1')], ready: {'tg-1'}));
      m.owner.flush();
      await _pump();
      m.owner.flush();
      await _pump();

      // The retired round-1 session is closed (D-2 fold: no more hand-close).
      final closes = f.runner.callsFor('close');
      expect(closes.where((c) => c[1] == 'tgdog-round1'), hasLength(1));
      expect(closes.first.join(' '), contains('reworked'));

      // Round 2 minted fresh — a SECOND createSession, a NEW id.
      expect(f.runner.callsFor('create'), hasLength(1));

      // The fresh round's leaf mounts under the NEW session id.
      expect(reg.events, contains('START agent(tgdog-round2/tg-1/agent)'));
    });

    test('a RUNNING (never-gated) round whose session vanishes DECLINES — '
        'marks the retired session LOUD and never re-mints (the guard '
        'principle)', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-live',
              cursor: {'tg-1/agent': NodeCursor(state: StepState.running)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      expect(reg.events, ['START agent(tgdog-live/tg-1/agent)']);

      // The session vanishes from the join WITHOUT ever having been observed
      // gated (an out-of-band edit, or a bypassed CLI guard) — declines.
      joined.push(_joined(beads: [_task('tg-1')], ready: {'tg-1'}));
      m.owner.flush();
      await _pump();
      m.owner.flush();
      await _pump();

      // No close, no fresh mint — the retired session is marked, not retired.
      expect(f.runner.callsFor('close'), isEmpty);
      expect(f.runner.callsFor('create'), isEmpty);
      final updates = f.runner.callsFor('update');
      final markers = [
        for (var i = 0; i < updates.length; i++)
          if (updates[i][1] == 'tgdog-live') f.runner.metadataOfUpdate(i),
      ].where((meta) => meta.containsKey('grid.rework_declined')).toList();
      expect(markers, hasLength(1));
      expect(markers.single['grid.rework_declined'], 'true');
    });

    test('a FRESH MINT whose join has not caught up yet is never mistaken '
        'for a rework orphan', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_task('tg-1')], ready: {'tg-1'}),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // The mint completes; the join is NEVER updated to reflect it in this
      // test (exactly like the offline mint fixture) — repeated rebuilds must
      // not treat "never observed" as "vanished".
      await _pump();
      m.owner.flush();
      await _pump();
      m.owner.flush();

      expect(f.runner.callsFor('create'), hasLength(1));
      expect(f.runner.callsFor('close'), isEmpty);
      final updates = f.runner.callsFor('update');
      final declineMarkers = [
        for (var i = 0; i < updates.length; i++) f.runner.metadataOfUpdate(i),
      ].where((meta) => meta.containsKey('grid.rework_declined'));
      expect(declineMarkers, isEmpty);
      expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
    });
  });
}
