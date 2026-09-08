/// The `traj committee-report` FOLD — pure, I/O-free, over decoded rows.
///
/// Every number the verb prints is derived HERE, from the log's own records,
/// out of TWO sources that are never merged silently:
///
/// * the DEDICATED families — `verify.verdict.recorded` (per-lane grade +
///   transport), `gate.opened` / `gate.closed` (the escalation cause and its
///   adjudication), the operator variant of `verify.route.verdict` (the
///   override vehicle, schema §Family 3), and `verify.usage.telemetry`
///   (cost/duration) — whenever a writer emits them; and
/// * the `step.transition` ADAPTER, which recovers the same facts from where
///   they actually ride today: a completed step's `result` map and a gated
///   step's `failure_reason` (schema §2 F5), plus durable selector and shadow
///   route receipts for per-rule committee evidence.
///
/// A dedicated record always wins over the adapter, and the adapter always wins
/// over the `.usage.json` fallback. [CommitteeReport.sources] reports how many
/// of each the fold counted, so a reader can tell a wired writer from the
/// adapter. Nothing here touches a socket or a file, so the whole report is
/// fixture-testable.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// Grades that open a gate (the bead's "D/F verdicts").
const Set<String> kAdverseGrades = {'D', 'F'};

/// Grades that count a respec round as CONVERGED.
const Set<String> kConvergedGrades = {'A', 'B'};

/// The `result` keys a completed step carries — grid_engine's `ResultKeys` and
/// `ResultMetricFields`, re-expressed rather than imported because
/// `grid_trajectory` is a LEAF with zero `grid_*` dependencies (decision
/// `the_grid#grid-trajectory-leaf-package`). Only keys the report reads appear.
abstract final class StepResultKeys {
  /// The letter grade a critic lane recorded (`ResultKeys.grade`).
  static const grade = 'grade';

  /// How the grade arrived (`ResultKeys.transport`).
  static const transport = 'transport';

  /// The committee's own respec round, written by the critic envelope.
  static const round = 'round';

  /// The typed route ruling the engine router persisted
  /// (`ResultKeys.routeVerdict`).
  static const routeVerdict = 'route_verdict';

  /// One run's harness cost (`ResultMetricFields.costUsd`).
  static const costUsd = 'costUsd';

  /// Marks the selector projection carried by this result.
  static const shadow = 'shadow';

  /// The selector that chose the committee lanes.
  static const source = 'source';

  /// The committee stage the selection ran for.
  static const stage = 'stage';

  /// The selected rubric ids, comma-joined.
  static const selected = 'selected';

  /// Every policy rule the sample matched, comma-joined.
  static const matchedRules = 'matchedRules';

  /// The number of classifier attempts made by the selector.
  static const classifierAttempts = 'classifierAttempts';

  /// The stable identity of one selection sample.
  static const sampleId = 'sampleId';

  /// The stable identity joining selector and route result rows.
  static const joinId = 'joinId';

  /// The policy version used to select lanes.
  static const policyVersion = 'policyVersion';

  /// The work bead the selection applies to.
  static const workBeadId = 'workBeadId';

  /// The selector node path.
  static const nodePath = 'nodePath';

  /// The hypothetically omitted rubric ids, comma-joined.
  static const omitted = 'omitted';

  /// The digest of the evidence presented to the selector.
  static const evidenceDigest = 'evidenceDigest';

  /// Evidence ids the selector could not observe, comma-joined.
  static const missingEvidenceIds = 'missingEvidenceIds';

  /// Canonical-JSON rubric id to lane-input digest map.
  static const laneInputDigests = 'laneInputDigests';

  /// Classifier result kinds, comma-joined in attempt order.
  static const classifierAttemptKinds = 'classifierAttemptKinds';

  /// The route receipt's sample identity.
  static const committeeShadowSampleId = 'committeeShadowSampleId';

  /// The route receipt's selector join identity.
  static const committeeShadowJoinId = 'committeeShadowJoinId';

  /// The route receipt's policy version.
  static const committeeShadowPolicyVersion = 'committeeShadowPolicyVersion';

  /// The route receipt's work bead identity.
  static const committeeShadowWorkBeadId = 'committeeShadowWorkBeadId';

  /// The route receipt's canonical-JSON committee round.
  static const committeeShadowRound = 'committeeShadowRound';

  /// The route receipt's selector node path.
  static const committeeShadowNodePath = 'committeeShadowNodePath';

  /// The node path of the shadowed authoritative route.
  static const committeeShadowRouteNodePath = 'committeeShadowRouteNodePath';

  /// The route receipt's committee stage.
  static const committeeShadowStage = 'committeeShadowStage';

  /// The route receipt's selection source.
  static const committeeShadowSource = 'committeeShadowSource';

  /// The route receipt's selected rubric ids, comma-joined.
  static const committeeShadowSelected = 'committeeShadowSelected';

  /// The route receipt's omitted rubric ids, comma-joined.
  static const committeeShadowOmitted = 'committeeShadowOmitted';

  /// The route receipt's matched rule ids, comma-joined.
  static const committeeShadowMatchedRules = 'committeeShadowMatchedRules';

  /// The route receipt's selector evidence digest.
  static const committeeShadowEvidenceDigest = 'committeeShadowEvidenceDigest';

  /// The route receipt's missing evidence ids, comma-joined.
  static const committeeShadowMissingEvidenceIds =
      'committeeShadowMissingEvidenceIds';

  /// The route receipt's canonical-JSON lane-input digest map.
  static const committeeShadowLaneInputDigests =
      'committeeShadowLaneInputDigests';

  /// The route receipt's classifier result kinds, comma-joined.
  static const committeeShadowClassifierAttemptKinds =
      'committeeShadowClassifierAttemptKinds';

  /// Rubric ids whose observed grades required action, comma-joined.
  static const committeeShadowActionLaneIds = 'committeeShadowActionLaneIds';

  /// The canonical-JSON gate disposition of the shadow receipt.
  static const committeeShadowGateDisposition =
      'committeeShadowGateDisposition';

  /// Canonical-JSON join keys for the downstream route.
  static const committeeShadowDownstreamJoinKeys =
      'committeeShadowDownstreamJoinKeys';

  /// Canonical-JSON omitted-rubric to actual-grade map.
  static const committeeShadowOmittedLaneGrades =
      'committeeShadowOmittedLaneGrades';

  /// Canonical-JSON omitted-rubric to grade-transport map.
  static const committeeShadowOmittedLaneTransports =
      'committeeShadowOmittedLaneTransports';

  /// Canonical-JSON omitted-rubric to gate-disposition map.
  static const committeeShadowOmittedLaneDispositions =
      'committeeShadowOmittedLaneDispositions';

  /// Actual committee run ids contributing usage, comma-joined.
  static const committeeShadowActualContributingRunIds =
      'committeeShadowActualContributingRunIds';

  /// Actual committee lanes with absent usage, comma-joined.
  static const committeeShadowActualMissingLaneIds =
      'committeeShadowActualMissingLaneIds';

  /// Canonical-JSON actual input-token total.
  static const committeeShadowActualTokensIn = 'committeeShadowActualTokensIn';

  /// Canonical-JSON actual output-token total.
  static const committeeShadowActualTokensOut =
      'committeeShadowActualTokensOut';

  /// Canonical-JSON actual cost total.
  static const committeeShadowActualCostUsd = 'committeeShadowActualCostUsd';

