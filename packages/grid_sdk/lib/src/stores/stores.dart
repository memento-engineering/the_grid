import 'dart:io';

import 'package:path/path.dart' as p;

import '../composition/scopes.dart';

/// The runtime dir name under a grid root — holds the grid's STATE store and
/// the station lock (Q5a: state lives under `<grid.root>/.grid/…`).
const String kGridRuntimeDirName = '.grid';

/// The store dir name at a root — **`.beads/` means *work store*, uniformly,
/// everywhere** (Q5a). A substation's work store is `<root>/.beads/`; the grid's
/// own state store nests one under `.grid/` (`<grid.root>/.grid/.beads/`) so the
/// dual-role repo never collides its work store with its state store.
const String kWorkStoreDirName = '.beads';

/// The station lock file — one supervisor per station STATE store (D-A1). It
/// **colocates** with the grid state store inside `<grid.root>/.grid/`.
const String kStationLockFileName = 'station.lock';

/// Raised when a required store is absent (or misplaced) at a root — a LOUD boot
/// refusal, never a silent default (the guard principle: LOUD or gone).
///
/// The v3 model kills cwd/walk-up store discovery (SCRATCH §7 item 9): a store is
/// expected **exactly at a root**, so its absence is an authoring/ops error the
/// operator must fix (run the substation init flow, or correct the root), not a
/// condition the framework papers over by searching upward.
class StoreRefusal implements Exception {
  /// Refuses with a human-readable [message] (names the root + the invariant).
  const StoreRefusal(this.message);

  /// The refusal detail — names the offending root and the remedy.
  final String message;

  @override
  String toString() => 'StoreRefusal: $message';
}

