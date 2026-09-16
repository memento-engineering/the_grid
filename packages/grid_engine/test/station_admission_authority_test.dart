import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

final class _FailingMountAttemptRunner extends RecordingBdRunner {
  var failNextAttemptUpdate = true;
  var writesStarted = 0;

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (failNextAttemptUpdate &&
        args.isNotEmpty &&
        args.first == 'update' &&
        args.any((arg) => arg.contains(MountAttemptKeys.count))) {
      writesStarted += 1;
      failNextAttemptUpdate = false;
      throw StateError('controlled mount-attempt failure');
    }
    if (args.isNotEmpty &&
        args.first == 'update' &&
        args.any((arg) => arg.contains(MountAttemptKeys.count))) {
      writesStarted += 1;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _GatedMountAttemptRunner extends RecordingBdRunner {
  final entered = Completer<void>();
  final release = Completer<void>();
  var writesStarted = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final type = args.indexOf('--type');
    if (args.isNotEmpty &&
        args.first == 'create' &&
        type >= 0 &&
        type + 1 < args.length &&
        args[type + 1] == GridIssueTypes.mountAttempt.wire) {
      writesStarted += 1;
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _GatedFailingSessionCreateRunner extends RecordingBdRunner {
  _GatedFailingSessionCreateRunner({
    required this.expectedCreates,
    super.createdId,
    this.failAfterRelease = true,
  });

  final int expectedCreates;
  final bool failAfterRelease;
  final allCreatesEntered = Completer<void>();
  final releaseCreates = Completer<void>();
  var sessionCreates = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final type = args.indexOf('--type');
    final isSessionCreate =
        args.isNotEmpty &&
        args.first == 'create' &&
        type >= 0 &&
        type + 1 < args.length &&
        args[type + 1] == GridIssueTypes.session.wire;
    if (!isSessionCreate) {
      return super.run(args, timeout: timeout, stdin: stdin);
    }
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    sessionCreates += 1;
    if (sessionCreates == expectedCreates && !allCreatesEntered.isCompleted) {
      allCreatesEntered.complete();
    }
    await releaseCreates.future;
    if (failAfterRelease) {
      throw StateError('controlled session-create failure');
    }
    return result;
  }
}

final class _UnusedTrust implements Trust {
  @override
  Future<TrustLevel> levelOf(ActorIdentity actor) =>
      throw StateError('trust resolution must stay off the mount path');
}

final class _GatedCloseRunner extends RecordingBdRunner {
  _GatedCloseRunner({super.createdId, super.eventLog});

  final error = const BdTimeoutException(
    command: ['bd', 'create', '--graph', 'plan.json'],
    timeout: BdCliService.pourTimeout,
  );
  final closeEntered = Completer<void>();
  final releaseClose = Completer<void>();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.length > 1 && args[0] == 'create' && args[1] == '--graph') {
      await super.run(args, timeout: timeout, stdin: stdin);
      throw error;
    }
    if (args.isNotEmpty && args.first == 'close') {
      if (!closeEntered.isCompleted) closeEntered.complete();
      await releaseClose.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _FailingCloseRunner extends RecordingBdRunner {
  _FailingCloseRunner({super.createdId});

  final error = const BdTimeoutException(
    command: ['bd', 'create', '--graph', 'plan.json'],
    timeout: BdCliService.pourTimeout,
  );

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.length > 1 && args[0] == 'create' && args[1] == '--graph') {
      await super.run(args, timeout: timeout, stdin: stdin);
      throw error;
    }
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (args.isNotEmpty && args.first == 'close') {
      throw StateError('controlled close failure');
    }
    return result;
  }
}

final class _GatedTerminalSettlementRunner extends RecordingBdRunner {
  final updateEntered = Completer<void>();
  final releaseUpdate = Completer<void>();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.length > 1 &&
        args.first == 'update' &&
        args[1] == 'tg-terminal-session') {
      if (!updateEntered.isCompleted) updateEntered.complete();
      await releaseUpdate.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _GraphErrorRunner extends RecordingBdRunner {
  _GraphErrorRunner(this.error, {super.createdId});

  final Object error;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (args.length > 1 && args[0] == 'create' && args[1] == '--graph') {
      throw error;
    }
    return result;
  }
}

final class _FailFirstVoidUpdateRunner extends RecordingBdRunner {
  _FailFirstVoidUpdateRunner({this.error});

  final Object? error;
  var _failed = false;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (!_failed &&
        args.isNotEmpty &&
        args.first == 'update' &&
        args.any((arg) => arg.startsWith('${SessionBeadKeys.workBead}='))) {
      _failed = true;
      throw error ?? StateError('controlled surplus update failure');
    }
    return result;
  }
}

final class _GatedStopProvider extends FakeRuntimeProvider {
  final stopEntered = Completer<void>();
  final releaseStop = Completer<void>();
  var listRunningCalls = 0;

  @override
  List<String> listRunning(String prefix) {
    listRunningCalls += 1;
    return super.listRunning(prefix);
  }

  @override
  Future<void> stop(String name) async {
    if (!stopEntered.isCompleted) stopEntered.complete();
    await releaseStop.future;
    await super.stop(name);
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: data));
  }
}

Bead _bead(String id, {int priority = 2}) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  priority: priority,
);

Bead _ownedSession(String id) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: const {
    'rig': 'tg',
    SessionBeadKeys.workBead: 'tg-1',
    SessionBeadKeys.model: kSessionModelMolecule,
  },
);

JoinedSnapshot _snapshot(
  List<Bead> beads, {
  Map<String, SessionProjection> sessions = const {},
  Map<String, List<SessionProjection>> surplus = const {},
  DateTime? stateCapturedAt,
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: {for (final bead in beads) bead.id},
    capturedAt: DateTime.utc(2026, 9, 4),
  ),
  stateCapturedAt: stateCapturedAt,
  sessionsByWorkBead: sessions,
  surplusSessionsByWorkBead: surplus,
);

const _config = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
  maxConcurrentWork: 2,
);

const _moleculePlan = GraphApplyPlan(
  commitMessage: 'test molecule',
  nodes: [GraphNode(key: 'root', title: 'root', type: 'molecule')],
);

StationServices _stationOver(
  RecordingBdRunner runner, {
  BeadProbeReader? reader,
  FakeRuntimeProvider? provider,
  AllocationLiveness? liveness,
  int maxConcurrentWork = 2,
}) {
  final runtime = provider ?? FakeRuntimeProvider();
  return StationServices(
    provider: runtime,
    writer: StationBeadWriter(
      bd: BdCliService(runner),
      reader: reader ?? runner,
      ownership: BeadOwnershipPredicate(const {'tg'}),
    ),
    stateSubstation: 'tg',
    liveness: liveness,
    maxConcurrentWork: maxConcurrentWork,
  );
}

Future<
  ({
    JoinedSnapshot snapshot,
    StationAdmissionCandidate candidate,
    String sessionId,
  })
>
_reserveAndCreate(StationServices station, String beadId) async {
  final work = _bead(beadId);
  final candidate = StationAdmissionCandidate(bead: work, session: null);
  final snapshot = _snapshot([work]);
  station.admission.admitPending(snapshot, _config, const ServiceBundle(), [
    candidate,
  ]);
  final created = await station.admission.createSessionAttempt(
    snapshot,
    candidate,
    title: 'grid session $beadId',
    metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
  );
  return (
    snapshot: snapshot,
    candidate: candidate,
    sessionId: created.sessionId!,
  );
}

