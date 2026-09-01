/// THE SESSION-AXIS DUAL READ, OBSERVE (cut-wiring C2) — the overlay's field
/// set and monotone guard, the comparator's classes, the ONE escalation rule,
/// and the durable round evidence.
///
/// The suite is written against the design's own falsifiers, and each group
/// names the finding it regressions: B-B4 (the escalated-session divergence
/// trap), F-B4 (terminal demotion), J6-B1/J7-B1 (the pgid fail-open), J9-B1
/// (the identity rule), J9-B2 (`workTerminalReason` compare-only), V2-B1 (the
/// normal-window race), V3-B1 (the guard skip).
library;

import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

// ── fakes ────────────────────────────────────────────────────────────────

final class _Head implements SessionHeadView {
  _Head({
    required this.sessionId,
    this.workBeadId = 'tg-9abc',
    this.round = 0,
    this.isOpen = true,
    this.outcome,
    this.held = false,
    this.heldReason,
    this.workTerminalReason,
    this.pgid,
    this.pid,
    this.attemptId,
    this.terminalProvenance,
    this.unknownReason,
    this.lastSeq = 1,
    DateTime? startedAt,
    this.closedAt,
  }) : startedAt = startedAt ?? DateTime.utc(2026, 8, 31, 10);

  @override
  final String sessionId;
  @override
  final String workBeadId;
  @override
  final int round;
  @override
  final bool isOpen;
  @override
  final SessionHeadOutcome? outcome;
  @override
  final bool held;
  @override
  final String? heldReason;
  @override
  final String? workTerminalReason;
  @override
  final int? pgid;
  @override
  final int? pid;
  @override
  final String? attemptId;
  @override
  final SessionHeadProvenance? terminalProvenance;
  @override
  final String? unknownReason;
  @override
  final DateTime startedAt;
  @override
  final DateTime? closedAt;
  @override
  final int lastSeq;
}

final class _Snapshot implements TrajectoryHeadSnapshot {
  _Snapshot(
    List<SessionHeadView> rows, {
    this.version = 7,
    this.health = TrajectorySnapshotHealth.live,
    this.firstEpochClaimedAt,
    this.seededAt,
  }) : _rows = rows;

  final List<SessionHeadView> _rows;

  @override
  final int version;
  @override
  final TrajectorySnapshotHealth health;
  @override
  final DateTime? firstEpochClaimedAt;
  @override
  final DateTime? seededAt;

  @override
  SessionHeadView? bySessionId(String sessionId) {
    for (final row in _rows) {
      if (row.sessionId == sessionId) return row;
    }
    return null;
  }

  @override
  SessionHeadWinner byWorkBead(String workBeadId) => sessionHeadWinnerOf([
    for (final row in _rows)
      if (row.workBeadId == workBeadId) row,
  ]);

  @override
  Iterable<SessionHeadView> get rows => _rows;
}

/// Collects everything the observer emits — flares, heal requests, notes.
final class _Sinks {
  final List<(String, Map<String, String>)> flares = [];
  final List<(String, String)> notes = [];
  final List<TerminalReconcileRequest> heals = [];

  /// What the next heal reports back. Default: it landed.
  TerminalReconcileOutcome healOutcome = TerminalReconcileOutcome.appended;

  void flare(String name, Map<String, String> data) =>
      flares.add((name, data));

  void note(String sessionId, String body) => notes.add((sessionId, body));

  void heal(TerminalReconcileRequest request) {
    heals.add(request);
    request.report(healOutcome);
  }

  Iterable<Map<String, String>> divergences() => [
    for (final (name, data) in flares)
      if (name == kDualReadDivergenceFlare) data,
  ];
}

