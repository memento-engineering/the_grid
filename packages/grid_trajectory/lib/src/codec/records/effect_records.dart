// Family 4 — effect intent / acknowledgement (§2 F4). `effect_id` keys the
// LOGICAL mutation (§1): respawn-proof, retry-proof, probe-joinable.

part of '../trajectory_record.dart';

enum EffectKind {
  commit('commit'),
  push('push'),
  prOpen('pr_open'),
  automerge('automerge'),
  directMerge('direct_merge'),
  ciReworkCommand('ci_rework_command');

  const EffectKind(this.wire);

  final String wire;

  static EffectKind fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum ClaimOrder {
  deliverThenClaim('deliver_then_claim');

  const ClaimOrder(this.wire);

  final String wire;

  static ClaimOrder fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum CommandRefusalReason {
  fingerprintMismatch('fingerprint-mismatch'),
  fenceStale('fence-stale');

  const CommandRefusalReason(this.wire);

  final String wire;

  static CommandRefusalReason fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

/// `effect.intent` — written and durable BEFORE the outward mutation. The
/// effect identity is deterministic from the ladder + kind + target, so decode
/// recomputes it and refuses a row whose envelope `effect_id` disagrees.
final class EffectIntent extends EffectRecord {
  EffectIntent({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.kind,
    required this.targetRepo,
    required this.targetBranch,
    required this.posture,
    this.targetBase,
    this.publishSha,
    this.attemptId,
  }) : identity = EffectIdentity.build(
         sessionId: sessionId,
         round: round,
         stepPath: stepPath,
         stepRound: stepRound,
         kind: kind.wire,
         targetDigest: effectTargetDigest(
           repo: targetRepo,
           branch: targetBranch,
           base: targetBase,
           publishSha: publishSha,
         ),
       );

  factory EffectIntent.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    final target = _reqMap(payload, 'target');
    final intent = EffectIntent(
      sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
      round: _envReq(envelope, 'round', envelope.round),
      stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
      stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
      kind: EffectKind.fromWire(_req<String>(payload, 'kind')),
      targetRepo: _req<String>(target, 'repo'),
      targetBranch: _req<String>(target, 'branch'),
      targetBase: _opt<String>(target, 'base'),
      publishSha: envelope.commitSha,
      posture: _reqMap(payload, 'posture'),
      attemptId: envelope.attemptId,
    );
    final stored = _envReq(envelope, 'effect_id', envelope.effectId);
    if (stored != intent.identity.effectId) {
      throw FormatException(
        'effect.intent: envelope effect_id does not match the identity '
        'recomputed from the ladder/kind/target',
      );
    }
    return intent;
  }

  final EffectIdentity identity;
  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final EffectKind kind;
  final String targetRepo;
  final String targetBranch;
  final String? targetBase;

  /// Rides the envelope `commit_sha` digest column.
  final String? publishSha;

  /// Posture snapshot: `{delivery_method, policy_version}`.
  final Map<String, Object?> posture;

  /// Attribution only — never part of the effect identity.
  final String? attemptId;

  @override
  String get recordType => 'effect.intent';

  @override
  Map<String, Object?> payloadToJson() => {
    'kind': kind.wire,
    'target': {
      'repo': targetRepo,
      'branch': targetBranch,
      if (targetBase != null) 'base': targetBase,
    },
    'posture': posture,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'effect_id': identity.effectId,
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    if (attemptId != null) 'attempt_id': attemptId,
    if (publishSha != null) 'commit_sha': publishSha,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'effect:${identity.effectId}:intent';
}

/// `effect.ack` — per-outcome acknowledgement; an unknown ack is resolvable by
/// a later probe ack carrying `resolves_record_id`. The ack ordinal is
/// service-minted: 0 primary, resolving acks take `resolve_count + 1`.
final class EffectAck extends EffectRecord {
  EffectAck({
    required this.effectId,
    required this.kind,
    required this.ackOrdinal,
    required this.outcome,
    this.unknownReason,
    this.resolvesRecordId,
    this.receipt,
    this.commitSha,
    this.pushedSha,
    this.prNumber,
    this.prUrl,
    this.reused,
    this.automergeMode,
    this.mergeSha,
    this.baseSha,
    this.refusedReason,
  }) {
    if (outcome == TerminalOutcome.unknown && unknownReason == null) {
      _refuse(recordType, 'outcome unknown requires unknown_reason');
    }
    // Per-kind receipt fields are required only on a succeeded ack (§2 F4);
    // failed/unknown acks have nothing to receipt.
    if (outcome == TerminalOutcome.succeeded) {
      final missing = switch (kind) {
        EffectKind.commit when commitSha == null => 'commit_sha',
        EffectKind.push when pushedSha == null => 'pushed_sha',
        EffectKind.prOpen when prNumber == null || prUrl == null =>
          'pr_number/pr_url',
        EffectKind.prOpen when reused == null => 'reused',
        EffectKind.automerge when automergeMode == null => 'mode',
        _ => null,
      };
      if (missing != null) {
        _refuse(recordType, 'succeeded ${kind.wire} ack requires $missing');
      }
    }
  }

  factory EffectAck.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => EffectAck(
    effectId: _envReq(envelope, 'effect_id', envelope.effectId),
    outcome: _envReq(envelope, 'outcome', envelope.outcome),
    unknownReason: envelope.unknownReason,
    resolvesRecordId: envelope.resolvesRecordId,
    receipt: envelope.receipt,
    kind: EffectKind.fromWire(_req<String>(payload, 'kind')),
    ackOrdinal: _req<int>(payload, 'ack_ordinal'),
    commitSha: _opt<String>(payload, 'commit_sha'),
    pushedSha: _opt<String>(payload, 'pushed_sha'),
    prNumber: _opt<int>(payload, 'pr_number'),
    prUrl: _opt<String>(payload, 'pr_url'),
    reused: _opt<bool>(payload, 'reused'),
    automergeMode: _opt<String>(payload, 'mode'),
    mergeSha: _opt<String>(payload, 'merge_sha'),
    baseSha: _opt<String>(payload, 'base_sha'),
    refusedReason: _opt<String>(payload, 'refused_reason'),
  );

  final String effectId;
  final EffectKind kind;
  final int ackOrdinal;
  final TerminalOutcome outcome;
  final String? unknownReason;

  /// A settling ack points at the unknown ack it resolves
  /// (provenance='inferred', basis='github-probe' on the envelope).
  final String? resolvesRecordId;

  /// `pr:<repo>#<n>` for pr_open.
  final String? receipt;
  final String? commitSha;
  final String? pushedSha;
  final int? prNumber;
  final String? prUrl;
  final bool? reused;

  /// automerge: `enabled` | `fallback_pr_no_merge`.
  final String? automergeMode;
  final String? mergeSha;
  final String? baseSha;
  final String? refusedReason;

  @override
  String get recordType => 'effect.ack';

  @override
  Map<String, Object?> payloadToJson() => {
    'kind': kind.wire,
    'ack_ordinal': ackOrdinal,
    if (commitSha != null) 'commit_sha': commitSha,
    if (pushedSha != null) 'pushed_sha': pushedSha,
    if (prNumber != null) 'pr_number': prNumber,
    if (prUrl != null) 'pr_url': prUrl,
    if (reused != null) 'reused': reused,
    if (automergeMode != null) 'mode': automergeMode,
    if (mergeSha != null) 'merge_sha': mergeSha,
    if (baseSha != null) 'base_sha': baseSha,
    if (refusedReason != null) 'refused_reason': refusedReason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'effect_id': effectId,
    'outcome': outcome.wire,
    if (unknownReason != null) 'unknown_reason': unknownReason,
    if (resolvesRecordId != null) 'resolves_record_id': resolvesRecordId,
    if (receipt != null) 'receipt': receipt,
  };

  @override
  String idemKeyText(IdemContext context) => 'effect:$effectId:ack:$ackOrdinal';
}

/// `effect.unarmed` — commit-only posture.
final class EffectUnarmed extends EffectRecord {
  const EffectUnarmed({required this.attemptId, required this.posture});

  factory EffectUnarmed.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => EffectUnarmed(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    posture: _reqMap(payload, 'posture'),
  );

  final String attemptId;
  final Map<String, Object?> posture;

  @override
  String get recordType => 'effect.unarmed';

  @override
  Map<String, Object?> payloadToJson() => {'posture': posture};

  @override
  Map<String, Object?> correlationToJson() => {'attempt_id': attemptId};

  @override
  String idemKeyText(IdemContext context) => 'unarmed:$attemptId';
}

/// `effect.observation.claimed` — deliver-then-claim, at-least-once; appended
/// before the cursor save, duplicates die on `uq_idem`.
final class EffectObservationClaimed extends EffectRecord {
  const EffectObservationClaimed({
    required this.observationId,
    required this.claimOrder,
  });

  factory EffectObservationClaimed.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    final receipt = _envReq(envelope, 'receipt', envelope.receipt);
    if (!receipt.startsWith('obs:')) {
      throw FormatException(
        "effect.observation.claimed: receipt must be namespaced 'obs:<id>', "
        "got '$receipt'",
      );
    }
    return EffectObservationClaimed(
      observationId: receipt.substring('obs:'.length),
      claimOrder: ClaimOrder.fromWire(_req<String>(payload, 'claim_order')),
    );
  }

  final String observationId;
  final ClaimOrder claimOrder;

  @override
  String get recordType => 'effect.observation.claimed';

  @override
  Map<String, Object?> payloadToJson() => {'claim_order': claimOrder.wire};

  @override
  Map<String, Object?> correlationToJson() => {'receipt': 'obs:$observationId'};

  @override
  String idemKeyText(IdemContext context) => 'obs:$observationId';
}

/// `effect.command.received` — ingress record for a received `/command`; a
/// reused wire key with a different body IS a distinct record.
final class EffectCommandReceived extends EffectRecord {
  const EffectCommandReceived({
    required this.wireKey,
    required this.command,
    required this.fence,
    required this.fingerprint,
  });

  factory EffectCommandReceived.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => EffectCommandReceived(
    wireKey: _req<String>(payload, 'wire_key'),
    command: _req<String>(payload, 'command'),
    fence: _req<int>(payload, 'fence'),
    fingerprint: _req<String>(payload, 'fingerprint'),
  );

  final String wireKey;
  final String command;
  final int fence;
  final String fingerprint;

  @override
  String get recordType => 'effect.command.received';

  @override
  Map<String, Object?> payloadToJson() => {
    'wire_key': wireKey,
    'command': command,
    'fence': fence,
    'fingerprint': fingerprint,
  };

  @override
  Map<String, Object?> correlationToJson() => const {};

  @override
  String idemKeyText(IdemContext context) => 'cmd:$wireKey:$fingerprint';
}

/// `effect.command.refused` — appended when P8 already holds the wire key with
/// a different fingerprint; the detected conflict is a record, not an
/// unreachable column.
final class EffectCommandRefused extends EffectRecord {
  const EffectCommandRefused({
    required this.wireKey,
    required this.reason,
    required this.fingerprint,
    required this.priorFingerprint,
  });

  factory EffectCommandRefused.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => EffectCommandRefused(
    wireKey: _req<String>(payload, 'wire_key'),
    reason: CommandRefusalReason.fromWire(_req<String>(payload, 'reason')),
    fingerprint: _req<String>(payload, 'fingerprint'),
    priorFingerprint: _req<String>(payload, 'prior_fingerprint'),
  );

  final String wireKey;
  final CommandRefusalReason reason;
  final String fingerprint;
  final String priorFingerprint;

  @override
  String get recordType => 'effect.command.refused';

  @override
  Map<String, Object?> payloadToJson() => {
    'wire_key': wireKey,
    'reason': reason.wire,
    'fingerprint': fingerprint,
    'prior_fingerprint': priorFingerprint,
  };

  @override
  Map<String, Object?> correlationToJson() => const {};

  @override
  String idemKeyText(IdemContext context) =>
      'cmd-refused:$wireKey:$fingerprint';
}

/// `effect.ci.rework.commanded` — the outbound half; dedupe rides P8.
final class EffectCiReworkCommanded extends EffectRecord {
  const EffectCiReworkCommanded({
    required this.workBeadId,
    required this.round,
    required this.observationId,
    required this.checkName,
    this.noteDigest,
  });

  factory EffectCiReworkCommanded.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    final receipt = _envReq(envelope, 'receipt', envelope.receipt);
    if (!receipt.startsWith('obs:')) {
      throw FormatException(
        "effect.ci.rework.commanded: receipt must be namespaced 'obs:<id>', "
        "got '$receipt'",
      );
    }
    return EffectCiReworkCommanded(
      workBeadId: _envReq(envelope, 'work_bead_id', envelope.workBeadId),
      round: _envReq(envelope, 'round', envelope.round),
      observationId: receipt.substring('obs:'.length),
      checkName: _req<String>(payload, 'check_name'),
      noteDigest: _opt<String>(payload, 'note_digest'),
    );
  }

  final String workBeadId;
  final int round;
  final String observationId;
  final String checkName;
  final String? noteDigest;

  @override
  String get recordType => 'effect.ci.rework.commanded';

  @override
  Map<String, Object?> payloadToJson() => {
    'check_name': checkName,
    if (noteDigest != null) 'note_digest': noteDigest,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'work_bead_id': workBeadId,
    'round': round,
    'receipt': 'obs:$observationId',
  };

  @override
  String idemKeyText(IdemContext context) =>
      'github-ci:$workBeadId:r$round:$checkName:$observationId';
}
