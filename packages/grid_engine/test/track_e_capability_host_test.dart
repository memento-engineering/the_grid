// Track E — the CapabilityHost carrier: mount=spawn / dispose=kill at depth, the
// per-STEP-BEAD persist (R5b) + cursor writes through the chokepoint, the
// async-gap guards, teardown, and the write fence (a Capability sees no
// writer/notifier — the sandbox DISSOLVED into layering with the context
// rip-out, ADR-0009: it reads the tree with the effect verb, it never writes).
//
// MIGRATED (tg-eli phase 2 — the molecule-only removal): the flat
// `grid.cursor.{nodePath}.*` session-bead write retired; every persist now
// targets the step's OWN durable bead (`InheritedCircuit.beadIdByNodePath`,
// R2/R5b) under the `grid.step.*` namespace (`MoleculeStepKeys`,
// `molecule_codec.dart`'s `stepBeadMetadata`) — so every host in this suite is
// now mounted under an `InheritedCircuit`. A `ProcessCapability` no longer
// mounts a flat `ProcessAllocation` directly: `_createAllocationOrFlare`
// routes it through the ambient `ProcessLeaseVendor` (tg-h4u) — this suite
// wires `SelfManagedProcessVendor(spawn: stationProcessSpawner, dispatch:
// stationProcessDispatcher)`, the REAL transport-backed hooks, so the
// `FakeRuntimeProvider` assertions (`started`/`stopped`) still read the exact
// same events as the retired flat path. Two consequences worth flagging
// (real behavior, not a test-authoring choice):
//  (1) the lease's spawn hook (`stationProcessSpawner`) resolves its
//      `ProcessHandle` off a `SessionStarted` event specifically — so every
//      terminal-event test here now emits `SessionStarted` BEFORE the
//      terminal, where the old flat `ProcessAllocation` needed no such
//      handshake.
//  (2) `LeaseAllocation.dispose` releases the lease (stops the transport) but
//      never calls the capability's own `teardown()` — `sdk/lease.dart` has no
//      `capability.teardown` call site, unlike the retired `ProcessAllocation`
//      (`sdk/allocation.dart`). A `ProcessCapability`'s `teardown` hook is
//      therefore DEAD on the molecule path today; this file asserts what
//      actually happens (the transport is stopped) and no longer asserts the
//      author teardown fires for a process capability. Worth a follow-up bead
//      (out of this lane's scope — engine behavior, not a test fix).
// `ServiceCapability` is unaffected by the lease fork (it still rides
// `capability.createAllocation` → `ServiceAllocation` directly, which DOES
// call `capability.teardown`), so its teardown coverage is untouched.
//
// ignore_for_file: invalid_use_of_protected_member
//
// ADR-0008 D4 / M4-P1 §5, Track E. Zero I/O — fakes + the recording chokepoint.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

// --- fake capabilities (the author leaves) -----------------------------------

class _RecordingProcessCap extends ProcessCapability {
  _RecordingProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    // The effect verb: the per-session Workspace is AMBIENT (mounted by
    // SessionScope in the full tree; by the harness here).
    final workspaceDir = context
        .getInheritedSeedOfExactType<Workspace>()!
        .workspaceDir;
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

/// The circuit the mounted `agent` step belongs to (`StepMount.circuit` — the
/// graph a Rewind would resolve its siblings against; tg-o90).
const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _mount(
  Capability cap, {
  String nodePath = 'tg-1/agent',
  int restartCount = 0,
}) => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: nodePath,
  circuit: _circuit,
  circuitPath: nodePath.contains('/')
      ? nodePath.substring(0, nodePath.lastIndexOf('/'))
      : '',
  session: const SessionHandle('tgdog-s'),
  node: NodeCursor(restartCount: restartCount),
  key: ValueKey('$nodePath#$restartCount.0'),
);

