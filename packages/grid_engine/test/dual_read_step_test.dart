/// THE STEP-AXIS DUAL READ (cut-wiring C4) — the collapse rule, the three
/// step-axis protections, `stepLag`'s arithmetic, and the shared helper the
/// seven cursor consumers adopt.
///
/// Written against the design's own falsifiers, each group naming what it
/// regressions: J8-B2 (the bead-first/append-later window at all three persist
/// sites), J10-B2/J11-B2 (the step axis's OVERLAY IDENTITY RULE), I-10 (an
/// omitted node re-mounted as unclaimed), I-14 (gate → rearm → resume), V1-M5
/// (the collapse's ordering), and the r4 OPEN CARRY (J6-M1/J7-M5: "config off
/// = today" at the two sites that iterate the structurally-empty field).
library;

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

// ── fakes ────────────────────────────────────────────────────────────────

final class _Row implements StepCursorView {
  _Row({
    required this.stepPath,
    required this.stepState,
    this.sessionId = 'tgdog-1',
    this.round = 0,
    this.stepRound = 0,
  });

  @override
  final String sessionId;
  @override
  final int round;
  @override
  final String stepPath;
  @override
  final int stepRound;
  @override
  final String stepState;

  // The rest of P2's column set is COMPARE-ONLY telemetry on the wave-1 path
  // (`restartCount`/`cooldownUntil` and the fence triple stay bead-read —
  // B-M2), so the fake pins them at their absent shape rather than pretending
  // a read that no consumer makes.
  @override
  int get incarnation => 0;
  @override
  String? get attemptId => null;
  @override
  int? get supersededByStepRound => null;
  @override
  DateTime? get cooldownUntil => null;
  @override
  int? get restartBudget => null;
  @override
  DateTime? get startedAt => null;
  @override
  DateTime? get readyAt => null;
  @override
  DateTime? get completedAt => null;
  @override
  String? get failureClass => null;
  @override
  int get lastSeq => 1;
}

final class _StepSnapshot implements TrajectoryStepSnapshot {
  _StepSnapshot(this._rows, {this.health = TrajectorySnapshotHealth.live});

  final List<StepCursorView> _rows;

  @override
  int get version => 11;
  @override
  final TrajectorySnapshotHealth health;
  @override
  DateTime? get seededAt => null;
  @override
  DateTime? get firstEpochClaimedAt => null;

  @override
  Iterable<StepCursorView> byP2SessionId(String sessionId) => [
    for (final row in _rows)
      if (row.sessionId == sessionId) row,
  ];
}

Bead _stepBead(
  String nodePath, {
  required StepState state,
  int restartCount = 0,
  DateTime? cooldownUntil,
  String sessionId = 'tgdog-1',
}) => Bead(
  id: 'tgdog-step-${nodePath.replaceAll('/', '-')}',
  issueType: GridIssueTypes.step,
  status: BeadStatus.open,
  metadata: {
    MoleculeStepKeys.path: nodePath,
    MoleculeStepKeys.state: state.name,
    MoleculeStepKeys.session: sessionId,
    MoleculeStepKeys.restartCount: '$restartCount',
    if (cooldownUntil != null)
      MoleculeStepKeys.cooldownUntil: cooldownUntil.toUtc().toIso8601String(),
  },
);

SessionProjection _session({
  List<Bead> steps = const [],
  CircuitCursor? trajCursor,
  bool terminal = false,
  String sessionId = 'tgdog-1',
  String workBeadId = 'tg-9abc',
}) => SessionProjection(
  workBeadId: workBeadId,
  sessionId: sessionId,
  isTerminal: terminal,
  isMolecule: true,
  moleculeBeads: steps,
  trajCursor: trajCursor,
);

