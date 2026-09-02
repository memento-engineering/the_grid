/// The `.usage.json` FALLBACK — the only filesystem read the report does.
///
/// The state of record is the log: `verify.usage.telemetry` rows are the
/// primary source and this scan is consulted ONLY for a (bead, lane) pair
/// that produced none (ADR-0013 D5 — a file may be agent-IO transport, never
/// the state of record). The parse is deliberately re-expressed here rather
/// than shared with power_station's `UsageReport`: `grid_trajectory` is a LEAF
/// with zero grid_* dependencies (decision: grid-trajectory-leaf-package) and
/// power_station is a separate repository, so there is no seam to extend.
/// Only the two fields the report needs are read.
///
/// FAIL-SAFE, like the writer it reads: an absent root, an unreadable file, or
/// a malformed envelope contributes NO sample and never throws — telemetry can
/// never fail the report.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'committee_report.dart';

/// The suffix power_station writes its per-step harness envelope under.
const String kUsageReportSuffix = '.usage.json';

/// Scans [root] recursively for `<bead>_<…>_<lane>.usage.json` files and
/// returns one [UsageSample] each.
///
/// The filename is the sanitized node path (`tg-1/review/coherence` →
/// `tg-1_review_coherence.usage.json`), so the FIRST underscore-separated
/// segment is the bead and the LAST is the lane. A name with no separator
/// carries no lane and is skipped.
List<UsageSample> scanUsageFallback(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final samples = <UsageSample>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.endsWith(kUsageReportSuffix)) continue;
    final stem = name.substring(0, name.length - kUsageReportSuffix.length);
    final parts = stem.split('_');
    if (parts.length < 2) continue;
    final sample = parseUsageEnvelope(
      beadId: parts.first,
      lane: parts.last,
      content: _read(entity),
    );
    if (sample != null) samples.add(sample);
  }
  samples.sort(
    (a, b) => '${a.beadId}|${a.lane}'.compareTo('${b.beadId}|${b.lane}'),
  );
  return samples;
}

String? _read(File file) {
  try {
    return file.readAsStringSync();
  } on IOException {
    return null;
  }
}

/// Parses one harness result envelope: `total_cost_usd` and `duration_ms`.
/// Returns null when [content] is absent, not a JSON object, or carries
/// neither field.
UsageSample? parseUsageEnvelope({
  required String beadId,
  required String lane,
  required String? content,
}) {
  if (content == null || content.trim().isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final cost = decoded['total_cost_usd'];
  final duration = decoded['duration_ms'];
  final costUsd = cost is num ? cost.toDouble() : null;
  final durationMs = duration is num ? duration.toInt() : null;
  if (costUsd == null && durationMs == null) return null;
  return UsageSample(
    lane: lane,
    beadId: beadId,
    fromFallback: true,
    costUsd: costUsd,
    durationMs: durationMs,
  );
}
