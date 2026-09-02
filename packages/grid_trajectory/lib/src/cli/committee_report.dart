/// The `traj committee-report` FOLD — pure, I/O-free, over decoded rows.
///
/// Every number the verb prints is derived HERE, from the log's own records:
/// `verify.verdict.recorded` (per-lane grade + transport), `gate.opened` /
/// `gate.closed` (the escalation cause and its adjudication), the operator
/// variant of `verify.route.verdict` (the override vehicle, schema §Family 3),
/// and `verify.usage.telemetry` (cost/duration). Nothing here touches a
/// socket or a file, so the whole report is fixture-testable.
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// Grades that open a gate (the bead's "D/F verdicts").
const Set<String> kAdverseGrades = {'D', 'F'};

/// Grades that count a respec round as CONVERGED.
const Set<String> kConvergedGrades = {'A', 'B'};

/// The escalation cause a gate's `reason` names.
///
/// `unclassified` is the LOUD bucket: a reason nobody recognises is counted
/// and printed under its own name, never folded into a neighbour where it
/// would read as a cause the committee understood.
enum GateCause {
  readinessHold('readiness-hold', ['readiness hold', 'readiness-hold']),
  respecCap('respec-cap', ['respec cap', 'respec-cap']),
  gradeSpread('grade-spread', ['grade spread', 'grade-spread']),
  hardBlock('hard-block', ['hard block', 'hard-block']),
  criticF('critic-f', ['critic f', 'critic-f']),
  unclassified('unclassified', []);

  const GateCause(this.wire, this.needles);

  /// Stable spelling in the `--json` object parsed downstream.
  final String wire;

  /// Phrases that name this cause in a gate's free-text reason.
  final List<String> needles;

  /// Classifies a gate's [reason]; null or unrecognised is [unclassified].
  static GateCause fromReason(String? reason) {
    if (reason == null) return GateCause.unclassified;
    final text = reason.toLowerCase();
    for (final cause in values) {
      for (final needle in cause.needles) {
        if (text.contains(needle)) return cause;
      }
    }
    return GateCause.unclassified;
  }
}

/// What became of a gate an adverse verdict opened.
enum GateDisposition {
  /// An operator route verdict, an adjudicated close, or an operator-transport
  /// verdict on the same step.
  overridden,

  /// No override, and a later round on the same lane followed — the committee
  /// was believed and the work was reworked.
  upheld,

  /// Still open, or nothing followed it yet.
  unresolved;

  String get wire => name;
}

/// Whether the respec round after an adverse verdict landed.
enum RespecOutcome {
  converged,
  unconverged,
  noFollowUp;

  String get wire => name;
}

/// One usage measurement, whatever its source.
@immutable
class UsageSample {
  const UsageSample({
    required this.lane,
    required this.beadId,
    required this.fromFallback,
    this.costUsd,
    this.durationMs,
  });

  final String lane;
  final String? beadId;

  /// True when the sample came off a `.usage.json` file rather than a
  /// `verify.usage.telemetry` row.
  final bool fromFallback;
  final double? costUsd;
  final int? durationMs;
}

/// One rubric lane's committee-effectiveness numbers.
@immutable
class LaneReport {
  const LaneReport({
    required this.lane,
    required this.gradeCounts,
    required this.adverseVerdicts,
    required this.gateCausing,
    required this.overridden,
    required this.upheld,
    required this.unresolved,
    required this.respecConverged,
    required this.respecUnconverged,
    required this.respecNoFollowUp,
    required this.runs,
    required this.runsFromFallback,
    this.meanCostUsd,
    this.meanDurationMs,
  });

  final String lane;

  /// Grade letter → count, over `verify.verdict.recorded` rows.
  final Map<String, int> gradeCounts;
  final int adverseVerdicts;
  final int gateCausing;
  final int overridden;
  final int upheld;
  final int unresolved;
  final int respecConverged;
  final int respecUnconverged;
  final int respecNoFollowUp;

