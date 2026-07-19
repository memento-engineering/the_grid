import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

class _CommittedProcessCap extends ProcessCapability {
  const _CommittedProcessCap({this.payload = const <String, String>{}});

  final Map<String, String> payload;

  @override
  CompletionContract get completionContract =>
      CompletionContract.committedWorkspace;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(
        workDir: '/tmp/tg-1',
        command: 'sh',
        args: ['-c', 'true'],
        lifecycle: Lifecycle.oneTurn,
      );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>> result(
    TreeContext context,
    StepArgs args,
  ) async => payload;
}

class _FakeSourceControl implements SourceControl {
  const _FakeSourceControl();

  @override
  String get baseBranch => 'main';

  @override
  String branchFor(String beadId) => 'grid/$beadId';

  @override
  String workspaceFor(String beadId) => '/tmp/$beadId';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {}
}

Future<({StepOutcome outcome, int probes})> _dispatchWith({
  required RuntimeEvent event,
  required GateOutcome gate,
}) async {
  var probes = 0;
  final transport = FakeRuntimeProvider();
  final tree = FakeTreeContext(
    values: {
      Workspace: testWorkspace('tg-1', workspaceDir: '/tmp/tg-1'),
      ServiceBundle: const ServiceBundle(sourceControl: _FakeSourceControl()),
    },
  );
  final ctx = AllocationContext(
    treeContext: tree,
    args: stepArgs('tg-1/build'),
    transport: transport,
    address: const AllocationAddress('tgdog-sess1', 'tg-1/build'),
    env: const {},
    sink: (_) {},
    workSignal: (_) async {
      probes += 1;
      return gate;
    },
  );
  final request = ProcessLeaseRequest(
    stepBeadId: 'tgdog-step-build',
    capability: const _CommittedProcessCap(payload: {'ok': 'true'}),
    allocation: ctx,
  );
  final future = stationProcessDispatcher(
    const ProcessHandle(pgid: 44, pid: 44, token: 'tok'),
    request,
    tree,
    ctx.args,
  );
  transport.emit(event);
  return (outcome: await future, probes: probes);
}

void main() {
  test(
    'inferred committed-work completion clears only after work signal clears',
    () async {
      final result = await _dispatchWith(
        event: const Exited(
          name: 'tgdog-sess1/tg-1/build',
          exitCode: 0,
          inferred: true,
        ),
        gate: GateOutcome.clear,
      );
      expect(result.probes, 1);
      expect(result.outcome, isA<Ok>());
      expect((result.outcome as Ok).payload, {'ok': 'true'});
    },
  );

  test(
    'inferred committed-work completion fails closed when work remains',
    () async {
      final result = await _dispatchWith(
        event: const Exited(
          name: 'tgdog-sess1/tg-1/build',
          exitCode: 0,
          inferred: true,
        ),
        gate: GateOutcome.present,
      );
      expect(result.probes, 1);
      expect(result.outcome, isA<Failed>());
      expect(
        (result.outcome as Failed).reason,
        contains('uncommitted work remains'),
      );
    },
  );

  test(
    'inferred committed-work completion fails closed on probe error',
    () async {
      final result = await _dispatchWith(
        event: const Exited(
          name: 'tgdog-sess1/tg-1/build',
          exitCode: 0,
          inferred: true,
        ),
        gate: GateOutcome.probeError,
      );
      expect(result.probes, 1);
      expect(result.outcome, isA<Failed>());
      expect(
        (result.outcome as Failed).reason,
        contains('work-signal probe failed'),
      );
    },
  );

  test('observed committed-work completion is not fenced', () async {
    final result = await _dispatchWith(
      event: const Exited(name: 'tgdog-sess1/tg-1/build', exitCode: 0),
      gate: GateOutcome.present,
    );
    expect(result.probes, 0);
    expect(result.outcome, isA<Ok>());
  });
}
