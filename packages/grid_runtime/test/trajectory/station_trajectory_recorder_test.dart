// W3 (tg-zfek Stage 1) — the derivation layer against the schema's field
// requirements:
//
//   * every builder's output survives the REAL envelope construction (the
//     ck_prov / ck_unknown / ck_seat constructor mirrors) and the REAL codec
//     round-trip — a missing CHECK-relevant field fails here, not at the
//     server;
//   * identity threading (§2.1/§2.2): session-scope attempt ids, the round
//     ladder (seeded by `#rN` at first sight, bumped only by round-retired),
//     the mount sequence ULID, the pre-grant id, seat via ownedPrefixOf with
//     the deterministic unowned fallback;
//   * the §2.3 trigger discipline as API shape: synchronous, void, and
//     NON-FATAL — a throwing sink or flare transport never reaches the caller.
import 'package:grid_runtime/grid_runtime.dart';
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

final class _Capture {
  const _Capture({
    required this.record,
    required this.occurredAt,
    required this.seat,
    required this.provenance,
    required this.provenanceBasis,
  });

  final TrajectoryRecord record;
  final DateTime? occurredAt;
  final String? seat;
  final TrajectoryProvenance provenance;
  final String? provenanceBasis;
}

final class _CapturingSink implements TrajectoryRecordSink {
  @override
  bool accepting = true;

  final List<_Capture> captured = [];

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    captured.add(
      _Capture(
        record: record,
        occurredAt: occurredAt,
        seat: seat,
        provenance: provenance,
        provenanceBasis: provenanceBasis,
      ),
    );
  }
}

final class _ThrowingSink implements TrajectoryRecordSink {
  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('sink refused');
}

/// 26-char Crockford ULID (the CHAR(26) identity classes mint).
final Matcher isUlid = matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$'));

