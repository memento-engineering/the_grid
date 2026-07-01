// Track C (ADR-0009 D4/D6) — the process family: daemon adopt-or-respawn +
// detach + no-adopt-on-faith, one-shot respawn-or-skip (never adopts/detaches).
// PURE (no tree): drives ProcessAllocation with a fake daemon capability + the
// controllable FakeRuntimeProvider + an injectable liveness seam. Zero I/O; the
// live cross-process output re-wire is the deferred adopt-a-live-process piece
// (ADR-0008 D6) — what's proven here is the adopt DECISION + not double-spawning.
import 'dart:async';

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// A daemon-style process capability: `ready` when up, `failed` on death, and a
/// programmable [fresh] endpoint/token proof (the domain half of adopt).
class _DaemonCap extends ProcessCapability {
  _DaemonCap({this.fresh = false, List<String>? log}) : log = log ?? [];
  final bool fresh;
  final List<String> log;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) {
    log.add('spawn');
    return RuntimeConfig(
      workDir: ctx.workspaceDir,
      command: 'sh',
      args: const ['-c', 'sleep 999'],
      lifecycle: Lifecycle.oneTurn,
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when active => StepSignal.ready,
    Died() || Exited() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<bool> proveFreshness(AdoptFence fence, CapabilityContext ctx) async {
    log.add('proveFreshness');
    return fresh;
  }

  @override
  Future<void> teardown(CapabilityContext ctx) async => log.add('teardown');
}

/// A one-shot (job) process capability — must NEVER adopt or detach.
class _JobCap extends ProcessCapability {
  _JobCap({List<String>? log}) : log = log ?? [];
  final List<String> log;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) {
    log.add('spawn');
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
  Future<bool> proveFreshness(AdoptFence fence, CapabilityContext ctx) async {
    // Even if a job somehow "proves fresh", it must not adopt (isAdoptable is
    // false for a job) — this makes the guard non-vacuous.
    log.add('proveFreshness');
    return true;
  }
}

CapabilityContext _capCtx(CancelToken cancel) => CapabilityContext(
  params: const {},
  bead: bead('tg-1'),
  workspaceDir: '/w/tg-1',
  branch: 'grid/tg-1',
  baseBranch: 'main',
  services: const ServiceBundle(),
  cancel: cancel,
  nodePath: 'tg-1/harness',
);

AllocationContext _ctx({
  required RuntimeProvider transport,
  required AllocationSink sink,
  required CancelToken cancel,
  StepKind kind = StepKind.daemon,
  bool live = true,
  AdoptFence fence = const AdoptFence(pgid: 200, pid: 201, token: 't'),
}) => AllocationContext(
  capContext: _capCtx(cancel),
  transport: transport,
  address: const AllocationAddress('tgdog-s', 'tg-1/harness'),
  env: const {},
  sink: sink,
  fence: fence,
  kind: kind,
  liveness: (_) => live,
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Track C — kind drives adoptability/detachability (D4)', () {
    test('a daemon is adoptable + detachable; a job is neither', () {
      final provider = FakeRuntimeProvider();
      final daemon = _DaemonCap().createAllocation(
        _ctx(transport: provider, sink: (_) {}, cancel: CancelToken()),
      );
      final job = _JobCap().createAllocation(
        _ctx(
          transport: provider,
          sink: (_) {},
          cancel: CancelToken(),
          kind: StepKind.job,
        ),
      );
      expect(daemon.isAdoptable, isTrue);
      expect(daemon.isDetachable, isTrue);
      expect(job.isAdoptable, isFalse);
      expect(job.isDetachable, isFalse);
    });
  });

  group('Track C — daemon adopt-or-respawn (no-adopt-on-faith, D4/D5)', () {
    test('a proven-fresh survivor (liveness ∧ endpoint proof) is ADOPTED — '
        'reattached, NOT respawned, surfaced ready', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap(fresh: true);
      final alloc = cap.createAllocation(
        _ctx(transport: provider, sink: reports.add, cancel: CancelToken()),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();

      expect(alloc.adopted, isTrue);
      expect(provider.started, isEmpty, reason: 'adopt must NOT respawn');
      expect(cap.log, isNot(contains('spawn')));
      expect(reports.whereType<AllocationReady>(), hasLength(1));
      expect(alloc.state, AllocationState.ready);
    });

    test('the ENGINE liveness half failing → spawn fresh (no-adopt-on-faith)',
        () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap(fresh: true); // endpoint proof would pass...
      final alloc = cap.createAllocation(
        _ctx(
          transport: provider,
          sink: (_) {},
          cancel: CancelToken(),
          live: false, // ...but the pgid is not live → must respawn.
        ),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      expect(alloc.adopted, isFalse);
      expect(provider.started, hasLength(1), reason: 'respawned fresh');
    });

    test('the CAPABILITY endpoint/token proof failing → spawn fresh', () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap(fresh: false); // endpoint proof fails
      final alloc = cap.createAllocation(
        _ctx(transport: provider, sink: (_) {}, cancel: CancelToken(), live: true),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      expect(alloc.adopted, isFalse);
      expect(provider.started, hasLength(1), reason: 'respawned fresh');
    });

    test('no prior identity (fresh node) → spawn fresh, no proof attempted',
        () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap(fresh: true);
      final alloc = cap.createAllocation(
        _ctx(
          transport: provider,
          sink: (_) {},
          cancel: CancelToken(),
          fence: const AdoptFence(), // nothing to adopt
        ),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      expect(alloc.adopted, isFalse);
      expect(provider.started, hasLength(1));
      expect(cap.log, isNot(contains('proveFreshness')));
    });

    test('a JOB never adopts even when everything would prove fresh (respawn-or-'
        'skip is the one-shot contract)', () async {
      final provider = FakeRuntimeProvider();
      final cap = _JobCap();
      final alloc = cap.createAllocation(
        _ctx(
          transport: provider,
          sink: (_) {},
          cancel: CancelToken(),
          kind: StepKind.job,
          live: true,
        ),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      expect(alloc.adopted, isFalse);
      expect(provider.started, hasLength(1));
      expect(cap.log, isNot(contains('proveFreshness')),
          reason: 'a job short-circuits before the proof (isAdoptable=false)');
    });
  });

  group('Track C — detach vs dispose (distinct verbs, D4)', () {
    test('detach LEAVES the spawned group running (never stops it, no teardown)',
        () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap();
      final alloc = cap.createAllocation(
        _ctx(transport: provider, sink: (_) {}, cancel: CancelToken(), live: false),
      ) as ProcessAllocation;
      await alloc.startOrAdopt(); // spawns (not fresh)
      await _pump();
      expect(provider.started, hasLength(1));
      expect(provider.eventListenerCount, 1);

      await alloc.detach();
      await _pump();
      expect(provider.stopped, isEmpty, reason: 'detach never stops the group');
      expect(cap.log, isNot(contains('teardown')),
          reason: 'detach does not tear down side-processes');
      expect(provider.eventListenerCount, 0, reason: 'stops observing though');
    });

    test('dispose KILLS the spawned group + tears down (the floor)', () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap();
      final alloc = cap.createAllocation(
        _ctx(transport: provider, sink: (_) {}, cancel: CancelToken(), live: false),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      await alloc.dispose();
      expect(provider.stopped, ['tgdog-s/tg-1/harness']);
      expect(cap.log, contains('teardown'));
    });

    test('dispose KILLS an ADOPTED survivor too (adopt then kill)', () async {
      final provider = FakeRuntimeProvider();
      final cap = _DaemonCap(fresh: true);
      final alloc = cap.createAllocation(
        _ctx(transport: provider, sink: (_) {}, cancel: CancelToken(), live: true),
      ) as ProcessAllocation;
      await alloc.startOrAdopt(); // adopts
      await _pump();
      expect(alloc.adopted, isTrue);
      await alloc.dispose();
      expect(provider.stopped, ['tgdog-s/tg-1/harness'],
          reason: 'dispose kills the adopted group (via the stop-if-managing gate)');
    });
  });
}
