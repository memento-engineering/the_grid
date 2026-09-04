/// One SESSION's round, folded from the log — pure, I/O-free, over decoded
/// rows.
///
/// The corpus is `TrajectoryLogReader.rowsForSubject(<sessionId>)`: the SAME
/// read `traj show` performs (schema section 9's forensics shape), no new
/// query and no new store path. The sources are the DEDICATED Family-3
/// verdict records — `verify.verdict.recorded` and `verify.verdict.recovered`
/// — plus `verify.route.verdict` for the routing ruling.
///
/// This fold deliberately does NOT read the `step.transition` adapter. That
/// recovery path plus its precedence rule (a dedicated record always wins
/// over the adapter, the adapter over the `.usage.json` fallback) belongs to
/// `committee_report.dart` and stays in ONE fold
/// (`the_grid#committee-report-reads-step-transition`); a second, cross-round
/// view carrying a second precedence ladder is exactly the drift that
/// decision exists to prevent. A round whose writer emitted no dedicated
/// verdict therefore reports zero lanes — an honest empty, not a silent
/// half-source.
library;

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';
import 'committee_report.dart' show kAdverseGrades;

/// One lane's verdict in a round.
@immutable
class BeadRoundLane {
  /// Creates a lane verdict.
  const BeadRoundLane({
    required this.lane,
    required this.grade,
    required this.rationale,
    required this.transport,
    required this.rubricVersion,
    required this.stepPath,
    required this.stepRound,
  });

  /// The rubric lane that graded.
  final String lane;

  /// A-F, upper-cased.
  final String grade;

  /// The lane's own justification.
  final String rationale;

  /// How the grade arrived (`VerdictTransport.wire`).
  final String transport;

  /// The rubric revision that graded.
  final String rubricVersion;

  /// The engine node path the lane ran at.
  final String stepPath;

  /// The step's round ordinal.
  final int stepRound;

  /// True when the route treats this grade as adverse (D or F).
  bool get adverse => kAdverseGrades.contains(grade);

  /// The wire shape, snake_case like the rest of this package's reports.
  Map<String, Object?> toJson() => {
    'lane': lane,
    'grade': grade,
    'rationale': rationale,
    'transport': transport,
    'rubric_version': rubricVersion,
    'step_path': stepPath,
    'step_round': stepRound,
    'adverse': adverse,
  };
}

/// The routing ruling a round reached, when the log carries one.
@immutable
class BeadRoundRoute {
  /// Creates a routing ruling.
  const BeadRoundRoute({
    required this.verdict,
    required this.rule,
    required this.gatingLanes,
    this.spread,
  });

  /// `advance` or `escalate` (`RouteVerdictKind.wire`).
  final String verdict;

  /// The rule the router applied.
  final String rule;

  /// The lanes whose adverse grade an ESCALATING ruling names — empty on an
  /// advance.
  final List<String> gatingLanes;

  /// The router's grade spread, when it recorded one.
  final double? spread;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'verdict': verdict,
    'rule': rule,
    'spread': spread,
    'gating_lanes': gatingLanes,
  };
}

/// One round's verdict view.
@immutable
class BeadRoundVerdicts {
  /// Creates the view.
  const BeadRoundVerdicts({
    required this.lanes,
    required this.gatingLanes,
    required this.recordsRead,
    this.route,
  });

  /// Lanes, alphabetical — a stable order so two runs diff cleanly.
  final List<BeadRoundLane> lanes;

  /// The lanes this round gated on: the ESCALATING route ruling's own
  /// adverse-graded lanes when the log carries one, else every adverse lane.
  /// Empty means nothing gated.
  final List<String> gatingLanes;

  /// The routing ruling, when the log carries one.
  final BeadRoundRoute? route;

  /// How many envelopes the fold read.
  final int recordsRead;

  /// The wire shape.
  Map<String, Object?> toJson() => {
    'source': 'trajectory',
    'records_read': recordsRead,
    'route': route?.toJson(),
    'gating_lanes': gatingLanes,
    'lanes': [for (final lane in lanes) lane.toJson()],
  };
}

/// Folds [rows] — one session's log window — into its round view.
///
/// A lane graded more than once (a supervised restart re-runs and re-grades;
/// each incarnation appends fresh evidence) keeps the HIGHEST-`seq` verdict:
/// the log is append-only, so the last row is the current answer.
BeadRoundVerdicts foldBeadRound(List<TrajectoryEnvelope> rows) {
  final byLane = <String, (int, BeadRoundLane)>{};
  (int, VerifyRouteVerdict)? ruling;
  for (final envelope in rows) {
    final seq = envelope.seq ?? 0;
    switch (TrajectoryCodec.decode(envelope)) {
      case VerifyVerdictRecorded record:
        _keep(
          byLane,
          seq,
          BeadRoundLane(
            lane: record.lane,
            grade: record.grade.toUpperCase(),
            rationale: record.rationale,
            transport: record.transport.wire,
            rubricVersion: record.rubricVersion,
            stepPath: record.stepPath,
            stepRound: record.stepRound,
          ),
        );
      case VerifyVerdictRecovered record:
        _keep(
          byLane,
          seq,
          BeadRoundLane(
            lane: record.lane,
            grade: record.grade.toUpperCase(),
            rationale: record.rationale,
            transport: VerdictTransport.envelope.wire,
            rubricVersion: record.rubricVersion,
            stepPath: record.stepPath,
            stepRound: record.stepRound,
          ),
        );
      case VerifyRouteVerdict record:
        if (ruling == null || seq > ruling.$1) ruling = (seq, record);
      case _:
        break;
    }
  }
  final lanes = [for (final held in byLane.values) held.$2]
    ..sort((left, right) => left.lane.compareTo(right.lane));
  final route = ruling?.$2;
  final gating = switch (route) {
    null => [
      for (final lane in lanes)
        if (lane.adverse) lane.lane,
    ],
    VerifyRouteVerdict(verdict: RouteVerdictKind.advance) => const <String>[],
    VerifyRouteVerdict(:final grades) => _adverseLanesOf(grades),
  };
  return BeadRoundVerdicts(
    lanes: lanes,
    gatingLanes: gating,
    recordsRead: rows.length,
    route: route == null
        ? null
        : BeadRoundRoute(
            verdict: route.verdict.wire,
            rule: route.rule,
            spread: route.spread,
            gatingLanes: gating,
          ),
  );
}

void _keep(
  Map<String, (int, BeadRoundLane)> byLane,
  int seq,
  BeadRoundLane lane,
) {
  final held = byLane[lane.lane];
  if (held == null || seq >= held.$1) byLane[lane.lane] = (seq, lane);
}

/// The lane names in a route verdict's `grades` map carrying an adverse
/// grade. Each value is `{grade, source_record_id, sha_drift}`; a bare string
/// value is accepted too, since the map is an opaque payload.
List<String> _adverseLanesOf(Map<String, Object?> grades) {
  final named = <String>[];
  for (final entry in grades.entries) {
    final value = entry.value;
    final grade = value is Map ? '${value['grade'] ?? ''}' : '$value';
    if (kAdverseGrades.contains(grade.toUpperCase())) named.add(entry.key);
  }
  return named..sort();
}
