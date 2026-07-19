// Track J (tg-yl8 / tg-bxu) — the four derailment invariants RE-ANCHORED on
// the NEW composition: the engine work subtree mounted INSIDE the runGrid
// tree (RawAssetGrid → Station → StationWork → Substations → Substation →
// SubstationWork → WorkList), driven end-to-end through the delegate — never
// a kernel-owned TreeOwner. Zero I/O: fake sources, a recording bd chokepoint,
// a fake transport. Every gate carries a positive control so it cannot pass
// vacuously (the at-depth suite's mutation-resistance pattern).
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show Lifecycle, RuntimeConfig, RuntimeEvent;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A writing one-step `code`-shaped circuit: the agent cap spawns through the
/// ambient transport (recorded by [FakeRuntimeProvider]) so mount=spawn is
/// observable through the NEW composition.
class _AgentCap extends engine.ProcessCapability {
  const _AgentCap();
  @override
  RuntimeConfig spawn(TreeContext context, engine.StepArgs args) =>
      RuntimeConfig(
        workDir: context
            .getInheritedSeedOfExactType<engine.Workspace>()!
            .workspaceDir,
        command: 'sh',
        args: const ['-c', 'echo'],
        lifecycle: Lifecycle.oneTurn,
      );
  @override
  engine.StepSignal interpretEvent(RuntimeEvent event) =>
      engine.StepSignal.none;
}

const _code = engine.Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [engine.CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

/// Resolves the ambient [engine.ProcessLeaseVendor] at a work-node context —
/// the tg-2mb witness. `requireProcessLeaseVendor` is exactly what a molecule
/// allocation calls; if StationWork omits the seed (the wedge) it THROWS here,
/// the spawn never happens, and [seen] stays empty.
class _VendorProbeCap extends engine.ProcessCapability {
  const _VendorProbeCap(this.seen);
  final List<engine.ProcessLeaseVendor> seen;
  @override
  RuntimeConfig spawn(TreeContext context, engine.StepArgs args) {
    seen.add(engine.requireProcessLeaseVendor(context));
    return RuntimeConfig(
      workDir: context
          .getInheritedSeedOfExactType<engine.Workspace>()!
          .workspaceDir,
      command: 'sh',
      args: const ['-c', 'echo'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  engine.StepSignal interpretEvent(RuntimeEvent event) =>
      engine.StepSignal.none;
}

/// Records WHICH beads the resolver was asked to root — the mount-boundary
/// witness for the type/ownership gates.
class _RecordingResolver implements engine.SessionResolver {
  _RecordingResolver(this._inner);
  final engine.SessionResolver _inner;
  final List<String> resolved = <String>[];
  @override
  Seed sessionFor({required Bead bead, engine.SessionProjection? session}) {
    resolved.add(bead.id);
    return _inner.sessionFor(bead: bead, session: session);
  }
}

/// Counts builds — the flush-isolation probe (a CONFIG ancestor of the work
/// subtree; a work tick must never rebuild it).
class _BuildProbe extends SingleChildStatelessSeed {
  // `child` is never passed at the call site — probes chain in a `Nest`, which
  // supplies it at fold time.
  // ignore: unused_element_parameter
  const _BuildProbe({required this.builds, super.child, super.key});
  final List<int> builds;
  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    builds.add(1);
    return child;
  }
}

/// The test station: the canonical v3 tree with the work binding mounted —
/// `power_station` authored with name ≠ prefix (`pow`), the Track I ruling.
class _TestDelegate extends GridDelegate {
  _TestDelegate({
    required this.wiring,
    required this.stationProbe,
    required this.substationProbe,
    this.mintMode,
  });

  /// Null ⇒ the unarmed authoring-only mount (H2's shape).
  final StationWorkWiring? wiring;
  final List<int> stationProbe;
  final List<int> substationProbe;

  /// Null ⇒ `const SubstationWork()` — the DEFAULT the baseline test pins
  /// (molecule since the live arm). Non-null ⇒ the explicit opt-out, so the
  /// flat path keeps composition-seam coverage (tg-6gi regression pin).
  final engine.CircuitMintMode? mintMode;

  void emitTick(int n) => state = GridConfiguration(settings: {'tick': '$n'});

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    final w = wiring;
    final mode = mintMode;
    final substations = Substations(
      substations: [
        Substation(
          'power_station',
          '/work/power_station',
          prefix: 'pow',
          assets: [
            Nest(
              children: [
                _BuildProbe(builds: substationProbe, key: const ValueKey('sp')),
              ],
              child: mode == null
                  ? const SubstationWork()
                  : SubstationWork(circuitMintMode: mode),
            ),
          ],
        ),
      ],
    );
    return RawAssetGrid(
      root: '/grid/home',
      assets: [
        Station(
          name: 'space',
          assets: [
            Nest(
              children: [
                _BuildProbe(builds: stationProbe, key: const ValueKey('stp')),
                if (w != null)
                  StationWork(wiring: w, key: const ValueKey('sw')),
              ],
              child: substations,
            ),
          ],
        ),
      ],
    );
  }
}

GraphSnapshot _graph(List<Bead> beads, Set<String> ready) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime(2026),
    );

Bead _bead(String id, {IssueType type = IssueType.task}) =>
    Bead(id: id, issueType: type, status: BeadStatus.open);

Bead _sessionBead(String id, {required String workBeadId}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    engine.SessionBeadKeys.workBead: workBeadId,
    engine.SessionBeadKeys.model: engine.kSessionModelMolecule,
  },
);

