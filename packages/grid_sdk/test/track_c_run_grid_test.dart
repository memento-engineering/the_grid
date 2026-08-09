// Track C (tg-tv3): runGrid + GridDelegate — the observable, the lifecycle
// rails, the master build.
//
// Model clauses under test (SCRATCH-station-config-model.md v3 §4, ratified):
// - the delegate IS the observable (`StateNotifier<GridConfiguration>`, a thin
//   plain value per Q6); a watched value re-composes the tree (§1).
// - runGrid mounts *delegate provision → configuration provision → build*.
// - the lifecycle rails run in order: didLaunch (pre-tree) → mount → initGrid
//   (post-mount async, UNAWAITED) → onReady (on init success); teardown runs
//   onTeardown then unmounts.
// - hook failures are captured, attributed, and LOUD — a named `GridHookError`
//   (the guard principle); a didLaunch failure ABORTS the launch (throws).
// - the master build default returns the §2 shape (`RawAssetGrid(root, assets)`).
import 'dart:async';
import 'dart:io';

// Narrow shows: the engine + sdk barrels both carry the composition names
// (Station/Substation/SubstationScope), so only the sweep's own types are
// pulled in here.
import 'package:beads_dart/beads_dart.dart' show GraphSnapshot;
import 'package:grid_engine/grid_engine.dart' show GridDiagnosticable;
import 'package:grid_engine/testing.dart' show FakeRuntimeProvider;
import 'package:grid_runtime/grid_runtime.dart'
    show ProcessGroupController, RootCheckout, RuntimeConfig;
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A terminal leaf (an empty fan-out).
class Leaf extends MultiChildSeed {
  const Leaf({super.key}) : super(children: const []);
}

final class _DiagnosableRoot extends Seed with GridDiagnosticable {
  const _DiagnosableRoot();

  @override
  Branch createBranch() => _DiagnosableBranch(this);
}

final class _DiagnosableBranch extends Branch {
  _DiagnosableBranch(super.seed);
}

/// A process-group seam that signals nothing — the sweep's TRANSPORT half is
/// what the teardown rail tests exercise.
class _NoGroups implements ProcessGroupController {
  const _NoGroups();

  @override
  Future<int?> resolvePgid(int pid) async => null;
  @override
  bool processAlive(int pid) => false;
  @override
  bool signalGroup(int pgid, ProcessSignal signal) => false;
  @override
  int currentGroupId() => 999;
}

/// The reconciler under test at the rail: no worktree seam is reachable from
/// `sweepOrphans`, so both refuse loudly if it ever calls them.
RestartReconciler _sweeper() => RestartReconciler(
  listWorktrees: (root) async =>
      throw StateError('sweepOrphans must not list worktrees'),
  reapWorktree: ({required root, required worktree}) async =>
      throw StateError('sweepOrphans must not reap worktrees'),
  workRoot: const RootCheckout(
    path: '/root',
    defaultBranch: 'main',
    substation: 'proj',
  ),
  groups: const _NoGroups(),
  freshnessBarrier: () async {},
  stateSnapshot: () => GraphSnapshot.fromParts(
    beads: const [],
    dependencies: const [],
    readyIds: const [],
    capturedAt: DateTime(2026, 7),
  ),
);

/// Captures the ambient configuration it mounts under (subscribes to it, so a
/// re-emission rebuilds this probe). Configuration is the ONLY sanctioned
/// observation — the delegate itself is not ambient (ADR-0008 D-H).
class ConfigProbe extends StatelessSeed {
  const ConfigProbe(this.sink, {super.key});

  final void Function(GridConfiguration config) sink;

  @override
  Seed build(TreeContext context) {
    sink(GridConfiguration.of(context));
    return const Leaf();
  }
}

/// Captures the ambient composition scopes (proves the default build returns a
/// real §2 tree).
class ScopeProbe extends StatelessSeed {
  const ScopeProbe(this.seen, {super.key});

  final List<({GridRoot? grid, StationScope? station, SubstationScope? sub})>
  seen;

