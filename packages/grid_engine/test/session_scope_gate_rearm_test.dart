// tg-boq — the D-7 gate re-arm, WIRING-SHAPED, through the REAL
// `StationJoinBridge` + the full `Station → … → SessionScope` tree.
//
// LIVE INCIDENT (2026-07-07, session tgdog-snp / bead tg-m2q): a space gate
// resolve CLOSED the gate bead, but the resident station NEVER re-armed the
// parked node — the cursor stayed `gated` for 30+ min, no re-arm write ever
// followed, and the operator's only recovery was a station bounce. Two
// suspects had to be ruled in/out OFFLINE:
//
//   (1) state-emission delivery — does an EXTERNAL gate-close pushed into the
//       state store re-emit and actually REBUILD the parked SessionScope?
//       → PROVEN HERE ('dynamic external gate-close'): the engine tree re-arms
//         correctly, so the deviation is NOT the join/rebuild.
//   (2) the `_ctx?.`/pre-write-latch compound — `_scheduleRearm` latched
//       `_rearmed` BEFORE a fire-and-forget write, so a DROPPED write made the
//       drop PERMANENT and SILENT.
//       → REPRODUCED HERE ('a dropped re-arm write RETRIES'): the old permanent
//         latch wedged the node forever; the fix (an in-flight guard cleared on
//         settle + a LOUD flare) retries on the next build.
//
// Plus the RESTART recovery path ('boots adopting a gated cursor …') — the
// operator's only recovery today, itself previously untested.
//
// Zero I/O: fakes + the recording chokepoint + a fake transport.
import 'dart:async';
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'route', capabilityId: 'route'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'route'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

GraphSnapshot _state(List<Bead> beads, {int tick = 0}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: const [],
      capturedAt: DateTime.fromMillisecondsSinceEpoch(tick),
    );

/// A session bead parked at `tg-1/route` = `gated` (the committee park), linked
/// to [workBead].
Bead _gatedSession(String id, {required String workBead}) => Bead(
  id: id,
  issueType: IssueType.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: workBead,
    ...nodeStateMetadata('tg-1/route', StepState.gated),
  },
);

/// The `type=gate` bead blocking [sessionId] at `tg-1/route` — OPEN parks the
/// node; CLOSED (a space gate resolve) re-arms it.
Bead _gate(String id, {required String sessionId, bool closed = false}) => Bead(
  id: id,
  issueType: IssueType.gate,
  status: closed ? BeadStatus.closed : BeadStatus.open,
  metadata: {'rig': stateSubstation, 'blocks': sessionId, 'node': 'tg-1/route'},
);

/// An [ExplorationTransport] that records every LOUD flare — the emit-only sink
/// the re-arm-failed signal fires through.
class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));
}

/// A [BdRunner] that FAILS the first [failUpdates] `update` calls (throwing, as
/// a live `bd` blip would) then succeeds — so a test can drive a DROPPED re-arm
/// write and prove the next build retries. Records every argv in order.
class _FailFirstUpdateRunner implements BdRunner {
  _FailFirstUpdateRunner({this.failUpdates = 1});

  final int failUpdates;
  final List<List<String>> calls = <List<String>>[];
  int _updates = 0;

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  Map<String, dynamic> metadataOfUpdate(int index) {
    final c = callsFor('update')[index];
    final i = c.indexOf('--metadata');
    return jsonDecode(c[i + 1]) as Map<String, dynamic>;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'update') {
      _updates++;
      if (_updates <= failUpdates) {
        throw StateError('fake bd update failure #$_updates (tg-boq)');
      }
    }
    final data = switch (sub) {
      'create' => '{"id":"tgdog-sess1"}',
      _ => '{"id":"${args.length >= 2 ? args[1] : ''}"}',
    };
    return BdResult(
      exitCode: 0,
      stdout: '{"schema_version":1,"data":$data}',
      stderr: '',
    );
  }
}

