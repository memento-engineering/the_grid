// Track E — the CapabilityHost carrier: mount=spawn / dispose=kill at depth, the
// per-node identity persist (D-4) + cursor writes through the chokepoint, the
// async-gap guards, teardown, and the sandbox fence (a Capability sees no
// Seed/writer/notifier).
//
// ADR-0008 D4 / M4-P1 §5, Track E. Zero I/O — fakes + the recording chokepoint.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- fake capabilities (the author leaves) -----------------------------------

class _RecordingProcessCap extends ProcessCapability {
  _RecordingProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) {
    log.add('spawn(${ctx.beadId}@${ctx.workspaceDir})');
    return RuntimeConfig(
      workDir: ctx.workspaceDir,
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
  Future<void> teardown(CapabilityContext ctx) async => log.add('teardown');
}

class _ServiceCap extends ServiceCapability {
  _ServiceCap(this.outcome, this.log);
  final StepOutcome outcome;
  final List<String> log;

  @override
  Future<StepOutcome> run(CapabilityContext ctx) async {
    log.add('run(${ctx.beadId})');
    return outcome;
  }

  @override
  Future<void> teardown(CapabilityContext ctx) async => log.add('svc-teardown');
}

/// A daemon-style capability: signals `ready` when up (ActivityChanged), `failed`
/// on death (the non-positive cursor, OQ-5).
class _DaemonCap extends ProcessCapability {
  _DaemonCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
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
  Future<void> teardown(CapabilityContext ctx) async => log.add('daemon-teardown');
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

StepMount _mount(Capability cap, {String nodePath = 'tg-1/agent'}) => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  bead: bead(nodePath.split('/').first),
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
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: StableInheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: _clock),
        child: InheritedSeed<ServiceBundle>(
          value: services,
          child: CapabilityHost(capability: cap, mount: _mount(cap)),
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
/// workspaceDir it is asked to provision — so a test can prove the HOST DERIVES
/// its workspace from the INHERITED SourceControl (ADR-0008 D5), not from a
/// baked-in engine path (the EffectContext→StationServices cleanup).
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
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(
          sourceControl: _RecordingProvisionSourceControl(log),
        ),
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

    test('the host DERIVES workspaceDir from the INHERITED SourceControl '
        '(ADR-0008 D5) — the engine holds no worktree layout', () async {
      final log = <String>[];
      final sc = _DerivingSourceControl();
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(sourceControl: sc),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // The workspace came from the inherited SourceControl's workspaceFor — it
      // reached the capability's spawn config AND the provision call, NOT a
      // baked engine path. (A mutation that hardcodes the workspace in the Host,
      // or resolves the wrong ambient, fails all three.)
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
      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'complete'});
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
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'failed',
        'grid.cursor.tg-1/agent.restartCount': '1',
        'grid.cursor.tg-1/agent.cooldownUntil':
            _clock.add(const Duration(seconds: 1)).toIso8601String(),
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
          child: StableInheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: _clock),
            child: InheritedSeed<ServiceBundle>(
              value: const ServiceBundle(),
              child: CapabilityHost(
                capability: _RecordingProcessCap(log),
                mount: StepMount(
                  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
                  bead: bead('tg-1'),
                  nodePath: 'tg-1/agent',
                  session: const SessionHandle('tgdog-s'),
                  node: const NodeCursor(restartCount: 2),
                  key: const ValueKey('tg-1/agent#2'),
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

    test('teardown fires even when disposed BEFORE _run reaches spawn '
        '(finding #1: guaranteed on every exit path)', () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      // Dispose IMMEDIATELY — _run is scheduled but has not passed `await null`,
      // so the spawn never happens (_started stays false). _capCtx was built in
      // didChangeDependencies, so teardown STILL fires.
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
      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'complete'});

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
      // ONE merged write: the terminal cursor state PLUS the namespaced result.
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'complete',
        'grid.result.tg-1/agent.pr_url': pr,
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
      expect(h.fakes.runner.metadataOfUpdate(0), {
        'grid.cursor.tg-1/agent.state': 'failed',
        'grid.cursor.tg-1/agent.restartCount': '1',
        'grid.cursor.tg-1/agent.cooldownUntil':
            _clock.add(const Duration(seconds: 1)).toIso8601String(),
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
      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'ready'});

      // Later the daemon dies → failed. A SECOND write (latch did not fire on
      // ready). A mutation latching on ready would drop this.
      h.fakes.provider.emit(const Died(name: 'tgdog-s/tg-1/agent'));
      await _pump();
      expect(h.fakes.runner.callsFor('update'), hasLength(2));
      expect(h.fakes.runner.metadataOfUpdate(1)['grid.cursor.tg-1/agent.state'],
          'failed');
    });
  });

  group('Track E — the sandbox fence (the SDK leaks no engine surface)', () {
    test('capability.dart IMPORTS no genesis_tree / writer / notifier', () async {
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
      expect(imports.any((l) => l.contains('genesis_tree')), isFalse);
      expect(imports.any((l) => l.contains('station_bead_writer')), isFalse);
      expect(imports.any((l) => l.contains('joined_snapshot_notifier')), isFalse);
      expect(imports.any((l) => l.contains('station_services')), isFalse);
    });

    test('CapabilityContext exposes no notifier/stream/writer surface', () {
      // Compile-time: a CapabilityContext has only the sandboxed fields. This
      // asserts the SHAPE (params/bead/workspaceDir/branch/baseBranch/services/
      // cancel/logFile) — no Stream, no writer, no TreeContext.
      final ctx = CapabilityContext(
        params: const {},
        bead: bead('tg-1'),
        workspaceDir: '/w',
        branch: 'grid/tg-1',
        baseBranch: 'main',
        services: const ServiceBundle(),
        cancel: CancelToken(),
        nodePath: 'tg-1/agent',
      );
      expect(ctx.beadId, 'tg-1');
      expect(ctx.services, isA<ServiceBundle>());
      expect(ctx.cancel, isA<CancelToken>());
      expect(ctx.siblings, isA<SiblingView>());
      expect(ctx.logFile, isNull);
    });
  });
}
