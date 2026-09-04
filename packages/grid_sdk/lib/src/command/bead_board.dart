/// The BOARD projection — one typed row per work bead, folded from
/// `(bead, metadata, dependencies)` as ADR-0002 Decision 2 requires.
///
/// Pure and I/O-free: the resident handler supplies an already-open
/// [GraphSnapshot] per work store and this file turns it into rows. Nothing
/// here opens a store, spawns `bd`, or writes.
///
/// Ordinary blocking edges are read inside one store's snapshot. Active
/// cross-store blockers arrive already enforced by the resident through
/// [linkBlockersByBeadId]. They originate only from OPEN `type=link` beads,
/// never raw cross-store dependency rows.
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'work_bead_keys.dart';

part 'bead_board.freezed.dart';
part 'bead_board.g.dart';

/// How a board read narrows the projection. Clauses AND together; an empty
/// or absent clause matches everything.
@freezed
abstract class BoardFilter with _$BoardFilter {
  /// Creates a filter.
  const factory BoardFilter({
    /// Substation names to keep; empty keeps every store.
    @Default(<String>{}) Set<String> stores,

    /// `BeadStatus` wire values to keep; empty keeps every non-closed status.
    @Default(<String>{}) Set<String> statuses,

    /// Keep only beads carrying at least one open blocking edge.
    @Default(false) bool blockedOnly,

    /// `true` keeps approval-stamped beads, `false` keeps unstamped ones,
    /// null keeps both.
    bool? approved,
  }) = _BoardFilter;
}

/// One board row: a bead, or a store that could not be projected.
@Freezed(unionKey: 'kind', unionValueCase: FreezedUnionCase.snake)
sealed class BoardRow with _$BoardRow {
  /// One non-closed work bead.
  @FreezedUnionValue('bead')
  const factory BoardRow.bead({
    required String id,
    required String store,
    required String root,
    required String type,
    required String status,
    required String title,
    @Default(false) bool ready,
    @JsonKey(name: 'blocked_by') @Default(<String>[]) List<String> blockedBy,
    @JsonKey(name: 'approved_by') String? approvedBy,
    @JsonKey(name: 'approved_at') String? approvedAt,
    @JsonKey(name: 'approved_rev') String? approvedRev,
  }) = BoardBeadRow;

  /// A store the resident holds but could not project — NEVER omitted.
  @FreezedUnionValue('store_unreadable')
  const factory BoardRow.storeUnreadable({
    required String store,
    required String root,
    required String reason,
  }) = BoardStoreUnreadableRow;

  /// Decodes a row off the resident door's `rows` array.
  factory BoardRow.fromJson(Map<String, dynamic> json) =>
      _$BoardRowFromJson(json);
}

/// Projects [snapshot] into board rows for the store named [store] at [root].
///
/// Closed beads are dropped — the board is OPEN work. Rows come back
/// id-sorted so two runs diff cleanly.
List<BoardRow> projectBoard({
  required String store,
  required String root,
  required GraphSnapshot snapshot,
  BoardFilter filter = const BoardFilter(),
  Map<String, Iterable<String>> linkBlockersByBeadId = const {},
}) {
  if (filter.stores.isNotEmpty && !filter.stores.contains(store)) {
    return const <BoardRow>[];
  }
  final blockers = <String, List<String>>{};
  for (final edge in snapshot.dependencies) {
    if (!edge.type.isBlockingEdge) continue;
    final blocker = snapshot.bead(edge.dependsOnId);
    if (blocker != null && blocker.isClosed) continue;
    (blockers[edge.issueId] ??= <String>[]).add(edge.dependsOnId);
  }
  final rows = <BoardBeadRow>[];
  for (final bead in snapshot.beads) {
    if (bead.isClosed) continue;
    if (filter.statuses.isNotEmpty &&
        !filter.statuses.contains(bead.status.wire)) {
      continue;
    }
    final blockedBy = <String>{
      ...?blockers[bead.id],
      ...?linkBlockersByBeadId[bead.id],
    }.toList()..sort();
    if (filter.blockedOnly && blockedBy.isEmpty) continue;
    final approvedAt = beadMetadataText(bead, WorkBeadKeys.approvedAt);
    if (filter.approved != null && (approvedAt != null) != filter.approved) {
      continue;
    }
    rows.add(
      BoardBeadRow(
        id: bead.id,
        store: store,
        root: root,
        type: bead.issueType.wire,
        status: bead.status.wire,
        title: bead.title,
        ready: snapshot.readyIds.contains(bead.id),
        blockedBy: blockedBy,
        approvedBy: beadMetadataText(bead, WorkBeadKeys.approvedBy),
        approvedAt: approvedAt,
        approvedRev: beadMetadataText(bead, WorkBeadKeys.approvedRev),
      ),
    );
  }
  rows.sort((left, right) => left.id.compareTo(right.id));
  return List<BoardRow>.unmodifiable(rows);
}
