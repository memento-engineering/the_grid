import 'package:flutter/material.dart';

import '../models/view_state.dart';
import '../primitives/step_state_badge.dart';
import '../view_models/tree_view_models.dart';
import 'notifier_view.dart';

/// Displays the projected work inventory.
final class WorkListView extends StatelessWidget {
  /// Creates a work list bound to [viewModel].
  const WorkListView({required this.viewModel, this.onSelectWork, super.key});

  /// The work projection observed by this view.
  final WorkListViewModel viewModel;

  /// Called with a selected work item's diagnostics node id.
  final ValueChanged<String>? onSelectWork;

  @override
  Widget build(BuildContext context) => NotifierView<WorkListState>(
    notifier: viewModel,
    builder: (context, state) => state.items.isEmpty
        ? const Text('No work mounted')
        : Column(
            children: [
              for (final item in state.items)
                WorkBeadTile(
                  key: ValueKey(item.nodeId),
                  item: item,
                  onTap: onSelectWork == null
                      ? null
                      : () => onSelectWork!(item.nodeId),
                ),
            ],
          ),
  );
}

/// One work bead with session identity and disposition.
final class WorkBeadTile extends StatelessWidget {
  /// Creates a tile for [item].
  const WorkBeadTile({required this.item, this.onTap, super.key});

  /// Display-ready work data.
  final WorkItemView item;

  /// Called when this tile is activated.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(item.beadId),
    subtitle: item.sessionId == null ? null : Text(item.sessionId!),
    trailing: StepStateBadge(state: item.state),
  );
}
