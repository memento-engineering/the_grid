import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

Bead _bead(String id) => Bead(
  id: id,
  issueType: IssueType.task,
  status: BeadStatus.open,
  priority: 2,
);

JoinedSnapshot _snapshot(
  List<Bead> beads, {
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: {for (final bead in beads) bead.id},
    capturedAt: DateTime.utc(2026, 9, 7, 20, 56, 3),
  ),
  sessionsByWorkBead: sessions,
);

Future<void> _pump() async {
  for (var i = 0; i < 12; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('paused owner release wakes an earlier zero-admission waiter without '
      'ending the session', () async {
    final runner = RecordingBdRunner(createdId: 'a-session');
    final provider = FakeRuntimeProvider();
    final writer = StationBeadWriter(
      bd: BdCliService(runner),
      reader: runner,
      ownership: BeadOwnershipPredicate(const {'a', 'b'}),
    );
    final authority = StationAdmissionAuthority(
      writer: writer,
      provider: provider,
      stateSubstation: 'a',
      maxConcurrentWork: 1,
    );
    addTearDown(authority.dispose);
    addTearDown(provider.close);

    final owner = _bead('a-1');
    final waiter = _bead('b-1');
    final ownerCandidate = StationAdmissionCandidate(
      bead: owner,
      session: null,
    );
    const ownerConfig = SubstationConfig(
      substationId: 'a',
      ownedSubstations: {'a'},
      maxConcurrentWork: 1,
    );
    const waiterConfig = SubstationConfig(
      substationId: 'b',
      ownedSubstations: {'b'},
      maxConcurrentWork: 1,
    );
    final setupSnapshot = _snapshot([owner]);
    final reserved = authority.admitPending(
      setupSnapshot,
      ownerConfig,
      const ServiceBundle(),
      [ownerCandidate],
    );
    expect(reserved.admitted.single.candidate.bead.id, owner.id);
    final created = await authority.createSessionAttempt(
      setupSnapshot,
      ownerCandidate,
      title: 'grid session ${owner.id}',
      metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
    );
    expect(created.sessionId, 'a-session');
    await _pump();

    final setupCallCount = runner.calls.length;
    final pausedOwner = SessionProjection(
      workBeadId: owner.id,
      sessionId: created.sessionId,
      pauseState: SessionPauseState.paused,
    );
    final joined = _snapshot(
      [owner, waiter],
      sessions: {owner.id: pausedOwner},
    );
    final waiterCandidate = StationAdmissionCandidate(
      bead: waiter,
      session: null,
    );

    final initiallyBlocked = authority.admitPending(
      joined,
      waiterConfig,
      const ServiceBundle(),
      [waiterCandidate],
    );
    expect(initiallyBlocked.admitted, isEmpty);
    expect(initiallyBlocked.waiting.single.bead.id, waiter.id);

    var invalidations = 0;
    var releaseCallCount = -1;
    StationAdmissionBatch? retried;
    late void Function() removeInvalidationListener;
    removeInvalidationListener = authority.addInvalidationListener(() {
      removeInvalidationListener();
      invalidations += 1;
      releaseCallCount = runner.calls.length;
      retried = authority.admitPending(
        joined,
        waiterConfig,
        const ServiceBundle(),
        [waiterCandidate],
      );
    });

    final paused = authority.admitPending(
      joined,
      ownerConfig,
      const ServiceBundle(),
      [StationAdmissionCandidate(bead: owner, session: pausedOwner)],
    );
    expect(paused.admitted, isEmpty);
    expect(paused.refused.single.clause, 'paused');

    await _pump();
    expect(invalidations, 1);
    expect(retried, isNotNull);
    expect(retried!.admitted.single.candidate.bead.id, waiter.id);
    expect(retried!.waiting, isEmpty);

    final pauseReleaseCalls = runner.calls.sublist(
      setupCallCount,
      releaseCallCount,
    );
    expect(pauseReleaseCalls.where((call) => call.first == 'close'), isEmpty);
    expect(
      pauseReleaseCalls.where(
        (call) => call.first == 'update' && call.contains('a-session'),
      ),
      isEmpty,
    );
  });
}
