import 'dart:async';

import 'package:beads_dart/beads_dart.dart';

import 'bead_ownership.dart';
import '../models/grid_issue_types.dart';

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

/// Raised when bd refuses an ownership-sensitive conditional update.
///
/// This is fail-closed and non-retryable: the caller must obtain a fresh
/// snapshot before deciding whether another write is valid.
class OwnershipGuardRefused implements Exception {
  OwnershipGuardRefused({
    required this.operation,
    required this.targetId,
    required this.cause,
  });

  /// The writer operation whose conditional update was refused.
  final String operation;

  /// The bead id protected by the failed guard.
  final String targetId;

  /// The typed bd exit-13 result; retained for diagnostics.
  final BdGuardMismatch cause;

  @override
  String toString() =>
      'OwnershipGuardRefused: $operation on "$targetId" refused by bd CAS '
      '(fail-closed; refresh ownership/status before another decision): $cause';
}

/// Raised when [StationBeadWriter] refuses to mint or refresh a gate for a
/// session bead that the state snapshot already shows as closed.
class SessionClosedRefused implements Exception {
  SessionClosedRefused({
    required this.operation,
    required this.sessionId,
    required this.reason,
  });

  /// The bd operation that was refused.
  final String operation;

  /// The session bead that the gate would have blocked.
  final String sessionId;

  /// The concrete refusal reason recorded for the operator.
  final String reason;

  @override
  String toString() =>
      'SessionClosedRefused: $operation for session "$sessionId" refused — '
      '$reason (fail-closed)';
}

/// Durable values for `grid.gate.close_cause`.
enum GateCloseCause {
  sessionTerminal('session-terminal'),
  workBeadClosed('work-bead-closed'),
  supersededRound('superseded-round'),
  duplicateMint('duplicate-mint'),
  stragglerRoute('straggler-route'),
  adjudicated('adjudicated'),
  unclassified('unclassified');

  const GateCloseCause(this.wireValue);
  final String wireValue;
}

/// The A48 session disposition supplied to a terminal gate sweep.
enum GateSweepSessionDisposition { live, done, held, voided }

/// Derives a session's disposition from its OWN metadata alone.
///
/// The one rule, extracted so the gate sweep and the boot-time teardown replay
/// (tg-tlea) share it rather than each carrying a copy that can drift:
///
/// * a HUMAN marker (`grid.escalation` / `grid.rework_declined`) ⇒ **held** —
///   the breaker-exhaustion escalation path deliberately preserves its
///   worktree for the human, and its molecule is preserved for the same
///   forensic reason;
/// * `grid.outcome=complete` ⇒ **done** — the_grid's own close path recorded
///   that THIS round finished;
/// * anything else ⇒ **voided** — closed mid-flight with no human marker.
///
/// Deliberately metadata-only: it says nothing about whether the bead is open
/// or closed. The gate sweep asks only about CLOSED sessions; the teardown
/// replay asks about OPEN ones carrying the completion marker, which is
/// exactly the "teardown outstanding" state.
GateSweepSessionDisposition sessionDispositionOfMetadata(
  Map<String, dynamic> metadata,
) {
  if (metadata['grid.escalation'] != null ||
      metadata['grid.rework_declined'] != null) {
    return GateSweepSessionDisposition.held;
  }
  if (metadata['grid.outcome'] == 'complete') {
    return GateSweepSessionDisposition.done;
  }
  return GateSweepSessionDisposition.voided;
}

/// One newly closed gate.
typedef GateAutoCloseReceipt = ({
  String gateId,
  String sessionId,
  GateCloseCause cause,
});

typedef WorkTerminalSettlementReceipt = ({
  String sessionId,
  String workBeadId,
  String terminalReason,
});

/// Reads a gate's durable close-cause vocabulary.
GateCloseCause gateCloseCauseOf(Bead gate) => GateCloseCause.values.firstWhere(
  (value) =>
      value.wireValue == gate.metadata[StationBeadWriter.gateCloseCauseKey],
  orElse: () => GateCloseCause.unclassified,
);

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
/// **Per-target-id write SERIALIZATION (ADR-0007 Amended / D-1).** The
/// in-process per-id queue ([_tail]) remains defense-in-depth and the ordering
/// guarantee for the_grid's sole-process writes to `tgdog`. Every
/// `update`/`close`/`delete`/`batch` on an id chains after the prior op on that
/// id (a `create` mints a fresh id no other op can reference yet, so it is not
/// queued). Ownership-sensitive snapshot-backed writes additionally use bd's
/// conditional-update guards and fail closed on stale state.
///
/// **bd-only, `--actor grid-controller`, never SQL, never `bd show`.** The
/// chokepoint holds a [BdCliService] (which holds no Dolt dependency by
/// construction — it cannot issue a SQL string) and never calls `show` on this
/// controller path (it self-triggers the watcher). Grouped `close`+`dep`
/// mutations go through `bd batch` (one transaction); session lifecycle is
/// single-bead writes.
/// A bead prose field writable by an operator one-shot.
enum OperatorBeadTextField { description, design, acceptance, notes }

class StationBeadWriter {
  StationBeadWriter({
    required BdCliService bd,
    required BeadProbeReader reader,
    required BeadOwnershipPredicate ownership,
    void Function(String message)? onRefusal,
    void Function(String name, Map<String, String> data)? onFlare,
    DateTime Function()? clock,
  }) : _bd = bd,
       _reader = reader,
       _ownership = ownership,
       _onRefusal = onRefusal,
       _onFlare = onFlare,
       _clock = clock ?? DateTime.now;

