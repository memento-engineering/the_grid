import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final class _AckSink implements TrajectoryAckRecordSink {
  _AckSink({List<TrajectoryAppendResult>? results})
    : results = results ?? [const TrajectoryAppendResult.acked()];

  final List<TrajectoryAppendResult> results;
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
  );
  final resolvedSink = sink ?? _AckSink();
  final recorder = StationTrajectoryRecorder(
    sink: resolvedSink,
    substationPrefixes: const {'tg'},
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
    final updates = h.runner.callsFor('update').length;
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

    expect(h.runner.callsFor('update'), hasLength(updates));
    expect(h.runner.callsFor('close'), hasLength(closes));
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
