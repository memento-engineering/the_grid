// Multi-tick SHADOW REPLAY goldens (M2 Track I — ADR-0000 A29). Drives the
// reusable [ShadowReplayHarness] across REAL gc-produced convergence snapshots
// and asserts the shadow's predicted transitions either AGREE with what gc
// actually did each tick or DIVERGE on a single perturbed tick.
//
// The snapshots are built from the pinned fixtures (same gc-1/gc-2/gc-3 ids,
// real `convergence.*` metadata): the codec-fidelity suite already proved the
// codec decodes them; this suite proves the shadow MECHANISM replays them.
//
// DivergenceReport.toString() is stable → golden-comparable.

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_reconciler/grid_reconciler.dart';
import 'package:test/test.dart';

import '../fixtures/convergence_fixtures.dart';
import 'support/runtime_fakes.dart';
import 'support/shadow_replay_harness.dart';

void main() {
  // ---------------------------------------------------------------------------
  // GOLDEN (i) — AGREE. A gate-PASS replay loop (real fixture 04 metadata): the
  // closing wisp gc-2 carries a persisted gate_outcome=pass for itself, so the
  // reducer predicts `approved` (controller terminal). gc is then observed
  // writing 04's terminal metadata (terminal_reason=approved,
  // terminal_actor=controller) — a handler approve. They AGREE.
  // ---------------------------------------------------------------------------
  group('AGREE — gate-pass replay (fixture 04, gc-1/gc-2)', () {
    test('the_grid predicts approved; gc approves → diverged:false', () async {
      final fixture04 = loadScenario('04-gate-pass-terminated.json');
      final terminalMeta = fixture04.rootMetadata;

      // Tick 0 — the PRE-transition state: same gate-pass replay markers, but
      // the loop is still `active` with gc-2 as the open active wisp and no
      // terminal fields yet. Derived from 04's real metadata (the gate markers
      // are byte-for-byte 04's).
      final activeMeta = _preTerminalActive(terminalMeta);
      final rootActive = convergenceBead('gc-1', metadata: activeMeta);
      final wispOpen = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
      );
      final tick0 = snapWith(
        roots: [rootActive],
        children: {
          'gc-1': [wispOpen],
        },
      );

      // Tick 1 — gc's actual terminal METADATA write (04's real metadata) +
      // gc-2 closed. The root's terminal metadata write is observable as a
      // `BeadUpdated` BEFORE gc closes the root bead itself (a later, separate
      // diff): the shadow's gc-command detection keys off that metadata
      // BeadUpdated, so the root status stays unchanged here (the close is not
      // needed for, and would mask — as a BeadClosed — the detection).
      final rootTerminated = convergenceBead(
        'gc-1',
        metadata: Map<String, dynamic>.from(terminalMeta),
      );
      final wispClosed = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
        closedAt: fakeClock,
      );
      final tick1 = snapWith(
        roots: [rootTerminated],
        children: {
          'gc-1': [wispClosed],
        },
      );

      final harness = ShadowReplayHarness.over([tick0, tick1]);
      final reports = await harness.run();

      // Exactly one tick (tick 0 → tick 1), one report.
      expect(harness.ticks, hasLength(1));
      expect(reports, hasLength(1));
      final report = reports.single;

      // the_grid predicted `approved` (the gate-pass replay terminal).
      expect(report.predictedWire, 'approved');
      // gc was observed performing a HANDLER approve (actor=controller).
      expect(report.observed.command, GcCommandKind.handlerApproved);
      expect(report.observed.actor, 'controller');
      expect(report.convergenceBeadId, 'gc-1');
      // AGREE.
      expect(report.diverged, isFalse, reason: 'both approved — they agree');

      // Golden: the stable toString.
      expect(
        report.toString(),
        'DivergenceReport(gc-1, predicted=approved, '
        'observed=handlerApproved, diverged=false)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GOLDEN (ii) — DIVERGE. The SAME gate-pass replay loop, but ONE tick is
  // perturbed: gc's terminal write is flipped from approved→no_convergence
  // (a different actor/reason, exactly as shadow_safety_test.dart:35-43 flips a
  // terminal_reason/actor). the_grid still predicts `approved` from the
  // gate-pass replay, so that tick DIVERGES; with only one transition tick
  // there is nothing else to stay quiet, so we ALSO drive a 3-tick variant to
  // prove the non-perturbed ticks stay quiet.
  // ---------------------------------------------------------------------------
  group('DIVERGE — one perturbed tick (fixture 04, gc-1/gc-2)', () {
    test('gc flips approved→no_convergence; predicted approved → '
        'diverged:true', () async {
      final fixture04 = loadScenario('04-gate-pass-terminated.json');
      final activeMeta = _preTerminalActive(fixture04.rootMetadata);

      final rootActive = convergenceBead('gc-1', metadata: activeMeta);
      final wispOpen = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
      );
      final tick0 = snapWith(
        roots: [rootActive],
        children: {
          'gc-1': [wispOpen],
        },
      );

      // PERTURB: gc terminates as no_convergence, NOT approved. (Root status
      // unchanged — the terminal METADATA write is the observable BeadUpdated.)
      final perturbedMeta = Map<String, dynamic>.from(
        fixture04.rootMetadata,
      )..[ConvergenceFields.terminalReason] = TerminalReason.noConvergence.wire;
      final rootTerminated = convergenceBead('gc-1', metadata: perturbedMeta);
      final wispClosed = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
        closedAt: fakeClock,
      );
      final tick1 = snapWith(
        roots: [rootTerminated],
        children: {
          'gc-1': [wispClosed],
        },
      );

      final harness = ShadowReplayHarness.over([tick0, tick1]);
      final reports = await harness.run();

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report.predictedWire, 'approved');
      expect(report.observed.command, GcCommandKind.handlerNoConvergence);
      // DIVERGE — the_grid would have approved; gc declared no_convergence.
      expect(report.diverged, isTrue);
      expect(harness.ticks.single.diverged, isTrue);

      // Golden.
      expect(
        report.toString(),
        'DivergenceReport(gc-1, predicted=approved, '
        'observed=handlerNoConvergence, diverged=true)',
      );
    });

    test('a quiet tick (no convergence command) before the perturbation stays '
        'quiet; only the perturbed tick diverges', () async {
      final fixture04 = loadScenario('04-gate-pass-terminated.json');
      final activeMeta = _preTerminalActive(fixture04.rootMetadata);

      // Tick 0 → Tick 1: a NON-command metadata change on the root (a city_path
      // touch) — observedGcCommand returns null, so the tick is quiet. The
      // active wisp stays open.
      final rootA = convergenceBead('gc-1', metadata: activeMeta);
      final rootB = convergenceBead(
        'gc-1',
        metadata: Map<String, dynamic>.from(activeMeta)
          ..[ConvergenceFields.cityPath] = '/tmp/touched',
      );
      // Tick 2: the perturbed terminal (no_convergence) + gc-2 closes.
      final perturbedMeta = Map<String, dynamic>.from(fixture04.rootMetadata)
        ..[ConvergenceFields.cityPath] = '/tmp/touched'
        ..[ConvergenceFields.terminalReason] =
            TerminalReason.noConvergence.wire;
      final rootTerminated = convergenceBead('gc-1', metadata: perturbedMeta);

      final wispOpen = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
      );
      final wispClosed = wispBead(
        'gc-2',
        key: idempotencyKey('gc-1', 1),
        status: BeadStatus.closed,
        createdAt: fakeClock.subtract(const Duration(minutes: 5)),
        closedAt: fakeClock,
      );

      final tick0 = snapWith(
        roots: [rootA],
        children: {
          'gc-1': [wispOpen],
        },
      );
      final tick1 = snapWith(
        roots: [rootB],
        children: {
          'gc-1': [wispOpen],
        },
      );
      final tick2 = snapWith(
        roots: [rootTerminated],
        children: {
          'gc-1': [wispClosed],
        },
      );

      final harness = ShadowReplayHarness.over([tick0, tick1, tick2]);
      await harness.run();

      expect(harness.ticks, hasLength(2));
      // Tick 0→1: a non-command metadata touch → quiet (no report).
      expect(
        harness.ticks[0].quiet,
        isTrue,
        reason: 'a city_path touch is not a convergence command',
      );
      // Tick 1→2: the perturbed terminal diverges.
      expect(harness.ticks[1].diverged, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // FIXTURE-FAITHFUL multi-tick replay — the literal 01→02→03 trio (the SAME
  // convergence advancing, shared gc-1/gc-2/gc-3 ids, all-real metadata). This
  // is a MANUAL loop: gc-2 closes, the_grid (manual gate) would hold in
  // waiting_manual, then gc's operator (operator:nico) force-approves it at 03.
  // That operator approve is a REAL divergence the fixtures expose — the_grid
  // predicted waiting_manual; gc operator-approved. We pin it as a golden so a
  // future capture that changed this behavior would fail loudly.
  // ---------------------------------------------------------------------------
  group('fixture-faithful 01→02→03 manual trio (gc-1/gc-2/gc-3)', () {
    test('the_grid would hold (waiting_manual); gc operator-approves → the '
        'operator approve tick diverges', () async {
      final f01 = loadScenario('01-active-manual.json');
      final f02 = loadScenario('02-waiting-manual.json');
      final f03 = loadScenario('03-terminated-approved.json');

      // Tick 0 (01): active loop, gc-2 the OPEN active wisp + its gc-3 step.
      final tick0 = _trioSnapshot(
        rootMeta: f01.rootMetadata,
        rootStatus: BeadStatus.inProgress,
        wispClosed: false,
      );
      // Tick 1 (02): gc-2 has closed; loop is waiting_manual.
      final tick1 = _trioSnapshot(
        rootMeta: f02.rootMetadata,
        rootStatus: BeadStatus.inProgress,
        wispClosed: true,
      );
      // Tick 2 (03): operator:nico approved → terminated. gc's terminal
      // METADATA write is the observable BeadUpdated (the root-close is a
      // later, separate diff and would mask detection as a BeadClosed), so the
      // root status stays unchanged here — only the metadata advances.
      final tick2 = _trioSnapshot(
        rootMeta: f03.rootMetadata,
        rootStatus: BeadStatus.inProgress,
        wispClosed: true,
      );

      final harness = ShadowReplayHarness.over([tick0, tick1, tick2]);
      final reports = await harness.run();

      // Two ticks. Tick 0→1 (the gc-2 closure) maps to a wisp-closed prediction
      // but produces NO report yet (the active→waiting_manual flip is not a
      // detected gc command). Tick 1→2 (the operator approve) is the detected
      // command and the divergence.
      expect(harness.ticks, hasLength(2));
      expect(
        harness.ticks[0].quiet,
        isTrue,
        reason: 'active→waiting_manual is not a detected gc command',
      );

      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report.convergenceBeadId, 'gc-1');
      // the_grid (manual mode) predicted a hold, NOT approved.
      expect(report.predictedWire, 'waiting_manual');
      // gc's actor is operator:nico → operatorApprove.
      expect(report.observed.command, GcCommandKind.operatorApprove);
      expect(report.observed.actor, 'operator:nico');
      // DIVERGE: the_grid would have held; gc operator-approved.
      expect(report.diverged, isTrue);

      // Golden.
      expect(
        report.toString(),
        'DivergenceReport(gc-1, predicted=waiting_manual, '
        'observed=operatorApprove, diverged=true)',
      );
    });
  });
}

/// Derives the PRE-transition `active` metadata from a captured terminal
/// metadata map: keep every gate-replay marker byte-for-byte (gate_outcome,
/// gate_outcome_wisp, gate_exit_code, …) so the reducer's replay branch fires,
/// but set the loop back to `active` with gc-2 as the active wisp and strip the
/// terminal fields gc writes only at termination. This is the honest state gc
/// was in immediately before it terminated the loop.
Map<String, dynamic> _preTerminalActive(Map<String, dynamic> terminal) {
  final m = Map<String, dynamic>.from(terminal);
  m[ConvergenceFields.state] = ConvergenceState.active.wire;
  m[ConvergenceFields.activeWisp] = 'gc-2';
  // Pre-termination, the dedup marker has NOT yet advanced to gc-2 (gc writes
  // last_processed_wisp as it processes the closing wisp — exactly like
  // fixture 01's active state, which carries no last_processed_wisp). Leaving
  // it pointing at gc-2 would (correctly) make the reducer skip the close as a
  // duplicate; clear it so this models the state in which gc-2 is the live,
  // unprocessed active wisp.
  m[ConvergenceFields.lastProcessedWisp] = '';
  // The terminal-only fields are not present pre-termination.
  m.remove(ConvergenceFields.terminalReason);
  m.remove(ConvergenceFields.terminalActor);
  m.remove('close_reason');
  return m;
}

/// Builds one tick of the 01→02→03 trio: the root with [rootMeta], plus the
/// gc-2 wisp (open or closed) and its gc-3 step, wired with parent-child edges.
GraphSnapshot _trioSnapshot({
  required Map<String, dynamic> rootMeta,
  required BeadStatus rootStatus,
  required bool wispClosed,
}) {
  final root = convergenceBead(
    'gc-1',
    status: rootStatus,
    metadata: Map<String, dynamic>.from(rootMeta),
  );
  final wisp = wispBead(
    'gc-2',
    key: idempotencyKey('gc-1', 1),
    status: wispClosed ? BeadStatus.closed : BeadStatus.open,
    createdAt: fakeClock.subtract(const Duration(minutes: 5)),
    closedAt: wispClosed ? fakeClock : null,
  );
  final step = Bead(
    id: 'gc-3',
    title: 'Work',
    issueType: IssueType.step,
    status: wispClosed ? BeadStatus.closed : BeadStatus.open,
    metadata: const {'gc.step_ref': 'test-formula.work'},
  );
  return snap(
    [root, wisp, step],
    deps: [parentChild('gc-2', 'gc-1'), parentChild('gc-3', 'gc-2')],
  );
}
