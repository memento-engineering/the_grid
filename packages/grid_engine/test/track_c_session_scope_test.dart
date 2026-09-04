// Track C — SessionScope (D-2): adopt-or-mint the session ABOVE the fan-out
// (one mint per work bead, never per leaf), provide the SessionHandle, own the
// positive-terminal close — and the work-tick flush stays isolated to WorkList
// (invariant 1 AT DEPTH, the new path).
//
// ADR-0008 D4 / M4-P1 §4, Track C. Zero I/O — fakes + the recording chokepoint.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';
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

const _burn = Circuit(
  id: 'burn',
  terminalStepId: 'report',
  steps: [
    CapabilityStep(stepId: 'a', capabilityId: 'a'),
    CapabilityStep(stepId: 'b', capabilityId: 'b'), // also dep-free → fan-out
    CapabilityStep(
      stepId: 'report',
      capabilityId: 'report',
      dependsOn: {'a', 'b'},
    ),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains TWO bd round-trips (`createSession`, then
/// `createMolecule`'s dedup-probe export + graph-apply pour, each its own
/// async gap) rather than the flat model's single `create` — polling is what
/// makes waiting for a fresh mint's inflated leaf deterministic (tg-eli
/// phase 2).
Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    // A molecule mint's `create --graph` pour writes a REAL temp file
    // (`BdCliService.applyGraph`'s plan.json) — genuine disk I/O, not just
    // microtask chaining — so a short real-time cushion is what makes
    // waiting for it deterministic under load (tg-eli phase 2: the flat
    // model's in-memory-only mint never hit disk).
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  List<BeadDependency> dependencies = const [],
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: dependencies,
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

/// The full new-path root: WorkList observes [joined]; WorkBead resolves through
/// the CircuitResolver → SessionScope → CircuitScope; SessionScope mints via the
/// StationServices writer; CircuitScope inflates via the registry.
({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
  ServiceBundle services = const ServiceBundle(),
  SubstationConfig substationConfig = _tgConfig,
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
                  configNotifier: SubstationConfigNotifier(substationConfig),
                  services: services,
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

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _whereSeed(Branch root, bool Function(Seed seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

void main() {
  group('Track C — SessionScope mints ONCE, above the fan-out', () {
    test(
      'a ready bead with no session mints exactly one session, then inflates',
      () async {
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

        // Resolving: no leaf yet (the session mint is async).
        expect(reg.events, isEmpty);
        await _pumpUntil(
          m.owner,
          () => reg.events.isNotEmpty && f.runner.workCreates.length >= 2,
        );

        // Exactly ONE createSession (minted above the fan-out) plus its
        // molecule pour (tg-eli phase 2: every fresh mint pours a molecule
        // graph — a second `create` call, `create --graph`), then the first
        // step inflates under the minted SessionHandle (id = tgdog-sess1).
        final creates = f.runner.workCreates;
        expect(creates, hasLength(2));
        expect(
          creates.where((c) => c.length > 1 && c[1] == '--graph'),
          hasLength(1),
        );
        expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
      },
    );

    test(
      'a fan-out circuit (two dep-free steps) still mints ONE session',
      () async {
        final f = buildFakes();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final joined = JoinedSnapshotNotifier(
          _joined(beads: [_task('tg-burn')], ready: {'tg-burn'}),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _burn,
        );
        addTearDown(m.owner.dispose);
        await _pumpUntil(
          m.owner,
          () => reg.events.length >= 2 && f.runner.workCreates.length >= 2,
        );

        // ONE mint (+ its molecule pour, tg-eli phase 2), both dep-free leaves
        // mounted under the SAME session id, with DISJOINT paths (disjoint
        // routing) — never two mints / two sessions.
        final creates = f.runner.workCreates;
        expect(creates, hasLength(2));
        expect(
          creates.where((c) => c.length > 1 && c[1] == '--graph'),
          hasLength(1),
        );
        expect(
          reg.events,
          unorderedEquals([
            'START a(tgdog-sess1/tg-burn/a)',
            'START b(tgdog-sess1/tg-burn/b)',
          ]),
        );
      },
    );

    test(
      'genesis-7ob real frontier shape mints or names a clause within one tick',
      () async {
        final f = buildFakes();
        final transport = RecordingExplorationTransport();
        final writer = StationBeadWriter(
          bd: BdCliService(f.runner),
          reader: f.runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
          onFlare: transport.flare,
        );
        const genesis = Bead(
          id: 'genesis-7ob',
          title:
              'P0: release tree invariants permit infinite flushes and '
              'corrupted reconciliation',
          issueType: IssueType.bug,
          status: BeadStatus.open,
          priority: 0,
          labels: ['orchestrator', 'review'],
          metadata: {
            'grid.approved_at': '2026-09-03T05:10:45.328492Z',
            'grid.approved_by': 'operator',
            'grid.approved_rev': 'db134bf211b3d1c3f037066eff178cf33d96af3a',
            'validation_plan':
                'cd packages/tree && dart analyze && dart test && dart run '
                'test/release_invariants_test.dart',
          },
        );
        const predecessor = Bead(
          id: 'genesis-7r9',
          issueType: IssueType.bug,
          status: BeadStatus.closed,
          priority: 0,
        );
        const alreadyLive = Bead(
          id: 'genesis-live',
          issueType: IssueType.task,
          status: BeadStatus.open,
          priority: 4,
        );
        final snapshot = _joined(
          beads: const [genesis, predecessor, alreadyLive],
          ready: const {'genesis-7ob'},
          dependencies: const [
            BeadDependency(
              issueId: 'genesis-7ob',
              dependsOnId: 'genesis-7r9',
              type: DependencyType.discoveredFrom,
            ),
          ],
          sessions: const {
            'genesis-live': SessionProjection(
              workBeadId: 'genesis-live',
              sessionId: 'tgdog-live',
            ),
          },
        );

        // the-frontier-demotes-surplus-linked-sessions governs the adjacent
        // join branch. The live receipt did not enumerate linked rows, so this
        // witness deliberately isolates the specified no-session acceptance
        // shape, while work_list_linked_sessions_test covers every non-empty
        // verdict (adopt, blocking terminal, dead-key remint, and surplus).
        expect(snapshot.linkedSessions(genesis.id), isEmpty);

        final joined = JoinedSnapshotNotifier(snapshot);
        final registry = RecordingCapabilityRegistry(circuits: const {});
        final mounted = _mountFull(
          joined: joined,
          ctx: StationServices(
            provider: f.provider,
            writer: writer,
            stateSubstation: stateSubstation,
            maxConcurrentWork: 6,
          ),
          registry: registry,
          rootCircuit: (_) => _code,
          services: ServiceBundle(transport: transport),
          substationConfig: const SubstationConfig(
            substationId: 'genesis',
            ownedSubstations: {'genesis'},
            resident: true,
            maxConcurrentWork: 6,
          ),
        );
        addTearDown(mounted.owner.dispose);

        bool namesGenesis(({String name, Map<String, String> data}) flare) {
          if (flare.name == 'session.minted' ||
              flare.name == 'session.mintRefused') {
            return flare.data['workBeadId'] == genesis.id;
          }
          if (flare.name == 'work.throttled') {
            return flare.data['beadIds']?.split(',').contains(genesis.id) ??
                false;
          }
          return const {
                'work.mountEligibilityRefused',
                'work.trustRefused',
              }.contains(flare.name) &&
              flare.data['beadId'] == genesis.id;
        }

        await _pumpUntil(
          mounted.owner,
          () => transport.flares.any(namesGenesis),
        );

        final observed = transport.flares.where(namesGenesis).toList();
        expect(
          observed,
          isNotEmpty,
          reason: 'a resident frontier head must never disappear silently',
        );
        expect(
          transport
              .named('session.minted')
              .where((flare) => flare.data['workBeadId'] == genesis.id),
          hasLength(1),
          reason: 'the valid no-session fixture must take the mint branch',
        );
      },
    );
  });

  group('Track C — SessionScope adopts an existing session', () {
    test('a bead with a linked session adopts it synchronously (no mint)', () {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-existing',
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

      // Adopted synchronously on mount — no createSession, leaf under the
      // adopted id.
      expect(f.runner.workCreates, isEmpty);
      expect(reg.events, ['START agent(tgdog-existing/tg-1/agent)']);
    });
  });

  test('closed work bead settles live molecule session', () async {
    final f = buildFakes();
    final transport = RecordingExplorationTransport();
    const sessionId = 'tgdog-live';
    f.runner.exportBeads = const [
      Bead(
        id: sessionId,
        issueType: GridIssueTypes.session,
        metadata: {
          'rig': 'tgdog',
          SessionBeadKeys.workBead: 'tg-closed',
          SessionBeadKeys.model: kSessionModelMolecule,
        },
      ),
      Bead(
        id: 'tgdog-molecule',
        issueType: GridIssueTypes.molecule,
        metadata: {'grid.circuit.session': sessionId},
      ),
      Bead(
        id: 'tgdog-running-step',
        issueType: GridIssueTypes.step,
        metadata: {
          'grid.step.session': sessionId,
          'grid.step.state': 'running',
        },
      ),
      Bead(
        id: 'tgdog-live-gate',
        issueType: GridIssueTypes.gate,
        metadata: {
          'rig': 'tgdog',
          'blocks': sessionId,
          'node': 'review/pin-diff',
        },
      ),
    ];
    final writer = StationBeadWriter(
      bd: BdCliService(f.runner),
      reader: f.runner,
      ownership: BeadOwnershipPredicate(const {'tgdog'}),
      onFlare: transport.flare,
    );
    final joined = JoinedSnapshotNotifier(
      _joined(
        beads: [_task('tg-closed')],
        ready: {'tg-closed'},
        sessions: {
          'tg-closed': const SessionProjection(
            workBeadId: 'tg-closed',
            sessionId: sessionId,
          ),
        },
      ),
    );
    final registry = RecordingCapabilityRegistry();
    final mounted = _mountFull(
      joined: joined,
      ctx: StationServices(
        provider: f.provider,
        writer: writer,
        stateSubstation: 'tgdog',
      ),
      registry: registry,
      rootCircuit: (_) => _code,
      services: ServiceBundle(transport: transport),
    );
    addTearDown(mounted.owner.dispose);
    expect(registry.events, ['START agent($sessionId/tg-closed/agent)']);

    joined.push(
      _joined(
        beads: [_task('tg-closed', status: BeadStatus.closed)],
        ready: const {},
        sessions: {
          'tg-closed': const SessionProjection(
            workBeadId: 'tg-closed',
            sessionId: sessionId,
          ),
        },
      ),
    );
    mounted.owner.flush();
    await _pumpUntil(
      mounted.owner,
      () => f.runner.callsFor('close').any((call) => call[1] == sessionId),
    );

    final sessionUpdate = f.runner
        .callsFor('update')
        .firstWhere(
          (call) =>
              call[1] == sessionId && call.join(' ').contains('grid.outcome'),
        );
    expect(sessionUpdate.join(' '), contains('grid.outcome=complete'));
    expect(
      sessionUpdate.join(' '),
      contains('grid.work_terminal_reason=work-bead-closed-under-live-session'),
    );
    expect(
      f.runner.stdins.whereType<String>().join('\n'),
      allOf(
        contains('close tgdog-running-step'),
        contains('close tgdog-molecule'),
      ),
    );
    expect(
      f.runner.callsFor('close').map((call) => call[1]),
      containsAll([sessionId, 'tgdog-live-gate']),
    );
    expect(transport.named('session.workTerminal').single.data, const {
      'sessionId': sessionId,
      'workBeadId': 'tg-closed',
      'reason': kWorkTerminalReasonWorkBeadClosed,
    });
    expect(registry.events, [
      'START agent($sessionId/tg-closed/agent)',
      'STOP agent($sessionId/tg-closed/agent)',
    ]);
  });

  group('Track C — SessionScope owns the positive-terminal close (D-2)', () {
    test(
      'when the terminal step completes, the session is closed exactly once',
      () async {
        final f = buildFakes();
        final transport = RecordingExplorationTransport();
        f.runner.exportBeads = const [
          Bead(
            id: 'tgdog-s',
            issueType: GridIssueTypes.session,
            status: BeadStatus.closed,
            metadata: {'rig': 'tgdog', 'grid.outcome': 'complete'},
          ),
          Bead(
            id: 'tgdog-terminal-gate',
            issueType: GridIssueTypes.gate,
            metadata: {
              'rig': 'tgdog',
              'blocks': 'tgdog-s',
              'node': 'review/route',
            },
          ),
        ];
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-s',
              ),
            },
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          services: ServiceBundle(transport: transport),
        );
        addTearDown(m.owner.dispose);

        // Drive the cursor to the terminal (land complete).
        joined.push(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-s',
                cursor: {
                  'tg-1/agent': NodeCursor(state: StepState.complete),
                  'tg-1/verify': NodeCursor(state: StepState.complete),
                  'tg-1/land': NodeCursor(state: StepState.complete),
                },
              ),
            },
          ),
        );
        m.owner.flush();

        // The close is SCHEDULED off build, NOT written during build (invariant 2:
        // no writes in build()) — so immediately after the synchronous flush, no
        // close has been issued yet.
        expect(
          f.runner.callsFor('close'),
          isEmpty,
          reason:
              'the close must be scheduled off build, not written in build()',
        );

        await _pump();
        await _pumpUntil(
          m.owner,
          () => f.runner
              .callsFor('close')
              .any(
                (call) => call.length > 1 && call[1] == 'tgdog-terminal-gate',
              ),
        );

        // After the microtask drains, SessionScope closed the session, exactly once
        // (latched).
        expect(
          f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
          hasLength(1),
        );
        expect(transport.named('session.closed').single.data, {
          'sessionId': 'tgdog-s',
          'disposition': 'done',
        });
        expect(
          f.runner.calls
              .where((call) => call.length > 1)
              .map((call) => '${call.first}:${call[1]}'),
          containsAllInOrder(<String>[
            'close:tgdog-s',
            'update:tgdog-terminal-gate',
            'close:tgdog-terminal-gate',
          ]),
        );
        expect(
          f.runner.calls
              .singleWhere(
                (call) =>
                    call.length > 1 &&
                    call.first == 'update' &&
                    call[1] == 'tgdog-terminal-gate' &&
                    call.contains('--if-status'),
              )
              .join(' '),
          contains('grid.gate.close_cause=session-terminal'),
        );
      },
    );

    test('the close is latched once across repeated terminal rebuilds', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      const terminal = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s',
        cursor: {
          'tg-1/agent': NodeCursor(state: StepState.complete),
          'tg-1/verify': NodeCursor(state: StepState.complete),
          'tg-1/land': NodeCursor(state: StepState.complete),
        },
      );
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {'tg-1': terminal},
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      await _pump();

      // Re-push the SAME terminal snapshot twice → SessionScope rebuilds, but the
      // _closeScheduled latch fires the close exactly once.
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {'tg-1': terminal},
        ),
      );
      m.owner.flush();
      await _pump();
      expect(
        f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
        hasLength(1),
      );
    });

    test(
      'delivery-bound terminal without recorded outcome blocks close and flares',
      () async {
        final f = buildFakes();
        final transport = RecordingExplorationTransport();
        final method = RecordingDeliveryMethod(id: 'github-pr');
        final reg = RecordingCapabilityRegistry(circuits: const {});
        const terminal = SessionProjection(
          workBeadId: 'tg-1',
          sessionId: 'tgdog-s',
          cursor: {
            'tg-1/agent': NodeCursor(state: StepState.complete),
            'tg-1/verify': NodeCursor(state: StepState.complete),
            'tg-1/land': NodeCursor(state: StepState.complete),
          },
          results: {
            'tg-1/land': {'grade': 'A'},
          },
        );
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            sessions: {'tg-1': terminal},
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          services: ServiceBundle(delivery: method, transport: transport),
        );
        addTearDown(m.owner.dispose);

        await _pump();
        m.owner.flush();
        await _pump();

        expect(f.runner.callsFor('close'), isEmpty);
        expect(f.runner.callsFor('update'), isEmpty);
        expect(method.requests, isEmpty);
        final flares = transport.named('delivery.outcomeMissing').toList();
        expect(flares, hasLength(1));
        expect(flares.single.data, {
          'sessionId': 'tgdog-s',
          'workBeadId': 'tg-1',
          'nodePath': 'tg-1/land',
          'method': 'github-pr',
        });

        joined.push(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            sessions: {'tg-1': terminal},
          ),
        );
        m.owner.flush();
        await _pump();

        expect(f.runner.callsFor('close'), isEmpty);
        expect(transport.named('delivery.outcomeMissing'), hasLength(1));
      },
    );

    test(
      'delivery-bound terminal with recorded outcome closes exactly once',
      () async {
        final f = buildFakes();
        final transport = RecordingExplorationTransport();
        final method = RecordingDeliveryMethod(id: 'github-pr');
        final reg = RecordingCapabilityRegistry(circuits: const {});
        const terminal = SessionProjection(
          workBeadId: 'tg-1',
          sessionId: 'tgdog-s',
          cursor: {
            'tg-1/agent': NodeCursor(state: StepState.complete),
            'tg-1/verify': NodeCursor(state: StepState.complete),
            'tg-1/land': NodeCursor(state: StepState.complete),
          },
          results: {
            'tg-1/land': {
              ResultKeys.delivery: 'github-pr',
              'pr_url': 'https://example.test/pr/66',
            },
          },
        );
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            sessions: {'tg-1': terminal},
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          services: ServiceBundle(delivery: method, transport: transport),
        );
        addTearDown(m.owner.dispose);

        await _pump();
        m.owner.flush();
        await _pump();

        expect(
          f.runner.callsFor('close').where((call) => call[1] == 'tgdog-s'),
          hasLength(1),
        );
        expect(f.runner.metadataOfUpdate(0), sessionCompleteMetadata());
        expect(transport.named('delivery.outcomeMissing'), isEmpty);
        expect(method.requests, isEmpty);
      },
    );
  });

  group(
    'Track C — invariant 1 at depth: only WorkList dirties on a work tick',
    () {
      test(
        'a cursor advance flush() returns exactly [WorkList]; config ancestors '
        '+ the inflater are absent from the drain',
        () {
          final f = buildFakes();
          final reg = RecordingCapabilityRegistry(circuits: const {});
          final joined = JoinedSnapshotNotifier(
            _joined(
              beads: [_task('tg-1')],
              ready: {'tg-1'},
              sessions: {
                'tg-1': const SessionProjection(
                  workBeadId: 'tg-1',
                  sessionId: 'tgdog-s',
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
          expect(reg.events, ['START agent(tgdog-s/tg-1/agent)']);
          reg.events.clear();

          // Advance the per-node cursor (agent complete) via the join.
          joined.push(
            _joined(
              beads: [_task('tg-1')],
              ready: {'tg-1'},
              sessions: {
                'tg-1': const SessionProjection(
                  workBeadId: 'tg-1',
                  sessionId: 'tgdog-s',
                  cursor: {'tg-1/agent': NodeCursor(state: StepState.complete)},
                ),
              },
            ),
          );
          final flushed = m.owner.flush();

          // Only the observing node drained — the SessionScope/CircuitScope/leaves
          // are force-rebuilt by WorkList's cascade, excluded from the drain.
          final workList = _whereSeed(m.root, (s) => s is WorkList);
          expect(flushed, equals([workList]));
          // The swap happened (agent retired, verify entered).
          expect(
            reg.events,
            unorderedEquals([
              'STOP agent(tgdog-s/tg-1/agent)',
              'START verify(tgdog-s/tg-1/verify)',
            ]),
          );
          // Config ancestors + the inflater are absent from the drain.
          expect(
            flushed,
            isNot(contains(_whereSeed(m.root, (s) => s is Station))),
          );
          expect(
            flushed,
            isNot(contains(_whereSeed(m.root, (s) => s is SubstationScope))),
          );
          expect(
            flushed,
            isNot(contains(_whereSeed(m.root, (s) => s is CircuitScope))),
          );
          expect(
            flushed,
            isNot(contains(_whereSeed(m.root, (s) => s is SessionScope))),
          );
        },
      );
    },
  );
}
