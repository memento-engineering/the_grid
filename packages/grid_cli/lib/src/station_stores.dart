/// Opens a beads workspace at a v3 store location — **exact-at-root, LOUD
/// refusal, never a walk-up.**
///
/// The four generic verbs (`watch` / `gate` / `rework` / `demo`) re-seat on the
/// code-as-config store model (`SCRATCH-station-config-model.md` v3): a store
/// lives *at a root*, and the grid state store nests one under `.grid/` (Q5a).
/// These openers replace the old `--workspace` / `--state-workspace` /
/// `BeadsWorkspace.discover()` (cwd walk-up) axis — the ambience fossil (§7
/// item 9). A store is looked for **exactly** where the model says it is; its
/// absence is an operator/ops error the operator fixes (the substation/grid init
/// flow, or a corrected root), never a condition the framework papers over by
/// searching upward into a sibling store.
///
/// Both openers gate existence through the pure [StoreLocator] (the injected
/// [DirectoryProbe] seam) BEFORE touching [BeadsWorkspace.discover]. Because the
/// gate guarantees the `.beads/` is at the exact root passed as `start`,
/// `discover` matches on its first iteration — it can never walk up into a
/// parent store (for the state store, that parent is the grid's own WORK store,
/// which the state store must never be confused for).
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_sdk/grid_sdk.dart'
    show
        DirectoryProbe,
        GridStateStore,
        StoreLocator,
        StoreRefusal,
        SubstationWorkStore;

/// Opens the grid **state store** at `<gridRoot>/.grid/.beads/`.
///
/// Refuses LOUD ([StoreRefusal]) when the state store has not been seeded there:
/// the grid's session/gate/cursor beads live under `.grid/`, distinct from the
/// grid root's own `.beads/` work store (A37; the dual-role repo has no
/// collision). [dirExists] is injected for offline tests (the real probe checks
/// the filesystem).
BeadsWorkspace openStateStore(
  GridStateStore store, {
  DirectoryProbe? dirExists,
}) {
  if (!StoreLocator(dirExists: dirExists).gridStateStoreExists(store)) {
    throw StoreRefusal(
      'no grid state store at ${store.beadsDir} — the grid state store lives '
      'under <grid.root>/.grid/.beads/ (Q5a). Seed it with the grid/substation '
      'initialization flow, or correct the grid root. The store is looked for '
      'at the grid root ONLY (never a walk-up into the sibling work store).',
    );
  }
  // The `.beads/` is EXACTLY at the runtime dir; the gate above guarantees no
  // walk-up into the grid root's own work store one level up.
  final ws = BeadsWorkspace.discover(start: store.runtimeDir);
  if (ws == null) {
    throw StoreRefusal(
      'the grid state store at ${store.beadsDir} could not be opened '
      '(it existed at the existence gate but discover found nothing — a race, '
      'or a malformed store).',
    );
  }
  return ws;
}

/// Opens a substation **work store** at `<root>/.beads/`.
///
/// Refuses LOUD ([StoreRefusal]) when no `.beads/` store exists at that exact
/// root — a substation names its ONE root, so its store is there or it is a boot
/// refusal (`.beads/` means *work store*, uniformly). [substationName] only
/// names the substation in the refusal; [dirExists] is injected for offline
/// tests.
BeadsWorkspace openWorkStore(
  SubstationWorkStore store, {
  String? substationName,
  DirectoryProbe? dirExists,
}) {
  // Throws StoreRefusal (naming the root + the remedy) when absent — the exact,
  // no-walk-up existence gate.
  StoreLocator(
    dirExists: dirExists,
  ).locateWorkStore(root: store.root, substationName: substationName);
  final ws = BeadsWorkspace.discover(start: store.storeRoot);
  if (ws == null) {
    throw StoreRefusal(
      'the work store at ${store.beadsDir} could not be opened (it existed at '
      'the existence gate but discover found nothing — a race, or a malformed '
      'store).',
    );
  }
  return ws;
}
