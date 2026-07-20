// pm6-r5b-host — CapabilityHost molecule targeting: the write fork
// (DESIGN-tg-pm6.md §11) + the R3 routing fork (tg-h4u).
//
// Every `_persistX` targets the step's OWN durable bead
// (`beadIdByNodePath[_nodePath]`), using the per-bead molecule metadata
// builders (`molecule_codec.dart`'s `stepBeadMetadata` — no `{nodePath}`
// infix, no `rewindCount`, no `grid.cursor.*` key). An ABSENT
// `InheritedCircuit` — a host mounted under an ADOPTED historical flat
// session — REFUSES LOUD at mount (tg-eli phase 2: the flat session-bead
// fallback retired with the flat model), proven in the legacy group below.
//
// THE ROUTING FORK (tg-h4u): a molecule-mode `ProcessCapability` no longer
// mounts a flat `ProcessAllocation` — `_createAllocationOrFlare` routes it
// through the ambient `ProcessLeaseVendor` (`leaseFor(request)` →
// `LeaseAllocation`), so the fake VENDOR's spawn/dispatch stand where the
// provider's event stream used to: the spawn surfaces `AllocationStarted`
// through the request's sink, and the dispatch is GATED behind an uncompleted
// Completer where a test must hold the incarnation at `running` (a
// `StepKind.job`'s immediate Ok would otherwise chain a SECOND terminal
// write in the same pump window — the round-3 committee's double-fire proof).
// A missing vendor is caught at MOUNT: flared `step.allocationFailed` +
// routed to a supervised failure (per-work fail-closed, ADR-0008 D10). A
// molecule circuit's `AllocationRewound` report is dead-code on
// `_persistRewind`'s write cascade (backward motion is derived, R4) and
// routes to a supervised failure instead.
//
// Zero I/O — Fakes throughout (a real TreeOwner-mounted tree + the recording
// bd runner + a controllable process transport), mirroring
// `track_e_capability_host_test.dart`'s harness shape.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// --- fake capabilities (mirrors track_e_capability_host_test.dart) ----------

class _RecordingProcessCap extends ProcessCapability {
  _RecordingProcessCap(this.log);
  final List<String> log;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) {
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
  _ServiceCap(this.outcome);
  final StepOutcome outcome;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;

  @override
  Future<void> teardown(StepArgs args) async {}
}

/// A daemon-style capability: signals `ready` when up (ActivityChanged), `failed`
/// on death — the same shape as track_e's own `_DaemonCap`.
class _DaemonCap extends ProcessCapability {
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
  Future<void> teardown(StepArgs args) async {}
}

class _ProvisionSourceControl implements SourceControl {
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
  }) async {}
}

Future<ProcessHandle> _neverSpawn(
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('spawn must not be called'));

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  ProcessLeaseRequest request,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

/// A vendor whose spawn surfaces [AllocationStarted] through the REQUEST's
/// sink (exactly what the real `stationProcessSpawner` does) and whose
/// dispatch is GATED behind [gate] — an uncompleted gate holds the
/// incarnation at `running` so a `StepKind.job`'s Ok cannot chain a second
/// terminal write into the same pump window (the round-3 double-fire fix).
SelfManagedProcessVendor _sinkingVendor(Completer<StepOutcome> gate) =>
    SelfManagedProcessVendor(
      spawn: (request, context, args) async {
        request.allocation.sink(const AllocationStarted(pid: 100, pgid: 200));
        return const ProcessHandle(pgid: 200, pid: 100, token: 'tok-h4u');
      },
      dispatch: (handle, request, context, args) => gate.future,
    );

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

