/// W6's BINDING acceptance criterion (stage1-wiring §2.5/§6): measure the
/// REAL P2+P6 fold shapes against a real hermetic dolt sql-server — sustained
/// drain rate and p99 writer-loop transaction time — and record the numbers
/// in the test output. The shadow window cannot arm without them.
///
/// What "above observed storm production rate" means here, stated for the
/// record: schema §5 sizes an 8-attempt storm at grid tempo at ~22–28
/// appends/s — that band's top (28/s) is the PRODUCTION rate the drain must
/// beat. The cited MEASURED baseline is stage0-measurements.md M3: **62.3
/// appends/s** (mean 16.05 ms, p99 24.93 ms) with `proj_meta` + P1 under
/// concurrent ledger load — a statement-count proxy that proved nothing about
/// P2–P6's actual row shapes (M3 implication 1), which is exactly the gap
/// this suite closes: every append below runs the REAL registered Stage-1
/// fold set (`kStage1FoldDeltas` — P1 + P2 + P6) inside its transaction.
///
/// The golden invariant rides along (§5 Rebuild): after the storm, the
/// truncate-and-replay folds must equal the incrementally maintained tables.
///
/// Hermetic only (temp dir, ephemeral port) — NEVER a real `.beads`/`.grid`
/// store. Fail-closed on a missing dolt, like every Stage-0 guard.
@Tags(['integration'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:grid_trajectory/grid_trajectory.dart';
import 'package:test/test.dart';

import '../support/baseline_calibration.dart';
import '../support/guard_budget.dart';
import 'support/hermetic_trajectory_server.dart';

/// The cited M3 baseline (stage0-measurements.md M3, Stage-1 run):
/// `proj_meta` + P1 only, 2,080 appends, under concurrent ledger load.
const double kM3BaselineRate = 62.3;

void main() {
  late HermeticTrajectoryServer server;
  late TrajectoryConnection admin;
  late TrajectoryConnection db;

  setUpAll(() async {
    server = await HermeticTrajectoryServer.create();
    admin = await TrajectoryConnection.connect(server.serverEndpoint);
    await createTrajectoryDatabase(admin);
    db = await TrajectoryConnection.connect(server.endpointFor('trajectory'));
    await applyTrajectorySchema(db);
    await createCalibrationTable(db);
  });

  tearDownAll(() async {
    await admin.close();
    await db.close();
    await server.dispose();
  });

  test(
    'W6 acceptance: sustained drain rate above the storm production rate, '
    'p99 writer-loop transaction time recorded — real P1+P2+P6 fold shapes',
    () async {
      final appender = TrajectoryAppender(
        db: db,
        station: 'stage1-w6',
        folds: kStage1FoldDeltas,
        onEvent: (_) {},
      );
      final claim = await appender.claimEpoch(pid: 4242, pgid: 4242);
      expect(claim, isA<EpochClaimed>());

      // FIVE interleaved calibration probes (tg-2zao round 2): one before the
      // storm, three between its quarters, one after — so a scheduler stall
      // lands on the guarded path AND on the calibration, and no single
      // unlucky window can move either band.
      final probes = <BaselineProbe>[];

      // The storm: full attempt lifecycles with a gated step whose rearm
      // BUMPS step_round (the two-ladder chain write — two fold statements in
      // one transaction, the heaviest Stage-1 shape).
      const sessions = 40;
      final base = DateTime.utc(2026, 8, 31, 8);
      final durationsMicros = <int>[];
      var appended = 0;
      final wall = Stopwatch()..start();
      probes.add(await runBaselineProbe(db, label: 'w6-probe0'));
      for (var i = 0; i < sessions; i++) {
        final sessionId = 'tranquility-w6$i';
        final workBead = 'tg-w6$i';
        final attemptId = mintUlid(now: base.add(Duration(seconds: i)));
        final worktree = '/tmp/wt/$workBead';
        StepTransition step(
          String state, {
          int stepRound = 0,
          StepCause? cause,
          Map<String, Object?>? result,
        }) => StepTransition(
          sessionId: sessionId,
          round: 0,
          stepPath: 'work.build',
          stepRound: stepRound,
          incarnation: 0,
          attemptId: attemptId,
          state: StepState.fromWire(state),
          cause: cause,
          result: result,
        );

        final records = <TrajectoryRecord>[
          AttemptSessionStarted(
            sessionId: sessionId,
            grantId: mintUlid(now: base),
            workBeadId: workBead,
            rig: 'operator',
            model: 'molecule',
          ),
          AttemptProcessStarted(
            attemptId: attemptId,
            sessionId: sessionId,
            incarnation: 0,
            pid: 1000 + i,
            pgid: 1000 + i,
            round: 0,
            stepPath: 'work.build',
            stepRound: 0,
          ),
          WorktreeProvisioned(
            attemptId: attemptId,
            sessionId: sessionId,
            worktree: worktree,
            branch: 'grid/$workBead',
            baseSha: 'a' * 40,
            adoptedExisting: false,
          ),
          AttemptLeaseTransition(
            attemptId: attemptId,
            phase: LeasePhase.acquired,
            token: attemptId,
          ),
          step('running'),
          step('gated'),
          // The rearm: bumps step_round AND writes the predecessor chain.
          step('pending', stepRound: 1, cause: StepCause.gateCleared),
          step('running', stepRound: 1),
          step('complete', stepRound: 1, result: {'rc': 0}),
          AttemptLeaseTransition(
            attemptId: attemptId,
            phase: LeasePhase.released,
            token: attemptId,
          ),
          AttemptProcessExited(
            attemptId: attemptId,
            sessionId: sessionId,
            pid: 1000 + i,
            exitCode: 0,
            exitKind: ExitKind.exited,
            inferred: false,
          ),
          AttemptTerminal(
            attemptId: attemptId,
            sessionId: sessionId,
            workBeadId: workBead,
            outcome: TerminalOutcome.succeeded,
          ),
          WorktreeReaped(sessionId: sessionId, worktree: worktree),
        ];
        for (final (ordinal, record) in records.indexed) {
          final txn = Stopwatch()..start();
          final landed = await appender.append(
            record,
            occurredAt: base.add(Duration(minutes: i, seconds: ordinal)),
          );
          txn.stop();
          durationsMicros.add(txn.elapsedMicroseconds);
          expect(
            landed,
            isA<Appended>(),
            reason: 'append $ordinal of $sessionId must land: $landed',
          );
          appended++;
        }
        if (i == 9 || i == 19 || i == 29) {
          probes.add(
            await runBaselineProbe(db, label: 'w6-probe${probes.length}'),
          );
        }
      }
      probes.add(await runBaselineProbe(db, label: 'w6-probe4'));
      wall.stop();
      expect(appended, sessions * 13);

      final calibration = BaselineCalibration(probes);
      final budget = GuardBudget(
        baselineUnitMicros: calibration.unitMicros,
        baselineTailMicros: calibration.tailMicros,
      );
      final host = resolveGuardHost(Platform.environment);

      // ── the numbers the window arms on (record, then assert) ────────────
      durationsMicros.sort();
      double atPercentile(double p) =>
          durationsMicros[(durationsMicros.length * p).ceil() - 1] / 1000.0;
      final appendMicros = durationsMicros.reduce((a, b) => a + b);
      final drainRate = appended / (appendMicros / 1e6);
      final mean = appendMicros / durationsMicros.length / 1000.0;
      // ignore: avoid_print — recording the measurement IS the deliverable.
      print(
        'W6 MEASUREMENT (real P1+P2+P6 fold shapes, hermetic dolt):\n'
        '  appends: $appended in '
        '${(appendMicros / 1e6).toStringAsFixed(2)} s of append time '
        '(${(wall.elapsedMicroseconds / 1e6).toStringAsFixed(2)} s wall, '
        'incl. the interleaved calibration trips)\n'
        '  sustained drain rate: ${drainRate.toStringAsFixed(1)} appends/s\n'
        '  writer-loop transaction time: mean ${mean.toStringAsFixed(2)} ms, '
        'p50 ${atPercentile(0.50).toStringAsFixed(2)} ms, '
        'p90 ${atPercentile(0.90).toStringAsFixed(2)} ms, '
        'p99 ${atPercentile(0.99).toStringAsFixed(2)} ms, '
        'max ${(durationsMicros.last / 1000.0).toStringAsFixed(2)} ms\n'
        '  storm production rate (schema §5 band top): '
        '$kStormProductionRateTop appends/s\n'
        '  cited M3 baseline (stage0-measurements.md M3, proj_meta+P1 only): '
        '$kM3BaselineRate appends/s — this run is '
        '${(drainRate / kM3BaselineRate * 100).toStringAsFixed(0)}% of it '
        'with the full Stage-1 fold set\n'
        '  calibration: $kProbeCount interleaved probes x '
        '${calibration.probes.first.trips} bare round trips\n'
        '  machine-speed unit (median of the probe medians): '
        '${(budget.baselineUnitMicros / 1000).toStringAsFixed(2)} ms '
        '(${budget.baselineOpsPerSecond.toStringAsFixed(1)} ops/s)\n'
        '  machine-tail unit (median of the probe slowest trips): '
        '${(budget.baselineTailMicros / 1000).toStringAsFixed(2)} ms\n'
        '  host: ${host.name} — calibrated floor '
        '${budget.minimumDrainPerSecond.toStringAsFixed(1)} appends/s '
        '(${kFoldMeanCostRatio}x bound at the '
        '${kDrainToleranceFraction}x round-2 tolerance), calibrated p99 '
        'ceiling ${budget.maximumP99Millis.toStringAsFixed(1)} ms '
        '(${kFoldTailCostRatio}x bound at the '
        '${kTailToleranceFactor}x round-2 tolerance)\n'
        '  OBSERVED RATIOS: mean/unit '
        '${(mean * 1000 / budget.baselineUnitMicros).toStringAsFixed(3)}, '
        'p99/tail '
        '${(atPercentile(0.99) * 1000 / budget.baselineTailMicros).toStringAsFixed(3)}',
      );
      expect(
        drainRate,
        greaterThan(budget.minimumDrainPerSecond),
        reason:
            'the Stage-1 fold costs more than '
            '${(kFoldMeanCostRatio / kDrainToleranceFraction).toStringAsFixed(2)}x '
            'a bare round trip on THIS machine (the calibrated '
            '${kFoldMeanCostRatio}x bound at the '
            '${kDrainToleranceFraction}x round-2 tolerance): drain '
            '${drainRate.toStringAsFixed(1)}/s under the calibrated floor '
            '${budget.minimumDrainPerSecond.toStringAsFixed(1)}/s '
            '(machine-speed unit '
            '${(budget.baselineUnitMicros / 1000).toStringAsFixed(2)} ms)',
      );
      expect(
        atPercentile(0.99),
        lessThan(budget.maximumP99Millis),
        reason:
            'p99 writer-loop transaction time exceeds '
            '${(kFoldTailCostRatio * kTailToleranceFactor).toStringAsFixed(2)}x '
            'the machine-tail unit: '
            '${atPercentile(0.99).toStringAsFixed(2)} ms over the calibrated '
            'ceiling ${budget.maximumP99Millis.toStringAsFixed(1)} ms',
      );

      if (absolutePinsApply(host)) {
        expect(
          drainRate,
          greaterThan(kStormProductionRateTop),
          reason:
              'the shadow window cannot arm: drain '
              '${drainRate.toStringAsFixed(1)}/s does not clear the observed '
              'storm production rate ($kStormProductionRateTop/s, schema §5; '
              'M3 measured $kM3BaselineRate/s for the lighter P1-only set)',
        );
        expect(
          atPercentile(0.99),
          lessThan(kP99CeilingMillis),
          reason:
              'p99 writer-loop transaction time regressed an order of '
              'magnitude past M3\'s 24.93 ms observation',
        );
      }

      // ── golden invariant (§5): fold(log) == incrementally maintained ────
      final cursorRows = await db.execute(
        'SELECT session_id, round, step_path, step_round, state, '
        'superseded_by_step_round, last_seq FROM proj_step_cursor',
      );
      expect(cursorRows.rows, hasLength(sessions * 2));
      final identityRows = await db.execute(
        'SELECT attempt_id, session_id, pid, lease_state, worktree_state, '
        'base_sha, last_seq FROM proj_process_identity',
      );
      expect(identityRows.rows, hasLength(sessions));

      final replayDb = await TrajectoryConnection.connect(
        server.endpointFor('trajectory'),
      );
      final cursorFold = await replayStepCursors(replayDb);
      final identityFold = await replayProcessIdentities(replayDb);
      await replayDb.close();

      expect(cursorFold.rows, hasLength(sessions * 2));
      for (final row in cursorRows.rows) {
        final folded =
            cursorFold.rows[(
              sessionId: row['session_id']!,
              round: int.parse(row['round']!),
              stepPath: row['step_path']!,
              stepRound: int.parse(row['step_round']!),
            )];
        expect(folded, isNotNull, reason: 'incremental row missing in replay');
        expect(folded!.state, row['state']);
        expect(
          folded.supersededByStepRound?.toString(),
          row['superseded_by_step_round'],
          reason: 'the chain must fold identically',
        );
        expect(folded.lastSeq.toString(), row['last_seq']);
      }
      expect(identityFold.rows, hasLength(sessions));
      for (final row in identityRows.rows) {
        final folded = identityFold.rows[row['attempt_id']!];
        expect(folded, isNotNull, reason: 'incremental row missing in replay');
        expect(folded!.sessionId, row['session_id']);
        expect(folded.pid?.toString(), row['pid']);
        expect(folded.leaseState, row['lease_state']);
        expect(folded.worktreeState, row['worktree_state']);
        expect(folded.baseSha, row['base_sha']);
        expect(folded.lastSeq.toString(), row['last_seq']);
      }
    },
  );
}
