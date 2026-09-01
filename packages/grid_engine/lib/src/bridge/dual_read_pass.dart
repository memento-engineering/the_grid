/// THE COMPARATOR PASS, session axis (cut-wiring C2) — the stateful half of
/// the dual read.
///
/// `session_head_read.dart` holds the pure functions; this file runs them over
/// one JOIN's sessions map, keeps the boot's accounting, owns the two lag
/// trackers, and emits — emit-only, never blocking — the divergence flares,
/// the `terminal-reconcile` heal requests, and the durable round summaries.
///
/// It is deliberately NOT part of `_join`'s value: the join stays a pure
/// function of (work, state, snapshot), and this observer is the third input's
/// BOOKKEEPER, handed in like `onUnresolvedCrossLink`. A null observer is the
/// offline default and changes nothing.
library;

import '../domain/session_head_read.dart';
import '../domain/session_projection.dart';
import '../domain/trajectory_views.dart';

/// The emit-only flare sink shape the engine already uses everywhere else.
typedef DualReadFlareSink = void Function(String name, Map<String, String> data);

/// Emits one durable round-summary note (§0.4) — `AttemptNote` REQUIRES a
/// `sessionId`, so the vehicle is always keyed to a real session: the session
/// that just reached its terminal, or (at the clean-down fixpoint) the LAST
/// terminal session of the boot.
typedef DualReadSummarySink = void Function(String sessionId, String body);

/// Subscribes to the P1 mirror's published snapshots and returns the remover
/// (house convention) — the `headChanges` seam that makes a fold-side fact
/// re-join PROMPTLY instead of waiting for the next work/state emission.
///
/// Spelled as a plain function type rather than the notifier's `RemoveListener`
/// so `grid_engine` names no `state_notifier` type for a surface that is
/// explicitly not notifier state (§0.2: the mirror is deliberately not a
/// `StateNotifier`).
typedef HeadSnapshotSubscribe =
    void Function() Function(
      void Function(TrajectoryHeadSnapshot snapshot) listener,
    );

/// Runs the session-axis comparator and owns everything it accumulates.
///
/// One instance per boot, held by the bridge. `observe` is called once per
/// join; `finish` once at the clean-down fixpoint.
class DualReadSessionObserver {
  DualReadSessionObserver({
    DualReadMode mode = DualReadMode.observe,
    DateTime Function()? clock,
    bool Function(String attemptId)? appendQueuedFor,
    TerminalReconcileHealer? healer,
    DualReadFlareSink? onFlare,
    DualReadSummarySink? onRoundSummary,
    DualReadAccounting? accounting,
  }) : _mode = mode,
       _clock = clock ?? DateTime.now,
       _appendQueuedFor = appendQueuedFor ?? _neverQueued,
       _healer = healer,
       _onFlare = onFlare,
       _onRoundSummary = onRoundSummary,
       accounting = accounting ?? DualReadAccounting();

  static bool _neverQueued(String _) => false;

  final DualReadMode _mode;
  final DateTime Function() _clock;

  /// The harness's answer for one attempt: is an append for it still QUEUED?
  /// A queued append means the real terminal record is on its way, so a heal
  /// would race it (r8 — V2-B1). With no harness wired there is no queue, and
  /// the honest answer is "no".
  final bool Function(String attemptId) _appendQueuedFor;

  final TerminalReconcileHealer? _healer;
  final DualReadFlareSink? _onFlare;
  final DualReadSummarySink? _onRoundSummary;

  /// The boot's counters — the round summary's payload and the soak gates'
  /// evidence.
  final DualReadAccounting accounting;

  final TerminalLagTracker _terminalLag = TerminalLagTracker();
  final RetirementLagTracker _retirementLag = RetirementLagTracker();

  /// Sessions already seen terminal — the transition edge the per-terminal
  /// round summary rides. A set, not a counter: the join recomputes on every
  /// snapshot emission and a terminal session stays terminal forever.
  final Set<String> _terminalSessions = <String>{};

  String? _lastTerminalSessionId;
  TrajectorySnapshotHealth? _lastHealth;
  bool _finished = false;

  /// The last terminal session of the boot — the boot-final note's vehicle.
  String? get lastTerminalSessionId => _lastTerminalSessionId;