StepMount _mount({String nodePath = 'tg-1/agent', int restartCount = 0}) =>
    StepMount(
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

/// A daemon-kind mount — the lease maps a daemon's Ok to `ready`
/// (non-latching) instead of a job's `complete` (tg-h4u routing tests).
StepMount _daemonMount({String nodePath = 'tg-1/agent'}) => StepMount(
  step: const CapabilityStep(
    stepId: 'agent',
    capabilityId: 'agent',
    kind: StepKind.daemon,
  ),
  nodePath: nodePath,
  circuit: _circuit,
  circuitPath: nodePath.contains('/')
      ? nodePath.substring(0, nodePath.lastIndexOf('/'))
      : '',
  session: const SessionHandle('tgdog-s'),
  node: const NodeCursor(),
  key: ValueKey('$nodePath#0.0'),
);

/// The fixed clock the host's backoff cooldown / telemetry is computed
/// against.
final _clock = DateTime(2026);

/// The step bead id [InheritedCircuit.beadIdByNodePath] resolves `tg-1/agent`
/// to across this suite.
const _stepBeadId = 'tgdog-step1';

/// An [InheritedCircuit] wired for `tg-1/agent` — a molecule session ambient
/// to the mounted host.
final _moleculeCircuit = InheritedCircuit(
  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
  beadIdByNodePath: const {'tg-1/agent': _stepBeadId},
  cursor: const {},
);

/// Records every LOUD flare the host emits (mirrors
/// `persist_never_crashes_test.dart`'s own recorder).
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

({TreeOwner owner, Branch root, Fakes fakes, _RecordingTransport transport})
_host(
  Capability cap, {
  InheritedCircuit? circuit,
  ProcessLeaseVendor? leaseVendor,
  EscalationHandler? escalation,
  StepMount? mount,
  SourceControl? sourceControl,
}) {
  final fakes = buildFakes();
  final owner = TreeOwner();
  final transport = _RecordingTransport();
  Seed tree = CapabilityHost(capability: cap, mount: mount ?? _mount());
  if (circuit != null) {
    tree = InheritedSeed<InheritedCircuit>(value: circuit, child: tree);
  }
  if (leaseVendor != null) {
    tree = InheritedSeed<ProcessLeaseVendor>(value: leaseVendor, child: tree);
  }
  final root = owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: _clock),
        child: InheritedSeed<ServiceBundle>(
          value: ServiceBundle(
            transport: transport,
            escalation: escalation,
            sourceControl: sourceControl,
          ),
          child: InheritedSeed<Workspace>(
            value: testWorkspace('tg-1'),
            child: tree,
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes, transport: transport);
}

void main() {
  group('molecule mode — every persist targets the STEP bead (R5b)', () {
    test(
      'SessionStarted targets the step bead: grid.step.state=running, no '
      'pgid/pid/token, no grid.cursor.* key (the vendor owns grid.lease.*). '
      'The spawn is routed through the VENDOR (leaseFor → LeaseAllocation, '
      'tg-h4u): its spawn sinks AllocationStarted; its dispatch stays GATED '
      'behind an uncompleted Completer, so a job Ok cannot chain a second '
      'terminal write into this pump window (the round-3 double-fire fix)',
      () async {
        final gate = Completer<StepOutcome>();
        final h = _host(
          _RecordingProcessCap(<String>[]),
          circuit: _moleculeCircuit,
          leaseVendor: _sinkingVendor(gate),
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        final updates = h.fakes.runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(
          updates.single[1],
          _stepBeadId,
          reason: 'the write targets the STEP bead, never the session bead',
        );
        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta['grid.step.state'], 'running');
        expect(meta['grid.step.restartCount'], '0');
        expect(
          meta.keys.where((k) => k.startsWith('grid.cursor.')),
          isEmpty,
          reason:
              'the molecule path never writes the flat grid.cursor.* '
              'namespace',
        );
        expect(
          meta.keys,
          isNot(anyOf(contains('grid.step.pgid'), contains('grid.step.pid'))),
          reason:
              'pgid/pid/token are vendor-owned (grid.lease.*), never the '
              "step bead's cursor keys",
        );
      },
    );

    test(
      'a daemon ready targets the step bead: grid.step.state=ready — routed '
      'through the vendor (a daemon Ok maps to AllocationReady, non-latching)',
      () async {
        // The daemon step: dispatch resolves Ok immediately — for a
        // StepKind.daemon the lease maps that to `ready` (never a latching
        // terminal), so ONE write lands and the effect stays live.
        final vendor = SelfManagedProcessVendor(
          spawn: (request, context, args) async =>
              const ProcessHandle(pgid: 200, pid: 100, token: 'tok-h4u'),
          dispatch: (handle, request, context, args) async => const Ok(),
        );
        final h = _host(
          _DaemonCap(),
          circuit: _moleculeCircuit,
          leaseVendor: vendor,
          mount: _daemonMount(),
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta['grid.step.state'], 'ready');
        expect(meta.keys.where((k) => k.startsWith('grid.cursor.')), isEmpty);
      },
    );

    test(
      'a clean completion targets the step bead, carrying the result payload '
      'under the SAME grid.result.<nodePath>.* namespace (ResultKeys reused '
      'VERBATIM — R1)',
      () async {
        const pr = 'https://github.com/acme/widget/pull/7';
        final h = _host(
          _ServiceCap(const Ok({'pr_url': pr})),
          circuit: _moleculeCircuit,
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta['grid.step.state'], 'complete');
        expect(meta['grid.result.tg-1/agent.pr_url'], pr);
        expect(meta.keys.where((k) => k.startsWith('grid.cursor.')), isEmpty);
        expect(
          meta.keys.where((k) => k.startsWith('grid.result.')),
          hasLength(1),
        );
      },
    );

    test('a supervised failure targets the step bead: state=failed + a bumped '
        'restartCount + cooldown, no grid.cursor.* key. The failure arrives '
        'through the LEASE (a throwing spawn → "acquire threw" → '
        'AllocationFailed), replacing the old provider-event trigger — the '
        'restated expectation for the routed path (tg-h4u)', () async {
      final log = <String>[];
      // _neverSpawn throws → LeaseAllocation contains it as a supervised
      // `acquire threw` failure (ADR-0008 D10) — no provider event needed.
      const vendor = SelfManagedProcessVendor(
        spawn: _neverSpawn,
        dispatch: _neverDispatch,
      );
      final h = _host(
        _RecordingProcessCap(log),
        circuit: _moleculeCircuit,
        leaseVendor: vendor,
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.step.state'], 'failed');
      expect(meta['grid.step.restartCount'], '1');
      expect(meta['grid.step.failureReason'], contains('acquire threw'));
      expect(
        // The molecule codec normalizes to UTC (`stepBeadMetadata`); the
        // flat codec (`nodeFailedMetadata`) does not — an intentional,
        // pre-existing divergence this rung does not touch.
        meta['grid.step.cooldownUntil'],
        _clock.add(const Duration(seconds: 1)).toUtc().toIso8601String(),
      );
      expect(meta.keys.where((k) => k.startsWith('grid.cursor.')), isEmpty);
    });

    test(
      'an escalation that PARKS writes state=gated on the STEP bead; the gate '
      'bead itself stays keyed to the OWNING SESSION (createGate is unchanged)',
      () async {
        final handler = RecordingEscalationHandler(
          decision: const ParkAtGate('parked by the fake handler'),
        );
        final h = _host(
          const FixedRouteCapability(Escalate('needs a human')),
          circuit: _moleculeCircuit,
          escalation: handler,
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        // TWO chokepoint `update`s: (1) the `state=gated` cursor write,
        // targeting the STEP bead (R5b's fork) and (2) `createGate`'s own
        // metadata stamp on the freshly minted gate bead (UNCHANGED — its
        // `sessionId:` argument still names the owning session; which bead
        // carries the cursor write above is an orthogonal, R5b-only concern).
        final updates = h.fakes.runner.callsFor('update');
        expect(updates, hasLength(2));
        expect(updates.first[1], _stepBeadId);
        expect(h.fakes.runner.metadataOfUpdate(0)['grid.step.state'], 'gated');

        expect(
          h.fakes.runner.callsFor('create'),
          hasLength(1),
          reason: 'the gate bead itself',
        );
        final gateStamp = h.fakes.runner.metadataOfUpdate(1);
        expect(gateStamp['blocks'], 'tgdog-s');
        expect(gateStamp['node'], 'tg-1/agent');
      },
    );

    test('AllocationRewound is DEAD CODE on the molecule path: routes to a '
        'supervised FAILURE on the step bead, never a rewindCount / '
        'grid.cursor.* write, never touches sibling nodes', () async {
      final h = _host(
        const FixedRouteCapability(Rewind({'other-step'}, 'because')),
        circuit: _moleculeCircuit,
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      final updates = h.fakes.runner.callsFor('update');
      expect(
        updates,
        hasLength(1),
        reason: 'no cascade — SELF only, never the named sibling',
      );
      expect(updates.single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.step.state'], 'failed');
      expect(
        meta.keys,
        isNot(contains('grid.step.rewindCount')),
        reason: 'the molecule schema never persists rewindCount (item 7)',
      );
      expect(meta.keys.where((k) => k.startsWith('grid.cursor.')), isEmpty);
    });
  });

  group(
    'legacy flat sessions — an ABSENT InheritedCircuit refuses LOUD '
    '(tg-eli phase 2: the molecule model is the only circuit engine)',
    () {
      test(
        'a ProcessCapability host with NO InheritedCircuit never spawns and '
        'never writes — it flares step.allocationFailed at mount and its '
        'supervised-failure persist is itself contained '
        '(step.persistFailed): a historical flat session cannot be driven',
        () async {
          final log = <String>[];
          final h = _host(_RecordingProcessCap(log)); // no InheritedCircuit
          addTearDown(() {
            h.owner.dispose();
            unawaited(h.fakes.provider.close());
          });
          await _pump();

          expect(log, isEmpty, reason: 'the capability was never spawned');
          expect(h.fakes.provider.started, isEmpty);
          expect(
            h.fakes.runner.calls,
            isEmpty,
            reason:
                'no write target exists — the retired flat session-bead '
                'write must never come back',
          );
          expect(
            h.transport.flares.map((f) => f.name),
            containsAll(['step.allocationFailed', 'step.persistFailed']),
          );
          final flare = h.transport.flares.firstWhere(
            (f) => f.name == 'step.allocationFailed',
          );
          expect(flare.data['error'], contains('InheritedCircuit'));
        },
      );

      test(
        'the refusal covers EVERY capability kind: a ServiceCapability host '
        'with NO InheritedCircuit is refused at MOUNT too — its effect never '
        'runs and no write ever lands on the session bead',
        () async {
          final h = _host(_ServiceCap(const Ok()));
          addTearDown(() {
            h.owner.dispose();
            unawaited(h.fakes.provider.close());
          });
          await _pump();

          expect(h.fakes.runner.calls, isEmpty);
          expect(
            h.transport.flares.map((f) => f.name),
            containsAll(['step.allocationFailed', 'step.persistFailed']),
          );
        },
      );
    },
  );

  group('LOUD-or-GONE — a process-backed molecule capability needs a mounted '
      'ProcessLeaseVendor (item 5)', () {
    test('no vendor mounted ⇒ the refusal fires at MOUNT (tg-h4u routing): a '
        'step.allocationFailed flare + a SUPERVISED failure on the step bead '
        '(per-work fail-closed, ADR-0008 D10 — contained, never crashes, '
        'never a silent stall)', () async {
      final log = <String>[];
      final h = _host(
        _RecordingProcessCap(log),
        circuit: _moleculeCircuit, // molecule mode, NO leaseVendor:
      );
      addTearDown(() {
        h.owner.dispose();
        unawaited(h.fakes.provider.close());
      });
      await _pump();

      // The refusal happened at mount — no spawn was ever attempted, so a
      // provider event is irrelevant; the ONLY write is the supervised
      // failure routing the mis-composition to the restart/breaker chain.
      final updates = h.fakes.runner.callsFor('update');
      expect(updates, hasLength(1));
      expect(updates.single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.step.state'], 'failed');
      expect(meta['grid.step.failureReason'], contains('ProcessLeaseVendor'));
      expect(
        h.transport.flares.map((f) => f.name),
        contains('step.allocationFailed'),
      );
      final f = h.transport.flares.firstWhere(
        (f) => f.name == 'step.allocationFailed',
      );
      expect(f.data['error'], contains('ProcessLeaseVendor'));
      expect(log, isEmpty, reason: 'the capability was never spawned');
    });

    test(
      'real stationProcessSpawner sourceless failure gates the step bead',
      () async {
        final log = <String>[];
        const vendor = SelfManagedProcessVendor(
          spawn: stationProcessSpawner,
          dispatch: _neverDispatch,
        );
        final h = _host(
          _RecordingProcessCap(log),
          circuit: _moleculeCircuit,
          leaseVendor: vendor,
          sourceControl: _ProvisionSourceControl(),
        );
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        final updates = h.fakes.runner.callsFor('update');
        expect(updates, hasLength(1));
        expect(updates.single[1], _stepBeadId);
        final meta = h.fakes.runner.metadataOfUpdate(0);
        expect(meta['grid.step.state'], 'failed');
        expect(
          meta['grid.step.failureReason'],
          contains('sourceless-workspace'),
        );
        expect(
          h.transport.flares.map((f) => f.name),
          contains('step.allocationFailed'),
        );
        final f = h.transport.flares.firstWhere(
          (f) => f.name == 'step.allocationFailed',
        );
        expect(f.data['error'], contains('sourceless-workspace'));
        expect(h.fakes.provider.started, isEmpty);
        expect(
          log,
          isEmpty,
          reason: 'spawn is guarded before capability.spawn',
        );
      },
    );

  });
}
