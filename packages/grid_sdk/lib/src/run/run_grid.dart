import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:state_notifier/state_notifier.dart';

import 'configuration.dart';
import 'grid_delegate.dart';

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
GridHandle runGrid(
  GridDelegate delegate, {
  void Function(GridHookError refusal)? onError,
  void Function()? onFlushed,
  Future<void> Function()? orphanSweep,
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
  final handle = GridHandle._(owner, delegate, report, onFlushed, orphanSweep);
  // Wire the flush trigger BEFORE mounting: the first build runs synchronously
  // in mountRoot with no markNeedsRebuild (the config scope assigns its
  // baseline directly, never setState during mount), so onNeedsFlush cannot
  // fire during it.
  handle._wireFlush();
  owner.mountRoot(_GridConfigurationScope(delegate: delegate));
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
  );

  final TreeOwner _owner;
  final GridDelegate _delegate;
  final void Function(GridHookError) _report;

  /// The runner's post-flush seam (see [runGrid]'s `onFlushed`).
  final void Function()? _onFlushed;

  /// The teardown-vs-spawn orphan reap — null when the station has no process
  /// transport to sweep.
  final Future<void> Function()? _orphanSweep;

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
        if (_tornDown) return;
        _owner.flush();
        _onFlushed?.call();
      });
    };
  }

  /// Whether [teardown] has run.
  bool get isTornDown => _tornDown;

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
    try {
      _delegate.onTeardown();
    } catch (e, st) {
      _report(GridHookError('onTeardown', _delegate.runtimeType, e, st));
    }
    // Unmount first (the configuration scope's dispose removes its listener
    // off the delegate), then dispose the delegate.
    _owner.dispose();
    _delegate.dispose();
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
class _GridConfigurationScope extends StatefulSeed {
  const _GridConfigurationScope({required this.delegate});

  /// The observable `runGrid` holds — subscribed here, never provided ambiently.
  final GridDelegate delegate;

  @override
  State<_GridConfigurationScope> createState() => _GridConfigurationScopeState();
}

class _GridConfigurationScopeState extends State<_GridConfigurationScope> {
  RemoveListener? _remove;
  late final GridDelegate _delegate;
  late GridConfiguration _config;

  @override
  void initState() {
    // The delegate is handed in by construction (runGrid holds it) — it never
    // rides the tree as an ambient value, so its `.state` cannot be snapshotted
    // by a consumer (D-H). This node is the sole subscriber.
    _delegate = seed.delegate;
    // The initial read IS the subscription (D-H rule 2): fireImmediately
    // delivers the baseline synchronously into the listener, assigned directly
    // (no setState during mount); every later emission goes through setState
    // and re-composes.
    var first = true;
    _remove = _delegate.addListener((config) {
      if (first) {
        first = false;
        _config = config;
        return;
      }
      setState(() => _config = config);
    });
  }

  @override
  void dispose() {
    _remove?.call();
    _remove = null;
  }

  @override
  Seed build(TreeContext context) {
    return InheritedSeed<GridConfiguration>(
      value: _config,
      child: _DelegateRoot(delegate: _delegate, configuration: _config),
    );
  }
}

/// Calls the master build — the delegate's own `build(context, configuration)`
/// — with the currently observed configuration. Re-created (and so re-run) by
/// the configuration scope on every emission.
class _DelegateRoot extends StatelessSeed {
  const _DelegateRoot({required this.delegate, required this.configuration});

  final GridDelegate delegate;
  final GridConfiguration configuration;

  @override
  Seed build(TreeContext context) => delegate.build(context, configuration);
}
