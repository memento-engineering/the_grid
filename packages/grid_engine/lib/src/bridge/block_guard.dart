import 'package:beads_dart/beads_dart.dart';

/// One blocking edge the union frontier must enforce, whatever authored it.
///
/// Two edge SOURCES feed this one enforcement: a real cross-store dependency
/// row observed on a member snapshot (`FederatedSnapshotSource`, D-F2) and an
/// OPEN grid-state `type=link` bead (`domain/cross_link.dart`). [origin] is the
/// human phrase the LOUD unresolved message names, so an operator reading the
/// log can tell the two apart.
class BlockEdge {
  /// Creates the edge "[from] is blocked until [to] closes", authored by
  /// [origin].
  const BlockEdge({required this.from, required this.to, required this.origin});

  /// The blocked bead id — a ready candidate this edge may hold out.
  final String from;

  /// The blocker bead id. [from] stays blocked while this is OPEN, and blocked
  /// fail-closed while it is unobservable.
  final String to;

  /// What authored the edge, for the LOUD message (e.g. `'a cross-store
  /// dependency'`, `'link bead houston-4f2'`).
  final String origin;
}

/// Re-applies [edges] over [candidates], fail-closed — the ONE implementation
/// of what a cross-store block means.
///
/// A candidate is excluded when any edge from it points at a target that is
/// OPEN in [beadsById], or that is **not present in [beadsById] at all** — the
/// latter LOUDLY through [onUnresolved], because an unresolvable blocker must
/// never silently pass as satisfied (a false negative an operator can see beats
/// a false positive that spawns unprerequisited work).
///
/// Callers own the FILTER (which edges apply at all); this function owns the
/// ENFORCEMENT. Returns [candidates] itself when there is nothing to apply.
Set<String> applyBlockGuard({
  required Set<String> candidates,
  required Map<String, Bead> beadsById,
  required Iterable<BlockEdge> edges,
  void Function(String message)? onUnresolved,
}) {
  if (candidates.isEmpty) return candidates;
  final byFrom = <String, List<BlockEdge>>{};
  for (final edge in edges) {
    (byFrom[edge.from] ??= <BlockEdge>[]).add(edge);
  }
  if (byFrom.isEmpty) return candidates;

  final result = <String>{};
  for (final id in candidates) {
    var blocked = false;
    for (final edge in byFrom[id] ?? const <BlockEdge>[]) {
      final target = beadsById[edge.to];
      if (target == null) {
        onUnresolved?.call(
          'grid: $id is blocked by ${edge.origin} on "${edge.to}", which is '
          'not observed by any federated store — excluding $id from ready '
          '(fail-closed).',
        );
        blocked = true;
        break;
      }
      if (!target.isClosed) {
        blocked = true;
        break;
      }
    }
    if (!blocked) result.add(id);
  }
  return result;
}