  /// ONE comparator pass over [sessions] (the join's map, keyed by the LEGACY
  /// work-bead key, which for a retired round is the `#rN`/`#void-` mutation)
  /// against [snapshot].
  ///
  /// Decisions are untouched: under `observe` this only counts, and under
  /// `primary` the overlay C3 serves is applied by the JOIN, never here.
  void observe(
    Map<String, SessionProjection> sessions,
    TrajectoryHeadSnapshot snapshot,
  ) {
    if (_finished) return;
    accounting.beginPass();
    _noteHealth(snapshot.health);
    _emitTerminalSummaries(sessions, snapshot);
    if (snapshot.health != TrajectorySnapshotHealth.live) {
      // Health non-`live` DISENGAGES the overlay for the boot (§0.2): every
      // session rides pure legacy — still fully written, still authoritative —
      // and every read counts as a fallback. No flares: the compromise itself
      // already flared once, at the latch.
      accounting.fallbacks += sessions.length;
      _terminalLag.retainOnly(const <String>{});
      _retirementLag.retainOnly(const <String>{});
      return;
    }
    final now = _clock();
    final matchedSessionIds = <String>{};
    final laggingTerminals = <String>{};
    final laggingRetirements = <String>{};
    final beadsToSentinel = <String>{};

    for (final legacy in sessions.values) {
      final sessionId = legacy.sessionId;
      if (sessionId == null || sessionId.isEmpty) continue;
      // THE OVERLAY IDENTITY RULE (§0.3): the same-session lookup, never a
      // `byWorkBead` winner. A miss is a MISS — pure legacy, counted — and
      // never a sibling row's terminal spliced onto a live session.
      final head = snapshot.bySessionId(sessionId);
      if (head == null) {
        accounting.fallbacks += 1;
        final miss = classifyDualReadMiss(legacy, snapshot.firstEpochClaimedAt);
        if (miss.nullStartedAt) accounting.nullStartedAt += 1;
        switch (miss.era) {
          case DualReadMissClass.postEpoch:
            accounting.missPostEpoch += 1;
          case DualReadMissClass.legacyEra:
            accounting.missLegacyEra += 1;
        }
        continue;
      }
      matchedSessionIds.add(sessionId);
      accounting.hits += 1;
      beadsToSentinel.add(head.workBeadId);

      // RETIREMENT LAG precedes the terminal-lag read: the retire path closes
      // the bd bead and emits ONLY `roundRetired`, so between the re-key and
      // that record landing the pair reads legacy-terminal / P1-current-open —
      // which is the rework window, not a missing terminal.
      final retired = isRetiredWorkBeadKey(legacy.workBeadId);
      if (retired && head.isOpen && head.round > 0) {
        // RETIREMENT IS LEGIBLE IN THE FOLD (§0.2), and this is its STEADY
        // STATE, not a lag: `_closeRetiredReworkSession` closes the bd bead
        // and emits ONLY `roundRetired`, so a retired session's P1 row stays
        // `status='open'` FOREVER — by schema design. `round > 0` is what says
        // so, and the two sides agree. Reading it as `terminalLag` would make
        // every rework round an unhealable lag entry and the gates
        // unsatisfiable.
        continue;
      }
      final currentOpen = head.isOpen && head.round == 0;
      if (retired && currentOpen) {
        laggingRetirements.add(sessionId);
        final escalates = _retirementLag.observe(
          sessionId,
          now: now,
          successorPresent: _successorPresent(snapshot, head),
        );
        final age = _retirementLag.ageOf(sessionId, now).inMilliseconds;
        if (age > accounting.maxRetirementLagMs) {
          accounting.maxRetirementLagMs = age;
        }
        if (escalates) {
          _recordAndFlare(
            DualReadComparison(
              sessionId: sessionId,
              workBeadId: head.workBeadId,
              classification: DualReadClass.divergence,
              mismatches: const [
                DualReadFieldMismatch(
                  field: 'retirementLag',
                  foldValue: 'current-open',
                  legacyValue: 'retired-key',
                ),
              ],
            ),
            snapshot,
          );
        } else {
          accounting.record(
            DualReadComparison(
              sessionId: sessionId,
              workBeadId: head.workBeadId,
              classification: DualReadClass.retirementLag,
            ),
          );
        }
        continue;
      }

      final comparison = compareHeadToProjection(legacy, head);
      if (comparison.classification == DualReadClass.terminalLag) {
        laggingTerminals.add(sessionId);
        _handleTerminalLag(comparison, head, snapshot, now);
        continue;
      }
      _recordAndFlare(comparison, snapshot);
    }

    // The CARDINALITY SENTINEL rides `byWorkBead` — the classification view,
    // which is exactly the read that already handles multiplicity (§0.2's
    // "which index feeds what"). It never serves a row.
    for (final workBeadId in beadsToSentinel) {
      final winner = snapshot.byWorkBead(workBeadId);
      if (winner is! SessionHeadCardinalityBreach) continue;
      _recordAndFlare(
        DualReadComparison(
          sessionId: (<String>[
            for (final row in winner.rows) row.sessionId,
          ]..sort()).join(','),
          workBeadId: workBeadId,
          classification: DualReadClass.cardinality,
          mismatches: [
            DualReadFieldMismatch(
              field: 'cardinality',
              foldValue: '${winner.rows.length} current-open rows',
              legacyValue: '1',
            ),
          ],
        ),
        snapshot,
      );
    }

    // P1 rows with NO legacy counterpart: structurally inert for decisions
    // (§0.2 — the join iterates legacy projections and the overlay never
    // creates), but counted and classified. An orphan with no matching session
    // bead ANYWHERE is a divergence immediately.
    for (final row in snapshot.rows) {
      if (matchedSessionIds.contains(row.sessionId)) continue;
      accounting.p1Orphan += 1;
    }

    _terminalLag.retainOnly(laggingTerminals);
    _retirementLag.retainOnly(laggingRetirements);
  }