Bead _moleculeBead(String id, {required String sessionId}) => Bead(
  id: id,
  issueType: IssueType.molecule,
  status: BeadStatus.open,
  metadata: {'grid.circuit.formula': 'code', 'grid.circuit.session': sessionId},
);

Bead _stepBead(String id, {required String sessionId, required String path}) =>
    Bead(
      id: id,
      issueType: IssueType.step,
      status: BeadStatus.open,
      metadata: {
        'grid.step.id': path.split('/').last,
        'grid.step.capability': path.split('/').last,
        'grid.step.kind': engine.StepKind.job.name,
        'grid.step.path': path,
        'grid.step.session': sessionId,
      },
    );

Future<void> _pump([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxTries = 2000,
}) async {
  for (var i = 0; i < maxTries && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

typedef _Rig = ({
  GridHandle grid,
  _TestDelegate delegate,
  FakeSnapshotSource work,
  FakeSnapshotSource state,
  engine.StationJoinBridge bridge,
  _RecordingResolver resolver,
  Fakes fakes,
  List<int> stationProbe,
  List<int> substationProbe,
});

/// Mounts the FULL new composition via runGrid over fakes — the bridge started
/// first (the pinned ordering's tail: barrier/restart are runner concerns
/// proven in the assembly; here the bridge simply precedes the mount).
_Rig _arm({
  bool armed = true,
  engine.CircuitMintMode? mintMode,
  engine.CapabilityRegistry? registryOverride,
}) {
  final work = FakeSnapshotSource();
  final state = FakeSnapshotSource();
  final bridge = engine.StationJoinBridge(work: work, state: state);
  final fakes = buildFakes();
  fakes.runner.graphApplyIds = const {
    'pow-1': 'tgdog-mol-pow-1',
    'pow-1/agent': 'tgdog-step-pow-1-agent',
  };
  final registry =
      registryOverride ??
      engine.DefaultCapabilityRegistry(
        capabilities: const {'agent': _AgentCap()},
        clock: () => DateTime(2026),
      );
  final resolver = _RecordingResolver(engine.CircuitResolver((_) => _code));
  final stationProbe = <int>[];
  final substationProbe = <int>[];
  final delegate = _TestDelegate(
    wiring: armed
        ? StationWorkWiring(
            notifier: bridge.notifier,
            services: fakes.ctx,
            resolver: resolver,
            registry: registry,
          )
        : null,
    stationProbe: stationProbe,
    substationProbe: substationProbe,
    mintMode: mintMode,
  );
  bridge.start();
  final grid = runGrid(delegate);
  return (
    grid: grid,
    delegate: delegate,
    work: work,
    state: state,
    bridge: bridge,
    resolver: resolver,
    fakes: fakes,
    stationProbe: stationProbe,
    substationProbe: substationProbe,
  );
}

Future<void> _pushMoleculeState(_Rig rig, String workBeadId) async {
  const sessionId = 'tgdog-sess1';
  await _pumpUntil(() => rig.fakes.runner.graphApplyCalls.isNotEmpty);
  await _pumpUntil(() => rig.fakes.runner.callsFor('update').length >= 3);
  rig.state.push(
    _graph([
      _sessionBead(sessionId, workBeadId: workBeadId),
      _moleculeBead('tgdog-mol-$workBeadId', sessionId: sessionId),
      _stepBead(
        'tgdog-step-$workBeadId-agent',
        sessionId: sessionId,
        path: '$workBeadId/agent',
      ),
    ], const {}),
  );
  await _pumpUntil(() => rig.fakes.provider.started.isNotEmpty);
}

void main() {
  group('Track J — the invariants re-anchored on the runGrid composition', () {
    test('the baseline: an owned ready bead mounts THROUGH the composition — '
        'resolver rooted it, the session minted through the chokepoint, the '
        'transport spawned (mount = spawn)', () async {
      final rig = _arm();
      addTearDown(rig.grid.teardown);
      rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
      await _pump();

      // The mount-boundary witness: the ownership axes are name ≠ prefix —
      // the substation is NAMED power_station; the bead carries the pow
      // PREFIX. Mounting proves ownership matched the prefix axis.
      expect(rig.resolver.resolved, ['pow-1']);
      expect(
        const SubstationWork().circuitMintMode,
        engine.CircuitMintMode.molecule,
      );
      await _pumpUntil(() => rig.fakes.runner.graphApplyCalls.isNotEmpty);
      final plainCreates = rig.fakes.runner
          .callsFor('create')
          .where((c) => !c.contains('--graph'));
      expect(
        plainCreates,
        hasLength(1),
        reason: 'the molecule path still creates exactly one session bead',
      );
      final stamp = rig.fakes.runner.metadataOfUpdate(0);
      expect(stamp[engine.SessionBeadKeys.model], engine.kSessionModelMolecule);
      expect(
        rig.fakes.runner.graphApplyCalls,
        hasLength(1),
        reason: 'const SubstationWork must reach the molecule graph pour',
      );
      // The transport spawned the agent step (mount = spawn).
      await _pushMoleculeState(rig, 'pow-1');
      expect(rig.fakes.provider.started, hasLength(1));

      // unmount = kill: tearing the grid down stops the live allocation.
      await rig.grid.teardown();
      await _pump();
      expect(rig.fakes.provider.stopped, isNotEmpty);
    });

    test('tg-2mb: StationWork mounts the ProcessLeaseVendor AMBIENT to the '
        'work subtree — a molecule allocation resolves the vendor '
        '`requireProcessLeaseVendor` needs (the seed StationKernel.start '
        'mounts, restored on the production runGrid seat). Without it the '
        'readiness gate throws `No ProcessLeaseVendor` and the station wedges '
        'to zero; positive control: the probe capability actually spawns.',
        () async {
      final seen = <engine.ProcessLeaseVendor>[];
      final rig = _arm(
        registryOverride: engine.DefaultCapabilityRegistry(
          capabilities: {'agent': _VendorProbeCap(seen)},
          clock: () => DateTime(2026),
        ),
      );
      addTearDown(rig.grid.teardown);
      rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
      await _pump();
      // Drive to the spawn point: the probe cap resolves the vendor at the work
      // node (mount = spawn). With the seed missing, spawn throws and the
      // provider never starts — this push would time out and `seen` stay empty.
      await _pushMoleculeState(rig, 'pow-1');
      expect(
        seen,
        isNotEmpty,
        reason: 'positive control — the probe capability spawned, which means '
            'requireProcessLeaseVendor resolved at the work node',
      );
      expect(
        seen.first,
        isA<engine.StationProcessLeaseVendor>(),
        reason: 'the ambient vendor is the real production vendor '
            '(defaultProcessLeaseVendor), not a stub or a foreign instance',
      );
    });

    test('the FLAT opt-out stays wired at the composition seam: an explicit '
        'CircuitMintMode.flatCursor SubstationWork mounts, mints through the '
        'chokepoint, and spawns exactly like the baseline — the molecule '
        'default flip never strands the opt-out (tg-6gi regression pin; the '
        'engine-level flat/molecule parity is drain_seam_test\'s)', () async {
      final rig = _arm(mintMode: engine.CircuitMintMode.flatCursor);
      addTearDown(rig.grid.teardown);
      rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
      await _pump();

      expect(rig.resolver.resolved, ['pow-1']);
      final plainCreates = rig.fakes.runner
          .callsFor('create')
          .where((c) => !c.contains('--graph'));
      expect(
        plainCreates,
        hasLength(1),
        reason: 'the flat session still mints through StationBeadWriter',
      );
      expect(
        rig.fakes.runner.graphApplyCalls,
        isEmpty,
        reason: 'explicit flatCursor never pours molecule beads',
      );
      final stamp = rig.fakes.runner.metadataOfUpdate(0);
      expect(stamp.containsKey(engine.SessionBeadKeys.model), isFalse);
      expect(rig.fakes.provider.started, hasLength(1));
    });

    test(
      'invariant 1 (flush isolation): a work tick rebuilds NOTHING above the '
      'WorkList — the config ancestors (station + substation assets) hold '
      'still; positive control: a configuration emission rebuilds them',
      () async {
        final rig = _arm();
        addTearDown(rig.grid.teardown);
        rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
        await _pump();
        final stationBuilds = rig.stationProbe.length;
        final substationBuilds = rig.substationProbe.length;
        expect(stationBuilds, greaterThan(0));

        // A work tick: a SECOND bead surfaces ready. Only WorkList (and the
        // new work subtree) reconciles — the probes must not rebuild.
        rig.work.push(
          _graph([_bead('pow-1'), _bead('pow-2')], {'pow-1', 'pow-2'}),
        );
        await _pump();
        expect(rig.resolver.resolved, contains('pow-2')); // the tick LANDED
        expect(
          rig.stationProbe.length,
          stationBuilds,
          reason: 'a snapshot tick must not rebuild the station config axis',
        );
        expect(
          rig.substationProbe.length,
          substationBuilds,
          reason: 'a snapshot tick must not rebuild the substation config axis',
        );

        // Positive control (non-vacuous): a CONFIG emission re-composes the
        // delegate subtree — the probes DO rebuild on the config axis.
        rig.delegate.emitTick(1);
        await _pump();
        expect(rig.stationProbe.length, greaterThan(stationBuilds));
        expect(rig.substationProbe.length, greaterThan(substationBuilds));
      },
    );

    test(
      'invariants 2 + 4 (one chokepoint, pristine source): every mutation the '
      'run produced is a bd call on the RECORDING chokepoint, and none of '
      'them targets a work bead — the work source is never written',
      () async {
        final rig = _arm();
        addTearDown(rig.grid.teardown);
        rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
        await _pump();

        final calls = rig.fakes.runner.calls;
        // Positive control: the chokepoint genuinely wrote (mint + cursor).
        expect(calls, isNotEmpty);
        expect(
          calls.where((c) => c.first == 'update'),
          isNotEmpty,
          reason: 'the host kick must stamp its cursor through the writer',
        );
        // The pristine-source gate (A37): no mutating bd call TARGETS a work
        // bead id. Session/cursor writes target the minted session (the state
        // partition); `pow-…` may appear only as a metadata VALUE
        // (work_bead linkage), never as the mutation target.
        for (final call in calls) {
          final verb = call.first;
          if (verb == 'update' || verb == 'close') {
            expect(
              call[1].startsWith('pow-'),
              isFalse,
              reason:
                  'bd $verb targeted work bead ${call[1]} — the work source '
                  'is READ-ONLY (A37)',
            );
          }
        }
      },
    );

    test('invariant 3 (the mount boundary): a convergence bead and an epic in '
        'the ready set NEVER mount — fail-closed type gate (A41 + the RS-3 '
        'resident narrowing) with the task as the positive control', () async {
      final rig = _arm();
      addTearDown(rig.grid.teardown);
      rig.work.push(
        _graph(
          [
            _bead('pow-1'),
            _bead('pow-2', type: IssueType.convergence),
            _bead('pow-3', type: IssueType.epic),
          ],
          {'pow-1', 'pow-2', 'pow-3'},
        ),
      );
      await _pump();
      expect(rig.resolver.resolved, ['pow-1']);
      await _pushMoleculeState(rig, 'pow-1');
      expect(rig.fakes.provider.started, hasLength(1));
    });

    test('ownership is fail-closed across substation boundaries: a ready bead '
        'with a foreign prefix (neither the name nor the prefix axis) never '
        'mounts', () async {
      final rig = _arm();
      addTearDown(rig.grid.teardown);
      rig.work.push(
        _graph([_bead('pow-1'), _bead('other-9')], {'pow-1', 'other-9'}),
      );
      await _pump();
      expect(rig.resolver.resolved, ['pow-1']);
    });

    test(
      'the unarmed grace (H2\'s shape survives): with no StationWork mounted, '
      'the authored tree stands — nothing resolves, nothing spawns, nothing '
      'writes',
      () async {
        final rig = _arm(armed: false);
        addTearDown(rig.grid.teardown);
        rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
        await _pump();
        expect(rig.stationProbe, isNotEmpty); // the tree DID mount
        expect(rig.resolver.resolved, isEmpty);
        expect(rig.fakes.provider.started, isEmpty);
        expect(rig.fakes.runner.calls, isEmpty);
      },
    );
  });
}
