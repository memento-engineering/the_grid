import 'package:grid_controller/grid_controller.dart';

import 'bead_ownership.dart';

/// Raised when the [GridBeadWriter] chokepoint refuses a write because the
/// target bead's rig is absent or not in the shared allow-set (fail-closed).
///
/// This is the second line of defense behind the dispatch predicate (ADR-0006
/// Decision 2): session/recovery writes never flow through a `Convergence`, so
/// the `ReconcilerRuntime`'s `_ownership.owns(convergence)` gate cannot cover
/// them — this refusal is the gate that fires for them. A refusal is a
/// programmer/config error (a bug in rig stamping, a wrong allow-set seed), not
/// a recoverable runtime condition, so it surfaces loudly.
class OwnershipRefused implements Exception {
  OwnershipRefused({
    required this.operation,
    required this.targetId,
    required this.rig,
  });

  /// The bd operation that was refused (`create`/`update`/`close`/`delete`).
  final String operation;

  /// The bead id (or requested rig, for a pre-mint create) the write targeted.
  final String targetId;

  /// The rig the chokepoint derived for the target — null/empty is exactly why
  /// it was refused.
  final String? rig;

  @override
  String toString() =>
      'OwnershipRefused: $operation on "$targetId" refused — rig '
      '"${rig ?? '<absent>'}" is not in the owned allow-set (fail-closed, '
      'ADR-0006 Decision 2)';
}

/// The single bd write chokepoint (ADR-0006 Decision 2; ADR-0000 A32) — the
/// ONLY path through which the_grid's session/lifecycle/recovery beads are
/// written, wrapping the M2 [BdCliService].
///
/// **Fail-closed ownership re-check before EVERY write.** Before each
/// `create` / `update --metadata` / `close` / `delete`, the chokepoint asserts
/// the target bead's rig is in the shared allow-set (the SAME `Set<String>`
/// the dispatch [BeadOwnershipPredicate] and M2's `OwnsRigs` consume — ADR-0000
/// A32) and **refuses + logs loudly** ([OwnershipRefused]) any write whose
/// target rig is absent or not owned. This mirrors how `ReconcilerRuntime`
/// gates convergence actuation on `_ownership.owns(convergence)`.
///
/// **Every minted session bead carries the owned rig marker from birth.**
/// [createSession] asserts the requested rig is owned BEFORE the `bd create`,
/// then immediately stamps `metadata.rig == <rig>` (a merge update) so every
/// subsequent write can assert ownership off the persisted marker. Because
/// `bd create` carries no `--metadata` flag (the M2 `BdCliService.create`
/// surface), the mint is `create` + a stamping `update` — the stamp is part of
/// birth, not a later mutation.
///
/// **bd-only, `--actor grid-controller`, never SQL, never `bd show`.** The
/// chokepoint holds a [BdCliService] (which holds no Dolt dependency by
/// construction — it cannot issue a SQL string) and never calls `show` on this
/// controller path (it self-triggers the watcher). Grouped `close`+`dep`
/// mutations go through `bd batch` (one transaction); session lifecycle is
/// single-bead writes.
class GridBeadWriter {
  GridBeadWriter({
    required BdCliService bd,
    required BeadOwnershipPredicate ownership,
    void Function(String message)? onRefusal,
  }) : _bd = bd,
       _ownership = ownership,
       _onRefusal = onRefusal;

  final BdCliService _bd;
  final BeadOwnershipPredicate _ownership;
  final void Function(String message)? _onRefusal;

  /// The owned-rig metadata key stamped on every minted session bead.
  static const String rigKey = 'rig';

  /// Mints a the_grid-owned session bead for work bead [workBeadId] in [rig],
  /// stamped with the owned rig marker from birth, and returns its id.
  ///
  /// Fail-closed: refuses ([OwnershipRefused]) when [rig] is not in the shared
  /// allow-set — the chokepoint never mints a bead outside the partition. The
  /// stamp also carries the work-bead linkage and the worktree/branch fields
  /// the caller supplies, all in the same first metadata merge so the bead is
  /// fully owned-and-linked from its first persisted state.
  Future<String> createSession({
    required String rig,
    required String title,
    required String workBeadId,
    Map<String, String> metadata = const {},
  }) async {
    // Re-check ownership of the REQUESTED rig before the create — the id does
    // not exist yet, so the rig the caller declares is the authority, and it
    // must be owned.
    if (!_ownership.ownsTarget(id: '$rig-pending', metadata: {rigKey: rig})) {
      _refuse('create', rig, rig);
    }
    final id = await _bd.create(title: title, type: IssueType.session);
    // Stamp the owned rig marker + linkage FROM BIRTH (merge update; the rig
    // key is what every later write asserts against).
    await _bd.update(
      id,
      metadata: {rigKey: rig, 'work_bead': workBeadId, ...metadata},
    );
    return id;
  }

  /// A lifecycle `bd update --metadata <json>` (merge semantics; works on
  /// closed beads) on a the_grid-owned session bead.
  ///
  /// Fail-closed: refuses when [id]'s rig is not owned. The chokepoint derives
  /// the rig from the id PREFIX (the owned-from-birth axis) plus any
  /// `metadata.rig` in the write — a write that does NOT itself carry the rig
  /// is still owned by virtue of its id prefix.
  Future<void> update(
    String id, {
    required Map<String, String> metadata,
  }) async {
    _assertOwned('update', id, metadata);
    await _bd.update(id, metadata: metadata);
  }

  /// `bd close` on a the_grid-owned session bead (terminal lifecycle).
  /// Fail-closed: refuses when [id]'s rig is not owned.
  Future<void> close(String id, {String? reason}) async {
    _assertOwned('close', id, const {});
    await _bd.close(id, reason: reason);
  }

  /// `bd delete <id> --force` — the burn primitive, used only for speculative
  /// wisp burns (never close-as-burn; A16). Fail-closed on the target's rig.
  Future<void> delete(String id) async {
    _assertOwned('delete', id, const {});
    await _bd.delete(id);
  }

  /// `bd batch` for grouped `close`+`dep` mutations (one transaction) — the
  /// ONLY grouped write path (CLAUDE.md). Every line's target id must be owned;
  /// the chokepoint refuses the whole batch if any line targets a non-owned
  /// bead (fail-closed — a batch is one transaction, so a single unowned target
  /// poisons it).
  Future<void> batch(List<({String id, String line})> lines) async {
    for (final entry in lines) {
      _assertOwned('batch', entry.id, const {});
    }
    if (lines.isEmpty) return;
    await _bd.batch([for (final entry in lines) entry.line]);
  }

  void _assertOwned(
    String operation,
    String id,
    Map<String, dynamic> metadata,
  ) {
    if (_ownership.ownsTarget(id: id, metadata: metadata)) return;
    _refuse(operation, id, BeadOwnershipPredicate.prefixOf(id));
  }

  Never _refuse(String operation, String targetId, String? rig) {
    final refusal = OwnershipRefused(
      operation: operation,
      targetId: targetId,
      rig: rig,
    );
    _onRefusal?.call(refusal.toString());
    throw refusal;
  }
}
