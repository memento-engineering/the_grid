import 'package:beads_dart/beads_dart.dart';

import '../bridge/block_guard.dart';

/// Metadata keys on a grid-state `type=link` bead — the station's OWN record of
/// a CROSS-REPO blocking edge.
///
/// Deliberately metadata on an OWNED bead, never a `bd dep` row: no store — the
/// state store included — ever holds a dangling dependency reference, so no
/// `bd doctor --fix` can classify the edge orphaned and silently remove it. The
/// work stores are never written to in order to express the edge, so a foreign
/// work source stays pristine.
abstract final class CrossLinkKeys {
  /// The flat-key namespace prefix (a scan/grep anchor, like every other
  /// namespace in this repo's bead schemas).
  static const prefix = 'grid.link.';

  /// The BLOCKED bead id — the edge's tail, the bead held out of ready.
  static const from = 'grid.link.from';

  /// The BLOCKER bead id — the edge's head, the bead that must close first.
  static const to = 'grid.link.to';

  /// The edge kind. [kCrossLinkBlocks] is the only value the engine enforces;
  /// any other value is refused LOUDLY and fails CLOSED (see
  /// [projectCrossLinks]).
  static const type = 'grid.link.type';

  /// Free-prose receipt: WHY the operator authored the edge.
  static const reason = 'grid.link.reason';

  /// The `--actor` that authored the edge.
  static const actor = 'grid.link.actor';
}

/// The one [CrossLinkKeys.type] value the engine enforces.
const kCrossLinkBlocks = 'blocks';

/// One projected cross-repo blocking edge, read off an OPEN link bead.
class CrossLink {
  /// Creates the projection of link bead [beadId].
  const CrossLink({
    required this.beadId,
    required this.from,
    required this.to,
  });

  /// The link bead's own id — the receipt an operator closes to retire the
  /// edge, and the id the LOUD messages name.
  final String beadId;

  /// The BLOCKED bead id.
  final String from;

  /// The BLOCKER bead id, or `''` when the link bead is MALFORMED. An empty
  /// target resolves to no bead in any store, so [applyBlockGuard] holds [from]
  /// out of ready and says so LOUDLY — a malformed edge is never a silent drop.
  final String to;
}

/// Projects every OPEN `type=link` bead in [state] (the station's own state
/// store) into a [CrossLink].
///
/// Lifecycle: a CLOSED link bead RETIRES its edge — it is skipped here, so the
/// blocked bead re-enters the frontier on the next join (the close reason is
/// where the receipts live).
///
/// Fail-closed, never assume: [onMalformed] receives one LOUD line per link
/// bead that cannot be read as an enforceable `blocks` edge, and the returned
/// [CrossLink] still blocks its `from` bead via an empty [CrossLink.to]. An
/// unrecognised (or absent) [CrossLinkKeys.type] is treated exactly the same
/// way — the engine refuses to guess what an edge kind it does not implement
/// means, and refusing to guess means blocking, not passing. A link bead naming
/// no `from` at all has no bead to hold out; it is reported and dropped.
List<CrossLink> projectCrossLinks(
  GraphSnapshot state, {
  void Function(String message)? onMalformed,
}) {
  final links = <CrossLink>[];
  for (final bead in state.beadsById.values) {
    if (bead.issueType != IssueType.link) continue;
    if (bead.isClosed) continue; // a closed link RETIRES the edge.
    final from = _str(bead.metadata[CrossLinkKeys.from]);
    final to = _str(bead.metadata[CrossLinkKeys.to]);
    final kind = _str(bead.metadata[CrossLinkKeys.type]);
    if (from == null || from.isEmpty) {
      onMalformed?.call(
        'grid: link bead ${bead.id} names no "${CrossLinkKeys.from}" — there '
        'is no bead to hold out, so it enforces nothing. Close it or repair '
        'it.',
      );
      continue;
    }
    if (to == null || to.isEmpty) {
      onMalformed?.call(
        'grid: link bead ${bead.id} names no "${CrossLinkKeys.to}" — blocking '
        '$from fail-closed until the link is repaired or closed.',
      );
      links.add(CrossLink(beadId: bead.id, from: from, to: ''));
      continue;
    }
    if (kind != kCrossLinkBlocks) {
      onMalformed?.call(
        'grid: link bead ${bead.id} carries '
        '"${CrossLinkKeys.type}"="${kind ?? ''}", which this engine does not '
        'enforce (the only known kind is "$kCrossLinkBlocks") — blocking $from '
        'fail-closed rather than guessing. Close it or repair it.',
      );
      links.add(CrossLink(beadId: bead.id, from: from, to: ''));
      continue;
    }
    links.add(CrossLink(beadId: bead.id, from: from, to: to));
  }
  return links;
}

/// Maps [links] onto the shared enforcement's edge shape.
List<BlockEdge> crossLinkEdges(Iterable<CrossLink> links) => <BlockEdge>[
  for (final link in links)
    BlockEdge(from: link.from, to: link.to, origin: 'link bead ${link.beadId}'),
];

/// The LOUD arming refusal for a state store that has not registered the `link`
/// custom type, or `null` when it has.
///
/// [typesEnvelope] is bd's `types --json` data object. Its `custom_types` is a
/// list of plain type-name strings as of the pinned capture
/// (`fixtures/upstream/.../tg-types.json`); `{"name": …}` maps — the shape
/// `core_types` uses — are accepted too, so a future upstream convergence of
/// the two shapes does not turn this into a false refusal.
///
/// Without the type seeded, `bd create -t link` is rejected and EVERY cross-repo
/// block is silently absent — so the arming caller (the link-authoring verb)
/// refuses LOUDLY with the remedy instead of assuming the store is capable.
///
/// Deliberately NOT wired into `buildStationWork`: that path is driven offline
/// over metadata-only temp stores, so probing `bd types` there would spawn a
/// process at every arming and break offline tests that exercise a different
/// contract. The probe belongs at the authoring verb, which already shells out
/// to bd.
String? crossLinkTypeRefusal(
  Map<String, dynamic> typesEnvelope, {
  required String store,
}) {
  final custom = typesEnvelope['custom_types'];
  final names = <String>{
    if (custom is List)
      for (final entry in custom)
        if (entry is String)
          entry
        else if (entry is Map && entry['name'] is String)
          entry['name'] as String,
  };
  if (names.contains(IssueType.link.wire)) return null;
  return 'grid: the state store "$store" has not registered the '
      '"${IssueType.link.wire}" issue type, so a cross-repo link bead cannot '
      'be minted and every cross-repo block would be silently absent. Add it '
      "to that store's `types.custom` (docs/SUBSTATION-INIT.md, step 4) "
      'before arming.';
}

/// A metadata value as a `String`, or `null` when absent or not a string —
/// `Bead.metadata` is `Map<String, dynamic>` and a hand-edited store can carry
/// anything.
String? _str(Object? value) => value is String ? value : null;
