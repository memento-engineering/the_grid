// THE COMPLETION FENCE: an INFERRED one-shot exit (a detached agent's vanish) is
// read as a completion ONLY when (a) the capability DECLARED the commit contract
// and (b) the work signal proves its workspace clean. A murdered coding agent
// (uncommitted work left behind) routes to supervision and RESPAWNS the step — it
// never advances the circuit to review. A CRITIC — which finishes by WRITING an
// uncommitted verdict — is NEVER fenced. Zero I/O: fakes + an injected
// work-signal probe.
import 'dart:async';
import 'dart:io';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

/// THE CODING AGENT: its working agreement is "commit your work in the worktree",
/// so it DECLARES the commit contract and its inferred completions are fenced.
/// Contributes a result payload, so a test can prove the fence never reads
/// `result` for an interrupted turn.
class _AgentCap extends ProcessCapability {
  _AgentCap(this.log);
  final List<String> log;

  @override
  CompletionContract get completionContract =>
      CompletionContract.committedWorkspace;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'do the work'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>?> result(TreeContext context, StepArgs args) async {
    log.add('result');
    return {'grade': 'A'};
  }
}

/// A COMMITTEE CRITIC: a one-shot that finishes by WRITING its verdict
/// (`.grid/critique/<rubric>.json`) and vanishing. It has NO commit obligation, so
/// it declares NO contract (the default) and must NEVER be fenced on worktree
/// dirtiness — that is the wedge.
class _CriticCap extends ProcessCapability {
  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
    workDir: '/w/tg-1',
    command: 'sh',
    args: ['-c', 'grade the diff'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// A daemon: `Exited` is a DEATH, never a completion — the signal-scoping control.
class _DaemonCap extends ProcessCapability {
  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => const RuntimeConfig(
    workDir: '/w/tg-1',
    command: 'sh',
    args: ['-c', 'sleep 999'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    ActivityChanged(:final active) when active => StepSignal.ready,
    Died() || Exited() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// A minimal ambient [SourceControl] — its PRESENCE is what arms the fence (the
/// tree has a real workspace); the fence's actual verdict comes from the injected
/// probe. It provisions only — delivery is the substation's bound method (M5
/// D-4a), and this fake binds none. Provisioning MATERIALIZES a `.git` marker
/// under [root] — the post-provision guard ([assertProvisionedCheckout], bead
/// tg-6jn) gives "provisioned" a checkable meaning; direct-allocation tests
/// that never provision keep the synthetic `/w` root.
class _FakeSourceControl implements SourceControl {
  _FakeSourceControl(this.root);
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
    Directory('$workspaceDir/.git').createSync(recursive: true);
  }
}

/// A recording work-signal probe returning a programmed [outcome] (or throwing),
/// with an optional [onCall] hook so a test can cancel MID-probe.
class _Probe {
  _Probe(this.outcome, {this.throws = false, this.onCall});
  final GateOutcome outcome;
  final bool throws;
  final void Function()? onCall;
  final List<String> calls = [];

  Future<GateOutcome> call(String workspaceDir) async {
    calls.add(workspaceDir);
    await Future<void>.delayed(Duration.zero);
    onCall?.call();
    if (throws) throw StateError('git is on fire');
    return outcome;
  }
}

const _inferredExit = Exited(
  name: 'tgdog-s/tg-1/agent',
  exitCode: 0,
  inferred: true,
);
const _observedExit = Exited(name: 'tgdog-s/tg-1/agent', exitCode: 0);

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AllocationContext _ctx({
  required AllocationSink sink,
  required CancelToken cancel,
  WorkSignalProbe? workSignal,
  bool withWorkspace = true,
  bool withSourceControl = true,
  StepKind kind = StepKind.job,
  Duration workSignalTimeout = kWorkSignalTimeout,
}) => AllocationContext(
  treeContext: FakeTreeContext(
    values: {
      ServiceBundle: withSourceControl
          ? ServiceBundle(sourceControl: _FakeSourceControl('/w'))
          : const ServiceBundle(),
      if (withWorkspace)
        Workspace: testWorkspace('tg-1', workspaceDir: '/w/tg-1'),
    },
  ),
  args: stepArgs('tg-1/agent', cancel: cancel),
  transport: FakeRuntimeProvider(),
  address: const AllocationAddress('tgdog-s', 'tg-1/agent'),
  env: const {},
  sink: sink,
  kind: kind,
  workSignal: workSignal ?? noWorkSignal,
  workSignalTimeout: workSignalTimeout,
);

void main() {
  group('the completion fence — an INFERRED exit is proven, never assumed', () {
    test('THE BUG: a fenced agent vanishing with UNCOMMITTED work → '
        'AllocationFailed (the step respawns), never a completion, and `result` '
        'is never read', () async {
      final reports = <AllocationReport>[];
      final log = <String>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _AgentCap(log).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, ['/w/tg-1'], reason: 'the fenced workspace is probed');
      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      final failed = reports.whereType<AllocationFailed>().toList();
      expect(failed, hasLength(1));
      expect(failed.single.reason, contains('interrupted'));
      expect(failed.single.reason, contains('UNCOMMITTED'));
      expect(
        log,
        isNot(contains('result')),
        reason: 'an interrupted turn has no result to read',
      );
    });

    test('THE CONTROL: a genuinely-CLEAN fenced vanish still ADVANCES '
        '(completed, with its result payload)', () async {
      final reports = <AllocationReport>[];
      final log = <String>[];
      final probe = _Probe(GateOutcome.clear);
      final alloc =
          _AgentCap(log).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, hasLength(1));
      expect(reports.whereType<AllocationFailed>(), isEmpty);
      final done = reports.whereType<AllocationCompleted>().toList();
      expect(done, hasLength(1));
      expect(done.single.payload, {'grade': 'A'});
      expect(log, contains('result'));
    });

    test('FAIL CLOSED: a probeError workspace is not a proven completion '
        '(ADR-0006 D3)', () async {
      final reports = <AllocationReport>[];
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: _Probe(GateOutcome.probeError).call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      expect(
        reports.whereType<AllocationFailed>().single.reason,
        contains('probe error'),
      );
    });

    test('FAIL CLOSED: a THROWING probe routes to supervision (never an '
        'unhandled zone error, never a stuck node)', () async {
      final reports = <AllocationReport>[];
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: _Probe(GateOutcome.clear, throws: true).call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      expect(
        reports.whereType<AllocationFailed>().single.reason,
        contains('probe threw'),
      );
    });

    test('BOUNDED: a HUNG probe fails closed instead of stalling the step '
        'forever (never a silently stuck node)', () async {
      final reports = <AllocationReport>[];
      // A probe that NEVER completes — a wedged `git status` (an index lock, a
      // stalled network FS). Without the timeout the node latches terminal and
      // reports NOTHING, forever: supervision cannot see it, and the work is lost.
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: (_) => Completer<GateOutcome>().future,
                  workSignalTimeout: const Duration(milliseconds: 20),
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(reports.whereType<AllocationCompleted>(), isEmpty);
      expect(
        reports.whereType<AllocationFailed>().single.reason,
        contains('probe error'),
        reason: 'a hung probe is an UNREADABLE workspace — fail closed, respawn',
      );
    });

    test('the production timeout default is armed (a fence with no explicit '
        'timeout is still bounded)', () {
      expect(
        AllocationContext(
          treeContext: FakeTreeContext(),
          args: stepArgs('tg-1/agent'),
          transport: FakeRuntimeProvider(),
          address: const AllocationAddress('tgdog-s', 'tg-1/agent'),
          env: const {},
          sink: (_) {},
        ).workSignalTimeout,
        kWorkSignalTimeout,
      );
    });

    test('THE LATCH: a RE-FIRED inferred exit probes ONCE and reports ONCE',
        () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.clear);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      alloc.deliverEventForTest(_inferredExit); // the stream re-fires
      await _pump();

      expect(probe.calls, hasLength(1), reason: 'the terminal latched at entry');
      expect(reports, hasLength(1));
    });
  });

