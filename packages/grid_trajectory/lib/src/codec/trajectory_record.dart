/// The §2 record-type vocabulary as one sealed hierarchy (§2.6).
///
/// Every subclass owns three things: its typed payload (encoded by
/// [TrajectoryRecord.payloadToJson], decoded by its `fromJson`), the envelope
/// correlation columns its type requires (encoded by
/// [TrajectoryRecord.correlationToJson]), and its row in the §5 idem-key
/// grammar table ([TrajectoryRecord.idemKeyText]). Required-field invariants
/// live in the constructors (§2.6 rule 6); breaking payload changes mint
/// `type_version + 1` and KEEP the old decoder forever — the log is never
/// migrated.
library;

import 'package:meta/meta.dart';

import 'envelope.dart';
import 'idem_key.dart';

part 'records/attempt_records.dart';
part 'records/admission_records.dart';
part 'records/verification_records.dart';
part 'records/effect_records.dart';
part 'records/step_records.dart';

/// One trajectory record, pre-envelope: the typed fact plus the identity
/// grammar. The service stamps everything else (§2.6 rule 7).
@immutable
sealed class TrajectoryRecord {
  const TrajectoryRecord();

  String get recordType;

  /// Per-type payload schema version; bumped only on breaking change.
  int get typeVersion => 1;

  TrajectoryFamily get family;

  /// The type-specific `payload` JSON column.
  Map<String, Object?> payloadToJson();

  /// The envelope columns this type demands, DDL names, nulls omitted.
  Map<String, Object?> correlationToJson();

  /// The §5 canonical grammar string (`idem_key_text`). [context] supplies the
  /// service-stamped `<station>` / `<boot_epoch>` holes a few rows use.
  String idemKeyText(IdemContext context);

  /// SHA-256 hex of [idemKeyText] — the `idem_key` column.
  String idemKey(IdemContext context) => sha256Hex(idemKeyText(context));
}

// Family bases — one per §2 family, so subclasses carry their fold-dispatch
// family without per-class repetition.

sealed class AttemptRecord extends TrajectoryRecord {
  const AttemptRecord();

  @override
  TrajectoryFamily get family => TrajectoryFamily.attempt;
}

sealed class AdmissionRecord extends TrajectoryRecord {
  const AdmissionRecord();

  @override
  TrajectoryFamily get family => TrajectoryFamily.admission;
}

sealed class VerificationRecord extends TrajectoryRecord {
  const VerificationRecord();

  @override
  TrajectoryFamily get family => TrajectoryFamily.verification;
}

sealed class EffectRecord extends TrajectoryRecord {
  const EffectRecord();

  @override
  TrajectoryFamily get family => TrajectoryFamily.effect;
}

sealed class StepRecord extends TrajectoryRecord {
  const StepRecord();

  @override
  TrajectoryFamily get family => TrajectoryFamily.step;
}

/// The §2.6 rule-3 fallback: an unknown `(record_type, type_version)` — or a
/// row whose known decoder refuses it — decodes to this instead of throwing,
/// so replay never throws; the fold records the skip in `proj_meta.skipped`.
final class OpaqueRecord extends TrajectoryRecord {
  const OpaqueRecord({
    required this.recordType,
    required this.typeVersion,
    required this.family,
    required this.rawPayload,
    this.decodeFailure,
  });

  @override
  final String recordType;

  @override
  final int typeVersion;

  @override
  final TrajectoryFamily family;

  final Map<String, Object?> rawPayload;

  /// Null when the pair was simply unregistered; otherwise the decode error.
  final String? decodeFailure;

  @override
  Map<String, Object?> payloadToJson() => rawPayload;

  @override
  Map<String, Object?> correlationToJson() => const {};

  @override
  String idemKeyText(IdemContext context) => throw UnsupportedError(
    'OpaqueRecord is decode-only; it is never appended and has no grammar '
    'row',
  );
}

// ── shared decode helpers (part files only) ──────────────────────────────

T _req<T>(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! T) {
    throw FormatException(
      'payload.$key: expected $T, got ${value.runtimeType}',
    );
  }
  return value;
}

T? _opt<T extends Object>(Map<String, Object?> payload, String key) =>
    payload[key] == null ? null : _req<T>(payload, key);

DateTime _reqDate(Map<String, Object?> payload, String key) =>
    DateTime.parse(_req<String>(payload, key));

DateTime? _optDate(Map<String, Object?> payload, String key) {
  final raw = _opt<String>(payload, key);
  return raw == null ? null : DateTime.parse(raw);
}

Map<String, Object?> _reqMap(Map<String, Object?> payload, String key) =>
    _req<Map<Object?, Object?>>(payload, key).cast<String, Object?>();

Map<String, Object?>? _optMap(Map<String, Object?> payload, String key) =>
    _opt<Map<Object?, Object?>>(payload, key)?.cast<String, Object?>();

/// A correlation column the record type requires but the envelope lacks.
T _envReq<T>(TrajectoryEnvelope envelope, String column, T? value) {
  if (value == null) {
    throw FormatException(
      '${envelope.recordType}: envelope column $column is required',
    );
  }
  return value;
}

Never _refuse(String recordType, String message) =>
    throw ArgumentError('$recordType: $message');
