import 'package:genesis_tree/genesis_tree.dart';
import 'package:state_notifier/state_notifier.dart';

import '../composition/composition.dart';
import 'configuration.dart';

/// The station author's delegate — **rails, not layers** (v3 §4).
///
/// The v2 `buildServices`/`buildSources` hook split **died** with the
/// code-as-config pivot: framework-owned layering is gone, because assets mount
/// in the tree at the right scope. What survives is exactly three things:
///
///  1. **Being the observable.** A `GridDelegate` *is* a
///     `StateNotifier<GridConfiguration>` (a thin plain value, Q6). Its state is
///     the current configuration; emitting a new one (`state = …` from a
///     subclass) re-composes the tree through the same reconcile path as any
///     observed change — no restart, no re-parse.
///  2. **The lifecycle rails** — [didLaunch] (pre-tree), [initGrid] (post-mount
///     async kickoff, unawaited), [onReady], [onTeardown]. A rail that throws is
///     captured, **attributed, and surfaced loud** as a [GridHookError] — a
///     named refusal, never a bare stack trace from library plumbing (the guard
///     principle).
///  3. **The master [build]** `(context, configuration) → Seed` — returns the
///     station tree (v3 §2). §2's `SpaceStationAsASeed.build` *is* this method
///     in delegate clothing; a full station overrides it wholesale.
///
/// The framework root is `final`: consumers **compose** (subclass this
/// delegate, author a tree) — they never subclass the running machine
/// (ADR-0008 Decision 2). Drive a delegate with `runGrid`.
///
/// Convenience build hooks (sugar over asset mounting) are **not designed up
/// front** — they are earned from real usage (v3 §4). The only compose surface
/// the base ships is [root] + [assets], feeding the default [build].
abstract class GridDelegate extends StateNotifier<GridConfiguration> {
  /// Creates a delegate seeded with [initialConfiguration] (an empty
  /// configuration by default — the delegate emits a richer one, e.g. after a
  /// TOML load, via its protected `state` setter).
  GridDelegate([super.initialConfiguration = const GridConfiguration()]);

  /// The grid's home — the `RawAssetGrid` root the default [build] roots the
  /// tree at (v3 §3; the grid's state store lives under `<root>/.grid/`).
  ///
  /// The base throws: **there is no default root** (v3 §0 — an unresolvable
  /// root is a loud refusal, never an ambient default). A station either
  /// overrides this getter (and uses the default [build]) or overrides [build]
  /// wholesale (in which case this getter is never called).
  String get root => throw StateError(
    '$runtimeType.root: a grid has no default root (v3 §0). Override `root` to '
    'use the default build, or override build(context, configuration) to '
    'author the tree wholesale.',
  );

  /// Grid-scoped assets mounted under the default [build]'s `RawAssetGrid`
  /// (v3 §3: an asset is anything mounted into the tree at a scope). Empty by
  /// default; a compose-style station mounts its `Station(...)`, config
  /// providers, and federation discovery here.
  List<Seed> get assets => const <Seed>[];

  /// The **master build**: returns the station tree for [configuration]
  /// (v3 §2/§4).
  ///
  /// The default returns the canonical §2 root — `RawAssetGrid(root, assets)` —
  /// composed from [root] and [assets]. A full station overrides it wholesale
  /// and authors `RawAssetGrid → Station → Substations → Substation` literally
  /// (that override IS §2's `SpaceStationAsASeed.build`).
  ///
  /// [configuration] is the currently-observed value, passed for convenience;
  /// it is **also** ambient below via `GridConfiguration.of(context)`, so a
  /// deeply-composed substation reads it without threading. Because a config
  /// re-emission re-runs this method, `build` stays a pure function of
  /// `(context, configuration)` — observe out of band, never mutate here (A39).
  Seed build(TreeContext context, GridConfiguration configuration) =>
      RawAssetGrid(root: root, assets: assets);

  /// **PRE-tree** rail — runs synchronously, before the tree mounts.
  ///
  /// There is no tree yet, so do **not** load state here (that is [initGrid]'s
  /// job, post-mount). A failure is terminal: `runGrid` wraps it as a
  /// [GridHookError] and **throws** — the launch aborts loudly, nothing
  /// mounts. Default: no-op. (Override to run; `runGrid` calls it.)
  void didLaunch() {}

  /// **POST-mount async kickoff** — started after the tree is up and
  /// **unawaited** by `runGrid` (the grid is live while this runs). This is
  /// where post-mount async work belongs: warming caches, opening federation
  /// discovery, priming the first configuration emission.
  ///
  /// A failure is captured, attributed, and surfaced loud (via `runGrid`'s
  /// error sink) — the running grid is **not** torn down. [onReady] fires only
  /// when this future completes successfully. Default: no-op. (Override to run;
  /// `runGrid` calls it.)
  Future<void> initGrid() async {}

  /// **READY** rail — fires once [initGrid] completes successfully: the grid
  /// finished its post-mount kickoff and is ready. A failure is loud
  /// (non-aborting). Default: no-op. (Override to run; `runGrid` calls it.)
  void onReady() {}

  /// **TEARDOWN** rail — fires when the running grid is torn down (via
  /// `GridHandle.teardown`), before the tree unmounts. A failure is loud;
  /// teardown proceeds regardless (an effect must never leak because a rail
  /// threw). Default: no-op. (Override to run; `runGrid` calls it.)
  void onTeardown() {}

  /// The ambient delegate provided by `runGrid`, or null outside a running
  /// grid. A **non-subscribing** lookup: the delegate *instance* is stable for
  /// a launch (its observable configuration is read via `GridConfiguration.of`
  /// instead), so a reader takes a snapshot, never a dependency.
  static GridDelegate? maybeOf(TreeContext context) =>
      context.getInheritedSeedOfExactType<GridDelegate>();

  /// The ambient delegate, **loud when absent** — there is no delegate outside
  /// a running grid (the guard principle).
  static GridDelegate of(TreeContext context) {
    final delegate = maybeOf(context);
    if (delegate == null) {
      throw StateError(
        'GridDelegate.of: no runGrid encloses this context. The delegate is '
        'provided by runGrid(delegate) — read it inside the grid tree.',
      );
    }
    return delegate;
  }
}

/// A lifecycle-rail failure, **captured and attributed** — which [hook] threw,
/// on which [delegateType] — so it surfaces as a *named refusal*, never a bare
/// stack trace from library plumbing (v3 §4; the guard principle: loud when an
/// invariant is violated).
///
/// A `didLaunch` failure is thrown from `runGrid` (the launch aborts). The
/// post-mount rails ([GridDelegate.initGrid] / [GridDelegate.onReady] /
/// [GridDelegate.onTeardown]) cannot throw to a caller, so `runGrid` reports
/// their refusals through its error sink (loud by default — rethrown into the
/// current zone).
class GridHookError extends Error {
  /// Wraps [cause] (with its [causeStackTrace]) thrown by [hook] on a delegate
  /// of type [delegateType].
  GridHookError(this.hook, this.delegateType, this.cause, this.causeStackTrace);

  /// The rail that threw: `didLaunch` / `initGrid` / `onReady` / `onTeardown`.
  final String hook;

  /// The runtime type of the delegate whose rail threw.
  final Type delegateType;

  /// The original error the rail threw.
  final Object cause;

  /// The original error's stack trace (preserved for attribution).
  final StackTrace causeStackTrace;

  @override
  String toString() =>
      'GridHookError: $delegateType.$hook() threw — $cause\n$causeStackTrace';
}
