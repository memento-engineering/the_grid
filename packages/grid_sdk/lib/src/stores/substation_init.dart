import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';

import '../composition/composition.dart';
import 'stores.dart';

/// Seeds a fresh beads work store at [root] whose id-prefix is [prefix] — the
/// injected primitive behind the substation initialization flow (Fakes, not
/// mocks). The default ([defaultBeadStoreSeeder]) shells out to
/// `bd init --prefix <prefix>`.
///
/// Contract: on success a `.beads/` store exists at `<root>/.beads/` with
/// [prefix] as its issue-id prefix; on failure the seeder throws (the flow turns
/// that into a [StoreRefusal]). It must NOT clobber an existing store — the flow
/// guards that before calling, but a seeder should be safe regardless.
typedef BeadStoreSeeder =
    Future<void> Function({required String root, required String prefix});

/// The real seeder: `bd init --prefix <prefix>` in [root]. Throws on a non-zero
/// exit (LOUD — a failed seed must never look like a seeded store).
///
/// Deliberately raw `Process.run`, NOT routed through the `BdRunner`/
/// `beads_dart` chokepoint: this call runs BEFORE any `.beads/` store exists
/// at [root] for a runner to bind to (a runner is constructed against a
/// `workspaceRoot` that already holds a store). This is bootstrap, not a
/// controller-path spawn — exempted by ruling, tg-8gv.11(d).
Future<void> defaultBeadStoreSeeder({
  required String root,
  required String prefix,
}) async {
  final result = await Process.run('bd', [
    'init',
    '--prefix',
    prefix,
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw StoreRefusal(
      'bd init --prefix $prefix failed in $root (exit ${result.exitCode}): '
      '${result.stderr}',
    );
  }
}

/// The result of a successful substation initialization — the freshly-seeded
/// project, ready to **mount in the tree**.
///
/// [name] is the substation name AND its store's adopted id-prefix (they are the
/// same axis: a substation's name is its `metadata.rig` marker and its issue-id
/// prefix). [toSeed] produces the Track B [Substation] the author drops into the
/// station's `Substations` fan-out — the "mount it in the tree" step made
/// concrete.
class SubstationInitResult {
  /// A substation named/prefixed [name], seeded at [root].
  const SubstationInitResult({required this.name, required this.root});

  /// The substation name — also the store's adopted id-prefix.
  final String name;

  /// The substation's single root (absolute), now holding a `.beads/` store.
  final String root;

  /// The freshly-seeded work store's location.
  SubstationWorkStore get store => SubstationWorkStore(root: root);

  /// Mounts the initialized substation into the tree — the final step of the
  /// flow (seed → adopt prefix → **mount**). Returns the Track B [Substation]
  /// with the seeded [name]/[root] and the author's [assets]; the author places
  /// it in the station's `Substations`.
  Seed toSeed({List<Seed> assets = const <Seed>[]}) =>
      Substation(name, root, assets: assets);

  @override
  bool operator ==(Object other) =>
      other is SubstationInitResult && other.name == name && other.root == root;

  @override
  int get hashCode => Object.hash(name, root);

  @override
  String toString() => 'SubstationInitResult(name: $name, root: $root)';
}

/// The **substation initialization flow** (Q-mig) as first-class code: given a
/// root and a name, it *seeds a new substation's work store at its root, adopts
/// its prefix, and yields the substation to mount in the tree*. Documented as a
/// process in `docs/SUBSTATION-INIT.md`.
///
/// A Service (stateless I/O): all its I/O rides two injected seams — the store
/// [BeadStoreSeeder] and a [DirectoryProbe] — so the flow is pure and
/// offline-testable (Fakes, not mocks). It clobbers nothing: a root that already
/// holds a `.beads/` store is a LOUD refusal, not a re-seed.
class SubstationInitializer {
  /// Creates the flow; [seed] defaults to the real [defaultBeadStoreSeeder] and
  /// [dirExists] to the real [defaultDirectoryProbe].
  SubstationInitializer({BeadStoreSeeder? seed, DirectoryProbe? dirExists})
    : _seed = seed ?? defaultBeadStoreSeeder,
      _dirExists = dirExists ?? defaultDirectoryProbe;

  final BeadStoreSeeder _seed;
  final DirectoryProbe _dirExists;

  /// Initializes a new substation named [name] at [root]:
  ///
  /// 1. **Validate** — [root] is absolute (loud refusal otherwise), [name] is a
  ///    non-empty, whitespace/separator-free store prefix.
  /// 2. **No clobber** — refuse LOUD if a `.beads/` store already exists at
  ///    `<root>/.beads/` (init is for a *new* substation; re-seeding is not this
  ///    flow's job).
  /// 3. **Seed** — the store at the root, adopting [name] as its issue-id prefix
  ///    (`bd init --prefix <name>`).
  /// 4. **Verify** — the store now exists (a seeder that silently no-ops is
  ///    caught here, not discovered later at the mount boundary).
  /// 5. **Yield** — a [SubstationInitResult] whose [SubstationInitResult.toSeed]
  ///    mounts the substation in the tree.
  Future<SubstationInitResult> initSubstation({
    required String root,
    required String name,
  }) async {
    requireAbsoluteRoot(root, 'SubstationInitializer');
    _requirePrefix(name);

    final store = SubstationWorkStore(root: root);
    if (_dirExists(store.beadsDir)) {
      throw StoreRefusal(
        'refusing to initialize substation "$name" at "$root" — a `.beads/` '
        'store already exists (${store.beadsDir}). The init flow seeds a NEW '
        'substation; it never clobbers an existing store. Mount the existing '
        'substation directly, or remove/relocate the store first.',
      );
    }

    await _seed(root: root, prefix: name);

    if (!_dirExists(store.beadsDir)) {
      throw StoreRefusal(
        'substation "$name" init at "$root" reported success but seeded no '
        'store — expected `.beads/` at ${store.beadsDir}. The seed silently '
        'no-op\'d; refusing rather than mounting a substation with no store.',
      );
    }

    return SubstationInitResult(name: name, root: root);
  }

  /// A substation name IS its store's id-prefix (`metadata.rig` marker + the
  /// issue-id prefix). A prefix must be a single non-empty token — refuse
  /// whitespace and path separators LOUD before the seed (bd would reject them,
  /// but an early loud refusal names the offender at the authoring boundary).
  static void _requirePrefix(String name) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'SubstationInitializer: name must be non-empty',
      );
    }
    if (name != name.trim() ||
        name.contains(RegExp(r'\s')) ||
        name.contains('/') ||
        name.contains(r'\')) {
      throw ArgumentError.value(
        name,
        'name',
        'SubstationInitializer: a substation name is its store id-prefix — it '
            'must be a single token with no whitespace or path separators',
      );
    }
  }
}