  @override
  Seed build(TreeContext context) {
    seen.add((
      grid: GridRoot.maybeOf(context),
      station: StationScope.maybeOf(context),
      sub: SubstationScope.maybeOf(context),
    ));
    return const Leaf();
  }
}

/// A StatefulSeed that records its dispose — proves teardown unmounts the tree.
class DisposeProbe extends StatefulSeed {
  const DisposeProbe(this.onDispose, {super.key});

  final void Function() onDispose;

  @override
  State<DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<DisposeProbe> {
  @override
  Seed build(TreeContext context) => const Leaf();

  @override
  void dispose() => seed.onDispose();
}

/// A configurable delegate that records every rail invocation and lets a test
/// inject failures / async control into any rail.
class RecordingDelegate extends GridDelegate {
  RecordingDelegate({
    this.rootPath = '/grid/home',
    this.assetsBuilder,
    this.buildOverride,
    this.onDidLaunch,
    this.onBoot,
    this.onInitGrid,
    this.onReadyHook,
    this.onTeardownHook,
    GridConfiguration? initial,
  }) : super(initial ?? const GridConfiguration());

  final String rootPath;
  final List<Seed> Function()? assetsBuilder;
  final Seed Function(TreeContext, GridConfiguration)? buildOverride;
  final void Function()? onDidLaunch;
  final Future<void> Function(GridConfiguration)? onBoot;
  final Future<void> Function()? onInitGrid;
  final void Function()? onReadyHook;
  final void Function()? onTeardownHook;

  /// The rails, in call order.
  final events = <String>[];

  /// Every configuration `build` was called with.
  final builtWith = <GridConfiguration>[];

  /// Emits a new configuration (the protected `state` setter, reachable from a
  /// subclass) — the observable's write path.
  void emit(GridConfiguration config) => state = config;

  @override
  String get root => rootPath;

  @override
  List<Seed> get assets => assetsBuilder?.call() ?? const <Seed>[];

  @override
  Seed build(TreeContext context, GridConfiguration configuration) {
    events.add('build');
    builtWith.add(configuration);
    if (buildOverride != null) return buildOverride!(context, configuration);
    return super.build(context, configuration);
  }

  @override
  void didLaunch() {
    events.add('didLaunch');
    onDidLaunch?.call();
  }

  @override
  Future<void> boot(GridConfiguration configuration) async {
    events.add('boot');
    if (onBoot != null) await onBoot!(configuration);
  }

  @override
  Future<void> initGrid() async {
    events.add('initGrid');
    if (onInitGrid != null) await onInitGrid!();
  }

  @override
  void onReady() {
    events.add('onReady');
    onReadyHook?.call();
  }

