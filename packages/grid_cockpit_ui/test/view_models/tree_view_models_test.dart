import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid_cockpit_ui/grid_cockpit_ui.dart';
import 'package:grid_diagnostics_contract/grid_diagnostics_contract.dart';

import '../fixtures.dart';

final class EmptyTreeSource implements TreeSource {
  final controller = StreamController<TreeSnapshot>.broadcast(sync: true);

  @override
  TreeSnapshot? get latest => null;

  @override
  Stream<TreeSnapshot> get snapshots => controller.stream;

  @override
  Future<void> dispose() => controller.close();
}

void main() {
  test('live notifiers use documented empty states before first snapshot', () {
    final source = EmptyTreeSource();
    final overview = OverviewViewModel(source);
    final work = WorkListViewModel(source);
    final pipeline = PipelineViewModel(source);
    final inspector = InspectorViewModel(source, nodeId: 'selected');
    final cost = CostRollupViewModel(source);

    expect(overview.state, emptyOverviewState);
    expect(work.state, const WorkListState(items: []));
    expect(pipeline.state, const PipelineState(roots: []));
    expect(inspector.state, isNull);
    expect(cost.state, const CostRollupState(hasData: false));

    overview.dispose();
    work.dispose();
    pipeline.dispose();
    inspector.dispose();
    cost.dispose();
  });

  test('all notifiers recompute from each replay snapshot', () async {
    TreeNode selected(String state) => node(
      id: 'selected',
      seedType: 'WorkBead',
      key: 'tg-1',
      properties: [
        stringProperty('stepState', state),
        intProperty('inputTokens', state == 'pending' ? 1 : 4),
      ],
    );
    final source = ReplayTreeSource([
      snapshot(version: 1, children: [selected('pending')]),
      snapshot(version: 2, children: [selected('complete')]),
    ]);
    final overview = OverviewViewModel(source);
    final work = WorkListViewModel(source);
    final pipeline = PipelineViewModel(source);
    final inspector = InspectorViewModel(source, nodeId: 'selected');
    final cost = CostRollupViewModel(source);

    expect(overview.state.activeWorkCount, 1);
    expect(work.state.items.single.state, StepVisualState.pending);
    expect(pipeline.state.roots.single.state, StepVisualState.pending);
    expect(inspector.state?.nodeId, 'selected');
    expect(cost.state.inputTokens, 1);

    expect(source.advance(), isTrue);
    expect(overview.state.projectedAt, DateTime.utc(2026, 1, 2));
    expect(overview.state.activeWorkCount, 0);
    expect(work.state.items.single.state, StepVisualState.complete);
    expect(pipeline.state.roots.single.state, StepVisualState.complete);
    expect(
      inspector.state?.properties
          .firstWhere((property) => property.name == 'stepState')
          .value,
      const PropertyValue.string('complete'),
    );
    expect(cost.state.inputTokens, 4);

    overview.dispose();
    work.dispose();
    pipeline.dispose();
    inspector.dispose();
    cost.dispose();
    await source.dispose();
  });

  test('inspector fails loudly when selected node disappears', () async {
    final source = ReplayTreeSource([
      snapshot(
        version: 1,
        children: [node(id: 'selected', seedType: 'Node')],
      ),
      snapshot(version: 2),
    ]);
    late InspectorViewModel inspector;
    Object? emittedError;
    runZonedGuarded(() {
      inspector = InspectorViewModel(source, nodeId: 'selected');
      source.advance();
    }, (error, _) => emittedError = error);
    expect(
      emittedError,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'Diagnostics node not found: selected',
      ),
    );
    inspector.dispose();
    await source.dispose();
  });

  test('disposing one notifier stops updates without closing source', () async {
    final source = ReplayTreeSource([
      snapshot(version: 1),
      snapshot(version: 2),
    ]);
    final overview = OverviewViewModel(source);
    final work = WorkListViewModel(source);
    final initial = overview.state;
    overview.dispose();

    expect(source.advance(), isTrue);
    expect(initial.projectedAt, DateTime.utc(2026, 1, 1));
    expect(work.state.items, isEmpty);
    expect(source.snapshots.isBroadcast, isTrue);

    work.dispose();
    await source.dispose();
  });
}
