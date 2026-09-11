// tg-6nf — SessionScope mint-failure discipline, WIRING-SHAPED, through the full
// `Station → SubstationScope → WorkList → WorkBead → SessionScope` tree.
//
// FIRST-LIVE-ARM INCIDENT (2026-07-10, boot #1): every `createSession` threw —
// the houston state store rejected `bd create -t session` (no `types.custom`
// configured). `_mint`'s `on Object` catch set `_failed=true` with NO transport
// flare, NO retry, NO surface — the station stood ARMED-but-silently-dead
// (ready 7 / mounted 0 / zero output). Violated LOUD-or-GONE (ADR-0008 D3).
//
// PROVEN HERE:
//   (1) a mint failure FLARES through the emit-only ExplorationTransport (the
//       same sink `_flareRearmFailed` / `CapabilityHost._emitFlare` use) — the
//       dead mint is observable, never an invisible mounted=0.
//   (2) the retry is BOUNDED (`_maxMintAttempts`) then ESCALATES with a distinct
//       terminal flare — never an infinite spin, never a silent permanent latch.
//   (3) a TRANSIENT blip (first attempt throws, then succeeds) RECOVERS with no
//       operator action and NO escalation — proving the fix is not "fail once,
//       give up" but genuine bounded retry.
//
// Zero I/O: fakes + the recording chokepoint + a fake transport.
import 'dart:async';
import 'dart:convert';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/molecule_codec.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';
import 'package:grid_engine/src/seeds/provider.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains multiple bd round-trips (`createSession`, THEN
/// `createMolecule`'s dedup-probe export + graph-apply pour, each its own
/// async gap) — a single pump/flush pair can settle mid-chain, so polling
/// (rather than a fixed pump count) is what makes this deterministic
/// (tg-eli phase 2: the flat model's one-hop `create` no longer applies).
Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    // A molecule mint's `create --graph` pour writes a REAL temp file
    // (`BdCliService.applyGraph`'s plan.json) — genuine disk I/O, not just
    // microtask chaining — so a short real-time cushion is what makes
    // waiting for it deterministic under load (tg-eli phase 2: the flat
    // model's in-memory-only mint never hit disk).
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

GraphSnapshot _work(List<Bead> beads, Set<String> ready) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: const [],
      readyIds: ready,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

GraphSnapshot _state(List<Bead> beads) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: const [],
  capturedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

SessionProjection _freshProjection(String sessionId) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: sessionId,
  isMolecule: true,
  moleculeBeads: _freshSteps(sessionId),
);

Bead _freshSession(String sessionId) => Bead(
  id: sessionId,
  issueType: GridIssueTypes.session,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    SessionBeadKeys.workBead: 'tg-1',
    SessionBeadKeys.model: kSessionModelMolecule,
  },
);

List<Bead> _freshSteps(String sessionId) => [
  for (final step in const ['agent', 'land'])
    Bead(
      id: '$sessionId-$step',
      issueType: GridIssueTypes.step,
      status: BeadStatus.open,
      metadata: {
        'rig': stateSubstation,
        MoleculeStepKeys.stepId: step,
        MoleculeStepKeys.capability: step,
        MoleculeStepKeys.kind: StepKind.job.name,
        MoleculeStepKeys.path: 'tg-1/$step',
        MoleculeStepKeys.session: sessionId,
        MoleculeStepKeys.state: StepState.pending.name,
      },
    ),
];

/// An [ExplorationTransport] that records every LOUD flare — the emit-only sink
/// the mint-failed / mint-exhausted signals fire through.
class _RecordingTransport implements ExplorationTransport {
  _RecordingTransport([this.eventLog]);

  final List<String>? eventLog;
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) {
    eventLog?.add('flare:$name');
    flares.add((name: name, data: data));
  }

  Iterable<({String name, Map<String, String> data})> named(String name) =>
      flares.where((f) => f.name == name);
}

final class _CapturingTrajectorySink implements TrajectoryRecordSink {
  final records = <TrajectoryRecord>[];

  @override
  bool get accepting => true;

  @override
  void enqueue(
    TrajectoryRecord record, {
    DateTime? occurredAt,
    String? substation,
    TrajectoryProvenance provenance = TrajectoryProvenance.observed,
    String? provenanceBasis,
  }) => records.add(record);
}

final class _CountingReapReader implements BeadProbeReader {
  final beadIds = <String>[];

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    beadIds.add(id);
    return null;
  }

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) async => const [];

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) async => const [];
}

/// A [BdRunner] that THROWS the first [failCreates] `create` calls (as the live
/// store did — `bd create -t session` rejected) then succeeds. `failCreates`
/// larger than the mint budget models the PERSISTENT misconfiguration; `1`
/// models a transient blip. Records every argv in order.
class _FailCreateRunner implements BdRunner {
  _FailCreateRunner({
    required this.failCreates,
    this.failSessionCreateAttempts = const {},
    this.failGraphApplies = 0,
    this.rawGraphTimeouts = 0,
    this.failListsWithTimeout = false,
    this.graphApplyError,
    this.sessionCreateError,
    this.eventLog,
  });

  final int failCreates;
  final Set<int> failSessionCreateAttempts;
  final int failGraphApplies;
  final int rawGraphTimeouts;
  final bool failListsWithTimeout;
  final Object? graphApplyError;
  final Object? sessionCreateError;
  final List<String>? eventLog;
  final List<List<String>> calls = <List<String>>[];
  int _creates = 0;
  int _graphApplies = 0;
  int _listTimeoutCount = 0;
  Completer<void>? closeEntered;
  Completer<void>? closeGate;

  /// The `key → id` map a `bd create --graph` pour reports (mirrors
  /// [RecordingBdRunner.graphApplyIds]) — `createMolecule`'s graph-apply pour
  /// throws `BdParseException` on a missing `ids` map, so every successful
  /// mint attempt (this fake's `create --graph` branch) must report one, even
  /// when empty.
  Map<String, String> graphApplyIds = const <String, String>{};

  List<List<String>> callsFor(String sub) =>
      calls.where((c) => c.isNotEmpty && c.first == sub).toList();

  /// Creates EXCLUDING the durable remount-budget record (tg-zlfu) — mirrors
  /// `RecordingBdRunner.workCreates`, so these mint assertions keep counting
  /// only the sessions and molecules they mean to count.
  List<List<String>> get workCreates => callsFor('create').where((c) {
    final i = c.indexOf('--type');
    return i < 0 || i + 1 >= c.length || c[i + 1] != 'mount-attempt';
  }).toList();

