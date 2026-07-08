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

import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

/// A terminal leaf (an empty fan-out).
class Leaf extends MultiChildSeed {
  const Leaf({super.key}) : super(children: const []);
}

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
    this.onInitGrid,
    this.onReadyHook,
    this.onTeardownHook,
    GridConfiguration? initial,
  }) : super(initial ?? const GridConfiguration());

  final String rootPath;
  final List<Seed> Function()? assetsBuilder;
  final Seed Function(TreeContext, GridConfiguration)? buildOverride;
  final void Function()? onDidLaunch;
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
  owner.mountRoot(root);
  owner.flush();
}

/// Drains microtasks + one event-loop turn (the coalesced flush + the
/// unawaited kickoff run on microtasks).
Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  group('the observable + provision + master build', () {
    test('runGrid mounts configuration; build sees the config; the config is '
        'ambient below (the delegate is NOT — D-H)', () {
      final probed = <GridConfiguration>[];
      final delegate = RecordingDelegate(
        rootPath: '/home/space',
        assetsBuilder: () => [
          ConfigProbe(probed.add),
        ],
        initial: const GridConfiguration(settings: {'v': 1}),
      );

      final handle = runGrid(delegate);
      addTearDown(handle.teardown);

      // The master build ran with the initial configuration.
      expect(delegate.builtWith.single, const GridConfiguration(settings: {'v': 1}));
      // The probe (inside the built tree) saw the ambient configuration —
      // configuration provision is real and load-bearing. It reads the VALUE,
      // never a handle on the notifier.
      expect(probed.single, const GridConfiguration(settings: {'v': 1}));
    });

    test('the default build returns the §2 shape (RawAssetGrid → Station → '
        'Substations → Substation)', () {
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
                  Substation(
                    name: 'tg',
                    root: '/work/tg',
                    assets: [ScopeProbe(seen)],
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final handle = runGrid(delegate);
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
        const SubstationScope(name: 'tg', root: '/work/tg'),
      );
    });

    test('a bare delegate (no root, no build override) refuses LOUD — there is '
        'no default root', () {
      // The default build calls `root`, which throws (v3 §0: no default root).
      expect(
        () => runGrid(_BareDelegate()),
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
    test('order: didLaunch (pre-tree) → build (mount) → initGrid → onReady',
        () async {
      final delegate = RecordingDelegate();
      final handle = runGrid(delegate);
      addTearDown(handle.teardown);

      // Synchronously after runGrid: pre-tree rail, then mount, then the async
      // kickoff STARTED (initGrid ran up to its await) — but onReady has not
      // fired (it is unawaited, scheduled).
      expect(delegate.events, ['didLaunch', 'build', 'initGrid']);

      await pump();
      // onReady fires once the (default, immediately-completing) initGrid
      // resolves.
      expect(delegate.events, ['didLaunch', 'build', 'initGrid', 'onReady']);
    });

    test('initGrid is UNAWAITED: runGrid returns before it completes; onReady '
        'waits for it', () async {
      final gate = Completer<void>();
      final delegate = RecordingDelegate(onInitGrid: () => gate.future);
      final handle = runGrid(delegate);
      addTearDown(handle.teardown);

      // runGrid returned while initGrid is still suspended on `gate`.
      expect(delegate.events, ['didLaunch', 'build', 'initGrid']);
      await pump();
      expect(delegate.events, isNot(contains('onReady')));

      gate.complete();
      await pump();
      expect(delegate.events.last, 'onReady');
    });

    test('didLaunch failure ABORTS the launch: throws GridHookError, no tree '
        'mounts', () {
      final delegate = RecordingDelegate(
        onDidLaunch: () => throw StateError('boom'),
      );

      expect(
        () => runGrid(delegate),
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

    test('initGrid failure: captured/attributed/loud via onError; onReady is '
        'NOT called; the grid stands', () async {
      final refusals = <GridHookError>[];
      final delegate = RecordingDelegate(
        onInitGrid: () => throw StateError('init blew up'),
      );

      final handle = runGrid(delegate, onError: refusals.add);
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

      final handle = runGrid(delegate, onError: refusals.add);
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
        final handle = runGrid(delegate);
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
      final handle = runGrid(delegate);
      await pump();

      handle.teardown();
      expect(delegate.events, contains('onTeardown'));
      // The tree unmounted (the effect tore down with it).
      expect(disposed, 1);
      // The delegate (the StateNotifier) is disposed.
      expect(delegate.mounted, isFalse);
      expect(handle.isTornDown, isTrue);

      // Idempotent — a second teardown is a no-op (onTeardown runs once).
      handle.teardown();
      expect(disposed, 1);
      expect(
        delegate.events.where((e) => e == 'onTeardown').length,
        1,
      );
    });

    test('onTeardown failure is loud but teardown still completes', () async {
      final refusals = <GridHookError>[];
      var disposed = 0;
      final delegate = RecordingDelegate(
        assetsBuilder: () => [DisposeProbe(() => disposed++)],
        onTeardownHook: () => throw StateError('teardown blew up'),
      );
      final handle = runGrid(delegate, onError: refusals.add);
      await pump();

      handle.teardown();
      expect(refusals.single.hook, 'onTeardown');
      // Teardown proceeded regardless — the effect still tore down.
      expect(disposed, 1);
      expect(delegate.mounted, isFalse);
    });
  });

  group('a watched value re-composes (v3 §1)', () {
    test('emitting a new configuration re-runs the master build with it', () async {
      final probed = <GridConfiguration>[];
      final delegate = RecordingDelegate(
        assetsBuilder: () => [ConfigProbe(probed.add)],
        initial: const GridConfiguration(settings: {'v': 1}),
      );
      final handle = runGrid(delegate);
      addTearDown(handle.teardown);
      await pump();

      expect(delegate.builtWith, [const GridConfiguration(settings: {'v': 1})]);
      expect(probed, [const GridConfiguration(settings: {'v': 1})]);

      delegate.emit(const GridConfiguration(settings: {'v': 2}));
      await pump();

      // build re-ran with the new configuration; the ambient reader saw it too.
      expect(delegate.builtWith, [
        const GridConfiguration(settings: {'v': 1}),
        const GridConfiguration(settings: {'v': 2}),
      ]);
      expect(probed.last, const GridConfiguration(settings: {'v': 2}));
    });
  });

  group('ambient lookups are loud outside a running grid (the guard principle)',
      () {
    test('GridConfiguration.of throws / maybeOf is null when unmounted', () {
      mount(
        _OfProbe((ctx) {
          expect(() => GridConfiguration.of(ctx), throwsStateError);
          expect(GridConfiguration.maybeOf(ctx), isNull);
        }),
      );
    });
  });

  group('the delegate is not ambient (ADR-0008 D-H)', () {
    test('a running grid provides the configuration VALUE, never the delegate '
        '(the StateNotifier) — it is not lookuppable from the tree', () {
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
      final handle = runGrid(delegate);
      addTearDown(handle.teardown);

      expect(seenDelegate, isNull,
          reason: 'the delegate/notifier must not ride the tree (D-H)');
      expect(seenConfig, const GridConfiguration(settings: {'v': 9}),
          reason: 'only the observed configuration value is ambient');
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
