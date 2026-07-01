// Track A5 — the four derailment-invariants AT DEPTH with the NEW Track A seams
// in play: a sibling-reading ServiceCapability (A2) + a Gate park (A3) + a flare
// emit (A4), inside a committee-shaped (critics → route) sub-formula. Each new
// assertion carries a positive control so it cannot be vacuous. Zero I/O —
// fakes + the recording chokepoint (an inline formula keeps grid_engine/test
// free of grid_assets, like track_j's _burn).
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- the inline committee-shaped capabilities (the author leaves) ------------

class _AgentCap extends ProcessCapability {
  const _AgentCap();
  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo'],
    lifecycle: Lifecycle.oneTurn,
  );
  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

class _CriticCap extends ProcessCapability {
  const _CriticCap();
  @override
  RuntimeConfig spawn(CapabilityContext ctx) => RuntimeConfig(
    workDir: ctx.workspaceDir,
    command: 'sh',
    args: const ['-c', 'echo'],
    lifecycle: Lifecycle.oneTurn,
  );
  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };
}

/// The sibling-reading aggregator (A2): reads each critic's grade through the
/// threaded [SiblingView] and parks at a gate (A3) on any fail-closed `F`.
class _RouteCap extends ServiceCapability {
  const _RouteCap();
  @override
  Future<StepOutcome> run(CapabilityContext ctx) async {
    final path = ctx.nodePath;
    final parent = path.substring(0, path.lastIndexOf('/'));
    final critics = (ctx.params['critics'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty);
    for (final critic in critics) {
      // Fail-closed: a missing grade reads as `F` (it can never advance).
      final grade = ctx.siblings.resultOf('$parent/$critic')['grade'] ?? 'F';
      if (grade == 'F') return Gate('critic $critic failed');
    }
    return const Ok({'verdict': 'advance'});
  }
}

class _LandCap extends ServiceCapability {
  const _LandCap();
  @override
  Future<StepOutcome> run(CapabilityContext ctx) async => const Ok();
}

const _caps = <String, Capability>{
  'agent': _AgentCap(),
  'critic': _CriticCap(),
  'route': _RouteCap(),
  'land': _LandCap(),
};

const _review = Formula(
  id: 'review',
  terminalStepId: 'route',
  steps: [
    CapabilityStep(stepId: 'critic1', capabilityId: 'critic'),
    CapabilityStep(stepId: 'critic2', capabilityId: 'critic'),
    CapabilityStep(
      stepId: 'route',
      capabilityId: 'route',
      dependsOn: {'critic1', 'critic2'},
      params: {'critics': 'critic1,critic2'},
    ),
  ],
);

const _code = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    SubFormulaStep(stepId: 'review', formulaId: 'review', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'review'}),
  ],
);

// --- a recording emit-only transport (A4) ------------------------------------

class _RecordingTransport implements ExplorationTransport {
  final List<String> names = [];
  @override
  void flare(String name, Map<String, String> data) => names.add(name);
}

// --- harness -----------------------------------------------------------------

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Bead _bead(String id, {IssueType type = IssueType.task}) =>
    Bead(id: id, issueType: type, status: BeadStatus.open);

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

SessionProjection _session(
  String workBead, {
  Map<String, NodeCursor> cursor = const {},
  Map<String, Map<String, String>> results = const {},
}) => SessionProjection(
  workBeadId: workBead,
  sessionId: 'tgdog-s',
  cursor: cursor,
  results: results,
);

const _tg = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

