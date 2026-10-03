// tg-gxp6 — the TERMINAL-WRITE BOUND and its IN-FLIGHT LATCH.
// `WorkList._projectTerminalAnswers` used to fire one unawaited state-store
// write per closed session, ALL AT ONCE and with no concurrency bound, on
// every build. A real store carrying ~280 closed sessions therefore opened
// that many simultaneous gate closes at boot; the tail of the burst blew
// `DoltQueryService.queryTimeout`, and the failed gate closes cancelled the
// first mint of every ready bead — the station sat UP and ARMED reporting
// `ready > 0, mounted 0`, with no retry.
//
// The fix has TWO halves and each gets a test here:
//
//  1. the BOUND — the sweep drains through at most [kTerminalWriteConcurrency]
//     workers, so an unbounded drain reads the full sweep width on the meter
//     below and fails, while every swept session still reaches the store;
//  2. the LATCH — `_projectTerminalAnswers` runs from `build`, so a rebuild
//     while a slow drain is still open used to start a SECOND sweep over the
//     SAME still-terminal sessions, and the overlapping drains re-formed the
//     very herd the bound exists to break. A rebuild mid-drain must start no
//     second sweep at all.
//
// The meter counts gate writes IN FLIGHT SIMULTANEOUSLY and records every
// write it sees, so both the peak (the bound) and the total (the latch) are
// assertable. Zero I/O — the recording bd chokepoint + a fake transport
// (Fakes, not mocks).
//
// tg-66w8 added the second group: the bound is STATION-WIDE. Per-WorkList it
// multiplied by the roster (lunar's thirteen substations ⇒ up to twenty-six
// simultaneous writes) and re-formed the burst one level up; every
// session-terminal close of epoch 98 died at the deadline and none was
// re-driven. The station-wide group mounts several substations under ONE
// station and meters the whole station, and pins the re-drive of a failed
// close even when the work bead is no longer eligible to re-mount.
import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

const _code = Circuit(
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

/// Wide enough that an unbounded sweep is unmistakable: 16 ≫ 4.
const _sessionCount = 16;

/// The bead a mid-drain snapshot push ADDS. Its `work.terminalSkip` flare is
/// emitted from inside `WorkList.build`, so it is the receipt that the
/// mid-drain flush really did re-enter the build — and its gate is the write a
/// second sweep would have opened.
const _lateBeadIndex = _sessionCount + 1;

const _gateIdPrefix = 'tgdog-gate-';

/// The gates whose first close throws in the retry test — three, so a single
/// dropped retry is unmistakable.
const _flakyGateIndices = [3, 7, 11];

String _workBeadId(int index) => 'tg-$index';

String _sessionId(int index) => 'tgdog-done-$index';

String _gateId(int index) => '$_gateIdPrefix$index';

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((flare) => flare.name == name).toList();
}

/// The live census of terminal gate writes: how many are open RIGHT NOW, the
/// running maximum, and every write that was opened and finished — duplicates
/// INCLUDED, because a second sweep of an already-swept gate is exactly the
/// failure the latch prevents.
final class _InFlightMeter {
  final List<String> entered = <String>[];
  final List<String> completed = <String>[];
  int _inFlight = 0;

  /// The high-water mark of simultaneously open terminal gate writes.
  int maxInFlight = 0;

  void enter(String gateId) {
    entered.add(gateId);
    _inFlight += 1;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
  }

  void exit(String gateId) {
    _inFlight -= 1;
    completed.add(gateId);
  }
}

/// Holds every `bd close <gate>` — the ONE write each gate sweep issues — open
/// for [hold], so a sibling write overlaps observably and the drain stays open
/// long enough for a test to rebuild underneath it. The production failure
/// mode was simultaneity, not slowness, so the write has to stay open to be
/// counted.
final class _MeteredGateWriteRunner extends RecordingBdRunner {
  _MeteredGateWriteRunner(
    this.meter, {
    required this.hold,
    this.failFirstGateIds = const <String>{},
  });

  final _InFlightMeter meter;
  final Duration hold;

