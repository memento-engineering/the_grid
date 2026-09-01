import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/channel';

/// In-engine stand-in for an assets-pack channel adapter: protocol progress
/// and completion arrive as non-exit observations and the capability alone
/// maps them to cursor signals.
class _ProtocolEventCapability extends ProcessCapability {
  const _ProtocolEventCapability();

  @override
  CompletionContract get completionContract =>
      CompletionContract.committedWorkspace;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(
        workDir: '/tmp/tg-1',
        command: 'protocol-probe',
        lifecycle: Lifecycle.longLived,
      );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when !active => StepSignal.complete,
    Died() => StepSignal.failed,
    SessionStarted() ||
    Exited() ||
    Respawned() ||
    ActivityChanged() => StepSignal.none,
  };

  @override
  Future<Map<String, String>> result(
    TreeContext context,
    StepArgs args,
  ) async => const {'completedBy': 'protocol-event'};
}

class _FixtureSourceControl implements SourceControl {
  const _FixtureSourceControl();

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

void main() {
  test('bare exit does not advance; protocol completion signal does', () async {
    final transport = FakeRuntimeProvider();
    addTearDown(transport.close);
    final tree = FakeTreeContext(
      values: {
        Workspace: testWorkspace('tg-1', workspaceDir: '/tmp/tg-1'),
        ServiceBundle: const ServiceBundle(
          sourceControl: _FixtureSourceControl(),
        ),
      },
    );
    var workSignalProbes = 0;
    final args = stepArgs('tg-1/channel');
    final allocation = AllocationContext(
      treeContext: tree,
      args: args,
      transport: transport,
      address: const AllocationAddress('tgdog-s', 'tg-1/channel'),
      env: const {},
      sink: (_) {},
      workSignal: (_) async {
        workSignalProbes += 1;
        return GateOutcome.present;
      },
    );
    final request = ProcessLeaseRequest(
      stepBeadId: 'tgdog-step-channel',
      capability: const _ProtocolEventCapability(),
      allocation: allocation,
    );
    final dispatch = stationProcessDispatcher(
      const ProcessHandle(pgid: 44, pid: 44, token: 'channel-token'),
      request,
      tree,
      args,
    );
    var settled = false;
    unawaited(
      dispatch.then<void>((_) {
        settled = true;
      }),
    );

    transport.emit(const ActivityChanged(name: _name, active: true));
    await pumpEventQueue();
    expect(settled, isFalse, reason: 'protocol progress is non-terminal');

    transport.emit(const Exited(name: _name, exitCode: 0));
    await pumpEventQueue();
    expect(
      settled,
      isFalse,
      reason: 'a bare exit mapped to StepSignal.none cannot advance',
    );
    expect(workSignalProbes, 0);

    transport.emit(const ActivityChanged(name: _name, active: false));
    final outcome = await dispatch.timeout(const Duration(seconds: 1));

    expect(outcome, isA<Ok>());
    expect((outcome as Ok).payload, const {'completedBy': 'protocol-event'});
    expect(workSignalProbes, 0);
  });
}
