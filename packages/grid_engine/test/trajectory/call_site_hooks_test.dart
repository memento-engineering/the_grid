// W4 + W5 (tg-zfek Stage 1) — the CALL-SITE HOOKS: the design's named
// observation sites, driven through the REAL engine paths.
//
// Every hook in `stage1-wiring.md` §2.3 carries the same three-part contract,
// and every group below proves all three for the sites it covers:
//
//   1. the record derives AFTER the legacy write it shadows returned
//      successfully — the shadow never leads the incumbent;
//   2. it is ENQUEUE-ONLY — no engine path awaits an append (proven by the
//      recorder's synchronous void API plus the legacy path finishing
//      unchanged when the sink is slow to matter at all);
//   3. it is NON-FATAL — a recorder that REFUSES (latched/degraded/disabled)
//      or THROWS leaves the legacy path byte-identical. That is the falsifier
//      that matters: an append failure must never fail, delay, or reorder a
//      legacy write (§2.5, §3).
//
// The legacy-unchanged proofs are differential: the same scenario runs twice,
// once with a capturing sink and once with a throwing/refusing one, and the
// recorded bd traffic is compared. A hook that reordered or dropped a write
// under failure shows up as a diff, not as a judgement call.
//
// ignore_for_file: invalid_use_of_protected_member
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart' hide SubstationScope;
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/seeds/provider.dart' as provider;
import 'package:grid_engine/src/seeds/substation_scope.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// The three sink postures every hook is proven against (§3's failure table).
// ---------------------------------------------------------------------------

final class _CapturingSink implements TrajectoryRecordSink {
  final List<TrajectoryRecord> records = [];
  final List<TrajectoryProvenance> provenances = [];
  final List<String?> seats = [];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) {
    records.add(record);
    provenances.add(provenance);
    seats.add(seat);
  }

  List<String> get types => [for (final r in records) r.recordType];

  /// The records of one type, flattened to `payload + correlation` maps.
  ///
  /// Deliberately UNTYPED: naming `StepTransition` here would mean a third
  /// inbound edge to the leaf package (grid_engine has none, by design), and
  /// the typed construction is already the recorder's own suite's job
  /// (`grid_runtime/test/trajectory/`). What THIS suite proves is which
  /// observation the engine made and when — a fact the wire shape states
  /// exactly as well.
  List<Map<String, Object?>> facts(String recordType) => [
    for (final r in records)
      if (r.recordType == recordType)
        {...r.correlationToJson(), ...r.payloadToJson()},
  ];

  Map<String, Object?> fact(String recordType) {
    final all = facts(recordType);
    expect(all, hasLength(1), reason: 'exactly one $recordType');
    return all.single;
  }
}

/// The LATCHED / degraded / disabled posture: the sink stops accepting, so the
/// recorder short-circuits every observation to a count.
final class _RefusingSink implements TrajectoryRecordSink {
  @override
  bool get accepting => false;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('a non-accepting sink must never be reached');
}

/// The worst case the design still promises to survive: an ACCEPTING sink that
/// throws inside the enqueue.
final class _ThrowingSink implements TrajectoryRecordSink {
  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? seat,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => throw StateError('sink refused');
}

StationTrajectoryRecorder _recorderOver(TrajectoryRecordSink sink) =>
    StationTrajectoryRecorder(sink: sink, seatPrefixes: const {'tg', 'tgdog'});

/// The three postures a differential test runs the SAME scenario under.
final class _Posture {
  _Posture(this.name, this.sink);
  final String name;
  final TrajectoryRecordSink sink;
}

List<_Posture> _failingPostures() => [
  _Posture('refusing', _RefusingSink()),
  _Posture('throwing', _ThrowingSink()),
];

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

// ---------------------------------------------------------------------------
// CapabilityHost harness (W5's persist sites).
// ---------------------------------------------------------------------------

const _stepBeadId = 'tgdog-step1';
final _clock = DateTime(2026);

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'agent',
  steps: [CapabilityStep(stepId: 'agent', capabilityId: 'agent')],
);

class _ServiceCap extends ServiceCapability {
  _ServiceCap(this.outcome);
  final StepOutcome outcome;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async => outcome;
}

