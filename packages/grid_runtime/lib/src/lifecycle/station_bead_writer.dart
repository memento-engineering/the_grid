import 'dart:async';

import 'package:grid_controller/grid_controller.dart';

import 'bead_ownership.dart';

/// Raised when the [StationBeadWriter] chokepoint refuses a write because the
/// target bead's substation is absent or not in the shared allow-set (fail-closed).
///
/// This is the second line of defense behind the dispatch predicate (ADR-0006
/// Decision 2): session/recovery writes never flow through a `Convergence`, so
/// the `ReconcilerRuntime`'s `_ownership.owns(convergence)` gate cannot cover
/// them — this refusal is the gate that fires for them. A refusal is a
/// programmer/config error (a bug in substation stamping, a wrong allow-set seed), not
/// a recoverable runtime condition, so it surfaces loudly.
class OwnershipRefused implements Exception {
  OwnershipRefused({
    required this.operation,
    required this.targetId,
    required this.substation,
  });

  /// The bd operation that was refused (`create`/`update`/`close`/`delete`).
  final String operation;

  /// The bead id (or requested substation, for a pre-mint create) the write targeted.
  final String targetId;

  /// The substation the chokepoint derived for the target — null/empty is exactly why
  /// it was refused.
  final String? substation;

  @override
  String toString() =>
      'OwnershipRefused: $operation on "$targetId" refused — substation '
      '"${substation ?? '<absent>'}" is not in the owned allow-set (fail-closed, '
      'ADR-0006 Decision 2)';
}

/// The single bd write chokepoint (ADR-0006 Decision 2; ADR-0000 A32) — the
/// ONLY path through which the_grid's session/lifecycle/recovery beads are
/// written, wrapping the M2 [BdCliService].
///
/// **Fail-closed ownership re-check before EVERY write.** Before each
/// `create` / `update --metadata` / `close` / `delete`, the chokepoint asserts
/// the target bead's substation is in the shared allow-set (the SAME `Set<String>`
/// the dispatch [BeadOwnershipPredicate] and M2's `OwnsSubstations` consume — ADR-0000
/// A32) and **refuses + logs loudly** ([OwnershipRefused]) any write whose
/// target substation is absent or not owned. This mirrors how `ReconcilerRuntime`
/// gates convergence actuation on `_ownership.owns(convergence)`.
///
/// **Every minted session bead carries the owned substation marker from birth.**
/// [createSession] asserts the requested substation is owned BEFORE the `bd create`,
/// then immediately stamps `metadata.rig == <substation>` (a merge update) so every
/// subsequent write can assert ownership off the persisted marker. Because
/// `bd create` carries no `--metadata` flag (the M2 `BdCliService.create`
/// surface), the mint is `create` + a stamping `update` — the stamp is part of
/// birth, not a later mutation.
///
/// **Per-target-id write SERIALIZATION (ADR-0007 Amended / D-1).** `bd update
/// --metadata` is a client-side read-modify-write inside the bd subprocess with
/// no row lock across the read and the write, so two concurrent `update`s on the
/// SAME bead with DISJOINT flat keys can still last-writer-wins → a
/// `grid.cursor.{path}.state` key is lost → the barrier never opens → a silent
/// liveness stall at depth (the exact case the reentrant engine exists for).
/// P0's 1-wide frontier never raced it; the Burn's fan-out makes concurrency
/// structural. Because invariant 2 already makes the_grid the SOLE process
/// writing `tgdog`, an in-process per-id queue ([_tail]) fully closes it — no
/// SQL/cross-process lock. Every `update`/`close`/`delete`/`batch` on an id
/// chains after the prior op on that id (a `create` mints a fresh id no other op
/// can reference yet, so it is not queued). Flat-per-key merge-safety closes the
/// disjoint-key half; this closes the same-key half. So invariant 2 is
/// ownership/auth **AND** write-ordering.
///
/// **bd-only, `--actor grid-controller`, never SQL, never `bd show`.** The
/// chokepoint holds a [BdCliService] (which holds no Dolt dependency by
/// construction — it cannot issue a SQL string) and never calls `show` on this
/// controller path (it self-triggers the watcher). Grouped `close`+`dep`
/// mutations go through `bd batch` (one transaction); session lifecycle is
/// single-bead writes.
class StationBeadWriter {
  StationBeadWriter({
    required BdCliService bd,
    required BeadOwnershipPredicate ownership,
    void Function(String message)? onRefusal,
  }) : _bd = bd,
       _ownership = ownership,
       _onRefusal = onRefusal;