  Map<String, dynamic> metadataOfUpdate(int index) {
    final call = callsFor('update')[index];
    final metadata = <String, dynamic>{};
    for (var i = 0; i < call.length - 1; i++) {
      if (call[i] != '--set-metadata') continue;
      final assignment = call[i + 1];
      final separator = assignment.indexOf('=');
      if (separator < 0) continue;
      metadata[assignment.substring(0, separator)] = assignment.substring(
        separator + 1,
      );
    }
    return metadata;
  }

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    eventLog?.add('bd:${args.join(' ')}');
    calls.add(List<String>.unmodifiable(args));
    final sub = args.isNotEmpty ? args.first : '';
    if (sub == 'close' && closeGate != null) {
      closeEntered?.complete();
      await closeGate!.future;
    }
    if (sub == 'list' &&
        failListsWithTimeout &&
        args.length > 2 &&
        (args[2] == GridIssueTypes.molecule.wire ||
            args[2] == GridIssueTypes.step.wire)) {
      // The full tree can schedule duplicate readiness checks while the first
      // dedup probe is in flight. Keep those pending, as a real 15s process
      // timeout would be, so this regression observes the first terminal park.
      if (_listTimeoutCount >= 2) return Completer<BdResult>().future;
      _listTimeoutCount++;
      throw BdTimeoutException(
        command: args,
        timeout: const Duration(seconds: 15),
      );
    }
    if (sub == 'query') {
      return const BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":[]}',
        stderr: '',
      );
    }
    if (sub == 'list') {
      return const BdResult(
        exitCode: 0,
        stdout: '{"schema_version":1,"data":[]}',
        stderr: '',
      );
    }
    final isGraphApply =
        sub == 'create' && args.length > 1 && args[1] == '--graph';
    if (isGraphApply) {
      _graphApplies++;
      if (_graphApplies <= rawGraphTimeouts) {
        throw TimeoutException('fake raw molecule timeout');
      }
      if (_graphApplies <= failGraphApplies) {
        throw graphApplyError ?? StateError('fake molecule graph pour refused');
      }
      return BdResult(
        exitCode: 0,
        stdout: jsonEncode({
          'schema_version': 1,
          'data': {'ids': graphApplyIds},
        }),
        stderr: '',
      );
    }
    final typeIndex = args.indexOf('--type');
    final type = typeIndex >= 0 && typeIndex + 1 < args.length
        ? args[typeIndex + 1]
        : '';
    if (sub == 'create' && type == GridIssueTypes.session.wire) {
      _creates++;
      if (_creates <= failCreates ||
          failSessionCreateAttempts.contains(_creates)) {
        final error = sessionCreateError;
        if (error != null) throw error;
        throw StateError(
          'fake bd create rejected #$_creates (no types.custom)',
        );
      }
      return BdResult(
        exitCode: 0,
        stdout:
            '{"schema_version":1,"data":{"id":"tgdog-sess${_creates - failCreates}"}}',
        stderr: '',
      );
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

final class _TimeoutMoleculeReads implements BeadProbeReader {
  _TimeoutMoleculeReads(this.delegate, {required this.remaining});

  final BeadProbeReader delegate;
  int remaining;
  int timeoutCount = 0;
  bool _allowRetirementRead = false;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (_allowRetirementRead && types.contains(GridIssueTypes.molecule)) {
      _allowRetirementRead = false;
    } else if (remaining > 0 && types.contains(GridIssueTypes.molecule)) {
      remaining--;
      timeoutCount++;
      _allowRetirementRead = true;
      throw TimeoutException('Future not completed');
    }
    return delegate.openBeads(
      types: types,
      metadataAll: metadataAll,
      metadataAny: metadataAny,
    );
  }

  @override
  Future<List<Bead>> openSuperseding(Set<String> priorIds) =>
      delegate.openSuperseding(priorIds);
}

/// A lifecycle reader whose first gate-session assertion fails, then behaves
/// like an empty store so the fresh-mint retry can re-pour the retained session.
class _ThrowOnceGateReader extends RecordingBdRunner {
  _ThrowOnceGateReader(TimeoutException error) : _error = error;

  TimeoutException? _error;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) async {
    final error = _error;
    if (error != null) {
      _error = null;
      throw error;
    }
    return super.beadById(id, types: types);
  }
}

/// A [StationServices] whose chokepoint writes through [runner], owning
/// [stateSubstation] — the same shape [buildFakes] builds, over a caller-
/// supplied runner so a test asserts against it directly.
StationServices _ctxOver(
  BdRunner runner, {
  BeadProbeReader reader = const EmptyBeadProbeReader(),
  int maxConcurrentWork = kDefaultMaxConcurrentWork,
}) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: reader,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
  maxConcurrentWork: maxConcurrentWork,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ServiceBundle services,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
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
    ),
  );
  return (owner: owner, root: root);
}

/// Re-provides authority grants under one constant provider key so the
/// descendant [SessionScope] retains its State across a post-void re-admission.
/// This isolates the contract from WorkList's current unmount/remount side
/// effect and proves the already-mounted execution surface consumes the grant.
final class _MutableReservationHost extends StatefulSeed {
  const _MutableReservationHost({
    required this.initialReservation,
    required this.snapshot,
    required this.ctx,
    required this.registry,
    required this.services,
    required this.onState,
    this.trajectoryScope,
  });

  final StationAdmissionReservation initialReservation;
  final JoinedSnapshot? snapshot;
  final StationServices ctx;
  final CapabilityRegistry registry;
  final ServiceBundle services;
  final void Function(_MutableReservationHostState state) onState;
  final TrajectoryRecorderScope? trajectoryScope;

  @override
  State<_MutableReservationHost> createState() =>
      _MutableReservationHostState();
}

final class _MutableReservationHostState
    extends State<_MutableReservationHost> {
  late StationAdmissionReservation _reservation;
  SessionProjection? _projection;

  @override
  void initState() {
    _reservation = seed.initialReservation;
    _projection = _reservation.candidate.session;
    seed.onState(this);
  }

  void provide(StationAdmissionReservation reservation) => setState(() {
    _reservation = reservation;
    _projection = reservation.candidate.session;
  });

  void project(SessionProjection projection) =>
      setState(() => _projection = projection);

  void refreshReservationDependency() {
    final reservation = _reservation;
    setState(() {
      _reservation = StationAdmissionReservation(
        candidate: reservation.candidate,
        substationId: reservation.substationId,
        mountAttempt: reservation.mountAttempt,
        sessionId: reservation.sessionId,
        adopted: reservation.adopted,
        reservationToken: reservation.reservationToken,
      );
    });
  }

  @override
  Seed build(TreeContext context) {
    Seed child = InheritedSeed<StationServices>(
      value: seed.ctx,
      child: InheritedSeed<CapabilityRegistry>(
        value: seed.registry,
        child: InheritedSeed<ServiceBundle>(
          value: seed.services,
          child: Provider<StationAdmissionReservation>.value(
            _reservation,
            key: const ValueKey('preserved-reservation'),
            child: SessionScope(
              bead: bead('tg-1'),
              circuit: _code,
              existingSession: _projection,
            ),
          ),
        ),
      ),
    );
    if (seed.snapshot case final snapshot?) {
      child = InheritedSeed<JoinedSnapshot>(value: snapshot, child: child);
    }
    if (seed.trajectoryScope case final trajectoryScope?) {
      child = InheritedSeed<TrajectoryRecorderScope>(
        value: trajectoryScope,
        child: child,
      );
    }
    return child;
  }
}

