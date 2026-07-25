import 'package:flutter/material.dart';

import '../models/view_state.dart';

/// Compact semantic badge for a pipeline step state.
final class StepStateBadge extends StatelessWidget {
  /// Creates a badge for [state].
  const StepStateBadge({required this.state, super.key});

  /// The step state displayed by this badge.
  final StepVisualState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (state) {
      StepVisualState.pending => colors.secondary,
      StepVisualState.running => colors.primary,
      StepVisualState.ready => colors.tertiary,
      StepVisualState.complete => colors.primary,
      StepVisualState.failed => colors.error,
      StepVisualState.gated => colors.tertiary,
      StepVisualState.unknown => colors.outline,
    };
    return Semantics(
      label: 'Step state: ${state.name}',
      child: Chip(
        label: Text(state.name),
        labelStyle: TextStyle(color: color),
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
