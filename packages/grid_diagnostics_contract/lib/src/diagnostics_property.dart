import 'package:freezed_annotation/freezed_annotation.dart';

part 'diagnostics_property.freezed.dart';
part 'diagnostics_property.g.dart';

/// Display severity attached to every diagnostics property.
enum DiagnosticsLevel {
  /// Fine-grained debugging detail.
  fine,

  /// Normal operator information.
  info,

  /// A condition requiring attention.
  warning,

  /// A failed or invalid condition.
  error,
}

/// Link target classifier for a [DiagnosticsProperty.reference].
enum ReferenceKind {
  /// A work bead identifier.
  bead,

  /// A session identifier.
  session,

  /// A substation identifier.
  substation,

  /// An operating-system process identifier.
  pid,
}

/// One typed, severity-bearing property on a diagnostics tree node.
@Freezed(unionKey: 'kind')
sealed class DiagnosticsProperty with _$DiagnosticsProperty {
  /// A string-valued property.
  const factory DiagnosticsProperty.string({
    required String name,
    required DiagnosticsLevel level,
    required String value,
  }) = DiagnosticsStringProperty;

  /// An integer-valued property.
  const factory DiagnosticsProperty.int({
    required String name,
    required DiagnosticsLevel level,
    required int value,
  }) = DiagnosticsIntProperty;

  /// A double-valued property.
  const factory DiagnosticsProperty.double({
    required String name,
    required DiagnosticsLevel level,
    required double value,
  }) = DiagnosticsDoubleProperty;

  /// A boolean flag property.
  const factory DiagnosticsProperty.flag({
    required String name,
    required DiagnosticsLevel level,
    required bool value,
  }) = DiagnosticsFlagProperty;

  /// An enum value plus its source enum's type name.
  const factory DiagnosticsProperty.enumValue({
    required String name,
    required DiagnosticsLevel level,
    required String value,
    required String enumType,
  }) = DiagnosticsEnumProperty;

  /// A duration encoded by json_serializable as microseconds.
  const factory DiagnosticsProperty.duration({
    required String name,
    required DiagnosticsLevel level,
    required Duration value,
  }) = DiagnosticsDurationProperty;

  /// A timestamp encoded by json_serializable as ISO-8601 text.
  const factory DiagnosticsProperty.timestamp({
    required String name,
    required DiagnosticsLevel level,
    required DateTime value,
  }) = DiagnosticsTimestampProperty;

  /// A typed, navigable reference rather than printable text.
  const factory DiagnosticsProperty.reference({
    required String name,
    required DiagnosticsLevel level,
    required ReferenceKind referenceKind,
    required String value,
  }) = DiagnosticsReferenceProperty;

  /// A nested group of typed diagnostics properties.
  const factory DiagnosticsProperty.object({
    required String name,
    required DiagnosticsLevel level,
    required List<DiagnosticsProperty> properties,
  }) = DiagnosticsObjectProperty;

  /// Decodes a property, failing loudly when [json] has an unknown `kind`.
  factory DiagnosticsProperty.fromJson(Map<String, Object?> json) =>
      _$DiagnosticsPropertyFromJson(json);
}
