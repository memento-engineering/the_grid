// tg-4rw / I-10 — a CLOSED session bead with a stale in-flight cursor is a DEAD
// KEY: it never blocks its work bead. The station mounts the bead, RETIRES the
// dead key through the chokepoint, and mints a FRESH session — LOUD. Controls:
// an OPEN session still adopts; a DONE (outcome-marked, or legacy
// all-complete-cursor) session still blocks; a HELD one blocks LOUD; a stale
// fence that is still ALIVE refuses the mint (fail-closed, never double-run).
//
// Zero I/O — the recording chokepoint + a fake transport (Fakes, not mocks).
import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((f) => f.name == name).toList();
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains multiple bd round-trips (`createSession`, THEN
/// `createMolecule`'s dedup-probe export + graph-apply pour — the latter a
/// REAL temp-file write, `BdCliService.applyGraph`'s plan.json) rather than
/// the flat model's single in-memory `create`, so a real-time cushion (not
/// only microtask draining) is what makes waiting for a fresh mint's
/// inflated leaf deterministic under load (tg-eli phase 2).
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

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

JoinedSnapshot _joined(Map<String, SessionProjection> sessions) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: [_task('tg-1')],
    dependencies: const [],
    readyIds: const {'tg-1'},
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

/// The DEAD KEY: closed, `agent` complete, `verify` still `running` with a
/// process fence on record — the I-10 shape (an operator-closed orphan).
const _deadKey = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-dead',
  isTerminal: true,
  cursor: {
    'tg-1/agent': NodeCursor(state: StepState.complete),
    'tg-1/verify': NodeCursor(
      state: StepState.running,
      pgid: 4242,
      pid: 4243,
      token: 'stale',
    ),
  },
);

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ExplorationTransport transport,
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
                services: ServiceBundle(transport: transport),
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

/// The same fakes, with an injected pgid-liveness probe (ADR-0009 D4's seam).
StationServices _withLiveness(StationServices base, AllocationLiveness probe) =>
    StationServices(
      provider: base.provider,
      writer: base.writer,
      stateSubstation: base.stateSubstation,
      liveness: probe,
    );

/// The decoded `--metadata` of every `update` call targeting [id].
List<Map<String, dynamic>> _updatesFor(RecordingBdRunner runner, String id) => [
  for (final c in runner.callsFor('update'))
    if (c.length > 1 && c[1] == id && c.contains('--metadata'))
      jsonDecode(c[c.indexOf('--metadata') + 1]) as Map<String, dynamic>,
];