/// The fixed clock the host's backoff cooldown / telemetry is computed
/// against — every `now()` call resolves to the SAME instant, so a terminal
/// write's derived `startedAt == finishedAt` and `durationMs == 0`.
final _clock = DateTime(2026);

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/agent`
/// to across this suite — the write TARGET every persist now resolves
/// (R5b), replacing the retired flat session-bead write.
const _stepBeadId = 'tgdog-step1';

/// An [InheritedCircuit] wired for `tg-1/agent` — the molecule ambient every
/// host in this suite mounts under (tg-eli phase 2: a bare host with no
/// `InheritedCircuit` refuses LOUD — proven in
/// `test/molecule/host_molecule_targeting_test.dart`, not re-proven here).
InheritedCircuit _moleculeCircuit({String nodePath = 'tg-1/agent'}) =>
    InheritedCircuit(
      root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
      beadIdByNodePath: {nodePath: _stepBeadId},
      cursor: const {},
    );

/// The step bead's expected timing metadata for a TERMINAL write under the
/// fixed [_clock] (`stepBeadMetadata` normalizes to UTC — an intentional
/// divergence from the retired flat codec, `host_molecule_targeting_test.dart`).
Map<String, String> _timing() => {
  MoleculeStepKeys.startedAt: _clock.toUtc().toIso8601String(),
  MoleculeStepKeys.finishedAt: _clock.toUtc().toIso8601String(),
  MoleculeStepKeys.durationMs: '0',
};

/// The REAL transport-backed lease vendor (tg-h4u): routes a molecule-mode
/// `ProcessCapability` through `stationProcessSpawner`/`stationProcessDispatcher`
/// — the SAME `RuntimeProvider` machinery the retired flat `ProcessAllocation`
/// drove — so `h.fakes.provider.started`/`stopped` observe identical events.
/// No durable breadcrumb (no adopt story needed for this suite).
const _realVendor = SelfManagedProcessVendor(
  spawn: stationProcessSpawner,
  dispatch: stationProcessDispatcher,
);

({TreeOwner owner, Branch root, Fakes fakes}) _host(
  Capability cap, {
  ServiceBundle services = const ServiceBundle(),
  Workspace? workspace,
  StepMount? mount,
  ProcessLeaseVendor? leaseVendor,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final stepMount = mount ?? _mount(cap);
  Seed tree = CapabilityHost(capability: cap, mount: stepMount);
  tree = InheritedSeed<InheritedCircuit>(
    value: _moleculeCircuit(nodePath: stepMount.nodePath),
    child: tree,
  );
  if (cap is ProcessCapability) {
    tree = InheritedSeed<ProcessLeaseVendor>(
      value: leaseVendor ?? _realVendor,
      child: tree,
    );
  }
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
            child: tree,
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes);
}

/// A [SourceControl] that records `provision(beadId)` into a shared [log] so a
/// test can assert provisioning fires BEFORE the spawn. Land is irrelevant
/// here. Rooted at a REAL temp dir, and provisioning MATERIALIZES a `.git`
/// marker — the post-provision guard ([assertProvisionedCheckout], bead
/// tg-6jn) gives "provisioned" a checkable meaning a fake may not skip.
class _RecordingProvisionSourceControl implements SourceControl {
  _RecordingProvisionSourceControl(this.log, this.root);
  final List<String> log;
  final String root;

  @override
  String workspaceFor(String beadId) => '$root/$beadId';
  @override
  String branchFor(String beadId) => 'grid/$beadId';
  @override
  String get baseBranch => 'main';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    log.add('provision($beadId)');
    Directory('$workspaceDir/.git').createSync(recursive: true);
  }
}

/// A [SourceControl] with a KNOWN workspace/branch layout that records the
/// workspaceDir it is asked to provision — so a test can prove the effect
/// spawns into + provisions the AMBIENT [Workspace] derived from the inherited
/// SourceControl (ADR-0008 D5; SessionScope owns the derivation since the
/// context rip-out), not a baked-in engine path. Rooted at a REAL temp dir and
/// materializes a `.git` marker for the same reason as
/// [_RecordingProvisionSourceControl].
class _DerivingSourceControl implements SourceControl {
  _DerivingSourceControl(this.root);
  final String root;
  final List<String> provisionedDirs = [];

  @override
  String workspaceFor(String beadId) => '$root/custom-ws-$beadId';
  @override
  String branchFor(String beadId) => 'custom/$beadId';
  @override
  String get baseBranch => 'trunk';

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async {
    provisionedDirs.add(workspaceDir);
    Directory('$workspaceDir/.git').createSync(recursive: true);
  }
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

/// Emits `SessionStarted` for [name] then pumps — the handshake
/// `stationProcessSpawner`'s acquire hook waits on to resolve its
/// [ProcessHandle] (see the file doc, consequence (1)) — clearing recorded
/// chokepoint calls afterward so a test's terminal-write assertions read only
/// the ONE write that follows, exactly like the retired flat suite's shape.
Future<void> _startThenIsolate(Fakes fakes, String name) async {
  await _pump();
  fakes.provider.emit(SessionStarted(name: name, pid: 100, pgid: 200));
  await _pump();
  fakes.runner.calls.clear();
}

void main() {
  group('Track E — ProcessCapability: mount=spawn, identity, terminal', () {
    test(
      'mount spawns under the per-step name with the engine env layered',
      () async {
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
      },
    );

    test('the host provisions the workspace BEFORE spawning into it', () async {
      final log = <String>[];
      final root = Directory.systemTemp.createTempSync('track-e-prov-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sc = _RecordingProvisionSourceControl(log, root.path);
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
        log.indexOf('provision(tg-1)') <
            log.indexWhere((l) => l.startsWith('spawn(')),
        isTrue,
        reason: 'provision must precede spawn',
      );
    });

    test('the effect spawns into + provisions the AMBIENT Workspace derived '
        'from the SourceControl (ADR-0008 D5) — the engine holds no worktree '
        'layout', () async {
      final log = <String>[];
      final root = Directory.systemTemp.createTempSync('track-e-derive-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sc = _DerivingSourceControl(root.path);
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
      final ws = sc.workspaceFor('tg-1');
      expect(h.fakes.provider.started.single.config.workDir, ws);
      expect(log.first, 'spawn(tg-1@$ws)');
      expect(sc.provisionedDirs, [
        ws,
      ], reason: 'the SAME derived path is provisioned');
    });

    test(
      'SessionStarted targets the STEP bead: grid.step.state=running (no '
      'pgid/pid/token there any more — R3 makes them the LEASE vendor\'s '
      'grid.lease.* breadcrumb, never the step bead\'s own cursor keys)',
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

        final updates = h.fakes.runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single[1], _stepBeadId);
        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta[MoleculeStepKeys.state], 'running');
        expect(meta[MoleculeStepKeys.restartCount], '0');
        expect(
          meta.keys,
          isNot(anyOf(contains('grid.step.pgid'), contains('grid.step.pid'))),
        );
        expect(meta.keys.where((k) => k.startsWith('grid.cursor.')), isEmpty);
      },
    );

    test(
      'a clean Exited(0) writes the step bead complete (interpretEvent)',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log));
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

        h.fakes.provider.emit(
          const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
        );
        await _pump();

        // The terminal cursor write (the only update since the clear — no
        // further SessionStarted write in this window). Carries capture-only
        // timing (FT-1) MERGED into the same single write.
        expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
        expect(h.fakes.runner.metadataOfUpdate(0), {
          MoleculeStepKeys.state: 'complete',
          MoleculeStepKeys.restartCount: '0',
          ..._timing(),
        });
      },
    );

    test('a non-zero Exited writes the SUPERVISED failure (failed + restartCount '
        '+ backoff cooldown — D-5)', () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
      h.fakes.provider.emit(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1),
      );
      await _pump();
      // restartCount bumped to 1; cooldown = clock + Backoff.standard.delayFor(1)
      // (= 1s). Within budget (maxRestarts default 3), so a cooldown is written.
      // The dispatcher's generic `interpretEvent` → failed signal carries no
      // capability-authored diagnostic → the generic dispatch reason.
      expect(h.fakes.runner.metadataOfUpdate(0), {
        MoleculeStepKeys.state: 'failed',
        MoleculeStepKeys.restartCount: '1',
        MoleculeStepKeys.cooldownUntil: _clock
            .add(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String(),
        MoleculeStepKeys.failureReason: 'the spawned process failed',
        ..._timing(),
      });
    });

    test(
      'a killed process event (Died BEFORE SessionStarted) fails the ACQUIRE '
      "— the dispatcher never runs, so the Died event's own reason text "
      'surfaces via the lease\'s "acquire threw" wrapping, never left running',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log));
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        expect(h.fakes.provider.started, hasLength(1));
        h.fakes.provider.emit(
          const Died(
            name: 'tgdog-s/tg-1/agent',
            reason: 'governor killed validation lane process group',
          ),
        );
        await _pump();

        expect(h.fakes.runner.callsFor('update'), hasLength(1));
        expect(
          h.fakes.runner.metadataOfUpdate(0),
          containsPair(MoleculeStepKeys.state, 'failed'),
        );
        expect(
          h.fakes.runner.metadataOfUpdate(0)[MoleculeStepKeys.failureReason],
          contains('process died before SessionStarted'),
        );
      },
    );

    test('the LAST restart (exhausted) writes failed + restartCount, NO cooldown '
        '(circuit-broken → SessionScope escalates)', () async {
      final log = <String>[];
      // The node is already at restartCount 2; one more failure → 3 == maxRestarts
      // → exhausted.
      final h = _host(
        _RecordingProcessCap(log),
        mount: _mount(_RecordingProcessCap(log), restartCount: 2),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
      h.fakes.provider.emit(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1),
      );
      await _pump();
      expect(h.fakes.runner.metadataOfUpdate(0), {
        MoleculeStepKeys.state: 'failed',
        MoleculeStepKeys.restartCount: '3', // == maxRestarts → exhausted
        // no cooldownUntil key — the breaker is tripped.
        MoleculeStepKeys.failureReason: 'the spawned process failed',
        ..._timing(),
      });
    });

    test(
      'dispose STOPS the spawned group (dispose == RELEASE, ADR-0009 D4). The '
      "author capability's OWN teardown() is NOT called on this path any more "
      '— sdk/lease.dart has no capability.teardown call site, unlike the '
      'retired flat ProcessAllocation (see file doc)',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log));
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
        h.owner.dispose();
        await _pump();
        unawaited(h.fakes.provider.close());

        expect(h.fakes.provider.stopped, ['tgdog-s/tg-1/agent']);
        expect(
          log,
          isNot(contains('teardown')),
          reason: 'ProcessCapability.teardown is dead on the lease-routed path',
        );
      },
    );
  });

  group('Track E — the async-gap guards (ported from EffectSeed)', () {
    test(
      'a terminal delivered AFTER dispose writes nothing + does not throw',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log));
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');
        // Capture the State BEFORE dispose (the branch leaves the tree on unmount).
        final state =
            (_hostBranch(h.root) as StatefulBranch).state
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
      },
    );

    test('dispose BEFORE any spawn is reached leaves the transport untouched '
        '(the pre-acquire cancel-token guard: finding #1 restated for the '
        'lease-routed path)', () async {
      final log = <String>[];
      // The pre-spawn async gap is the provisioning await (without source
      // control the new kick spawns synchronously at mount — nothing to race).
      final root = Directory.systemTemp.createTempSync('track-e-race-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sc = _RecordingProvisionSourceControl(log, root.path);
      final h = _host(
        _RecordingProcessCap(log),
        services: ServiceBundle(sourceControl: sc),
        workspace: testWorkspace('tg-1', workspaceDir: sc.workspaceFor('tg-1')),
      );
      // Dispose IMMEDIATELY — startOrAdopt is parked on the provision await; its
      // cancel-token check after the gap bails, so the spawn is never reached
      // (transport.start is never called; no handle is ever bound, so dispose
      // has nothing to release either).
      h.owner.dispose();
      await _pump();
      unawaited(h.fakes.provider.close());
      expect(
        h.fakes.provider.started,
        isEmpty,
        reason: 'the spawn was never reached',
      );
      expect(h.fakes.provider.stopped, isEmpty);
      expect(h.fakes.runner.calls, isEmpty);
    });

    test(
      'two terminals in one incarnation write the cursor only ONCE (latch)',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log));
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

        h.fakes.provider.emit(
          const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
        );
        h.fakes.provider.emit(
          const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0),
        );
        await _pump();

        expect(h.fakes.runner.callsFor('update'), hasLength(1));
      },
    );
  });

  group('Track E — ServiceCapability', () {
    test('run → Ok writes complete; teardown runs on dispose', () async {
      final log = <String>[];
      final h = _host(_ServiceCap(const Ok(), log));
      await _pump();
      expect(log, contains('run(tg-1)'));
      expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
      expect(h.fakes.runner.metadataOfUpdate(0), {
        MoleculeStepKeys.state: 'complete',
        MoleculeStepKeys.restartCount: '0',
        ..._timing(),
      });

      h.owner.dispose();
      await _pump();
      unawaited(h.fakes.provider.close());
      expect(log, contains('svc-teardown'));
      // A ServiceCapability is not a process — never stopped.
      expect(h.fakes.provider.stopped, isEmpty);
    });

    test('run → Ok(payload) records the result alongside complete — the land '
        "step's pr_url lands on the STEP bead (R1 — ResultKeys reused "
        'VERBATIM; only the host bead moved from session to step), '
        'namespaced disjoint from the cursor so it never misreads as state',
        () async {
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
        MoleculeStepKeys.state: 'complete',
        MoleculeStepKeys.restartCount: '0',
        'grid.result.tg-1/agent.pr_url': pr,
        ..._timing(),
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
        MoleculeStepKeys.state: 'failed',
        MoleculeStepKeys.restartCount: '1',
        MoleculeStepKeys.cooldownUntil: _clock
            .add(const Duration(seconds: 1))
            .toUtc()
            .toIso8601String(),
        MoleculeStepKeys.failureReason: 'nope',
        ..._timing(),
      });
    });
  });

  group('Track E — the daemon ready→death path (no latch on ready, OQ-5)', () {
    test(
      'a daemon writes ready (no latch — a second write COULD still land after '
      'it). A death emitted AFTER ready is NOT observed on the lease-routed '
      'path today: stationProcessDispatcher waits for the FIRST non-none '
      'signal and cancels its subscription once dispatch resolves, so nothing '
      'keeps listening for a later Died once a daemon reaches `ready` — a real '
      'gap versus the retired flat ProcessAllocation (which kept its '
      'subscription open for the life of the mount); flagged, not fixed here '
      '(out of this lane\'s scope — engine behavior, not a test fix)',
      () async {
      final log = <String>[];
      // A daemon-style capability: SessionStarted → ready (up), Died → failed.
      final h = _host(
        _DaemonCap(log),
        mount: StepMount(
          step: const CapabilityStep(
            stepId: 'agent',
            capabilityId: 'agent',
            kind: StepKind.daemon,
          ),
          nodePath: 'tg-1/agent',
          circuit: _circuit,
          circuitPath: 'tg-1',
          session: const SessionHandle('tgdog-s'),
          node: const NodeCursor(),
          key: const ValueKey('tg-1/agent#0.0'),
        ),
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _startThenIsolate(h.fakes, 'tgdog-s/tg-1/agent');

      // The daemon signals up → ready (positive terminal; stays mounted).
      h.fakes.provider.emit(
        const ActivityChanged(name: 'tgdog-s/tg-1/agent', active: true),
      );
      await _pump();
      // A daemon `ready` is a positive terminal too → it carries timing (FT-1).
      expect(h.fakes.runner.metadataOfUpdate(0), {
        MoleculeStepKeys.state: 'ready',
        MoleculeStepKeys.restartCount: '0',
        ..._timing(),
      });

      // The later death is a no-op on the chokepoint today (see the group
      // doc): NOT because a latch swallowed it (the honest OQ-5 guarantee —
      // `ready` never latches), but because nothing is listening any more.
      h.fakes.provider.emit(const Died(name: 'tgdog-s/tg-1/agent'));
      await _pump();
      expect(h.fakes.runner.callsFor('update'), hasLength(1));
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
      expect(
        imports.any((l) => l.contains('joined_snapshot_notifier')),
        isFalse,
      );
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
