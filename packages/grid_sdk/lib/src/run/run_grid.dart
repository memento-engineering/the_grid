import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:state_notifier/state_notifier.dart';

import 'configuration.dart';
import 'grid_delegate.dart';
import 'reassemble.dart';

/// Launches a grid from [delegate] — **the entry point** (v3 §4 / GLOSSARY R15:
/// the delegation pattern's `runGrid(delegate)`). The framework root is
/// `final`; all station behaviour enters through the delegate.
///
/// It runs the lifecycle rails around a single mounted tree:
///
///  1. `delegate.didLaunch()` — **pre-tree**, synchronous. A failure is
///     terminal: it is wrapped as a [GridHookError] and **thrown** (the launch
///     aborts loudly — nothing mounts).
///  2. **Mount the tree**: *configuration provision → `delegate.build`*. The
///     delegate does **not** ride the tree — `runGrid` holds it and drives the
///     configuration scope directly (by construction), because a
///     `StateNotifier`'s `.state` must never be reachable as a snapshot
///     (ADR-0008 D-H). Only its observed `GridConfiguration` is ambient,
///     provided just below as `InheritedSeed<GridConfiguration>` and re-provided
///     on every emission; `delegate.build(context, configuration)` roots the
///     station subtree. A configuration re-emission re-composes that subtree on
///     a coalesced microtask flush (the reactive loop, mirroring the kernel).
///  3. **Kick off** `delegate.initGrid()` — post-mount, async, **unawaited**;
///     on success `delegate.onReady()` fires. A failure in either is captured,
///     attributed, and reported loudly via [onError] — the running grid stands.
///
/// Returns a [GridHandle]: `await teardown()` runs `onTeardown`, unmounts the
/// tree (every mounted effect tears down with it), then runs [orphanSweep] —
/// the teardown-vs-spawn reap. [orphanSweep] is null by default (a station with
/// no process transport has nothing to sweep); a runner with work machinery
/// passes `work.sweepOrphans`.
///
/// [onError] receives the captured refusals from the **post-mount** rails
/// (`initGrid` / `onReady` / `onTeardown`). It defaults to rethrowing into the
/// current zone (loud). A `didLaunch` failure does not go through [onError] —
/// it is thrown from `runGrid` directly (the caller cannot proceed with a grid
/// that never mounted).
///
/// [onFlushed] fires once after EVERY completed tree flush (the initial mount
/// flush included) — the seam a runner hangs off-tree post-flush machinery on
/// (the engine's `StationDriver.afterFlush` cooldown/unclaimed re-scans,
/// tg-yl8). Nullable and opinion-free: `runGrid` neither knows nor cares what
/// rides it.
///
/// [delegateFactory] arms the dev-mode hot-RESTART ([GridHandle.hotRestart]):
/// it is re-invoked to build a FRESH delegate from the same runner inputs
/// (flags, env, wiring, harness registry). A JIT station (started with
/// `--enable-vm-service`) passes it; an AOT station omits it and `hotRestart`
/// then refuses LOUDLY. [GridHandle.hotReload] needs no factory.
GridHandle runGrid(
  GridDelegate delegate, {
  void Function(GridHookError refusal)? onError,
  void Function()? onFlushed,
  Future<void> Function()? orphanSweep,
  GridDelegate Function()? delegateFactory,
}) {
  final report = onError ?? _rethrowToZone;

  // 1. Pre-tree rail — synchronous; a failure aborts the launch (loud throw).
  try {
    delegate.didLaunch();
  } catch (e, st) {
    throw GridHookError('didLaunch', delegate.runtimeType, e, st);
  }

  // 2. Mount: configuration provision → build. The delegate is held here (by
  //    construction), never provided ambiently (D-H).
  final owner = TreeOwner();
  // The dev-mode reassemble bus: held HERE and handed to the scope by
  // construction — never ambient (D-H), exactly like the delegate.
  final reassemble = ReassembleBus();
  final handle = GridHandle._(
    owner,
    delegate,
    report,
    onFlushed,
    orphanSweep,
    reassemble,
    delegateFactory,
  );
  // Wire the flush trigger BEFORE mounting: the first build runs synchronously
  // in mountRoot with no markNeedsRebuild (the config scope assigns its
  // baseline directly, never setState during mount), so onNeedsFlush cannot
  // fire during it.
  handle._wireFlush();
  owner.mountRoot(
    _GridConfigurationScope(delegate: delegate, reassemble: reassemble),
  );
  owner.flush();
  onFlushed?.call();

  // 3. Post-mount async kickoff — unawaited by the caller; onReady chained
  // after it; both surfaced loud on failure.
  unawaited(_kickoff(delegate, report));

  return handle;
}

