/// Rendering for `traj committee-report`: the operator table and the one
/// `--json` object.
///
/// Both are pure functions over a folded [CommitteeReport] — the verb decides
/// WHICH to print, this file decides how, and neither touches the log.
library;

import 'dart:convert';

import 'committee_report.dart';

/// The human table, followed by per-rule shadow evidence when it was observed.
List<String> renderCommitteeReport(CommitteeReport report) {
  final lines = <String>[
    'traj committee-report — ${report.recordsRead} record'
        '${report.recordsRead == 1 ? '' : 's'}'
        '${report.truncated ? ' (TRUNCATED — totals are a prefix, not a total)' : ''}',
  ];
  final sources = report.sources;
  lines.add(
    '  sources: verdicts ${sources.verdictsFromRecord} record / '
    '${sources.verdictsFromStep} step.transition · usage '
    '${sources.usageFromTelemetry} telemetry / ${sources.usageFromStep} '
    'step.transition / ${sources.usageFromFallback} fallback',
  );
  if (sources.shadowSelectionsFromStep > 0) {
    lines.add(
      '  shadow selections: ${sources.shadowSelectionsFromStep} '
      'step.transition',
    );
  }
  if (report.gateCauses.isEmpty) {
    lines.add('  gates: none opened in this window');
  } else {
    lines.add('  gates by cause:');
    for (final entry in report.gateCauses.entries) {
      lines.add('    ${entry.key.wire.padRight(16)} ${entry.value}');
    }
  }
  lines.add('');
  lines.add(
    '  ${'lane'.padRight(22)}${'grades'.padRight(24)}'
    '${'gated'.padRight(7)}${'ovr'.padRight(5)}${'uph'.padRight(5)}'
    '${'unres'.padRight(7)}${'respec'.padRight(12)}'
    '${r'$/run'.padRight(9)}s/run',
  );
  for (final lane in report.lanes) {
    final respec =
        '${lane.respecConverged}/${lane.respecUnconverged}/'
        '${lane.respecNoFollowUp}';
    lines.add(
      '  ${lane.lane.padRight(22)}'
      '${_grades(lane.gradeCounts).padRight(24)}'
      '${'${lane.gateCausing}/${lane.adverseVerdicts}'.padRight(7)}'
      '${'${lane.overridden}'.padRight(5)}'
      '${'${lane.upheld}'.padRight(5)}'
      '${'${lane.unresolved}'.padRight(7)}'
      '${respec.padRight(12)}'
      '${_money(lane.meanCostUsd).padRight(9)}'
      '${_seconds(lane.meanDurationMs)}',
    );
  }
  lines.add('');
  lines.add('  ${'bead'.padRight(22)}${'rounds'.padRight(9)}total \$');
  for (final bead in report.beads) {
    lines.add(
      '  ${bead.beadId.padRight(22)}'
      '${'${bead.rounds}'.padRight(9)}'
      '${_money(bead.costUsd)}',
    );
  }
  if (sources.shadowSelectionsFromStep > 0) {
    _renderShadowSelection(lines, report);
  }
  return lines;
}

/// The single `--json` object, pretty-printed with a trailing newline.
String renderCommitteeReportJson(CommitteeReport report) =>
    const JsonEncoder.withIndent('  ').convert(report.toJson());

String _grades(Map<String, int> counts) => counts.isEmpty
    ? '-'
    : [
        for (final entry in counts.entries) '${entry.key}:${entry.value}',
      ].join(' ');

String _money(double? value) =>
    value == null ? '-' : '\$${value.toStringAsFixed(2)}';

String _seconds(int? milliseconds) =>
    milliseconds == null ? '-' : (milliseconds / 1000).toStringAsFixed(1);

