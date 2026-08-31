/// Operator rendering for trajectory rows.
///
/// Every row goes through the §2.6 codec first, so an unregistered
/// `(record_type, type_version)` — or a row its decoder refuses — renders as
/// OPAQUE rather than as a plausible-looking typed line. Payload fields are
/// rendered as scalars, not as a JSON dump: the point of `traj show` is that
/// an operator reads a session's history down the page.
library;

import '../codec/codec_registry.dart';
import '../codec/envelope.dart';
import '../codec/trajectory_record.dart';

/// Longest payload/correlation value rendered before elision.
const int _maxValueChars = 72;

/// The lines for one row: a header, then the correlation and payload details
/// the row actually carries.
List<String> renderTrajectoryRow(TrajectoryEnvelope envelope) {
  final record = TrajectoryCodec.decode(envelope);
  final lines = <String>[_header(envelope)];
  final correlation = _correlation(envelope);
  if (correlation.isNotEmpty) lines.add('      $correlation');
  switch (record) {
    case OpaqueRecord(:final decodeFailure, :final rawPayload):
      lines.add(
        '      opaque ${envelope.recordType} v${envelope.typeVersion} — '
        '${decodeFailure == null ? 'no decoder registered' : 'decode failed: $decodeFailure'}',
      );
      final keys = rawPayload.keys.toList()..sort();
      if (keys.isNotEmpty) lines.add('      payload keys: ${keys.join(', ')}');
    case TrajectoryRecord():
      final payload = _fields(record.payloadToJson());
      if (payload.isNotEmpty) lines.add('      $payload');
  }
  return lines;
}

String _header(TrajectoryEnvelope envelope) {
  final seq = '${envelope.seq ?? '-'}'.padLeft(7);
  final at = _instant(envelope.occurredAt);
  final type = envelope.recordType.padRight(30);
  final outcome = envelope.outcome == null
      ? ''
      : '  ${envelope.outcome!.wire}'
            '${envelope.unknownReason == null ? '' : ' (${envelope.unknownReason})'}';
  final provenance = envelope.provenance == TrajectoryProvenance.observed
      ? ''
      : '  [${envelope.provenance.wire}: ${envelope.provenanceBasis}]';
  return '$seq  $at  $type$outcome$provenance';
}

/// The envelope's identity columns, in the order an operator scans them.
String _correlation(TrajectoryEnvelope envelope) {
  final step = envelope.stepPath == null
      ? null
      : '${envelope.stepPath}#${envelope.stepRound ?? '-'}'
            '${envelope.incarnation == null ? '' : '/i${envelope.incarnation}'}';
  return _fields({
    'bead': envelope.workBeadId,
    'session': envelope.sessionId,
    'round': envelope.round,
    'step': step,
    'attempt': envelope.attemptId,
    'mount_attempt': envelope.mountAttemptId,
    'grant': envelope.grantId,
    'effect': envelope.effectId,
    'gate': envelope.gateId,
    'branch': envelope.branch,
    'sha': envelope.commitSha,
    'worktree': envelope.worktree,
    'receipt': envelope.receipt,
    'expires': envelope.expiresAt == null
        ? null
        : _instant(envelope.expiresAt!),
    'fence': envelope.fencingToken,
    'resolves': envelope.resolvesRecordId,
  });
}

/// `key=value` pairs for the non-null entries of [values]; nested structures
/// are summarized, never expanded — this is a log line, not the row's JSON.
String _fields(Map<String, Object?> values) {
  final parts = <String>[];
  for (final entry in values.entries) {
    final value = entry.value;
    if (value == null) continue;
    parts.add('${entry.key}=${_scalar(value)}');
  }
  return parts.join('  ');
}

String _scalar(Object value) {
  if (value is Map) {
    return '{${value.length} field${value.length == 1 ? '' : 's'}}';
  }
  if (value is List) return '[${value.length}]';
  final text = value is DateTime ? _instant(value) : '$value';
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  return flat.length <= _maxValueChars
      ? flat
      : '${flat.substring(0, _maxValueChars)}…';
}

/// Second-precision UTC — the log stores microseconds, but a screen full of
/// them reads worse and the `seq` column is the ordering authority anyway.
String _instant(DateTime value) {
  final utc = value.toUtc();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)}T'
      '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}