  final BdCliService _bd;
  final BeadProbeReader _reader;
  final BeadOwnershipPredicate _ownership;
  final void Function(String message)? _onRefusal;
  final void Function(String name, Map<String, String> data)? _onFlare;

  /// The wall clock for capture-only session lifecycle stamps (FT-1, tg-pez) —
  /// injected so tests are deterministic; never read on a build path.
  final DateTime Function() _clock;

  /// The session-lifecycle telemetry metadata keys (FT-1) — string literals here
  /// (grid_runtime cannot import grid_engine's `SessionBeadKeys`), kept
  /// wire-identical to it. Session-level, disjoint from the `grid.cursor.*` codec.
  static const String startedAtKey = 'started_at';
  static const String closedAtKey = 'closed_at';
  static const String outcomeKey = 'grid.outcome';
  static const String outcomeComplete = 'complete';
  static const String workTerminalReasonKey = 'grid.work_terminal_reason';
  static const String workTerminalReasonWorkBeadClosed =
      'work-bead-closed-under-live-session';

  /// The per-target-id serialization chain (D-1). `_tail[id]` completes when the
  /// last-queued write on `id` settles (success OR failure — it never rejects,
  /// so a failed op does not poison the chain). A new op on `id` awaits this
  /// before running. Entries self-prune once their chain drains.
  final Map<String, Future<void>> _tail = {};

  /// The owned-substation metadata key stamped on every minted session bead.
  static const String rigKey = 'rig';

  /// Content-provenance marker for work-bead specification fields.
  static const String specAuthorKey = 'spec.author';

  /// Marker value written by [writeSpecifyAuthoredSpec].
  static const String specifyAuthor = 'specify';

  /// The re-gate marker keys a [createGate] REFRESH stamps on a REUSED gate
  /// bead (tg-i08 mint-dedup): the count of times the node re-gated onto the
  /// SAME bead, and the ISO-8601 instant of the latest re-gate. `grid gate ls`
  /// reads them to show a reset age + a `re-gated Nx` marker instead of a pile
  /// of duplicate gate beads accumulating one-per-cycle.
  static const String gateRegateCountKey = 'regate_count';
  static const String gateRegatedAtKey = 'regated_at';
  static const String gateCloseCauseKey = 'grid.gate.close_cause';

  /// The molecule model's owning-session JOIN keys (`DESIGN-tg-pm6.md` R1/R6)
  /// — string literals here (grid_runtime cannot import grid_engine's
  /// `MoleculeCircuitKeys`/`MoleculeStepKeys`; the dependency arc is
  /// one-directional), kept wire-identical to them. [moleculeSessionKey]
  /// stamps a `type=molecule` bead; [stepSessionKey] stamps a `type=step`
  /// bead — DIFFERENT wire strings by design (`grid.circuit.*` vs
  /// `grid.step.*`), so [createMolecule]'s dedup probe and [reapMolecule]'s
  /// collection scan both check EITHER key against the matching [IssueType].
  static const String moleculeSessionKey = 'grid.circuit.session';
  static const String moleculeCrumbKey = 'grid.circuit.crumb';
  static const String stepSessionKey = 'grid.step.session';
  static const String stepCrumbKey = 'grid.step.crumb';
  static const String stepPathKey = 'grid.step.path';
  static const String stepStateKey = 'grid.step.state';
  static const String stepStartedAtKey = 'grid.step.startedAt';
  static const String stepFinishedAtKey = 'grid.step.finishedAt';
  static const String stepDurationMsKey = 'grid.step.durationMs';
  static const String stepFailureReasonKey = 'grid.step.failureReason';
  static const String _moleculeCrumbSeparator = '/';