/// The default [runGrid] error sink: surface a refusal loudly into the current
/// zone (the uncaught-error handler) so it is never swallowed.
void _rethrowToZone(GridHookError refusal) =>
    Zone.current.handleUncaughtError(refusal, refusal.causeStackTrace);

/// Runs the post-mount async rails in order: `initGrid` (unawaited kickoff) →
/// `onReady` (only on success). Each failure is a captured, attributed, loud
/// [GridHookError].
Future<void> _kickoff(
  GridDelegate delegate,
  void Function(GridHookError) report,
) async {
  try {
    await delegate.initGrid();
  } catch (e, st) {
    report(GridHookError('initGrid', delegate.runtimeType, e, st));
    return; // init failed loudly → the grid is not "ready".
  }
  try {
    delegate.onReady();
  } catch (e, st) {
    report(GridHookError('onReady', delegate.runtimeType, e, st));
  }
}

/// A running grid — the handle [runGrid] returns.
///
/// The grid runs its reactive loop autonomously: a configuration re-emission
/// dirties the configuration scope and flushes on a coalesced microtask
/// (mirroring `StationKernel` — many dirties between turns collapse into one
/// flush). `root.markNeedsRebuild()` is never called; only the observing scope
/// dirties.
///
/// Call [teardown] to run the delegate's `onTeardown` rail and unmount the
/// tree. Idempotent.
class GridHandle {
  GridHandle._(
    this._owner,
    this._delegate,
    this._report,
    this._onFlushed,
    this._orphanSweep,
    this._reassemble,
    this._delegateFactory,
  );

  final TreeOwner _owner;

  /// The LIVE delegate. Mutable: a hot-RESTART retires the running delegate for
  /// a fresh one from the factory, and the rails (`onTeardown`/`dispose`) must
  /// then run on the live one — never on the corpse.
  GridDelegate _delegate;

  final void Function(GridHookError) _report;

  /// The runner's post-flush seam (see [runGrid]'s `onFlushed`).
  final void Function()? _onFlushed;

  /// The teardown-vs-spawn orphan reap — null when the station has no process
  /// transport to sweep.
  final Future<void> Function()? _orphanSweep;

  /// The off-tree bus a dev-mode re-composition rides (see [hotReload]).
  final ReassembleBus _reassemble;

  /// The hot-RESTART factory — null when the station never armed one.
  final GridDelegate Function()? _delegateFactory;

  /// Callers awaiting the NEXT completed flush (one per in-flight reassemble),
  /// completed with the rebuilt-branch count — or failed LOUDLY if the grid
  /// tears down before the flush lands (never a future that hangs forever).
  final List<Completer<int>> _flushWaiters = <Completer<int>>[];

  /// The monotonic re-composition counter; 0 is the launch baseline.
  int _generation = 0;

  bool _tornDown = false;
  bool _flushScheduled = false;
  Future<void>? _teardown;

  /// Coalesces dirties into one microtask flush. Wired before mount so the
  /// synchronous first build never trips it.
  void _wireFlush() {
    _owner.onNeedsFlush = () {
      if (_flushScheduled || _tornDown) return;
      _flushScheduled = true;
      scheduleMicrotask(() {
        _flushScheduled = false;
        if (_tornDown) {
          _failWaiters();
          return;
        }
        final rebuilt = _owner.flush();
        _onFlushed?.call();
        _completeWaiters(rebuilt.length);
      });
    };
  }

