// tg-7ux — a FAILING STATE-STORE WRITE MUST NEVER TAKE THE STATION DOWN.
//
// `CapabilityHost._onReport` is a SYNCHRONOUS callback, so every persist path is
// fired without being awaited. A bare `unawaited(...)` turns any throw into an
// UNHANDLED async error that kills the whole isolate — and every one of those
// paths WRITES to the state store, which fails for reasons that are none of the
// node's business and are usually transient: a bd timeout, a Dolt server that
// died with the power, an open circuit breaker.
//
// The blast radius is the point: ONE substation's flaky store would take down
// every OTHER substation's in-flight agents. So the failure is contained to its
// own node and flared LOUD (`step.persistFailed`) — a stuck node is recoverable
// by the governor, a dead station is not.
//
// Zero I/O — fakes + a throwing chokepoint.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// A [BdRunner] whose every call throws the REAL [BdTimeoutException] the live
/// station hit — a Dolt server that is simply not there.
class _DeadStoreBdRunner implements BdRunner {
  int calls = 0;

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    calls++;
    throw BdTimeoutException(
      command: args,
      timeout: timeout ?? const Duration(seconds: 30),
    );
  }
}

/// Records every LOUD flare the host emits (the emit-only observability sink).
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

/// A [ServiceCapability] that simply succeeds — the shortest path to a terminal
/// persist (`Ok` → `AllocationCompleted` → `_persistComplete` → a store write).
class _OkCap extends ServiceCapability {
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async =>
      const Ok({'pr': 'https://example.invalid/pr/1'});

  @override
  Future<void> teardown(StepArgs args) async {}
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _mount() => const StepMount(
  step: CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: 'tg-1/agent',
  circuit: _circuit,
  circuitPath: 'tg-1',
  session: SessionHandle('tgdog-s'),
  node: NodeCursor(),
  key: ValueKey('tg-1/agent#0.0'),
);

void main() {
  group('tg-7ux — a dead state store never crashes the station', () {
    test(
      'THE BUG: a terminal persist whose store write THROWS is contained to its '
      'own node and flares LOUD — the isolate survives',
      () async {
        final runner = _DeadStoreBdRunner();
        final transport = _RecordingTransport();
        final owner = TreeOwner();

        owner.mountRoot(
          InheritedSeed<StationServices>(
            value: StationServices(
              provider: FakeRuntimeProvider(),
              writer: StationBeadWriter(
                bd: BdCliService(runner),
                ownership: BeadOwnershipPredicate(const {stateSubstation}),
              ),
              stateSubstation: stateSubstation,
            ),
            child: InheritedSeed<CapabilityRegistry>(
              value: RecordingCapabilityRegistry(),
              child: InheritedSeed<ServiceBundle>(
                value: ServiceBundle(transport: transport),
                child: InheritedSeed<Workspace>(
                  value: testWorkspace('tg-1'),
                  child: CapabilityHost(capability: _OkCap(), mount: _mount()),
                ),
              ),
            ),
          ),
        );
        addTearDown(owner.dispose);

        // Let the capability run and its terminal persist fire-and-fail. Before
        // the fix this throw escaped the bare `unawaited` as an unhandled async
        // error and the test process died with it.
        await _pump();
        await _pump();

        expect(
          runner.calls,
          greaterThan(0),
          reason: 'the persist must actually have ATTEMPTED a store write — '
              'otherwise this test proves nothing about a failing one',
        );
        expect(
          transport.flares.map((f) => f.name),
          contains('step.persistFailed'),
          reason: 'a failed persist must flare (LOUD or GONE), never vanish',
        );
        final f = transport.flares.firstWhere(
          (f) => f.name == 'step.persistFailed',
        );
        expect(f.data['op'], 'complete');
        expect(f.data['nodePath'], 'tg-1/agent');
        expect(f.data['sessionId'], 'tgdog-s');
        expect(f.data['error'], contains('imed'), reason: 'carries the cause');
      },
    );
  });
}
