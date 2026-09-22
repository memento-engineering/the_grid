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
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
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

/// A delivery seam that lets the test supersede the dependency pass while the
/// terminal route is waiting on its external push/PR round-trip.
final class _BlockingDeliveryMethod implements DeliveryMethod {
  @override
  String get id => 'blocking-delivery';

  final entered = Completer<void>();
  final release = Completer<StepOutcome>();
  final requests = <DeliveryRequest>[];

  @override
  Future<StepOutcome> deliver(DeliveryRequest request) {
    requests.add(request);
    entered.complete();
    return release.future;
  }
}

final class _PersistAttemptBarrier {
  final entered = Completer<void>();
  final release = Completer<void>();
}

/// Records every bd call and pauses each `state=complete` update so a test can
/// land another tree pass (or teardown) inside the persist's async gap.
final class _TimeoutCompleteRunner extends RecordingBdRunner {
  _TimeoutCompleteRunner({
    required this.timeoutAttempts,
    required int completionAttempts,
  }) : barriers = List.generate(
         completionAttempts,
         (_) => _PersistAttemptBarrier(),
       ),
       super(createdId: 'tgdog-gate1');

  final int timeoutAttempts;
  final List<_PersistAttemptBarrier> barriers;
  final List<int> timedOutCompletionAttempts = [];
  final List<int> landedCompletionAttempts = [];
  int _nextCompletionAttempt = 0;

  static String? _stateOf(List<String> args) {
    for (var i = 0; i + 1 < args.length; i++) {
      if (args[i] == '--set-metadata') {
        final pair = args[i + 1];
        final prefix = '${MoleculeStepKeys.state}=';
        if (pair.startsWith(prefix)) return pair.substring(prefix.length);
      }
      if (args[i] == '--metadata') {
        final metadata = jsonDecode(args[i + 1]) as Map<String, dynamic>;
        return metadata[MoleculeStepKeys.state]?.toString();
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
    final result = await super.run(args, timeout: timeout, stdin: stdin);
    if (_stateOf(args) != StepState.complete.name) return result;

    final attempt = _nextCompletionAttempt++;
    if (attempt >= barriers.length) {
      throw StateError('unexpected completion attempt ${attempt + 1}');
    }
    final barrier = barriers[attempt];
    barrier.entered.complete();
    await barrier.release.future;
    if (attempt < timeoutAttempts) {
      timedOutCompletionAttempts.add(attempt);
      throw BdTimeoutException(
        command: args,
        timeout: const Duration(seconds: 10),
      );
    }
    landedCompletionAttempts.add(attempt);
    return result;
  }
}

/// A passive effect: the test drives each advance explicitly through the real
/// Host report sink, so no automatic terminal report races the persist probe.
final class _ManualAdvanceCapability extends Capability {
  const _ManualAdvanceCapability();

  @override
  Allocation createAllocation(AllocationInputs inputs) =>
      _ManualAdvanceAllocation(inputs);
}

final class _ManualAdvanceAllocation extends Allocation {
  _ManualAdvanceAllocation(super.inputs);

  @override
  Future<void> startOrAdopt(TreeContext treeContext) async {
    state = AllocationState.live;
  }

  @override
  Future<void> dispose() async {
    inputs.args.cancel.cancel();
    state = AllocationState.gone;
  }
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
    required this.replacementFactory,
    required this.onState,
    required this.child,
  });

  final CapabilityRegistry initial;
  final CapabilityRegistry Function() replacementFactory;
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
  void rebuild() => setState(() => _value = seed.replacementFactory());

  @override
  Seed build(TreeContext context) =>
      InheritedSeed<CapabilityRegistry>(value: _value, child: seed.child);
}

/// Owns the observed cursor and rebuilds the real [CircuitScope] from each
/// persisted step-bead projection, exactly as the live join does.
final class _PersistCursorHarness extends StatefulSeed {
  const _PersistCursorHarness({required this.onState});

  final void Function(_PersistCursorHarnessState state) onState;

  @override
  State<_PersistCursorHarness> createState() => _PersistCursorHarnessState();
}

final class _PersistCursorHarnessState extends State<_PersistCursorHarness> {
  CircuitCursor _cursor = const {};

  @override
  void initState() => seed.onState(this);

