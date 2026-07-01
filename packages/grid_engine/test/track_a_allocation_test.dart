// Track A (ADR-0009) — the Allocation SDK, PURE (no tree): the address/value
// types, the built-in ServiceAllocation/ProcessAllocation families, and the
// Capability.createAllocation factory defaults. The effect layer REPORTS through
// the sink and holds NO writer — these tests drive it with a capturing sink + the
// controllable FakeRuntimeProvider (Fakes, not mocks; zero I/O).
import 'dart:async';

import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- fake capabilities (the author leaves) -----------------------------------

class _RecProcessCap extends ProcessCapability {
  _RecProcessCap(this.log, {this.payload});
  final List<String> log;
  final Map<String, String>? payload;

  @override
  RuntimeConfig spawn(CapabilityContext ctx) {
    log.add('spawn(${ctx.beadId}@${ctx.workspaceDir})');
    return RuntimeConfig(
      workDir: ctx.workspaceDir,
      command: 'sh',
      args: const ['-c', 'echo hi'],
      lifecycle: Lifecycle.oneTurn,
      env: const {'BASE': '1'},
    );
  }

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    ActivityChanged(:final active) when active => StepSignal.ready,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(CapabilityContext ctx) async => payload;

  @override
  Future<void> teardown(CapabilityContext ctx) async => log.add('teardown');
}

class _RecServiceCap extends ServiceCapability {
  _RecServiceCap(this.outcome, this.log);
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

/// A [SourceControl] that records `provision(beadId)` so a test can assert
/// provisioning fires BEFORE the spawn.
class _RecordingProvisionSourceControl implements SourceControl {
  _RecordingProvisionSourceControl(this.log);
  final List<String> log;

  @override
  bool get canLand => false;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async => log.add('provision($beadId)');

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) async {}
  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {}
  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async => null;
}

// --- builders ----------------------------------------------------------------

CapabilityContext _capCtx(CancelToken cancel, {ServiceBundle services = const ServiceBundle()}) =>
    CapabilityContext(
      params: const {},
      bead: bead('tg-1'),
      workspaceDir: '/w/tg-1',
      branch: 'grid/tg-1',
      baseBranch: 'main',
      services: services,
      cancel: cancel,
      nodePath: 'tg-1/agent',
    );