void main() {
  final clockNow = DateTime.utc(2026, 8, 31, 12);
  late _CapturingSink sink;
  late List<(String, Map<String, String>)> flares;
  late StationTrajectoryRecorder recorder;

  setUp(() {
    sink = _CapturingSink();
    flares = [];
    recorder = StationTrajectoryRecorder(
      sink: sink,
      seatPrefixes: const {'tg', 'swift-infer', 'tranquility'},
      clock: () => clockNow,
      onFlare: (name, data) => flares.add((name, data)),
    );
  });

  /// Builds the envelope EXACTLY the way the appender's `_buildEnvelope`
  /// does — correlation columns merged over the service-stamped base, the
  /// recorder-supplied seat applied when `work_bead_id` is present — so the
  /// §4 cross-cutting CHECK mirrors (`ck_prov`, `ck_unknown`, `ck_seat`) and
  /// each type's `_envReq` required-column reads all run for real.
  TrajectoryEnvelope envelopeOf(_Capture capture) {
    const context = IdemContext(station: 'tranquility', bootEpoch: 3);
    final record = capture.record;
    final json = <String, Object?>{
      'record_id': mintUlid(now: clockNow),
      'idem_key': record.idemKey(context),
      'idem_key_text': record.idemKeyText(context),
      'family': record.family.wire,
      'record_type': record.recordType,
      'type_version': record.typeVersion,
      'occurred_at': (capture.occurredAt ?? clockNow).toIso8601String(),
      'recorded_at': clockNow.toIso8601String(),
      'station': 'tranquility',
      'authority_id': 'tranquility/3',
      'boot_epoch': 3,
      'provenance': capture.provenance.wire,
      if (capture.provenanceBasis != null)
        'provenance_basis': capture.provenanceBasis,
      'source': 'test',
      'payload': record.payloadToJson(),
      ...record.correlationToJson(),
    };
    if (json['work_bead_id'] != null) json['seat'] = capture.seat;
    return TrajectoryEnvelope.fromJson(json);
  }

  /// The schema-conformance gate every capture rides: the envelope
  /// constructs (CHECK mirrors green) and the codec decodes it back to the
  /// same typed fact — never an [OpaqueRecord], payload and correlation
  /// byte-identical.
  _Capture expectSchemaClean(_Capture capture) {
    final envelope = envelopeOf(capture);
    final decoded = TrajectoryCodec.decode(envelope);
    expect(
      decoded,
      isNot(isA<OpaqueRecord>()),
      reason:
          '${capture.record.recordType} must decode '
          '(${decoded is OpaqueRecord ? decoded.decodeFailure : ''})',
    );
    expect(decoded.payloadToJson(), capture.record.payloadToJson());
    expect(decoded.correlationToJson(), capture.record.correlationToJson());
    return capture;
  }

  _Capture single() {
    expect(sink.captured, hasLength(1));
    return expectSchemaClean(sink.captured.single);
  }

  group('parseLegacyWorkKey (§2.2 work_bead_id row)', () {
    test('plain id passes through', () {
      expect(StationTrajectoryRecorder.parseLegacyWorkKey('tg-9xk2'), (
        workBeadId: 'tg-9xk2',
        round: null,
      ));
    });

    test('#rN strips and names the round', () {
      expect(StationTrajectoryRecorder.parseLegacyWorkKey('tg-9xk2#r3'), (
        workBeadId: 'tg-9xk2',
        round: 3,
      ));
    });

    test('#void-<session> strips with no round', () {
      expect(StationTrajectoryRecorder.parseLegacyWorkKey('tg-1di#void-i8'), (
        workBeadId: 'tg-1di',
        round: null,
      ));
    });

    test('an unrecognized suffix still yields the original id', () {
      expect(StationTrajectoryRecorder.parseLegacyWorkKey('tg-1di#rework'), (
        workBeadId: 'tg-1di',
        round: null,
      ));
    });
  });

  group('sessionMinted (attempt.session.started)', () {
    test('carries rig/model, a pre-grant ULID, and a mount ULID', () {
      recorder.sessionMinted(
        sessionId: 'tranquility-s1',
        workBeadId: 'tg-9xk2',
        rig: 'the_grid',
        model: 'claude-fable-5',
      );
      final record = single().record as AttemptSessionStarted;
      expect(record.rig, 'the_grid');
      expect(record.model, 'claude-fable-5');
      expect(record.sessionId, 'tranquility-s1');
      expect(record.workBeadId, 'tg-9xk2');
      expect(record.grantId, isUlid);
      expect(record.mountAttemptId, isUlid);
      // §2.2 grant_id row: no grants before Stage 3 — payload-marked.
      expect(record.grantBasis, kPreStage3GrantBasis);
      expect(record.payloadToJson()['grant_basis'], kPreStage3GrantBasis);
    });

    test('strips the legacy #rN re-key — the record never carries it', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-9xk2#r2',
        rig: 'r',
        model: 'm',
      );
      final record = single().record as AttemptSessionStarted;
      expect(record.workBeadId, 'tg-9xk2');
    });

    test('reads legacy_attempt_count from the mount-attempt metadata', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-9xk2',
        rig: 'r',
        model: 'm',
        mountAttemptMetadata: const {kLegacyAttemptCountKey: 2},
      );
      final record = single().record as AttemptSessionStarted;
      expect(record.legacyAttemptCount, 2);
    });

    test('tolerates a string-typed count and an absent key', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
        mountAttemptMetadata: const {kLegacyAttemptCountKey: '3'},
      );
      recorder.sessionMinted(
        sessionId: 's2',
        workBeadId: 'tg-2',
        rig: 'r',
        model: 'm',
      );
      final counts = [
        for (final c in sink.captured)
          (expectSchemaClean(c).record as AttemptSessionStarted)
              .legacyAttemptCount,
      ];
      expect(counts, [3, null]);
    });

    test('stamps the observation instant from the clock', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      expect(single().occurredAt, clockNow);
    });
  });

  group('seat derivation (§2.2 seat row, r2 minor 12)', () {
    test('longest owned prefix wins', () {
      recorder.mintOutcome(
        workBeadId: 'swift-infer-097',
        phase: MintPhase.failed,
        mintAttempt: 1,
      );
      final capture = single();
      expect(capture.seat, 'swift-infer');
      final record = capture.record as AttemptMintOutcome;
      expect(record.seatBasis, isNull);
    });

    test('no owned prefix stamps the literal unowned + payload marker', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'lenny-880l',
        rig: 'r',
        model: 'm',
      );
      final capture = single();
      expect(capture.seat, kUnownedSeat);
      final record = capture.record as AttemptSessionStarted;
      expect(record.seatBasis, kUnownedSeatBasis);
      expect(record.payloadToJson()['seat_basis'], kUnownedSeatBasis);
    });
  });

  group('mount sequence (§2.2 mount_attempt_id row)', () {
    AttemptMintOutcome mintFailed(int attempt) {
      recorder.mintOutcome(
        workBeadId: 'tg-9xk2',
        phase: MintPhase.failed,
        mintAttempt: attempt,
        maxAttempts: 5,
        stage: 'createSession',
        reason: 'bd blip',
      );
      return expectSchemaClean(sink.captured.last).record as AttemptMintOutcome;
    }

    test('one ULID spans the whole mint sequence, consumed by the mint', () {
      final first = mintFailed(1);
      final second = mintFailed(2);
      expect(second.mountAttemptId, first.mountAttemptId);

      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-9xk2',
        rig: 'r',
        model: 'm',
      );
      final started =
          expectSchemaClean(sink.captured.last).record as AttemptSessionStarted;
      expect(started.mountAttemptId, first.mountAttemptId);

      // The NEXT sequence for the same work bead is a fresh ULID.
      final next = mintFailed(1);
      expect(next.mountAttemptId, isNot(first.mountAttemptId));
    });

    test('exhausted ENDS the sequence', () {
      final first = mintFailed(1);
      recorder.mintOutcome(
        workBeadId: 'tg-9xk2',
        phase: MintPhase.exhausted,
        mintAttempt: 5,
      );
      final exhausted =
          expectSchemaClean(sink.captured.last).record as AttemptMintOutcome;
      expect(exhausted.mountAttemptId, first.mountAttemptId);
      expect(mintFailed(1).mountAttemptId, isNot(first.mountAttemptId));
    });

    test('a refused evaluation appends with the sequence id (r2 minor 14)', () {
      recorder.mintOutcome(
        workBeadId: 'tg-9xk2#r1',
        phase: MintPhase.refused,
        mintAttempt: 1,
        reason: 'store guard',
      );
      final record = single().record as AttemptMintOutcome;
      expect(record.workBeadId, 'tg-9xk2');
      expect(record.phase, MintPhase.refused);
      expect(record.mountAttemptId, isUlid);
    });
  });

  group('the round ladder (§2.2 round row)', () {
    test('seeded by #rN at first sight, bumped only by round-retired', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-9xk2#r2',
        rig: 'r',
        model: 'm',
      );
      recorder.reworkDeclined(sessionId: 's1', reason: 'HELD');
      final declined =
          expectSchemaClean(sink.captured.last).record as AttemptReworkDeclined;
      expect(declined.round, 2, reason: 'seeded from the #r2 re-key');

      recorder.roundRetired(sessionId: 's1', cause: RoundRetireCause.rework);
      final retired =
          expectSchemaClean(sink.captured.last).record as AttemptRoundRetired;
      expect((retired.oldRound, retired.newRound), (2, 3));

      recorder.processStarted(
        attemptId: mintUlid(),
        sessionId: 's1',
        incarnation: 0,
        pid: 100,
        pgid: 100,
      );
      final started =
          expectSchemaClean(sink.captured.last).record as AttemptProcessStarted;
      expect(started.round, 3, reason: 'the retire bumped the counter');
    });

    test('an unseeded session retires 0 → 1 and is re-seedable', () {
      recorder.roundRetired(sessionId: 's9', cause: RoundRetireCause.voided);
      final retired = single().record as AttemptRoundRetired;
      expect(
        (retired.oldRound, retired.newRound, retired.cause),
        (0, 1, RoundRetireCause.voided),
      );

      recorder.seedRound('s9', 4);
      recorder.roundRetired(sessionId: 's9', cause: RoundRetireCause.rework);
      final reseeded =
          expectSchemaClean(sink.captured.last).record as AttemptRoundRetired;
      expect((reseeded.oldRound, reseeded.newRound), (4, 5));
    });
  });

  group('terminals (§2.3 rows, one record, NO tail)', () {
    test('the four site-mapped outcomes', () {
      recorder.seedSessionAttempt('s1', 'A' * 26);
      recorder.sessionCompleted(sessionId: 's1', workBeadId: 'tg-1');
      recorder.sessionEscalated(
        sessionId: 's1',
        workBeadId: 'tg-1',
        reason: 'operator gate',
      );
      recorder.sessionVoided(sessionId: 's1', workBeadId: 'tg-1#void-s1');
      recorder.sessionSettled(
        sessionId: 's1',
        workBeadId: 'tg-1',
        workTerminalReason: 'work-bead-closed',
      );
      final outcomes = [
        for (final c in sink.captured)
          (expectSchemaClean(c).record as AttemptTerminal).outcome,
      ];
      expect(outcomes, [
        TerminalOutcome.succeeded,
        TerminalOutcome.escalated,
        TerminalOutcome.lost,
        TerminalOutcome.settled,
      ]);
    });

    test('voiding carries the ORIGINAL work bead id — intact keys', () {
      recorder.seedSessionAttempt('s1', 'A' * 26);
      recorder.sessionVoided(sessionId: 's1', workBeadId: 'tg-1di#void-i8');
      final record = single().record as AttemptTerminal;
      expect(record.workBeadId, 'tg-1di');
      expect(record.outcome, TerminalOutcome.lost);
    });

    test('terminal joins the session-scope attempt minted at session mint', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      recorder.sessionCompleted(sessionId: 's1', workBeadId: 'tg-1');
      final terminal =
          expectSchemaClean(sink.captured.last).record as AttemptTerminal;
      expect(terminal.attemptId, isUlid);
      expect(terminal.attemptIdBasis, isNull, reason: 'recovered, not minted');
      const context = IdemContext(station: 'tranquility', bootEpoch: 3);
      expect(
        terminal.idemKeyText(context),
        'terminal:${terminal.attemptId}',
        reason: 'the §5 idem join keys on the recovered attempt id',
      );
    });

    test(
      'reconciler settlement: inferred provenance, breadcrumb id when present',
      () {
        recorder.sessionSettled(
          sessionId: 'old-1',
          workBeadId: 'tg-1',
          attemptId: 'B' * 26,
          workTerminalReason: 'work-bead-closed',
          reconcilerOriginated: true,
        );
        final capture = single();
        expect(capture.provenance, TrajectoryProvenance.inferred);
        expect(capture.provenanceBasis, isNotNull);
        final record = capture.record as AttemptTerminal;
        expect(record.attemptId, 'B' * 26);
        expect(record.attemptIdBasis, isNull);
      },
    );

    test('pre-Stage-1 settlement mints and SAYS SO (§2.1 bounce rule)', () {
      recorder.sessionSettled(
        sessionId: 'ancient-1',
        workBeadId: 'tg-1',
        reconcilerOriginated: true,
      );
      final record = single().record as AttemptTerminal;
      expect(record.attemptId, isUlid);
      expect(record.attemptIdBasis, kReconcilerMintedAttemptBasis);
      expect(
        record.payloadToJson()['attempt_id_basis'],
        kReconcilerMintedAttemptBasis,
      );
    });

    test(
      'a settling terminal carries resolves_record_id (§2.4 obligation 1)',
      () {
        recorder.sessionSettled(
          sessionId: 's1',
          attemptId: 'B' * 26,
          resolvesRecordId: 'C' * 26,
          reconcilerOriginated: true,
        );
        final record = single().record as AttemptTerminal;
        expect(record.isSettling, isTrue);
        expect(record.resolvesRecordId, 'C' * 26);
      },
    );

    test('an observed terminal for an unseeded session mints defensively', () {
      recorder.sessionEscalated(
        sessionId: 'mystery-1',
        workBeadId: 'tg-1',
        reason: 'x',
      );
      final record = single().record as AttemptTerminal;
      expect(record.attemptIdBasis, kRecorderMintedAttemptBasis);
    });
  });

  group('process lifecycle', () {
    test('processStarted carries pid/pgid/incarnation + predecessor', () {
      recorder.processStarted(
        attemptId: 'A' * 26,
        sessionId: 's1',
        incarnation: 2,
        pid: 41,
        pgid: 42,
        predecessorAttemptId: 'B' * 26,
        stepPath: 'build/apply',
        stepRound: 1,
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
      );
      final record = single().record as AttemptProcessStarted;
      expect((record.pid, record.pgid, record.incarnation), (41, 42, 2));
      expect(record.predecessorAttemptId, 'B' * 26);
      expect(record.stepPath, 'build/apply');
      expect(record.worktree, '/wt/tg-1');
    });

    test('an inferred exit stamps inferred provenance (ck_prov basis)', () {
      recorder.processExited(
        attemptId: 'A' * 26,
        pid: 41,
        exitKind: ExitKind.exited,
        inferred: true,
        exitCode: 0,
      );
      final capture = single();
      expect(capture.provenance, TrajectoryProvenance.inferred);
      expect(capture.provenanceBasis, isNotNull);
      expect((capture.record as AttemptProcessExited).inferred, isTrue);
    });

    test('a read exit code is observed', () {
      recorder.processExited(
        attemptId: 'A' * 26,
        sessionId: 's1',
        pid: 41,
        exitKind: ExitKind.died,
        inferred: false,
        reason: 'vanished from the table',
      );
      final capture = single();
      expect(capture.provenance, TrajectoryProvenance.observed);
      expect((capture.record as AttemptProcessExited).exitKind, ExitKind.died);
    });
  });

  group('lease / adopt / liveness / note', () {
    test('the three lease phases carry the breadcrumb token', () {
      recorder.leaseAcquired(attemptId: 'A' * 26, token: 'tok-1');
      recorder.leaseReleased(
        attemptId: 'A' * 26,
        token: 'tok-1',
        disposition: LeaseDisposition.released,
        terminateResult: 'clean',
      );
      recorder.leaseSwept(
        attemptId: 'A' * 26,
        token: 'tok-1',
        disposition: LeaseDisposition.killed,
        clearFailure: 'none',
      );
      final records = [
        for (final c in sink.captured)
          expectSchemaClean(c).record as AttemptLeaseTransition,
      ];
      expect(
        [for (final r in records) r.phase],
        [LeasePhase.acquired, LeasePhase.released, LeasePhase.swept],
      );
      expect(records.every((r) => r.token == 'tok-1'), isTrue);
      expect(records[2].disposition, LeaseDisposition.killed);
    });

    test('adoptProved continues the breadcrumb attempt (§2.1)', () {
      recorder.adoptProved(
        attemptId: 'A' * 26,
        outcome: AdoptOutcome.adopted,
        fencePgid: 42,
        fencePid: 41,
      );
      final record = single().record as AttemptAdoptProved;
      expect(record.outcome, AdoptOutcome.adopted);
      expect((record.fencePgid, record.fencePid), (42, 41));
    });

    test('liveness crossings carry beat + threshold', () {
      final beat = DateTime.utc(2026, 8, 31, 11, 59);
      recorder.livenessLost(
        attemptId: 'A' * 26,
        lastBeatAt: beat,
        thresholdMs: 90000,
      );
      recorder.livenessRegained(
        attemptId: 'A' * 26,
        lastBeatAt: beat.add(const Duration(minutes: 2)),
        thresholdMs: 90000,
      );
      final crossings = [
        for (final c in sink.captured)
          (expectSchemaClean(c).record as AttemptLivenessTransition).crossing,
      ];
      expect(crossings, [LivenessCrossing.lost, LivenessCrossing.regained]);
    });

    test('note ordinals are service-minted per session', () {
      recorder.obligationStuckNoted(sessionId: 's1', body: 'stuck x5');
      recorder.obligationStuckNoted(sessionId: 's1', body: 'still stuck');
      recorder.obligationStuckNoted(sessionId: 's2', body: 'other');
      final notes = [
        for (final c in sink.captured)
          expectSchemaClean(c).record as AttemptNote,
      ];
      expect([for (final n in notes) n.noteOrdinal], [1, 2, 1]);
      expect(
        notes.every((n) => n.channel == kObligationStuckChannel),
        isTrue,
        reason: 'Stage 1 arms ONLY the obligation-stuck channel (§2.3)',
      );
    });
  });

  group('worktree family (§2.3 worktree rows)', () {
    test('provisioned requires sha + branch + worktree (ck_provision)', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      recorder.worktreeProvisioned(
        workBeadId: 'tg-1',
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
        baseSha: 'f5baf0e',
        adoptedExisting: false,
      );
      final capture = expectSchemaClean(sink.captured.last);
      final record = capture.record as WorktreeProvisioned;
      expect(record.baseSha, 'f5baf0e');
      expect(record.branch, 'grid/tg-1');
      expect(record.adoptedExisting, isFalse);
      // The work-bead join: provisioning has only the work bead in hand, and
      // resolves the SAME session-scope attempt the terminal will carry.
      recorder.sessionCompleted(sessionId: 's1', workBeadId: 'tg-1');
      final terminal =
          expectSchemaClean(sink.captured.last).record as AttemptTerminal;
      expect(record.attemptId, terminal.attemptId);
    });

    test('a tick reaped-backfill is inferred (§2.4 obligation 2)', () {
      recorder.worktreeReaped(
        sessionId: 's1',
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
        inferred: true,
      );
      final capture = single();
      expect(capture.provenance, TrajectoryProvenance.inferred);
      expect(capture.provenanceBasis, isNotNull);
    });

    test('held carries the refusal evidence the flares omit', () {
      recorder.worktreeHeld(
        sessionId: 's1',
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
        uncommitted: 3,
        unpushed: 1,
        stashes: 0,
      );
      final record = single().record as WorktreeHeld;
      expect((record.uncommitted, record.unpushed, record.stashes), (3, 1, 0));
    });
  });

  group('the step.transition family (W5 — §2.3\'s four step rows)', () {
    test('running carries the kick instant and no terminal fields', () {
      recorder.stepRunning(
        sessionId: 'tranquility-s1',
        stepPath: 'tg-9xk2/build',
        stepRound: 0,
        incarnation: 0,
        attemptId: 'A' * 26,
        startedAt: clockNow,
      );
      final record = single().record as StepTransition;
      expect(record.state, StepState.running);
      expect(record.startedAt, clockNow);
      expect(record.completedAt, isNull);
      expect(record.failureClass, isNull);
      expect(record.attemptId, 'A' * 26);
    });

    test('complete carries the result keys the legacy write merged', () {
      recorder.stepComplete(
        sessionId: 'tranquility-s1',
        stepPath: 'tg-9xk2/verify',
        stepRound: 1,
        incarnation: 2,
        completedAt: clockNow,
        result: const {'grid.result.grade': 'A'},
      );
      final record = single().record as StepTransition;
      expect(record.state, StepState.complete);
      expect(record.stepRound, 1);
      expect(record.incarnation, 2);
      expect(record.result, {'grid.result.grade': 'A'});
    });

    test('failed splits the tg-7ux conflation: work vs store_unavailable', () {
      recorder.stepFailed(
        sessionId: 's1',
        stepPath: 'tg-1/build',
        stepRound: 0,
        incarnation: 1,
        storeUnavailable: false,
        failureReason: 'the agent exited 1',
        restartBudget: 2,
      );
      recorder.stepFailed(
        sessionId: 's1',
        stepPath: 'tg-1/build',
        stepRound: 0,
        incarnation: 2,
        storeUnavailable: true,
        failureReason: 'persist "complete" failed: bd timeout',
        restartBudget: 1,
      );
      final classes = sink.captured
          .map((c) => expectSchemaClean(c).record as StepTransition)
          .map((r) => r.failureClass)
          .toList();
      expect(classes, [
        StepFailureClass.work,
        StepFailureClass.storeUnavailable,
      ]);
    });

    test('the failed record names the BUMPED incarnation (succession)', () {
      // The persisted restartCount the D-5 write just bumped IS the durable
      // succession signal — the successor mounts at incarnation+1.
      recorder.stepFailed(
        sessionId: 's1',
        stepPath: 'tg-1/build',
        stepRound: 0,
        incarnation: 3,
        storeUnavailable: false,
      );
      expect((single().record as StepTransition).incarnation, 3);
    });

    test('gated is the STEP half only — no gate record is ever built', () {
      recorder.stepGated(
        sessionId: 's1',
        stepPath: 'tg-1/route',
        stepRound: 0,
        incarnation: 0,
        reason: 'needs a human',
      );
      final record = single().record as StepTransition;
      expect(record.state, StepState.gated);
      expect(record.cause, StepCause.route);
      expect(record.failureReason, 'needs a human');
      // G1 carries no gate family at Stage 1.
      expect(sink.captured.map((c) => c.record.recordType), [
        'step.transition',
      ]);
    });

    test('rearm bumps step_round and names cause=gate_cleared', () {
      recorder.stepRearmed(
        sessionId: 's1',
        stepPath: 'tg-1/route',
        fromStepRound: 2,
        incarnation: 0,
      );
      final record = single().record as StepTransition;
      expect(record.state, StepState.pending);
      expect(record.cause, StepCause.gateCleared);
      expect(record.stepRound, 3, reason: 'the gate-cleared rearm bumps it');
    });

    test('a step transition OBSERVES the round ladder, never advances it', () {
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1#r4',
        rig: 'r',
        model: 'm',
      );
      sink.captured.clear();
      recorder.stepRunning(
        sessionId: 's1',
        stepPath: 'tg-1/build',
        stepRound: 0,
        incarnation: 0,
      );
      expect((single().record as StepTransition).round, 4);
      sink.captured.clear();
      recorder.stepComplete(
        sessionId: 's1',
        stepPath: 'tg-1/build',
        stepRound: 0,
        incarnation: 0,
      );
      expect((single().record as StepTransition).round, 4);
    });
  });

  group('incarnation succession (§2.3 — never the dead Respawned event)', () {
    final first = 'A' * 26;
    final second = 'B' * 26;

    test('a spawn OVER a standing breadcrumb names its predecessor', () {
      recorder.leaseAcquired(
        attemptId: first,
        token: 't1',
        stepBeadId: 'tranquility-step-1',
      );
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'tranquility-step-1',
      );
      expect(recorder.predecessorAttemptIdOf(second), first);
      expect(recorder.predecessorAttemptIdOf(first), isNull);
    });

    test('a RELEASED lease clears the breadcrumb — no succession after', () {
      recorder.leaseAcquired(
        attemptId: first,
        token: 't1',
        stepBeadId: 'tranquility-step-1',
      );
      recorder.leaseReleased(
        attemptId: first,
        token: 't1',
        stepBeadId: 'tranquility-step-1',
        disposition: LeaseDisposition.released,
      );
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'tranquility-step-1',
      );
      expect(recorder.predecessorAttemptIdOf(second), isNull);
    });

    test('a KILLED sweep clears it; a LEFT one does not', () {
      recorder.leaseObserved(stepBeadId: 'killed-step', attemptId: first);
      recorder.leaseSwept(
        attemptId: first,
        token: 't1',
        stepBeadId: 'killed-step',
        disposition: LeaseDisposition.killed,
        terminateResult: 'exitedOnTerm',
      );
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'killed-step',
      );
      expect(recorder.predecessorAttemptIdOf(second), isNull);

      recorder.leaseObserved(stepBeadId: 'left-step', attemptId: first);
      recorder.leaseSwept(
        attemptId: first,
        token: 't1',
        stepBeadId: 'left-step',
        disposition: LeaseDisposition.leftAdoptable,
      );
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'left-step',
      );
      expect(recorder.predecessorAttemptIdOf(second), first);
    });

    test('a kill whose CLEAR was dropped leaves the breadcrumb standing', () {
      recorder.leaseObserved(stepBeadId: 'step-1', attemptId: first);
      recorder.leaseSwept(
        attemptId: first,
        token: 't1',
        stepBeadId: 'step-1',
        disposition: LeaseDisposition.killed,
        terminateResult: 'killed',
        clearFailure: 'bd timeout',
      );
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'step-1',
      );
      expect(
        recorder.predecessorAttemptIdOf(second),
        first,
        reason: 'the cache follows the BEAD, not the kill\'s intent',
      );
    });

    test('a re-persist of the SAME attempt is not a succession', () {
      recorder.leaseAcquired(
        attemptId: first,
        token: 't1',
        stepBeadId: 'step-1',
      );
      recorder.leaseAcquired(
        attemptId: first,
        token: 't1',
        stepBeadId: 'step-1',
      );
      expect(recorder.predecessorAttemptIdOf(first), isNull);
    });

    test('leaseObserved seeds from a READ and appends nothing', () {
      recorder.leaseObserved(stepBeadId: 'step-1', attemptId: first);
      expect(sink.captured, isEmpty);
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'step-1',
      );
      expect(recorder.predecessorAttemptIdOf(second), first);
    });

    test('a pre-Stage-1 breadcrumb (blank id) forgets rather than chains', () {
      recorder.leaseObserved(stepBeadId: 'step-1', attemptId: first);
      recorder.leaseObserved(stepBeadId: 'step-1', attemptId: '');
      recorder.leaseAcquired(
        attemptId: second,
        token: 't2',
        stepBeadId: 'step-1',
      );
      expect(recorder.predecessorAttemptIdOf(second), isNull);
    });
  });

  group('failure posture (§3) — the trajectory can degrade; work cannot', () {
    test('a non-accepting sink short-circuits to a count', () {
      sink.accepting = false;
      recorder.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      expect(sink.captured, isEmpty);
      expect(recorder.stats.skipped, 1);
      expect(recorder.stats.derived, 0);
    });

    test('a throwing sink is counted + flared, NEVER propagated', () {
      final throwing = StationTrajectoryRecorder(
        sink: _ThrowingSink(),
        onFlare: (name, data) => flares.add((name, data)),
      );
      throwing.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      expect(throwing.stats.deriveFailures, 1);
      expect(flares.single.$1, 'trajectory.deriveFailed');
      expect(flares.single.$2['site'], 'sessionMinted');
    });

    test('a throwing flare transport is swallowed too', () {
      final doubleFault = StationTrajectoryRecorder(
        sink: _ThrowingSink(),
        onFlare: (_, _) => throw StateError('transport down'),
      );
      doubleFault.processExited(
        attemptId: 'A' * 26,
        pid: 1,
        exitKind: ExitKind.exited,
        inferred: false,
      );
      expect(doubleFault.stats.deriveFailures, 1);
    });

    test('the disabled null-object derives nothing', () {
      final disabled = StationTrajectoryRecorder.disabled();
      disabled.sessionMinted(
        sessionId: 's1',
        workBeadId: 'tg-1',
        rig: 'r',
        model: 'm',
      );
      disabled.roundRetired(sessionId: 's1', cause: RoundRetireCause.rework);
      expect(disabled.stats.skipped, 2);
      expect(disabled.stats.derived, 0);
    });
  });
}
