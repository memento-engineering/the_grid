import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// The worktree-outstanding barrier (cut-wiring §W2.4 W2-B): the clause, its
/// observe-form counting arm, and the `admission.refused` derivation armed at
/// the cut.

// ── the two ambient mirrors, faked ───────────────────────────────────────────

final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    required this.workBeadId,
    this.round = 0,
    this.isOpen = true,
  });

  @override
  final String sessionId;
  @override
  final String workBeadId;
  @override
  final int round;
  @override
  final bool isOpen;

  @override
  SessionHeadOutcome? get outcome =>
      isOpen ? null : SessionHeadOutcome.succeeded;
  @override
  DateTime get startedAt => DateTime.utc(2026, 9, 12, 9);
  @override
  DateTime? get closedAt => isOpen ? null : DateTime.utc(2026, 9, 12, 10);
  @override
  bool get held => false;
  @override
  String? get heldReason => null;
  @override
  String? get workTerminalReason => null;
  @override
  int? get pgid => null;
  @override
  int? get pid => null;
  @override
  String? get attemptId => null;
  @override
  SessionHeadProvenance? get terminalProvenance => null;
  @override
  String? get unknownReason => null;
  @override
  int get lastSeq => 1;
}

final class _Heads implements TrajectoryHeadSnapshot {
  _Heads(this.rows);

  @override
  final List<SessionHeadView> rows;

  @override
  int get version => 1;
  @override
  TrajectorySnapshotHealth get health => TrajectorySnapshotHealth.live;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 9, 12, 9);
  @override
  DateTime? get firstEpochClaimedAt => DateTime.utc(2026, 9, 12, 9);

  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) =>
      throw StateError('the barrier never uses the classification view');
}

final class _Identity implements ProcessIdentityView {
  _Identity({
    required this.sessionId,
    required this.worktree,
    this.worktreeState = 'live',
  });

  @override
  final String sessionId;
  @override
  final String? worktree;
  @override
  final String? worktreeState;
  @override
  String get attemptId => 'att-1';

  @override
  int get round => 0;
  @override
  String get stepPath => 'tg-1/build';
  @override
  int get stepRound => 0;
  @override
  int get incarnation => 0;
  @override
  int? get pid => null;
  @override
  int? get pgid => null;
  @override
  String? get leaseState => null;
  @override
  String? get branch => 'grid/tg-1';
  @override
  String? get baseSha => null;
  @override
  bool? get adoptedExisting => null;
  @override
  String? get predecessorAttemptId => null;
  @override
  int get lastSeq => 1;
}

final class _Identities implements TrajectoryProcessIdentitySnapshot {
  _Identities(
    this.rows, {
    this.lastTickAt,
    this.health = TrajectorySnapshotHealth.live,
  });

  @override
  final List<ProcessIdentityView> rows;
  @override
  final DateTime? lastTickAt;
  @override
  final TrajectorySnapshotHealth health;

  @override
  int get version => 1;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 9, 12, 9);

  @override
  Iterable<ProcessIdentityView> bySessionId(String sessionId) =>
      rows.where((row) => row.sessionId == sessionId);
}

// ── the recorder's sink postures ─────────────────────────────────────────────

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = <TrajectoryRecord>[];
  final List<String?> substations = <String?>[];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    records.add(record);
    substations.add(substation);
  }

  List<String> get types => [for (final record in records) record.recordType];

  List<String> keys({String station = 'tg', int bootEpoch = 7}) => [
    for (final record in records)
      record.idemKeyText(IdemContext(station: station, bootEpoch: bootEpoch)),
  ];
}

/// The LOSS posture: the sink stops accepting, so every observation is counted
/// and dropped. A dropped refusal must not change what the barrier decided.
final class _RefusingSink implements TrajectoryRecordSink {
  @override
  bool get accepting => false;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('a non-accepting sink must never be reached');
}

// ── fixtures ─────────────────────────────────────────────────────────────────

const _workBead = 'tg-1';
final _now = DateTime.utc(2026, 9, 12, 12);

Bead _task([String id = _workBead]) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

WorktreeOutstandingRead _read({
  List<_Identity> identities = const [],
  List<_Head> heads = const [],
  DateTime? lastTickAt,
  TrajectorySnapshotHealth health = TrajectorySnapshotHealth.live,
}) => WorktreeOutstandingRead(
  processIdentities: _Identities(
    identities,
    lastTickAt: lastTickAt ?? _now,
    health: health,
  ),
  heads: _Heads(heads),
);

