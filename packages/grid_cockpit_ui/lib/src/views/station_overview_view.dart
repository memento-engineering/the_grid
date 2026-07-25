import 'package:flutter/material.dart';

import '../models/view_state.dart';
import '../view_models/tree_view_models.dart';
import 'notifier_view.dart';

/// Snapshot-driven station health summary.
final class StationOverviewView extends StatelessWidget {
  /// Creates an overview bound to [viewModel].
  const StationOverviewView({
    required this.viewModel,
    this.onSelectSubstation,
    super.key,
  });

  /// The snapshot projection observed by this view.
  final OverviewViewModel viewModel;

  /// Called with the selected substation diagnostics node id.
  final ValueChanged<String>? onSelectSubstation;

  @override
  Widget build(BuildContext context) => NotifierView<OverviewState>(
    notifier: viewModel,
    builder: (context, state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('Active ${state.activeWorkCount}')),
            Chip(label: Text('Warnings ${state.warningCount}')),
            Chip(label: Text('Errors ${state.errorCount}')),
          ],
        ),
        if (state.substations.isEmpty)
          const Text('No substations reporting')
        else
          for (final substation in state.substations)
            ListTile(
              key: ValueKey(substation.nodeId),
              onTap: onSelectSubstation == null
                  ? null
                  : () => onSelectSubstation!(substation.nodeId),
              title: Text(substation.substationId),
              subtitle: Text('${substation.mountedWorkCount} mounted work'),
            ),
      ],
    ),
  );
}
