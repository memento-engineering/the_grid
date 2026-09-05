// tg-nmhy case 2 / tg-hceh sequel — an ORPHANED POUR is resumed, not idled.
//
// `_mintMolecule` writes the session bead, then checks `_cancelled` /
// `context.mounted` before pouring the step graph. The session write itself
// triggers the snapshot tick that reconciles the WorkList — which can retire
// the minting scope mid-flight. The pour is then silently abandoned, and the
// ADOPTING scope joins a step-less molecule session that nobody will ever
// pour: pre-#122 that partial projection crashed the VM; post-#122 it idled
// FOREVER. Live receipt (2026-07-26): an entire arm minted 14 sessions and
// poured ZERO step graphs — 14 silent idles.
//
// The fix: the adopting scope RESUMES the pour — the plan is deterministic
// (`instantiateMolecule`) and `createMolecule` is re-entry-safe (R6 dedup),
// so a snapshot-lag false positive degrades to a no-op.
//
// Zero I/O — the recording chokepoint + a fake transport (Fakes, not mocks).
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
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
      flares.where((f) => f.name == name).toList();
}

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

Bead _stepBead(String id, {required String path, required String session}) =>
    Bead(
      id: id,
      issueType: GridIssueTypes.step,
      status: BeadStatus.open,
      metadata: {
        MoleculeStepKeys.path: path,
        MoleculeStepKeys.session: session,
        MoleculeStepKeys.state: StepState.pending.name,
        MoleculeStepKeys.stepId: path.split('/').last,
        MoleculeStepKeys.capability: path.split('/').last,
        MoleculeStepKeys.kind: StepKind.job.name,
      },
    );

JoinedSnapshot _joined(Map<String, SessionProjection> sessions) =>
    JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: [_task('tg-1')],
        dependencies: const [],
        readyIds: const {'tg-1'},
        capturedAt: DateTime(2026),
      ),
      sessionsByWorkBead: sessions,
    );

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ExplorationTransport transport,
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
  );
  return (owner: owner, root: root);
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

/// A [RecordingBdRunner] whose first [graphThrows] `create --graph` pours
/// THROW (the tg-aec shape: a completed future that failed — a bd timeout or
/// refused lifecycle type — against an EXISTING adopted session).
class _ThrowingGraphRunner extends RecordingBdRunner {
  _ThrowingGraphRunner({Object? beadByIdError})
    : _beadByIdError = beadByIdError;

  int graphThrows = 1;
  Object? _beadByIdError;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    final error = _beadByIdError;
    if (error != null) {
      _beadByIdError = null;
      throw error;
    }
    return super.beadById(id, types: types);
  }

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (args.length > 1 &&
        args[0] == 'create' &&
        args[1] == '--graph' &&
        graphThrows > 0) {
      graphThrows--;
      calls.add(List<String>.unmodifiable(args));
      stdins.add(stdin);
      throw StateError('fake orphan graph pour timed out');
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

/// A [StationServices] over [runner] with the runner as its probe reader too,
/// so the gate path's session-open assert and dedup probe read the same fake.
StationServices _ctxOver(_ThrowingGraphRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

/// The orphan: an OPEN molecule session bead with ZERO step beads — the
/// abandoned-pour shape the adopting scope joins.
const _orphan = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-orphan',
  isMolecule: true,
  cursor: {},
  moleculeBeads: [],
  moleculeDependencies: [],
);

JoinedSnapshot _joinedWithHealthySibling() => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [_task('tg-1'), _task('tg-2')],
    dependencies: const [],
    readyIds: const {'tg-1', 'tg-2'},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: {
    'tg-1': _orphan,
    'tg-2': SessionProjection(
      workBeadId: 'tg-2',
      sessionId: 'tgdog-healthy',
      isMolecule: true,
      cursor: const {'tg-2/agent': NodeCursor()},
      moleculeBeads: [
        _stepBead(
          'step-healthy-agent',
          path: 'tg-2/agent',
          session: 'tgdog-healthy',
        ),
        _stepBead(
          'step-healthy-verify',
          path: 'tg-2/verify',
          session: 'tgdog-healthy',
        ),
        _stepBead(
          'step-healthy-land',
          path: 'tg-2/land',
          session: 'tgdog-healthy',
        ),
      ],
      moleculeDependencies: const [],
    ),
  },
);

