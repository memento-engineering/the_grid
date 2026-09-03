/// Rendering for `traj committee-report`: the operator table and the one
/// `--json` object.
///
/// Both are pure functions over a folded [CommitteeReport] — the verb decides
/// WHICH to print, this file decides how, and neither touches the log.
library;

import 'dart:convert';

import 'committee_report.dart';

/// The human table: gate causes, then one row per lane, then one per bead.
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
