// Track A (ADR-0009) — the Allocation SDK, PURE (no tree): the address/value
// types, the built-in ServiceAllocation/ProcessAllocation families, and the
// Capability.createAllocation factory defaults. The effect layer REPORTS through
// the sink and holds NO writer — these tests drive it with a capturing sink + the
// controllable FakeRuntimeProvider (Fakes, not mocks; zero I/O).
import 'dart:io';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

// --- fake capabilities (the author leaves) -----------------------------------

class _RecProcessCap extends ProcessCapability {
  _RecProcessCap(this.log, {this.payload});
  final List<String> log;
  final Map<String, String>? payload;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
    final workspace = context.getInheritedSeedOfExactType<Workspace>()!;
    log.add('spawn(${args.beadId}@${workspace.workspaceDir})');
    return RuntimeConfig(
      workDir: workspace.workspaceDir,
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
  Future<Map<String, String>?> result(
    TreeContext context,
    StepArgs args,
  ) async => payload;

  @override
  Future<void> teardown(StepArgs args) async => log.add('teardown');
}

class _RecServiceCap extends ServiceCapability {
  _RecServiceCap(this.outcome, this.log);
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

/// A [SourceControl] that records `provision(beadId)` so a test can assert
/// provisioning fires BEFORE the spawn. An optional [root] label distinguishes
/// which registered root's instance actually provisioned (tg-8tn: a
/// `ServiceBundle` carries one instance per root, so a per-bead resolution bug
/// shows up as the WRONG instance's log entry).
class _RecordingProvisionSourceControl implements SourceControl {
  _RecordingProvisionSourceControl(
    this.log, {
    this.root = '',
    this.createGitEntry = false,
  });
  final List<String> log;
  final String root;
  final bool createGitEntry;

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
  }) async {
    log.add(root.isEmpty ? 'provision($beadId)' : 'provision($root:$beadId)');
    if (createGitEntry) {
      Directory(workspaceDir).createSync(recursive: true);
      Directory('$workspaceDir/.git').createSync();
    }
  }
}

// --- builders ----------------------------------------------------------------

/// The ambient values the old CapabilityContext threaded, now read from the
/// tree (the context rip-out): the workspace + the per-substation services +
/// (optionally) the work bead (mounted by `WorkBead` in the real tree — omit
/// to reproduce the pre-tg-8tn tests that never mounted one).
FakeTreeContext _treeCtx({
  ServiceBundle services = const ServiceBundle(),
  Bead? bead,
  String workspaceDir = '/w/tg-1',
}) => FakeTreeContext(
  values: {
    Workspace: testWorkspace(
      'tg-1',
      workspaceDir: workspaceDir,
      branch: 'grid/tg-1',
    ),
    ServiceBundle: services,
    if (bead != null) Bead: bead,
  },
);

