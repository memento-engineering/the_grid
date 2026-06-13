/// The result of reading one typed `convergence.*` field from a metadata map.
///
/// Decode is **total**: a field read can never throw. Three readings:
///
/// * [FieldValue] — the key was present and parsed.
/// * [FieldAbsent] — the key is missing, or present as the empty string where
///   gc treats `""` as "unset" (Go map access yields `""` for absent keys, so
///   gc itself cannot tell the two apart — e.g. `DecodeInt("") == (0, false)`,
///   metadata.go:147-149).
/// * [FieldMalformed] — the key is present with a value gc could not have
///   written (garbage int, bad duration, out-of-set enum value, non-String
///   JSON value). gc either errors on these (`ParseGateConfig`) or silently
///   collapses them (`DecodeInt` → false); the_grid surfaces them as typed
///   failures so shadow mode never crashes *and* never silently coerces.
///   Where Track B needs gc's collapsing read, `ConvergenceMetadata` exposes
///   explicit `...OrZero`/`...OrNull` helpers that document the collapse.
sealed class FieldReading<T> {
  const FieldReading();

  /// The parsed value when this is a [FieldValue], else null.
  T? get valueOrNull => switch (this) {
    FieldValue<T>(:final value) => value,
    FieldAbsent<T>() || FieldMalformed<T>() => null,
  };

  bool get isAbsent => this is FieldAbsent<T>;
  bool get isMalformed => this is FieldMalformed<T>;
}

/// A present, well-formed field value.
final class FieldValue<T> extends FieldReading<T> {
  const FieldValue(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is FieldValue<T> && other.value == value;

  @override
  int get hashCode => Object.hash(FieldValue<T>, value);

  @override
  String toString() => 'FieldValue<$T>($value)';
}

/// The key is missing (or empty where gc reads empty as unset — see class doc).
final class FieldAbsent<T> extends FieldReading<T> {
  const FieldAbsent();

  @override
  bool operator ==(Object other) => other is FieldAbsent<T>;

  @override
  int get hashCode => (FieldAbsent<T>).hashCode;

  @override
  String toString() => 'FieldAbsent<$T>()';
}

/// The key is present with a value that does not decode — a typed failure,
/// never an exception.
final class FieldMalformed<T> extends FieldReading<T> {
  const FieldMalformed(this.key, this.rawValue, this.reason);

  /// The metadata key that failed to decode.
  final String key;

  /// The offending raw value, preserved verbatim.
  final Object? rawValue;

  /// Human-readable description of the failure.
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is FieldMalformed<T> &&
      other.key == key &&
      other.rawValue == rawValue &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(FieldMalformed<T>, key, rawValue, reason);

  @override
  String toString() => 'FieldMalformed<$T>($key: $rawValue — $reason)';
}
