// Track A1 — ProcessCapability.result() payload hook.
//
// A process step (e.g. a critic) contributes a result payload on a clean
// completion. The host reads result() AFTER latching `complete`, and writes the
// grade MERGED with `state=complete` in ONE chokepoint update — a null result
// writes state only. Zero I/O: fakes + the recording chokepoint.
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

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/critic`
/// to — every persist now targets the step's OWN durable bead (R5b; tg-eli
/// phase 2 retired the flat `grid.cursor.*` session-bead write).
const _stepBeadId = 'tgdog-step1';

final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/critic': _stepBeadId},
  cursor: const {},
);

/// The REAL transport-backed lease vendor (tg-h4u) — routes the molecule-mode
/// critic through the SAME `RuntimeProvider` machinery the retired flat
/// `ProcessAllocation` drove.
const _realVendor = SelfManagedProcessVendor(
  spawn: stationProcessSpawner,
  dispatch: stationProcessDispatcher,
);

/// The circuit the mounted `critic` step belongs to (`StepMount.circuit`, tg-o90).
const _circuit = Circuit(
  id: 'spec_review',
  terminalStepId: 'critic',
  steps: [CapabilityStep(stepId: 'critic', capabilityId: 'critic')],
);

/// A process critic whose [result] returns [grade] (or null for no result).
class _GradingCritic extends ProcessCapability {
  const _GradingCritic(this.grade);
  final String? grade;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo grade'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async =>
      grade == null ? null : {'grade': grade!};
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

({TreeOwner owner, Fakes fakes}) _host(Capability cap) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(),
          // The workspace is an AMBIENT value now (mounted by SessionScope in
          // the real tree) — the critic's spawn reads it with the effect verb.
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: InheritedSeed<InheritedCircuit>(
              value: _moleculeCircuit,
              child: InheritedSeed<ProcessLeaseVendor>(
                value: _realVendor,
                child: CapabilityHost(
                  capability: cap,
                  mount: StepMount(
                    step: const CapabilityStep(
                      stepId: 'critic',
                      capabilityId: 'critic',
                    ),
                    nodePath: 'tg-1/critic',
                    circuit: _circuit,
                    circuitPath: 'tg-1',
                    session: const SessionHandle('tgdog-s'),
                    node: const NodeCursor(),
                    key: const ValueKey('tg-1/critic#0.0'),
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
/// `ProcessHandle`, clearing recorded chokepoint calls afterward so a
/// terminal-write assertion reads only the ONE write that follows.
Future<void> _startThenIsolate(Fakes fakes, String name) async {
  await _pump();
  fakes.provider.emit(SessionStarted(name: name, pid: 100, pgid: 200));
  await _pump();
  fakes.runner.calls.clear();
}

void main() {
  group('Track A1 — ProcessCapability.result() merges into the complete write', () {
    test('a clean Exited(0) carries state=complete AND grid.result.<path>.grade '
        'in ONE update', () async {
      final h = _host(const _GradingCritic('B'));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/critic');

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/critic', exitCode: 0));
      await _pump();

      // EXACTLY one chokepoint update — targeting the step's OWN bead (R5b) —
      // carrying both the cursor advance and the namespaced grade — disjoint
      // keys merge in one write (A1/invariant 2).
      final updates = h.fakes.runner.callsFor('update');
      expect(updates, hasLength(1));
      expect(updates.single[1], _stepBeadId);
      expect(h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
          'complete');
      expect(h.fakes.runner.metadataOfUpdate(0)['grid.result.tg-1/critic.grade'],
          'B');
    });

    test('a null-result process writes state only (positive control: no grade '
        'key leaks)', () async {
      final h = _host(const _GradingCritic(null));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/critic');

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/critic', exitCode: 0));
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta[MoleculeStepKeys.state], 'complete');
      expect(
        meta.keys.where((k) => k.startsWith('grid.result.')),
        isEmpty,
        reason: 'a null result() writes no grade key',
      );
    });
  });
}
