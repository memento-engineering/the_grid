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
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- helpers -----------------------------------------------------------------

Future<String> _readEngineSource(String libRelative) async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:grid_engine/$libRelative'),
  );
  return File(uri!.toFilePath()).readAsStringSync();
}

List<String> _importLines(String src) => src
    .split('\n')
    .where((l) => l.trimLeft().startsWith('import '))
    .toList();

class _RecProcessCap extends ProcessCapability {
  _RecProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) {
    log.add('spawn');
    return RuntimeConfig(
      workDir: ctx.workspaceDir,
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

class _DaemonCap extends ProcessCapability {
  _DaemonCap({this.fresh = false});
  final bool fresh;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
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
  Future<bool> proveFreshness(AdoptFence fence, CapabilityContext ctx) async =>
      fresh;
}

CapabilityContext _capCtx() => CapabilityContext(
  params: const {},
  bead: bead('tg-1'),
  workspaceDir: '/w',
  branch: 'grid/tg-1',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: CancelToken(),
  nodePath: 'tg-1/n',
);

AllocationContext _allocCtx(
  RuntimeProvider transport, {
  StepKind kind = StepKind.daemon,
  bool live = true,
  AdoptFence fence = const AdoptFence(pgid: 1, pid: 2, token: 't'),
}) => AllocationContext(
  capContext: _capCtx(),
  transport: transport,
  address: const AllocationAddress('s', 'tg-1/n'),
  env: const {},
  sink: (_) {},
  fence: fence,
  kind: kind,
  liveness: (_) => live,
);

StepMount _mount() => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  bead: bead('tg-1'),
  nodePath: 'tg-1/agent',
  session: const SessionHandle('tgdog-s'),
  node: const NodeCursor(),
  key: const ValueKey('tg-1/agent#0'),
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Track F/G — D3: the effect layer holds NO writer (structural fence)', () {
    test('allocation.dart imports no writer / notifier / tree / effect-context',
        () async {
      final imports = _importLines(await _readEngineSource('src/sdk/allocation.dart'));
      // The invariant is about IMPORTS — the effect layer cannot even NAME a
      // writer/notifier/tree, so invariant 2 holds by construction (not a wall).
      expect(imports.any((l) => l.contains('genesis_tree')), isFalse,
          reason: 'the effect layer is not a tree node — it holds no TreeContext');
      expect(imports.any((l) => l.contains('station_bead_writer')), isFalse);
      expect(imports.any((l) => l.contains('joined_snapshot_notifier')), isFalse);
      expect(imports.any((l) => l.contains('station_services')), isFalse);
      // Sanity control: it DOES import its legitimate transport (grid_runtime) —
      // proving the fence above is meaningful, not vacuously true on an empty set.
      expect(imports.any((l) => l.contains('grid_runtime')), isTrue);
    });

    test('AllocationContext exposes only the sandboxed shape (no writer field)',
        () {
      final ctx = _allocCtx(FakeRuntimeProvider());
      // Compile-time shape: the effect gets transport (process), a report sink,
      // the sandboxed capContext, address, env, fence, kind, liveness — and NO
      // writer/notifier. Reading these proves the shape.
      expect(ctx.transport, isA<RuntimeProvider>());
      expect(ctx.sink, isA<AllocationSink>());
      expect(ctx.capContext, isA<CapabilityContext>());
      expect(ctx.address.providerName, 's/tg-1/n');
    });
  });

  group('Track F/G — D4: dispose (kill) and detach (leave) are DISTINCT verbs', () {
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
      final left = ProcessAllocation(_RecProcessCap([]), _allocCtx(p1, live: false));
      await left.startOrAdopt();
      await _pump();
      await left.detach();
      expect(p1.stopped, isEmpty, reason: 'detach must NOT stop the group');

      final p2 = FakeRuntimeProvider();
      final killed = ProcessAllocation(_RecProcessCap([]), _allocCtx(p2, live: false));
      await killed.startOrAdopt();
      await _pump();
      await killed.dispose();
      expect(p2.stopped, hasLength(1), reason: 'dispose MUST kill the group');
    });
  });

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
      expect(await didAdopt(live: false, fresh: true), isFalse,
          reason: 'engine pgid-liveness half missing');
      expect(await didAdopt(live: true, fresh: false), isFalse,
          reason: 'capability endpoint/token half missing');
      // Sanity control: BOTH halves present DOES adopt — so the two asserts above
      // are non-vacuous (a mutation dropping a guard would flip one of them).
      expect(await didAdopt(live: true, fresh: true), isTrue);
    });
  });

  group('Track G — the P0 Host juggling is GONE (cleanup fence)', () {
    test('capability_host.dart names no _capCtx / _stepName / _writeSignal / '
        '_writeOutcome / Expando remnant', () async {
      final src = await _readEngineSource('src/formula/capability_host.dart');
      for (final dead in const [
        '_capCtx',
        '_stepName',
        '_writeSignal',
        '_writeOutcome',
        'Expando',
      ]) {
        expect(src.contains(dead), isFalse,
            reason: 'the thin-driver Host must not carry the P0 remnant "$dead"');
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
          child: StableInheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: DateTime(2026)),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: CapabilityHost(
                capability: _RecProcessCap([]),
                mount: _mount(),
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
      // A reported terminal is PERSISTED through the chokepoint — one write, the
      // node cursor advanced. (A mutation dropping the sink→persist wiring writes
      // nothing here.)
      fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      expect(fakes.runner.callsFor('update'), hasLength(1));
      expect(fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'complete'});
      expect(root, isNotNull);
    });
  });
}

/// A no-op service capability for the detach-throws shape test.
class _NoopService extends ServiceCapability {
  @override
  Future<StepOutcome> run(CapabilityContext ctx) async => const Ok();
}
