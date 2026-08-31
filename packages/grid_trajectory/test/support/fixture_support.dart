/// Shared fixture machinery for the §2.6 rule-4 golden suite and
/// `tool/regenerate_fixtures.dart`.
///
/// The checked-in fixtures under `test/fixtures/` are the source of truth: a
/// payload-shape change without a `type_version` bump fails the round-trip
/// against them, and regenerating them is a deliberate, reviewed act.
library;

import 'package:grid_trajectory/grid_trajectory.dart';

/// The service-stamped grammar holes, fixed for fixtures.
const fixtureContext = IdemContext(station: 'lunar', bootEpoch: 7);

/// The fixture file body for one record.
Map<String, Object?> fixtureFor(TrajectoryRecord record) => {
  'record_type': record.recordType,
  'type_version': record.typeVersion,
  'family': record.family.wire,
  'envelope': record.correlationToJson(),
  'payload': record.payloadToJson(),
  'idem_key_text': record.idemKeyText(fixtureContext),
  'idem_key': record.idemKey(fixtureContext),
};

/// Rebuilds the full envelope row a fixture describes: service-stamped base
/// columns + the fixture's correlation block. `seat` is service-derived from
/// the bead's store prefix, so fixtures omit it and it is supplied here
/// (ck_seat).
TrajectoryEnvelope envelopeFor(Map<String, Object?> fixture) {
  final overrides = (fixture['envelope'] as Map).cast<String, Object?>();
  final json = <String, Object?>{
    'record_id': '01FIXTURE0000000000000RECD',
    'idem_key': fixture['idem_key'],
    'idem_key_text': fixture['idem_key_text'],
    'family': fixture['family'],
    'record_type': fixture['record_type'],
    'type_version': fixture['type_version'],
    'occurred_at': '2026-08-31T12:00:00.000123Z',
    'recorded_at': '2026-08-31T12:00:00.000456Z',
    'station': fixtureContext.station,
    'authority_id': '${fixtureContext.station}/${fixtureContext.bootEpoch}',
    'boot_epoch': fixtureContext.bootEpoch,
    'source': 'fixture',
    'payload': (fixture['payload'] as Map).cast<String, Object?>(),
    ...overrides,
  };
  if (json['work_bead_id'] != null) {
    json['seat'] ??= 'tg';
  }
  return TrajectoryEnvelope.fromJson(json);
}

final _beat = DateTime.utc(2026, 8, 31, 11, 58, 3, 0, 250);
final _expiry = DateTime.utc(2026, 8, 31, 12, 30);

// ── maximum-width variants (§5: "a stage-0 test constructs a
// maximum-length key of every type") ──────────────────────────────────────

/// Every interpolated identity field at its §4 DDL width; free-width payload
/// identities (observation/wire/lease keys) at a generous 128.
final String _xSession = 's' * 40; // session_id VARCHAR(40)
final String _xBead = 'b' * 40; // work_bead_id VARCHAR(40)
final String _xUlid = 'A' * 26; // CHAR(26) ids
final String _xPath = 'p' * 255; // step_path/worktree VARCHAR(255)
final String _xGate = 'g' * 64; // gate_id VARCHAR(64)
final String _xBranch = 'r' * 160; // branch VARCHAR(160)
final String _xSha = 'a' * 40; // CHAR(40)
final String _xHex64 = 'f' * 64; // effect_id / digests CHAR(64)
final String _xFree = 'k' * 128; // free-width payload identities
const int _xInt = 2147483647;

/// The service-stamped holes at their widest: station VARCHAR(64), a 64-bit
/// boot epoch.
final maxLengthContext = IdemContext(
  station: 'x' * 64,
  bootEpoch: 9223372036854775807,
);