  /// The clean-down fixpoint's boot-final summary (§0.4), riding the sessionId
  /// of the LAST terminal session of the boot. A boot with ZERO terminal
  /// sessions appends no note — nothing gate-relevant happened, and every gate
  /// round contains terminal sessions by definition.
  void finish(TrajectoryHeadSnapshot snapshot) {
    if (_finished) return;
    _finished = true;
    final sessionId = _lastTerminalSessionId;
    if (sessionId == null) return;
    _emitSummary(sessionId, snapshot, scope: 'boot-final');
  }

  // ── internals ──────────────────────────────────────────────────────────

  void _handleTerminalLag(
    DualReadComparison comparison,
    SessionHeadView head,
    TrajectoryHeadSnapshot snapshot,
    DateTime now,
  ) {
    final sessionId = comparison.sessionId;
    final attemptId = head.attemptId;
    final age = _terminalLag.ageOf(sessionId, now).inMilliseconds;
    if (age > accounting.maxTerminalLagMs) accounting.maxTerminalLagMs = age;
    accounting.record(comparison);
    final action = _terminalLag.observe(
      sessionId,
      now: now,
      appendQueued: attemptId != null && _appendQueuedFor(attemptId),
    );
    switch (action) {
      case TerminalLagAction.watch:
        return;
      case TerminalLagAction.heal:
        if (attemptId == null) {
          // The head predates process start: `AttemptTerminal.attemptId` is
          // REQUIRED and no id is ever minted here. SKIP and count.
          accounting.healsSkipped += 1;
          _terminalLag.noteHealAttempted(
            sessionId,
            TerminalReconcileOutcome.skippedNoAttemptId,
          );
          _flare(kReconstructedTerminalSkippedFlare, {
            'session_id': sessionId,
            'work_bead': head.workBeadId,
            'reason': 'no attempt_id on the P1 head',
            'basis': 'terminal-reconcile',
          });
          return;
        }
        final healer = _healer;
        if (healer == null) {
          accounting.healsSkipped += 1;
          _terminalLag.noteHealAttempted(
            sessionId,
            TerminalReconcileOutcome.skippedGuard,
          );
          return;
        }
        healer(
          TerminalReconcileRequest(
            sessionId: sessionId,
            attemptId: attemptId,
            workBeadId: head.workBeadId,
            report: (outcome) => _reportHeal(sessionId, outcome),
          ),
        );
      case TerminalLagAction.escalate:
        accounting.healEscalations += 1;
        _recordAndFlare(
          DualReadComparison(
            sessionId: sessionId,
            workBeadId: head.workBeadId,
            classification: DualReadClass.divergence,
            mismatches: const [
              DualReadFieldMismatch(
                field: 'terminalLag',
                foldValue: 'open',
                legacyValue: 'terminal',
              ),
            ],
          ),
          snapshot,
        );
    }
  }

