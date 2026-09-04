// A capability that NAMES its failure keeps the kind through the direct
// ProcessAllocation path AND the lease-vended dispatcher; an untyped throw
// stays work. No allocation-local wrapper is introduced: the one seam is
// ProcessLeaseVendor → ProcessAllocation → AllocationFailed → CapabilityHost.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/critic';
const _exit = Exited(name: _name, exitCode: 0);

class _NamingCap extends ProcessCapability {
  const _NamingCap({
    this.onResult,
    this.onProbe,
    this.contract = CompletionContract.none,
  });

  final Object? onResult;
  final Object? onProbe;
  final CompletionContract contract;

  @override
  CompletionContract get completionContract => contract;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/w', command: 'x', args: []);

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<GateOutcome> probeCompletionArtifact(
    TreeContext context,
    StepArgs args,
  ) async {
    if (onProbe != null) throw onProbe!;
    return GateOutcome.clear;
  }

  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    if (onResult != null) throw onResult!;
    return const {'grade': 'A'};
  }
}

AllocationContext _ctx(FakeRuntimeProvider transport, AllocationSink sink) =>
    AllocationContext(
      treeContext: FakeTreeContext(),
      args: stepArgs('tg-1/critic'),
      transport: transport,
      address: const AllocationAddress('tgdog-s', 'tg-1/critic'),
      env: const {},
      sink: sink,
    );

Future<List<AllocationReport>> _direct(_NamingCap capability) async {
  final reports = <AllocationReport>[];
  final transport = FakeRuntimeProvider();
  addTearDown(transport.close);
  final alloc =
      capability.createAllocation(_ctx(transport, reports.add))
          as ProcessAllocation;
  alloc.deliverEventForTest(_exit);
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return reports;
}

Future<StepOutcome> _leased(_NamingCap capability) async {
  final transport = FakeRuntimeProvider();
  addTearDown(transport.close);
  final context = _ctx(transport, (_) {});
  transport.emit(_exit);
  return stationProcessDispatcher(
    const ProcessHandle(pgid: 1, pid: 1, token: 'token'),
    ProcessLeaseRequest(
      stepBeadId: 'step-critic',
      capability: capability,
      allocation: context,
    ),
    context.treeContext,
    context.args,
  );
}

void main() {
  test('a typed result failure keeps its kind on the DIRECT path', () async {
    final reports = await _direct(
      _NamingCap(
        onResult: CapabilityFailure.invalidResult('grade "Z" is not a band'),
      ),
    );
    final failed = reports.whereType<AllocationFailed>().single;
    expect(failed.kind, CapabilityFailureKind.invalidResult);
    expect(failed.reason, contains('not a band'));
    expect(reports.whereType<AllocationCompleted>(), isEmpty);
  });

  test(
    'a typed result failure keeps its kind on the LEASE-VENDED path',
    () async {
      final outcome = await _leased(
        _NamingCap(
          onResult: CapabilityFailure.invalidResult('grade "Z" is not a band'),
        ),
      );
      expect((outcome as Failed).kind, CapabilityFailureKind.invalidResult);
      expect(outcome.reason, contains('not a band'));
    },
  );

  test('a typed PROBE failure keeps its kind on both paths', () async {
    final reports = await _direct(
      _NamingCap(
        contract: CompletionContract.artifactDurability,
        onProbe: CapabilityFailure.noResult('the verdict file is absent'),
      ),
    );
    expect(
      reports.whereType<AllocationFailed>().single.kind,
      CapabilityFailureKind.noResult,
    );
    final outcome = await _leased(
      _NamingCap(
        contract: CompletionContract.artifactDurability,
        onProbe: CapabilityFailure.noResult('the verdict file is absent'),
      ),
    );
    expect((outcome as Failed).kind, CapabilityFailureKind.noResult);
  });

  test(
    'an UNKNOWN throw stays work on both paths (backward compatible)',
    () async {
      final reports = await _direct(
        _NamingCap(onResult: StateError('the result file is unreadable')),
      );
      final failed = reports.whereType<AllocationFailed>().single;
      expect(failed.kind, CapabilityFailureKind.work);
      expect(failed.reason, contains('result threw'));

      final outcome = await _leased(
        _NamingCap(onResult: StateError('the result file is unreadable')),
      );
      expect((outcome as Failed).kind, CapabilityFailureKind.work);
      expect(outcome.reason, contains('result threw'));
    },
  );

  test('a clean turn still completes with its payload', () async {
    final reports = await _direct(const _NamingCap());
    expect(reports.whereType<AllocationCompleted>().single.payload, {
      'grade': 'A',
    });
  });
}
