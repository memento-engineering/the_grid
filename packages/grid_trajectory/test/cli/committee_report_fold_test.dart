/// The committee-report FOLD over a synthetic trajectory: the five named gate
/// causes, one operator override, an upheld gate that converged, and the
/// `.usage.json` fallback.
library;

import 'dart:convert';
import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/scripted_reader.dart';

int _seq = 0;

TrajectoryEnvelope _verdict({
  required String session,
  required String lane,
  required String grade,
  required int round,
  VerdictTransport transport = VerdictTransport.artifact,
}) => envelope(
  recordType: 'verify.verdict.recorded',
  family: TrajectoryFamily.verification,
  seq: ++_seq,
  sessionId: session,
  round: round,
  stepPath: '$session/review/$lane',
  stepRound: round,
  incarnation: 1,
  commitSha: 'a' * 40,
  payload: {
    'lane': lane,
    'rubric_version': 'v1',
    'grade': grade,
    'rationale': 'because',
    'transport': transport.wire,
    'pinned_head_sha': 'a' * 40,
    'sha_drift': false,
  },
);

TrajectoryEnvelope _gateOpened({
  required String gate,
  required String session,
  required String lane,
  required int round,
  required String reason,
}) => envelope(
  recordType: 'gate.opened',
  family: TrajectoryFamily.step,
  seq: ++_seq,
  gateId: gate,
  sessionId: session,
  stepPath: '$session/review/$lane',
  stepRound: round,
  payload: {'node': '$session/review/$lane', 'reason': reason},
);

TrajectoryEnvelope _gateClosed({
  required String gate,
  required String session,
  required GateCloseCause cause,
}) => envelope(
  recordType: 'gate.closed',
  family: TrajectoryFamily.step,
  seq: ++_seq,
  gateId: gate,
  sessionId: session,
  payload: {'close_cause': cause.wire, 'cycle': 0, 'actor': 'nico'},
);

/// The bead↔session and attempt↔step joins the fold rides.
TrajectoryEnvelope _processStarted({
  required String session,
  required String bead,
  required String attempt,
  required String lane,
  required int round,
}) => envelope(
  recordType: 'attempt.process.started',
  family: TrajectoryFamily.attempt,
  seq: ++_seq,
  sessionId: session,
  workBeadId: bead,
  attemptId: attempt,
  round: round,
  stepPath: '$session/review/$lane',
  stepRound: round,
  incarnation: 1,
  payload: {'pid': 4242, 'pgid': 4242},
);

TrajectoryEnvelope _usage({
  required String session,
  required String attempt,
  required double cost,
  required int durationMs,
}) => envelope(
  recordType: 'verify.usage.telemetry',
  family: TrajectoryFamily.verification,
  seq: ++_seq,
  typeVersion: 2,
  sessionId: session,
  attemptId: attempt,
  payload: {
    'gen_ai.request.model': 'claude-opus-5',
    'gen_ai.usage.input_tokens': 1000,
    'gen_ai.usage.output_tokens': 200,
    'cost_usd': cost,
    'duration_ms': durationMs,
  },
);

TrajectoryEnvelope _step({
  required String session,
  required String node,
  required StepState state,
  int stepRound = 1,
  String? attempt,
  String? failureReason,
  Map<String, String>? result,
  DateTime? startedAt,
  DateTime? completedAt,
}) => envelope(
  recordType: 'step.transition',
  family: TrajectoryFamily.step,
  seq: ++_seq,
  sessionId: session,
  round: 1,
  stepPath: node,
  stepRound: stepRound,
  incarnation: 1,
  attemptId: attempt,
  payload: {
    'state': state.wire,
    if (failureReason != null) 'failure_reason': failureReason,
    if (startedAt != null) 'started_at': startedAt.toIso8601String(),
    if (completedAt != null) 'completed_at': completedAt.toIso8601String(),
    if (result != null) 'result': result,
  },
);

