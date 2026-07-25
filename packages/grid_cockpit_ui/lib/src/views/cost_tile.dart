import 'package:flutter/material.dart';

import '../models/view_state.dart';
import '../view_models/tree_view_models.dart';
import 'notifier_view.dart';

/// Displays aggregate tokens, cost, and committee grades.
final class CostTile extends StatelessWidget {
  /// Creates a cost tile bound to [viewModel].
  const CostTile({required this.viewModel, super.key});

  /// The cost projection observed by this tile.
  final CostRollupViewModel viewModel;

  @override
  Widget build(BuildContext context) => NotifierView<CostRollupState>(
    notifier: viewModel,
    builder: (context, state) => Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.hasData ? 'Cost' : 'Cost unavailable'),
            Text('Input tokens: ${state.inputTokens ?? '—'}'),
            Text('Output tokens: ${state.outputTokens ?? '—'}'),
            Text(
              'USD: ${state.costUsd == null ? '—' : state.costUsd!.toStringAsFixed(4)}',
            ),
            Wrap(
              spacing: 4,
              children: state.grades.isEmpty
                  ? const [Chip(label: Text('Grade —'))]
                  : [
                      for (final grade in state.grades)
                        Chip(label: Text('Grade $grade')),
                    ],
            ),
          ],
        ),
      ),
    ),
  );
}