({TreeOwner owner, Branch root}) _mountPreservedReservation({
  required StationAdmissionReservation reservation,
  required JoinedSnapshot? snapshot,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ServiceBundle services,
  required void Function(_MutableReservationHostState state) onState,
  TrajectoryRecorderScope? trajectoryScope,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: _MutableReservationHost(
        initialReservation: reservation,
        snapshot: snapshot,
        ctx: ctx,
        registry: registry,
        services: services,
        onState: onState,
        trajectoryScope: trajectoryScope,
      ),
    ),
  );
  return (owner: owner, root: root);
}

void Function() _deliverReplacementReservations({
  required StationServices ctx,
  required JoinedSnapshot snapshot,
  required SubstationConfig config,
  required ServiceBundle services,
  required StationAdmissionCandidate candidate,
  required StationAdmissionReservation initialReservation,
  required _MutableReservationHostState host,
  void Function()? onDelivery,
}) {
  Object? replacementToken;
  return ctx.admission.addInvalidationListener(() {
    final batch = ctx.admission.admitPending(snapshot, config, services, [
      candidate,
    ]);
    if (batch.admitted.isEmpty) return;
    final next = batch.admitted.single;
    final token = next.reservationToken;
    if (next.sessionId != null ||
        token == null ||
        identical(token, initialReservation.reservationToken) ||
        identical(token, replacementToken)) {
      return;
    }
    replacementToken = token;
    host.provide(next);
    onDelivery?.call();
  });
}

Branch _sessionScopeBranch(Branch root) {
  final all = <Branch>[];
  void collect(Branch branch) {
    all.add(branch);
    branch.visitChildren(collect);
  }

  collect(root);
  return all.singleWhere((branch) => branch.seed is SessionScope);
}

TreeNode _sessionScopeNodeOf(Branch root) {
  final snapshot = DiagnosticsTreeWalker().walk(
    root,
    projectedAt: DateTime.utc(2026, 9, 5),
  );
  final nodes = <TreeNode>[];
  void collect(TreeNode node) {
    nodes.add(node);
    node.children.forEach(collect);
  }

  collect(snapshot.root);
  return nodes.singleWhere((node) => node.seedType == 'SessionScope');
}

DiagnosticsFlagProperty _mintFailedPropertyOf(Branch root) =>
    _sessionScopeNodeOf(
          root,
        ).properties.singleWhere((property) => property.name == 'mintFailed')
        as DiagnosticsFlagProperty;

DiagnosticsIntProperty _moleculePourVoidsPropertyOf(Branch root) =>
    _sessionScopeNodeOf(root).properties.singleWhere(
          (property) => property.name == 'moleculePourVoids',
        )
        as DiagnosticsIntProperty;

