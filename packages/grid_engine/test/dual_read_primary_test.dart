/// THE SESSION-AXIS DUAL READ, P1-PRIMARY (cut-wiring C3) — the overlay as
/// SERVED state.
///
/// C2 certified these functions while serving nothing; this suite is about the
/// serve. Its spine is the design's own property: for an equivalent
/// (record-stream, bead-state) pair the overlay must decide EXACTLY what pure
/// legacy decides, across every disposition — because wave 1 retires no writer,
/// so a `primary` boot that changed a disposition changed it for no reason a
/// human asked for.
///
/// Each group names the finding it regressions: F-B4 (terminal demotion),
/// J6-B1/J7-B1 (the pgid fail-open through a VOIDED overlay), J9-B1 (the
/// identity rule, now at the point of serve), J9-B2 (`workTerminalReason`
/// compare-only), O-B6 (the rework window never serving a P1-only entry),
/// J6-B3/J7-M3 (health disengages for the BOOT, not the pass).
library;

import 'dart:convert';
import 'dart:math';

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
    this.terminalProvenance,
    this.unknownReason,
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
  // Observed as a PRESENCE PAIR and never served (§0.3) — no test here needs
  // to vary them, and the fence-identity regression lives on the LEGACY side.
  @override
  int? get pgid => null;
  @override
  int? get pid => null;
  @override
  String? get attemptId => null;
  @override
  final SessionHeadProvenance? terminalProvenance;
  @override
  final String? unknownReason;
  @override
  final DateTime startedAt;
  @override
  final DateTime? closedAt;
  @override
  int get lastSeq => 1;
}

final class _Snapshot implements TrajectoryHeadSnapshot {
  _Snapshot(
    List<SessionHeadView> rows, {
    this.health = TrajectorySnapshotHealth.live,
    DateTime? firstEpochClaimedAt,
  }) : _rows = rows,
       firstEpochClaimedAt =
           firstEpochClaimedAt ?? DateTime.utc(2026, 8, 31, 9);

  final List<SessionHeadView> _rows;

  @override
  int get version => 11;
  @override
  final TrajectorySnapshotHealth health;
  @override
  final DateTime? firstEpochClaimedAt;
  @override
  DateTime? get seededAt => DateTime.utc(2026, 8, 31, 9);

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

DualReadSessionObserver _primary({
  DualReadAccounting? accounting,
  void Function(String, Map<String, String>)? onFlare,
  void Function(String, String)? onRoundSummary,
  DualReadAppendStats Function()? appendStats,
  DateTime Function()? clock,
}) => DualReadSessionObserver(
  mode: DualReadMode.primary,
  accounting: accounting,
  onFlare: onFlare,
  onRoundSummary: onRoundSummary,
  appendStats: appendStats,
  clock: clock,
);

/// ONE lifecycle shape, expressed on BOTH carriers — the "equivalent
/// (record-stream, bead-state) pair" the property quantifies over.
typedef _Shape = ({
  String name,
  SessionProjection legacy,
  SessionHeadView head,
});

/// Every disposition the design's test plan enumerates, each built so the two
/// sides describe the SAME history. `unknown` is deliberately absent: it is the
/// one shape where the fold's fail-closed mapping is MEANT to outrank what
/// legacy derives, and it has its own test below.
List<_Shape> _equivalentShapes() => [
  (name: 'live', legacy: _legacy(), head: _Head(sessionId: 's1')),
  (
    name: 'declined-open (F-m4: live on both sides)',
    legacy: _legacy(humanHeld: true),
    head: _Head(sessionId: 's1', held: true, heldReason: 'declined'),
  ),
  (
    name: 'done',
    legacy: _legacy(isTerminal: true, completed: true),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.succeeded,
    ),
  ),
  (
    name: 'settled (done)',
    legacy: _legacy(isTerminal: true, completed: true),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.settled,
    ),
  ),
  (
    name: 'escalated (held)',
    legacy: _legacy(isTerminal: true, humanHeld: true),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.escalated,
      workTerminalReason: 'breaker exhausted',
    ),
  ),
  (
    name: 'declined-then-terminal (held)',
    legacy: _legacy(isTerminal: true, humanHeld: true),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.failed,
      held: true,
      heldReason: 'declined',
    ),
  ),
  (
    name: 'void (lost)',
    legacy: _legacy(isTerminal: true, pgid: 4242, pid: 4243, token: 'tok'),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.lost,
    ),
  ),
  (
    name: 'failed (falls through to the cursor arm)',
    legacy: _legacy(isTerminal: true, pgid: 4242, pid: 4243, token: 'tok'),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.failed,
    ),
  ),
  (
    name: 'cancelled (falls through to the cursor arm)',
    legacy: _legacy(isTerminal: true),
    head: _Head(
      sessionId: 's1',
      isOpen: false,
      outcome: SessionHeadOutcome.cancelled,
    ),
  ),
];