  void _completeWaiters(int rebuilt) {
    final waiters = List<Completer<int>>.of(_flushWaiters);
    _flushWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete(rebuilt);
    }
  }

  void _failWaiters() {
    final waiters = List<Completer<int>>.of(_flushWaiters);
    _flushWaiters.clear();
    for (final waiter in waiters) {
      waiter.completeError(
        StateError('the grid tore down before the flush landed'),
      );
    }
  }

  /// Whether [teardown] has run.
  bool get isTornDown => _tornDown;

  /// **HOT-RELOAD** (dev mode): re-runs the master build on the SAME delegate,
  /// so code swapped into the running isolate by the VM's `reloadSources` takes
  /// effect — WITHOUT a down/up bounce.
  ///
  /// It dirties exactly ONE branch: the configuration scope (the same node a
  /// configuration emission dirties). `root.markNeedsRebuild()` is never called
  /// (ADR-0007 Decision 2). Keyed reconcile then ADOPTS every live node: nothing
  /// unmounts, so no `CapabilityHost` disposes, so no `Allocation` is killed
  /// (ADR-0009 D4 — `dispose` = KILL) and every live session's running agent
  /// survives with its cursor untouched. Only a genuinely re-keyed node
  /// re-mounts.
  ///
  /// It is NOT a work trigger: it re-composes the tree over the SAME observed
  /// frontier, so it enqueues nothing, mints no bead and spawns nothing (a bead
  /// going ready in the owned store stays the only work-intake trigger).
  ///
  /// KNOWN LIMIT (genesis semantics, not a bug): a `const`-authored subtree is
  /// pruned by the identical-skip fast path, so its `build` bodies do not re-run
  /// — the same as for a configuration emission. Changed *capability/service*
  /// bodies need no rebuild at all: `reloadSources` swaps the method bodies and
  /// the next call runs the new code.
  ///
  /// The future completes when the resulting flush lands. Torn down → a LOUD
  /// [StateError].
  Future<ReassembleReport> hotReload() {
    _refuseIfTornDown('hotReload');
    final generation = ++_generation;
    return _reassemble0(
      ReloadRequest(generation),
      ReassembleMode.reload,
      generation,
    );
  }

  /// **HOT-RESTART** (dev mode): re-runs the [runGrid] `delegateFactory` and
  /// re-composes on the FRESH delegate — the Flutter hot-restart shape, minus
  /// the teardown.
  ///
  /// Sessions and work are ADOPTED, not re-minted: the work-bead keys are bead
  /// ids and the session cursor is untouched, so `SessionScope` adopts the
  /// persisted session bead (ADR-0008 D-2 — adopt-or-mint ONCE) and the running
  /// allocations are never disposed (ADR-0009 D4).
  ///
  /// The retired delegate is unsubscribed then `dispose`d; its `onTeardown` rail
  /// does NOT run (the grid did not tear down — the delegate was replaced). The
  /// fresh delegate takes the POST-MOUNT rails (`initGrid` → `onReady`,
  /// unawaited, loud on failure) but **not `didLaunch`**: that rail is defined
  /// pre-tree and terminal ("nothing mounts" on failure), and a restart mounts
  /// no new tree — re-running it would let a fresh delegate's throw kill a live
  /// station with agents mid-build.
  ///
  /// Launched without a `delegateFactory` → a LOUD [StateError] (never a silent
  /// no-op).
  Future<ReassembleReport> hotRestart() {
    _refuseIfTornDown('hotRestart');
    final factory = _delegateFactory;
    if (factory == null) {
      throw StateError(
        'GridHandle.hotRestart: this grid was launched without a '
        '`delegateFactory` — there is no factory to re-run. Pass '
        '`runGrid(delegate, delegateFactory: () => MyDelegate(...))` to arm '
        'hot-restart; `hotReload` needs no factory.',
      );
    }
    final next = factory();
    final generation = ++_generation;
    // The LIVE delegate from here on: teardown must reach this one, never the
    // corpse the configuration scope is about to retire.
    _delegate = next;
    final done = _reassemble0(
      RestartRequest(generation, next),
      ReassembleMode.restart,
      generation,
    );
    // The post-mount rails on the FRESH delegate, in runGrid's own order.
    unawaited(_kickoff(next, _report));
    return done;
  }

  /// Emits [request] on the bus the configuration scope observes — dirtying
  /// that ONE branch — and reports what the resulting flush rebuilt.
  Future<ReassembleReport> _reassemble0(
    ReassembleRequest request,
    ReassembleMode mode,
    int generation,
  ) {
    final completer = Completer<int>();
    _flushWaiters.add(completer);
    _reassemble.request(request);
    return completer.future.then(
      (rebuilt) => ReassembleReport(
        mode: mode,
        generation: generation,
        rebuiltBranches: rebuilt,
      ),
    );
  }

  void _refuseIfTornDown(String verb) {
    if (_tornDown) {
      throw StateError(
        'GridHandle.$verb: the grid is torn down — there is no tree to '
        're-compose (LOUD, never a silent no-op).',
      );
    }
  }

  /// Tears the grid down: runs `onTeardown` (loud on failure, non-aborting),
  /// unmounts the tree (every mounted effect tears down), disposes the delegate,
  /// and ENDS with the ORPHAN SWEEP when one is wired.
  ///
  /// **`await` it.** Unmount = kill, but the kill chain is fire-and-forget
  /// (`CapabilityHost.dispose` → `unawaited(allocation.dispose())` →
  /// `unawaited(transport.stop(...))`), so when the tree finishes unmounting the
  /// kills are merely IN FLIGHT — a runner that exits here sends no SIGTERM at
  /// all, and an effect that was itself mid-spawn can land afterwards (the
  /// observed orphan: an agent spawned moments before `down`, alive after the
  /// lock released). The returned future completes only once the sweep has
  /// reconciled the station against zero-expected. A runner that drops this
  /// future exits back into that window.
  ///
  /// The rails through `_owner.dispose()` still run SYNCHRONOUSLY (the body runs
  /// to its first await), so a caller that only needs "the tree is down" sees no
  /// behaviour change; only the sweep is awaited.
  ///
  /// A THROWING sweep is loud (a [GridHookError] on hook `orphanSweep`, through
  /// [runGrid]'s error sink) and never breaks the teardown — the tree is already
  /// unmounted by then.
  ///
  /// Idempotent: a second call returns the SAME future; the rails and the sweep
  /// run exactly once.
  Future<void> teardown() => _teardown ??= _runTeardown();

  Future<void> _runTeardown() async {
    // Set synchronously (an async body runs to its first await eagerly): the
    // flush loop reads it to stop scheduling into a dying tree.
    _tornDown = true;
    // An in-flight reassemble will never see its flush — fail it LOUDLY rather
    // than leave the caller's future hanging forever.
    _failWaiters();
    try {
      _delegate.onTeardown();
    } catch (e, st) {
      _report(GridHookError('onTeardown', _delegate.runtimeType, e, st));
    }
    // Unmount first (the configuration scope's dispose removes its listener
    // off the delegate), then dispose the delegate.
    _owner.dispose();
    _delegate.dispose();
    _reassemble.dispose();
    // ... and END with the sweep: no effect of this tree may outlive its
    // unmount. It runs AFTER the unmount by construction — the stragglers it
    // reconciles against zero-expected only exist once the kills are in flight.
    final sweep = _orphanSweep;
    if (sweep == null) return;
    try {
      await sweep();
    } catch (e, st) {
      _report(GridHookError('orphanSweep', _delegate.runtimeType, e, st));
    }
  }
}

