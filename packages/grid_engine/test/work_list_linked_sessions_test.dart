// tg-83k1 — a work bead with MANY linked session rows. The frontier demotes the
// older dead keys through the ONE re-key mechanic, re-mints once, and never
// skips a terminal cursor silently. Controls: a `done`/`held` row still blocks
// and demotes nothing; a surplus row whose fence is ALIVE holds the bead.
//
// Zero I/O — the recording chokepoint + a fake transport (Fakes, not mocks).
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

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

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joined(
  Map<String, SessionProjection> sessions, {
  Map<String, List<SessionProjection>> surplus = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [_task('tg-1')],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
  surplusSessionsByWorkBead: surplus,
);

/// A dead key with an EMPTY cursor — "closed with an EMPTY cursor — no step
/// ever ran", the tg-99rr shape (an operator void at zero commits). It records
/// no process fence, so the liveness probe has nothing to refuse.
SessionProjection _dead(String id, {DateTime? closedAt}) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: id,
  isTerminal: true,
  closedAt: closedAt,
);

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ExplorationTransport transport,
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
              value: CircuitResolver((_) => _code),
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

StationServices _withLiveness(StationServices base, AllocationLiveness probe) =>
    StationServices(
      provider: base.provider,
      writer: base.writer,
      stateSubstation: base.stateSubstation,
      liveness: probe,
    );

List<Map<String, dynamic>> _updatesFor(RecordingBdRunner runner, String id) {
  final updates = runner.workUpdates;
  return [
    for (var i = 0; i < updates.length; i++)
      if (updates[i].length > 1 && updates[i][1] == id)
        runner.metadataOfUpdate(i),
  ];
}

