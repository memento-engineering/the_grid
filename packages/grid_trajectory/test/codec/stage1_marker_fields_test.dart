// W3 (tg-zfek Stage 1) — the additive payload markers the derivation layer
// stamps (stage1-wiring §2.1/§2.2): `grant_basis` + `legacy_attempt_count` +
// `substation_basis` on attempt.session.started, `attempt_id_basis` +
// `substation_basis` on attempt.terminal, `legacy_attempt_count` +
// `substation_basis` on
// attempt.mint.outcome.
//
// Rule under test is §2.6 rule 1: within type_version 1 the change is
// additive-only — unset markers leave the wire payload byte-identical to the
// pre-Stage-1 shape (golden fixtures untouched), set markers round-trip.
import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

TrajectoryEnvelope _envelope(TrajectoryRecord record, {String? substation}) {
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
  if (json['work_bead_id'] != null) json['substation'] = substation ?? 'tg';
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
        substationBasis: 'no-owned-prefix',
      );
      final decoded = TrajectoryCodec.decode(
        _envelope(record, substation: 'unowned'),
      );
      final typed = decoded as AttemptSessionStarted;
      expect(typed.grantBasis, 'pre-stage3');
      expect(typed.legacyAttemptCount, 2);
      expect(typed.substationBasis, 'no-owned-prefix');
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
        substationBasis: 'no-owned-prefix',
      );
      final typed =
          TrajectoryCodec.decode(_envelope(record)) as AttemptTerminal;
      expect(typed.attemptIdBasis, 'reconciler-minted');
      expect(typed.substationBasis, 'no-owned-prefix');
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
        substationBasis: 'no-owned-prefix',
      );
      final typed =
          TrajectoryCodec.decode(_envelope(record)) as AttemptMintOutcome;
      expect(typed.legacyAttemptCount, 3);
      expect(typed.substationBasis, 'no-owned-prefix');
      expect(typed.payloadToJson(), record.payloadToJson());
    });
  });

  group('worktree.provisioned markers (adjudicated: the marked mint)', () {
    test('unset attempt_id_basis keeps the v1 payload shape exactly', () {
      const record = WorktreeProvisioned(
        attemptId: '01J8ATTEMPT000000000000001',
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
        baseSha: 'f5baf0e0f5baf0e0f5baf0e0f5baf0e0f5baf0e0',
        adoptedExisting: false,
      );
      expect(record.payloadToJson(), {'adopted_existing': false});
    });

    test('a recorder-minted provision round-trips its basis marker', () {
      const record = WorktreeProvisioned(
        attemptId: '01J8ATTEMPT000000000000001',
        worktree: '/wt/tg-1',
        branch: 'grid/tg-1',
        baseSha: 'f5baf0e0f5baf0e0f5baf0e0f5baf0e0f5baf0e0',
        adoptedExisting: true,
        attemptIdBasis: 'recorder-minted',
      );
      final typed =
          TrajectoryCodec.decode(_envelope(record)) as WorktreeProvisioned;
      expect(typed.attemptIdBasis, 'recorder-minted');
      expect(typed.payloadToJson(), record.payloadToJson());
    });
  });
}
