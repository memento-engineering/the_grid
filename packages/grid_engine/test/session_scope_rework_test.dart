// tg-x1j v2 — the gate-resolve REWORK transition: a latched-gated
// SessionScope observes `grid rework`'s re-key (the adopted session vanishing
// from the join while this branch stays mounted, A40) and re-arms IN PLACE —
// closes the retired round, mints round N+1 — with no station restart. Also
// covers the guard-principle decline: a session that vanishes WITHOUT ever
// having been observed gated is never silently abandoned. Zero I/O: fakes +
// the recording chokepoint.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';
import 'package:grid_engine/src/seeds/provider.dart';
import 'package:grid_runtime/grid_runtime.dart';

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

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((flare) => flare.name == name).toList();
}

class _GatedCloseRunner extends RecordingBdRunner {
  final closeEntered = Completer<void>();
  final releaseClose = Completer<void>();

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (args.isNotEmpty && args.first == 'close') {
      if (!closeEntered.isCompleted) closeEntered.complete();
      await releaseClose.future;
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

enum _AbandonmentStage {
  voidSessionRetired('void-session-retired'),
  mintCatch('mint-catch'),
  moleculeSessionCreated('molecule-session-created'),
  moleculePoured('molecule-poured'),
  moleculePourParked('molecule-pour-parked');

  const _AbandonmentStage(this.wireName);
  final String wireName;
}

typedef _AbandonmentCase = ({
  _AbandonmentStage stage,
  bool Function(List<String> args) gateCall,
  bool throwAfterRelease,
});

class _StageGatedRunner extends RecordingBdRunner {
  _StageGatedRunner({
    required this.gateCall,
    this.throwAfterRelease = false,
    super.createdId = 'tgdog-round2',
  });

  final bool Function(List<String> args) gateCall;
  final bool throwAfterRelease;
  final entered = Completer<void>();
  final release = Completer<void>();
  var _gated = false;

  @override
  Future<BdResult> run(
    List<String> args, {
    Duration? timeout,
    String? stdin,
  }) async {
    if (!_gated && gateCall(args)) {
      _gated = true;
      entered.complete();
      await release.future;
      if (throwAfterRelease) {
        throw StateError('controlled bd failure');
      }
    }
    return super.run(args, timeout: timeout, stdin: stdin);
  }
}

bool _isPlainCreateOf(List<String> args, String type) {
  final typeIndex = args.indexOf('--type');
  return args.isNotEmpty &&
      args.first == 'create' &&
      (args.length < 2 || args[1] != '--graph') &&
      typeIndex >= 0 &&
      typeIndex + 1 < args.length &&
      args[typeIndex + 1] == type;
}

bool _setsMetadata(List<String> args, String key) =>
    args.isNotEmpty &&
    args.first == 'update' &&
    args.any((arg) => arg.contains(key));

void _expectAbandonment(
  _RecordingTransport transport, {
  required String retiredSessionId,
  required String stage,
  Object reason = const TypeMatcher<String>(),
}) {
  final flares = transport.named('session.mintAbandoned');
  expect(flares, hasLength(1));
  expect(flares.single.data['workBeadId'], 'tg-1');
  expect(flares.single.data['retiredSessionId'], retiredSessionId);
  expect(flares.single.data['stage'], stage);
  expect(flares.single.data['reason'], reason);
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Drains the microtask queue and renders every dirty rebuild it produced,
/// repeating until [condition] is satisfied or [maxRounds] is spent. A
/// molecule mint chains TWO bd round-trips (`createSession`, then
/// `createMolecule`'s dedup-probe export + graph-apply pour, each its own
/// async gap) rather than the flat model's single `create` — polling is what
/// makes waiting for round N+1's mint deterministic (tg-eli phase 2).
Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    // A molecule mint's `create --graph` pour writes a REAL temp file
    // (`BdCliService.applyGraph`'s plan.json) — genuine disk I/O, not just
    // microtask chaining — so a short real-time cushion (not only
    // `pumpEventQueue`) is what makes waiting for it deterministic under
    // load (tg-eli phase 2: the flat model's in-memory-only mint never hit
    // disk).
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  required DateTime capturedAt,
  List<BeadDependency> dependencies = const [],
  Map<String, SessionProjection> sessions = const {},
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: dependencies,
    readyIds: ready,
    capturedAt: capturedAt,
  ),
  sessionsByWorkBead: sessions,
);

Bead _task(String id, {BeadStatus status = BeadStatus.open}) =>
    Bead(id: id, issueType: IssueType.task, status: status);

const _tgConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
  driveList: {'tg-1'},
);