  void _reportHeal(String sessionId, TerminalReconcileOutcome outcome) {
    switch (outcome) {
      case TerminalReconcileOutcome.appended:
        accounting.healsAppended += 1;
      case TerminalReconcileOutcome.skippedGuard:
      case TerminalReconcileOutcome.skippedNoAttemptId:
        accounting.healsSkipped += 1;
      case TerminalReconcileOutcome.failed:
        accounting.healsFailed += 1;
    }
    _terminalLag.noteHealAttempted(sessionId, outcome);
  }

  /// A CURRENT-open row for the same immutable base bead under a DIFFERENT
  /// session id — the successor mint, whose arrival is what makes a still-open
  /// retired row a dropped `roundRetired` rather than a live window.
  bool _successorPresent(
    TrajectoryHeadSnapshot snapshot,
    SessionHeadView retiredRow,
  ) {
    for (final row in snapshot.rows) {
      if (row.workBeadId != retiredRow.workBeadId) continue;
      if (row.sessionId == retiredRow.sessionId) continue;
      if (row.isOpen && row.round == 0) return true;
    }
    return false;
  }

  void _recordAndFlare(
    DualReadComparison comparison,
    TrajectoryHeadSnapshot snapshot,
  ) {
    final first = accounting.record(comparison);
    // A cardinality breach flares under the SAME name with `field:'cardinality'`
    // (§0.2 partition case 2) — it is its own accounting class only because the
    // gate arithmetic wants it separable, not because it is quieter.
    final flares =
        comparison.isDivergence ||
        comparison.classification == DualReadClass.cardinality;
    if (!first || !flares) return;
    for (final mismatch in comparison.mismatches) {
      _flare(kDualReadDivergenceFlare, {
        'axis': 'session',
        'work_bead': comparison.workBeadId,
        'session_id': comparison.sessionId,
        'field': mismatch.field,
        'fold_value': mismatch.foldValue,
        'legacy_value': mismatch.legacyValue,
        'snapshot_version': '${snapshot.version}',
      });
    }
  }

  void _noteHealth(TrajectorySnapshotHealth health) {
    if (_lastHealth == health) return;
    final previous = _lastHealth;
    _lastHealth = health;
    accounting.healthTransitions.add(
      previous == null ? health.name : '${previous.name}->${health.name}',
    );
  }

  /// One summary note per session TERMINAL (§0.4) — the transition edge, not
  /// the state, so a terminal session's note is written once however many
  /// joins observe it afterwards.
  void _emitTerminalSummaries(
    Map<String, SessionProjection> sessions,
    TrajectoryHeadSnapshot snapshot,
  ) {
    for (final legacy in sessions.values) {
      final sessionId = legacy.sessionId;
      if (sessionId == null || sessionId.isEmpty) continue;
      if (!legacy.isTerminal) continue;
      if (!_terminalSessions.add(sessionId)) continue;
      _lastTerminalSessionId = sessionId;
      _emitSummary(sessionId, snapshot, scope: 'session-terminal');
    }
  }

  void _emitSummary(
    String sessionId,
    TrajectoryHeadSnapshot snapshot, {
    required String scope,
  }) {
    final sink = _onRoundSummary;
    if (sink == null) return;
    try {
      sink(
        sessionId,
        accounting.toNoteBody(
          mode: _mode,
          health: snapshot.health,
          snapshotVersion: snapshot.version,
          seededAt: snapshot.seededAt,
          scope: scope,
        ),
      );
    } on Object {
      // Emit-only, the flare convention: an evidence sink that throws never
      // breaks the join that produced the evidence.
    }
  }

  void _flare(String name, Map<String, String> data) {
    final sink = _onFlare;
    if (sink == null) return;
    try {
      sink(name, data);
    } on Object {
      // Emit-only.
    }
  }
}