void main() {
  group('a work bead with many linked session rows', () {
    test('a ready bead whose ONE linked row is a closed dead key mints a '
        'FRESH round at the circuit first step, on the BARE work_bead key '
        '(round 0)', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final mounted = _mount(
        joined: JoinedSnapshotNotifier(_joined({'tg-1': _dead('tgdog-dead')})),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _pumpUntil(
        mounted.owner,
        () => reg.events.isNotEmpty && f.runner.workCreates.length >= 2,
      );

      expect(f.runner.workCreates, hasLength(2));
      expect(
        _updatesFor(f.runner, 'tgdog-dead').single[SessionBeadKeys.workBead],
        'tg-1#void-tgdog-dead',
      );
      expect(
        _updatesFor(f.runner, 'tgdog-sess1').singleWhere(
          (metadata) => metadata.containsKey(SessionBeadKeys.workBead),
        )[SessionBeadKeys.workBead],
        'tg-1',
      );
      expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
    });

    test(
      'TWO terminal rows mint EXACTLY ONCE and BOTH dead rows are re-keyed',
      () async {
        final f = buildFakes();
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final snapshot = _joined(
          {'tg-1': _dead('tgdog-new', closedAt: DateTime.utc(2026, 9, 3, 2))},
          surplus: {
            'tg-1': [_dead('tgdog-old', closedAt: DateTime.utc(2026, 9, 3, 1))],
          },
        );
        final joined = JoinedSnapshotNotifier(snapshot);
        final mounted = _mount(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          transport: transport,
        );
        addTearDown(mounted.owner.dispose);

        await _pumpUntil(
          mounted.owner,
          () => reg.events.isNotEmpty && f.runner.workCreates.length >= 2,
        );

        expect(f.runner.workCreates, hasLength(2));
        expect(
          _updatesFor(f.runner, 'tgdog-new').single[SessionBeadKeys.workBead],
          'tg-1#void-tgdog-new',
        );
        expect(
          _updatesFor(f.runner, 'tgdog-old').single[SessionBeadKeys.workBead],
          'tg-1#void-tgdog-old',
        );
        final retired = transport.named('work.sessionSurplusRetired');
        expect(retired, hasLength(1));
        expect(retired.single.data['sessionId'], 'tgdog-old');
        expect(retired.single.data['beadId'], 'tg-1');

        joined.push(snapshot);
        mounted.owner.flush();
        await _pump();
        expect(f.runner.workCreates, hasLength(2));
        expect(_updatesFor(f.runner, 'tgdog-new'), hasLength(1));
        expect(_updatesFor(f.runner, 'tgdog-old'), hasLength(1));
        expect(transport.named('work.sessionSurplusRetired'), hasLength(1));
      },
    );

    test(
      'a DONE row BLOCKS and demotes nothing, and the skip is LOUD',
      () async {
        final f = buildFakes();
        f.runner.exportBeads = const [
          Bead(
            id: 'tgdog-done',
            issueType: GridIssueTypes.session,
            status: BeadStatus.closed,
            metadata: {'rig': 'tgdog', 'grid.outcome': 'complete'},
          ),
        ];
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final snapshot = _joined(
          const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-done',
              isTerminal: true,
              completed: true,
            ),
          },
          surplus: {
            'tg-1': [_dead('tgdog-dead')],
          },
        );
        final joined = JoinedSnapshotNotifier(snapshot);
        final mounted = _mount(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          transport: transport,
        );
        addTearDown(mounted.owner.dispose);

        await _pump();
        mounted.owner.flush();

        expect(f.runner.calls, isEmpty);
        expect(reg.events, isEmpty);
        final skipped = transport.named('work.terminalSkip');
        expect(skipped, hasLength(1));
        expect(skipped.single.data['beadId'], 'tg-1');
        expect(skipped.single.data['sessionId'], 'tgdog-done');
        expect(skipped.single.data['disposition'], 'done');

        joined.push(snapshot);
        mounted.owner.flush();
        await _pump();
        expect(transport.named('work.terminalSkip'), hasLength(1));
      },
    );

    test('a HELD row BLOCKS and the skip names the session', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final mounted = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(
            const {
              'tg-1': SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-held',
                isTerminal: true,
                humanHeld: true,
              ),
            },
            surplus: {
              'tg-1': [_dead('tgdog-dead')],
            },
          ),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _pump();
      mounted.owner.flush();

      expect(f.runner.calls, isEmpty);
      expect(reg.events, isEmpty);
      final skipped = transport.named('work.terminalSkip');
      expect(skipped, hasLength(1));
      expect(skipped.single.data['beadId'], 'tg-1');
      expect(skipped.single.data['sessionId'], 'tgdog-held');
      expect(skipped.single.data['disposition'], 'held');
    });

    test('FAIL-CLOSED: a surplus row whose fence still probes ALIVE is not '
        'demoted and the bead does not mount', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      const liveTwin = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-live-twin',
        isTerminal: true,
        pgid: 4242,
        pid: 4243,
      );
      final mounted = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(
            {'tg-1': _dead('tgdog-new')},
            surplus: const {
              'tg-1': [liveTwin],
            },
          ),
        ),
        ctx: _withLiveness(f.ctx, (fence) => true),
        registry: reg,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _pump();
      mounted.owner.flush();

      expect(f.runner.calls, isEmpty);
      expect(reg.events, isEmpty);
      final alive = transport.named('work.sessionSurplusAlive');
      expect(alive, hasLength(1));
      expect(alive.single.data['beadId'], 'tg-1');
      expect(alive.single.data['sessionIds'], 'tgdog-live-twin');
    });

    test('TWO OPEN rows: duplicate-live is refused before any mint and no row '
        'is demoted', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final mounted = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(
            {
              'tg-1': SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-live-new',
                startedAt: DateTime.utc(2026, 9, 2),
              ),
            },
            surplus: {
              'tg-1': [
                SessionProjection(
                  workBeadId: 'tg-1',
                  sessionId: 'tgdog-live-old',
                  startedAt: DateTime.utc(2026, 9, 1),
                ),
              ],
            },
          ),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _pump();
      mounted.owner.flush();

      expect(reg.events, isEmpty);
      expect(f.runner.workUpdates, isEmpty);
      expect(f.runner.workCreates, isEmpty);
      final refused = transport.named('work.duplicateLiveRefused');
      expect(refused, hasLength(1));
      expect(refused.single.data['beadId'], 'tg-1');
      expect(refused.single.data['rivalSessionIds'], 'tgdog-live-old');
    });
  });
}
