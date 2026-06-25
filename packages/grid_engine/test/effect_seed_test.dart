// Track C — the EFFECT SEED carrier: a tree node whose Branch lifecycle IS the
// work-process lifecycle (mount = spawn, unmount = kill, completion = advance
// the session cursor).
//
// Offline only — FAKES, no live tg/gc/claude/network/git. The acceptance grid
// (M4-P0-BUILD-ORDER Track C) is exercised end to end by mounting a concrete
// _SpawnEffect under InheritedSeed<EffectContext> via a TreeOwner and driving a
// controllable FakeRuntimeProvider event stream. The two races — a completion
// event AFTER dispose, and a dispose DURING the async createSession — are the
// load-bearing cases Track D/E-F build on.
//
// The fakes (FakeRuntimeProvider + RecordingBdRunner + the context builder) now
// live in test/support/engine_fakes.dart, shared with the kernel reactive-loop
// test and the land test (Track E/F).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// ---------------------------------------------------------------------------
// A concrete effect under test: the IMPLEMENT/VERIFY/LAND shape, configurable
// advanceTo so one fake covers "advance the cursor" and "close the session".
// ---------------------------------------------------------------------------

class _SpawnEffect extends EffectSeed {
  const _SpawnEffect({
    required super.bead,
    required super.phase,
    required this.target,
    super.session,
    super.key,
  });

  /// The cursor to advance to on clean completion; null ⇒ close the session.
  final WorkPhase? target;

  @override
  RuntimeConfig buildConfig(EffectContext ctx) => const RuntimeConfig(
    workDir: '/tmp/x',
    command: 'true',
    lifecycle: Lifecycle.oneTurn,
    env: {'EXISTING': 'kept'},
  );

  @override
  WorkPhase? get advanceTo => target;
}

// ---------------------------------------------------------------------------
// Harness: mount the effect under InheritedSeed<EffectContext> via a TreeOwner.
// ---------------------------------------------------------------------------

/// Mounts [effect] under `InheritedSeed<EffectContext>(value: ctx)` and returns
/// the owner so the test can unmount (dispose the effect) on demand.
TreeOwner _mount(EffectContext ctx, EffectSeed effect) {
  final owner = TreeOwner();
  owner.mountRoot(InheritedSeed<EffectContext>(value: ctx, child: effect));
  return owner;
}

