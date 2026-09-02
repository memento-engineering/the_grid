/// The committee-report FOLD over a synthetic trajectory: the five named gate
/// causes, one operator override, an upheld gate that converged, and the
/// `.usage.json` fallback.
library;

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
}