/// A window with NO `verify.*` and NO `gate.*` row — only the step family the
/// engine actually writes today, plus the attempt row that joins session→bead.
///
/// Session s3 (`tg-ccc`): coherence A, adr-alignment D, a gate parked at the
/// route node, and a route step that ESCALATED — the D is upheld.
/// Session s4 (`tg-ddd`): code-validation F, a gate, and a route step that
/// ADVANCED anyway — the F is overridden.
List<TrajectoryEnvelope> stepOnlyRows() {
  _seq = 0;
  final t0 = DateTime.utc(2026, 9, 2, 12);
  return [
    _processStarted(
      session: 's3',
      bead: 'tg-ccc',
      attempt: 'att-10',
      lane: 'coherence',
      round: 1,
    ),
    _step(
      session: 's3',
      node: 'review/coherence',
      state: StepState.complete,
      attempt: 'att-10',
      startedAt: t0,
      completedAt: t0.add(const Duration(minutes: 1)),
      result: {'grade': 'A', 'round': '1', 'costUsd': '5.00'},
    ),
    _step(
      session: 's3',
      node: 'review/adr-alignment',
      state: StepState.complete,
      startedAt: t0,
      completedAt: t0.add(const Duration(minutes: 3)),
      result: {'grade': 'D', 'round': '1', 'costUsd': '2.00'},
    ),
    _step(
      session: 's3',
      node: 'review/route',
      state: StepState.gated,
      failureReason: 'hard block: structural contract failed',
    ),
    _step(
      session: 's3',
      node: 'review/route',
      state: StepState.complete,
      result: {
        'route_verdict': 'escalate',
        'lane': 'adr-alignment',
        'grade': 'D',
      },
    ),
    _processStarted(
      session: 's4',
      bead: 'tg-ddd',
      attempt: 'att-11',
      lane: 'code-validation',
      round: 1,
    ),
    _step(
      session: 's4',
      node: 'review/code-validation',
      state: StepState.complete,
      attempt: 'att-11',
      startedAt: t0,
      completedAt: t0.add(const Duration(minutes: 2)),
      result: {'grade': 'F', 'round': '1', 'costUsd': '1.00'},
    ),
    _step(
      session: 's4',
      node: 'review/route',
      state: StepState.gated,
      failureReason: 'critic F on a non-code diff',
    ),
    _step(
      session: 's4',
      node: 'review/route',
      state: StepState.complete,
      result: {'route_verdict': 'advance', 'lane': 'code-validation'},
    ),
  ];
}

/// One boot's worth of records: two beads, five gates (one per named cause),
/// one operator override, one upheld+converged respec, one unwinnable loop.
List<TrajectoryEnvelope> fixtureRows() {
  _seq = 0;
  return [
    // --- bead one: spec readiness, respec-cap, and the override -------------
    _processStarted(
      session: 's1',
      bead: 'tg-aaa',
      attempt: 'att-1',
      lane: 'coherence',
      round: 1,
    ),
    _verdict(session: 's1', lane: 'coherence', grade: 'D', round: 1),
    _gateOpened(
      gate: 'gate-1',
      session: 's1',
      lane: 'coherence',
      round: 1,
      reason: 'readiness hold: spec not implementation-ready',
    ),
    _usage(session: 's1', attempt: 'att-1', cost: 9.0, durationMs: 600000),
    // round 2 on the same lane converges — upheld.
    _processStarted(
      session: 's1',
      bead: 'tg-aaa',
      attempt: 'att-2',
      lane: 'coherence',
      round: 2,
    ),
    _verdict(session: 's1', lane: 'coherence', grade: 'A', round: 2),
    _usage(session: 's1', attempt: 'att-2', cost: 9.0, durationMs: 400000),
    // the unwinnable respec loop: D then D, gated on the respec cap.
    _processStarted(
      session: 's1',
      bead: 'tg-aaa',
      attempt: 'att-3',
      lane: 'plan-completeness',
      round: 1,
    ),
    _verdict(session: 's1', lane: 'plan-completeness', grade: 'D', round: 1),
    _gateOpened(
      gate: 'gate-2',
      session: 's1',
      lane: 'plan-completeness',
      round: 1,
      reason: 'respec-cap reached after 3 rounds',
    ),
    _verdict(session: 's1', lane: 'plan-completeness', grade: 'D', round: 2),
    // --- bead two: the grade spread, the hard block, the critic F ----------
    _processStarted(
      session: 's2',
      bead: 'tg-bbb',
      attempt: 'att-4',
      lane: 'test-coverage',
      round: 1,
    ),
    // The false positive: an F the operator overrode (adjudicated close).
    _verdict(session: 's2', lane: 'test-coverage', grade: 'F', round: 1),
    _gateOpened(
      gate: 'gate-3',
      session: 's2',
      lane: 'test-coverage',
      round: 1,
      reason: 'critic F on a non-code diff',
    ),
    _gateClosed(
      gate: 'gate-3',
      session: 's2',
      cause: GateCloseCause.adjudicated,
    ),
    _usage(session: 's2', attempt: 'att-4', cost: 1.5, durationMs: 120000),
    _verdict(session: 's2', lane: 'adr-alignment', grade: 'D', round: 1),
    _gateOpened(
      gate: 'gate-4',
      session: 's2',
      lane: 'adr-alignment',
      round: 1,
      reason: 'grade spread across lanes exceeded the route rule',
    ),
    _verdict(session: 's2', lane: 'spec-validation', grade: 'F', round: 1),
    _gateOpened(
      gate: 'gate-5',
      session: 's2',
      lane: 'spec-validation',
      round: 1,
      reason: 'hard block: structural contract failed',
    ),
  ];
}