  /// Counterfactual committee run ids contributing usage, comma-joined.
  static const committeeShadowCounterfactualContributingRunIds =
      'committeeShadowCounterfactualContributingRunIds';

  /// Counterfactual lanes with absent usage, comma-joined.
  static const committeeShadowCounterfactualMissingLaneIds =
      'committeeShadowCounterfactualMissingLaneIds';

  /// Canonical-JSON counterfactual input-token total.
  static const committeeShadowCounterfactualTokensIn =
      'committeeShadowCounterfactualTokensIn';

  /// Canonical-JSON counterfactual output-token total.
  static const committeeShadowCounterfactualTokensOut =
      'committeeShadowCounterfactualTokensOut';

  /// Canonical-JSON counterfactual cost total.
  static const committeeShadowCounterfactualCostUsd =
      'committeeShadowCounterfactualCostUsd';

  /// Canonical-JSON declaration that the writer clipped the receipt.
  static const committeeShadowTruncated = 'committeeShadowTruncated';

  /// Fields the route receipt writer could not capture, comma-joined.
  static const committeeShadowMissingFields = 'committeeShadowMissingFields';
}

/// The group id for an observed, empty [ShadowSelectionSample.matchedRules].
const String kNoMatchedRuleId = '(none)';

/// The observation state of one shadow receipt field.
enum ShadowFieldState {
  /// The result map did not contain the field.
  missing('missing'),

  /// The field contained canonical JSON `null`.
  notObserved('not_observed'),

  /// The field was present but did not decode to its declared shape.
  invalid('invalid'),

  /// The field was present and decoded successfully.
  observed('observed');

  const ShadowFieldState(this.wire);

  /// Stable spelling in report JSON.
  final String wire;
}

/// One totally decoded field from a shadow selection result map.
///
/// State is held beside the value so absence, canonical JSON `null`, malformed
/// input, an observed empty collection, and an observed zero remain distinct.
@immutable
class ShadowField<T> {
  /// Creates a field whose key was absent.
  const ShadowField.missing() : state = ShadowFieldState.missing, value = null;

  /// Creates a field whose canonical JSON value was `null`.
  const ShadowField.notObserved()
    : state = ShadowFieldState.notObserved,
      value = null;

  /// Creates a field whose wire value was malformed or had the wrong type.
  const ShadowField.invalid() : state = ShadowFieldState.invalid, value = null;

  /// Creates a successfully observed field, defensively copying collections.
  ShadowField.observed(T value)
    : state = ShadowFieldState.observed,
      value = _copyShadowValue(value) as T;

  /// The explicit state carried by this field.
  final ShadowFieldState state;

  /// The decoded value, present only when [state] is
  /// [ShadowFieldState.observed].
  final T? value;

  /// The stable state-and-value JSON object.
  Map<String, Object?> toJson() => switch (state) {
    ShadowFieldState.missing => const {'state': 'missing'},
    ShadowFieldState.notObserved => const {'state': 'not_observed'},
    ShadowFieldState.invalid => const {'state': 'invalid'},
    ShadowFieldState.observed => {
      'state': 'observed',
      'value': _shadowJsonValue(value),
    },
  };
}

/// How the selector and shadow-route halves of a sample assembled.
enum ShadowJoinState {
  /// Both halves joined and their shared fields agree.
  joined('joined'),

  /// Only a selector result was observed.
  selectorOnly('selector_only'),

  /// Only a shadow-route result was observed.
  routeOnly('route_only'),

  /// Both halves joined but at least one shared field disagreed.
  conflict('conflict');

  const ShadowJoinState(this.wire);

  /// Stable spelling in report JSON.
  final String wire;
}

/// Per-sample usage evidence for one actual or counterfactual committee.
@immutable
class ShadowUsageObservation {
  /// Creates one immutable usage observation.
  ShadowUsageObservation({
    required this.contributingRunIds,
    required this.missingLaneIds,
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
  });

  /// Run identities contributing to the totals.
  final ShadowField<List<String>> contributingRunIds;

  /// Lanes whose usage was not captured.
  final ShadowField<List<String>> missingLaneIds;

  /// Input tokens, with the writer's sparsity preserved.
  final ShadowField<int> tokensIn;

  /// Output tokens, with the writer's sparsity preserved.
  final ShadowField<int> tokensOut;

  /// Billed cost, with the writer's sparsity preserved.
  final ShadowField<num> costUsd;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'contributing_run_ids': contributingRunIds.toJson(),
    'missing_lane_ids': missingLaneIds.toJson(),
    'tokens_in': tokensIn.toJson(),
    'tokens_out': tokensOut.toJson(),
    'cost_usd': costUsd.toJson(),
  };
}

/// A field-state-aware total for one usage metric across a rule group.
@immutable
class ShadowMetricAggregate {
  /// Creates one aggregate with a count for every possible field state.
  const ShadowMetricAggregate({
    required this.observedTotal,
    required this.observedSampleCount,
    required this.notObservedSampleCount,
    required this.missingSampleCount,
    required this.invalidSampleCount,
  });

  /// Sum of observed values, or null when no sample observed this metric.
  final num? observedTotal;

  /// Samples contributing to [observedTotal].
  final int observedSampleCount;

  /// Samples carrying canonical JSON `null`.
  final int notObservedSampleCount;

  /// Samples whose result map omitted the key.
  final int missingSampleCount;

  /// Samples whose value could not be decoded.
  final int invalidSampleCount;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'observed_total': observedTotal,
    'observed_sample_count': observedSampleCount,
    'not_observed_sample_count': notObservedSampleCount,
    'missing_sample_count': missingSampleCount,
    'invalid_sample_count': invalidSampleCount,
  };
}

/// Actual or counterfactual usage totals across one rule group.
@immutable
class ShadowUsageAggregate {
  /// Creates the three metric aggregates.
  const ShadowUsageAggregate({
    required this.tokensIn,
    required this.tokensOut,
    required this.costUsd,
  });

  /// Input-token aggregate.
  final ShadowMetricAggregate tokensIn;

  /// Output-token aggregate.
  final ShadowMetricAggregate tokensOut;

  /// Cost aggregate.
  final ShadowMetricAggregate costUsd;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'tokens_in': tokensIn.toJson(),
    'tokens_out': tokensOut.toJson(),
    'cost_usd': costUsd.toJson(),
  };
}

/// One joined, per-sample shadow committee evidence packet.
@immutable
class ShadowSelectionSample {
  /// Creates an immutable sample packet.
  ShadowSelectionSample({
    required this.identity,
    required this.seq,
    required this.joinState,
    required Iterable<String> conflictingKeys,
    required this.sampleId,
    required this.joinId,
    required this.policyVersion,
    required this.stage,
    required this.source,
    required this.selected,
    required this.omitted,
    required this.matchedRules,
    required this.classifierAttempts,
    required this.workBeadId,
    required this.round,
    required this.selectorNodePath,
    required this.routeNodePath,
    required this.evidenceDigest,
    required this.missingEvidenceIds,
    required this.laneInputDigests,
    required this.classifierAttemptKinds,
    required this.actionLaneIds,
    required this.gateDisposition,
    required this.downstreamJoinKeys,
    required this.omittedLaneGrades,
    required this.omittedLaneTransports,
    required this.omittedLaneDispositions,
    required this.actual,
    required this.counterfactual,
    required this.truncated,
    required this.missingFields,
  }) : conflictingKeys = List.unmodifiable(conflictingKeys);

  /// Rendered identity: sample id, then join id, then row sequence.
  final String identity;

  /// Highest source-row sequence contributing to this packet.
  final int seq;

