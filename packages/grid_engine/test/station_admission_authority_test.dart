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

Future<void> _pump() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
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

    const voided = StationMintVoided(
      workBeadId: 'tg-1',
      retiredSessionId: 'tgdog-s1',
    );
    expect(voided.workBeadId, 'tg-1');
    expect(voided.retiredSessionId, 'tgdog-s1');
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

      expect(first.admitted, isEmpty);
      expect(first.waiting.map((candidate) => candidate.bead.id), [
        'tg-a',
        'tg-b',
        'tg-z',
      ]);
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
    'a failed durable attempt releases, flares, and invalidates once after standard backoff',
    () async {
      final runner = _FailingMountAttemptRunner();
      final authority = StationAdmissionAuthority(
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {'tg'}),
        ),
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
      expect(writing.admitted, isEmpty);
      expect(writing.waiting.single.bead.id, bead.id);
      await _pump();

      expect(transport.flares.single.name, 'work.mountAttemptRecordFailed');
      expect(transport.flares.single.data['beadId'], bead.id);
      expect(notifications, 0, reason: 'failure waits for standard backoff');
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
      expect(notifications, 1);

      authority.admitPending(snapshot, _config, services, [candidate]);
      await _pump();
      final admitted = authority.admitPending(snapshot, _config, services, [
        candidate,
      ]);
      expect(admitted.admitted.single.candidate.bead.id, bead.id);
    },
  );
}