  /// Gate ids whose FIRST close throws the store-deadline shape, and whose
  /// second succeeds — the failure the sweep must RETRY rather than memoize.
  final Set<String> failFirstGateIds;

  final Set<String> _alreadyFailed = <String>{};

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    final metered =
        args.length > 1 &&
        args.first == 'close' &&
        args[1].startsWith(_gateIdPrefix);
    if (!metered) return super.run(args, timeout: timeout, stdin: stdin);
    final gateId = args[1];
    meter.enter(gateId);
    try {
      await Future<void>.delayed(hold);
      if (failFirstGateIds.contains(gateId) && _alreadyFailed.add(gateId)) {
        throw TimeoutException('Future not completed');
      }
      return await super.run(args, timeout: timeout, stdin: stdin);
    } finally {
      meter.exit(gateId);
    }
  }
}

/// Settles on wall time ONLY. Flushing is the tree-rebuild lever, so a test
/// that is not deliberately rebuilding must never flush here.
Future<void> _settleUntil(
  bool Function() condition, {
  int maxRounds = 4000,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

/// Every work bead is ready AND carries a `done` terminal session — the exact
/// boot shape that makes the admission authority refuse with clause `done` and
/// hand the whole set to the terminal-gate sweep at once.
JoinedSnapshot _joined({int count = _sessionCount}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [for (var i = 1; i <= count; i++) _task(_workBeadId(i))],
    dependencies: const [],
    readyIds: {for (var i = 1; i <= count; i++) _workBeadId(i)},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: {
    for (var i = 1; i <= count; i++)
      _workBeadId(i): SessionProjection(
        workBeadId: _workBeadId(i),
        sessionId: _sessionId(i),
        isTerminal: true,
        completed: true,
      ),
  },
);

/// The state rows the sweep reads: a CLOSED session row per work bead (the
/// gate-close eligibility evidence) and the one OPEN gate it still owes. The
/// recorder never mutates these, so a gate stays sweepable — a second sweep
/// WOULD write it again, which is what makes the latch's absence visible.
///
/// [gateCount] stages FEWER gates than sessions. A work bead with a session
/// row but no gate still refuses with clause `done` — so `build` reports it —
/// and its terminal write still settles, yet it issues no `bd close`. That is
/// a REBUILD RECEIPT the meter never sees, which is what lets a test assert
/// "this rebuild happened AND cost zero writes".
List<Bead> _stateBeads({int count = _sessionCount, int? gateCount}) => [
  for (var i = 1; i <= count; i++) ...[
    sessionBead(
      id: _sessionId(i),
      workBeadId: _workBeadId(i),
      closed: true,
      outcomeComplete: true,
    ),
    if (i <= (gateCount ?? count))
      Bead(
        id: _gateId(i),
        issueType: GridIssueTypes.gate,
        metadata: {
          'rig': stateSubstation,
          'blocks': _sessionId(i),
          'node': '${_workBeadId(i)}/route',
        },
      ),
  ],
];

/// How many times [index]'s gate was written across the whole episode.
int _writesFor(_InFlightMeter meter, int index) =>
    meter.entered.where((gateId) => gateId == _gateId(index)).length;

/// The `work.terminalSkip` flares naming the LATE bead — emitted from inside
/// `WorkList.build`, so their presence proves a rebuild really re-entered it.
List<({String name, Map<String, String> data})> _lateBuildReceipts(
  _RecordingTransport transport,
) => transport
    .named('work.terminalSkip')
    .where((flare) => flare.data['beadId'] == _workBeadId(_lateBeadIndex))
    .toList();

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ExplorationTransport transport,
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
                  services: ServiceBundle(transport: transport),
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

/// The substations the station-wide group composes — more than the bound, so
/// a per-WorkList bound (bound × substations = 8) is unmistakable against the
/// station bound (2).
const _substationIds = ['sa', 'sb', 'sc', 'sd'];

/// Terminal sessions per substation in the station-wide group.
const _sessionsPerSubstation = 4;

String _stationWorkBeadId(String substation, int index) => '$substation-$index';

String _stationSessionId(String substation, int index) =>
    'tgdog-done-$substation-$index';

String _stationGateId(String substation, int index) =>
    '$_gateIdPrefix$substation-$index';

/// Every work bead of every substation is ready AND carries a `done` terminal
/// session — the boot shape that hands the whole roster's terminal sweep to
/// the drain at once. [attemptCapped] beads additionally carry an EXHAUSTED
/// durable mount-attempt record, so the admission authority refuses them under
/// the attempt-cap clause rather than `done`.
JoinedSnapshot _stationJoined({Set<String> attemptCapped = const {}}) =>
    JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: [
          for (final substation in _substationIds)
            for (var i = 1; i <= _sessionsPerSubstation; i++)
              _task(_stationWorkBeadId(substation, i)),
        ],
        dependencies: const [],
        readyIds: {
          for (final substation in _substationIds)
            for (var i = 1; i <= _sessionsPerSubstation; i++)
              _stationWorkBeadId(substation, i),
        },
        capturedAt: DateTime(2026),
      ),
      sessionsByWorkBead: {
        for (final substation in _substationIds)
          for (var i = 1; i <= _sessionsPerSubstation; i++)
            _stationWorkBeadId(substation, i): SessionProjection(
              workBeadId: _stationWorkBeadId(substation, i),
              sessionId: _stationSessionId(substation, i),
              isTerminal: true,
              completed: true,
            ),
      },
      mountAttemptsByWorkBead: {
        for (final workBeadId in attemptCapped)
          workBeadId: MountAttemptRecord(
            recordId: 'tgdog-attempt-$workBeadId',
            workBeadId: workBeadId,
            count: kMaxMountAttempts,
          ),
      },
    );