  group('THE WEDGE — the fence is PER-CAPABILITY, not per-one-shot', () {
    test('a CRITIC (no commit contract) vanishing over a DIRTY workspace still '
        'COMPLETES — and is never probed', () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _CriticCap().createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(
        probe.calls,
        isEmpty,
        reason: 'a critic writes an uncommitted verdict and vanishes — by design',
      );
      expect(reports.whereType<AllocationFailed>(), isEmpty);
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });

    test('the DEFAULT contract is `none` (an un-declaring capability is '
        'unfenced)', () {
      expect(_CriticCap().completionContract, CompletionContract.none);
      expect(
        _AgentCap([]).completionContract,
        CompletionContract.committedWorkspace,
      );
    });
  });

  group('the fence DISARMS when the two seams disagree (fail-SAFE)', () {
    test('no ambient SourceControl (SessionScope mounts a SYNTHETIC workspace '
        'path) → no probe, the inferred exit stands', () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                  withSourceControl: false,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(
        probe.calls,
        isEmpty,
        reason: 'never fence a workspace we cannot even address',
      );
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });

    test('no ambient Workspace (a bare composition) → no probe', () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                  withWorkspace: false,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, isEmpty);
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });

    test('the DEFAULT seam (noWorkSignal) fences nothing — an unwired station '
        'behaves exactly as today', () async {
      final reports = <AllocationReport>[];
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(sink: reports.add, cancel: CancelToken()),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });
  });

  group('the fence is SCOPED to the heuristic (it is not a general gate)', () {
    test('an OBSERVED Exited(0) completes even with a DIRTY workspace — the '
        'probe is never called', () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_observedExit);
      await _pump();

      expect(probe.calls, isEmpty, reason: 'an observed exit needs no proof');
      expect(reports.whereType<AllocationCompleted>(), hasLength(1));
    });

    test('a non-completion signal (a daemon reading Exited as a DEATH) is never '
        'fenced', () async {
      final reports = <AllocationReport>[];
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _DaemonCap().createAllocation(
                _ctx(
                  sink: reports.add,
                  cancel: CancelToken(),
                  workSignal: probe.call,
                  kind: StepKind.daemon,
                ),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, isEmpty);
      expect(reports.whereType<AllocationFailed>(), hasLength(1));
    });
  });

  group('the three CANCEL guards — a disposed node never reports', () {
    test('cancelled BEFORE the probe → no probe, no report', () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      final probe = _Probe(GateOutcome.present);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(sink: reports.add, cancel: cancel, workSignal: probe.call),
              )
              as ProcessAllocation;

      cancel.cancel();
      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, isEmpty);
      expect(reports, isEmpty);
    });

    test('cancelled DURING the probe → no report', () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      final probe = _Probe(GateOutcome.present, onCall: cancel.cancel);
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(sink: reports.add, cancel: cancel, workSignal: probe.call),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(probe.calls, hasLength(1));
      expect(reports, isEmpty);
    });

    test('cancelled during a THROWING probe → no report', () async {
      final reports = <AllocationReport>[];
      final cancel = CancelToken();
      final probe = _Probe(
        GateOutcome.clear,
        throws: true,
        onCall: cancel.cancel,
      );
      final alloc =
          _AgentCap([]).createAllocation(
                _ctx(sink: reports.add, cancel: cancel, workSignal: probe.call),
              )
              as ProcessAllocation;

      alloc.deliverEventForTest(_inferredExit);
      await _pump();

      expect(reports, isEmpty);
    });
  });

  group('AT DEPTH — the real CapabilityHost + the one chokepoint', () {
    const circuit = Circuit(
      id: 'code',
      terminalStepId: 'land',
      steps: [
        CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
        CapabilityStep(
          stepId: 'verify',
          capabilityId: 'verify',
          dependsOn: {'agent'},
        ),
        CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
      ],
    );
    final clock = DateTime(2026);

    ({TreeOwner owner, Fakes fakes}) host(
      WorkSignalProbe probe, {
      bool withSourceControl = true,
    }) {
      // AT DEPTH the REAL host provisions before spawning, and the
      // post-provision guard (bead tg-6jn) checks the result on disk — so
      // this harness roots the workspace at a REAL temp dir the fake
      // provisions into (the direct-allocation tests above never provision
      // and keep their synthetic paths).
      final root = Directory.systemTemp.createTempSync('fence-depth-');
      addTearDown(() => root.deleteSync(recursive: true));
      final sc = _FakeSourceControl(root.path);
      final fakes = buildFakes(workSignal: probe);
      final owner = TreeOwner();
      owner.mountRoot(
        InheritedSeed<StationServices>(
          value: fakes.ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(clock: clock),
            child: InheritedSeed<ServiceBundle>(
              value: withSourceControl
                  ? ServiceBundle(sourceControl: sc)
                  : const ServiceBundle(),
              child: InheritedSeed<Workspace>(
                value: testWorkspace(
                  'tg-1',
                  workspaceDir: sc.workspaceFor('tg-1'),
                ),
                child: CapabilityHost(
                  capability: _AgentCap([]),
                  mount: const StepMount(
                    step: CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
                    nodePath: 'tg-1/agent',
                    circuit: circuit,
                    circuitPath: 'tg-1',
                    session: SessionHandle('tgdog-s'),
                    node: NodeCursor(),
                    key: ValueKey('tg-1/agent#0.0'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return (owner: owner, fakes: fakes);
    }

    test('an INTERRUPTED vanish writes the SUPERVISED failure through the ONE '
        'chokepoint — never state=complete — and review does NOT advance',
        () async {
      final h = host(_Probe(GateOutcome.present).call);
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(_inferredExit);
      await _pump();

      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.cursor.tg-1/agent.state'], 'failed');
      expect(meta['grid.cursor.tg-1/agent.restartCount'], '1');
      // Within budget → a backoff cooldown → the node RE-KEYS and RESPAWNS.
      expect(
        meta['grid.cursor.tg-1/agent.cooldownUntil'],
        clock.add(const Duration(seconds: 1)).toIso8601String(),
      );
      expect(
        meta['grid.cursor.tg-1/agent.failureReason'],
        contains('interrupted'),
      );
      // The whole point: the cursor NEVER says complete.
      expect(
        h.fakes.runner.callsFor('update').join(' '),
        isNot(contains('complete')),
      );
      // ...so the dependent `verify` step is still withheld by the frontier — the
      // circuit did not advance to review over a broken tree.
      expect(
        depsSatisfied(
          circuit,
          circuit.stepById('verify')!,
          const {
            'tg-1/agent': NodeCursor(state: StepState.failed, restartCount: 1),
          },
          'tg-1',
          circuitById: (_) => null,
        ),
        isFalse,
      );
    });

    test('CONTROL at depth: a CLEAN vanish writes state=complete (review '
        'advances exactly as before)', () async {
      final h = host(_Probe(GateOutcome.clear).call);
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(_inferredExit);
      await _pump();

      expect(
        h.fakes.runner.metadataOfUpdate(0)['grid.cursor.tg-1/agent.state'],
        'complete',
      );
      expect(
        depsSatisfied(
          circuit,
          circuit.stepById('verify')!,
          const {'tg-1/agent': NodeCursor(state: StepState.complete)},
          'tg-1',
          circuitById: (_) => null,
        ),
        isTrue,
      );
    });

    test('FAIL-SAFE at depth: with NO SourceControl the fence disarms — a DIRTY '
        'probe still writes state=complete (a bare composition never wedges)',
        () async {
      final h = host(
        _Probe(GateOutcome.present).call,
        withSourceControl: false,
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      h.fakes.provider.emit(_inferredExit);
      await _pump();

      expect(
        h.fakes.runner.metadataOfUpdate(0)['grid.cursor.tg-1/agent.state'],
        'complete',
      );
    });
  });
}