  /// Whether selector and route halves joined cleanly.
  final ShadowJoinState joinState;

  /// Shared selector wire keys whose two halves disagreed.
  final List<String> conflictingKeys;

  /// Durable sample identity.
  final ShadowField<String> sampleId;

  /// Durable selector-to-route join identity.
  final ShadowField<String> joinId;

  /// Committee selection policy version.
  final ShadowField<String> policyVersion;

  /// Committee stage.
  final ShadowField<String> stage;

  /// Selection source.
  final ShadowField<String> source;

  /// Actually selected rubric ids, retaining writer order.
  final ShadowField<List<String>> selected;

  /// Hypothetically omitted rubric ids, retaining writer order.
  final ShadowField<List<String>> omitted;

  /// All policy rules matched by this sample, retaining writer order.
  final ShadowField<List<String>> matchedRules;

  /// Number of classifier attempts made by the selector.
  final ShadowField<int> classifierAttempts;

  /// Work bead selected for.
  final ShadowField<String> workBeadId;

  /// Committee round.
  final ShadowField<int> round;

  /// Selector node path.
  final ShadowField<String> selectorNodePath;

  /// Shadowed route node path.
  final ShadowField<String> routeNodePath;

  /// Digest of the selector's evidence.
  final ShadowField<String> evidenceDigest;

  /// Evidence ids that were missing.
  final ShadowField<List<String>> missingEvidenceIds;

  /// Rubric id to selector-input digest.
  final ShadowField<Map<String, String>> laneInputDigests;

  /// Classifier outcome kinds in attempt order.
  final ShadowField<List<String>> classifierAttemptKinds;

  /// Rubric ids whose actual grades required action.
  final ShadowField<List<String>> actionLaneIds;

  /// Actual route disposition produced by the omitted-lane evidence.
  final ShadowField<String> gateDisposition;

  /// Stable downstream route joins.
  final ShadowField<Map<String, String>> downstreamJoinKeys;

  /// Actual grades for every omitted lane; null members are not observed.
  final ShadowField<Map<String, ShadowField<String>>> omittedLaneGrades;

  /// Grade transports for every omitted lane; null members are not observed.
  final ShadowField<Map<String, ShadowField<String>>> omittedLaneTransports;

  /// Gate dispositions for every omitted lane; null members are not observed.
  final ShadowField<Map<String, ShadowField<String>>> omittedLaneDispositions;

  /// Actual full-committee usage.
  final ShadowUsageObservation actual;

  /// Usage the selected committee would have consumed.
  final ShadowUsageObservation counterfactual;

  /// Whether the writer declared this sample truncated.
  final ShadowField<bool> truncated;

  /// Fields the writer declared absent, retaining writer order.
  final ShadowField<List<String>> missingFields;

  /// True only for an observed writer declaration of truncation.
  bool get isTruncated =>
      truncated.state == ShadowFieldState.observed && truncated.value == true;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'identity': identity,
    'seq': seq,
    'join_state': joinState.wire,
    'conflicting_keys': conflictingKeys,
    'sample_id': sampleId.toJson(),
    'join_id': joinId.toJson(),
    'policy_version': policyVersion.toJson(),
    'stage': stage.toJson(),
    'source': source.toJson(),
    'selected': selected.toJson(),
    'omitted': omitted.toJson(),
    'matched_rules': matchedRules.toJson(),
    'classifier_attempts': classifierAttempts.toJson(),
    'work_bead_id': workBeadId.toJson(),
    'round': round.toJson(),
    'selector_node_path': selectorNodePath.toJson(),
    'route_node_path': routeNodePath.toJson(),
    'evidence_digest': evidenceDigest.toJson(),
    'missing_evidence_ids': missingEvidenceIds.toJson(),
    'lane_input_digests': laneInputDigests.toJson(),
    'classifier_attempt_kinds': classifierAttemptKinds.toJson(),
    'action_lane_ids': actionLaneIds.toJson(),
    'gate_disposition': gateDisposition.toJson(),
    'downstream_join_keys': downstreamJoinKeys.toJson(),
    'omitted_lane_grades': omittedLaneGrades.toJson(),
    'omitted_lane_transports': omittedLaneTransports.toJson(),
    'omitted_lane_dispositions': omittedLaneDispositions.toJson(),
    'actual': actual.toJson(),
    'counterfactual': counterfactual.toJson(),
    'truncated': truncated.toJson(),
    'missing_fields': missingFields.toJson(),
  };
}

/// One policy-version, stage, and matched-rule evidence group.
@immutable
class ShadowRuleReport {
  /// Creates an immutable rule report in stable sample order.
  ShadowRuleReport({
    required this.policyVersion,
    required this.stage,
    required this.ruleId,
    required Iterable<String> sampleIds,
    required Map<String, int> scopeCoverage,
    required Map<String, int> changeShapeCoverage,
    required this.truncatedSampleCount,
    required this.actual,
    required this.counterfactual,
    required Iterable<ShadowSelectionSample> samples,
  }) : sampleIds = List.unmodifiable(sampleIds),
       scopeCoverage = Map.unmodifiable(scopeCoverage),
       changeShapeCoverage = Map.unmodifiable(changeShapeCoverage),
       samples = List.unmodifiable(samples);

  /// Rendered policy version, including explicit sparse-state labels.
  final String policyVersion;

  /// Rendered committee stage, including explicit sparse-state labels.
  final String stage;

  /// Matched rule id, `(none)`, or an explicit sparse-state label.
  final String ruleId;

  /// Rendered identities of the group's samples.
  final List<String> sampleIds;

  /// Exact `workBeadId|nodePath` pair to sample count, sorted by key.
  final Map<String, int> scopeCoverage;

  /// Complete ordered matched-rule signature to sample count, sorted by key.
  final Map<String, int> changeShapeCoverage;

  /// Samples carrying an observed true writer truncation declaration.
  final int truncatedSampleCount;

  /// Actual usage totals and field-state counts.
  final ShadowUsageAggregate actual;

  /// Counterfactual usage totals and field-state counts.
  final ShadowUsageAggregate counterfactual;

  /// Per-sample evidence packets in rendered-identity order.
  final List<ShadowSelectionSample> samples;

  /// Number of samples in this overlapping rule group.
  int get sampleCount => samples.length;

  /// Whether any sample carries an observed true truncation declaration.
  bool get truncated => truncatedSampleCount > 0;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'policy_version': policyVersion,
    'stage': stage,
    'rule_id': ruleId,
    'sample_count': sampleCount,
    'sample_ids': sampleIds,
    'scope_coverage': scopeCoverage,
    'change_shape_coverage': changeShapeCoverage,
    'truncated_sample_count': truncatedSampleCount,
    'actual': actual.toJson(),
    'counterfactual': counterfactual.toJson(),
    'samples': [for (final sample in samples) sample.toJson()],
  };
}

/// The shadow committee section of a committee report.
@immutable
class ShadowSelectionReport {
  /// Creates an immutable shadow selection report.
  ShadowSelectionReport({
    required this.distinctSampleCount,
    required this.unidentifiedSampleCount,
    required Iterable<ShadowRuleReport> groups,
  }) : groups = List.unmodifiable(groups);

  /// An empty report for windows containing no shadow selection result rows.
  factory ShadowSelectionReport.empty() => ShadowSelectionReport(
    distinctSampleCount: 0,
    unidentifiedSampleCount: 0,
    groups: const [],
  );

  /// Canonical samples, counted once even when rules overlap.
  final int distinctSampleCount;

