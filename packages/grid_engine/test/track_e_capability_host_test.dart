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

({TreeOwner owner, Branch root, Fakes fakes}) _host(Capability cap) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<EffectContext>(
      value: fakes.ctx,
      child: InheritedSeed<ServiceBundle>(
        value: const ServiceBundle(),
        child: CapabilityHost(capability: cap, mount: _mount(cap)),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes);
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
      expect(started.config.env['GRID_STEP_PATH'], 'tg-1/agent');
      expect(started.config.env['GRID_INSTANCE_TOKEN'], isNotEmpty);
      expect(log.first, startsWith('spawn(tg-1@'));
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

    test('a non-zero Exited writes failed', () async {
      final log = <String>[];
      final h = _host(_RecordingProcessCap(log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      h.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1));
      await _pump();
      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'failed'});
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

    test('run → Failed writes failed', () async {
      final log = <String>[];
      final h = _host(_ServiceCap(const Failed('nope'), log));
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();
      expect(h.fakes.runner.metadataOfUpdate(0),
          {'grid.cursor.tg-1/agent.state': 'failed'});
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
      expect(imports.any((l) => l.contains('effect_context')), isFalse);
    });

    test('CapabilityContext exposes no notifier/stream/writer surface', () {
      // Compile-time: a CapabilityContext has only the sandboxed fields. This
      // asserts the SHAPE (params/beadId/workspaceDir/branch/baseBranch/services/
      // cancel/logFile) — no Stream, no writer, no TreeContext.
      final ctx = CapabilityContext(
        params: const {},
        beadId: 'tg-1',
        workspaceDir: '/w',
        branch: 'grid/tg-1',
        baseBranch: 'main',
        services: const ServiceBundle(),
        cancel: CancelToken(),
      );
      expect(ctx.services, isA<ServiceBundle>());
      expect(ctx.cancel, isA<CancelToken>());
      expect(ctx.logFile, isNull);
    });
  });
}