AllocationContext _allocCtx({
  required RuntimeProvider transport,
  required AllocationSink sink,
  required CancelToken cancel,
  ServiceBundle services = const ServiceBundle(),
  AdoptFence fence = const AdoptFence(),
  Map<String, String> env = const {},
}) => AllocationContext(
  capContext: _capCtx(cancel, services: services),
  transport: transport,
  address: const AllocationAddress('tgdog-s', 'tg-1/agent'),
  env: env,
  sink: sink,
  fence: fence,
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Track A — value types', () {
    test('AllocationAddress.providerName is <sessionId>/<nodePath>', () {
      const a = AllocationAddress('tgdog-s', 'tg-1/agent');
      expect(a.providerName, 'tgdog-s/tg-1/agent');
      expect(a.toString(), 'tgdog-s/tg-1/agent');
    });

    test('AllocationAddress has value equality + hashCode', () {
      const a = AllocationAddress('s', 'n');
      const b = AllocationAddress('s', 'n');
      const c = AllocationAddress('s', 'other');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('AdoptFence.hasIdentity is false only when all-null', () {
      expect(const AdoptFence().hasIdentity, isFalse);
      expect(const AdoptFence(pgid: 1).hasIdentity, isTrue);
      expect(const AdoptFence(token: 't').hasIdentity, isTrue);
    });
  });

  group('Track A — Capability.createAllocation defaults', () {
    test('ProcessCapability → ProcessAllocation; ServiceCapability → '
        'ServiceAllocation', () {
      final cancel = CancelToken();
      final ctx = _allocCtx(
        transport: FakeRuntimeProvider(),
        sink: (_) {},
        cancel: cancel,
      );
      expect(_RecProcessCap([]).createAllocation(ctx), isA<ProcessAllocation>());
      expect(
        _RecServiceCap(const Ok(), []).createAllocation(ctx),
        isA<ServiceAllocation>(),
      );
    });

    test('the base families are neither adoptable nor detachable, and never '
        'update in place (the P0 replace default)', () {
      final ctx = _allocCtx(
        transport: FakeRuntimeProvider(),
        sink: (_) {},
        cancel: CancelToken(),
      );
      final proc = _RecProcessCap([]).createAllocation(ctx);
      final svc = _RecServiceCap(const Ok(), []).createAllocation(ctx);
      for (final a in [proc, svc]) {
        expect(a.isAdoptable, isFalse);
        expect(a.isDetachable, isFalse);
        expect(a.canUpdate(a), isFalse);
      }
    });

    test('detach() on a non-detachable allocation throws (never an overloaded '
        'dispose — ADR-0009 D4)', () {
      final ctx = _allocCtx(
        transport: FakeRuntimeProvider(),
        sink: (_) {},
        cancel: CancelToken(),
      );
      final svc = _RecServiceCap(const Ok(), []).createAllocation(ctx);
      expect(svc.detach, throwsA(isA<UnsupportedError>()));
    });
  });

  group('Track A — ServiceAllocation (the JobAllocation convenience)', () {
    test('startOrAdopt runs the body → reports Completed(payload) for Ok', () async {
      final log = <String>[];
      final reports = <AllocationReport>[];
      const pr = 'https://x/pr/1';
      final cancel = CancelToken();
      final alloc = _RecServiceCap(const Ok({'pr_url': pr}), log).createAllocation(
        _allocCtx(transport: FakeRuntimeProvider(), sink: reports.add, cancel: cancel),
      );
      await alloc.startOrAdopt();
      expect(log, contains('run(tg-1)'));
      expect(reports.single, isA<AllocationCompleted>());
      expect((reports.single as AllocationCompleted).payload, {'pr_url': pr});
      expect(alloc.state, AllocationState.gone);
    });

    test('Failed → AllocationFailed; Gate → AllocationGated', () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      await _RecServiceCap(const Failed('nope'), [])
          .createAllocation(_allocCtx(
            transport: FakeRuntimeProvider(),
            sink: reports.add,
            cancel: cancel,
          ))
          .startOrAdopt();
      expect(reports.single, isA<AllocationFailed>());
      expect((reports.single as AllocationFailed).reason, 'nope');

      final gated = <AllocationReport>[];
      await _RecServiceCap(const Gate('block'), [])
          .createAllocation(_allocCtx(
            transport: FakeRuntimeProvider(),
            sink: gated.add,
            cancel: CancelToken(),
          ))
          .startOrAdopt();
      expect(gated.single, isA<AllocationGated>());
      expect((gated.single as AllocationGated).reason, 'block');
    });

    test('a body that resolves AFTER cancel reports nothing (the cancel guard)',
        () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      final alloc = _RecServiceCap(const Ok(), []).createAllocation(
        _allocCtx(transport: FakeRuntimeProvider(), sink: reports.add, cancel: cancel),
      );
      cancel.cancel(); // the Host unmounted before run resolved
      await alloc.startOrAdopt();
      expect(reports, isEmpty);
    });

    test('dispose cancels the token + runs teardown (no process stop)', () async {
      final log = <String>[];
      final provider = FakeRuntimeProvider();
      final cancel = CancelToken();
      final alloc = _RecServiceCap(const Ok(), log).createAllocation(
        _allocCtx(transport: provider, sink: (_) {}, cancel: cancel),
      );
      await alloc.startOrAdopt();
      await alloc.dispose();
      expect(cancel.isCancelled, isTrue);
      expect(log, contains('svc-teardown'));
      expect(provider.stopped, isEmpty); // a service is not a process
    });
  });

  group('Track A — ProcessAllocation (the process family)', () {
    test('startOrAdopt provisions BEFORE spawn, under the address, with the env '
        'overlay layered over the base env', () async {
      final log = <String>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap(log).createAllocation(
        _allocCtx(
          transport: provider,
          sink: (_) {},
          cancel: CancelToken(),
          services: ServiceBundle(
            sourceControl: _RecordingProvisionSourceControl(log),
          ),
          env: const {'GRID_BEAD_ID': 'tg-1', 'GRID_INSTANCE_TOKEN': 'tok'},
        ),
      );
      await alloc.startOrAdopt();
      await _pump();

      expect(provider.started, hasLength(1));
      final started = provider.started.single;
      expect(started.name, 'tgdog-s/tg-1/agent'); // the address = provider name
      expect(started.config.env['BASE'], '1'); // base env preserved
      expect(started.config.env['GRID_BEAD_ID'], 'tg-1'); // overlay merged
      expect(started.config.env['GRID_INSTANCE_TOKEN'], 'tok');
      expect(
        log.indexOf('provision(tg-1)') <
            log.indexWhere((l) => l.startsWith('spawn(')),
        isTrue,
        reason: 'provision must precede spawn',
      );
      expect(alloc.state, AllocationState.live);
    });

    test('SessionStarted → AllocationStarted(pid,pgid)', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap([]).createAllocation(
        _allocCtx(transport: provider, sink: reports.add, cancel: CancelToken()),
      );
      await alloc.startOrAdopt();
      provider.emit(const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200));
      await _pump();
      final started = reports.whereType<AllocationStarted>().single;
      expect(started.pid, 100);
      expect(started.pgid, 200);
    });

    test('a clean Exited(0) reports Completed(payload); a non-zero Exited reports '
        'Failed', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap([], payload: const {'grade': 'A'}).createAllocation(
        _allocCtx(transport: provider, sink: reports.add, cancel: CancelToken()),
      );
      await alloc.startOrAdopt();
      provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
      await _pump();
      final done = reports.whereType<AllocationCompleted>().single;
      expect(done.payload, {'grade': 'A'});
      expect(alloc.state, AllocationState.gone);
    });

    test('a daemon reaches ready (state=ready) WITHOUT terminating, then a later '
        'death reports Failed (no latch on ready — OQ-5)', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap([]).createAllocation(
        _allocCtx(transport: provider, sink: reports.add, cancel: CancelToken()),
      );
      await alloc.startOrAdopt();
      provider.emit(const ActivityChanged(name: 'tgdog-s/tg-1/agent', active: true));
      await _pump();
      expect(reports.whereType<AllocationReady>(), hasLength(1));
      expect(alloc.state, AllocationState.ready);

      provider.emit(const Died(name: 'tgdog-s/tg-1/agent'));
      await _pump();
      expect(reports.whereType<AllocationFailed>(), hasLength(1));
    });

    test('dispose cancels the subscription, stops the group, runs teardown',
        () async {
      final log = <String>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap(log).createAllocation(
        _allocCtx(transport: provider, sink: (_) {}, cancel: CancelToken()),
      ) as ProcessAllocation;
      await alloc.startOrAdopt();
      await _pump();
      expect(provider.eventListenerCount, 1);
      await alloc.dispose();
      await _pump();
      expect(provider.stopped, ['tgdog-s/tg-1/agent']);
      expect(log, contains('teardown'));
      expect(provider.eventListenerCount, 0, reason: 'the subscription is cancelled');
    });

    test('a spawn never reached (disposed first) does NOT stop the group but '
        'still tears down', () async {
      final log = <String>[];
      final provider = FakeRuntimeProvider();
      final cancel = CancelToken();
      final alloc = _RecProcessCap(log).createAllocation(
        _allocCtx(transport: provider, sink: (_) {}, cancel: cancel),
      ) as ProcessAllocation;
      // Cancel before startOrAdopt runs its body → the provision guard drops out
      // before the spawn.
      cancel.cancel();
      await alloc.startOrAdopt();
      await alloc.dispose();
      expect(provider.started, isEmpty, reason: 'the spawn was never reached');
      expect(provider.stopped, isEmpty, reason: 'no group to stop');
      expect(log, contains('teardown'));
    });
  });
}
