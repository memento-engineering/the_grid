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
  _MeteredGateWriteRunner(this.meter, {required this.hold});

  final _InFlightMeter meter;
  final Duration hold;

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
List<Bead> _stateBeads({int count = _sessionCount}) => [
  for (var i = 1; i <= count; i++) ...[
    sessionBead(
      id: _sessionId(i),
      workBeadId: _workBeadId(i),
      closed: true,
      outcomeComplete: true,
    ),
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
  });
}
