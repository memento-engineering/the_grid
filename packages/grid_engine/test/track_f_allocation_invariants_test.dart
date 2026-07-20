// Track F + G (ADR-0009) — the Allocation-layer invariants + structural fences,
// mutation-resistant, each with a sanity control. These LOCK the decisions the
// refactor rests on:
//
//  - D3 "the sandbox dissolves; invariants hold by LAYERING + a single
//    write-locus": the effect layer (allocation.dart) is NEVER handed a writer/
//    notifier — a STRUCTURAL fact (import fence), not a wall.
//  - D4 "dispose is not overloaded": dispose (kill) and detach (leave) are
//    distinct verbs — a mutation aliasing them FAILS.
//  - D5 "no-adopt-on-faith": an adopt with a missing freshness half spawns fresh
//    — the test is non-vacuous (both-halves-true DOES adopt: the sanity control).
//  - Track G cleanup: the Host's P0 juggling (`_capCtx`/`_stepName`/`_writeSignal`
//    /`_writeOutcome`/`Expando`) is GONE.
//
// Plus the three-tree interlock end-to-end at the effect depth: Host CREATES the
// Allocation → kicks startOrAdopt → the Allocation REPORTS → the Host PERSISTS
// off-build through the one chokepoint.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

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
const _interlockStepBeadId = 'tgdog-step1';

final _interlockCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _interlockStepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _interlockStepBeadId},
  cursor: const {},
);

/// The REAL transport-backed lease vendor (tg-h4u) — routes the molecule-mode
/// `_RecProcessCap` through the SAME `RuntimeProvider` machinery the retired
/// flat `ProcessAllocation` drove.
const _interlockVendor = SelfManagedProcessVendor(
  spawn: stationProcessSpawner,
  dispatch: stationProcessDispatcher,
);

// --- helpers -----------------------------------------------------------------

Future<String> _readEngineSource(String libRelative) async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:grid_engine/$libRelative'),
  );
  return File(uri!.toFilePath()).readAsStringSync();
}

List<String> _importLines(String src) =>
    src.split('\n').where((l) => l.trimLeft().startsWith('import ')).toList();

