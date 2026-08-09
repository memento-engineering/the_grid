/// The resident station's delegate contract (tg-1fa2.4).
///
/// The delegate-boot + mounted-provider composition: a resident delegate is
/// constructed from parsed configuration ALONE, assembles its off-tree work
/// machinery inside the `GridDelegate.boot` rail (awaited by `runGrid` before
/// the first mount — once per delegate instance, fresh delegate + fresh boot
/// on hot restart), and VENDS the narrow views the command shell reads.
/// Reference types flow OUT of the delegate, never in.
library;

import 'package:grid_engine/grid_engine.dart' show JoinedSnapshot, WedgeState;
import 'package:grid_sdk/grid_sdk.dart'
    show
        GridCommandHandler,
        GridDelegate,
        StoreLocator,
        StoreRefusal,
        SubstationWorkSpec;
import 'package:meta/meta.dart';

import 'resident_station_flags.dart';
import 'station_lock.dart';

/// The narrow status view a resident delegate vends — the VALUES the command
/// shell's banner, `/status` view, and dev-mode seat read. A view over the
/// boot-assembled work machinery; never the runtime object wholesale.
abstract interface class ResidentStationView {
  /// The owned state partition sessions are minted into.
  String get stateSubstation;

  /// The controllers' read-path provenance (banner material).
  String get readPathName;

  /// The producer-side latest join (status counts read THIS).
  JoinedSnapshot get latest;

  /// The station's wedge signal — one truth for "is the grid stuck?".
  WedgeState get wedge;

  /// The JSON-shaped sync-loop observability payload for `/status` (tg-zd4v):
  /// per-store `GraphSyncStats` under `stats`, the federation's per-member
  /// freshness vector under `freshness`. Empty when the assembly exposes none.
  Map<String, Object?> syncStatus();
}

/// The staleness posture a resident delegate chooses over the inspected
/// primary-checkout freshness vector — a station opinion (relocated from the
/// command's inline refusal, tg-1fa2.4), rendered by the shell.
sealed class StalenessPosture {
  const StalenessPosture();
}

/// Every checkout fresh — proceed silently.
final class StalenessClear extends StalenessPosture {
  /// Const-constructible.
  const StalenessClear();
}

/// Stale but accepted (`--allow-stale`): the shell warns with [message] on
/// stderr and proceeds.
final class StalenessWarned extends StalenessPosture {
  /// Creates the warning posture.
  const StalenessWarned(this.message);

  /// The warning line (the shell prefixes `<station> up: `).
  final String message;
}

/// Stale and refused: the shell writes [message] on stderr and exits 64.
final class StalenessRefused extends StalenessPosture {
  /// Creates the refusal posture.
  const StalenessRefused(this.message);

  /// The refusal line (the shell prefixes `<station> up: `).
  final String message;
}

/// A station-authored delegate the resident `up` command can drive.
///
/// The composition contract, in lifecycle order:
///
///  1. **Construction is config-only** (the resident `up` command's
///     `delegateFactory` receives the parsed [ResidentStationConfig] and
///     nothing else). No wiring, no provisioner, no effect implementations
///     enter the factory — assembly is [boot]-owned. The dry-run effect
///     posture TODAY is boot-selected OFF-tree: boot passes the config's
///     `dryRun` to `assembleStationWork`, which selects inert implementations
///     by type. Declaring the posture in the TREE (dry-run mounts no effect
///     providers, so the projection sees the absence) is the TARGET state,
///     owned by the reference-boot follow-up bead.
///  2. **[resolveArmedRoster]** — the shell calls it exactly once per
///     delegate instance, BEFORE the boot rail, folding the station's arming
///     policy (skip a coded seat with no store, refuse an appended one) over
///     the roster. The delegate retains the result ([armedRoster]) — what
///     [boot] assembles over.
///  3. **`boot`** (`runGrid` awaits it before the first mount) — assembles
///     AND starts the off-tree work machinery, including the diagnostics
///     reporter effect (previously the command's one hardcoded seamless
///     effect). Assembly only — no NEW policy may enter it (the rule-5
///     ratchet; see the honest posture note below).
///  4. **The vended views** ([stationView], [commandHandler], [afterFlush],
///     [sweepOrphans]) are valid once `boot` completed; the shell reads them
///     per request, never earlier. The diagnostics `TreeProjector` is NOT a
///     delegate concern: it is shell-owned and process-lifetime (the shell
///     threads ONE instance into `runGrid` and `/stream`, and a hot restart's
///     fresh delegate flushes into that same sink — a delegate-owned
///     projector would be disposed with the retired delegate and leave the
///     flush rail and `/stream` permanently dark).
///  5. **`dispose`** unwinds what boot assembled, in reverse creation order.
///     It does NOT presume the earlier steps ran: `dispose` MUST tolerate
///     (i) a delegate whose [resolveArmedRoster]/`boot` never ran and (ii) a
///     boot that threw partway through assembly — the shell disposes
///     never-booted delegates on its refusal paths (roster refusal,
///     staleness, lock conflict); the runner (`runGrid`) disposes a
///     partially-booted one when the boot rail
///     throws. Implement it over nullable fields or a booted flag; never
///     assume boot completed.
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
/// **OPEN SEAM — no reference boot implementation ships yet.** This contract
/// specifies the delegate half of the tg-1fa2.4 migration (boot-owned
/// `assembleStationWork` + the `StationDiagnosticsReporter` effect, views
/// vended over the assembled `StationWorkRuntime`; dry-run as provider
/// ABSENCE in the tree is that follow-up's target — today
/// `assembleStationWork` selects inert implementations off-tree from its
/// `dryRun` flag), but grid_cli ships only the abstract
/// contract — every concrete `boot` today lives in tests. The reference
/// boot-owned assembly delegate is deliberate follow-up work under the
/// tg-1fa2 epic (file it as its own bead when composing the first production
/// station on this command); until it lands, a composing station authors its
/// own `boot` from this contract plus `assembleStationWork`'s docs.
abstract class ResidentGridDelegate extends GridDelegate {
  /// Creates the delegate seeded like any [GridDelegate].
  ResidentGridDelegate([super.initialConfiguration]);

  List<SubstationWorkSpec> _armed = const <SubstationWorkSpec>[];

  /// The armed roster [resolveArmedRoster] resolved — what `boot` assembles
  /// over. Empty until resolved.
  List<SubstationWorkSpec> get armedRoster => _armed;

  /// Resolves and RETAINS the armed roster: applies [armRoster] (the
  /// overridable policy), refuses an empty result LOUD, and stores the
  /// outcome for `boot`. Called by the shell exactly once per delegate
  /// instance, before the boot rail (a hot restart's fresh delegate is
  /// re-resolved by the shell's delegate factory).
  @nonVirtual
  List<SubstationWorkSpec> resolveArmedRoster({
    required List<SubstationWorkSpec> coded,
    required List<ResidentSubstationConfig> appended,
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
    required List<ResidentSubstationConfig> appended,
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

  /// The narrow status view (valid once `boot` completed).
  ResidentStationView get stationView;

  /// The operator-command handler `POST /command` dispatches to (valid once
  /// `boot` completed).
  GridCommandHandler get commandHandler;

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
}