  /// Canonical samples without an observed sample id.
  final int unidentifiedSampleCount;

  /// Rule reports sorted by policy version, stage, and rule id.
  final List<ShadowRuleReport> groups;

  /// The stable JSON object.
  Map<String, Object?> toJson() => {
    'distinct_sample_count': distinctSampleCount,
    'unidentified_sample_count': unidentifiedSampleCount,
    'groups': [for (final group in groups) group.toJson()],
  };
}

/// The lane a step path names — its LAST segment (`review/coherence` →
/// `coherence`).
String laneOfStepPath(String stepPath) => stepPath.split('/').last;

/// The sibling SCOPE of a step: its session plus its path's parent
/// (`s1` + `review/coherence` → `s1|review/`).
///
/// This is the gate↔verdict join for step-derived facts, and it is deliberately
/// NOT [stepKey]: a `gated` row carries the ESCALATING node's path — the route
/// step (`packages/grid_engine/lib/src/circuit/capability_host.dart` passes
/// `request.nodePath` to `stepGated`) — never the critic lane's, so an exact
/// step match would never join. The gate and the verdicts that opened it are
/// siblings under one parent.
String stepScope(String sessionId, String stepPath) {
  final cut = stepPath.lastIndexOf('/');
  return '$sessionId|${cut < 0 ? '' : stepPath.substring(0, cut + 1)}';
}

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

  /// True only when the sample came off a `.usage.json` fallback file.
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

  /// Grade letter → count, over dedicated or step-derived verdicts.
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

/// How many observations each SOURCE contributed — the report's own provenance
/// line. Dedicated records, the `step.transition` adapter, and the
/// `.usage.json` fallback are different evidence and are never merged silently.
@immutable
class ReportSources {
  const ReportSources({
    this.verdictsFromRecord = 0,
    this.verdictsFromStep = 0,
    this.usageFromTelemetry = 0,
    this.usageFromStep = 0,
    this.usageFromFallback = 0,
    this.shadowSelectionsFromStep = 0,
  });

  /// Verdicts off `verify.verdict.recorded`.
  final int verdictsFromRecord;

  /// Verdicts recovered from `step.transition` result maps.
  final int verdictsFromStep;

  /// Usage samples off `verify.usage.telemetry`.
  final int usageFromTelemetry;

  /// Usage samples recovered from `step.transition` result maps.
  final int usageFromStep;

  /// Usage samples off `--telemetry-root` `.usage.json` files.
  final int usageFromFallback;

  /// Canonical shadow selection samples assembled from step result maps.
  final int shadowSelectionsFromStep;

  Map<String, Object?> toJson() => {
    'verdicts_from_record': verdictsFromRecord,
    'verdicts_from_step_transition': verdictsFromStep,
    'usage_from_telemetry': usageFromTelemetry,
    'usage_from_step_transition': usageFromStep,
    'usage_from_fallback': usageFromFallback,
    'shadow_selections_from_step_transition': shadowSelectionsFromStep,
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
    required this.sources,
    required this.shadowSelection,
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

  /// Where each folded number came from.
  final ReportSources sources;

  /// Per-rule shadow committee selection evidence.
  final ShadowSelectionReport shadowSelection;

  Map<String, Object?> toJson() => {
    'records_read': recordsRead,
    'truncated': truncated,
    'sources': sources.toJson(),
    'gate_causes': {
      for (final entry in gateCauses.entries) entry.key.wire: entry.value,
    },
    'lanes': [for (final lane in lanes) lane.toJson()],
    'beads': [for (final bead in beads) bead.toJson()],
    'shadow_selection': shadowSelection.toJson(),
  };
}

/// The step coordinate a verdict and a gate share.
String stepKey(String sessionId, String stepPath, int? stepRound) =>
    '$sessionId|$stepPath|${stepRound ?? '-'}';

/// The `transport` an OPERATOR RULING stamps on a lane result — grid_engine's
/// `kOperatorRulingTransport`, mirrored per [StepResultKeys]. Private: a leaf
/// package must not export a second public spelling of a grid_engine constant.
const String _kOperatorRulingTransport = 'operator-ruling';

/// A `result` value as text. The writer types the map `Map<String, String>`
/// (`StationTrajectoryRecorder.stepComplete`), so text is the real case.
String? _asString(Object? value) => value is String ? value : null;

/// A `result` value as a double — `tryParse`, never `parse`: one malformed
/// result must not throw the whole report away.
double? _asDouble(Object? value) => switch (value) {
  final num number => number.toDouble(),
  final String text => double.tryParse(text),
  _ => null,
};

/// A `result` value as an int, on the same fail-soft rule as [_asDouble].
int? _asInt(Object? value) => switch (value) {
  final int number => number,
  final String text => int.tryParse(text),
  _ => null,
};

const Set<String> _committeeShadowRouteKeys = {
  StepResultKeys.committeeShadowSampleId,
  StepResultKeys.committeeShadowJoinId,
  StepResultKeys.committeeShadowPolicyVersion,
  StepResultKeys.committeeShadowWorkBeadId,
  StepResultKeys.committeeShadowRound,
  StepResultKeys.committeeShadowNodePath,
  StepResultKeys.committeeShadowRouteNodePath,
  StepResultKeys.committeeShadowStage,
  StepResultKeys.committeeShadowSource,
  StepResultKeys.committeeShadowSelected,
  StepResultKeys.committeeShadowOmitted,
  StepResultKeys.committeeShadowMatchedRules,
  StepResultKeys.committeeShadowEvidenceDigest,
  StepResultKeys.committeeShadowMissingEvidenceIds,
  StepResultKeys.committeeShadowLaneInputDigests,
  StepResultKeys.committeeShadowClassifierAttemptKinds,
  StepResultKeys.committeeShadowActionLaneIds,
  StepResultKeys.committeeShadowGateDisposition,
  StepResultKeys.committeeShadowDownstreamJoinKeys,
  StepResultKeys.committeeShadowOmittedLaneGrades,
  StepResultKeys.committeeShadowOmittedLaneTransports,
  StepResultKeys.committeeShadowOmittedLaneDispositions,
  StepResultKeys.committeeShadowActualContributingRunIds,
  StepResultKeys.committeeShadowActualMissingLaneIds,
  StepResultKeys.committeeShadowActualTokensIn,
  StepResultKeys.committeeShadowActualTokensOut,
  StepResultKeys.committeeShadowActualCostUsd,
  StepResultKeys.committeeShadowCounterfactualContributingRunIds,
  StepResultKeys.committeeShadowCounterfactualMissingLaneIds,
  StepResultKeys.committeeShadowCounterfactualTokensIn,
  StepResultKeys.committeeShadowCounterfactualTokensOut,
  StepResultKeys.committeeShadowCounterfactualCostUsd,
  StepResultKeys.committeeShadowTruncated,
  StepResultKeys.committeeShadowMissingFields,
};

enum _ShadowRowKind { selector, route }

class _ShadowRow {
  _ShadowRow({
    required this.kind,
    required Map<String, Object?> result,
    required this.seq,
  }) : result = Map.unmodifiable(result);

  final _ShadowRowKind kind;
  final Map<String, Object?> result;
  final int seq;
}

/// The elapsed span between two stamps, or null when either is absent.
int? _spanMs(DateTime? from, DateTime? to) =>
    from == null || to == null ? null : to.difference(from).inMilliseconds;

/// The (bead, lane) pair one usage sample is attributed to — the precedence key
/// shared by all three tiers.
String _pairKey(UsageSample sample) => '${sample.beadId ?? '-'}|${sample.lane}';

/// The `step.transition` ADAPTER's yield — the dedicated families' observations,
/// recovered from step rows.
class _StepFacts {
  /// Verdicts recovered from completed critic steps.
  final List<_Verdict> verdicts = [];