/// One closed session row plus its one open gate per work bead, across the
/// whole roster.
List<Bead> _stationStateBeads() => [
  for (final substation in _substationIds)
    for (var i = 1; i <= _sessionsPerSubstation; i++) ...[
      sessionBead(
        id: _stationSessionId(substation, i),
        workBeadId: _stationWorkBeadId(substation, i),
        closed: true,
        outcomeComplete: true,
      ),
      Bead(
        id: _stationGateId(substation, i),
        issueType: GridIssueTypes.gate,
        metadata: {
          'rig': stateSubstation,
          'blocks': _stationSessionId(substation, i),
          'node': '${_stationWorkBeadId(substation, i)}/route',
        },
      ),
    ],
];

/// Mounts ONE station over [_substationIds] substations, each its own
/// `SubstationScope` (and therefore its own `WorkList`), all sharing [ctx].
({TreeOwner owner, Branch root}) _mountStation({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required ExplorationTransport transport,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    ProviderScope(
      child: InheritedSeed<JoinedSnapshotNotifier>(
        value: joined,
        child: InheritedSeed<StationServices>(
          value: ctx,
          child: InheritedSeed<CapabilityRegistry>(
            value: RecordingCapabilityRegistry(circuits: const {}),
            child: InheritedSeed<SessionResolver>(
              value: CircuitResolver((_) => _code),
              child: Station([
                for (final substation in _substationIds)
                  SubstationScope(
                    configNotifier: SubstationConfigNotifier(
                      SubstationConfig(
                        substationId: substation,
                        ownedSubstations: {substation},
                      ),
                    ),
                    services: ServiceBundle(transport: transport),
                    key: ValueKey('scope.$substation'),
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

int _stationWritesFor(_InFlightMeter meter, String gateId) =>
    meter.entered.where((entered) => entered == gateId).length;

StationServices _station(
  _MeteredGateWriteRunner runner,
  FakeRuntimeProvider provider,
) => StationServices(
  provider: provider,
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

void main() {
  group('the boot terminal-gate sweep is concurrency-bounded (tg-gxp6)', () {
    test('$_sessionCount closed sessions sweep with at most '
        'kTerminalWriteConcurrency gate writes in flight, and NONE is '
        'dropped', () async {
      final meter = _InFlightMeter();
      final runner = _MeteredGateWriteRunner(
        meter,
        hold: const Duration(milliseconds: 20),
      )..exportBeads = _stateBeads();
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final mounted = _mount(
        joined: JoinedSnapshotNotifier(_joined()),
        ctx: station,
        registry: registry,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      // No flush: this test bounds ONE drain, and a flush would rebuild
      // `WorkList` underneath it (the latch's territory — the next test).
      await _settleUntil(() => meter.completed.length >= _sessionCount);

      // THE BOUND. An unbounded drain opens all $_sessionCount writes in the
      // same turn and reads $_sessionCount here.
      expect(
        meter.maxInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
        reason:
            'the boot sweep opened ${meter.maxInFlight} simultaneous terminal '
            'gate writes; the drain must never exceed '
            '$kTerminalWriteConcurrency',
      );
      // …and the meter is not trivially satisfied: it really does observe
      // overlap, so `<= 4` is a bound the sweep respects, not one it can never
      // reach.
      expect(
        meter.maxInFlight,
        greaterThan(1),
        reason:
            'the meter never saw two writes overlap — it cannot '
            'distinguish a bounded drain from a broken one',
      );
      // NONE DROPPED: every terminal session was swept, exactly once.
      expect(meter.completed, hasLength(_sessionCount));
      expect(meter.entered, hasLength(_sessionCount));
      expect(meter.entered.toSet(), {
        for (var i = 1; i <= _sessionCount; i++) _gateId(i),
      });
      expect(transport.named('gate.autoCloseFailed'), isEmpty);
      expect(registry.events, isEmpty, reason: 'a done row mounts nothing');
    });

    test('a rebuild MID-DRAIN starts NO second sweep — every gate is written '
        'exactly once across the episode', () async {
      final meter = _InFlightMeter();
      // A wide hold: ~120ms per wave × 4 waves leaves the drain open for
      // roughly half a second, so the flushes below land unambiguously inside
      // it.
      final runner = _MeteredGateWriteRunner(
        meter,
        hold: const Duration(milliseconds: 120),
      )..exportBeads = _stateBeads(count: _lateBeadIndex);
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final registry = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(_joined());
      final mounted = _mount(
        joined: joined,
        ctx: station,
        registry: registry,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _settleUntil(() => meter.entered.isNotEmpty);

      // REBUILD, TWICE, WHILE THE DRAIN IS STILL OPEN. The pushed snapshot
      // adds one more ready bead carrying its own `done` terminal session, so
      // the build has strictly MORE terminal answers to project than the
      // drain that is already running.
      joined.push(_joined(count: _lateBeadIndex));
      mounted.owner.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      mounted.owner.flush();

      // The rebuild really happened: `work.terminalSkip` is emitted from
      // inside `WorkList.build`, and only a build that saw the NEW bead can
      // name it (the per-bead report is deduped, so the original 16 stay
      // silent).
      final lateSkip = transport
          .named('work.terminalSkip')
          .where((flare) => flare.data['beadId'] == _workBeadId(_lateBeadIndex))
          .toList();
      expect(
        lateSkip,
        hasLength(1),
        reason:
            'the mid-drain flush did not re-enter WorkList.build — the '
            'test would be vacuous',
      );
      // …and it happened MID-drain, not after it.
      expect(
        meter.completed.length,
        lessThan(_sessionCount),
        reason:
            'the drain had already finished before the rebuild — the '
            'latch was never exercised',
      );

      await _settleUntil(() => meter.completed.length >= _sessionCount);
      // Let any second drain the rebuild might have started become visible
      // before the census is read.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // THE LATCH. Total work, not just peak: one write per gate for the whole
      // episode. Without it the rebuild opens a second sweep over the same 16
      // still-terminal sessions plus the new one.
      expect(
        meter.entered,
        hasLength(_sessionCount),
        reason:
            'the rebuild started a second sweep: ${meter.entered.length} gate '
            'writes for $_sessionCount terminal sessions',
      );
      expect(
        meter.entered.toSet(),
        {for (var i = 1; i <= _sessionCount; i++) _gateId(i)},
        reason:
            'the swept set must be exactly the drain that was already '
            'running — the late bead is picked up by a LATER sweep, not this one',
      );
      expect(meter.completed, hasLength(_sessionCount));
      // The bound still holds across the rebuild.
      expect(
        meter.maxInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
        reason:
            'two overlapping drains re-formed the herd: '
            '${meter.maxInFlight} writes in flight',
      );
      expect(transport.named('gate.autoCloseFailed'), isEmpty);
    });

    test('a COMPLETED sweep is never re-issued — rebuilds after the drain cost '
        'ZERO gate writes', () async {
      final meter = _InFlightMeter();
      final runner =
          _MeteredGateWriteRunner(meter, hold: const Duration(milliseconds: 5))
            ..exportBeads = _stateBeads(
              count: _lateBeadIndex,
              gateCount: _sessionCount,
            );
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(_joined());
      final mounted = _mount(
        joined: joined,
        ctx: station,
        registry: RecordingCapabilityRegistry(circuits: const {}),
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      // Let the drain FINISH. The in-flight latch is open again, so anything
      // that holds the next sweep back is the settled-session memo alone.
      await _settleUntil(() => meter.completed.length >= _sessionCount);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(meter.entered, hasLength(_sessionCount));

      // Three rebuilds over the SAME still-terminal sessions — the live shape
      // that re-issued a terminal write forever: every closed bead with a
      // linked session re-entered the candidate list on every build, and the
      // station flared ~46 gate.autoCloseFailed a minute for 48 minutes over a
      // store holding ZERO open gates.
      joined.push(_joined(count: _lateBeadIndex));
      for (var i = 0; i < 3; i++) {
        mounted.owner.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      // The rebuilds really happened — only a build that saw the LATE bead can
      // name it, and that bead carries no gate, so the receipt costs the meter
      // nothing.
      expect(
        _lateBuildReceipts(transport),
        hasLength(1),
        reason:
            'the post-drain flushes never re-entered WorkList.build — the '
            'test would be vacuous',
      );
      // THE MEMO. A settled session is skipped by id, so three rebuilds over a
      // fully swept store issue nothing at all.
      expect(
        meter.entered,
        hasLength(_sessionCount),
        reason:
            'rebuilds after a completed sweep re-issued '
            '${meter.entered.length - _sessionCount} terminal writes',
      );
      expect(meter.entered.toSet(), {
        for (var i = 1; i <= _sessionCount; i++) _gateId(i),
      });
      expect(transport.named('gate.autoCloseFailed'), isEmpty);
    });

    test('a FAILED terminal write is RETRIED on the next build, and memoized '
        'only once it succeeds', () async {
      final meter = _InFlightMeter();
      final runner =
          _MeteredGateWriteRunner(
              meter,
              hold: const Duration(milliseconds: 5),
              failFirstGateIds: {
                for (final index in _flakyGateIndices) _gateId(index),
              },
            )
            ..exportBeads = _stateBeads(
              count: _lateBeadIndex,
              gateCount: _sessionCount,
            );
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(_joined());
      final mounted = _mount(
        joined: joined,
        ctx: station,
        registry: RecordingCapabilityRegistry(circuits: const {}),
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      // Drain 1 — all $_sessionCount sessions swept, three of them throwing the
      // store-deadline shape the live incident was made of.
      await _settleUntil(() => meter.completed.length >= _sessionCount);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(meter.entered, hasLength(_sessionCount));

      // Drain 2 — the rebuild re-issues ONLY the three that failed. A memo
      // that latched on dispatch instead of on success would strand them.
      const retried = _sessionCount + 3;
      joined.push(_joined());
      mounted.owner.flush();
      await _settleUntil(() => meter.completed.length >= retried);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // One more rebuild, now that every session has succeeded: the total must
      // stop growing.
      joined.push(_joined(count: _lateBeadIndex));
      mounted.owner.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        _lateBuildReceipts(transport),
        hasLength(1),
        reason:
            'the final flush never re-entered WorkList.build — "the total '
            'stopped growing" would be vacuous',
      );

      // EXACTLY TWICE for the three that failed, EXACTLY ONCE for every other.
      for (var i = 1; i <= _sessionCount; i++) {
        expect(
          _writesFor(meter, i),
          _flakyGateIndices.contains(i) ? 2 : 1,
          reason: '${_gateId(i)} was written ${_writesFor(meter, i)} times',
        );
      }
      expect(
        meter.entered,
        hasLength(retried),
        reason:
            'the episode issued ${meter.entered.length} gate writes for '
            '$_sessionCount sessions with ${_flakyGateIndices.length} '
            'first-attempt failures',
      );
      expect(
        meter.maxInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
        reason: 'the retry drain broke the bound',
      );

      // The failures were LOUD, once each, and kept their store-deadline
      // provenance.
      final failed = transport.named('gate.autoCloseFailed');
      expect(failed, hasLength(_flakyGateIndices.length));
      expect(failed.map((flare) => flare.data['sessionId']).toSet(), {
        for (final index in _flakyGateIndices) _sessionId(index),
      });
      expect(
        failed.every(
          (flare) =>
              flare.data['deadlineConstant'] == 'DoltQueryService.queryTimeout',
        ),
        isTrue,
      );
    });
  });

  group('the terminal-write bound is STATION-WIDE (tg-66w8)', () {
    const totalSessions = _sessionsPerSubstation * 4;

    test('${_substationIds.length} substations × $_sessionsPerSubstation done '
        'sessions sweep with at most kTerminalWriteConcurrency gate writes in '
        'flight ACROSS THE STATION, and NONE is dropped', () async {
      final meter = _InFlightMeter();
      final runner = _MeteredGateWriteRunner(
        meter,
        hold: const Duration(milliseconds: 20),
      )..exportBeads = _stationStateBeads();
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final mounted = _mountStation(
        joined: JoinedSnapshotNotifier(_stationJoined()),
        ctx: station,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      await _settleUntil(() => meter.completed.length >= totalSessions);

      // THE STATION BOUND. A per-WorkList bound opens
      // kTerminalWriteConcurrency × substations writes at once and reads
      // ${kTerminalWriteConcurrency * _substationIds.length} here.
      expect(
        meter.maxInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
        reason:
            'the roster opened ${meter.maxInFlight} simultaneous terminal '
            'gate writes across ${_substationIds.length} substations; the '
            'station-wide bound is $kTerminalWriteConcurrency',
      );
      expect(
        station.terminalWrites.peakInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
      );
      // …and the meter really observed overlap: the bound is a ceiling the
      // drain reaches, not one it can never touch.
      expect(meter.maxInFlight, greaterThan(1));
      // NONE DROPPED: every substation's every terminal session was swept,
      // exactly once.
      expect(meter.completed, hasLength(totalSessions));
      expect(meter.entered.toSet(), {
        for (final substation in _substationIds)
          for (var i = 1; i <= _sessionsPerSubstation; i++)
            _stationGateId(substation, i),
      });
      expect(transport.named('gate.autoCloseFailed'), isEmpty);
    });

    test('a terminal close that fails is RE-DRIVEN on a later build even when '
        'the work bead is no longer eligible to re-mount, and every failure '
        'names its substation and attempt', () async {
      final flaky = {
        _stationGateId('sa', 2): _stationWorkBeadId('sa', 2),
        _stationGateId('sc', 1): _stationWorkBeadId('sc', 1),
        _stationGateId('sd', 4): _stationWorkBeadId('sd', 4),
      };
      final meter = _InFlightMeter();
      final runner = _MeteredGateWriteRunner(
        meter,
        hold: const Duration(milliseconds: 5),
        failFirstGateIds: flaky.keys.toSet(),
      )..exportBeads = _stationStateBeads();
      final provider = FakeRuntimeProvider();
      addTearDown(provider.close);
      final station = _station(runner, provider);
      addTearDown(station.dispose);
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(_stationJoined());
      final mounted = _mountStation(
        joined: joined,
        ctx: station,
        transport: transport,
      );
      addTearDown(mounted.owner.dispose);

      // Drain 1 — the whole roster swept, three closes dying in the
      // store-deadline shape the live incident was made of.
      await _settleUntil(() => meter.completed.length >= totalSessions);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(meter.entered, hasLength(totalSessions));
      final firstFailures = transport.named('gate.autoCloseFailed');
      expect(firstFailures, hasLength(flaky.length));
      for (final failure in firstFailures) {
        final sessionId = failure.data['sessionId']!;
        final substation = sessionId.split('-')[2];
        expect(
          failure.data,
          containsPair('substation', substation),
          reason: 'the failure must name the WorkList that owns the session',
        );
        expect(failure.data, containsPair('attempt', '1'));
        expect(failure.data, containsPair('cause', 'session-terminal'));
        expect(
          failure.data,
          containsPair('deadlineConstant', 'DoltQueryService.queryTimeout'),
        );
      }

      // Drain 2 — the rebuild arrives with the three flaky beads' durable
      // mount-attempt budget EXHAUSTED, so admission refuses them under the
      // attempt-cap clause, not `done`. The gate close is owed all the same.
      joined.push(_stationJoined(attemptCapped: flaky.values.toSet()));
      mounted.owner.flush();
      await _settleUntil(
        () => meter.completed.length >= totalSessions + flaky.length,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // The receipt that the rebuild really did refuse them by eligibility —
      // without it the re-drive assertion below would be testing the `done`
      // path the first group already covers.
      expect(
        transport
            .named('work.mountEligibilityRefused')
            .map((flare) => flare.data['beadId'])
            .toSet(),
        flaky.values.toSet(),
      );

      // EXACTLY TWICE for the three that failed, EXACTLY ONCE for every other,
      // across the whole roster.
      for (final substation in _substationIds) {
        for (var i = 1; i <= _sessionsPerSubstation; i++) {
          final gateId = _stationGateId(substation, i);
          expect(
            _stationWritesFor(meter, gateId),
            flaky.containsKey(gateId) ? 2 : 1,
            reason:
                '$gateId was written ${_stationWritesFor(meter, gateId)} '
                'times',
          );
        }
      }
      expect(meter.entered, hasLength(totalSessions + flaky.length));
      expect(
        meter.maxInFlight,
        lessThanOrEqualTo(kTerminalWriteConcurrency),
        reason: 'the retry drain broke the station-wide bound',
      );
      // The re-drive succeeded, so no second failure was flared, and the
      // three first-attempt failures stay the whole failure record.
      expect(transport.named('gate.autoCloseFailed'), hasLength(flaky.length));

      // A THIRD build issues nothing: every session is memoized on success.
      joined.push(_stationJoined(attemptCapped: flaky.values.toSet()));
      mounted.owner.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(meter.entered, hasLength(totalSessions + flaky.length));
    });

    test('the governor releases a throwing write\'s permit, hands permits to '
        'FIFO waiters, and never exceeds its bound', () async {
      // The governor itself — the contract the WorkList relies on.
      final governor = StateStoreWriteGovernor(bound: 2, lane: 'test');
      final completers = <Completer<void>>[];
      final results = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        final completer = Completer<void>();
        completers.add(completer);
        results.add(
          governor.run(() async {
            await completer.future;
            if (i == 1) throw TimeoutException('Future not completed');
          }),
        );
      }
      // Attached BEFORE the write is released, so the throw is never an
      // unhandled async error.
      final failing = expectLater(results[1], throwsA(isA<TimeoutException>()));
      expect(governor.inFlight, 2);
      expect(governor.queued, 3);
      completers[0].complete();
      completers[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(governor.inFlight, 2);
      expect(governor.queued, 1);
      for (final completer in completers.skip(2)) {
        completer.complete();
      }
      await failing;
      for (final index in [0, 2, 3, 4]) {
        await results[index];
      }
      expect(governor.inFlight, 0);
      expect(governor.queued, 0);
      expect(governor.peakInFlight, 2);
    });
  });
}
