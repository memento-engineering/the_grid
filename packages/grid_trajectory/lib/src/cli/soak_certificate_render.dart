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
    'traj certify — the §W2.5 soak certificate over the last '
        '${certificate.requestedBoots} boot'
        '${certificate.requestedBoots == 1 ? '' : 's'}',
  ];
  if (certificate.insufficient) {
    lines.add(
      '  only ${certificate.claimedEpochs.length} boot epoch'
      '${certificate.claimedEpochs.length == 1 ? ' is' : 's are'} claimed on '
      'this grid home; ${certificate.requestedBoots} are required — nothing '
      'was measured.',
    );
    _renderChecklist(lines);
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
    lines
      ..add(
        '      governing seq ${governing.seq} '
        '(${governing.scope ?? 'no scope'}, session '
        '${governing.sessionId}) · passes ${governing.passes} · mode '
        '${governing.stringOf('mode') ?? 'absent'} · overlay '
        '${governing.boolOf('overlay_engaged') ?? 'absent'} · health '
        '${governing.stringOf('health') ?? 'absent'}',
      )
      ..add('      gating   ${_counters(boot, kCertificateGatingCounters)}')
      ..add('      reported ${_counters(boot, kCertificateReportedCounters)}')
      ..add(
        '      seats    '
        '${[for (final entry in boot.seatRounds.entries) '${entry.key} ${entry.value}'].join(' · ')}'
        '${boot.unattributedRounds == 0 ? '' : ' · unattributed ${boot.unattributedRounds}'}',
      );
  }
  _renderChecklist(lines);
  return lines;
}

/// The single `--json` object, pretty-printed with a trailing newline.
String renderSoakCertificateJson(SoakCertificate certificate) =>
    const JsonEncoder.withIndent('  ').convert(certificate.toJson());

void _renderChecklist(List<String> lines) {
  lines
    ..add('')
    ..add(
      '  human-only certificate items — state ${CertificateStatus.unknown.wire}, '
      'never claimed by this verb:',
    );
  for (final item in kCertificateHumanItems) {
    lines.add('    [?] $item');
  }
}

String _counters(BootEvidence boot, List<String> keys) {
  final counters = boot.counters;
  return [
    for (final key in keys) '$key ${counters[key] ?? 'absent'}',
  ].join(' · ');
}