/// A route that DECLINES — the escalate path, whose unbound handler defaults
/// to `HumanGate` ⇒ `ParkAtGate` ⇒ the gated step half (§2.3's gated row).
class _EscalatingRoute extends RouteCapability {
  const _EscalatingRoute();

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async =>
      const Escalate('needs a human');
}

StepMount _mount({int restartCount = 0, int circuitRound = 0}) => StepMount(
  step: const CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
  nodePath: 'tg-1/agent',
  circuit: _circuit,
  circuitPath: 'tg-1',
  session: const SessionHandle('tgdog-s'),
  node: NodeCursor(restartCount: restartCount),
  key: ValueKey('tg-1/agent#$restartCount.0'),
  circuitRound: circuitRound,
  maxRestarts: 3,
);

/// The `--metadata` argv of every recorded `bd update` — the legacy write
/// trace a hook must leave untouched, read at the wire the chokepoint actually
/// emits rather than through a convenience accessor.
List<String> _updateArgv(Fakes fakes) => [
  for (final call in fakes.runner.calls)
    if (call.isNotEmpty && call.first == 'update') call.join(' '),
];

/// A [BdRunner] that DROPS the first [failures] `update` calls and delegates
/// everything else — the transient store blip `_firePersist` exists to
/// survive, reproduced rather than described.
class _DroppingUpdateRunner implements BdRunner {
  _DroppingUpdateRunner(this.inner, this.failures);
  final RecordingBdRunner inner;
  int failures;

  @override
  Future<BdResult> run(List<String> args, {Duration? timeout, String? stdin}) {
    if (args.isNotEmpty && args.first == 'update' && failures > 0) {
      failures -= 1;
      inner.calls.add(List<String>.unmodifiable(args));
      return Future<BdResult>.value(
        const BdResult(exitCode: 1, stdout: '', stderr: 'store unavailable'),
      );
    }
    return inner.run(args, timeout: timeout, stdin: stdin);
  }
}

