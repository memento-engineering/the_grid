import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('relay contract and persisted horizon projection', () async {
    final deadline = DateTime.utc(2026, 9, 12, 12);
    final observedAt = deadline.add(const Duration(minutes: 1));
    final observation = RelayObservation(
      sessionId: 'state-session-1',
      workBeadId: 'work-1',
      startedAt: deadline.subtract(const Duration(hours: 24)),
      deadline: deadline,
      observedAt: observedAt,
    );
    expect(observation.copyWith(observedAt: observedAt), observation);

    final observer = _FakeRelayObserver(
      const RelayVerdict.absorb(nextHorizon: Duration(hours: 6)),
    );
    final absorb = await observer.observe(observation);
    final absorbSummary = switch (absorb) {
      RelayAbsorb(:final nextHorizon) => 'absorb:${nextHorizon.inHours}',
      RelayEscalate(:final reason) => 'escalate:$reason',
    };
    expect(absorbSummary, 'absorb:6');

    const escalate = RelayVerdict.escalate(reason: 'operator needed');
    final escalationSummary = switch (escalate) {
      RelayAbsorb(:final nextHorizon) => 'absorb:${nextHorizon.inHours}',
      RelayEscalate(:final reason) => 'escalate:$reason',
    };
    expect(escalationSummary, 'escalate:operator needed');

    final nextAt = DateTime.utc(2026, 9, 13, 3, 4, 5);
    final metadata = <String, String>{
      SessionBeadKeys.workBead: 'work-1',
      ...relayHorizonMetadata(nextAt),
    };
    expect(
      metadata[SessionBeadKeys.relayNextObservationAt],
      '2026-09-13T03:04:05.000Z',
    );

    final projected = projectSession(
      Bead(
        id: 'state-session-1',
        issueType: GridIssueTypes.session,
        metadata: metadata,
      ),
    );
    expect(projected.relayNextObservationAt, nextAt);
    expect(projected.copyWith(relayNextObservationAt: nextAt), projected);

    const flareNames = <String>[
      kRelayAbsentFlare,
      kRelayErrorFlare,
      kRelayTimeoutFlare,
      kRelayCapacityFlare,
      kRelayEscalatedFlare,
    ];
    expect(flareNames, everyElement(startsWith('relay.')));
    expect(kDefaultWorkSessionTimeToLive, const Duration(hours: 24));
    expect(kDefaultRelayObservationTimeout, const Duration(minutes: 5));
  });

  test(
    'AC-1 fenced tick requests observation without session mutation',
    () async {
      var now = DateTime.utc(2026, 9, 12, 12);
      final runner = RecordingBdRunner();
      final writer = _writer(runner);
      final pending = Completer<RelayVerdict>();
      final observer = _FakeRelayObserver.from((_) => pending.future);
      final liveness = WorkSessionLiveness(
        writeHorizon: (sessionId, nextAt) =>
            writer.update(sessionId, metadata: relayHorizonMetadata(nextAt)),
        timeToLive: const Duration(hours: 1),
        clock: () => now,
        timeout: (operation, _) => operation,
      );
      addTearDown(() {
        liveness.dispose();
        if (!pending.isCompleted) {
          pending.complete(
            const RelayVerdict.escalate(reason: 'test teardown'),
          );
        }
      });
      liveness.mountRelay(observer: observer, ceiling: 1);
      liveness.refresh(
        _snapshot([
          _session(
            'state-session-1',
            'work-1',
            startedAt: now.subtract(const Duration(hours: 2)),
          ),
        ]),
      );

      liveness.onFencedTick();
      expect(observer.observations, isEmpty, reason: 'not active before mount');
      liveness.activate();
      liveness.activate();
      liveness.onFencedTick();
      liveness.onFencedTick();

      expect(observer.observations, hasLength(1));
      expect(observer.observations.single.sessionId, 'state-session-1');
      expect(observer.observations.single.workBeadId, 'work-1');
      expect(
        observer.observations.single.deadline,
        now.subtract(const Duration(hours: 1)),
      );
      expect(runner.callsFor('update'), isEmpty);
      expect(runner.callsFor('close'), isEmpty);
      expect(runner.callsFor('delete'), isEmpty);

      now = now.add(const Duration(days: 30));
      liveness.onFencedTick();
      expect(observer.observations, hasLength(1));
    },
  );

  test('AC-2 verdict persists and enforces the next horizon', () async {
    var now = DateTime.utc(2026, 9, 12, 12);
    final runner = RecordingBdRunner();
    final writer = _writer(runner);
    final observer = _FakeRelayObserver(
      const RelayVerdict.absorb(nextHorizon: Duration(hours: 6)),
    );
    final liveness = WorkSessionLiveness(
      writeHorizon: (sessionId, nextAt) =>
          writer.update(sessionId, metadata: relayHorizonMetadata(nextAt)),
      clock: () => now,
    );
    addTearDown(liveness.dispose);
    liveness.mountRelay(observer: observer, ceiling: 1);
    liveness.refresh(
      _snapshot([
        _session(
          'state-session-1',
          'work-1',
          deadline: now.subtract(const Duration(minutes: 1)),
        ),
      ]),
    );
    liveness.activate();

    liveness.onFencedTick();
    await _drainAsync();
    final nextAt = now.add(const Duration(hours: 6));
    expect(runner.callsFor('update'), hasLength(1));
    expect(runner.callsFor('close'), isEmpty);
    expect(runner.metadataOfUpdate(0), relayHorizonMetadata(nextAt));

    now = nextAt.subtract(const Duration(microseconds: 1));
    liveness.onFencedTick();
    expect(observer.observations, hasLength(1));
    now = nextAt;
    liveness.onFencedTick();
    expect(observer.observations, hasLength(2));

    final escalations = _RecordingTransport();
    final escalating = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      transport: escalations,
      clock: () => now,
    );
    addTearDown(escalating.dispose);
    escalating.mountRelay(
      observer: _FakeRelayObserver(
        const RelayVerdict.escalate(reason: 'round needs governor review'),
      ),
      ceiling: 1,
    );
    escalating.refresh(
      _snapshot([_session('state-session-2', 'work-2', deadline: now)]),
    );
    escalating.activate();
    escalating.onFencedTick();
    escalating.onFencedTick();
    await _drainAsync();
    expect(escalations.flares, hasLength(1));
    expect(escalations.flares.single.name, kRelayEscalatedFlare);
    expect(
      escalations.flares.single.data,
      containsPair('sessionId', 'state-session-2'),
    );
    expect(
      escalations.flares.single.data,
      containsPair('workBeadId', 'work-2'),
    );
    expect(
      escalations.flares.single.data,
      containsPair('reason', 'round needs governor review'),
    );
  });

  test('AC-3 unavailable relay paths flare once', () async {
    var now = DateTime.utc(2026, 9, 12, 12);

    final absentTransport = _RecordingTransport();
    final absent = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      transport: absentTransport,
      clock: () => now,
    );
    addTearDown(absent.dispose);
    absent.refresh(
      _snapshot([_session('state-absent', 'work-absent', deadline: now)]),
    );
    absent.activate();
    absent.onFencedTick();
    absent.onFencedTick();
    expect(absentTransport.names, [kRelayAbsentFlare]);

    final rearmedAt = now.add(const Duration(hours: 1));
    final rearmedObserver = _FakeRelayObserver(
      const RelayVerdict.escalate(reason: 'observed after durable re-arm'),
    );
    absent.mountRelay(observer: rearmedObserver, ceiling: 1);
    absent.refresh(
      _snapshot([_session('state-absent', 'work-absent', deadline: rearmedAt)]),
    );
    now = rearmedAt;
    absent.onFencedTick();
    expect(rearmedObserver.observations, hasLength(1));

    final syncErrorTransport = _RecordingTransport();
    final syncError = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      transport: syncErrorTransport,
      clock: () => now,
      timeout: (operation, _) => operation,
    );
    addTearDown(syncError.dispose);
    syncError.mountRelay(
      observer: _FakeRelayObserver.from(
        (_) => throw StateError('synchronous relay failure'),
      ),
      ceiling: 1,
    );
    syncError.refresh(
      _snapshot([_session('state-sync', 'work-sync', deadline: now)]),
    );
    syncError.activate();
    syncError.onFencedTick();
    syncError.onFencedTick();
    expect(syncErrorTransport.names, [kRelayErrorFlare]);

    final asyncErrorTransport = _RecordingTransport();
    final asyncError = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      transport: asyncErrorTransport,
      clock: () => now,
      timeout: (operation, _) => operation,
    );
    addTearDown(asyncError.dispose);
    asyncError.mountRelay(
      observer: _FakeRelayObserver.from(
        (_) => Future<RelayVerdict>.error(StateError('async relay failure')),
      ),
      ceiling: 1,
    );
    asyncError.refresh(
      _snapshot([_session('state-async', 'work-async', deadline: now)]),
    );
    asyncError.activate();
    asyncError.onFencedTick();
    asyncError.onFencedTick();
    await _drainAsync();
    expect(asyncErrorTransport.names, [kRelayErrorFlare]);

    final timeoutTransport = _RecordingTransport();
    final hanging = Completer<RelayVerdict>();
    final horizonWrites = <DateTime>[];
    final timedOut = WorkSessionLiveness(
      writeHorizon: (_, nextAt) async => horizonWrites.add(nextAt),
      transport: timeoutTransport,
      clock: () => now,
      timeout: (_, __) => Future<RelayVerdict>.error(
        TimeoutException('controlled relay timeout'),
      ),
    );
    addTearDown(() {
      timedOut.dispose();
      if (!hanging.isCompleted) {
        hanging.complete(
          const RelayVerdict.absorb(nextHorizon: Duration(hours: 1)),
        );
      }
    });
    timedOut.mountRelay(
      observer: _FakeRelayObserver.from((_) => hanging.future),
      ceiling: 1,
    );
    timedOut.refresh(
      _snapshot([
        _session('state-timeout-a', 'work-timeout-a', deadline: now),
        _session('state-timeout-b', 'work-timeout-b', deadline: now),
      ]),
    );
    timedOut.activate();
    timedOut.onFencedTick();
    await _drainAsync();
    expect(timeoutTransport.names, contains(kRelayTimeoutFlare));
    expect(timeoutTransport.names, contains(kRelayCapacityFlare));
    expect(
      timeoutTransport.names.where((name) => name == kRelayTimeoutFlare),
      hasLength(1),
    );
    expect(
      timeoutTransport.names.where((name) => name == kRelayCapacityFlare),
      hasLength(1),
    );
    timedOut.onFencedTick();
    await _drainAsync();
    expect(timeoutTransport.names, hasLength(2));
    hanging.complete(
      const RelayVerdict.absorb(nextHorizon: Duration(hours: 1)),
    );
    await _drainAsync();
    expect(horizonWrites, isEmpty, reason: 'a late verdict is quarantined');

    final throwingTransport = _ThrowingTransport();
    final transportLoss = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      transport: throwingTransport,
      clock: () => now,
    );
    addTearDown(transportLoss.dispose);
    transportLoss.refresh(
      _snapshot([_session('state-transport', 'work-transport', deadline: now)]),
    );
    transportLoss.activate();
    expect(transportLoss.onFencedTick, returnsNormally);
    expect(throwingTransport.calls, 1);
  });

  test(
    'invalid verdicts and failed horizon writes flare as relay errors',
    () async {
      final now = DateTime.utc(2026, 9, 12, 12);
      for (final verdict in <RelayVerdict>[
        const RelayVerdict.absorb(nextHorizon: Duration.zero),
        const RelayVerdict.escalate(reason: '  '),
      ]) {
        final transport = _RecordingTransport();
        final liveness = WorkSessionLiveness(
          writeHorizon: (_, _) async {},
          transport: transport,
          clock: () => now,
        );
        liveness.mountRelay(observer: _FakeRelayObserver(verdict), ceiling: 1);
        liveness.refresh(
          _snapshot([_session('state-invalid', 'work-invalid', deadline: now)]),
        );
        liveness.activate();
        liveness.onFencedTick();
        await _drainAsync();
        expect(transport.names, [kRelayErrorFlare]);
        liveness.dispose();
      }

      final writeTransport = _RecordingTransport();
      final writeFailure = WorkSessionLiveness(
        writeHorizon: (_, _) => Future<void>.error(StateError('write failed')),
        transport: writeTransport,
        clock: () => now,
      );
      addTearDown(writeFailure.dispose);
      writeFailure.mountRelay(
        observer: _FakeRelayObserver(
          const RelayVerdict.absorb(nextHorizon: Duration(hours: 1)),
        ),
        ceiling: 1,
      );
      writeFailure.refresh(
        _snapshot([_session('state-write', 'work-write', deadline: now)]),
      );
      writeFailure.activate();
      writeFailure.onFencedTick();
      writeFailure.onFencedTick();
      await _drainAsync();
      expect(writeTransport.names, [kRelayErrorFlare]);
    },
  );

  test('relay registration validates ceiling and is identity-bound', () {
    final liveness = WorkSessionLiveness(writeHorizon: (_, _) async {});
    addTearDown(liveness.dispose);
    final observer = _FakeRelayObserver(
      const RelayVerdict.escalate(reason: 'unused'),
    );
    expect(
      () => liveness.mountRelay(observer: observer, ceiling: 0),
      throwsArgumentError,
    );
    final first = liveness.mountRelay(observer: observer, ceiling: 1);
    expect(
      () => liveness.mountRelay(observer: observer, ceiling: 1),
      throwsStateError,
    );
    first.dispose();
    first.dispose();
    final second = liveness.mountRelay(observer: observer, ceiling: 1);
    first.dispose();
    second.dispose();
  });

  test('refresh includes paused and surplus live sessions', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    final observer = _FakeRelayObserver(
      const RelayVerdict.escalate(reason: 'seen'),
    );
    final liveness = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      clock: () => now,
    );
    addTearDown(liveness.dispose);
    liveness.mountRelay(observer: observer, ceiling: 2);
    final paused = _session(
      'state-paused',
      'work-1',
      deadline: now,
    ).copyWith(pauseState: SessionPauseState.paused);
    final surplus = _session('state-surplus', 'work-1', deadline: now);
    liveness.refresh(
      _snapshot(
        [paused],
        surplus: {
          'work-1': [surplus],
        },
      ),
    );
    liveness.activate();
    liveness.onFencedTick();
    expect(observer.observations.map((observation) => observation.sessionId), [
      'state-paused',
      'state-surplus',
    ]);
  });

  test('AC-4 relay capacity is independent of work slots', () {
    final now = DateTime.utc(2026, 9, 12, 12);
    final runner = RecordingBdRunner();
    final services = StationServices(
      provider: FakeRuntimeProvider(),
      writer: _writer(runner),
      stateSubstation: 'tg',
      maxConcurrentWork: 1,
    );
    addTearDown(services.dispose);
    final owner = _workBead('tg-a');
    final waiter = _workBead('tg-b');
    final live = _session('tg-session-a', owner.id, deadline: now);
    final snapshot = _snapshot([live], workBeads: [owner, waiter]);
    const config = SubstationConfig(
      substationId: 'tg',
      ownedSubstations: {'tg'},
      maxConcurrentWork: 1,
    );
    final batch = services.admission
        .admitPending(snapshot, config, const ServiceBundle(), [
          StationAdmissionCandidate(bead: owner, session: live),
          StationAdmissionCandidate(bead: waiter, session: null),
        ]);
    expect(batch.admitted.single.candidate.bead.id, owner.id);
    expect(batch.waiting.single.bead.id, waiter.id);
    final before = services.admission.admissionStatus;

    final pending = Completer<RelayVerdict>();
    final observer = _FakeRelayObserver.from((_) => pending.future);
    final liveness = WorkSessionLiveness(
      writeHorizon: (_, _) async {},
      clock: () => now,
      timeout: (operation, _) => operation,
    );
    addTearDown(() {
      liveness.dispose();
      if (!pending.isCompleted) {
        pending.complete(const RelayVerdict.escalate(reason: 'test teardown'));
      }
    });
    liveness.mountRelay(observer: observer, ceiling: 1);
    liveness.refresh(snapshot);
    liveness.activate();
    liveness.onFencedTick();

    expect(observer.observations, hasLength(1));
    final after = services.admission.admissionStatus;
    expect(after.maxAgents, before.maxAgents);
    expect(after.reservations, before.reservations);
    expect(after.refusals, before.refusals);
    expect(after.zeroAdmissionWaiters, before.zeroAdmissionWaiters);
    expect(batch.waiting.single.bead.id, waiter.id);
    expect(runner.calls, isEmpty);
  });
}

