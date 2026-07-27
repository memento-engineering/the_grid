import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import '../events/events_panel.dart';
import '../protocol/grid_exploration_client.dart';
import '../replay/snapshot_json_loader.dart';

/// Station, projected-tree inspector, and exploration event observations.
final class ProjectionTabs extends StatefulWidget {
  /// Creates the three-tab surface over an injected diagnostics [source].
  const ProjectionTabs({
    required this.client,
    required this.source,
    this.snapshotJsonPicker = pickSnapshotJson,
    super.key,
  });

  /// Exploration client used only by the Events tab.
  final GridExplorationClient client;

  /// Transport-neutral source shared by the two projection tabs.
  final TreeSource source;

  /// File-selection boundary for replacing the replay recording.
  final SnapshotJsonPicker snapshotJsonPicker;

  @override
  State<ProjectionTabs> createState() => _ProjectionTabsState();
}

final class _ProjectionTabsState extends State<ProjectionTabs> {
  late TreeSource _activeSource = widget.source;
  ReplayTreeSource? _ownedSource;
  String? _loadError;

  @override
  void didUpdateWidget(covariant ProjectionTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source && _ownedSource == null) {
      _activeSource = widget.source;
    }
  }

  Future<void> _loadSnapshot() async {
    try {
      final contents = await widget.snapshotJsonPicker();
      if (!mounted || contents == null) return;
      final replacement = ReplayTreeSource(decodeSnapshotRecording(contents));
      final previous = _ownedSource;
      setState(() {
        _activeSource = replacement;
        _ownedSource = replacement;
        _loadError = null;
      });
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(previous.dispose());
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.toString());
    }
  }

  @override
  void dispose() {
    final ownedSource = _ownedSource;
    if (ownedSource != null) unawaited(ownedSource.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Station'),
                    Tab(text: 'Inspector'),
                    Tab(text: 'Events'),
                  ],
                ),
              ),
              IconButton(
                key: const Key('projection.loadSnapshot'),
                tooltip: 'Load TreeSnapshot JSON',
                onPressed: _loadSnapshot,
                icon: const Icon(Icons.file_open),
              ),
            ],
          ),
          if (_loadError case final message?)
            Text(message, key: const Key('projection.loadError')),
          Expanded(
            child: TabBarView(
              children: [
                _StationFlow(
                  key: ValueKey(_activeSource),
                  source: _activeSource,
                ),
                _InspectorFlow(
                  key: ValueKey(_activeSource),
                  source: _activeSource,
                ),
                EventsPanel(client: widget.client),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _StationPage { overview, work, bead }

final class _StationFlow extends StatefulWidget {
  const _StationFlow({required this.source, super.key});

  final TreeSource source;

  @override
  State<_StationFlow> createState() => _StationFlowState();
}

final class _StationFlowState extends State<_StationFlow> {
  late final OverviewViewModel _overview;
  late final WorkListViewModel _work;
  late final PipelineViewModel _pipeline;
  late final CostRollupViewModel _cost;
  _StationPage _page = _StationPage.overview;

  @override
  void initState() {
    super.initState();
    _overview = OverviewViewModel(widget.source);
    _work = WorkListViewModel(widget.source);
    _pipeline = PipelineViewModel(widget.source);
    _cost = CostRollupViewModel(widget.source);
  }

  @override
  void dispose() {
    _overview.dispose();
    _work.dispose();
    _pipeline.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_page) {
    _StationPage.overview => SingleChildScrollView(
      child: StationOverviewView(
        viewModel: _overview,
        onSelectSubstation: (_) => setState(() => _page = _StationPage.work),
      ),
    ),
    _StationPage.work => ListView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(
            onPressed: () => setState(() => _page = _StationPage.overview),
          ),
        ),
        WorkListView(
          viewModel: _work,
          onSelectWork: (_) => setState(() => _page = _StationPage.bead),
        ),
      ],
    ),
    _StationPage.bead => ListView(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: BackButton(
            onPressed: () => setState(() => _page = _StationPage.work),
          ),
        ),
        CircuitPipelineView(viewModel: _pipeline),
        CostTile(viewModel: _cost),
      ],
    ),
  };
}

final class _InspectorFlow extends StatefulWidget {
  const _InspectorFlow({required this.source, super.key});

  final TreeSource source;

  @override
  State<_InspectorFlow> createState() => _InspectorFlowState();
}

final class _InspectorFlowState extends State<_InspectorFlow> {
  late String _selectedNodeId;
  late InspectorViewModel _inspector;
  late final StreamSubscription<TreeSnapshot> _subscription;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = widget.source.latest!.root.id;
    // Register before the node-specific model so a missing selection can be
    // replaced before that model observes the same synchronous replay event.
    _subscription = widget.source.snapshots.listen(_onSnapshot);
    _inspector = InspectorViewModel(widget.source, nodeId: _selectedNodeId);
  }

  void _select(TreeNode node) {
    if (node.id == _selectedNodeId) return;
    final previous = _inspector;
    setState(() {
      _selectedNodeId = node.id;
      _inspector = InspectorViewModel(widget.source, nodeId: node.id);
    });
    previous.dispose();
  }

  void _onSnapshot(TreeSnapshot snapshot) {
    if (_findNode(snapshot.root, _selectedNodeId) != null) {
      setState(() {});
      return;
    }
    final previous = _inspector;
    setState(() {
      _selectedNodeId = snapshot.root.id;
      _inspector = InspectorViewModel(widget.source, nodeId: _selectedNodeId);
    });
    previous.dispose();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _inspector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.source.latest!.root;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: ListView(children: _nodeTiles(root, 0).toList())),
        const VerticalDivider(width: 1),
        Expanded(child: DiagnosticsInspectorView(viewModel: _inspector)),
      ],
    );
  }

  Iterable<Widget> _nodeTiles(TreeNode node, int depth) sync* {
    yield Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ListTile(
        key: Key('inspector.node.${node.id}'),
        selected: node.id == _selectedNodeId,
        title: Text(node.key ?? node.id),
        subtitle: Text(node.seedType),
        onTap: () => _select(node),
      ),
    );
    for (final child in node.children) {
      yield* _nodeTiles(child, depth + 1);
    }
  }
}

TreeNode? _findNode(TreeNode node, String id) {
  if (node.id == id) return node;
  for (final child in node.children) {
    final found = _findNode(child, id);
    if (found != null) return found;
  }
  return null;
}