  NodeCursor projectUpdate(Map<String, dynamic> metadata) {
    final projected = projectMoleculeCursor([
      Bead(
        id: _stepBeadId,
        issueType: GridIssueTypes.step,
        metadata: {MoleculeStepKeys.path: 'tg-1/agent', ...metadata},
      ),
    ]);
    final node = projected.cursor['tg-1/agent']!;
    setState(() => _cursor = projected.cursor);
    return node;
  }

  @override
  Seed build(TreeContext context) => InheritedSeed<SessionHandle>(
    value: const SessionHandle('tgdog-s'),
    child: InheritedSeed<InheritedCircuit>(
      value: InheritedCircuit(
        root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
        beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
        cursor: _cursor,
      ),
      child: CircuitScope(circuit: _circuit, cursor: _cursor, nodePath: 'tg-1'),
    ),
  );
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
        replacementFactory: () =>
            RecordingCapabilityRegistry(clock: DateTime(2026)),
        onState: (state) => registryState = state,
        child: InheritedSeed<ServiceBundle>(
          value: services,
          child: InheritedSeed<Bead>(
            value: bead('tg-1'),
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
    ),
  );
  return (owner: owner, root: root, fakes: fakes, registryState: registryState);
}

Fakes _fakesWithRunner(RecordingBdRunner runner) {
  final provider = FakeRuntimeProvider();
  final git = RecordingGitRunner();
  final pr = FakePrOpener();
  final writer = StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  );
  return (
    ctx: StationServices(
      provider: provider,
      writer: writer,
      stateSubstation: stateSubstation,
    ),
    runner: runner,
    provider: provider,
    git: git,
    pr: pr,
  );
}

