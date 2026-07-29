import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

void rejectDetached(String message) {
  unawaited(
    Future<void>.delayed(Duration.zero, () => throw StateError(message)),
  );
}

Future<void> drainTurns() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<List<Object>> parentErrorsFor(Future<void> Function() body) async {
  final parentErrors = <Object>[];
  await runZonedGuarded(() async {
    await body();
    await drainTurns();
  }, (error, stackTrace) => parentErrors.add(error));
  return parentErrors;
}

AllocationContext contextFor(
  FakeRuntimeProvider provider,
  List<AllocationReport> reports, {
  StepKind kind = StepKind.job,
  AdoptFence fence = const AdoptFence(),
  bool Function(AdoptFence) liveness = neverLive,
}) => AllocationContext(
  treeContext: FakeTreeContext(),
  args: stepArgs('tg-1/work'),
  transport: provider,
  address: const AllocationAddress('sess-1', 'tg-1/work'),
  env: const {},
  sink: reports.add,
  kind: kind,
  fence: fence,
  liveness: liveness,
);

void expectFailure(
  List<AllocationReport> reports,
  String prefix,
  String message,
) {
  expect(reports, hasLength(1));
  expect(
    reports.single,
    isA<AllocationFailed>().having(
      (report) => report.reason,
      'reason',
      allOf(contains(prefix), contains(message)),
    ),
  );
  expect(reports.whereType<AllocationCompleted>(), isEmpty);
}

class _ServiceCap extends ServiceCapability {
  const _ServiceCap({this.runError, this.teardownError});

  final String? runError;
  final String? teardownError;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    if (runError case final error?) rejectDetached(error);
    return const Ok({'grade': 'A'});
  }

  @override
  Future<void> teardown(StepArgs args) async {
    if (teardownError case final error?) rejectDetached(error);
  }
}

enum _ProcessHook { freshness, spawn, result, teardown }

class _ProcessCap extends ProcessCapability {
  const _ProcessCap({this.failingHook, this.message = ''});

  final _ProcessHook? failingHook;
  final String message;

  void _rejectAt(_ProcessHook hook) {
    if (failingHook == hook) rejectDetached(message);
  }

  @override
  Future<bool> proveFreshness(
    AdoptFence fence,
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_ProcessHook.freshness);
    return true;
  }

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    _rejectAt(_ProcessHook.spawn);
    return const RuntimeConfig(workDir: '/w', command: 'true', args: []);
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_ProcessHook.result);
    return {'grade': 'A'};
  }

  @override
  Future<void> teardown(StepArgs args) async {
    _rejectAt(_ProcessHook.teardown);
  }
}

enum _LeaseHook { adoptable, freshness, acquire, dispatch, release }

class _LeaseCap extends LeaseCapability<String> {
  const _LeaseCap({this.failingHook, this.message = '', this.prior});

  final _LeaseHook? failingHook;
  final String message;
  final LeaseBound<String>? prior;

  void _rejectAt(_LeaseHook hook) {
    if (failingHook == hook) rejectDetached(message);
  }

  @override
  Future<LeaseBound<String>?> adoptable(
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_LeaseHook.adoptable);
    return prior;
  }

  @override
  Future<bool> proveFresh(
    String handle,
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_LeaseHook.freshness);
    return true;
  }

  @override
  Future<LeaseResolution<String>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_LeaseHook.acquire);
    return const LeaseBound('lease-1');
  }

  @override
  Future<StepOutcome> dispatchOn(
    String handle,
    TreeContext context,
    StepArgs args,
  ) async {
    _rejectAt(_LeaseHook.dispatch);
    return const Ok({'grade': 'A'});
  }

  @override
  Future<void> release(String handle) async {
    _rejectAt(_LeaseHook.release);
  }
}

