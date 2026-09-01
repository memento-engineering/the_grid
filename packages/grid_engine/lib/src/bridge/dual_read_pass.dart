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
///
/// **C3 — what changed.** The pass now RESOLVES the overlay for every
/// identity-matched head and RETURNS the entries that differ, keyed by the
/// sessions map's own key. It still splices nothing itself: the JOIN applies
/// them, so the map has exactly one writer and the observer stays a
/// bookkeeper. Under `observe` the map is always empty and the resolution is
/// pure accounting — which is what makes the observe window a forecast of the
/// flip rather than a different code path.
library;

import '../domain/session_head_read.dart';
import '../domain/session_projection.dart';
import '../domain/step_cursor_read.dart' show legacyStepCursorOf;
import '../domain/trajectory_views.dart';
import '../sdk/circuit.dart' show StepState;

/// The emit-only flare sink shape the engine already uses everywhere else.
typedef DualReadFlareSink =
    void Function(String name, Map<String, String> data);

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

final class _SessionCompareWindow {
  const _SessionCompareWindow({
    required this.legacy,
    required this.foldLastSeq,
  });

  final SessionHeadFacts legacy;
  final int foldLastSeq;
}

/// Runs the session-axis comparator and owns everything it accumulates.
///
/// One instance per boot, held by the bridge. `observe` is called once per
/// join; `finish` once at the clean-down fixpoint.
class DualReadSessionObserver {
  DualReadSessionObserver({
    // OFF BY DEFAULT (r13): a composition that does not name a posture gets
    // the pre-cut station. The soak posture is armed explicitly.
    DualReadMode mode = DualReadMode.off,
    DateTime Function()? clock,
    bool Function(String attemptId)? appendQueuedFor,
    TerminalReconcileHealer? healer,
    DualReadFlareSink? onFlare,
    DualReadSummarySink? onRoundSummary,
    DualReadAppendStats Function()? appendStats,
    bool Function()? stepAxisEngaged,
    DualReadAccounting? accounting,
  }) : _mode = mode,
       _clock = clock ?? DateTime.now,
       _appendQueuedFor = appendQueuedFor ?? _neverQueued,
       _healer = healer,
       _onFlare = onFlare,
       _onRoundSummary = onRoundSummary,
       _appendStats = appendStats,
       _stepAxisEngaged = stepAxisEngaged,
       accounting = accounting ?? DualReadAccounting(clock: clock);

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

  /// The harness's append counters, read at summary time (§0.4's "drops").
  /// Null off-tree, and the summary simply omits the block.
  final DualReadAppendStats Function()? _appendStats;

  /// The STEP axis's posture at summary time (C4). It is the step observer's
  /// own `stepAxisEngaged`, read through a getter rather than passed as a
  /// value because the two passes run at different points of one join and the
  /// note must report what the step axis actually did — the same reason
  /// `overlay_engaged` is a served fact rather than the configured mode.
  final bool Function()? _stepAxisEngaged;

  /// The boot's counters — the round summary's payload and the soak gates'
  /// evidence.
  final DualReadAccounting accounting;

  final TerminalLagTracker _terminalLag = TerminalLagTracker();
  final RetirementLagTracker _retirementLag = RetirementLagTracker();
  final Map<String, _SessionCompareWindow> _compareWindowBySession =
      <String, _SessionCompareWindow>{};
  final Set<String> _operatorEditedSessions = <String>{};

  /// Sessions already seen terminal — the transition edge the per-terminal
  /// round summary rides. A set, not a counter: the join recomputes on every
  /// snapshot emission and a terminal session stays terminal forever.
  final Set<String> _terminalSessions = <String>{};

  String? _lastTerminalSessionId;
  TrajectorySnapshotHealth? _lastHealth;
  bool _finished = false;

  /// The last terminal session of the boot — the boot-final note's vehicle.
  String? get lastTerminalSessionId => _lastTerminalSessionId;

  /// THE POSTURE, as a served fact (C3): `primary` AND the boot has not
  /// disengaged. A caller reads this rather than the mode, because a
  /// `primary` boot that latched `compromised` serves legacy and must SAY so.
  bool get overlayEngaged =>
      _mode == DualReadMode.primary && !accounting.overlayDisengaged;

  /// Is the comparator ARMED at all? False under [DualReadMode.off], which is
  /// the rollback posture: no pass, no counters, no flares, no heal requests,
  /// no durable notes — and, because the bridge reads this before it
  /// subscribes, no mirror-driven re-join cadence either. `off` is the one
  /// posture that is byte-identical to pre-cut mainline.
  bool get armed => _mode != DualReadMode.off;