  /// The DURABLE remount-attempt budget's keys (tg-zlfu), carried by ONE
  /// `type=mount-attempt` bead per work bead in the station's OWN state store.
  ///
  /// [mountAttemptWorkBeadKey] is the JOIN key the projection reads; the other
  /// two are the budget itself. Wire-identical to grid_engine's
  /// `MountAttemptKeys` — grid_runtime cannot import grid_engine (the
  /// dependency arc is one-directional), the same split the molecule keys
  /// above live under.
  static const String mountAttemptWorkBeadKey = 'grid.attempt.work_bead';
  static const String mountAttemptCountKey = 'grid.attempt.count';
  static const String mountAttemptLastAtKey = 'grid.attempt.last_at';

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
    final id = await _bd.create(title: title, type: GridIssueTypes.session);
    // Stamp the owned substation marker + linkage FROM BIRTH (merge update; the substation
    // key is what every later write asserts against). The capture-only
    // `started_at` stamp (FT-1) rides the SAME birth write — no extra traffic;
    // a caller-supplied [metadata] value wins (it can override the default).
    await _updateBead(
      'createSession',
      id,
      mergeMetadata: {
        rigKey: substation,
        'work_bead': workBeadId,
        startedAtKey: _clock().toUtc().toIso8601String(),
        ...metadata,
      },
    );
    _flare('session.minted', {'sessionId': id, 'workBeadId': workBeadId});
    return id;
  }

  /// Closes [sessionId] and then runs the guarded terminal gate sweep as one
  /// causally ordered transition.
  Future<List<GateAutoCloseReceipt>> closeSessionAndOpenGatesForTerminal({
    required String sessionId,
    required String closeReason,
    required GateCloseCause trigger,
  }) async {
    await close(sessionId, reason: closeReason);
    return _closeOpenGatesForTerminal(
      sessionId: sessionId,
      trigger: trigger,
      disposition: GateSweepSessionDisposition.voided,
      sessionClosedByWriter: true,
    );
  }

  Future<List<GateAutoCloseReceipt>> closeOpenGatesForTerminal({
    required String sessionId,
    required GateCloseCause trigger,
    required GateSweepSessionDisposition disposition,
    Bead? terminalWorkBead,
  }) async => _closeOpenGatesForTerminal(
    sessionId: sessionId,
    trigger: trigger,
    disposition: disposition,
    terminalWorkBead: terminalWorkBead,
  );

  Future<List<GateAutoCloseReceipt>> _closeOpenGatesForTerminal({
    required String sessionId,
    required GateCloseCause trigger,
    required GateSweepSessionDisposition disposition,
    Bead? terminalWorkBead,
    bool sessionClosedByWriter = false,
  }) async {
    final session = await _reader.beadById(
      sessionId,
      types: {GridIssueTypes.session},
    );
    final workTerminal =
        terminalWorkBead != null &&
        terminalWorkBead.isClosed &&
        session?.metadata['work_bead'] == terminalWorkBead.id;
    final sessionHeld =
        session?.metadata['grid.escalation'] != null ||
        session?.metadata['grid.rework_declined'] != null;
    final eligible =
        !sessionHeld &&
        switch (disposition) {
          GateSweepSessionDisposition.done ||
          GateSweepSessionDisposition.voided =>
            sessionClosedByWriter || (session?.isClosed ?? false),
          GateSweepSessionDisposition.live => workTerminal,
          GateSweepSessionDisposition.held => false,
        };
    if (!eligible) {
      throw StateError(
        sessionHeld || disposition == GateSweepSessionDisposition.held
            ? 'gate auto-close refused: held session'
            : 'gate auto-close refused: live session',
      );
    }
    if (disposition == GateSweepSessionDisposition.live) {
      await settleSessionForTerminalWork(
        sessionId: sessionId,
        terminalWorkBead: terminalWorkBead!,
      );
    }
    return _closeEligibleOpenGates(sessionId: sessionId, trigger: trigger);
  }

  Future<List<GateAutoCloseReceipt>> _closeEligibleOpenGates({
    required String sessionId,
    required GateCloseCause trigger,
  }) async {
    final gates = await _findOpenGates(sessionId: sessionId);
    final oldestByNode = <String, Bead>{};
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    for (final gate in gates) {
      final node = gate.metadata['node'] as String? ?? '';
      final prior = oldestByNode[node];
      if (prior == null ||
          (gate.createdAt ?? epoch).isBefore(prior.createdAt ?? epoch)) {
        oldestByNode[node] = gate;
      }
    }
    final receipts = <GateAutoCloseReceipt>[];
    for (final gate in gates) {
      final node = gate.metadata['node'] as String? ?? '';
      final cause = identical(oldestByNode[node], gate)
          ? trigger
          : GateCloseCause.duplicateMint;
      await update(
        gate.id,
        metadata: {gateCloseCauseKey: cause.wireValue},
        ifAssignee: gate.assignee,
        ifStatus: gate.status,
      );
      await close(gate.id, reason: 'grid auto-close: ${cause.wireValue}');
      final receipt = (gateId: gate.id, sessionId: sessionId, cause: cause);
      receipts.add(receipt);
      _onFlare?.call('gate.autoClosed', {
        'gateId': gate.id,
        'sessionId': sessionId,
        'cause': cause.wireValue,
      });
    }
    return receipts;
  }

  Future<WorkTerminalSettlementReceipt> settleSessionForTerminalWork({
    required String sessionId,
    required Bead terminalWorkBead,
  }) async {
    final session = await _reader.beadById(
      sessionId,
      types: {GridIssueTypes.session},
    );
    if (session == null ||
        session.isClosed ||
        !terminalWorkBead.isClosed ||
        session.metadata['work_bead'] != terminalWorkBead.id) {
      throw StateError(
        'work-terminal settlement refused: session/work terminal mismatch',
      );
    }
    await update(
      sessionId,
      metadata: const {
        outcomeKey: outcomeComplete,
        workTerminalReasonKey: workTerminalReasonWorkBeadClosed,
      },
    );
    await reapMolecule(sessionId: sessionId);
    await close(
      sessionId,
      reason: 'grid settle: $workTerminalReasonWorkBeadClosed',
    );
    _flare('session.workTerminal', {
      'sessionId': sessionId,
      'workBeadId': terminalWorkBead.id,
      'reason': workTerminalReasonWorkBeadClosed,
    });
    return (
      sessionId: sessionId,
      workBeadId: terminalWorkBead.id,
      terminalReason: workTerminalReasonWorkBeadClosed,
    );
  }

  /// Mints an owned state-store cross-repository blocking-link receipt.
  ///
  /// Wire-key strings live here deliberately: `grid_runtime` must not depend
  /// on `grid_engine` merely to stamp its cross-link schema.
  Future<String> createLink({
    required String substation,
    required String from,
    required String to,
    required String reason,
    required String actor,
  }) async {
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    final id = await _bd.create(
      title: 'grid link $from blocked by $to',
      type: GridIssueTypes.link,
    );
    await _updateBead(
      'createLink',
      id,
      mergeMetadata: {
        rigKey: substation,
        'grid.link.from': from,
        'grid.link.to': to,
        'grid.link.type': 'blocks',
        'grid.link.reason': reason,
        'grid.link.actor': actor,
      },
    );
    return id;
  }

  /// Records that the station is about to make mount attempt [attempt] on work
  /// bead [workBeadId] — the DURABLE half of the remount budget (tg-zlfu).
  ///
  /// ONE `type=mount-attempt` bead per work bead, never one per attempt: a bead
  /// per attempt would make the mechanism that bounds the storage amplifier
  /// into one, emitting records at exactly the rate it exists to stop. So this
  /// probes for the existing record by its [mountAttemptWorkBeadKey] join key
  /// and MERGES the new count in place (the tg-i08 dedup shape [createGate]
  /// already uses), minting only when no record exists.
  ///
  /// [attempt] is supplied by the caller from the in-memory projection rather
  /// than re-read here: the merge is per-key and row-locked (#4732), so it
  /// overwrites the two budget keys and preserves every other key on the
  /// record, and the whole-map replace that would clobber a concurrent write
  /// never happens. Per-attempt forensics ride [note] as an APPENDED note —
  /// `--notes` REPLACES and has silently clobbered accrued corpus before.
  ///
  /// Fail-closed on ownership exactly like [createGate] and [createSession]:
  /// the record lives in the station's OWN store, never on the work bead, which
  /// is frequently foreign and read-only (A37).
  Future<String> recordMountAttempt({
    required String substation,
    required String workBeadId,
    required int attempt,
    String? note,
  }) async {
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    final budget = <String, String>{
      mountAttemptCountKey: '$attempt',
      mountAttemptLastAtKey: _clock().toUtc().toIso8601String(),
    };
    final existing = await _findMountAttemptRecord(workBeadId);
    if (existing != null) {
      await update(existing.id, metadata: budget, appendNotes: note);
      return existing.id;
    }
    final id = await _bd.create(
      title: 'grid mount-attempt $workBeadId',
      type: GridIssueTypes.mountAttempt,
    );
    // The join key + the owned-substation marker land in the SAME first merge
    // as the budget, so the record is owned-and-joinable from its first
    // persisted state (the [createSession] convention — `bd create` carries no
    // `--metadata`).
    await _updateBead(
      'recordMountAttempt',
      id,
      mergeMetadata: {
        rigKey: substation,
        mountAttemptWorkBeadKey: workBeadId,
        ...budget,
      },
      appendNotes: note,
    );
    return id;
  }

  /// The OPEN `type=mount-attempt` record for [workBeadId], or null when the
  /// station has never attempted it. Narrow by construction: the join key is a
  /// metadata equality, so this never scans the work store.
  Future<Bead?> _findMountAttemptRecord(String workBeadId) async {
    final records = await _reader.openBeads(
      types: {GridIssueTypes.mountAttempt},
      metadataAll: {mountAttemptWorkBeadKey: workBeadId},
    );
    return records.isEmpty ? null : records.first;
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
    await _assertGateSessionOpen(sessionId);
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
        ifAssignee: existing.assignee,
        ifStatus: existing.status,
      );
      _flare('gate.opened', {
        'gateId': existing.id,
        'sessionId': sessionId,
        'nodePath': nodePath,
        'reason': reason,
        'reused': 'true',
      });
      await _sweepStragglerGateIfSessionTerminal(sessionId);
      return existing.id;
    }
    final id = await _bd.create(
      title: 'grid gate $sessionId@$nodePath',
      type: GridIssueTypes.gate,
    );
    // Stamp the owned substation marker + the block linkage FROM BIRTH (merge
    // update; the `blocks`/`node` keys are how the join re-arms the parked node).
    await _updateBead(
      'createGate',
      id,
      mergeMetadata: {
        rigKey: substation,
        'blocks': sessionId,
        'node': nodePath,
        'reason': reason,
      },
    );
    _flare('gate.opened', {
      'gateId': id,
      'sessionId': sessionId,
      'nodePath': nodePath,
      'reason': reason,
      'reused': 'false',
    });
    await _sweepStragglerGateIfSessionTerminal(sessionId);
    return id;
  }

  Future<void> _sweepStragglerGateIfSessionTerminal(String sessionId) async {
    try {
      final session = await _reader.beadById(
        sessionId,
        types: {GridIssueTypes.session},
      );
      if (session?.isClosed ?? false) {
        final disposition = sessionDispositionOfMetadata(session!.metadata);
        if (disposition != GateSweepSessionDisposition.held) {
          await closeOpenGatesForTerminal(
            sessionId: sessionId,
            trigger: GateCloseCause.stragglerRoute,
            disposition: disposition,
          );
        }
      }
    } on Object catch (error) {
      _flare('gate.autoCloseFailed', {
        'sessionId': sessionId,
        'cause': GateCloseCause.stragglerRoute.wireValue,
        'reason': _truncateGateFlareReason('$error'),
      });
    }
  }

  /// Parks an EXISTING session at a durable human gate for a SESSION-LIFECYCLE
  /// failure (tg-aec: a thrown molecule pour) — deliberately a DISTINCT verb
  /// from [createGate]'s route-verdict use, though the wire shape is identical.
  ///
  /// The distinction is WHO decides what: a route verdict (advance/block/
  /// re-key) is effected only by the one router (`CapabilityHost`, tg-6gn);
  /// this park records that a session EXISTS but never became drivable — no
  /// step, no cursor, nothing to route. Per A47 the park is FOR a human
  /// (repair the cause, then `grid rework`); the engine never resolves it.
  Future<String> parkSessionAtGate({
    required String substation,
    required String sessionId,
    required String nodePath,
    required String reason,
  }) => createGate(
    substation: substation,
    sessionId: sessionId,
    nodePath: nodePath,
    reason: reason,
  );

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
    required Iterable<String> rootCrumbs,
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
    final rootCrumbList = _dedupeCrumbs(rootCrumbs);
    if (rootCrumbList.isEmpty) {
      throw ArgumentError.value(
        rootCrumbs,
        'rootCrumbs',
        'createMolecule requires at least one root crumb',
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
      final ids = await _bd.applyGraph(plan, ephemeral: false);
      await _stampMoleculeCrumbs(plan, ids, rootCrumbList);
      return ids;
    });
  }

  Future<void> _stampMoleculeCrumbs(
    GraphApplyPlan plan,
    Map<String, String> ids,
    List<String> rootCrumbs,
  ) async {
    final parentKeyByChildKey = <String, String>{
      for (final node in plan.nodes)
        if (node.parentKey != null) node.key: node.parentKey!,
      for (final edge in plan.edges)
        if (edge.type == DependencyType.parentChild.wire)
          edge.fromKey: edge.toKey,
    };
    for (final node in plan.nodes) {
      final id = ids[node.key];
      if (id == null) continue;
      final metadataKey = _moleculeCrumbMetadataKey(node);
      if (metadataKey == null) continue;
      _assertOwned('update', id, const {});
      await _updateBead(
        'update',
        id,
        mergeMetadata: {
          metadataKey: _canonicalMoleculeCrumb(
            rootCrumbs,
            node.key,
            ids,
            parentKeyByChildKey,
          ),
        },
      );
    }
  }

  static String? _moleculeCrumbMetadataKey(GraphNode node) =>
      switch (node.type) {
        'molecule' => moleculeCrumbKey,
        'step' => stepCrumbKey,
        _ => null,
      };

  static String _canonicalMoleculeCrumb(
    List<String> rootCrumbs,
    String nodeKey,
    Map<String, String> ids,
    Map<String, String> parentKeyByChildKey,
  ) {
    final chain = <String>[];
    String? cursor = nodeKey;
    while (cursor != null) {
      final id = ids[cursor];
      if (id != null) chain.add(id);
      cursor = parentKeyByChildKey[cursor];
    }
    return _dedupeCrumbs([
      ...rootCrumbs,
      ...chain.reversed,
    ]).join(_moleculeCrumbSeparator);
  }

  static List<String> _dedupeCrumbs(Iterable<String> crumbs) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final crumb in crumbs) {
      if (seen.add(crumb)) ordered.add(crumb);
    }
    return List<String>.unmodifiable(ordered);
  }

  /// Mints the A52 Ratified successor incarnation bead for an invalidated
  /// terminal molecule step.
  ///
  /// [spentRounds] is the number of predecessor incarnations with durable
  /// verdicts. The single bd-write chokepoint refuses before mutation when that
  /// spend reaches [maxRounds]. Structural supersedes depth is identity history
  /// and is deliberately not a refusal axis.
  Future<String> createStepSuccessor({
    required String substation,
    required Bead priorStep,
    required int spentRounds,
    required int maxRounds,
  }) async {
    if (priorStep.issueType != GridIssueTypes.step) {
      throw ArgumentError.value(priorStep.id, 'priorStep', 'must be type=step');
    }
    if (spentRounds >= maxRounds) {
      throw StateError('rework verdict cap reached ($spentRounds/$maxRounds)');
    }
    if (!_ownership.ownsTarget(
      id: '$substation-pending',
      metadata: {rigKey: substation},
    )) {
      _refuse('create', substation, substation);
    }
    _assertOwned('create', priorStep.id, const {});
    return _serializedMulti({priorStep.id}, () async {
      final existing = await _findOpenSuccessor(priorStep.id);
      if (existing != null) return existing.id;
      final id = await _bd.create(
        title: priorStep.title,
        type: GridIssueTypes.step,
      );
      final successorCrumb = _successorStepCrumb(priorStep, id);
      final metadata = <String, String>{
        rigKey: substation,
        for (final entry in priorStep.metadata.entries)
          if (entry.value is String &&
              entry.key != stepCrumbKey &&
              entry.key != stepStateKey &&
              entry.key != stepStartedAtKey &&
              entry.key != stepFinishedAtKey &&
              entry.key != stepDurationMsKey &&
              entry.key != stepFailureReasonKey &&
              !entry.key.startsWith('grid.result.'))
            entry.key: entry.value as String,
        if (successorCrumb != null) stepCrumbKey: successorCrumb,
        stepStateKey: 'pending',
      };
      // tg-q3q0 (deep): the supersedes edge MUST land before the metadata
      // that makes this successor selectable as the path's active bead. A
      // snapshot taken between the two writes used to see a fully-formed
      // pending step at the SAME path with NO edge — supersedes depth 0 — so
      // the host mounted with grid.round frozen at the OLD round, and the
      // dedup probe (which searches BY the edge) could never find it. With
      // the edge first, a half-minted successor is an inert bead with no
      // path metadata: invisible to activeStepBeadsByPath, harmless.
      await _bd.depAdd(id, priorStep.id, type: DependencyType.supersedes);
      await _updateBead('createStepSuccessor', id, mergeMetadata: metadata);
      return id;
    });
  }

  static String? _successorStepCrumb(Bead priorStep, String successorId) {
    final priorCrumb = priorStep.metadata[stepCrumbKey];
    if (priorCrumb is! String || priorCrumb.isEmpty) return null;
    final crumbs = priorCrumb
        .split(_moleculeCrumbSeparator)
        .where((crumb) => crumb.isNotEmpty)
        .toList(growable: false);
    if (crumbs.isEmpty) return successorId;
    return _dedupeCrumbs([
      ...crumbs.take(crumbs.length - 1),
      successorId,
    ]).join(_moleculeCrumbSeparator);
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
  /// The targeted read is loud: a failure aborts session close so lifecycle
  /// debt cannot accumulate invisibly. An empty match set — a flat-mode
  /// session, or a molecule already reaped — is a no-op.
  ///
  /// The unforced close script is dependency-ordered across blocking,
  /// parent-child, and supersedes edges. The proxied-server fallback consumes
  /// that identical order per bead. A cycle refuses the reap before any write.
  /// Every session whose teardown is OUTSTANDING — open, and already carrying
  /// `grid.outcome=complete` (tg-tlea).
  ///
  /// That conjunction IS the crash window. `_completeAndClose` stamps the
  /// completion marker FIRST, on purpose, and closes the bead only after the
  /// molecule reap, the worktree reap and the gate sweep have run; so a bead
  /// that still carries the marker while open is a station that died partway
  /// down its own teardown tail.
  ///
  /// **The filter is SERVER-SIDE and that is load-bearing** (#192 pushed
  /// metadata filters into `bd list`). Expressed instead as "list every owned
  /// session, filter in Dart", this would reintroduce precisely the unbounded
  /// boot pass `RestartReconciler` documents itself refusing to do — a large
  /// backlog would then be walked on every boot. [BeadProbeReader.openBeads]
  /// also excludes closed beads, so the open half of the conjunction costs
  /// nothing extra.
  Future<List<Bead>> sessionsAwaitingTeardown() => _reader.openBeads(
    types: {GridIssueTypes.session},
    metadataAll: const {'grid.outcome': 'complete'},
  );

  Future<void> reapMolecule({required String sessionId}) async {
    final session = await _reader.beadById(
      sessionId,
      types: {GridIssueTypes.session},
    );
    final workBeadId = session?.metadata['work_bead'] as String?;
    final attempt = workBeadId == null
        ? null
        : await _findMountAttemptRecord(workBeadId);
    final matched = await _moleculeBeadsFor(sessionId: sessionId);
    final roots = <Bead>[...matched, if (attempt != null) attempt];
    if (roots.isEmpty) return;
    final chain = await _supersedesChainFor(matched);
    final beads = {
      for (final bead in [...roots, ...chain]) bead.id: bead,
    };
    final dependencies = await _bd.depList(beads.keys.toList(growable: false));
    final orderedBeads = _moleculeReapOrder(beads, dependencies);
    try {
      await batch([
        for (final bead in orderedBeads)
          (id: bead.id, line: 'close ${bead.id}'),
      ]);
    } on BdCommandFailed catch (error) {
      // PROXIED-SERVER stores refuse `bd batch` outright ("batch is not
      // supported in proxied-server mode") — so the reap threw on EVERY
      // session close on such a store, silently accumulating 9,389 orphaned
      // step/molecule beads by 2026-08-07 (tg-ehht). Degrading to per-bead
      // closes trades ADR-0001 D4's one-transaction grouping for the only
      // write shape the store supports; the set is bounded (one session's
      // graph, ~35 beads). Any OTHER batch failure still propagates.
      if (!'$error'.contains('not supported in proxied-server mode')) {
        rethrow;
      }
      for (final bead in orderedBeads) {
        await close(bead.id, reason: 'molecule reaped (session close)');
      }
    }
  }

  /// A lifecycle atomic metadata merge (works on closed beads) on a
  /// the_grid-owned session bead.
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
  /// #4732 makes the row-locked transaction own the merge re-read. Serialized
  /// per-id (D-1): ownership is checked synchronously (fail-closed immediately),
  /// then the bd write chains after any prior write on [id]. The queue remains
  /// defense-in-depth and provides deterministic same-id ordering.
  Future<void> update(
    String id, {
    required Map<String, String> metadata,
    String? appendNotes,
    String? ifAssignee,
    BeadStatus? ifStatus,
  }) async {
    // `async` so the fail-closed `_assertOwned` throw surfaces as a rejected
    // future (not a synchronous throw at the call site); `_serialized` registers
    // its tail synchronously before the first await, so ordering is preserved.
    _assertOwned('update', id, metadata);
    return _serialized(
      id,
      () => _updateBead(
        'update',
        id,
        mergeMetadata: metadata,
        appendNotes: appendNotes,
        ifAssignee: ifAssignee,
        ifStatus: ifStatus,
      ),
    );
  }

  /// Writes one owned operator prose field through the verified bd seam.
  Future<void> writeOperatorText(
    String id, {
    required OperatorBeadTextField field,
    required String content,
    required bool append,
  }) async {
    _assertOwned('writeOperatorText', id, const {});
    if (append && field != OperatorBeadTextField.notes) {
      throw ArgumentError.value(
        field,
        'field',
        'append is valid only for notes',
      );
    }
    return _serialized(id, () async {
      switch (field) {
        case OperatorBeadTextField.description:
          await _bd.update(id, description: content);
        case OperatorBeadTextField.design:
          await _bd.update(id, design: content);
        case OperatorBeadTextField.acceptance:
          await _bd.update(id, acceptanceCriteria: content);
        case OperatorBeadTextField.notes:
          await _bd.update(
            id,
            notes: append ? null : content,
            appendNotes: append ? content : null,
          );
      }
    });
  }

  /// Writes SPECIFY-authored fields and their provenance atomically.
  ///
  /// A hand-authored `bd update --design` does not stamp [specAuthorKey].
  /// Therefore only this method establishes SPECIFY provenance; once rework
  /// clears the prior marker, a later operator overwrite is preserved.
  Future<void> writeSpecifyAuthoredSpec(
    String id, {
    required String design,
    required String acceptanceCriteria,
  }) async {
    _assertOwned('writeSpecifyAuthoredSpec', id, const {});
    return _serialized(
      id,
      () => _updateBead(
        'writeSpecifyAuthoredSpec',
        id,
        design: design,
        acceptanceCriteria: acceptanceCriteria,
        mergeMetadata: const {specAuthorKey: specifyAuthor},
      ),
    );
  }

  /// Clears only currently SPECIFY-authored spec fields on an owned WORK bead
  /// before a rework session is retired. Operator-authored or unknown
  /// provenance is preserved and signalled; description and notes are always
  /// untouched.
  Future<void> clearSpecifyAuthoredSpec(String id) async {
    _assertOwned('clearSpecifyAuthoredSpec', id, const {});
    return _serialized(id, () async {
      final bead = await _reader.beadById(
        id,
        types: {...IssueType.coreTypes, ...GridIssueTypes.all},
      );
      final author = bead?.metadata[specAuthorKey] as String?;
      if (author != specifyAuthor) {
        _flare('rework.specPreserved', {'beadId': id});
        return;
      }
      await _updateBead(
        'clearSpecifyAuthoredSpec',
        id,
        ifAssignee: bead!.assignee,
        ifStatus: bead.status,
        design: '',
        acceptanceCriteria: '',
        unsetMetadata: const [specAuthorKey],
      );
    });
  }

  Future<void> _updateBead(
    String operation,
    String id, {
    String? ifAssignee,
    BeadStatus? ifStatus,
    String? title,
    BeadStatus? status,
    int? priority,
    String? description,
    String? design,
    String? acceptanceCriteria,
    IssueType? type,
    String? assignee,
    Map<String, String> mergeMetadata = const {},
    Iterable<String> unsetMetadata = const [],
    String? appendNotes,
  }) async {
    try {
      await _bd.update(
        id,
        ifAssignee: ifAssignee,
        ifStatus: ifStatus,
        onGuardDegraded: _flare,
        title: title,
        status: status,
        priority: priority,
        description: description,
        design: design,
        acceptanceCriteria: acceptanceCriteria,
        type: type,
        assignee: assignee,
        mergeMetadata: mergeMetadata,
        unsetMetadata: unsetMetadata,
        appendNotes: appendNotes,
        // ADR-0006 D2 / ADR-0001 D5: controller writes never issue bd show.
        // BdCliService still applies every pre-exec argv-text guard; only the
        // post-write verification read is disabled here.
        verifyTextRoundTrip: false,
      );
    } on BdGuardMismatch catch (cause) {
      final refusal = OwnershipGuardRefused(
        operation: operation,
        targetId: id,
        cause: cause,
      );
      _onRefusal?.call(refusal.toString());
      throw refusal;
    }
  }

  void _flare(String name, Map<String, String> data) {
    try {
      _onFlare?.call(name, data);
    } catch (_) {
      // Fire-and-continue observability cannot fail the protected transition.
    }
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
      await _updateBead(
        'close',
        id,
        mergeMetadata: {closedAtKey: _clock().toUtc().toIso8601String()},
      );
      await _bd.close(id, reason: reason);
    });
  }

  /// A bead's CURRENT metadata via the safe snapshot read — the molecule
  /// model's `StepMetadataReader` (tg-h4u, R3): what the process-lease
  /// vendor's `adoptable` consults to see a prior incarnation's `grid.lease.*`
  /// breadcrumb after a station restart.
  ///
  /// **Never `bd show`.** ADR-0006 Decision 2's FORBIDDEN list is verbatim:
  /// "No `bd show` from any controller/re-query/dispatch path (self-triggers
  /// the watcher) — use snapshot reads / the SELECT probe". This targeted read
  /// uses the same-store reader injected beside the write chokepoint.
  Future<Map<String, String>?> metadataOf(String beadId) async {
    final bead = await _reader.beadById(
      beadId,
      types: {...IssueType.coreTypes, ...GridIssueTypes.all},
    );
    if (bead == null) return null;
    return {
      for (final entry in bead.metadata.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
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
  Future<List<Bead>> _findOpenGates({
    required String sessionId,
    String? nodePath,
  }) => _reader.openBeads(
    types: {GridIssueTypes.gate},
    metadataAll: {'blocks': sessionId, if (nodePath != null) 'node': nodePath},
  );

  Future<Bead?> _findOpenGate({
    required String sessionId,
    required String nodePath,
  }) async {
    final gates = await _findOpenGates(
      sessionId: sessionId,
      nodePath: nodePath,
    );
    return gates.isEmpty ? null : gates.first;
  }

  /// Refuses gate mint/refresh when the snapshot proves [sessionId] is closed.
  ///
  /// The snapshot probe is intentionally narrow: an absent session keeps the
  /// existing fake/offline behavior, while a present closed session is a hard
  /// refusal before `bd create` or a dedup refresh can run.
  Future<void> _assertGateSessionOpen(String sessionId) async {
    final bead = await _reader.beadById(
      sessionId,
      types: {GridIssueTypes.session},
    );
    if (bead?.isClosed ?? false) {
      _refuseClosedSession('create', sessionId, 'session bead is closed');
    }
  }

  Never _refuseClosedSession(
    String operation,
    String sessionId,
    String reason,
  ) {
    final refusal = SessionClosedRefused(
      operation: operation,
      sessionId: sessionId,
      reason: reason,
    );
    _onRefusal?.call(refusal.toString());
    throw refusal;
  }

  /// True when an OPEN `type=molecule`/`type=step` bead already carries
  /// [sessionId] in the molecule-model JOIN keys — [createMolecule]'s
  /// dedup probe. A read failure is treated as "not yet minted" (best-effort,
  /// mirrors [_findOpenGate]: a probe failure must never block a legitimate
  /// mint).
  Future<bool> _moleculeAlreadyMinted({required String sessionId}) async =>
      (await _moleculeBeadsFor(sessionId: sessionId)).isNotEmpty;

  Future<Bead?> _findOpenSuccessor(String priorStepId) async {
    final successors = await _reader.openSuperseding({priorStepId});
    return successors.isEmpty ? null : successors.first;
  }

  Future<List<Bead>> _supersedesChainFor(List<Bead> roots) async {
    if (roots.isEmpty) return const [];
    final seen = {for (final bead in roots) bead.id};
    var frontier = Set<String>.of(seen);
    final found = <Bead>[];
    while (frontier.isNotEmpty) {
      final successors = await _reader.openSuperseding(frontier);
      frontier = <String>{};
      for (final bead in successors) {
        if (!seen.add(bead.id)) continue;
        found.add(bead);
        frontier.add(bead.id);
      }
    }
    return found;
  }

  static int _moleculeReapRank(Bead bead) => switch (bead.issueType) {
    GridIssueTypes.mountAttempt => 0,
    GridIssueTypes.step => 1,
    GridIssueTypes.molecule => 2,
    _ => throw StateError(
      'reapMolecule collected unsupported type ${bead.issueType}',
    ),
  };

  static List<Bead> _moleculeReapOrder(
    Map<String, Bead> beads,
    List<BeadDependency> dependencies,
  ) {
    final outgoing = {for (final id in beads.keys) id: <String>{}};
    final indegree = {for (final id in beads.keys) id: 0};
    for (final dependency in dependencies) {
      if (!beads.containsKey(dependency.issueId) ||
          !beads.containsKey(dependency.dependsOnId)) {
        continue;
      }
      final (before, after) = dependency.type == DependencyType.parentChild
          ? (dependency.issueId, dependency.dependsOnId)
          : dependency.type.isBlockingEdge ||
                dependency.type == DependencyType.supersedes
          ? (dependency.dependsOnId, dependency.issueId)
          : (null, null);
      if (before == null || after == null || !outgoing[before]!.add(after)) {
        continue;
      }
      indegree[after] = indegree[after]! + 1;
    }

    final ready =
        indegree.entries
            .where((entry) => entry.value == 0)
            .map((entry) => beads[entry.key]!)
            .toList()
          ..sort(_moleculeReadyCompare);
    final ordered = <Bead>[];
    while (ready.isNotEmpty) {
      final bead = ready.removeAt(0);
      ordered.add(bead);
      final dependents = outgoing[bead.id]!.toList()..sort();
      for (final dependent in dependents) {
        final next = indegree[dependent]! - 1;
        indegree[dependent] = next;
        if (next == 0) {
          ready.add(beads[dependent]!);
          ready.sort(_moleculeReadyCompare);
        }
      }
    }
    if (ordered.length != beads.length) {
      final remaining =
          indegree.entries
              .where((entry) => entry.value > 0)
              .map((entry) => entry.key)
              .toList()
            ..sort();
      throw StateError(
        'molecule reap dependency cycle: ${remaining.join(', ')}',
      );
    }
    return ordered;
  }

  static int _moleculeReadyCompare(Bead left, Bead right) {
    final byKind = _moleculeReapRank(left).compareTo(_moleculeReapRank(right));
    return byKind != 0 ? byKind : left.id.compareTo(right.id);
  }

  /// The OPEN molecule/step beads stamped with [sessionId] — the shared scan
  /// [_moleculeAlreadyMinted] and [reapMolecule] both read. Reads the OWN
  /// state store through the targeted reader and propagates read failures.
  Future<List<Bead>> _moleculeBeadsFor({required String sessionId}) async {
    final matched = await Future.wait([
      _reader.openBeads(
        types: {GridIssueTypes.molecule},
        metadataAll: {moleculeSessionKey: sessionId},
      ),
      _reader.openBeads(
        types: {GridIssueTypes.step},
        metadataAll: {stepSessionKey: sessionId},
      ),
    ]);
    return [...matched[0], ...matched[1]];
  }

  void _assertOwned(
    String operation,
    String id,
    Map<String, dynamic> metadata,
  ) {
    if (_ownership.ownsTarget(id: id, metadata: metadata)) return;
    _refuse(
      operation,
      id,
      BeadOwnershipPredicate.ownedPrefixOf(id, _ownership.substations),
    );
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

String _truncateGateFlareReason(String reason) =>
    reason.length <= 500 ? reason : reason.substring(0, 500);
