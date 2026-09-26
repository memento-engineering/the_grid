import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _circuit = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'agent'}),
  ],
);

final class _TimeoutFirstMountAttemptRead implements BeadProbeReader {
  _TimeoutFirstMountAttemptRead(this.delegate);

  final BeadProbeReader delegate;
  bool _timedOut = false;

  @override
  Future<Bead?> beadById(String id, {required Set<IssueType> types}) =>
      delegate.beadById(id, types: types);

  @override
  Future<List<Bead>> openBeads({
    required Set<IssueType> types,
    Map<String, String> metadataAll = const {},
    Map<String, String> metadataAny = const {},
  }) {
    if (!_timedOut && types.contains(GridIssueTypes.mountAttempt)) {
      _timedOut = true;
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

final class _Transport implements ExplorationTransport {
  final flares = <({String name, Map<String, String> data})>[];

  @override
  void flare(String name, Map<String, String> data) {
    flares.add((name: name, data: Map.unmodifiable(data)));
  }

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((flare) => flare.name == name).toList();
}

/// Holds every mount-attempt record CREATE open for [hold] and meters how many
/// are open at once — the reservation-write burst the station-wide bound
/// exists to break (tg-fpvk AC-3).
final class _MeteredMountAttemptRunner extends RecordingBdRunner {
  _MeteredMountAttemptRunner({required this.hold});

  final Duration hold;
  int inFlight = 0;
  int maxInFlight = 0;
  int started = 0;
  int completed = 0;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final type = args.indexOf('--type');
    final isAttemptCreate =
        args.isNotEmpty &&
        args.first == 'create' &&
        type >= 0 &&
        type + 1 < args.length &&
        args[type + 1] == GridIssueTypes.mountAttempt.wire;
    if (!isAttemptCreate) {
      return super.run(args, timeout: timeout, stdin: stdin);
    }
    started += 1;
    inFlight += 1;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(hold);
      return await super.run(args, timeout: timeout, stdin: stdin);
    } finally {
      inFlight -= 1;
      completed += 1;
    }
  }
}

/// How many stamped ready beads the burst test admits at once — more than the
/// bound, so an unbounded burst is unmistakable.
const _burstWidth = 6;

Bead _readyTask(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

Future<void> _settleUntil(bool Function() condition) async {
  for (var i = 0; i < 4000 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

JoinedSnapshot _snapshot({
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: const [
      Bead(id: 'tg-1', issueType: IssueType.task, status: BeadStatus.open),
    ],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime(2026, 9, 4),
  ),
  sessionsByWorkBead: sessions,
);

SessionProjection _freshMolecule(String sessionId) => SessionProjection(
  workBeadId: 'tg-1',
  sessionId: sessionId,
  isMolecule: true,
  moleculeBeads: [
    for (final step in const ['agent', 'land'])
      Bead(
        id: '$sessionId-$step',
        issueType: GridIssueTypes.step,
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
  ],
);

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

bool _plainCreateOf(List<String> args, IssueType type) {
  final typeIndex = args.indexOf('--type');
  return args.isNotEmpty &&
      args.first == 'create' &&
      (args.length < 2 || args[1] != '--graph') &&
      typeIndex >= 0 &&
      typeIndex + 1 < args.length &&
      args[typeIndex + 1] == type.wire;
}

void main() {
  test(
    'a mount-attempt timeout fences session I/O and retries after backoff',
    () async {
      final runner = RecordingBdRunner(createdId: 'tgdog-created');
      final reader = _TimeoutFirstMountAttemptRead(runner);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = StationServices(
        provider: provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: reader,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      );
      addTearDown(station.dispose);
      final transport = _Transport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(_snapshot());
      final owner = TreeOwner();
      owner.mountRoot(
        ProviderScope(
          child: InheritedSeed<JoinedSnapshotNotifier>(
            value: joined,
            child: InheritedSeed<StationServices>(
              value: station,
              child: InheritedSeed<CapabilityRegistry>(
                value: registry,
                child: InheritedSeed<SessionResolver>(
                  value: CircuitResolver((_) => _circuit),
                  child: Station([
                    SubstationScope(
                      configNotifier: SubstationConfigNotifier(
                        const SubstationConfig(
                          substationId: 'tg',
                          ownedSubstations: {'tg'},
                        ),
                      ),
                      services: ServiceBundle(transport: transport),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
      addTearDown(owner.dispose);

      await _pumpUntil(
        owner,
        () => transport.flares.any(
          (flare) => flare.name == 'work.mountAttemptRecordFailed',
        ),
      );

      final failed = transport.flares.singleWhere(
        (flare) => flare.name == 'work.mountAttemptRecordFailed',
      );
      expect(failed.data, containsPair('beadId', 'tg-1'));
      expect(failed.data, containsPair('attempt', '1'));
      expect(
        failed.data,
        containsPair('deadlineConstant', 'DoltQueryService.queryTimeout'),
      );
      expect(failed.data, containsPair('deadlineMs', '10000'));
      expect(
        runner.calls.any(
          (call) => _plainCreateOf(call, GridIssueTypes.session),
        ),
        isFalse,
      );
      expect(runner.graphApplyCalls, isEmpty);
      expect(registry.events, isEmpty);

      // While the released reservation waits out its backoff, the bead is not
      // quiet: the very next admission pass reports it throttled and NAMES the
      // condition (tg-fpvk AC-2) — a missing reservation, not slot contention.
      await _pumpUntil(
        owner,
        () => transport
            .named('work.throttled')
            .any((flare) => flare.data['beadIds'] == 'tg-1'),
      );
      final held = transport
          .named('work.throttled')
          .where((flare) => flare.data['beadIds'] == 'tg-1');
      expect(held, isNotEmpty);
      expect(
        held.every(
          (flare) =>
              flare.data['cause'] == WorkThrottleCause.reservationMissing &&
              flare.data['causes'] ==
                  'tg-1=${WorkThrottleCause.reservationMissing}',
        ),
        isTrue,
        reason: 'every hold during the backoff must read reservation-missing',
      );

      await Future<void>.delayed(
        Backoff.standard.delayFor(1) + const Duration(milliseconds: 50),
      );
      await _pumpUntil(owner, () => runner.graphApplyCalls.isNotEmpty);
      expect(registry.events, isEmpty, reason: 'the joined pour still lags');
      joined.push(
        _snapshot(sessions: {'tg-1': _freshMolecule('tgdog-created')}),
      );
      owner.flush();
      await _pumpUntil(owner, () => registry.events.isNotEmpty);

      expect(
        runner.calls.where(
          (call) => _plainCreateOf(call, GridIssueTypes.mountAttempt),
        ),
        hasLength(1),
      );
      expect(
        runner.calls.where(
          (call) => _plainCreateOf(call, GridIssueTypes.session),
        ),
        hasLength(1),
      );
      expect(runner.graphApplyCalls, hasLength(1));
      expect(registry.events, ['START agent(tgdog-created/tg-1/agent)']);
      // Once re-reserved and minted, the bead is no longer reported held: one
      // more pass over the same live projection adds no throttle for it.
      final throttlesBefore = transport.named('work.throttled').length;
      joined.push(
        _snapshot(sessions: {'tg-1': _freshMolecule('tgdog-created')}),
      );
      owner.flush();
      await _pumpUntil(owner, () => false, maxRounds: 5);
      expect(
        transport
            .named('work.throttled')
            .skip(throttlesBefore)
            .where((flare) => flare.data['beadIds']!.contains('tg-1')),
        isEmpty,
        reason: 'a throttle after the mint would mean the hold never cleared',
      );
    },
  );

  test(
    'a boot burst of $_burstWidth stamped ready beads issues at most '
    'kMountAttemptWriteConcurrency reservation writes at once, station-wide, '
    'and every bead is recorded',
    () async {
      final runner = _MeteredMountAttemptRunner(
        hold: const Duration(milliseconds: 20),
      );
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = StationServices(
        provider: provider,
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
        maxConcurrentWork: _burstWidth,
      );
      addTearDown(station.dispose);
      final beads = [
        for (var i = 1; i <= _burstWidth; i++) _readyTask('tg-$i'),
      ];
      final snapshot = JoinedSnapshot(
        graph: GraphSnapshot.fromParts(
          beads: beads,
          dependencies: const [],
          readyIds: {for (final bead in beads) bead.id},
          capturedAt: DateTime(2026, 9, 25),
        ),
      );
      // Two substation scopes admitting in the SAME flush — the roster shape
      // that made the per-scope count irrelevant and the station count the
      // one that matters.
      final first = station.admission.admitPending(
        snapshot,
        const SubstationConfig(
          substationId: 'tg',
          ownedSubstations: {'tg'},
          maxConcurrentWork: _burstWidth,
        ),
        const ServiceBundle(),
        [
          for (final bead in beads.take(_burstWidth ~/ 2))
            StationAdmissionCandidate(bead: bead, session: null),
        ],
      );
      final second = station.admission.admitPending(
        snapshot,
        const SubstationConfig(
          substationId: 'tg2',
          ownedSubstations: {'tg'},
          maxConcurrentWork: _burstWidth,
        ),
        const ServiceBundle(),
        [
          for (final bead in beads.skip(_burstWidth ~/ 2))
            StationAdmissionCandidate(bead: bead, session: null),
        ],
      );
      expect(first.admitted, hasLength(_burstWidth ~/ 2));
      expect(second.admitted, hasLength(_burstWidth ~/ 2));

      await _settleUntil(() => runner.completed >= _burstWidth);

      // THE STATION BOUND on the reservation burst: an unbounded burst starts
      // all $_burstWidth creates in the same turn and reads $_burstWidth here.
      expect(
        runner.maxInFlight,
        lessThanOrEqualTo(kMountAttemptWriteConcurrency),
        reason:
            'the boot burst opened ${runner.maxInFlight} simultaneous '
            'mount-attempt record writes; the station-wide bound is '
            '$kMountAttemptWriteConcurrency',
      );
      // …and the meter really saw overlap, so the bound is a reached ceiling.
      expect(runner.maxInFlight, greaterThan(1));
      // NONE DROPPED: every bead's reservation was recorded exactly once.
      expect(runner.started, _burstWidth);
      expect(runner.completed, _burstWidth);
    },
  );
}