void main() {
  test(
    'detached service run rejection fails the allocation without escaping',
    () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final reports = <AllocationReport>[];
      final errors = await parentErrorsFor(
        () => ServiceAllocation(
          const _ServiceCap(runError: 'detached run failed'),
          contextFor(provider, reports),
        ).startOrAdopt(),
      );

      expect(errors, isEmpty);
      expectFailure(reports, 'run threw:', 'detached run failed');
    },
  );

  test(
    'process lifecycle detached rejections stay inside the allocation zone',
    () async {
      for (final testCase in [
        (
          hook: _ProcessHook.freshness,
          prefix: 'spawn failed:',
          message: 'detached freshness failed',
        ),
        (
          hook: _ProcessHook.spawn,
          prefix: 'spawn failed:',
          message: 'detached spawn failed',
        ),
        (
          hook: _ProcessHook.result,
          prefix: 'result threw:',
          message: 'detached result failed',
        ),
      ]) {
        final provider = FakeRuntimeProvider();
        addTearDown(provider.close);
        final reports = <AllocationReport>[];
        final allocation = ProcessAllocation(
          _ProcessCap(failingHook: testCase.hook, message: testCase.message),
          contextFor(
            provider,
            reports,
            kind: testCase.hook == _ProcessHook.freshness
                ? StepKind.daemon
                : StepKind.job,
            fence: testCase.hook == _ProcessHook.freshness
                ? const AdoptFence(pgid: 42)
                : const AdoptFence(),
            liveness: (_) => true,
          ),
        );
        final errors = await parentErrorsFor(() async {
          await allocation.startOrAdopt();
          if (testCase.hook == _ProcessHook.result) {
            allocation.deliverEventForTest(
              const Exited(name: 'sess-1/tg-1/work', exitCode: 0),
            );
            await drainTurns();
          }
        });

        expect(errors, isEmpty, reason: testCase.message);
        expectFailure(reports, testCase.prefix, testCase.message);
        await allocation.dispose();
      }
    },
  );

  test(
    'lease lifecycle detached rejections stay inside the allocation zone',
    () async {
      for (final testCase in [
        (
          hook: _LeaseHook.adoptable,
          prefix: 'adopt failed:',
          message: 'detached adoptable failed',
          prior: null,
          kind: StepKind.daemon,
        ),
        (
          hook: _LeaseHook.freshness,
          prefix: 'adopt failed:',
          message: 'detached freshness failed',
          prior: const LeaseBound<String>('prior-1'),
          kind: StepKind.daemon,
        ),
        (
          hook: _LeaseHook.acquire,
          prefix: 'acquire threw:',
          message: 'detached acquire failed',
          prior: null,
          kind: StepKind.job,
        ),
        (
          hook: _LeaseHook.dispatch,
          prefix: 'dispatch threw:',
          message: 'detached dispatch failed',
          prior: null,
          kind: StepKind.job,
        ),
      ]) {
        final provider = FakeRuntimeProvider();
        addTearDown(provider.close);
        final reports = <AllocationReport>[];
        final allocation = LeaseAllocation<String>(
          _LeaseCap(
            failingHook: testCase.hook,
            message: testCase.message,
            prior: testCase.prior,
          ),
          contextFor(provider, reports, kind: testCase.kind),
        );
        final errors = await parentErrorsFor(allocation.startOrAdopt);

        expect(errors, isEmpty, reason: testCase.message);
        expectFailure(reports, testCase.prefix, testCase.message);
        await allocation.dispose();
      }
    },
  );

  test(
    'capability teardown and release detached rejections do not escape',
    () async {
      final serviceProvider = FakeRuntimeProvider();
      final processProvider = FakeRuntimeProvider();
      final leaseProvider = FakeRuntimeProvider();
      addTearDown(serviceProvider.close);
      addTearDown(processProvider.close);
      addTearDown(leaseProvider.close);
      final reports = <AllocationReport>[];
      final service = ServiceAllocation(
        const _ServiceCap(teardownError: 'service teardown failed'),
        contextFor(serviceProvider, reports),
      );
      final process = ProcessAllocation(
        const _ProcessCap(
          failingHook: _ProcessHook.teardown,
          message: 'process teardown failed',
        ),
        contextFor(processProvider, reports),
      );
      final lease = LeaseAllocation<String>(
        const _LeaseCap(
          failingHook: _LeaseHook.release,
          message: 'lease release failed',
        ),
        contextFor(leaseProvider, reports, kind: StepKind.job),
      );
      await service.startOrAdopt();
      await process.startOrAdopt();
      await lease.startOrAdopt();
      final reportCount = reports.length;

      final errors = await parentErrorsFor(() async {
        await service.dispose();
        await process.dispose();
        await lease.dispose();
      });

      expect(errors, isEmpty);
      expect(reports, hasLength(reportCount));
    },
  );

  test(
    'fresh replay allocations each contain the detached rejection',
    () async {
      final failures = <List<AllocationReport>>[];
      final errors = await parentErrorsFor(() async {
        for (var i = 0; i < 2; i++) {
          final provider = FakeRuntimeProvider();
          addTearDown(provider.close);
          final reports = <AllocationReport>[];
          failures.add(reports);
          await ServiceAllocation(
            const _ServiceCap(runError: 'replayed detached failure'),
            contextFor(provider, reports),
          ).startOrAdopt();
        }
      });

      expect(errors, isEmpty);
      for (final reports in failures) {
        expectFailure(reports, 'run threw:', 'replayed detached failure');
      }
    },
  );

  test(
    'well-behaved service process and lease outcomes are unchanged',
    () async {
      final serviceProvider = FakeRuntimeProvider();
      final processProvider = FakeRuntimeProvider();
      final leaseProvider = FakeRuntimeProvider();
      addTearDown(serviceProvider.close);
      addTearDown(processProvider.close);
      addTearDown(leaseProvider.close);
      final serviceReports = <AllocationReport>[];
      final processReports = <AllocationReport>[];
      final leaseReports = <AllocationReport>[];
      final service = ServiceAllocation(
        const _ServiceCap(),
        contextFor(serviceProvider, serviceReports),
      );
      final process = ProcessAllocation(
        const _ProcessCap(),
        contextFor(processProvider, processReports),
      );
      final lease = LeaseAllocation<String>(
        const _LeaseCap(),
        contextFor(leaseProvider, leaseReports, kind: StepKind.job),
      );

      await service.startOrAdopt();
      await process.startOrAdopt();
      process.deliverEventForTest(
        const Exited(name: 'sess-1/tg-1/work', exitCode: 0),
      );
      await lease.startOrAdopt();
      await drainTurns();

      for (final reports in [serviceReports, processReports, leaseReports]) {
        expect(reports.single, isA<AllocationCompleted>());
        expect((reports.single as AllocationCompleted).payload, {'grade': 'A'});
      }
      await service.dispose();
      await process.dispose();
      await lease.dispose();
    },
  );
}