({
  TreeOwner owner,
  Branch root,
  Fakes fakes,
  _RecordingTransport transport,
  _MutableCapabilityRegistryState registryState,
  _PersistCursorHarnessState cursorState,
})
_persistHost(RecordingBdRunner runner, {required DateTime Function() clock}) {
  const capability = _ManualAdvanceCapability();
  CapabilityRegistry registry() => DefaultCapabilityRegistry(
    capabilities: const {'agent': capability},
    circuits: {_circuit.id: _circuit},
    clock: clock,
  );

  final fakes = _fakesWithRunner(runner);
  final transport = _RecordingTransport();
  final owner = TreeOwner();
  late _MutableCapabilityRegistryState registryState;
  late _PersistCursorHarnessState cursorState;
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<StationServices>(
        value: fakes.ctx,
        child: _MutableCapabilityRegistry(
          initial: registry(),
          replacementFactory: registry,
          onState: (state) => registryState = state,
          child: InheritedSeed<ServiceBundle>(
            value: ServiceBundle(transport: transport),
            child: InheritedSeed<Bead>(
              value: bead('tg-1'),
              child: InheritedSeed<Workspace>(
                value: testWorkspace('tg-1'),
                child: _PersistCursorHarness(
                  onState: (state) => cursorState = state,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (
    owner: owner,
    root: root,
    fakes: fakes,
    transport: transport,
    registryState: registryState,
    cursorState: cursorState,
  );
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

List<Branch> _hostBranches(Branch root) {
  final found = <Branch>[];
  void walk(Branch branch) {
    if (branch.seed is CapabilityHost) found.add(branch);
    branch.visitChildren(walk);
  }

  walk(root);
  return found;
}

List<Map<String, dynamic>> _stepUpdates(
  RecordingBdRunner runner,
  StepState state,
) {
  final updates = runner.workUpdates;
  final found = <Map<String, dynamic>>[];
  for (var i = 0; i < updates.length; i++) {
    if (updates[i].length < 2 || updates[i][1] != _stepBeadId) continue;
    final metadata = runner.metadataOfUpdate(i);
    if (metadata[MoleculeStepKeys.state] == state.name) found.add(metadata);
  }
  return found;
}

Future<void> _waitUntil(
  bool Function() predicate, {
  String reason = 'condition did not become true',
}) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail(reason);
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

      test('a terminal delivery that spans a later dependency pass still '
          'persists complete once', () async {
        final delivery = _BlockingDeliveryMethod();
        final transport = _RecordingTransport();
        final h = _host(
          ServiceBundle(delivery: delivery, transport: transport),
        );
        addTearDown(() {
          if (!delivery.release.isCompleted) {
            delivery.release.complete(const Failed('test teardown'));
          }
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
        final hostBranch = _hostBranch(h.root);
        final state =
            (hostBranch as StatefulBranch).state as CapabilityHostState;

        state.deliverReportForTest(const AllocationAdvanced({'grade': 'pass'}));
        await delivery.entered.future;

        h.registryState.rebuild();
        h.owner.flush();
        await _pump();

        expect(_hostBranch(h.root), same(hostBranch));
        expect(hostBranch.mounted, isTrue);

        delivery.release.complete(
          const Ok({'pr_url': 'https://example.test/pr/469'}),
        );
        await _pump();

        expect(delivery.requests, hasLength(1));
        final updates = h.fakes.runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single[1], _stepBeadId);
        expect(
          h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
          'complete',
        );
        expect(
          transport.flares.where((flare) => flare.name == 'step.complete'),
          hasLength(1),
        );
        expect(
          transport.flares.where((flare) => flare.name == 'step.reportDropped'),
          isEmpty,
        );
        expect(
          transport.flares.where(
            (flare) => flare.name == 'step.persistDropped',
          ),
          isEmpty,
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

  group('persist-timeout recovery across dependency passes', () {
    test('a timed-out advance survives a superseding pass, persists restart 1, '
        'and completes on the next pass', () async {
      var now = DateTime.utc(2026, 9, 17);
      final runner = _TimeoutCompleteRunner(
        timeoutAttempts: 1,
        completionAttempts: 2,
      );
      final h = _persistHost(runner, clock: () => now);
      addTearDown(() {
        h.owner.dispose();
        h.fakes.ctx.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final firstHost = _hostBranch(h.root);
      final firstState =
          (firstHost as StatefulBranch).state as CapabilityHostState;
      firstState.deliverReportForTest(
        const AllocationAdvanced({'grade': 'pass'}),
      );
      await runner.barriers[0].entered.future;

      // Supersede the pass that reported the advance while its store write is
      // still pending. The host stays mounted and receives a fresh scope.
      h.registryState.rebuild();
      h.owner.flush();
      await _pump();
      expect(_hostBranch(h.root), same(firstHost));

      runner.barriers[0].release.complete();
      await _waitUntil(
        () => _stepUpdates(runner, StepState.failed).isNotEmpty,
        reason: 'the timeout recovery write never landed',
      );

      final failed = _stepUpdates(runner, StepState.failed).single;
      expect(failed[MoleculeStepKeys.restartCount], '1');
      expect(failed[MoleculeStepKeys.cooldownUntil], isNotNull);
      expect(runner.timedOutCompletionAttempts, [0]);
      expect(
        h.transport.flares.where(
          (flare) => flare.name == 'step.persistDropped',
        ),
        isEmpty,
      );

      final cooldown = DateTime.parse(
        '${failed[MoleculeStepKeys.cooldownUntil]}',
      );
      now = cooldown.add(const Duration(milliseconds: 1));
      final recovered = h.cursorState.projectUpdate(failed);
      expect(recovered.restartCount, 1);
      expect(recovered.cooldownUntil, cooldown);
      h.owner.flush();
      await _pump();

      final retriedHost = _hostBranch(h.root);
      expect(retriedHost, isNot(same(firstHost)));
      final retriedState =
          (retriedHost as StatefulBranch).state as CapabilityHostState;
      retriedState.deliverReportForTest(
        const AllocationAdvanced({'grade': 'pass'}),
      );
      await runner.barriers[1].entered.future;
      runner.barriers[1].release.complete();
      await _waitUntil(
        () => h.transport.flares.any((flare) => flare.name == 'step.complete'),
        reason: 'the re-armed advance never completed',
      );

      expect(runner.landedCompletionAttempts, [1]);
      expect(_stepUpdates(runner, StepState.complete), hasLength(2));
      expect(
        h.transport.flares.where((flare) => flare.name == 'step.persistFailed'),
        hasLength(1),
      );
      expect(
        h.transport.flares.where((flare) => flare.name == 'step.complete'),
        hasLength(1),
      );
    });

    test('maxRestarts timed-out advances park one persist-exhausted gate and '
        'stop', () async {
      var now = DateTime.utc(2026, 9, 17);
      final runner = _TimeoutCompleteRunner(
        timeoutAttempts: 3,
        completionAttempts: 3,
      );
      final h = _persistHost(runner, clock: () => now);
      addTearDown(() {
        h.owner.dispose();
        h.fakes.ctx.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      for (var attempt = 0; attempt < 3; attempt++) {
        final host = _hostBranch(h.root);
        final state = (host as StatefulBranch).state as CapabilityHostState;
        state.deliverReportForTest(const AllocationAdvanced({'grade': 'pass'}));
        await runner.barriers[attempt].entered.future;

        h.registryState.rebuild();
        h.owner.flush();
        await _pump();
        expect(_hostBranch(h.root), same(host));

        runner.barriers[attempt].release.complete();
        if (attempt < 2) {
          await _waitUntil(
            () => _stepUpdates(runner, StepState.failed).length == attempt + 1,
            reason: 'restart ${attempt + 1} was not persisted',
          );
          final failed = _stepUpdates(runner, StepState.failed).last;
          expect(failed[MoleculeStepKeys.restartCount], '${attempt + 1}');
          final cooldown = DateTime.parse(
            '${failed[MoleculeStepKeys.cooldownUntil]}',
          );
          now = cooldown.add(const Duration(milliseconds: 1));
          h.cursorState.projectUpdate(failed);
          h.owner.flush();
          await _pump();
        }
      }

      await _waitUntil(
        () => h.transport.flares.any((flare) => flare.name == 'step.gated'),
        reason: 'restart exhaustion never opened a gate',
      );

      final gated = _stepUpdates(runner, StepState.gated).single;
      expect(gated[MoleculeStepKeys.restartCount], '3');
      expect(gated.containsKey(MoleculeStepKeys.cooldownUntil), isFalse);
      expect(runner.callsFor('create'), hasLength(1));
      expect(runner.callsFor('close'), isEmpty, reason: 'session stays open');

      final gateUpdate = runner.workUpdates.indexWhere(
        (call) => call.length > 1 && call[1] == 'tgdog-gate1',
      );
      expect(gateUpdate, isNot(-1));
      final gateMetadata = runner.metadataOfUpdate(gateUpdate);
      expect(gateMetadata['blocks'], 'tgdog-s');
      expect(gateMetadata['node'], 'tg-1/agent');
      expect(gateMetadata['reason'], startsWith('persist-exhausted:'));
      expect(
        h.transport.flares.where((flare) => flare.name == 'step.gated'),
        hasLength(1),
      );

      h.cursorState.projectUpdate(gated);
      h.owner.flush();
      await _pump();
      expect(_hostBranches(h.root), isEmpty);

      final callCount = runner.calls.length;
      final flareCount = h.transport.flares.length;
      h.registryState.rebuild();
      h.owner.flush();
      await _pump();
      expect(runner.calls, hasLength(callCount));
      expect(h.transport.flares, hasLength(flareCount));
      expect(
        h.transport.flares.where((flare) => flare.name == 'step.persistFailed'),
        hasLength(3),
      );
    });

    test('an invalid advance result is named and supervised before any gate '
        'close or complete write', () async {
      var now = DateTime.utc(2026, 9, 21);
      final runner = RecordingBdRunner(createdId: 'tgdog-unused')
        ..exportBeads = [
          sessionBead(id: 'tgdog-s', workBeadId: 'tg-1'),
          const Bead(
            id: 'tgdog-route-gate',
            issueType: GridIssueTypes.gate,
            status: BeadStatus.open,
            metadata: {
              'rig': stateSubstation,
              'blocks': 'tgdog-s',
              'node': 'tg-1/agent',
              'reason': 'route review requested changes',
            },
          ),
        ];
      final h = _persistHost(runner, clock: () => now);
      addTearDown(() {
        h.owner.dispose();
        h.fakes.ctx.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      for (var attempt = 0; attempt < 3; attempt++) {
        final host = _hostBranch(h.root);
        final state = (host as StatefulBranch).state as CapabilityHostState;
        state.deliverReportForTest(
          const AllocationAdvanced({'source-state': 'accepted'}),
        );
        await _waitUntil(
          () =>
              h.transport.flares
                  .where((flare) => flare.name == 'step.persistFailed')
                  .length ==
              attempt + 1,
          reason: 'invalid result attempt ${attempt + 1} was not flared',
        );

        if (attempt < 2) {
          await _waitUntil(
            () => _stepUpdates(runner, StepState.failed).length == attempt + 1,
            reason: 'invalid result restart ${attempt + 1} was not persisted',
          );
          final failed = _stepUpdates(runner, StepState.failed).last;
          final cooldown = DateTime.parse(
            '${failed[MoleculeStepKeys.cooldownUntil]}',
          );
          now = cooldown.add(const Duration(milliseconds: 1));
          h.cursorState.projectUpdate(failed);
          h.owner.flush();
          await _pump();
        }
      }

      await _waitUntil(
        () => _stepUpdates(runner, StepState.gated).length == 1,
        reason: 'invalid result exhaustion did not park the route',
      );

      final persistFailures = h.transport.flares
          .where((flare) => flare.name == 'step.persistFailed')
          .toList();
      expect(persistFailures, hasLength(3));
      for (final flare in persistFailures) {
        expect(flare.data['op'], 'advance');
        expect(flare.data['error'], contains('source-state'));
        expect(flare.data['error'], contains('tg-1/agent'));
        expect(flare.data['error'], contains('-'));
        expect(flare.data['error'], contains('[a-z0-9_]+'));
      }

      expect(
        _stepUpdates(runner, StepState.complete),
        isEmpty,
        reason: 'validation must precede the complete transition',
      );
      expect(
        runner.callsFor('close'),
        isEmpty,
        reason: 'validation must precede superseded-gate closure',
      );
      expect(
        h.transport.flares.where(
          (flare) => flare.name == 'gate.supersededByAdvance',
        ),
        isEmpty,
      );

      final routeGateUpdates = <Map<String, dynamic>>[];
      final updates = runner.workUpdates;
      for (var i = 0; i < updates.length; i++) {
        if (updates[i][1] == 'tgdog-route-gate') {
          routeGateUpdates.add(runner.metadataOfUpdate(i));
        }
      }
      expect(routeGateUpdates, hasLength(1));
      final exhaustionReason = '${routeGateUpdates.single['reason']}';
      expect(exhaustionReason, startsWith('persist-exhausted:'));
      expect(exhaustionReason, contains('source-state'));
      expect(exhaustionReason, contains('tg-1/agent'));
      expect(exhaustionReason, contains('-'));
      expect(exhaustionReason, contains('[a-z0-9_]+'));

      for (var i = 0; i < updates.length; i++) {
        final metadata = runner.metadataOfUpdate(i);
        expect(metadata.keys, isNot(contains('source-state')));
        expect(
          metadata.keys,
          isNot(contains('grid.result.tg_h1_sagent.source-state')),
        );
      }
    });

    test('true teardown drops persist recovery loudly', () async {
      final runner = _TimeoutCompleteRunner(
        timeoutAttempts: 1,
        completionAttempts: 1,
      );
      final h = _persistHost(runner, clock: () => DateTime.utc(2026, 9, 17));
      var disposed = false;
      addTearDown(() {
        if (!disposed) h.owner.dispose();
        h.fakes.ctx.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final state =
          (_hostBranch(h.root) as StatefulBranch).state as CapabilityHostState;
      state.deliverReportForTest(const AllocationAdvanced({'grade': 'pass'}));
      await runner.barriers[0].entered.future;

      h.owner.dispose();
      disposed = true;
      runner.barriers[0].release.complete();
      await _waitUntil(
        () => h.transport.flares.any(
          (flare) => flare.name == 'step.persistDropped',
        ),
        reason: 'teardown did not surface the recovery drop',
      );

      final dropped = h.transport.flares
          .where((flare) => flare.name == 'step.persistDropped')
          .single;
      expect(dropped.data['op'], 'recover');
      expect(dropped.data['mounted'], 'false');
      expect(dropped.data['scopeCurrent'], 'false');
      expect(_stepUpdates(runner, StepState.failed), isEmpty);
      expect(_stepUpdates(runner, StepState.gated), isEmpty);
      expect(runner.callsFor('create'), isEmpty);
      expect(
        h.transport.flares.where(
          (flare) => flare.name == 'step.persistRecoveryFailed',
        ),
        isEmpty,
      );
    });
  });
}