/// The **configuration provision** node: subscribes to the [GridDelegate]
/// `runGrid` holds (`StateNotifier<GridConfiguration>`) and re-provides its
/// current value as `InheritedSeed<GridConfiguration>` to the station subtree
/// below.
///
/// The delegate is passed **by construction** ([delegate]), never as an ambient
/// value the tree provides: the `StateNotifier` itself must not ride the tree,
/// or a consumer could snapshot its `.state` synchronously (ADR-0008 D-H). Only
/// the *value* it emits is made ambient — the `InheritedSeed<GridConfiguration>`
/// this node provides.
///
/// It is the tree's single observer of the delegate's config axis — a config
/// emission rebuilds *only* this node (observational isolation), which
/// re-composes the master build with the new configuration.
/// It is ALSO the tree's single observer of the dev-mode reassemble axis: a
/// `hotReload`/`hotRestart` emission dirties this ONE node, and the
/// re-composition below it is plain keyed reconcile — which ADOPTS every live
/// node rather than unmounting it (no unmount ⇒ no `dispose` ⇒ no killed agent).
class _GridConfigurationScope extends StatefulSeed {
  const _GridConfigurationScope({
    required this.delegate,
    required this.reassemble,
  });

  /// The observable `runGrid` holds — subscribed here, never provided ambiently.
  final GridDelegate delegate;