  final BdCliService _bd;
  final BeadOwnershipPredicate _ownership;
  final void Function(String message)? _onRefusal;

  /// The per-target-id serialization chain (D-1). `_tail[id]` completes when the
  /// last-queued write on `id` settles (success OR failure — it never rejects,
  /// so a failed op does not poison the chain). A new op on `id` awaits this
  /// before running. Entries self-prune once their chain drains.
  final Map<String, Future<void>> _tail = {};

  /// The owned-substation metadata key stamped on every minted session bead.
  static const String rigKey = 'rig';

  /// Mints a the_grid-owned session bead for work bead [workBeadId] in [substation],
  /// stamped with the owned substation marker from birth, and returns its id.
  ///
  /// Fail-closed: refuses ([OwnershipRefused]) when [substation] is not in the shared
  /// allow-set — the chokepoint never mints a bead outside the partition. The
  /// stamp also carries the work-bead linkage and the worktree/branch fields
  /// the caller supplies, all in the same first metadata merge so the bead is
  /// fully owned-and-linked from its first persisted state.
  Future<String> createSession({
    required String substation,
    required String title,
    required String workBeadId,
    Map<String, String> metadata = const {},
  }) async {
    // Re-check ownership of the REQUESTED substation before the create — the id does
    // not exist yet, so the substation the caller declares is the authority, and it
    // must be owned.
    if (!_ownership.ownsTarget(id: '$substation-pending', metadata: {rigKey: substation})) {
      _refuse('create', substation, substation);
    }
    final id = await _bd.create(title: title, type: IssueType.session);
    // Stamp the owned substation marker + linkage FROM BIRTH (merge update; the substation
    // key is what every later write asserts against).
    await _bd.update(
      id,
      metadata: {rigKey: substation, 'work_bead': workBeadId, ...metadata},
    );
    return id;
  }

  /// Mints a the_grid-owned `type=gate` bead in [substation] (the OWN state store)
  /// that functionally blocks the session [sessionId] at [nodePath] (D-7).
  /// Fail-closed on ownership exactly like [createSession]; stamps `rig`
  /// (= [substation]) + `blocks` (= [sessionId]) + `node` (= [nodePath]) +
  /// `reason`. Returns the gate id. NEVER touches the foreign work bead (A37) —
  /// a gate is a functional block in the_grid's OWN store, not a mutation of the
  /// parked work. `bd create -t gate` + a stamping `update` (the mint = birth,
  /// mirroring [createSession] — `bd create` carries no `--metadata`).
  Future<String> createGate({
    required String substation,
    required String sessionId,
    required String nodePath,
    required String reason,
  }) async {
    // Re-check ownership of the REQUESTED substation before the create — the
    // gate bead does not exist yet, so the declared substation is the authority,
    // and it must be owned.
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    final id = await _bd.create(
      title: 'grid gate $sessionId@$nodePath',
      type: IssueType.gate,
    );
    // Stamp the owned substation marker + the block linkage FROM BIRTH (merge
    // update; the `blocks`/`node` keys are how the join re-arms the parked node).
    await _bd.update(
      id,
      metadata: {
        rigKey: substation,
        'blocks': sessionId,
        'node': nodePath,
        'reason': reason,
      },
    );
    return id;
  }