void main() {
  group('tg-4rw / I-10 — a dead session key mints fresh instead of wedging', () {
    test('a CLOSED session with a stale running cursor: the bead MOUNTS, the '
        'dead key is RETIRED, exactly ONE fresh session is minted, and the '
        'decision is LOUD once', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(_joined(const {'tg-1': _deadKey})),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();
      await _pumpUntil(
        m.owner,
        () => reg.events.isNotEmpty && f.runner.callsFor('create').length >= 2,
      );

      // MINT: exactly one fresh session, plus its molecule pour (tg-eli
      // phase 2: every fresh mint pours a molecule graph) — the pre-fix
      // behavior was ZERO creates at all (the bead never even mounted).
      final creates = f.runner.callsFor('create');
      expect(creates, hasLength(2));
      expect(
        creates.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );

      // RETIRE: the dead key is re-keyed off this bead through the chokepoint,
      // with the WHY recorded beside it.
      final retire = _updatesFor(f.runner, 'tgdog-dead');
      expect(retire, hasLength(1));
      expect(retire.single[SessionBeadKeys.workBead], 'tg-1#void-tgdog-dead');
      expect(
        retire.single[SessionBeadKeys.voidedReason],
        contains('tg-1/verify=running'),
      );

      // LOUD, once — naming the dead session and WHY.
      final voided = transport.named('session.voided');
      expect(voided, hasLength(1));
      expect(voided.single.data['deadSessionId'], 'tgdog-dead');
      expect(voided.single.data['workBeadId'], 'tg-1');
      expect(voided.single.data['reason'], contains('tg-1/verify=running'));

      // The fresh round starts VIRGIN: the frontier mounts `agent`, NOT the dead
      // cursor's `verify` — a fresh session never inherits a dead row's cursor.
      expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
      expect(f.runner.neverShowOrSql, isTrue);
    });

    test('the retire→join-catch-up gap is idempotent: a repeated snapshot still '
        'carrying the dead key neither re-retires nor re-mints, and once the '
        'join catches up the FRESH cursor threads through', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(_joined(const {'tg-1': _deadKey}));
      final m = _mount(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();
      await _pumpUntil(
        m.owner,
        () => reg.events.isNotEmpty && f.runner.callsFor('create').length >= 2,
      );
      final creates = f.runner.callsFor('create');
      expect(creates, hasLength(2));
      expect(
        creates.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );
      reg.events.clear();

      // The bd write has not propagated yet — the join STILL projects the dead
      // session for this bead. The scope is already mounted (same key), so it
      // must not re-key, must not re-mint, and must keep serving the FRESH id
      // over an EMPTY cursor (never the dead row's `verify=running`).
      joined.push(_joined(const {'tg-1': _deadKey}));
      m.owner.flush();
      await _pump();
      expect(f.runner.callsFor('create'), hasLength(2), reason: 'no second mint');
      expect(_updatesFor(f.runner, 'tgdog-dead'), hasLength(1), reason: 'once');
      expect(transport.named('session.voided'), hasLength(1));
      expect(reg.events, isEmpty, reason: 'the agent leaf stays mounted in place');

      // The join catches up: the dead key is gone (re-keyed) and the fresh
      // session projects its own cursor — `agent` done, so `verify` inflates.
      joined.push(
        _joined(const {
          'tg-1': SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-sess1',
            cursor: {'tg-1/agent': NodeCursor(state: StepState.complete)},
          ),
        }),
      );
      m.owner.flush();
      await _pump();
      expect(reg.events, [
        'START verify(tgdog-sess1/tg-1/verify)',
        'STOP agent(tgdog-sess1/tg-1/agent)',
      ]);
      expect(f.runner.callsFor('create'), hasLength(2));
    });

    test('FAIL-CLOSED: a stale fence that still probes ALIVE refuses the mint — '
        'no create, no retire, one LOUD session.voidRefused', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(_joined(const {'tg-1': _deadKey})),
        ctx: _withLiveness(f.ctx, (fence) => true), // the orphan is STILL alive
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      expect(f.runner.callsFor('create'), isEmpty);
      expect(f.runner.callsFor('update'), isEmpty);
      expect(reg.events, isEmpty, reason: 'nothing spawns over a live orphan');
      final refused = transport.named('session.voidRefused');
      expect(refused, hasLength(1));
      expect(refused.single.data['pgids'], '4242');
      expect(refused.single.data['deadSessionId'], 'tgdog-dead');
    });

    test('CONTROL — a DONE session (the grid.outcome marker) still blocks: no '
        'mount, no mint, no retire (landed work is never re-driven)', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-done',
              isTerminal: true,
              completed: true,
            ),
          }),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      expect(f.runner.calls, isEmpty);
      expect(reg.events, isEmpty);
      expect(transport.flares, isEmpty);
    });

    test('CONTROL — a LEGACY done session (no marker, an all-positive-terminal '
        'cursor) still blocks', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-legacy',
              isTerminal: true,
              cursor: {
                'tg-1/agent': NodeCursor(state: StepState.complete),
                'tg-1/verify': NodeCursor(state: StepState.complete),
                'tg-1/land': NodeCursor(state: StepState.complete),
              },
            ),
          }),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      expect(f.runner.calls, isEmpty);
      expect(reg.events, isEmpty);
    });

    test('CONTROL — a HELD session (escalated) blocks, and says WHY exactly '
        'once per bead', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(const {
          'tg-1': SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-esc',
            isTerminal: true,
            humanHeld: true,
            cursor: {
              'tg-1/agent': NodeCursor(state: StepState.failed, restartCount: 3),
            },
          ),
        }),
      );
      final m = _mount(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      expect(f.runner.calls, isEmpty);
      expect(reg.events, isEmpty);
      final held = transport.named('work.held');
      expect(held, hasLength(1));
      expect(held.single.data['sessionId'], 'tgdog-esc');

      // A second snapshot must NOT re-flare (LOUD, never spammy).
      joined.push(
        _joined(const {
          'tg-1': SessionProjection(
            workBeadId: 'tg-1',
            sessionId: 'tgdog-esc',
            isTerminal: true,
            humanHeld: true,
          ),
        }),
      );
      m.owner.flush();
      await _pump();
      expect(transport.named('work.held'), hasLength(1));
    });

    test('CONTROL — an OPEN session for the bead is still ADOPTED (no mint, no '
        'retire): the pre-I-10 live semantics are untouched', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-live',
              cursor: {'tg-1/agent': NodeCursor(state: StepState.running)},
            ),
          }),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      expect(f.runner.callsFor('create'), isEmpty);
      expect(reg.events, ['START agent(tgdog-live/tg-1/agent)']);
      expect(transport.flares, isEmpty);
    });
  });

  group('tg-4rw — the positive-terminal close stamps the DONE evidence', () {
    test('grid.outcome=complete is written through the chokepoint BEFORE the '
        'bd close (so the next mount reads done, not a dead key)', () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final m = _mount(
        joined: JoinedSnapshotNotifier(
          _joined(const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              cursor: {
                'tg-1/agent': NodeCursor(state: StepState.complete),
                'tg-1/verify': NodeCursor(state: StepState.complete),
                'tg-1/land': NodeCursor(state: StepState.complete),
              },
            ),
          }),
        ),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);
      await _pump();

      final calls = f.runner.calls;
      final markIndex = calls.indexWhere(
        (c) =>
            c.isNotEmpty &&
            c.first == 'update' &&
            c.length > 1 &&
            c[1] == 'tgdog-s' &&
            c.join(' ').contains(SessionBeadKeys.outcome),
      );
      final closeIndex = calls.indexWhere(
        (c) =>
            c.isNotEmpty &&
            c.first == 'close' &&
            c.length > 1 &&
            c[1] == 'tgdog-s',
      );
      expect(markIndex, greaterThanOrEqualTo(0), reason: 'the marker is stamped');
      expect(closeIndex, greaterThan(markIndex), reason: 'marker BEFORE close');
      expect(transport.named('session.outcomeUnmarked'), isEmpty);
    });
  });
}
