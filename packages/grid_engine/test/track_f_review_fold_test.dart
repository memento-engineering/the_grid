// ADR-0009 adversarial-review FOLD — the two concrete findings from the
// read-only Explore refute-review, turned into regression tests:
//
//  1. VACUOUSNESS: the allocation-level `_terminal` latch and the Host-level
//     `_completed` latch mutually masked each other — track_e's "two terminals
//     write once" passed as long as EITHER survived, so neither was tested in
//     isolation. These two tests exercise each latch ALONE.
//  2. LEAK-SAFETY: the adopt halves were asymmetrically wireable (reconciler
//     adoptProof injectable, Host liveness not) → half-enabling adopt double-runs.
//     StationServices now carries the liveness seam; this proves it flows to the
//     mount-time adopt (co-wireable), with a sanity control (unwired → spawn).
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- capabilities ------------------------------------------------------------

/// A job capability that COUNTS `result()` reads, so a duplicate terminal that
/// slipped the allocation latch would be observable (result read twice).
class _ResultCountingCap extends ProcessCapability {
  int resultCalls = 0;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
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

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    resultCalls++;
    return {'n': '$resultCalls'};
  }
}

/// A daemon capability whose endpoint/token proof always passes (the domain
/// adopt half), so the engine liveness half is the only variable under test.
class _AlwaysFreshDaemon extends ProcessCapability {
  final log = <String>[];

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    log.add('spawn');
    return RuntimeConfig(
      workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
      command: 'sh',
      args: const ['-c', 'sleep 999'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

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
  ) async =>
      true;
}

// --- helpers -----------------------------------------------------------------

/// The ambient values the old CapabilityContext threaded, now read from the
/// tree (the context rip-out): the workspace the spawn runs in.
FakeTreeContext _treeCtx() => FakeTreeContext(
  values: {
    Workspace: testWorkspace('tg-1', workspaceDir: '/w', branch: 'grid/tg-1'),
  },
);

AllocationContext _allocCtx(RuntimeProvider transport, AllocationSink sink) =>
    AllocationContext(
      treeContext: _treeCtx(),
      args: stepArgs('tg-1/agent'),
      transport: transport,
      address: const AllocationAddress('s', 'tg-1/agent'),
      env: const {},
      sink: sink,
    );

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// An StationServices over the fakes with an explicit [liveness] seam (the live-arm
/// adopt half). Null ⇒ the Host uses `neverLive` (no mount-time adopt).
StationServices _ctxWithLiveness(Fakes fakes, {AllocationLiveness? liveness}) =>
    StationServices(
      provider: fakes.ctx.provider,
      writer: fakes.ctx.writer,
      stateSubstation: fakes.ctx.stateSubstation,
      liveness: liveness,
    );

StepMount _daemonMount() => StepMount(
  step: const CapabilityStep(
    stepId: 'harness',
    capabilityId: 'harness',
    kind: StepKind.daemon,
  ),
  nodePath: 'tg-1/harness',
  session: const SessionHandle('tgdog-s'),
  // A prior incarnation's identity (the fence) — so adopt has something to prove.
  node: const NodeCursor(pgid: 200, pid: 201, token: 't'),
  key: const ValueKey('tg-1/harness#0'),
);

Branch _hostBranch(Branch root) {
  Branch? found;
  void walk(Branch b) {
    if (b.seed is CapabilityHost) found = b;
    b.visitChildren(walk);
  }

  walk(root);
  return found!;
}

CapabilityHostState _mountDaemonHost(
  TreeOwner owner,
  Fakes fakes, {
  AllocationLiveness? liveness,
}) {
  final root = owner.mountRoot(
    InheritedSeed<StationServices>(
      value: _ctxWithLiveness(fakes, liveness: liveness),
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: DateTime(2026)),
        child: InheritedSeed<ServiceBundle>(
          value: const ServiceBundle(),
          // The workspace is an AMBIENT value now (mounted by SessionScope in
          // the real tree) — the daemon's spawn reads it with the effect verb.
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1', workspaceDir: '/w'),
            child: CapabilityHost(
              capability: _AlwaysFreshDaemon(),
              mount: _daemonMount(),
            ),
          ),
        ),
      ),
    ),
  );
  // ignore: invalid_use_of_protected_member
  return (_hostBranch(root) as StatefulBranch).state as CapabilityHostState;
}

void main() {
  group('review fold — vacuousness: each terminal latch in ISOLATION', () {
    test('the ALLOCATION latch alone: two terminals → ONE AllocationCompleted '
        'report AND capability.result() read exactly once', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final cap = _ResultCountingCap();
      final alloc =
          ProcessAllocation(cap, _allocCtx(provider, reports.add));
      await alloc.startOrAdopt();
      await _pump();

      // Two terminal events straight to the allocation's handler (bypassing the
      // Host entirely, so ONLY the allocation `_terminal` latch is under test).
      alloc.deliverEventForTest(const Exited(name: 's/tg-1/agent', exitCode: 0));
      alloc.deliverEventForTest(const Exited(name: 's/tg-1/agent', exitCode: 0));
      await _pump();

      expect(reports.whereType<AllocationCompleted>(), hasLength(1),
          reason: 'the allocation latch dedupes the terminal');
      expect(cap.resultCalls, 1,
          reason: 'result() is read once (a non-idempotent result must not '
              'double-fire) — this fails if the _terminal latch is removed');
    });

    test('the HOST latch alone: two AllocationCompleted reports delivered '
        'straight into the sink → ONE chokepoint write', () async {
      final fakes = buildFakes();
      final owner = TreeOwner();
      final state = _mountDaemonHost(owner, fakes); // liveness unwired
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      await _pump();
      fakes.runner.calls.clear();

      // Two terminal REPORTS straight to the Host sink (bypassing the allocation
      // latch), so ONLY the Host `_completed` latch is under test.
      state.deliverReportForTest(const AllocationCompleted());
      state.deliverReportForTest(const AllocationCompleted());
      await _pump();

      expect(fakes.runner.callsFor('update'), hasLength(1),
          reason: 'the Host _completed latch dedupes — fails if it is removed');
    });
  });

  group('review fold — leak-safety: the adopt halves are SYMMETRICALLY '
      'wireable (StationServices.liveness)', () {
    test('liveness WIRED (live arm) → the Host ADOPTS at mount (no respawn)',
        () async {
      final fakes = buildFakes();
      final owner = TreeOwner();
      final state = _mountDaemonHost(owner, fakes, liveness: (_) => true);
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      await _pump();

      // Both halves proven (StationServices.liveness=true + the daemon's endpoint
      // proof) → the survivor is reattached, NOT respawned. This is the mount
      // half that was previously unwireable (the review footgun): now it fires.
      expect(fakes.provider.started, isEmpty, reason: 'adopt must not respawn');
      expect(state, isNotNull);
    });

    test('liveness UNWIRED (P1 default) → the Host SPAWNS fresh (no adopt) — the '
        'sanity control proving the wired case is non-vacuous', () async {
      final fakes = buildFakes();
      final owner = TreeOwner();
      _mountDaemonHost(owner, fakes); // liveness null → neverLive
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      await _pump();

      expect(fakes.provider.started, hasLength(1),
          reason: 'no liveness half → no mount-time adopt → spawn fresh (P1)');
    });
  });
}
