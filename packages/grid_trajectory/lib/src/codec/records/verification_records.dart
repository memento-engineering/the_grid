// Family 3 — verification bindings (§2 F3). The pin/verdict/gating/route keys
// carry <incarnation>: a supervised restart re-pins, re-runs, re-grades — each
// appends as fresh evidence, never a dedupe of incarnation 0's digests.

part of '../trajectory_record.dart';

enum VerdictTransport {
  artifact,
  operator,
  envelope;

  static VerdictTransport fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum FenceProbeOutcome {
  clear('clear'),
  present('present'),
  probeError('probe_error');

  const FenceProbeOutcome(this.wire);

  final String wire;

  static FenceProbeOutcome fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum RouteVerdictKind {
  advance,
  escalate;

  static RouteVerdictKind fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// `verify.scope.pinned` — digest capture point #1; env `commit_sha` carries
/// the head.
final class VerifyScopePinned extends VerificationRecord {
  const VerifyScopePinned({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.baseSha,
    required this.headSha,
    required this.branch,
    required this.commitCount,
    required this.diffDigest,
    required this.diffBytes,
  });

  factory VerifyScopePinned.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyScopePinned(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
    incarnation: _envReq(envelope, 'incarnation', envelope.incarnation),
    baseSha: _req<String>(payload, 'base_sha'),
    headSha: _req<String>(payload, 'head_sha'),
    branch: _req<String>(payload, 'branch'),
    commitCount: _req<int>(payload, 'commit_count'),
    diffDigest: _req<String>(payload, 'diff_digest'),
    diffBytes: _req<int>(payload, 'diff_bytes'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final String baseSha;
  final String headSha;
  final String branch;
  final int commitCount;
  final String diffDigest;
  final int diffBytes;

  @override
  String get recordType => 'verify.scope.pinned';

  @override
  Map<String, Object?> payloadToJson() => {
    'base_sha': baseSha,
    'head_sha': headSha,
    'branch': branch,
    'commit_count': commitCount,
    'diff_digest': diffDigest,
    'diff_bytes': diffBytes,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'incarnation': incarnation,
    'commit_sha': headSha,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'pin:$sessionId:$round:$stepPath:$stepRound:$incarnation';
}

/// `verify.verdict.recorded` — observer-written: the service copies the
/// critic's on-disk artifact, stamps HEAD at record time (env `commit_sha`)
/// and `sha_drift` against the pin.
final class VerifyVerdictRecorded extends VerificationRecord {
  VerifyVerdictRecorded({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.headShaAtRecord,
    required this.lane,
    required this.rubricVersion,
    required this.grade,
    required this.rationale,
    required this.transport,
    required this.pinnedHeadSha,
    required this.shaDrift,
  }) {
    if (transport == VerdictTransport.envelope) {
      _refuse(recordType, "transport 'envelope' is verify.verdict.recovered");
    }
  }

  factory VerifyVerdictRecorded.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyVerdictRecorded(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
    incarnation: _envReq(envelope, 'incarnation', envelope.incarnation),
    headShaAtRecord: _envReq(envelope, 'commit_sha', envelope.commitSha),
    lane: _req<String>(payload, 'lane'),
    rubricVersion: _req<String>(payload, 'rubric_version'),
    grade: _req<String>(payload, 'grade'),
    rationale: _req<String>(payload, 'rationale'),
    transport: VerdictTransport.fromWire(_req<String>(payload, 'transport')),
    pinnedHeadSha: _req<String>(payload, 'pinned_head_sha'),
    shaDrift: _req<bool>(payload, 'sha_drift'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final String headShaAtRecord;
  final String lane;
  final String rubricVersion;

  /// A–F, one char.
  final String grade;
  final String rationale;
  final VerdictTransport transport;
  final String pinnedHeadSha;
  final bool shaDrift;

  @override
  String get recordType => 'verify.verdict.recorded';

  @override
  Map<String, Object?> payloadToJson() => {
    'lane': lane,
    'rubric_version': rubricVersion,
    'grade': grade,
    'rationale': rationale,
    'transport': transport.wire,
    'pinned_head_sha': pinnedHeadSha,
    'sha_drift': shaDrift,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'incarnation': incarnation,
    'commit_sha': headShaAtRecord,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'verdict:$sessionId:$round:$stepPath:$stepRound:$incarnation:$lane';
}

/// `verify.verdict.recovered` — its own type so the recovered verdict and the
/// artifact one can BOTH exist (distinct idem keys, no incarnation in this
/// one); envelope provenance is `inferred`, transport pinned to `envelope`.
final class VerifyVerdictRecovered extends VerificationRecord {
  const VerifyVerdictRecovered({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.lane,
    required this.rubricVersion,
    required this.grade,
    required this.rationale,
    required this.pinnedHeadSha,
    required this.shaDrift,
  });

  factory VerifyVerdictRecovered.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    final transport = _req<String>(payload, 'transport');
    if (transport != VerdictTransport.envelope.wire) {
      throw FormatException(
        "verify.verdict.recovered: transport must be 'envelope', got "
        "'$transport'",
      );
    }
    return VerifyVerdictRecovered(
      sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
      round: _envReq(envelope, 'round', envelope.round),
      stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
      stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
      lane: _req<String>(payload, 'lane'),
      rubricVersion: _req<String>(payload, 'rubric_version'),
      grade: _req<String>(payload, 'grade'),
      rationale: _req<String>(payload, 'rationale'),
      pinnedHeadSha: _req<String>(payload, 'pinned_head_sha'),
      shaDrift: _req<bool>(payload, 'sha_drift'),
    );
  }

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final String lane;
  final String rubricVersion;
  final String grade;
  final String rationale;
  final String pinnedHeadSha;
  final bool shaDrift;

  @override
  String get recordType => 'verify.verdict.recovered';

  @override
  Map<String, Object?> payloadToJson() => {
    'lane': lane,
    'rubric_version': rubricVersion,
    'grade': grade,
    'rationale': rationale,
    'transport': VerdictTransport.envelope.wire,
    'pinned_head_sha': pinnedHeadSha,
    'sha_drift': shaDrift,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'verdict-recovered:$sessionId:$round:$stepPath:$stepRound:$lane';
}

/// `verify.gating.rc` — the sh wrapper stamps HEAD at exec start (a named
/// tg-zfek code change); env `commit_sha` carries it.
final class VerifyGatingRc extends VerificationRecord {
  const VerifyGatingRc({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.rc,
    required this.durationMs,
    required this.planDigest,
    required this.headShaAtExec,
  });

  factory VerifyGatingRc.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyGatingRc(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
    incarnation: _envReq(envelope, 'incarnation', envelope.incarnation),
    rc: _req<int>(payload, 'rc'),
    durationMs: _req<int>(payload, 'duration_ms'),
    planDigest: _req<String>(payload, 'plan_digest'),
    headShaAtExec: _req<String>(payload, 'head_sha_at_exec'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final int rc;
  final int durationMs;
  final String planDigest;
  final String headShaAtExec;

  @override
  String get recordType => 'verify.gating.rc';

  @override
  Map<String, Object?> payloadToJson() => {
    'rc': rc,
    'duration_ms': durationMs,
    'plan_digest': planDigest,
    'head_sha_at_exec': headShaAtExec,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'incarnation': incarnation,
    'commit_sha': headShaAtExec,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'gating:$sessionId:$round:$stepPath:$stepRound:$incarnation';
}

/// `verify.completion.fence` — digest capture point #2; env `commit_sha` =
/// HEAD at probe.
final class VerifyCompletionFence extends VerificationRecord {
  const VerifyCompletionFence({
    required this.attemptId,
    required this.outcome,
    required this.headShaAtProbe,
  });

  factory VerifyCompletionFence.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyCompletionFence(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    headShaAtProbe: _envReq(envelope, 'commit_sha', envelope.commitSha),
    outcome: FenceProbeOutcome.fromWire(_req<String>(payload, 'outcome')),
  );

  final String attemptId;
  final FenceProbeOutcome outcome;
  final String headShaAtProbe;

  @override
  String get recordType => 'verify.completion.fence';

  @override
  Map<String, Object?> payloadToJson() => {'outcome': outcome.wire};

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    'commit_sha': headShaAtProbe,
  };

  @override
  String idemKeyText(IdemContext context) => 'fence-probe:$attemptId';
}

/// `verify.route.verdict` — fail-closed missing-grade→F stays visible (NULL
/// source_record_id in `grades`); the operator-override variant appends on
/// adjudication with `transport='operator'` and keys on the gate cycle.
final class VerifyRouteVerdict extends VerificationRecord {
  VerifyRouteVerdict({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.verdict,
    required this.rule,
    required this.grades,
    this.incarnation,
    this.spread,
    this.operatorGateId,
    this.operatorCycle,
  }) {
    if (isOperatorOverride) {
      if (operatorGateId == null || operatorCycle == null) {
        _refuse(
          recordType,
          'operator variant requires operatorGateId and operatorCycle',
        );
      }
    } else if (incarnation == null) {
      _refuse(recordType, 'service variant requires incarnation');
    }
  }

  factory VerifyRouteVerdict.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyRouteVerdict(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
    incarnation: envelope.incarnation,
    verdict: RouteVerdictKind.fromWire(_req<String>(payload, 'verdict')),
    rule: _req<String>(payload, 'rule'),
    spread: _opt<num>(payload, 'spread')?.toDouble(),
    grades: _reqMap(payload, 'grades'),
    operatorGateId: envelope.gateId,
    operatorCycle: _opt<int>(payload, 'operator_cycle'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;

  /// Required on the service variant; absent on the operator override.
  final int? incarnation;
  final RouteVerdictKind verdict;
  final String rule;
  final double? spread;

  /// Per-lane `{grade, source_record_id, sha_drift}`.
  final Map<String, Object?> grades;
  final String? operatorGateId;
  final int? operatorCycle;

  bool get isOperatorOverride =>
      operatorGateId != null || operatorCycle != null;

  @override
  String get recordType => 'verify.route.verdict';

  @override
  Map<String, Object?> payloadToJson() => {
    'verdict': verdict.wire,
    'rule': rule,
    if (spread != null) 'spread': spread,
    'grades': grades,
    if (isOperatorOverride) 'transport': 'operator',
    if (operatorCycle != null) 'operator_cycle': operatorCycle,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    if (incarnation != null) 'incarnation': incarnation,
    if (operatorGateId != null) 'gate_id': operatorGateId,
  };

  @override
  String idemKeyText(IdemContext context) => isOperatorOverride
      ? 'route-operator:$operatorGateId:$operatorCycle'
      : 'route:$sessionId:$round:$stepPath:$stepRound:$incarnation';
}

/// `verify.usage.telemetry` — FT-2 capture-only; nothing in it is a decision
/// input (P7 folds async).
final class VerifyUsageTelemetry extends VerificationRecord {
  const VerifyUsageTelemetry({
    required this.attemptId,
    required this.model,
    this.sessionId,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.premiumRequests,
    this.numTurns,
    this.durationMs,
  });

  factory VerifyUsageTelemetry.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => VerifyUsageTelemetry(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    sessionId: envelope.sessionId,
    model: _req<String>(payload, 'model'),
    tokensIn: _opt<int>(payload, 'tokens_in'),
    tokensOut: _opt<int>(payload, 'tokens_out'),
    costUsd: _opt<num>(payload, 'cost_usd')?.toDouble(),
    premiumRequests: _opt<int>(payload, 'premium_requests'),
    numTurns: _opt<int>(payload, 'num_turns'),
    durationMs: _opt<int>(payload, 'duration_ms'),
  );

  final String attemptId;
  final String? sessionId;
  final String model;
  final int? tokensIn;
  final int? tokensOut;
  final double? costUsd;
  final int? premiumRequests;
  final int? numTurns;
  final int? durationMs;

  @override
  String get recordType => 'verify.usage.telemetry';

  @override
  Map<String, Object?> payloadToJson() => {
    'model': model,
    if (tokensIn != null) 'tokens_in': tokensIn,
    if (tokensOut != null) 'tokens_out': tokensOut,
    if (costUsd != null) 'cost_usd': costUsd,
    if (premiumRequests != null) 'premium_requests': premiumRequests,
    if (numTurns != null) 'num_turns': numTurns,
    if (durationMs != null) 'duration_ms': durationMs,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    if (sessionId != null) 'session_id': sessionId,
  };

  @override
  String idemKeyText(IdemContext context) => 'usage:$attemptId';
}

/// `verify.ci.concluded` — CI conclusions bind to what was verified; the
/// observation id rides the envelope receipt as `obs:<id>`.
final class VerifyCiConcluded extends VerificationRecord {
  const VerifyCiConcluded({
    required this.observationId,
    required this.headSha,
    required this.repo,
    required this.checkName,
    required this.conclusion,
    this.workBeadId,
    this.sessionId,
  });

  factory VerifyCiConcluded.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) {
    final receipt = _envReq(envelope, 'receipt', envelope.receipt);
    if (!receipt.startsWith('obs:')) {
      throw FormatException(
        "verify.ci.concluded: receipt must be namespaced 'obs:<id>', got "
        "'$receipt'",
      );
    }
    return VerifyCiConcluded(
      observationId: receipt.substring('obs:'.length),
      headSha: _envReq(envelope, 'commit_sha', envelope.commitSha),
      workBeadId: envelope.workBeadId,
      sessionId: envelope.sessionId,
      repo: _req<String>(payload, 'repo'),
      checkName: _req<String>(payload, 'check_name'),
      conclusion: _req<String>(payload, 'conclusion'),
    );
  }

  final String observationId;
  final String headSha;
  final String? workBeadId;
  final String? sessionId;
  final String repo;
  final String checkName;
  final String conclusion;

  @override
  String get recordType => 'verify.ci.concluded';

  @override
  Map<String, Object?> payloadToJson() => {
    'repo': repo,
    'check_name': checkName,
    'conclusion': conclusion,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'receipt': 'obs:$observationId',
    'commit_sha': headSha,
    if (workBeadId != null) 'work_bead_id': workBeadId,
    if (sessionId != null) 'session_id': sessionId,
  };

  @override
  String idemKeyText(IdemContext context) => 'ci:$observationId';
}