void main() {
  group('EffectSeed — mount = spawn', () {
    test(
      'session==null ⇒ createSession ONCE then start with the minted token + '
      'bead id in config.env',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final owner = _mount(
          f.ctx,
          _SpawnEffect(
            bead: bead('tg-1'),
            phase: WorkPhase.implement,
            target: WorkPhase.verify,
            key: const ValueKey('tg-1.agent'),
          ),
        );
        addTearDown(owner.dispose);
        addTearDown(f.provider.close);

        // initState fires _run() synchronously up to the first await; let the
        // create + start microtasks drain.
        await pumpEventQueue();

        // createSession was called exactly once, into the owned state rig, for
        // this work bead.
        final creates = f.runner.callsFor('create');
        expect(creates, hasLength(1));
        expect(creates.single, containsAllInOrder(['create', '--json']));
        expect(creates.single, containsAllInOrder(['--type', 'session']));
        // The mint stamps rig + work_bead from birth (the chokepoint's stamp).
        final mintStamp = f.runner.metadataOfUpdate(0);
        expect(mintStamp['rig'], stateRig);
        expect(mintStamp['work_bead'], 'tg-1');

        // start(sessionName, config): name == the minted session id; config.env
        // carries the engine-minted token + the bead id, and KEEPS the base env.
        expect(f.provider.started, hasLength(1));
        final call = f.provider.started.single;
        expect(call.name, 'tgdog-sess1');
        expect(call.config.env['GRID_BEAD_ID'], 'tg-1');
        expect(call.config.env['GRID_INSTANCE_TOKEN'], isNotEmpty);
        expect(call.config.env['EXISTING'], 'kept');
      },
    );

    test('session!=null (verify/land) ⇒ NO createSession; start on the existing '
        'session id', () async {
      final f = buildFakes();
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.verify,
          target: WorkPhase.land,
          session: const SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-existing',
            phase: WorkPhase.verify,
          ),
          key: const ValueKey('tg-1.verify'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();

      // No new session bead was minted — the existing cursor is reused.
      expect(f.runner.callsFor('create'), isEmpty);
      expect(f.provider.started, hasLength(1));
      expect(f.provider.started.single.name, 'tgdog-existing');
    });
  });

  group('EffectSeed — SessionStarted persists the process identity', () {
    test('emit SessionStarted(pgid:111,pid:112) ⇒ update with '
        'startedIdentityMetadata', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();

      final token =
          f.provider.started.single.config.env['GRID_INSTANCE_TOKEN']!;
      final updatesBefore = f.runner.callsFor('update').length;

      f.provider.emit(
        const SessionStarted(name: 'tgdog-sess1', pid: 112, pgid: 111),
      );
      await pumpEventQueue();

      // Exactly one new update — the identity stamp on the SAME session bead.
      final updates = f.runner.callsFor('update');
      expect(updates, hasLength(updatesBefore + 1));
      expect(updates.last, containsAllInOrder(['update', 'tgdog-sess1']));
      final stamp = f.runner.metadataOfUpdate(updates.length - 1);
      expect(stamp, startedIdentityMetadata(pgid: 111, pid: 112, token: token));
      // No bd show / SQL on this controller path.
      expect(f.runner.neverShowOrSql, isTrue);
    });
  });

  group('EffectSeed — completion advances the cursor or closes', () {
    test('Exited (advanceTo=verify) ⇒ update phaseCursorMetadata(verify)',
        () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      final updatesBefore = f.runner.callsFor('update').length;

      f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
      await pumpEventQueue();

      final updates = f.runner.callsFor('update');
      expect(updates, hasLength(updatesBefore + 1));
      expect(
        f.runner.metadataOfUpdate(updates.length - 1),
        phaseCursorMetadata(WorkPhase.verify),
      );
      // A cursor advance is NOT a close.
      expect(f.runner.callsFor('close'), isEmpty);
    });

    test('Exited (advanceTo=null) ⇒ close the session bead (positive terminal)',
        () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.land,
          target: null, // land has no next phase
          session: const SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-sess1',
            phase: WorkPhase.land,
          ),
          key: const ValueKey('tg-1.land'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();

      f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
      await pumpEventQueue();

      final closes = f.runner.callsFor('close');
      expect(closes, hasLength(1));
      expect(closes.single, containsAllInOrder(['close', 'tgdog-sess1']));
      // A close is NOT a cursor advance.
      expect(
        f.runner.callsFor('update').where(
          (c) => c.contains('--metadata') &&
              c[c.indexOf('--metadata') + 1].contains('grid.phase'),
        ),
        isEmpty,
      );
    });

    test('Died ⇒ same completion path as Exited (advance the cursor)',
        () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      final updatesBefore = f.runner.callsFor('update').length;

      f.provider.emit(const Died(name: 'tgdog-sess1', reason: 'vanished'));
      await pumpEventQueue();

      final updates = f.runner.callsFor('update');
      expect(updates, hasLength(updatesBefore + 1));
      expect(
        f.runner.metadataOfUpdate(updates.length - 1),
        phaseCursorMetadata(WorkPhase.verify),
      );
    });

    test('Respawned / ActivityChanged are ignored (no writer call)', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      final updatesBefore = f.runner.callsFor('update').length;

      f.provider.emit(const Respawned(name: 'tgdog-sess1', epoch: 2));
      f.provider.emit(const ActivityChanged(name: 'tgdog-sess1', active: true));
      await pumpEventQueue();

      // No new writes — neither is a lifecycle terminal here.
      expect(f.runner.callsFor('update'), hasLength(updatesBefore));
      expect(f.runner.callsFor('close'), isEmpty);
    });
  });

  group('EffectSeed — demux: an event for ANOTHER session is dropped', () {
    test('a completion event whose name != our session id is ignored',
        () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      final updatesBefore = f.runner.callsFor('update').length;

      // A neighbour session's exit must not advance our cursor.
      f.provider.emit(const Exited(name: 'tgdog-OTHER', exitCode: 0));
      await pumpEventQueue();

      expect(f.runner.callsFor('update'), hasLength(updatesBefore));
    });
  });

  group('EffectSeed — unmount = kill, and the post-dispose guards', () {
    test('dispose ⇒ provider.stop(sessionName) called', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(f.provider.close);
      await pumpEventQueue();
      expect(f.provider.started, hasLength(1));

      owner.dispose(); // unmounts the effect branch → State.dispose
      expect(f.provider.stopped, ['tgdog-sess1']);
    });

    test(
      'a completion event emitted AFTER dispose ⇒ NO writer call, NO StateError '
      '(the _cancelled + mounted guard)',
      () async {
        final f = buildFakes(createdId: 'tgdog-sess1');
        final owner = _mount(
          f.ctx,
          _SpawnEffect(
            bead: bead('tg-1'),
            phase: WorkPhase.implement,
            target: WorkPhase.verify,
            key: const ValueKey('tg-1.agent'),
          ),
        );
        addTearDown(f.provider.close);
        await pumpEventQueue();
        final updatesBefore = f.runner.callsFor('update').length;

        // The branch is gone; the subscription is cancelled in dispose, but
        // belt-and-suspenders: the guard must also drop a late event reaching a
        // dead node without throwing the post-unmount StateError.
        owner.dispose();
        f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
        f.provider.emit(
          const SessionStarted(name: 'tgdog-sess1', pid: 1, pgid: 2),
        );

        // No throw escapes (the test would fail on an unhandled async error),
        // and no completion/identity write landed.
        await expectLater(pumpEventQueue(), completes);
        expect(f.runner.callsFor('update'), hasLength(updatesBefore));
        expect(f.runner.callsFor('close'), isEmpty);
      },
    );

    test(
      'dispose DURING the async createSession ⇒ provider.start is NEVER called '
      '(the step-3 guard), and stop is not called (never spawned)',
      () async {
        // Gate the create so dispose lands while _run() is awaiting it.
        final runner = GatedCreateBdRunner();
        final provider = FakeRuntimeProvider();
        final writer = GridBeadWriter(
          bd: BdCliService(runner),
          ownership: BeadOwnershipPredicate(const {stateRig}),
        );
        final ctx = EffectContext(
          provider: provider,
          writer: writer,
          stateRig: stateRig,
        );
        addTearDown(provider.close);

        final owner = _mount(
          ctx,
          _SpawnEffect(
            bead: bead('tg-1'),
            phase: WorkPhase.implement,
            target: WorkPhase.verify,
            key: const ValueKey('tg-1.agent'),
          ),
        );

        // _run() is parked awaiting createSession. Dispose now.
        await pumpEventQueue();
        expect(runner.createPending, isTrue, reason: 'create should be in-flight');
        owner.dispose();

        // Now let the create resolve — the post-create guard must abort before
        // spawning.
        runner.releaseCreate('tgdog-sess1');
        await pumpEventQueue();

        expect(provider.started, isEmpty, reason: 'start must never be called');
        // We never reached the spawn, so dispose must not have issued a stop.
        expect(provider.stopped, isEmpty);
      },
    );

    test('a re-fired ready event mid-spawn: SessionAlreadyExists from start is '
        'swallowed (no throw escapes)', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      f.provider.throwOnStart = const SessionAlreadyExists('tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);

      // start threw SessionAlreadyExists, which the effect must swallow.
      await expectLater(pumpEventQueue(), completes);
      expect(f.provider.started, hasLength(1));
    });
  });

  group('EffectSeed — never bypasses the chokepoint', () {
    test('the effect issues bd ONLY via the injected writer (no show/SQL); '
        'every mutation carries --actor grid-controller', () async {
      final f = buildFakes(createdId: 'tgdog-sess1');
      final owner = _mount(
        f.ctx,
        _SpawnEffect(
          bead: bead('tg-1'),
          phase: WorkPhase.implement,
          target: WorkPhase.verify,
          key: const ValueKey('tg-1.agent'),
        ),
      );
      addTearDown(owner.dispose);
      addTearDown(f.provider.close);
      await pumpEventQueue();
      f.provider.emit(
        const SessionStarted(name: 'tgdog-sess1', pid: 1, pgid: 2),
      );
      f.provider.emit(const Exited(name: 'tgdog-sess1', exitCode: 0));
      await pumpEventQueue();

      expect(f.runner.neverShowOrSql, isTrue);
      // Every mutation went through the chokepoint with the grid actor.
      const mutations = {'create', 'update', 'close', 'delete', 'batch'};
      for (final c in f.runner.calls) {
        if (c.isEmpty || !mutations.contains(c.first)) continue;
        final i = c.indexOf('--actor');
        expect(
          i >= 0 && i + 1 < c.length && c[i + 1] == 'grid-controller',
          isTrue,
          reason: 'mutation $c lacked --actor grid-controller',
        );
      }
    });
  });
}
