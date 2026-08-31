// Family 1 — attempt lifecycle (§2 F1). One class per record type; sibling
// types sharing a payload shape ride one class with a phase discriminator.

part of '../trajectory_record.dart';

/// `attempt.process.exited` exit_kind — a respawn ENDS the attempt (§3).
enum ExitKind {
  exited,
  died,
  respawned;

  static ExitKind fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum LivenessCrossing {
  lost,
  regained;

  static LivenessCrossing fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum LeasePhase {
  acquired,
  released,
  swept;

  static LeasePhase fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum LeaseDisposition {
  held('held'),
  released('released'),
  killed('killed'),
  refusedUnsafe('refused_unsafe'),
  leftAdoptable('left_adoptable');

  const LeaseDisposition(this.wire);

  final String wire;

  static LeaseDisposition fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum AdoptOutcome {
  adopted,
  respawned;

  static AdoptOutcome fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// `attempt.round.retired` cause — `void` is the Dart keyword, hence [voided].
enum RoundRetireCause {
  rework('rework'),
  voided('void');

  const RoundRetireCause(this.wire);

  final String wire;

  static RoundRetireCause fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum MintPhase {
  failed,
  exhausted,
  abandoned,
  refused;

  static MintPhase fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

final class AttemptSessionStarted extends AttemptRecord {
  const AttemptSessionStarted({
    required this.sessionId,
    required this.grantId,
    required this.rig,
    required this.model,
    this.workBeadId,
    this.mountAttemptId,
  });

  factory AttemptSessionStarted.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptSessionStarted(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    // ck_grant_link: the grant link is the envelope grant_id, nothing else.
    grantId: _envReq(envelope, 'grant_id', envelope.grantId),
    workBeadId: envelope.workBeadId,
    mountAttemptId: envelope.mountAttemptId,
    rig: _req<String>(payload, 'rig'),
    model: _req<String>(payload, 'model'),
  );

  final String sessionId;
  final String grantId;
  final String? workBeadId;
  final String? mountAttemptId;
  final String rig;
  final String model;

  @override
  String get recordType => 'attempt.session.started';

  /// Grant-consuming: mounting the session is what spends the grant, so the
  /// belt checks the issuing row's token and expiry first (§5 step 2).
  @override
  String? get grantBeltIssuerType => grantIssuedRecordType;

  @override
  Map<String, Object?> payloadToJson() => {'rig': rig, 'model': model};

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'grant_id': grantId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
    if (mountAttemptId != null) 'mount_attempt_id': mountAttemptId,
  };

  @override
  String idemKeyText(IdemContext context) => 'session-started:$sessionId';
}

final class AttemptProcessStarted extends AttemptRecord {
  const AttemptProcessStarted({
    required this.attemptId,
    required this.sessionId,
    required this.incarnation,
    required this.pid,
    required this.pgid,
    this.predecessorAttemptId,
    this.round,
    this.stepPath,
    this.stepRound,
    this.worktree,
    this.branch,
  });

  factory AttemptProcessStarted.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptProcessStarted(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    incarnation: _envReq(envelope, 'incarnation', envelope.incarnation),
    round: envelope.round,
    stepPath: envelope.stepPath,
    stepRound: envelope.stepRound,
    worktree: envelope.worktree,
    branch: envelope.branch,
    pid: _req<int>(payload, 'pid'),
    pgid: _req<int>(payload, 'pgid'),
    predecessorAttemptId: _opt<String>(payload, 'predecessor_attempt_id'),
  );

  final String attemptId;
  final String sessionId;
  final int incarnation;
  final int? round;
  final String? stepPath;
  final int? stepRound;
  final String? worktree;
  final String? branch;
  final int pid;
  final int pgid;

  /// Set on a respawn successor — the chain is walkable in both directions.
  final String? predecessorAttemptId;

  @override
  String get recordType => 'attempt.process.started';

  @override
  Map<String, Object?> payloadToJson() => {
    'pid': pid,
    'pgid': pgid,
    if (predecessorAttemptId != null)
      'predecessor_attempt_id': predecessorAttemptId,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    'session_id': sessionId,
    'incarnation': incarnation,
    if (round != null) 'round': round,
    if (stepPath != null) 'step_path': stepPath,
    if (stepRound != null) 'step_round': stepRound,
    if (worktree != null) 'worktree': worktree,
    if (branch != null) 'branch': branch,
  };

  @override
  String idemKeyText(IdemContext context) => 'proc-started:$attemptId';
}

final class AttemptProcessExited extends AttemptRecord {
  const AttemptProcessExited({
    required this.attemptId,
    required this.pid,
    required this.exitKind,
    required this.inferred,
    this.sessionId,
    this.exitCode,
    this.reason,
  });

  factory AttemptProcessExited.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptProcessExited(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    sessionId: envelope.sessionId,
    pid: _req<int>(payload, 'pid'),
    exitCode: _opt<int>(payload, 'exit_code'),
    exitKind: ExitKind.fromWire(_req<String>(payload, 'exit_kind')),
    inferred: _req<bool>(payload, 'inferred'),
    reason: _opt<String>(payload, 'reason'),
  );

  final String attemptId;
  final String? sessionId;
  final int pid;
  final int? exitCode;
  final ExitKind exitKind;

  /// True ⇒ the service stamps envelope `provenance='inferred'`.
  final bool inferred;
  final String? reason;

  @override
  String get recordType => 'attempt.process.exited';

  @override
  Map<String, Object?> payloadToJson() => {
    'pid': pid,
    if (exitCode != null) 'exit_code': exitCode,
    'exit_kind': exitKind.wire,
    'inferred': inferred,
    if (reason != null) 'reason': reason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    if (sessionId != null) 'session_id': sessionId,
  };

  @override
  String idemKeyText(IdemContext context) => 'proc-exited:$attemptId';
}

/// `attempt.liveness.lost` / `.regained` — threshold transitions only; raw
/// beats ride `traj_pulse`, never the log.
final class AttemptLivenessTransition extends AttemptRecord {
  const AttemptLivenessTransition({
    required this.attemptId,
    required this.crossing,
    required this.lastBeatAt,
    required this.thresholdMs,
  });

  factory AttemptLivenessTransition.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptLivenessTransition(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    crossing: LivenessCrossing.fromWire(envelope.recordType.split('.').last),
    lastBeatAt: _reqDate(payload, 'last_beat_at'),
    thresholdMs: _req<int>(payload, 'threshold_ms'),
  );

  final String attemptId;
  final LivenessCrossing crossing;
  final DateTime lastBeatAt;
  final int thresholdMs;

  @override
  String get recordType => 'attempt.liveness.${crossing.wire}';

  @override
  Map<String, Object?> payloadToJson() => {
    'last_beat_at': lastBeatAt.toIso8601String(),
    'threshold_ms': thresholdMs,
  };

  @override
  Map<String, Object?> correlationToJson() => {'attempt_id': attemptId};

  // Keyed on the observed crossing: idempotent under retry of that
  // observation, distinct per flap.
  @override
  String idemKeyText(IdemContext context) =>
      'liveness:$attemptId:${lastBeatAt.microsecondsSinceEpoch}:'
      '${crossing.wire}';
}

/// `attempt.lease.acquired` / `.released` / `.swept` — the in-place breadcrumb
/// overwrite becomes append history.
final class AttemptLeaseTransition extends AttemptRecord {
  const AttemptLeaseTransition({
    required this.attemptId,
    required this.phase,
    required this.token,
    this.disposition,
    this.terminateResult,
    this.clearFailure,
  });

  factory AttemptLeaseTransition.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptLeaseTransition(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    phase: LeasePhase.fromWire(envelope.recordType.split('.').last),
    token: _req<String>(payload, 'token'),
    disposition: switch (_opt<String>(payload, 'disposition')) {
      null => null,
      final wire => LeaseDisposition.fromWire(wire),
    },
    terminateResult: _opt<String>(payload, 'terminate_result'),
    clearFailure: _opt<String>(payload, 'clear_failure'),
  );

  final String attemptId;
  final LeasePhase phase;

  /// The lease token IS the attempt_id (§3).
  final String token;
  final LeaseDisposition? disposition;
  final String? terminateResult;
  final String? clearFailure;

  @override
  String get recordType => 'attempt.lease.${phase.wire}';

  @override
  Map<String, Object?> payloadToJson() => {
    'token': token,
    if (disposition != null) 'disposition': disposition!.wire,
    if (terminateResult != null) 'terminate_result': terminateResult,
    if (clearFailure != null) 'clear_failure': clearFailure,
  };

  @override
  Map<String, Object?> correlationToJson() => {'attempt_id': attemptId};

  // A sweep is per-epoch (the sweeper re-finds the lease each boot); acquire
  // and release are once per attempt.
  @override
  String idemKeyText(IdemContext context) => phase == LeasePhase.swept
      ? 'lease-swept:$attemptId:${context.bootEpoch}'
      : 'lease:$attemptId:${phase.wire}';
}

final class AttemptAdoptProved extends AttemptRecord {
  const AttemptAdoptProved({
    required this.attemptId,
    required this.outcome,
    this.fencePgid,
    this.fencePid,
  });

  factory AttemptAdoptProved.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptAdoptProved(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    outcome: AdoptOutcome.fromWire(_req<String>(payload, 'outcome')),
    fencePgid: _opt<int>(payload, 'fence_pgid'),
    fencePid: _opt<int>(payload, 'fence_pid'),
  );

  final String attemptId;
  final AdoptOutcome outcome;
  final int? fencePgid;
  final int? fencePid;

  @override
  String get recordType => 'attempt.adopt.proved';

  @override
  Map<String, Object?> payloadToJson() => {
    'outcome': outcome.wire,
    if (fencePgid != null) 'fence_pgid': fencePgid,
    if (fencePid != null) 'fence_pid': fencePid,
  };

  @override
  Map<String, Object?> correlationToJson() => {'attempt_id': attemptId};

  @override
  String idemKeyText(IdemContext context) => 'adopt:$attemptId';
}

/// `attempt.terminal` — ONE terminal type, no tail; the former tail members
/// are §5 derived obligations. An unknown terminal is settleable: the settling
/// record carries `resolves_record_id` → the unknown one, and
/// `traj_terminal_guard` permits the chain while refusing two independent
/// terminals.
final class AttemptTerminal extends AttemptRecord {
  AttemptTerminal({
    required this.attemptId,
    required this.outcome,
    this.sessionId,
    this.workBeadId,
    this.unknownReason,
    this.resolvesRecordId,
    this.reason,
  }) {
    if (outcome == TerminalOutcome.unknown && unknownReason == null) {
      _refuse(recordType, 'outcome unknown requires unknown_reason');
    }
  }

  factory AttemptTerminal.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptTerminal(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    sessionId: envelope.sessionId,
    workBeadId: envelope.workBeadId,
    // ck_terminal: outcome is a required envelope column here.
    outcome: _envReq(envelope, 'outcome', envelope.outcome),
    unknownReason: envelope.unknownReason,
    resolvesRecordId: envelope.resolvesRecordId,
    reason: _opt<String>(payload, 'reason'),
  );

  final String attemptId;
  final String? sessionId;
  final String? workBeadId;
  final TerminalOutcome outcome;
  final String? unknownReason;

  /// Set on a SETTLING terminal, pointing at the unknown one it heals.
  final String? resolvesRecordId;
  final String? reason;

  /// The §5 terminal guard keys on this: `traj_terminal_guard` takes one row
  /// per attempt, so an unsettled terminal INSERTs and a second independent
  /// one dies on the PK.
  @override
  bool get isTerminal => true;

  @override
  bool get isSettling => resolvesRecordId != null;

  /// One of §5's three dolt-commit boundaries.
  @override
  bool get forcesDoltCommitBoundary => true;

  @override
  String get recordType => 'attempt.terminal';

  @override
  Map<String, Object?> payloadToJson() => {
    if (reason != null) 'reason': reason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    if (sessionId != null) 'session_id': sessionId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
    'outcome': outcome.wire,
    if (unknownReason != null) 'unknown_reason': unknownReason,
    if (resolvesRecordId != null) 'resolves_record_id': resolvesRecordId,
  };

  @override
  String idemKeyText(IdemContext context) => isSettling
      ? 'terminal-resolve:$attemptId:$resolvesRecordId'
      : 'terminal:$attemptId';
}

/// `attempt.round.retired` — bumps envelope `round` only; the operator
/// note/spec-clear stays a bd write.
final class AttemptRoundRetired extends AttemptRecord {
  const AttemptRoundRetired({
    required this.sessionId,
    required this.oldRound,
    required this.newRound,
    required this.cause,
  });

  factory AttemptRoundRetired.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptRoundRetired(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    oldRound: _req<int>(payload, 'old_round'),
    newRound: _req<int>(payload, 'new_round'),
    cause: RoundRetireCause.fromWire(_req<String>(payload, 'cause')),
  );

  final String sessionId;
  final int oldRound;
  final int newRound;
  final RoundRetireCause cause;

  @override
  String get recordType => 'attempt.round.retired';

  /// One of §5's three dolt-commit boundaries.
  @override
  bool get forcesDoltCommitBoundary => true;

  @override
  Map<String, Object?> payloadToJson() => {
    'old_round': oldRound,
    'new_round': newRound,
    'cause': cause.wire,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': newRound,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'round-retired:$sessionId:$oldRound';
}

final class AttemptReworkDeclined extends AttemptRecord {
  const AttemptReworkDeclined({
    required this.sessionId,
    required this.round,
    required this.reason,
  });

  factory AttemptReworkDeclined.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptReworkDeclined(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    reason: _req<String>(payload, 'reason'),
  );

  final String sessionId;
  final int round;
  final String reason;

  @override
  String get recordType => 'attempt.rework_declined';

  @override
  Map<String, Object?> payloadToJson() => {'reason': reason};

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'rework-declined:$sessionId:$round';
}

/// `attempt.mint.outcome` — the merge of the four mint flares, durable for the
/// first time; keyed by `work_bead_id` + `mount_attempt_id`.
final class AttemptMintOutcome extends AttemptRecord {
  const AttemptMintOutcome({
    required this.workBeadId,
    required this.mountAttemptId,
    required this.phase,
    required this.mintAttempt,
    this.maxAttempts,
    this.stage,
    this.reason,
  });

  factory AttemptMintOutcome.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptMintOutcome(
    workBeadId: _envReq(envelope, 'work_bead_id', envelope.workBeadId),
    mountAttemptId: _envReq(
      envelope,
      'mount_attempt_id',
      envelope.mountAttemptId,
    ),
    phase: MintPhase.fromWire(_req<String>(payload, 'phase')),
    mintAttempt: _req<int>(payload, 'mint_attempt'),
    maxAttempts: _opt<int>(payload, 'max_attempts'),
    stage: _opt<String>(payload, 'stage'),
    reason: _opt<String>(payload, 'reason'),
  );

  final String workBeadId;
  final String mountAttemptId;
  final MintPhase phase;
  final int mintAttempt;
  final int? maxAttempts;
  final String? stage;
  final String? reason;

  @override
  String get recordType => 'attempt.mint.outcome';

  @override
  Map<String, Object?> payloadToJson() => {
    'phase': phase.wire,
    'mint_attempt': mintAttempt,
    if (maxAttempts != null) 'max_attempts': maxAttempts,
    if (stage != null) 'stage': stage,
    if (reason != null) 'reason': reason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'work_bead_id': workBeadId,
    'mount_attempt_id': mountAttemptId,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'mint:$workBeadId:$mountAttemptId:${phase.wire}';
}

/// `attempt.note` — Q5 destination-declared journaling; the ordinal is
/// service-minted (free text has no natural key), accepted at-most-once.
final class AttemptNote extends AttemptRecord {
  const AttemptNote({
    required this.sessionId,
    required this.body,
    required this.channel,
    required this.noteOrdinal,
  });

  factory AttemptNote.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AttemptNote(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    body: _req<String>(payload, 'body'),
    channel: _req<String>(payload, 'channel'),
    noteOrdinal: _req<int>(payload, 'note_ordinal'),
  );

  final String sessionId;
  final String body;
  final String channel;
  final int noteOrdinal;

  @override
  String get recordType => 'attempt.note';

  @override
  Map<String, Object?> payloadToJson() => {
    'body': body,
    'channel': channel,
    'note_ordinal': noteOrdinal,
  };

  @override
  Map<String, Object?> correlationToJson() => {'session_id': sessionId};

  @override
  String idemKeyText(IdemContext context) => 'note:$sessionId:$noteOrdinal';
}

/// `worktree.provisioned` — `ck_provision` promotes base sha + branch to
/// required envelope columns.
final class WorktreeProvisioned extends AttemptRecord {
  const WorktreeProvisioned({
    required this.attemptId,
    required this.worktree,
    required this.branch,
    required this.baseSha,
    required this.adoptedExisting,
    this.sessionId,
  });

  factory WorktreeProvisioned.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => WorktreeProvisioned(
    attemptId: _envReq(envelope, 'attempt_id', envelope.attemptId),
    sessionId: envelope.sessionId,
    worktree: _envReq(envelope, 'worktree', envelope.worktree),
    branch: _envReq(envelope, 'branch', envelope.branch),
    baseSha: _envReq(envelope, 'commit_sha', envelope.commitSha),
    adoptedExisting: _req<bool>(payload, 'adopted_existing'),
  );

  final String attemptId;
  final String? sessionId;
  final String worktree;
  final String branch;

  /// Rides the envelope `commit_sha` digest column.
  final String baseSha;
  final bool adoptedExisting;

  @override
  String get recordType => 'worktree.provisioned';

  @override
  Map<String, Object?> payloadToJson() => {'adopted_existing': adoptedExisting};

  @override
  Map<String, Object?> correlationToJson() => {
    'attempt_id': attemptId,
    if (sessionId != null) 'session_id': sessionId,
    'worktree': worktree,
    'branch': branch,
    'commit_sha': baseSha,
  };

  @override
  String idemKeyText(IdemContext context) => 'wt-provisioned:$attemptId';
}

final class WorktreeReaped extends AttemptRecord {
  const WorktreeReaped({
    required this.sessionId,
    required this.worktree,
    this.branch,
    this.uncommitted,
    this.unpushed,
    this.stashes,
  });

  factory WorktreeReaped.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => WorktreeReaped(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    worktree: _envReq(envelope, 'worktree', envelope.worktree),
    branch: envelope.branch,
    uncommitted: _opt<int>(payload, 'uncommitted'),
    unpushed: _opt<int>(payload, 'unpushed'),
    stashes: _opt<int>(payload, 'stashes'),
  );

  final String sessionId;
  final String worktree;
  final String? branch;
  final int? uncommitted;
  final int? unpushed;
  final int? stashes;

  @override
  String get recordType => 'worktree.reaped';

  @override
  Map<String, Object?> payloadToJson() => {
    if (uncommitted != null) 'uncommitted': uncommitted,
    if (unpushed != null) 'unpushed': unpushed,
    if (stashes != null) 'stashes': stashes,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'worktree': worktree,
    if (branch != null) 'branch': branch,
  };

  @override
  String idemKeyText(IdemContext context) => 'wt-reaped:$sessionId:$worktree';
}

/// `worktree.held` — per-epoch (the hold is re-observed each boot), hence the
/// `<boot_epoch>` hole in its key.
final class WorktreeHeld extends AttemptRecord {
  const WorktreeHeld({
    required this.sessionId,
    required this.worktree,
    this.branch,
    this.uncommitted,
    this.unpushed,
    this.stashes,
  });

  factory WorktreeHeld.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => WorktreeHeld(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    worktree: _envReq(envelope, 'worktree', envelope.worktree),
    branch: envelope.branch,
    uncommitted: _opt<int>(payload, 'uncommitted'),
    unpushed: _opt<int>(payload, 'unpushed'),
    stashes: _opt<int>(payload, 'stashes'),
  );

  final String sessionId;
  final String worktree;
  final String? branch;
  final int? uncommitted;
  final int? unpushed;
  final int? stashes;

  @override
  String get recordType => 'worktree.held';

  @override
  Map<String, Object?> payloadToJson() => {
    if (uncommitted != null) 'uncommitted': uncommitted,
    if (unpushed != null) 'unpushed': unpushed,
    if (stashes != null) 'stashes': stashes,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'worktree': worktree,
    if (branch != null) 'branch': branch,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'wt-held:$sessionId:$worktree:${context.bootEpoch}';
}