/// Validates a root path is a non-empty ABSOLUTE path, LOUD (release-safe).
///
/// Mirrors the composition layer's authoring guard (an absolute root or a loud
/// refusal — cwd-relative roots re-import the ambience the v3 model kills) but
/// applies at the store/ops boundary, where the root is an operator-supplied
/// string rather than an already-validated `GridRoot`/`SubstationScope`. Returns
/// [root] so callers validate-and-use in one expression.
String requireAbsoluteRoot(String root, String owner) {
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

/// The grid's **state store** location — one per grid (Q5a).
///
/// Everything the grid owns about itself lives under `<gridRoot>/.grid/`: the
/// state beads store (session / cursor / gate lifecycle beads — A37) at
/// [beadsDir], and the station lock ([lockPath]) *colocated* beside it. This is
/// deliberately **not** a `<gridRoot>/.beads/` store — `.beads/` at a root means
/// *work* store, so nesting the state store under `.grid/` lets the dual-role
/// repo (a grid whose own root is also a substation under development) hold its
/// work store at `<gridRoot>/.beads/` and its state at `<gridRoot>/.grid/.beads/`
/// with no collision.
///
/// A plain immutable value: a derivation locator over one root — no union, no
/// serialization, so it stays plain rather than freezed (house rule: value types
/// are plain).
class GridStateStore {
  /// Locates the state store for the grid rooted at [gridRoot].
  const GridStateStore({required this.gridRoot});

  /// Locates the state store for the grid rooted at [gridRoot], refusing a
  /// non-absolute root LOUD.
  factory GridStateStore.forGridRoot(String gridRoot) =>
      GridStateStore(gridRoot: requireAbsoluteRoot(gridRoot, 'GridStateStore'));

  /// The grid's home (absolute).
  final String gridRoot;

  /// The runtime dir — `<gridRoot>/.grid/`. Holds the state beads store and the
  /// station lock. This is the store root a `bd`/`BeadsWorkspace` treats as its
  /// working directory (its `.beads/` subdir is [beadsDir]).
  String get runtimeDir => p.join(gridRoot, kGridRuntimeDirName);

  /// The state store's beads dir — `<gridRoot>/.grid/.beads/`. A `.beads/`
  /// *under* `.grid/` (never at a root) is unambiguously the grid's own state,
  /// never a work store.
  String get beadsDir => p.join(runtimeDir, kWorkStoreDirName);

  /// The station lock path — `<gridRoot>/.grid/station.lock` — colocated with
  /// the state store. Equal to `StationLockService.lockPath(gridRoot)` (the lock
  /// service already writes `<dir>/.grid/station.lock`; its input re-sources to
  /// the grid root in the runner — SCRATCH E4).
  String get lockPath => p.join(runtimeDir, kStationLockFileName);

  @override
  bool operator ==(Object other) =>
      other is GridStateStore && other.gridRoot == gridRoot;

  @override
  int get hashCode => gridRoot.hashCode;

  @override
  String toString() => 'GridStateStore(gridRoot: $gridRoot)';
}

/// A substation's **work store** location — at `<root>/.beads/`, uniformly
/// (Q5a). A substation is a name + ONE root; its work lives in the store at that
/// root. The store is expected *exactly* here — never discovered by walking up.
///
/// A plain immutable value (see [GridStateStore]).
class SubstationWorkStore {
  /// Locates the work store at the substation [root].
  const SubstationWorkStore({required this.root});

  /// Locates the work store at [root], refusing a non-absolute root LOUD.
  factory SubstationWorkStore.forRoot(String root) => SubstationWorkStore(
    root: requireAbsoluteRoot(root, 'SubstationWorkStore'),
  );

  /// The substation's single root (absolute).
  final String root;

  /// The store root — `<root>` — the dir a `bd`/`BeadsWorkspace` runs in.
  String get storeRoot => root;

  /// The work store's beads dir — `<root>/.beads/`.
  String get beadsDir => p.join(root, kWorkStoreDirName);

  @override
  bool operator ==(Object other) =>
      other is SubstationWorkStore && other.root == root;

  @override
  int get hashCode => root.hashCode;

  @override
  String toString() => 'SubstationWorkStore(root: $root)';
}

/// Derives the [GridStateStore] from the ambient grid root (Track B's scope).
extension GridRootStores on GridRoot {
  /// The grid's state store, under `<path>/.grid/` (Q5a).
  GridStateStore get stateStore => GridStateStore(gridRoot: path);
}

/// Derives the [SubstationWorkStore] from the ambient substation scope.
extension SubstationScopeStores on SubstationScope {
  /// The substation's work store, at `<root>/.beads/` (Q5a).
  SubstationWorkStore get workStore => SubstationWorkStore(root: root);
}

/// Probes directory existence — the injected filesystem seam (Fakes, not mocks)
/// that keeps store discovery pure and offline-testable. The default
/// ([defaultDirectoryProbe]) is a real `dart:io` check.
typedef DirectoryProbe = bool Function(String path);

/// The real directory-existence probe.
bool defaultDirectoryProbe(String path) => Directory(path).existsSync();

/// Locates grid stores at roots — the discovery service (stateless I/O; the
/// reference type carries the classifier).
///
/// **Exact-at-root, never a walk-up.** [locateWorkStore] checks for `.beads/`
/// *at the given root only* — it does not search parent directories the way
/// `BeadsWorkspace.discover` does. Walk-up store discovery is the ambience the
/// v3 model kills (SCRATCH §7 item 9: "cwd store discovery under arming"): a
/// substation names its ONE root, so its store is there or it is a boot refusal.
class StoreLocator {
  /// Creates the locator; [dirExists] defaults to the real
  /// [defaultDirectoryProbe] and is injected for offline tests.
  StoreLocator({DirectoryProbe? dirExists})
    : _dirExists = dirExists ?? defaultDirectoryProbe;

  final DirectoryProbe _dirExists;

  /// Locates the work store for a substation rooted at [root], or refuses LOUD
  /// ([StoreRefusal]) when no `.beads/` store exists *at that exact root*.
  ///
  /// [substationName] is used only to name the substation in the refusal (the
  /// operator's remedy: run the substation init flow, or fix the root); pass it
  /// when known.
  SubstationWorkStore locateWorkStore({
    required String root,
    String? substationName,
  }) {
    final store = SubstationWorkStore.forRoot(root);
    if (!_dirExists(store.beadsDir)) {
      final who = substationName == null ? '' : ' "$substationName"';
      throw StoreRefusal(
        'substation$who at "$root" has no work store — expected a `.beads/` '
        'directory at ${store.beadsDir}. A substation is a name + ONE root, and '
        '`.beads/` means work store uniformly, everywhere (Q5a); the store is '
        'looked for at the root ONLY (no walk-up). Seed it with the substation '
        'initialization flow (see docs/SUBSTATION-INIT.md), or correct the root.',
      );
    }
    return store;
  }

  /// Whether the grid's state store already exists on disk (its `.beads/` under
  /// `.grid/`). Absence is NOT a refusal here — it means the state store has yet
  /// to be seeded (first boot / a fresh grid root); the runner decides whether to
  /// seed it. (Only a *substation* whose root has no store is a boot refusal —
  /// [locateWorkStore].)
  bool gridStateStoreExists(GridStateStore store) => _dirExists(store.beadsDir);
}