SessionProjection _legacy({
  String sessionId = 's1',
  String workBeadId = 'tg-9abc',
  bool isTerminal = false,
  bool completed = false,
  bool humanHeld = false,
  int? pgid,
  int? pid,
  String? token,
  String? workTerminalReason,
  DateTime? startedAt,
  DateTime? closedAt,
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  isTerminal: isTerminal,
  completed: completed,
  humanHeld: humanHeld,
  pgid: pgid,
  pid: pid,
  token: token,
  workTerminalReason: workTerminalReason,
  startedAt: startedAt ?? DateTime.utc(2026, 8, 31, 10),
  closedAt: closedAt,
);

Map<String, SessionProjection> _map(List<SessionProjection> sessions) => {
  for (final session in sessions) session.workBeadId: session,
};

void main() {
  group('sessionProjectionOverlay — the r5 field set (§0.3)', () {
    test('an open head leaves a live session live', () {
      final legacy = _legacy();
      final overlaid = sessionProjectionOverlay(legacy, _Head(sessionId: 's1'));
      expect(overlaid.isTerminal, isFalse);
      expect(sessionDispositionOf(overlaid), isA<LiveSession>());
    });

    test('outcome succeeded/settled ⇒ done; lost ⇒ voided; escalated and '
        'unknown ⇒ held (unknown FAIL-CLOSED, FINAL Q3)', () {
      SessionDisposition dispositionFor(SessionHeadOutcome outcome) =>
          sessionDispositionOf(
            sessionProjectionOverlay(
              _legacy(),
              _Head(
                sessionId: 's1',
                isOpen: false,
                outcome: outcome,
                unknownReason: outcome == SessionHeadOutcome.unknown
                    ? 'external-close'
                    : null,
              ),
            ),
          );
      expect(dispositionFor(SessionHeadOutcome.succeeded), isA<DoneSession>());
      expect(dispositionFor(SessionHeadOutcome.settled), isA<DoneSession>());
      expect(dispositionFor(SessionHeadOutcome.lost), isA<VoidedSession>());
      expect(dispositionFor(SessionHeadOutcome.escalated), isA<HeldSession>());
      // FAIL-CLOSED: never voided, never done. The settlement obligation heals
      // the outcome; until then a human owns the round.
      expect(dispositionFor(SessionHeadOutcome.unknown), isA<HeldSession>());
    });

    test('a DECLINED-open head is live on both sides (r3 — F-m4): the marker '
        'only becomes decision-bearing at terminality', () {
      final overlaid = sessionProjectionOverlay(
        _legacy(),
        _Head(sessionId: 's1', held: true, heldReason: 'declined'),
      );
      expect(overlaid.humanHeld, isTrue);
      expect(sessionDispositionOf(overlaid), isA<LiveSession>());
    });

    test('MONOTONE GUARD (F-B4): a P1 value that would demote a legacy '
        'terminal fact applies NO overrides at all', () {
      final legacy = _legacy(isTerminal: true, completed: true);
      final overlaid = sessionProjectionOverlay(
        legacy,
        _Head(sessionId: 's1'),
      );
      expect(overlaid, same(legacy));
      expect(overlaid.isTerminal, isTrue);
      expect(overlaid.completed, isTrue);
    });

    test('the guard covers completed and humanHeld demotions too, not just '
        'isTerminal', () {
      final completedLegacy = _legacy(isTerminal: true, completed: true);
      expect(
        sessionProjectionOverlay(
          completedLegacy,
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.failed,
          ),
        ),
        same(completedLegacy),
      );
      final heldLegacy = _legacy(isTerminal: true, humanHeld: true);
      expect(
        sessionProjectionOverlay(
          heldLegacy,
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ),
        same(heldLegacy),
      );
    });

    test('a RECONSTRUCTED head serves PURE LEGACY (r5/r7): fold bookkeeping '
        'is never decision state', () {
      final legacy = _legacy();
      expect(
        sessionProjectionOverlay(
          legacy,
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.unknown,
            unknownReason: 'external-close',
            terminalProvenance: SessionHeadProvenance.reconstructed,
          ),
        ),
        same(legacy),
      );
    });

    test('J6-B1/J7-B1 REGRESSION: pgid/pid/token stay WHOLE on the legacy '
        'carrier — a voided overlaid session yields the SAME fence list as '
        'pure legacy', () {
      final legacy = _legacy(pgid: 4242, pid: 4243, token: 'tok');
      final overlaid = sessionProjectionOverlay(
        legacy,
        // P1 SET-NULLs pid/pgid on `attempt.process.exited`, including an
        // inferred exit. An overlaid null here would yield ZERO fences, pass
        // the deadness proof vacuously, and authorize spawning over a
        // possibly-live process group.
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.lost,
        ),
      );
      expect(sessionDispositionOf(overlaid), isA<VoidedSession>());
      expect(overlaid.pgid, 4242);
      expect(overlaid.pid, 4243);
      expect(overlaid.token, 'tok');
      final overlaidFences = staleFences(overlaid);
      final legacyFences = staleFences(legacy);
      expect(overlaidFences, hasLength(1));
      expect(legacyFences, hasLength(1));
      expect(overlaidFences.single.pgid, legacyFences.single.pgid);
      expect(overlaidFences.single.pid, legacyFences.single.pid);
      expect(overlaidFences.single.token, legacyFences.single.token);
    });

    test('J9-B2 REGRESSION: workTerminalReason is NOT overridden', () {
      final overlaid = sessionProjectionOverlay(
        _legacy(),
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.escalated,
          workTerminalReason: 'breaker exhausted',
        ),
      );
      expect(overlaid.workTerminalReason, isNull);
    });

    test('closedAt IS in the override set, and a null fold value never wipes '
        'the legacy instant', () {
      final closedAt = DateTime.utc(2026, 8, 31, 15);
      expect(
        sessionProjectionOverlay(
          _legacy(),
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
            closedAt: closedAt,
          ),
        ).closedAt,
        closedAt,
      );
      expect(
        sessionProjectionOverlay(
          _legacy(closedAt: closedAt),
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ).closedAt,
        closedAt,
      );
    });
  });

  group('compareHeadToProjection — the derived tuple (§0.3)', () {
    test('B-B4 REGRESSION: an ESCALATED session is a MATCH — the reason-key '
        'asymmetry is compare-only, never a divergence', () {
      final comparison = compareHeadToProjection(
        // Legacy derives humanHeld from the `grid.escalation` stamp and leaves
        // work_terminal_reason NULL (the escalation reason rides a DIFFERENT
        // bd key); P1 takes the breaker reason into work_terminal_reason.
        _legacy(isTerminal: true, humanHeld: true),
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.escalated,
          workTerminalReason: 'breaker exhausted',
        ),
      );
      expect(comparison.classification, DualReadClass.match);
      expect(comparison.mismatches, isEmpty);
      expect(comparison.foldWorkTerminalReason, 'breaker exhausted');
      expect(comparison.legacyWorkTerminalReason, isNull);
    });

    test('the pgid/pid PRESENCE pair is observed and reported, never served', () {
      // P1 SET-NULLs pid/pgid on `attempt.process.exited` while legacy's
      // scalar fence is stamped at SessionStarted and never cleared, so the
      // pair disagreeing is EXPECTED after an exit — which is exactly why
      // neither field is served.
      final afterExit = compareHeadToProjection(
        _legacy(pgid: 1, pid: 2),
        _Head(sessionId: 's1'),
      );
      expect(afterExit.pgidPresenceAgrees, isFalse);
      // …and it does not make the pair a divergence.
      expect(afterExit.classification, DualReadClass.match);
      final live = compareHeadToProjection(
        _legacy(pgid: 1, pid: 2),
        _Head(sessionId: 's1', pgid: 1, pid: 2),
      );
      expect(live.pgidPresenceAgrees, isTrue);
    });

    test('a real tuple mismatch is a divergence naming the field', () {
      final comparison = compareHeadToProjection(
        _legacy(),
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      );
      expect(comparison.classification, DualReadClass.divergence);
      expect(
        comparison.mismatches.map((m) => m.field),
        containsAll(<String>['isTerminal', 'completed']),
      );
    });

    test('legacy terminal + P1 open is terminalLag, never a divergence', () {
      final comparison = compareHeadToProjection(
        _legacy(isTerminal: true, completed: true),
        _Head(sessionId: 's1'),
      );
      expect(comparison.classification, DualReadClass.terminalLag);
    });

    test('the reconstructed mark suppresses even a real mismatch', () {
      final comparison = compareHeadToProjection(
        _legacy(),
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.unknown,
          unknownReason: 'teardown-replay',
          terminalProvenance: SessionHeadProvenance.reconstructed,
        ),
      );
      expect(comparison.classification, DualReadClass.reconstructedTerminal);
      expect(comparison.mismatches, isNotEmpty);
    });
  });

  group('the miss classifier (B-M5)', () {
    final epoch = DateTime.utc(2026, 8, 31, 12);

    test('post-epoch start with no head is a POST-EPOCH miss', () {
      final miss = classifyDualReadMiss(
        _legacy(startedAt: DateTime.utc(2026, 8, 31, 13)),
        epoch,
      );
      expect(miss.era, DualReadMissClass.postEpoch);
      expect(miss.nullStartedAt, isFalse);
    });

    test('a pre-epoch start is legacy-era', () {
      final miss = classifyDualReadMiss(
        _legacy(startedAt: DateTime.utc(2026, 8, 31, 11)),
        epoch,
      );
      expect(miss.era, DualReadMissClass.legacyEra);
    });

    test('a NULL startedAt is classified legacyEra and counted separately, so '
        'corruption stays visible without poisoning the post-epoch gate', () {
      final legacy = SessionProjection(workBeadId: 'tg-9abc', sessionId: 's1');
      final miss = classifyDualReadMiss(legacy, epoch);
      expect(miss.era, DualReadMissClass.legacyEra);
      expect(miss.nullStartedAt, isTrue);
    });

    test('with no epoch boundary known, nothing post-epoch is asserted', () {
      expect(
        classifyDualReadMiss(_legacy(), null).era,
        DualReadMissClass.legacyEra,
      );
    });
  });

  group('DualReadSessionObserver — the pass', () {
    test('a planted mismatch flares ONCE with the full payload', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      final sessions = _map([_legacy()]);
      final snapshot = _Snapshot([
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]);
      observer
        ..observe(sessions, snapshot)
        ..observe(sessions, snapshot)
        ..observe(sessions, snapshot);
      final flares = sinks.divergences().toList();
      expect(flares, hasLength(2)); // isTerminal + completed, once each.
      expect(flares.first['axis'], 'session');
      expect(flares.first['work_bead'], 'tg-9abc');
      expect(flares.first['session_id'], 's1');
      expect(flares.first['snapshot_version'], '7');
      expect(flares.map((f) => f['field']), containsAll(['isTerminal', 'completed']));
      // Deduped by (session, field): a persistent divergence counts once.
      expect(observer.accounting.divergences, 2);
      expect(observer.accounting.passes, 3);
    });

    test('an ESCALATED session produces ZERO divergences (the B-B4 trap the '
        'C2 gate would otherwise be unable to satisfy)', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      observer.observe(
        _map([_legacy(isTerminal: true, humanHeld: true)]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.escalated,
            workTerminalReason: 'breaker exhausted',
          ),
        ]),
      );
      expect(observer.accounting.divergences, isZero);
      expect(sinks.divergences(), isEmpty);
      expect(observer.accounting.hits, 1);
    });

    test('a SNAPSHOT-ABSENT boot is all-fallback with zero flares', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      observer.observe(
        _map([_legacy(), _legacy(sessionId: 's2', workBeadId: 'tg-2')]),
        _Snapshot(const [], health: TrajectorySnapshotHealth.refused),
      );
      expect(observer.accounting.fallbacks, 2);
      expect(observer.accounting.hits, isZero);
      expect(sinks.flares, isEmpty);
      expect(observer.accounting.healthTransitions, ['refused']);
    });

    test('a P1 MISS is a fallback classified by era — never a sibling row '
        'spliced on (J9-B1, the OVERLAY IDENTITY RULE)', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      // The live session has NO row; a TERMINAL SIBLING sits on the same bead.
      observer.observe(
        _map([_legacy(startedAt: DateTime.utc(2026, 8, 31, 13))]),
        _Snapshot(
          [
            _Head(
              sessionId: 'sibling',
              isOpen: false,
              outcome: SessionHeadOutcome.succeeded,
              lastSeq: 99,
            ),
          ],
          firstEpochClaimedAt: DateTime.utc(2026, 8, 31, 12),
        ),
      );
      expect(observer.accounting.fallbacks, 1);
      expect(observer.accounting.missPostEpoch, 1);
      expect(observer.accounting.divergences, isZero);
      // The sibling is inert for decisions and merely counted.
      expect(observer.accounting.p1Orphan, 1);
      expect(sinks.flares, isEmpty);
    });

    test('a genuine two-CURRENT-open plant breaches cardinality and serves no '
        'row', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      observer.observe(
        _map([_legacy()]),
        _Snapshot([
          _Head(sessionId: 's1'),
          _Head(sessionId: 's2'),
        ]),
      );
      expect(observer.accounting.cardinalityBreaches, 1);
      final flare = sinks.divergences().single;
      expect(flare['field'], 'cardinality');
      expect(flare['session_id'], 's1,s2');
    });

    test('two current-open rows on DIFFERENT beads are not a breach', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onFlare: sinks.flare);
      observer.observe(
        _map([_legacy(), _legacy(sessionId: 's2', workBeadId: 'tg-other')]),
        _Snapshot([
          _Head(sessionId: 's1'),
          _Head(sessionId: 's2', workBeadId: 'tg-other'),
        ]),
      );
      expect(observer.accounting.cardinalityBreaches, isZero);
      expect(observer.accounting.hits, 2);
      expect(sinks.flares, isEmpty);
    });

    test('a full REWORK lifecycle produces retirementLag transients, ZERO '
        'divergences, and lag zero at round end', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
      );
      // 1. the re-key: the bd bead is closed and re-keyed `#r1`, the P1 row is
      //    still CURRENT-open because `roundRetired` has not landed.
      final retiredLegacy = _legacy(
        sessionId: 's1',
        workBeadId: 'tg-9abc#r1',
        isTerminal: true,
      );
      observer.observe(
        _map([retiredLegacy]),
        _Snapshot([_Head(sessionId: 's1')]),
      );
      expect(observer.accounting.retirementLagObserved, 1);
      expect(observer.accounting.openRetirementLag, 1);
      expect(observer.accounting.divergences, isZero);

      // 2. `roundRetired` lands: the row leaves the CURRENT partition, and the
      //    successor is minted. Both sides agree again.
      now = now.add(const Duration(seconds: 5));
      observer.observe(
        _map([
          retiredLegacy,
          _legacy(sessionId: 's2'),
        ]),
        _Snapshot([
          _Head(sessionId: 's1', round: 1, isOpen: true),
          _Head(sessionId: 's2'),
        ]),
      );
      expect(observer.accounting.divergences, isZero);
      expect(observer.accounting.openRetirementLag, isZero);
      expect(observer.accounting.openLagEntries, isZero);
    });

    test('a retired row still CURRENT past the grace WITH the successor '
        'present escalates to a divergence (r9)', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
      );
      final sessions = _map([
        _legacy(sessionId: 's1', workBeadId: 'tg-9abc#r1', isTerminal: true),
        _legacy(sessionId: 's2'),
      ]);
      final snapshot = _Snapshot([
        _Head(sessionId: 's1'),
        _Head(sessionId: 's2'),
      ]);
      List<String> fields() => [
        for (final flare in sinks.divergences()) flare['field']!,
      ];
      observer.observe(sessions, snapshot);
      // The successor's arrival with the retired row still CURRENT is ALSO a
      // genuine two-current-open partition, so the cardinality sentinel speaks
      // immediately; the retirement escalation waits out its grace.
      expect(fields(), ['cardinality']);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot);
      expect(fields(), ['cardinality', 'retirementLag']);
    });
  });

  group('MONOTONIC TERMINALITY — the ONE escalation rule (§0.3, r8)', () {
    test('RACE REGRESSION (V2-B1): a NORMAL terminal transiting the window '
        'triggers NO heal and NO flare', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final terminal = _legacy(isTerminal: true, completed: true);
      // bd first, append after: two passes inside the post-ACK apply time.
      observer.observe(
        _map([terminal]),
        _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]),
      );
      now = now.add(const Duration(milliseconds: 40));
      observer.observe(
        _map([terminal]),
        _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]),
      );
      // The record lands; the head closes.
      now = now.add(const Duration(milliseconds: 10));
      observer.observe(
        _map([terminal]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
            attemptId: 'att-1',
          ),
        ]),
      );
      expect(sinks.heals, isEmpty);
      expect(sinks.flares, isEmpty);
      expect(observer.accounting.divergences, isZero);
      expect(observer.accounting.openTerminalLag, isZero);
      expect(observer.accounting.terminalLagObserved, 1);
    });

    test('a queued append for the attempt holds the heal off however long the '
        'lag runs', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
        appendQueuedFor: (attemptId) => attemptId == 'att-1',
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]);
      for (var i = 0; i < 4; i++) {
        observer.observe(sessions, snapshot);
        now = now.add(const Duration(seconds: 60));
      }
      expect(sinks.heals, isEmpty);
      expect(sinks.flares, isEmpty);
    });

    test('a DROPPED terminal append heals at the 90 s grace across two '
        'passes, and the heal alone raises no flare', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]);
      observer.observe(sessions, snapshot); // pass 1 — inside the grace
      expect(sinks.heals, isEmpty);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot); // pass 2 — past it
      expect(sinks.heals, hasLength(1));
      expect(sinks.heals.single.sessionId, 's1');
      expect(sinks.heals.single.attemptId, 'att-1');
      expect(sinks.heals.single.workBeadId, 'tg-9abc');
      expect(observer.accounting.healsAppended, 1);
      expect(sinks.flares, isEmpty);
    });

    test('ESCALATION fires only after a heal was attempted AND the entry '
        'survived one further full pass', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]);
      observer.observe(sessions, snapshot);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot); // heal
      expect(sinks.divergences(), isEmpty);
      observer.observe(sessions, snapshot); // one further pass ⇒ escalate
      final flare = sinks.divergences().single;
      expect(flare['field'], 'terminalLag');
      expect(observer.accounting.healEscalations, 1);
      // …and it escalates exactly once, however many passes follow.
      observer.observe(sessions, snapshot);
      expect(sinks.divergences(), hasLength(1));
    });

    test('a heal planted to FAIL escalates on the very next pass', () {
      final sinks = _Sinks()..healOutcome = TerminalReconcileOutcome.failed;
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]);
      observer.observe(sessions, snapshot);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot);
      expect(observer.accounting.healsFailed, 1);
      observer.observe(sessions, snapshot);
      expect(sinks.divergences().single['field'], 'terminalLag');
    });

    test('a GUARD SKIP (V3-B1: the real record already landed) is pure lag — '
        'counted, never escalated on its own account', () {
      final sinks = _Sinks()
        ..healOutcome = TerminalReconcileOutcome.skippedGuard;
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1', attemptId: 'att-1')]);
      observer.observe(sessions, snapshot);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot);
      expect(observer.accounting.healsSkipped, 1);
      expect(observer.accounting.healsAppended, isZero);
      expect(sinks.divergences(), isEmpty);
    });

    test('a head with NO attempt_id SKIPS the heal, counts it, and flares '
        'reconstructedTerminalSkipped — no id is ever minted', () {
      final sinks = _Sinks();
      var now = DateTime.utc(2026, 8, 31, 14);
      final observer = DualReadSessionObserver(
        onFlare: sinks.flare,
        clock: () => now,
        healer: sinks.heal,
      );
      final sessions = _map([_legacy(isTerminal: true, completed: true)]);
      final snapshot = _Snapshot([_Head(sessionId: 's1')]);
      observer.observe(sessions, snapshot);
      now = now.add(const Duration(seconds: 91));
      observer.observe(sessions, snapshot);
      expect(sinks.heals, isEmpty);
      expect(observer.accounting.healsSkipped, 1);
      expect(
        sinks.flares.single.$1,
        kReconstructedTerminalSkippedFlare,
      );
      expect(sinks.flares.single.$2['basis'], 'terminal-reconcile');
    });
  });

  group('the durable round evidence (§0.4)', () {
    test('one note per session TERMINAL, on the transition edge', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onRoundSummary: sinks.note);
      final live = _map([_legacy()]);
      final snapshot = _Snapshot([_Head(sessionId: 's1')]);
      observer.observe(live, snapshot);
      expect(sinks.notes, isEmpty);
      final terminal = _map([_legacy(isTerminal: true, completed: true)]);
      final closed = _Snapshot(
        [
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ],
        version: 31,
        seededAt: DateTime.utc(2026, 8, 31, 9),
      );
      observer
        ..observe(terminal, closed)
        ..observe(terminal, closed)
        ..observe(terminal, closed);
      expect(sinks.notes, hasLength(1));
      expect(sinks.notes.single.$1, 's1');
      expect(sinks.notes.single.$2, contains('"scope":"session-terminal"'));
      expect(sinks.notes.single.$2, contains('"mode":"observe"'));
      // C4: ONE note carries BOTH axes, so the field names both.
      expect(sinks.notes.single.$2, contains('"axis":"session+step"'));
      // The note names the exact snapshot it was written against, so a gate
      // reading it across boots can say which state produced the counters.
      expect(sinks.notes.single.$2, contains('"snapshot_version":31'));
      expect(sinks.notes.single.$2, contains('"seeded_at":'));
    });

    test('the boot-final note rides the LAST terminal session; an idle boot '
        'appends none', () {
      final sinks = _Sinks();
      final observer = DualReadSessionObserver(onRoundSummary: sinks.note);
      final snapshot = _Snapshot(const []);
      observer
        ..observe(
          _map([
            _legacy(isTerminal: true),
            _legacy(sessionId: 's2', workBeadId: 'tg-2', isTerminal: true),
          ]),
          snapshot,
        )
        ..finish(snapshot);
      expect(sinks.notes.last.$1, observer.lastTerminalSessionId);
      expect(sinks.notes.last.$2, contains('"scope":"boot-final"'));

      final idleSinks = _Sinks();
      DualReadSessionObserver(onRoundSummary: idleSinks.note)
        ..observe(_map([_legacy()]), snapshot)
        ..finish(snapshot);
      expect(idleSinks.notes, isEmpty);
    });

    test('the summary carries every gate-relevant counter', () {
      final accounting = DualReadAccounting()
        ..beginPass()
        ..hits = 3
        ..missPostEpoch = 1
        ..nullStartedAt = 2;
      final json = accounting.toJson(
        mode: DualReadMode.observe,
        health: TrajectorySnapshotHealth.live,
        snapshotVersion: 12,
      );
      expect(json['hits'], 3);
      expect(json['miss_post_epoch'], 1);
      expect(json['null_started_at'], 2);
      expect(json['divergences'], 0);
      expect(json['terminal_lag'], 0);
      expect(json['retirement_lag'], 0);
      expect(json['reconstructed_terminals'], 0);
      expect(json['channel'], kDualReadRoundSummaryChannel);
    });
  });
}