Map<String, String> _selectorProjection({
  required String sampleId,
  required String joinId,
  String policyVersion = 'policy-v1',
  String stage = 'implementation',
  String workBeadId = 'bead-a',
  String nodePath = 'review/select',
  String selected = 'coherence,code-validation',
  String omitted = 'security',
  String matchedRules = 'rule-a',
  String evidenceDigest = 'evidence-a',
  Set<String> omitKeys = const {},
  Map<String, String> overrides = const {},
}) {
  final result = <String, String>{
    StepResultKeys.shadow: 'selection',
    StepResultKeys.source: 'policy',
    StepResultKeys.stage: stage,
    StepResultKeys.selected: selected,
    StepResultKeys.matchedRules: matchedRules,
    StepResultKeys.classifierAttempts: '1',
    StepResultKeys.sampleId: sampleId,
    StepResultKeys.joinId: joinId,
    StepResultKeys.policyVersion: policyVersion,
    StepResultKeys.workBeadId: workBeadId,
    StepResultKeys.round: '1',
    StepResultKeys.nodePath: nodePath,
    StepResultKeys.omitted: omitted,
    StepResultKeys.evidenceDigest: evidenceDigest,
    StepResultKeys.missingEvidenceIds: '',
    StepResultKeys.laneInputDigests: jsonEncode({
      'code-validation': 'input-code',
      'coherence': 'input-coherence',
    }),
    StepResultKeys.classifierAttemptKinds: 'selected',
  }..addAll(overrides);
  for (final key in omitKeys) {
    result.remove(key);
  }
  return result;
}

Map<String, String> _shadowRouteProjection({
  required String sampleId,
  required String joinId,
  String policyVersion = 'policy-v1',
  String stage = 'implementation',
  String workBeadId = 'bead-a',
  String nodePath = 'review/select',
  String routeNodePath = 'review/route',
  String selected = 'coherence,code-validation',
  String omitted = 'security',
  String matchedRules = 'rule-a',
  String evidenceDigest = 'evidence-a',
  Map<String, Object?> omittedGrades = const {'security': 'D'},
  Map<String, Object?> omittedTransports = const {'security': 'artifact'},
  Map<String, Object?> omittedDispositions = const {'security': 'upheld'},
  int? actualTokensIn = 100,
  int? actualTokensOut = 20,
  num? actualCostUsd = 1.5,
  int? counterfactualTokensIn = 60,
  int? counterfactualTokensOut = 10,
  num? counterfactualCostUsd = 0.8,
  bool truncated = false,
  String missingFields = '',
  Set<String> omitKeys = const {},
  Map<String, String> overrides = const {},
}) {
  final result = <String, String>{
    StepResultKeys.committeeShadowSampleId: sampleId,
    StepResultKeys.committeeShadowJoinId: joinId,
    StepResultKeys.committeeShadowPolicyVersion: policyVersion,
    StepResultKeys.committeeShadowWorkBeadId: workBeadId,
    StepResultKeys.committeeShadowRound: '1',
    StepResultKeys.committeeShadowNodePath: nodePath,
    StepResultKeys.committeeShadowRouteNodePath: routeNodePath,
    StepResultKeys.committeeShadowStage: stage,
    StepResultKeys.committeeShadowSource: 'policy',
    StepResultKeys.committeeShadowSelected: selected,
    StepResultKeys.committeeShadowOmitted: omitted,
    StepResultKeys.committeeShadowMatchedRules: matchedRules,
    StepResultKeys.committeeShadowEvidenceDigest: evidenceDigest,
    StepResultKeys.committeeShadowMissingEvidenceIds: '',
    StepResultKeys.committeeShadowLaneInputDigests: jsonEncode({
      'code-validation': 'input-code',
      'coherence': 'input-coherence',
    }),
    StepResultKeys.committeeShadowClassifierAttemptKinds: 'selected',
    StepResultKeys.committeeShadowActionLaneIds: 'security',
    StepResultKeys.committeeShadowGateDisposition: jsonEncode('upheld'),
    StepResultKeys.committeeShadowDownstreamJoinKeys: jsonEncode({
      'routeNodePath': routeNodePath,
      'workBeadId': workBeadId,
    }),
    StepResultKeys.committeeShadowOmittedLaneGrades: jsonEncode(omittedGrades),
    StepResultKeys.committeeShadowOmittedLaneTransports: jsonEncode(
      omittedTransports,
    ),
    StepResultKeys.committeeShadowOmittedLaneDispositions: jsonEncode(
      omittedDispositions,
    ),
    StepResultKeys.committeeShadowActualContributingRunIds: 'run-full',
    StepResultKeys.committeeShadowActualMissingLaneIds: '',
    StepResultKeys.committeeShadowActualTokensIn: jsonEncode(actualTokensIn),
    StepResultKeys.committeeShadowActualTokensOut: jsonEncode(actualTokensOut),
    StepResultKeys.committeeShadowActualCostUsd: jsonEncode(actualCostUsd),
    StepResultKeys.committeeShadowCounterfactualContributingRunIds:
        'run-selected',
    StepResultKeys.committeeShadowCounterfactualMissingLaneIds: '',
    StepResultKeys.committeeShadowCounterfactualTokensIn: jsonEncode(
      counterfactualTokensIn,
    ),
    StepResultKeys.committeeShadowCounterfactualTokensOut: jsonEncode(
      counterfactualTokensOut,
    ),
    StepResultKeys.committeeShadowCounterfactualCostUsd: jsonEncode(
      counterfactualCostUsd,
    ),
    StepResultKeys.committeeShadowTruncated: jsonEncode(truncated),
    StepResultKeys.committeeShadowMissingFields: missingFields,
  }..addAll(overrides);
  for (final key in omitKeys) {
    result.remove(key);
  }
  return result;
}

