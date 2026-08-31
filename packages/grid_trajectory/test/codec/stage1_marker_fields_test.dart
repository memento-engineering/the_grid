// W3 (tg-zfek Stage 1) — the additive payload markers the derivation layer
// stamps (stage1-wiring §2.1/§2.2): `grant_basis` + `legacy_attempt_count` +
// `seat_basis` on attempt.session.started, `attempt_id_basis` + `seat_basis`
// on attempt.terminal, `legacy_attempt_count` + `seat_basis` on
// attempt.mint.outcome.
//
// Rule under test is §2.6 rule 1: within type_version 1 the change is
// additive-only — unset markers leave the wire payload byte-identical to the
// pre-Stage-1 shape (golden fixtures untouched), set markers round-trip.
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

TrajectoryEnvelope _envelope(TrajectoryRecord record, {String? seat}) {
  const context = IdemContext(station: 'tranquility', bootEpoch: 1);
  final now = DateTime.utc(2026, 8, 31, 12);
  final json = <String, Object?>{
    'record_id': mintUlid(now: now),
    'idem_key': record.idemKey(context),
    'idem_key_text': record.idemKeyText(context),
    'family': record.family.wire,
    'record_type': record.recordType,
    'type_version': record.typeVersion,
    'occurred_at': now.toIso8601String(),
    'recorded_at': now.toIso8601String(),
    'station': 'tranquility',
    'authority_id': 'tranquility/1',
    'boot_epoch': 1,
    'provenance': TrajectoryProvenance.observed.wire,
    'source': 'test',
    'payload': record.payloadToJson(),
    ...record.correlationToJson(),
  };
  if (json['work_bead_id'] != null) json['seat'] = seat ?? 'tg';
  return TrajectoryEnvelope.fromJson(json);
}

void main() {
  group('attempt.session.started markers', () {
    test('unset markers keep the v1 payload shape exactly', () {
      const record = AttemptSessionStarted(
        sessionId: 's-1',
        grantId: 'G-1',
        rig: 'the_grid',
        model: 'claude-fable-5',
      );
      expect(record.payloadToJson(), {
        'rig': 'the_grid',
        'model': 'claude-fable-5',
      });
    });

    test('set markers round-trip through the codec at type_version 1', () {
      const record = AttemptSessionStarted(
        sessionId: 's-1',
        grantId: 'G-1',
        rig: 'the_grid',
        model: 'claude-fable-5',
        workBeadId: 'tg-9xk2',
        mountAttemptId: 'M-1',
        grantBasis: 'pre-stage3',
        legacyAttemptCount: 2,
        seatBasis: 'no-owned-prefix',
      );
      final decoded = TrajectoryCodec.decode(
        _envelope(record, seat: 'unowned'),
      );
      final typed = decoded as AttemptSessionStarted;
      expect(typed.grantBasis, 'pre-stage3');
      expect(typed.legacyAttemptCount, 2);
      expect(typed.seatBasis, 'no-owned-prefix');
      expect(typed.payloadToJson(), record.payloadToJson());
    });
  });

  group('attempt.terminal markers', () {
    test('unset markers keep the v1 payload shape exactly', () {
      final record = AttemptTerminal(
        attemptId: 'A-1',
        outcome: TerminalOutcome.succeeded,
        reason: 'done',
      );
      expect(record.payloadToJson(), {'reason': 'done'});
    });

    test('a minted-attempt settlement round-trips its basis', () {
      final record = AttemptTerminal(
        attemptId: 'A-1',
        sessionId: 's-1',
        workBeadId: 'tg-9xk2',
        outcome: TerminalOutcome.settled,
        attemptIdBasis: 'reconciler-minted',
        seatBasis: 'no-owned-prefix',
      );
      final typed =
          TrajectoryCodec.decode(_envelope(record)) as AttemptTerminal;
      expect(typed.attemptIdBasis, 'reconciler-minted');
      expect(typed.seatBasis, 'no-owned-prefix');
      expect(typed.payloadToJson(), record.payloadToJson());
    });
  });

  group('attempt.mint.outcome markers', () {
    test('unset markers keep the v1 payload shape exactly', () {
      const record = AttemptMintOutcome(
        workBeadId: 'tg-9xk2',
        mountAttemptId: 'M-1',
        phase: MintPhase.failed,
        mintAttempt: 1,
      );
      expect(record.payloadToJson(), {'phase': 'failed', 'mint_attempt': 1});
    });

    test('the shadow-comparable ordinal rides the payload (r2 major 8)', () {
      const record = AttemptMintOutcome(
        workBeadId: 'tg-9xk2',
        mountAttemptId: 'M-1',
        phase: MintPhase.refused,
        mintAttempt: 1,
        legacyAttemptCount: 3,
        seatBasis: 'no-owned-prefix',
      );
      final typed =
          TrajectoryCodec.decode(_envelope(record)) as AttemptMintOutcome;
      expect(typed.legacyAttemptCount, 3);
      expect(typed.seatBasis, 'no-owned-prefix');
      expect(typed.payloadToJson(), record.payloadToJson());
    });
  });
}