void _renderShadowSelection(List<String> lines, CommitteeReport report) {
  final shadow = report.shadowSelection;
  lines.add('');
  lines.add(
    'shadow committee selection — ${shadow.distinctSampleCount} distinct '
    'samples (${report.sources.shadowSelectionsFromStep} observations; '
    '${shadow.unidentifiedSampleCount} unidentified)',
  );
  for (final group in shadow.groups) {
    lines.add(
      'policy ${group.policyVersion} · stage ${group.stage} · rule '
      '${group.ruleId} — ${group.sampleCount} samples '
      '[${group.sampleIds.join(', ')}]${group.truncated ? ' · TRUNCATED' : ''}',
    );
    lines.add('  scope coverage: ${_histogram(group.scopeCoverage)}');
    lines.add(
      '  change-shape coverage: ${_histogram(group.changeShapeCoverage)}',
    );
    lines.add('  actual: ${_usageAggregate(group.actual)}');
    lines.add('  counterfactual: ${_usageAggregate(group.counterfactual)}');
    for (final sample in group.samples) {
      lines.add('  sample ${sample.identity}');
      lines.add(
        '    join: ${_joinState(sample.joinState)} · sampleId '
        '${_field(sample.sampleId, _text)} · joinId '
        '${_field(sample.joinId, _text)} · conflicts '
        '${sample.conflictingKeys.isEmpty ? '(empty)' : sample.conflictingKeys.join(',')}',
      );
      lines.add(
        '    lanes: selected ${_field(sample.selected, _list)} · omitted '
        '${_field(sample.omitted, _list)}',
      );
      lines.add(
        '    omitted grades: ${_field(sample.omittedLaneGrades, _omittedMap)}',
      );
      lines.add(
        '    omitted transports: '
        '${_field(sample.omittedLaneTransports, _omittedMap)}',
      );
      lines.add(
        '    omitted dispositions: '
        '${_field(sample.omittedLaneDispositions, _omittedMap)}',
      );
      lines.add(
        '    selection: source ${_field(sample.source, _text)} · rules '
        '${_field(sample.matchedRules, _list)} · classifierAttempts '
        '${_field(sample.classifierAttempts, _number)} · classifierKinds '
        '${_field(sample.classifierAttemptKinds, _list)}',
      );
      lines.add(
        '    evidence: digest ${_field(sample.evidenceDigest, _text)} · '
        'missing ${_field(sample.missingEvidenceIds, _list)} · lane inputs '
        '${_field(sample.laneInputDigests, _stringMap)}',
      );
      lines.add(
        '    route: bead ${_field(sample.workBeadId, _text)} · round '
        '${_field(sample.round, _number)} · selector path '
        '${_field(sample.selectorNodePath, _text)} · route path '
        '${_field(sample.routeNodePath, _text)}',
      );
      lines.add(
        '    route outcome: action lanes '
        '${_field(sample.actionLaneIds, _list)} · gate '
        '${_field(sample.gateDisposition, _text)} · downstream '
        '${_field(sample.downstreamJoinKeys, _stringMap)}',
      );
      lines.add('    actual usage: ${_usageObservation(sample.actual)}');
      lines.add(
        '    counterfactual usage: '
        '${_usageObservation(sample.counterfactual)}',
      );
      lines.add(
        '    truncated: ${_field(sample.truncated, _boolean)} · '
        'missingFields: ${_field(sample.missingFields, _list)}',
      );
    }
  }
}

String _histogram(Map<String, int> values) => values.isEmpty
    ? '(empty)'
    : values.entries.map((entry) => '${entry.key}=${entry.value}').join(', ');

String _usageAggregate(ShadowUsageAggregate usage) =>
    'tokens in ${_metric(usage.tokensIn)} · '
    'tokens out ${_metric(usage.tokensOut)} · '
    'cost USD ${_metric(usage.costUsd)}';

String _metric(ShadowMetricAggregate metric) =>
    '${metric.observedTotal ?? 'not available'} '
    '[observed=${metric.observedSampleCount}, '
    'not observed=${metric.notObservedSampleCount}, '
    'missing=${metric.missingSampleCount}, invalid=${metric.invalidSampleCount}]';

String _usageObservation(ShadowUsageObservation usage) =>
    'contributors ${_field(usage.contributingRunIds, _list)} · '
    'missing lanes ${_field(usage.missingLaneIds, _list)} · '
    'tokens in ${_field(usage.tokensIn, _number)} · '
    'tokens out ${_field(usage.tokensOut, _number)} · '
    'cost USD ${_field(usage.costUsd, _number)}';

String _field<T>(ShadowField<T> field, String Function(T value) observed) =>
    switch (field.state) {
      ShadowFieldState.missing => 'missing',
      ShadowFieldState.notObserved => 'not observed',
      ShadowFieldState.invalid => 'invalid',
      ShadowFieldState.observed => observed(field.value as T),
    };

String _text(String value) => value.isEmpty ? '(empty)' : value;

String _list(List<String> values) =>
    values.isEmpty ? '(empty)' : values.join(',');

String _number(num value) => value.toString();

String _boolean(bool value) => value.toString();

String _joinState(ShadowJoinState state) => switch (state) {
  ShadowJoinState.joined => 'joined',
  ShadowJoinState.selectorOnly => 'selector-only',
  ShadowJoinState.routeOnly => 'route-only',
  ShadowJoinState.conflict => 'conflict',
};

String _stringMap(Map<String, String> values) => values.isEmpty
    ? '(empty)'
    : values.entries.map((entry) => '${entry.key}=${entry.value}').join(',');

String _omittedMap(Map<String, ShadowField<String>> values) => values.isEmpty
    ? '(empty)'
    : values.entries
          .map((entry) => '${entry.key}=${_field(entry.value, _text)}')
          .join(',');
