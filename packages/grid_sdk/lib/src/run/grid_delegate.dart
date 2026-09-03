import 'package:genesis_tree/genesis_tree.dart';
import 'package:meta/meta.dart';
import 'package:state_notifier/state_notifier.dart';

import '../command/command_operation.dart';
import '../composition/composition.dart';
import '../stores/stores.dart';
import '../work/store_connection.dart';
import '../work/work_assembly.dart';
import 'configuration.dart';
import 'staleness_posture.dart';
import 'station_refusal.dart';
import 'station_view.dart';
import 'substation_config.dart';

/// The station author's delegate — **rails, not layers** (v3 §4).
///
/// The v2 `buildServices`/`buildSources` hook split **died** with the
/// code-as-config pivot: framework-owned layering is gone, because assets mount
/// in the tree at the right scope. What survives is exactly three things, with
/// five lifecycle rails:
///
///  1. **Being the observable.** A `GridDelegate` *is* a
///     `StateNotifier<GridConfiguration>` (a thin plain value, Q6). Its state is
///     the current configuration; emitting a new one (`state = …` from a
///     subclass) re-composes the tree through the same reconcile path as any
///     observed change — no restart, no re-parse.
///  2. **The lifecycle rails** — [didLaunch] (synchronous pre-tree), [boot]
///     (awaited pre-tree assembly), [initGrid] (post-mount async kickoff,
///     unawaited), [onReady], [onTeardown]. A rail that throws is captured,
///     **attributed, and surfaced loud** as a [GridHookError] — a named refusal,
///     never a bare stack trace from library plumbing (the guard principle).
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
///
/// ## The station composition contract (tg-1fa2.4, unified here by tg-at3r)
///
/// A station-authored delegate the station `up` shell can drive. This is the
/// delegate-boot + mounted-provider composition: the delegate is constructed
/// from parsed configuration ALONE, assembles its off-tree work machinery
/// inside the [boot] rail (awaited by `runGrid` before the first mount — once
/// per delegate instance, fresh delegate + fresh boot on hot restart), and
/// VENDS the narrow views the command shell reads. Reference types flow OUT
/// of the delegate, never in.
///
/// The composition contract, in lifecycle order:
///
///  1. **Construction is config-only** (the station `up` command's
///     `delegateFactory` receives the parsed `StationConfig` and nothing
///     else). No wiring, no provisioner, no effect implementations enter the
///     factory — assembly is [boot]-owned. The dry-run effect posture TODAY
///     is boot-selected OFF-tree: boot passes the config's `dryRun` to
///     `assembleStationWork`, which selects inert implementations by type.
///     Declaring the posture in the TREE (dry-run mounts no effect providers,
///     so the projection sees the absence) is the TARGET state, owned by the
///     reference-boot follow-up bead.
///  2. **[resolveArmedRoster]** — the shell calls it exactly once per
///     delegate instance, BEFORE the boot rail, folding the station's arming
///     policy (skip a coded seat with no store, refuse an appended one) over
///     the roster. The delegate retains the result ([armedRoster]) — what
///     [boot] assembles over.
///  3. **[boot]** (`runGrid` awaits it before the first mount) — assembles
///     AND starts the off-tree work machinery, including the diagnostics
///     reporter effect (previously the command's one hardcoded seamless
///     effect). Assembly only — no NEW policy may enter it (the rule-5
///     ratchet; see the honest posture note below).
///  4. **The vended views** ([stationView], [commandHandler], [afterFlush],
///     [sweepOrphans]) are valid once [boot] completed; the shell reads them
///     per request, never earlier. Absence is a designed posture
///     (docs/STYLE.md rules 3/4): [stationView] and [commandHandler] default
///     to null, and the shell renders the absence honestly — `/status`
///     reports what it can, the control surface refuses commands with a clear
///     message. The diagnostics `TreeProjector` is NOT a delegate concern: it
///     is shell-owned and process-lifetime (the shell threads ONE instance
///     into `runGrid` and `/stream`, and a hot restart's fresh delegate
///     flushes into that same sink — a delegate-owned projector would be
///     disposed with the retired delegate and leave the flush rail and
///     `/stream` permanently dark).
///  5. **[dispose]** unwinds what boot assembled, in reverse creation order.
///     It does NOT presume the earlier steps ran: `dispose` MUST tolerate
///     (i) a delegate whose [resolveArmedRoster]/[boot] never ran and (ii) a
///     boot that threw partway through assembly — the shell disposes
///     never-booted delegates on its refusal paths (roster refusal,
///     staleness, lock conflict); the runner (`runGrid`) disposes a
///     partially-booted one when the boot rail throws. Implement it over
///     nullable fields or a booted flag; never assume boot completed.
///     The shell's teardown: unmount tree (in-tree resources unwind by
///     unmount order — tree-owned `Provider` create/dispose) → [sweepOrphans]
///     on the STILL-LIVE delegate → dispose the delegate (both inside the
///     runner's teardown, in that order — the sweep reaps over the
///     boot-assembled runtime, exactly what `dispose` unwinds) → dispose the
///     shell projector → release lock.
///
/// **The rule-5 posture, honestly stated.** [armRoster] (which seats arm,
/// skip-coded vs refuse-appended) and [stalenessPosture] are STATION POLICY
/// executing on the pre-boot rail, not in `build` — docs/STYLE.md rule 5
/// names exactly these decisions as tree policy. They live here pre-tree by
/// NECESSITY: their outcomes are exit codes and the lock decision, both of
/// which must land before anything mounts. That makes them ratchet DEBT under
/// rule 5's own clause ("assembly moves into the tree as lifecycle-capable
/// providers become available"), not rule-5-clean: the decisions render to
/// the operator's stdout/stderr, invisible to the tree projection, and must
/// migrate into `build` (where `/stream` can observe them) once the tree can
/// carry refusal postures with exit semantics. Do not add new policy here.
///
/// **OPEN SEAM — no reference boot implementation ships yet.** The station
/// half of the tg-1fa2.4 migration (boot-owned `assembleStationWork` + the
/// `StationDiagnosticsReporter` effect, views vended over the assembled
/// `StationWorkRuntime`; dry-run as provider ABSENCE in the tree is that
/// follow-up's target — today `assembleStationWork` selects inert
/// implementations off-tree from its `dryRun` flag) ships only as this
/// abstract contract — every concrete `boot` today lives in tests. The
/// reference boot-owned assembly delegate is deliberate follow-up work under
/// the tg-1fa2 epic (file it as its own bead when composing the first
/// production station on this command); until it lands, a composing station
/// authors its own `boot` from this contract plus `assembleStationWork`'s
/// docs.
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

  /// PRE-tree asynchronous assembly rail.
  ///
  /// [configuration] is the delegate's initial observed value. Override only to
  /// construct and connect owner-held resources required before the first mount;
  /// policy remains in [build]. `runGrid` awaits this method exactly once for
  /// each delegate instance. A failure is terminal for that instance.
  Future<void> boot(GridConfiguration configuration) async {}

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

  List<SubstationWorkSpec> _armed = const <SubstationWorkSpec>[];

  /// The armed roster [resolveArmedRoster] resolved — what [boot] assembles
  /// over. Empty until resolved.
  List<SubstationWorkSpec> get armedRoster => _armed;

  /// Resolves and RETAINS the armed roster: applies [armRoster] (the
  /// overridable policy), refuses an empty result LOUD, and stores the
  /// outcome for [boot]. Called by the shell exactly once per delegate
  /// instance, before the boot rail (a hot restart's fresh delegate is
  /// re-resolved by the shell's delegate factory).
  @nonVirtual
  List<SubstationWorkSpec> resolveArmedRoster({
    required List<SubstationWorkSpec> coded,
    required List<SubstationConfig> appended,
    required void Function(String message) onSkip,
  }) {
    final armed = armRoster(coded: coded, appended: appended, onSkip: onSkip);
    if (armed.isEmpty) {
      throw const StationRefusal(
        'no substation resolved a work store at its root.',
        code: 1,
      );
    }
    return _armed = List.unmodifiable(armed);
  }

  /// THE arming policy (relocated from the command's for-loops, tg-1fa2.4 —
  /// pre-tree by necessity, ratchet debt under STYLE.md rule 5; see the class
  /// doc): which seats arm is a station opinion. The standing default: a
  /// CODED seat whose root resolves no work store is skipped loudly via
  /// [onSkip] (not present in this checkout — a legitimate partial checkout);
  /// an APPENDED seat that refuses is a boot refusal ([StationRefusal] — the
  /// operator explicitly asked for it, so absence is an error: exit 64 for a
  /// malformed spec, exit 1 for a missing store).
  ///
  /// Override to change the opinion; the shell renders whatever this decides
  /// (messages are written without the `<station> up: ` prefix — the shell
  /// adds it).
  List<SubstationWorkSpec> armRoster({
    required List<SubstationWorkSpec> coded,
    required List<SubstationConfig> appended,
    required void Function(String message) onSkip,
  }) {
    final locator = StoreLocator();
    final armed = <SubstationWorkSpec>[];
    for (final seat in coded) {
      try {
        locator.locateWorkStore(root: seat.root, substationName: seat.name);
        armed.add(seat);
      } on StoreRefusal {
        onSkip(
          'skipping coded substation "${seat.name}" — no work store '
          'at ${seat.root} (not present in this checkout).',
        );
      }
    }
    for (final seat in appended) {
      try {
        locator.locateWorkStore(root: seat.root, substationName: seat.name);
        armed.add(
          SubstationWorkSpec(
            name: seat.name,
            root: seat.root,
            prefix: seat.prefix,
          ),
        );
      } on ArgumentError catch (error) {
        throw StationRefusal('${error.message}', code: 64);
      } on StoreRefusal catch (error) {
        throw StationRefusal('$error', code: 1);
      }
    }
    return armed;
  }

  /// The staleness posture over the inspected freshness vector (relocated
  /// from the command's `--allow-stale` refusal, tg-1fa2.4 — pre-tree by
  /// necessity, ratchet debt under STYLE.md rule 5; see the class doc).
  /// [verdicts] is
  /// the rendered per-seat verdict line (`earth: fresh, moon: stale: …`, in
  /// roster order); the standing default refuses any stale checkout unless
  /// [allowStale] downgrades the refusal to one warning.
  StalenessPosture stalenessPosture({
    required bool anyStale,
    required bool allowStale,
    required String verdicts,
  }) {
    if (!anyStale) return const StalenessClear();
    if (!allowStale) {
      return StalenessRefused(
        'refusing stale primary checkout(s): {$verdicts}; '
        'pass --allow-stale to warn and continue.',
      );
    }
    return StalenessWarned(
      'WARNING --allow-stale accepted primary checkout verdicts: {$verdicts}',
    );
  }

  /// The narrow status view (valid once [boot] completed), or null when this
  /// station vends none — absence is a designed posture (docs/STYLE.md rule
  /// 3): the shell reports what it can without one, never throws.
  ///
  /// The null default compiles, so a forgotten override is silent at build
  /// time: a production station should override [stationView] (and
  /// [commandHandler]) — a delegate vending neither still boots, but renders
  /// an empty work axis and refuses every operator command.
  StationView? get stationView => null;

  /// The operator-command handler `POST /command` dispatches to (valid once
  /// [boot] completed), or null when this station vends none — the control
  /// surface then refuses commands with a clear message (docs/STYLE.md rule
  /// 3: absence is rendered, never converted into an exception). Production
  /// stations should override this (see [stationView]).
  GridCommandHandler? get commandHandler => null;

  /// The `runGrid(onFlushed:)` hook — post-flush machinery (cooldown and
  /// unclaimed-frontier re-scans) on the boot-assembled runtime. Default:
  /// nothing rides the flush rail.
  void afterFlush() {}

  /// The `runGrid(orphanSweep:)` hook — the teardown-vs-spawn reap on the
  /// boot-assembled runtime. The runner calls it AFTER the tree unmounted
  /// (the stragglers it reconciles only exist once the kills are in flight)
  /// and BEFORE [dispose] — an implementation may rely on everything boot
  /// assembled still being live. Default: nothing to sweep.
  Future<void> sweepOrphans() async {}

  /// The store connections this delegate's boot opened, in shutdown order
  /// (state store first — it is the last writer). Default: none.
  ///
  /// The shell reads this while the delegate is still live, and closes the
  /// handles after the tree unmounted and [sweepOrphans] ran — the tree, the
  /// sweep and the trajectory all read their stores on the way down. The
  /// handles must therefore survive [dispose], and their [StoreConnection.close]
  /// must be idempotent: a boot-assembled [StationWorkRuntime.shutdown] closes
  /// the same pools.
  ///
  /// This is a handle vend, not a state read: it exposes no `StateNotifier`
  /// state, exactly as [stationView] and [sweepOrphans] vend reference types
  /// out of the delegate.
  ///
  /// The shell owns this because [dispose] is synchronous and void. A delegate
  /// can only fire the async store shutdown and drop its future; an unawaited
  /// close leaves established proxy sockets able to keep the resident alive.
  List<StoreConnection> get openStores => const <StoreConnection>[];

  // Deliberately NO ambient `of`/`maybeOf` accessor for the delegate itself.
  //
  // A `GridDelegate` IS a `StateNotifier<GridConfiguration>`; handing its
  // instance to a consumer is a public SYNCHRONOUS handle on reactive state —
  // exactly the leak ADR-0008 D-H bans (no public sync accessors over notifier
  // state). Configuration reaches consumers ONLY as an *observed value*:
  // `runGrid` holds this delegate (it never rides the tree) and provides its
  // emitted `GridConfiguration` below as an ambient value, read with
  // `GridConfiguration.of(context)` — which SUBSCRIBES, so a re-emission
  // re-composes the reader. If a rail ever needs the current configuration, the
  // framework passes it as a parameter (a value), never an accessor.
  //
  // The `dh_state_leak_gate_test` fences this structurally.
}

/// A lifecycle-rail failure, **captured and attributed** — which [hook] threw,
/// on which [delegateType] — so it surfaces as a *named refusal*, never a bare
/// stack trace from library plumbing (v3 §4; the guard principle: loud when an
/// invariant is violated).
///
/// A `didLaunch` or `boot` failure is thrown from `runGrid` (the launch aborts).
/// The post-mount rails ([GridDelegate.initGrid] / [GridDelegate.onReady] /
/// [GridDelegate.onTeardown]) cannot throw to a caller, so `runGrid` reports
/// their refusals through its error sink (loud by default — rethrown into the
/// current zone).
class GridHookError extends Error {
  /// Wraps [cause] (with its [causeStackTrace]) thrown by [hook] on a delegate
  /// of type [delegateType].
  GridHookError(this.hook, this.delegateType, this.cause, this.causeStackTrace);

  /// The rail that threw: `didLaunch` / `boot` / `initGrid` / `onReady` /
  /// `onTeardown`.
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