void main() {
  test(
    'tg-akc8 boot burst: a timed-out mint is voided and a live bead refuses a second attempt',
    () async {
      final runner = _FailCreateRunner(failCreates: 0, rawGraphTimeouts: 1);
      runner.closeEntered = Completer<void>();
      runner.closeGate = Completer<void>();
      final reapReader = _CountingReapReader();
      final station = _ctxOver(runner, reader: reapReader);
      addTearDown(station.dispose);
      const config = SubstationConfig(
        substationId: 'tg',
        ownedSubstations: {'tg'},
        maxConcurrentWork: 1,
      );
      final workBead = bead('tg-1');
      final candidate = StationAdmissionCandidate(
        bead: workBead,
        session: null,
      );
      final snapshot = JoinedSnapshot(graph: _work([workBead], {'tg-1'}));
      var invalidations = 0;
      station.admission.addInvalidationListener(() => invalidations++);

      final first = station.admission.admitPending(
        snapshot,
        config,
        const ServiceBundle(),
        [candidate],
      );
      expect(first.admitted, hasLength(1));
      expect(first.admitted.single.mountAttempt, isNull);
      final created = await station.admission.createSessionAttempt(
        snapshot,
        candidate,
        title: 'grid session tg-1',
        metadata: const {SessionBeadKeys.model: kSessionModelMolecule},
      );
      expect(created.sessionId, 'tgdog-sess1');

      final plan = instantiateMolecule(
        _code,
        sessionId: created.sessionId!,
        root: BeadPathKey(['tg-1', created.sessionId!]),
        nodePath: 'tg-1',
      );
      final pour = station.admission.pourMolecule(
        plan,
        workBeadId: 'tg-1',
        sessionId: created.sessionId!,
        rootCrumbs: ['tg-1', created.sessionId!],
        services: const ServiceBundle(),
      );
      await runner.closeEntered!.future;
      final rivalBead = bead('tg-2');
      final rival = StationAdmissionCandidate(bead: rivalBead, session: null);
      final bothSnapshot = JoinedSnapshot(
        graph: _work([workBead, rivalBead], {'tg-1', 'tg-2'}),
      );
      final heldBeforeClose = station.admission.admitPending(
        bothSnapshot,
        config,
        const ServiceBundle(),
        [candidate, rival],
      );
      expect(
        heldBeforeClose.waiting.map((entry) => entry.bead.id),
        contains('tg-2'),
      );

      runner.closeGate!.complete();
      await expectLater(
        pour,
        throwsA(
          isA<StationMintVoided>()
              .having((error) => error.workBeadId, 'workBeadId', 'tg-1')
              .having(
                (error) => error.retiredSessionId,
                'retiredSessionId',
                'tgdog-sess1',
              ),
        ),
      );
      expect(reapReader.beadIds, contains('tgdog-sess1'));

      final reusable = station.admission.admitPending(
        bothSnapshot,
        config,
        const ServiceBundle(),
        [rival],
      );
      expect(reusable.admitted.single.candidate.bead.id, 'tg-2');
      expect(reusable.admitted.single.mountAttempt, isNull);
      await _pump();
      expect(
        station.admission
            .admitPending(bothSnapshot, config, const ServiceBundle(), [rival])
            .admitted
            .single
            .candidate
            .bead
            .id,
        'tg-2',
      );

      final updateIndex = runner.calls.indexWhere(
        (call) => call.isNotEmpty && call.first == 'update',
      );
      final closeIndex = runner.calls.indexWhere(
        (call) => call.isNotEmpty && call.first == 'close',
      );
      expect(updateIndex, greaterThanOrEqualTo(0));
      expect(closeIndex, greaterThan(updateIndex));
      final updateCalls = runner.callsFor('update');
      final voidUpdate = updateCalls.indexWhere(
        (call) => call.any((arg) => arg.contains('tg-1#void-tgdog-sess1')),
      );
      expect(voidUpdate, greaterThanOrEqualTo(0));
      final voidMetadata = runner.metadataOfUpdate(voidUpdate);
      expect(voidMetadata[SessionBeadKeys.workBead], 'tg-1#void-tgdog-sess1');
      expect(voidMetadata[SessionBeadKeys.voidedReason], 'mint-timeout');
      expect(
        runner.callsFor('create').where((call) => call.contains('gate')),
        isEmpty,
      );

      const live = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-live',
      );
      final liveSnapshot = JoinedSnapshot(
        graph: snapshot.graph,
        sessionsByWorkBead: const {'tg-1': live},
      );
      final second = await station.admission.createSessionAttempt(
        liveSnapshot,
        StationAdmissionCandidate(bead: workBead, session: live),
        title: 'second session',
        metadata: const {},
      );
      expect(second.sessionId, isNull);
      expect(second.refusal?.clause, 'live-attempt');
      expect(
        runner.workCreates.where((call) => !call.contains('--graph')),
        hasLength(1),
      );

      final beforeBackoff = invalidations;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(invalidations, beforeBackoff + 1);
    },
  );

  test(
    'fresh-frontier refusal abandons its reservation and admits a rival in the same tick',
    () async {
      final runner = _FailCreateRunner(failCreates: 0);
      final ctx = _ctxOver(runner, maxConcurrentWork: 2);
      addTearDown(ctx.dispose);
      final transport = _RecordingTransport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final workBead = bead('tg-1');
      final rivalBead = bead('tg-2');
      const retired = SessionProjection(
        workBeadId: 'tg-1#r1',
        sessionId: 'tgdog-round1',
      );
      final candidate = StationAdmissionCandidate(
        bead: workBead,
        session: retired,
      );
      final rival = StationAdmissionCandidate(bead: rivalBead, session: null);
      const config = SubstationConfig(
        substationId: 'tg',
        ownedSubstations: {'tg'},
        maxConcurrentWork: 2,
      );
      final initiallyReady = JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [workBead, rivalBead],
          dependencies: const [],
          readyIds: const {'tg-1', 'tg-2'},
          capturedAt: DateTime.now(),
        ),
      );
      final initial = ctx.admission.admitPending(
        initiallyReady,
        config,
        ServiceBundle(transport: transport),
        [candidate],
      );
      expect(initial.admitted.single.candidate.bead.id, 'tg-1');

      final dependencyBlocked = JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: [workBead, rivalBead],
          dependencies: const [
            BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-2'),
          ],
          readyIds: const {'tg-2'},
          capturedAt: DateTime.now().add(const Duration(seconds: 1)),
        ),
      );
      final services = ServiceBundle(transport: transport);
      final mounted = _mountPreservedReservation(
        reservation: initial.admitted.single,
        snapshot: dependencyBlocked,
        ctx: ctx,
        registry: registry,
        services: services,
        onState: (_) {},
      );
      addTearDown(mounted.owner.dispose);
      await _pumpUntil(
        mounted.owner,
        () => transport.named('session.mintAbandoned').isNotEmpty,
      );

      const refusalReason = 'work bead is absent from the fresh ready frontier';
      final refused = transport.named('session.mintRefused').single;
      expect(refused.data['reason'], refusalReason);
      final abandoned = transport.named('session.mintAbandoned').single;
      expect(abandoned.data['stage'], 'fresh-snapshot');
      expect(abandoned.data['reason'], refusalReason);
      expect(ctx.admission.admissionStatus.reservations, isEmpty);
      expect(runner.workCreates, isEmpty);

      final sameSnapshotAdmission = ctx.admission.admitPending(
        dependencyBlocked,
        config,
        services,
        [candidate, rival],
      );
      expect(sameSnapshotAdmission.waiting.single.bead.id, 'tg-1');
      expect(sameSnapshotAdmission.admitted.single.candidate.bead.id, 'tg-2');
      expect(
        ctx.admission.admissionStatus.reservations.map(
          (reservation) => reservation.bead,
        ),
        ['tg-2'],
      );
    },
  );

  test('session-attempt refusal abandons an unconsumed reservation', () async {
    final runner = _FailCreateRunner(failCreates: 0);
    final ctx = _ctxOver(runner);
    addTearDown(ctx.dispose);
    final transport = _RecordingTransport();
    final services = ServiceBundle(transport: transport);
    final registry = RecordingCapabilityRegistry(circuits: const {});
    final workBead = bead('tg-1');
    final candidate = StationAdmissionCandidate(bead: workBead, session: null);
    final reservationSnapshot = JoinedSnapshot(
      graph: _work([workBead], {'tg-1'}),
    );
    final initial = ctx.admission.admitPending(
      reservationSnapshot,
      const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
      services,
      [candidate],
    );
    expect(initial.admitted, hasLength(1));

    const live = SessionProjection(workBeadId: 'tg-1', sessionId: 'tgdog-live');
    final liveSnapshot = JoinedSnapshot(
      graph: reservationSnapshot.graph,
      sessionsByWorkBead: const {'tg-1': live},
    );
    final mounted = _mountPreservedReservation(
      reservation: initial.admitted.single,
      snapshot: liveSnapshot,
      ctx: ctx,
      registry: registry,
      services: services,
      onState: (_) {},
    );
    addTearDown(mounted.owner.dispose);
    await _pumpUntil(
      mounted.owner,
      () => transport.named('session.mintAbandoned').isNotEmpty,
    );

    final refused = transport.named('session.mintRefused').single;
    expect(refused.data['clause'], 'live-attempt');
    expect(
      refused.data['reason'],
      'a live durable attempt already links this bead',
    );
    final abandoned = transport.named('session.mintAbandoned').single;
    expect(abandoned.data['stage'], 'session-attempt-refused');
    expect(
      abandoned.data['reason'],
      'a live durable attempt already links this bead',
    );
    expect(ctx.admission.admissionStatus.reservations, isEmpty);
    expect(runner.workCreates, isEmpty);
  });

  test(
    'unavailable fresh snapshot remains a one-shot observable wait',
    () async {
      final runner = _FailCreateRunner(failCreates: 0);
      final ctx = _ctxOver(runner);
      addTearDown(ctx.dispose);
      final transport = _RecordingTransport();
      final services = ServiceBundle(transport: transport);
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final sink = _CapturingTrajectorySink();
      final trajectoryScope = TrajectoryRecorderScope(
        StationTrajectoryRecorder(
          sink: sink,
          substationPrefixes: const {'tg', 'tgdog'},
        ),
      );
      final workBead = bead('tg-1');
      const retired = SessionProjection(
        workBeadId: 'tg-1#r1',
        sessionId: 'tgdog-round1',
      );
      final candidate = StationAdmissionCandidate(
        bead: workBead,
        session: retired,
      );
      final initial = ctx.admission.admitPending(
        JoinedSnapshot(graph: _work([workBead], {'tg-1'})),
        const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'}),
        services,
        [candidate],
      );
      expect(initial.admitted, hasLength(1));
      late _MutableReservationHostState host;
      final mounted = _mountPreservedReservation(
        reservation: initial.admitted.single,
        snapshot: null,
        ctx: ctx,
        registry: registry,
        services: services,
        onState: (state) => host = state,
        trajectoryScope: trajectoryScope,
      );
      addTearDown(mounted.owner.dispose);
      await _pumpUntil(
        mounted.owner,
        () => transport.named('session.mintRefused').isNotEmpty,
      );

      host.refreshReservationDependency();
      mounted.owner.flush();
      await _pump();
      host.refreshReservationDependency();
      mounted.owner.flush();
      await _pump();

      const unavailableReason = 'fresh joined snapshot is unavailable';
      final refused = transport.named('session.mintRefused').single;
      expect(refused.data['reason'], unavailableReason);
      final outcomes = sink.records
          .where((record) => record.recordType == 'attempt.mint.outcome')
          .toList();
      expect(outcomes, hasLength(1));
      expect(outcomes.single.payloadToJson()['phase'], 'refused');
      expect(outcomes.single.payloadToJson()['reason'], unavailableReason);
      expect(transport.named('session.mintAbandoned'), isEmpty);
      expect(runner.workCreates, isEmpty);
      expect(ctx.admission.admissionStatus.reservations.single.bead, 'tg-1');
    },
  );

  group('SessionScope mint failure (tg-6nf)', () {
    test(
      'a PERSISTENT mint failure FLARES every attempt, retries a BOUNDED number '
      'of times, then ESCALATES loud — never a silent latch, never an inflated '
      'leaf',
      () async {
        final runner = _FailCreateRunner(failCreates: 100); // always rejects.
        final ctx = _ctxOver(runner);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: FakeSnapshotSource(_state(const [])),
        )..start();
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

        // BOUNDED: exactly the mint budget of createSession attempts — not one
        // (the old give-up-on-first-failure), not an infinite spin.
        expect(
          runner.workCreates,
          hasLength(5),
          reason: 'the mint is retried a bounded number of times (5), no more',
        );
        expect(
          _mintFailedPropertyOf(m.root).value,
          isTrue,
          reason: 'the mounted scope retains its exhausted mint failure',
        );

        // LOUD: every attempt under budget flared `session.mintFailed`, and the
        // exhausted attempt flared exactly one terminal `session.mintExhausted`.
        expect(
          transport.named('session.mintFailed'),
          hasLength(4),
          reason: 'attempts 1..4 flare mintFailed while still retrying',
        );
        final exhausted = transport.named('session.mintExhausted').toList();
        expect(
          exhausted,
          hasLength(1),
          reason: 'the spent budget escalates with one terminal flare',
        );
        // VISIBLE: the escalation flare names the dead-minting work bead so an
        // observer can count it — never an anonymous mounted=0.
        expect(exhausted.single.data['workBeadId'], 'tg-1');
        expect(exhausted.single.data['attempt'], '5');
        expect(exhausted.single.data['maxAttempts'], '5');
        expect(exhausted.single.data['reason'], isNotEmpty);
        expect(exhausted.single.data, isNot(contains('deadlineConstant')));
        expect(exhausted.single.data, isNot(contains('deadlineMs')));
        for (final failed in transport.named('session.mintFailed')) {
          expect(failed.data, isNot(contains('deadlineConstant')));
          expect(failed.data, isNot(contains('deadlineMs')));
        }

        // INERT: no session minted → no leaf inflated (the scope renders Idle).
        expect(
          reg.events,
          isEmpty,
          reason: 'a failed mint never inflates the circuit',
        );
        // The chokepoint stayed pristine (never `bd show`, never SQL).
        expect(
          runner.calls.every(
            (c) => c.isEmpty || (c.first != 'show' && c.first != 'sql'),
          ),
          isTrue,
        );
      },
    );

    test(
      'mint retries and exhaustion retain raw SQL deadline provenance',
      () async {
        final runner = _FailCreateRunner(
          failCreates: 100,
          sessionCreateError: TimeoutException('Future not completed'),
        );
        final ctx = _ctxOver(runner);
        addTearDown(ctx.dispose);
        final transport = _RecordingTransport();
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: FakeSnapshotSource(_state(const [])),
        )..start();
        addTearDown(bridge.dispose);
        final m = _mountFull(
          joined: bridge.notifier,
          ctx: ctx,
          registry: RecordingCapabilityRegistry(circuits: const {}),
          services: ServiceBundle(transport: transport),
        );
        addTearDown(m.owner.dispose);

        await _pumpUntil(
          m.owner,
          () => transport.named('session.mintExhausted').isNotEmpty,
        );

        final deadlineFlares = [
          ...transport.named('session.mintFailed'),
          ...transport.named('session.mintExhausted'),
        ];
        expect(deadlineFlares, hasLength(5));
        for (final flare in deadlineFlares) {
          expect(
            flare.data,
            containsPair('deadlineConstant', 'DoltQueryService.queryTimeout'),
          );
          expect(flare.data, containsPair('deadlineMs', '10000'));
        }
      },
    );

    test('a thrown molecule POUR (post-createSession) flares once, parks the '
        'existing session at a durable gate, and never burns the mint budget — '
        'terminal, not retried (tg-aec)', () async {
      final runner = _FailCreateRunner(failCreates: 0, failGraphApplies: 1);
      final ctx = _ctxOver(runner);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final bridge = StationJoinBridge(
        work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
        state: FakeSnapshotSource(_state(const [])),
      )..start();
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
      // The park chains createSession → thrown pour → gate create → the
      // gate's blocks/node metadata stamp; settle on the stamp landing.
      await _pumpUntil(m.owner, () {
        final updates = runner.callsFor('update');
        return [
          for (var i = 0; i < updates.length; i++) runner.metadataOfUpdate(i),
        ].any((metadata) => metadata.containsKey('blocks'));
      });

      // LOUD once, with the cause: one moleculePourFailed naming the parked
      // session, its work bead, and the thrown error.
      final parked = transport.named('session.moleculePourFailed').toList();
      expect(parked, hasLength(1));
      expect(parked.single.data['sessionId'], 'tgdog-sess1');
      expect(parked.single.data['workBeadId'], 'tg-1');
      expect(
        parked.single.data['reason'],
        contains('fake molecule graph pour refused'),
      );
      expect(parked.single.data, isNot(contains('deadlineConstant')));
      expect(parked.single.data, isNot(contains('deadlineMs')));

      // ONE pour attempt — the park is terminal, never a blind re-pour.
      expect(
        runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );
      // Exactly two plain creates: the session, then the gate bead.
      expect(
        runner.workCreates.where((c) => c.length <= 1 || c[1] != '--graph'),
        hasLength(2),
      );
      // The gate stamp carries the re-arm linkage + the cause.
      final updates = runner.callsFor('update');
      final stamps = [
        for (var i = 0; i < updates.length; i++)
          if (runner.metadataOfUpdate(i).containsKey('blocks'))
            runner.metadataOfUpdate(i),
      ];
      expect(stamps, hasLength(1));
      final stamp = stamps.single;
      expect(stamp['blocks'], 'tgdog-sess1');
      expect(stamp['node'], 'tg-1');
      expect(stamp['reason'], contains('fake molecule graph pour refused'));

      // The mint budget is UNTOUCHED: a post-session pour failure is not a
      // mint failure — no retry flares, no exhaustion escalation.
      expect(transport.named('session.mintFailed'), isEmpty);
      expect(transport.named('session.mintExhausted'), isEmpty);

      // INERT: the parked session never inflates the circuit.
      expect(reg.events, isEmpty);
    });

    test(
      'bd graph deadline re-mints from a replacement grant without remounting',
      () async {
        final events = <String>[];
        final runner = _FailCreateRunner(
          failCreates: 0,
          failGraphApplies: 1,
          graphApplyError: const BdTimeoutException(
            command: ['bd', 'create', '--graph', 'plan.json'],
            timeout: BdCliService.pourTimeout,
          ),
          eventLog: events,
        );
        final ctx = _ctxOver(runner);
        addTearDown(ctx.dispose);
        final transport = _RecordingTransport(events);
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final sink = _CapturingTrajectorySink();
        final trajectoryScope = TrajectoryRecorderScope(
          StationTrajectoryRecorder(
            sink: sink,
            substationPrefixes: const {'tg', 'tgdog'},
          ),
        );
        final workBead = bead('tg-1');
        final snapshot = JoinedSnapshot(graph: _work([workBead], {'tg-1'}));
        const config = SubstationConfig(
          substationId: 'tg',
          ownedSubstations: {'tg'},
        );
        final services = ServiceBundle(transport: transport);
        final candidate = StationAdmissionCandidate(
          bead: workBead,
          session: null,
        );
        final initial = ctx.admission.admitPending(snapshot, config, services, [
          candidate,
        ]);
        expect(initial.admitted, hasLength(1));
        final initialReservation = initial.admitted.single;
        late _MutableReservationHostState reservationHost;
        final m = _mountPreservedReservation(
          reservation: initialReservation,
          snapshot: snapshot,
          ctx: ctx,
          registry: reg,
          services: services,
          onState: (state) => reservationHost = state,
          trajectoryScope: trajectoryScope,
        );
        addTearDown(m.owner.dispose);
        final scopeBranchId = _sessionScopeBranch(m.root).branchId;
        var replacementDeliveries = 0;
        final removeInvalidation = _deliverReplacementReservations(
          ctx: ctx,
          snapshot: snapshot,
          config: config,
          services: services,
          candidate: candidate,
          initialReservation: initialReservation,
          host: reservationHost,
          onDelivery: () => replacementDeliveries++,
        );
        addTearDown(removeInvalidation);
        await _pumpUntil(
          m.owner,
          () => transport.named('session.mintAbandoned').isNotEmpty,
        );

        final abandoned = transport.named('session.mintAbandoned').single;
        expect(abandoned.data['workBeadId'], 'tg-1');
        expect(abandoned.data['retiredSessionId'], 'tgdog-sess1');
        expect(abandoned.data['stage'], 'molecule-pour');
        expect(abandoned.data['reason'], 'mint-timeout');
        expect(
          abandoned.data,
          containsPair('deadlineConstant', 'BdCliService.pourTimeout'),
        );
        expect(abandoned.data, containsPair('deadlineMs', '60000'));
        expect(_moleculePourVoidsPropertyOf(m.root).value, 1);
        expect(transport.named('session.moleculePourFailed'), isEmpty);
        expect(transport.named('session.mintFailed'), isEmpty);
        expect(reg.events, isEmpty);

        final voidUpdate = runner
            .callsFor('update')
            .singleWhere(
              (call) =>
                  call.length > 1 &&
                  call[1] == 'tgdog-sess1' &&
                  call.contains(
                    '${SessionBeadKeys.workBead}=tg-1#void-tgdog-sess1',
                  ),
            );
        expect(
          voidUpdate,
          contains('${SessionBeadKeys.voidedReason}=mint-timeout'),
        );
        final closeIndex = events.indexWhere(
          (event) => event.startsWith('bd:close tgdog-sess1 '),
        );
        final flareIndex = events.indexOf('flare:session.mintAbandoned');
        expect(closeIndex, isNonNegative);
        expect(closeIndex, lessThan(flareIndex));
        expect(
          runner.callsFor('create').where((call) => call.contains('gate')),
          isEmpty,
        );
        final terminalRecords = sink.records
            .where((record) => record.recordType == 'attempt.terminal')
            .toList();
        expect(terminalRecords, hasLength(1));
        expect(
          terminalRecords.single.correlationToJson(),
          containsPair('outcome', 'lost'),
        );
        expect(
          terminalRecords.single.payloadToJson(),
          containsPair('reason', 'mint-timeout'),
        );
        final retiredRecords = sink.records
            .where((record) => record.recordType == 'attempt.round.retired')
            .toList();
        expect(retiredRecords, hasLength(1));
        expect(
          retiredRecords.single.payloadToJson(),
          containsPair('cause', 'void'),
        );
        expect(_sessionScopeBranch(m.root).branchId, scopeBranchId);

        await Future<void>.delayed(
          Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
        );
        await _pumpUntil(
          m.owner,
          () => runner.calls.any((call) => call.contains('--graph')),
        );
        expect(reg.events, isEmpty, reason: 'the joined pour still lags');
        reservationHost.project(_freshProjection('tgdog-sess2'));
        m.owner.flush();
        await _pumpUntil(m.owner, () => reg.events.isNotEmpty);
        final sessionCreates = runner.workCreates.where((call) {
          final typeIndex = call.indexOf('--type');
          return typeIndex >= 0 &&
              call[typeIndex + 1] == GridIssueTypes.session.wire;
        });
        expect(sessionCreates, hasLength(2));
        expect(
          runner.calls.where((call) => call.contains('--graph')),
          hasLength(2),
        );
        expect(runner.callsFor('close'), hasLength(1));
        expect(replacementDeliveries, 1);
        expect(_sessionScopeBranch(m.root).branchId, scopeBranchId);
        expect(reg.events, ['START agent(tgdog-sess2/tg-1/agent)']);
        expect(transport.named('session.mintFailed'), isEmpty);
        expect(transport.named('session.mintExhausted'), isEmpty);
        expect(_mintFailedPropertyOf(m.root).value, isFalse);
        expect(_moleculePourVoidsPropertyOf(m.root).value, 0);
      },
    );

    test('consecutive bd graph deadlines exhaust after three voids', () async {
      final runner = _FailCreateRunner(
        failCreates: 0,
        failGraphApplies: 4,
        graphApplyError: const BdTimeoutException(
          command: ['bd', 'create', '--graph', 'plan.json'],
          timeout: BdCliService.pourTimeout,
        ),
      );
      final ctx = _ctxOver(runner);
      addTearDown(ctx.dispose);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final workBead = bead('tg-1');
      final snapshot = JoinedSnapshot(graph: _work([workBead], {'tg-1'}));
      const config = SubstationConfig(
        substationId: 'tg',
        ownedSubstations: {'tg'},
      );
      final services = ServiceBundle(transport: transport);
      final candidate = StationAdmissionCandidate(
        bead: workBead,
        session: null,
      );
      final initial = ctx.admission.admitPending(snapshot, config, services, [
        candidate,
      ]);
      expect(initial.admitted, hasLength(1));
      final initialReservation = initial.admitted.single;
      late _MutableReservationHostState reservationHost;
      final m = _mountPreservedReservation(
        reservation: initialReservation,
        snapshot: snapshot,
        ctx: ctx,
        registry: reg,
        services: services,
        onState: (state) => reservationHost = state,
      );
      addTearDown(m.owner.dispose);
      var replacementDeliveries = 0;
      final removeInvalidation = _deliverReplacementReservations(
        ctx: ctx,
        snapshot: snapshot,
        config: config,
        services: services,
        candidate: candidate,
        initialReservation: initialReservation,
        host: reservationHost,
        onDelivery: () => replacementDeliveries++,
      );
      addTearDown(removeInvalidation);

      await _pumpUntil(
        m.owner,
        () => transport.named('session.moleculePourExhausted').isNotEmpty,
        maxRounds: 4000,
      );
      expect(
        transport.named('session.moleculePourExhausted'),
        hasLength(1),
        reason:
            'deliveries=$replacementDeliveries graphApplies='
            '${runner.calls.where((call) => call.contains('--graph')).length} '
            'creates=${runner.workCreates.length} flares=${transport.flares}',
      );

      await _pumpUntil(
        m.owner,
        () => replacementDeliveries >= 3,
        maxRounds: 2000,
      );
      await _pump();
      m.owner.flush();
      await _pump();

      final sessionCreates = runner.workCreates.where((call) {
        final typeIndex = call.indexOf('--type');
        return typeIndex >= 0 &&
            call[typeIndex + 1] == GridIssueTypes.session.wire;
      });
      expect(sessionCreates, hasLength(3));
      expect(transport.named('session.mintAbandoned'), hasLength(3));
      for (final abandoned in transport.named('session.mintAbandoned')) {
        expect(abandoned.data['stage'], 'molecule-pour');
        expect(abandoned.data['reason'], 'mint-timeout');
        expect(abandoned.data['deadlineConstant'], 'BdCliService.pourTimeout');
        expect(abandoned.data['deadlineMs'], '60000');
      }
      expect(
        runner.calls.where((call) => call.contains('--graph')),
        hasLength(3),
      );
      expect(runner.callsFor('close'), hasLength(3));
      expect(
        runner.callsFor('create').where((call) => call.contains('gate')),
        isEmpty,
      );
      expect(transport.named('session.moleculePourFailed'), isEmpty);
      expect(reg.events, isEmpty);
      final exhausted = transport.named('session.moleculePourExhausted').single;
      expect(exhausted.data, {
        'workBeadId': 'tg-1',
        'retiredSessionId': 'tgdog-sess3',
        'attempt': '3',
        'maxAttempts': '3',
        'reason': 'mint-timeout',
        'deadlineConstant': 'BdCliService.pourTimeout',
        'deadlineMs': '60000',
      });
      expect(_moleculePourVoidsPropertyOf(m.root).value, 3);
      expect(replacementDeliveries, 3);
      expect(transport.named('session.mintExhausted'), isEmpty);
      expect(transport.named('session.moleculePourStalled'), isEmpty);
    });

    test('pour void preserves the create-session failure budget', () async {
      final runner = _FailCreateRunner(
        failCreates: 0,
        failSessionCreateAttempts: const {1, 3},
      );
      final reader = _TimeoutMoleculeReads(
        const EmptyBeadProbeReader(),
        remaining: 1,
      );
      final ctx = _ctxOver(runner, reader: reader);
      addTearDown(ctx.dispose);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final workBead = bead('tg-1');
      final snapshot = JoinedSnapshot(graph: _work([workBead], {'tg-1'}));
      const config = SubstationConfig(
        substationId: 'tg',
        ownedSubstations: {'tg'},
      );
      final services = ServiceBundle(transport: transport);
      final candidate = StationAdmissionCandidate(
        bead: workBead,
        session: null,
      );
      final initial = ctx.admission.admitPending(snapshot, config, services, [
        candidate,
      ]);
      expect(initial.admitted, hasLength(1));
      final initialReservation = initial.admitted.single;
      late _MutableReservationHostState reservationHost;
      final m = _mountPreservedReservation(
        reservation: initialReservation,
        snapshot: snapshot,
        ctx: ctx,
        registry: reg,
        services: services,
        onState: (state) => reservationHost = state,
      );
      addTearDown(m.owner.dispose);
      var replacementDeliveries = 0;
      final removeInvalidation = _deliverReplacementReservations(
        ctx: ctx,
        snapshot: snapshot,
        config: config,
        services: services,
        candidate: candidate,
        initialReservation: initialReservation,
        host: reservationHost,
        onDelivery: () => replacementDeliveries++,
      );
      addTearDown(removeInvalidation);
      await _pumpUntil(
        m.owner,
        () => transport.named('session.mintAbandoned').isNotEmpty,
      );
      expect(transport.named('session.mintFailed').single.data['attempt'], '1');
      expect(_mintFailedPropertyOf(m.root).value, isTrue);
      expect(_moleculePourVoidsPropertyOf(m.root).value, 1);
      await _pumpUntil(
        m.owner,
        () => runner.calls.any((call) => call.contains('--graph')),
        maxRounds: 2500,
      );
      expect(reg.events, isEmpty, reason: 'the joined pour still lags');
      reservationHost.project(_freshProjection('tgdog-sess4'));
      m.owner.flush();
      await _pumpUntil(m.owner, () => reg.events.isNotEmpty);
      final mintFailures = transport.named('session.mintFailed').toList();
      expect(mintFailures, hasLength(2));
      expect(mintFailures.map((flare) => flare.data['attempt']), ['1', '3']);
      expect(_mintFailedPropertyOf(m.root).value, isFalse);
      expect(_moleculePourVoidsPropertyOf(m.root).value, 0);
      expect(reader.timeoutCount, 1);
      expect(replacementDeliveries, 1);
      expect(reg.events, ['START agent(tgdog-sess4/tg-1/agent)']);
      expect(transport.named('session.mintExhausted'), isEmpty);
      expect(transport.named('session.moleculePourExhausted'), isEmpty);
    });

    test(
      'a fresh-mint park failure propagates to the bounded mint retry',
      () async {
        final runner = _FailCreateRunner(failCreates: 0, failGraphApplies: 1);
        final gateTimeout = TimeoutException('fake gate assertion timed out');
        final ctx = _ctxOver(runner, reader: _ThrowOnceGateReader(gateTimeout));
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final stateSource = FakeSnapshotSource(_state(const []));
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: stateSource,
        )..start();
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
        await _pumpUntil(
          m.owner,
          () =>
              runner.calls
                  .where((c) => c.length > 1 && c[1] == '--graph')
                  .length >=
              2,
        );
        expect(reg.events, isEmpty, reason: 'the joined pour still lags');
        stateSource.push(
          _state([_freshSession('tgdog-sess1'), ..._freshSteps('tgdog-sess1')]),
        );
        await _pumpUntil(m.owner, () => reg.events.isNotEmpty);

        final pourFailures = transport
            .named('session.moleculePourFailed')
            .toList();
        expect(pourFailures, hasLength(1));
        expect(
          pourFailures.single.data['reason'],
          contains('fake molecule graph pour refused'),
        );

        final mintFailures = transport.named('session.mintFailed').toList();
        expect(mintFailures, hasLength(1));
        expect(mintFailures.single.data['reason'], contains('$gateTimeout'));
        expect(
          runner.workCreates.where((c) => c.length <= 1 || c[1] != '--graph'),
          hasLength(1),
          reason: 'the retry reuses the first durable session id',
        );
        expect(
          runner.calls.where((c) => c.length > 1 && c[1] == '--graph'),
          hasLength(2),
        );
        expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
        expect(transport.named('session.mintExhausted'), isEmpty);
      },
    );

    test('a timed-out molecule dedup read flares and parks without burning the '
        'mint budget', () async {
      final runner = _FailCreateRunner(
        failCreates: 0,
        failListsWithTimeout: true,
      );
      final reader = CliBeadProbeReader(
        BdCliService(runner),
        lifecycleTypes: const {GridIssueTypes.molecule, GridIssueTypes.step},
      );
      final ctx = _ctxOver(runner, reader: reader);
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final bridge = StationJoinBridge(
        work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
        state: FakeSnapshotSource(_state(const [])),
      )..start();
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
      await _pumpUntil(m.owner, () {
        final updates = runner.callsFor('update');
        return [
          for (var i = 0; i < updates.length; i++) runner.metadataOfUpdate(i),
        ].any((metadata) => metadata.containsKey('blocks'));
      });

      expect(transport.named('session.moleculePourFailed'), hasLength(1));
      expect(
        runner.workCreates.where(
          (call) => call.length <= 1 || call[1] != '--graph',
        ),
        hasLength(2),
      );
      expect(runner.calls.where((call) => call.contains('--graph')), isEmpty);
      final stamps = [
        for (var i = 0; i < runner.callsFor('update').length; i++)
          if (runner.metadataOfUpdate(i).containsKey('blocks'))
            runner.metadataOfUpdate(i),
      ];
      expect(stamps, hasLength(1));
      expect(stamps.single['blocks'], 'tgdog-sess1');
      expect(transport.named('session.mintFailed'), isEmpty);
      expect(transport.named('session.mintExhausted'), isEmpty);
    });

    test(
      'a TRANSIENT mint blip (first attempt throws, then succeeds) RECOVERS — '
      'flares once, never escalates, and the session mints + inflates',
      () async {
        final runner = _FailCreateRunner(failCreates: 1); // one blip, then ok.
        final ctx = _ctxOver(runner);
        final transport = _RecordingTransport();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final stateSource = FakeSnapshotSource(_state(const []));
        final bridge = StationJoinBridge(
          work: FakeSnapshotSource(_work([bead('tg-1')], {'tg-1'})),
          state: stateSource,
        )..start();
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
        await _pumpUntil(m.owner, () => runner.workCreates.length >= 3);
        expect(reg.events, isEmpty, reason: 'the joined pour still lags');
        stateSource.push(
          _state([_freshSession('tgdog-sess1'), ..._freshSteps('tgdog-sess1')]),
        );
        await _pumpUntil(m.owner, () => reg.events.isNotEmpty);

        // RETRIED: attempt #1's `createSession` dropped, attempt #2's
        // succeeded — never latched off. `callsFor('create')` also carries
        // the successful attempt's `create --graph` molecule pour (tg-eli
        // phase 2: every fresh mint pours a molecule), so the plain-create
        // count is 2 (the failed + the recovered `createSession`) plus one
        // graph-apply.
        final creates = runner.workCreates;
        expect(creates, hasLength(3));
        expect(
          creates.where((c) => c.length > 1 && c[1] == '--graph'),
          hasLength(1),
        );
        // The single drop was LOUD but there was NO escalation.
        expect(transport.named('session.mintFailed'), hasLength(1));
        expect(
          transport.named('session.mintExhausted'),
          isEmpty,
          reason: 'a recovered blip must not escalate',
        );
        // RECOVERED: the minted session inflated the first step.
        expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
        expect(
          _mintFailedPropertyOf(m.root).value,
          isFalse,
          reason: 'successful recovery clears the active mint failure',
        );
      },
    );
  });
}