/// Mounts the committee-wired `code` tree with FAKE hosts (no per-host
/// subscription) — for the invariant-1 flush-graph gate.
({TreeOwner owner, Branch root}) _mountFake(JoinedSnapshotNotifier joined) {
  final reg = RecordingCapabilityRegistry(formulas: const {'review': _review});
  final fakes = buildFakes();
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: fakes.ctx,
        child: StableInheritedSeed<CapabilityRegistry>(
          value: reg,
          child: InheritedSeed<EffectResolver>(
            value: FormulaResolver((_) => _code),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(_tg),
                key: const ValueKey('scope'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  addTearDown(owner.dispose);
  return (owner: owner, root: root);
}

/// Mounts the committee-wired `code` tree with REAL CapabilityHosts (so the
/// route genuinely runs its sibling-read + gate + flare) — for invariants 2/4
/// and the no-spurious-land-mount gate.
({TreeOwner owner, Branch root, Fakes fakes, _RecordingTransport flares}) _mountReal(
  JoinedSnapshotNotifier joined, {
  SubstationConfig config = _tg,
}) {
  final fakes = buildFakes();
  final flares = _RecordingTransport();
  final registry = DefaultCapabilityRegistry(
    capabilities: _caps,
    formulas: const {'review': _review},
    clock: () => DateTime(2026),
  );
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: fakes.ctx,
        child: StableInheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<EffectResolver>(
            value: FormulaResolver((_) => _code),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(config),
                services: ServiceBundle(transport: flares),
                key: const ValueKey('scope'),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes, flares: flares);
}

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _whereSeed(Branch root, bool Function(Seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

/// The mounted CapabilityHosts whose nodePath ends with `/$stepId`.
Iterable<Branch> _hostsFor(Branch root, String stepId) => _all(root).where(
  (b) => b.seed is CapabilityHost &&
      (b.seed as CapabilityHost).mount.nodePath.endsWith('/$stepId'),
);

/// A cursor with the agent + both critics already complete (so the review
/// sub-formula's route mounts), plus the supplied critic [grades].
SessionProjection _routeReady(Map<String, String> grades) => _session(
  'tg-b',
  cursor: const {
    'tg-b/agent': NodeCursor(state: StepState.complete),
    'tg-b/review/critic1': NodeCursor(state: StepState.complete),
    'tg-b/review/critic2': NodeCursor(state: StepState.complete),
  },
  results: {
    'tg-b/review/critic1': {'grade': grades['critic1'] ?? 'A'},
    'tg-b/review/critic2': {'grade': grades['critic2'] ?? 'A'},
  },
);

void main() {
  group('A5 invariant 1 AT DEPTH (with the threaded sibling seam present)', () {
    test('a deep committee cursor tick → flush() == [WorkList]; no FormulaScope '
        'is in the drain (the results/cursor threading added no subscription)',
        () {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {
            'tg-b': _session('tg-b', cursor: const {
              'tg-b/agent': NodeCursor(state: StepState.complete),
            }),
          },
        ),
      );
      final m = _mountFake(joined);

      // Advance a DEEP node (a critic, two levels down) via the join.
      joined.push(_joined(
        beads: [_bead('tg-b')],
        ready: {'tg-b'},
        sessions: {
          'tg-b': _session('tg-b', cursor: const {
            'tg-b/agent': NodeCursor(state: StepState.complete),
            'tg-b/review/critic1': NodeCursor(state: StepState.complete),
          }),
        },
      ));
      final flushed = m.owner.flush();

      expect(flushed, equals([_whereSeed(m.root, (s) => s is WorkList)]));
      final scopes = _all(m.root).where((b) => b.seed is FormulaScope).toList();
      // Positive control: the committee tree really is deep (outer + nested).
      expect(scopes.length, greaterThanOrEqualTo(2));
      for (final scope in scopes) {
        expect(flushed, isNot(contains(scope)));
      }
    });
  });

  group('A5 invariant 2 AT DEPTH — the gate mint + park write go via the '
      'chokepoint onto the OWN session, never the foreign bead', () {
    test('a fail-closed critic grade parks the route at a gate (sibling-read + '
        'Gate + flare all in play)', () async {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {'tg-b': _routeReady(const {'critic1': 'F'})},
        ),
      );
      final m = _mountReal(joined);
      addTearDown(() {
        m.owner.dispose();
        unawaited(m.fakes.provider.close());
      });
      await _pump();

      // The route gated → a real type=gate bead was minted via the chokepoint.
      expect(m.fakes.runner.callsFor('create').single,
          containsAllInOrder(['--type', 'gate']));

      // The parked-cursor write landed on the OWN session (tgdog-s) at the deep
      // route path — and NOT ONE bd call touches the foreign work bead `tg-b`.
      final gatedWrites = m.fakes.runner
          .callsFor('update')
          .where((c) => c[1] == 'tgdog-s')
          .where((c) => c.join(' ').contains('grid.cursor.tg-b/review/route.state'))
          .toList();
      expect(gatedWrites, isNotEmpty);
      for (final call in m.fakes.runner.calls) {
        if (call.length > 1) expect(call[1], isNot('tg-b'));
      }

      // A4: the host emitted a step.gated flare (out-of-band, non-blocking).
      expect(m.flares.names, contains('step.gated'));

      // The gate park did NOT mount `land` (no spurious mount): no land host,
      // no land cursor write.
      expect(_hostsFor(m.root, 'land'), isEmpty);
      expect(
        m.fakes.runner.calls.any((c) => c.join(' ').contains('grid.cursor.tg-b/land')),
        isFalse,
      );
    });

    test('positive control — all-pass grades advance the route (Ok, no gate '
        'mint): the gate above was the fail, not a structural bug', () async {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {'tg-b': _routeReady(const {'critic1': 'A', 'critic2': 'A'})},
        ),
      );
      final m = _mountReal(joined);
      addTearDown(() {
        m.owner.dispose();
        unawaited(m.fakes.provider.close());
      });
      await _pump();

      // No gate minted; the route wrote `complete` (advance) instead.
      expect(m.fakes.runner.callsFor('create'), isEmpty);
      final routeWrite = m.fakes.runner
          .callsFor('update')
          .firstWhere((c) =>
              c.join(' ').contains('grid.cursor.tg-b/review/route.state'));
      expect(routeWrite.join(' '), contains('complete'));
      expect(m.flares.names, contains('step.complete'));
    });
  });

  group('A5 — the gate park withholds land; a complete route lets it mount', () {
    test('positive control: with the route ALREADY complete in the cursor, the '
        'land host mounts (proving the park, not a missing capability, blocked '
        'it)', () async {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {
            'tg-b': _session('tg-b', cursor: const {
              'tg-b/agent': NodeCursor(state: StepState.complete),
              'tg-b/review/critic1': NodeCursor(state: StepState.complete),
              'tg-b/review/critic2': NodeCursor(state: StepState.complete),
              'tg-b/review/route': NodeCursor(state: StepState.complete),
            }),
          },
        ),
      );
      final m = _mountReal(joined);
      addTearDown(() {
        m.owner.dispose();
        unawaited(m.fakes.provider.close());
      });
      await _pump();

      expect(_hostsFor(m.root, 'land'), isNotEmpty);
      expect(
        m.fakes.runner.calls.any((c) => c.join(' ').contains('grid.cursor.tg-b/land')),
        isTrue,
      );
    });
  });
}