  /// Usage samples attributed to this lane.
  final int runs;
  final int runsFromFallback;
  final double? meanCostUsd;
  final int? meanDurationMs;

  /// The share of adverse verdicts the operator upheld — null when no gate
  /// this lane opened has resolved yet (an unearned 0 is worse than a blank).
  double? get precision =>
      overridden + upheld == 0 ? null : upheld / (overridden + upheld);

  Map<String, Object?> toJson() => {
    'lane': lane,
    'grades': gradeCounts,
    'adverse_verdicts': adverseVerdicts,
    'gate_causing': gateCausing,
    'overridden': overridden,
    'upheld': upheld,
    'unresolved': unresolved,
    'precision': precision,
    'respec_converged': respecConverged,
    'respec_unconverged': respecUnconverged,
    'respec_no_follow_up': respecNoFollowUp,
    'runs': runs,
    'runs_from_fallback': runsFromFallback,
    'mean_cost_usd': meanCostUsd,
    'mean_duration_ms': meanDurationMs,
  };
}

/// One work bead's round and dollar totals.
@immutable
class BeadReport {
  const BeadReport({
    required this.beadId,
    required this.rounds,
    required this.costUsd,
  });

  final String beadId;

  /// Distinct `round` values the log carries for this bead.
  final int rounds;
  final double costUsd;

  Map<String, Object?> toJson() => {
    'bead': beadId,
    'rounds': rounds,
    'cost_usd': costUsd,
  };
}

/// The whole report.
@immutable
class CommitteeReport {
  const CommitteeReport({
    required this.lanes,
    required this.beads,
    required this.gateCauses,
    required this.recordsRead,
    required this.truncated,
  });

  /// Lanes, alphabetical — a stable order so two runs diff cleanly.
  final List<LaneReport> lanes;

  /// Beads, id-ordered.
  final List<BeadReport> beads;

  /// Cause → gates opened under it.
  final Map<GateCause, int> gateCauses;
  final int recordsRead;

  /// True when the reader could not hand over the whole window — the report
  /// is a PREFIX and says so rather than reporting totals it did not earn.
  final bool truncated;

  Map<String, Object?> toJson() => {
    'records_read': recordsRead,
    'truncated': truncated,
    'gate_causes': {
      for (final entry in gateCauses.entries) entry.key.wire: entry.value,
    },
    'lanes': [for (final lane in lanes) lane.toJson()],
    'beads': [for (final bead in beads) bead.toJson()],
  };
}

/// The step coordinate a verdict and a gate share.
String stepKey(String sessionId, String stepPath, int? stepRound) =>
    '$sessionId|$stepPath|${stepRound ?? '-'}';

class _Verdict {
  _Verdict({
    required this.sessionId,
    required this.lane,
    required this.grade,
    required this.round,
    required this.stepKey,
    required this.transport,
    required this.seq,
  });

  final String sessionId;
  final String lane;
  final String grade;
  final int round;
  final String stepKey;
  final VerdictTransport transport;
  final int seq;

  bool get isAdverse => kAdverseGrades.contains(grade);
}

class _LaneAccum {
  final Map<String, int> grades = {};
  int adverse = 0;
  int gateCausing = 0;
  int overridden = 0;
  int upheld = 0;
  int unresolved = 0;
  int converged = 0;
  int unconverged = 0;
  int noFollowUp = 0;
  int runs = 0;
  int runsFromFallback = 0;
  double cost = 0;
  int costSamples = 0;
  int duration = 0;
  int durationSamples = 0;
}

