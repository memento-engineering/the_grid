import 'package:flutter/material.dart';

import '../models/view_state.dart';
import 'reference_chip.dart';
import 'severity_colors.dart';

/// Displays one property and recursively displays object-valued children.
final class PropertyRow extends StatelessWidget {
  /// Creates a property row.
  const PropertyRow({required this.property, this.onOpenReference, super.key});

  /// The display-ready property.
  final PropertyRowModel property;

  /// Called when a nested or direct reference is activated.
  final ValueChanged<ReferenceTarget>? onOpenReference;

  @override
  Widget build(BuildContext context) {
    final markerColor = severityColor(
      Theme.of(context).colorScheme,
      property.severity,
    );
    return Semantics(
      label: 'Severity: ${property.severity.name}',
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Icon(Icons.circle, size: 8, color: markerColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.name),
                _PropertyValue(
                  value: property.value,
                  onOpenReference: onOpenReference,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _PropertyValue extends StatelessWidget {
  const _PropertyValue({required this.value, this.onOpenReference});

  final PropertyValue value;
  final ValueChanged<ReferenceTarget>? onOpenReference;

  @override
  Widget build(BuildContext context) => switch (value) {
    StringPropertyValue(:final value) => Text(value),
    IntPropertyValue(:final value) => Text(value.toString()),
    DoublePropertyValue(:final value) => Text(value.toString()),
    FlagPropertyValue(:final value) => Text(value ? 'true' : 'false'),
    EnumPropertyValue(:final value) => Text(value),
    DurationPropertyValue(:final value) => Text(
      '${value.inMicroseconds} \u00b5s',
    ),
    TimestampPropertyValue(:final value) => Text(
      value.toUtc().toIso8601String(),
    ),
    ReferencePropertyValue(:final kind, :final value) => ReferenceChip(
      kind: kind,
      value: value,
      onOpen: onOpenReference,
    ),
    ObjectPropertyValue(:final properties) => Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        children: [
          for (final child in properties)
            PropertyRow(property: child, onOpenReference: onOpenReference),
        ],
      ),
    ),
  };
}
