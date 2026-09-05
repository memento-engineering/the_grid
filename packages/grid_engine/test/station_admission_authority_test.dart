import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

final class _FailingMountAttemptRunner extends RecordingBdRunner {
  var failNextAttemptUpdate = true;

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (failNextAttemptUpdate &&
        args.isNotEmpty &&
        args.first == 'update' &&
        args.any((arg) => arg.contains(MountAttemptKeys.count))) {
      failNextAttemptUpdate = false;
      throw StateError('controlled mount-attempt failure');
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _TimeoutFirstMoleculeReader implements BeadProbeReader {
  _TimeoutFirstMoleculeReader(this.delegate)
    : error = TimeoutException('Future not completed');

  final BeadProbeReader delegate;
  final TimeoutException error;
  var _thrown = false;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (!_thrown && types.contains(GridIssueTypes.molecule)) {
      _thrown = true;
      throw error;
    }
    return delegate.openBeads(
      types: types,
      metadataAll: metadataAll,
      metadataAny: metadataAny,
    );
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) =>
      delegate.openSuperseding(priorIds);
}

final class _GatedCloseRunner extends RecordingBdRunner {
  _GatedCloseRunner({super.createdId, super.eventLog});

  final closeEntered = Completer<void>();
  final releaseClose = Completer<void>();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.isNotEmpty && args.first == 'close') {
      if (!closeEntered.isCompleted) closeEntered.complete();
      await releaseClose.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

final class _FailingCloseRunner extends RecordingBdRunner {
  _FailingCloseRunner({super.createdId});

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (args.isNotEmpty && args.first == 'close') {
      throw StateError('controlled close failure');
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

JoinedSnapshot _snapshot(
  List<Bead> beads, {
  Map<String, SessionProjection> sessions = const {},
  Map<String, List<SessionProjection>> surplus = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: {for (final bead in beads) bead.id},
    capturedAt: DateTime.utc(2026, 9, 4),
  ),
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
    'a failed durable attempt invalidates immediately and after standard backoff',
    () async {
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
      expect(
        authority
            .admitPending(snapshot, _config, services, [candidate])
            .waiting
            .single
            .bead
            .id,
        bead.id,
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
      final reader = _TimeoutFirstMoleculeReader(runner);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(
        runner,
        reader: reader,
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
              .having((error) => error.cause, 'cause', same(reader.error))
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

      await _pump();
      final beforeBackoff = invalidations;
      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      expect(invalidations, beforeBackoff + 1);
    },
  );

  test(
    'failed timeout close retains capacity and schedules no retry',
    () async {
      final runner = _FailingCloseRunner(createdId: 'tg-s1');
      final reader = _TimeoutFirstMoleculeReader(runner);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _stationOver(
        runner,
        reader: reader,
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

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      expect(invalidations, beforeTimeout);
    },
  );

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
          services: const ServiceBundle(),
        ),
        isNull,
      );
      expect(
        await station.admission.abandonSessionAttempt(
          workBeadId: 'tg-1',
          sessionId: 'tg-stale',
          services: const ServiceBundle(),
        ),
        isNull,
      );
      expect(runner.callsFor('close'), isEmpty);

      expect(
        await station.admission.abandonSessionAttempt(
          workBeadId: 'tg-1',
          sessionId: owned.sessionId,
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
      provider.releaseStop.complete();
      await _waitUntil(
        () => transport.flares.any(
          (flare) => flare.name == 'work.sessionSurplusRetired',
        ),
      );

      expect(provider.stopped, ['tg-rival/tg-1/agent', 'tg-rival/tg-1/verify']);
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

      final stale = station.admission.admitPending(
        duplicate,
        _config,
        services,
        [candidate],
      );
      expect(stale.refused.single.clause, 'duplicate-live');
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
        hasLength(1),
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
      expect(
        transport.flares.where(
          (flare) => flare.name == 'work.duplicateLiveRefused',
        ),
        hasLength(1),
      );
      expect(
        transport.flares.where(
          (flare) => flare.name == 'work.sessionSurplusAlive',
        ),
        hasLength(1),
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
        hasLength(1),
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
