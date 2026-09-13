import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

final class _SequentialSessionRunner extends RecordingBdRunner {
  _SequentialSessionRunner(this._sessionIds);

  final List<String> _sessionIds;
  var _nextSession = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final recorded = await super.run(args, timeout: timeout, stdin: stdin);
    final typeIndex = args.indexOf('--type');
    final createsSession =
        args.isNotEmpty &&
        args.first == 'create' &&
        typeIndex >= 0 &&
        typeIndex + 1 < args.length &&
        args[typeIndex + 1] == GridIssueTypes.session.wire;
    if (!createsSession) return recorded;
    final id = _sessionIds[_nextSession];
    _nextSession += 1;
    return BdResult(
      exitCode: 0,
      stdout: jsonEncode({
        'schema_version': 1,
        'data': {'id': id},
      }),
      stderr: '',
    );
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
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: {for (final bead in beads) bead.id},
    capturedAt: DateTime.utc(2026, 9, 13),
  ),
  sessionsByWorkBead: sessions,
);

const _config = SubstationConfig(
  substationId: 'a',
  ownedSubstations: {'a'},
  maxConcurrentWork: 1,
);

StationAdmissionAuthority _authority(
  RecordingBdRunner runner,
  FakeRuntimeProvider provider,
) => StationAdmissionAuthority(
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {'a'}),
  ),
  provider: provider,
  stateSubstation: 'a',
  maxConcurrentWork: 1,
);