({TreeOwner owner, Fakes fakes}) _host(
  Capability cap, {
  required TrajectoryRecordSink sink,
  StepMount? mount,
  int failUpdates = 0,
}) {
  var fakes = buildFakes();
  if (failUpdates > 0) {
    final runner = fakes.runner;
    final dropping = _DroppingUpdateRunner(runner, failUpdates);
    fakes = (
      ctx: StationServices(
        provider: fakes.provider,
        writer: StationBeadWriter(
          bd: BdCliService(dropping),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      ),
      runner: runner,
      provider: fakes.provider,
      git: fakes.git,
      pr: fakes.pr,
    );
  }
  final owner = TreeOwner();
  final stepMount = mount ?? _mount();
  owner.mountRoot(
    InheritedSeed<StationServices>(
      value: fakes.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: RecordingCapabilityRegistry(clock: _clock),
        child: InheritedSeed<TrajectoryRecorderScope>(
          value: TrajectoryRecorderScope(_recorderOver(sink)),
          child: InheritedSeed<ServiceBundle>(
            value: const ServiceBundle(),
            child: InheritedSeed<Workspace>(
              value: testWorkspace('tg-1'),
              child: InheritedSeed<InheritedCircuit>(
                value: InheritedCircuit(
                  root: BeadPathKey(const ['tg-1', 'tgdog-s', _stepBeadId]),
                  beadIdByNodePath: {stepMount.nodePath: _stepBeadId},
                  cursor: const {},
                ),
                child: CapabilityHost(capability: cap, mount: stepMount),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, fakes: fakes);
}

// ---------------------------------------------------------------------------
// SessionScope harness (W4's session sites) — the full new path.
// ---------------------------------------------------------------------------

const _codeCircuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: const [],
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

TreeOwner _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required TrajectoryRecordSink sink,
  ServiceBundle services = const ServiceBundle(),
}) {
  final owner = TreeOwner();
  owner.mountRoot(
    provider.ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(circuits: const {}),
            child: InheritedSeed<TrajectoryRecorderScope>(
              value: TrajectoryRecorderScope(_recorderOver(sink)),
              child: InheritedSeed<SessionResolver>(
                value: CircuitResolver((_) => _codeCircuit),
                child: Station([
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(_tgConfig),
                    services: services,
                    key: const ValueKey('scope.tg'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return owner;
}

/// 26-char ULID-shaped attempt names — the identity classes the log mints.
const _attemptA = 'AAAAAAAAAAAAAAAAAAAAAAAAAA';
const _attemptB = 'BBBBBBBBBBBBBBBBBBBBBBBBBB';
const _attemptC = 'CCCCCCCCCCCCCCCCCCCCCCCCCC';

typedef _Vended = ({
  StationProcessLeaseVendor vendor,
  LeaseCapability<ProcessHandle> lease,
  Fakes fakes,
});

/// The REAL vendor over the recording chokepoint. Nothing is spawned: the
/// vendor's WRITE paths (`acquire`'s breadcrumb persist, `release`'s clear,
/// the sweep) plus `proveFresh` are what carry every observation the design
/// puts here, and those are exactly what this drives.
_Vended _vendor({
  required TrajectoryRecordSink sink,
  Map<String, String>? existing,
  AllocationLiveness liveness = neverLive,
}) {
  final fakes = buildFakes();
  final vendor = StationProcessLeaseVendor(
    writer: fakes.ctx.writer,
    spawn: (request, context, args) async =>
        throw UnimplementedError('no spawn is driven here'),
    dispatch: (handle, request, context, args) async => const Ok(),
    metadataOf: (id) async => existing,
    liveness: liveness,
    recorder: _recorderOver(sink),
  );
  final lease = vendor.leaseFor(
    ProcessLeaseRequest(
      stepBeadId: _stepBeadId,
      capability: const _NullProcessCap(),
      allocation: AllocationContext(
        treeContext: _NullTreeContext(),
        args: StepArgs(
          params: const {},
          nodePath: 'tg-1/agent',
          cancel: CancelToken(),
        ),
        transport: fakes.provider,
        address: const AllocationAddress('tgdog-s', 'tg-1/agent'),
        env: const {},
        sink: (_) {},
      ),
    ),
  );
  return (vendor: vendor, lease: lease, fakes: fakes);
}

Future<_Vended> _released(TrajectoryRecordSink sink) async {
  final b = _vendor(sink: sink);
  await b.lease.release(
    ProcessHandle(pgid: 10, pid: 10, token: 't', attemptId: _attemptA),
  );
  return b;
}

class _NullProcessCap extends ProcessCapability {
  const _NullProcessCap();

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) =>
      const RuntimeConfig(workDir: '/tmp', command: 'true', args: []);

  @override
  StepSignal interpretEvent(RuntimeEvent event) => StepSignal.none;
}

/// The vendor's write paths never touch the tree context — `release` stops the
/// transport and clears the breadcrumb, `proveFresh` only calls liveness. A
/// THROWING stand-in is therefore a proof rather than a shortcut: if any of
/// them ever reached into the tree, this suite would fail loudly instead of
/// quietly exercising some other path.
class _NullTreeContext implements TreeContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('the vendor write paths read no tree context');
}

void main() {
  group('W5 — the CapabilityHost persist sites (§2.3 step.transition)', () {
    test('a completion appends complete AFTER the step-bead write', () async {
      final sink = _CapturingSink();
      final h = _host(_ServiceCap(const Ok({'grade': 'A'})), sink: sink);
      addTearDown(h.owner.dispose);
      await _pump();

      final step = sink.fact('step.transition');
      expect(step['state'], 'complete');
      expect(step['step_path'], 'tg-1/agent');
      expect(step['session_id'], 'tgdog-s');
      expect((step['result']! as Map)['grade'], 'A');
      // AFTER the legacy write: the update carrying `complete` already ran.
      expect(_updateArgv(h.fakes).last, contains('grid.step.state=complete'));
    });

    test(
      'a failure names the BUMPED incarnation and failure_class=work',
      () async {
        final sink = _CapturingSink();
        final h = _host(_ServiceCap(const Failed('exit 1')), sink: sink);
        addTearDown(h.owner.dispose);
        await _pump();

        final step = sink.fact('step.transition');
        expect(step['state'], 'failed');
        // The D-5 write persisted restartCount 1; the record names the SAME
        // successor incarnation — the durable succession signal (§2.3), with
        // no event to key on.
        expect(step['incarnation'], 1);
        expect(step['failure_class'], 'work');
        expect(step['failure_reason'], 'exit 1');
        expect(
          _updateArgv(h.fakes).last,
          contains('${MoleculeStepKeys.restartCount}=1'),
        );
      },
    );

    test(
      'a DROPPED persist is failure_class=store_unavailable (tg-7ux)',
      () async {
        final sink = _CapturingSink();
        // Refuse the FIRST update — the `complete` persist — so the host
        // routes through `_superviseFailedPersist`, the one site that knows
        // the `failed` it is about to write means "the store dropped it",
        // not "the work failed". Both land as `state=failed` on the bead;
        // only the record separates them.
        final h = _host(_ServiceCap(const Ok()), sink: sink, failUpdates: 1);
        addTearDown(h.owner.dispose);
        await _pump();

        final steps = sink.facts('step.transition');
        expect(
          steps.map((s) => s['state']),
          ['failed'],
          reason: 'the DROPPED complete appends nothing — legacy success first',
        );
        expect(steps.single['failure_class'], 'store_unavailable');
      },
    );

    test('the gated STEP half appends; no gate record ever does', () async {
      final sink = _CapturingSink();
      final h = _host(const _EscalatingRoute(), sink: sink);
      addTearDown(h.owner.dispose);
      await _pump();

      final step = sink.fact('step.transition');
      expect(step['state'], 'gated');
      expect(step['cause'], 'route');
      // `gate.opened` is a P4 record: the gate BEAD's mint stays wholly legacy
      // through the whole shadow window.
      expect(sink.types, ['step.transition']);
      expect(
        h.fakes.runner.calls.where((c) => c.first == 'create'),
        isNotEmpty,
        reason: 'the legacy gate mint still fires — Stage 1 removes no write',
      );
    });

    test('step_round is the mount circuitRound, never invented', () async {
      final sink = _CapturingSink();
      final h = _host(
        _ServiceCap(const Ok()),
        sink: sink,
        mount: _mount(circuitRound: 4),
      );
      addTearDown(h.owner.dispose);
      await _pump();
      expect(sink.fact('step.transition')['step_round'], 4);
    });

    test(
      'NON-FATAL: a refusing/throwing recorder leaves the bd traffic identical',
      () async {
        Future<List<List<String>>> traffic(TrajectoryRecordSink sink) async {
          final h = _host(_ServiceCap(const Ok({'grade': 'A'})), sink: sink);
          addTearDown(h.owner.dispose);
          await _pump();
          return h.fakes.runner.calls;
        }

        final expected = await traffic(_CapturingSink());
        expect(expected, isNotEmpty, reason: 'sanity: the legacy write ran');
        for (final posture in _failingPostures()) {
          expect(
            await traffic(posture.sink),
            expected,
            reason: '${posture.name} sink changed the legacy write',
          );
        }
      },
    );
  });

  group('W4 — the SessionScope sites (§2.3 attempt rows)', () {
    test(
      'a fresh mint appends attempt.session.started with rig + model',
      () async {
        final sink = _CapturingSink();
        final fakes = buildFakes();
        final owner = _mountFull(
          joined: JoinedSnapshotNotifier(
            _joined(beads: [bead('tg-1')], ready: {'tg-1'}),
          ),
          ctx: fakes.ctx,
          sink: sink,
        );
        addTearDown(owner.dispose);
        await _pumpUntil(owner, () => sink.records.isNotEmpty);

        final started = sink.fact('attempt.session.started');
        expect(started['session_id'], 'tgdog-sess1');
        expect(started['work_bead_id'], 'tg-1');
        expect(started['rig'], stateSubstation);
        expect(started['model'], kSessionModelMolecule);
        // §2.2's grant_id row: no grants exist before Stage 3.
        expect(started['grant_basis'], kPreStage3GrantBasis);
        // §2.2's seat row, resolved by ownedPrefixOf over the allow-set.
        expect(sink.seats.first, 'tg');
      },
    );

    test(
      'the record derives AFTER createSession, never on a mint RETRY',
      () async {
        final sink = _CapturingSink();
        final fakes = buildFakes();
        final owner = _mountFull(
          joined: JoinedSnapshotNotifier(
            _joined(beads: [bead('tg-1')], ready: {'tg-1'}),
          ),
          ctx: fakes.ctx,
          sink: sink,
        );
        addTearDown(owner.dispose);
        await _pumpUntil(owner, () => fakes.runner.calls.length >= 3);
        // ONE session bead was created, so ONE `.started` — a mint retry
        // reuses the first attempt's id and must not append a second record
        // with no legacy write behind it.
        expect(sink.facts('attempt.session.started'), hasLength(1));
      },
    );

    test(
      'NON-FATAL: a refusing/throwing recorder still mints the session',
      () async {
        for (final posture in _failingPostures()) {
          final fakes = buildFakes();
          final owner = _mountFull(
            joined: JoinedSnapshotNotifier(
              _joined(beads: [bead('tg-1')], ready: {'tg-1'}),
            ),
            ctx: fakes.ctx,
            sink: posture.sink,
          );
          addTearDown(owner.dispose);
          await _pumpUntil(owner, () => fakes.runner.workCreates.length >= 2);
          // The SAME two legacy writes a healthy mint makes: `createSession`,
          // then the molecule pour (`create --graph`).
          expect(
            fakes.runner.workCreates,
            hasLength(2),
            reason: '${posture.name} sink broke the mint',
          );
          expect(
            fakes.runner.workCreates.where(
              (c) => c.length > 1 && c[1] == '--graph',
            ),
            hasLength(1),
          );
        }
      },
    );
  });

  group('W4 — the lease vendor sites (§2.3 lease + adopt rows)', () {
    test('release appends released AFTER the clearing write', () async {
      final sink = _CapturingSink();
      final b = _vendor(sink: sink);
      await b.lease.release(
        ProcessHandle(pgid: 10, pid: 10, token: 't', attemptId: _attemptA),
      );

      final record = sink.fact('attempt.lease.released');
      expect(record['attempt_id'], _attemptA);
      // The phase rides the record TYPE (`attempt.lease.<phase>`), never a
      // payload field — asking for it by name is asking the wrong question.
      expect(sink.types, ['attempt.lease.released']);
      expect(record['disposition'], 'released');
      // The legacy clearing write landed first.
      expect(
        _updateArgv(b.fakes).single,
        contains('${LeaseKeys.attemptId}='),
        reason: 'the breadcrumb was cleared before the record derived',
      );
    });

    test('a pre-Stage-1 handle (no attempt id) appends nothing', () async {
      final sink = _CapturingSink();
      final b = _vendor(sink: sink);
      await b.lease.release(ProcessHandle(pgid: 10, pid: 10, token: 't'));
      expect(
        sink.records,
        isEmpty,
        reason: 'the record READS the attempt id, it never invents one',
      );
      // The legacy clear still happened — adoption never regresses.
      expect(_updateArgv(b.fakes), hasLength(1));
    });

    test('proveFresh appends adopt.proved on BOTH outcomes', () async {
      for (final (live, expected) in [
        (true, 'adopted'),
        (false, 'respawned'),
      ]) {
        final sink = _CapturingSink();
        final b = _vendor(sink: sink, liveness: (_) => live);
        final fresh = await b.lease.proveFresh(
          ProcessHandle(pgid: 9, pid: 9, token: 't', attemptId: _attemptB),
          _NullTreeContext(),
          StepArgs(
            params: const {},
            nodePath: 'tg-1/agent',
            cancel: CancelToken(),
          ),
        );
        expect(fresh, live);
        final record = sink.fact('attempt.adopt.proved');
        expect(record['outcome'], expected);
        expect(record['attempt_id'], _attemptB);
        expect(record['fence_pgid'], 9);
      }
    });

    test(
      'NON-FATAL: a refusing/throwing recorder still clears the breadcrumb',
      () async {
        final expected = _updateArgv((await _released(_CapturingSink())).fakes);
        expect(expected, hasLength(1), reason: 'sanity: the clear ran');
        for (final posture in _failingPostures()) {
          expect(
            _updateArgv((await _released(posture.sink)).fakes),
            expected,
            reason: '${posture.name} sink changed the release write',
          );
        }
      },
    );

    test('the sweep appends one swept record per disposition', () async {
      final sink = _CapturingSink();
      final b = _vendor(sink: sink);
      final swept = await b.vendor.sweepOrphanedLeases(
        candidates: [
          (
            stepBeadId: _stepBeadId,
            willRemount: true,
            metadata: {
              MoleculeStepKeys.state: 'running',
              LeaseKeys.pgid: '77',
              LeaseKeys.pid: '77',
              LeaseKeys.token: 'tok',
              LeaseKeys.attemptId: _attemptC,
            },
          ),
        ],
        alive: ({required int pgid, required int leaderPid}) => true,
        terminate: ({required int pgid, required int leaderPid}) async =>
            GroupTerminateResult.exitedOnTerm,
        onOrphan: (_) {},
      );
      expect(swept.single.disposition, LeaseSweepDisposition.killed);
      final record = sink.fact('attempt.lease.swept');
      expect(record['disposition'], 'killed');
      expect(record['attempt_id'], _attemptC);
      expect(record['terminate_result'], 'exitedOnTerm');
    });

    test('a sweep candidate with no attempt id appends nothing', () async {
      final sink = _CapturingSink();
      final b = _vendor(sink: sink);
      // A pre-Stage-1 breadcrumb: pgid/pid/token, no attempt name. The kill
      // still happens; there is simply nothing to key a record on.
      final swept = await b.vendor.sweepOrphanedLeases(
        candidates: [
          (
            stepBeadId: _stepBeadId,
            willRemount: true,
            metadata: {
              MoleculeStepKeys.state: 'running',
              LeaseKeys.pgid: '77',
              LeaseKeys.pid: '77',
              LeaseKeys.token: 'tok',
            },
          ),
        ],
        alive: ({required int pgid, required int leaderPid}) => true,
        terminate: ({required int pgid, required int leaderPid}) async =>
            GroupTerminateResult.exitedOnTerm,
        onOrphan: (_) {},
      );
      expect(swept.single.disposition, LeaseSweepDisposition.killed);
      expect(sink.records, isEmpty);
    });
  });

  group('W4 — the terminal callers (§2.3, r2 major 6)', () {
    /// The session projection a live molecule session joins under.
    SessionProjection live(String sessionId, String workBeadId) =>
        SessionProjection(workBeadId: workBeadId, sessionId: sessionId);

    test('the positive terminal appends terminal(succeeded)', () async {
      final sink = _CapturingSink();
      final fakes = buildFakes();
      fakes.runner.exportBeads = const [
        Bead(
          id: 'tgdog-s',
          issueType: GridIssueTypes.session,
          status: BeadStatus.closed,
          metadata: {'rig': 'tgdog', 'grid.outcome': 'complete'},
        ),
      ];
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [bead('tg-1')],
          ready: {'tg-1'},
          sessions: {'tg-1': live('tgdog-s', 'tg-1')},
        ),
      );
      final owner = _mountFull(joined: joined, ctx: fakes.ctx, sink: sink);
      addTearDown(owner.dispose);

      joined.push(
        _joined(
          beads: [bead('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              cursor: {
                'tg-1/agent': NodeCursor(state: StepState.complete),
                'tg-1/land': NodeCursor(state: StepState.complete),
              },
            ),
          },
        ),
      );
      owner.flush();
      await _pumpUntil(owner, () => fakes.runner.callsFor('close').isNotEmpty);

      final terminal = sink.fact('attempt.terminal');
      expect(terminal['outcome'], 'succeeded');
      expect(terminal['session_id'], 'tgdog-s');
      // The record carries the ORIGINAL work bead id and its resolved seat.
      expect(terminal['work_bead_id'], 'tg-1');
      expect(sink.seats.last, 'tg');
      // Derived at the OUTCOME-BEARING caller, after the legacy close landed.
      expect(
        fakes.runner.callsFor('close').map((c) => c[1]),
        contains('tgdog-s'),
      );
    });

    test(
      'NON-FATAL: a refusing/throwing recorder still closes the session',
      () async {
        for (final posture in _failingPostures()) {
          final fakes = buildFakes();
          fakes.runner.exportBeads = const [
            Bead(
              id: 'tgdog-s',
              issueType: GridIssueTypes.session,
              status: BeadStatus.closed,
              metadata: {'rig': 'tgdog', 'grid.outcome': 'complete'},
            ),
          ];
          final joined = JoinedSnapshotNotifier(
            _joined(
              beads: [bead('tg-1')],
              ready: {'tg-1'},
              sessions: {'tg-1': live('tgdog-s', 'tg-1')},
            ),
          );
          final owner = _mountFull(
            joined: joined,
            ctx: fakes.ctx,
            sink: posture.sink,
          );
          addTearDown(owner.dispose);
          joined.push(
            _joined(
              beads: [bead('tg-1')],
              ready: {'tg-1'},
              sessions: {
                'tg-1': const SessionProjection(
                  workBeadId: 'tg-1',
                  sessionId: 'tgdog-s',
                  cursor: {
                    'tg-1/agent': NodeCursor(state: StepState.complete),
                    'tg-1/land': NodeCursor(state: StepState.complete),
                  },
                ),
              },
            ),
          );
          owner.flush();
          await _pumpUntil(
            owner,
            () => fakes.runner.callsFor('close').isNotEmpty,
          );
          expect(
            fakes.runner.callsFor('close').map((c) => c[1]),
            contains('tgdog-s'),
            reason: '${posture.name} sink blocked the legacy close',
          );
        }
      },
    );

    test(
      'a LIVE re-key retires the round the #rN key names, minus one',
      () async {
        final sink = _CapturingSink();
        final fakes = buildFakes();
        fakes.runner.exportBeads = const [
          Bead(
            id: 'tgdog-s',
            issueType: GridIssueTypes.session,
            metadata: {'rig': 'tgdog', SessionBeadKeys.workBead: 'tg-1'},
          ),
        ];
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [bead('tg-1')],
            ready: {'tg-1'},
            sessions: {'tg-1': live('tgdog-s', 'tg-1')},
          ),
        );
        final owner = _mountFull(joined: joined, ctx: fakes.ctx, sink: sink);
        addTearDown(owner.dispose);

        // The operator's `grid rework` re-keyed the session onto `tg-1#r2`;
        // this mounted scope observes the retirement and closes the round.
        joined.push(
          _joined(
            beads: [bead('tg-1')],
            ready: {'tg-1'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1#r2',
                sessionId: 'tgdog-s',
              ),
            },
          ),
        );
        owner.flush();
        await _pumpUntil(
          owner,
          () => sink.facts('attempt.round.retired').isNotEmpty,
        );

        final retired = sink.fact('attempt.round.retired');
        expect(retired['session_id'], 'tgdog-s');
        // `#r2` is the round being minted, so round 1 is the one retired —
        // the SAME old_round the command handler derived from its own
        // re-key, which is what dedupes the two sites to one record.
        expect(retired['old_round'], 1);
        expect(retired['new_round'], 2);
        expect(retired['cause'], 'rework');
      },
    );

    test(
      'a work bead closing under a live session appends terminal(settled)',
      () async {
        final sink = _CapturingSink();
        final fakes = buildFakes();
        const sessionId = 'tgdog-live';
        fakes.runner.exportBeads = const [
          Bead(
            id: sessionId,
            issueType: GridIssueTypes.session,
            metadata: {
              'rig': 'tgdog',
              SessionBeadKeys.workBead: 'tg-closed',
              SessionBeadKeys.model: kSessionModelMolecule,
            },
          ),
        ];
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [bead('tg-closed')],
            ready: {'tg-closed'},
            sessions: {'tg-closed': live(sessionId, 'tg-closed')},
          ),
        );
        final owner = _mountFull(joined: joined, ctx: fakes.ctx, sink: sink);
        addTearDown(owner.dispose);

        joined.push(
          _joined(
            beads: [
              Bead(
                id: 'tg-closed',
                issueType: IssueType.task,
                status: BeadStatus.closed,
              ),
            ],
            ready: const {},
            sessions: {'tg-closed': live(sessionId, 'tg-closed')},
          ),
        );
        owner.flush();
        await _pumpUntil(
          owner,
          () => fakes.runner
              .callsFor('close')
              .any((call) => call[1] == sessionId),
        );

        final terminal = sink.fact('attempt.terminal');
        expect(terminal['outcome'], 'settled');
        expect(terminal['session_id'], sessionId);
        expect(terminal['work_bead_id'], 'tg-closed');
        // The work-terminal reason rides the record's `reason` — the same
        // string the legacy `grid.work_terminal_reason` write carried.
        expect(terminal['reason'], kWorkTerminalReasonWorkBeadClosed);
        // OBSERVED, not inferred: the station watched this transition happen.
        expect(sink.provenances.last, TrajectoryProvenance.observed);
      },
    );
  });
}