  /// A lifecycle `bd update --metadata <json>` (merge semantics; works on
  /// closed beads) on a the_grid-owned session bead.
  ///
  /// Fail-closed: refuses when [id]'s substation is not owned. The chokepoint derives
  /// the substation from the id PREFIX (the owned-from-birth axis) plus any
  /// `metadata.rig` in the write — a write that does NOT itself carry the substation
  /// is still owned by virtue of its id prefix.
  ///
  /// Serialized per-id (D-1): ownership is checked synchronously (fail-closed
  /// immediately), then the bd write chains after any prior write on [id] so two
  /// concurrent updates with disjoint keys can never last-writer-wins.
  Future<void> update(
    String id, {
    required Map<String, String> metadata,
  }) async {
    // `async` so the fail-closed `_assertOwned` throw surfaces as a rejected
    // future (not a synchronous throw at the call site); `_serialized` registers
    // its tail synchronously before the first await, so ordering is preserved.
    _assertOwned('update', id, metadata);
    return _serialized(id, () => _bd.update(id, metadata: metadata));
  }

  /// `bd close` on a the_grid-owned session bead (terminal lifecycle).
  /// Fail-closed: refuses when [id]'s substation is not owned. Serialized per-id
  /// (D-1) so a close cannot race an in-flight cursor update on the same bead.
  Future<void> close(String id, {String? reason}) async {
    _assertOwned('close', id, const {});
    return _serialized(id, () => _bd.close(id, reason: reason));
  }

  /// `bd delete <id> --force` — the burn primitive, used only for speculative
  /// wisp burns (never close-as-burn; A16). Fail-closed on the target's substation.
  /// Serialized per-id (D-1).
  Future<void> delete(String id) async {
    _assertOwned('delete', id, const {});
    return _serialized(id, () => _bd.delete(id));
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
    // Serialize after EVERY involved id's prior op, and make every involved id's
    // next op wait for the batch (one transaction across all of them — D-1).
    final ids = {for (final entry in lines) entry.id};
    return _serializedMulti(
      ids,
      () => _bd.batch([for (final entry in lines) entry.line]),
    );
  }

  /// Chains [op] after the prior write on [id] (D-1). Returns [op]'s future
  /// (its error propagates to the caller); the chain itself never rejects, so a
  /// failed op does not stall the next one. The tail entry self-prunes when its
  /// chain drains and no later op replaced it.
  Future<T> _serialized<T>(String id, Future<T> Function() op) {
    final prior = _tail[id] ?? Future<void>.value();
    final run = prior.then((_) => op());
    final tail = run.then((_) {}, onError: (_) {});
    _tail[id] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tail[id], tail)) _tail.remove(id);
      }),
    );
    return run;
  }

  /// Like [_serialized] but spans multiple [ids] (a batch transaction): [op]
  /// runs after every id's prior op, and becomes every id's new tail.
  Future<T> _serializedMulti<T>(Set<String> ids, Future<T> Function() op) {
    final prior = Future.wait([
      for (final id in ids) _tail[id] ?? Future<void>.value(),
    ]);
    final run = prior.then((_) => op());
    final tail = run.then((_) {}, onError: (_) {});
    for (final id in ids) {
      _tail[id] = tail;
    }
    unawaited(
      tail.whenComplete(() {
        for (final id in ids) {
          if (identical(_tail[id], tail)) _tail.remove(id);
        }
      }),
    );
    return run;
  }

  void _assertOwned(
    String operation,
    String id,
    Map<String, dynamic> metadata,
  ) {
    if (_ownership.ownsTarget(id: id, metadata: metadata)) return;
    _refuse(operation, id, BeadOwnershipPredicate.prefixOf(id));
  }

  Never _refuse(String operation, String targetId, String? substation) {
    final refusal = OwnershipRefused(
      operation: operation,
      targetId: targetId,
      substation: substation,
    );
    _onRefusal?.call(refusal.toString());
    throw refusal;
  }
}