  /// Cost/duration samples recovered from completed steps.
  final List<UsageSample> usage = [];

  /// Every gated row's cause, in row order — the histogram.
  final List<GateCause> gateCauses = [];

  /// The scopes a gate parked in — the attribution key ([stepScope]).
  final Set<String> gatedScopes = {};

  /// Scope → the LATEST route ruling recorded in it.
  final Map<String, ({RouteVerdictKind kind, int seq})> routes = {};

  /// Selector and shadow-route result halves recovered from completed steps.
  final List<_ShadowRow> shadowRows = [];
}

/// Maps ONE `step.transition` row onto the fold's observations.
///
/// A completed step carries what the dedicated families would have said:
/// `result['grade']` is a verdict, `result['costUsd']` a usage sample,
/// `result['route_verdict']` the route's ruling, and a `gated` row's
/// `failure_reason` the gate cause. A route step contributes its ruling and its
/// cost but NEVER a verdict.
void _adaptStepTransition(
  StepTransition record, {
  required int seq,
  required Map<String, String> beadBySession,
  required _StepFacts into,
}) {
  final lane = laneOfStepPath(record.stepPath);
  final scope = stepScope(record.sessionId, record.stepPath);
  switch (record.state) {
    case StepState.gated:
      into.gateCauses.add(GateCause.fromReason(record.failureReason));
      into.gatedScopes.add(scope);
    case StepState.complete:
      final result = record.result;
      if (result == null) return;
      if (_asString(result[StepResultKeys.shadow]) == 'selection') {
        into.shadowRows.add(
          _ShadowRow(kind: _ShadowRowKind.selector, result: result, seq: seq),
        );
      }
      if (_committeeShadowRouteKeys.any(result.containsKey)) {
        into.shadowRows.add(
          _ShadowRow(kind: _ShadowRowKind.route, result: result, seq: seq),
        );
      }
      final ruling = _asString(result[StepResultKeys.routeVerdict]);
      if (ruling != null) {
        RouteVerdictKind? kind;
        for (final value in RouteVerdictKind.values) {
          if (value.wire == ruling) kind = value;
        }
        final held = into.routes[scope];
        if (kind != null && (held == null || seq >= held.seq)) {
          into.routes[scope] = (kind: kind, seq: seq);
        }
      } else if (_asString(result[StepResultKeys.grade])
          case final String grade) {
        into.verdicts.add(
          _Verdict(
            sessionId: record.sessionId,
            lane: lane,
            grade: grade.toUpperCase(),
            // The committee's own round first; `step_round` is the fallback
            // ladder, which a gate-cleared re-arm bumps (schema §2 F5).
            round: _asInt(result[StepResultKeys.round]) ?? record.stepRound,
            stepKey: stepKey(
              record.sessionId,
              record.stepPath,
              record.stepRound,
            ),
            scope: scope,
            transport:
                _asString(result[StepResultKeys.transport]) ==
                    _kOperatorRulingTransport
                ? VerdictTransport.operator
                : VerdictTransport.stepTransition,
            seq: seq,
          ),
        );
      }
      if (_asDouble(result[StepResultKeys.costUsd]) case final double cost) {
        into.usage.add(
          UsageSample(
            lane: lane,
            beadId: beadBySession[record.sessionId],
            fromFallback: false,
            costUsd: cost,
            durationMs: _spanMs(record.startedAt, record.completedAt),
          ),
        );
      }
    case StepState.pending:
    case StepState.running:
    case StepState.ready:
    case StepState.failed:
      return;
  }
}

ShadowField<String> _plainStringField(Map<String, Object?> result, String key) {
  if (!result.containsKey(key)) return const ShadowField.missing();
  return switch (result[key]) {
    final String value => ShadowField.observed(value),
    _ => const ShadowField.invalid(),
  };
}

ShadowField<List<String>> _csvField(Map<String, Object?> result, String key) {
  if (!result.containsKey(key)) return const ShadowField.missing();
  return switch (result[key]) {
    final String value => ShadowField.observed(
      value.isEmpty ? const <String>[] : value.split(','),
    ),
    _ => const ShadowField.invalid(),
  };
}

ShadowField<int> _plainIntField(Map<String, Object?> result, String key) {
  if (!result.containsKey(key)) return const ShadowField.missing();
  final raw = result[key];
  if (raw is! String) return const ShadowField.invalid();
  return switch (int.tryParse(raw)) {
    final int value => ShadowField.observed(value),
    null => const ShadowField.invalid(),
  };
}

ShadowField<T> _jsonField<T>(
  Map<String, Object?> result,
  String key, {
  required bool Function(Object? value) accepts,
  required T Function(Object? value) convert,
}) {
  if (!result.containsKey(key)) return const ShadowField.missing();
  final raw = result[key];
  if (raw is! String) return const ShadowField.invalid();
  try {
    final decoded = jsonDecode(raw);
    if (decoded == null) return const ShadowField.notObserved();
    if (!accepts(decoded)) return const ShadowField.invalid();
    return ShadowField.observed(convert(decoded));
  } on FormatException {
    return const ShadowField.invalid();
  }
}

ShadowField<int> _jsonIntField(Map<String, Object?> result, String key) =>
    _jsonField<int>(
      result,
      key,
      accepts: (value) => value is int,
      convert: (value) => value! as int,
    );

ShadowField<num> _jsonNumField(Map<String, Object?> result, String key) =>
    _jsonField<num>(
      result,
      key,
      accepts: (value) => value is num,
      convert: (value) => value! as num,
    );

ShadowField<bool> _jsonBoolField(Map<String, Object?> result, String key) =>
    _jsonField<bool>(
      result,
      key,
      accepts: (value) => value is bool,
      convert: (value) => value! as bool,
    );

ShadowField<String> _jsonStringField(Map<String, Object?> result, String key) =>
    _jsonField<String>(
      result,
      key,
      accepts: (value) => value is String,
      convert: (value) => value! as String,
    );

ShadowField<Map<String, String>> _jsonStringMapField(
  Map<String, Object?> result,
  String key,
) => _jsonField<Map<String, String>>(
  result,
  key,
  accepts: (value) =>
      value is Map &&
      value.keys.every((entry) => entry is String) &&
      value.values.every((entry) => entry is String),
  convert: (value) {
    final decoded = value! as Map;
    final keys = decoded.keys.cast<String>().toList()..sort();
    return Map.unmodifiable({
      for (final mapKey in keys) mapKey: decoded[mapKey]! as String,
    });
  },
);

ShadowField<Map<String, ShadowField<String>>> _jsonOmittedMapField(
  Map<String, Object?> result,
  String key,
) => _jsonField<Map<String, ShadowField<String>>>(
  result,
  key,
  accepts: (value) =>
      value is Map &&
      value.keys.every((entry) => entry is String) &&
      value.values.every((entry) => entry == null || entry is String),
  convert: (value) {
    final decoded = value! as Map;
    final keys = decoded.keys.cast<String>().toList()..sort();
    return Map.unmodifiable({
      for (final mapKey in keys)
        mapKey: switch (decoded[mapKey]) {
          final String member => ShadowField.observed(member),
          null => const ShadowField<String>.notObserved(),
          _ => const ShadowField<String>.invalid(),
        },
    });
  },
);

T _mergedShadowField<T>(
  _ShadowRow? selector,
  String selectorKey,
  _ShadowRow? route,
  String routeKey,
  T Function(Map<String, Object?> result, String key) decode,
) {
  if (route != null && route.result.containsKey(routeKey)) {
    return decode(route.result, routeKey);
  }
  return decode(selector?.result ?? const {}, selectorKey);
}

bool _sharedShadowFieldConflicts<T>(
  _ShadowRow selector,
  String selectorKey,
  _ShadowRow route,
  String routeKey,
  ShadowField<T> Function(Map<String, Object?> result, String key) decode,
) {
  if (!selector.result.containsKey(selectorKey) ||
      !route.result.containsKey(routeKey)) {
    return false;
  }
  return jsonEncode(decode(selector.result, selectorKey).toJson()) !=
      jsonEncode(decode(route.result, routeKey).toJson());
}

List<String> _shadowConflicts(_ShadowRow selector, _ShadowRow route) {
  final conflicts = <String>[];

  void compare<T>(
    String selectorKey,
    String routeKey,
    ShadowField<T> Function(Map<String, Object?> result, String key) decode,
  ) {
    if (_sharedShadowFieldConflicts(
      selector,
      selectorKey,
      route,
      routeKey,
      decode,
    )) {
      conflicts.add(selectorKey);
    }
  }

  compare(
    StepResultKeys.sampleId,
    StepResultKeys.committeeShadowSampleId,
    _plainStringField,
  );
  compare(
    StepResultKeys.joinId,
    StepResultKeys.committeeShadowJoinId,
    _plainStringField,
  );
  compare(
    StepResultKeys.policyVersion,
    StepResultKeys.committeeShadowPolicyVersion,
    _plainStringField,
  );
  compare(
    StepResultKeys.workBeadId,
    StepResultKeys.committeeShadowWorkBeadId,
    _plainStringField,
  );
  compare(
    StepResultKeys.round,
    StepResultKeys.committeeShadowRound,
    _jsonIntField,
  );
  compare(
    StepResultKeys.nodePath,
    StepResultKeys.committeeShadowNodePath,
    _plainStringField,
  );
  compare(
    StepResultKeys.stage,
    StepResultKeys.committeeShadowStage,
    _plainStringField,
  );
  compare(
    StepResultKeys.source,
    StepResultKeys.committeeShadowSource,
    _plainStringField,
  );
  compare(
    StepResultKeys.selected,
    StepResultKeys.committeeShadowSelected,
    _csvField,
  );
  compare(
    StepResultKeys.omitted,
    StepResultKeys.committeeShadowOmitted,
    _csvField,
  );
  compare(
    StepResultKeys.matchedRules,
    StepResultKeys.committeeShadowMatchedRules,
    _csvField,
  );
  compare(
    StepResultKeys.evidenceDigest,
    StepResultKeys.committeeShadowEvidenceDigest,
    _plainStringField,
  );
  compare(
    StepResultKeys.missingEvidenceIds,
    StepResultKeys.committeeShadowMissingEvidenceIds,
    _csvField,
  );
  compare(
    StepResultKeys.laneInputDigests,
    StepResultKeys.committeeShadowLaneInputDigests,
    _jsonStringMapField,
  );
  compare(
    StepResultKeys.classifierAttemptKinds,
    StepResultKeys.committeeShadowClassifierAttemptKinds,
    _csvField,
  );
  return conflicts..sort();
}

ShadowSelectionSample _assembleShadowSample(
  _ShadowRow? selector,
  _ShadowRow? route,
) {
  assert(selector != null || route != null);
  final conflicts = selector != null && route != null
      ? _shadowConflicts(selector, route)
      : const <String>[];
  final sampleId = _mergedShadowField(
    selector,
    StepResultKeys.sampleId,
    route,
    StepResultKeys.committeeShadowSampleId,
    _plainStringField,
  );
  final joinId = _mergedShadowField(
    selector,
    StepResultKeys.joinId,
    route,
    StepResultKeys.committeeShadowJoinId,
    _plainStringField,
  );
  final seq = switch ((selector?.seq, route?.seq)) {
    (final int left, final int right) => left > right ? left : right,
    (final int value, null) || (null, final int value) => value,
    (null, null) => 0,
  };
  final identity = switch ((sampleId.state, joinId.state)) {
    (ShadowFieldState.observed, _) => sampleId.value!,
    (_, ShadowFieldState.observed) => joinId.value!,
    _ => 'row:$seq',
  };
  final routeResult = route?.result ?? const <String, Object?>{};

  return ShadowSelectionSample(
    identity: identity,
    seq: seq,
    joinState: switch ((selector, route, conflicts.isNotEmpty)) {
      (_ShadowRow(), _ShadowRow(), true) => ShadowJoinState.conflict,
      (_ShadowRow(), _ShadowRow(), false) => ShadowJoinState.joined,
      (_ShadowRow(), null, _) => ShadowJoinState.selectorOnly,
      (null, _ShadowRow(), _) => ShadowJoinState.routeOnly,
      _ => throw StateError('a shadow sample must have at least one half'),
    },
    conflictingKeys: conflicts,
    sampleId: sampleId,
    joinId: joinId,
    policyVersion: _mergedShadowField(
      selector,
      StepResultKeys.policyVersion,
      route,
      StepResultKeys.committeeShadowPolicyVersion,
      _plainStringField,
    ),
    stage: _mergedShadowField(
      selector,
      StepResultKeys.stage,
      route,
      StepResultKeys.committeeShadowStage,
      _plainStringField,
    ),
    source: _mergedShadowField(
      selector,
      StepResultKeys.source,
      route,
      StepResultKeys.committeeShadowSource,
      _plainStringField,
    ),
    selected: _mergedShadowField(
      selector,
      StepResultKeys.selected,
      route,
      StepResultKeys.committeeShadowSelected,
      _csvField,
    ),
    omitted: _mergedShadowField(
      selector,
      StepResultKeys.omitted,
      route,
      StepResultKeys.committeeShadowOmitted,
      _csvField,
    ),
    matchedRules: _mergedShadowField(
      selector,
      StepResultKeys.matchedRules,
      route,
      StepResultKeys.committeeShadowMatchedRules,
      _csvField,
    ),
    classifierAttempts: _plainIntField(
      selector?.result ?? const {},
      StepResultKeys.classifierAttempts,
    ),
    workBeadId: _mergedShadowField(
      selector,
      StepResultKeys.workBeadId,
      route,
      StepResultKeys.committeeShadowWorkBeadId,
      _plainStringField,
    ),
    round: _mergedShadowField(
      selector,
      StepResultKeys.round,
      route,
      StepResultKeys.committeeShadowRound,
      _jsonIntField,
    ),
    selectorNodePath: _mergedShadowField(
      selector,
      StepResultKeys.nodePath,
      route,
      StepResultKeys.committeeShadowNodePath,
      _plainStringField,
    ),
    routeNodePath: _plainStringField(
      routeResult,
      StepResultKeys.committeeShadowRouteNodePath,
    ),
    evidenceDigest: _mergedShadowField(
      selector,
      StepResultKeys.evidenceDigest,
      route,
      StepResultKeys.committeeShadowEvidenceDigest,
      _plainStringField,
    ),
    missingEvidenceIds: _mergedShadowField(
      selector,
      StepResultKeys.missingEvidenceIds,
      route,
      StepResultKeys.committeeShadowMissingEvidenceIds,
      _csvField,
    ),
    laneInputDigests: _mergedShadowField(
      selector,
      StepResultKeys.laneInputDigests,
      route,
      StepResultKeys.committeeShadowLaneInputDigests,
      _jsonStringMapField,
    ),
    classifierAttemptKinds: _mergedShadowField(
      selector,
      StepResultKeys.classifierAttemptKinds,
      route,
      StepResultKeys.committeeShadowClassifierAttemptKinds,
      _csvField,
    ),
    actionLaneIds: _csvField(
      routeResult,
      StepResultKeys.committeeShadowActionLaneIds,
    ),
    gateDisposition: _jsonStringField(
      routeResult,
      StepResultKeys.committeeShadowGateDisposition,
    ),
    downstreamJoinKeys: _jsonStringMapField(
      routeResult,
      StepResultKeys.committeeShadowDownstreamJoinKeys,
    ),
    omittedLaneGrades: _jsonOmittedMapField(
      routeResult,
      StepResultKeys.committeeShadowOmittedLaneGrades,
    ),
    omittedLaneTransports: _jsonOmittedMapField(
      routeResult,
      StepResultKeys.committeeShadowOmittedLaneTransports,
    ),
    omittedLaneDispositions: _jsonOmittedMapField(
      routeResult,
      StepResultKeys.committeeShadowOmittedLaneDispositions,
    ),
    actual: ShadowUsageObservation(
      contributingRunIds: _csvField(
        routeResult,
        StepResultKeys.committeeShadowActualContributingRunIds,
      ),
      missingLaneIds: _csvField(
        routeResult,
        StepResultKeys.committeeShadowActualMissingLaneIds,
      ),
      tokensIn: _jsonIntField(
        routeResult,
        StepResultKeys.committeeShadowActualTokensIn,
      ),
      tokensOut: _jsonIntField(
        routeResult,
        StepResultKeys.committeeShadowActualTokensOut,
      ),
      costUsd: _jsonNumField(
        routeResult,
        StepResultKeys.committeeShadowActualCostUsd,
      ),
    ),
    counterfactual: ShadowUsageObservation(
      contributingRunIds: _csvField(
        routeResult,
        StepResultKeys.committeeShadowCounterfactualContributingRunIds,
      ),
      missingLaneIds: _csvField(
        routeResult,
        StepResultKeys.committeeShadowCounterfactualMissingLaneIds,
      ),
      tokensIn: _jsonIntField(
        routeResult,
        StepResultKeys.committeeShadowCounterfactualTokensIn,
      ),
      tokensOut: _jsonIntField(
        routeResult,
        StepResultKeys.committeeShadowCounterfactualTokensOut,
      ),
      costUsd: _jsonNumField(
        routeResult,
        StepResultKeys.committeeShadowCounterfactualCostUsd,
      ),
    ),
    truncated: _jsonBoolField(
      routeResult,
      StepResultKeys.committeeShadowTruncated,
    ),
    missingFields: _csvField(
      routeResult,
      StepResultKeys.committeeShadowMissingFields,
    ),
  );
}

String? _observedJoinId(_ShadowRow row) {
  final field = switch (row.kind) {
    _ShadowRowKind.selector => _plainStringField(
      row.result,
      StepResultKeys.joinId,
    ),
    _ShadowRowKind.route => _plainStringField(
      row.result,
      StepResultKeys.committeeShadowJoinId,
    ),
  };
  return field.state == ShadowFieldState.observed ? field.value : null;
}

ShadowSelectionReport _foldShadowSelection(List<_ShadowRow> rows) {
  if (rows.isEmpty) return ShadowSelectionReport.empty();

  final selectorsByJoin = <String, _ShadowRow>{};
  final routesByJoin = <String, _ShadowRow>{};
  final unpaired = <_ShadowRow>[];
  for (final row in rows) {
    final joinId = _observedJoinId(row);
    if (joinId == null) {
      unpaired.add(row);
      continue;
    }
    final byJoin = switch (row.kind) {
      _ShadowRowKind.selector => selectorsByJoin,
      _ShadowRowKind.route => routesByJoin,
    };
    final held = byJoin[joinId];
    if (held == null || row.seq >= held.seq) byJoin[joinId] = row;
  }

  final joinIds = <String>{
    ...selectorsByJoin.keys,
    ...routesByJoin.keys,
  }.toList()..sort();
  final assembled = <ShadowSelectionSample>[
    for (final joinId in joinIds)
      _assembleShadowSample(selectorsByJoin[joinId], routesByJoin[joinId]),
    for (final row in unpaired)
      _assembleShadowSample(
        row.kind == _ShadowRowKind.selector ? row : null,
        row.kind == _ShadowRowKind.route ? row : null,
      ),
  ];

  // A retried terminal row can reproduce a whole assembled packet. Sample
  // identity, rather than row count, is the canonical observation boundary.
  final canonicalByIdentity = <String, ShadowSelectionSample>{};
  for (final sample in assembled) {
    final held = canonicalByIdentity[sample.identity];
    if (held == null || sample.seq >= held.seq) {
      canonicalByIdentity[sample.identity] = sample;
    }
  }
  final samples = canonicalByIdentity.values.toList()
    ..sort((left, right) => left.identity.compareTo(right.identity));

  final samplesByGroup =
      <(String, String, String), List<ShadowSelectionSample>>{};
  for (final sample in samples) {
    final policy = _groupFieldLabel(sample.policyVersion);
    final stage = _groupFieldLabel(sample.stage);
    final rules = _ruleGroups(sample.matchedRules);
    for (final rule in rules) {
      samplesByGroup
          .putIfAbsent((policy, stage, rule), () => <ShadowSelectionSample>[])
          .add(sample);
    }
  }

  final groupKeys = samplesByGroup.keys.toList()
    ..sort((left, right) {
      final policy = left.$1.compareTo(right.$1);
      if (policy != 0) return policy;
      final stage = left.$2.compareTo(right.$2);
      if (stage != 0) return stage;
      return left.$3.compareTo(right.$3);
    });
  return ShadowSelectionReport(
    distinctSampleCount: samples.length,
    unidentifiedSampleCount: samples
        .where((sample) => sample.sampleId.state != ShadowFieldState.observed)
        .length,
    groups: [
      for (final key in groupKeys)
        _shadowRuleReport(
          policyVersion: key.$1,
          stage: key.$2,
          ruleId: key.$3,
          samples: samplesByGroup[key]!,
        ),
    ],
  );
}

ShadowRuleReport _shadowRuleReport({
  required String policyVersion,
  required String stage,
  required String ruleId,
  required List<ShadowSelectionSample> samples,
}) {
  final ordered = samples.toList()
    ..sort((left, right) => left.identity.compareTo(right.identity));
  return ShadowRuleReport(
    policyVersion: policyVersion,
    stage: stage,
    ruleId: ruleId,
    sampleIds: [for (final sample in ordered) sample.identity]..sort(),
    scopeCoverage: _coverageHistogram([
      for (final sample in ordered)
        '${_groupFieldLabel(sample.workBeadId)}|'
            '${_groupFieldLabel(sample.selectorNodePath)}',
    ]),
    changeShapeCoverage: _coverageHistogram([
      for (final sample in ordered) _changeShapeLabel(sample.matchedRules),
    ]),
    truncatedSampleCount: ordered.where((sample) => sample.isTruncated).length,
    actual: _usageAggregate([for (final sample in ordered) sample.actual]),
    counterfactual: _usageAggregate([
      for (final sample in ordered) sample.counterfactual,
    ]),
    samples: ordered,
  );
}

List<String> _ruleGroups(ShadowField<List<String>> rules) =>
    switch (rules.state) {
      ShadowFieldState.missing => const ['(missing)'],
      ShadowFieldState.notObserved => const ['(not observed)'],
      ShadowFieldState.invalid => const ['(invalid)'],
      ShadowFieldState.observed => switch (rules.value!) {
        [] => const [kNoMatchedRuleId],
        final values => [
          for (final value in values) value.isEmpty ? '(empty)' : value,
        ],
      },
    };

String _changeShapeLabel(ShadowField<List<String>> rules) =>
    switch (rules.state) {
      ShadowFieldState.missing => '(missing)',
      ShadowFieldState.notObserved => '(not observed)',
      ShadowFieldState.invalid => '(invalid)',
      ShadowFieldState.observed => switch (rules.value!) {
        [] => kNoMatchedRuleId,
        final values =>
          values.map((value) => value.isEmpty ? '(empty)' : value).join(','),
      },
    };

String _groupFieldLabel(ShadowField<String> field) => switch (field.state) {
  ShadowFieldState.missing => '(missing)',
  ShadowFieldState.notObserved => '(not observed)',
  ShadowFieldState.invalid => '(invalid)',
  ShadowFieldState.observed => field.value!.isEmpty ? '(empty)' : field.value!,
};

Map<String, int> _coverageHistogram(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final keys = counts.keys.toList()..sort();
  return Map.unmodifiable({for (final key in keys) key: counts[key]!});
}

ShadowUsageAggregate _usageAggregate(
  Iterable<ShadowUsageObservation> observations,
) {
  final values = observations.toList();
  return ShadowUsageAggregate(
    tokensIn: _metricAggregate([for (final value in values) value.tokensIn]),
    tokensOut: _metricAggregate([for (final value in values) value.tokensOut]),
    costUsd: _metricAggregate([for (final value in values) value.costUsd]),
  );
}

ShadowMetricAggregate _metricAggregate(Iterable<ShadowField<num>> fields) {
  num total = 0;
  var observed = 0;
  var notObserved = 0;
  var missing = 0;
  var invalid = 0;
  for (final field in fields) {
    switch (field.state) {
      case ShadowFieldState.missing:
        missing++;
      case ShadowFieldState.notObserved:
        notObserved++;
      case ShadowFieldState.invalid:
        invalid++;
      case ShadowFieldState.observed:
        total += field.value!;
        observed++;
    }
  }
  return ShadowMetricAggregate(
    observedTotal: observed == 0 ? null : total,
    observedSampleCount: observed,
    notObservedSampleCount: notObserved,
    missingSampleCount: missing,
    invalidSampleCount: invalid,
  );
}

Object? _copyShadowValue(Object? value) => switch (value) {
  final List<String> values => List<String>.unmodifiable(values),
  final Map<String, String> values => Map<String, String>.unmodifiable(values),
  final Map<String, ShadowField<String>> values =>
    Map<String, ShadowField<String>>.unmodifiable(values),
  _ => value,
};

Object? _shadowJsonValue(Object? value) => switch (value) {
  final ShadowField<Object?> field => field.toJson(),
  final List<Object?> values => [
    for (final member in values) _shadowJsonValue(member),
  ],
  final Map<Object?, Object?> values => {
    for (final entry in values.entries)
      entry.key.toString(): _shadowJsonValue(entry.value),
  },
  _ => value,
};

class _Verdict {
  _Verdict({
    required this.sessionId,
    required this.lane,
    required this.grade,
    required this.round,
    required this.stepKey,
    required this.scope,
    required this.transport,
    required this.seq,
  });

