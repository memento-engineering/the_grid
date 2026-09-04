// Family 5 — step and molecule transitions (§2 F5). The gate bead id rides
// the envelope `gate_id` column; supersession is NOT an edge — the chain is
// linear per path (`superseded_by_step_round` on P2).

part of '../trajectory_record.dart';

enum StepState {
  pending,
  running,
  ready,
  complete,
  failed,
  gated;

  static StepState fromWire(String wire) => values.byName(wire);

  String get wire => name;
}

enum StepCause {
  scheduled('scheduled'),
  allocation('allocation'),
  route('route'),
  gateCleared('gate_cleared'),
  rearm('rearm'),
  recovery('recovery');

  const StepCause(this.wire);

  final String wire;

  static StepCause fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

enum StepFailureClass {
  /// The step's own WORK failed: the agent ran and produced a bad result.
  work('work'),

  /// The step produced NO usable result: no artifact, nothing to grade.
  noResult('no_result'),

  /// A result exists but violates the capability's declared contract.
  invalidResult('invalid_result'),

  /// The failed write is a dropped persist recovered through the same writer.
  storeUnavailable('store_unavailable'),

  /// The step never ran because its execution environment refused it.
  infra('infra'),

  unknown('unknown');

  const StepFailureClass(this.wire);

  final String wire;

  static StepFailureClass fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

/// `gate.closed` close_cause — the enum that makes 554/601 causeless closes
/// impossible to recur.
enum GateCloseCause {
  sessionTerminal('session-terminal'),
  workBeadClosed('work-bead-closed'),
  supersededRound('superseded-round'),
  duplicateMint('duplicate-mint'),
  stragglerRoute('straggler-route'),
  adjudicated('adjudicated'),
  capReleased('cap-released'),
  unclassified('unclassified');

  const GateCloseCause(this.wire);

  final String wire;

  static GateCloseCause fromWire(String wire) =>
      values.firstWhere((value) => value.wire == wire);
}

/// `molecule.poured` — one record replaces the ~6k-bead pour; the fold
/// flattens blocks/validates edges into `proj_step_edges`.
final class MoleculePoured extends StepRecord {
  const MoleculePoured({
    required this.sessionId,
    required this.round,
    required this.formula,
    required this.graph,
    required this.nodeCount,
    required this.graphDigest,
  });

  factory MoleculePoured.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => MoleculePoured(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    formula: _req<String>(payload, 'formula'),
    graph: _reqMap(payload, 'graph'),
    nodeCount: _req<int>(payload, 'node_count'),
    graphDigest: _req<String>(payload, 'graph_digest'),
  );

  final String sessionId;
  final int round;
  final String formula;
  final Map<String, Object?> graph;
  final int nodeCount;
  final String graphDigest;

  @override
  String get recordType => 'molecule.poured';

  @override
  Map<String, Object?> payloadToJson() => {
    'formula': formula,
    'graph': graph,
    'node_count': nodeCount,
    'graph_digest': graphDigest,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
  };

  @override
  String idemKeyText(IdemContext context) => 'pour:$sessionId:$round';
}

/// `step.transition` — running/ready/complete/failed/rearmed plus the step
/// half of `step.gated`. A `cause='gate_cleared'` rearm bumps `step_round`;
/// the predecessor-chain write is the FOLD's job, the cause rides here.
final class StepTransition extends StepRecord {
  const StepTransition({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.stepRound,
    required this.incarnation,
    required this.state,
    this.attemptId,
    this.cause,
    this.startedAt,
    this.readyAt,
    this.completedAt,
    this.cooldownUntil,
    this.restartBudget,
    this.failureReason,
    this.failureClass,
    this.result,
  });

