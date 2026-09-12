import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

final class _MutableEligibility {
  MountEligibilityDecision decision = const MountEligibilityDecision.eligible();
  int evaluations = 0;

  MountEligibilityDecision call(Bead bead) {
    evaluations += 1;
    return decision;
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map.unmodifiable(data)));
  }
}

final class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) {
    throw StateError('transport unavailable');
  }
}

final class _RecordingResolver implements SessionResolver {
  final calls = <String>[];

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) {
    calls.add(bead.id);
    return const Idle();
  }
}

final class _LifecycleRecordingResolver implements SessionResolver {
  final events = <String>[];

  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      _LifecycleChild(
        beadId: bead.id,
        events: events,
        key: ValueKey('session:${bead.id}'),
      );
}

final class _LifecycleChild extends StatefulSeed {
  const _LifecycleChild({
    required this.beadId,
    required this.events,
    super.key,
  });

  final String beadId;
  final List<String> events;

  @override
  State<_LifecycleChild> createState() => _LifecycleChildState();
}

final class _LifecycleChildState extends State<_LifecycleChild> {
  @override
  void initState() => seed.events.add('start:${seed.beadId}');

  @override
  void dispose() => seed.events.add('dispose:${seed.beadId}');

  @override
  Seed build(TreeContext context) => const Idle();
}

final class _Harness {
  _Harness({
    required this.owner,
    required this.root,
    required this.joined,
    required this.bead,
    required this.runner,
  });

  final TreeOwner owner;
  final Branch root;
  final JoinedSnapshotNotifier joined;
  final Bead bead;
  final RecordingBdRunner runner;
  var _second = 1;

  void pushAndFlush({
    Set<String>? readyIds,
    DateTime? stateCapturedAt,
    Map<String, String> frontierExclusionsByBeadId = const {},
    Map<String, SessionProjection> sessionsByWorkBead = const {},
  }) {
    joined.push(
      _snapshot(
        bead,
        _second++,
        readyIds: readyIds,
        stateCapturedAt: stateCapturedAt,
        frontierExclusionsByBeadId: frontierExclusionsByBeadId,
        sessionsByWorkBead: sessionsByWorkBead,
      ),
    );
    owner.flush();
  }

  List<WorkBead> workBeads() => _workBeads(root);
}

Bead _task() =>
    const Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _snapshot(
  Bead bead,
  int second, {
  Set<String>? readyIds,
  DateTime? stateCapturedAt,
  List<Bead> additionalBeads = const [],
  Map<String, String> frontierExclusionsByBeadId = const {},
  Map<String, SessionProjection> sessionsByWorkBead = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [bead, ...additionalBeads],
    dependencies: const [],
    readyIds: readyIds ?? {bead.id},
    capturedAt: DateTime(2026, 1, 1, 0, 0, second),
  ),
  stateCapturedAt: stateCapturedAt,
  sessionsByWorkBead: sessionsByWorkBead,
  frontierExclusionsByBeadId: frontierExclusionsByBeadId,
);

List<WorkBead> _workBeads(Branch root) {
  final found = <WorkBead>[];
  void walk(Branch branch) {
    if (branch.seed case final WorkBead bead) found.add(bead);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
}

Future<void> _settleAdmissions(_Harness harness) async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    harness.owner.flush();
  }
}

