// C2 (cut-wiring) — the session dual read's COMPOSITION.
//
// The pure comparator, the overlay, the escalation rule and the two
// reconstructed writers are pinned in grid_engine, grid_runtime and
// grid_trajectory. What only the assembly can prove is that they were actually
// WIRED — and this chunk has three seams a silent miss would darken exactly
// the way C8a's missing `onFlare` did:
//
//   * ONE accounting per boot, shared by the join bridge's comparator and the
//     restart reconciler's — the round summary must not report two different
//     truths for one boot;
//   * the heal's two harness answers (is an append queued for this attempt;
//     is the terminal guard already taken) reaching the bridge, because the
//     trigger and the precondition both live there;
//   * the durable round-summary channel reaching the recorder, because the
//     wave-1 gates read notes and silence there reads as a pass.
import 'dart:io';

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

class _NullResolver implements SessionResolver {
  const _NullResolver();
  @override
  Seed sessionFor({required bead, session}) =>
      throw UnimplementedError('never reached');
}

void _seedStore(String dir, {String? database}) {
  Directory('$dir/.beads').createSync(recursive: true);
  File('$dir/.beads/metadata.json').writeAsStringSync(
    database == null
        ? '{"dolt_mode":"embedded"}'
        : '{"dolt_mode":"embedded","dolt_database":"$database"}',
  );
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('c2-dual-read-');
    _seedStore('${tmp.path}/proj', database: 'proj');
    _seedStore('${tmp.path}/home/.grid', database: 'tgstate');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<StationWorkRuntime> assemble({
    TrajectoryConfig trajectoryConfig = const TrajectoryConfig(),
  }) => assembleStationWork(
    stateStore: GridStateStore.forGridRoot('${tmp.path}/home'),
    substations: [SubstationWorkSpec(name: 'proj', root: '${tmp.path}/proj')],
    resolver: const _NullResolver(),
    dryRun: true,
    trajectoryConfig: trajectoryConfig,
  );

  test('a dry assembly stands up cleanly with the dual read composed, and the '
      'unseeded snapshot is REFUSED — legacy-primary, never a mirror that '
      'never read the fold', () async {
    final work = await assemble();
    expect(
      work.trajectory.sessionHeads.health,
      TrajectorySnapshotHealth.refused,
    );
    // The harness's two heal answers exist and are honest with no queue.
    expect(work.trajectory.hasQueuedAppendFor('A' * 26), isFalse);
  });

  test('the posture defaults to OFF (r13) — wave 1 lands on main as INERT '
      'plumbing, and the soak posture is armed explicitly by the runner', () {
    expect(const TrajectoryConfig().dualRead, DualReadMode.off);
  });

  test('discipline defaults to shadow and has exactly shadow and cut', () {
    expect(TrajectoryDiscipline.values, [
      TrajectoryDiscipline.shadow,
      TrajectoryDiscipline.cut,
    ]);
    expect(const TrajectoryConfig().discipline, TrajectoryDiscipline.shadow);
  });

  test('cut resolves every requested mode and dualRead pair', () {
    for (final requestedMode in TrajectoryConfigMode.values) {
      for (final requestedDualRead in DualReadMode.values) {
        final config = TrajectoryConfig(
          discipline: TrajectoryDiscipline.cut,
          mode: requestedMode,
          dualRead: requestedDualRead,
        );
        expect(
          config.mode,
          TrajectoryConfigMode.required,
          reason:
              'requested mode=${requestedMode.name}, '
              'dualRead=${requestedDualRead.name}',
        );
        expect(
          config.dualRead,
          DualReadMode.primary,
          reason:
              'requested mode=${requestedMode.name}, '
              'dualRead=${requestedDualRead.name}',
        );
      }
    }
  });

  test('cut accepts omitted and matching posture requests', () {
    expect(
      const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
      ).cutPostureRefusal,
      isNull,
    );
    expect(
      const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
        mode: TrajectoryConfigMode.required,
      ).cutPostureRefusal,
      isNull,
    );
    expect(
      const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
        dualRead: DualReadMode.primary,
      ).cutPostureRefusal,
      isNull,
    );
    expect(
      const TrajectoryConfig(
        discipline: TrajectoryDiscipline.cut,
        mode: TrajectoryConfigMode.required,
        dualRead: DualReadMode.primary,
      ).cutPostureRefusal,
      isNull,
    );
  });

  test('cut refusal names requested and resolved values in posture order', () {
    final refusal = const TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      mode: TrajectoryConfigMode.disabled,
      dualRead: DualReadMode.observe,
    ).cutPostureRefusal!;

    expect(refusal.requestedMode, TrajectoryConfigMode.disabled);
    expect(refusal.resolvedMode, TrajectoryConfigMode.required);
    expect(refusal.requestedDualRead, DualReadMode.observe);
    expect(refusal.resolvedDualRead, DualReadMode.primary);
    expect(
      refusal.toString(),
      'CutPostureRefused(requested dualRead=observe, resolved '
      'dualRead=primary; requested mode=disabled, resolved mode=required)',
    );
  });

  test('asDisabled preserves discipline and the cut implication', () {
    const shadow = TrajectoryConfig(dualRead: DualReadMode.observe);
    final disabledShadow = shadow.asDisabled;
    expect(disabledShadow.discipline, TrajectoryDiscipline.shadow);
    expect(disabledShadow.mode, TrajectoryConfigMode.disabled);
    expect(disabledShadow.dualRead, DualReadMode.observe);

    const cut = TrajectoryConfig(
      discipline: TrajectoryDiscipline.cut,
      mode: TrajectoryConfigMode.required,
      dualRead: DualReadMode.primary,
    );
    final disabledCut = cut.asDisabled;
    expect(disabledCut.discipline, TrajectoryDiscipline.cut);
    expect(disabledCut.mode, TrajectoryConfigMode.required);
    expect(disabledCut.dualRead, DualReadMode.primary);
  });

  group('the composition seams (textual — these construction sites are only '
      'reachable from the live assembly)', () {
    late String source;

    setUp(() {
      source = File('lib/src/work/work_assembly.dart').readAsStringSync();
    });

    test('ONE accounting instance is shared by the bridge observer and the '
        'reconciler', () {
      expect(
        RegExp(
          r'DualReadAccounting\(soakWindowEpoch: trajectoryConfig\.soakWindowEpoch\)',
        ).allMatches(source).length,
        1,
      );
      expect(source, contains('accounting: dualReadAccounting'));
      expect(source, contains('dualReadAccounting: dualReadAccounting'));
    });

    test("the heal's trigger and precondition both reach the observer", () {
      expect(
        source,
        contains('appendQueuedFor: trajectory.hasQueuedAppendFor'),
      );
      expect(source, contains('healer: trajectory.requestTerminalReconcile'));
    });

    test('the durable round summary reaches the recorder — silence on this '
        'channel would read as a passing gate', () {
      expect(source, contains('.dualReadRoundSummaryNoted('));
    });

    test('the bridge takes the snapshot AND the headChanges re-join seam — '
        'BOTH gated on the posture (r13)', () {
      expect(
        source,
        contains('headSnapshot: dualReadArmed ? () => trajectory.sessionHeads'),
      );
      expect(source, contains('trajectory.onSessionHeadsChanged('));
      expect(
        source,
        contains('onHeadChanges: !dualReadArmed'),
        reason: 'no acked-envelope handback subscription at `off`',
      );
    });

    test('the reconciler takes the same snapshot getter, under the same '
        'posture gate', () {
      expect(
        RegExp(
          r'headSnapshot: dualReadArmed \? \(\) => trajectory\.sessionHeads',
        ).allMatches(source).length,
        2,
        reason: 'the bridge AND the restart reconciler',
      );
    });

    test('THE POSTURE IS ONE PREDICATE, read from the config (r13) — the '
        'fold-side machinery and the comparator can never drift apart', () {
      expect(
        source,
        contains(
          'final dualReadArmed = trajectoryConfig.dualRead != DualReadMode.off',
        ),
      );
    });

    // ── C3 (cut-wiring) — the flip's own composition seams ───────────────
    test('C3: the POSTURE reaches BOTH readers from ONE config field — a '
        'bridge serving the fold while the reconciler served legacy would '
        'reap and re-mount the same session by turns', () {
      expect(source, contains('mode: trajectoryConfig.dualRead'));
      expect(source, contains('dualReadMode: trajectoryConfig.dualRead'));
    });

    test("C3: the harness's append counters reach the round summary — the "
        'gate reads "zero drops" from the note, and no comparator can '
        'observe a dropped append', () {
      expect(source, contains('appendStats:'));
      expect(source, contains('dropped: status.dropped'));
      expect(source, contains('refusedTestimony: status.refusedTestimony'));
    });
  });

  group('C3 — the flip is a CONFIG line, and the default is OFF', () {
    test(
      'soak window epoch defaults to zero, rejects negative, and survives disable',
      () {
        expect(const TrajectoryConfig().soakWindowEpoch, 0);
        expect(
          () => TrajectoryConfig(soakWindowEpoch: -1),
          throwsA(isA<AssertionError>()),
        );
        const config = TrajectoryConfig(soakWindowEpoch: 41);
        expect(config.asDisabled.soakWindowEpoch, 41);
      },
    );

    test('primary is expressible without disturbing any other field', () {
      const config = TrajectoryConfig(dualRead: DualReadMode.primary);
      expect(config.dualRead, DualReadMode.primary);
      // …and it survives the dry-run force, which only ever touches `mode`.
      // A dry arm claims no epoch and writes nothing, so its mirror never
      // seeds and its snapshot stays `refused` — the posture is carried, and
      // health is what disengages.
      expect(config.asDisabled.dualRead, DualReadMode.primary);
      expect(config.asDisabled.mode, TrajectoryConfigMode.disabled);
    });

    test('the PR default stays OFF — neither the soak posture nor the flip is '
        'ever inherited; both are runner-armed, one line apart', () {
      expect(const TrajectoryConfig().dualRead, DualReadMode.off);
    });
  });

  test('one accounting feeds the round note and trajectory status', () async {
    final source = File('lib/src/work/work_assembly.dart').readAsStringSync();
    expect(RegExp(r'DualReadAccounting\(').allMatches(source), hasLength(1));
    expect(source, contains('accounting: dualReadAccounting'));
    expect(source, contains('dualReadAccounting: dualReadAccounting'));
    expect(source, contains('appendAckP99Ms:'));

    final work = await assemble(
      trajectoryConfig: const TrajectoryConfig(
        dualRead: DualReadMode.observe,
        soakWindowEpoch: 17,
      ),
    );
    final status = work.trajectoryStatus();
    expect(status['soak_window_epoch'], 17);
    expect(status['miss_post_epoch_total'], 0);
    expect(status['p2_miss_total'], 0);
    expect(status['first_epoch_claimed_at'], isNull);
    expect(status['append_ack_p99_ms'], 0);
  });
}
