// Hot-RELOAD / hot-RESTART of a JIT station: the re-composition ADOPTS every
// live node. The witness is the transport itself — FakeRuntimeProvider records
// every spawn (`started`) and every kill (`stopped`), so "the running agent
// survived" is an assertion, not a story. Zero I/O.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart' as engine;
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart'
    show Lifecycle, RuntimeConfig, RuntimeEvent;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// The agent capability: mount = spawn through the recorded transport.
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

/// Records WHICH beads the resolver was asked to root — the no-new-work witness.
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

/// Counts builds — the "the master build RE-RAN" probe.
class _BuildProbe extends SingleChildStatelessSeed {
  // ignore: unused_element_parameter
  const _BuildProbe({required this.builds, super.child, super.key});
  final List<int> builds;
  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    builds.add(1);
    return child;
  }
}

/// Throws only when the test flips [shouldThrow]; initial mount stays valid.
class _ThrowOnBuildSeed extends StatelessSeed {
  const _ThrowOnBuildSeed(this.shouldThrow);

  final bool Function() shouldThrow;

  @override
  Seed build(TreeContext context) {
    if (shouldThrow()) {
      throw StateError('fake post-swap rebuild failure');
    }
    return const RawAssetGrid(root: '/grid/home');
  }
}

class _ThrowingReloadDelegate extends GridDelegate {
  bool failOnBuild = false;

  @override
  Seed build(TreeContext context, GridConfiguration configuration) =>
      _ThrowOnBuildSeed(() => failOnBuild);
}

/// The test station — the canonical v3 tree, with the rails recorded so a
/// restart's rail contract is assertable.
class _TestDelegate extends GridDelegate {
  _TestDelegate({
    required this.wiring,
    required this.substationProbe,
    required this.launches,
    required this.inits,
  });

  final StationWorkWiring wiring;
  final List<int> substationProbe;
  final List<String> launches;
  final List<String> inits;

  @override
  void didLaunch() => launches.add('didLaunch');

