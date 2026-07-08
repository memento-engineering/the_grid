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
///  2. **Mount the tree**: *delegate provision → configuration provision →
///     `delegate.build`*. The delegate rides the tree as
///     `InheritedSeed<GridDelegate>`; its observed `GridConfiguration` rides
///     just below as `InheritedSeed<GridConfiguration>`, re-provided on every
///     emission; `delegate.build(context, configuration)` roots the station
///     subtree. A configuration re-emission re-composes that subtree on a
///     coalesced microtask flush (the reactive loop, mirroring the kernel).
///  3. **Kick off** `delegate.initGrid()` — post-mount, async, **unawaited**;
///     on success `delegate.onReady()` fires. A failure in either is captured,
///     attributed, and reported loudly via [onError] — the running grid stands.
///
/// Returns a [GridHandle]: `teardown()` runs `onTeardown` and unmounts the tree
/// (every mounted effect tears down with it).
///
/// [onError] receives the captured refusals from the **post-mount** rails
/// (`initGrid` / `onReady` / `onTeardown`). It defaults to rethrowing into the
/// current zone (loud). A `didLaunch` failure does not go through [onError] —
/// it is thrown from `runGrid` directly (the caller cannot proceed with a grid
/// that never mounted).
GridHandle runGrid(
  GridDelegate delegate, {
  void Function(GridHookError refusal)? onError,
}) {
  final report = onError ?? _rethrowToZone;

  // 1. Pre-tree rail — synchronous; a failure aborts the launch (loud throw).
  try {
    delegate.didLaunch();
  } catch (e, st) {
    throw GridHookError('didLaunch', delegate.runtimeType, e, st);
  }

  // 2. Mount: delegate provision → configuration provision → build.
  final owner = TreeOwner();
  final handle = GridHandle._(owner, delegate, report);
  // Wire the flush trigger BEFORE mounting: the first build runs synchronously
  // in mountRoot with no markNeedsRebuild (the config scope assigns its
  // baseline directly, never setState during mount), so onNeedsFlush cannot
  // fire during it.
  handle._wireFlush();
  owner.mountRoot(
    InheritedSeed<GridDelegate>(
      value: delegate,
      child: const _GridConfigurationScope(),
    ),
  );
  owner.flush();

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
  GridHandle._(this._owner, this._delegate, this._report);

  final TreeOwner _owner;
  final GridDelegate _delegate;
  final void Function(GridHookError) _report;
  bool _tornDown = false;
  bool _flushScheduled = false;

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
      });
    };
  }

  /// Whether [teardown] has run.
  bool get isTornDown => _tornDown;

  /// Tears the grid down: runs `onTeardown` (loud on failure, non-aborting),
  /// then unmounts the tree (every mounted effect tears down) and disposes the
  /// delegate. Idempotent.
  void teardown() {
    if (_tornDown) return;
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
  }
}

/// The **configuration provision** node: observes the ambient [GridDelegate]
/// (`StateNotifier<GridConfiguration>`) and re-provides its current value as
/// `InheritedSeed<GridConfiguration>` to the station subtree below.
///
/// It is the tree's single observer of the delegate's config axis — a config
/// emission rebuilds *only* this node (observational isolation), which
/// re-composes the master build with the new configuration.
class _GridConfigurationScope extends StatefulSeed {
  const _GridConfigurationScope();

  @override
  State<_GridConfigurationScope> createState() => _GridConfigurationScopeState();
}

class _GridConfigurationScopeState extends State<_GridConfigurationScope> {
  RemoveListener? _remove;
  late final GridDelegate _delegate;
  late GridConfiguration _config;

  @override
  void initState() {
    // The delegate provided just above — a stable instance; a one-shot,
    // non-subscribing read is correct in initState (D-H rule).
    _delegate = GridDelegate.of(context);
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