Future<void> _pump() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  test(
    'lost-session retirement shares one exact future and stops every runtime '
    'before the incumbent void path',
    () async {
      final runner = RecordingBdRunner();
      final provider = _GatedStopProvider();
      addTearDown(() {
        if (!provider.releaseStop.isCompleted) provider.releaseStop.complete();
      });
      addTearDown(provider.close);
      await provider.start(
        'tg-lost/tg-work/agent',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      await provider.start(
        'tg-lost/tg-work/verify',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      final station = _stationOver(runner, provider: provider);
      addTearDown(station.dispose);

      final first = station.admission.retireLostSession(
        workBeadId: 'tg-work',
        sessionId: 'tg-lost',
        attemptId: 'attempt-1',
        services: const ServiceBundle(),
      );
      await provider.stopEntered.future;
      final same = station.admission.retireLostSession(
        workBeadId: 'tg-work',
        sessionId: 'tg-lost',
        attemptId: 'attempt-1',
        services: const ServiceBundle(),
      );

      expect(identical(first, same), isTrue);
      expect(
        () => station.admission.retireLostSession(
          workBeadId: 'tg-work',
          sessionId: 'tg-lost',
          attemptId: 'attempt-2',
          services: const ServiceBundle(),
        ),
        throwsStateError,
      );
      expect(provider.listRunningCalls, 1);
      expect(
        runner.calls,
        isEmpty,
        reason: 'all runtime stops precede voiding',
      );

      provider.releaseStop.complete();
      expect(await first, 'tg-lost');
      expect(await same, 'tg-lost');
      expect(provider.stopped, [
        'tg-lost/tg-work/agent',
        'tg-lost/tg-work/verify',
      ]);
      final update = runner
          .callsFor('update')
          .singleWhere(
            (call) => call.contains(
              '${SessionBeadKeys.voidedReason}=attempt-liveness-lost',
            ),
          );
      expect(
        update,
        contains('${SessionBeadKeys.voidedReason}=attempt-liveness-lost'),
      );
      expect(
        update,
        contains('${SessionBeadKeys.workBead}=tg-work#void-tg-lost'),
      );
      expect(runner.callsFor('close'), hasLength(1));
    },
  );

  test('lost-session close holds capacity and releases it before retry '
      'invalidation', () async {
    final runner = _GatedCloseRunner(createdId: 'tg-lost');
    final provider = FakeRuntimeProvider();
    addTearDown(() {
      if (!runner.releaseClose.isCompleted) runner.releaseClose.complete();
    });
    addTearDown(provider.close);
    final station = _stationOver(
      runner,
      provider: provider,
      maxConcurrentWork: 1,
    );
    addTearDown(station.dispose);
    final owned = await _reserveAndCreate(station, 'tg-work');
    var invalidations = 0;
    station.admission.addInvalidationListener(() => invalidations += 1);
    final beforeRetirement = invalidations;

    final retirement = station.admission.retireLostSession(
      workBeadId: 'tg-work',
      sessionId: owned.sessionId,
      attemptId: 'attempt-1',
      services: const ServiceBundle(),
    );
    await runner.closeEntered.future;
    expect(
      station.admission.admissionStatus.reservations.single.sessionId,
      owned.sessionId,
    );
    final rival = _bead('tg-rival');
    final held = station.admission.admitPending(
      _snapshot([owned.candidate.bead, rival]),
      _config.copyWith(maxConcurrentWork: 1),
      const ServiceBundle(),
      [owned.candidate, StationAdmissionCandidate(bead: rival, session: null)],
    );
    expect(held.waiting.single.bead.id, 'tg-rival');
    expect(invalidations, beforeRetirement);

    runner.releaseClose.complete();
    await retirement;
    expect(station.admission.admissionStatus.reservations, isEmpty);
    expect(invalidations, greaterThan(beforeRetirement));
    final admitted = station.admission.admitPending(
      _snapshot([rival]),
      _config.copyWith(maxConcurrentWork: 1),
      const ServiceBundle(),
      [StationAdmissionCandidate(bead: rival, session: null)],
    );
    expect(admitted.admitted.single.candidate.bead.id, 'tg-rival');
  });

  test(
    'a failed lost-session void removes the in-flight identity for retry',
    () async {
      final runner = _FailFirstVoidUpdateRunner();
      final provider = _GatedStopProvider();
      addTearDown(() {
        if (!provider.releaseStop.isCompleted) provider.releaseStop.complete();
      });
      addTearDown(provider.close);
      await provider.start(
        'tg-lost/tg-work/agent',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      final station = _stationOver(runner, provider: provider);
      addTearDown(station.dispose);

      final failed = station.admission.retireLostSession(
        workBeadId: 'tg-work',
        sessionId: 'tg-lost',
        attemptId: 'attempt-1',
        services: const ServiceBundle(),
      );
      await provider.stopEntered.future;
      provider.releaseStop.complete();
      await expectLater(failed, throwsStateError);

      final retried = station.admission.retireLostSession(
        workBeadId: 'tg-work',
        sessionId: 'tg-lost',
        attemptId: 'attempt-1',
        services: const ServiceBundle(),
      );
      expect(identical(failed, retried), isFalse);
      expect(await retried, 'tg-lost');
      expect(provider.listRunningCalls, 2);
      expect(runner.callsFor('close'), hasLength(1));
    },
  );

  test('trajectory loss invalidates admission, preserves live work, and routes '
      'step and terminal gates through their distinct seams', () async {
    final runner = RecordingBdRunner(createdId: 'tg-gate');
    runner.exportBeads = const [
      Bead(
        id: 'tg-live',
        issueType: GridIssueTypes.session,
        status: BeadStatus.open,
        metadata: {'rig': 'tg'},
      ),
    ];
    final writer = StationBeadWriter(
      bd: BdCliService(runner),
      reader: runner,
      ownership: BeadOwnershipPredicate(const {'tg'}),
    );
    final halt = TrajectoryAdmissionHalt(
      writer: writer,
      stateSubstation: 'tg',
      bootEpoch: () => 42,
    );
    final station = StationServices(
      provider: FakeRuntimeProvider(),
      writer: writer,
      stateSubstation: 'tg',
      trajectoryAdmissionHalt: halt,
    );
    addTearDown(station.dispose);
    var invalidations = 0;
    station.admission.addInvalidationListener(() => invalidations += 1);

    final stepGate = halt.handleStepResult(
      const TrajectoryAppendResult.dropped(),
      sessionId: 'tg-live',
      nodePath: 'tg-1/build',
      recordClass: 'step.transition',
    );
    expect(halt.halted, isTrue, reason: 'the latch precedes gate I/O');
    expect(invalidations, 1, reason: 'admission invalidates synchronously');
    await stepGate;
    expect(halt.reason, 'trajectory append dropped');
    expect(halt.recordClass, 'step.transition');

    const live = SessionProjection(workBeadId: 'tg-1', sessionId: 'tg-live');
    final liveBead = _bead('tg-1');
    final freshBead = _bead('tg-2');
    final snapshot = _snapshot(
      [liveBead, freshBead],
      sessions: const {'tg-1': live},
    );
    final batch = station.admission
        .admitPending(snapshot, _config, const ServiceBundle(), [
          StationAdmissionCandidate(bead: liveBead, session: live),
          StationAdmissionCandidate(bead: freshBead, session: null),
        ]);
    expect(batch.admitted.single.candidate.bead.id, 'tg-1');
    expect(batch.refused.single.candidate.bead.id, 'tg-2');
    expect(batch.refused.single.clause, 'trajectory admission halted');

    await halt.handleTerminalResult(
      const TrajectoryAppendResult.suppressed(),
      recordClass: 'attempt.terminal',
    );
    expect(halt.reason, 'trajectory append dropped', reason: 'first loss wins');
    expect(halt.recordClass, 'step.transition');
    expect(runner.workUpdates, hasLength(2));
    expect(runner.metadataOfUpdate(0), containsPair('blocks', 'tg-live'));
    expect(runner.metadataOfUpdate(0), containsPair('node', 'tg-1/build'));
    expect(runner.metadataOfUpdate(1), containsPair('blocks', 'tg/42'));
    expect(runner.metadataOfUpdate(1), isNot(containsPair('node', anything)));
  });

  test('value fields are exact and batch collections are immutable', () {
    final candidate = StationAdmissionCandidate(
      bead: _bead('tg-1'),
      session: null,
    );
    final reservation = StationAdmissionReservation(
      candidate: candidate,
      substationId: 'tg',
      mountAttempt: 1,
      sessionId: null,
      adopted: false,
      reservationToken: null,
    );
    final refusal = StationAdmissionRefusal(
      candidate: candidate,
      clause: 'approval',
      detail: 'not approved',
    );
    final admitted = [reservation];
    final waiting = [candidate];
    final refused = [refusal];
    final batch = StationAdmissionBatch(
      admitted: admitted,
      waiting: waiting,
      refused: refused,
    );

    admitted.clear();
    waiting.clear();
    refused.clear();
    expect(batch.admitted.single.mountAttempt, 1);
    expect(batch.waiting.single.bead.id, 'tg-1');
    expect(batch.refused.single.detail, 'not approved');
    expect(() => batch.admitted.add(reservation), throwsUnsupportedError);
    expect(() => batch.waiting.clear(), throwsUnsupportedError);
    expect(() => batch.refused.clear(), throwsUnsupportedError);

    final cause = TimeoutException('controlled timeout');
    final voided = StationMintVoided(
      workBeadId: 'tg-1',
      retiredSessionId: 'tgdog-s1',
      cause: cause,
    );
    expect(voided.workBeadId, 'tg-1');
    expect(voided.retiredSessionId, 'tgdog-s1');
    expect(voided.cause, same(cause));
  });

  test(
    'snapshot-derived reports and obligations are level-triggered per pass',
    () async {
      final trustRunner = RecordingBdRunner();
      final trustStation = _stationOver(trustRunner);
      addTearDown(trustStation.dispose);
      final trustTransport = _RecordingTransport();
      final trustServices = ServiceBundle(
        trust: _UnusedTrust(),
        trustFloor: const TrustFloor(TrustLevel.trusted),
        transport: trustTransport,
      );
      final untrusted = _bead('tg-trust').copyWith(
        metadata: const {
          OriginTrustKeys.scheme: 'github',
          OriginTrustKeys.actor: 'octocat',
          OriginTrustKeys.level: 'external',
        },
      );
      final trustSnapshot = _snapshot([untrusted]);
      final trustCandidate = StationAdmissionCandidate(
        bead: untrusted,
        session: null,
      );
      for (var pass = 0; pass < 2; pass += 1) {
        expect(
          trustStation.admission
              .admitPending(trustSnapshot, _config, trustServices, [
                trustCandidate,
              ])
              .refused
              .single
              .clause,
          'trust',
        );
      }
      expect(
        trustTransport.flares.where(
          (flare) => flare.name == 'work.trustRefused',
        ),
        hasLength(2),
      );

      final fenceRunner = RecordingBdRunner();
      final fenceStation = _stationOver(fenceRunner, liveness: (_) => true);
      addTearDown(fenceStation.dispose);
      final fenceTransport = _RecordingTransport();
      final fenceServices = ServiceBundle(transport: fenceTransport);
      final duplicateWork = _bead('tg-duplicate');
      const winner = SessionProjection(
        workBeadId: 'tg-duplicate',
        sessionId: 'tg-winner',
      );
      const rival = SessionProjection(
        workBeadId: 'tg-duplicate',
        sessionId: 'tg-rival',
        pid: 42,
        pgid: 41,
      );
      final duplicateSnapshot = _snapshot(
        [duplicateWork],
        sessions: const {'tg-duplicate': winner},
        surplus: const {
          'tg-duplicate': [rival],
        },
      );
      final duplicateCandidate = StationAdmissionCandidate(
        bead: duplicateWork,
        session: winner,
      );
      for (var pass = 0; pass < 2; pass += 1) {
        expect(
          fenceStation.admission
              .admitPending(duplicateSnapshot, _config, fenceServices, [
                duplicateCandidate,
              ])
              .refused
              .single
              .clause,
          'duplicate-live',
        );
      }
      expect(
        fenceTransport.flares.where(
          (flare) => flare.name == 'work.duplicateLiveRefused',
        ),
        hasLength(2),
      );

      final voidedWork = _bead('tg-voided');
      const voided = SessionProjection(
        workBeadId: 'tg-voided',
        sessionId: 'tg-voided-session',
        isTerminal: true,
        pid: 52,
        pgid: 51,
      );
      final voidedSnapshot = _snapshot(
        [voidedWork],
        sessions: const {'tg-voided': voided},
      );
      final voidedCandidate = StationAdmissionCandidate(
        bead: voidedWork,
        session: voided,
      );
      for (var pass = 0; pass < 2; pass += 1) {
        expect(
          fenceStation.admission
              .admitPending(voidedSnapshot, _config, fenceServices, [
                voidedCandidate,
              ])
              .refused
              .single
              .clause,
          'live-fence',
        );
      }
      expect(
        fenceTransport.flares.where(
          (flare) => flare.name == 'session.voidRefused',
        ),
        hasLength(2),
      );

      final throttleRunner = RecordingBdRunner();
      final throttleStation = _stationOver(
        throttleRunner,
        maxConcurrentWork: 1,
      );
      addTearDown(throttleStation.dispose);
      final throttleTransport = _RecordingTransport();
      final throttleServices = ServiceBundle(transport: throttleTransport);
      final first = _bead('tg-first', priority: 0);
      final waiting = _bead('tg-waiting', priority: 1);
      final throttleSnapshot = _snapshot([first, waiting]);
      final throttleCandidates = [
        StationAdmissionCandidate(bead: first, session: null),
        StationAdmissionCandidate(bead: waiting, session: null),
      ];
      for (var pass = 0; pass < 2; pass += 1) {
        final batch = throttleStation.admission.admitPending(
          throttleSnapshot,
          _config.copyWith(maxConcurrentWork: 1),
          throttleServices,
          throttleCandidates,
        );
        expect(batch.waiting.single.bead.id, waiting.id);
      }
      final throttled = throttleTransport.flares.where(
        (flare) => flare.name == 'work.throttled',
      );
      expect(throttled, hasLength(2));
      expect(
        throttled.every(
          (flare) =>
              flare.data['count'] == '1' &&
              flare.data['beadIds'] == 'tg-waiting',
        ),
        isTrue,
      );

      final surplusRunner = RecordingBdRunner();
      final surplusStation = _stationOver(surplusRunner);
      addTearDown(surplusStation.dispose);
      const terminalSurplus = SessionProjection(
        workBeadId: 'tg-surplus',
        sessionId: 'tg-surplus-session',
        isTerminal: true,
      );
      for (var request = 0; request < 2; request += 1) {
        await surplusStation.admission.retireSurplusSessions(
          workBeadId: 'tg-surplus',
          keptSessionId: 'tg-kept',
          surplus: const [terminalSurplus],
          services: const ServiceBundle(),
        );
      }
      expect(
        surplusRunner
            .callsFor('update')
            .where(
              (call) => call.length > 1 && call[1] == 'tg-surplus-session',
            ),
        hasLength(2),
      );

      final gateRunner = RecordingBdRunner();
      gateRunner.exportBeads = const [
        Bead(
          id: 'tg-terminal-session',
          issueType: GridIssueTypes.session,
          status: BeadStatus.closed,
          metadata: {'rig': 'tg'},
        ),
      ];
      final gateStation = _stationOver(gateRunner);
      addTearDown(gateStation.dispose);
      for (var request = 0; request < 2; request += 1) {
        await gateStation.admission.closeTerminalGates(
          sessionId: 'tg-terminal-session',
          cause: GateCloseCause.sessionTerminal,
          disposition: GateSweepSessionDisposition.done,
          services: const ServiceBundle(),
        );
      }
      expect(gateRunner.openBeadsCallCount, 2);
    },
  );

  test(
    'surplus retirement preserves the adopt verdict decision gate',
    () async {
      final runner = RecordingBdRunner();
      final station = _stationOver(runner);
      addTearDown(station.dispose);
      const winner = SessionProjection(
        workBeadId: 'tg-surplus',
        sessionId: 'tg-winner',
      );
      const terminal = SessionProjection(
        workBeadId: 'tg-surplus',
        sessionId: 'tg-terminal',
        isTerminal: true,
      );

      await station.admission.retireSurplusSessions(
        workBeadId: 'tg-surplus',
        keptSessionId: 'tg-winner',
        surplus: const [winner, terminal],
        services: const ServiceBundle(),
      );

      expect(
        runner.callsFor('update'),
        isEmpty,
        reason: 'an adopt verdict leaves terminal-row retirement to its owner',
      );
    },
  );

  test(
    'terminal settlement releases an unsessioned reservation after the writer succeeds',
    () async {
      final runner = _GatedTerminalSettlementRunner();
      addTearDown(() {
        if (!runner.releaseUpdate.isCompleted) runner.releaseUpdate.complete();
      });
      const sessionId = 'tg-terminal-session';
      final work = _bead('tg-terminal-work');
      runner.exportBeads = const [
        Bead(
          id: sessionId,
          issueType: GridIssueTypes.session,
          status: BeadStatus.open,
          metadata: {'rig': 'tg', SessionBeadKeys.workBead: 'tg-terminal-work'},
        ),
      ];
      final station = _stationOver(runner, maxConcurrentWork: 1);
      addTearDown(station.dispose);
      final snapshot = _snapshot([work]);
      final reservation = station.admission
          .admitPending(
            snapshot,
            _config.copyWith(maxConcurrentWork: 1),
            const ServiceBundle(),
            [StationAdmissionCandidate(bead: work, session: null)],
          )
          .admitted
          .single;
      expect(reservation.sessionId, isNull);

      final settlement = station.admission.settleWorkTerminalSession(
        terminalWorkBead: work.copyWith(status: BeadStatus.closed),
        sessionId: sessionId,
        services: const ServiceBundle(),
      );
      await runner.updateEntered.future;
      expect(
        station.admission.admissionStatus.reservations.single.bead,
        work.id,
      );

      runner.releaseUpdate.complete();
      await settlement;
      expect(station.admission.admissionStatus.reservations, isEmpty);
      expect(runner.callsFor('close'), hasLength(1));
    },
  );

  test(
    'admission status is ordered, sanitized, immutable, and retains since',
    () async {
      final runner = RecordingBdRunner(createdId: 'tg-session');
      final provider = FakeRuntimeProvider();
      var now = DateTime(2026, 9, 7, 10);
      final authority = StationAdmissionAuthority(
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {'tg'}),
        ),
        provider: provider,
        stateSubstation: 'tg',
        maxConcurrentWork: 4,
        clock: () => now,
      );
      addTearDown(authority.dispose);
      const bodySentinel = 'SECRET BODY PROSE MUST NOT CROSS STATUS';
      final beads = [
        _bead('tg-z', priority: 0).copyWith(description: bodySentinel),
        _bead('tg-y', priority: 1),
        _bead('tg-b', priority: 2).copyWith(title: bodySentinel),
        _bead('tg-a', priority: 3),
      ];
      final candidates = [
        for (final bead in beads)
          StationAdmissionCandidate(bead: bead, session: null),
      ];
      final snapshot = _snapshot(beads);
      final clauses = <String, String>{
        'tg-y': 'fresh mount-eligibility read pending',
        'tg-b': 'approval: not approved - run the approve verb',
      };
      MountEligibilityDecision eligibility(Bead bead) {
        final clause = clauses[bead.id];
        return clause == null
            ? const MountEligibilityDecision.eligible()
            : MountEligibilityDecision.refused(clause: clause);
      }

      authority.admitPending(
        snapshot,
        _config.copyWith(maxConcurrentWork: 4),
        ServiceBundle(mountEligibility: eligibility),
        candidates,
      );

      final firstSince = now.toUtc();
      final initial = authority.admissionStatus;
      expect(initial.maxAgents, 4);
      expect(initial.reservations, [
        (bead: 'tg-a', sessionId: null, since: firstSince),
        (bead: 'tg-z', sessionId: null, since: firstSince),
      ]);
      expect(initial.refusals, [
        (
          bead: 'tg-b',
          clause: 'approval: not approved - run the approve verb',
          since: firstSince,
        ),
        (
          bead: 'tg-y',
          clause: 'fresh mount-eligibility read pending',
          since: firstSince,
        ),
      ]);
      expect(initial.reservations.every((row) => row.since.isUtc), isTrue);
      expect(initial.refusals.every((row) => row.since.isUtc), isTrue);
      final exposedText = <String>[
        for (final row in initial.reservations)
          '${row.bead}|${row.sessionId}|${row.since.toIso8601String()}',
        for (final row in initial.refusals)
          '${row.bead}|${row.clause}|${row.since.toIso8601String()}',
      ].join('\n');
      expect(exposedText, isNot(contains(bodySentinel)));
      expect(
        () => initial.reservations.add((
          bead: 'tg-nope',
          sessionId: null,
          since: firstSince,
        )),
        throwsUnsupportedError,
      );
      expect(() => initial.refusals.clear(), throwsUnsupportedError);

      now = DateTime(2026, 9, 7, 11);
      final created = await authority.createSessionAttempt(
        snapshot,
        candidates.first,
        title: 'session title',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      expect(created.sessionId, 'tg-session');
      expect(created.refusal, isNull);
      authority.admitPending(
        snapshot,
        _config.copyWith(maxConcurrentWork: 4),
        ServiceBundle(mountEligibility: eligibility),
        candidates,
      );
      final repeated = authority.admissionStatus;
      expect(repeated.reservations, [
        (bead: 'tg-a', sessionId: null, since: firstSince),
        (bead: 'tg-z', sessionId: 'tg-session', since: firstSince),
      ]);
      expect(repeated.refusals, initial.refusals);

      now = DateTime(2026, 9, 7, 12);
      clauses['tg-b'] = 'approval: policy changed';
      authority.admitPending(
        snapshot,
        _config.copyWith(maxConcurrentWork: 4),
        ServiceBundle(mountEligibility: eligibility),
        candidates,
      );
      final changed = authority.admissionStatus;
      expect(changed.refusals, [
        (bead: 'tg-b', clause: 'approval: policy changed', since: now.toUtc()),
        initial.refusals.last,
      ]);

      clauses.remove('tg-b');
      authority.admitPending(
        snapshot,
        _config.copyWith(maxConcurrentWork: 4),
        ServiceBundle(mountEligibility: eligibility),
        candidates,
      );
      expect(authority.admissionStatus.refusals, [initial.refusals.last]);
    },
  );

  test(
    'stranded work is read-only over eligibility and terminal disposition',
    () {
      final work = _bead('tg-work').copyWith(
        metadata: const {
          'grid.approved_by': 'governor',
          'grid.approved_at': '2026-09-13T12:00:00Z',
          'grid.approved_rev': 'current',
        },
      );
      const delivered = SessionProjection(
        workBeadId: 'tg-work',
        sessionId: 'session-done',
        isTerminal: true,
        completed: true,
        results: {
          'blank-first': {ResultKeys.delivery: '   ', 'pr_url': 'ignored'},
          'land-a': {
            ResultKeys.delivery: 'github-pr',
            'pr_url': 'https://github.test/the-grid/pull/426',
          },
          'land-z': {
            ResultKeys.delivery: 'export',
            'pr_url': 'https://example.test/export',
          },
        },
      );
      const eligible = MountEligibilityDecision.eligible();

      expect(
        strandedWorkOf(
          workBead: work,
          session: delivered,
          eligibility: eligible,
        ),
        (
          workBeadId: 'tg-work',
          blockingSessionId: 'session-done',
          disposition: 'done',
          deliveryMethod: 'github-pr',
          deliveryReference: 'https://github.test/the-grid/pull/426',
        ),
      );
      expect(
        strandedWorkOf(
          workBead: work,
          session: delivered.copyWith(
            sessionId: 'session-held',
            completed: false,
            humanHeld: true,
            results: const {},
          ),
          eligibility: eligible,
        )?.disposition,
        'held',
      );
      expect(
        strandedWorkOf(
          workBead: work,
          session: delivered,
          eligibility: const MountEligibilityDecision.refused(
            clause: 'approval revision is stale',
          ),
        ),
        isNull,
      );
      expect(
        strandedWorkOf(
          workBead: work.copyWith(status: BeadStatus.closed),
          session: delivered,
          eligibility: eligible,
        ),
        isNull,
      );
      expect(
        strandedWorkOf(
          workBead: work.copyWith(status: BeadStatus.inProgress),
          session: delivered,
          eligibility: eligible,
        ),
        isNull,
      );
      expect(
        strandedWorkOf(
          workBead: work,
          session: const SessionProjection(
            workBeadId: 'tg-work',
            sessionId: 'session-paused',
            pauseState: SessionPauseState.paused,
          ),
          eligibility: eligible,
        ),
        isNull,
      );
      expect(
        strandedWorkOf(
          workBead: work,
          session: const SessionProjection(
            workBeadId: 'tg-work',
            sessionId: 'session-voided',
            isTerminal: true,
          ),
          eligibility: eligible,
        ),
        isNull,
      );
    },
  );

  test('admission replaces per-scope stranded projections from each pass', () {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 8);
    addTearDown(station.dispose);
    Bead approved(String id) => _bead(id).copyWith(
      metadata: const {
        'grid.approved_by': 'governor',
        'grid.approved_at': '2026-09-13T12:00:00Z',
        'grid.approved_rev': 'current',
      },
    );

    final doneWork = approved('tg-alpha-done');
    final staleWork = approved('tg-alpha-stale').copyWith(
      metadata: const {
        'grid.approved_by': 'governor',
        'grid.approved_at': '2026-09-13T12:00:00Z',
        'grid.approved_rev': 'stale',
      },
    );
    final closedWork = approved(
      'tg-alpha-closed',
    ).copyWith(status: BeadStatus.closed);
    final pausedWork = approved('tg-alpha-paused');
    final voidedWork = approved('tg-alpha-voided');
    final heldWork = approved('tg-beta-held');
    const done = SessionProjection(
      workBeadId: 'tg-alpha-done',
      sessionId: 'session-alpha-done',
      isTerminal: true,
      completed: true,
      results: {
        'land': {
          ResultKeys.delivery: 'github-pr',
          'pr_url': 'https://github.test/the-grid/pull/426',
        },
      },
    );
    const stale = SessionProjection(
      workBeadId: 'tg-alpha-stale',
      sessionId: 'session-alpha-stale',
      isTerminal: true,
      completed: true,
    );
    const closed = SessionProjection(
      workBeadId: 'tg-alpha-closed',
      sessionId: 'session-alpha-closed',
      isTerminal: true,
      completed: true,
    );
    const paused = SessionProjection(
      workBeadId: 'tg-alpha-paused',
      sessionId: 'session-alpha-paused',
      pauseState: SessionPauseState.paused,
    );
    const voided = SessionProjection(
      workBeadId: 'tg-alpha-voided',
      sessionId: 'session-alpha-voided',
      isTerminal: true,
    );
    const held = SessionProjection(
      workBeadId: 'tg-beta-held',
      sessionId: 'session-beta-held',
      isTerminal: true,
      humanHeld: true,
    );
    MountEligibilityDecision approval(Bead bead) =>
        bead.metadata['grid.approved_rev'] == 'current'
        ? const MountEligibilityDecision.eligible()
        : const MountEligibilityDecision.refused(
            clause: 'approval revision is stale',
          );
    final alphaSnapshot = _snapshot(
      [doneWork, staleWork, closedWork, pausedWork, voidedWork],
      sessions: const {
        'tg-alpha-done': done,
        'tg-alpha-stale': stale,
        'tg-alpha-closed': closed,
        'tg-alpha-paused': paused,
        'tg-alpha-voided': voided,
      },
      stateCapturedAt: DateTime.utc(2026, 9, 13, 12, 1),
    );
    final betaSnapshot = _snapshot(
      [heldWork],
      sessions: const {'tg-beta-held': held},
      stateCapturedAt: DateTime.utc(2026, 9, 13, 12, 1),
    );
    final services = ServiceBundle(mountEligibility: approval);
    final alphaConfig = _config.copyWith(
      substationId: 'alpha',
      maxConcurrentWork: 8,
    );
    final betaConfig = _config.copyWith(
      substationId: 'beta',
      maxConcurrentWork: 8,
    );

    station.admission.admitPending(alphaSnapshot, alphaConfig, services, [
      StationAdmissionCandidate(bead: doneWork, session: done),
      StationAdmissionCandidate(bead: staleWork, session: stale),
      StationAdmissionCandidate(bead: closedWork, session: closed),
      StationAdmissionCandidate(bead: pausedWork, session: paused),
      StationAdmissionCandidate(bead: voidedWork, session: voided),
    ]);
    station.admission.admitPending(betaSnapshot, betaConfig, services, [
      StationAdmissionCandidate(bead: heldWork, session: held),
    ]);

    final stranded = station.admission.admissionStatus.stranded;
    expect(stranded, [
      (
        workBeadId: 'tg-alpha-done',
        blockingSessionId: 'session-alpha-done',
        disposition: 'done',
        deliveryMethod: 'github-pr',
        deliveryReference: 'https://github.test/the-grid/pull/426',
      ),
      (
        workBeadId: 'tg-beta-held',
        blockingSessionId: 'session-beta-held',
        disposition: 'held',
        deliveryMethod: null,
        deliveryReference: null,
      ),
    ]);
    expect(() => stranded.clear(), throwsUnsupportedError);

    station.admission.admitPending(
      alphaSnapshot,
      alphaConfig,
      services,
      const [],
    );
    expect(station.admission.admissionStatus.stranded, [
      (
        workBeadId: 'tg-beta-held',
        blockingSessionId: 'session-beta-held',
        disposition: 'held',
        deliveryMethod: null,
        deliveryReference: null,
      ),
    ]);

    station.admission.admitPending(
      betaSnapshot,
      betaConfig,
      services,
      const [],
    );
    expect(station.admission.admissionStatus.stranded, isEmpty);
  });

  test(
    'zero-admission waiter status is stable, sorted, immutable, and clears',
    () async {
      final runner = RecordingBdRunner();
      var now = DateTime(2026, 9, 7, 10);
      final authority = StationAdmissionAuthority(
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {'a', 'b', 'owner'}),
        ),
        provider: FakeRuntimeProvider(),
        stateSubstation: 'owner',
        maxConcurrentWork: 1,
        clock: () => now,
      );
      addTearDown(authority.dispose);
      const ownerConfig = SubstationConfig(
        substationId: 'owner',
        ownedSubstations: {'owner'},
        maxConcurrentWork: 1,
      );
      const aConfig = SubstationConfig(
        substationId: 'a',
        ownedSubstations: {'a'},
        maxConcurrentWork: 1,
      );
      const bConfig = SubstationConfig(
        substationId: 'b',
        ownedSubstations: {'b'},
        maxConcurrentWork: 1,
      );
      final owner = _bead('owner-1');
      final aWaiter = _bead('a-1');
      final bWaiters = [_bead('b-z'), _bead('b-a')];
      final snapshot = _snapshot([owner, aWaiter, ...bWaiters]);

      authority.admitPending(snapshot, ownerConfig, const ServiceBundle(), [
        StationAdmissionCandidate(bead: owner, session: null),
      ]);
      await _pump();

      now = DateTime(2026, 9, 7, 11);
      final blockedB = authority
          .admitPending(snapshot, bConfig, const ServiceBundle(), [
            for (final bead in bWaiters)
              StationAdmissionCandidate(bead: bead, session: null),
          ]);
      expect(blockedB.admitted, isEmpty);
      expect(blockedB.waiting, hasLength(2));
      final bSince = now.toUtc();

      now = DateTime(2026, 9, 7, 12);
      authority.admitPending(snapshot, bConfig, const ServiceBundle(), [
        for (final bead in bWaiters)
          StationAdmissionCandidate(bead: bead, session: null),
      ]);
      authority.admitPending(snapshot, aConfig, const ServiceBundle(), [
        StationAdmissionCandidate(bead: aWaiter, session: null),
      ]);

      final waiting = authority.admissionStatus.zeroAdmissionWaiters;
      expect(waiting, [
        (bead: 'a-1', substation: 'a', since: now.toUtc()),
        (bead: 'b-a', substation: 'b', since: bSince),
        (bead: 'b-z', substation: 'b', since: bSince),
      ]);
      expect(waiting.every((row) => row.since.isUtc), isTrue);
      expect(
        () => waiting.add((bead: 'nope', substation: 'z', since: now.toUtc())),
        throwsUnsupportedError,
      );

      final pausedOwner = SessionProjection(
        workBeadId: owner.id,
        sessionId: 'owner-session',
        pauseState: SessionPauseState.paused,
      );
      final pausedSnapshot = _snapshot(
        [owner, aWaiter, ...bWaiters],
        sessions: {owner.id: pausedOwner},
      );
      authority.admitPending(
        pausedSnapshot,
        ownerConfig,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: owner, session: pausedOwner)],
      );
      final admittedB = authority
          .admitPending(pausedSnapshot, bConfig, const ServiceBundle(), [
            for (final bead in bWaiters)
              StationAdmissionCandidate(bead: bead, session: null),
          ]);
      expect(admittedB.admitted, hasLength(1));
      expect(authority.admissionStatus.zeroAdmissionWaiters, [
        (bead: 'a-1', substation: 'a', since: now.toUtc()),
      ]);

      authority.admitPending(
        pausedSnapshot,
        aConfig,
        const ServiceBundle(),
        const [],
      );
      expect(authority.admissionStatus.zeroAdmissionWaiters, isEmpty);
    },
  );

  test(
    'capacity recheck coalesces reservation releases and ignores no-ops',
    () async {
      final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 2);
      addTearDown(station.dispose);
      const ownerConfig = SubstationConfig(
        substationId: 'owner',
        ownedSubstations: {'owner'},
        maxConcurrentWork: 2,
      );
      const waiterConfig = SubstationConfig(
        substationId: 'waiter',
        ownedSubstations: {'waiter'},
        maxConcurrentWork: 2,
      );
      final owners = [_bead('owner-1'), _bead('owner-2')];
      final waiter = _bead('waiter-1');
      final snapshot = _snapshot([...owners, waiter]);
      final held = station.admission
          .admitPending(snapshot, ownerConfig, const ServiceBundle(), [
            for (final bead in owners)
              StationAdmissionCandidate(bead: bead, session: null),
          ]);
      expect(held.admitted, hasLength(2));
      await _pump();

      final blocked = station.admission.admitPending(
        snapshot,
        waiterConfig,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: waiter, session: null)],
      );
      expect(blocked.admitted, isEmpty);
      expect(blocked.waiting.single.bead.id, waiter.id);

      var notifications = 0;
      station.admission.addInvalidationListener(() => notifications += 1);
      final pausedSessions = {
        for (final owner in owners)
          owner.id: SessionProjection(
            workBeadId: owner.id,
            sessionId: '${owner.id}-session',
            pauseState: SessionPauseState.paused,
          ),
      };
      final pausedSnapshot = _snapshot([
        ...owners,
        waiter,
      ], sessions: pausedSessions);
      final pausedCandidates = [
        for (final owner in owners)
          StationAdmissionCandidate(
            bead: owner,
            session: pausedSessions[owner.id],
          ),
      ];

      station.admission.admitPending(
        pausedSnapshot,
        ownerConfig,
        const ServiceBundle(),
        pausedCandidates,
      );
      await _pump();
      expect(notifications, 1, reason: 'same-turn releases share one recheck');

      station.admission.admitPending(
        pausedSnapshot,
        ownerConfig,
        const ServiceBundle(),
        pausedCandidates,
      );
      await _pump();
      expect(notifications, 1, reason: 'a no-op release schedules no recheck');
    },
  );

  test(
    'disposing before a queued capacity recheck suppresses its callback',
    () async {
      final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
      const ownerConfig = SubstationConfig(
        substationId: 'owner',
        ownedSubstations: {'owner'},
        maxConcurrentWork: 1,
      );
      const waiterConfig = SubstationConfig(
        substationId: 'waiter',
        ownedSubstations: {'waiter'},
        maxConcurrentWork: 1,
      );
      final owner = _bead('owner-1');
      final waiter = _bead('waiter-1');
      final snapshot = _snapshot([owner, waiter]);
      station.admission.admitPending(
        snapshot,
        ownerConfig,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: owner, session: null)],
      );
      await _pump();
      station.admission.admitPending(
        snapshot,
        waiterConfig,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: waiter, session: null)],
      );

      var notifications = 0;
      station.admission.addInvalidationListener(() => notifications += 1);
      final pausedOwner = SessionProjection(
        workBeadId: owner.id,
        sessionId: 'owner-session',
        pauseState: SessionPauseState.paused,
      );
      station.admission.admitPending(
        _snapshot([owner, waiter], sessions: {owner.id: pausedOwner}),
        ownerConfig,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: owner, session: pausedOwner)],
      );
      station.dispose();
      await _pump();
      expect(notifications, 0);
    },
  );

  test(
    'priority then bead id reserves synchronously under both ceilings',
    () async {
      final fakes = buildFakes();
      addTearDown(fakes.ctx.dispose);
      final authority = fakes.ctx.admission;
      final beads = [
        _bead('tg-z', priority: 3),
        _bead('tg-b', priority: 0),
        _bead('tg-a', priority: 0),
      ];
      final snapshot = _snapshot(beads);
      final first = authority.admitPending(
        snapshot,
        _config,
        const ServiceBundle(),
        [
          for (final bead in beads)
            StationAdmissionCandidate(bead: bead, session: null),
        ],
      );

      expect(first.admitted.map((entry) => entry.candidate.bead.id), [
        'tg-a',
        'tg-b',
      ]);
      expect(first.admitted.map((entry) => entry.mountAttempt), [null, null]);
      expect(first.waiting.map((candidate) => candidate.bead.id), ['tg-z']);
      // Only the first two own synchronous reservations; the third is held by
      // capacity and never receives a mount-attempt write.
      await _pump();
      expect(
        fakes.runner.callsFor('create').where((call) {
          final type = call.indexOf('--type');
          return type >= 0 &&
              type + 1 < call.length &&
              call[type + 1] == GridIssueTypes.mountAttempt.wire;
        }),
        hasLength(2),
      );

      final second = authority.admitPending(
        snapshot,
        _config,
        const ServiceBundle(),
        [
          for (final bead in beads)
            StationAdmissionCandidate(bead: bead, session: null),
        ],
      );
      expect(second.admitted.map((entry) => entry.candidate.bead.id), [
        'tg-a',
        'tg-b',
      ]);
      expect(second.admitted.map((entry) => entry.mountAttempt), [1, 1]);
      expect(second.waiting.map((candidate) => candidate.bead.id), ['tg-z']);
    },
  );

  test(
    'snapshot live rows adopt once and duplicate-live refuses before I/O',
    () {
      final fakes = buildFakes();
      addTearDown(fakes.ctx.dispose);
      final bead = _bead('tg-1');
      final candidate = StationAdmissionCandidate(bead: bead, session: null);
      final one = _snapshot(
        [bead],
        sessions: const {
          'tg-1': SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-live',
          ),
        },
      );
      final adopted = fakes.ctx.admission.admitPending(
        one,
        _config,
        const ServiceBundle(),
        [candidate],
      );
      expect(adopted.admitted.single.adopted, isTrue);
      expect(adopted.admitted.single.sessionId, 'tgdog-live');

      final twin = _snapshot(
        [bead],
        sessions: one.sessionsByWorkBead,
        surplus: const {
          'tg-1': [
            SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-rival'),
          ],
        },
      );
      final refused = fakes.ctx.admission.admitPending(
        twin,
        _config,
        const ServiceBundle(),
        [candidate],
      );
      expect(refused.admitted, isEmpty);
      expect(refused.refused.single.clause, 'duplicate-live');
      expect(fakes.runner.calls, isEmpty);
    },
  );

  test('paused rows release authority capacity without retiring', () async {
    final runner = RecordingBdRunner();
    final station = _stationOver(runner, maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final first = _bead('tg-1');
    final second = _bead('tg-2');
    const live = SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-s1');
    final paused = live.copyWith(pauseState: SessionPauseState.paused);
    final capOne = _config.copyWith(maxConcurrentWork: 1);

    final mounted = station.admission.admitPending(
      _snapshot([first], sessions: const {'tg-1': live}),
      capOne,
      const ServiceBundle(),
      [StationAdmissionCandidate(bead: first, session: live)],
    );
    expect(mounted.admitted.single.sessionId, 'tgdog-s1');

    var eligibilityChecks = 0;
    final parkedBeforeContentGates = station.admission.admitPending(
      _snapshot([first], sessions: {'tg-1': paused}),
      capOne,
      ServiceBundle(
        mountEligibility: (_) {
          eligibilityChecks += 1;
          return const MountEligibilityDecision.refused(
            clause: 'controlled refusal',
          );
        },
      ),
      [StationAdmissionCandidate(bead: first, session: paused)],
    );
    expect(parkedBeforeContentGates.refused.single.clause, 'paused');
    expect(eligibilityChecks, 0);

    final parked = station.admission.admitPending(
      _snapshot([first, second], sessions: {'tg-1': paused}),
      capOne,
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: first, session: paused),
        StationAdmissionCandidate(bead: second, session: null),
      ],
    );
    expect(parked.refused.single.clause, 'paused');
    expect(parked.admitted.single.candidate.bead.id, 'tg-2');
    await _pump();
    expect(runner.callsFor('close'), isEmpty);
    expect(
      runner.callsFor('update').where((call) => call[1] == 'tgdog-s1'),
      isEmpty,
      reason: 'parking never mutates the durable session',
    );
  });

  test('resumed rows re-compete once and retain their session identity', () {
    final runner = RecordingBdRunner();
    final station = _stationOver(runner, maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final first = _bead('tg-1');
    final second = _bead('tg-2');
    const resumed = SessionProjection(
      workBeadId: 'tg-1',
      sessionId: 'tgdog-s1',
      pauseState: SessionPauseState.resumed,
    );
    const occupying = SessionProjection(
      workBeadId: 'tg-2',
      sessionId: 'tgdog-s2',
    );
    final capOne = _config.copyWith(maxConcurrentWork: 1);

    final waiting = station.admission.admitPending(
      _snapshot(
        [first, second],
        sessions: const {'tg-1': resumed, 'tg-2': occupying},
      ),
      capOne,
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: first, session: resumed),
        StationAdmissionCandidate(bead: second, session: occupying),
      ],
    );
    expect(waiting.admitted.single.sessionId, 'tgdog-s2');
    expect(waiting.waiting.single.bead.id, 'tg-1');

    final closedOccupant = occupying.copyWith(
      isTerminal: true,
      completed: true,
    );
    final admitted = station.admission.admitPending(
      _snapshot(
        [first, second],
        sessions: {'tg-1': resumed, 'tg-2': closedOccupant},
      ),
      capOne,
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: first, session: resumed),
        StationAdmissionCandidate(bead: second, session: closedOccupant),
      ],
    );
    expect(admitted.admitted.single.sessionId, 'tgdog-s1');
    expect(admitted.admitted.single.adopted, isTrue);
    expect(admitted.waiting, isEmpty);
    expect(runner.calls, isEmpty, reason: 'resume adopts instead of minting');
  });

  test('multiple resumed rows consume synchronous authority slots', () {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final first = _bead('tg-1');
    final second = _bead('tg-2');
    const resumedFirst = SessionProjection(
      workBeadId: 'tg-1',
      sessionId: 'tgdog-s1',
      pauseState: SessionPauseState.resumed,
    );
    const resumedSecond = SessionProjection(
      workBeadId: 'tg-2',
      sessionId: 'tgdog-s2',
      pauseState: SessionPauseState.resumed,
    );
    final batch = station.admission.admitPending(
      _snapshot(
        [first, second],
        sessions: const {'tg-1': resumedFirst, 'tg-2': resumedSecond},
      ),
      _config.copyWith(maxConcurrentWork: 1),
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: first, session: resumedFirst),
        StationAdmissionCandidate(bead: second, session: resumedSecond),
      ],
    );

    expect(batch.admitted.single.sessionId, 'tgdog-s1');
    expect(batch.waiting.single.bead.id, 'tg-2');
  });

  test('lowered live ceiling drains by attrition without eviction', () async {
    final runner = RecordingBdRunner();
    final provider = FakeRuntimeProvider();
    addTearDown(provider.close);
    final station = _stationOver(
      runner,
      provider: provider,
      maxConcurrentWork: 3,
    );
    addTearDown(station.dispose);
    final liveBeads = [_bead('tg-1'), _bead('tg-2'), _bead('tg-3')];
    final fresh = _bead('tg-4');
    final sessions = {
      for (final bead in liveBeads)
        bead.id: SessionProjection(
          workBeadId: bead.id,
          sessionId: '${bead.id}-session',
        ),
    };
    final candidates = [
      for (final bead in liveBeads)
        StationAdmissionCandidate(bead: bead, session: sessions[bead.id]),
      StationAdmissionCandidate(bead: fresh, session: null),
    ];
    final capThree = _config.copyWith(maxConcurrentWork: 3);

    final before = station.admission.admitPending(
      _snapshot([...liveBeads, fresh], sessions: sessions),
      capThree,
      const ServiceBundle(),
      candidates,
    );
    expect(before.admitted, hasLength(3));
    expect(before.waiting.single.bead.id, fresh.id);

    var notifications = 0;
    station.admission.addInvalidationListener(() => notifications += 1);
    final lowered = station.admission.setMaxAgents(1);
    expect(lowered?.maxAgents, 1);
    expect(lowered?.maxAgentsSource, StationAdmissionCeilingSource.control);
    expect(notifications, 1);
    expect(runner.calls, isEmpty, reason: 'the setter performs no bead write');

    StationAdmissionBatch passWithTerminalCount(int terminalCount) {
      final projected = <String, SessionProjection>{};
      for (var index = 0; index < liveBeads.length; index += 1) {
        final bead = liveBeads[index];
        final session = sessions[bead.id]!;
        projected[bead.id] = index < terminalCount
            ? session.copyWith(isTerminal: true, completed: true)
            : session;
      }
      return station.admission.admitPending(
        _snapshot([...liveBeads, fresh], sessions: projected),
        capThree,
        const ServiceBundle(),
        [
          for (final bead in liveBeads)
            StationAdmissionCandidate(bead: bead, session: projected[bead.id]),
          StationAdmissionCandidate(bead: fresh, session: null),
        ],
      );
    }

    expect(passWithTerminalCount(0).waiting.single.bead.id, fresh.id);
    expect(passWithTerminalCount(1).waiting.single.bead.id, fresh.id);
    expect(passWithTerminalCount(2).waiting.single.bead.id, fresh.id);
    final afterDrain = passWithTerminalCount(3);
    expect(afterDrain.admitted.single.candidate.bead.id, fresh.id);
    await _pump();
    expect(provider.stopped, isEmpty, reason: 'a lower cap never evicts');
    expect(runner.callsFor('close'), isEmpty);
    expect(
      runner
          .callsFor('update')
          .where(
            (call) => sessions.values.any(
              (session) => call.length > 1 && call[1] == session.sessionId,
            ),
          ),
      isEmpty,
      reason: 'attrition never mutates a live session',
    );
  });

  test('raising shares the pause readmission pass and admits by priority', () {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final occupyingBead = _bead('tg-1', priority: 0);
    final resumedBead = _bead('tg-2', priority: 1);
    final freshBead = _bead('tg-3', priority: 2);
    const occupying = SessionProjection(
      workBeadId: 'tg-1',
      sessionId: 'tg-1-session',
    );
    const resumed = SessionProjection(
      workBeadId: 'tg-2',
      sessionId: 'tg-2-session',
      pauseState: SessionPauseState.resumed,
    );
    final snapshot = _snapshot(
      [occupyingBead, resumedBead, freshBead],
      sessions: const {'tg-1': occupying, 'tg-2': resumed},
    );
    final capThree = _config.copyWith(maxConcurrentWork: 3);
    final candidates = [
      StationAdmissionCandidate(bead: occupyingBead, session: occupying),
      StationAdmissionCandidate(bead: resumedBead, session: resumed),
      StationAdmissionCandidate(bead: freshBead, session: null),
    ];

    final before = station.admission.admitPending(
      snapshot,
      capThree,
      const ServiceBundle(),
      candidates,
    );
    expect(before.admitted.single.candidate.bead.id, occupyingBead.id);
    expect(before.waiting.map((candidate) => candidate.bead.id), [
      resumedBead.id,
      freshBead.id,
    ]);

    var notifications = 0;
    station.admission.addInvalidationListener(() => notifications += 1);
    final raised = station.admission.setMaxAgents(2);
    expect(raised?.maxAgents, 2);
    expect(notifications, 1);

    final after = station.admission.admitPending(
      snapshot,
      capThree,
      const ServiceBundle(),
      candidates,
    );
    expect(after.admitted.map((entry) => entry.candidate.bead.id), [
      occupyingBead.id,
      resumedBead.id,
    ]);
    expect(after.waiting.single.bead.id, freshBead.id);
    expect(after.admitted.last.adopted, isTrue);
  });

  test('live ceiling validation, notifications, and boot reset are exact', () {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 8);
    addTearDown(station.dispose);
    expect(station.maxConcurrentWork, 8);
    expect(station.admission.admissionStatus.maxAgents, 8);
    expect(
      station.admission.admissionStatus.maxAgentsSource,
      StationAdmissionCeilingSource.boot,
    );

    var notifications = 0;
    station.admission.addInvalidationListener(() => notifications += 1);
    expect(station.admission.setMaxAgents(0), isNull);
    expect(station.admission.setMaxAgents(-1), isNull);
    expect(notifications, 0);
    expect(station.admission.admissionStatus.maxAgents, 8);
    expect(
      station.admission.admissionStatus.maxAgentsSource,
      StationAdmissionCeilingSource.boot,
    );

    final firstSame = station.admission.setMaxAgents(8);
    expect(firstSame?.maxAgentsSource, StationAdmissionCeilingSource.control);
    expect(notifications, 1, reason: 'the first control source is observable');
    final repeatedSame = station.admission.setMaxAgents(8);
    expect(
      repeatedSame?.maxAgentsSource,
      StationAdmissionCeilingSource.control,
    );
    expect(notifications, 1, reason: 'an identical control value is a no-op');
    expect(station.maxConcurrentWork, 8, reason: 'boot input stays immutable');

    final bounced = _stationOver(RecordingBdRunner(), maxConcurrentWork: 6);
    addTearDown(bounced.dispose);
    expect(bounced.admission.admissionStatus.maxAgents, 6);
    expect(
      bounced.admission.admissionStatus.maxAgentsSource,
      StationAdmissionCeilingSource.boot,
    );

    station.dispose();
    expect(station.admission.setMaxAgents(7), isNull);
    expect(notifications, 1);
  });

  test(
    'invalidation removal and disposal are idempotent and fail closed',
    () async {
      final fakes = buildFakes();
      final authority = fakes.ctx.admission;
      var notifications = 0;
      final remove = authority.addInvalidationListener(() => notifications++);
      remove();
      remove();
      final bead = _bead('tg-1');
      final snapshot = _snapshot([bead]);
      authority.admitPending(snapshot, _config, const ServiceBundle(), [
        StationAdmissionCandidate(bead: bead, session: null),
      ]);
      await _pump();
      expect(notifications, 0);

      authority.dispose();
      authority.dispose();
      final disposed = authority.admitPending(
        snapshot,
        _config,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: bead, session: null)],
      );
      expect(disposed.admitted, isEmpty);
      expect(disposed.waiting, isEmpty);
      expect(disposed.refused.single.clause, 'disposed');
    },
  );

  test(
    'mount-attempt and retry registries remain the single asynchronous sources of truth',
    () async {
      final gatedRunner = _GatedMountAttemptRunner();
      addTearDown(() {
        if (!gatedRunner.release.isCompleted) gatedRunner.release.complete();
      });
      final gatedStation = _stationOver(gatedRunner, maxConcurrentWork: 1);
      addTearDown(gatedStation.dispose);
      final gatedBead = _bead('tg-gated');
      final gatedCandidate = StationAdmissionCandidate(
        bead: gatedBead,
        session: null,
      );
      final gatedSnapshot = _snapshot([gatedBead]);
      final firstReservation = gatedStation.admission
          .admitPending(gatedSnapshot, _config, const ServiceBundle(), [
            gatedCandidate,
          ])
          .admitted
          .single;
      await gatedRunner.entered.future;
      gatedStation.admission.admitPending(
        gatedSnapshot,
        _config,
        const ServiceBundle(),
        const [],
      );
      final repeatedReservation = gatedStation.admission
          .admitPending(gatedSnapshot, _config, const ServiceBundle(), [
            gatedCandidate,
          ])
          .admitted
          .single;
      expect(
        repeatedReservation.reservationToken,
        isNot(same(firstReservation.reservationToken)),
      );
      expect(gatedRunner.writesStarted, 1);
      gatedRunner.release.complete();
      await _pump();
      expect(
        gatedStation.admission
            .admitPending(gatedSnapshot, _config, const ServiceBundle(), [
              gatedCandidate,
            ])
            .admitted
            .single
            .mountAttempt,
        1,
      );

      final runner = _FailingMountAttemptRunner();
      final authority = StationAdmissionAuthority(
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {'tg'}),
        ),
        provider: FakeRuntimeProvider(),
        stateSubstation: 'tg',
        maxConcurrentWork: 1,
      );
      addTearDown(authority.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      final bead = _bead('tg-1');
      final candidate = StationAdmissionCandidate(bead: bead, session: null);
      final snapshot = _snapshot([bead]);
      var notifications = 0;
      authority.addInvalidationListener(() => notifications += 1);

      final writing = authority.admitPending(
        snapshot,
        _config.copyWith(maxConcurrentWork: 1),
        services,
        [candidate],
      );
      expect(writing.admitted.single.candidate.bead.id, bead.id);
      expect(writing.admitted.single.mountAttempt, isNull);
      expect(writing.waiting, isEmpty);
      await _pump();

      expect(transport.flares.single.name, 'work.mountAttemptRecordFailed');
      expect(transport.flares.single.data['beadId'], bead.id);
      expect(notifications, 1, reason: 'failure invalidates the mounted scope');
      expect(runner.writesStarted, 1);
      expect(
        authority
            .admitPending(snapshot, _config, services, [candidate])
            .waiting
            .single
            .bead
            .id,
        bead.id,
      );
      await _pump();
      expect(
        runner.writesStarted,
        1,
        reason: 'the live retry timer is the sole admission block',
      );

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      expect(notifications, 2, reason: 'standard backoff reopens admission');

      final admitted = authority.admitPending(snapshot, _config, services, [
        candidate,
      ]);
      expect(admitted.admitted.single.candidate.bead.id, bead.id);
      expect(admitted.admitted.single.mountAttempt, isNull);
      await _pump();
      expect(
        runner.writesStarted,
        2,
        reason: 'timer removal permits one retry',
      );
    },
  );

  test(
    'timeout compensation closes before release and preserves the cause',
    () async {
      final events = <String>[];
      final runner = _GatedCloseRunner(createdId: 'tg-s1', eventLog: events);
      addTearDown(() {
        if (!runner.releaseClose.isCompleted) runner.releaseClose.complete();
      });
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(
        runner,
        provider: provider,
        maxConcurrentWork: 1,
      );
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      var invalidations = 0;
      station.admission.addInvalidationListener(() => invalidations += 1);
      final owned = await _reserveAndCreate(station, 'tg-1');
      final beforeTimeout = invalidations;

      final pour = station.admission.pourMolecule(
        _moleculePlan,
        workBeadId: 'tg-1',
        sessionId: owned.sessionId,
        rootCrumbs: const ['tg-1', 'tg-s1'],
        services: services,
      );
      await runner.closeEntered.future;

      final rival = _bead('tg-2');
      final bothSnapshot = _snapshot([owned.candidate.bead, rival]);
      final held = station.admission.admitPending(
        bothSnapshot,
        _config,
        services,
        [
          owned.candidate,
          StationAdmissionCandidate(bead: rival, session: null),
        ],
      );
      expect(
        held.waiting.map((candidate) => candidate.bead.id),
        contains('tg-2'),
      );
      expect(
        invalidations,
        beforeTimeout,
        reason: 'close is the release fence',
      );

      runner.releaseClose.complete();
      await expectLater(
        pour,
        throwsA(
          isA<StationMintVoided>()
              .having((error) => error.cause, 'cause', same(runner.error))
              .having(
                (error) => error.retiredSessionId,
                'retiredSessionId',
                'tg-s1',
              ),
        ),
      );
      expect(invalidations, beforeTimeout + 1);
      final released = station.admission.admitPending(
        bothSnapshot,
        _config,
        services,
        [StationAdmissionCandidate(bead: rival, session: null)],
      );
      expect(released.admitted.single.candidate.bead.id, 'tg-2');
      expect(
        transport.flares.where(
          (flare) => flare.name == 'session.moleculeReapFailed',
        ),
        isEmpty,
      );

      final closeIndex = events.indexOf('bd:close');
      final voidIndex = runner.calls.indexWhere(
        (call) => call.any(
          (arg) => arg == '${SessionBeadKeys.workBead}=tg-1#void-tg-s1',
        ),
      );
      expect(voidIndex, isNonNegative);
      expect(closeIndex, isNonNegative);
      expect(voidIndex, lessThan(closeIndex));
      expect(
        runner.calls[voidIndex],
        contains('${SessionBeadKeys.voidedReason}=mint-timeout'),
      );
      expect(runner.graphApplyCalls, hasLength(1));
      expect(
        runner.workCreates.where((call) => call.contains('gate')),
        isEmpty,
      );

      await _pump();
      final beforeBackoff = invalidations;
      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      expect(invalidations, beforeBackoff + 1);
    },
  );

  test('marks only the matching retired session terminal', () async {
    final runner = RecordingBdRunner(createdId: 'tg-successor');
    runner.exportBeads = [
      _ownedSession('tg-retired'),
      _ownedSession('tg-unrelated'),
    ];
    final station = _stationOver(runner, maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final work = _bead('tg-1');
    const retired = SessionProjection(
      workBeadId: 'tg-1#r1',
      sessionId: 'tg-retired',
    );
    final candidate = StationAdmissionCandidate(bead: work, session: retired);
    final stale = _snapshot([work], sessions: const {'tg-1': retired});

    final reservation = station.admission.admitPending(
      stale,
      _config.copyWith(maxConcurrentWork: 1),
      const ServiceBundle(),
      [candidate],
    );
    expect(reservation.admitted.single.reservationToken, isNotNull);

    await station.admission.closeRetiredReworkSession(
      workBeadId: work.id,
      sessionId: 'tg-retired',
      reapMolecule: false,
      services: const ServiceBundle(),
    );

    const unrelated = SessionProjection(
      workBeadId: 'tg-1',
      sessionId: 'tg-unrelated',
    );
    final unrelatedStillOpen = await station.admission.createSessionAttempt(
      _snapshot(
        [work],
        sessions: const {'tg-1': retired},
        surplus: const {
          'tg-1': [unrelated],
        },
      ),
      candidate,
      title: 'grid session ${work.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    expect(unrelatedStillOpen.sessionId, isNull);
    expect(unrelatedStillOpen.refusal?.clause, 'live-attempt');

    final created = await station.admission.createSessionAttempt(
      stale,
      candidate,
      title: 'grid session ${work.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    expect(created.refusal, isNull);
    expect(created.sessionId, 'tg-successor');
  });

  test(
    "a different session's release does not evict the reservation",
    () async {
      for (final releaseKind in const ['close', 'completion']) {
        final runner = RecordingBdRunner(
          createdId: 'tg-successor-$releaseKind',
        );
        runner.exportBeads = [
          _ownedSession('tg-retired'),
          _ownedSession('tg-unrelated'),
        ];
        final station = _stationOver(runner, maxConcurrentWork: 1);
        addTearDown(station.dispose);
        final work = _bead('tg-1');
        const retired = SessionProjection(
          workBeadId: 'tg-1#r1',
          sessionId: 'tg-retired',
        );
        final candidate = StationAdmissionCandidate(
          bead: work,
          session: retired,
        );
        final stale = _snapshot([work], sessions: const {'tg-1': retired});
        final config = _config.copyWith(maxConcurrentWork: 1);

        final before = station.admission
            .admitPending(stale, config, const ServiceBundle(), [candidate])
            .admitted
            .single;
        expect(before.reservationToken, isNotNull);

        if (releaseKind == 'close') {
          await station.admission.closeRetiredReworkSession(
            workBeadId: work.id,
            sessionId: 'tg-unrelated',
            reapMolecule: false,
            services: const ServiceBundle(),
          );
        } else {
          await station.admission.completeSession(
            workBeadId: work.id,
            sessionId: 'tg-unrelated',
            outcomeMarked: true,
            outcomeMetadata: const {},
            reapMolecule: false,
            services: const ServiceBundle(),
          );
        }

        final after = station.admission
            .admitPending(stale, config, const ServiceBundle(), [candidate])
            .admitted
            .single;
        expect(after.reservationToken, same(before.reservationToken));

        await station.admission.closeRetiredReworkSession(
          workBeadId: work.id,
          sessionId: 'tg-retired',
          reapMolecule: false,
          services: const ServiceBundle(),
        );
        final created = await station.admission.createSessionAttempt(
          stale,
          candidate,
          title: 'grid session ${work.id}',
          metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
        );
        expect(created.refusal, isNull, reason: releaseKind);
        expect(created.sessionId, 'tg-successor-$releaseKind');
      }
    },
  );

  test('retired-round break admits a second candidate in the same pass', () {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 2);
    addTearDown(station.dispose);
    final retiredWork = _bead('tg-1', priority: 1);
    final nextWork = _bead('tg-2', priority: 1);
    const retired = SessionProjection(
      workBeadId: 'tg-1#r1',
      sessionId: 'tgdog-retired',
    );
    final snapshot = _snapshot([retiredWork, nextWork]);

    final batch = station.admission.admitPending(
      snapshot,
      _config.copyWith(maxConcurrentWork: 2),
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: nextWork, session: null),
        StationAdmissionCandidate(bead: retiredWork, session: retired),
      ],
    );

    expect(batch.admitted.map((reservation) => reservation.candidate.bead.id), [
      'tg-1',
      'tg-2',
    ]);
    expect(batch.waiting, isEmpty);
    expect(batch.refused, isEmpty);
  });

  test(
    'failed timeout close retains capacity and schedules no retry',
    () async {
      final runner = _FailingCloseRunner(createdId: 'tg-s1');
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(
        runner,
        provider: provider,
        maxConcurrentWork: 1,
      );
      addTearDown(station.dispose);
      var invalidations = 0;
      station.admission.addInvalidationListener(() => invalidations += 1);
      final owned = await _reserveAndCreate(station, 'tg-1');
      final beforeTimeout = invalidations;

      await expectLater(
        station.admission.pourMolecule(
          _moleculePlan,
          workBeadId: 'tg-1',
          sessionId: owned.sessionId,
          rootCrumbs: const ['tg-1', 'tg-s1'],
          services: const ServiceBundle(),
        ),
        throwsA(isA<StateError>()),
      );
      final rival = _bead('tg-2');
      final held = station.admission.admitPending(
        _snapshot([owned.candidate.bead, rival]),
        _config,
        const ServiceBundle(),
        [
          owned.candidate,
          StationAdmissionCandidate(bead: rival, session: null),
        ],
      );
      expect(
        held.waiting.map((candidate) => candidate.bead.id),
        contains('tg-2'),
      );
      expect(invalidations, beforeTimeout);
      expect(
        runner
            .callsFor('update')
            .singleWhere(
              (call) =>
                  call.contains('${SessionBeadKeys.voidedReason}=mint-timeout'),
            ),
        contains('${SessionBeadKeys.voidedReason}=mint-timeout'),
      );
      expect(runner.callsFor('close'), hasLength(1));

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      expect(invalidations, beforeTimeout);
    },
  );

  test(
    'unclassified and stale pour failures retain their original identity',
    () async {
      final unclassified = StateError('controlled graph failure');
      final unclassifiedRunner = _GraphErrorRunner(
        unclassified,
        createdId: 'tg-unclassified',
      );
      final unclassifiedStation = _stationOver(unclassifiedRunner);
      addTearDown(unclassifiedStation.dispose);
      final unclassifiedOwned = await _reserveAndCreate(
        unclassifiedStation,
        'tg-1',
      );

      await expectLater(
        unclassifiedStation.admission.pourMolecule(
          _moleculePlan,
          workBeadId: 'tg-1',
          sessionId: unclassifiedOwned.sessionId,
          rootCrumbs: const ['tg-1', 'tg-unclassified'],
          services: const ServiceBundle(),
        ),
        throwsA(same(unclassified)),
      );
      expect(
        unclassifiedRunner
            .callsFor('update')
            .any(
              (call) => call.any(
                (arg) => arg.startsWith('${SessionBeadKeys.voidedReason}='),
              ),
            ),
        isFalse,
      );
      expect(unclassifiedRunner.callsFor('close'), isEmpty);

      const stale = BdTimeoutException(
        command: ['bd', 'create', '--graph', 'plan.json'],
        timeout: BdCliService.pourTimeout,
      );
      final staleRunner = _GraphErrorRunner(stale, createdId: 'tg-owned');
      final staleStation = _stationOver(staleRunner);
      addTearDown(staleStation.dispose);
      await _reserveAndCreate(staleStation, 'tg-2');

      await expectLater(
        staleStation.admission.pourMolecule(
          _moleculePlan,
          workBeadId: 'tg-2',
          sessionId: 'tg-stale',
          rootCrumbs: const ['tg-2', 'tg-stale'],
          services: const ServiceBundle(),
        ),
        throwsA(same(stale)),
      );
      expect(
        staleRunner
            .callsFor('update')
            .any(
              (call) => call.any(
                (arg) => arg.startsWith('${SessionBeadKeys.voidedReason}='),
              ),
            ),
        isFalse,
      );
      expect(staleRunner.callsFor('close'), isEmpty);
    },
  );

  test('reservation token release returns pre-session capacity', () async {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final first = _bead('tg-1');
    final rival = _bead('tg-2');
    final snapshot = _snapshot([first, rival]);
    final config = _config.copyWith(maxConcurrentWork: 1);
    final candidates = [
      StationAdmissionCandidate(bead: first, session: null),
      StationAdmissionCandidate(bead: rival, session: null),
    ];

    final held = station.admission.admitPending(
      snapshot,
      config,
      const ServiceBundle(),
      candidates,
    );
    final reservation = held.admitted.single;
    expect(reservation.candidate.bead.id, 'tg-1');
    expect(reservation.reservationToken, isNotNull);
    expect(held.waiting.single.bead.id, 'tg-2');

    await station.admission.abandonSessionAttempt(
      workBeadId: 'tg-1',
      sessionId: null,
      reservationToken: reservation.reservationToken,
      services: const ServiceBundle(),
    );

    final released = station.admission.admitPending(
      snapshot,
      config,
      const ServiceBundle(),
      [candidates.last],
    );
    expect(released.admitted.single.candidate.bead.id, 'tg-2');
    expect(released.waiting, isEmpty);
  });

  test('pre-session abandon releases K minting reservations and admits K '
      'replacements', () async {
    const candidateCount = 3;
    const abandonedCount = 2;
    final runner = _GatedFailingSessionCreateRunner(
      expectedCreates: abandonedCount,
    );
    final station = _stationOver(runner, maxConcurrentWork: candidateCount);
    addTearDown(() {
      if (!runner.releaseCreates.isCompleted) {
        runner.releaseCreates.complete();
      }
    });
    addTearDown(station.dispose);
    final initialBeads = [
      for (var index = 1; index <= candidateCount; index += 1)
        _bead('tg-$index'),
    ];
    final initialCandidates = [
      for (final bead in initialBeads)
        StationAdmissionCandidate(bead: bead, session: null),
    ];
    final config = _config.copyWith(maxConcurrentWork: candidateCount);
    final initialSnapshot = _snapshot(initialBeads);
    final initial = station.admission.admitPending(
      initialSnapshot,
      config,
      const ServiceBundle(),
      initialCandidates,
    );
    expect(initial.admitted, hasLength(candidateCount));

    final creates = [
      for (var index = 0; index < abandonedCount; index += 1)
        station.admission.createSessionAttempt(
          initialSnapshot,
          initialCandidates[index],
          title: 'grid session ${initialBeads[index].id}',
          metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
        ),
    ];
    await runner.allCreatesEntered.future;

    for (var index = 0; index < abandonedCount; index += 1) {
      final concurrent = await station.admission.createSessionAttempt(
        initialSnapshot,
        initialCandidates[index],
        title: 'duplicate grid session ${initialBeads[index].id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      expect(concurrent.sessionId, isNull);
      expect(concurrent.refusal?.clause, 'missing-reservation');
      await station.admission.abandonSessionAttempt(
        workBeadId: initialBeads[index].id,
        sessionId: null,
        reservationToken: initial.admitted[index].reservationToken,
        services: const ServiceBundle(),
      );
    }

    expect(
      station.admission.admissionStatus.reservations.map(
        (reservation) => reservation.bead,
      ),
      ['tg-3'],
    );
    runner.releaseCreates.complete();
    for (final create in creates) {
      await expectLater(create, throwsA(isA<StateError>()));
    }

    final replacements = [_bead('tg-4'), _bead('tg-5')];
    final replacementCandidates = [
      initialCandidates.last,
      for (final bead in replacements)
        StationAdmissionCandidate(bead: bead, session: null),
    ];
    final transport = _RecordingTransport();
    final replacementSnapshot = _snapshot([initialBeads.last, ...replacements]);
    final replacementBatch = station.admission.admitPending(
      replacementSnapshot,
      config,
      ServiceBundle(transport: transport),
      replacementCandidates,
    );

    expect(
      replacementBatch.admitted.map(
        (reservation) => reservation.candidate.bead.id,
      ),
      ['tg-3', 'tg-4', 'tg-5'],
    );
    expect(replacementBatch.waiting, isEmpty);
    expect(
      transport.flares.where((flare) => flare.name == 'work.throttled'),
      isEmpty,
    );
  });

  test(
    'session create that settles after release is voided and throws',
    () async {
      const createdSessionId = 'tg-abandoned-session';
      const settledReleaseReason =
          'admission reservation released while the create settled';
      final runner = _GatedFailingSessionCreateRunner(
        expectedCreates: 1,
        createdId: createdSessionId,
        failAfterRelease: false,
      );
      final station = _stationOver(runner, maxConcurrentWork: 1);
      addTearDown(() {
        if (!runner.releaseCreates.isCompleted) {
          runner.releaseCreates.complete();
        }
      });
      addTearDown(station.dispose);
      final owner = _bead('tg-owner');
      final rival = _bead('tg-rival');
      final config = _config.copyWith(maxConcurrentWork: 1);
      final snapshot = _snapshot([owner, rival]);
      final ownerCandidate = StationAdmissionCandidate(
        bead: owner,
        session: null,
      );
      final rivalCandidate = StationAdmissionCandidate(
        bead: rival,
        session: null,
      );
      final initial = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        [ownerCandidate, rivalCandidate],
      );
      final ownerReservation = initial.admitted.single;
      final create = station.admission.createSessionAttempt(
        snapshot,
        ownerCandidate,
        title: 'grid session ${owner.id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      await runner.allCreatesEntered.future;

      await station.admission.abandonSessionAttempt(
        workBeadId: owner.id,
        sessionId: null,
        reservationToken: ownerReservation.reservationToken,
        services: const ServiceBundle(),
      );
      final replacement = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        [rivalCandidate],
      );
      expect(replacement.admitted.single.candidate.bead.id, rival.id);
      expect(station.admission.admissionStatus.reservations, hasLength(1));
      expect(
        station.admission.admissionStatus.reservations.single.bead,
        rival.id,
      );

      runner.releaseCreates.complete();
      await expectLater(
        create,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'the admission reservation was released while its write settled',
          ),
        ),
      );

      final voidUpdateIndex = runner.calls.indexWhere(
        (call) =>
            call.isNotEmpty &&
            call.first == 'update' &&
            call.contains(
              '${SessionBeadKeys.workBead}=${owner.id}#void-$createdSessionId',
            ) &&
            call.contains(
              '${SessionBeadKeys.voidedReason}=$settledReleaseReason',
            ),
      );
      expect(voidUpdateIndex, isNonNegative);
      final closeIndex = runner.calls.indexWhere(
        (call) =>
            call.isNotEmpty &&
            call.first == 'close' &&
            call.length > 1 &&
            call[1] == createdSessionId &&
            call.contains(settledReleaseReason),
      );
      expect(closeIndex, greaterThan(voidUpdateIndex));
      expect(station.admission.admissionStatus.reservations, hasLength(1));
      expect(
        station.admission.admissionStatus.reservations.single.bead,
        rival.id,
      );
    },
  );

  test('pause during mint releases capacity and leaves readmission to the '
      'authority', () async {
    final runner = _GatedFailingSessionCreateRunner(expectedCreates: 1);
    final station = _stationOver(runner, maxConcurrentWork: 1);
    addTearDown(() {
      if (!runner.releaseCreates.isCompleted) {
        runner.releaseCreates.complete();
      }
    });
    addTearDown(station.dispose);
    final pausedWork = _bead('tg-paused');
    final rival = _bead('tg-rival');
    final config = _config.copyWith(maxConcurrentWork: 1);
    final initialSnapshot = _snapshot([pausedWork, rival]);
    final pausedCandidate = StationAdmissionCandidate(
      bead: pausedWork,
      session: null,
    );
    final initial = station.admission.admitPending(
      initialSnapshot,
      config,
      const ServiceBundle(),
      [pausedCandidate, StationAdmissionCandidate(bead: rival, session: null)],
    );
    final reservation = initial.admitted.single;
    final create = station.admission.createSessionAttempt(
      initialSnapshot,
      pausedCandidate,
      title: 'grid session ${pausedWork.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    await runner.allCreatesEntered.future;

    await station.admission.abandonSessionAttempt(
      workBeadId: pausedWork.id,
      sessionId: null,
      reservationToken: reservation.reservationToken,
      services: const ServiceBundle(),
    );
    expect(station.admission.admissionStatus.reservations, isEmpty);

    final paused = SessionProjection(
      workBeadId: pausedWork.id,
      sessionId: 'tg-paused-session',
      pauseState: SessionPauseState.paused,
    );
    final whilePaused = station.admission.admitPending(
      _snapshot([pausedWork, rival], sessions: {pausedWork.id: paused}),
      config,
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: pausedWork, session: paused),
        StationAdmissionCandidate(bead: rival, session: null),
      ],
    );
    expect(whilePaused.refused.single.clause, 'paused');
    expect(whilePaused.admitted.single.candidate.bead.id, rival.id);

    runner.releaseCreates.complete();
    await expectLater(create, throwsA(isA<StateError>()));

    final resumed = paused.copyWith(pauseState: SessionPauseState.resumed);
    final whileOccupied = station.admission.admitPending(
      _snapshot([pausedWork, rival], sessions: {pausedWork.id: resumed}),
      config,
      const ServiceBundle(),
      [
        StationAdmissionCandidate(bead: pausedWork, session: resumed),
        StationAdmissionCandidate(bead: rival, session: null),
      ],
    );
    expect(whileOccupied.waiting.single.bead.id, pausedWork.id);
    expect(whileOccupied.admitted.single.candidate.bead.id, rival.id);

    await station.admission.abandonSessionAttempt(
      workBeadId: rival.id,
      sessionId: null,
      reservationToken: whilePaused.admitted.single.reservationToken,
      services: const ServiceBundle(),
    );
    final readmitted = station.admission.admitPending(
      _snapshot([pausedWork], sessions: {pausedWork.id: resumed}),
      config,
      const ServiceBundle(),
      [StationAdmissionCandidate(bead: pausedWork, session: resumed)],
    );
    expect(readmitted.admitted.single.sessionId, resumed.sessionId);
    expect(readmitted.admitted.single.adopted, isTrue);
  });

  test('session-carrying abandon waits for durable close before releasing '
      'capacity', () async {
    final runner = _GatedCloseRunner(createdId: 'tg-session');
    final station = _stationOver(runner, maxConcurrentWork: 1);
    addTearDown(() {
      if (!runner.releaseClose.isCompleted) runner.releaseClose.complete();
    });
    addTearDown(station.dispose);
    final owner = _bead('tg-owner');
    final rival = _bead('tg-rival');
    final config = _config.copyWith(maxConcurrentWork: 1);
    final ownerCandidate = StationAdmissionCandidate(
      bead: owner,
      session: null,
    );
    final initialSnapshot = _snapshot([owner, rival]);
    final initial = station.admission.admitPending(
      initialSnapshot,
      config,
      const ServiceBundle(),
      [ownerCandidate],
    );
    final token = initial.admitted.single.reservationToken;
    final created = await station.admission.createSessionAttempt(
      initialSnapshot,
      ownerCandidate,
      title: 'grid session ${owner.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    expect(created.sessionId, 'tg-session');

    await station.admission.abandonSessionAttempt(
      workBeadId: owner.id,
      sessionId: null,
      reservationToken: token,
      services: const ServiceBundle(),
    );
    expect(
      station.admission.admissionStatus.reservations.single.bead,
      owner.id,
    );

    final abandon = station.admission.abandonSessionAttempt(
      workBeadId: owner.id,
      sessionId: created.sessionId,
      reservationToken: token,
      services: const ServiceBundle(),
    );
    await runner.closeEntered.future;
    final voidUpdateIndex = runner.calls.indexWhere(
      (call) =>
          call.isNotEmpty &&
          call.first == 'update' &&
          call.contains(
            '${SessionBeadKeys.workBead}=${owner.id}#void-tg-session',
          ),
    );
    expect(voidUpdateIndex, isNonNegative);
    expect(runner.callsFor('close'), isEmpty);
    expect(
      station.admission.admissionStatus.reservations.single.bead,
      owner.id,
    );
    final beforeClose = station.admission.admitPending(
      initialSnapshot,
      config,
      const ServiceBundle(),
      [ownerCandidate, StationAdmissionCandidate(bead: rival, session: null)],
    );
    expect(beforeClose.waiting.single.bead.id, rival.id);

    runner.releaseClose.complete();
    expect(await abandon, 'tg-session');
    final closeIndex = runner.calls.indexWhere(
      (call) => call.isNotEmpty && call.first == 'close',
    );
    expect(closeIndex, greaterThan(voidUpdateIndex));
    final afterClose = station.admission.admitPending(
      _snapshot([rival]),
      config,
      const ServiceBundle(),
      [StationAdmissionCandidate(bead: rival, session: null)],
    );
    expect(afterClose.admitted.single.candidate.bead.id, rival.id);
    expect(afterClose.waiting, isEmpty);
  });

  test(
    'frontier-abandoned reservation stays released until the bead is ready',
    () async {
      final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
      addTearDown(station.dispose);
      final first = _bead('tg-1');
      final rival = _bead('tg-2');
      final config = _config.copyWith(maxConcurrentWork: 1);
      final candidates = [
        StationAdmissionCandidate(bead: first, session: null),
        StationAdmissionCandidate(bead: rival, session: null),
      ];
      final initiallyReady = _snapshot([first, rival]);

      final initial = station.admission.admitPending(
        initiallyReady,
        config,
        const ServiceBundle(),
        candidates,
      );
      final firstReservation = initial.admitted.single;
      expect(firstReservation.candidate.bead.id, 'tg-1');

      await station.admission.abandonSessionAttempt(
        workBeadId: 'tg-1',
        sessionId: null,
        reservationToken: firstReservation.reservationToken,
        services: const ServiceBundle(),
        blockUntilFreshReady: true,
      );
      expect(station.admission.admissionStatus.reservations, isEmpty);

      final dependencyBlocked = JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [first, rival],
          dependencies: const [
            BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2'),
          ],
          readyIds: const {'tg-2'},
          capturedAt: DateTime.utc(2026, 9, 8),
        ),
      );
      final released = station.admission.admitPending(
        dependencyBlocked,
        config,
        const ServiceBundle(),
        candidates,
      );

      expect(released.waiting.single.bead.id, 'tg-1');
      expect(released.admitted.single.candidate.bead.id, 'tg-2');
      expect(
        station.admission.admissionStatus.reservations.map(
          (reservation) => reservation.bead,
        ),
        ['tg-2'],
      );

      await station.admission.abandonSessionAttempt(
        workBeadId: 'tg-2',
        sessionId: null,
        reservationToken: released.admitted.single.reservationToken,
        services: const ServiceBundle(),
      );
      final readyAgain = station.admission.admitPending(
        initiallyReady,
        config,
        const ServiceBundle(),
        candidates,
      );
      expect(readyAgain.admitted.single.candidate.bead.id, 'tg-1');
      expect(
        identical(
          readyAgain.admitted.single.reservationToken,
          firstReservation.reservationToken,
        ),
        isFalse,
      );
    },
  );

  test(
    'frontier block preserves a live retired-round mount in substation capacity',
    () async {
      final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 2);
      addTearDown(station.dispose);
      final retiredBead = _bead('tg-1');
      final rival = _bead('tg-2');
      const retired = SessionProjection(
        workBeadId: 'tg-1#r1',
        sessionId: 'tgdog-round1',
      );
      final retiredCandidate = StationAdmissionCandidate(
        bead: retiredBead,
        session: retired,
      );
      final rivalCandidate = StationAdmissionCandidate(
        bead: rival,
        session: null,
      );
      final config = _config.copyWith(maxConcurrentWork: 1);
      final initiallyReady = _snapshot([retiredBead, rival]);

      final initial = station.admission.admitPending(
        initiallyReady,
        config,
        const ServiceBundle(),
        [retiredCandidate],
      );
      final retiredReservation = initial.admitted.single;
      expect(retiredReservation.candidate.bead.id, 'tg-1');

      await station.admission.abandonSessionAttempt(
        workBeadId: 'tg-1',
        sessionId: null,
        reservationToken: retiredReservation.reservationToken,
        services: const ServiceBundle(),
        blockUntilFreshReady: true,
      );

      final dependencyBlocked = JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [retiredBead, rival],
          dependencies: const [
            BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2'),
          ],
          readyIds: const {'tg-2'},
          capturedAt: DateTime.utc(2026, 9, 8),
        ),
      );
      final blocked = station.admission.admitPending(
        dependencyBlocked,
        config,
        const ServiceBundle(),
        [retiredCandidate, rivalCandidate],
      );

      expect(blocked.waiting.map((candidate) => candidate.bead.id), [
        'tg-1',
        'tg-2',
      ]);
      expect(blocked.admitted, isEmpty);
      expect(station.admission.admissionStatus.reservations, isEmpty);
    },
  );

  test(
    'reservation token is reused only while one held grant survives',
    () async {
      final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
      addTearDown(station.dispose);
      final first = _bead('tg-1');
      final rival = _bead('tg-2');
      final snapshot = _snapshot([first, rival]);
      final config = _config.copyWith(maxConcurrentWork: 1);
      final candidates = [
        StationAdmissionCandidate(bead: first, session: null),
        StationAdmissionCandidate(bead: rival, session: null),
      ];

      final initial = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        candidates,
      );
      final initialToken = initial.admitted.single.reservationToken;
      final repeated = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        candidates,
      );
      expect(repeated.admitted.single.reservationToken, same(initialToken));

      await station.admission.abandonSessionAttempt(
        workBeadId: 'tg-1',
        sessionId: null,
        reservationToken: initialToken,
        services: const ServiceBundle(),
      );
      final readmitted = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        candidates,
      );
      final freshToken = readmitted.admitted.single.reservationToken;
      expect(freshToken, isNotNull);
      expect(identical(freshToken, initialToken), isFalse);

      await station.admission.abandonSessionAttempt(
        workBeadId: 'tg-1',
        sessionId: null,
        reservationToken: initialToken,
        services: const ServiceBundle(),
      );
      final staleRelease = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        candidates,
      );
      expect(staleRelease.admitted.single.candidate.bead.id, 'tg-1');
      expect(staleRelease.admitted.single.reservationToken, same(freshToken));
      expect(staleRelease.waiting.single.bead.id, 'tg-2');
    },
  );

  test('null reservation token cannot release pre-session capacity', () async {
    final station = _stationOver(RecordingBdRunner(), maxConcurrentWork: 1);
    addTearDown(station.dispose);
    final first = _bead('tg-1');
    final rival = _bead('tg-2');
    final snapshot = _snapshot([first, rival]);
    final config = _config.copyWith(maxConcurrentWork: 1);
    final candidates = [
      StationAdmissionCandidate(bead: first, session: null),
      StationAdmissionCandidate(bead: rival, session: null),
    ];

    final held = station.admission.admitPending(
      snapshot,
      config,
      const ServiceBundle(),
      candidates,
    );
    expect(held.admitted.single.candidate.bead.id, 'tg-1');

    await station.admission.abandonSessionAttempt(
      workBeadId: 'tg-1',
      sessionId: null,
      reservationToken: null,
      services: const ServiceBundle(),
    );
    final retained = station.admission.admitPending(
      snapshot,
      config,
      const ServiceBundle(),
      candidates,
    );
    expect(retained.admitted.single.candidate.bead.id, 'tg-1');
    expect(
      retained.admitted.single.reservationToken,
      same(held.admitted.single.reservationToken),
    );
    expect(retained.waiting.single.bead.id, 'tg-2');
  });

  test(
    'abandonment ignores stale ids and compensates an owned session',
    () async {
      final events = <String>[];
      final runner = RecordingBdRunner(createdId: 'tg-s1', eventLog: events);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(runner, provider: provider);
      addTearDown(station.dispose);
      final owned = await _reserveAndCreate(station, 'tg-1');
      var invalidations = 0;
      station.admission.addInvalidationListener(() => invalidations += 1);

      expect(
        await station.admission.abandonSessionAttempt(
          workBeadId: 'tg-1',
          sessionId: null,
          reservationToken: null,
          services: const ServiceBundle(),
        ),
        isNull,
      );
      expect(
        await station.admission.abandonSessionAttempt(
          workBeadId: 'tg-1',
          sessionId: 'tg-stale',
          reservationToken: null,
          services: const ServiceBundle(),
        ),
        isNull,
      );
      expect(runner.callsFor('close'), isEmpty);

      expect(
        await station.admission.abandonSessionAttempt(
          workBeadId: 'tg-1',
          sessionId: owned.sessionId,
          reservationToken: null,
          services: const ServiceBundle(),
        ),
        'tg-s1',
      );
      expect(invalidations, 1);
      final voidUpdate = runner
          .callsFor('update')
          .singleWhere(
            (call) => call.any(
              (arg) => arg == '${SessionBeadKeys.workBead}=tg-1#void-tg-s1',
            ),
          );
      expect(
        voidUpdate,
        contains('${SessionBeadKeys.voidedReason}=mint-abandoned'),
      );
      expect(events.indexOf('bd:close'), isNonNegative);

      final rival = _bead('tg-2');
      final admitted = station.admission.admitPending(
        _snapshot([rival]),
        _config,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: rival, session: null)],
      );
      expect(admitted.admitted.single.candidate.bead.id, 'tg-2');
    },
  );

  test(
    'open rivals stop every runtime and retire before later adoption',
    () async {
      final events = <String>[];
      final runner = RecordingBdRunner(eventLog: events);
      final provider = _GatedStopProvider();
      addTearDown(() {
        if (!provider.releaseStop.isCompleted) provider.releaseStop.complete();
      });
      addTearDown(provider.close);
      await provider.start(
        'tg-rival/tg-1/agent',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      await provider.start(
        'tg-rival/tg-1/verify',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      final station = _stationOver(runner, provider: provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      final work = _bead('tg-1');
      const winner = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-winner',
      );
      const rival = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-rival',
      );
      final duplicate = _snapshot(
        [work],
        sessions: const {'tg-1': winner},
        surplus: const {
          'tg-1': [rival],
        },
      );
      final candidate = StationAdmissionCandidate(bead: work, session: winner);

      final first = station.admission.admitPending(
        duplicate,
        _config,
        services,
        [candidate],
      );
      expect(first.refused.single.clause, 'duplicate-live');
      await provider.stopEntered.future;
      expect(
        runner.calls,
        isEmpty,
        reason: 'all stops precede durable cleanup',
      );
      final overlapping = station.admission.admitPending(
        duplicate,
        _config,
        services,
        [candidate],
      );
      expect(overlapping.refused.single.clause, 'duplicate-live');
      final overlappingFlares = transport.flares.where(
        (flare) => flare.name == 'work.duplicateLiveRefused',
      );
      expect(overlappingFlares, hasLength(2));
      expect(
        overlappingFlares.every(
          (flare) =>
              flare.data['beadId'] == 'tg-1' &&
              flare.data['sessionId'] == 'tg-winner' &&
              flare.data['rivalSessionIds'] == 'tg-rival',
        ),
        isTrue,
      );
      expect(provider.listRunningCalls, 1);
      provider.releaseStop.complete();
      await _waitUntil(
        () => transport.flares.any(
          (flare) => flare.name == 'work.sessionSurplusRetired',
        ),
      );

      expect(provider.stopped, ['tg-rival/tg-1/agent', 'tg-rival/tg-1/verify']);
      expect(provider.listRunningCalls, 1);
      expect(runner.callsFor('close'), hasLength(1));
      expect(
        runner
            .callsFor('update')
            .where(
              (call) => call.contains(
                '${SessionBeadKeys.workBead}=tg-1#void-tg-rival',
              ),
            ),
        hasLength(1),
      );
      final closeIndex = runner.calls.indexWhere(
        (call) => call.isNotEmpty && call.first == 'close',
      );
      final voidIndex = runner.calls.indexWhere(
        (call) => call.any(
          (arg) => arg == '${SessionBeadKeys.workBead}=tg-1#void-tg-rival',
        ),
      );
      expect(closeIndex, isNonNegative);
      expect(closeIndex, lessThan(voidIndex));
      final retired = transport.flares.singleWhere(
        (flare) => flare.name == 'work.sessionSurplusRetired',
      );
      expect(retired.data['sessionId'], 'tg-rival');

      await _pump();
      final stale = station.admission.admitPending(
        duplicate,
        _config,
        services,
        [candidate],
      );
      expect(stale.refused.single.clause, 'duplicate-live');
      await _waitUntil(
        () =>
            transport.flares
                .where((flare) => flare.name == 'work.sessionSurplusRetired')
                .length ==
            2,
      );
      expect(provider.listRunningCalls, 2);
      expect(
        transport.flares.where(
          (flare) => flare.name == 'work.sessionSurplusRetired',
        ),
        hasLength(2),
      );
      final joined = _snapshot([work], sessions: const {'tg-1': winner});
      final adopted = station.admission.admitPending(
        joined,
        _config,
        services,
        [candidate],
      );
      expect(adopted.admitted.single.sessionId, 'tg-winner');
      expect(
        transport.flares.where(
          (flare) => flare.name == 'work.duplicateLiveRefused',
        ),
        hasLength(3),
      );
    },
  );

  test(
    'an unmanaged live rival stays refused and performs no writer call',
    () async {
      final runner = RecordingBdRunner();
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(
        runner,
        provider: provider,
        liveness: (_) => true,
      );
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      final work = _bead('tg-1');
      const winner = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-winner',
      );
      const rival = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-rival',
        pid: 42,
        pgid: 41,
      );
      final duplicate = _snapshot(
        [work],
        sessions: const {'tg-1': winner},
        surplus: const {
          'tg-1': [rival],
        },
      );
      final candidate = StationAdmissionCandidate(bead: work, session: winner);

      expect(
        station.admission
            .admitPending(duplicate, _config, services, [candidate])
            .refused
            .single
            .clause,
        'duplicate-live',
      );
      await _waitUntil(
        () => transport.flares.any(
          (flare) => flare.name == 'work.sessionSurplusAlive',
        ),
      );
      expect(runner.calls, isEmpty);
      expect(
        station.admission
            .admitPending(duplicate, _config, services, [candidate])
            .refused
            .single
            .clause,
        'duplicate-live',
      );
      await _pump();
      expect(runner.calls, isEmpty);
      final duplicateFlares = transport.flares.where(
        (flare) => flare.name == 'work.duplicateLiveRefused',
      );
      expect(duplicateFlares, hasLength(2));
      expect(
        duplicateFlares.every(
          (flare) =>
              flare.data['beadId'] == 'tg-1' &&
              flare.data['sessionId'] == 'tg-winner' &&
              flare.data['rivalSessionIds'] == 'tg-rival',
        ),
        isTrue,
      );
      final aliveFlares = transport.flares.where(
        (flare) => flare.name == 'work.sessionSurplusAlive',
      );
      expect(aliveFlares, hasLength(2));
      expect(
        aliveFlares.every(
          (flare) =>
              flare.data['beadId'] == 'tg-1' &&
              flare.data['sessionIds'] == 'tg-rival',
        ),
        isTrue,
      );
    },
  );

  test(
    'failed rival retirement stays refused and retries on a later request',
    () async {
      final runner = _FailFirstVoidUpdateRunner(
        error: TimeoutException('Future not completed'),
      );
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(runner, provider: provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      final work = _bead('tg-1');
      const winner = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-winner',
      );
      const rival = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tg-rival',
      );
      final duplicate = _snapshot(
        [work],
        sessions: const {'tg-1': winner},
        surplus: const {
          'tg-1': [rival],
        },
      );
      final candidate = StationAdmissionCandidate(bead: work, session: winner);

      station.admission.admitPending(duplicate, _config, services, [candidate]);
      await _waitUntil(
        () => transport.flares.any(
          (flare) => flare.name == 'work.sessionSurplusRetireFailed',
        ),
      );
      final failed = transport.flares.singleWhere(
        (flare) => flare.name == 'work.sessionSurplusRetireFailed',
      );
      expect(
        failed.data,
        containsPair('deadlineConstant', 'DoltQueryService.queryTimeout'),
      );
      expect(failed.data, containsPair('deadlineMs', '10000'));
      expect(
        station.admission
            .admitPending(duplicate, _config, services, [candidate])
            .refused
            .single
            .clause,
        'duplicate-live',
      );
      await _waitUntil(
        () => transport.flares.any(
          (flare) => flare.name == 'work.sessionSurplusRetired',
        ),
      );
      expect(
        transport.flares.where(
          (flare) => flare.name == 'work.duplicateLiveRefused',
        ),
        hasLength(2),
      );
      expect(
        transport.flares
            .singleWhere((flare) => flare.name == 'work.sessionSurplusRetired')
            .data['sessionId'],
        'tg-rival',
      );
    },
  );
}