void main() {
  group('THE PROPERTY (C3): an equivalent pair decides identically', () {
    for (final shape in _equivalentShapes()) {
      test('${shape.name} — sessionDispositionOf(overlay) == '
          'sessionDispositionOf(legacy)', () {
        final overlaid = sessionProjectionOverlay(shape.legacy, shape.head);
        expect(
          sessionDispositionOf(overlaid),
          sessionDispositionOf(shape.legacy),
          reason:
              'wave 1 retires no writer: a served overlay that changes a '
              'disposition on an agreeing pair changed it for no reason',
        );
      });
    }

    test('J6-B1/J7-B1 REGRESSION at the point of SERVE: a VOIDED overlaid '
        'session yields the same fence list as pure legacy', () {
      final legacy = _legacy(
        isTerminal: true,
        pgid: 4242,
        pid: 4243,
        token: 'tok',
      );
      // P1 SET-NULLs pid/pgid on `attempt.process.exited`, inferred exits
      // included. Serving those nulls would yield ZERO fences, pass the
      // deadness proof vacuously, and authorize spawning over a possibly-live
      // process group — I-10's fence turned fail-open.
      final overlaid = sessionProjectionOverlay(
        legacy,
        _Head(sessionId: 's1', isOpen: false, outcome: SessionHeadOutcome.lost),
      );
      expect(sessionDispositionOf(overlaid), isA<VoidedSession>());
      final served = staleFences(overlaid);
      final pure = staleFences(legacy);
      expect(served, hasLength(1));
      expect(served.single.pgid, pure.single.pgid);
      expect(served.single.pid, pure.single.pid);
      expect(served.single.token, pure.single.token);
    });

    test('unknown is the ONE deliberate asymmetry: HELD, fail-closed, where '
        'legacy would VOID (FINAL Q3)', () {
      // An empty-cursor legacy close voids — and voiding re-mints. The fold's
      // `unknown` says the station does not know how this round ended, so the
      // overlay holds it for a human and the settlement obligation heals the
      // outcome. Never voided, never done.
      final legacy = _legacy(isTerminal: true);
      expect(sessionDispositionOf(legacy), isA<VoidedSession>());
      final overlaid = sessionProjectionOverlay(
        legacy,
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.unknown,
          unknownReason: 'external-close',
        ),
      );
      expect(sessionDispositionOf(overlaid), isA<HeldSession>());
    });

    test('F-B4 REGRESSION as a PROPERTY: over 2000 generated pairs the served '
        'projection never demotes a terminal-family fact', () {
      final random = Random(20260901);
      const outcomes = SessionHeadOutcome.values;
      for (var i = 0; i < 2000; i++) {
        final legacy = _legacy(
          isTerminal: random.nextBool(),
          completed: random.nextBool(),
          humanHeld: random.nextBool(),
          closedAt: random.nextBool() ? DateTime.utc(2026, 8, 31, 12) : null,
        );
        final open = random.nextBool();
        final head = _Head(
          sessionId: 's1',
          isOpen: open,
          outcome: open ? null : outcomes[random.nextInt(outcomes.length)],
          held: random.nextBool(),
          unknownReason: 'external-close',
          closedAt: open ? null : DateTime.utc(2026, 8, 31, 13),
        );
        final served = sessionProjectionOverlay(legacy, head);
        expect(
          legacy.isTerminal && !served.isTerminal,
          isFalse,
          reason: 'isTerminal demoted at iteration $i',
        );
        expect(
          legacy.completed && !served.completed,
          isFalse,
          reason: 'completed demoted at iteration $i',
        );
        expect(
          legacy.humanHeld && !served.humanHeld,
          isFalse,
          reason: 'humanHeld demoted at iteration $i',
        );
        // …and the fields OUTSIDE the certified set never move, whatever the
        // fold says.
        expect(served.pgid, legacy.pgid);
        expect(served.pid, legacy.pid);
        expect(served.token, legacy.token);
        expect(served.workTerminalReason, legacy.workTerminalReason);
        expect(served.startedAt, legacy.startedAt);
      }
    });
  });

  group('resolveSessionOverlay — the outcome axis C3 counts on', () {
    test('an agreeing pair is AGREED and serves the legacy INSTANCE', () {
      final legacy = _legacy(isTerminal: true, completed: true);
      final resolved = resolveSessionOverlay(
        legacy,
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
          closedAt: null,
        ),
      );
      expect(resolved.outcome, SessionOverlayOutcome.agreed);
      expect(resolved.changed, isFalse);
      expect(resolved.projection, same(legacy));
    });

    test('a fold-ahead terminal is APPLIED', () {
      final legacy = _legacy();
      final resolved = resolveSessionOverlay(
        legacy,
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
          closedAt: DateTime.utc(2026, 8, 31, 12),
        ),
      );
      expect(resolved.outcome, SessionOverlayOutcome.applied);
      expect(resolved.projection.isTerminal, isTrue);
      expect(resolved.projection.completed, isTrue);
      expect(resolved.projection.closedAt, DateTime.utc(2026, 8, 31, 12));
    });

    test('the two suppressors are distinguishable — a round summary must be '
        'able to tell testimony from lag', () {
      final legacy = _legacy(isTerminal: true, completed: true);
      expect(
        resolveSessionOverlay(legacy, _Head(sessionId: 's1')).outcome,
        SessionOverlayOutcome.suppressedDemotion,
      );
      expect(
        resolveSessionOverlay(
          _legacy(),
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.unknown,
            unknownReason: 'external-close',
            terminalProvenance: SessionHeadProvenance.reconstructed,
          ),
        ).outcome,
        SessionOverlayOutcome.suppressedReconstructed,
      );
    });
  });

  group('the pass SERVES it (DualReadSessionObserver under primary)', () {
    test('observe serves nothing and primary serves the overlay — same input, '
        'same comparator, one config line apart', () {
      final legacy = _legacy();
      final snapshot = _Snapshot([
        _Head(
          sessionId: 's1',
          isOpen: false,
          outcome: SessionHeadOutcome.succeeded,
        ),
      ]);

      final observing = DualReadSessionObserver(mode: DualReadMode.observe);
      expect(observing.observe(_map([legacy]), snapshot), isEmpty);
      expect(observing.overlayEngaged, isFalse);

      final serving = _primary();
      final overlays = serving.observe(_map([legacy]), snapshot);
      expect(serving.overlayEngaged, isTrue);
      expect(overlays.keys, ['tg-9abc']);
      expect(sessionDispositionOf(overlays['tg-9abc']), isA<DoneSession>());
      expect(serving.accounting.overlaysApplied, 1);
      expect(serving.accounting.overlaysServed, 1);
      // OBSERVE still COUNTS what primary would have served — the observe
      // window is a forecast of the flip, not a different code path.
      expect(observing.accounting.overlaysApplied, 1);
      expect(observing.accounting.overlaysServed, isZero);
    });

    test(
      'an agreeing pass serves NOTHING — primary is quiet by construction',
      () {
        final observer = _primary();
        final overlays = observer.observe(
          _map([_legacy(isTerminal: true, completed: true)]),
          _Snapshot([
            _Head(
              sessionId: 's1',
              isOpen: false,
              outcome: SessionHeadOutcome.succeeded,
            ),
          ]),
        );
        expect(overlays, isEmpty);
        expect(observer.accounting.overlaysApplied, isZero);
        expect(observer.accounting.overlaysSuppressed, isZero);
        expect(observer.accounting.divergences, isZero);
      },
    );

    test('MONOTONE TERMINALITY at the serve: a legacy-terminal / P1-open pair '
        'serves nothing and is `terminalLag`, not a demotion', () {
      final observer = _primary();
      final overlays = observer.observe(
        _map([_legacy(isTerminal: true, completed: true)]),
        _Snapshot([_Head(sessionId: 's1')]),
      );
      expect(overlays, isEmpty);
      expect(observer.accounting.overlaysSuppressed, 1);
      expect(observer.accounting.terminalLagObserved, 1);
      expect(observer.accounting.divergences, isZero);
    });

    test('THE RECONSTRUCTED SUPPRESSOR at the serve: testimony never becomes a '
        'decision', () {
      final observer = _primary();
      final overlays = observer.observe(
        _map([_legacy()]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.unknown,
            unknownReason: 'external-close',
            terminalProvenance: SessionHeadProvenance.reconstructed,
          ),
        ]),
      );
      expect(overlays, isEmpty);
      expect(observer.accounting.overlaysSuppressed, 1);
      expect(observer.accounting.reconstructedTerminals, 1);
      expect(observer.accounting.divergences, isZero);
    });

    test('J9-B1 REGRESSION at the serve: a legacy session with NO row of its '
        'own is served PURE LEGACY even when a terminal SIBLING row sits on '
        'the same bead', () {
      final observer = _primary();
      final live = _legacy(sessionId: 's-live');
      final overlays = observer.observe(
        _map([live]),
        // The sibling is a PRIOR round's session on the same immutable base
        // key — done, closed, and none of this session's business. Serving it
        // would unmount live work; `lost` would route into a deadness proof
        // the unwired liveness probe passes vacuously.
        _Snapshot([
          _Head(
            sessionId: 's-sibling',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
      );
      expect(overlays, isEmpty);
      expect(observer.accounting.fallbacks, 1);
      expect(observer.accounting.hits, isZero);
      expect(observer.accounting.p1Orphan, 1);
      expect(sessionDispositionOf(live), isA<LiveSession>());
    });

    test('J9-B2 REGRESSION: an escalated session serves held with ZERO '
        'divergence, and workTerminalReason is reported COMPARE-ONLY', () {
      final observer = _primary();
      final legacy = _legacy(isTerminal: true, humanHeld: true);
      final overlays = observer.observe(
        _map([legacy]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.escalated,
            // The reason-key asymmetry: legacy stores escalation under
            // `grid.escalation_reason` and never reaches this field.
            workTerminalReason: 'breaker exhausted',
          ),
        ]),
      );
      expect(observer.accounting.divergences, isZero);
      final served = overlays['tg-9abc'] ?? legacy;
      expect(sessionDispositionOf(served), isA<HeldSession>());
      expect(served.workTerminalReason, isNull);
    });

    test('a CARDINALITY breach RETRACTS the serve for that bead (§0.2 case 2: '
        'serve NO row)', () {
      final flares = <(String, Map<String, String>)>[];
      final observer = _primary(onFlare: (n, d) => flares.add((n, d)));
      final overlays = observer.observe(
        _map([_legacy()]),
        // Two CURRENT open rows on one bead — a genuine double-mount, never a
        // rework (retired rows carry round > 0 and are excluded).
        _Snapshot([_Head(sessionId: 's1', held: true), _Head(sessionId: 's2')]),
      );
      expect(overlays, isEmpty, reason: 'the whole bead falls back to legacy');
      expect(observer.accounting.overlaysApplied, 1);
      expect(observer.accounting.overlaysServed, isZero);
      expect(observer.accounting.cardinalityBreaches, 1);
      expect(flares.where((f) => f.$2['field'] == 'cardinality'), hasLength(1));
    });

    test('O-B6 REGRESSION — the REWORK WINDOW: at every intermediate state the '
        'pass serves an entry legacy already has, or nothing new', () {
      // re-key → retire → remint, walked one state at a time. The invariant
      // under test is structural: the overlay decorates the legacy map and
      // never creates a key in it.
      final observer = _primary();
      final states = <(Map<String, SessionProjection>, _Snapshot)>[
        // 1. live round 0.
        (_map([_legacy()]), _Snapshot([_Head(sessionId: 's1')])),
        // 2. the bd bead is `#r1`-re-keyed and closed; the P1 row is still
        //    CURRENT open (the `roundRetired` record has not landed).
        (
          _map([_legacy(workBeadId: 'tg-9abc#r1', isTerminal: true)]),
          _Snapshot([_Head(sessionId: 's1')]),
        ),
        // 3. `roundRetired` lands: the row stays OPEN by schema design with
        //    round = 1. Retirement is LEGIBLE, and this is a steady state.
        (
          _map([_legacy(workBeadId: 'tg-9abc#r1', isTerminal: true)]),
          _Snapshot([_Head(sessionId: 's1', round: 1)]),
        ),
        // 4. the successor mints on the immutable base key.
        (
          _map([
            _legacy(workBeadId: 'tg-9abc#r1', isTerminal: true),
            _legacy(sessionId: 's2'),
          ]),
          _Snapshot([_Head(sessionId: 's1', round: 1), _Head(sessionId: 's2')]),
        ),
      ];
      for (var i = 0; i < states.length; i++) {
        final (sessions, snapshot) = states[i];
        final overlays = observer.observe(sessions, snapshot);
        for (final key in overlays.keys) {
          expect(
            sessions.containsKey(key),
            isTrue,
            reason: 'state $i created a P1-only entry under $key',
          );
        }
        for (final entry in overlays.entries) {
          expect(
            entry.value.isTerminal || !sessions[entry.key]!.isTerminal,
            isTrue,
            reason: 'state $i demoted a legacy terminal',
          );
        }
      }
      expect(observer.accounting.divergences, isZero);
    });
  });

  group('WAVE-1 HEALTH: any non-live snapshot disengages the overlay FOR THE '
      'BOOT (§0.2)', () {
    test('compromised serves nothing and counts every session a fallback', () {
      final observer = _primary();
      final overlays = observer.observe(
        _map([_legacy()]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ], health: TrajectorySnapshotHealth.compromised),
      );
      expect(overlays, isEmpty);
      expect(observer.overlayEngaged, isFalse);
      expect(observer.accounting.overlayDisengaged, isTrue);
      expect(observer.accounting.fallbacks, 1);
    });

    test('a refused SEED disengages too — a mirror that never read the fold '
        'is not a carrier', () {
      final observer = _primary();
      expect(
        observer.observe(
          _map([_legacy()]),
          _Snapshot(const [], health: TrajectorySnapshotHealth.refused),
        ),
        isEmpty,
      );
      expect(observer.accounting.overlayDisengaged, isTrue);
    });

    test('THE LATCH: a snapshot that reads live again does NOT re-engage the '
        'boot', () {
      final observer = _primary();
      final head = _Head(
        sessionId: 's1',
        isOpen: false,
        outcome: SessionHeadOutcome.succeeded,
      );
      observer.observe(
        _map([_legacy()]),
        _Snapshot([head], health: TrajectorySnapshotHealth.compromised),
      );
      // The mirror latches downward on its own, so this snapshot is a
      // hypothetical — which is exactly why the ENGINE keeps its own latch:
      // "for the boot" must not depend on another object's discipline.
      final overlays = observer.observe(_map([_legacy()]), _Snapshot([head]));
      expect(overlays, isEmpty);
      expect(observer.overlayEngaged, isFalse);
    });

    test('the latch is SHARED: one accounting, so a compromise seen by either '
        'reader stops both', () {
      final accounting = DualReadAccounting();
      DualReadSessionObserver(
        mode: DualReadMode.primary,
        accounting: accounting,
      ).observe(
        _map([_legacy()]),
        _Snapshot(const [], health: TrajectorySnapshotHealth.compromised),
      );
      final second = _primary(accounting: accounting);
      expect(second.overlayEngaged, isFalse);
      expect(
        second.observe(
          _map([_legacy()]),
          _Snapshot([
            _Head(
              sessionId: 's1',
              isOpen: false,
              outcome: SessionHeadOutcome.succeeded,
            ),
          ]),
        ),
        isEmpty,
      );
    });
  });

  group("THE SOAK GATE'S COUNTERS ride the round summary (§0.4)", () {
    Map<String, Object?> bodyOf(List<(String, String)> notes) =>
        jsonDecode(notes.last.$2) as Map<String, Object?>;

    test('a primary round reports what it SERVED — mode, engagement, and the '
        'three overlay gauges', () {
      final notes = <(String, String)>[];
      final observer = _primary(
        onRoundSummary: (id, body) => notes.add((id, body)),
      );
      observer.observe(
        _map([
          _legacy(isTerminal: true),
          _legacy(sessionId: 's2', workBeadId: 'tg-2'),
        ]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.unknown,
            unknownReason: 'external-close',
          ),
          _Head(sessionId: 's2', workBeadId: 'tg-2'),
        ]),
      );
      final body = bodyOf(notes);
      expect(body['mode'], 'primary');
      expect(body['overlay_engaged'], isTrue);
      expect(body['overlay_disengaged_for_boot'], isFalse);
      expect(body['overlays_applied'], 1);
      expect(body['overlays_served'], 1);
      expect(body['overlays_suppressed'], 0);
    });

    test('a DISENGAGED primary round says so — `mode: primary` alone would '
        'certify a round that quietly rode legacy', () {
      final notes = <(String, String)>[];
      final observer = _primary(
        onRoundSummary: (id, body) => notes.add((id, body)),
      );
      observer.observe(
        _map([_legacy(isTerminal: true)]),
        _Snapshot(const [], health: TrajectorySnapshotHealth.compromised),
      );
      final body = bodyOf(notes);
      expect(body['mode'], 'primary');
      expect(body['overlay_engaged'], isFalse);
      expect(body['health'], 'compromised');
      expect(body['fallbacks'], 1);
    });

    test("the harness's APPEND counters land in the note — a dropped append is "
        'a fold hole no comparator can see', () {
      final notes = <(String, String)>[];
      final observer = _primary(
        onRoundSummary: (id, body) => notes.add((id, body)),
        appendStats: () => (
          appended: 41,
          deduped: 2,
          dropped: 3,
          suppressed: 1,
          refusedTestimony: 4,
          queueDepth: 5,
        ),
      );
      observer.observe(
        _map([_legacy(isTerminal: true)]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
        ]),
      );
      final body = bodyOf(notes);
      expect(body['appends'], 41);
      expect(body['append_dedupes'], 2);
      expect(body['append_drops'], 3);
      expect(body['append_suppressed'], 1);
      expect(body['append_refused_testimony'], 4);
      expect(body['append_queue_depth'], 5);
    });

    test('a note carries THIS pass\'s gauges, not the zeroed ones `beginPass` '
        'just wrote — a gate that cannot fail is not a gate', () {
      final notes = <(String, String)>[];
      final observer = _primary(
        onRoundSummary: (id, body) => notes.add((id, body)),
      );
      observer.observe(
        _map([
          // A terminal session (the note's vehicle) beside a post-epoch MISS
          // and a lagging terminal — both gate-relevant gauges.
          _legacy(isTerminal: true, completed: true),
          _legacy(
            sessionId: 's2',
            workBeadId: 'tg-2',
            startedAt: DateTime.utc(2026, 8, 31, 10),
          ),
          _legacy(sessionId: 's3', workBeadId: 'tg-3', isTerminal: true),
        ]),
        _Snapshot([
          _Head(
            sessionId: 's1',
            isOpen: false,
            outcome: SessionHeadOutcome.succeeded,
          ),
          _Head(sessionId: 's3', workBeadId: 'tg-3'),
        ]),
      );
      final body = bodyOf(notes);
      expect(body['hits'], 2);
      expect(body['miss_post_epoch'], 1);
      expect(body['terminal_lag_open'], 1);
      expect(body['fallbacks'], 1);
    });
  });
}