  @override
  Future<void> initGrid() async => inits.add('initGrid');

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
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
              child: const SubstationWork(),
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
                StationWork(wiring: wiring, key: const ValueKey('sw')),
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

Bead _bead(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

Future<void> _pump([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

typedef _Rig = ({
  GridHandle grid,
  List<_TestDelegate> delegates,
  FakeSnapshotSource work,
  _RecordingResolver resolver,
  Fakes fakes,
  List<int> substationProbe,
  List<String> launches,
  List<String> inits,
});

/// Mounts the full composition via runGrid over fakes, with the delegate built
/// by a FACTORY the handle can re-run.
_Rig _arm({bool withFactory = true}) {
  final work = FakeSnapshotSource();
  final state = FakeSnapshotSource();
  final bridge = engine.StationJoinBridge(work: work, state: state);
  final fakes = buildFakes();
  final registry = engine.DefaultCapabilityRegistry(
    capabilities: const {'agent': _AgentCap()},
    clock: () => DateTime(2026),
  );
  final resolver = _RecordingResolver(engine.CircuitResolver((_) => _code));
  final substationProbe = <int>[];
  final launches = <String>[];
  final inits = <String>[];
  final delegates = <_TestDelegate>[];
  // The runner-level wiring is built ONCE and captured by the factory closure —
  // exactly as a real runner's `main()` builds it once and the factory re-uses
  // it. A restart re-runs the DELEGATE, never the transports.
  final wiring = StationWorkWiring(
    notifier: bridge.notifier,
    services: fakes.ctx,
    resolver: resolver,
    registry: registry,
  );

  _TestDelegate build() {
    final delegate = _TestDelegate(
      wiring: wiring,
      substationProbe: substationProbe,
      launches: launches,
      inits: inits,
    );
    delegates.add(delegate);
    return delegate;
  }

  bridge.start();
  final grid = runGrid(build(), delegateFactory: withFactory ? build : null);
  return (
    grid: grid,
    delegates: delegates,
    work: work,
    resolver: resolver,
    fakes: fakes,
    substationProbe: substationProbe,
    launches: launches,
    inits: inits,
  );
}

void main() {
  group('the dev-mode re-composition ADOPTS, never kills', () {
    test(
      'hot RELOAD re-runs the master build and ADOPTS the running agent',
      () async {
        final rig = _arm();
        addTearDown(rig.grid.teardown);
        rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
        await _pump();
        expect(rig.fakes.provider.started, hasLength(1)); // mount = spawn
        final buildsBefore = rig.substationProbe.length;
        final writesBefore = rig.fakes.runner.calls.length;

        final report = await rig.grid.hotReload();
        await _pump();

        expect(report.mode, ReassembleMode.reload);
        expect(report.generation, 1);
        expect(report.rebuiltBranches, greaterThan(0));
        // The master build RE-RAN (a changed build body takes effect)…
        expect(rig.substationProbe.length, greaterThan(buildsBefore));
        // …and the live agent was ADOPTED: no kill (ADR-0009 D4 — dispose = KILL)
        // and no respawn (no rework-from-top).
        expect(rig.fakes.provider.stopped, isEmpty);
        expect(rig.fakes.provider.started, hasLength(1));
        // NO NEW TRIGGER: nothing new resolved, nothing new was written.
        expect(rig.resolver.resolved, ['pow-1']);
        expect(rig.fakes.runner.calls, hasLength(writesBefore));
      },
    );

    test(
      'post-swap flush throw refuses reload and leaves the grid alive',
      () async {
        Object? uncaught;
        StackTrace? uncaughtStack;
        ReassembleReport? report;
        final delegate = _ThrowingReloadDelegate();
        final grid = runGrid(delegate);
        addTearDown(grid.teardown);

        await runZonedGuarded(
          () async {
            delegate.failOnBuild = true;
            report = await grid.hotReload();
            await _pump();
          },
          (error, stackTrace) {
            uncaught = error;
            uncaughtStack = stackTrace;
          },
        );

        expect(uncaught, isNull, reason: '$uncaughtStack');
        expect(grid.isTornDown, isFalse);
        final refused = report!;
        expect(refused, isA<ReassembleReportRefused>());
        expect(refused.refused, isTrue);
        expect(refused.reason, 'post_swap_recompose_failed');
        expect(refused.requiresBounce, isTrue);
        expect(refused.error, contains('bounce the station'));
        expect(refused.details, contains('fake post-swap rebuild failure'));
      },
    );

    test('hot RESTART re-runs the delegate FACTORY and STILL adopts', () async {
      final rig = _arm();
      addTearDown(rig.grid.teardown);
      rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
      await _pump();
      final first = rig.delegates.single;
      final writesBefore = rig.fakes.runner.calls.length;

      final report = await rig.grid.hotRestart();
      await _pump();

      expect(report.mode, ReassembleMode.restart);
      // A FRESH delegate drives the tree; the retired one is disposed…
      expect(rig.delegates, hasLength(2));
      expect(identical(rig.delegates.last, first), isFalse);
      expect(
        first.mounted,
        isFalse,
        reason: 'the retired delegate is disposed',
      );
      // …the POST-MOUNT rails ran on the fresh delegate, and `didLaunch` — the
      // pre-tree, terminal rail — did NOT (the tree never re-mounted).
      expect(rig.inits, ['initGrid', 'initGrid']);
      expect(rig.launches, ['didLaunch']);
      // …and the session's agent is still the SAME running process.
      expect(rig.fakes.provider.stopped, isEmpty);
      expect(rig.fakes.provider.started, hasLength(1));
      expect(rig.resolver.resolved, ['pow-1']);
      expect(rig.fakes.runner.calls, hasLength(writesBefore));
    });

    test('POSITIVE CONTROL: a real unmount DOES kill (the probe is not '
        'vacuous)', () async {
      final rig = _arm();
      rig.work.push(_graph([_bead('pow-1')], {'pow-1'}));
      await _pump();
      expect(rig.fakes.provider.stopped, isEmpty);

      await rig.grid.teardown();
      await _pump();

      expect(rig.fakes.provider.stopped, isNotEmpty);
    });

    test('hotRestart with NO delegateFactory refuses LOUDLY', () async {
      final rig = _arm(withFactory: false);
      addTearDown(rig.grid.teardown);
      expect(rig.grid.hotRestart, throwsA(isA<StateError>()));
    });

    test('both verbs refuse LOUDLY after teardown', () async {
      final rig = _arm();
      await rig.grid.teardown();
      expect(rig.grid.hotReload, throwsA(isA<StateError>()));
      expect(rig.grid.hotRestart, throwsA(isA<StateError>()));
    });
  });
}