/// Folds [rows] (and any [fallback] usage samples the command recovered from
/// `.usage.json` files) into the report.
///
/// [truncated] is the reader's own statement that the window was cut; it is
/// carried through rather than swallowed, so a prefix is never printed as a
/// total.
CommitteeReport foldCommitteeReport(
  List<TrajectoryEnvelope> rows, {
  List<UsageSample> fallback = const [],
  bool truncated = false,
}) {
  // Pass 1 — the identity joins, built over ALL rows before anything is
  // interpreted: a verdict does not carry its bead and a usage row does not
  // carry its step, so both are resolved through envelope columns other
  // records promote. Order-independent by construction.
  final beadBySession = <String, String>{};
  final stepByAttempt = <String, String>{};
  final roundsBySession = <String, Set<int>>{};
  for (final envelope in rows) {
    final session = envelope.sessionId;
    if (session == null) continue;
    if (envelope.workBeadId case final String bead) {
      beadBySession[session] = bead;
    }
    if (envelope.round case final int round) {
      roundsBySession.putIfAbsent(session, () => <int>{}).add(round);
    }
    if (envelope.attemptId case final String attempt) {
      if (envelope.stepPath case final String path) {
        stepByAttempt[attempt] = stepKey(session, path, envelope.stepRound);
      }
    }
  }

  // Pass 2 — decode and collect the typed facts.
  final verdicts = <_Verdict>[];
  final gateByStep = <String, GateOpened>{};
  final causeByGate = <String, GateCause>{};
  final overriddenGates = <String>{};
  final usageRows = <VerifyUsageTelemetry>[];
  final usageSessionByAttempt = <String, String>{};
  for (final envelope in rows) {
    switch (TrajectoryCodec.decode(envelope)) {
      case VerifyVerdictRecorded record:
        verdicts.add(
          _Verdict(
            sessionId: record.sessionId,
            lane: record.lane,
            grade: record.grade.toUpperCase(),
            round: record.round,
            stepKey: stepKey(
              record.sessionId,
              record.stepPath,
              record.stepRound,
            ),
            transport: record.transport,
            seq: envelope.seq ?? 0,
          ),
        );
      case VerifyRouteVerdict record when record.isOperatorOverride:
        if (record.operatorGateId case final String gate) {
          overriddenGates.add(gate);
        }
      case GateOpened record:
        if (record.sessionId case final String session) {
          if (record.stepPath case final String path) {
            gateByStep[stepKey(session, path, record.stepRound)] = record;
          }
        }
        causeByGate[record.gateId] = GateCause.fromReason(record.reason);
      case GateClosed record
          when record.closeCause == GateCloseCause.adjudicated:
        overriddenGates.add(record.gateId);
      case VerifyUsageTelemetry record:
        usageRows.add(record);
        if (record.sessionId case final String session) {
          usageSessionByAttempt[record.attemptId] = session;
        }
      case _:
        break;
    }
  }

  // Lane attribution for usage: the verdicts themselves name the lane at a
  // step, and `attempt.process.started` names the step at an attempt.
  final laneByStep = <String, String>{
    for (final verdict in verdicts) verdict.stepKey: verdict.lane,
  };

  final lanes = <String, _LaneAccum>{};
  _LaneAccum accumFor(String lane) => lanes.putIfAbsent(lane, _LaneAccum.new);

  for (final verdict in verdicts) {
    final accum = accumFor(verdict.lane);
    accum.grades[verdict.grade] = (accum.grades[verdict.grade] ?? 0) + 1;
    if (!verdict.isAdverse) continue;
    accum.adverse++;
    final respec = _respecOutcomeFor(verdict, verdicts);
    switch (respec) {
      case RespecOutcome.converged:
        accum.converged++;
      case RespecOutcome.unconverged:
        accum.unconverged++;
      case RespecOutcome.noFollowUp:
        accum.noFollowUp++;
    }
    final gate = gateByStep[verdict.stepKey];
    if (gate == null) continue;
    accum.gateCausing++;
    final wasOverridden =
        overriddenGates.contains(gate.gateId) ||
        verdict.transport == VerdictTransport.operator;
    if (wasOverridden) {
      accum.overridden++;
    } else if (respec != RespecOutcome.noFollowUp) {
      accum.upheld++;
    } else {
      accum.unresolved++;
    }
  }

  // Usage: trajectory rows first; a `.usage.json` sample is folded only where
  // its (bead, lane) pair produced NO telemetry row (the bead's fallback rule).
  final samples = <UsageSample>[];
  final covered = <String>{};
  for (final row in usageRows) {
    final step = stepByAttempt[row.attemptId];
    if (step == null) continue;
    final lane = laneByStep[step];
    if (lane == null) continue;
    final session =
        usageSessionByAttempt[row.attemptId] ?? step.split('|').first;
    final bead = beadBySession[session];
    covered.add('${bead ?? '-'}|$lane');
    samples.add(
      UsageSample(
        lane: lane,
        beadId: bead,
        fromFallback: false,
        costUsd: row.costUsd,
        durationMs: row.durationMs,
      ),
    );
  }
  for (final sample in fallback) {
    if (covered.contains('${sample.beadId ?? '-'}|${sample.lane}')) continue;
    samples.add(sample);
  }

  final costByBead = <String, double>{};
  for (final sample in samples) {
    final accum = accumFor(sample.lane);
    accum.runs++;
    if (sample.fromFallback) accum.runsFromFallback++;
    if (sample.costUsd case final double cost) {
      accum.cost += cost;
      accum.costSamples++;
      if (sample.beadId case final String bead) {
        costByBead[bead] = (costByBead[bead] ?? 0) + cost;
      }
    }
    if (sample.durationMs case final int duration) {
      accum.duration += duration;
      accum.durationSamples++;
    }
  }

  final roundsByBead = <String, Set<int>>{};
  roundsBySession.forEach((session, rounds) {
    final bead = beadBySession[session];
    if (bead == null) return;
    roundsByBead.putIfAbsent(bead, () => <int>{}).addAll(rounds);
  });

  final beadIds = <String>{...roundsByBead.keys, ...costByBead.keys}.toList()
    ..sort();
  final laneNames = lanes.keys.toList()..sort();
  final causeCounts = <GateCause, int>{};
  for (final cause in causeByGate.values) {
    causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
  }

  return CommitteeReport(
    recordsRead: rows.length,
    truncated: truncated,
    gateCauses: {
      for (final cause in GateCause.values)
        if (causeCounts[cause] case final int count) cause: count,
    },
    lanes: [
      for (final name in laneNames)
        if (lanes[name] case final _LaneAccum accum)
          LaneReport(
            lane: name,
            gradeCounts: Map<String, int>.fromEntries(
              (accum.grades.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key)))
                  .map((entry) => MapEntry(entry.key, entry.value)),
            ),
            adverseVerdicts: accum.adverse,
            gateCausing: accum.gateCausing,
            overridden: accum.overridden,
            upheld: accum.upheld,
            unresolved: accum.unresolved,
            respecConverged: accum.converged,
            respecUnconverged: accum.unconverged,
            respecNoFollowUp: accum.noFollowUp,
            runs: accum.runs,
            runsFromFallback: accum.runsFromFallback,
            meanCostUsd: accum.costSamples == 0
                ? null
                : accum.cost / accum.costSamples,
            meanDurationMs: accum.durationSamples == 0
                ? null
                : accum.duration ~/ accum.durationSamples,
          ),
    ],
    beads: [
      for (final bead in beadIds)
        BeadReport(
          beadId: bead,
          rounds: roundsByBead[bead]?.length ?? 0,
          costUsd: costByBead[bead] ?? 0,
        ),
    ],
  );
}

/// The respec round that followed [verdict]: the LATEST verdict on the same
/// session and lane at `round + 1`.
RespecOutcome _respecOutcomeFor(_Verdict verdict, List<_Verdict> all) {
  _Verdict? follow;
  for (final other in all) {
    if (other.sessionId != verdict.sessionId) continue;
    if (other.lane != verdict.lane) continue;
    if (other.round != verdict.round + 1) continue;
    if (follow == null || other.seq > follow.seq) follow = other;
  }
  if (follow == null) return RespecOutcome.noFollowUp;
  return kConvergedGrades.contains(follow.grade)
      ? RespecOutcome.converged
      : RespecOutcome.unconverged;
}
