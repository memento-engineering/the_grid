import 'package:flutter/material.dart';

import '../models/view_state.dart';
import '../primitives/property_row.dart';
import '../primitives/reference_chip.dart';
import '../view_models/tree_view_models.dart';
import 'notifier_view.dart';

/// Generic typed-property inspector for one diagnostics node.
final class DiagnosticsInspectorView extends StatelessWidget {
  /// Creates an inspector bound to [viewModel].
  const DiagnosticsInspectorView({
    required this.viewModel,
    this.onOpenReference,
    super.key,
  });

  /// The selected-node projection observed by this view.
  final InspectorViewModel viewModel;

  /// Receives typed bead, session, pid, or other contract references unchanged.
  final ValueChanged<ReferenceTarget>? onOpenReference;

  @override
  Widget build(BuildContext context) => NotifierView<InspectorState?>(
    notifier: viewModel,
    builder: (context, state) {
      if (state == null) return const Text('No diagnostics selected');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(state.seedType, style: Theme.of(context).textTheme.titleMedium),
          Text(
            state.key == null ? state.nodeId : '${state.key} · ${state.nodeId}',
          ),
          for (final property in state.properties)
            PropertyRow(property: property, onOpenReference: onOpenReference),
        ],
      );
    },
  );
}