MountEligibilityDecision _evaluate(
  WorktreeOutstandingRead read, {
  List<SessionProjection> linked = const [],
  bool observeForm = false,
  String? snapshotRev,
  void Function(WorktreeOutstandingFinding)? onFinding,
}) => worktreeOutstandingClause(
  read: read,
  linkedSessionsOf: (_) => linked,
  observeForm: observeForm,
  snapshotRevOf: snapshotRev == null ? null : (_) => snapshotRev,
  onFinding: onFinding,
  clock: () => _now,
)(_task());

void main() {
  group('the clause', () {
    test('refuses a P6 live row whose session is P1-closed', () {
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
        ),
      );

      expect(decision, isA<MountRefused>());
      final clause = (decision as MountRefused).clause;
      expect(clause, startsWith('$kWorktreeOutstandingClause:'));
      expect(clause, contains('s1'));
      expect(clause, contains('/w/tg-1'));
      expect(clause, contains('p1-closed'));
    });

    test(
      'refuses on the LEDGER half while P1 is still open — the heal grace',
      () {
        final decision = _evaluate(
          _read(
            identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
            heads: [_Head(sessionId: 's1', workBeadId: _workBead)],
          ),
          linked: const [
            SessionProjection(
              workBeadId: _workBead,
              sessionId: 's1',
              isTerminal: true,
            ),
          ],
        );

        expect(decision, isA<MountRefused>());
        expect(
          (decision as MountRefused).clause,
          contains('ledger-terminal'),
          reason: 'the OR is what makes the read complete at every instant',
        );
      },
    );

    test('a live row on a RETIRED round still refuses', () {
      // The retired round is invisible on the ledger side — only the P1
      // multiplicity rule (every row for the bead, retired included) can catch
      // it, which is exactly the class the barrier exists for.
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 'r1', worktree: '/w/tg-1-r1')],
          heads: [
            _Head(
              sessionId: 'r1',
              workBeadId: _workBead,
              round: 1,
              isOpen: false,
            ),
            _Head(sessionId: 'r2', workBeadId: _workBead),
          ],
        ),
        linked: const [
          SessionProjection(workBeadId: _workBead, sessionId: 'r2'),
        ],
      );

      expect(decision, isA<MountRefused>());
      expect((decision as MountRefused).clause, contains('r1'));
    });

    test('a candidate with no live P6 row is admitted unchanged', () {
      final decision = _evaluate(
        _read(
          identities: [
            _Identity(
              sessionId: 's1',
              worktree: '/w/tg-1',
              worktreeState: 'reaped',
            ),
          ],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
        ),
      );

      expect(decision, isA<MountEligible>());
    });

    test('a live row under a LIVE session is not the barrier\'s business', () {
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead)],
        ),
        linked: const [
          SessionProjection(workBeadId: _workBead, sessionId: 's1'),
        ],
      );

      expect(decision, isA<MountEligible>());
    });

    test('another bead\'s live row never refuses this candidate', () {
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's9', worktree: '/w/tg-9')],
          heads: [_Head(sessionId: 's9', workBeadId: 'tg-9', isOpen: false)],
        ),
      );

      expect(decision, isA<MountEligible>());
    });

    test('no beat for three tick intervals fails CLOSED', () {
      final decision = _evaluate(
        _read(
          lastTickAt: _now.subtract(
            kWorktreeOutstandingStaleAfter + const Duration(seconds: 1),
          ),
        ),
      );

      expect(decision, isA<MountRefused>());
      expect(
        (decision as MountRefused).clause,
        contains('has not beaten'),
        reason: 'a wedged harness cannot prove the bead is clear',
      );
    });

    test('an IDLE but healthy station admits', () {
      // DISCRIMINATING: the mirror is not empty — it holds a live worktree
      // under a LIVE session, the shape a station at rest actually has — and
      // the beat is one tick old. The clause must clear it on the JOIN (the
      // session is not terminal) rather than on an empty read, and the 90 s
      // grace must not trip on a quiet station.
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead)],
          lastTickAt: _now.subtract(const Duration(seconds: 30)),
        ),
        linked: const [
          SessionProjection(workBeadId: _workBead, sessionId: 's1'),
        ],
      );

      expect(decision, isA<MountEligible>());
    });

    test('a COMPROMISED mirror does NOT disarm the barrier', () {
      // THE FAIL-OPEN THAT MUST NOT EXIST. `_latchMirrorCompromised` is
      // reached from the mode latch, the fence-out, the halt and the degrade
      // WITHOUT `_haltAdmission` — only a decision-bearing drop or suppression
      // halts admission — so a harness with an empty append queue can latch
      // its mirrors compromised while `TrajectoryAdmissionHalt` stays
      // unlatched. If health disarmed the read, that harness would re-mount
      // every stranded worktree under the cut.
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
          health: TrajectorySnapshotHealth.compromised,
        ),
      );

      expect(decision, isA<MountRefused>());
      expect((decision as MountRefused).clause, contains('/w/tg-1'));
    });

    test('a mirror that stops beating fails closed whatever its health', () {
      // A harness that leaves `live` returns before `noteTickAt`, so the beat
      // freezes and the SAME three-tick rule catches it — fail-closed, after
      // the same grace the heal uses, not by a health enum.
      for (final health in TrajectorySnapshotHealth.values) {
        final decision = _evaluate(
          _read(
            lastTickAt: _now.subtract(
              kWorktreeOutstandingStaleAfter + const Duration(seconds: 1),
            ),
            health: health,
          ),
        );

        expect(decision, isA<MountRefused>(), reason: '${health.name} wedges');
        expect((decision as MountRefused).clause, contains(health.name));
      }
    });

    test(
      'wedged detail reports compromised health without changing the predicate',
      () {
        final staleAt = _now.subtract(
          kWorktreeOutstandingStaleAfter + const Duration(seconds: 1),
        );
        final live = evaluateWorktreeOutstanding(
          read: _read(lastTickAt: staleAt),
          workBeadId: _workBead,
          linkedSessions: const <SessionProjection>[],
          now: _now,
        );
        final compromised = evaluateWorktreeOutstanding(
          read: _read(
            lastTickAt: staleAt,
            health: TrajectorySnapshotHealth.compromised,
          ),
          workBeadId: _workBead,
          linkedSessions: const <SessionProjection>[],
          now: _now,
        );

        expect(live.refuse, isTrue);
        expect(live.wedged, isTrue);
        expect(compromised.refuse, isTrue);
        expect(compromised.wedged, isTrue);
        expect(live.detail, contains('beat source P6'));
        expect(compromised.detail, contains('beat source P6'));
        expect(live.detail, contains(staleAt.toIso8601String()));
        expect(compromised.detail, contains(staleAt.toIso8601String()));
        expect(live.detail, contains('mirror health live'));
        expect(compromised.detail, contains('mirror health compromised'));
      },
    );

    test('a freshly compromised mirror still admits inside the grace', () {
      // Health alone refuses NOTHING: within three tick intervals the rows are
      // as fresh as any live mirror's, so the grace holds exactly as it does
      // for an idle station.
      final decision = _evaluate(
        _read(
          identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
          heads: [_Head(sessionId: 's1', workBeadId: _workBead)],
          lastTickAt: _now.subtract(const Duration(seconds: 30)),
          health: TrajectorySnapshotHealth.compromised,
        ),
        linked: const [
          SessionProjection(workBeadId: _workBead, sessionId: 's1'),
        ],
      );

      expect(decision, isA<MountEligible>());
    });

    test('a disarmed read (no P6 mirror) refuses nothing', () {
      final decision = worktreeOutstandingClause(
        read: const WorktreeOutstandingRead.disarmed(),
        linkedSessionsOf: (_) => const <SessionProjection>[],
        observeForm: false,
        clock: () => _now,
      )(_task());

      expect(decision, isA<MountEligible>());
    });
  });

  group('the observe-form counting arm', () {
    test('changes eligibility for NO candidate while still finding', () {
      final findings = <WorktreeOutstandingFinding>[];
      final read = _read(
        identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
        heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
      );

      final armed = _evaluate(read);
      final observing = _evaluate(
        read,
        observeForm: true,
        onFinding: findings.add,
      );

      expect(armed, isA<MountRefused>());
      expect(
        observing,
        isA<MountEligible>(),
        reason: 'the shadow window changes NOTHING about what mounts',
      );
      expect(findings.single.refuse, isTrue);
    });

    test('the counter moves and no record is emitted under shadow', () {
      final sink = _CapturingSink();
      final accounting = DualReadAccounting();
      final barrier = AdmissionBarrier(
        recorder: StationTrajectoryRecorder(
          sink: sink,
          substationPrefixes: const {'tg'},
        ),
        accounting: accounting,
        clock: () => _now,
      );
      final read = _read(
        identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
        heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
      );
      final clause = worktreeOutstandingClause(
        read: read,
        linkedSessionsOf: (_) => const <SessionProjection>[],
        observeForm: barrier.observeForm,
        snapshotRevOf: (_) => '1-abc',
        onFinding: barrier.observe,
        clock: () => _now,
      );

      // Three passes over the same unchanged candidate.
      expect(clause(_task()), isA<MountEligible>());
      expect(clause(_task()), isA<MountEligible>());
      expect(clause(_task()), isA<MountEligible>());

      expect(barrier.observeForm, isTrue);
      expect(accounting.barrierWouldRefuse, 1, reason: 'deduped per bead');
      expect(
        accounting.toCertificationJson()['barrier_would_refuse'],
        1,
        reason: 'the §W2.5 row is REPORTED, never gating',
      );
      expect(sink.records, isEmpty);
    });

    test('the counter rides the round summary shape', () {
      final accounting = DualReadAccounting()
        ..recordBarrierWouldRefuse('tg-1')
        ..recordBarrierWouldRefuse('tg-2')
        ..recordBarrierWouldRefuse('tg-1');
      final json = accounting.toJson(
        mode: DualReadMode.observe,
        health: TrajectorySnapshotHealth.live,
        snapshotVersion: 3,
      );

      expect(json['barrier_would_refuse'], 2);
      expect(
        (json['counter_semantics']!
            as Map<String, String>)['barrier_would_refuse'],
        'cumulative',
      );
    });
  });

  group('the admission.refused derivation, armed at the cut', () {
    AdmissionBarrier barrierOver(
      TrajectoryRecordSink sink, {
      bool cut = true,
      DateTime Function()? clock,
    }) => AdmissionBarrier(
      recorder: StationTrajectoryRecorder(
        sink: sink,
        substationPrefixes: const {'tg'},
      ),
      cut: cut,
      clock: clock ?? () => _now,
    );

    WorktreeOutstandingFinding refusing({String rev = '1-abc'}) =>
        evaluateWorktreeOutstanding(
          read: _read(
            identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
            heads: [
              _Head(sessionId: 's1', workBeadId: _workBead, isOpen: false),
            ],
          ),
          workBeadId: _workBead,
          linkedSessions: const [],
          now: _now,
          snapshotRev: rev,
        );

    test('appends one record on the RATIFIED key', () {
      final sink = _CapturingSink();
      barrierOver(sink).observe(refusing());

      expect(sink.types, ['admission.refused']);
      expect(sink.keys(), [
        'refused:$_workBead:$kWorktreeOutstandingClause:1-abc',
      ]);
      expect(sink.substations, ['tg']);
      final payload = sink.records.single.payloadToJson();
      expect(payload['clause'], kWorktreeOutstandingClause);
      expect(payload['snapshot_rev'], '1-abc');
      expect((payload['detail']! as Map<String, Object?>)['worktrees'], [
        '/w/tg-1',
      ]);
      final correlation = sink.records.single.correlationToJson();
      expect(correlation['work_bead_id'], _workBead);
      expect(
        correlation['mount_attempt_id'],
        isA<String>().having((id) => id.length, 'a minted ULID', 26),
      );
    });

    test('a repeated refusal of the same unchanged candidate appends once', () {
      final sink = _CapturingSink();
      final barrier = barrierOver(sink)
        ..observe(refusing())
        ..observe(refusing())
        ..observe(refusing());

      expect(sink.records, hasLength(1));
      expect(barrier.refusalsAppended, 1);
    });

    test('a CHANGED basis revision re-latches', () {
      final sink = _CapturingSink();
      barrierOver(sink)
        ..observe(refusing())
        ..observe(refusing(rev: '2-def'));

      expect(sink.keys(), [
        'refused:$_workBead:$kWorktreeOutstandingClause:1-abc',
        'refused:$_workBead:$kWorktreeOutstandingClause:2-def',
      ]);
    });

    test('no revision, no record — an unkeyable refusal is never minted', () {
      final sink = _CapturingSink();
      barrierOver(sink).observe(
        evaluateWorktreeOutstanding(
          read: _read(
            identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
            heads: [
              _Head(sessionId: 's1', workBeadId: _workBead, isOpen: false),
            ],
          ),
          workBeadId: _workBead,
          linkedSessions: const [],
          now: _now,
        ),
      );

      expect(sink.records, isEmpty);
    });

    test('UNDER SHADOW nothing is appended at all', () {
      final sink = _CapturingSink();
      barrierOver(sink, cut: false)
        ..observe(refusing())
        ..observe(refusing(rev: '2-def'));

      expect(sink.records, isEmpty);
    });

    test('a dropped refusal record does not halt admission', () {
      // The sink refuses every record; the clause's verdict is unchanged and
      // nothing throws — the refusal is not decision-bearing.
      final barrier = barrierOver(_RefusingSink());
      final read = _read(
        identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
        heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
      );
      final clause = worktreeOutstandingClause(
        read: read,
        linkedSessionsOf: (_) => const <SessionProjection>[],
        observeForm: false,
        snapshotRevOf: (_) => '1-abc',
        onFinding: barrier.observe,
        clock: () => _now,
      );

      expect(clause(_task()), isA<MountRefused>());
      expect(clause(_task('tg-2')), isA<MountEligible>());
    });

    test('a cleared bead forgets its dedupe so the next episode appends', () {
      final sink = _CapturingSink();
      final barrier = barrierOver(sink)..observe(refusing());
      barrier.observe(
        const WorktreeOutstandingFinding.clear(_workBead, snapshotRev: '1-abc'),
      );
      barrier.observe(refusing());

      expect(sink.records, hasLength(2));
    });
  });

  group('composed at BOTH composeMountEligibility sites', () {
    test('the source of each call site composes the clause', () {
      for (final path in const [
        'lib/src/seeds/work_list.dart',
        'lib/src/kernel/station_admission_authority.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('composeMountEligibility('),
          reason: '$path is a composition site',
        );
        expect(
          source,
          contains('worktreeOutstandingClause('),
          reason: '$path must compose the barrier clause',
        );
      }
    });

    // The barrier's fixture, shared by both call-site tests: a live P6 row
    // under a P1-CLOSED session of the candidate bead.
    WorktreeOutstandingRead outstandingRead() => _read(
      identities: [_Identity(sessionId: 's1', worktree: '/w/tg-1')],
      heads: [_Head(sessionId: 's1', workBeadId: _workBead, isOpen: false)],
    );

    // THE CONTROL. Same clock, same beat, EMPTY P6 mirror. Every behavioural
    // call-site assertion below is paired with this one, because a refusal
    // that also fires here came from the WEDGED branch and would pass with the
    // P6 → P1 join deleted.
    WorktreeOutstandingRead clearRead() => _read();

    test('the AUTHORITY site refuses on the JOIN, and admits without it', () {
      StationAdmissionBatch admit(WorktreeOutstandingRead read) {
        final runner = RecordingBdRunner();
        final services = StationServices(
          provider: FakeRuntimeProvider(),
          writer: StationBeadWriter(
            bd: BdCliService(runner),
            reader: runner,
            ownership: BeadOwnershipPredicate(const {'tg'}),
          ),
          stateSubstation: 'tg',
          maxConcurrentWork: 2,
          // THE CLOCK SEAM. Without it the authority evaluates the clause at
          // the wall clock, the fixture's beat reads 3+ intervals old, and
          // every refusal below arrives through the wedged branch instead of
          // the join.
          clock: () => _now,
          admissionBarrier: AdmissionBarrier(
            recorder: StationTrajectoryRecorder(sink: _CapturingSink()),
            cut: true,
            clock: () => _now,
          ),
        );
        addTearDown(services.dispose);

        final bead = _task();
        return services.admission.admitPending(
          JoinedSnapshot(
            graph: GraphSnapshot.fromParts(
              beads: [bead],
              dependencies: const [],
              readyIds: {bead.id},
              capturedAt: _now,
            ),
            worktreeOutstanding: read,
          ),
          const SubstationConfig(
            substationId: 'tg',
            ownedSubstations: {'tg'},
            maxConcurrentWork: 2,
          ),
          const ServiceBundle(),
          [StationAdmissionCandidate(bead: bead, session: null)],
        );
      }

      final refusing = admit(outstandingRead());
      expect(refusing.admitted, isEmpty);
      expect(refusing.refused.single.clause, kWorktreeOutstandingClause);
      expect(
        refusing.refused.single.detail,
        allOf(contains('s1'), contains('/w/tg-1'), contains('p1-closed')),
        reason: 'the refusal is the JOIN, not the heartbeat',
      );

      final clear = admit(clearRead());
      expect(clear.refused, isEmpty);
      expect(
        {
          for (final reservation in clear.admitted)
            reservation.candidate.bead.id,
        },
        {_workBead},
      );
    });

    test('UNDER SHADOW the mount set is identical with and without it', () {
      final sink = _CapturingSink();
      final accounting = DualReadAccounting();
      final bead = _task();

      Set<String> mountSet({required bool composed, bool cut = false}) {
        final services = StationServices(
          provider: FakeRuntimeProvider(),
          writer: StationBeadWriter(
            bd: BdCliService(RecordingBdRunner()),
            reader: RecordingBdRunner(),
            ownership: BeadOwnershipPredicate(const {'tg'}),
          ),
          stateSubstation: 'tg',
          maxConcurrentWork: 2,
          clock: () => _now,
          admissionBarrier: !composed
              ? null
              : AdmissionBarrier(
                  recorder: StationTrajectoryRecorder(
                    sink: sink,
                    substationPrefixes: const {'tg'},
                  ),
                  accounting: cut ? null : accounting,
                  cut: cut,
                  clock: () => _now,
                ),
        );
        addTearDown(services.dispose);
        final batch = services.admission.admitPending(
          JoinedSnapshot(
            graph: GraphSnapshot.fromParts(
              beads: [bead],
              dependencies: const [],
              readyIds: {bead.id},
              capturedAt: _now,
            ),
            // ARMED in every arm — the candidate really does hold an
            // outstanding worktree. What differs is only whether the barrier's
            // observer is composed, and under which posture.
            worktreeOutstanding: outstandingRead(),
            eligibilityBasisRevisionsByBeadId: const {_workBead: '1-abc'},
          ),
          const SubstationConfig(
            substationId: 'tg',
            ownedSubstations: {'tg'},
            maxConcurrentWork: 2,
          ),
          const ServiceBundle(),
          [StationAdmissionCandidate(bead: bead, session: null)],
        );
        return {
          for (final reservation in batch.admitted)
            reservation.candidate.bead.id,
        };
      }

      expect(mountSet(composed: false), {_workBead});
      expect(
        mountSet(composed: true),
        {_workBead},
        reason: 'the shadow window changes NOTHING about what mounts',
      );
      expect(accounting.barrierWouldRefuse, 1, reason: 'but it COUNTS');
      expect(sink.records, isEmpty);
      // …and the counted would-refuse is a REAL one: the same snapshot under
      // the cut takes the candidate out of the mount set.
      expect(
        mountSet(composed: true, cut: true),
        isEmpty,
        reason: 'the shadow counter counts the decision the cut would make',
      );
    });

    test('the OFFLINE site refuses on the JOIN, and admits without it', () {
      List<WorkBead> mounted(WorktreeOutstandingRead read) {
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final bead = _task();
        final joined = JoinedSnapshotNotifier(
          JoinedSnapshot(
            graph: GraphSnapshot.fromParts(
              beads: [bead],
              dependencies: const [],
              readyIds: {bead.id},
              capturedAt: _now,
            ),
            worktreeOutstanding: read,
          ),
        );
        addTearDown(joined.dispose);

        final root = owner.mountRoot(
          ProviderScope(
            child: InheritedSeed<TrajectoryRecorderScope>(
              value: TrajectoryRecorderScope(
                StationTrajectoryRecorder(sink: _CapturingSink()),
                // The offline path has no clock of its own: the barrier's IS
                // the clause's clock at this site.
                barrier: AdmissionBarrier(
                  recorder: StationTrajectoryRecorder(sink: _CapturingSink()),
                  cut: true,
                  clock: () => _now,
                ),
              ),
              child: InheritedSeed<JoinedSnapshotNotifier>(
                value: joined,
                child: InheritedSeed<SessionResolver>(
                  value: _IdleResolver(),
                  child: Station([
                    SubstationScope(
                      configNotifier: SubstationConfigNotifier(
                        const SubstationConfig(
                          substationId: 'test',
                          ownedSubstations: {'tg'},
                          maxConcurrentWork: 10,
                        ),
                      ),
                      services: const ServiceBundle(),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
        owner.flush();
        return _workBeads(root);
      }

      expect(mounted(outstandingRead()), isEmpty);
      expect(
        [for (final work in mounted(clearRead())) work.bead.id],
        [_workBead],
        reason:
            'an EMPTY P6 mirror at the same beat mounts — so the refusal '
            'above is the join, not the heartbeat',
      );
    });
  });
}

final class _IdleResolver implements SessionResolver {
  @override
  Seed sessionFor({required Bead bead, SessionProjection? session}) =>
      const Idle();
}

List<WorkBead> _workBeads(Branch root) {
  final found = <WorkBead>[];
  void walk(Branch branch) {
    if (branch.seed case final WorkBead bead) found.add(bead);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
}
