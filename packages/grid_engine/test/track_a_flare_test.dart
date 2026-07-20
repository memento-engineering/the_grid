// Track A4 — the flare primitive (D-8).
//
// A flare emits a fire-and-forget observability signal at a terminal transition
// and CONTINUES — it never blocks the loop. The host emits through the reserved
// emit-only ExplorationTransport (invariant 1: emit-only, never an inbound
// pipeline handle). A throwing transport must NOT break the flush. Zero I/O.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/agent`
/// to — every persist now targets the step's OWN durable bead (R5b; tg-eli
/// phase 2 retired the flat `grid.cursor.*` session-bead write).
const _stepBeadId = 'tgdog-step1';

final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
  cursor: const {},
);

/// The REAL transport-backed lease vendor (tg-h4u) — routes the molecule-mode
/// `_CompletingCap` through the SAME `RuntimeProvider` machinery the retired
/// flat `ProcessAllocation` drove.
const _realVendor = SelfManagedProcessVendor(
  spawn: stationProcessSpawner,
  dispatch: stationProcessDispatcher,
);

/// The circuit the mounted `agent` step belongs to (`StepMount.circuit`, tg-o90).
const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

class _CompletingCap extends ProcessCapability {
  const _CompletingCap();
  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo'],
    lifecycle: Lifecycle.oneTurn,
  );
  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// A recording emit-only transport — records every flare in call order.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];
  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

/// A transport that throws on every flare (the non-blocking proof).
class _ThrowingTransport implements ExplorationTransport {
  @override
  void flare(String name, Map<String, String> data) =>
      throw StateError('transport boom');
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

({TreeOwner owner, Fakes fakes}) _host(ServiceBundle services) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: services,
          // A bare host (no real SessionScope) — mount the ambient Workspace
          // the capability's spawn reads with the effect verb, plus the
          // molecule ambients every host now requires (InheritedCircuit,
          // R2; a ProcessLeaseVendor for a ProcessCapability, tg-h4u).
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: InheritedSeed<InheritedCircuit>(
              value: _moleculeCircuit,
              child: const InheritedSeed<ProcessLeaseVendor>(
                value: _realVendor,
                child: CapabilityHost(
                  capability: _CompletingCap(),
                  mount: StepMount(
                    step: CapabilityStep(
                      stepId: 'agent',
                      capabilityId: 'agent',
                    ),
                    nodePath: 'tg-1/agent',
                    circuit: _circuit,
                    circuitPath: 'tg-1',
                    session: SessionHandle('tgdog-s'),
                    node: NodeCursor(),
                    key: ValueKey('tg-1/agent#0.0'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

/// Emits `SessionStarted` for [name] then pumps — the handshake
/// `stationProcessSpawner`'s acquire hook waits on to resolve its
/// `ProcessHandle` (mirrors `track_e_capability_host_test.dart`'s
/// `_startThenIsolate`), clearing recorded chokepoint calls afterward so a
/// terminal-write assertion reads only the ONE write that follows.
Future<void> _startThenIsolate(Fakes fakes, String name) async {
  await _pump();
  fakes.provider.emit(SessionStarted(name: name, pid: 100, pgid: 200));
  await _pump();
  fakes.runner.calls.clear();
}

void main() {
  group('Track A4 — the host emits a flare on a terminal transition', () {
    test('a clean complete emits step.complete with {sessionId,nodePath}', () async {
      final transport = _RecordingTransport();
      final h = _host(ServiceBundle(transport: transport));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();

      expect(transport.flares, hasLength(1));
      expect(transport.flares.single.name, 'step.complete');
      expect(transport.flares.single.data,
          {'sessionId': 'tgdog-s', 'nodePath': 'tg-1/agent'});
    });

    test('a THROWING transport does NOT break the flush — the cursor still '
        'advanced (non-blocking proof)', () async {
      final h = _host(ServiceBundle(transport: _ThrowingTransport()));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();

      // The flare threw, but the terminal cursor write STILL landed (the flush
      // completed) — targeting the step's OWN bead (R5b). Positive control vs
      // the recording case above.
      final updates = h.fakes.runner.callsFor('update');
      expect(updates.single[1], _stepBeadId);
      expect(h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
          'complete');
    });

    test('no transport (null) — no flare, no error', () async {
      final h = _host(const ServiceBundle());
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      final updates = h.fakes.runner.callsFor('update');
      expect(updates.single[1], _stepBeadId);
      expect(h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
          'complete');
    });
  });
}
