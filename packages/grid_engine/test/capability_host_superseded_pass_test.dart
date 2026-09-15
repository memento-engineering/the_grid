// tg-adic — a superseded dependency pass must not permanently deafen a live
// Host's report sink.
//
// capability_host.dart:465 built the allocation report sink as a closure over
// the TreeDependencyScope of the PASS THAT CREATED the allocation:
// `sink: (report) => _onReport(scope, report)`. genesis_tree invalidates that
// scope on EVERY later dependency pass (lifecycle_provider.dart:73,
// `_LifecycleProviderState.didChangeDependencies` calls
// `_dependencyScope?._invalidate()` before minting the next scope), not only
// on teardown — and the Host never re-creates the allocation on a refresh
// (`_refreshDependencies`'s update-in-place branch, ADR-0008: "We NEVER
// re-key here"). So a host that is watched by StationServices, ServiceBundle
// or CapabilityRegistry and lives through a second dependency pass has its
// ONLY sink permanently reading a stale, non-current scope — every report
// after that pass, including a genuine terminal completion, is silently
// dropped at capability_host.dart:491 (`if (!scope.isCurrent ||
// !context.mounted) return;`). Modelled on track_a_flare_test.dart.
//
// ignore_for_file: invalid_use_of_protected_member
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

/// The step bead id `InheritedCircuit.beadIdByNodePath` resolves `tg-1/agent`
/// to (R5b).
const _stepBeadId = 'tgdog-step1';

final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
  cursor: const {},
);

/// The REAL transport-backed lease vendor (tg-h4u) — routes the molecule-mode
/// `_CompletingCap` through the same `RuntimeProvider` machinery production
/// drives.
const _realVendor = SelfManagedProcessVendor(
  spawn: stationProcessSpawner,
  dispatch: stationProcessDispatcher,
);

/// The circuit the mounted `agent` step belongs to (`StepMount.circuit`).
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

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Sources `InheritedSeed<CapabilityRegistry>` from mutable `State` so a test
/// can force a SECOND dependency pass — a fresh registry instance — without
/// disposing the host, reproducing the exact ambient re-announcement
/// genesis_tree's `LifecycleProvider` reacts to.
final class _MutableCapabilityRegistry extends StatefulSeed {
  const _MutableCapabilityRegistry({
    required this.initial,
    required this.onState,
    required this.child,
  });

  final CapabilityRegistry initial;
  final void Function(_MutableCapabilityRegistryState state) onState;
  final Seed child;

  @override
  State<_MutableCapabilityRegistry> createState() =>
      _MutableCapabilityRegistryState();
}

final class _MutableCapabilityRegistryState
    extends State<_MutableCapabilityRegistry> {
  late CapabilityRegistry _value;

  @override
  void initState() {
    _value = seed.initial;
    seed.onState(this);
  }

  /// Mints a FRESH registry instance and rebuilds. `CapabilityRegistry` is a
  /// reference type with no `==` override and genesis_tree's
  /// `InheritedSeed.updateShouldNotify` is `value != oldSeed.value`, so a
  /// fresh instance reliably re-runs the host's dependency pass.
  void rebuild() => setState(
    () => _value = RecordingCapabilityRegistry(clock: DateTime(2026)),
  );

  @override
  Seed build(TreeContext context) =>
      InheritedSeed<CapabilityRegistry>(value: _value, child: seed.child);
}

({
  TreeOwner owner,
  Branch root,
  Fakes fakes,
  _MutableCapabilityRegistryState registryState,
})
_host(ServiceBundle services) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  late _MutableCapabilityRegistryState registryState;
  final root = owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: _MutableCapabilityRegistry(
        initial: RecordingCapabilityRegistry(clock: DateTime(2026)),
        onState: (state) => registryState = state,
        child: InheritedSeed<ServiceBundle>(
          value: services,
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
  return (owner: owner, root: root, fakes: fakes, registryState: registryState);
}

Branch _hostBranch(Branch root) {
  Branch? found;
  void walk(Branch b) {
    if (b.seed is CapabilityHost) found = b;
    b.visitChildren(walk);
  }

  walk(root);
  return found!;
}

/// Emits `SessionStarted` for [name] then pumps — the handshake
/// `stationProcessSpawner`'s acquire hook waits on to resolve its
/// `ProcessHandle` — clearing recorded chokepoint calls afterward so a
/// terminal-write assertion reads only the ONE write that follows.
Future<void> _startThenIsolate(Fakes fakes, String name) async {
  await _pump();
  fakes.provider.emit(SessionStarted(name: name, pid: 100, pgid: 200));
  await _pump();
  fakes.runner.calls.clear();
}

void main() {
  group(
    'tg-adic — a superseded dependency pass must not deafen a live host',
    () {
      test('an agent that exits AFTER a later dependency pass still completes '
          '(step.complete, not silently dropped)', () async {
        final transport = _RecordingTransport();
        final h = _host(ServiceBundle(transport: transport));
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        // Pass 1 — the allocation is created and captures pass 1.
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

        // Pass 2 supersedes pass 1 — the SAME host stays mounted; only the
        // CapabilityRegistry instance identity changes.
        h.registryState.rebuild();
        h.owner.flush();
        await _pump();

        // The agent finishes AFTER the pass.
        h.fakes.provider.emit(
          const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
        );
        await _pump();

        final completes = transport.flares.where(
          (f) => f.name == 'step.complete',
        );
        expect(completes, hasLength(1));
        expect(completes.single.data, {
          'sessionId': 'tgdog-s',
          'nodePath': 'tg-1/agent',
        });
        expect(
          transport.flares.where((f) => f.name == 'step.reportDropped'),
          isEmpty,
        );

        final updates = h.fakes.runner.callsFor('update');
        expect(updates, isNotEmpty, reason: 'the terminal write must land');
        expect(updates.last[1], _stepBeadId);
        expect(
          h.fakes.runner.metadataOfUpdate(
            updates.length - 1,
          )[MoleculeStepKeys.state],
          'complete',
        );
      });

      test('a report delivered to a torn-down host emits step.reportDropped '
          'instead of vanishing', () async {
        final transport = _RecordingTransport();
        final h = _host(ServiceBundle(transport: transport));
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
        // Capture the State BEFORE dispose (the branch leaves the tree on
        // unmount).
        final state =
            (_hostBranch(h.root) as StatefulBranch).state
                as CapabilityHostState;
        transport.flares.clear();
        h.owner.dispose();
        state.deliverReportForTest(const AllocationCompleted());
        await _pump();
        unawaited(h.fakes.provider.close());

        expect(transport.flares, hasLength(1));
        expect(transport.flares.single.name, 'step.reportDropped');
        expect(transport.flares.single.data['sessionId'], 'tgdog-s');
        expect(transport.flares.single.data['nodePath'], 'tg-1/agent');
      });
    },
  );
}