_Harness _mountHarness({
  Bead? bead,
  MountEligibilityPredicate? mountEligibility,
  ExplorationTransport? transport,
  Set<String>? readyIds,
  DateTime? stateCapturedAt,
  List<Bead> additionalBeads = const [],
  Map<String, String> frontierExclusionsByBeadId = const {},
  Map<String, SessionProjection> sessionsByWorkBead = const {},
  SessionResolver? resolver,
  bool includeStationServices = true,
  TrajectoryRecorderScope? trajectoryScope,
}) {
  final workBead = bead ?? _task();
  final joined = JoinedSnapshotNotifier(
    _snapshot(
      workBead,
      0,
      readyIds: readyIds,
      stateCapturedAt: stateCapturedAt,
      additionalBeads: additionalBeads,
      frontierExclusionsByBeadId: frontierExclusionsByBeadId,
      sessionsByWorkBead: sessionsByWorkBead,
    ),
  );
  final owner = TreeOwner();
  final fakes = buildFakes();
  Seed station = InheritedSeed<JoinedSnapshotNotifier>(
    value: joined,
    child: InheritedSeed<SessionResolver>(
      value: resolver ?? _RecordingResolver(),
      child: Station([
        SubstationScope(
          configNotifier: SubstationConfigNotifier(
            const SubstationConfig(
              substationId: 'test',
              ownedSubstations: {'tg'},
              maxConcurrentWork: 10,
            ),
          ),
          services: ServiceBundle(
            transport: transport,
            mountEligibility: mountEligibility,
          ),
        ),
      ]),
    ),
  );
  if (includeStationServices) {
    station = InheritedSeed<StationServices>(value: fakes.ctx, child: station);
  }
  if (trajectoryScope != null) {
    station = InheritedSeed<TrajectoryRecorderScope>(
      value: trajectoryScope,
      child: station,
    );
  }
  final root = owner.mountRoot(ProviderScope(child: station));
  addTearDown(() {
    owner.dispose();
    fakes.ctx.dispose();
  });
  return _Harness(
    owner: owner,
    root: root,
    joined: joined,
    bead: workBead,
    runner: fakes.runner,
  );
}

