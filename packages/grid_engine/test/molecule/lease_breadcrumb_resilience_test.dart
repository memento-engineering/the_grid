// tg-uad D3 repair round 1 — the breadcrumb write must not be silently
// forfeitable.
//
// D3 moved the acquire's breadcrumb write OUT of the critical section
// (concurrent with dispatch — SCRATCH-async-step-lifecycle §6 point 4), but
// the first cut fire-and-forgot it with a bare swallow: ONE transient bd blip
// and the incarnation ran breadcrumb-less forever — and
// `sweepOrphanedLeases` treats an absent breadcrumb as "nothing is leased",
// so a crash while that incarnation was still alive left a live orphan the
// restart sweep could neither find, kill, NOR EVEN MENTION (the round-1
// verifier's Probe A/B, kept here as regression tests).
//
// The repaired posture:
//  - the concurrent write RETRIES (backoff) until it lands, gated on the
//    incarnation still being live and its lease still held — a transient
//    blip costs milliseconds of adoption-blindness, not the whole run;
//  - a sweep candidate that already SPAWNED (state running/ready) but whose
//    lease keys are entirely ABSENT (not the cleared sentinel release
//    writes) is reported LOUD through `onOrphan` — never a silent skip.
//
// Fully offline (Fakes, not mocks).
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _name = 'tgdog-s/tg-1/lease';
const _stepBeadId = 'tgdog-step-bc';

class _JobCap extends ProcessCapability {
  const _JobCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/tmp/tg-1', command: 'sh');

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

ProcessLeaseRequest _request(FakeRuntimeProvider transport) =>
    ProcessLeaseRequest(
      stepBeadId: _stepBeadId,
      capability: const _JobCap(),
      allocation: AllocationContext(
        treeContext: FakeTreeContext(),
        args: stepArgs('tg-1/lease'),
        transport: transport,
        address: const AllocationAddress('tgdog-s', 'tg-1/lease'),
        env: const {'GRID_INSTANCE_TOKEN': 'tok-bc'},
        sink: (_) {},
      ),
    );

/// The production-shaped spawn: mints the handle WITH an open incarnation tap
/// (exactly what `stationProcessSpawner` hands back).
Future<ProcessHandle> _spawnWithTap(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) async => ProcessHandle(
  pgid: 4242,
  pid: 4243,
  token: 'tok-bc',
  events: ProcessEventTap.open(
    request.allocation.transport.events,
    request.allocation.address.providerName,
  ),
);

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

/// A [BdRunner] whose first [failFirstUpdates] `update` calls throw (the
/// transient bd blip), then land and record — so a test proves the write is
/// retried until it lands, not forfeited on the first failure.
class _FlakyBdRunner implements BdRunner {
  _FlakyBdRunner({required this.failFirstUpdates});

  int failFirstUpdates;

  /// How many `update` attempts were made (failed + landed), in order.
  int updateAttempts = 0;

  /// The decoded `--metadata` JSON of every LANDED `update`, in order.
  final List<Map<String, dynamic>> landedUpdateMetadata =
      <Map<String, dynamic>>[];

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.isNotEmpty && args.first == 'update') {
      updateAttempts += 1;
      if (failFirstUpdates > 0) {
        failFirstUpdates -= 1;
        throw StateError('bd unavailable (transient)');
      }
      final i = args.indexOf('--metadata');
      if (i >= 0) {
        landedUpdateMetadata.add(
          jsonDecode(args[i + 1]) as Map<String, dynamic>,
        );
      }
    }
    final id = args.length >= 2 ? args[1] : '';
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$id"}}',
      stderr: '',
    );
  }
}

