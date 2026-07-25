import 'package:flutter/material.dart';

import '../models/view_state.dart';
import '../primitives/step_state_badge.dart';
import '../view_models/tree_view_models.dart';
import 'notifier_view.dart';

/// Displays the complete projected circuit forest.
final class CircuitPipelineView extends StatelessWidget {
  /// Creates a pipeline bound to [viewModel].
  const CircuitPipelineView({
    required this.viewModel,
    this.onSelectNode,
    super.key,
  });

  /// The pipeline projection observed by this view.
  final PipelineViewModel viewModel;

  /// Called with the selected step diagnostics node id.
  final ValueChanged<String>? onSelectNode;

  @override
  Widget build(BuildContext context) => NotifierView<PipelineState>(
    notifier: viewModel,
    builder: (context, state) => state.roots.isEmpty
        ? const Text('No circuit steps')
        : Column(
            children: [
              for (final root in state.roots)
                _PipelineNode(node: root, depth: 0, onSelectNode: onSelectNode),
            ],
          ),
  );
}

final class _PipelineNode extends StatelessWidget {
  const _PipelineNode({
    required this.node,
    required this.depth,
    this.onSelectNode,
  });

  final PipelineNodeView node;
  final int depth;
  final ValueChanged<String>? onSelectNode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: depth * 16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: ValueKey(node.nodeId),
          onTap: onSelectNode == null ? null : () => onSelectNode!(node.nodeId),
          title: Text(node.label),
          subtitle: Text(
            [
              'incarnation ${node.incarnationDepth}',
              if (node.duration case final duration?)
                '${duration.inMicroseconds} µs',
            ].join(' · '),
          ),
          trailing: StepStateBadge(state: node.state),
        ),
        for (final child in node.children)
          _PipelineNode(
            node: child,
            depth: depth + 1,
            onSelectNode: onSelectNode,
          ),
      ],
    ),
  );
}
