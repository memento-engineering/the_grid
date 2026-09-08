import 'package:flutter/material.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

/// One-screen composition of the landed cockpit projection views.
final class CockpitDashboard extends StatefulWidget {
  /// Creates a dashboard over [source] without taking source ownership.
  const CockpitDashboard({super.key, required this.source});

  /// Live diagnostics source owned by the connection controller.
  final TreeSource source;

  @override
  State<CockpitDashboard> createState() => _CockpitDashboardState();
}

final class _CockpitDashboardState extends State<CockpitDashboard> {
  late OverviewViewModel _overview;
  late WorkListViewModel _work;
  late PipelineViewModel _pipeline;
  late CostRollupViewModel _cost;

  @override
  void initState() {
    super.initState();
    _createViewModels();
  }

  @override
  void didUpdateWidget(covariant CockpitDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _disposeViewModels();
      _createViewModels();
    }
  }

  void _createViewModels() {
    _overview = OverviewViewModel(widget.source);
    _work = WorkListViewModel(widget.source);
    _pipeline = PipelineViewModel(widget.source);
    _cost = CostRollupViewModel(widget.source);
  }

  void _disposeViewModels() {
    _overview.dispose();
    _work.dispose();
    _pipeline.dispose();
    _cost.dispose();
  }

  @override
  void dispose() {
    _disposeViewModels();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StationOverviewView(viewModel: _overview),
        const SizedBox(height: 16),
        WorkListView(viewModel: _work),
        const SizedBox(height: 16),
        CircuitPipelineView(viewModel: _pipeline),
        const SizedBox(height: 16),
        CostTile(viewModel: _cost),
      ],
    ),
  );
}