  @override
  void onTeardown() {
    events.add('onTeardown');
    onTeardownHook?.call();
  }
}

/// Mounts [root] offline (for the Track-B-style loud-refusal checks that don't
/// need runGrid).
void mount(Seed root) {
  final owner = TreeOwner();
  owner.mountRoot(ProviderScope(child: root));
  owner.flush();
}

/// Drains microtasks + one event-loop turn (the coalesced flush + the
/// unawaited kickoff run on microtasks).
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('the observable + provision + master build', () {
    test('runGrid mounts configuration; build sees the config; the config is '
        'ambient below (the delegate is NOT — D-H)', () async {
      final probed = <GridConfiguration>[];
      final delegate = RecordingDelegate(
        rootPath: '/home/space',
        assetsBuilder: () => [ConfigProbe(probed.add)],
        initial: const GridConfiguration(settings: {'v': 1}),
      );

      final handle = await runGrid(delegate);
      addTearDown(handle.teardown);

      // The master build ran with the initial configuration.
      expect(
        delegate.builtWith.single,
        const GridConfiguration(settings: {'v': 1}),
      );
      // The probe (inside the built tree) saw the ambient configuration —
      // configuration provision is real and load-bearing. It reads the VALUE,
      // never a handle on the notifier.
      expect(probed.single, const GridConfiguration(settings: {'v': 1}));
    });

    test('the default build returns the §2 shape (RawAssetGrid → Station → '
        'Substations → Substation)', () async {
      final seen =
          <({GridRoot? grid, StationScope? station, SubstationScope? sub})>[];
      final delegate = RecordingDelegate(
        rootPath: '/home/space',
        assetsBuilder: () => [
          Station(
            name: 'MBP',
            assets: [
              Substations(
                substations: [
                  Substation('tg', '/work/tg', assets: [ScopeProbe(seen)]),
                ],
              ),
            ],
          ),
        ],
      );

      final handle = await runGrid(delegate);
      addTearDown(handle.teardown);

      // The default build produced a real §2 tree: the probe sees the whole
      // ancestry (deployment → machine → project).
      expect(seen.single.grid, const GridRoot(path: '/home/space'));
      expect(
        seen.single.station,
        const StationScope(name: 'MBP', root: '/home/space'),
      );
      expect(
        seen.single.sub,
        const SubstationScope(name: 'tg', root: '/work/tg', prefix: 'tg'),
      );
    });

    test('a bare delegate (no root, no build override) refuses LOUD — there is '
        'no default root', () async {
      // The default build calls `root`, which throws (v3 §0: no default root).
      await expectLater(
        runGrid(_BareDelegate()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no default root'),
          ),
        ),
      );
    });
  });

  group('the lifecycle rails', () {
    test(
      'order: didLaunch → boot → build (mount) → initGrid → onReady',
      () async {
        final delegate = RecordingDelegate();
        final handle = await runGrid(delegate);
        addTearDown(handle.teardown);

        // Synchronously after runGrid: pre-tree rail, then mount, then the async
        // kickoff STARTED (initGrid ran up to its await) — but onReady has not
        // fired (it is unawaited, scheduled).
        expect(delegate.events, ['didLaunch', 'boot', 'build', 'initGrid']);

        await pump();
        // onReady fires once the (default, immediately-completing) initGrid
        // resolves.
        expect(delegate.events, [
          'didLaunch',
          'boot',
          'build',
          'initGrid',
          'onReady',
        ]);
      },
    );

    test('initGrid is UNAWAITED: runGrid returns before it completes; onReady '
        'waits for it', () async {
      final gate = Completer<void>();
      final delegate = RecordingDelegate(onInitGrid: () => gate.future);
      final handle = await runGrid(delegate);
      addTearDown(handle.teardown);

      // runGrid returned while initGrid is still suspended on `gate`.
      expect(delegate.events, ['didLaunch', 'boot', 'build', 'initGrid']);
      await pump();
      expect(delegate.events, isNot(contains('onReady')));

      gate.complete();
      await pump();
      expect(delegate.events.last, 'onReady');
    });

    test('didLaunch failure ABORTS the launch: throws GridHookError, no tree '
        'mounts', () async {
      final delegate = RecordingDelegate(
        onDidLaunch: () => throw StateError('boom'),
      );

      await expectLater(
        runGrid(delegate),
        throwsA(
          isA<GridHookError>()
              .having((e) => e.hook, 'hook', 'didLaunch')
              .having((e) => e.delegateType, 'delegateType', RecordingDelegate)
              .having((e) => e.cause, 'cause', isA<StateError>()),
        ),
      );
      // The tree never mounted — build was never reached.
      expect(delegate.events, ['didLaunch']);
    });

    test(
      'boot receives the initial configuration and gates first mount exactly '
      'once',
      () async {
        final gate = Completer<void>();
        GridConfiguration? received;
        final initial = const GridConfiguration(settings: {'phase': 'boot'});
        final delegate = RecordingDelegate(
          initial: initial,
          onBoot: (configuration) {
            received = configuration;
            return gate.future;
          },
        );

        final launch = runGrid(delegate);
        await pump();
        expect(received, initial);
        expect(delegate.events, ['didLaunch', 'boot']);
        expect(delegate.events, isNot(contains('build')));

        gate.complete();
        final handle = await launch;
        addTearDown(handle.teardown);
        expect(delegate.events.where((event) => event == 'boot'), hasLength(1));
        expect(delegate.events, containsAllInOrder(['boot', 'build']));
      },
    );

    test('boot failure is attributed, mounts nothing, and disposes the '
        'delegate', () async {
      final delegate = RecordingDelegate(
        onBoot: (_) async => throw StateError('assembly failed'),
      );

      await expectLater(
        runGrid(delegate),
        throwsA(
          isA<GridHookError>()
              .having((error) => error.hook, 'hook', 'boot')
              .having(
                (error) => error.delegateType,
                'delegateType',
                RecordingDelegate,
              )
              .having((error) => error.cause, 'cause', isA<StateError>()),
        ),
      );
      expect(delegate.events, ['didLaunch', 'boot']);
      expect(delegate.mounted, isFalse);
    });

    test(
      'hot restart boots a fresh delegate before swap and preserves the live '
      'delegate when fresh boot fails',
      () async {
        final first = RecordingDelegate();
        final fresh = <RecordingDelegate>[];
        var refuse = true;
        RecordingDelegate factory() {
          final next = RecordingDelegate(
            onBoot: (_) async {
              if (refuse) throw StateError('fresh assembly failed');
            },
          );
          fresh.add(next);
          return next;
        }

        // The COMMIT seam: each swap notification, with whether the retired
        // delegate was still alive at notify time (it must be — the corpse is
        // disposed only by the re-composition, after the shell re-pointed).
        final swaps = <({GridDelegate next, bool retiredAlive})>[];
        final handle = await runGrid(
          first,
          delegateFactory: factory,
          onDelegateSwapped: (next) =>
              swaps.add((next: next, retiredAlive: first.mounted)),
        );
        addTearDown(handle.teardown);
        await expectLater(
          handle.hotRestart(),
          throwsA(
            isA<GridHookError>().having((error) => error.hook, 'hook', 'boot'),
          ),
        );
        expect(first.mounted, isTrue);
        expect(fresh.single.events, ['boot']);
        expect(fresh.single.mounted, isFalse);
        // A FAILED restart never commits: the shell is never told to re-point,
        // so its read surface stays on the live (old) delegate.
        expect(swaps, isEmpty);

        refuse = false;
        final report = await handle.hotRestart();
        expect(
          report.generation,
          1,
          reason: 'a failed boot does not advance it',
        );
        expect(first.mounted, isFalse);
        expect(fresh.last.events, containsAllInOrder(['boot', 'build']));
        expect(
          fresh.last.events.where((event) => event == 'boot'),
          hasLength(1),
        );
        // The successful restart commits EXACTLY once, with the booted fresh
        // delegate, while the retired one was still alive.
        expect(swaps, hasLength(1));
        expect(identical(swaps.single.next, fresh.last), isTrue);
        expect(swaps.single.retiredAlive, isTrue);
      },
    );

    test(
      'teardown during the restart boot: the fresh delegate is disposed and '
      'the holders never swap',
      () async {
        final first = RecordingDelegate();
        final gate = Completer<void>();
        final fresh = <RecordingDelegate>[];
        RecordingDelegate factory() {
          final next = RecordingDelegate(onBoot: (_) => gate.future);
          fresh.add(next);
          return next;
        }

        final swaps = <GridDelegate>[];
        final handle = await runGrid(
          first,
          delegateFactory: factory,
          onDelegateSwapped: swaps.add,
        );
        await pump();

        // The restart suspends on the fresh delegate's awaited boot …
        final restart = handle.hotRestart();
        await pump();
        expect(fresh.single.events, ['boot']);

        // … teardown lands mid-boot …
        await handle.teardown();
        expect(first.mounted, isFalse, reason: 'teardown disposed the live '
            'delegate');

        // … and the boot then completing must NOT commit: the fresh delegate
        // is disposed, the swap seam never fires, no post-mount rail runs.
        gate.complete();
        await expectLater(
          restart,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('tore down during the restart boot'),
            ),
          ),
        );
        expect(fresh.single.mounted, isFalse, reason: 'the fresh delegate is '
            'disposed, never adopted');
        expect(swaps, isEmpty, reason: 'the commit seam never fired');
        expect(fresh.single.events, ['boot'], reason: 'no initGrid/onReady '
            'kickoff on the refused restart');
      },
    );

    test('initGrid failure: captured/attributed/loud via onError; onReady is '
        'NOT called; the grid stands', () async {
      final refusals = <GridHookError>[];
      final delegate = RecordingDelegate(
        onInitGrid: () => throw StateError('init blew up'),
      );

      final handle = await runGrid(delegate, onError: refusals.add);
      addTearDown(handle.teardown);
      await pump();

      expect(refusals.single.hook, 'initGrid');
      expect(refusals.single.cause, isA<StateError>());
      expect(delegate.events, isNot(contains('onReady')));
      // A post-mount rail failure does not tear the running grid down.
      expect(handle.isTornDown, isFalse);
    });

    test('onReady failure: captured/attributed/loud; non-aborting', () async {
      final refusals = <GridHookError>[];
      final delegate = RecordingDelegate(
        onReadyHook: () => throw StateError('ready blew up'),
      );

      final handle = await runGrid(delegate, onError: refusals.add);
      addTearDown(handle.teardown);
      await pump();

      expect(refusals.single.hook, 'onReady');
      expect(handle.isTornDown, isFalse);
    });

    test('the DEFAULT onError is loud: an unhandled rail refusal surfaces to '
        'the zone', () async {
      final zoneErrors = <Object>[];
      await runZonedGuarded(() async {
        final delegate = RecordingDelegate(
          onInitGrid: () => throw StateError('init blew up'),
        );
        // No onError → the default rethrows into the current zone.
        final handle = await runGrid(delegate);
        addTearDown(handle.teardown);
        await pump();
      }, (error, stack) => zoneErrors.add(error));

      expect(zoneErrors.single, isA<GridHookError>());
      expect((zoneErrors.single as GridHookError).hook, 'initGrid');
    });
  });

  group('teardown', () {
    test('runs onTeardown then unmounts the tree and disposes the delegate; '
        'idempotent', () async {
      var disposed = 0;
      final delegate = RecordingDelegate(
        assetsBuilder: () => [DisposeProbe(() => disposed++)],
      );
      final handle = await runGrid(delegate);
      await pump();

      await handle.teardown();
      expect(delegate.events, contains('onTeardown'));
      // The tree unmounted (the effect tore down with it).
      expect(disposed, 1);
      // The delegate (the StateNotifier) is disposed.
      expect(delegate.mounted, isFalse);
      expect(handle.isTornDown, isTrue);

      // Idempotent — a second teardown is a no-op (onTeardown runs once).
      await handle.teardown();
      expect(disposed, 1);
      expect(delegate.events.where((e) => e == 'onTeardown').length, 1);
    });

    test('onTeardown failure is loud but teardown still completes', () async {
      final refusals = <GridHookError>[];
      var disposed = 0;
      final delegate = RecordingDelegate(
        assetsBuilder: () => [DisposeProbe(() => disposed++)],
        onTeardownHook: () => throw StateError('teardown blew up'),
      );
      final handle = await runGrid(delegate, onError: refusals.add);
      await pump();

      await handle.teardown();
      expect(refusals.single.hook, 'onTeardown');
      // Teardown proceeded regardless — the effect still tore down.
      expect(disposed, 1);
      expect(delegate.mounted, isFalse);
    });
  });

  group('teardown — the orphan sweep', () {
    test(
      'the sweep runs AFTER the tree unmounted, and teardown awaits it',
      () async {
        final order = <String>[];
        final provider = FakeRuntimeProvider();
        addTearDown(provider.close);
        // A session the transport still holds when the tree comes down — the
        // agent that spawned into the teardown window.
        await provider.start(
          'st-1/tg-gpg/agent',
          const RuntimeConfig(workDir: '/tmp', command: 'sh'),
        );

        final delegate = RecordingDelegate(
          assetsBuilder: () => [DisposeProbe(() => order.add('unmount'))],
        );
        final handle = await runGrid(
          delegate,
          orphanSweep: () => _sweeper().sweepOrphans(
            transport: provider,
            sessionPrefix: 'st-',
            onOrphan: (_) => order.add('sweep'),
            pollInterval: const Duration(milliseconds: 5),
          ),
        );
        await pump();

        await handle.teardown();

        // The rail order: the tree unmounted BEFORE the sweep reconciled — the
        // stragglers only exist once the kills are in flight.
        expect(order.first, 'unmount');
        expect(order, contains('sweep'));
        expect(provider.stopped, contains('st-1/tg-gpg/agent'));
        expect(
          provider.listRunning('st-'),
          isEmpty,
          reason: 'zero-expected after teardown — no agent survives `down`',
        );
      },
    );

    test('the sweep runs on the LIVE delegate — dispose follows the '
        'sweep', () async {
      // The sweep is the reap on the delegate's boot-assembled runtime, and
      // dispose unwinds exactly that machinery (a StateNotifier's state
      // throws after dispose): a teardown that disposed first would serve
      // the sweep off a corpse and silently reopen the orphan window.
      final order = <String>[];
      final delegate = RecordingDelegate();
      final handle = await runGrid(
        delegate,
        orphanSweep: () async =>
            order.add(delegate.mounted ? 'sweep-live' : 'sweep-on-corpse'),
      );
      await pump();

      await handle.teardown();

      expect(order, ['sweep-live']);
      expect(delegate.mounted, isFalse, reason: 'disposed after the sweep');
    });

    test('teardown is idempotent — the sweep runs exactly once', () async {
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      await provider.start(
        'st-1/tg-gpg/agent',
        const RuntimeConfig(workDir: '/tmp', command: 'sh'),
      );
      final handle = await runGrid(
        RecordingDelegate(),
        orphanSweep: () => _sweeper().sweepOrphans(
          transport: provider,
          sessionPrefix: 'st-',
          onOrphan: (_) {},
          pollInterval: const Duration(milliseconds: 5),
        ),
      );
      await pump();

      await handle.teardown();
      await handle.teardown();

      expect(provider.stopped, ['st-1/tg-gpg/agent']);
    });

    test('a THROWING sweep is LOUD (GridHookError on hook orphanSweep) and '
        'teardown still completes', () async {
      final refusals = <GridHookError>[];
      var disposed = 0;
      final delegate = RecordingDelegate(
        assetsBuilder: () => [DisposeProbe(() => disposed++)],
      );
      final handle = await runGrid(
        delegate,
        onError: refusals.add,
        orphanSweep: () async => throw StateError('the state store blew up'),
      );
      await pump();

      await handle.teardown();

      expect(refusals.single.hook, 'orphanSweep');
      expect(disposed, 1, reason: 'the tree still unmounted');
      expect(handle.isTornDown, isTrue);
    });

    test(
      'a station with no sweep wired tears down unchanged (the null default)',
      () async {
        var disposed = 0;
        final handle = await runGrid(
          RecordingDelegate(
            assetsBuilder: () => [DisposeProbe(() => disposed++)],
          ),
        );
        await pump();

        await handle.teardown();

        expect(disposed, 1);
        expect(handle.isTornDown, isTrue);
      },
    );
  });

  group('a watched value re-composes (v3 §1)', () {
    test('projects every completed flush before the runner callback', () async {
      final projector = TreeProjector();
      final snapshots = <Object>[];
      final order = <String>[];
      var closed = false;
      projector.snapshots.listen((_) {
        snapshots.add(projector.latest!);
        order.add('project');
      }, onDone: () => closed = true);
      final delegate = RecordingDelegate(
        initial: const GridConfiguration(settings: <String, Object?>{'v': 1}),
        buildOverride: (_, _) => const _DiagnosableRoot(),
      );

      final handle = await runGrid(
        delegate,
        treeProjector: projector,
        onFlushed: () => order.add('callback'),
      );

      expect(projector.latest, isNotNull);
      expect(snapshots, hasLength(1));
      expect(order, <String>['project', 'callback']);

      delegate.emit(
        const GridConfiguration(settings: <String, Object?>{'v': 2}),
      );
      await pump();

      expect(snapshots, hasLength(2));
      expect(order, <String>['project', 'callback', 'project', 'callback']);

      await handle.teardown();
      await pump();
      expect(closed, isFalse, reason: 'the runner owns the projector lifetime');
      projector.dispose();
    });

    test(
      'emitting a new configuration re-runs the master build with it',
      () async {
        final probed = <GridConfiguration>[];
        final delegate = RecordingDelegate(
          assetsBuilder: () => [ConfigProbe(probed.add)],
          initial: const GridConfiguration(settings: {'v': 1}),
        );
        final handle = await runGrid(delegate);
        addTearDown(handle.teardown);
        await pump();

        expect(delegate.builtWith, [
          const GridConfiguration(settings: {'v': 1}),
        ]);
        expect(probed, [
          const GridConfiguration(settings: {'v': 1}),
        ]);

        delegate.emit(const GridConfiguration(settings: {'v': 2}));
        await pump();

        // build re-ran with the new configuration; the ambient reader saw it too.
        expect(delegate.builtWith, [
          const GridConfiguration(settings: {'v': 1}),
          const GridConfiguration(settings: {'v': 2}),
        ]);
        expect(probed.last, const GridConfiguration(settings: {'v': 2}));
      },
    );
  });

  group(
    'ambient lookups are loud outside a running grid (the guard principle)',
    () {
      test('GridConfiguration.of throws / maybeOf is null when unmounted', () {
        mount(
          _OfProbe((ctx) {
            expect(() => GridConfiguration.of(ctx), throwsStateError);
            expect(GridConfiguration.maybeOf(ctx), isNull);
          }),
        );
      });
    },
  );

  group('the delegate is not ambient (ADR-0008 D-H)', () {
    test('a running grid provides the configuration VALUE, never the delegate '
        '(the StateNotifier) — it is not lookuppable from the tree', () async {
      GridDelegate? seenDelegate;
      GridConfiguration? seenConfig;
      final delegate = RecordingDelegate(
        assetsBuilder: () => [
          _RawLookupProbe((ctx) {
            // The framework must not have provided the delegate ambiently: a
            // consumer that reached the notifier could snapshot its `.state`.
            seenDelegate = ctx.getInheritedSeedOfExactType<GridDelegate>();
            // The configuration VALUE, however, IS ambient (the observed read).
            seenConfig = GridConfiguration.maybeOf(ctx);
          }),
        ],
        initial: const GridConfiguration(settings: {'v': 9}),
      );
      final handle = await runGrid(delegate);
      addTearDown(handle.teardown);

      expect(
        seenDelegate,
        isNull,
        reason: 'the delegate/notifier must not ride the tree (D-H)',
      );
      expect(
        seenConfig,
        const GridConfiguration(settings: {'v': 9}),
        reason: 'only the observed configuration value is ambient',
      );
    });
  });
}

/// A delegate that authors neither `root` nor `build` — the bare-misuse case.
class _BareDelegate extends GridDelegate {}

/// Runs [probe] against a live TreeContext at build time.
class _OfProbe extends StatelessSeed {
  const _OfProbe(this.probe);

  final void Function(TreeContext) probe;

  @override
  Seed build(TreeContext context) {
    probe(context);
    return const Leaf();
  }
}

/// Probes the tree with the RAW effect verb (not any SDK accessor) to prove the
/// delegate is not provided ambiently — a test-only reach-in, exactly the
/// snapshot a consumer must not be handed.
class _RawLookupProbe extends StatelessSeed {
  const _RawLookupProbe(this.probe);

  final void Function(TreeContext) probe;

  @override
  Seed build(TreeContext context) {
    probe(context);
    return const Leaf();
  }
}