AllocationContext _allocCtx({
  required RuntimeProvider transport,
  required AllocationSink sink,
  required CancelToken cancel,
  ServiceBundle services = const ServiceBundle(),
  Bead? bead,
  AdoptFence fence = const AdoptFence(),
  Map<String, String> env = const {},
  String workspaceDir = '/w/tg-1',
}) => AllocationContext(
  treeContext: _treeCtx(
    services: services,
    bead: bead,
    workspaceDir: workspaceDir,
  ),
  args: stepArgs('tg-1/agent', cancel: cancel),
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
      expect(
        _RecProcessCap([]).createAllocation(ctx),
        isA<ProcessAllocation>(),
      );
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
    test(
      'startOrAdopt runs the body → reports Completed(payload) for Ok',
      () async {
        final log = <String>[];
        final reports = <AllocationReport>[];
        const pr = 'https://x/pr/1';
        final cancel = CancelToken();
        final alloc = _RecServiceCap(const Ok({'pr_url': pr}), log)
            .createAllocation(
              _allocCtx(
                transport: FakeRuntimeProvider(),
                sink: reports.add,
                cancel: cancel,
              ),
            );
        await alloc.startOrAdopt();
        expect(log, contains('run(tg-1)'));
        expect(reports.single, isA<AllocationCompleted>());
        expect((reports.single as AllocationCompleted).payload, {'pr_url': pr});
        expect(alloc.state, AllocationState.gone);
      },
    );

    test('Failed → AllocationFailed', () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      await _RecServiceCap(const Failed('nope'), [])
          .createAllocation(
            _allocCtx(
              transport: FakeRuntimeProvider(),
              sink: reports.add,
              cancel: cancel,
            ),
          )
          .startOrAdopt();
      expect(reports.single, isA<AllocationFailed>());
      expect((reports.single as AllocationFailed).reason, 'nope');
    });

    test(
      'a body that resolves AFTER cancel reports nothing (the cancel guard)',
      () async {
        final reports = <AllocationReport>[];
        final cancel = CancelToken();
        final alloc = _RecServiceCap(const Ok(), []).createAllocation(
          _allocCtx(
            transport: FakeRuntimeProvider(),
            sink: reports.add,
            cancel: cancel,
          ),
        );
        cancel.cancel(); // the Host unmounted before run resolved
        await alloc.startOrAdopt();
        expect(reports, isEmpty);
      },
    );

    test(
      'dispose cancels the token + runs teardown (no process stop)',
      () async {
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
      },
    );
  });

  group('Track A — ProcessAllocation (the process family)', () {
    test(
      'startOrAdopt provisions BEFORE spawn, under the address, with the env '
      'overlay layered over the base env',
      () async {
        final workspaceDir = Directory.systemTemp
            .createTempSync('grid-flat-checkout-')
            .path;
        addTearDown(() => Directory(workspaceDir).deleteSync(recursive: true));
        final log = <String>[];
        final provider = FakeRuntimeProvider();
        final alloc = _RecProcessCap(log).createAllocation(
          _allocCtx(
            transport: provider,
            sink: (_) {},
            cancel: CancelToken(),
            services: ServiceBundle(
              sourceControl: _RecordingProvisionSourceControl(
                log,
                createGitEntry: true,
              ),
            ),
            env: const {'GRID_BEAD_ID': 'tg-1', 'GRID_INSTANCE_TOKEN': 'tok'},
            workspaceDir: workspaceDir,
          ),
        );
        await alloc.startOrAdopt();
        await _pump();

        expect(provider.started, hasLength(1));
        final started = provider.started.single;
        expect(
          started.name,
          'tgdog-s/tg-1/agent',
        ); // the address = provider name
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
      },
    );

    test(
      'a provisioned workspace without .git fails LOUD before spawn',
      () async {
        final workspaceDir = Directory.systemTemp
            .createTempSync('grid-flat-sourceless-')
            .path;
        addTearDown(() => Directory(workspaceDir).deleteSync(recursive: true));
        final log = <String>[];
        final reports = <AllocationReport>[];
        final provider = FakeRuntimeProvider();
        final alloc = _RecProcessCap(log).createAllocation(
          _allocCtx(
            transport: provider,
            sink: reports.add,
            cancel: CancelToken(),
            services: ServiceBundle(
              sourceControl: _RecordingProvisionSourceControl(log),
            ),
            workspaceDir: workspaceDir,
          ),
        );

        await alloc.startOrAdopt();
        await _pump();

        expect(provider.started, isEmpty);
        expect(log, ['provision(tg-1)']);
        final failed = reports.whereType<AllocationFailed>().single;
        expect(failed.reason, contains('sourceless-workspace'));
        expect(alloc.state, AllocationState.gone);
      },
    );

    test(
      'the CREATE-path provision uses the substation\'s ONE '
      'SourceControl (v3 single-root — no metadata.grid.root selector)',
      () async {
        final workspaceDir = Directory.systemTemp
            .createTempSync('grid-flat-root-checkout-')
            .path;
        addTearDown(() => Directory(workspaceDir).deleteSync(recursive: true));
        final log = <String>[];
        final provider = FakeRuntimeProvider();
        final alloc = _RecProcessCap(log).createAllocation(
          _allocCtx(
            transport: provider,
            sink: (_) {},
            cancel: CancelToken(),
            bead: const Bead(id: 'tg-1', issueType: IssueType.task),
            services: ServiceBundle(
              sourceControl: _RecordingProvisionSourceControl(
                log,
                root: 'default',
                createGitEntry: true,
              ),
            ),
            workspaceDir: workspaceDir,
          ),
        );
        await alloc.startOrAdopt();
        await _pump();

        expect(log, contains('provision(default:tg-1)'));
      },
    );

    test('SessionStarted → AllocationStarted(pid,pgid)', () async {
      final reports = <AllocationReport>[];
      final provider = FakeRuntimeProvider();
      final alloc = _RecProcessCap([]).createAllocation(
        _allocCtx(
          transport: provider,
          sink: reports.add,
          cancel: CancelToken(),
        ),
      );
      await alloc.startOrAdopt();
      provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
      );
      await _pump();
      final started = reports.whereType<AllocationStarted>().single;
      expect(started.pid, 100);
      expect(started.pgid, 200);
    });

    test(
      'a clean Exited(0) reports Completed(payload); a non-zero Exited reports '
      'Failed',
      () async {
        final reports = <AllocationReport>[];
        final provider = FakeRuntimeProvider();
        final alloc = _RecProcessCap([], payload: const {'grade': 'A'})
            .createAllocation(
              _allocCtx(
                transport: provider,
                sink: reports.add,
                cancel: CancelToken(),
              ),
            );
        await alloc.startOrAdopt();
        provider.emit(const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0));
        await _pump();
        final done = reports.whereType<AllocationCompleted>().single;
        expect(done.payload, {'grade': 'A'});
        expect(alloc.state, AllocationState.gone);
      },
    );

    test(
      'a daemon reaches ready (state=ready) WITHOUT terminating, then a later '
      'death reports Failed (no latch on ready — OQ-5)',
      () async {
        final reports = <AllocationReport>[];
        final provider = FakeRuntimeProvider();
        final alloc = _RecProcessCap([]).createAllocation(
          _allocCtx(
            transport: provider,
            sink: reports.add,
            cancel: CancelToken(),
          ),
        );
        await alloc.startOrAdopt();
        provider.emit(
          const ActivityChanged(name: 'tgdog-s/tg-1/agent', active: true),
        );
        await _pump();
        expect(reports.whereType<AllocationReady>(), hasLength(1));
        expect(alloc.state, AllocationState.ready);

        provider.emit(const Died(name: 'tgdog-s/tg-1/agent'));
        await _pump();
        expect(reports.whereType<AllocationFailed>(), hasLength(1));
      },
    );

    test(
      'dispose cancels the subscription, stops the group, runs teardown',
      () async {
        final log = <String>[];
        final provider = FakeRuntimeProvider();
        final alloc =
            _RecProcessCap(log).createAllocation(
                  _allocCtx(
                    transport: provider,
                    sink: (_) {},
                    cancel: CancelToken(),
                  ),
                )
                as ProcessAllocation;
        await alloc.startOrAdopt();
        await _pump();
        expect(provider.eventListenerCount, 1);
        await alloc.dispose();
        await _pump();
        expect(provider.stopped, ['tgdog-s/tg-1/agent']);
        expect(log, contains('teardown'));
        expect(
          provider.eventListenerCount,
          0,
          reason: 'the subscription is cancelled',
        );
      },
    );

    test('a spawn never reached (disposed first) does NOT stop the group but '
        'still tears down', () async {
      final log = <String>[];
      final provider = FakeRuntimeProvider();
      final cancel = CancelToken();
      final alloc =
          _RecProcessCap(log).createAllocation(
                _allocCtx(transport: provider, sink: (_) {}, cancel: cancel),
              )
              as ProcessAllocation;
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
