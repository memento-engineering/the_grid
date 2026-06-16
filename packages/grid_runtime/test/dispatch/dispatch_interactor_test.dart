import 'dart:io';

import 'package:grid_controller/grid_controller.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lifecycle/support/recording_bd_runner.dart';
import 'support/dispatch_fakes.dart';

/// Offline proofs for the [DispatchInteractor] (M3 Track 5; ADR-0006 Decision 1;
/// ADR-0000 A32) — Fakes, not mocks, no live state, no real `claude`, no real
/// `git`, no `bd` writes to live `tg`. The DoD:
///
///  1. an OWNED-rig ready bead spawns EXACTLY ONE agent in a worktree with a
///     session bead (fake provider + fake git + fake bd);
///  2. a NON-owned ready bead is observed read-only and NEVER dispatched;
///  3. a RE-FIRED ready event does NOT double-spawn (single-flight per bead).
void main() {
  late Directory tmpRoot;
  late FakeReadyWorkSource source;
  late FakeRuntimeProvider provider;
  late FakeGitRunner gitRunner;
  late RecordingBdRunner bdRunner;
  late GridGitService git;
  late RuntimeActuator actuator;
  late RootCheckout root;
  late DispatchInteractor dispatcher;

  /// A RootCheckout pointed at a fresh temp dir (so provisionWorktree creates
  /// the rig dir under temp and the stale-ancestor guard reaches the fs root
  /// safely — no real lenny / lenny-tgdog ever touched).
  RootCheckout rootAt(String path) => RootCheckout(
    path: path,
    defaultBranch: 'main',
    rig: 'tgdog',
  );

  /// The config builder Track 7 supplies; here a minimal `claude -p` invocation
  /// (the token rides env, never argv — asserted in the env-allowlist tests).
  RuntimeConfig buildConfig(DispatchRequest request) => RuntimeConfig(
    workDir: request.worktree.path,
    command: 'claude',
    args: ['-p', request.bead.title],
  );

  void wire({bool dryRun = false, int maxInFlight = 8}) {
    bdRunner = RecordingBdRunner(createdId: 'tgdog-sess1');
    final writer = GridBeadWriter(
      bd: BdCliService(bdRunner),
      ownership: BeadOwnershipPredicate({'tgdog'}),
    );
    actuator = RuntimeActuator(writer: writer);
    // The actuator ingests the provider's RuntimeEvent stream (Track 4 bind).
    actuator.bind(provider.events);
    git = GridGitService(runner: gitRunner, prOpener: FakePrOpener());
    dispatcher = DispatchInteractor(
      source: source,
      ownership: BeadOwnershipPredicate({'tgdog'}),
      git: git,
      root: root,
      provider: provider,
      actuator: actuator,
      configBuilder: buildConfig,
      maxInFlight: maxInFlight,
      dryRun: dryRun,
    );
  }

  setUp(() {
    tmpRoot = Directory.systemTemp.createTempSync('grid_dispatch_');
    source = FakeReadyWorkSource();
    provider = FakeRuntimeProvider();
    gitRunner = FakeGitRunner();
    root = rootAt(tmpRoot.path);
  });

  tearDown(() async {
    await dispatcher.dispose();
    await actuator.dispose();
    await source.close();
    await provider.close();
    if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
  });

  group('DoD 1 — an owned ready bead spawns exactly one agent + session bead',
      () {
    test(
      'provision worktree → start agent → mint session bead (one each)',
      () async {
        wire();
        source.addReady(Bead(id: 'tgdog-work1', title: 'do the thing'));
        await dispatcher.start();

        // Exactly ONE dispatch record for the owned bead.
        expect(dispatcher.inFlight, 1);
        final record = dispatcher.dispatched['tgdog-work1']!;
        expect(record.sessionBeadId, 'tgdog-sess1');
        expect(
          record.worktree.path,
          p.join(tmpRoot.path, '.grid', 'worktrees', 'tgdog', 'tgdog-work1'),
        );
        expect(record.worktree.branch, 'grid/tgdog-work1');

        // Exactly ONE agent start, into the worktree, named by the session bead.
        expect(provider.starts, hasLength(1));
        expect(provider.starts.single.name, 'tgdog-sess1');
        expect(provider.starts.single.config.workDir, record.worktree.path);
        expect(provider.starts.single.config.command, 'claude');

        // The session bead was minted through the chokepoint (bd create + a
        // rig-stamping update carrying state/worktree/branch).
        expect(bdRunner.callsFor('create'), hasLength(1));
        expect(bdRunner.everyMutationHasActor, isTrue);
        expect(bdRunner.neverCalledShow, isTrue);
        // git worktree add ran once (no real git — the fake recorded it).
        final worktreeAdds = gitRunner.calls
            .where((c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'add')
            .toList();
        expect(worktreeAdds, hasLength(1));
      },
    );

    test(
      'a SessionStarted from the provider drives the session bead to active',
      () async {
        wire();
        source.addReady(Bead(id: 'tgdog-work1', title: 't'));
        await dispatcher.start();
        final id = dispatcher.dispatched['tgdog-work1']!.sessionBeadId;

        provider.emit(
          RuntimeEvent.sessionStarted(name: id, pid: 999, beadId: 'tgdog-work1'),
        );
        // Let the bound actuator's async handler run.
        await pumpEventQueue();
        expect(actuator.stateOf(id), LifecycleState.active);
      },
    );

    test('a bead that enters the ready set LATER is dispatched on the event', () async {
      wire();
      await dispatcher.start(); // nothing ready yet.
      expect(dispatcher.inFlight, 0);

      // Now the bead becomes ready and a readySetChanged fires.
      source.addReady(Bead(id: 'tgdog-late', title: 'late'));
      source.fireReady({'tgdog-late'});
      await pumpEventQueue();

      expect(dispatcher.inFlight, 1);
      expect(provider.startCountFor('tgdog-sess1'), 1);
    });
  });

  group('DoD 2 — a non-owned ready bead is observed read-only, never dispatched',
      () {
    test(
      'a gascity-prefixed ready bead is NEVER spawned (mirrors OwnsRigs)',
      () async {
        wire();
        source.addReady(Bead(id: 'gascity-xyz', title: 'gc work'));
        await dispatcher.start();

        // Nothing dispatched — observed read-only.
        expect(dispatcher.inFlight, 0);
        expect(dispatcher.observedNonOwned, contains('gascity-xyz'));
        // NO agent started, NO worktree provisioned, NO bead minted.
        expect(provider.starts, isEmpty);
        expect(bdRunner.calls, isEmpty);
        expect(
          gitRunner.calls.where(
            (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'add',
          ),
          isEmpty,
        );
      },
    );

    test('a non-owned bead via readySetChanged is also never dispatched', () async {
      wire();
      source.addReady(Bead(id: 'gascity-evt', title: 'gc'));
      await dispatcher.start();
      source.fireReady({'gascity-evt'});
      await pumpEventQueue();

      expect(dispatcher.inFlight, 0);
      expect(provider.starts, isEmpty);
      expect(bdRunner.calls, isEmpty);
    });

    test('a mixed ready set dispatches ONLY the owned bead', () async {
      wire();
      source
        ..addReady(Bead(id: 'tgdog-mine', title: 'mine'))
        ..addReady(Bead(id: 'gascity-theirs', title: 'theirs'));
      await dispatcher.start();

      expect(dispatcher.inFlight, 1);
      expect(dispatcher.dispatched.keys, equals({'tgdog-mine'}));
      expect(dispatcher.observedNonOwned, contains('gascity-theirs'));
    });
  });

  group('DoD 3 — a re-fired ready event does NOT double-spawn (single-flight)',
      () {
    test('the same bead fired twice spawns exactly once', () async {
      wire();
      source.addReady(Bead(id: 'tgdog-work1', title: 't'));
      await dispatcher.start(); // dispatch #1 (the start-time reconcile).

      // The ready event re-fires for the SAME bead (a re-query churn).
      source.fireReady({'tgdog-work1'});
      source.fireReady({'tgdog-work1'});
      await pumpEventQueue();

      // Still exactly one dispatch / one agent / one session bead.
      expect(dispatcher.inFlight, 1);
      expect(provider.startCountFor('tgdog-sess1'), 1);
      expect(provider.starts, hasLength(1));
      expect(bdRunner.callsFor('create'), hasLength(1));
    });

    test(
      'a burst of simultaneous fires (racing the first spawn) spawns once',
      () async {
        wire();
        source.addReady(Bead(id: 'tgdog-burst', title: 't'));
        // Three near-simultaneous fires + the start reconcile — all for one id.
        await dispatcher.start();
        source
          ..fireReady({'tgdog-burst'})
          ..fireReady({'tgdog-burst'})
          ..fireReady({'tgdog-burst'});
        await pumpEventQueue();

        expect(provider.startCountFor('tgdog-sess1'), 1);
        expect(dispatcher.inFlight, 1);
      },
    );
  });

  group('supervision — crash/exit drive restart / quarantine / reap', () {
    test('a clean exit closes the session bead and reaps the worktree', () async {
      wire();
      source.addReady(Bead(id: 'tgdog-work1', title: 't'));
      await dispatcher.start();
      final id = dispatcher.dispatched['tgdog-work1']!.sessionBeadId;

      provider.emit(RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''));
      await pumpEventQueue();
      // A clean exit → SessionParked → close + reap (gates clean in the fake).
      provider.emit(RuntimeEvent.exited(name: id, exitCode: 0));
      await pumpEventQueue();

      // The session bead was closed through the chokepoint.
      expect(bdRunner.callsFor('close'), hasLength(1));
      // The worktree was reaped (git worktree remove ran) and the record dropped.
      expect(
        gitRunner.calls.any(
          (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'remove',
        ),
        isTrue,
      );
      expect(dispatcher.inFlight, 0);
    });

    test(
      'an unpushed worktree is REFUSED by the reaper (fail-closed) and kept',
      () async {
        wire();
        gitRunner.unpushed = true; // the unpushed gate trips.
        source.addReady(Bead(id: 'tgdog-work1', title: 't'));
        await dispatcher.start();
        final id = dispatcher.dispatched['tgdog-work1']!.sessionBeadId;

        provider.emit(RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''));
        await pumpEventQueue();
        provider.emit(RuntimeEvent.exited(name: id, exitCode: 0));
        await pumpEventQueue();

        // The bead is still closed, but the worktree was NOT removed.
        expect(bdRunner.callsFor('close'), hasLength(1));
        expect(
          gitRunner.calls.any(
            (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'remove',
          ),
          isFalse,
        );
      },
    );

    test('a crash under the threshold re-spawns the same bead', () async {
      wire();
      source.addReady(Bead(id: 'tgdog-work1', title: 't'));
      await dispatcher.start();
      final id = dispatcher.dispatched['tgdog-work1']!.sessionBeadId;

      provider.emit(RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''));
      await pumpEventQueue();
      // A crash → RestartSession → the dispatcher stops then re-starts.
      provider.emit(RuntimeEvent.died(name: id, reason: 'OOM'));
      await pumpEventQueue();

      // The session bead was NOT closed (restart leaves it open).
      expect(bdRunner.callsFor('close'), isEmpty);
      // The provider saw a stop (clear the stale process) then a second start.
      expect(provider.stops, contains(id));
      expect(provider.startCountFor(id), 2);
      // Still in flight (parked for restart, not reaped).
      expect(dispatcher.inFlight, 1);
    });

    test('a crash-loop quarantine parks the session — no respawn, no reap', () async {
      wire();
      source.addReady(Bead(id: 'tgdog-work1', title: 't'));
      await dispatcher.start();
      final id = dispatcher.dispatched['tgdog-work1']!.sessionBeadId;

      provider.emit(RuntimeEvent.sessionStarted(name: id, pid: 1, beadId: ''));
      await pumpEventQueue();
      // Three crashes (default threshold) → quarantine on the third.
      provider.emit(RuntimeEvent.died(name: id, reason: 'c1'));
      await pumpEventQueue();
      provider.emit(RuntimeEvent.died(name: id, reason: 'c2'));
      await pumpEventQueue();
      provider.emit(RuntimeEvent.died(name: id, reason: 'c3'));
      await pumpEventQueue();

      expect(actuator.stateOf(id), LifecycleState.quarantined);
      // Parked: no close, no reap.
      expect(bdRunner.callsFor('close'), isEmpty);
      expect(
        gitRunner.calls.any(
          (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'remove',
        ),
        isFalse,
      );
    });
  });

  group('--dry-run is observe-only (the safe default arm)', () {
    test('a dry run dispatches NOTHING: no worktree, no spawn, no bd write', () async {
      wire(dryRun: true);
      source.addReady(Bead(id: 'tgdog-work1', title: 't'));
      await dispatcher.start();

      expect(dispatcher.inFlight, 0);
      expect(provider.starts, isEmpty);
      expect(bdRunner.calls, isEmpty);
      expect(
        gitRunner.calls.where(
          (c) => c.length >= 2 && c[0] == 'worktree' && c[1] == 'add',
        ),
        isEmpty,
      );
    });
  });

  group('the max-in-flight cap (M3 backpressure; full pool deferred to M4)', () {
    test('a second owned bead beyond the cap is deferred, not spawned', () async {
      wire(maxInFlight: 1);
      // Two ids minting distinct session ids.
      bdRunner.nextCreatedId = 'tgdog-sessA';
      source
        ..addReady(Bead(id: 'tgdog-a', title: 'a'))
        ..addReady(Bead(id: 'tgdog-b', title: 'b'));
      await dispatcher.start();

      // Only one dispatched (the cap); the other is deferred (not observed as
      // non-owned — it IS owned, just over the cap).
      expect(dispatcher.inFlight, 1);
      expect(provider.starts, hasLength(1));
    });
  });

  test('a non-readySetChanged event is ignored (the second-consumer filter)', () async {
    wire();
    source.addReady(Bead(id: 'tgdog-work1', title: 't'));
    await dispatcher.start();
    final before = provider.starts.length;
    // A bead-created event must NOT trigger a dispatch (only readySetChanged).
    source.fire(GraphEvent.beadCreated(Bead(id: 'tgdog-other')));
    await pumpEventQueue();
    expect(provider.starts.length, before);
  });
}