const _voidedSession = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-void',
  isTerminal: true,
  cursor: {
    'tg-1/agent': NodeCursor(
      state: StepState.running,
      pgid: 42,
      pid: 43,
      token: 'stale',
    ),
  },
);

StationServices _servicesFor(RecordingBdRunner runner) => StationServices(
  provider: FakeRuntimeProvider(),
  writer: StationBeadWriter(
    bd: BdCliService(runner),
    reader: runner,
    ownership: BeadOwnershipPredicate(const {stateSubstation}),
  ),
  stateSubstation: stateSubstation,
);

({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
  ExplorationTransport? transport,
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
              value: CircuitResolver(rootCircuit),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(_tgConfig),
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

void main() {
  group('SessionScope rework re-arm (tg-x1j v2) — the gated case re-mints', () {
    test('disposing after retirement begins emits one reasoned abandonment '
        'flare and creates no successor', () async {
      final runner = _GatedCloseRunner();
      final ctx = StationServices(
        provider: FakeRuntimeProvider(),
        writer: StationBeadWriter(
          bd: BdCliService(runner),
          reader: runner,
          ownership: BeadOwnershipPredicate(const {stateSubstation}),
        ),
        stateSubstation: stateSubstation,
      );
      final transport = _RecordingTransport();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime.now().subtract(const Duration(seconds: 1)),
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: ctx,
        registry: RecordingCapabilityRegistry(circuits: const {}),
        rootCircuit: (_) => _code,
        transport: transport,
      );
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime.now(),
          sessions: const {
            'tg-1#r1': SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
            ),
          },
        ),
      );
      m.owner.flush();
      await runner.closeEntered.future;
      m.owner.dispose();
      runner.releaseClose.complete();
      await _pump();

      final flare = transport.named('session.mintAbandoned').single;
      expect(flare.data['workBeadId'], 'tg-1');
      expect(flare.data['retiredSessionId'], 'tgdog-round1');
      expect(flare.data['stage'], 'retired-gates-closed');
      expect(flare.data['reason'], anyOf('cancelled', 'unmounted'));
      expect(runner.workCreates, isEmpty);
    });

    test('disposing while the fresh-snapshot barrier is pending emits one '
        'reasoned abandonment flare', () async {
      final originalGrace = SessionScopeState.freshMintSnapshotGrace;
      addTearDown(() {
        SessionScopeState.freshMintSnapshotGrace = originalGrace;
      });
      SessionScopeState.freshMintSnapshotGrace = Duration.zero;
      final runner = RecordingBdRunner(createdId: 'tgdog-round2');
      final transport = _RecordingTransport();
      final beforeDecision = DateTime.now().subtract(const Duration(days: 1));
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: beforeDecision,
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: _servicesFor(runner),
        registry: RecordingCapabilityRegistry(circuits: const {}),
        rootCircuit: (_) => _code,
        transport: transport,
      );

      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {},
          capturedAt: beforeDecision,
          sessions: const {
            'tg-1#r1': SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
            ),
          },
        ),
      );
      m.owner.flush();
      await _pumpUntil(
        m.owner,
        () => transport.named('session.mintRefused').isNotEmpty,
      );
      expect(runner.workCreates, isEmpty);
      expect(transport.named('session.mintRefused'), hasLength(1));

      m.owner.dispose();
      await _pump();

      _expectAbandonment(
        transport,
        retiredSessionId: 'tgdog-round1',
        stage: 'fresh-snapshot',
        reason: anyOf('cancelled', 'unmounted'),
      );
      // `_awaitFreshReadySnapshot` has exactly one null-completion path:
      // `dispose`, which sets `_cancelled` before this continuation runs.
      // This direct receipt proves `snapshot-unavailable` is unreachable while
      // the round-one production ordering stands.
      expect(
        transport.named('session.mintAbandoned').single.data['reason'],
        isNot('snapshot-unavailable'),
      );
      expect(runner.workCreates, isEmpty);
    });

    test('disposing after the fresh snapshot releases the barrier emits the '
        'fresh-snapshot-ready stage', () async {
      final originalGrace = SessionScopeState.freshMintSnapshotGrace;
      addTearDown(() {
        SessionScopeState.freshMintSnapshotGrace = originalGrace;
      });
      SessionScopeState.freshMintSnapshotGrace = const Duration(days: 1);
      final runner = RecordingBdRunner(createdId: 'tgdog-round2');
      final transport = _RecordingTransport();
      final beforeDecision = DateTime.now().subtract(const Duration(days: 1));
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: beforeDecision,
          sessions: const {
            'tg-1': SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: _servicesFor(runner),
        registry: RecordingCapabilityRegistry(circuits: const {}),
        rootCircuit: (_) => _code,
        transport: transport,
      );
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: beforeDecision,
          sessions: const {
            'tg-1#r1': SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
            ),
          },
        ),
      );
      m.owner.flush();
      await _pumpUntil(m.owner, () => runner.callsFor('close').isNotEmpty);

      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime.now().add(const Duration(days: 1)),
          sessions: const {
            'tg-1#r1': SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
            ),
          },
        ),
      );
      m.owner.flush();
      m.owner.dispose();
      await _pump();

      _expectAbandonment(
        transport,
        retiredSessionId: 'tgdog-round1',
        stage: 'fresh-snapshot-ready',
        reason: anyOf('cancelled', 'unmounted'),
      );
      expect(runner.workCreates, isEmpty);
    });

    final abandonmentCases = <_AbandonmentCase>[
      (
        stage: _AbandonmentStage.voidSessionRetired,
        gateCall: (args) => _setsMetadata(args, 'grid.voided_reason'),
        throwAfterRelease: false,
      ),
      (
        stage: _AbandonmentStage.mintCatch,
        gateCall: (args) => _isPlainCreateOf(args, 'session'),
        throwAfterRelease: true,
      ),
      (
        stage: _AbandonmentStage.moleculeSessionCreated,
        gateCall: (args) => _isPlainCreateOf(args, 'session'),
        throwAfterRelease: false,
      ),
      (
        stage: _AbandonmentStage.moleculePoured,
        gateCall: (args) =>
            args.length > 1 && args[0] == 'create' && args[1] == '--graph',
        throwAfterRelease: false,
      ),
      (
        stage: _AbandonmentStage.moleculePourParked,
        gateCall: (args) =>
            args.length > 1 && args[0] == 'create' && args[1] == '--graph',
        throwAfterRelease: true,
      ),
    ];

    for (final abandonmentCase in abandonmentCases) {
      test('disposing at ${abandonmentCase.stage.wireName} emits its literal '
          'abandonment stage and stops the lifecycle', () async {
        final runner = _StageGatedRunner(
          gateCall: abandonmentCase.gateCall,
          throwAfterRelease: abandonmentCase.throwAfterRelease,
          createdId: 'tgdog-round2',
        );
        final transport = _RecordingTransport();
        final isVoid =
            abandonmentCase.stage == _AbandonmentStage.voidSessionRetired;
        final now = DateTime.now();
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1')],
            ready: {'tg-1'},
            capturedAt: now.add(const Duration(seconds: 1)),
            sessions: isVoid
                ? const {'tg-1': _voidedSession}
                : const {
                    'tg-1': SessionProjection(
                      workBeadId: 'tg-1',
                      sessionId: 'tgdog-round1',
                      cursor: {
                        'tg-1/route': NodeCursor(state: StepState.gated),
                      },
                    ),
                  },
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: _servicesFor(runner),
          registry: RecordingCapabilityRegistry(circuits: const {}),
          rootCircuit: (_) => _code,
          transport: transport,
        );
        if (!isVoid) {
          joined.push(
            _joined(
              beads: [_task('tg-1')],
              ready: {'tg-1'},
              capturedAt: now.add(const Duration(days: 1)),
              sessions: const {
                'tg-1#r1': SessionProjection(
                  workBeadId: 'tg-1#r1',
                  sessionId: 'tgdog-round1',
                ),
              },
            ),
          );
          m.owner.flush();
        }

        await runner.entered.future;
        m.owner.dispose();
        runner.release.complete();
        await _waitUntil(
          () => transport.named('session.mintAbandoned').isNotEmpty,
        );

        _expectAbandonment(
          transport,
          retiredSessionId: isVoid ? '' : 'tgdog-round1',
          stage: abandonmentCase.stage.wireName,
          reason: anyOf('cancelled', 'unmounted'),
        );
        switch (abandonmentCase.stage) {
          case _AbandonmentStage.voidSessionRetired:
          case _AbandonmentStage.mintCatch:
            expect(runner.graphApplyCalls, isEmpty);
          case _AbandonmentStage.moleculeSessionCreated:
            expect(runner.graphApplyCalls, isEmpty);
          case _AbandonmentStage.moleculePoured:
          case _AbandonmentStage.moleculePourParked:
            expect(
              runner.workCreates.where(
                (call) => _isPlainCreateOf(call, 'session'),
              ),
              hasLength(1),
            );
        }
      });
    }

    test('a GATED round with durable #rN row closes the retired round and '
        'mints round N+1, in place (no restart)', () async {
      final f = buildFakes(createdId: 'tgdog-round2');
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final beforeDecision = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      final afterDecision = DateTime.now().add(const Duration(seconds: 1));
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: beforeDecision,
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // Adopted synchronously — round 1's gated session, no mint.
      expect(f.runner.workCreates, isEmpty);

      // `grid rework` re-keys round 1's `work_bead` off `tg-1`. The durable
      // `#rN` row authorizes re-mint while the ready bead keeps the branch
      // mounted (A40: never a ready-set exit).
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: beforeDecision,
          sessions: {
            'tg-1#r1': const SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      m.owner.flush();
      await _pump();
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: afterDecision,
          sessions: {
            'tg-1#r1': const SessionProjection(
              workBeadId: 'tg-1#r1',
              sessionId: 'tgdog-round1',
              cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
            ),
          },
        ),
      );
      await _pumpUntil(
        m.owner,
        () =>
            reg.events.contains('START agent(tgdog-round2/tg-1/agent)') &&
            f.runner.workCreates.length >= 2,
      );

      // The retired round-1 session is closed (D-2 fold: no more hand-close).
      final closes = f.runner.callsFor('close');
      expect(closes.where((c) => c[1] == 'tgdog-round1'), hasLength(1));
      expect(closes.first.join(' '), contains('reworked'));

      // Round 2 minted fresh — a SECOND createSession (+ its molecule pour,
      // tg-eli phase 2), a NEW id.
      final creates = f.runner.workCreates;
      expect(
        creates.where((c) => c.length <= 1 || c[1] != '--graph'),
        hasLength(1),
      );
      expect(
        creates.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );

      // The fresh round's leaf mounts under the NEW session id.
      expect(reg.events, contains('START agent(tgdog-round2/tg-1/agent)'));
    });

    test(
      'dep-add then immediate re-key waits for a fresh ready snapshot before '
      'minting',
      () async {
        final f = buildFakes(createdId: 'tgdog-round2');
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final transport = _RecordingTransport();
        final beforeDecision = DateTime.now().subtract(
          const Duration(seconds: 1),
        );
        final afterDecision = DateTime.now().add(const Duration(seconds: 1));
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1'), _task('tg-blocker')],
            ready: {'tg-1', 'tg-blocker'},
            capturedAt: beforeDecision,
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-round1',
                cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
              ),
            },
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          transport: transport,
        );
        addTearDown(m.owner.dispose);

        joined.push(
          _joined(
            beads: [_task('tg-1'), _task('tg-blocker')],
            ready: {'tg-1', 'tg-blocker'},
            capturedAt: beforeDecision,
            sessions: {
              'tg-1#r1': const SessionProjection(
                workBeadId: 'tg-1#r1',
                sessionId: 'tgdog-round1',
                cursor: {'tg-1/route': NodeCursor(state: StepState.gated)},
              ),
            },
          ),
        );
        m.owner.flush();
        await _pump();

        joined.push(
          _joined(
            beads: [_task('tg-1'), _task('tg-blocker')],
            ready: {'tg-blocker'},
            capturedAt: afterDecision,
            dependencies: const [
              BeadDependency(issueId: 'tg-1', dependsOnId: 'tg-blocker'),
            ],
            sessions: const {
              'tg-1#r1': SessionProjection(
                workBeadId: 'tg-1#r1',
                sessionId: 'tgdog-round1',
              ),
            },
          ),
        );
        m.owner.flush();
        await _pump();

        expect(f.runner.workCreates, isEmpty);
        expect(transport.named('session.mintRefused'), hasLength(1));

        joined.push(
          _joined(
            beads: [
              _task('tg-1'),
              _task('tg-blocker', status: BeadStatus.closed),
            ],
            ready: {'tg-1'},
            capturedAt: afterDecision.add(const Duration(seconds: 1)),
            sessions: const {
              'tg-1#r1': SessionProjection(
                workBeadId: 'tg-1#r1',
                sessionId: 'tgdog-round1',
              ),
            },
          ),
        );
        m.owner.flush();
        await _pumpUntil(m.owner, () => f.runner.workCreates.length >= 2);

        expect(f.runner.workCreates, hasLength(2));
        expect(
          f.runner.callsFor('close').where((call) => call[1] == 'tgdog-round1'),
          hasLength(1),
        );
        expect(transport.named('session.mintRefused'), hasLength(1));
      },
    );

    test('a RUNNING round with non-#rN disappearance declines LOUD and never '
        're-mints', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime(2026),
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-live',
              cursor: {'tg-1/agent': NodeCursor(state: StepState.running)},
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      expect(reg.events, ['START agent(tgdog-live/tg-1/agent)']);

      // The session vanishes from the join WITHOUT ever having been observed
      // gated (an out-of-band edit, or a bypassed CLI guard) — declines.
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime(2026),
        ),
      );
      m.owner.flush();
      await _pump();
      m.owner.flush();
      await _pump();

      // No close, no fresh mint — the retired session is marked, not retired.
      expect(f.runner.callsFor('close'), isEmpty);
      expect(f.runner.workCreates, isEmpty);
      final updates = f.runner.callsFor('update');
      final markers = [
        for (var i = 0; i < updates.length; i++)
          if (updates[i][1] == 'tgdog-live') f.runner.metadataOfUpdate(i),
      ].where((meta) => meta.containsKey('grid.rework_declined')).toList();
      expect(markers, hasLength(1));
      expect(markers.single['grid.rework_declined'], 'true');
    });

    test('a FRESH MINT whose join has not caught up yet is never mistaken '
        'for a rework orphan', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          capturedAt: DateTime(2026),
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // The mint completes; the join is NEVER updated to reflect it in this
      // test (exactly like the offline mint fixture) — repeated rebuilds must
      // not treat "never observed" as "vanished".
      await _pumpUntil(
        m.owner,
        () => reg.events.isNotEmpty && f.runner.workCreates.length >= 2,
      );

      // A fresh mint is a createSession call PLUS its molecule pour (tg-eli
      // phase 2: every fresh mint pours a molecule graph).
      final creates = f.runner.workCreates;
      expect(
        creates.where((c) => c.length <= 1 || c[1] != '--graph'),
        hasLength(1),
      );
      expect(
        creates.where((c) => c.length > 1 && c[1] == '--graph'),
        hasLength(1),
      );
      expect(f.runner.callsFor('close'), isEmpty);
      final updates = f.runner.callsFor('update');
      final declineMarkers = [
        for (var i = 0; i < updates.length; i++) f.runner.metadataOfUpdate(i),
      ].where((meta) => meta.containsKey('grid.rework_declined'));
      expect(declineMarkers, isEmpty);
      expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
    });
  });
}
