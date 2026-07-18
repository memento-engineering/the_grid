/// `BeadPathKey` — the molecule model's canonical string identity
/// (`DESIGN-tg-pm6.md` §5, R7; Decided items 2/3/6).
///
/// Every rung after this one builds on it: `instantiateMolecule` (R1) takes a
/// `BeadPathKey` root, `InheritedCircuit` (R2) carries one, and `reapMolecule`
/// (R6) reasons about a molecule by its crumb. Zero dependencies — this file
/// imports nothing from the rest of `molecule/`.
library;

/// The breadcrumb join separator.
///
/// Not legal inside a bd id and not `.` — the `lastIndexOf('.')` flat-cursor
/// parse (`domain/session_bead.dart:465,508`) never has to disambiguate a
/// molecule path, because a molecule path never uses that codec.
const String kBreadcrumbSeparator = '/';

/// The ordered, DE-DUPLICATED breadcrumb of stable bead ids that identifies
/// one coordinate in the molecule model (Decided item 2): work bead ⇄ session
/// ⇄ molecule ⇄ nested step. Bead ids never reshape once minted, so a
/// `BeadPathKey` is topology-stable BY CONSTRUCTION — there is no analogue of
/// the flat model's `nodePath` renaming under rework.
///
/// [canonical] is the DURABLE identity (Decided item 3): a deterministic
/// string, joined with [kBreadcrumbSeparator], safe to persist and to compare
/// across process restarts. "Hash for the tick, string for the record":
/// [hashCode] exists only so a `BeadPathKey` behaves in an in-memory `Set` or
/// `Map` key during a single run — it is never written to a bead and never
/// compared across runs.
///
/// Identity is derived entirely from the bead ids in play (Decided item 6) —
/// there is no `GlobalKey`-style out-of-band identity here or anywhere else in
/// the molecule model.
class BeadPathKey {
  /// Builds a key from [crumbs], preserving first-occurrence order and
  /// dropping any later repeat of a crumb already seen (a bead reappearing on
  /// its own ancestry chain — e.g. crash-adopt re-walking the same molecule —
  /// collapses to the one crumb instead of doubling up).
  BeadPathKey(Iterable<String> crumbs) : crumbs = _dedupe(crumbs);

  /// The ordered, de-duplicated bead ids from root to leaf.
  final List<String> crumbs;

  static List<String> _dedupe(Iterable<String> crumbs) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final crumb in crumbs) {
      if (seen.add(crumb)) ordered.add(crumb);
    }
    return List.unmodifiable(ordered);
  }

  /// A child key one crumb deeper than this one (e.g. a molecule's own key
  /// extended by a nested step's bead id). Already-present crumbs still
  /// de-duplicate — `child` never breaks the first-occurrence invariant.
  BeadPathKey child(String crumb) => BeadPathKey([...crumbs, crumb]);

  /// The DURABLE identity (Decided item 3): [crumbs] joined by
  /// [kBreadcrumbSeparator]. Deterministic across runs and processes because
  /// it is built ONLY from stable bead ids — never from [hashCode], never
  /// from anything process-local.
  String get canonical => crumbs.join(kBreadcrumbSeparator);

  @override
  bool operator ==(Object other) =>
      other is BeadPathKey && _crumbsEqual(other.crumbs, crumbs);

  @override
  int get hashCode => Object.hashAll(crumbs);

  @override
  String toString() => 'BeadPathKey($canonical)';
}

bool _crumbsEqual(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