/// One maximum-width record per §2 record type — the same 50 as
/// [sampleRecords], with every grammar interpolation at its column bound.
List<TrajectoryRecord> maxLengthSampleRecords() => [
  // Family 1 — attempt lifecycle.
  AttemptSessionStarted(
    sessionId: _xSession,
    grantId: _xUlid,
    workBeadId: _xBead,
    mountAttemptId: _xUlid,
    rig: 'operator',
    model: 'molecule',
  ),
  AttemptProcessStarted(
    attemptId: _xUlid,
    sessionId: _xSession,
    incarnation: _xInt,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    worktree: _xPath,
    branch: _xBranch,
    pid: _xInt,
    pgid: _xInt,
    predecessorAttemptId: _xUlid,
  ),
  AttemptProcessExited(
    attemptId: _xUlid,
    sessionId: _xSession,
    pid: _xInt,
    exitCode: 255,
    exitKind: ExitKind.exited,
    inferred: false,
    reason: 'clean exit',
  ),
  AttemptLivenessTransition(
    attemptId: _xUlid,
    crossing: LivenessCrossing.lost,
    lastBeatAt: _beat,
    thresholdMs: _xInt,
  ),
  AttemptLivenessTransition(
    attemptId: _xUlid,
    crossing: LivenessCrossing.regained,
    lastBeatAt: _beat.add(const Duration(seconds: 120)),
    thresholdMs: _xInt,
  ),
  AttemptLeaseTransition(
    attemptId: _xUlid,
    phase: LeasePhase.acquired,
    token: _xUlid,
    disposition: LeaseDisposition.held,
  ),
  AttemptLeaseTransition(
    attemptId: _xUlid,
    phase: LeasePhase.released,
    token: _xUlid,
    disposition: LeaseDisposition.released,
  ),
  AttemptLeaseTransition(
    attemptId: _xUlid,
    phase: LeasePhase.swept,
    token: _xUlid,
    disposition: LeaseDisposition.killed,
    terminateResult: 'SIGKILL delivered',
  ),
  AttemptAdoptProved(
    attemptId: _xUlid,
    outcome: AdoptOutcome.adopted,
    fencePgid: _xInt,
    fencePid: _xInt,
  ),
  AttemptTerminal(
    attemptId: _xUlid,
    sessionId: _xSession,
    workBeadId: _xBead,
    outcome: TerminalOutcome.settled,
    resolvesRecordId: _xUlid,
  ),
  AttemptRoundRetired(
    sessionId: _xSession,
    oldRound: _xInt,
    newRound: _xInt,
    cause: RoundRetireCause.rework,
  ),
  AttemptReworkDeclined(
    sessionId: _xSession,
    round: _xInt,
    reason: 'operator declined',
  ),
  AttemptMintOutcome(
    workBeadId: _xBead,
    mountAttemptId: _xUlid,
    phase: MintPhase.exhausted,
    mintAttempt: _xInt,
    maxAttempts: _xInt,
    stage: 'pour',
    reason: 'graph-apply timeout',
  ),
  AttemptNote(
    sessionId: _xSession,
    body: 'note body',
    channel: 'obligation-stuck',
    noteOrdinal: _xInt,
  ),
  WorktreeProvisioned(
    attemptId: _xUlid,
    sessionId: _xSession,
    worktree: _xPath,
    branch: _xBranch,
    baseSha: _xSha,
    adoptedExisting: false,
  ),
  WorktreeReaped(
    sessionId: _xSession,
    worktree: _xPath,
    branch: _xBranch,
    uncommitted: 0,
    unpushed: 0,
    stashes: 0,
  ),
  WorktreeHeld(
    sessionId: _xSession,
    worktree: _xPath,
    branch: _xBranch,
    uncommitted: _xInt,
    unpushed: _xInt,
    stashes: _xInt,
  ),
  // Family 2 — admission grants and authority.
  AdmissionGrantIssued(
    grantId: _xUlid,
    workBeadId: _xBead,
    mountAttemptId: _xUlid,
    fencingToken: 9223372036854775807,
    expiresAt: _expiry,
    basis: const {'bead_rev': 'r12'},
  ),
  AdmissionGrantConsumed(
    grantId: _xUlid,
    sessionId: _xSession,
    workBeadId: _xBead,
  ),
  AdmissionGrantClosed(
    grantId: _xUlid,
    closure: GrantClosure.expired,
    cause: GrantCloseCause.expired,
    workBeadId: _xBead,
  ),
  AdmissionGrantClosed(
    grantId: _xUlid,
    closure: GrantClosure.released,
    cause: GrantCloseCause.superseded,
    workBeadId: _xBead,
  ),
  AdmissionRefused(
    workBeadId: _xBead,
    mountAttemptId: _xUlid,
    clause: 'c' * 48,
    snapshotRev: 'v' * 64,
    detail: const {'k': 'v'},
  ),
  AdmissionRestored(
    workBeadId: _xBead,
    clause: 'c' * 48,
    refusalRecordId: _xUlid,
    actor: 'nico',
  ),
  AdmissionDriveApproved(approvedBeads: [_xBead]),
  const AuthorityEpochTransition(
    phase: EpochPhase.advanced,
    epoch: 9223372036854775807,
    pid: _xInt,
    pgid: _xInt,
    cause: EpochCause.steal,
    priorEpoch: 9223372036854775806,
    priorPid: _xInt,
    stealReason: StealReason.stale,
  ),
  const AuthorityEpochTransition(
    phase: EpochPhase.closed,
    epoch: 9223372036854775807,
    pid: _xInt,
    pgid: _xInt,
    cause: EpochCause.down,
    outstandingObligations: _xInt,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.granted,
    leaseId: _xFree,
    kind: 'substation',
    lessee: _xBead,
    fencingToken: 9223372036854775807,
    expiresAt: _expiry,
    ttlS: _xInt,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.reaped,
    leaseId: _xFree,
    kind: 'substation',
    lessee: _xBead,
    fencingToken: 9223372036854775807,
    expiresAt: _expiry,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.expired,
    leaseId: _xFree,
    kind: 'substation',
    lessee: _xBead,
    fencingToken: 9223372036854775807,
    expiresAt: _expiry,
  ),
  // Family 3 — verification bindings.
  VerifyScopePinned(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    incarnation: _xInt,
    baseSha: _xSha,
    headSha: _xSha,
    branch: _xBranch,
    commitCount: _xInt,
    diffDigest: _xHex64,
    diffBytes: _xInt,
  ),
  VerifyVerdictRecorded(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    incarnation: _xInt,
    headShaAtRecord: _xSha,
    lane: 'l' * 64,
    rubricVersion: 'v3',
    grade: 'B',
    rationale: 'rationale',
    transport: VerdictTransport.artifact,
    pinnedHeadSha: _xSha,
    shaDrift: false,
  ),
  VerifyVerdictRecovered(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    lane: 'l' * 64,
    rubricVersion: 'v3',
    grade: 'C',
    rationale: 'recovered',
    pinnedHeadSha: _xSha,
    shaDrift: true,
  ),
  VerifyGatingRc(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    incarnation: _xInt,
    rc: 255,
    durationMs: _xInt,
    planDigest: _xHex64,
    headShaAtExec: _xSha,
  ),
  VerifyCompletionFence(
    attemptId: _xUlid,
    outcome: FenceProbeOutcome.clear,
    headShaAtProbe: _xSha,
  ),
  VerifyRouteVerdict(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    incarnation: _xInt,
    verdict: RouteVerdictKind.advance,
    rule: 'decent-grades',
    spread: 1.0,
    grades: const {
      'critic': {'grade': 'B', 'source_record_id': null, 'sha_drift': null},
    },
  ),
  VerifyUsageTelemetry(
    attemptId: _xUlid,
    sessionId: _xSession,
    model: 'molecule',
    tokensIn: _xInt,
    tokensOut: _xInt,
    costUsd: 999999.99,
    premiumRequests: _xInt,
    numTurns: _xInt,
    durationMs: _xInt,
  ),
  VerifyCiConcluded(
    observationId: _xFree,
    headSha: _xSha,
    workBeadId: _xBead,
    sessionId: _xSession,
    repo: 'memento-engineering/the_grid',
    checkName: 'n' * 128,
    conclusion: 'success',
  ),
  // Family 4 — effect intent / acknowledgement.
  EffectIntent(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    kind: EffectKind.prOpen,
    targetRepo: 'o' * 128,
    targetBranch: _xBranch,
    targetBase: _xBranch,
    posture: const {'delivery_method': 'pr', 'policy_version': 'v2'},
    attemptId: _xUlid,
  ),
  EffectAck(
    effectId: _xHex64,
    kind: EffectKind.prOpen,
    ackOrdinal: _xInt,
    outcome: TerminalOutcome.succeeded,
    receipt: 'e' * 255,
    prNumber: _xInt,
    prUrl: 'https://github.com/${'u' * 200}',
    reused: false,
  ),
  EffectUnarmed(
    attemptId: _xUlid,
    posture: const {'delivery_method': 'commit-only', 'policy_version': 'v2'},
  ),
  EffectObservationClaimed(
    observationId: _xFree,
    claimOrder: ClaimOrder.deliverThenClaim,
  ),
  EffectCommandReceived(
    wireKey: _xFree,
    command: '/rework',
    fence: 9223372036854775807,
    fingerprint: _xHex64,
  ),
  EffectCommandRefused(
    wireKey: _xFree,
    reason: CommandRefusalReason.fingerprintMismatch,
    fingerprint: _xHex64,
    priorFingerprint: _xHex64,
  ),
  EffectCiReworkCommanded(
    workBeadId: _xBead,
    round: _xInt,
    observationId: _xFree,
    checkName: 'n' * 128,
    noteDigest: _xHex64,
  ),
  // Family 5 — step and molecule transitions.
  MoleculePoured(
    sessionId: _xSession,
    round: _xInt,
    formula: 'implement-verify-deliver',
    graph: const {'nodes': [], 'edges': []},
    nodeCount: _xInt,
    graphDigest: _xHex64,
  ),
  StepTransition(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    stepRound: _xInt,
    incarnation: _xInt,
    attemptId: _xUlid,
    state: StepState.failed,
    cause: StepCause.allocation,
    restartBudget: _xInt,
    failureReason: 'store unavailable',
    failureClass: StepFailureClass.storeUnavailable,
  ),
  StepSuperseded(
    sessionId: _xSession,
    round: _xInt,
    stepPath: _xPath,
    cause: 'restart-budget',
    budgetRemaining: _xInt,
    oldStepRound: _xInt - 1,
    newStepRound: _xInt,
  ),
  GateOpened(
    gateId: _xGate,
    sessionId: _xSession,
    workBeadId: _xBead,
    stepPath: _xPath,
    stepRound: _xInt,
    attemptId: _xUlid,
    node: _xPath,
    reason: 'critic graded F',
  ),
  GateRegated(
    gateId: _xGate,
    sessionId: _xSession,
    regateCycle: _xInt,
    node: _xPath,
    reason: 'second F',
  ),
  GateClosed(
    gateId: _xGate,
    sessionId: _xSession,
    closeCause: GateCloseCause.adjudicated,
    cycle: _xInt,
    actor: 'nico',
    openDurationMs: _xInt,
  ),
];

