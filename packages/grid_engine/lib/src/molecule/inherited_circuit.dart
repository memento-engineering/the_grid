/// `InheritedCircuit` — the molecule model's ambient storage seam
/// (`DESIGN-tg-pm6.md` §6, R2; Decided item 6).
///
/// The molecule-mode analogue of `SessionHandle`
/// (`circuit/session_handle.dart`): once `SessionScope` has projected a
/// molecule session's beads to its effective [CircuitCursor] (R4), it provides
/// this value via a 4th nested `InheritedSeed<InheritedCircuit>` (R5,
/// `session_scope.dart:742-755`) so every `CapabilityHost` in the subtree
/// resolves ITS OWN step-bead id from [beadIdByNodePath] instead of writing to
/// the session bead. Flat-mode sessions provide nothing new here — a fork at
/// `CapabilityHost`'s persist call sites (R5b) falls back to `SessionHandle`
/// when no `InheritedCircuit` is ambient, so the flat path is byte-for-byte
/// untouched (the additivity story, `DESIGN-tg-pm6.md` §2).
///
/// **Config-is-values:** this seam carries no writer. Every write still rides
/// the ambient `StationServices.writer` chokepoint
/// (`kernel/station_services.dart:43`) — [InheritedCircuit] only tells a
/// capability WHICH bead id to target, never how to reach one (Decided
/// conflict 3, `DESIGN-tg-pm6.md` §3).
///
/// Pure value type. No IO, no bd, no genesis_tree import — only the two prior
/// rungs it composes ([BeadPathKey], [CircuitCursor]).
library;

import '../sdk/cursor.dart';
import 'bead_path_key.dart';

/// The ambient molecule-session context a `CapabilityHost` reads to target its
/// persists at a STEP bead instead of the session bead.
///
/// Value-typed so a re-provide with the SAME projected state never notifies
/// (the `SessionHandle` discipline, `session_scope.dart:721`): `genesis_tree`'s
/// `InheritedSeed.updateShouldNotify` is `value != oldSeed.value`
/// (`genesis_tree/src/inherited.dart`), so [operator ==] is the whole
/// notification contract — every dependent subtree rebuilds exactly when the
/// PROJECTED state changes and never merely because `SessionScope.build` ran
/// again.
class InheritedCircuit {
  /// Wraps this molecule's [root] crumb, its [beadIdByNodePath] lookup, and
  /// the projected [cursor].
  const InheritedCircuit({
    required this.root,
    required this.beadIdByNodePath,
    required this.cursor,
  });

  /// The canonical breadcrumb identifying this molecule instance (R7) — work
  /// bead ⇄ session ⇄ molecule, extended per nested sub-molecule.
  final BeadPathKey root;

  /// nodePath → durable step-bead id: the lookup a `CapabilityHost` uses to
  /// resolve WHICH bead its own persists target. Keyed by the engine's
  /// in-run `nodePath` coordinate (the same key space as [cursor] and as
  /// today's flat `grid.cursor.{nodePath}.*` keys) so a step's own view of
  /// itself needs no translation beyond the lookup.
  final Map<String, String> beadIdByNodePath;

  /// The projected EFFECTIVE cursor (R4's `effectiveCursor`) — the identical
  /// shape `CircuitScope` already consumes from the flat path's
  /// `joined?.cursor`, so `CircuitScope`/`frontier.dart` read either mode
  /// unchanged.
  final CircuitCursor cursor;

  /// Structural equality over ([root], [cursor]) ONLY — deliberately NOT
  /// [beadIdByNodePath] (Decided conflict 4, `DESIGN-tg-pm6.md` §3): the
  /// lookup is a derived, topology-stable view of the SAME molecule beads
  /// `cursor` already reflects, so it never disagrees with `cursor` about
  /// whether projected state changed. Comparing it too would only cost a
  /// second deep walk for an answer [cursor] has already given — and would
  /// risk a false "changed" from map-instance churn a rebuild introduces
  /// without any state actually moving.
  @override
  bool operator ==(Object other) =>
      other is InheritedCircuit &&
      other.root == root &&
      _cursorEquals(other.cursor, cursor);

  /// Consistent with [operator ==]: hashes exactly the fields equality
  /// compares, so two equal instances never disagree in a `Set`/`Map` key.
  @override
  int get hashCode => Object.hash(root, _cursorHash(cursor));

  @override
  String toString() => 'InheritedCircuit(root: $root, cursor: $cursor)';
}

/// Order-independent structural equality for a [CircuitCursor]: two cursors
/// are equal iff they carry the same `nodePath` keys, each mapped to an
/// `==`-equal [NodeCursor] (freezed-generated structural equality). `Map`
/// itself has no built-in deep equality in Dart, so this is hand-rolled here
/// rather than pulling `package:collection` in for one comparison — the same
/// choice `BeadPathKey._crumbsEqual` already made for its `List<String>`.
bool _cursorEquals(CircuitCursor a, CircuitCursor b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Order-independent hash for a [CircuitCursor], XOR-combined per entry so it
/// agrees with [_cursorEquals] regardless of the two maps' iteration/insertion
/// order (two projections of the same beads need not walk them in the same
/// order to hash identically).
int _cursorHash(CircuitCursor cursor) {
  var hash = 0;
  for (final entry in cursor.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
