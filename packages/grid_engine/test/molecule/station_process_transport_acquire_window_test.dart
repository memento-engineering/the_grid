// tg-uad regression (defect D4 closes the D1 test gap): the
// acquire→dispatch window. The pre-existing suite structurally could not
// reach it — `station_process_transport_completion_fence_test.dart`'s
// `_dispatchWith` always calls `stationProcessDispatcher` FIRST and emits
// terminals AFTER, so a terminal firing while nobody is subscribed (the
// leased path's breadcrumb-write window, the pow-87e stall) was never
// exercised. These two tests emit the terminal INSIDE the window and MUST
// fail against the pre-fix lib (verified as a negative control):
//
//  t1 — transport tier: `Exited(0, inferred: true)` lands AFTER
//       `SessionStarted` resolved the spawner's handle but BEFORE
//       `stationProcessDispatcher` subscribes (a slow step-metadata writer
//       between acquire and dispatch). The step must still complete.
//  t2 — composition tier: the REAL `StationProcessLeaseVendor` +
//       `LeaseAllocation` over a `StationBeadWriter` whose serialized queue
//       holds a pending write, with a lane that exits ~immediately after
//       spawn (the warm gating lane's ~1.8s signature). The step must still
//       report `AllocationCompleted`.
//
// Fully offline (Fakes, not mocks).
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/lease';

/// A fast-exiting job lane (the gating-lane shape): no completion contract
/// (critic/validation lanes default to none — their problem is DELIVERY, not
/// proof), clean exit → complete, crash → failed.
class _JobCap extends ProcessCapability {
  const _JobCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
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
  ) async => const {'rc': '0'};
}

ProcessLeaseRequest _request({
  required FakeRuntimeProvider transport,
  AllocationSink sink = _ignoreReport,
  StepArgs? args,
}) => ProcessLeaseRequest(
  stepBeadId: 'tgdog-step-window',
  capability: const _JobCap(),
  allocation: AllocationContext(
    treeContext: FakeTreeContext(),
    args: args ?? stepArgs('tg-1/lease'),
    transport: transport,
    address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
    env: const {'GRID_INSTANCE_TOKEN': 'tok-window'},
    sink: sink,
  ),
);

void _ignoreReport(AllocationReport report) {}

/// A [BdRunner] whose `update` calls PARK until [releaseUpdates] — the
/// serialized `StationBeadWriter` queue "holding pending writes" (the
/// post-boot remount burst / committee fan-out signature). Everything else
/// answers immediately with a success envelope.
class _GatedUpdateBdRunner implements BdRunner {
  final Completer<void> _gate = Completer<void>();

  /// How many `update` invocations reached the runner (parked or done).
  int updates = 0;

  /// Opens the gate: every parked and future `update` proceeds.
  void releaseUpdates() => _gate.complete();

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) async {
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'update') {
      updates += 1;
      await _gate.future;
    }
    final id = args.length >= 2 ? args[1] : '';
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }
}

void main() {
  test(
    't1 (transport tier): an inferred exit emitted AFTER SessionStarted but '
    'BEFORE the dispatcher subscribes still completes the step',
    () async {
      final transport = FakeRuntimeProvider();
      addTearDown(transport.close);
      final reports = <AllocationReport>[];
      final args = stepArgs('tg-1/lease');
      final request = _request(
        transport: transport,
        sink: reports.add,
        args: args,
      );
      final tree = FakeTreeContext();

      // ACQUIRE: the spawner resolves its handle on SessionStarted.
      final spawning = stationProcessSpawner(request, tree, args);
      await pumpEventQueue();
      expect(transport.started, hasLength(1));
      transport.emit(const SessionStarted(name: _name, pid: 7, pgid: 7));
      final handle = await spawning;
      expect(reports.whereType<AllocationStarted>(), hasLength(1));

      // THE WINDOW: a slow step-metadata write parks dispatch while the warm
      // lane exits — the terminal fires before stationProcessDispatcher has
      // subscribed. Pre-fix this emission reached ZERO listeners on the
      // unbuffered broadcast stream and the step latched at running forever.
      transport.emit(
        const Exited(name: _name, exitCode: 0, inferred: true),
      );
      await pumpEventQueue();

      // DISPATCH (late): must still settle — bounded, never an infinite wait.
      final outcome = await stationProcessDispatcher(
        handle,
        request,
        tree,
        args,
      ).timeout(const Duration(seconds: 2));

      expect(outcome, isA<Ok>());
      expect((outcome as Ok).payload, const {'rc': '0'});
    },
  );

  test(
    't2 (composition tier): a lane that exits ~immediately after spawn while '
    'the StationBeadWriter queue holds pending writes still completes',
    () async {
      final transport = FakeRuntimeProvider();
      addTearDown(transport.close);
      final runner = _GatedUpdateBdRunner();
      final writer = StationBeadWriter(
        bd: BdCliService(runner),
        ownership: BeadOwnershipPredicate(const {'tgdog'}),
      );
      final vendor = StationProcessLeaseVendor(
        writer: writer,
        spawn: stationProcessSpawner,
        dispatch: stationProcessDispatcher,
        metadataOf: writer.metadataOf,
      );

      // The queue already holds a pending write on the SAME step bead (the
      // writer serializes per id), so the lease breadcrumb write parks
      // behind it — the pow-87e post-boot burst in miniature.
      unawaited(
        writer.update('tgdog-step-window', metadata: const {'busy': '1'}),
      );

      final reports = <AllocationReport>[];
      final args = stepArgs('tg-1/lease');
      final request = _request(
        transport: transport,
        sink: reports.add,
        args: args,
      );
      final alloc =
          vendor.leaseFor(request).createAllocation(request.allocation)
              as LeaseAllocation<ProcessHandle>;

      final done = alloc.startOrAdopt();
      await pumpEventQueue();
      expect(transport.started, hasLength(1));
      transport.emit(const SessionStarted(name: _name, pid: 9, pgid: 9));
      await pumpEventQueue();

      // The FAST EXIT: the lane is gone moments after spawn, while the
      // writer queue is still held. Pre-fix, acquire was parked awaiting the
      // breadcrumb write, the spawner's subscription was already inert, and
      // the dispatcher had not subscribed — the terminal was dropped and the
      // step never settled.
      transport.emit(
        const Exited(name: _name, exitCode: 0, inferred: true),
      );
      await pumpEventQueue();

      // Only NOW does the writer queue drain.
      runner.releaseUpdates();

      await done.timeout(const Duration(seconds: 5));
      expect(
        reports.whereType<AllocationCompleted>(),
        hasLength(1),
        reason: 'the fast-exit lane must settle, not latch at running',
      );
      await alloc.dispose();
    },
  );
}
