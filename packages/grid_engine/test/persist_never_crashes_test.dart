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
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
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

/// A [BdRunner] whose write of ONE named cursor state throws and whose every
/// other call succeeds — the `tg-0zq8` shape. The live incident was narrower
/// than a dead store: the step's own terminal write was refused while writes to
/// other beads kept landing, so the node re-derived at 1 Hz forever.
class _SelectiveThrowingBdRunner implements BdRunner {
  _SelectiveThrowingBdRunner(this.refusedState);

  /// The `grid.step.state` value whose write is refused (`complete`/`escalated`).
  final String refusedState;

  /// Full argv of every recorded call, in order.
  final List<List<String>> calls = <List<String>>[];

  /// The `grid.step.state` value of every call that was ALLOWED to land.
  List<String> get landedStates => [
    for (final argv in calls)
      if (_stateOf(argv) case final String state)
        if (state != refusedState) state,
  ];

  static String? _stateOf(List<String> argv) {
    for (final arg in argv) {
      if (arg.startsWith('${MoleculeStepKeys.state}=')) {
        return arg.split('=').last;
      }
    }
    return null;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(args);
    if (_stateOf(args) == refusedState) {
      throw BdTimeoutException(
        command: args,
        timeout: timeout ?? const Duration(seconds: 30),
      );
    }
    return const BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":{"id":"$_stepBeadId"}}',
      stderr: '',
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

/// A [ServiceCapability] that FAILS — the shortest path to the `failure` persist
/// op, whose write IS `_persistFailure` and must therefore never be "recovered"
/// by a second `_persistFailure`.
class _FailingCap extends ServiceCapability {
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async =>
      const Failed('the capability itself failed');

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

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/agent`
/// to — the molecule model is the ONLY circuit engine (tg-eli phase 2), so a
/// terminal persist needs this ambient to have anywhere to WRITE at all
/// before it can prove that write's throw is contained (mirrors
/// `host_molecule_targeting_test.dart`'s `_moleculeCircuit` fixture).
const _stepBeadId = 'tgdog-step1';

final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
  cursor: const {},
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
                reader: const EmptyBeadProbeReader(),
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
                  child: InheritedSeed<InheritedCircuit>(
                    value: _moleculeCircuit,
                    child: CapabilityHost(
                      capability: _OkCap(),
                      mount: _mount(),
                    ),
                  ),
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
          reason:
              'the persist must actually have ATTEMPTED a store write — '
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

  group('tg-0zq8 — a dropped persist gets a BOUNDED, DURABLE consequence', () {
    /// Mounts one [CapabilityHost] under the same five-layer inherited tree the
    /// tg-7ux fixture uses, with [capability] and [runner] swapped in.
    TreeOwner mountHost(
      Capability capability,
      BdRunner runner,
      ExplorationTransport transport,
    ) {
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<StationServices>(
          value: StationServices(
            provider: FakeRuntimeProvider(),
            writer: StationBeadWriter(
              bd: BdCliService(runner),
              reader: const EmptyBeadProbeReader(),
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
                child: InheritedSeed<InheritedCircuit>(
                  value: _moleculeCircuit,
                  child: CapabilityHost(
                    capability: capability,
                    mount: _mount(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return owner;
    }

    List<({String name, Map<String, String> data})> named(
      _RecordingTransport t,
      String name,
    ) => t.flares.where((f) => f.name == name).toList();

    test('THE BUG: a REFUSED terminal write is routed into the D-5 supervised-'
        'restart writer — restartCount is bumped and PERSISTED, so the frontier '
        'cannot re-derive the node forever', () async {
      final runner = _SelectiveThrowingBdRunner('complete');
      final transport = _RecordingTransport();
      addTearDown(mountHost(_OkCap(), runner, transport).dispose);

      await _pump();
      await _pump();

      final failed = named(transport, 'step.persistFailed');
      expect(failed, hasLength(1), reason: 'exactly one, not one per turn');
      expect(failed.single.data['op'], 'complete');
      expect(failed.single.data['maxRestarts'], '3');

      expect(
        named(transport, 'step.persistRecoveryFailed'),
        isEmpty,
        reason: 'the supervision write itself was allowed to land',
      );

      // The whole point: the drop left a DURABLE mark. Before the fix the
      // only write attempted was the refused one and nothing was recorded,
      // so the node re-ran at 1 Hz — 149,420 commits against one step bead.
      expect(
        runner.landedStates,
        ['failed'],
        reason:
            'the refused `complete` must be followed by exactly one landed '
            '`failed` — the supervised-restart cursor write',
      );
      final supervision = runner.calls.last.join(' ');
      expect(
        supervision,
        contains('${MoleculeStepKeys.restartCount}=1'),
        reason:
            'restartCount rides the PERSISTED cursor (ADR-0008 D7), so '
            'the breaker survives a bounce and actually trips',
      );
      expect(
        supervision,
        contains(MoleculeStepKeys.cooldownUntil),
        reason: 'a backoff cooldown is what stops the 1 Hz re-derive',
      );
      expect(
        supervision,
        contains('complete'),
        reason: 'the failure reason names the op that was dropped',
      );
    });

    test(
      'the `failure` op is NOT recovered — recovering a failed failure-write '
      'with another failure-write is the loop this bead closes',
      () async {
        final runner = _SelectiveThrowingBdRunner('failed');
        final transport = _RecordingTransport();
        addTearDown(mountHost(_FailingCap(), runner, transport).dispose);

        await _pump();
        await _pump();

        final failed = named(transport, 'step.persistFailed');
        expect(failed, hasLength(1));
        expect(failed.single.data['op'], 'failure');
        expect(
          runner.landedStates,
          isEmpty,
          reason: 'no second write may be attempted for the failure op',
        );
        expect(named(transport, 'step.persistRecoveryFailed'), isEmpty);
      },
    );

    test('a store that is COMPLETELY gone flares twice and stops — two writes '
        'maximum per report, never a third', () async {
      final runner = _DeadStoreBdRunner();
      final transport = _RecordingTransport();
      addTearDown(mountHost(_OkCap(), runner, transport).dispose);

      await _pump();
      await _pump();

      expect(named(transport, 'step.persistFailed'), hasLength(1));
      final recovery = named(transport, 'step.persistRecoveryFailed');
      expect(
        recovery,
        hasLength(1),
        reason: 'the supervision write failed too — LOUD under its own name',
      );
      expect(recovery.single.data['op'], 'complete');
      expect(
        runner.calls,
        2,
        reason:
            'the refused write plus ONE supervision attempt — a third would '
            'be the unbounded loop again',
      );
    });
  });
}
