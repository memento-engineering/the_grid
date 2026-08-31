// Family 2 — admission grants and authority (§2 F2).

part of '../trajectory_record.dart';

/// Which of the two grant-close record types this is.
enum GrantClosure {
  expired,
  released;

  static GrantClosure fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// The grant-close payload cause — `superseded` closes via `.released`.
enum GrantCloseCause {
  expired,
  released,
  superseded;

  static GrantCloseCause fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum EpochPhase {
  advanced,
  closed;

  static EpochPhase fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum EpochCause {
  boot,
  steal,
  down;

  static EpochCause fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum StealReason {
  stale,
  corrupt;

  static StealReason fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum FederationLeasePhase {
  granted,
  reaped,
  expired;

  static FederationLeasePhase fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

/// `admission.grant.issued` — the tg-y4fd grant. `ck_grant` promotes grant_id,
/// expiry, and the fencing token to required envelope columns; `basis` stays
/// JSON deliberately (a snapshot document, not a join surface).
final class AdmissionGrantIssued extends AdmissionRecord {
  const AdmissionGrantIssued({
    required this.grantId,
    required this.workBeadId,
    required this.mountAttemptId,
    required this.fencingToken,
    required this.expiresAt,
    required this.basis,
  });

  factory AdmissionGrantIssued.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionGrantIssued(
    grantId: _envReq(envelope, 'grant_id', envelope.grantId),
    workBeadId: _envReq(envelope, 'work_bead_id', envelope.workBeadId),
    mountAttemptId: _envReq(
      envelope,
      'mount_attempt_id',
      envelope.mountAttemptId,
    ),
    fencingToken: _envReq(envelope, 'fencing_token', envelope.fencingToken),
    expiresAt: _envReq(envelope, 'expires_at', envelope.expiresAt),
    basis: _reqMap(payload, 'basis'),
  );

  final String grantId;
  final String workBeadId;
  final String mountAttemptId;
  final int fencingToken;
  final DateTime expiresAt;

  /// `{bead_rev, approved_label_rev, validation_plan_digest, issue_type,
  /// dep_revs, drive_list_member, snapshot_captured_at, cap_override?}`.
  final Map<String, Object?> basis;

  @override
  String get recordType => 'admission.grant.issued';

  @override
  Map<String, Object?> payloadToJson() => {'basis': basis};

  @override
  Map<String, Object?> correlationToJson() => {
    'grant_id': grantId,
    'work_bead_id': workBeadId,
    'mount_attempt_id': mountAttemptId,
    'fencing_token': fencingToken,
    'expires_at': expiresAt.toIso8601String(),
  };

  @override
  String idemKeyText(IdemContext context) => 'grant:$grantId:issued';
}

final class AdmissionGrantConsumed extends AdmissionRecord {
  const AdmissionGrantConsumed({
    required this.grantId,
    this.sessionId,
    this.workBeadId,
  });

  factory AdmissionGrantConsumed.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionGrantConsumed(
    grantId: _envReq(envelope, 'grant_id', envelope.grantId),
    sessionId: envelope.sessionId,
    workBeadId: envelope.workBeadId,
  );

  final String grantId;
  final String? sessionId;
  final String? workBeadId;

  @override
  String get recordType => 'admission.grant.consumed';

  @override
  Map<String, Object?> payloadToJson() => const {};

  @override
  Map<String, Object?> correlationToJson() => {
    'grant_id': grantId,
    if (sessionId != null) 'session_id': sessionId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
  };

  @override
  String idemKeyText(IdemContext context) => 'grant:$grantId:consumed';
}

/// `admission.grant.expired` / `.released` — level-triggered lease lifecycle.
final class AdmissionGrantClosed extends AdmissionRecord {
  const AdmissionGrantClosed({
    required this.grantId,
    required this.closure,
    this.cause,
    this.workBeadId,
  });

  factory AdmissionGrantClosed.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionGrantClosed(
    grantId: _envReq(envelope, 'grant_id', envelope.grantId),
    closure: GrantClosure.fromWire(envelope.recordType.split('.').last),
    workBeadId: envelope.workBeadId,
    cause: switch (_opt<String>(payload, 'cause')) {
      null => null,
      final wire => GrantCloseCause.fromWire(wire),
    },
  );

  final String grantId;
  final GrantClosure closure;
  final GrantCloseCause? cause;
  final String? workBeadId;

  @override
  String get recordType => 'admission.grant.${closure.wire}';

  @override
  Map<String, Object?> payloadToJson() => {
    if (cause != null) 'cause': cause!.wire,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'grant_id': grantId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
  };

  @override
  String idemKeyText(IdemContext context) => 'grant:$grantId:${closure.wire}';
}

/// `admission.refused` — level-shaped key: re-fires exactly when the evaluated
/// basis changed (new snapshot_rev), dedupes an idle ineligible bead. One row
/// per FAILING clause per evaluation.
final class AdmissionRefused extends AdmissionRecord {
  const AdmissionRefused({
    required this.workBeadId,
    required this.mountAttemptId,
    required this.clause,
    required this.snapshotRev,
    this.detail,
  });

  factory AdmissionRefused.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionRefused(
    workBeadId: _envReq(envelope, 'work_bead_id', envelope.workBeadId),
    // §3: a mount_attempt_id is minted per admission evaluation — grant OR
    // refusal.
    mountAttemptId: _envReq(
      envelope,
      'mount_attempt_id',
      envelope.mountAttemptId,
    ),
    clause: _req<String>(payload, 'clause'),
    snapshotRev: _req<String>(payload, 'snapshot_rev'),
    detail: _optMap(payload, 'detail'),
  );

  final String workBeadId;
  final String mountAttemptId;
  final String clause;
  final String snapshotRev;

  /// Origin/floor for trust refusals; dead_session + pgids for void-refused.
  final Map<String, Object?>? detail;

  @override
  String get recordType => 'admission.refused';

  @override
  Map<String, Object?> payloadToJson() => {
    'clause': clause,
    'snapshot_rev': snapshotRev,
    if (detail != null) 'detail': detail,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'work_bead_id': workBeadId,
    'mount_attempt_id': mountAttemptId,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'refused:$workBeadId:$clause:$snapshotRev';
}

/// `admission.restored` — per-clause and independent of overall eligibility;
/// also the operator cap-release vehicle (`clause='attempt-cap'`, actor set).
final class AdmissionRestored extends AdmissionRecord {
  const AdmissionRestored({
    required this.workBeadId,
    required this.clause,
    required this.refusalRecordId,
    this.actor,
  });

  factory AdmissionRestored.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionRestored(
    workBeadId: _envReq(envelope, 'work_bead_id', envelope.workBeadId),
    refusalRecordId: _envReq(
      envelope,
      'resolves_record_id',
      envelope.resolvesRecordId,
    ),
    clause: _req<String>(payload, 'clause'),
    actor: _opt<String>(payload, 'actor'),
  );

  final String workBeadId;
  final String clause;

  /// Rides `resolves_record_id` → the refusal this clears.
  final String refusalRecordId;
  final String? actor;

  @override
  String get recordType => 'admission.restored';

  @override
  Map<String, Object?> payloadToJson() => {
    'clause': clause,
    if (actor != null) 'actor': actor,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'work_bead_id': workBeadId,
    'resolves_record_id': refusalRecordId,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'restored:$workBeadId:$clause:$refusalRecordId';
}

/// `admission.drive.approved` — one per boot epoch; a grant-basis input.
final class AdmissionDriveApproved extends AdmissionRecord {
  const AdmissionDriveApproved({required this.approvedBeads});

  factory AdmissionDriveApproved.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AdmissionDriveApproved(
    approvedBeads: _req<List<Object?>>(
      payload,
      'approved_beads',
    ).cast<String>(),
  );

  final List<String> approvedBeads;

  @override
  String get recordType => 'admission.drive.approved';

  @override
  Map<String, Object?> payloadToJson() => {'approved_beads': approvedBeads};

  @override
  Map<String, Object?> correlationToJson() => const {};

  @override
  String idemKeyText(IdemContext context) =>
      'drive:${context.station}:${context.bootEpoch}';
}

/// `authority.epoch.advanced` / `.closed` — a steal finally leaves a monotonic
/// record; `.closed` is appended only after the obligation tick reached
/// fixpoint (that is the definition of a clean down, §5).
final class AuthorityEpochTransition extends AdmissionRecord {
  const AuthorityEpochTransition({
    required this.phase,
    required this.epoch,
    required this.pid,
    required this.pgid,
    required this.cause,
    this.priorEpoch,
    this.priorPid,
    this.stealReason,
    this.outstandingObligations,
  });

  factory AuthorityEpochTransition.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => AuthorityEpochTransition(
    phase: EpochPhase.fromWire(envelope.recordType.split('.').last),
    epoch: _req<int>(payload, 'epoch'),
    pid: _req<int>(payload, 'pid'),
    pgid: _req<int>(payload, 'pgid'),
    cause: EpochCause.fromWire(_req<String>(payload, 'cause')),
    priorEpoch: _opt<int>(payload, 'prior_epoch'),
    priorPid: _opt<int>(payload, 'prior_pid'),
    stealReason: switch (_opt<String>(payload, 'steal_reason')) {
      null => null,
      final wire => StealReason.fromWire(wire),
    },
    outstandingObligations: _opt<int>(payload, 'outstanding_obligations'),
  );

  final EpochPhase phase;
  final int epoch;
  final int pid;
  final int pgid;
  final EpochCause cause;
  final int? priorEpoch;
  final int? priorPid;
  final StealReason? stealReason;

  /// On `.closed`: nonzero when down could not reach fixpoint (§5) — the
  /// successor boot's tick inherits the remainder.
  final int? outstandingObligations;

  @override
  String get recordType => 'authority.epoch.${phase.wire}';

  @override
  Map<String, Object?> payloadToJson() => {
    'epoch': epoch,
    'pid': pid,
    'pgid': pgid,
    'cause': cause.wire,
    if (priorEpoch != null) 'prior_epoch': priorEpoch,
    if (priorPid != null) 'prior_pid': priorPid,
    if (stealReason != null) 'steal_reason': stealReason!.wire,
    if (outstandingObligations != null)
      'outstanding_obligations': outstandingObligations,
  };

  @override
  Map<String, Object?> correlationToJson() => const {};

  // `<epoch>` here is the payload epoch being advanced/closed, not the
  // writer's boot_epoch (a successor closes its predecessor's epoch).
  @override
  String idemKeyText(IdemContext context) =>
      'epoch:${context.station}:$epoch:${phase.wire}';
}

/// `federation.lease.granted` / `.reaped` / `.expired` — owner-side lease
/// state; beats ride `traj_pulse` (kind='lease'), never the log.
final class FederationLeaseTransition extends AdmissionRecord {
  const FederationLeaseTransition({
    required this.phase,
    required this.leaseId,
    required this.kind,
    required this.lessee,
    required this.fencingToken,
    required this.expiresAt,
    this.ttlS,
  });

  factory FederationLeaseTransition.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => FederationLeaseTransition(
    phase: FederationLeasePhase.fromWire(envelope.recordType.split('.').last),
    // The lease id rides the envelope receipt column (§1).
    leaseId: _envReq(envelope, 'receipt', envelope.receipt),
    fencingToken: _envReq(envelope, 'fencing_token', envelope.fencingToken),
    expiresAt: _envReq(envelope, 'expires_at', envelope.expiresAt),
    kind: _req<String>(payload, 'kind'),
    lessee: _req<String>(payload, 'lessee'),
    ttlS: _opt<int>(payload, 'ttl_s'),
  );

  final FederationLeasePhase phase;
  final String leaseId;
  final String kind;
  final String lessee;
  final int fencingToken;
  final DateTime expiresAt;
  final int? ttlS;

  @override
  String get recordType => 'federation.lease.${phase.wire}';

  @override
  Map<String, Object?> payloadToJson() => {
    'kind': kind,
    'lessee': lessee,
    if (ttlS != null) 'ttl_s': ttlS,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'receipt': leaseId,
    'fencing_token': fencingToken,
    'expires_at': expiresAt.toIso8601String(),
  };

  @override
  String idemKeyText(IdemContext context) => 'flease:$leaseId:${phase.wire}';
}