  factory StepTransition.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => StepTransition(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    stepRound: _envReq(envelope, 'step_round', envelope.stepRound),
    incarnation: _envReq(envelope, 'incarnation', envelope.incarnation),
    attemptId: envelope.attemptId,
    state: StepState.fromWire(_req<String>(payload, 'state')),
    cause: switch (_opt<String>(payload, 'cause')) {
      null => null,
      final wire => StepCause.fromWire(wire),
    },
    startedAt: _optDate(payload, 'started_at'),
    readyAt: _optDate(payload, 'ready_at'),
    completedAt: _optDate(payload, 'completed_at'),
    cooldownUntil: _optDate(payload, 'cooldown_until'),
    restartBudget: _opt<int>(payload, 'restart_budget'),
    failureReason: _opt<String>(payload, 'failure_reason'),
    failureClass: switch (_opt<String>(payload, 'failure_class')) {
      null => null,
      final wire => StepFailureClass.fromWire(wire),
    },
    result: _optMap(payload, 'result'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final int stepRound;
  final int incarnation;
  final String? attemptId;
  final StepState state;
  final StepCause? cause;
  final DateTime? startedAt;
  final DateTime? readyAt;
  final DateTime? completedAt;

  /// Absent means absent — never a sentinel.
  final DateTime? cooldownUntil;
  final int? restartBudget;
  final String? failureReason;
  final StepFailureClass? failureClass;
  final Map<String, Object?>? result;

  @override
  String get recordType => 'step.transition';

  @override
  Map<String, Object?> payloadToJson() => {
    'state': state.wire,
    if (cause != null) 'cause': cause!.wire,
    if (startedAt != null) 'started_at': startedAt!.toIso8601String(),
    if (readyAt != null) 'ready_at': readyAt!.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    if (cooldownUntil != null)
      'cooldown_until': cooldownUntil!.toIso8601String(),
    if (restartBudget != null) 'restart_budget': restartBudget,
    if (failureReason != null) 'failure_reason': failureReason,
    if (failureClass != null) 'failure_class': failureClass!.wire,
    if (result != null) 'result': result,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': stepRound,
    'incarnation': incarnation,
    if (attemptId != null) 'attempt_id': attemptId,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'step:$sessionId:$round:$stepPath:$stepRound:$incarnation:'
      '${state.wire}';
}

/// `step.superseded` — the successor KEEPS the path and bumps `step_round`;
/// envelope `step_round` carries the NEW round.
final class StepSuperseded extends StepRecord {
  StepSuperseded({
    required this.sessionId,
    required this.round,
    required this.stepPath,
    required this.cause,
    required this.budgetRemaining,
    required this.oldStepRound,
    required this.newStepRound,
  }) {
    if (newStepRound <= oldStepRound) {
      _refuse(recordType, 'new_step_round must exceed old_step_round');
    }
  }

  factory StepSuperseded.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => StepSuperseded(
    sessionId: _envReq(envelope, 'session_id', envelope.sessionId),
    round: _envReq(envelope, 'round', envelope.round),
    stepPath: _envReq(envelope, 'step_path', envelope.stepPath),
    cause: _req<String>(payload, 'cause'),
    budgetRemaining: _req<int>(payload, 'budget_remaining'),
    oldStepRound: _req<int>(payload, 'old_step_round'),
    newStepRound: _req<int>(payload, 'new_step_round'),
  );

  final String sessionId;
  final int round;
  final String stepPath;
  final String cause;
  final int budgetRemaining;
  final int oldStepRound;
  final int newStepRound;

  @override
  String get recordType => 'step.superseded';

  @override
  Map<String, Object?> payloadToJson() => {
    'cause': cause,
    'budget_remaining': budgetRemaining,
    'old_step_round': oldStepRound,
    'new_step_round': newStepRound,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'session_id': sessionId,
    'round': round,
    'step_path': stepPath,
    'step_round': newStepRound,
  };

  @override
  String idemKeyText(IdemContext context) =>
      'supersede:$sessionId:$round:$stepPath:$oldStepRound';
}

/// `gate.opened` — the gate bead stays a ledger act, stamped once at mint with
/// the opening record_id (gap 7).
final class GateOpened extends StepRecord {
  const GateOpened({
    required this.gateId,
    required this.node,
    this.sessionId,
    this.workBeadId,
    this.stepPath,
    this.stepRound,
    this.attemptId,
    this.reason,
  });

  factory GateOpened.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => GateOpened(
    gateId: _envReq(envelope, 'gate_id', envelope.gateId),
    sessionId: envelope.sessionId,
    workBeadId: envelope.workBeadId,
    stepPath: envelope.stepPath,
    stepRound: envelope.stepRound,
    attemptId: envelope.attemptId,
    node: _req<String>(payload, 'node'),
    reason: _opt<String>(payload, 'reason'),
  );

  final String gateId;
  final String? sessionId;
  final String? workBeadId;
  final String? stepPath;
  final int? stepRound;
  final String? attemptId;
  final String node;

  /// ≤16 KB (§10 payload policy).
  final String? reason;

  @override
  String get recordType => 'gate.opened';

  @override
  Map<String, Object?> payloadToJson() => {
    'node': node,
    if (reason != null) 'reason': reason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'gate_id': gateId,
    if (sessionId != null) 'session_id': sessionId,
    if (workBeadId != null) 'work_bead_id': workBeadId,
    if (stepPath != null) 'step_path': stepPath,
    if (stepRound != null) 'step_round': stepRound,
    if (attemptId != null) 'attempt_id': attemptId,
  };

  @override
  String idemKeyText(IdemContext context) => 'gate:$gateId:opened';
}

/// `gate.regated` — per-cycle history; the bead's reason gets a courtesy
/// refresh through the epoch-fenced bd write path (§5), never here.
final class GateRegated extends StepRecord {
  const GateRegated({
    required this.gateId,
    required this.regateCycle,
    this.sessionId,
    this.node,
    this.reason,
  });

  factory GateRegated.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => GateRegated(
    gateId: _envReq(envelope, 'gate_id', envelope.gateId),
    sessionId: envelope.sessionId,
    regateCycle: _req<int>(payload, 'regate_cycle'),
    node: _opt<String>(payload, 'node'),
    reason: _opt<String>(payload, 'reason'),
  );

  final String gateId;
  final String? sessionId;
  final int regateCycle;
  final String? node;
  final String? reason;

  @override
  String get recordType => 'gate.regated';

  @override
  Map<String, Object?> payloadToJson() => {
    'regate_cycle': regateCycle,
    if (node != null) 'node': node,
    if (reason != null) 'reason': reason,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'gate_id': gateId,
    if (sessionId != null) 'session_id': sessionId,
  };

  @override
  String idemKeyText(IdemContext context) => 'gate:$gateId:regate:$regateCycle';
}

final class GateClosed extends StepRecord {
  const GateClosed({
    required this.gateId,
    required this.closeCause,
    required this.cycle,
    this.sessionId,
    this.actor,
    this.openDurationMs,
  });

  factory GateClosed.fromJson(
    TrajectoryEnvelope envelope,
    Map<String, Object?> payload,
  ) => GateClosed(
    gateId: _envReq(envelope, 'gate_id', envelope.gateId),
    sessionId: envelope.sessionId,
    closeCause: GateCloseCause.fromWire(_req<String>(payload, 'close_cause')),
    cycle: _req<int>(payload, 'cycle'),
    actor: _opt<String>(payload, 'actor'),
    openDurationMs: _opt<int>(payload, 'open_duration_ms'),
  );

  final String gateId;
  final String? sessionId;
  final GateCloseCause closeCause;

  /// The regate cycle being closed — 0 for a never-regated gate.
  final int cycle;
  final String? actor;
  final int? openDurationMs;

  @override
  String get recordType => 'gate.closed';

  @override
  Map<String, Object?> payloadToJson() => {
    'close_cause': closeCause.wire,
    'cycle': cycle,
    if (actor != null) 'actor': actor,
    if (openDurationMs != null) 'open_duration_ms': openDurationMs,
  };

  @override
  Map<String, Object?> correlationToJson() => {
    'gate_id': gateId,
    if (sessionId != null) 'session_id': sessionId,
  };

  @override
  String idemKeyText(IdemContext context) => 'gate:$gateId:closed:$cycle';
}
