import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart' hide SubstationConfig;
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final class _AckSink implements TrajectoryAckRecordSink {
  _AckSink({List<TrajectoryAppendResult>? results, this.onAppend})
    : results = results ?? [const TrajectoryAppendResult.acked()];

  final List<TrajectoryAppendResult> results;
  final Future<TrajectoryAppendResult> Function(TrajectoryRecord record)?
  onAppend;
  final List<TrajectoryRecord> enqueued = <TrajectoryRecord>[];
  final List<TrajectoryRecord> acknowledged = <TrajectoryRecord>[];

  @override
  bool accepting = true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => enqueued.add(record);

  @override
  Future<TrajectoryAppendResult> appendAcked(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
    required bool decisionBearing,
  }) async {
    acknowledged.add(record);
    final callback = onAppend;
    if (callback != null) return callback(record);
    return results.removeAt(0);
  }
}

final class _Transport implements ExplorationTransport {
  _Transport({this.throws = false});

  final bool throws;
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) {
    if (throws) throw StateError('controlled transport failure');
    flares.add((name: name, data: data));
  }
}

GraphSnapshot _snapshot(Iterable<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.utc(2026, 9, 14),
);

Bead _session(
  String id,
  String workKey, {
  BeadStatus status = BeadStatus.open,
}) => Bead(
  id: id,
  issueType: GridIssueTypes.session,
  status: status,
  metadata: {SessionBeadKeys.workBead: workKey},
);

Bead _work(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joined(Bead work, {SessionProjection? session}) =>
    JoinedSnapshot(
      graph: _snapshot([work]),
      sessionsByWorkBead: session == null ? const {} : {work.id: session},
    );

const _config = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
  maxConcurrentWork: 1,
);

Future<void> _pump() => Future<void>.delayed(Duration.zero);

({
  StationServices services,
  StationTrajectoryRecorder recorder,
  RecordingBdRunner runner,
  FakeRuntimeProvider provider,
  _AckSink sink,
  StationAttemptLivenessRecovery adapter,
})
_build({
  required GraphSnapshot Function() snapshot,
  _AckSink? sink,
  _Transport? transport,
}) {
  final runner = RecordingBdRunner();
  final provider = FakeRuntimeProvider();
  final resolvedSink = sink ?? _AckSink();
  final recorder = StationTrajectoryRecorder(
    sink: resolvedSink,
    substationPrefixes: const {'tg'},
  );
  final writer = StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {'tg'}),
  );
  final halt = TrajectoryAdmissionHalt(
    writer: writer,
    stateSubstation: 'tg',
    bootEpoch: () => 79,
  );
  final services = StationServices(
    provider: provider,
    writer: writer,
    stateSubstation: 'tg',
    trajectoryAdmissionHalt: halt,
    trajectoryRecorder: recorder,
  );
  final adapter = StationAttemptLivenessRecovery(
    services: () => services,
    snapshot: snapshot,
    recorder: recorder,
    transportServices: ServiceBundle(transport: transport),
  );
  return (
    services: services,
    recorder: recorder,
    runner: runner,
    provider: provider,
    sink: resolvedSink,
    adapter: adapter,
  );
}

