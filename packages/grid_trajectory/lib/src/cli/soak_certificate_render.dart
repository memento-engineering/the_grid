/// Rendering for `traj certify`: the operator table and the one `--json`
/// object.
///
/// Both are pure functions over a folded [SoakCertificate] — the verb decides
/// WHICH to print, this file decides how, and neither touches the log.
library;

import 'dart:convert';

import 'soak_certificate.dart';

/// The operator table: the five rows, their failures, the per-boot numbers,
/// and the checklist the verb never claims.
List<String> renderSoakCertificate(SoakCertificate certificate) {
  final lines = <String>[
    'traj certify — the machine-checkable §W2.5 certificate rows over the '
        'last ${certificate.requestedBoots} boot'
        '${certificate.requestedBoots == 1 ? '' : 's'} '
        '(the table\'s human and event rows are the checklist below, never '
        'claimed here)',
  ];
  if (certificate.insufficient) {
    lines.add(
      '  only ${certificate.claimedEpochs.length} boot epoch'
      '${certificate.claimedEpochs.length == 1 ? ' is' : 's are'} claimed on '
      'this grid home; ${certificate.requestedBoots} are required — nothing '
      'was measured.',
    );
    lines.addAll(renderCertificateChecklist());
    return lines;
  }
  final stations = {for (final boot in certificate.boots) boot.station};
  lines
    ..add(
      '  counted boots: epoch '
      '${[for (final boot in certificate.boots) boot.epoch].join(', ')} of '
      '${certificate.claimedEpochs.length} claimed (station '
      '${stations.join(', ')})',
    )
    ..add('  seats: ${certificate.seats.join(', ')}')
    ..add('');
  for (final item in certificate.items) {
    lines.add(
      '  ${item.row.wire.padRight(16)}${item.status.wire.padRight(8)}'
      '${item.detail}',
    );
    for (final failure in item.failures) {
      lines.add('      × $failure');
    }
  }
  lines
    ..add('')
    ..add('  per boot:');
  for (final boot in certificate.boots) {
    final governing = boot.governing;
    lines.add(
      '    epoch ${boot.epoch} · ${boot.recordsRead} record'
      '${boot.recordsRead == 1 ? '' : 's'}'
      '${boot.truncated ? ' (TRUNCATED)' : ''} · ${boot.summaries} round '
      'summar${boot.summaries == 1 ? 'y' : 'ies'}',
    );
    if (governing == null) {
      lines.add('      no governing note (none with passes > 1)');
      continue;
    }
    final transitions = governing.listOf(kHealthTransitionsKey);
    lines
      ..add(
        '      governing seq ${governing.seq} '
        '(${governing.scope ?? 'no scope'}, session '
        '${governing.sessionId}) · passes ${governing.passes} · mode '
        '${governing.stringOf('mode') ?? 'absent'} · overlay '
        '${governing.boolOf('overlay_engaged') ?? 'absent'} · health '
        '${governing.stringOf('health') ?? 'absent'}',
      )
      ..add(
        '      anchor   $kEpochAnchorKey '
        '${governing.stringOf(kEpochAnchorKey) ?? 'NULL'} · '
        '$kHealthTransitionsKey '
        '${transitions == null
            ? 'absent'
            : transitions.isEmpty
            ? 'none'
            : transitions.join(' → ')}',
      )
      ..add('      gating   ${_counters(boot, kCertificateGatingCounters)}')
      ..add('      reported ${_counters(boot, kCertificateReportedCounters)}')
      ..add(
        '      seats    '
        '${[for (final entry in boot.seatRounds.entries) '${entry.key} ${entry.value}'].join(' · ')}'
        '${boot.offSeatRounds == 0 ? '' : ' · other substations ${boot.offSeatRounds}'}'
        '${boot.unjoinedRounds == 0 ? '' : ' · unjoined ${boot.unjoinedRounds}'}',
      );
  }
  lines.addAll(renderCertificateChecklist());
  return lines;
}

/// The single `--json` object, pretty-printed with a trailing newline.
String renderSoakCertificateJson(SoakCertificate certificate) =>
    const JsonEncoder.withIndent('  ').convert(certificate.toJson());

/// The UNKNOWN checklist, on its own — printed under EVERY disposition the
/// verb has, measured or not. A run that could measure nothing is exactly the
/// run whose reader most needs telling which items no verb will ever claim.
List<String> renderCertificateChecklist() => <String>[
  '',
  '  human-only certificate items — state ${CertificateStatus.unknown.wire}, '
      'never claimed by this verb:',
  for (final item in kCertificateHumanItems) '    [?] $item',
];

String _counters(BootEvidence boot, List<String> keys) {
  final counters = boot.counters;
  return [
    for (final key in keys) '$key ${counters[key] ?? 'absent'}',
  ].join(' · ');
}
