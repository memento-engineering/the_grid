import 'package:flutter/material.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

/// A typed target emitted when a diagnostics reference is activated.
@immutable
final class ReferenceTarget {
  /// Creates a reference target.
  const ReferenceTarget({required this.kind, required this.value});

  /// The kind of referenced entity.
  final ReferenceKind kind;

  /// The referenced entity identifier.
  final String value;
}

/// Compact activatable display for a diagnostics reference.
final class ReferenceChip extends StatelessWidget {
  /// Creates a reference chip.
  const ReferenceChip({
    required this.kind,
    required this.value,
    this.onOpen,
    super.key,
  });

  /// The kind of referenced entity.
  final ReferenceKind kind;

  /// The referenced entity identifier.
  final String value;

  /// Called with the exact typed target when the chip is activated.
  final ValueChanged<ReferenceTarget>? onOpen;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(value),
    tooltip: '${kind.name}: $value',
    visualDensity: VisualDensity.compact,
    onPressed: onOpen == null
        ? null
        : () => onOpen!(ReferenceTarget(kind: kind, value: value)),
  );
}