/// A [StationServices] whose chokepoint writes through [runner] (a recording
/// fake), owning [stateSubstation] — the same shape [buildFakes] builds, but
/// over a caller-supplied runner so a test can assert against it directly.
StationServices _ctxOver(BdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  ServiceBundle services = const ServiceBundle(),
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<SessionResolver>(
            value: CircuitResolver((_) => _code),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(
                  const SubstationConfig(
                    substationId: 'tg',
                    ownedSubstations: {'tg'},
                  ),
                ),
                services: services,
                key: const ValueKey('scope.tg'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root);
}

void main() {
  group('D-7 gate re-arm, wiring-shaped (tg-boq)', () {
    test(
      'SUSPECT 1 — a dynamic external gate-close pushed into the STATE source '
      're-arms the parked node (the join/rebuild is NOT where the incident '
      'came from)',
      () async {
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s'),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(joined: bridge.notifier, ctx: ctx, registry: reg);
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // OPEN gate → parked, no re-arm.
        expect(
          runner.callsFor('update'),
          isEmpty,
          reason: 'an open gate leaves the node parked',
        );

        // The space resolves the gate — an EXTERNAL writer CLOSES the gate bead
        // in the state store. Push the new state snapshot.
        state.push(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        final updates = runner.callsFor('update');
        expect(
          updates,
          hasLength(1),
          reason: 'the resolved gate flips the parked node back to pending',
        );
        expect(runner.metadataOfUpdate(0), {
          'grid.cursor.tg-1/route.state': 'pending',
        });
        // The chokepoint stayed pristine (never `bd show`, never SQL).
        expect(runner.neverShowOrSql, isTrue);
      },
    );

    test(
      'RESTART recovery — a station that BOOTS adopting a gated cursor whose '
      'gate is ALREADY closed re-arms on adopt (the operator\'s only recovery '
      'path today: a station bounce)',
      () async {
        final runner = RecordingBdRunner();
        final ctx = _ctxOver(runner);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        // Boot state: the cursor is gated AND the gate bead is already CLOSED
        // (resolved while the prior station was down) — openGateNodes is empty
        // from the very first join.
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(joined: bridge.notifier, ctx: ctx, registry: reg);
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        final updates = runner.callsFor('update');
        expect(
          updates,
          hasLength(1),
          reason: 'adopt sees the already-resolved gate and re-arms immediately',
        );
        expect(runner.metadataOfUpdate(0), {
          'grid.cursor.tg-1/route.state': 'pending',
        });
      },
    );

    test(
      'SUSPECT 2 — a DROPPED re-arm write RETRIES on the next build (never a '
      'permanent silent latch) and FLARES loud',
      () async {
        final runner = _FailFirstUpdateRunner(failUpdates: 1);
        final ctx = _ctxOver(runner);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final work = FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'}));
        final state = FakeSnapshotSource(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s'),
          ]),
        );
        final bridge = StationJoinBridge(work: work, state: state)..start();
        addTearDown(bridge.dispose);

        final m = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: reg,
          services: ServiceBundle(transport: transport),
        );
        addTearDown(m.owner.dispose);
        await _pump();
        m.owner.flush();
        await _pump();

        // First resolve → re-arm attempt #1, which DROPS (the runner throws).
        state.push(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 1),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        // The drop is LOUD — a flare fired — and NOT silent-swallowed.
        expect(
          transport.flares.map((f) => f.name),
          contains('gate.rearmFailed'),
          reason: 'a dropped re-arm write must flare (LOUD or GONE)',
        );
        expect(transport.flares.single.data['nodePath'], 'tg-1/route');

        // A SECOND store tick (still the resolved gate) — with the OLD permanent
        // latch this build would be a no-op (the node stays wedged `gated`
        // forever). With the in-flight guard cleared on failure, D-7 re-fires
        // and the retry SUCCEEDS.
        state.push(
          _state([
            _gatedSession('tgdog-s', workBead: 'tg-1'),
            _gate('gate-1', sessionId: 'tgdog-s', closed: true),
          ], tick: 2),
        );
        await _pump();
        m.owner.flush();
        await _pump();

        final updates = runner.callsFor('update');
        expect(
          updates,
          hasLength(2),
          reason: 'attempt #1 dropped + attempt #2 retried — never latched off',
        );
        // Both attempts carry the same pending flip; #2 (index 1) succeeded.
        expect(runner.metadataOfUpdate(1), {
          'grid.cursor.tg-1/route.state': 'pending',
        });
        // Exactly ONE flare — the retry succeeded, so it did not re-flare.
        expect(
          transport.flares.where((f) => f.name == 'gate.rearmFailed'),
          hasLength(1),
        );
      },
    );
  });
}