final class _FakeRelayObserver implements RelayObserver {
  _FakeRelayObserver(RelayVerdict verdict)
    : this.from((_) => Future<RelayVerdict>.value(verdict));

  _FakeRelayObserver.from(this._observe);

  final Future<RelayVerdict> Function(RelayObservation) _observe;
  final List<RelayObservation> observations = <RelayObservation>[];

  @override
  Future<RelayVerdict> observe(RelayObservation observation) {
    observations.add(observation);
    return _observe(observation);
  }
}

final class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  List<String> get names => [for (final flare in flares) flare.name];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map<String, String>.of(data)));
  }
}

final class _ThrowingTransport implements ExplorationTransport {
  int calls = 0;

  @override
  void flare(String name, Map<String, String> data) {
    calls += 1;
    throw StateError('controlled transport loss');
  }
}

StationBeadWriter _writer(RecordingBdRunner runner) => StationBeadWriter(
  bd: BdCliService(runner),
  reader: runner,
  ownership: BeadOwnershipPredicate(const {'state', 'tg'}),
);

SessionProjection _session(
  String sessionId,
  String workBeadId, {
  DateTime? startedAt,
  DateTime? deadline,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  startedAt: startedAt,
  relayNextObservationAt: deadline,
);

Bead _workBead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _snapshot(
  List<SessionProjection> sessions, {
  Map<String, List<SessionProjection>> surplus = const {},
  List<Bead> workBeads = const [],
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: workBeads,
    dependencies: const [],
    readyIds: {for (final bead in workBeads) bead.id},
    capturedAt: DateTime.utc(2026, 9, 12),
  ),
  sessionsByWorkBead: {
    for (final session in sessions) session.workBeadId: session,
  },
  surplusSessionsByWorkBead: surplus,
);

Future<void> _drainAsync() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