/// One constructed sample per §2 record type — 50 in all; the generator turns
/// these into the golden files.
List<TrajectoryRecord> sampleRecords() => [
  // Family 1 — attempt lifecycle.
  const AttemptSessionStarted(
    sessionId: 'tranquility-5xk',
    grantId: '01J8GRANT00000000000000001',
    workBeadId: 'tg-9abc',
    mountAttemptId: '01J8MOUNT00000000000000001',
    rig: 'operator',
    model: 'molecule',
  ),
  const AttemptProcessStarted(
    attemptId: '01J8ATTEMPT000000000000002',
    sessionId: 'tranquility-5xk',
    incarnation: 1,
    round: 0,
    stepPath: 'root.implement',
    stepRound: 0,
    worktree: '.grid/worktrees/tg/tg-9abc',
    branch: 'grid/tg-9abc',
    pid: 4242,
    pgid: 4242,
    predecessorAttemptId: '01J8ATTEMPT000000000000001',
  ),
  const AttemptProcessExited(
    attemptId: '01J8ATTEMPT000000000000002',
    sessionId: 'tranquility-5xk',
    pid: 4242,
    exitCode: 0,
    exitKind: ExitKind.exited,
    inferred: false,
    reason: 'clean exit',
  ),
  AttemptLivenessTransition(
    attemptId: '01J8ATTEMPT000000000000002',
    crossing: LivenessCrossing.lost,
    lastBeatAt: _beat,
    thresholdMs: 90000,
  ),
  AttemptLivenessTransition(
    attemptId: '01J8ATTEMPT000000000000002',
    crossing: LivenessCrossing.regained,
    lastBeatAt: _beat.add(const Duration(seconds: 120)),
    thresholdMs: 90000,
  ),
  const AttemptLeaseTransition(
    attemptId: '01J8ATTEMPT000000000000002',
    phase: LeasePhase.acquired,
    token: '01J8ATTEMPT000000000000002',
    disposition: LeaseDisposition.held,
  ),
  const AttemptLeaseTransition(
    attemptId: '01J8ATTEMPT000000000000002',
    phase: LeasePhase.released,
    token: '01J8ATTEMPT000000000000002',
    disposition: LeaseDisposition.released,
  ),
  const AttemptLeaseTransition(
    attemptId: '01J8ATTEMPT000000000000002',
    phase: LeasePhase.swept,
    token: '01J8ATTEMPT000000000000002',
    disposition: LeaseDisposition.killed,
    terminateResult: 'SIGKILL delivered to pgid 4242',
  ),
  const AttemptAdoptProved(
    attemptId: '01J8ATTEMPT000000000000002',
    outcome: AdoptOutcome.adopted,
    fencePgid: 4242,
    fencePid: 4242,
  ),
  AttemptTerminal(
    attemptId: '01J8ATTEMPT000000000000002',
    sessionId: 'tranquility-5xk',
    workBeadId: 'tg-9abc',
    outcome: TerminalOutcome.unknown,
    unknownReason: 'write_timeout',
    reason: 'report write timed out',
  ),
  const AttemptRoundRetired(
    sessionId: 'tranquility-5xk',
    oldRound: 0,
    newRound: 1,
    cause: RoundRetireCause.rework,
  ),
  const AttemptReworkDeclined(
    sessionId: 'tranquility-5xk',
    round: 1,
    reason: 'operator declined the readiness-hold rework',
  ),
  const AttemptMintOutcome(
    workBeadId: 'tg-9abc',
    mountAttemptId: '01J8MOUNT00000000000000001',
    phase: MintPhase.exhausted,
    mintAttempt: 3,
    maxAttempts: 3,
    stage: 'pour',
    reason: 'graph-apply timeout',
  ),
  const AttemptNote(
    sessionId: 'tranquility-5xk',
    body: 'obligation stuck: bd close failed read-back 5 ticks',
    channel: 'obligation-stuck',
    noteOrdinal: 2,
  ),
  const WorktreeProvisioned(
    attemptId: '01J8ATTEMPT000000000000002',
    sessionId: 'tranquility-5xk',
    worktree: '.grid/worktrees/tg/tg-9abc',
    branch: 'grid/tg-9abc',
    baseSha: 'a3f9c1d2e4b5a6978877665544332211ffeeddcc',
    adoptedExisting: false,
  ),
  const WorktreeReaped(
    sessionId: 'tranquility-5xk',
    worktree: '.grid/worktrees/tg/tg-9abc',
    branch: 'grid/tg-9abc',
    uncommitted: 0,
    unpushed: 0,
    stashes: 0,
  ),
  const WorktreeHeld(
    sessionId: 'tranquility-5xk',
    worktree: '.grid/worktrees/tg/tg-9abc',
    branch: 'grid/tg-9abc',
    uncommitted: 3,
    unpushed: 1,
    stashes: 0,
  ),
  // Family 2 — admission grants and authority.
  AdmissionGrantIssued(
    grantId: '01J8GRANT00000000000000001',
    workBeadId: 'tg-9abc',
    mountAttemptId: '01J8MOUNT00000000000000001',
    fencingToken: (7 << 32) | 41,
    expiresAt: _expiry,
    basis: const {
      'bead_rev': 'r12',
      'approved_label_rev': 'r11',
      'validation_plan_digest': 'd41d8cd98f00b204e9800998ecf8427e',
      'issue_type': 'task',
      'dep_revs': {'tg-1aaa': 'r4'},
      'drive_list_member': true,
      'snapshot_captured_at': '2026-08-31T11:59:00.000000Z',
    },
  ),
  const AdmissionGrantConsumed(
    grantId: '01J8GRANT00000000000000001',
    sessionId: 'tranquility-5xk',
    workBeadId: 'tg-9abc',
  ),
  const AdmissionGrantClosed(
    grantId: '01J8GRANT00000000000000001',
    closure: GrantClosure.expired,
    cause: GrantCloseCause.expired,
    workBeadId: 'tg-9abc',
  ),
  const AdmissionGrantClosed(
    grantId: '01J8GRANT00000000000000001',
    closure: GrantClosure.released,
    cause: GrantCloseCause.superseded,
    workBeadId: 'tg-9abc',
  ),
  const AdmissionRefused(
    workBeadId: 'tg-9abc',
    mountAttemptId: '01J8MOUNT00000000000000002',
    clause: 'worktree-outstanding',
    snapshotRev: 'r12',
    detail: {
      'dead_session': 'tranquility-5xk',
      'pgids': [4242],
    },
  ),
  const AdmissionRestored(
    workBeadId: 'tg-9abc',
    clause: 'attempt-cap',
    refusalRecordId: '01J8REFUSAL000000000000001',
    actor: 'nico',
  ),
  const AdmissionDriveApproved(approvedBeads: ['tg-9abc', 'tg-1aaa']),
  const AuthorityEpochTransition(
    phase: EpochPhase.advanced,
    epoch: 7,
    pid: 4200,
    pgid: 4200,
    cause: EpochCause.steal,
    priorEpoch: 6,
    priorPid: 3999,
    stealReason: StealReason.stale,
  ),
  const AuthorityEpochTransition(
    phase: EpochPhase.closed,
    epoch: 7,
    pid: 4200,
    pgid: 4200,
    cause: EpochCause.down,
    outstandingObligations: 0,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.granted,
    leaseId: 'lease-butane-01',
    kind: 'substation',
    lessee: 'butane_flutter',
    fencingToken: (7 << 32) | 42,
    expiresAt: _expiry,
    ttlS: 1800,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.reaped,
    leaseId: 'lease-butane-01',
    kind: 'substation',
    lessee: 'butane_flutter',
    fencingToken: (7 << 32) | 55,
    expiresAt: _expiry,
  ),
  FederationLeaseTransition(
    phase: FederationLeasePhase.expired,
    leaseId: 'lease-butane-01',
    kind: 'substation',
    lessee: 'butane_flutter',
    fencingToken: (7 << 32) | 56,
    expiresAt: _expiry,
  ),
  // Family 3 — verification bindings.
  const VerifyScopePinned(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.verify',
    stepRound: 0,
    incarnation: 0,
    baseSha: 'a3f9c1d2e4b5a6978877665544332211ffeeddcc',
    headSha: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
    branch: 'grid/tg-9abc',
    commitCount: 4,
    diffDigest:
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    diffBytes: 20480,
  ),
  VerifyVerdictRecorded(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.verify',
    stepRound: 0,
    incarnation: 0,
    headShaAtRecord: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
    lane: 'adr-alignment',
    rubricVersion: 'v3',
    grade: 'B',
    rationale: 'clause-by-clause pass; one doc drift noted',
    transport: VerdictTransport.artifact,
    pinnedHeadSha: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
    shaDrift: false,
  ),
  const VerifyVerdictRecovered(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.verify',
    stepRound: 0,
    lane: 'adr-alignment',
    rubricVersion: 'v3',
    grade: 'C',
    rationale: 'recovered from envelope after artifact loss',
    pinnedHeadSha: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
    shaDrift: true,
  ),
  const VerifyGatingRc(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.verify',
    stepRound: 0,
    incarnation: 0,
    rc: 0,
    durationMs: 412345,
    planDigest:
        '2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae',
    headShaAtExec: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
  ),
  const VerifyCompletionFence(
    attemptId: '01J8ATTEMPT000000000000002',
    outcome: FenceProbeOutcome.clear,
    headShaAtProbe: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
  ),
  VerifyRouteVerdict(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.verify',
    stepRound: 0,
    incarnation: 0,
    verdict: RouteVerdictKind.advance,
    rule: 'decent-grades',
    spread: 1.0,
    grades: const {
      'adr-alignment': {
        'grade': 'B',
        'source_record_id': '01J8VERDICT000000000000001',
        'sha_drift': false,
      },
      'critic': {'grade': 'F', 'source_record_id': null, 'sha_drift': null},
    },
  ),
  const VerifyUsageTelemetry(
    attemptId: '01J8ATTEMPT000000000000002',
    sessionId: 'tranquility-5xk',
    model: 'molecule',
    tokensIn: 182000,
    tokensOut: 24000,
    costUsd: 3.1275,
    premiumRequests: 2,
    numTurns: 41,
    durationMs: 1834000,
  ),
  const VerifyCiConcluded(
    observationId: 'obs-20260831-0007',
    headSha: 'b4a0d2e3f5c6b7a89988776655443322aabbccdd',
    workBeadId: 'tg-9abc',
    sessionId: 'tranquility-5xk',
    repo: 'memento-engineering/the_grid',
    checkName: 'analyze + test (pure Dart)',
    conclusion: 'success',
  ),
  // Family 4 — effect intent / acknowledgement.
  EffectIntent(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.deliver',
    stepRound: 0,
    kind: EffectKind.prOpen,
    targetRepo: 'memento-engineering/the_grid',
    targetBranch: 'grid/tg-9abc',
    targetBase: 'main',
    posture: const {'delivery_method': 'pr', 'policy_version': 'v2'},
    attemptId: '01J8ATTEMPT000000000000002',
  ),
  EffectAck(
    effectId:
        '5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03',
    kind: EffectKind.prOpen,
    ackOrdinal: 0,
    outcome: TerminalOutcome.succeeded,
    receipt: 'pr:memento-engineering/the_grid#241',
    prNumber: 241,
    prUrl: 'https://github.com/memento-engineering/the_grid/pull/241',
    reused: false,
  ),
  const EffectUnarmed(
    attemptId: '01J8ATTEMPT000000000000002',
    posture: {'delivery_method': 'commit-only', 'policy_version': 'v2'},
  ),
  const EffectObservationClaimed(
    observationId: 'obs-20260831-0007',
    claimOrder: ClaimOrder.deliverThenClaim,
  ),
  const EffectCommandReceived(
    wireKey: 'cmd-rework-tg-9abc-r1',
    command: '/rework tg-9abc',
    fence: 30064771113,
    fingerprint: 'fp-8c1a2b3c',
  ),
  const EffectCommandRefused(
    wireKey: 'cmd-rework-tg-9abc-r1',
    reason: CommandRefusalReason.fingerprintMismatch,
    fingerprint: 'fp-9d2b3c4d',
    priorFingerprint: 'fp-8c1a2b3c',
  ),
  const EffectCiReworkCommanded(
    workBeadId: 'tg-9abc',
    round: 1,
    observationId: 'obs-20260831-0008',
    checkName: 'analyze + test (pure Dart)',
    noteDigest:
        '486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7',
  ),
  // Family 5 — step and molecule transitions.
  const MoleculePoured(
    sessionId: 'tranquility-5xk',
    round: 0,
    formula: 'implement-verify-deliver',
    graph: {
      'nodes': ['root.implement', 'root.verify', 'root.deliver'],
      'edges': [
        {'from': 'root.implement', 'to': 'root.verify', 'kind': 'blocks'},
        {'from': 'root.verify', 'to': 'root.deliver', 'kind': 'blocks'},
      ],
    },
    nodeCount: 3,
    graphDigest:
        '3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855e',
  ),
  const StepTransition(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.implement',
    stepRound: 0,
    incarnation: 0,
    attemptId: '01J8ATTEMPT000000000000002',
    state: StepState.failed,
    cause: StepCause.allocation,
    restartBudget: 2,
    failureReason: 'store unavailable during allocation',
    failureClass: StepFailureClass.storeUnavailable,
  ),
  StepSuperseded(
    sessionId: 'tranquility-5xk',
    round: 0,
    stepPath: 'root.implement',
    cause: 'restart-budget',
    budgetRemaining: 1,
    oldStepRound: 0,
    newStepRound: 1,
  ),
  const GateOpened(
    gateId: 'tg-gate-77',
    sessionId: 'tranquility-5xk',
    workBeadId: 'tg-9abc',
    stepPath: 'root.verify',
    stepRound: 1,
    attemptId: '01J8ATTEMPT000000000000002',
    node: 'root.verify',
    reason: 'critic graded F: consumer coverage missing',
  ),
  const GateRegated(
    gateId: 'tg-gate-77',
    sessionId: 'tranquility-5xk',
    regateCycle: 1,
    node: 'root.verify',
    reason: 'second F after rework round',
  ),
  const GateClosed(
    gateId: 'tg-gate-77',
    sessionId: 'tranquility-5xk',
    closeCause: GateCloseCause.adjudicated,
    cycle: 1,
    actor: 'nico',
    openDurationMs: 5400000,
  ),
];