void main() {
  test('an adopted step-less molecule session gets its pour RESUMED: exactly '
      'one graph pour, NO fresh session mint, no flares', () async {
    final f = buildFakes();
    final transport = _RecordingTransport();
    final reg = RecordingCapabilityRegistry(circuits: const {});
    final m = _mount(
      joined: JoinedSnapshotNotifier(_joined(const {'tg-1': _orphan})),
      ctx: f.ctx,
      registry: reg,
      transport: transport,
    );
    addTearDown(m.owner.dispose);

    await _pumpUntil(m.owner, () => f.runner.callsFor('create').isNotEmpty);

    final creates = f.runner.callsFor('create');
    // Pre-fix: ZERO creates, ever — the scope idled forever on the partial
    // projection. Post-fix: exactly the resumed graph pour, and NOTHING
    // else — resuming must never mint a second session bead.
    expect(creates, isNotEmpty, reason: 'the orphaned pour must be resumed');
    expect(
      creates.where((c) => c.length > 1 && c[1] == '--graph'),
      hasLength(1),
      reason: 'the resume is a single graph pour',
    );
    expect(
      creates.where((c) => c.length > 1 && c[1] != '--graph'),
      isEmpty,
      reason: 'adoption resumes the EXISTING session — no fresh mint',
    );
    expect(transport.named('session.orphanedPourResumeFailed'), isEmpty);
  });

  test(
    'tg-q3q0 (deep): a resume whose createMolecule NO-OPS (R6 dedup — open '
    'steps already in the store, projection lagging) resets the latch: the '
    'next build RE-SCHEDULES the resume instead of idling the scope forever',
    () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      // The store ALREADY holds an open step for this session, so the
      // resume's dedup probe no-ops (no --graph pour) — but the injected
      // projection stays step-less, the exact lag that used to latch the
      // scope idle permanently.
      f.runner.exportBeads = [
        _stepBead('step-agent', path: 'tg-1/agent', session: 'tgdog-orphan'),
      ];
      final joined = JoinedSnapshotNotifier(_joined(const {'tg-1': _orphan}));
      final m = _mount(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);

      await _pumpUntil(m.owner, () => f.runner.openBeadsCallCount > 0);
      final probesAfterFirst = f.runner.openBeadsCallCount;
      expect(probesAfterFirst, greaterThan(0));
      expect(
        f.runner
            .callsFor('create')
            .where((c) => c.length > 1 && c[1] == '--graph'),
        isEmpty,
        reason: 'the dedup probe suppresses the pour',
      );

      // A later snapshot (fresh instance, same step-less shape) rebuilds the
      // scope. Pre-fix: the success-path latch was never reset, the build
      // hit the guard, and the scope idled forever. Post-fix: the resume is
      // re-scheduled (another dedup probe fires).
      joined.push(_joined(const {'tg-1': _orphan}));
      await _pumpUntil(
        m.owner,
        () => f.runner.openBeadsCallCount > probesAfterFirst,
        maxRounds: 200,
      );
      expect(
        f.runner.openBeadsCallCount,
        greaterThan(probesAfterFirst),
        reason:
            'the latch must reset after a no-op resume so a later '
            'build can retry — the reset-only-on-failure posture idled '
            'the scope for the life of the arm',
      );
      expect(transport.named('session.orphanedPourResumeFailed'), isEmpty);
    },
  );

  for (final scenario in <({String label, Object error, String reason})>[
    (
      label: 'TimeoutException',
      error: TimeoutException('fake gate assertion timed out'),
      reason: 'fake gate assertion timed out',
    ),
    (
      label: 'StateError',
      error: StateError('fake gate assertion refused'),
      reason: 'fake gate assertion refused',
    ),
  ]) {
    test(
      'orphan-resume park failure is contained (${scenario.label})',
      () async {
        final runner = _ThrowingGraphRunner(beadByIdError: scenario.error);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final uncaught = <Object>[];
        late ({TreeOwner owner, Branch root}) mounted;

        await runZonedGuarded(() async {
          mounted = _mount(
            joined: JoinedSnapshotNotifier(_joinedWithHealthySibling()),
            ctx: _ctxOver(runner),
            registry: reg,
            transport: transport,
          );
          await _pumpUntil(
            mounted.owner,
            () =>
                transport.named('session.moleculePourParkFailed').isNotEmpty &&
                reg.events.contains('START agent(tgdog-healthy/tg-2/agent)'),
          );
          await Future<void>.delayed(Duration.zero);
          mounted.owner.flush();
        }, (error, stackTrace) => uncaught.add(error))!;
        addTearDown(mounted.owner.dispose);

        expect(uncaught, isEmpty);
        final parkFailures = transport.named('session.moleculePourParkFailed');
        expect(parkFailures, hasLength(1));
        expect(parkFailures.single.data['sessionId'], 'tgdog-orphan');
        expect(parkFailures.single.data['workBeadId'], 'tg-1');
        expect(parkFailures.single.data['reason'], contains(scenario.reason));
        expect(
          reg.events,
          contains('START agent(tgdog-healthy/tg-2/agent)'),
          reason: 'a failed orphan park must not kill healthy sibling work',
        );
      },
    );
  }

  test(
    'failed orphan-resume park clears its latch for a later build retry',
    () async {
      final runner = _ThrowingGraphRunner(
        beadByIdError: StateError('fake gate assertion refused once'),
      );
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(_joined(const {'tg-1': _orphan}));
      final m = _mount(
        joined: joined,
        ctx: _ctxOver(runner),
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);

      await _pumpUntil(
        m.owner,
        () => transport.named('session.moleculePourParkFailed').isNotEmpty,
      );
      expect(
        runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );

      joined.push(_joined(const {'tg-1': _orphan}));
      await _pumpUntil(
        m.owner,
        () =>
            runner.calls
                .where((c) => c.length > 1 && c[1] == '--graph')
                .length >=
            2,
      );

      expect(
        runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(2),
        reason: 'a later snapshot retries the existing session pour',
      );
      expect(
        runner
            .callsFor('create')
            .where((c) => c.length <= 1 || c[1] != '--graph'),
        isEmpty,
        reason:
            'retrying an adopted session mints no replacement session or gate',
      );
      expect(
        transport.named('session.moleculePourParkFailed'),
        hasLength(1),
        reason: 'the successful retry emits no duplicate park-failure flare',
      );
    },
  );

  test('a THROWN resume pour flares moleculePourFailed once, parks the adopted '
      'session at a durable gate, and never re-pours (tg-aec)', () async {
    final runner = _ThrowingGraphRunner();
    final transport = _RecordingTransport();
    final reg = RecordingCapabilityRegistry(circuits: const {});
    final joined = JoinedSnapshotNotifier(_joined(const {'tg-1': _orphan}));
    final m = _mount(
      joined: joined,
      ctx: _ctxOver(runner),
      registry: reg,
      transport: transport,
    );
    addTearDown(m.owner.dispose);

    await _pumpUntil(
      m.owner,
      () => runner
          .callsFor('update')
          .any((c) => c.join(' ').contains('Molecule pour failed')),
    );

    // The same orphan shape lands again — the parked scope must stay
    // parked: no second pour, no second gate, no flare spam.
    joined.push(_joined(const {'tg-1': _orphan}));
    await _pumpUntil(m.owner, () => false, maxRounds: 30);

    // LOUD once, cause-bearing, naming the ADOPTED session.
    final parked = transport.named('session.moleculePourFailed');
    expect(parked, hasLength(1));
    expect(parked.single.data['sessionId'], 'tgdog-orphan');
    expect(parked.single.data['workBeadId'], 'tg-1');
    expect(
      parked.single.data['reason'],
      contains('fake orphan graph pour timed out'),
    );
    // The park REPLACES the old silent-retry flare, it does not add to it.
    expect(transport.named('session.orphanedPourResumeFailed'), isEmpty);

    // ONE pour attempt total — terminal park, never a blind re-pour.
    expect(
      runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
      hasLength(1),
    );
    // One gate bead created (the only plain create — adoption never mints
    // a fresh session), and one cause-bearing stamp re-arm linkage.
    expect(
      runner
          .callsFor('create')
          .where((c) => c.length <= 1 || c[1] != '--graph'),
      hasLength(1),
    );
    final updates = runner.callsFor('update');
    final stamps = [
      for (var i = 0; i < updates.length; i++)
        if (runner.metadataOfUpdate(i).containsKey('blocks'))
          runner.metadataOfUpdate(i),
    ];
    expect(stamps, hasLength(1));
    final stamp = stamps.single;
    expect(stamp['blocks'], 'tgdog-orphan');
    expect(stamp['node'], 'tg-1');
    expect(stamp['reason'], contains('fake orphan graph pour timed out'));

    // The parked session never inflates the circuit.
    expect(reg.events, isEmpty);
  });

  test(
    'a healthy adopted molecule session (steps present) pours NOTHING',
    () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final healthy = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-live',
        isMolecule: true,
        cursor: const {'tg-1/agent': NodeCursor()},
        moleculeBeads: [
          _stepBead('step-agent', path: 'tg-1/agent', session: 'tgdog-live'),
          _stepBead('step-verify', path: 'tg-1/verify', session: 'tgdog-live'),
          _stepBead('step-land', path: 'tg-1/land', session: 'tgdog-live'),
        ],
        moleculeDependencies: const [],
      );
      final m = _mount(
        joined: JoinedSnapshotNotifier(_joined({'tg-1': healthy})),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);

      await _pumpUntil(m.owner, () => reg.events.isNotEmpty, maxRounds: 200);

      expect(
        f.runner
            .callsFor('create')
            .where((c) => c.length > 1 && c[1] == '--graph'),
        isEmpty,
        reason: 'a complete projection never triggers a resume pour',
      );
    },
  );
}
