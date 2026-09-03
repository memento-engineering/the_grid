import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart' show TreeProjector;
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:state_notifier/state_notifier.dart';

import 'configuration.dart';
import 'grid_delegate.dart';
import 'reassemble.dart';

/// How long a grid waits before re-attempting a flush pass that threw (tg-60n,
/// ported from the retired coordinator). Coarse on purpose: the retry
/// exists to un-strand a dirty set, not to drive latency.
const Duration _kFlushRetryDelay = Duration(seconds: 1);

/// How many CONSECUTIVE failed flush passes a grid re-arms before it stops and
/// lets the stall become a VISIBLE wedge (tg-60n). Loud and stuck beats silent
/// and stuck; a hot loop is neither.
const int _kMaxFlushRetries = 5;

/// Launches a grid from [delegate] — **the entry point** (v3 §4 / GLOSSARY R15:
/// the delegation pattern's `runGrid(delegate)`). The framework root is
/// `final`; all station behaviour enters through the delegate.
///
/// It runs five lifecycle rails around a single mounted tree:
///
///  1. `delegate.didLaunch()` — **pre-tree**, synchronous. A failure is
///     terminal: it is wrapped as a [GridHookError] and **thrown** (the launch
///     aborts loudly — nothing mounts).
///  2. `await delegate.boot(delegate.state)` — **pre-tree**, asynchronous
///     resource assembly. Failure is terminal and mounts nothing.
///  3. **Mount the tree**: *configuration provision → `delegate.build`*. The
///     delegate does **not** ride the tree — `runGrid` holds it and drives the
///     configuration scope directly (by construction), because a
///     `StateNotifier`'s `.state` must never be reachable as a snapshot
///     (ADR-0008 D-H). Only its observed `GridConfiguration` is ambient,
///     provided just below as `InheritedSeed<GridConfiguration>` and re-provided
///     on every emission; `delegate.build(context, configuration)` roots the
///     station subtree. A configuration re-emission re-composes that subtree on
///     a coalesced microtask flush (the reactive loop, mirroring the kernel).
///  4. **Kick off** `delegate.initGrid()` — post-mount, async, **unawaited**;
///     on success `delegate.onReady()` fires. A failure in either is captured,
///     attributed, and reported loudly via [onError] — the running grid stands.
///
/// Returns a [GridHandle]: `await teardown()` runs `onTeardown`, unmounts the
/// tree (every mounted effect tears down with it), runs [orphanSweep] — the
/// teardown-vs-spawn reap — and only then disposes the delegate: the sweep
/// reconciles over the delegate's boot-assembled runtime, so the delegate must
/// still be LIVE to serve it. [orphanSweep] is null by default (a station with
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
/// [treeProjector], when supplied, receives that same completed-flush rail
/// before [onFlushed]. Its lifetime remains owned by the composing runner;
/// [GridHandle.teardown] does not dispose it.
///
/// [delegateFactory] arms the dev-mode hot-RESTART ([GridHandle.hotRestart]):
/// it is re-invoked to build a FRESH delegate from the same runner inputs
/// (flags, env, wiring, harness registry). A JIT station (started with
/// `--enable-vm-service`) passes it; an AOT station omits it and `hotRestart`
/// then refuses LOUDLY. [GridHandle.hotReload] needs no factory.
///
/// [onDelegateSwapped] fires synchronously at the hot-restart COMMIT point —
/// after the fresh delegate's `boot` succeeded and the handle adopted it as
/// the live delegate, before the retired one is disposed. It is the seam a
/// composing shell re-points its per-request read surface (status views,
/// command handlers, sweep closures) through: swapping a shell-side holder
/// inside [delegateFactory] instead would publish an un-booted delegate, and
/// a FAILED restart boot would leave the shell reading a disposed corpse
/// while the mounted grid keeps running the old delegate. Never invoked for
/// the launch delegate, and never on a failed restart.
///
/// [scheduleTimer] is the failed-flush RE-ARM seam (tg-um8k): a pass that threw
/// schedules one bounded retry through it, so the re-arm is driven
/// deterministically offline. Defaults to [Timer.new]. It is the SAME
/// `Timer Function(Duration, void Function())` seam `StationDriver` and
/// `WedgeMonitor` already take — no new abstraction.
Future<GridHandle> runGrid(
  GridDelegate delegate, {
  void Function(GridHookError refusal)? onError,
  void Function()? onFlushed,
  TreeProjector? treeProjector,
  Future<void> Function()? orphanSweep,
  GridDelegate Function()? delegateFactory,
  void Function(GridDelegate next)? onDelegateSwapped,
  Timer Function(Duration, void Function())? scheduleTimer,
}) async {
  final report = onError ?? _rethrowToZone;

  // 1. Pre-tree rail — synchronous; a failure aborts the launch (loud throw).
  try {
    delegate.didLaunch();
  } catch (e, st) {
    throw GridHookError('didLaunch', delegate.runtimeType, e, st);
  }

  try {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    await delegate.boot(delegate.state);
  } catch (error, stackTrace) {
    delegate.dispose();
    throw GridHookError('boot', delegate.runtimeType, error, stackTrace);
  }

  // 3. Mount: configuration provision → build. The delegate is held here (by
  //    construction), never provided ambiently (D-H).
  final owner = TreeOwner();
  // The dev-mode reassemble bus: held HERE and handed to the scope by
  // construction — never ambient (D-H), exactly like the delegate.
  final reassemble = ReassembleBus();
  final handle = GridHandle._(
    owner,
    treeProjector,
    delegate,
    report,
    onFlushed,
    orphanSweep,
    reassemble,
    delegateFactory,
    onDelegateSwapped,
    scheduleTimer ?? Timer.new,
  );
  // Wire the flush trigger BEFORE mounting: the first build runs synchronously
  // in mountRoot with no markNeedsRebuild (the config scope assigns its
  // baseline directly, never setState during mount), so onNeedsFlush cannot
  // fire during it.
  handle._wireFlush();
  try {
    final root = owner.mountRoot(
      _GridConfigurationScope(delegate: delegate, reassemble: reassemble),
    );
    owner.flush();
    handle._root = root;
    treeProjector?.afterFlush(root);
    onFlushed?.call();
  } on Object {
    // A throw anywhere between mount and the first completed flush must not
    // strand the owner and the reassemble bus — release both, then let the
    // error reach the caller raw (the composing shell owns the delegate's
    // disposal on this path). RESIDUAL LIMIT: genesis_tree 0.2.0's
    // `mountRoot` assigns its root only after `mount` returns, so a
    // mid-mount throw leaves the partially mounted branches unreachable —
    // `owner.dispose()` then unmounts nothing. That is an upstream seam (a
    // bead will track it); do not fork or patch genesis_tree here.
    // The handle dies with the rail: a branch dirtied during mount has already
    // scheduled the coalesced flush microtask, and TreeOwner.dispose does not
    // clear onNeedsFlush — marking the handle torn down makes that pending
    // microtask take its early-out instead of flushing a disposed owner and
    // reading the never-assigned root mid-unwind.
    handle._tornDown = true;
    owner.dispose();
    reassemble.dispose();
    rethrow;
  }

  // 4. Post-mount async kickoff — unawaited by the caller; onReady chained
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
/// (many dirties between turns collapse into one flush). This loop is the
/// station's ONE flush coordinator (tg-um8k).
/// `root.markNeedsRebuild()` is never called; only the observing scope
/// dirties.
///
/// Call [teardown] to run the delegate's `onTeardown` rail and unmount the
/// tree. Idempotent.
class GridHandle {
  GridHandle._(
    this._owner,
    this._treeProjector,
    this._delegate,
    this._report,
    this._onFlushed,
    this._orphanSweep,
    this._reassemble,
    this._delegateFactory,
    this._onDelegateSwapped,
    this._scheduleTimer,
  );

  final TreeOwner _owner;
  final TreeProjector? _treeProjector;
  late final Branch _root;

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

  /// The hot-restart COMMIT notification (see [runGrid]'s `onDelegateSwapped`).
  final void Function(GridDelegate next)? _onDelegateSwapped;

  /// Callers awaiting the NEXT completed flush (one per in-flight reassemble),
  /// completed with the reassemble report — or failed LOUDLY if the grid tears
  /// down before the flush lands.
  final List<_ReassembleWaiter> _flushWaiters = <_ReassembleWaiter>[];

  /// The monotonic re-composition counter; 0 is the launch baseline.
  int _generation = 0;

  bool _tornDown = false;
  bool _flushScheduled = false;
  Future<void>? _teardown;

  /// The retry clock for [_rearmAfterFailedFlush] — injectable so the re-arm is
  /// driven deterministically offline.
  final Timer Function(Duration, void Function()) _scheduleTimer;

  /// Consecutive failed flush passes — reset by the first clean pass. Bounds
  /// [_rearmAfterFailedFlush] so a branch that throws every time degrades into
  /// a visible wedge instead of a hot retry loop.
  int _consecutiveFlushFailures = 0;

  /// The pending failure re-arm, if any (cancelled on [teardown]).
  Timer? _flushRetry;

  /// Coalesces dirties into one microtask flush. Wired before mount so the
  /// synchronous first build never trips it.
  void _wireFlush() {
    _owner.onNeedsFlush = _scheduleFlush;
  }

  void _scheduleFlush() {
    if (_flushScheduled || _tornDown) return;
    _flushScheduled = true;
    scheduleMicrotask(_runFlushPass);
  }

  /// One flush pass, FAIL-CLOSED (tg-60n, ported here by tg-um8k from the
  /// retired coordinator, which held this guard while never running in
  /// production).
  ///
  /// `TreeOwner.flush()` has no internal catch (genesis_tree 0.3.0
  /// `tree_owner.dart`), so one throwing `branch.rebuild()` propagates straight
  /// out. Unguarded that killed the WHOLE remainder of the tick, and the two
  /// consequences were invisible and unbounded:
  ///
  /// 1. **[_onFlushed] never ran.** It carries `StationDriver.afterFlush`,
  ///    whose `WedgeMonitor.poll` is the station's ONLY stall alarm. A
  ///    non-stalled sample cancels the monitor's timer by design ("a healthy
  ///    grid arms no wall clock at all"), so a flush is its only remaining
  ///    heartbeat. Skipping it froze the wedge state at its last good sample: a
  ///    live arm reported `wedged: false, live: 0` while `/status` computed 6
  ///    live sessions from the SAME bridge, for 18.6 hours (receipt on tg-60n,
  ///    2026-08-06).
  /// 2. **The dirty set could strand NON-EMPTY.** `TreeOwner.scheduleRebuildFor`
  ///    fires `onNeedsFlush` only on the empty→non-empty EDGE. A pass that
  ///    threw part-way leaves branches dirty, so every later `markNeedsRebuild`
  ///    sees a non-empty set and schedules NOTHING — the tree freezes for the
  ///    life of the process, and a bounce is the only cure.
  ///
  /// The guard fixes both: [_onFlushed] runs in a `finally`, and a failed pass
  /// re-arms so a stranded set cannot wedge the tree silently.
  void _runFlushPass() {
    _flushScheduled = false;
    if (_tornDown) {
      _failWaiters();
      return;
    }
    // The APPLIED generation: the waiters this pass answers for, captured
    // BEFORE the flush. A waiter registered while the pass runs (a reassemble
    // requested from the post-flush rail) belongs to a LATER generation and is
    // served by the flush its own emission schedules — never completed or
    // refused by a pass that did not carry it.
    final applied = List<_ReassembleWaiter>.of(_flushWaiters);
    _flushWaiters.clear();
    var failed = false;
    try {
      final rebuilt = _owner.flush();
      _treeProjector?.afterFlush(_root);
      _consecutiveFlushFailures = 0;
      _completeWaiters(applied, rebuilt.length);
    } on Object catch (error, stackTrace) {
      failed = true;
      _consecutiveFlushFailures++;
      _refusePostSwapFlush(applied, error, stackTrace);
    } finally {
      // The runner's post-flush machinery runs even when the pass THREW: a
      // broken tick is exactly when the stall alarm must keep sampling.
      if (!_tornDown) {
        try {
          _onFlushed?.call();
        } on Object catch (error, stackTrace) {
          _report(
            GridHookError(
              'onFlushed',
              _delegate.runtimeType,
              error,
              stackTrace,
            ),
          );
        }
      }
    }
    if (failed) _rearmAfterFailedFlush();
  }

  /// Re-arms a flush after a failed pass, so a dirty set stranded by the throw
  /// cannot silently freeze the tree (the edge-trigger trap above).
  ///
  /// BOUNDED on purpose: a branch that throws on every pass would otherwise
  /// spin. After [_kMaxFlushRetries] consecutive failures the grid stops
  /// re-arming and lets the station ripen into a VISIBLE wedge — which it now
  /// can, because [_onFlushed] keeps running.
  void _rearmAfterFailedFlush() {
    if (_tornDown || _flushScheduled) return;
    if (_consecutiveFlushFailures > _kMaxFlushRetries) return;
    _flushRetry?.cancel();
    _flushRetry = _scheduleTimer(_kFlushRetryDelay, () {
      _flushRetry = null;
      if (_tornDown) return;
      _scheduleFlush();
    });
  }

  void _completeWaiters(List<_ReassembleWaiter> waiters, int rebuilt) {
    for (final waiter in waiters) {
      waiter.completer.complete(
        ReassembleReport(
          mode: waiter.mode,
          generation: waiter.generation,
          rebuiltBranches: rebuilt,
        ),
      );
    }
  }

  void _failWaiters() {
    final waiters = List<_ReassembleWaiter>.of(_flushWaiters);
    _flushWaiters.clear();
    for (final waiter in waiters) {
      waiter.completer.completeError(
        StateError('the grid tore down before the flush landed'),
      );
    }
  }

  // The refusal rides its first-class carriers only: the awaited
  // [ReassembleReport] when a caller is waiting, the [GridHookError] report
  // rail when none is. No VM-service log side channel — that surface is the
  // JIT debug channel, never a diagnostic dependency (ADR-0012 D2).
  void _refusePostSwapFlush(
    List<_ReassembleWaiter> waiters,
    Object error,
    StackTrace stackTrace,
  ) {
    if (waiters.isEmpty) {
      _report(GridHookError('flush', _delegate.runtimeType, error, stackTrace));
      return;
    }
    for (final waiter in waiters) {
      waiter.completer.complete(
        ReassembleReport.refusedAfterSourceSwap(
          mode: waiter.mode,
          generation: waiter.generation,
          details: '$error',
        ),
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
  /// fresh delegate takes the awaited pre-recomposition `boot` rail and the
  /// POST-MOUNT rails (`initGrid` → `onReady`, unawaited, loud on failure), but
  /// **not `didLaunch`**: that rail is defined
  /// pre-tree and terminal ("nothing mounts" on failure), and a restart mounts
  /// no new tree — re-running it would let a fresh delegate's throw kill a live
  /// station with agents mid-build.
  ///
  /// Launched without a `delegateFactory` → a LOUD [StateError] (never a silent
  /// no-op).
  Future<ReassembleReport> hotRestart() async {
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
    try {
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      await next.boot(next.state);
    } catch (error, stackTrace) {
      next.dispose();
      throw GridHookError('boot', next.runtimeType, error, stackTrace);
    }
    // Re-check AFTER the awaited boot: teardown() can land while the fresh
    // delegate boots, and committing past it would swap the shell's read
    // surface onto a delegate whose tree is already unmounted (and dispose
    // the corpse twice — teardown already disposed the live one). Refuse
    // LOUDLY before assigning the live holder, notifying the commit seam, or
    // kicking off the post-mount rails.
    if (_tornDown) {
      next.dispose();
      throw StateError('the grid tore down during the restart boot');
    }
    final generation = ++_generation;
    // The LIVE delegate from here on: teardown must reach this one, never the
    // corpse the configuration scope is about to retire.
    _delegate = next;
    // THE COMMIT NOTIFICATION — synchronous with the swap, so a composing
    // shell's read surface never spans an event-loop turn pointed at either
    // an un-booted fresh delegate or the retired corpse.
    _onDelegateSwapped?.call(next);
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
  /// that ONE branch — and reports what the resulting flush rebuilt or refused.
  Future<ReassembleReport> _reassemble0(
    ReassembleRequest request,
    ReassembleMode mode,
    int generation,
  ) {
    final waiter = _ReassembleWaiter(mode: mode, generation: generation);
    _flushWaiters.add(waiter);
    try {
      _reassemble.request(request);
    } catch (error) {
      _flushWaiters.remove(waiter);
      // Delivered via the awaited report — no VM-service log side channel
      // (ADR-0012 D2; the refusal's carrier is [ReassembleReport]).
      waiter.completer.complete(
        ReassembleReport.refusedAfterSourceSwap(
          mode: mode,
          generation: generation,
          details: '$error',
        ),
      );
    }
    return waiter.completer.future;
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
  /// unmounts the tree (every mounted effect tears down), runs the ORPHAN
  /// SWEEP when one is wired, and ENDS by disposing the delegate. The sweep
  /// precedes the dispose BY CONTRACT: it is the teardown-vs-spawn reap on the
  /// delegate's boot-assembled runtime, and `dispose` unwinds exactly that
  /// machinery — a sweep served off a disposed delegate would silently
  /// recreate the orphaned-agent window it exists to close.
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
    _flushRetry?.cancel();
    _flushRetry = null;
    // An in-flight reassemble will never see its flush — fail it LOUDLY rather
    // than leave the caller's future hanging forever.
    _failWaiters();
    try {
      _delegate.onTeardown();
    } catch (e, st) {
      _report(GridHookError('onTeardown', _delegate.runtimeType, e, st));
    }
    // Unmount first (the configuration scope's dispose removes its listener
    // off the delegate).
    _owner.dispose();
    _reassemble.dispose();
    // The sweep runs AFTER the unmount by construction — the stragglers it
    // reconciles against zero-expected only exist once the kills are in
    // flight — and BEFORE the delegate disposes: it is the reap on the
    // delegate's boot-assembled runtime, which `dispose` unwinds.
    final sweep = _orphanSweep;
    if (sweep != null) {
      try {
        await sweep();
      } catch (e, st) {
        _report(GridHookError('orphanSweep', _delegate.runtimeType, e, st));
      }
    }
    _delegate.dispose();
  }
}

class _ReassembleWaiter {
  _ReassembleWaiter({required this.mode, required this.generation});

  final ReassembleMode mode;
  final int generation;
  final Completer<ReassembleReport> completer = Completer<ReassembleReport>();
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
  State<_GridConfigurationScope> createState() =>
      _GridConfigurationScopeState();
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
    // The tree's ONE ProviderScope (the availability registry) sits HERE, at
    // the production root, over the observed-configuration provider.
    return ProviderScope(
      child: Provider<GridConfiguration>.value(
        _config,
        child: _DelegateRoot(
          delegate: _delegate,
          configuration: _config,
          generation: _generation,
        ),
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