void main() {
  group('the collapse rule (r7 — V1-M5)', () {
    test('one row per step_path — the greatest (round, step_round) wins', () {
      final collapsed = collapseStepCursors([
        _Row(stepPath: 'a', stepState: 'complete'),
        _Row(stepPath: 'a', stepState: 'pending', stepRound: 1),
        _Row(stepPath: 'b', stepState: 'running'),
      ]);
      expect(collapsed.keys, unorderedEquals(['a', 'b']));
      expect(collapsed['a']!.stepRound, 1);
      expect(collapsed['a']!.stepState, 'pending');
    });

    test('ROUND outranks step_round — a rework round 1 rung at step_round 0 '
        'beats round 0 at step_round 9', () {
      // The ladder's own precedence: a new rework round restarts the step
      // ladder, so ordering by step_round alone would serve the PREVIOUS
      // round's last rung forever.
      final collapsed = collapseStepCursors([
        _Row(stepPath: 'a', stepState: 'complete', stepRound: 9),
        _Row(stepPath: 'a', stepState: 'pending', round: 1),
      ]);
      expect(collapsed['a']!.round, 1);
      expect(collapsed['a']!.stepState, 'pending');
    });

    test('input order does not decide — the ladder does', () {
      final ascending = collapseStepCursors([
        _Row(stepPath: 'a', stepState: 'gated'),
        _Row(stepPath: 'a', stepState: 'running', stepRound: 2),
      ]);
      final descending = collapseStepCursors([
        _Row(stepPath: 'a', stepState: 'running', stepRound: 2),
        _Row(stepPath: 'a', stepState: 'gated'),
      ]);
      expect(ascending['a']!.stepRound, descending['a']!.stepRound);
      expect(ascending['a']!.stepState, 'running');
    });

    test('an UNKNOWN state word is a miss, never a default', () {
      // Schema drift must not silently demote a node to `pending`.
      final cursor = trajCursorOf([_Row(stepPath: 'a', stepState: 'quantum')]);
      expect(cursor, isEmpty);
    });
  });

  group('the merge — the three step-axis protections (J8-B2)', () {
    test('THE P2-MISS RULE: a node with no P2 row keeps its BEAD state and is '
        'never omitted (I-10)', () {
      final legacy = {
        'a': const NodeCursor(state: StepState.complete),
        'b': const NodeCursor(state: StepState.running),
      };
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: legacy,
        traj: {'a': const NodeCursor(state: StepState.complete)},
      );
      // Omitting `b` would read as unclaimed at the frontier and at the mount
      // scope, and it would be re-claimed and re-mounted — a double-run.
      expect(merge.cursor.keys, unorderedEquals(['a', 'b']));
      expect(merge.cursor['b']!.state, StepState.running);
      expect(
        merge.nodes
            .where((n) => n.classification == StepNodeClass.p2Miss)
            .map((n) => n.stepPath),
        ['b'],
      );
    });

    test('MONOTONE NO-DEMOTION: a bead-terminal state is never overridden', () {
      for (final bead in [
        StepState.complete,
        StepState.ready,
        StepState.failed,
      ]) {
        final merge = mergeStepCursor(
          sessionId: 'tgdog-1',
          legacy: {'a': NodeCursor(state: bead)},
          traj: {'a': const NodeCursor(state: StepState.running)},
        );
        expect(merge.cursor['a']!.state, bead, reason: 'bead ${bead.name}');
        expect(merge.nodes.single.classification, StepNodeClass.stepLag);
      }
    });

    test('the three terminals are ALTERNATIVES, not a ladder — no swap among '
        'them is served', () {
      // Serving `complete` over a bead `ready` would retire a daemon the
      // ledger says is still up.
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: {'a': const NodeCursor(state: StepState.ready)},
        traj: {'a': const NodeCursor(state: StepState.complete)},
      );
      expect(merge.cursor['a']!.state, StepState.ready);
      expect(merge.nodes.single.classification, StepNodeClass.stepLag);
    });

    test('THE STALE-RUNG GUARD (I-14): a bead re-armed to `pending` is never '
        'promoted back by the previous rung', () {
      // The gate-cleared rearm flips the bead to `pending` and appends a
      // BUMPED-ladder transition. Until that record lands the collapse still
      // serves the old rung's `gated` — serving it would re-park the node the
      // ledger just re-armed, which is the stale-join loop this read exists to
      // retire.
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: {'a': const NodeCursor(state: StepState.pending)},
        traj: {'a': const NodeCursor(state: StepState.gated)},
      );
      expect(merge.cursor['a']!.state, StepState.pending);
      expect(merge.nodes.single.classification, StepNodeClass.stepLag);
    });

    test('THE NEVER-CREATES RULE: a P2 node the ledger has no bead for is '
        'dropped and counted', () {
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: {'a': const NodeCursor(state: StepState.running)},
        traj: {
          'a': const NodeCursor(state: StepState.running),
          'ghost': const NodeCursor(state: StepState.complete),
        },
      );
      expect(merge.cursor.keys, ['a']);
      expect(
        merge.nodes
            .where((n) => n.classification == StepNodeClass.p2Orphan)
            .map((n) => n.stepPath),
        ['ghost'],
      );
    });

    test('a P2 state STRICTLY AHEAD of a non-pending bead is served and '
        'classed a divergence', () {
      // Unreachable in a healthy station (every persist site writes the bead
      // first), which is exactly why it is the class the gates count.
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: {'a': const NodeCursor(state: StepState.running)},
        traj: {'a': const NodeCursor(state: StepState.complete)},
      );
      expect(merge.cursor['a']!.state, StepState.complete);
      expect(merge.nodes.single.classification, StepNodeClass.divergence);
      expect(merge.changed, isTrue);
    });

    test('BREAKER PARITY (B-M2): restartCount and cooldownUntil come off the '
        'BEAD under both feeds', () {
      final cooldown = DateTime.utc(2026, 8, 31, 12);
      final beadNode = NodeCursor(
        state: StepState.failed,
        restartCount: 3,
        cooldownUntil: cooldown,
      );
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: {'a': beadNode},
        // A P2 node carries state and nothing else; if the merge built the
        // served node OUT of P2 rather than splicing onto the bead, the
        // breaker would silently read restartCount 0 and never trip.
        traj: {'a': const NodeCursor(state: StepState.failed)},
      );
      expect(merge.cursor['a']!.restartCount, 3);
      expect(merge.cursor['a']!.cooldownUntil, cooldown);
    });

    test('a null traj is the identity — the same map INSTANCE comes back', () {
      final legacy = {'a': const NodeCursor(state: StepState.running)};
      final merge = mergeStepCursor(
        sessionId: 'tgdog-1',
        legacy: legacy,
        traj: null,
      );
      expect(identical(merge.cursor, legacy), isTrue);
      expect(merge.nodes, isEmpty);
    });
  });

  group('effectiveStepCursor — "config off = today", pinned per site', () {
    test('a null trajCursor returns the SITE cursor, instance and all', () {
      // The r4 OPEN CARRY: the frontier and the cooldown scan iterate the
      // structurally-empty `SessionProjection.cursor`, so the unengaged branch
      // must return THAT — not a bead recompute — or the rollback claim is
      // false at those two sites.
      final session = _session(
        steps: [_stepBead('a', state: StepState.running)],
      );
      const site = <String, NodeCursor>{};
      expect(
        identical(effectiveStepCursor(session, siteCursor: site), site),
        isTrue,
      );
    });

    test(
      'with a trajCursor the BEAD cursor is the floor, not the site read',
      () {
        // Engaged, the frontier stops reading an empty map and starts reading
        // the session's real nodes — the behavior CHANGE the carry names.
        final session = _session(
          steps: [_stepBead('a', state: StepState.running)],
          trajCursor: {'a': const NodeCursor(state: StepState.running)},
        );
        final cursor = effectiveStepCursor(
          session,
          siteCursor: const <String, NodeCursor>{},
        );
        expect(cursor.keys, ['a']);
        expect(cursor['a']!.state, StepState.running);
      },
    );

    test('a supplied beadCursor is used rather than recomputed', () {
      final session = _session(
        steps: [_stepBead('a', state: StepState.running)],
        trajCursor: {'b': const NodeCursor(state: StepState.complete)},
      );
      final cursor = effectiveStepCursor(
        session,
        siteCursor: const <String, NodeCursor>{},
        beadCursor: {'b': const NodeCursor(state: StepState.running)},
      );
      expect(cursor.keys, ['b']);
      expect(cursor['b']!.state, StepState.complete);
    });
  });

  group('StepLagTracker — stepLag\'s arithmetic', () {
    test('never escalates inside the grace, however many passes', () {
      final tracker = StepLagTracker();
      var now = DateTime.utc(2026, 8, 31, 10);
      for (var i = 0; i < 10; i++) {
        expect(tracker.observe('s', 'a', now: now), isFalse);
        now = now.add(const Duration(seconds: 5));
      }
    });

    test('needs TWO passes as well as the grace', () {
      final tracker = StepLagTracker();
      final start = DateTime.utc(2026, 8, 31, 10);
      // The FIRST observation only starts the clock: one pass can never tell a
      // persistent lag from a snapshot taken mid-window, whatever the wall
      // clock says.
      expect(tracker.observe('s', 'a', now: start), isFalse);
      // The second, past the grace, is both conditions at once.
      expect(
        tracker.observe('s', 'a', now: start.add(const Duration(minutes: 2))),
        isTrue,
      );
    });

    test('escalates exactly ONCE', () {
      final tracker = StepLagTracker();
      final late = DateTime.utc(2026, 8, 31, 10, 5);
      tracker
        ..observe('s', 'a', now: DateTime.utc(2026, 8, 31, 10))
        ..observe('s', 'a', now: late);
      expect(tracker.observe('s', 'a', now: late), isFalse);
    });

    test('a node that stops lagging is forgotten and starts fresh', () {
      final tracker = StepLagTracker();
      final start = DateTime.utc(2026, 8, 31, 10);
      tracker
        ..observe('s', 'a', now: start)
        ..retainOnly(const <String>{});
      expect(tracker.openEntries, 0);
      // The re-observation's clock starts now, so a healed-then-relapsed node
      // gets the full grace again rather than inheriting an expired one.
      expect(
        tracker.observe('s', 'a', now: start.add(const Duration(minutes: 5))),
        isFalse,
      );
    });

    test('two sessions at the same path are two independent lags', () {
      final tracker = StepLagTracker();
      final now = DateTime.utc(2026, 8, 31, 10);
      tracker
        ..observe('s1', 'a', now: now)
        ..observe('s2', 'a', now: now);
      expect(tracker.openEntries, 2);
    });
  });

  group('the comparator pass', () {
    late List<(String, Map<String, String>)> flares;

    setUp(() => flares = []);

    DualReadStepObserver observer({
      DualReadMode mode = DualReadMode.observe,
      DateTime Function()? clock,
      DualReadAccounting? accounting,
    }) => DualReadStepObserver(
      mode: mode,
      clock: clock,
      accounting: accounting,
      onFlare: (name, data) => flares.add((name, data)),
    );

    test('OBSERVE serves nothing: the returned map is empty and the counters '
        'still fill', () {
      final o = observer();
      final sessions = {
        'tg-9abc': _session(steps: [_stepBead('a', state: StepState.running)]),
      };
      final served = o.observe(
        sessions,
        _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]),
      );
      expect(served, isEmpty);
      expect(o.accounting.stepHits, 1);
      expect(o.accounting.stepDivergences, 0);
    });

    test(
      'PRIMARY returns the session\'s own P2 cursor, keyed by the map key',
      () {
        final o = observer(mode: DualReadMode.primary);
        final served = o.observe({
          'tg-9abc': _session(
            steps: [_stepBead('a', state: StepState.running)],
          ),
        }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]));
        expect(served.keys, ['tg-9abc']);
        expect(served['tg-9abc']!.cursor['a']!.state, StepState.running);
        expect(o.accounting.stepCursorsServed, 1);
      },
    );

    test('THE IDENTITY RULE (J10-B2/J11-B2): a SIBLING session\'s rows never '
        'reach this session', () {
      // Two sessions on ONE work bead — the rework shape. Serving the
      // sibling's `complete` here would mark a live node done: a promotion the
      // monotone rule cannot catch, which is why identity is the guard.
      final o = observer(mode: DualReadMode.primary);
      final served = o.observe(
        {
          'tg-9abc': _session(
            steps: [_stepBead('a', state: StepState.running)],
          ),
        },
        _StepSnapshot([
          _Row(sessionId: 'tgdog-OTHER', stepPath: 'a', stepState: 'complete'),
        ]),
      );
      // No same-session rows at all ⇒ the P2-miss rule wholesale.
      expect(served, isEmpty);
      expect(o.accounting.stepFallbacks, 1);
      expect(o.accounting.p2Miss, 1);
      expect(flares, isEmpty);
    });

    test('the append-in-flight window at a persist site is stepLag, never a '
        'divergence (J8-B2)', () {
      // Every step persist site writes the BEAD first and appends after, so
      // this pair — bead terminal, P2 still `running` — is the guaranteed
      // steady state of the window.
      for (final bead in [
        StepState.ready,
        StepState.complete,
        StepState.failed,
      ]) {
        final o = observer(mode: DualReadMode.primary);
        final served = o.observe({
          'tg-9abc': _session(steps: [_stepBead('a', state: bead)]),
        }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]));
        expect(o.accounting.stepDivergences, 0, reason: bead.name);
        expect(o.accounting.openStepLag, 1, reason: bead.name);
        // And what is SERVED is the bead's state — the window never demotes.
        expect(served['tg-9abc']!.cursor['a']!.state, StepState.running);
      }
      expect(flares, isEmpty);
    });

    test('retired rework rounds never enter the step comparator', () {
      var now = DateTime.utc(2026, 9, 1, 15, 46);
      final o = observer(mode: DualReadMode.observe, clock: () => now);
      final sessions = <String, SessionProjection>{
        'tg-9abc#r1': _session(
          sessionId: 'retired',
          workBeadId: 'tg-9abc#r1',
          steps: [
            _stepBead('a', state: StepState.complete, sessionId: 'retired'),
          ],
        ),
        'tg-9abc': _session(
          sessionId: 'current',
          workBeadId: 'tg-9abc',
          steps: [
            _stepBead('a', state: StepState.running, sessionId: 'current'),
          ],
        ),
      };
      final snapshot = _StepSnapshot([
        _Row(sessionId: 'retired', stepPath: 'a', stepState: 'running'),
        _Row(sessionId: 'current', stepPath: 'a', stepState: 'running'),
      ]);

      o.observe(sessions, snapshot);
      now = now.add(const Duration(minutes: 5));
      o.observe(sessions, snapshot);

      expect(o.accounting.stepHits, 1);
      expect(o.accounting.openStepLag, 0);
      expect(o.accounting.stepLagEscalations, 0);
      expect(o.accounting.stepDivergences, 0);
      expect(flares, isEmpty);
    });

    test('step lag divergence is unexplained and durable', () {
      var now = DateTime.utc(2026, 8, 31, 10);
      final o = observer(mode: DualReadMode.primary, clock: () => now);
      final sessions = {
        'tg-9abc': _session(steps: [_stepBead('a', state: StepState.complete)]),
      };
      final snapshot = _StepSnapshot([
        _Row(stepPath: 'a', stepState: 'running'),
      ]);

      o.observe(sessions, snapshot);
      expect(flares, isEmpty);
      now = now.add(const Duration(minutes: 5));
      o.observe(sessions, snapshot);
      o.observe(sessions, snapshot);

      expect(o.accounting.stepLagEscalations, 1);
      expect(o.accounting.stepDivergences, 1);
      final divergences = [
        for (final (name, data) in flares)
          if (name == kDualReadDivergenceFlare) data,
      ];
      expect(divergences, hasLength(1));
      expect(divergences.single['axis'], 'step');
      expect(divergences.single['step_path'], 'a');
      expect(divergences.single['field'], 'stepLag');
      expect(divergences.single['cause'], 'unexplained');
      expect(o.accounting.stepUnexplainedDivergences, 1);
      expect(o.accounting.stepOperatorStoreEditDivergences, 0);
      final detail = o.accounting.divergenceDetails.single;
      expect(detail.axis, 'step');
      expect(detail.activeStepPath, 'a');
      expect(detail.field, 'stepLag');
      expect(detail.legacyValue, 'complete');
      expect(detail.foldValue, 'running');
      expect(detail.cause, DualReadDivergenceCause.unexplained);
      expect(o.accounting.maxStepLagMs, greaterThan(0));
    });

    test('a TERMINAL session is skipped — its ladder is not a live lag', () {
      final o = observer(mode: DualReadMode.primary);
      final served = o.observe({
        'tg-9abc': _session(
          terminal: true,
          steps: [_stepBead('a', state: StepState.complete)],
        ),
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]));
      expect(served, isEmpty);
      expect(o.accounting.openStepLag, 0);
      expect(o.accounting.stepHits, 0);
    });

    test('health non-live DISENGAGES the axis for the boot and counts every '
        'session a fallback', () {
      final accounting = DualReadAccounting();
      final o = observer(mode: DualReadMode.primary, accounting: accounting);
      final sessions = {
        'tg-9abc': _session(steps: [_stepBead('a', state: StepState.running)]),
      };
      expect(
        o.observe(
          sessions,
          _StepSnapshot([
            _Row(stepPath: 'a', stepState: 'running'),
          ], health: TrajectorySnapshotHealth.compromised),
        ),
        isEmpty,
      );
      expect(accounting.overlayDisengaged, isTrue);
      expect(accounting.stepFallbacks, 1);
      expect(
        flares,
        isEmpty,
        reason: 'the compromise already flared at the latch',
      );
      // LATCHED FOR THE BOOT: a snapshot that reads `live` again does not
      // re-engage a boot whose mirror already missed an append.
      expect(o.stepAxisEngaged, isFalse);
      expect(
        o.observe(
          sessions,
          _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]),
        ),
        isEmpty,
      );
    });

    test('the SHARED accounting carries both axes into one round summary', () {
      final accounting = DualReadAccounting()..openTerminalLag = 1;
      final o = observer(mode: DualReadMode.primary, accounting: accounting);
      o.observe({
        'tg-9abc': _session(steps: [_stepBead('a', state: StepState.complete)]),
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]));
      final json = accounting.toJson(
        mode: DualReadMode.primary,
        health: TrajectorySnapshotHealth.live,
        snapshotVersion: 11,
        stepAxisEngaged: true,
      );
      expect(json['axis'], 'session+step');
      expect(json['step_axis_engaged'], isTrue);
      expect(json['step_lag_open'], 1);
      expect(json['step_hits'], 1);
      expect(json['step_divergences'], 0);
      // §0.3's gate (b) reads ONE number for every lag class, both axes.
      expect(accounting.openLagEntries, 2);
    });

    /// What a CONSUMER would read: the pass returns P2's own cursor and the
    /// merge happens at the read site, so a decision test has to go through
    /// `effectiveStepCursor` — exactly the seam production uses.
    CircuitCursor consumerReads(
      SessionProjection legacy,
      Map<String, StepCursorOverlay> served,
    ) {
      final overlay = served['tg-9abc'];
      return effectiveStepCursor(
        legacy.copyWith(
          trajCursor: overlay?.cursor,
          trajStepViews: overlay?.views ?? const <String, StepCursorView>{},
        ),
        siteCursor: const <String, NodeCursor>{},
      );
    }

    test('THE I-14 WALK: gate -> rearm -> resume never re-parks the node', () {
      final o = observer(mode: DualReadMode.primary);
      // 1. Parked, and both sides agree.
      var legacy = _session(steps: [_stepBead('a', state: StepState.gated)]);
      var served = o.observe({
        'tg-9abc': legacy,
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'gated')]));
      expect(consumerReads(legacy, served)['a']!.state, StepState.gated);
      expect(o.accounting.stepDivergences, 0);

      // 2. The gate cleared: the BEAD flips to `pending` and the rearm's
      //    transition is still in flight, so the collapse still reads the OLD
      //    rung. Serving it would re-park a node the ledger just re-armed.
      legacy = _session(steps: [_stepBead('a', state: StepState.pending)]);
      served = o.observe({
        'tg-9abc': legacy,
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'gated')]));
      expect(consumerReads(legacy, served)['a']!.state, StepState.pending);
      expect(o.accounting.openStepLag, 1);
      expect(o.accounting.stepDivergences, 0);

      // 3. The BUMPED rung lands and the two agree again — the lag healed on
      //    its own, which is what the window does.
      served = o.observe(
        {'tg-9abc': legacy},
        _StepSnapshot([
          _Row(stepPath: 'a', stepState: 'gated'),
          _Row(stepPath: 'a', stepState: 'pending', stepRound: 1),
        ]),
      );
      expect(consumerReads(legacy, served)['a']!.state, StepState.pending);
      expect(o.accounting.openStepLag, 0);
      expect(o.accounting.stepDivergences, 0);
      expect(flares, isEmpty);
    });

    test('a SUPERVISED RESTART (an incarnation bump) is telemetry, never a '
        'served field', () {
      // P2's `incarnation` is the bumped `restartCount`, and its NodeCursor
      // analogue is the BREAKER's input — which stays bead-read for all of
      // wave 1 (B-M2). The fold may disagree about it without moving a
      // decision.
      final o = observer(mode: DualReadMode.primary);
      final served = o.observe({
        'tg-9abc': _session(
          steps: [_stepBead('a', state: StepState.failed, restartCount: 2)],
        ),
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'failed')]));
      expect(served['tg-9abc']!.cursor['a']!.state, StepState.failed);
      expect(o.accounting.stepDivergences, 0);
      // What the frontier reads for the breaker is the BEAD's count.
      final merged = consumerReads(
        _session(
          steps: [_stepBead('a', state: StepState.failed, restartCount: 2)],
        ),
        served,
      );
      expect(merged['a']!.restartCount, 2);
      expect(merged['a']!.state, StepState.failed);
    });

    test('a session with no id is skipped rather than compared against an '
        'empty key', () {
      final o = observer(mode: DualReadMode.primary);
      final served = o.observe({
        'tg-9abc': const SessionProjection(
          workBeadId: 'tg-9abc',
          isMolecule: true,
        ),
      }, _StepSnapshot([_Row(stepPath: 'a', stepState: 'running')]));
      expect(served, isEmpty);
      expect(o.accounting.stepHits, 0);
    });
  });
}