  final String sessionId;
  final String lane;
  final String grade;
  final int round;
  final String stepKey;

  /// The sibling scope a step-derived gate is joined on ([stepScope]).
  final String scope;
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
  final stepFacts = _StepFacts();
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
            scope: stepScope(record.sessionId, record.stepPath),
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
      case StepTransition record:
        _adaptStepTransition(
          record,
          seq: envelope.seq ?? 0,
          beadBySession: beadBySession,
          into: stepFacts,
        );
      case _:
        break;
    }
  }
  final shadowSelection = _foldShadowSelection(stepFacts.shadowRows);

  // The dedicated verdicts are the state of record; the adapter's are folded in
  // beside them and COUNTED separately — a reader must be able to tell a wired
  // writer from the adapter.
  final verdictsFromRecord = verdicts.length;
  final verdictsFromStep = stepFacts.verdicts.length;
  verdicts.addAll(stepFacts.verdicts);

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
    if (gate != null) {
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
      continue;
    }
    if (!stepFacts.gatedScopes.contains(verdict.scope)) continue;
    // A step-derived gate: the ROUTE step's own ruling adjudicates it.
    // `escalate` means the committee was believed; `advance` past an adverse
    // verdict is an override; an operator ruling on the lane result is an
    // override however the route ruled.
    accum.gateCausing++;
    final route = stepFacts.routes[verdict.scope]?.kind;
    if (verdict.transport == VerdictTransport.operator ||
        route == RouteVerdictKind.advance) {
      accum.overridden++;
    } else if (route == RouteVerdictKind.escalate ||
        respec != RespecOutcome.noFollowUp) {
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
  final usageFromTelemetry = samples.length;

  // Tier 2 — the adapter. A telemetry row for the same (bead, lane) wins.
  var usageFromStep = 0;
  final stepCovered = <String>{};
  for (final sample in stepFacts.usage) {
    final key = _pairKey(sample);
    stepCovered.add(key);
    if (covered.contains(key)) continue;
    samples.add(sample);
    usageFromStep++;
  }

  // Tier 3 — the `.usage.json` fallback. The scan is NOT windowed (it reads
  // whatever is on disk), so the WINDOW scopes it here: a (bead, lane) pair the
  // window's records never mention gets no dollars, which is how a bead with
  // zero rounds in `--epoch` stops being charged another epoch's spend. The
  // scoping lives in the fold rather than the command because only the fold
  // decodes the window — doing it in the command would mean a second decode
  // pass over the same rows.
  final windowPairs = <String>{
    for (final verdict in verdicts)
      '${beadBySession[verdict.sessionId] ?? '-'}|${verdict.lane}',
    for (final envelope in rows)
      if (envelope.sessionId case final String session)
        if (envelope.stepPath case final String path)
          '${beadBySession[session] ?? '-'}|${laneOfStepPath(path)}',
  };
  var usageFromFallback = 0;
  for (final sample in fallback) {
    final key = _pairKey(sample);
    if (covered.contains(key) || stepCovered.contains(key)) continue;
    if (!windowPairs.contains(key)) continue;
    samples.add(sample);
    usageFromFallback++;
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
  for (final cause in stepFacts.gateCauses) {
    causeCounts[cause] = (causeCounts[cause] ?? 0) + 1;
  }

  return CommitteeReport(
    recordsRead: rows.length,
    truncated: truncated,
    sources: ReportSources(
      verdictsFromRecord: verdictsFromRecord,
      verdictsFromStep: verdictsFromStep,
      usageFromTelemetry: usageFromTelemetry,
      usageFromStep: usageFromStep,
      usageFromFallback: usageFromFallback,
      shadowSelectionsFromStep: shadowSelection.distinctSampleCount,
    ),
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
    shadowSelection: shadowSelection,
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
