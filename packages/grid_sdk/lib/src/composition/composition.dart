import 'package:genesis_tree/genesis_tree.dart';
import 'package:path/path.dart' as p;

import 'scopes.dart';

/// Validates a root path LOUD (release-safe): non-empty and absolute.
///
/// cwd-relative roots are the ambience fossil the v3 model kills (§7:
/// "cwd discovery under arming") — a root is authored absolute or refused.
/// Returns [root] so callers can validate-and-use in one expression.
String _requireRoot(String root, String owner) {
  if (root.trim().isEmpty) {
    throw ArgumentError.value(root, 'root', '$owner: root must be non-empty');
  }
  if (!p.isAbsolute(root)) {
    throw ArgumentError.value(
      root,
      'root',
      '$owner: root must be an ABSOLUTE path — cwd-relative roots re-import '
          'the ambience the v3 model kills (unresolvable input = loud refusal)',
    );
  }
  return root;
}

String _requireName(String name, String owner) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(name, 'name', '$owner: name must be non-empty');
  }
  return name;
}

/// Mounts an `assets:` slot — the multi-child fan-out under every composition
/// scope (Q7: asset slots are `List<Seed>`; group stacks with [Nest]).
///
/// Not exported: an implementation detail of the composition Seeds.
class AssetFanOut extends MultiChildSeed {
  /// Mounts [assets] in order.
  const AssetFanOut(List<Seed> assets, {super.key}) : super(children: assets);
}

/// The raw grid root — the `WidgetsApp`-to-`MaterialApp` relationship (v3 §3):
/// unopinionated, low-level. A batteries-included `Grid` analogue can layer on
/// top later.
///
/// [root] is **the grid's home**: the grid's state store lives under
/// `<root>/.grid/` (Q5a) and the grid has NO work store. The root is provided
/// to the whole tree as the ambient [GridRoot] — a `Station` authored without
/// its own `root` defaults to it.
///
/// Everything else — config providers, federation discovery, the `Station`
/// itself — mounts through [assets] (an asset is *anything mounted into the
/// tree at a scope*, GLOSSARY R3).
class RawAssetGrid extends StatelessSeed {
  /// Roots a grid at [root] and mounts [assets] under the [GridRoot] scope.
  const RawAssetGrid({
    required this.root,
    this.assets = const <Seed>[],
    super.key,
  });

  /// The grid's home (absolute; validated loud at build).
  final String root;

  /// Grid-scoped assets — serve the deployment (v3 §3).
  final List<Seed> assets;

  @override
  Seed build(TreeContext context) {
    _requireRoot(root, 'RawAssetGrid');
    return InheritedSeed<GridRoot>(
      value: GridRoot(path: root),
      child: AssetFanOut(assets),
    );
  }
}

/// The machine (GLOSSARY: Station) — one runtime, one reconcile loop, one
/// capacity budget.
///
/// [root] is optional and defaults to the ambient [GridRoot] (v3 §3). A
/// `Station` authored with neither a `root` nor an enclosing [RawAssetGrid]
/// refuses loud. Station-scoped [assets] serve the machine: harness
/// providers, platform providers, and the `Substations` fan-out itself.
class Station extends StatelessSeed {
  /// A station named [name], rooted at [root] (or the grid root), mounting
  /// [assets] under its [StationScope].
  const Station({
    required this.name,
    this.root,
    this.assets = const <Seed>[],
    super.key,
  });

  /// The machine's name.
  final String name;

  /// The station's root; null defaults to the ambient [GridRoot].
  final String? root;

  /// Station-scoped assets — serve the machine (v3 §3).
  final List<Seed> assets;

  @override
  Seed build(TreeContext context) {
    _requireName(name, 'Station');
    final explicit = root;
    // The defaulted grid root is RE-validated: a GridRoot can reach the tree
    // from a consumer-authored InheritedSeed, not only RawAssetGrid.build —
    // the refusal holds at every mount point, not just the canonical one.
    final resolved = _requireRoot(
      explicit ??
          (GridRoot.maybeOf(context) ??
                  (throw StateError(
                    'Station("$name"): no root authored and no RawAssetGrid '
                    'encloses it — there is no default root (v3 §0).',
                  )))
              .path,
      'Station("$name")',
    );
    return InheritedSeed<StationScope>(
      value: StationScope(name: name, root: resolved),
      child: AssetFanOut(assets),
    );
  }
}

/// The substation fan-out (v3 §3): a [MultiChildSeed] whose children are the
/// station's [Substation]s — literal, composed (a seed that *builds* a
/// `Substation`, never subclasses it — ADR-0008 D2), or conditional
/// (`if (kDebug) Substation(...)`). Plain language features ARE the
/// configuration language (v3 §1).
class Substations extends MultiChildSeed {
  /// Fans out [substations].
  const Substations({required List<Seed> substations, super.key})
    : super(children: substations);
}

/// A project (GLOSSARY: Substation) — a name and **ONE root**, never sets,
/// never defaults (v3 §0). Its work store lives at `<root>/.beads/` —
/// a store lives at a root, uniformly (Q5a).
///
/// Substation-scoped [assets] serve the project: source control
/// (git/GitHub assets), circuit providers, orders. Extend by **composition**:
/// a domain substation is a seed whose `build` returns a `Substation` with
/// its own assets folded in (v3 §2's `ButaneDevelopmentSubstation`).
class Substation extends StatelessSeed {
  /// A substation named [name] with the single [root], mounting [assets]
  /// under its [SubstationScope].
  ///
  /// Carries an intrinsic identity key (`ValueKey('substation:<name>')`)
  /// unless [key] overrides it: sibling substations reconcile by NAME, never
  /// by position — so a conditional substation anywhere in the fan-out
  /// (`if (kDebug) Substation(...)`) can appear or vanish without a
  /// neighbour's live subtree (post-Track-C: its WorkList, worktrees, lock)
  /// rebinding onto the wrong project identity.
  Substation({
    required this.name,
    required this.root,
    String? prefix,
    this.assets = const <Seed>[],
    Key? key,
  }) : prefix = prefix ?? name,
       super(key: key ?? ValueKey<String>('substation:$name'));

  /// The project's name (the tree identity + the `metadata.rig` marker axis).
  final String name;

  /// The project's single root (absolute; validated loud at build).
  final String root;

  /// The work store's issue-id prefix — a SEPARATE axis from [name] (Nico,
  /// 2026-07-08; `SUBSTATION-INIT.md` §2): `the_grid` (name) mints `tg-…`
  /// (prefix). Defaults to [name] for the stations whose short name IS the
  /// prefix. Ownership matches either axis.
  final String prefix;

  /// Substation-scoped assets — serve the project (v3 §3).
  final List<Seed> assets;

  @override
  Seed build(TreeContext context) {
    _requireName(name, 'Substation');
    _requireName(prefix, 'Substation("$name").prefix');
    _requireRoot(root, 'Substation("$name")');
    return InheritedSeed<SubstationScope>(
      value: SubstationScope(name: name, root: root, prefix: prefix),
      child: AssetFanOut(assets),
    );
  }
}
