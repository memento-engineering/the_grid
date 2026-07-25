import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';

import 'fixtures.dart';

void main() => runApp(const CockpitExampleApp());

/// Runnable fixture documentation for the v1 cockpit views.
final class CockpitExampleApp extends StatefulWidget {
  /// Creates the fixture example.
  const CockpitExampleApp({super.key});

  @override
  State<CockpitExampleApp> createState() => _CockpitExampleAppState();
}

final class _CockpitExampleAppState extends State<CockpitExampleApp> {
  late final ReplayTreeSource source;
  late final OverviewViewModel overview;
  late final WorkListViewModel work;
  late final PipelineViewModel pipeline;
  late final InspectorViewModel inspector;
  late final CostRollupViewModel cost;

  @override
  void initState() {
    super.initState();
    source = ReplayTreeSource(cockpitRecording);
    overview = OverviewViewModel(source);
    work = WorkListViewModel(source);
    pipeline = PipelineViewModel(source);
    inspector = InspectorViewModel(source, nodeId: 'pipeline-build');
    cost = CostRollupViewModel(source);
  }

  @override
  void dispose() {
    overview.dispose();
    work.dispose();
    pipeline.dispose();
    inspector.dispose();
    cost.dispose();
    unawaited(source.dispose());
    super.dispose();
  }

  void seek(int index) => setState(() => source.seek(index));

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Grid Cockpit UI',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(title: const Text('Grid Cockpit UI · fixture replay')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Snapshot ${source.index + 1} of ${cockpitRecording.length}'),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: source.index == 0
                      ? null
                      : () => seek(source.index - 1),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: source.canAdvance
                      ? () => seek(source.index + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: 420,
                  child: StationOverviewView(viewModel: overview),
                ),
                SizedBox(width: 420, child: WorkListView(viewModel: work)),
                SizedBox(
                  width: 560,
                  child: CircuitPipelineView(viewModel: pipeline),
                ),
                SizedBox(width: 360, child: CostTile(viewModel: cost)),
                SizedBox(
                  width: 420,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Projected-tree explorer'),
                      DiagnosticsInspectorView(viewModel: inspector),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