void main() {
  test(
    'fresh cross-link clause gates valid approvals until the state read catches up',
    () async {
      final approval = DateTime.utc(2026, 9, 10, 5, 30, 41);
      final approved = Bead(
        id: 'tg-1',
        issueType: IssueType.task,
        status: BeadStatus.open,
        metadata: const {'grid.approved_at': '2026-09-10T00:30:41-05:00'},
      );
      const clause = 'fresh cross-link read pending: tg-1';

      MountEligibilityDecision evaluate(Bead bead, DateTime? capturedAt) =>
          freshCrossLinkReadClause(capturedAt)(bead);

      expect(
        evaluate(approved, null),
        const MountEligibilityDecision.refused(clause: clause),
      );
      expect(
        evaluate(approved, approval.subtract(const Duration(microseconds: 1))),
        const MountEligibilityDecision.refused(clause: clause),
      );
      expect(
        evaluate(approved, approval),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(approved, approval.add(const Duration(microseconds: 1))),
        const MountEligibilityDecision.eligible(),
      );

      for (final bead in <Bead>[
        _task(),
        const Bead(
          id: 'tg-1',
          issueType: IssueType.task,
          metadata: {'grid.approved_at': ''},
        ),
        const Bead(
          id: 'tg-1',
          issueType: IssueType.task,
          metadata: {'grid.approved_at': 41},
        ),
        const Bead(
          id: 'tg-1',
          issueType: IssueType.task,
          metadata: {'grid.approved_at': 'not-an-instant'},
        ),
      ]) {
        expect(
          evaluate(bead, null),
          const MountEligibilityDecision.eligible(),
          reason: 'the vended approval policy owns malformed or absent values',
        );
      }

      final stale = approval.subtract(const Duration(seconds: 13));
      final authorityTransport = _RecordingTransport();
      final authority = _mountHarness(
        bead: approved,
        stateCapturedAt: stale,
        transport: authorityTransport,
      );
      expect(authority.workBeads(), isEmpty);
      expect(
        authorityTransport.flares.single.name,
        'work.mountEligibilityRefused',
      );
      expect(authorityTransport.flares.single.data, {
        'beadId': 'tg-1',
        'clause': clause,
      });

      authority.pushAndFlush(stateCapturedAt: approval);
      await _settleAdmissions(authority);
      expect(authority.workBeads().map((work) => work.bead.id), ['tg-1']);
      expect(
        authorityTransport.flares.last.name,
        'work.mountEligibilityRestored',
      );
      expect(authorityTransport.flares.last.data, {
        'beadId': 'tg-1',
        'clause': clause,
      });

      final offline = _mountHarness(
        bead: approved,
        stateCapturedAt: stale,
        includeStationServices: false,
      );
      expect(offline.workBeads(), isEmpty);
      offline.pushAndFlush(stateCapturedAt: approval);
      expect(offline.workBeads().map((work) => work.bead.id), ['tg-1']);
    },
  );

  test(
    'offline fallback refuses fresh work after the shared trajectory halt',
    () {
      final runner = RecordingBdRunner();
      final writer = StationBeadWriter(
        bd: BdCliService(runner),
        reader: runner,
        ownership: BeadOwnershipPredicate(const {'tg'}),
      );
      final halt = TrajectoryAdmissionHalt(
        writer: writer,
        stateSubstation: 'tg',
        bootEpoch: () => 1,
      );
      final harness = _mountHarness(
        includeStationServices: false,
        readyIds: const {},
        trajectoryScope: TrajectoryRecorderScope(
          TrajectoryRecorderScope.disabled.recorder,
          admissionHalt: halt,
        ),
      );

      halt.latch(reason: 'controlled', recordClass: 'step.transition');
      harness.owner.flush();
      harness.pushAndFlush(readyIds: const {'tg-1'});

      expect(harness.workBeads(), isEmpty);
      expect(runner.calls, isEmpty);
    },
  );

  test('warm live branch keeps identity and refusal flares once', () async {
    const staleApproval = 'approval: stale - rerun the approve verb';
    const liveSessions = {
      'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-live'),
    };
    final eligibility = _MutableEligibility();
    final transport = _RecordingTransport();
    final resolver = _LifecycleRecordingResolver();
    final harness = _mountHarness(
      mountEligibility: eligibility.call,
      transport: transport,
      readyIds: const {},
      sessionsByWorkBead: liveSessions,
      resolver: resolver,
    );
    final mounted = harness.workBeads().single;
    expect(resolver.events, ['start:tg-1']);

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: staleApproval,
    );
    harness.pushAndFlush(readyIds: const {}, sessionsByWorkBead: liveSessions);
    harness.pushAndFlush(readyIds: const {}, sessionsByWorkBead: liveSessions);
    await _settleAdmissions(harness);

    expect(harness.workBeads().single, same(mounted));
    expect(resolver.events, ['start:tg-1']);
    expect(transport.flares, hasLength(1));
    expect(transport.flares.single.name, 'work.mountEligibilityRefused');
    expect(transport.flares.single.data, {
      'beadId': 'tg-1',
      'clause': staleApproval,
    });
  });

  test(
    'cold live row mounts through refusing eligibility without writes',
    () async {
      const staleApproval = 'approval: stale - rerun the approve verb';
      final eligibility = _MutableEligibility()
        ..decision = const MountEligibilityDecision.refused(
          clause: staleApproval,
        );
      final transport = _RecordingTransport();
      final resolver = _LifecycleRecordingResolver();
      final harness = _mountHarness(
        mountEligibility: eligibility.call,
        transport: transport,
        readyIds: const {},
        sessionsByWorkBead: const {
          'tg-1': SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-live',
          ),
        },
        resolver: resolver,
      );
      await _settleAdmissions(harness);

      expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
      expect(resolver.events, ['start:tg-1']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.mountEligibilityRefused');
      expect(transport.flares.single.data, {
        'beadId': 'tg-1',
        'clause': staleApproval,
      });
      expect(harness.runner.calls, isEmpty);
    },
  );

  test('offline fallback keeps live row through refusing eligibility', () {
    final eligibility = _MutableEligibility()
      ..decision = const MountEligibilityDecision.refused(
        clause: 'approval: stale - rerun the approve verb',
      );
    final resolver = _LifecycleRecordingResolver();
    final harness = _mountHarness(
      mountEligibility: eligibility.call,
      readyIds: const {},
      sessionsByWorkBead: const {
        'tg-1': SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-live'),
      },
      resolver: resolver,
      includeStationServices: false,
    );

    expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
    expect(resolver.events, ['start:tg-1']);
    expect(harness.runner.calls, isEmpty);
  });

  test(
    'the authority evaluates the vended mount eligibility predicate without copying it',
    () async {
      final fakes = buildFakes();
      addTearDown(fakes.ctx.dispose);
      final bead = _task();
      final snapshot = _snapshot(bead, 0);
      const live = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-live',
      );
      final liveSnapshot = _snapshot(
        bead,
        1,
        sessionsByWorkBead: const {'tg-1': live},
      );
      var evaluations = 0;
      var invalidations = 0;
      var decision = const MountEligibilityDecision.refused(
        clause: 'vended-policy',
      );
      var throws = false;
      fakes.ctx.admission.addInvalidationListener(() => invalidations++);
      final services = ServiceBundle(
        mountEligibility: (evaluated) {
          evaluations++;
          expect(evaluated, same(bead));
          if (throws) throw StateError('vended-policy-failed');
          return decision;
        },
      );
      const config = SubstationConfig(
        substationId: 'test',
        ownedSubstations: {'tg'},
        maxConcurrentWork: 10,
      );
      final candidate = StationAdmissionCandidate(bead: bead, session: null);
      final batch = fakes.ctx.admission.admitPending(
        snapshot,
        config,
        services,
        [candidate],
      );

      expect(evaluations, 1);
      expect(batch.admitted, isEmpty);
      expect(batch.refused.single.detail, 'vended-policy');

      await Future<void>.delayed(Duration.zero);
      expect(invalidations, 1, reason: 'one bounded refusal recheck');
      await Future<void>.delayed(Duration.zero);
      expect(invalidations, 1, reason: 'a stable refusal cannot hot-loop');

      decision = const MountEligibilityDecision.eligible();
      final restored = fakes.ctx.admission.admitPending(
        liveSnapshot,
        config,
        services,
        [StationAdmissionCandidate(bead: bead, session: live)],
      );
      expect(evaluations, 2);
      expect(restored.admitted.single.adopted, isTrue);

      throws = true;
      final failed = fakes.ctx.admission.admitPending(
        liveSnapshot,
        config,
        services,
        [StationAdmissionCandidate(bead: bead, session: live)],
      );
      expect(evaluations, 3);
      expect(failed.admitted.single.adopted, isTrue);
      expect(failed.refused, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(invalidations, 2, reason: 'the throwing clause gets one recheck');
      await Future<void>.delayed(Duration.zero);
      expect(invalidations, 2);
      expect(fakes.runner.calls, isEmpty);
    },
  );

  test('refusal edges exclude work and carry bead id plus clause', () async {
    final eligibility = _MutableEligibility()
      ..decision = const MountEligibilityDecision.refused(
        clause: 'required-field',
      );
    final transport = _RecordingTransport();
    final harness = _mountHarness(
      mountEligibility: eligibility.call,
      transport: transport,
    );

    harness.pushAndFlush();
    expect(harness.workBeads(), isEmpty);
    expect(transport.flares, hasLength(1));
    expect(transport.flares.single.name, 'work.mountEligibilityRefused');
    expect(transport.flares.single.data, {
      'beadId': 'tg-1',
      'clause': 'required-field',
    });

    harness.pushAndFlush();
    expect(transport.flares, hasLength(1));

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: 'approval',
    );
    harness.pushAndFlush();
    expect(transport.flares, hasLength(2));
    expect(transport.flares.last.name, 'work.mountEligibilityRefused');
    expect(transport.flares.last.data['clause'], 'approval');

    eligibility.decision = const MountEligibilityDecision.eligible();
    harness.pushAndFlush();
    await _settleAdmissions(harness);
    expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
    expect(transport.flares.last.name, 'work.mountEligibilityRestored');
    expect(transport.flares.last.data, {
      'beadId': 'tg-1',
      'clause': 'approval',
    });

    eligibility.decision = const MountEligibilityDecision.refused(
      clause: 'required-field',
    );
    harness.pushAndFlush();
    expect(transport.flares.last.name, 'work.mountEligibilityRefused');
    expect(transport.flares, hasLength(4));
  });

  test(
    'eligibility retry does not re-resolve unchanged mounted neighbors',
    () async {
      const neighbor = Bead(
        id: 'tg-2',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      final resolver = _RecordingResolver();
      final transport = _RecordingTransport();
      var pendingEvaluations = 0;
      var neighborEvaluations = 0;
      var pendingEligible = false;
      final harness = _mountHarness(
        mountEligibility: (bead) {
          if (bead.id == 'tg-2') {
            neighborEvaluations += 1;
            return const MountEligibilityDecision.eligible();
          }
          pendingEvaluations += 1;
          return pendingEligible
              ? const MountEligibilityDecision.eligible()
              : const MountEligibilityDecision.refused(
                  clause: 'fresh mount-eligibility read pending',
                );
        },
        transport: transport,
        readyIds: const {'tg-1', 'tg-2'},
        additionalBeads: const [neighbor],
        resolver: resolver,
      );

      await _settleAdmissions(harness);
      expect(harness.workBeads().map((work) => work.bead.id), ['tg-2']);
      expect(resolver.calls, ['tg-2']);
      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'work.mountEligibilityRefused');
      expect(transport.flares.single.data, {
        'beadId': 'tg-1',
        'clause': 'fresh mount-eligibility read pending',
      });

      pendingEligible = true;
      harness.joined.push(
        _snapshot(
          harness.bead,
          99,
          readyIds: const {'tg-1', 'tg-2'},
          additionalBeads: const [neighbor],
        ),
      );
      harness.owner.flush();
      await _settleAdmissions(harness);

      expect(pendingEvaluations, greaterThanOrEqualTo(2));
      expect(neighborEvaluations, greaterThanOrEqualTo(2));
      expect(harness.workBeads().map((work) => work.bead.id), ['tg-2', 'tg-1']);
      expect(
        resolver.calls,
        ['tg-2', 'tg-1'],
        reason: 'the unchanged mounted neighbor must retain seed identity',
      );
      expect(transport.flares, hasLength(2));
      expect(transport.flares.last.name, 'work.mountEligibilityRestored');
      expect(transport.flares.last.data, {
        'beadId': 'tg-1',
        'clause': 'fresh mount-eligibility read pending',
      });

      final pendingBefore = pendingEvaluations;
      final neighborBefore = neighborEvaluations;
      await Future<void>.delayed(Duration.zero);
      harness.owner.flush();
      expect(pendingEvaluations, pendingBefore);
      expect(neighborEvaluations, neighborBefore);
      expect(resolver.calls, ['tg-2', 'tg-1']);
      expect(transport.flares, hasLength(2));
    },
  );

  test('a persistent refusal receives only one automatic recheck', () async {
    final eligibility = _MutableEligibility()
      ..decision = const MountEligibilityDecision.refused(
        clause: 'approval: not approved',
      );
    final transport = _RecordingTransport();
    final harness = _mountHarness(
      mountEligibility: eligibility.call,
      transport: transport,
    );

    expect(eligibility.evaluations, 1);
    await Future<void>.delayed(Duration.zero);
    harness.owner.flush();
    expect(eligibility.evaluations, 2);

    await Future<void>.delayed(Duration.zero);
    harness.owner.flush();
    expect(eligibility.evaluations, 2);
    expect(transport.flares, hasLength(1));
  });

  test('a throwing predicate names the failure and does not abort the next '
      'candidate', () async {
    final transport = _RecordingTransport();
    final first = _task();
    const second = Bead(
      id: 'tg-2',
      issueType: IssueType.task,
      status: BeadStatus.open,
    );
    final joined = JoinedSnapshotNotifier(
      JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [first, second],
          dependencies: const [],
          readyIds: const {'tg-1', 'tg-2'},
          capturedAt: DateTime(2026),
        ),
      ),
    );
    final owner = TreeOwner();
    final fakes = buildFakes(maxConcurrentWork: 10);
    final stationServices = fakes.ctx;
    addTearDown(() {
      owner.dispose();
      stationServices.dispose();
    });
    final root = owner.mountRoot(
      ProviderScope(
        child: InheritedSeed<StationServices>(
          value: stationServices,
          child: InheritedSeed<JoinedSnapshotNotifier>(
            value: joined,
            child: InheritedSeed<SessionResolver>(
              value: _RecordingResolver(),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(
                    const SubstationConfig(
                      substationId: 'test',
                      ownedSubstations: {'tg'},
                      maxConcurrentWork: 10,
                    ),
                  ),
                  services: ServiceBundle(
                    transport: transport,
                    mountEligibility: (bead) {
                      if (bead.id == 'tg-1') {
                        throw StateError('asset unavailable');
                      }
                      return const MountEligibilityDecision.eligible();
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    await _settleAdmissions(
      _Harness(
        owner: owner,
        root: root,
        joined: joined,
        bead: first,
        runner: fakes.runner,
      ),
    );

    expect(_workBeads(root).map((work) => work.bead.id), ['tg-2']);
    expect(transport.flares.single.name, 'work.mountEligibilityRefused');
    expect(transport.flares.single.data['beadId'], 'tg-1');
    expect(
      transport.flares.single.data['clause'],
      'mount eligibility evaluation failed: Bad state: asset unavailable',
    );
  });

  test('frontier exclusion uses existing refusal edges and preserves live '
      'sessions', () async {
    const clause =
        'frontier cross-link: link bead tranquility-awgj18 blocks tg-1 '
        'on open target "genesis-7ob"';

    final transport = _RecordingTransport();
    final fresh = _mountHarness(
      readyIds: const {},
      frontierExclusionsByBeadId: const {'tg-1': clause},
      transport: transport,
    );
    expect(fresh.workBeads(), isEmpty);
    expect(transport.flares.single.name, 'work.mountEligibilityRefused');
    expect(transport.flares.single.data, {'beadId': 'tg-1', 'clause': clause});

    fresh.pushAndFlush(
      readyIds: const {},
      frontierExclusionsByBeadId: const {'tg-1': clause},
    );
    expect(transport.flares, hasLength(1));

    fresh.pushAndFlush(
      readyIds: const {},
      frontierExclusionsByBeadId: const {
        'tg-1':
            'frontier cross-link: link bead tranquility-new blocks tg-1 '
            'on unobserved target "genesis-new" (fail-closed)',
      },
    );
    expect(transport.flares, hasLength(2));
    expect(transport.flares.last.name, 'work.mountEligibilityRefused');

    fresh.pushAndFlush();
    await _settleAdmissions(fresh);
    expect(fresh.workBeads().map((work) => work.bead.id), ['tg-1']);
    expect(transport.flares.last.name, 'work.mountEligibilityRestored');

    final liveTransport = _RecordingTransport();
    final live = _mountHarness(
      readyIds: const {},
      frontierExclusionsByBeadId: const {'tg-1': clause},
      sessionsByWorkBead: const {
        'tg-1': SessionProjection(
          workBeadId: 'tg-1',
          sessionId: 'tgdog-live',
          isTerminal: false,
        ),
      },
      transport: liveTransport,
    );
    expect(live.workBeads().map((work) => work.bead.id), ['tg-1']);
    expect(liveTransport.flares, isEmpty);
  });

  test(
    'sameStoreDependencyExclusionClause follows bd ready same-store semantics',
    () {
      const source = Bead(
        id: 'tg-1',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      const lowBlocker = Bead(
        id: 'tg-a',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      const highBlocker = Bead(
        id: 'tg-z',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      const closedBlocker = Bead(
        id: 'tg-closed',
        issueType: IssueType.task,
        status: BeadStatus.closed,
      );
      const foreignBlocker = Bead(
        id: 'pow-1',
        issueType: IssueType.task,
        status: BeadStatus.open,
      );
      final ownership = BeadOwnershipPredicate(const {'tg'});

      GraphSnapshot graph(
        List<BeadDependency> dependencies, {
        Set<String> readyIds = const {},
      }) => GraphSnapshot.fromParts(
        beads: const [
          source,
          lowBlocker,
          highBlocker,
          closedBlocker,
          foreignBlocker,
        ],
        dependencies: dependencies,
        readyIds: readyIds,
        capturedAt: DateTime(2026),
      );

      MountEligibilityDecision evaluate(
        List<BeadDependency> dependencies, {
        Set<String> readyIds = const {},
        Map<String, SessionProjection> sessions = const {},
      }) => sameStoreDependencyExclusionClause(
        graph(dependencies, readyIds: readyIds),
        ownership,
        sessions,
      )(source);

      expect(
        evaluate(const [BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-z')]),
        const MountEligibilityDecision.refused(
          clause:
              'frontier dependency: bead tg-1 is blocked by open dependency '
              '"tg-z"',
        ),
      );
      expect(
        evaluate(const [
          BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-closed'),
        ]),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(const [
          BeadDependency(
            issueId: 'tg-1',
            dependsOnId: 'tg-a',
            type: DependencyType.related,
          ),
        ]),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(
          const [BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-a')],
          readyIds: const {'tg-1'},
        ),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(const [BeadDependency(issueId: 'tg-1', dependsOnId: 'pow-1')]),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(const [
          BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-z'),
          BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-a'),
          BeadDependency(
            issueId: 'tg-1',
            dependsOnId: 'tg-a',
            type: DependencyType.waitsFor,
          ),
        ]),
        const MountEligibilityDecision.refused(
          clause:
              'frontier dependency: bead tg-1 is blocked by open dependency '
              '"tg-a"',
        ),
      );
      expect(
        evaluate(
          const [BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-a')],
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-live',
            ),
          },
        ),
        const MountEligibilityDecision.eligible(),
      );
      expect(
        evaluate(
          const [BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-a')],
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-terminal',
              isTerminal: true,
            ),
          },
        ),
        const MountEligibilityDecision.refused(
          clause:
              'frontier dependency: bead tg-1 is blocked by open dependency '
              '"tg-a"',
        ),
      );
    },
  );

  test('null predicate preserves mounting', () async {
    final harness = _mountHarness(mountEligibility: null);
    await _settleAdmissions(harness);
    expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
  });

  test('null and throwing transports do not break eligibility edges', () async {
    for (final transport in <ExplorationTransport?>[
      null,
      _ThrowingTransport(),
    ]) {
      final eligibility = _MutableEligibility()
        ..decision = const MountEligibilityDecision.refused(
          clause: 'required-field',
        );
      final harness = _mountHarness(
        mountEligibility: eligibility.call,
        transport: transport,
      );
      expect(harness.pushAndFlush, returnsNormally);
      expect(harness.workBeads(), isEmpty);
      eligibility.decision = const MountEligibilityDecision.eligible();
      expect(harness.pushAndFlush, returnsNormally);
      await _settleAdmissions(harness);
      expect(harness.workBeads().map((work) => work.bead.id), ['tg-1']);
    }
  });

  test('the public seam is exported and the join bridge stays ignorant', () {
    final barrel = File('lib/grid_engine.dart').readAsStringSync();
    final bridge = File(
      'lib/src/bridge/station_join_bridge.dart',
    ).readAsStringSync();
    expect(barrel, contains("export 'src/domain/mount_eligibility.dart';"));
    expect(bridge, isNot(contains('MountEligibility')));
    expect(bridge, isNot(contains('mountEligibility')));
  });

  test(
    'the new engine surface contains no assets convention or competing name',
    () {
      final sources = [
        File('lib/src/domain/mount_eligibility.dart').readAsStringSync(),
        File('lib/src/seeds/work_list.dart').readAsStringSync(),
        File('lib/src/sdk/capability.dart').readAsStringSync(),
      ].join('\n');
      expect(sources, isNot(contains('validation_plan')));
      expect(sources, isNot(contains('package:grid_assets')));
      expect(
        File('lib/src/domain/mount_eligibility.dart').readAsStringSync(),
        isNot(contains('DriveabilityPredicate')),
      );
    },
  );
}