List<TrajectoryEnvelope> _shadowPair({
  required String sampleId,
  required String joinId,
  String session = 'shadow-session',
  Map<String, String>? selector,
  Map<String, String>? route,
  bool routeFirst = false,
}) {
  final selectorRow = _step(
    session: session,
    node: 'review/select',
    state: StepState.complete,
    result: selector ?? _selectorProjection(sampleId: sampleId, joinId: joinId),
  );
  final routeRow = _step(
    session: session,
    node: 'review/route',
    state: StepState.complete,
    result: route ?? _shadowRouteProjection(sampleId: sampleId, joinId: joinId),
  );
  return routeFirst ? [routeRow, selectorRow] : [selectorRow, routeRow];
}

List<TrajectoryEnvelope> _mixedShadowRows() {
  _seq = 0;
  return [
    ..._shadowPair(sampleId: 'sample-full', joinId: 'join-full'),
    ..._shadowPair(
      sampleId: 'sample-sparse',
      joinId: 'join-sparse',
      selector: _selectorProjection(
        sampleId: 'sample-sparse',
        joinId: 'join-sparse',
        workBeadId: 'bead-b',
        nodePath: 'review/sparse-select',
        matchedRules: 'rule-sparse',
        omitted: 'security,tests',
        omitKeys: {StepResultKeys.selected},
      ),
      route: _shadowRouteProjection(
        sampleId: 'sample-sparse',
        joinId: 'join-sparse',
        workBeadId: 'bead-b',
        nodePath: 'review/sparse-select',
        routeNodePath: 'review/sparse-route',
        matchedRules: 'rule-sparse',
        omitted: 'security,tests',
        omittedGrades: const {'security': null, 'tests': 'B'},
        omittedTransports: const {'security': null, 'tests': 'envelope'},
        omittedDispositions: const {'security': null, 'tests': null},
        actualTokensIn: null,
        actualCostUsd: 0,
        truncated: true,
        missingFields: 'lanes.security.grade,actual.tokensIn',
        omitKeys: {StepResultKeys.committeeShadowSelected},
        overrides: {
          StepResultKeys.committeeShadowActualTokensOut: '{malformed',
          StepResultKeys.committeeShadowActualMissingLaneIds: '',
          StepResultKeys.committeeShadowCounterfactualTokensIn: '0',
        },
      ),
    ),
  ];
}

