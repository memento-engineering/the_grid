import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const cachedCurrentRound = <String, String>{'round': '1', 'grade': 'B'};
const _name = 'tgdog-s/tg-1/critic';
const _exit = Exited(name: _name, exitCode: 0);

class _ArtifactCapability extends ProcessCapability {
  _ArtifactCapability({
    required this.contract,
    required this.artifactOutcome,
    required this.log,
    this.payload = cachedCurrentRound,
    this.throwProbe = false,
    this.throwResult = false,
  });

  final CompletionContract contract;
  final GateOutcome artifactOutcome;
  final List<String> log;
  final Map<String, String> payload;
  final bool throwProbe;
  final bool throwResult;

  @override
  CompletionContract get completionContract => contract;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(
        workDir: '/tmp/tg-1',
        command: 'sh',
        args: ['-c', 'grade'],
        lifecycle: Lifecycle.oneTurn,
      );

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
    await Future<void>.delayed(Duration.zero);
    if (throwProbe) throw StateError('artifact read failed');
    if (artifactOutcome == GateOutcome.clear) {
      log.add('artifact-durable');
    }
    return artifactOutcome;
  }

  @override
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async {
    if (throwResult) throw StateError('result read failed');
    log.add('result-read');
    return payload;
  }
}

AllocationContext _context({
  required FakeRuntimeProvider transport,
  required AllocationSink sink,
}) => AllocationContext(
  treeContext: FakeTreeContext(),
  args: stepArgs('tg-1/critic'),
  transport: transport,
  address: const AllocationAddress('tgdog-s', 'tg-1/critic'),
  env: const {},
  sink: sink,
);

Future<List<AllocationReport>> _direct(_ArtifactCapability capability) async {
  final reports = <AllocationReport>[];
  final allocation =
      capability.createAllocation(
            _context(
              transport: FakeRuntimeProvider(),
              sink: (report) {
                reports.add(report);
                if (report is AllocationCompleted) {
                  capability.log.add('completion-visible');
                }
              },
            ),
          )
          as ProcessAllocation;
  allocation.deliverEventForTest(_exit);
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return reports;
}

Future<StepOutcome> _leased(
  _ArtifactCapability capability, {
  required bool retained,
}) async {
  final transport = FakeRuntimeProvider();
  final context = _context(transport: transport, sink: (_) {});
  if (retained) transport.emit(_exit);
  final outcome = stationProcessDispatcher(
    const ProcessHandle(pgid: 1, pid: 1, token: 'token'),
    ProcessLeaseRequest(
      stepBeadId: 'step-critic',
      capability: capability,
      allocation: context,
    ),
    context.treeContext,
    context.args,
  );
  if (!retained) transport.emit(_exit);
  return outcome;
}

void main() {
  group('artifact-durable direct completion', () {
    for (final outcome in <GateOutcome>[
      GateOutcome.present,
      GateOutcome.probeError,
    ]) {
      test('an artifactless completion ($outcome) is a non-result', () async {
        final reports = await _direct(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: outcome,
            log: <String>[],
          ),
        );
        expect(reports.whereType<AllocationFailed>().single.nonResult, isTrue);
      });

      test('the leased artifactless completion ($outcome) is too', () async {
        final result = await _leased(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: outcome,
            log: <String>[],
          ),
          retained: true,
        );
        expect((result as Failed).nonResult, isTrue);
      });
    }

    test(
      'cached current-round result without an artifact is unresolved',
      () async {
        final log = <String>[];
        final reports = await _direct(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: GateOutcome.present,
            log: log,
          ),
        );

        expect(reports.whereType<AllocationCompleted>(), isEmpty);
        expect(reports.whereType<AllocationFailed>(), hasLength(1));
        expect(
          reports.whereType<AllocationFailed>().single.reason,
          contains('unresolved'),
        );
        expect(log, isNot(contains('result-read')));
      },
    );

    test('durability and result read precede visible completion', () async {
      final log = <String>[];
      final reports = await _direct(
        _ArtifactCapability(
          contract: CompletionContract.artifactDurability,
          artifactOutcome: GateOutcome.clear,
          log: log,
        ),
      );

      expect(
        reports.whereType<AllocationCompleted>().single.payload,
        cachedCurrentRound,
      );
      expect(log, <String>[
        'artifact-durable',
        'result-read',
        'completion-visible',
      ]);
    });

    test('an empty durable payload completes', () async {
      final reports = await _direct(
        _ArtifactCapability(
          contract: CompletionContract.artifactDurability,
          artifactOutcome: GateOutcome.clear,
          log: <String>[],
          payload: const <String, String>{},
        ),
      );
      expect(reports.whereType<AllocationCompleted>().single.payload, isEmpty);
    });

    for (final edge in <({String name, GateOutcome outcome, bool throws})>[
      (name: 'probe error', outcome: GateOutcome.probeError, throws: false),
      (name: 'throwing probe', outcome: GateOutcome.clear, throws: true),
    ]) {
      test('${edge.name} fails without reading the cache', () async {
        final log = <String>[];
        final reports = await _direct(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: edge.outcome,
            throwProbe: edge.throws,
            log: log,
          ),
        );
        expect(reports.whereType<AllocationFailed>(), hasLength(1));
        expect(log, isNot(contains('result-read')));
      });
    }

    test('a throwing result fails after a clear artifact probe', () async {
      final log = <String>[];
      final reports = await _direct(
        _ArtifactCapability(
          contract: CompletionContract.artifactDurability,
          artifactOutcome: GateOutcome.clear,
          throwResult: true,
          log: log,
        ),
      );
      expect(reports.whereType<AllocationFailed>(), hasLength(1));
      expect(log, <String>['artifact-durable']);
    });

    test('none preserves the artifactless cached completion', () async {
      final log = <String>[];
      final reports = await _direct(
        _ArtifactCapability(
          contract: CompletionContract.none,
          artifactOutcome: GateOutcome.present,
          log: log,
        ),
      );
      expect(
        reports.whereType<AllocationCompleted>().single.payload,
        cachedCurrentRound,
      );
      expect(log, <String>['result-read', 'completion-visible']);
    });
  });

  group('artifact-durable leased completion', () {
    for (final retained in <bool>[false, true]) {
      final kind = retained ? 'retained' : 'live';
      test('$kind artifactless cached completion is unresolved', () async {
        final log = <String>[];
        final outcome = await _leased(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: GateOutcome.present,
            log: log,
          ),
          retained: retained,
        );
        expect(outcome, isA<Failed>());
        expect((outcome as Failed).reason, contains('unresolved'));
        expect(log, isEmpty);
      });

      test('$kind durable completion probes before reading result', () async {
        final log = <String>[];
        final outcome = await _leased(
          _ArtifactCapability(
            contract: CompletionContract.artifactDurability,
            artifactOutcome: GateOutcome.clear,
            log: log,
          ),
          retained: retained,
        );
        expect((outcome as Ok).payload, cachedCurrentRound);
        expect(log, <String>['artifact-durable', 'result-read']);
      });

      test('$kind none preserves artifactless cached completion', () async {
        final log = <String>[];
        final outcome = await _leased(
          _ArtifactCapability(
            contract: CompletionContract.none,
            artifactOutcome: GateOutcome.present,
            log: log,
          ),
          retained: retained,
        );
        expect((outcome as Ok).payload, cachedCurrentRound);
        expect(log, <String>['result-read']);
      });
    }
  });
}
