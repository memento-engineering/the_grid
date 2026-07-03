// Track E — the CapabilityHost carrier: mount=spawn / dispose=kill at depth, the
// per-node identity persist (D-4) + cursor writes through the chokepoint, the
// async-gap guards, teardown, and the write fence (a Capability sees no
// writer/notifier — the sandbox DISSOLVED into layering with the context
// rip-out, ADR-0009: it reads the tree with the effect verb, it never writes).
//
// ADR-0008 D4 / M4-P1 §5, Track E. Zero I/O — fakes + the recording chokepoint.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- fake capabilities (the author leaves) -----------------------------------

class _RecordingProcessCap extends ProcessCapability {
  _RecordingProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // The effect verb: the per-session Workspace is AMBIENT (mounted by
    // SessionScope in the full tree; by the harness here).
    final workspaceDir =
        context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir;
    log.add('spawn(${args.beadId}@$workspaceDir)');
    return RuntimeConfig(
      workDir: workspaceDir,
      command: 'sh',
      args: const ['-c', 'echo hi'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<void> teardown(StepArgs args) async => log.add('teardown');
}

class _ServiceCap extends ServiceCapability {
  _ServiceCap(this.outcome, this.log);
  final StepOutcome outcome;
  final List<String> log;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    log.add('run(${args.beadId})');
    return outcome;
  }

  @override
  Future<void> teardown(StepArgs args) async => log.add('svc-teardown');
}

/// A daemon-style capability: signals `ready` when up (ActivityChanged), `failed`
/// on death (the non-positive cursor, OQ-5).
class _DaemonCap extends ProcessCapability {
  _DaemonCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'sleep 999'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when active => StepSignal.ready,
    Died() || Exited() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<void> teardown(StepArgs args) async => log.add('daemon-teardown');
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

StepMount _mount(Capability cap, {String nodePath = 'tg-1/agent'}) => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: nodePath,
  session: const SessionHandle('tgdog-s'),
  node: const NodeCursor(),
  key: ValueKey('$nodePath#0'),
);

/// The fixed clock the host's backoff cooldown is computed against.
final _clock = DateTime(2026);

({TreeOwner owner, Branch root, Fakes fakes}) _host(
  Capability cap, {
  ServiceBundle services = const ServiceBundle(),
  Workspace? workspace,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  // The Workspace is the ambient value SessionScope would mount in the full
  // tree (the context rip-out) — the harness mounts it above the bare host. A
  // test wiring a SourceControl passes the workspace derived from it (matching
  // SessionScope's computation), per the ProcessAllocation spawn-path assert.
  final root = owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: _clock),
        child: InheritedSeed<ServiceBundle>(
          value: services,
          child: InheritedSeed<Workspace>(
            value: workspace ?? testWorkspace('tg-1'),
            child: CapabilityHost(capability: cap, mount: _mount(cap)),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes);
}

/// A [SourceControl] that records `provision(beadId)` into a shared [log] so a
/// test can assert provisioning fires BEFORE the spawn. Land is irrelevant here.
class _RecordingProvisionSourceControl implements SourceControl {
  _RecordingProvisionSourceControl(this.log);
  final List<String> log;

  @override
  bool get canLand => false;

  @override
  String workspaceFor(String beadId) => '/w/$beadId';
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async => log.add('provision($beadId)');

  @override
  Future<void> commitAll({required String workspaceDir, required String message}) async {}
  @override
  Future<void> push({required String workspaceDir, required String remote, required String branch}) async {}
  @override
  Future<PrRef?> openPr({required String workspaceDir, required String branch, required String baseBranch, required String title}) async => null;
}

/// A [SourceControl] with a KNOWN workspace/branch layout that records the
/// workspaceDir it is asked to provision — so a test can prove the effect
/// spawns into + provisions the AMBIENT [Workspace] derived from the inherited
/// SourceControl (ADR-0008 D5; SessionScope owns the derivation since the
/// context rip-out), not a baked-in engine path.
class _DerivingSourceControl implements SourceControl {
  final List<String> provisionedDirs = [];

  @override
  bool get canLand => false;
  @override
  String workspaceFor(String beadId) => '/custom/ws/$beadId';
  @override
  String branchFor(String beadId) => 'custom/$beadId';
  @override
  String get baseBranch => 'trunk';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async => provisionedDirs.add(workspaceDir);

  @override
  Future<void> commitAll({required String workspaceDir, required String message}) async {}
  @override
  Future<void> push({required String workspaceDir, required String remote, required String branch}) async {}
  @override
  Future<PrRef?> openPr({required String workspaceDir, required String branch, required String baseBranch, required String title}) async => null;
}

Branch _hostBranch(Branch root) {
  Branch? found;
  void walk(Branch b) {
    if (b.seed is CapabilityHost) found = b;
    b.visitChildren(walk);
  }

  walk(root);
  return found!;
}

void main() {
  group('Track E — ProcessCapability: mount=spawn, identity, terminal', () {
    test('mount spawns under the per-step name with the engine env layered', () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      expect(h.fakes.provider.started, hasLength(1));
      final started = h.fakes.provider.started.single;
      expect(started.name, 'tgdog-s/tg-1/agent'); // $sessionId/$nodePath
      expect(started.config.env['GRID_BEAD_ID'], 'tg-1');
      expect(started.config.env['GRID_SESSION_ID'], 'tgdog-s');
      expect(started.config.env['GRID_STEP_PATH'], 'tg-1/agent');
      expect(started.config.env['GRID_INSTANCE_TOKEN'], isNotEmpty);
      expect(log.first, startsWith('spawn(tg-1@'));
    });

    test('the host provisions the workspace BEFORE spawning into it', () async {
      final log = <String>[];
      final sc = _RecordingProvisionSourceControl(log);
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(sourceControl: sc),
        workspace: testWorkspace('tg-1', workspaceDir: sc.workspaceFor('tg-1')),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // Provision is recorded, and it precedes the spawn — the agent never lands
      // in a non-existent worktree (the M3-dispatcher parity the tree path lost).
      expect(log, contains('provision(tg-1)'));
      expect(
        log.indexOf('provision(tg-1)') < log.indexWhere((l) => l.startsWith('spawn(')),
        isTrue,
        reason: 'provision must precede spawn',
      );
    });

    test('the effect spawns into + provisions the AMBIENT Workspace derived '
        'from the SourceControl (ADR-0008 D5) — the engine holds no worktree '
        'layout', () async {
      final log = <String>[];
      final sc = _DerivingSourceControl();
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(sourceControl: sc),
        // The Workspace SessionScope computes from this SourceControl in the
        // full tree (the derivation moved off the Host with the rip-out);
        // mounted here so the ambient value is what the assertions trace.
        workspace: testWorkspace(
          'tg-1',
          workspaceDir: sc.workspaceFor('tg-1'),
          branch: sc.branchFor('tg-1'),
          baseBranch: sc.baseBranch,
        ),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // The SourceControl-derived AMBIENT workspace reached the capability's
      // spawn config AND the provision call, NOT a baked engine path. (A
      // mutation that hardcodes the workspace in the Host/Allocation, or
      // resolves the wrong ambient, fails all three.)
      expect(h.fakes.provider.started.single.config.workDir, '/custom/ws/tg-1');
      expect(log.first, 'spawn(tg-1@/custom/ws/tg-1)');
      expect(sc.provisionedDirs, ['/custom/ws/tg-1'],
          reason: 'the SAME derived path is provisioned');
    });

    test('SessionStarted persists the per-node identity (pgid/pid/token/running)',
        () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
      );
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/agent.state'], 'running');
      expect(meta['grid.cursor.tg-1/agent.pgid'], '200');
      expect(meta['grid.cursor.tg-1/agent.pid'], '100');
      expect(meta['grid.cursor.tg-1/agent.token'], isNotEmpty);
      // The step-begin instant is stamped on the `running` write (FT-1), so a
      // live step's start is durable BEFORE its terminal.
      expect(meta['grid.cursor.tg-1/agent.startedAt'], isNotEmpty);
    });

    test('a clean Exited(0) writes the node cursor complete (interpretEvent)',
        () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();

      // The terminal cursor write (the only update — no SessionStarted here).
      // Carries capture-only timing (FT-1) MERGED into the same single write.
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'complete',
        ...expectedTiming('tg-1/agent'),
      });
    });

    test('a non-zero Exited writes the SUPERVISED failure (failed + restartCount '
        '+ backoff cooldown — D-5)', () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1));
      await _pump();
      // restartCount bumped to 1; cooldown = clock + Backoff.standard.delayFor(1)
      // (= 1s). Within budget (maxRestarts default 3), so a cooldown is written.
      // A bare process death carries no diagnostic → no failureReason key (FT-1).
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'failed',
        'grid.cursor.tg-1/agent.restartCount': '1',
        'grid.cursor.tg-1/agent.cooldownUntil':
            _clock.add(const Duration(seconds: 1)).toIso8601String(),
        ...expectedTiming('tg-1/agent'),
      });
    });

    test('the LAST restart (exhausted) writes failed + restartCount, NO cooldown '
        '(circuit-broken → SessionScope escalates)', () async {
      final log = <String>[];
      final fakes = buildFakes();
      final owner = TreeOwner();
      addTearDown(() {
        owner.dispose();
        unawaited(fakes.provider.close());
      });
      // The node is already at restartCount 2; one more failure → 3 == maxRestarts
      // → exhausted.
      owner.mountRoot(
        InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: _clock),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: InheritedSeed<Workspace>(
                value: testWorkspace('tg-1'),
                child: CapabilityHost(
                  capability: _RecordingProcessCap(log),
                  mount: StepMount(
                    step: const CapabilityStep(
                      stepId: 'agent',
                      capabilityId: 'agent',
                    ),
                    nodePath: 'tg-1/agent',
                    session: const SessionHandle('tgdog-s'),
                    node: const NodeCursor(restartCount: 2),
                    key: const ValueKey('tg-1/agent#2'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _pump();
      fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1));
      await _pump();
      expect(fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'failed',
        'grid.cursor.tg-1/agent.restartCount': '3', // == maxRestarts → exhausted
        // no cooldownUntil key — the breaker is tripped.
        ...expectedTiming('tg-1/agent'),
      });
    });

    test('dispose kills the managed group AND runs the belt-and-braces teardown',
        () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      await _pump();
      h.owner.dispose();
      await _pump();
      unawaited(h.fakes.provider.close());

      expect(h.fakes.provider.stopped, ['tgdog-s/tg-1/agent']);
      expect(log, contains('teardown'));
    });
  });

  group('Track E — the async-gap guards (ported from EffectSeed)', () {
    test('a terminal delivered AFTER dispose writes nothing + does not throw',
        () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      await _pump();
      // Capture the State BEFORE dispose (the branch leaves the tree on unmount).
      // ignore: invalid_use_of_protected_member
      final state = (_hostBranch(h.root) as StatefulBranch).state
          as CapabilityHostState;
      h.fakes.runner.calls.clear();
      h.owner.dispose(); // _cancelled = true FIRST
      // Deliver a terminal straight to the handler (the subscription is gone).
      state.deliverEventForTest(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
      );
      await _pump();
      unawaited(h.fakes.provider.close());

      expect(
        h.fakes.runner.callsFor('update'),
        isEmpty,
        reason: 'a post-dispose completion is dropped (the _cancelled guard)',
      );
    });

    test('teardown fires even when disposed BEFORE the kick reaches spawn '
        '(finding #1: guaranteed on every exit path)', () async {
      final log = <String>[];
      // The pre-spawn async gap is the provisioning await (without source
      // control the new kick spawns synchronously at mount — nothing to race).
      final sc = _RecordingProvisionSourceControl(log);
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(sourceControl: sc),
        workspace: testWorkspace('tg-1', workspaceDir: sc.workspaceFor('tg-1')),
      );
      // Dispose IMMEDIATELY — startOrAdopt is parked on the provision await; its
      // cancel-token check after the gap bails, so the spawn is never reached
      // (_started stays false). The Allocation was minted in
      // didChangeDependencies, so dispose → teardown STILL fires.
      h.owner.dispose();
      await _pump();
      unawaited(h.fakes.provider.close());
      expect(log, contains('teardown'));
      expect(
        h.fakes.provider.started,
        isEmpty,
        reason: 'the spawn was never reached',
      );
    });

    test('two terminals in one incarnation write the cursor only ONCE (latch)',
        () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();

      expect(h.fakes.runner.callsFor('update'), hasLength(1));
    });
  });

  group('Track E — ServiceCapability', () {
    test('run → Ok writes complete; teardown runs on dispose', () async {
      final log = <String>[];
      final h = _host(_ServiceCap(const Ok(), log));
      await _pump();
      expect(log, contains('run(tg-1)'));
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'complete',
        ...expectedTiming('tg-1/agent'),
      });

      h.owner.dispose();
      await _pump();
      unawaited(h.fakes.provider.close());
      expect(log, contains('svc-teardown'));
      // A ServiceCapability is not a process — never stopped.
      expect(h.fakes.provider.stopped, isEmpty);
    });

    test('run → Ok(payload) records the result alongside complete — the land '
        "step's pr_url lands on the session bead (ADR-0006 D3), namespaced "
        'disjoint from the cursor so it never misreads as state', () async {
      final log = <String>[];
      const pr = 'https://github.com/acme/widget/pull/7';
      final h = _host(_ServiceCap(const Ok({'pr_url': pr}), log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      expect(log, contains('run(tg-1)'));
      // ONE merged write: the terminal cursor state PLUS the namespaced result
      // PLUS the capture-only timing (FT-1) — all in a single chokepoint write.
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'complete',
        'grid.result.tg-1/agent.pr_url': pr,
        ...expectedTiming('tg-1/agent'),
      });
    });

    test('run → Failed writes the supervised failure (failed + restartCount + '
        'cooldown)', () async {
      final log = <String>[];
      final h = _host(_ServiceCap(const Failed('nope'), log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      // A ServiceCapability Failed('nope') carries a diagnostic → it is persisted
      // capture-only as the truncated failureReason, MERGED into the same write.
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'failed',
        'grid.cursor.tg-1/agent.restartCount': '1',
        'grid.cursor.tg-1/agent.cooldownUntil':
            _clock.add(const Duration(seconds: 1)).toIso8601String(),
        'grid.cursor.tg-1/agent.failureReason': 'nope',
        ...expectedTiming('tg-1/agent'),
      });
    });
  });

  group('Track E — the daemon ready→death path (no latch on ready, OQ-5)', () {
    test('a daemon writes ready (no latch), then a later death writes failed — '
        'TWO writes (the latch must NOT fire on ready)', () async {
      final log = <String>[];
      // A daemon-style capability: SessionStarted → ready (up), Died → failed.
      final h = _host(_DaemonCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // The daemon signals up → ready (positive terminal; stays mounted).
      h.fakes.provider.emit(
        const ActivityChanged(name: 'tgdog-s/tg-1/agent', active: true),
      );
      await _pump();
      // A daemon `ready` is a positive terminal too → it carries timing (FT-1).
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'ready',
        ...expectedTiming('tg-1/agent'),
      });

      // Later the daemon dies → failed. A SECOND write (latch did not fire on
      // ready). A mutation latching on ready would drop this.
      h.fakes.provider.emit(const Died(name: 'tgdog-s/tg-1/agent'));
      await _pump();
      expect(h.fakes.runner.callsFor('update'), hasLength(2));
      expect(h.fakes.runner.metadataOfUpdate(1)['grid.cursor.tg-1/agent.state'],
          'failed');
    });
  });

  group('Track E — the write fence (the SDK leaks no engine WRITE surface)', () {
    test('capability.dart IMPORTS no writer / notifier / station services '
        '(genesis_tree IS imported — the effect verb is the norm)', () async {
      // Resolve the source CWD-independently (the repo-root `dart test` and the
      // per-package `melos test` have different working directories).
      final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:grid_engine/src/sdk/capability.dart'),
      );
      final src = File(uri!.toFilePath()).readAsStringSync();
      // The fence is about IMPORTS (the doc comment may mention these by name to
      // explain what a capability deliberately CANNOT touch).
      final imports = src
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '))
          .toList();
      // The context rip-out (ADR-0009: the sandbox DISSOLVES — layering + a
      // single write-locus, not a wall): a capability now receives the
      // TreeContext and reads ambient values with the effect verb, so the
      // genesis_tree import is EXPECTED — the positive control that this is
      // the post-rip-out SDK file. What remains fenced is the WRITE surface.
      expect(imports.any((l) => l.contains('genesis_tree')), isTrue);
      expect(imports.any((l) => l.contains('station_bead_writer')), isFalse);
      expect(imports.any((l) => l.contains('joined_snapshot_notifier')), isFalse);
      expect(imports.any((l) => l.contains('station_services')), isFalse);
    });

    test('StepArgs carries only the per-step values; the ambient values resolve '
        'from the tree (no writer/notifier/stream anywhere)', () {
      // The deleted CapabilityContext threaded bead/workspace/services/siblings
      // BY VALUE. The new shape splits them (ADR-0008 Decision 3): StepArgs
      // carries only what is OF the step incarnation — params, nodePath, the
      // derived beadId, the cooperative cancel token, and the restoration
      // logFile seam. No Stream, no writer, no TreeContext rides in it.
      final args = StepArgs(
        params: const <String, String>{},
        nodePath: 'tg-1/agent',
        cancel: CancelToken(),
      );
      expect(args.beadId, 'tg-1');
      expect(args.params, isEmpty);
      expect(args.cancel, isA<CancelToken>());
      expect(args.logFile, isNull);

      // …and everything the old context threaded is now AMBIENT, read with the
      // effect verb off the (fake) tree — still values only, never a writer.
      final tree = FakeTreeContext(
        values: {
          Bead: bead('tg-1'),
          Workspace: testWorkspace('tg-1', branch: 'grid/tg-1'),
          ServiceBundle: const ServiceBundle(),
          SiblingView: const SiblingView(),
        },
      );
      expect(tree.getInheritedSeedOfExactType<Bead>()!.id, 'tg-1');
      final workspace = tree.getInheritedSeedOfExactType<Workspace>()!;
      expect(workspace.workspaceDir, '/grid/workspaces/tg-1');
      expect(workspace.branch, 'grid/tg-1');
      expect(workspace.baseBranch, 'main');
      expect(
        tree.getInheritedSeedOfExactType<ServiceBundle>(),
        isA<ServiceBundle>(),
      );
      expect(
        tree.getInheritedSeedOfExactType<SiblingView>(),
        isA<SiblingView>(),
      );
    });
  });
}