  /// The dev-mode reassemble bus `runGrid` holds — same posture: handed in by
  /// construction, observed here, never ambient (D-H).
  final ReassembleBus reassemble;

  @override
  State<_GridConfigurationScope> createState() => _GridConfigurationScopeState();
}

class _GridConfigurationScopeState extends State<_GridConfigurationScope> {
  RemoveListener? _removeConfig;
  RemoveListener? _removeReassemble;
  late GridDelegate _delegate;
  late GridConfiguration _config;
  int _generation = 0;

  @override
  void initState() {
    // The delegate is handed in by construction (runGrid holds it) — it never
    // rides the tree as an ambient value, so its `.state` cannot be snapshotted
    // by a consumer (D-H). This node is the sole subscriber.
    _delegate = seed.delegate;
    _subscribeConfig(_delegate);

    // The reassemble axis. Its FIRST delivery is the launch baseline
    // (generation 0) — the bus's seed state, not a request — so it is skipped
    // (no setState during mount).
    var first = true;
    _removeReassemble = seed.reassemble.addListener((request) {
      if (first) {
        first = false;
        return;
      }
      switch (request) {
        case ReloadRequest(:final generation):
          // Same delegate, new CODE: re-running the master build IS the act.
          setState(() => _generation = generation);
        case RestartRequest(:final generation, :final delegate):
          // A FRESH delegate replaces the running one. Unsubscribe the old one
          // BEFORE disposing it; re-subscribing delivers the new delegate's
          // baseline synchronously (fireImmediately), so ONE setState carries
          // the whole swap and the node re-composes exactly once.
          final retired = _delegate;
          _removeConfig?.call();
          _removeConfig = null;
          setState(() {
            _delegate = delegate;
            _subscribeConfig(delegate);
            _generation = generation;
          });
          retired.dispose();
      }
    });
  }

  /// Subscribes to [delegate], seeding [_config] from its baseline: the initial
  /// read IS the subscription (D-H rule 1 — always watch deps; `fireImmediately`
  /// delivers the current value synchronously into the listener, so no
  /// `setState` runs during mount); every later emission re-composes through
  /// `setState`.
  ///
  /// It RETURNS nothing on purpose: a `GridConfiguration`-returning declaration
  /// is a sync accessor over notifier state, which the D-H fence bans outright
  /// (only `GridConfiguration.of`/`maybeOf` — the subscribing observations — may
  /// hand the value back).
  void _subscribeConfig(GridDelegate delegate) {
    var seeded = false;
    _removeConfig = delegate.addListener((config) {
      if (!seeded) {
        seeded = true;
        _config = config;
        return;
      }
      setState(() => _config = config);
    });
  }

  @override
  void dispose() {
    _removeConfig?.call();
    _removeConfig = null;
    _removeReassemble?.call();
    _removeReassemble = null;
  }

  @override
  Seed build(TreeContext context) {
    return InheritedSeed<GridConfiguration>(
      value: _config,
      child: _DelegateRoot(
        delegate: _delegate,
        configuration: _config,
        generation: _generation,
      ),
    );
  }
}

/// Calls the master build — the delegate's own `build(context, configuration)`
/// — with the currently observed configuration, at the current reassemble
/// [generation]. Re-created (and so re-run) by the configuration scope on every
/// configuration emission AND on every dev-mode reload/restart.
class _DelegateRoot extends StatelessSeed {
  const _DelegateRoot({
    required this.delegate,
    required this.configuration,
    required this.generation,
  });

  final GridDelegate delegate;
  final GridConfiguration configuration;

  /// The reassemble generation this composition was built at (0 = launch). It
  /// makes the re-composition a VALUE in the tree — genesis prunes an
  /// `identical` child seed by design — so the generation is what keeps a
  /// re-composition honest for any future const-authored root.
  final int generation;

  @override
  Seed build(TreeContext context) => delegate.build(context, configuration);
}
