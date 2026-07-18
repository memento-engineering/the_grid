import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

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
    DateTime Function()? clock,
  }) : _bd = bd,
       _ownership = ownership,
       _onRefusal = onRefusal,
       _clock = clock ?? DateTime.now;

  final BdCliService _bd;
  final BeadOwnershipPredicate _ownership;
  final void Function(String message)? _onRefusal;

  /// The wall clock for capture-only session lifecycle stamps (FT-1, tg-pez) —
  /// injected so tests are deterministic; never read on a build path.
  final DateTime Function() _clock;

  /// The session-lifecycle telemetry metadata keys (FT-1) — string literals here
  /// (grid_runtime cannot import grid_engine's `SessionBeadKeys`), kept
  /// wire-identical to it. Session-level, disjoint from the `grid.cursor.*` codec.
  static const String startedAtKey = 'started_at';
  static const String closedAtKey = 'closed_at';

  /// The per-target-id serialization chain (D-1). `_tail[id]` completes when the
  /// last-queued write on `id` settles (success OR failure — it never rejects,
  /// so a failed op does not poison the chain). A new op on `id` awaits this
  /// before running. Entries self-prune once their chain drains.
  final Map<String, Future<void>> _tail = {};

  /// The owned-substation metadata key stamped on every minted session bead.
  static const String rigKey = 'rig';

  /// The re-gate marker keys a [createGate] REFRESH stamps on a REUSED gate
  /// bead (tg-i08 mint-dedup): the count of times the node re-gated onto the
  /// SAME bead, and the ISO-8601 instant of the latest re-gate. `grid gate ls`
  /// reads them to show a reset age + a `re-gated Nx` marker instead of a pile
  /// of duplicate gate beads accumulating one-per-cycle.
  static const String gateRegateCountKey = 'regate_count';
  static const String gateRegatedAtKey = 'regated_at';

  /// The molecule model's owning-session JOIN keys (`DESIGN-tg-pm6.md` R1/R6)
  /// — string literals here (grid_runtime cannot import grid_engine's
  /// `MoleculeCircuitKeys`/`MoleculeStepKeys`; the dependency arc is
  /// one-directional), kept wire-identical to them. [moleculeSessionKey]
  /// stamps a `type=molecule` bead; [stepSessionKey] stamps a `type=step`
  /// bead — DIFFERENT wire strings by design (`grid.circuit.*` vs
  /// `grid.step.*`), so [createMolecule]'s dedup probe and [reapMolecule]'s
  /// collection scan both check EITHER key against the matching [IssueType].
  static const String moleculeSessionKey = 'grid.circuit.session';
  static const String stepSessionKey = 'grid.step.session';

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
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    final id = await _bd.create(title: title, type: IssueType.session);
    // Stamp the owned substation marker + linkage FROM BIRTH (merge update; the substation
    // key is what every later write asserts against). The capture-only
    // `started_at` stamp (FT-1) rides the SAME birth write — no extra traffic;
    // a caller-supplied [metadata] value wins (it can override the default).
    await _bd.update(
      id,
      metadata: {
        rigKey: substation,
        'work_bead': workBeadId,
        startedAtKey: _clock().toUtc().toIso8601String(),
        ...metadata,
      },
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
  ///
  /// **Mint-dedup (tg-i08).** A node that re-gates while a gate for the SAME
  /// (session, node) is already OPEN must not pile up a fresh duplicate gate
  /// bead per cycle (I-14). So before minting, the chokepoint probes for an
  /// existing open gate on this (session, node) via the safe snapshot read; if
  /// found it REFRESHES that bead (fresh [reason] + a bumped [gateRegateCountKey]
  /// + a reset [gateRegatedAtKey]) and returns its id — one stable gate id the
  /// operator keeps watching, with `grid gate ls` showing the reset age. The
  /// probe is best-effort: a read error falls through to a fresh mint (a
  /// duplicate gate is inert; a crashed mint is not).
  Future<String> createGate({
    required String substation,
    required String sessionId,
    required String nodePath,
    required String reason,
  }) async {
    // Re-check ownership of the REQUESTED substation before the create — the
    // gate bead does not exist yet, so the declared substation is the authority,
    // and it must be owned. (Fail-closed BEFORE the dedup read, so a foreign
    // substation never even reaches the wire — A37.)
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    // Mint-dedup: reuse+refresh an existing OPEN gate for this (session, node).
    final existing = await _findOpenGate(
      sessionId: sessionId,
      nodePath: nodePath,
    );
    if (existing != null) {
      final priorCount =
          int.tryParse('${existing.metadata[gateRegateCountKey] ?? ''}') ?? 0;
      await update(
        existing.id,
        metadata: {
          'reason': reason,
          gateRegateCountKey: (priorCount + 1).toString(),
          gateRegatedAtKey: _clock().toUtc().toIso8601String(),
        },
      );
      return existing.id;
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

  /// Mints a the_grid-owned MOLECULE — the durable, graph-shaped mint
  /// parallel to [createSession]/[createGate] (`DESIGN-tg-pm6.md` R6): one
  /// `bd create --graph` pour = one Dolt transaction
  /// (`BdCliService.applyGraph`, `ephemeral: false` — Decided item 1:
  /// durable-until-session-close, never a wisp). [plan] is
  /// `instantiateMolecule`'s pure output (grid_engine's cook's-role compile
  /// step — this chokepoint never imports it and stays domain-free; it only
  /// pours the plan and guards ownership + dedup, exactly like it does for a
  /// session or a gate).
  ///
  /// **Fail-closed BEFORE the wire, per node** (mirrors [batch]'s per-line
  /// loop: a batch is one transaction, so a single unowned target must poison
  /// the WHOLE pour, not just its own row). [plan]'s nodes are pre-mint — no
  /// real id exists yet — so each is checked the same way [createSession]/
  /// [createGate] check their own not-yet-existing target: against the
  /// REQUESTED [substation] (belt-and-suspenders with any `rig` the node's
  /// own metadata might carry). A node parented onto an EXISTING bead
  /// ([GraphNode.parentId] — `instantiateMolecule`'s root node parents onto
  /// the owning session) must ALSO itself be an owned bead: never silently
  /// nest a molecule under a foreign session.
  ///
  /// **Mint-dedup on re-entry** (the [_findOpenGate] precedent, tg-i08):
  /// serialized on [sessionId] (D-1, extended past single beads to a mint
  /// operation) so two concurrent [createMolecule] calls for the SAME session
  /// cannot both observe "nothing minted yet" and both pour — the second
  /// chains behind the first's dedup-probe-then-pour exactly as a same-id
  /// [update] would. The probe itself reads the OWN store via the safe
  /// snapshot path (never `bd show`) for an OPEN `type=molecule`/`type=step`
  /// bead already stamped with [sessionId]; when found, a prior pour already
  /// landed (a crashed or re-entered mint) and this call returns an EMPTY id
  /// map rather than pouring a duplicate graph — the persisted beads are the
  /// source of truth from here; a caller re-derives bead ids from the
  /// state-store JOIN projection (R5a), never from this return value on the
  /// dedup path.
  Future<Map<String, String>> createMolecule(
    GraphApplyPlan plan, {
    required String substation,
    required String sessionId,
  }) async {
    // `async` so a fail-closed throw below surfaces as a rejected future (not
    // a synchronous throw at the call site) — mirrors [update]'s own note.
    if (plan.nodes.isEmpty) {
      throw ArgumentError.value(
        plan,
        'plan',
        'createMolecule requires at least one node',
      );
    }
    // Re-check ownership BEFORE any node is wired — per node, so one foreign
    // target (declared substation OR an existing parent bead) poisons the
    // whole pour before the first byte reaches bd.
    for (final node in plan.nodes) {
      if (!_ownership.ownsTarget(
        id: '$substation-pending',
        metadata: {rigKey: substation, ...node.metadata},
      )) {
        _refuse('create', node.key, substation);
      }
      final parentId = node.parentId;
      if (parentId != null) {
        _assertOwned('create', parentId, const {});
      }
    }
    return _serializedMulti({sessionId}, () async {
      if (await _moleculeAlreadyMinted(sessionId: sessionId)) {
        return const <String, String>{};
      }
      return _bd.applyGraph(plan, ephemeral: false);
    });
  }

  /// Session-close collection for the molecule model (item 1): `bd purge`
  /// reaps only ephemerals, and [createMolecule] pours are deliberately
  /// PERSISTENT (never wisps), so a completed session's molecule/step beads
  /// need their OWN collection — this scans the OWN store for every OPEN
  /// `type=molecule`/`type=step` bead stamped with [sessionId] and closes
  /// EXACTLY that set through the grouped [batch] path (one transaction,
  /// per-line ownership-checked — fail-closed — and D-1 serialized). Never
  /// touches the entire store, a different session's beads, or an
  /// already-closed bead.
  ///
  /// No separate `substation` parameter: [batch] already derives and asserts
  /// ownership from each matched bead's OWN id prefix, so a bead that somehow
  /// carries a foreign id refuses the WHOLE reap exactly like an unowned
  /// [createMolecule] node does.
  ///
  /// Best-effort on the scan (mirrors [_findOpenGate]): a snapshot-read
  /// failure closes nothing rather than crashing session close; the beads
  /// stay open for a later reap attempt. An empty match set — a flat-mode
  /// session, or a molecule already reaped — is a silent no-op.
  Future<void> reapMolecule({required String sessionId}) async {
    final matched = await _moleculeBeadsFor(sessionId: sessionId);
    if (matched.isEmpty) return;
    await batch([
      for (final bead in matched) (id: bead.id, line: 'close ${bead.id}'),
    ]);
  }

  /// A lifecycle `bd update --metadata <json>` (merge semantics; works on
  /// closed beads) on a the_grid-owned session bead.
  ///
  /// Fail-closed: refuses when [id]'s substation is not owned. The chokepoint derives
  /// the substation from the id PREFIX (the owned-from-birth axis) plus any
  /// `metadata.rig` in the write — a write that does NOT itself carry the substation
  /// is still owned by virtue of its id prefix.
  ///
  /// [appendNotes] is a straight `--append-notes` passthrough to
  /// [BdCliService.update] (e.g. `grid rework`'s operator-finding append) — it
  /// rides the SAME serialized, ownership-checked write as [metadata], never a
  /// separate chokepoint call.
  ///
  /// Serialized per-id (D-1): ownership is checked synchronously (fail-closed
  /// immediately), then the bd write chains after any prior write on [id] so two
  /// concurrent updates with disjoint keys can never last-writer-wins.
  Future<void> update(
    String id, {
    required Map<String, String> metadata,
    String? appendNotes,
  }) async {
    // `async` so the fail-closed `_assertOwned` throw surfaces as a rejected
    // future (not a synchronous throw at the call site); `_serialized` registers
    // its tail synchronously before the first await, so ordering is preserved.
    _assertOwned('update', id, metadata);
    return _serialized(
      id,
      () => _bd.update(id, metadata: metadata, appendNotes: appendNotes),
    );
  }

  /// `bd close` on a the_grid-owned session bead (terminal lifecycle).
  /// Fail-closed: refuses when [id]'s substation is not owned. Serialized per-id
  /// (D-1) so a close cannot race an in-flight cursor update on the same bead.
  ///
  /// Stamps the capture-only `closed_at` telemetry (FT-1) in the SAME serialized
  /// chain link, immediately before the `bd close`, so EVERY session close (the
  /// M3 actuator + the M4 `SessionScope`) records a terminal instant with no
  /// caller change. The stamp is a merge `update` (bd merges named keys; the
  /// bead is still open here), then `bd close`.
  Future<void> close(String id, {String? reason}) async {
    _assertOwned('close', id, const {});
    return _serialized(id, () async {
      await _bd.update(
        id,
        metadata: {closedAtKey: _clock().toUtc().toIso8601String()},
      );
      await _bd.close(id, reason: reason);
    });
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

  /// The OPEN `type=gate` bead already blocking [sessionId] at [nodePath], or
  /// null when none exists (the mint-dedup probe, tg-i08). Reads the OWN state
  /// store via the safe snapshot path (never `bd show` on a controller path);
  /// returns null on ANY read error so dedup is best-effort and never blocks a
  /// legitimate gate mint.
  Future<Bead?> _findOpenGate({
    required String sessionId,
    required String nodePath,
  }) async {
    try {
      final export = await _bd.exportAll();
      for (final bead in export.beads) {
        if (bead.issueType != IssueType.gate || bead.isClosed) continue;
        if (bead.metadata['blocks'] == sessionId &&
            bead.metadata['node'] == nodePath) {
          return bead;
        }
      }
    } catch (_) {
      // Best-effort: a snapshot-read failure must never block a real gate mint.
    }
    return null;
  }

  /// True when an OPEN `type=molecule`/`type=step` bead already carries
  /// [sessionId] in the molecule-model JOIN keys — [createMolecule]'s
  /// dedup probe. A read failure is treated as "not yet minted" (best-effort,
  /// mirrors [_findOpenGate]: a probe failure must never block a legitimate
  /// mint).
  Future<bool> _moleculeAlreadyMinted({required String sessionId}) async =>
      (await _moleculeBeadsFor(sessionId: sessionId)).isNotEmpty;

  /// The OPEN molecule/step beads stamped with [sessionId] — the shared scan
  /// [_moleculeAlreadyMinted] and [reapMolecule] both read. Reads the OWN
  /// state store via the safe snapshot path (never `bd show` on a controller
  /// path); returns an empty list on ANY read error so both callers degrade
  /// gracefully instead of throwing (mirrors [_findOpenGate]).
  Future<List<Bead>> _moleculeBeadsFor({required String sessionId}) async {
    final matched = <Bead>[];
    try {
      final export = await _bd.exportAll();
      for (final bead in export.beads) {
        if (bead.isClosed) continue;
        final owns =
            (bead.issueType == IssueType.molecule &&
                bead.metadata[moleculeSessionKey] == sessionId) ||
            (bead.issueType == IssueType.step &&
                bead.metadata[stepSessionKey] == sessionId);
        if (owns) matched.add(bead);
      }
    } catch (_) {
      // Best-effort: a snapshot-read failure must never block a mint or
      // crash a session close.
    }
    return matched;
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
