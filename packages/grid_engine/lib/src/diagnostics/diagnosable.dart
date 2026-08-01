import 'package:genesis_foundation/genesis_foundation.dart';

/// Marks a genesis diagnostic object as part of the grid semantic projection.
mixin GridDiagnosticable {}

/// Adds grid's strongly typed property adapter to foundation's builder.
extension GridDiagnosticsBuilder on DiagnosticsBuilder {
  /// Converts and appends [property] in display order.
  void addTyped<T>(DiagnosticProperty<T> property) {
    add(property.toContract());
  }
}

/// A typed property contributed by a [Diagnosticable] object.
abstract class DiagnosticProperty<T> {
  /// Creates a typed property.
  const DiagnosticProperty(
    this.name,
    this.value, {
    this.level = DiagnosticsLevel.info,
  });

  /// Property label on the diagnostics wire.
  final String name;

  /// Strongly typed value before wire conversion.
  final T value;

  /// Display severity.
  final DiagnosticsLevel level;

  /// Converts this typed object to the versioned contract union.
  DiagnosticsProperty toContract();
}

/// A string-valued diagnostic property.
final class StringProperty extends DiagnosticProperty<String> {
  /// Creates a string property.
  const StringProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.string(name: name, level: level, value: value);
}

/// An integer-valued diagnostic property.
final class IntProperty extends DiagnosticProperty<int> {
  /// Creates an integer property.
  const IntProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.int(name: name, level: level, value: value);
}

/// A double-valued diagnostic property.
final class DoubleProperty extends DiagnosticProperty<double> {
  /// Creates a double property.
  const DoubleProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.double(name: name, level: level, value: value);
}

/// A boolean flag diagnostic property.
final class FlagProperty extends DiagnosticProperty<bool> {
  /// Creates a flag property.
  const FlagProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.flag(name: name, level: level, value: value);
}

/// An enum-valued diagnostic property.
final class EnumProperty<T extends Enum> extends DiagnosticProperty<T> {
  /// Creates an enum property.
  const EnumProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() => DiagnosticsProperty.enumValue(
    name: name,
    level: level,
    value: value.name,
    enumType: T.toString(),
  );
}

/// A duration-valued diagnostic property.
final class DurationProperty extends DiagnosticProperty<Duration> {
  /// Creates a duration property.
  const DurationProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.duration(name: name, level: level, value: value);
}

/// A timestamp-valued diagnostic property.
final class TimestampProperty extends DiagnosticProperty<DateTime> {
  /// Creates a timestamp property.
  const TimestampProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() =>
      DiagnosticsProperty.timestamp(name: name, level: level, value: value);
}

/// A reference-valued diagnostic property.
final class ReferenceProperty extends DiagnosticProperty<String> {
  /// Creates a reference property with its semantic [kind].
  const ReferenceProperty(
    super.name,
    super.value, {
    required this.kind,
    super.level,
  });

  /// The kind of referenced engine identity.
  final ReferenceKind kind;

  @override
  DiagnosticsProperty toContract() => DiagnosticsProperty.reference(
    name: name,
    level: level,
    referenceKind: kind,
    value: value,
  );
}

/// A nested object diagnostic property.
final class ObjectProperty
    extends DiagnosticProperty<List<DiagnosticProperty<Object?>>> {
  /// Creates an object property from ordered nested [value] properties.
  const ObjectProperty(super.name, super.value, {super.level});

  @override
  DiagnosticsProperty toContract() => DiagnosticsProperty.object(
    name: name,
    level: level,
    properties: [for (final property in value) property.toContract()],
  );
}
