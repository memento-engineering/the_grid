// A throwing `ProcessCapability.result` routes to SUPERVISION, never an
// unhandled async error + a silently-stuck node (adversarial-review finding,
// 2026-07-02): the completion event is real, but if the result payload cannot
// be read the node must fail LOUD (supervised `Failed` → backoff/breaker), in
// line with the per-work fail-closed posture (ADR-0008 Decision 10 / OQ-c).

import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A one-turn capability whose completion payload read THROWS.
class _ThrowingResultCap extends ProcessCapability {
  const _ThrowingResultCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/w', command: 'x', args: []);

  @override
  StepSignal interpretEvent(RuntimeEvent event) => jobSignal(event);

  static StepSignal jobSignal(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    throw StateError('the result file is unreadable');
  }
}

void main() {
  test(
    'a throwing result() reports AllocationFailed (supervision), '
    'never completes and never leaks an unhandled error',
    () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final reports = <AllocationReport>[];
      final alloc = ProcessAllocation(
        const _ThrowingResultCap(),
        AllocationContext(
          treeContext: FakeTreeContext(),
          args: stepArgs('tg-1/agent'),
          transport: provider,
          address: const AllocationAddress('sess-1', 'tg-1/agent'),
          env: const {},
          sink: reports.add,
        ),
      );

      // The whole test body runs in a guarded zone: an unhandled async error
      // from the completion path would fail the test loudly (the OLD bug).
      await alloc.startOrAdopt();
      alloc.deliverEventForTest(const Exited(name: 'sess-1/tg-1/agent', exitCode: 0));
      // Drain the unawaited _reportComplete.
      await Future<void>.delayed(Duration.zero);

      expect(reports, hasLength(1));
      expect(
        reports.single,
        isA<AllocationFailed>().having(
          (f) => f.reason,
          'reason',
          contains('result threw'),
        ),
        reason: 'the real completion with an unreadable result must rout to '
            'supervision, not complete blind nor hang the node',
      );
      await alloc.dispose();
    },
  );

  test('a clean result() still completes (the guard is not over-broad)',
      () async {
    final provider = FakeRuntimeProvider();
    addTearDown(provider.close);
    final reports = <AllocationReport>[];
    final alloc = ProcessAllocation(
      const _OkResultCap(),
      AllocationContext(
        treeContext: FakeTreeContext(),
        args: stepArgs('tg-1/agent'),
        transport: provider,
        address: const AllocationAddress('sess-1', 'tg-1/agent'),
        env: const {},
        sink: reports.add,
      ),
    );
    await alloc.startOrAdopt();
    alloc.deliverEventForTest(const Exited(name: 'sess-1/tg-1/agent', exitCode: 0));
    await Future<void>.delayed(Duration.zero);
    expect(reports.single, isA<AllocationCompleted>());
    expect(
      (reports.single as AllocationCompleted).payload,
      {'grade': 'A'},
    );
    await alloc.dispose();
  });
}

class _OkResultCap extends ProcessCapability {
  const _OkResultCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/w', command: 'x', args: []);

  @override
  StepSignal interpretEvent(RuntimeEvent event) =>
      _ThrowingResultCap.jobSignal(event);

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async =>
      {'grade': 'A'};
}