class _RecProcessCap extends ProcessCapability {
  _RecProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    log.add('spawn');
    return RuntimeConfig(
      workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
      command: 'sh',
      args: const ['-c', 'echo hi'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

class _WorkDirCap extends ProcessCapability {
  const _WorkDirCap(this.workDir);

  final String workDir;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: workDir,
    command: 'sh',
    args: const ['-c', 'echo hi'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

class _DaemonCap extends ProcessCapability {
  _DaemonCap({this.fresh = false});
  final bool fresh;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'sleep 999'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when active => StepSignal.ready,
    _ => StepSignal.none,
  };

  @override
  Future<bool> proveFreshness(
    AdoptFence fence,
    TreeContext context,
    StepArgs args,
  ) async => fresh;
}

/// The ambient values the old CapabilityContext threaded, now read from the
/// tree (the context rip-out): the workspace the spawn runs in.
FakeTreeContext _treeCtx() => FakeTreeContext(
  values: {
    Workspace: testWorkspace('tg-1', workspaceDir: '/w', branch: 'grid/tg-1'),
  },
);

AllocationContext _allocCtx(
  RuntimeProvider transport, {
  StepKind kind = StepKind.daemon,
  bool live = true,
  AdoptFence fence = const AdoptFence(pgid: 1, pid: 2, token: 't'),
}) => AllocationContext(
  treeContext: _treeCtx(),
  args: stepArgs('tg-1/n'),
  transport: transport,
  address: const AllocationAddress('s', 'tg-1/n'),
  env: const {},
  sink: (_) {},
  fence: fence,
  kind: kind,
  liveness: (_) => live,
);

/// The circuit the mounted `agent` step belongs to (`StepMount.circuit`, tg-o90).
const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _mount() => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: 'tg-1/agent',
  circuit: _circuit,
  circuitPath: 'tg-1',
  session: const SessionHandle('tgdog-s'),
  node: const NodeCursor(),
  key: const ValueKey('tg-1/agent#0.0'),
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Track F/G — D3: the effect layer holds NO writer (structural fence)', () {
    test(
      'allocation.dart imports no writer / notifier / station-services',
      () async {
        final imports = _importLines(
          await _readEngineSource('src/sdk/allocation.dart'),
        );
        // The invariant is about IMPORTS — the effect layer cannot even NAME a
        // writer/notifier, so invariant 2 holds by construction (not a wall).
        // (The context rip-out, ADR-0009 D3: depending on the TREE is the norm —
        // the effect reads its ambient values through the host's TreeContext, so
        // genesis_tree is now a LEGITIMATE import; the write locus stays out.)
        expect(imports.any((l) => l.contains('station_bead_writer')), isFalse);
        expect(
          imports.any((l) => l.contains('joined_snapshot_notifier')),
          isFalse,
        );
        expect(imports.any((l) => l.contains('station_services')), isFalse);
        // Sanity control: it DOES import its legitimate transport (grid_runtime)
        // and the tree it reads ambient values from (genesis_tree) — proving the
        // fence above is meaningful, not vacuously true on an empty set.
        expect(imports.any((l) => l.contains('grid_runtime')), isTrue);
        expect(imports.any((l) => l.contains('genesis_tree')), isTrue);
      },
    );

    test(
      'AllocationContext exposes only the effect-layer shape (no writer field)',
      () {
        final ctx = _allocCtx(FakeRuntimeProvider());
        // Compile-time shape: the effect gets transport (process), a report sink,
        // the host's tree context + the per-step args, address, env, fence, kind,
        // liveness — and NO writer/notifier. Reading these proves the shape.
        expect(ctx.transport, isA<RuntimeProvider>());
        expect(ctx.sink, isA<AllocationSink>());
        expect(ctx.treeContext, isA<TreeContext>());
        expect(ctx.args, isA<StepArgs>());
        expect(ctx.address.providerName, 's/tg-1/n');
      },
    );
  });

  group(
    'Track F/G — D4: dispose (kill) and detach (leave) are DISTINCT verbs',
    () {
      test('a job/service is not detachable and its detach() THROWS (never an '
          'overloaded dispose)', () {
        final svc = ServiceAllocation(
          _NoopService(),
          _allocCtx(FakeRuntimeProvider(), kind: StepKind.job),
        );
        expect(svc.isDetachable, isFalse);
        expect(svc.detach, throwsA(isA<UnsupportedError>()));
      });

      test('ProcessAllocation.detach LEAVES the group; dispose KILLS it — a '
          'mutation aliasing them fails this pair', () async {
        final p1 = FakeRuntimeProvider();
        final left = ProcessAllocation(
          _RecProcessCap([]),
          _allocCtx(p1, live: false),
        );
        await left.startOrAdopt();
        await _pump();
        await left.detach();
        expect(p1.stopped, isEmpty, reason: 'detach must NOT stop the group');

        final p2 = FakeRuntimeProvider();
        final killed = ProcessAllocation(
          _RecProcessCap([]),
          _allocCtx(p2, live: false),
        );
        await killed.startOrAdopt();
        await _pump();
        await killed.dispose();
        expect(p2.stopped, hasLength(1), reason: 'dispose MUST kill the group');
      });
    },
  );

  group('Track F/G — D5: no-adopt-on-faith is non-vacuous', () {
    Future<bool> didAdopt({required bool live, required bool fresh}) async {
      final provider = FakeRuntimeProvider();
      final alloc = ProcessAllocation(
        _DaemonCap(fresh: fresh),
        _allocCtx(provider, live: live),
      );
      await alloc.startOrAdopt();
      await _pump();
      return alloc.adopted;
    }

    test('either freshness half missing → spawn (no adopt); BOTH present → adopt '
        '(the sanity control proves the guard is real)', () async {
      expect(
        await didAdopt(live: false, fresh: true),
        isFalse,
        reason: 'engine pgid-liveness half missing',
      );
      expect(
        await didAdopt(live: true, fresh: false),
        isFalse,
        reason: 'capability endpoint/token half missing',
      );
      // Sanity control: BOTH halves present DOES adopt — so the two asserts above
      // are non-vacuous (a mutation dropping a guard would flip one of them).
      expect(await didAdopt(live: true, fresh: true), isTrue);
    });
  });

  group('Track G — the P0 Host juggling is GONE (cleanup fence)', () {
    test('capability_host.dart names no _capCtx / _stepName / _writeSignal / '
        '_writeOutcome / Expando remnant', () async {
      final src = await _readEngineSource('src/circuit/capability_host.dart');
      for (final dead in const [
        '_capCtx',
        '_stepName',
        '_writeSignal',
        '_writeOutcome',
        'Expando',
      ]) {
        expect(
          src.contains(dead),
          isFalse,
          reason: 'the thin-driver Host must not carry the P0 remnant "$dead"',
        );
      }
      // Sanity control: it DOES drive an Allocation now (the new shape) — so the
      // absence above is the refactor, not an empty/renamed file.
      expect(src.contains('Allocation'), isTrue);
      expect(src.contains('startOrAdopt'), isTrue);
    });
  });

  group('Track F — the three-tree interlock at the effect depth', () {
    test('the Host CREATES the Allocation, kicks startOrAdopt, and a reported '
        'terminal PERSISTS through the one chokepoint (off-build)', () async {
      final fakes = buildFakes();
      final owner = TreeOwner();
      final root = owner.mountRoot(
        InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: DateTime(2026)),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              // The workspace is an AMBIENT value now (mounted by SessionScope
              // in the real tree) — the capability's spawn reads it. The
              // molecule ambients (InheritedCircuit, R2; a ProcessLeaseVendor,
              // tg-h4u) are likewise every host's requirement now.
              child: InheritedSeed<Workspace>(
                value: testWorkspace('tg-1', workspaceDir: '/w'),
                child: InheritedSeed<InheritedCircuit>(
                  value: _interlockCircuit,
                  child: InheritedSeed<ProcessLeaseVendor>(
                    value: _interlockVendor,
                    child: CapabilityHost(
                      capability: _RecProcessCap([]),
                      mount: _mount(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      await _pump();

      // The Allocation was created + spawned (the interlock kicked).
      expect(fakes.provider.started, hasLength(1));
      // The `SessionStarted` handshake `stationProcessSpawner`'s acquire hook
      // waits on to resolve its `ProcessHandle` before dispatch can observe a
      // terminal event.
      fakes.provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
      );
      await _pump();
      fakes.runner.calls.clear();
      // A reported terminal is PERSISTED through the chokepoint — one write,
      // targeting the step's OWN bead (R5b). (A mutation dropping the
      // sink→persist wiring writes nothing here.)
      fakes.provider.emit(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
      );
      await _pump();
      final updates = fakes.runner.callsFor('update');
      expect(updates, hasLength(1));
      expect(updates.single[1], _interlockStepBeadId);
      expect(
        fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.state],
        'complete',
      );
      expect(root, isNotNull);
    });

    test(
      'ProcessAllocation refuses a workDir outside the ambient Workspace before start',
      () async {
        final provider = FakeRuntimeProvider();
        addTearDown(provider.close);
        final reports = <AllocationReport>[];
        final alloc = ProcessAllocation(
          const _WorkDirCap('/grid/main-checkout'),
          AllocationContext(
            treeContext: FakeTreeContext(
              values: {
                Workspace: testWorkspace(
                  'tg-1',
                  workspaceDir: '/grid/workspaces/tg-1',
                ),
              },
            ),
            args: stepArgs('tg-1/critic'),
            transport: provider,
            address: const AllocationAddress('sess-1', 'tg-1/critic'),
            env: const {},
            sink: reports.add,
            kind: StepKind.job,
          ),
        );

        await alloc.startOrAdopt();
        await _pump();

        expect(provider.started, isEmpty);
        expect(reports, hasLength(1));
        expect(
          reports.single,
          isA<AllocationFailed>().having(
            (f) => f.reason,
            'reason',
            contains('refused process workDir outside workspace'),
          ),
        );
      },
    );

    test(
      'ProcessAllocation accepts the workspace root and descendants',
      () async {
        for (final workDir in const [
          '/grid/workspaces/tg-1',
          '/grid/workspaces/tg-1/packages/grid_runtime',
        ]) {
          final provider = FakeRuntimeProvider();
          addTearDown(provider.close);
          final reports = <AllocationReport>[];
          final alloc = ProcessAllocation(
            _WorkDirCap(workDir),
            AllocationContext(
              treeContext: FakeTreeContext(
                values: {
                  Workspace: testWorkspace(
                    'tg-1',
                    workspaceDir: '/grid/workspaces/tg-1',
                  ),
                },
              ),
              args: stepArgs('tg-1/critic'),
              transport: provider,
              address: AllocationAddress('sess-1', 'tg-1/critic-$workDir'),
              env: const {},
              sink: reports.add,
              kind: StepKind.job,
            ),
          );

          await alloc.startOrAdopt();
          await _pump();

          expect(provider.started, hasLength(1));
          expect(provider.started.single.config.workDir, workDir);
          expect(reports.whereType<AllocationFailed>(), isEmpty);
        }
      },
    );
  });
}

/// A no-op service capability for the detach-throws shape test.
class _NoopService extends ServiceCapability {
  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async =>
      const Ok();
}
