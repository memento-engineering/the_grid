// pm6-r5b-host — CapabilityHost molecule targeting: the write fork
// (DESIGN-tg-pm6.md §11).
//
// The additive fork: an ambient `InheritedCircuit` (R2) means every `_persistX`
// targets its OWN durable step bead (`beadIdByNodePath[_nodePath]`), using the
// per-bead molecule metadata builders (`molecule_codec.dart`'s
// `stepBeadMetadata` — no `{nodePath}` infix, no `rewindCount`, no
// `grid.cursor.*` key). ABSENT `InheritedCircuit` falls back to today's flat
// target (`_sessionId`) — proven BYTE-IDENTICAL to
// `track_e_capability_host_test.dart`'s own assertions. A process-backed
// capability on the molecule path additionally requires a mounted
// `ProcessLeaseVendor` (LOUD-or-GONE, R3) before its `SessionStarted` report
// lands anywhere; a molecule circuit's `AllocationRewound` report is dead-code
// on `_persistRewind`'s write cascade (backward motion is derived, R4) and
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

Future<ProcessHandle> _neverSpawn(TreeContext context, StepArgs args) =>
    Future.error(StateError('spawn must not be called'));

Future<StepOutcome> _neverDispatch(
  ProcessHandle handle,
  TreeContext context,
  StepArgs args,
) => Future.error(StateError('dispatch must not be called'));

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
          value: ServiceBundle(transport: transport, escalation: escalation),
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
      'pgid/pid/token, no grid.cursor.* key (the vendor owns grid.lease.*)',
      () async {
        final log = <String>[];
        final vendor = const SelfManagedProcessVendor(
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

        h.fakes.provider.emit(
          const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
        );
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
      'a daemon ready targets the step bead: grid.step.state=ready',
      () async {
        final h = _host(_DaemonCap(), circuit: _moleculeCircuit);
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        h.fakes.provider.emit(
          const ActivityChanged(name: 'tgdog-s/tg-1/agent', active: true),
        );
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
        'restartCount + cooldown, no grid.cursor.* key', () async {
      final log = <String>[];
      final vendor = const SelfManagedProcessVendor(
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
      h.fakes.provider.emit(
        const Exited(name: 'tgdog-s/tg-1/agent', exitCode: 1),
      );
      await _pump();

      expect(h.fakes.runner.callsFor('update').single[1], _stepBeadId);
      final meta = h.fakes.runner.metadataOfUpdate(0);
      expect(meta['grid.step.state'], 'failed');
      expect(meta['grid.step.restartCount'], '1');
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
    'flat mode — an ABSENT InheritedCircuit is byte-identical to today',
    () {
      test(
        'SessionStarted persists the per-node identity on the SESSION bead — '
        'the SAME shape track_e_capability_host_test.dart asserts',
        () async {
          final log = <String>[];
          final h = _host(_RecordingProcessCap(log)); // no InheritedCircuit
          addTearDown(() {
            h.owner.dispose();
            unawaited(h.fakes.provider.close());
          });
          await _pump();

          h.fakes.provider.emit(
            const SessionStarted(
              name: 'tgdog-s/tg-1/agent',
              pid: 100,
              pgid: 200,
            ),
          );
          await _pump();

          expect(h.fakes.runner.callsFor('update').single[1], 'tgdog-s');
          final meta = h.fakes.runner.metadataOfUpdate(0);
          expect(meta['grid.cursor.tg-1/agent.state'], 'running');
          expect(meta['grid.cursor.tg-1/agent.pgid'], '200');
          expect(meta['grid.cursor.tg-1/agent.pid'], '100');
          expect(meta['grid.cursor.tg-1/agent.token'], isNotEmpty);
          expect(meta['grid.cursor.tg-1/agent.startedAt'], isNotEmpty);
        },
      );

      test('a clean completion writes the SESSION bead cursor — transcript '
          'equality with expectedTiming (the flat codec, unchanged)', () async {
        final h = _host(_ServiceCap(const Ok()));
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        expect(h.fakes.runner.callsFor('update').single[1], 'tgdog-s');
        expect(h.fakes.runner.metadataOfUpdate(0), {
          'grid.cursor.tg-1/agent.state': 'complete',
          ...expectedTiming('tg-1/agent'),
        });
      });

      test(
        'AllocationRewound still runs the flat cascade (session bead, '
        'rewindCount bumped) — the molecule fork never touches this path',
        () async {
          // 'agent' is the only step in `_circuit` — a legal self-rewind (the
          // dangling/empty-stepIds guard only rejects an UNKNOWN sibling).
          final h = _host(
            const FixedRouteCapability(Rewind({'agent'}, 'because')),
          );
          addTearDown(() {
            h.owner.dispose();
            unawaited(h.fakes.provider.close());
          });
          await _pump();

          final meta = h.fakes.runner.metadataOfUpdate(0);
          expect(meta['grid.cursor.tg-1/agent.state'], 'pending');
          expect(meta['grid.cursor.tg-1/agent.rewindCount'], '1');
        },
      );
    },
  );

  group('LOUD-or-GONE — a process-backed molecule capability needs a mounted '
      'ProcessLeaseVendor (item 5)', () {
    test('no vendor mounted ⇒ NO write lands + a step.persistFailed flare '
        '(contained, never crashes)', () async {
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

      h.fakes.provider.emit(
        const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
      );
      await _pump();

      expect(
        h.fakes.runner.callsFor('update'),
        isEmpty,
        reason: 'the throw must land BEFORE any write is issued',
      );
      expect(
        h.transport.flares.map((f) => f.name),
        contains('step.persistFailed'),
      );
      final f = h.transport.flares.firstWhere(
        (f) => f.name == 'step.persistFailed',
      );
      expect(f.data['error'], contains('ProcessLeaseVendor'));
    });

    test(
      'the throw is MOLECULE-PATH-ONLY: a flat session (no InheritedCircuit) '
      'needs no vendor at all — the write lands exactly as before',
      () async {
        final log = <String>[];
        final h = _host(_RecordingProcessCap(log)); // flat, NO vendor
        addTearDown(() {
          h.owner.dispose();
          unawaited(h.fakes.provider.close());
        });
        await _pump();

        h.fakes.provider.emit(
          const SessionStarted(name: 'tgdog-s/tg-1/agent', pid: 100, pgid: 200),
        );
        await _pump();

        expect(h.fakes.runner.callsFor('update'), hasLength(1));
        expect(h.transport.flares, isEmpty);
      },
    );
  });
}