Future<void> _pump() async {
  for (var i = 0; i < 12; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

({StationAdmissionBatch batch, Set<String> charges}) _capture(
  StationAdmissionAuthority authority,
  JoinedSnapshot snapshot,
  StationAdmissionBatch batch,
) {
  final charges = <String>{
    for (final row in snapshot.sessionsByWorkBead.values)
      if (!row.isTerminal &&
          row.pauseState != SessionPauseState.paused &&
          row.sessionId != null &&
          row.sessionId!.isNotEmpty)
        row.sessionId!,
  };
  for (final reservation in authority.admissionStatus.reservations) {
    final sessionId = reservation.sessionId;
    if (sessionId != null) {
      charges.add(sessionId);
      continue;
    }
    final predecessor = snapshot.sessionsByWorkBead[reservation.bead];
    final reclaimsOpenPredecessor =
        predecessor != null &&
        !predecessor.isTerminal &&
        predecessor.pauseState != SessionPauseState.paused &&
        predecessor.sessionId != null &&
        predecessor.sessionId!.isNotEmpty &&
        reworkRoundOf(reservation.bead, predecessor.workBeadId) != null;
    charges.add(
      reclaimsOpenPredecessor
          ? predecessor.sessionId!
          : 'reservation:${reservation.bead}',
    );
  }
  return (batch: batch, charges: charges);
}

void main() {
  test('an open gated durable session holds the station slot', () async {
    final runner = RecordingBdRunner(createdId: 'a-session');
    final provider = FakeRuntimeProvider();
    final authority = _authority(runner, provider);
    addTearDown(authority.dispose);
    addTearDown(provider.close);

    final owner = _bead('a-owner');
    final waiter = _bead('a-waiter', priority: 0);
    final ownerCandidate = StationAdmissionCandidate(
      bead: owner,
      session: null,
    );
    final initial = _snapshot([owner]);
    authority.admitPending(initial, _config, const ServiceBundle(), [
      ownerCandidate,
    ]);
    final created = await authority.createSessionAttempt(
      initial,
      ownerCandidate,
      title: 'grid session ${owner.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );

    final gated = SessionProjection(
      workBeadId: owner.id,
      sessionId: created.sessionId,
      openGateNodes: const {'gate-a'},
    );
    final joined = _snapshot([owner, waiter], sessions: {owner.id: gated});
    final transport = _RecordingTransport();
    final batch = authority
        .admitPending(joined, _config, ServiceBundle(transport: transport), [
          StationAdmissionCandidate(bead: owner, session: gated),
          StationAdmissionCandidate(bead: waiter, session: null),
        ]);

    expect(batch.admitted.map((entry) => entry.candidate.bead.id), [owner.id]);
    expect(batch.waiting.single.bead.id, waiter.id);
    final throttled = transport.flares.singleWhere(
      (flare) => flare.name == 'work.throttled',
    );
    expect(throttled.data['beadIds'], waiter.id);
  });

  test('closed held and done sessions hold no station slot', () async {
    final owner = _bead('a-owner');
    final waiter = _bead('a-waiter', priority: 0);
    final cases = <({String clause, SessionProjection session})>[
      (
        clause: 'held',
        session: SessionProjection(
          workBeadId: owner.id,
          sessionId: 'a-held',
          isTerminal: true,
          humanHeld: true,
        ),
      ),
      (
        clause: 'done',
        session: SessionProjection(
          workBeadId: owner.id,
          sessionId: 'a-done',
          isTerminal: true,
          completed: true,
        ),
      ),
    ];

    for (final terminalCase in cases) {
      final runner = RecordingBdRunner();
      final provider = FakeRuntimeProvider();
      final authority = _authority(runner, provider);
      try {
        final joined = _snapshot(
          [owner, waiter],
          sessions: {owner.id: terminalCase.session},
        );
        final batch = authority
            .admitPending(joined, _config, const ServiceBundle(), [
              StationAdmissionCandidate(
                bead: owner,
                session: terminalCase.session,
              ),
              StationAdmissionCandidate(bead: waiter, session: null),
            ]);

        expect(batch.admitted.single.candidate.bead.id, waiter.id);
        expect(batch.refused.single.candidate.bead.id, owner.id);
        expect(batch.refused.single.clause, terminalCase.clause);
        await _pump();
      } finally {
        authority.dispose();
        await provider.close();
      }
    }
  });

  test(
    'retired-open rework preserves one charged slot through remint',
    () async {
      final runner = _SequentialSessionRunner(['a-session-1', 'a-session-2']);
      final provider = FakeRuntimeProvider();
      final authority = _authority(runner, provider);
      addTearDown(authority.dispose);
      addTearDown(provider.close);

      final owner = _bead('a-owner');
      final waiter = _bead('a-waiter', priority: 0);
      final ownerCandidate = StationAdmissionCandidate(
        bead: owner,
        session: null,
      );
      final initialSnapshot = _snapshot([owner]);
      final initialPass = _capture(
        authority,
        initialSnapshot,
        authority.admitPending(
          initialSnapshot,
          _config,
          const ServiceBundle(),
          [ownerCandidate],
        ),
      );
      final firstCreated = await authority.createSessionAttempt(
        initialSnapshot,
        ownerCandidate,
        title: 'grid session ${owner.id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      final firstSessionId = firstCreated.sessionId!;

      final openSession = SessionProjection(
        workBeadId: owner.id,
        sessionId: firstSessionId,
        openGateNodes: const {'gate-a'},
      );
      final openSnapshot = _snapshot(
        [owner, waiter],
        sessions: {owner.id: openSession},
      );
      final openPass = _capture(
        authority,
        openSnapshot,
        authority.admitPending(openSnapshot, _config, const ServiceBundle(), [
          StationAdmissionCandidate(bead: owner, session: openSession),
          StationAdmissionCandidate(bead: waiter, session: null),
        ]),
      );

      final rekeyedSession = openSession.copyWith(workBeadId: '${owner.id}#r1');
      final rekeyedCandidate = StationAdmissionCandidate(
        bead: owner,
        session: rekeyedSession,
      );
      final rekeyedSnapshot = _snapshot(
        [owner, waiter],
        sessions: {owner.id: rekeyedSession},
      );
      final rekeyedPass = _capture(
        authority,
        rekeyedSnapshot,
        authority.admitPending(
          rekeyedSnapshot,
          _config,
          const ServiceBundle(),
          [
            rekeyedCandidate,
            StationAdmissionCandidate(bead: waiter, session: null),
          ],
        ),
      );

      await authority.closeRetiredReworkSession(
        workBeadId: owner.id,
        sessionId: firstSessionId,
        reapMolecule: false,
        services: const ServiceBundle(),
      );
      final closedPredecessor = rekeyedSession.copyWith(isTerminal: true);
      final closedCandidate = StationAdmissionCandidate(
        bead: owner,
        session: closedPredecessor,
      );
      final closedSnapshot = _snapshot(
        [owner, waiter],
        sessions: {owner.id: closedPredecessor},
      );
      final closedPass = _capture(
        authority,
        closedSnapshot,
        authority.admitPending(closedSnapshot, _config, const ServiceBundle(), [
          closedCandidate,
          StationAdmissionCandidate(bead: waiter, session: null),
        ]),
      );

      final reminted = await authority.createSessionAttempt(
        closedSnapshot,
        closedCandidate,
        title: 'grid session ${owner.id}',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      final successor = SessionProjection(
        workBeadId: owner.id,
        sessionId: reminted.sessionId,
      );
      final successorSnapshot = _snapshot(
        [owner, waiter],
        sessions: {owner.id: successor},
      );
      final successorPass = _capture(
        authority,
        successorSnapshot,
        authority
            .admitPending(successorSnapshot, _config, const ServiceBundle(), [
              StationAdmissionCandidate(bead: owner, session: successor),
              StationAdmissionCandidate(bead: waiter, session: null),
            ]),
      );

      expect(
        closedPass.batch.admitted.map((entry) => entry.candidate.bead.id),
        [owner.id],
        reason: 'the higher-priority waiter cannot take the reclaimed slot',
      );
      expect(closedPass.batch.waiting.single.bead.id, waiter.id);
      expect(
        rekeyedPass.batch.admitted.single.sessionId,
        isNull,
        reason: 'the re-key pass installs a pre-session successor',
      );
      expect(
        rekeyedPass.batch.admitted.single.reservationToken,
        same(closedPass.batch.admitted.single.reservationToken),
        reason: 'closing the predecessor preserves the successor reservation',
      );
      expect(reminted.sessionId, 'a-session-2');
      expect(
        [
          openPass,
          rekeyedPass,
          closedPass,
          successorPass,
        ].map((pass) => pass.batch.waiting.single.bead.id),
        everyElement(waiter.id),
      );
      expect(
        [
          initialPass,
          openPass,
          rekeyedPass,
          closedPass,
          successorPass,
        ].map((pass) => pass.charges.length),
        everyElement(lessThanOrEqualTo(1)),
      );
    },
  );
}
