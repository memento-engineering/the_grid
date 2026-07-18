import 'package:genesis_tree/genesis_tree.dart';
// The engine's OLD SubstationScope seed collides in name with the SDK's scope
// VALUE (`scopes.dart`) — hide it; this module reads only the SDK scope.
import 'package:grid_engine/grid_engine.dart' hide SubstationScope;

import '../composition/scopes.dart';

/// The station-level work-axis wiring — the ambient VALUES [StationWork]
/// provides to the work subtree (the same stack `StationKernel.start` mounts
/// above the engine's `Station` seed, tg-yl8): the work-axis
/// [JoinedSnapshotNotifier], the machine's [StationServices], the
/// bead→work-Seed [SessionResolver], and the reentrant [CapabilityRegistry].
///
/// Impls = DI (ADR-0008 D-H): every field is constructed OFF-tree by the
/// runner's assembly (`buildStationWork`) and enters the tree only as a
/// provided value — a branch holds config values and effect handles, never
/// builds a service.
class StationWorkWiring {
  /// Bundles the four ambient work-axis values.
  const StationWorkWiring({
    required this.notifier,
    required this.services,
    required this.resolver,
    this.registry,
  });

  /// The work-axis notifier the substations' `WorkList`s observe — driven by
  /// the (off-tree) `StationJoinBridge`, the lone pipeline subscription (A39).
  final JoinedSnapshotNotifier notifier;

  /// The machine's ambient services (transport + the bd write chokepoint +
  /// the owned state partition — ADR-0009 D2).
  final StationServices services;

  /// The bead→work-Seed seam (ADR-0007 D5 / ADR-0008 D4).
  final SessionResolver resolver;

  /// The reentrant capability/circuit registry; null when the resolver roots a
  /// non-reentrant subtree (a fake returning a plain leaf needs none).
  final CapabilityRegistry? registry;
}

/// The STATION-scoped work asset (tg-yl8): provides the engine's ambient
/// work-axis stack — [StationWorkWiring]'s four values — to everything below,
/// so each `Substation`'s [SubstationWork] can mount the engine's `WorkList`
/// INSIDE the `runGrid` tree ("each child `Substation` establishes its
/// `WorkList`", v3 §3).
///
/// Mounted as a station asset ABOVE the `Substations` fan-out (typically under
/// `HarnessProvider`); chains in a `Nest`. The provided stack is exactly
/// `StationKernel.start`'s, in the same order (notifier outermost). The
/// off-tree machinery those values are driven by (the join bridge, the D-5
/// cooldown Timer, the restart reconciler) is the runner-held
/// `StationWorkRuntime` — unmounting this asset stops NOTHING by itself; the
/// runner tears the tree down first, then its runtime (`grid.teardown()` →
/// `runtime.shutdown()`).
class StationWork extends SingleChildStatelessSeed {
  /// Provides [wiring]'s values ambiently over [child] (supplied by an
  /// enclosing `Nest` when chained).
  const StationWork({required this.wiring, super.child, super.key});

  /// The DI'd work-axis values (built by `buildStationWork`).
  final StationWorkWiring wiring;

  @override
  Seed buildWithChild(TreeContext context, Seed child) {
    Seed out = child;
    final registry = wiring.registry;
    if (registry != null) {
      out = InheritedSeed<CapabilityRegistry>(value: registry, child: out);
    }
    out = InheritedSeed<SessionResolver>(value: wiring.resolver, child: out);
    out = InheritedSeed<StationServices>(value: wiring.services, child: out);
    return InheritedSeed<JoinedSnapshotNotifier>(
      value: wiring.notifier,
      child: out,
    );
  }
}

/// The SUBSTATION-scoped work seat (tg-yl8): mounts the engine's `WorkList`
/// for the enclosing `Substation` — the node H2's placeholder leaf held open.
///
/// Reads the ambient [SubstationScope] (LOUD outside a `Substation` — an
/// authoring error, not a default) and the ambient work-axis notifier
/// ([StationWork] provides it). **Unarmed grace:** with no [StationWork]
/// above (the offline / authoring-only mount, H2's shape), it mounts nothing —
/// the tree stands, drives no work. Armed, it derives the engine's
/// `SubstationConfig` from the scope — `substationId` = the name,
/// `ownedSubstations` = {name, prefix} (BOTH identity axes: the id prefix is
/// ownership's primary axis, the `metadata.rig` marker its belt —
/// `BeadOwnershipPredicate`; names ≠ prefixes, Nico 2026-07-08) — and builds
/// the `WorkList`.
///
/// This node is CONFIG (an ancestor of work nodes, ADR-0007): it depends only
/// on config-axis inherited values (the scope, the notifier HANDLE — which
/// never notifies on a work tick), so a snapshot emission rebuilds only the
/// `WorkList` below it (derailment-invariant 1).
class SubstationWork extends StatelessSeed {
  /// Creates the work seat. [resident] narrows the mount boundary to
  /// driveable work types (RS-3/D-R4 — a resident station's ready frontier IS
  /// the drive set); [maxConcurrentWork] is the per-substation governor
  /// override (null falls back to the station ceiling); [driveList] is the
  /// ADR-0006 blessed-bead gate for a NON-resident arm (when non-empty, ONLY
  /// those bead ids mount) — a resident station never sets it (D-R1/D-R4: no
  /// drive-list, ever; the frontier is the drive set). [circuitMintMode] is
  /// the live-arm switch for the molecule model: the SDK's single work-seat
  /// composition now mints molecule sessions by default, while tests and
  /// future non-live callers can name [CircuitMintMode.flatCursor] explicitly.
  const SubstationWork({
    this.resident = true,
    this.maxConcurrentWork,
    this.driveList = const <String>{},
    this.circuitMintMode = CircuitMintMode.molecule,
    super.key,
  });

  /// Resident all-ready arming (RS-3/D-R4).
  final bool resident;

  /// The per-substation concurrency override (tg-42f); null = station default.
  final int? maxConcurrentWork;

  /// The blessed-bead drive-list (ADR-0006) — empty for a resident station.
  final Set<String> driveList;

  /// The circuit mint model a fresh [SessionScope] reads from
  /// [SubstationConfig]. Existing sessions keep their durable
  /// `grid.session.model` stamp and are never reinterpreted by this value.
  final CircuitMintMode circuitMintMode;

  @override
  Seed build(TreeContext context) {
    final scope = SubstationScope.of(context);
    // The tree/build verb (subscribing): a re-provided notifier VALUE (not an
    // emission — the handle itself) re-composes this seat. Null = unarmed.
    final notifier = context
        .dependOnInheritedSeedOfExactType<JoinedSnapshotNotifier>();
    if (notifier == null) return const _UnarmedWork();
    return WorkList(
      substationConfig: SubstationConfig(
        substationId: scope.name,
        ownedSubstations: {scope.name, scope.prefix},
        resident: resident,
        driveList: driveList,
        maxConcurrentWork: maxConcurrentWork,
        circuitMintMode: circuitMintMode,
      ),
      key: ValueKey<String>('worklist:${scope.name}'),
    );
  }
}

/// The unarmed seat — nothing mounts, the authored tree stands (H2's shape).
class _UnarmedWork extends MultiChildSeed {
  const _UnarmedWork() : super(children: const <Seed>[]);
}