void main() {
  group('gate causes', () {
    test('classifies each named reason, and nothing else', () {
      final report = foldCommitteeReport(fixtureRows());
      expect(report.gateCauses, {
        GateCause.readinessHold: 1,
        GateCause.respecCap: 1,
        GateCause.gradeSpread: 1,
        GateCause.hardBlock: 1,
        GateCause.criticF: 1,
      });
    });

    test('an unrecognised reason is LOUD, never folded into a neighbour', () {
      expect(GateCause.fromReason('the moon was full'), GateCause.unclassified);
      expect(GateCause.fromReason(null), GateCause.unclassified);
    });
  });

  group('per-lane effectiveness', () {
    late CommitteeReport report;
    setUp(() => report = foldCommitteeReport(fixtureRows()));

    LaneReport lane(String name) =>
        report.lanes.firstWhere((row) => row.lane == name);

    test('lanes are alphabetical and carry grade counts', () {
      expect(report.lanes.map((row) => row.lane), [
        'adr-alignment',
        'coherence',
        'plan-completeness',
        'spec-validation',
        'test-coverage',
      ]);
      expect(lane('coherence').gradeCounts, {'A': 1, 'D': 1});
    });

    test('a D that opened a gate and was reworked reads as UPHELD', () {
      final coherence = lane('coherence');
      expect(coherence.adverseVerdicts, 1);
      expect(coherence.gateCausing, 1);
      expect(coherence.upheld, 1);
      expect(coherence.overridden, 0);
      expect(coherence.respecConverged, 1);
      expect(coherence.precision, 1.0);
    });

    test('an adjudicated close reads as OVERRIDDEN', () {
      final coverage = lane('test-coverage');
      expect(coverage.gateCausing, 1);
      expect(coverage.overridden, 1);
      expect(coverage.upheld, 0);
      expect(coverage.precision, 0.0);
    });

    test('an unwinnable respec loop is unconverged, not converged', () {
      final plan = lane('plan-completeness');
      expect(plan.respecConverged, 0);
      expect(plan.respecUnconverged, 1);
      expect(plan.respecNoFollowUp, 1);
    });

    test('a gate nothing followed is unresolved, never counted as upheld', () {
      expect(lane('spec-validation').unresolved, 1);
      expect(lane('spec-validation').upheld, 0);
      expect(lane('spec-validation').precision, isNull);
    });

    test('mean cost and duration come off the telemetry rows', () {
      expect(lane('coherence').runs, 2);
      expect(lane('coherence').runsFromFallback, 0);
      expect(lane('coherence').meanCostUsd, 9.0);
      expect(lane('coherence').meanDurationMs, 500000);
    });
  });

  group('per bead', () {
    test('rounds and dollars total per bead', () {
      final report = foldCommitteeReport(fixtureRows());
      expect(report.beads.map((row) => row.beadId), ['tg-aaa', 'tg-bbb']);
      expect(report.beads.first.rounds, 2);
      expect(report.beads.first.costUsd, 18.0);
      expect(report.beads.last.costUsd, 1.5);
    });
  });

  group('the .usage.json fallback', () {
    test('fills a (bead, lane) pair the log has no telemetry row for', () {
      final report = foldCommitteeReport(
        fixtureRows(),
        fallback: const [
          UsageSample(
            lane: 'adr-alignment',
            beadId: 'tg-bbb',
            fromFallback: true,
            costUsd: 2.5,
            durationMs: 90000,
          ),
        ],
      );
      final adr = report.lanes.firstWhere((row) => row.lane == 'adr-alignment');
      expect(adr.runs, 1);
      expect(adr.runsFromFallback, 1);
      expect(adr.meanCostUsd, 2.5);
    });

    test('never displaces a telemetry row for the same bead and lane', () {
      final report = foldCommitteeReport(
        fixtureRows(),
        fallback: const [
          UsageSample(
            lane: 'test-coverage',
            beadId: 'tg-bbb',
            fromFallback: true,
            costUsd: 99.0,
          ),
        ],
      );
      final coverage = report.lanes.firstWhere(
        (row) => row.lane == 'test-coverage',
      );
      expect(coverage.runs, 1);
      expect(coverage.runsFromFallback, 0);
      expect(coverage.meanCostUsd, 1.5);
    });
  });

  group('truncation', () {
    test('a cut window is reported, never printed as a total', () {
      final report = foldCommitteeReport(fixtureRows(), truncated: true);
      expect(report.truncated, isTrue);
      expect(report.toJson()['truncated'], isTrue);
    });
  });

  group('the step.transition adapter', () {
    late CommitteeReport report;
    setUp(() => report = foldCommitteeReport(stepOnlyRows()));

    LaneReport lane(String name) =>
        report.lanes.firstWhere((row) => row.lane == name);

    test('a window with NO verify.* or gate.* row still reports a populated '
        'lane table', () {
      expect(report.recordsRead, 9);
      expect(report.lanes.map((row) => row.lane), [
        'adr-alignment',
        'code-validation',
        'coherence',
      ]);
      expect(lane('coherence').gradeCounts, {'A': 1});
      expect(lane('adr-alignment').gradeCounts, {'D': 1});
      expect(lane('code-validation').gradeCounts, {'F': 1});
      // Gate-causing, dollars and seconds all come off the same step rows.
      expect(lane('adr-alignment').gateCausing, 1);
      expect(lane('coherence').runs, 1);
      expect(lane('coherence').runsFromFallback, 0);
      expect(lane('coherence').meanCostUsd, 5.0);
      expect(lane('coherence').meanDurationMs, 60000);
    });

    test('a gated row lights the cause histogram', () {
      expect(report.gateCauses, {GateCause.hardBlock: 1, GateCause.criticF: 1});
    });

    test('an escalating route UPHOLDS the adverse verdict it gated on', () {
      final adr = lane('adr-alignment');
      expect(adr.adverseVerdicts, 1);
      expect(adr.gateCausing, 1);
      expect(adr.upheld, 1);
      expect(adr.overridden, 0);
      expect(adr.precision, 1.0);
    });

    test('an advancing route OVERRIDES it', () {
      final code = lane('code-validation');
      expect(code.gateCausing, 1);
      expect(code.overridden, 1);
      expect(code.upheld, 0);
      expect(code.precision, 0.0);
    });

    test('an operator ruling on the lane result is an override', () {
      final ruled = foldCommitteeReport([
        ...stepOnlyRows(),
        _step(
          session: 's3',
          node: 'review/plan-completeness',
          state: StepState.complete,
          result: {'grade': 'D', 'round': '1', 'transport': 'operator-ruling'},
        ),
      ]);
      final plan = ruled.lanes.firstWhere(
        (row) => row.lane == 'plan-completeness',
      );
      expect(plan.gateCausing, 1);
      expect(plan.overridden, 1);
    });

    test('a route step contributes no verdict and no lane of its own', () {
      expect(report.lanes.map((row) => row.lane), isNot(contains('route')));
      expect(lane('adr-alignment').gradeCounts['D'], 1);
    });

    test('per-bead dollars total from the step rows', () {
      expect(report.beads.map((row) => row.beadId), ['tg-ccc', 'tg-ddd']);
      expect(report.beads.first.costUsd, 7.0);
      expect(report.beads.last.costUsd, 1.0);
    });

    test('the report names its sources', () {
      expect(report.sources.verdictsFromRecord, 0);
      expect(report.sources.verdictsFromStep, 3);
      expect(report.sources.usageFromTelemetry, 0);
      expect(report.sources.usageFromStep, 3);
      expect(report.sources.usageFromFallback, 0);
      expect(
        report.toJson()['sources'],
        containsPair('verdicts_from_step_transition', 3),
      );
      expect(
        renderCommitteeReport(report)[1],
        '  sources: verdicts 0 record / 3 step.transition · usage '
        '0 telemetry / 3 step.transition / 0 fallback',
      );
    });
  });

  group('usage precedence', () {
    test('a telemetry row beats a step-derived cost for the same pair', () {
      final report = foldCommitteeReport([
        ...stepOnlyRows(),
        _usage(session: 's3', attempt: 'att-10', cost: 42.0, durationMs: 1000),
      ]);
      final coherence = report.lanes.firstWhere(
        (row) => row.lane == 'coherence',
      );
      expect(coherence.runs, 1);
      expect(coherence.meanCostUsd, 42.0);
      expect(report.sources.usageFromTelemetry, 1);
      expect(report.sources.usageFromStep, 2);
    });

    test(
      'a step-derived cost beats a fallback sample, and is not fallback',
      () {
        final report = foldCommitteeReport(
          stepOnlyRows(),
          fallback: const [
            UsageSample(
              lane: 'coherence',
              beadId: 'tg-ccc',
              fromFallback: true,
              costUsd: 99.0,
            ),
          ],
        );
        final coherence = report.lanes.firstWhere(
          (row) => row.lane == 'coherence',
        );
        expect(coherence.runs, 1);
        expect(coherence.runsFromFallback, 0);
        expect(coherence.meanCostUsd, 5.0);
        expect(report.sources.usageFromFallback, 0);
      },
    );

    test('a fallback sample outside the window contributes NO dollars', () {
      final report = foldCommitteeReport(
        stepOnlyRows(),
        fallback: const [
          UsageSample(
            lane: 'readiness',
            beadId: 'lenny-qxx.7',
            fromFallback: true,
            costUsd: 18.92,
          ),
        ],
      );
      expect(report.sources.usageFromFallback, 0);
      expect(
        report.beads.map((row) => row.beadId),
        isNot(contains('lenny-qxx.7')),
      );
      expect(report.lanes.map((row) => row.lane), isNot(contains('readiness')));
    });
  });

  group('shadow selection fold', () {
    test('groups shadow samples by policy stage and rule', () {
      _seq = 0;
      final report = foldCommitteeReport([
        ..._shadowPair(
          sampleId: 'sample-b',
          joinId: 'join-b',
          selector: _selectorProjection(
            sampleId: 'sample-b',
            joinId: 'join-b',
            matchedRules: 'rule-b',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-b',
            joinId: 'join-b',
            matchedRules: 'rule-b',
          ),
        ),
        ..._shadowPair(
          sampleId: 'sample-a',
          joinId: 'join-a',
          selector: _selectorProjection(
            sampleId: 'sample-a',
            joinId: 'join-a',
            matchedRules: 'rule-a',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-a',
            joinId: 'join-a',
            matchedRules: 'rule-a',
          ),
        ),
      ]);

      expect(report.shadowSelection.groups.map((group) => group.ruleId), [
        'rule-a',
        'rule-b',
      ]);
      final group = report.shadowSelection.groups.first;
      expect(group.sampleCount, 1);
      expect(group.sampleIds, ['sample-a']);
      final sample = group.samples.single;
      expect(sample.selected.value, ['coherence', 'code-validation']);
      expect(sample.omitted.value, ['security']);
      expect(sample.omittedLaneGrades.value!['security']!.value, 'D');
      expect(
        sample.omittedLaneTransports.value!['security']!.value,
        'artifact',
      );
    });

    test('overlapping rules preserve distinct sample total', () {
      _seq = 0;
      final report = foldCommitteeReport([
        ..._shadowPair(
          sampleId: 'sample-overlap',
          joinId: 'join-overlap',
          selector: _selectorProjection(
            sampleId: 'sample-overlap',
            joinId: 'join-overlap',
            matchedRules: 'rule-a,rule-b',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-overlap',
            joinId: 'join-overlap',
            matchedRules: 'rule-a,rule-b',
          ),
        ),
        ..._shadowPair(
          sampleId: 'sample-none',
          joinId: 'join-none',
          selector: _selectorProjection(
            sampleId: 'sample-none',
            joinId: 'join-none',
            matchedRules: '',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-none',
            joinId: 'join-none',
            matchedRules: '',
          ),
        ),
      ]);

      expect(report.shadowSelection.distinctSampleCount, 2);
      expect(report.shadowSelection.groups.map((group) => group.ruleId), [
        kNoMatchedRuleId,
        'rule-a',
        'rule-b',
      ]);
      expect(
        report.shadowSelection.groups
            .map((group) => group.sampleCount)
            .reduce((left, right) => left + right),
        3,
      );
      expect(
        report.shadowSelection.groups
            .where((group) => group.ruleId != kNoMatchedRuleId)
            .every((group) => group.sampleIds.contains('sample-overlap')),
        isTrue,
      );
    });

    test('reports scope shape and usage aggregates', () {
      _seq = 0;
      final report = foldCommitteeReport([
        ..._shadowPair(
          sampleId: 'sample-a',
          joinId: 'join-a',
          selector: _selectorProjection(
            sampleId: 'sample-a',
            joinId: 'join-a',
            workBeadId: 'bead-a',
            nodePath: 'review/a',
            matchedRules: 'rule-a,rule-shared',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-a',
            joinId: 'join-a',
            workBeadId: 'bead-a',
            nodePath: 'review/a',
            matchedRules: 'rule-a,rule-shared',
            actualTokensIn: 100,
            actualTokensOut: 20,
            actualCostUsd: 1.25,
            counterfactualTokensIn: 50,
            counterfactualTokensOut: 10,
            counterfactualCostUsd: 0.5,
          ),
        ),
        ..._shadowPair(
          sampleId: 'sample-b',
          joinId: 'join-b',
          selector: _selectorProjection(
            sampleId: 'sample-b',
            joinId: 'join-b',
            workBeadId: 'bead-b',
            nodePath: 'review/b',
            matchedRules: 'rule-a',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-b',
            joinId: 'join-b',
            workBeadId: 'bead-b',
            nodePath: 'review/b',
            matchedRules: 'rule-a',
            actualTokensIn: 200,
            actualTokensOut: null,
            actualCostUsd: 2.75,
            counterfactualTokensIn: 75,
            counterfactualTokensOut: 15,
            counterfactualCostUsd: 0.75,
          ),
        ),
      ]);
      final group = report.shadowSelection.groups.firstWhere(
        (value) => value.ruleId == 'rule-a',
      );

      expect(group.scopeCoverage, {'bead-a|review/a': 1, 'bead-b|review/b': 1});
      expect(group.changeShapeCoverage, {'rule-a': 1, 'rule-a,rule-shared': 1});
      expect(group.actual.tokensIn.observedTotal, 300);
      expect(group.actual.tokensIn.observedSampleCount, 2);
      expect(group.actual.tokensOut.observedTotal, 20);
      expect(group.actual.tokensOut.notObservedSampleCount, 1);
      expect(group.actual.costUsd.observedTotal, 4.0);
      expect(group.counterfactual.tokensIn.observedTotal, 125);
      expect(group.counterfactual.tokensOut.observedTotal, 25);
      expect(group.counterfactual.costUsd.observedTotal, 1.25);
    });

    test('renders missing null empty and truncated distinctly', () {
      final report = foldCommitteeReport(_mixedShadowRows());
      final group = report.shadowSelection.groups.firstWhere(
        (value) => value.ruleId == 'rule-sparse',
      );
      final sample = group.samples.single;

      expect(sample.selected.state, ShadowFieldState.missing);
      expect(sample.actual.tokensIn.state, ShadowFieldState.notObserved);
      expect(sample.actual.tokensOut.state, ShadowFieldState.invalid);
      expect(sample.actual.costUsd.state, ShadowFieldState.observed);
      expect(sample.actual.costUsd.value, 0);
      expect(sample.actual.missingLaneIds.state, ShadowFieldState.observed);
      expect(sample.actual.missingLaneIds.value, isEmpty);
      expect(
        sample.omittedLaneGrades.value!['security']!.state,
        ShadowFieldState.notObserved,
      );
      expect(sample.truncated.value, isTrue);
      expect(sample.missingFields.value, [
        'lanes.security.grade',
        'actual.tokensIn',
      ]);
      expect(group.truncated, isTrue);

      final json = sample.toJson();
      expect((json['selected']! as Map)['state'], 'missing');
      final actual = json['actual']! as Map;
      expect((actual['tokens_in']! as Map)['state'], 'not_observed');
      expect((actual['tokens_out']! as Map)['state'], 'invalid');
      expect((actual['cost_usd']! as Map), {'state': 'observed', 'value': 0});
      expect((actual['missing_lane_ids']! as Map)['value'], isEmpty);
      final grades = json['omitted_lane_grades']! as Map;
      final gradeValues = grades['value']! as Map;
      expect((gradeValues['security']! as Map)['state'], 'not_observed');

      final rendered = renderCommitteeReport(report).join('\n');
      expect(rendered, contains('rule rule-sparse — 1 samples'));
      expect(rendered, contains('· TRUNCATED'));
      expect(rendered, contains('lanes: selected missing'));
      expect(rendered, contains('security=not observed'));
      expect(rendered, contains('missing lanes (empty)'));
      expect(rendered, contains('tokens in not observed'));
      expect(rendered, contains('tokens out invalid'));
      expect(rendered, contains('cost USD 0'));
      expect(rendered, contains('missingFields: lanes.security.grade'));
    });

    test('joins selector and shadow route out of order', () {
      _seq = 0;
      final rows = <TrajectoryEnvelope>[
        ..._shadowPair(
          sampleId: 'sample-joined',
          joinId: 'join-joined',
          routeFirst: true,
        ),
        _step(
          session: 'selector-only',
          node: 'review/select',
          state: StepState.complete,
          result: _selectorProjection(
            sampleId: 'sample-selector',
            joinId: 'join-selector',
          ),
        ),
        _step(
          session: 'route-only',
          node: 'review/route',
          state: StepState.complete,
          result: _shadowRouteProjection(
            sampleId: 'sample-route',
            joinId: 'join-route',
          ),
        ),
        ..._shadowPair(
          sampleId: 'sample-conflict',
          joinId: 'join-conflict',
          selector: _selectorProjection(
            sampleId: 'sample-conflict',
            joinId: 'join-conflict',
            policyVersion: 'policy-old',
          ),
          route: _shadowRouteProjection(
            sampleId: 'sample-conflict',
            joinId: 'join-conflict',
            policyVersion: 'policy-new',
          ),
        ),
        _step(
          session: 'unpaired',
          node: 'review/route',
          state: StepState.complete,
          result: _shadowRouteProjection(
            sampleId: 'sample-unpaired',
            joinId: 'unused',
            omitKeys: {StepResultKeys.committeeShadowJoinId},
          ),
        ),
      ];
      final report = foldCommitteeReport(rows);
      final samples = {
        for (final group in report.shadowSelection.groups)
          for (final sample in group.samples) sample.identity: sample,
      };

      expect(report.shadowSelection.distinctSampleCount, 5);
      expect(samples['sample-joined']!.joinState, ShadowJoinState.joined);
      expect(
        samples['sample-selector']!.joinState,
        ShadowJoinState.selectorOnly,
      );
      expect(samples['sample-route']!.joinState, ShadowJoinState.routeOnly);
      expect(samples['sample-conflict']!.joinState, ShadowJoinState.conflict);
      expect(
        samples['sample-conflict']!.conflictingKeys,
        contains(StepResultKeys.policyVersion),
      );
      expect(samples['sample-conflict']!.policyVersion.value, 'policy-new');
      expect(samples['sample-unpaired']!.joinState, ShadowJoinState.routeOnly);
      expect(
        samples['sample-unpaired']!.joinId.state,
        ShadowFieldState.missing,
      );
    });

    test('mixed shadow window matches the golden', () {
      final report = foldCommitteeReport(_mixedShadowRows());
      final json = report.toJson();
      expect(json, contains('shadow_selection'));
      final shadow = json['shadow_selection']! as Map;
      expect(shadow['distinct_sample_count'], 2);
      final groups = shadow['groups']! as List;
      expect(groups.map((value) => (value as Map)['rule_id']), [
        'rule-a',
        'rule-sparse',
      ]);
      expect(
        ((groups.first as Map)['samples']! as List).map(
          (value) => (value as Map)['identity'],
        ),
        ['sample-full'],
      );
      expect(
        (((groups.last as Map)['samples']! as List).single as Map)['identity'],
        'sample-sparse',
      );
      final actual = (groups.last as Map)['actual']! as Map;
      expect((actual['tokens_in']! as Map)['not_observed_sample_count'], 1);
      expect((actual['tokens_out']! as Map)['invalid_sample_count'], 1);

      final rendered = renderCommitteeReport(report).join('\n');
      final golden = File(
        'test/cli/fixtures/committee_report_shadow.golden.txt',
      ).readAsStringSync();
      expect(rendered, golden);
    });

    test('reports shadow provenance without changing empty windows', () {
      final shadow = foldCommitteeReport(_mixedShadowRows());
      expect(shadow.sources.shadowSelectionsFromStep, 2);
      expect(
        shadow.sources.toJson(),
        containsPair('shadow_selections_from_step_transition', 2),
      );
      expect(
        renderCommitteeReport(shadow),
        contains('  shadow selections: 2 step.transition'),
      );

      final empty = foldCommitteeReport(const []);
      expect(empty.sources.shadowSelectionsFromStep, 0);
      expect(empty.sources.verdictsFromRecord, 0);
      expect(empty.sources.verdictsFromStep, 0);
      expect(empty.sources.usageFromTelemetry, 0);
      expect(empty.sources.usageFromStep, 0);
      expect(empty.sources.usageFromFallback, 0);
      expect(empty.shadowSelection.distinctSampleCount, 0);
      expect(empty.shadowSelection.groups, isEmpty);
      final rendered = renderCommitteeReport(empty);
      expect(rendered, [
        'traj committee-report — 0 records',
        '  sources: verdicts 0 record / 0 step.transition · usage '
            '0 telemetry / 0 step.transition / 0 fallback',
        '  gates: none opened in this window',
        '',
        '  lane                  grades                  gated  ovr  uph  '
            r'unres  respec      $/run    s/run',
        '',
        r'  bead                  rounds   total $',
      ]);
      expect(empty.lanes, isEmpty);
      expect(empty.beads, isEmpty);
      expect(empty.gateCauses, isEmpty);
    });

    test('shadow fold is step-only and package stays a leaf', () {
      final shadow = foldCommitteeReport(_mixedShadowRows());
      final dedicated = foldCommitteeReport(fixtureRows());
      expect(shadow.sources.shadowSelectionsFromStep, 2);
      expect(dedicated.sources.shadowSelectionsFromStep, 0);

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        RegExp(r'^\s+grid_[^:]*:', multiLine: true).hasMatch(pubspec),
        isFalse,
      );
      final source = File(
        'lib/src/cli/committee_report.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('package:grid_assets')));
      expect(source, isNot(contains('shadow_accounting.dart')));
      expect(source, isNot(contains('shadow_corroboration_reader.dart')));
    });
  });
}