  /// ONE comparator pass over [sessions] (the join's map, keyed by the LEGACY
  /// work-bead key, which for a retired round is the `#rN`/`#void-` mutation)
  /// against [snapshot].
  ///
  /// Returns THE OVERLAY ENTRIES the join should splice, keyed by the same map
  /// key — empty under `observe`, empty while the boot is disengaged, and
  /// empty on the pass where every head agrees with its projection. The pass
  /// never mutates [sessions]: the join owns its map.
  Map<String, SessionProjection> observe(
    Map<String, SessionProjection> sessions,
    TrajectoryHeadSnapshot snapshot,
  ) {
    if (_finished) return const <String, SessionProjection>{};
    // THE ROLLBACK POSTURE: `off` runs no pass at all. Not "runs and serves
    // nothing" — nothing observable happens, so a boot under `off` writes the
    // same records, pushes the same joins and flares the same flares as
    // pre-cut mainline.
    if (!armed) return const <String, SessionProjection>{};
    accounting.beginPass();
    _noteHealth(snapshot.health);
    if (snapshot.health != TrajectorySnapshotHealth.live) {
      // Health non-`live` DISENGAGES the overlay for the boot (§0.2): every
      // session rides pure legacy — still fully written, still authoritative —
      // and every read counts as a fallback. No flares: the compromise itself
      // already flared once, at the latch. The LATCH is what makes "for the
      // boot" true rather than "for this pass": a mirror that missed one
      // append never becomes trustworthy again, whatever its health reads
      // later, and the reconciler reads the same latch off the same object.
      accounting.overlayDisengaged = true;
      accounting.fallbacks += sessions.length;
      _terminalLag.retainOnly(const <String>{});
      _retirementLag.retainOnly(const <String>{});
      _compareWindowBySession.clear();
      _operatorEditedSessions.clear();
      _emitTerminalSummaries(sessions, snapshot);
      return const <String, SessionProjection>{};
    }
    final engaged = overlayEngaged;
    final now = _clock();
    final matchedSessionIds = <String>{};
    final laggingTerminals = <String>{};
    final laggingRetirements = <String>{};
    final beadsToSentinel = <String>{};
    final overlays = <String, SessionProjection>{};
    final overlaidBeadByKey = <String, String>{};

    for (final entry in sessions.entries) {
      final legacy = entry.value;
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
      _observeCompareWindow(legacy, head);
      final cause = _causeFor(sessionId);
      final activeStepPath = _activeStepPathOf(legacy);

      // THE OVERLAY (C3), resolved for EVERY identity-matched head before any
      // classification branch — the two suppressors live inside
      // `resolveSessionOverlay`, so a reconstructed head and a demoting one
      // decline here for the same reason the comparator classes them
      // `reconstructedTerminal` and `terminalLag` below. One decision, one
      // function, no second copy of the rules.
      final resolved = resolveSessionOverlay(legacy, head);
      switch (resolved.outcome) {
        case SessionOverlayOutcome.applied:
          accounting.overlaysApplied += 1;
          if (engaged) {
            overlays[entry.key] = resolved.projection;
            overlaidBeadByKey[entry.key] = head.workBeadId;
            accounting.overlaysServed += 1;
          }
        case SessionOverlayOutcome.agreed:
          break;
        case SessionOverlayOutcome.suppressedReconstructed:
        case SessionOverlayOutcome.suppressedDemotion:
          accounting.overlaysSuppressed += 1;
      }

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
            cause: cause,
            activeStepPath: activeStepPath,
          );
        } else {
          accounting.record(
            DualReadComparison(
              sessionId: sessionId,
              workBeadId: head.workBeadId,
              classification: DualReadClass.retirementLag,
            ),
            cause: cause,
            activeStepPath: activeStepPath,
          );
        }
        continue;
      }

      final comparison = compareHeadToProjection(legacy, head);
      if (comparison.classification == DualReadClass.terminalLag) {
        laggingTerminals.add(sessionId);
        _handleTerminalLag(
          comparison,
          head,
          snapshot,
          now,
          cause: cause,
          activeStepPath: activeStepPath,
        );
        continue;
      }
      _recordAndFlare(
        comparison,
        snapshot,
        cause: cause,
        activeStepPath: activeStepPath,
      );
    }

    // The CARDINALITY SENTINEL rides `byWorkBead` — the classification view,
    // which is exactly the read that already handles multiplicity (§0.2's
    // "which index feeds what"). It never serves a row.
    for (final workBeadId in beadsToSentinel) {
      final winner = snapshot.byWorkBead(workBeadId);
      if (winner is! SessionHeadCardinalityBreach) continue;
      // THE BREACH RETRACTS THE SERVE (§0.2 partition case 2: "serve NO row").
      // The identity rule already kept a sibling's terminal off this session,
      // so what is left is narrower and still wrong to serve: the bead is
      // genuinely double-mounted, which means the fold and the ledger disagree
      // about how many sessions exist at all. Nothing about the four certified
      // fields is trustworthy under that, so the whole bead falls back to
      // legacy for the pass.
      overlays.removeWhere((key, _) {
        if (overlaidBeadByKey[key] != workBeadId) return false;
        accounting.overlaysServed -= 1;
        accounting.overlaysSuppressed += 1;
        return true;
      });
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
    _compareWindowBySession.removeWhere(
      (sessionId, _) => !matchedSessionIds.contains(sessionId),
    );
    _operatorEditedSessions.retainAll(matchedSessionIds);
    // THE NOTES RIDE THE END OF THE PASS, not its start (C3): `beginPass`
    // zeroes the GAUGES, and the gauges are half of what a gate reads —
    // `terminal_lag_open`, `miss_post_epoch`, `overlays_served`. A note
    // emitted before the loop would carry a zeroed pass and report every
    // round clean by construction, which is the same defect class r3 fixed
    // for the winner rule: a gate that cannot fail is not a gate.
    _emitTerminalSummaries(sessions, snapshot);
    return overlays;
  }

  /// The clean-down fixpoint's boot-final summary (§0.4), riding the sessionId
  /// of the LAST terminal session of the boot. A boot with ZERO terminal
  /// sessions appends no note — nothing gate-relevant happened, and every gate
  /// round contains terminal sessions by definition.
  void finish(TrajectoryHeadSnapshot snapshot) {
    if (_finished) return;
    if (!armed) return;
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
    DateTime now, {
    required DualReadDivergenceCause cause,
    required String? activeStepPath,
  }) {
    final sessionId = comparison.sessionId;
    final attemptId = head.attemptId;
    final age = _terminalLag.ageOf(sessionId, now).inMilliseconds;
    if (age > accounting.maxTerminalLagMs) accounting.maxTerminalLagMs = age;
    accounting.record(comparison, cause: cause, activeStepPath: activeStepPath);
    final action = _terminalLag.observe(
      sessionId,
      now: now,
      appendQueued: attemptId != null && _appendQueuedFor(attemptId),
    );
    switch (action) {
      case TerminalLagAction.watch:
        return;
      case TerminalLagAction.heal:
        if (cause == DualReadDivergenceCause.operatorStoreEdit) {
          _recordAndFlare(
            DualReadComparison(
              sessionId: comparison.sessionId,
              workBeadId: comparison.workBeadId,
              classification: DualReadClass.divergence,
              mismatches: comparison.mismatches,
            ),
            snapshot,
            cause: cause,
            activeStepPath: activeStepPath,
          );
        }
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
          // NO healer on this boot: no `traj_terminal_guard` was ever read, so
          // the durable evidence must not assert a guard fact nobody observed.
          // Its own outcome member, counted and permanently lag-classed.
          accounting.healsSkipped += 1;
          _terminalLag.noteHealAttempted(
            sessionId,
            TerminalReconcileOutcome.skippedNoHealer,
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
          cause: cause,
          activeStepPath: activeStepPath,
        );
    }
  }

  void _reportHeal(String sessionId, TerminalReconcileOutcome outcome) {
    switch (outcome) {
      case TerminalReconcileOutcome.appended:
        accounting.healsAppended += 1;
      case TerminalReconcileOutcome.skippedGuard:
      case TerminalReconcileOutcome.skippedNoAttemptId:
      case TerminalReconcileOutcome.skippedNoHealer:
      // Counted like any other skip — the round summary reports that no repair
      // was made. What differs is the TRACKER's treatment: this one does not
      // latch, so a later pass asks again (r13).
      case TerminalReconcileOutcome.skippedUnavailable:
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

  void _observeCompareWindow(SessionProjection legacy, SessionHeadView head) {
    final sessionId = head.sessionId;
    final current = legacyFactsOf(legacy);
    final previous = _compareWindowBySession[sessionId];
    final attemptId = head.attemptId;
    final appendQueued = attemptId != null && _appendQueuedFor(attemptId);
    if (previous != null) {
      if (head.lastSeq != previous.foldLastSeq || appendQueued) {
        _operatorEditedSessions.remove(sessionId);
      } else if (_sessionFactsDiffer(previous.legacy, current)) {
        _operatorEditedSessions.add(sessionId);
      }
    }
    _compareWindowBySession[sessionId] = _SessionCompareWindow(
      legacy: current,
      foldLastSeq: head.lastSeq,
    );
  }

  bool _sessionFactsDiffer(SessionHeadFacts left, SessionHeadFacts right) =>
      left.isTerminal != right.isTerminal ||
      left.completed != right.completed ||
      left.humanHeld != right.humanHeld ||
      left.closedAt != right.closedAt;

  DualReadDivergenceCause _causeFor(String sessionId) =>
      _operatorEditedSessions.contains(sessionId)
      ? DualReadDivergenceCause.operatorStoreEdit
      : DualReadDivergenceCause.unexplained;

  String? _activeStepPathOf(SessionProjection legacy) {
    final running = <String>[
      for (final entry in legacyStepCursorOf(legacy).entries)
        if (entry.value.state == StepState.running) entry.key,
    ]..sort();
    return running.isEmpty ? null : running.first;
  }

  void _recordAndFlare(
    DualReadComparison comparison,
    TrajectoryHeadSnapshot snapshot, {
    DualReadDivergenceCause cause = DualReadDivergenceCause.unexplained,
    String? activeStepPath,
  }) {
    final first = accounting.record(
      comparison,
      cause: cause,
      activeStepPath: activeStepPath,
    );
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
        'cause': cause.wire,
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
          overlayEngaged: overlayEngaged,
          stepAxisEngaged: _stepAxisEngaged?.call() ?? false,
          appendStats: _appendStats?.call(),
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