Future<void> _eventually(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
  String reason = 'condition',
}) async {
  final sw = Stopwatch()..start();
  while (!predicate()) {
    if (sw.elapsed > timeout) {
      fail('$reason not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('a TRANSIENT breadcrumb-write failure is retried until the write LANDS '
      '(concurrently with dispatch, off the critical path) — never silently '
      'forfeited on the first blip', () async {
    final transport = FakeRuntimeProvider();
    addTearDown(transport.close);
    // The incarnation is LIVE for the whole test.
    await transport.start(
      _name,
      const RuntimeConfig(workDir: '/tmp/tg-1', command: 'sh'),
    );

    final runner = _FlakyBdRunner(failFirstUpdates: 2);
    final writer = StationBeadWriter(
      bd: BdCliService(runner),
      ownership: BeadOwnershipPredicate(const {stateSubstation}),
    );
    final request = _request(transport);
    final lease = StationProcessLeaseVendor(
      writer: writer,
      spawn: _spawnWithTap,
      dispatch: _neverDispatch,
      metadataOf: (stepBeadId) async => null,
    ).leaseFor(request);

    final resolution = await lease.acquire(
      FakeTreeContext(),
      stepArgs('tg-1/lease'),
    );
    final handle = (resolution as LeaseBound<ProcessHandle>).handle;

    // Acquire resolved IMMEDIATELY (the write is concurrent) — and the
    // retried write eventually LANDS the full breadcrumb.
    await _eventually(
      () => runner.landedUpdateMetadata.isNotEmpty,
      reason: 'the retried breadcrumb write landing',
    );
    final landed = runner.landedUpdateMetadata.single;
    expect(landed[LeaseKeys.pgid], '4242');
    expect(landed[LeaseKeys.pid], '4243');
    expect(landed[LeaseKeys.token], 'tok-bc');
    expect(
      runner.updateAttempts,
      3,
      reason: 'two failed attempts, then the landing one',
    );
    await handle.events?.close();
  });

  test('the sweep reports LOUD — never a silent skip — when a candidate that '
      'already SPAWNED (state=running) carries NO lease keys at all: the '
      'dropped-breadcrumb-write shape it cannot kill', () async {
    final fakes = buildFakes();
    final loud = <String>[];
    var aliveCalls = 0;
    var terminateCalls = 0;

    final swept =
        await StationProcessLeaseVendor(
          writer: fakes.ctx.writer,
          spawn: _spawnWithTap,
          dispatch: _neverDispatch,
          metadataOf: (stepBeadId) async => null,
        ).sweepOrphanedLeases(
          candidates: [
            // The dropped-write shape: spawned (running), NO lease keys.
            (
              stepBeadId: 'tgdog-step-dropped',
              willRemount: true,
              metadata: {
                MoleculeStepKeys.kind: StepKind.job.name,
                MoleculeStepKeys.state: StepState.running.name,
              },
            ),
            // A pre-spawn step (pending, no keys): nothing was owed —
            // stays silent.
            (
              stepBeadId: 'tgdog-step-pending',
              willRemount: true,
              metadata: {
                MoleculeStepKeys.kind: StepKind.job.name,
                MoleculeStepKeys.state: StepState.pending.name,
              },
            ),
            // The cleared SENTINEL (release ran and stopped the group):
            // an explicit record, not a dropped write — stays silent.
            (
              stepBeadId: 'tgdog-step-cleared',
              willRemount: true,
              metadata: {
                MoleculeStepKeys.kind: StepKind.job.name,
                MoleculeStepKeys.state: StepState.running.name,
                ...kClearedLeaseKeys,
              },
            ),
          ],
          alive: ({required int pgid, required int leaderPid}) {
            aliveCalls += 1;
            return true;
          },
          terminate: ({required int pgid, required int leaderPid}) async {
            terminateCalls += 1;
            return GroupTerminateResult.exitedOnTerm;
          },
          onOrphan: loud.add,
        );

    // Nothing to kill (no pgid to key from) and nothing swept — but the
    // dropped-write candidate is REPORTED, and only that one.
    expect(swept, isEmpty);
    expect(aliveCalls, 0);
    expect(terminateCalls, 0);
    expect(loud, hasLength(1));
    expect(loud.single, contains('tgdog-step-dropped'));
    expect(loud.single, contains('NO lease breadcrumb'));
    expect(fakes.runner.callsFor('update'), isEmpty);
  });
}