void main() {
  test(
    'is inert until activated and then re-reads fresh session state',
    () async {
      var snapshot = _snapshot(const []);
      final h = _build(snapshot: () => snapshot);
      addTearDown(h.services.dispose);
      addTearDown(h.provider.close);

      await h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: 'tg-work',
      );
      h.adapter.activate();
      h.adapter.activate();
      await h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: 'tg-work',
      );
      expect(h.runner.calls, isEmpty);
      expect(h.sink.acknowledged, isEmpty);

      snapshot = _snapshot([_session('tg-session', 'tg-work')]);
      await h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: 'tg-work',
      );

      expect(
        h.runner
            .callsFor('update')
            .where(
              (call) => call.contains(
                '${SessionBeadKeys.voidedReason}=attempt-liveness-lost',
              ),
            ),
        hasLength(1),
      );
      expect(h.runner.callsFor('close'), hasLength(1));
      final terminal = h.sink.acknowledged.single as AttemptTerminal;
      expect(terminal.attemptId, 'attempt-1');
      expect(terminal.sessionId, 'tg-session');
      expect(terminal.workBeadId, 'tg-work');
      expect(terminal.outcome, TerminalOutcome.lost);
      final retired = h.sink.enqueued.single as AttemptRoundRetired;
      expect(retired.oldRound, 0);
      expect(retired.newRound, 1);
      expect(retired.cause, RoundRetireCause.voided);
    },
  );

  test('stops descendants and emits the loss flare after acknowledged '
      'retirement', () async {
    final transport = _Transport();
    final h = _build(
      snapshot: () => _snapshot([_session('tg-session', 'tg-work')]),
      transport: transport,
    );
    addTearDown(h.services.dispose);
    addTearDown(h.provider.close);
    await h.provider.start(
      'tg-session/tg-work/agent',
      const RuntimeConfig(workDir: '/tmp', command: 'sh'),
    );
    await h.provider.start(
      'tg-session/tg-work/verify',
      const RuntimeConfig(workDir: '/tmp', command: 'sh'),
    );
    h.adapter.activate();

    await h.adapter.handle(
      attemptId: 'attempt-1',
      sessionId: 'tg-session',
      workBeadId: 'tg-work',
    );

    expect(h.provider.stopped, [
      'tg-session/tg-work/agent',
      'tg-session/tg-work/verify',
    ]);
    expect(transport.flares.single.name, 'attempt.liveness.lost');
    expect(transport.flares.single.data, {
      'workBeadId': 'tg-work',
      'sessionId': 'tg-session',
      'attemptId': 'attempt-1',
    });
  });

  test(
    'liveness retirement releases capacity but fences a successor create',
    () async {
      final acknowledgementEntered = Completer<void>();
      final releaseAcknowledgement = Completer<TrajectoryAppendResult>();
      final sink = _AckSink(
        onAppend: (record) {
          acknowledgementEntered.complete();
          return releaseAcknowledgement.future;
        },
      );
      final work = _work('tg-work');
      var state = _snapshot([_session('tg-session', work.id)]);
      final h = _build(snapshot: () => state, sink: sink);
      addTearDown(h.services.dispose);
      addTearDown(h.provider.close);
      addTearDown(() {
        if (!releaseAcknowledgement.isCompleted) {
          releaseAcknowledgement.complete(const TrajectoryAppendResult.acked());
        }
      });
      const predecessor = SessionProjection(
        workBeadId: 'tg-work',
        sessionId: 'tg-session',
      );
      final liveJoined = _joined(work, session: predecessor);
      final adopted = h.services.admission.admitPending(
        liveJoined,
        _config,
        const ServiceBundle(),
        [StationAdmissionCandidate(bead: work, session: predecessor)],
      );
      expect(adopted.admitted.single.sessionId, 'tg-session');
      h.adapter.activate();

      final retirement = h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: work.id,
      );
      await acknowledgementEntered.future;

      expect(h.runner.callsFor('close'), hasLength(1));
      expect(h.services.admission.admissionStatus.reservations, isEmpty);

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );

      state = _snapshot([
        _session(
          'tg-session',
          voidKeyFor(work.id, 'tg-session'),
          status: BeadStatus.closed,
        ),
      ]);
      final successorJoined = _joined(work);
      final successor = StationAdmissionCandidate(bead: work, session: null);
      final admitted = h.services.admission.admitPending(
        successorJoined,
        _config,
        const ServiceBundle(),
        [successor],
      );
      expect(admitted.admitted, hasLength(1));
      final create = h.services.admission.createSessionAttempt(
        successorJoined,
        successor,
        title: 'grid session ${work.id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      await _pump();
      expect(
        h.runner
            .callsFor('create')
            .where((call) => call.contains(GridIssueTypes.session.wire)),
        isEmpty,
      );

      releaseAcknowledgement.complete(const TrajectoryAppendResult.acked());
      await retirement;
      final created = await create;

      expect(created.refusal, isNull);
      expect(created.sessionId, isNotNull);
      expect(
        h.runner
            .callsFor('create')
            .where((call) => call.contains(GridIssueTypes.session.wire)),
        hasLength(1),
      );
    },
  );

  test('a dropped terminal latches the halt and retries an already-void row '
      'without losing its original rework round', () async {
    var snapshot = _snapshot([_session('tg-session', 'tg-work#r2')]);
    final sink = _AckSink(
      results: [
        const TrajectoryAppendResult.dropped(),
        const TrajectoryAppendResult.acked(),
      ],
    );
    final h = _build(snapshot: () => snapshot, sink: sink);
    addTearDown(h.services.dispose);
    addTearDown(h.provider.close);
    h.adapter.activate();

    await expectLater(
      h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: 'tg-work',
      ),
      throwsStateError,
    );
    expect(h.services.trajectoryAdmissionHalt!.halted, isTrue);
    expect(h.sink.enqueued, isEmpty, reason: 'no round retires without an ack');
    final voidUpdates = h.runner
        .callsFor('update')
        .where(
          (call) => call.contains(
            '${SessionBeadKeys.voidedReason}=attempt-liveness-lost',
          ),
        )
        .length;
    final closes = h.runner.callsFor('close').length;

    snapshot = _snapshot([
      _session(
        'tg-session',
        voidKeyFor('tg-work', 'tg-session'),
        status: BeadStatus.closed,
      ),
    ]);
    await h.adapter.handle(
      attemptId: 'attempt-1',
      sessionId: 'tg-session',
      workBeadId: 'tg-work',
    );

    expect(
      h.runner
          .callsFor('update')
          .where(
            (call) => call.contains(
              '${SessionBeadKeys.voidedReason}=attempt-liveness-lost',
            ),
          ),
      hasLength(voidUpdates + 1),
    );
    expect(h.runner.callsFor('close'), hasLength(closes + 1));
    expect(h.sink.acknowledged, hasLength(2));
    final retired = h.sink.enqueued.single as AttemptRoundRetired;
    expect(retired.oldRound, 2);
    expect(retired.newRound, 3);
  });

  test('malformed, mismatched, and closed non-void rows are inert', () async {
    final cases = <Bead>[
      Bead(id: 'tg-session', issueType: IssueType.task),
      _session('tg-session', 'other-work'),
      _session('tg-session', 'tg-work#r02'),
      _session('tg-session', 'tg-work', status: BeadStatus.closed),
    ];
    for (final session in cases) {
      final h = _build(snapshot: () => _snapshot([session]));
      addTearDown(h.services.dispose);
      addTearDown(h.provider.close);
      h.adapter.activate();

      await h.adapter.handle(
        attemptId: 'attempt-1',
        sessionId: 'tg-session',
        workBeadId: 'tg-work',
      );

      expect(h.runner.calls, isEmpty);
      expect(h.sink.acknowledged, isEmpty);
    }
  });

  test('a throwing observability transport cannot undo retirement', () async {
    final h = _build(
      snapshot: () => _snapshot([_session('tg-session', 'tg-work')]),
      transport: _Transport(throws: true),
    );
    addTearDown(h.services.dispose);
    addTearDown(h.provider.close);
    h.adapter.activate();

    await h.adapter.handle(
      attemptId: 'attempt-1',
      sessionId: 'tg-session',
      workBeadId: 'tg-work',
    );

    expect(h.runner.callsFor('close'), hasLength(1));
    expect(h.sink.enqueued.single, isA<AttemptRoundRetired>());
  });
}
