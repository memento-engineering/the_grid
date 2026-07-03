import 'dart:async';
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/recording_bd_runner.dart';

/// Drives the [RuntimeActuator] with a FAKE bd runner (record commands) — the
/// Track-4 DoD (M3-BUILD-ORDER): a spawn writes a session bead and its `state`
/// transitions on start / activity / exit via bd-only writes; a crash
/// quarantines + sets restart_requested; the fail-closed chokepoint refuses a
/// wrong/absent rig.
void main() {
  late RecordingBdRunner runner;
  late RuntimeActuator actuator;

  /// Builds an actuator over the recording runner with the {tgdog} allow-set
  /// and a fixed clock (so `quarantined_until` is deterministic).
  RuntimeActuator build({int crashThreshold = 3}) {
    runner = RecordingBdRunner(createdId: 'tgdog-sess1');
    final writer = StationBeadWriter(
      bd: BdCliService(runner),
      ownership: BeadOwnershipPredicate({'tgdog'}),
    );
    return RuntimeActuator(
      writer: writer,
      crashThreshold: crashThreshold,
      quarantineBackoff: const Duration(minutes: 5),
      clock: () => DateTime.utc(2026, 6, 15, 12),
    );
  }

  /// The decoded metadata of the Nth `bd update` call.
  Map<String, dynamic> updateMeta(int n) =>
      jsonDecode(runner.metadataOfUpdate(n)!) as Map<String, dynamic>;

  setUp(() {
    actuator = build();
  });

  tearDown(() async {
    await actuator.dispose();
  });

  group('spawn → start → activity → exit (bd-only, --actor grid-controller)', () {
    test(
      'spawn mints a session bead at start_pending through the chokepoint',
      () async {
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
          worktreePath: '/root/.grid/worktrees/tgdog/tgdog-work1',
          branch: 'grid/tgdog-work1',
        );
        expect(id, 'tgdog-sess1');
        expect(actuator.stateOf(id), LifecycleState.startPending);

        // One create + one rig-stamping update carrying state/worktree/branch.
        expect(runner.callsFor('create'), hasLength(1));
        final birth = updateMeta(0);
        expect(birth['rig'], 'tgdog');
        expect(birth['work_bead'], 'tgdog-work1');
        expect(birth['state'], 'start_pending');
        expect(birth['worktree'], '/root/.grid/worktrees/tgdog/tgdog-work1');
        expect(birth['branch'], 'grid/tgdog-work1');
      },
    );

    test('SessionStarted drives the bead to active via bd update', () async {
      final id = await actuator.spawnSession(
        substation: 'tgdog',
        workBeadId: 'tgdog-work1',
      );
      await actuator.handle(
        RuntimeEvent.sessionStarted(name: id, pid: 4242, beadId: 'tgdog-work1'),
      );
      expect(actuator.stateOf(id), LifecycleState.active);
      // The transition was a `bd update --metadata {state: active}` (the 2nd
      // update — birth-stamp is the 1st).
      expect(updateMeta(1), {'state': 'active'});
    });

    test(
      'a clean Exited(0) parks the bead asleep and resets crash_count',
      () async {
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
        );
        await actuator.handle(
          RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
        );
        final decision = await actuator.handle(
          RuntimeEvent.exited(name: id, exitCode: 0),
        );
        expect(decision, isA<SessionParked>());
        expect(actuator.stateOf(id), LifecycleState.asleep);
        // The sleep transition wrote state=asleep + crash_count=0.
        final sleepMeta = updateMeta(2);
        expect(sleepMeta['state'], 'asleep');
        expect(sleepMeta['crash_count'], '0');
      },
    );

    test(
      'EVERY write went through bd with --actor and NEVER `bd show`/SQL',
      () async {
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
        );
        await actuator.handle(
          RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
        );
        await actuator.handle(
          RuntimeEvent.activityChanged(name: id, active: true),
        );
        await actuator.handle(RuntimeEvent.exited(name: id, exitCode: 0));
        await actuator.closeSession(id);

        expect(runner.everyMutationHasActor, isTrue);
        expect(runner.neverCalledShow, isTrue);
        // The only subcommands ever used are bd CLI mutations — never a raw SQL
        // verb (the BdCliService holds no Dolt dependency by construction).
        const allowed = {'create', 'update', 'close', 'delete', 'batch'};
        for (final c in runner.calls) {
          expect(
            allowed.contains(c.first),
            isTrue,
            reason: 'unexpected bd subcommand ${c.first}',
          );
        }
      },
    );

    test('closeSession writes state=closed then `bd close`', () async {
      final id = await actuator.spawnSession(
        substation: 'tgdog',
        workBeadId: 'tgdog-work1',
      );
      await actuator.handle(
        RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
      );
      await actuator.closeSession(id, reason: 'done');
      expect(actuator.stateOf(id), LifecycleState.closed);
      final closes = runner.callsFor('close');
      expect(closes, hasLength(1));
      expect(closes.single, containsAllInOrder(['close', id]));
    });
  });

  group('crash detection → restart, then crash-loop quarantine', () {
    test(
      'a crash under the threshold sets restart_requested (bead NOT closed)',
      () async {
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
        );
        await actuator.handle(
          RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
        );
        final decision = await actuator.handle(
          RuntimeEvent.died(name: id, reason: 'OOM'),
        );

        expect(decision, isA<RestartSession>());
        expect(actuator.crashCountOf(id), 1);
        // No `bd close` — the bead stays open for a fresh restart.
        expect(runner.callsFor('close'), isEmpty);
        // The restart write set restart_requested=true (gc RequestFreshRestart).
        final last = updateMeta(runner.callsFor('update').length - 1);
        expect(last['restart_requested'], 'true');
        expect(last['continuation_reset_pending'], 'true');
        expect(last['crash_count'], '1');
        expect(last['crash_reason'], 'OOM');
      },
    );

    test('a non-zero Exited counts as a crash (not a clean park)', () async {
      final id = await actuator.spawnSession(
        substation: 'tgdog',
        workBeadId: 'tgdog-work1',
      );
      await actuator.handle(
        RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
      );
      final decision = await actuator.handle(
        RuntimeEvent.exited(name: id, exitCode: 137),
      );
      expect(decision, isA<RestartSession>());
      expect(actuator.crashCountOf(id), 1);
    });

    test(
      'repeated crashes trip crash-loop quarantine at the threshold',
      () async {
        actuator = build(crashThreshold: 3);
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
        );
        await actuator.handle(
          RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
        );

        // Crashes 1 + 2 → restart.
        expect(
          await actuator.handle(RuntimeEvent.died(name: id, reason: 'c1')),
          isA<RestartSession>(),
        );
        expect(
          await actuator.handle(RuntimeEvent.died(name: id, reason: 'c2')),
          isA<RestartSession>(),
        );
        // Crash 3 → quarantine.
        final quarantine = await actuator.handle(
          RuntimeEvent.died(name: id, reason: 'c3'),
        );
        expect(quarantine, isA<QuarantineSession>());
        expect((quarantine! as QuarantineSession).cycle, 1);
        expect(actuator.stateOf(id), LifecycleState.quarantined);

        // The quarantine write carries gc's QuarantinePatch shape.
        final qMeta = updateMeta(runner.callsFor('update').length - 1);
        expect(qMeta['state'], 'quarantined');
        expect(qMeta['state_reason'], 'crash-loop');
        expect(qMeta['quarantine_cycle'], '1');
        // quarantined_until = clock + 5m, deterministic under the fixed clock.
        expect(qMeta['quarantined_until'], '2026-06-15T12:05:00.000Z');
      },
    );

    test(
      'a fresh Respawned clears restart_requested and resets crash_count',
      () async {
        final id = await actuator.spawnSession(
          substation: 'tgdog',
          workBeadId: 'tgdog-work1',
        );
        await actuator.handle(
          RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''),
        );
        await actuator.handle(RuntimeEvent.died(name: id, reason: 'c1'));
        // Now a respawn lands.
        await actuator.handle(RuntimeEvent.respawned(name: id, epoch: 2));
        expect(actuator.crashCountOf(id), 0);
        final last = updateMeta(runner.callsFor('update').length - 1);
        expect(last['restart_requested'], '');
        expect(last['crash_count'], '0');
        expect(last['runtime_epoch'], '2');
      },
    );
  });

  group('the chokepoint guards the actuator end-to-end', () {
    test(
      'spawnSession with a non-owned rig is refused (no bead minted)',
      () async {
        await expectLater(
          actuator.spawnSession(substation: 'gascity', workBeadId: 'gascity-1'),
          throwsA(isA<OwnershipRefused>()),
        );
        expect(runner.calls, isEmpty);
      },
    );
  });

  test('bind() drives the lifecycle off a live RuntimeEvent stream', () async {
    final id = await actuator.spawnSession(
      substation: 'tgdog',
      workBeadId: 'tgdog-work1',
    );
    final controller = StreamController<RuntimeEvent>();
    final sub = actuator.bind(controller.stream);
    controller.add(
      RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: 'tgdog-work1'),
    );
    // Let the async handler run.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(actuator.stateOf(id), LifecycleState.active);
    await sub.cancel();
    await controller.close();
  });
}
