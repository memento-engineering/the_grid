import 'package:grid_cockpit_contract/grid_cockpit_contract.dart' as contract;

/// Collects typed diagnostic properties in insertion order.
final class DiagnosticsBuilder {
  final List<contract.DiagnosticsProperty> _properties = [];

  /// Adds [property] to this node.
  void add<T>(DiagnosticProperty<T> property) {
    _properties.add(property.toContract());
  }

  /// Returns an immutable snapshot of the collected wire properties.
  List<contract.DiagnosticsProperty> build() => List.unmodifiable(_properties);
}

/// A typed property contributed by a [Diagnosable] object.
abstract class DiagnosticProperty<T> {
  /// Creates a typed property.
  const DiagnosticProperty(
    this.name,
    this.value, {
    this.level = contract.DiagnosticsLevel.info,
  });

  /// Property label on the diagnostics wire.
  final String name;

  /// Strongly typed value before wire conversion.
  final T value;

  /// Display severity.
  final contract.DiagnosticsLevel level;

  /// Converts this typed object to the versioned contract union.
  contract.DiagnosticsProperty toContract();
}

/// A string-valued diagnostic property.
final class StringProperty extends DiagnosticProperty<String> {
  /// Creates a string property.
  const StringProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.string(
        name: name,
        level: level,
        value: value,
      );
}

/// An integer-valued diagnostic property.
final class IntProperty extends DiagnosticProperty<int> {
  /// Creates an integer property.
  const IntProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.int(name: name, level: level, value: value);
}

/// A double-valued diagnostic property.
final class DoubleProperty extends DiagnosticProperty<double> {
  /// Creates a double property.
  const DoubleProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.double(
        name: name,
        level: level,
        value: value,
      );
}

/// A boolean flag diagnostic property.
final class FlagProperty extends DiagnosticProperty<bool> {
  /// Creates a flag property.
  const FlagProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.flag(name: name, level: level, value: value);
}

/// An enum-valued diagnostic property.
final class EnumProperty<T extends Enum> extends DiagnosticProperty<T> {
  /// Creates an enum property.
  const EnumProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.enumValue(
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
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.duration(
        name: name,
        level: level,
        value: value,
      );
}

/// A timestamp-valued diagnostic property.
final class TimestampProperty extends DiagnosticProperty<DateTime> {
  /// Creates a timestamp property.
  const TimestampProperty(super.name, super.value, {super.level});

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.timestamp(
        name: name,
        level: level,
        value: value,
      );
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
  final contract.ReferenceKind kind;

  @override
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.reference(
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
  contract.DiagnosticsProperty toContract() =>
      contract.DiagnosticsProperty.object(
        name: name,
        level: level,
        properties: [for (final property in value) property.toContract()],
      );
}

/// Internal engine objects opt into ordered, super-chainable introspection.
mixin Diagnosable {
  /// Adds this inheritance level's properties to [builder].
  void debugFillProperties(DiagnosticsBuilder builder) {}
}
