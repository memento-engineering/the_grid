// Track I — the four derailment-invariants as gates AT DEPTH (M4-P1 §8).
//
// The per-track suites prove the invariants where each mechanism lives
// (invariant 1: track_a/c/d flush isolation; invariant 2: track_e sandbox +
// the D-1 race in grid_runtime; invariant 3: track_a A41 allow-list; invariant
// 4: track_c/restart). THIS file re-proves all four INSIDE a nested formula
// subtree (the Burn shape), each as a mutation-resistant gate. Zero I/O.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

/// A real (writing) fake ProcessCapability — so a CapabilityHost actually mounts,
/// spawns, and WRITES its cursor through the chokepoint (the invariant-2/4 gates
/// must exercise a running host, not just SessionScope's close).
class _WritingCap extends ProcessCapability {
  const _WritingCap();
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

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _burnCaps = <String, Capability>{
  'build': _WritingCap(),
  'install': _WritingCap(),
  'waitWS': _WritingCap(),
  'report': _WritingCap(),
};

const _deploy = Formula(
  id: 'deploy',
  terminalStepId: 'waitWS',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    CapabilityStep(stepId: 'install', capabilityId: 'install', dependsOn: {'build'}),
    CapabilityStep(stepId: 'waitWS', capabilityId: 'waitWS', dependsOn: {'install'}),
  ],
);
const _burn = Formula(
  id: 'burn',
  terminalStepId: 'report',
  steps: [
    SubFormulaStep(stepId: 'harness', formulaId: 'deploy'),
    CapabilityStep(stepId: 'report', capabilityId: 'report', dependsOn: {'harness'}),
  ],
);

NodeCursor _done() => const NodeCursor(state: StepState.complete);

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

Bead _bead(String id, {IssueType type = IssueType.task}) =>
    Bead(id: id, issueType: type, status: BeadStatus.open);

SessionProjection _session(
  String workBead,
  String sessionId, {
  Map<String, NodeCursor> cursor = const {},
}) => SessionProjection(
  workBeadId: workBead,
  sessionId: sessionId,
  cursor: cursor,
);

({TreeOwner owner, Branch root, Fakes fakes, RecordingCapabilityRegistry reg})
    _mount({
  required JoinedSnapshotNotifier joined,
  required SubstationConfig config,
}) {
  final fakes = buildFakes();
  final reg = RecordingCapabilityRegistry(formulas: const {'deploy': _deploy});
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<EffectContext>(
        value: fakes.ctx,
        child: StableInheritedSeed<CapabilityRegistry>(
          value: reg,
          child: InheritedSeed<ServiceBundle>(
            value: const ServiceBundle(),
            child: InheritedSeed<EffectResolver>(
              value: FormulaResolver((_) => _burn),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(config),
                  key: const ValueKey('scope'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes, reg: reg);
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

/// Mounts the burn formula with REAL CapabilityHosts (DefaultCapabilityRegistry
/// over [_burnCaps]) so a host genuinely spawns + writes its cursor — for the
/// invariant-2/4 write-target gates.
({TreeOwner owner, Branch root, Fakes fakes}) _mountReal({
  required JoinedSnapshotNotifier joined,
  required SubstationConfig config,
}) {
  final fakes = buildFakes();
  final registry = DefaultCapabilityRegistry(
    capabilities: _burnCaps,
    formulas: const {'deploy': _deploy},
    clock: () => DateTime(2026),
  );
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<EffectContext>(
        value: fakes.ctx,
        child: StableInheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<ServiceBundle>(
            value: const ServiceBundle(),
            child: InheritedSeed<EffectResolver>(
              value: FormulaResolver((_) => _burn),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(config),
                  key: const ValueKey('scope'),
                ),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
  return (owner: owner, root: root, fakes: fakes);
}

const _tg = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

void main() {
  group('Invariant 1 AT DEPTH — only WorkList dirties on a work tick', () {
    test('a deep (nested sub-formula) cursor tick → flush() == [WorkList]; the '
        'nested FormulaScopes + hosts are force-rebuilt, NOT in the drain', () {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {
            'tg-b': _session('tg-b', 'tgdog-s', cursor: const {
              'tg-b/harness/build': NodeCursor(state: StepState.complete),
            }),
          },
        ),
      );
      final m = _mount(joined: joined, config: _tg);
      addTearDown(m.owner.dispose);

      // Advance a DEEP node (install, two levels down) via the join.
      joined.push(_joined(
        beads: [_bead('tg-b')],
        ready: {'tg-b'},
        sessions: {
          'tg-b': _session('tg-b', 'tgdog-s', cursor: {
            'tg-b/harness/build': _done(),
            'tg-b/harness/install': _done(),
          }),
        },
      ));
      final flushed = m.owner.flush();

      // Only WorkList drained — every FormulaScope (the outer burn + the nested
      // deploy) is force-rebuilt by the cascade, excluded. A mutation making any
      // of them subscribe the notifier would put it in the drain.
      expect(flushed, equals([_whereSeed(m.root, (s) => s is WorkList)]));
      final scopes = _all(m.root).where((b) => b.seed is FormulaScope).toList();
      expect(scopes.length, greaterThanOrEqualTo(2)); // outer + nested
      for (final scope in scopes) {
        expect(flushed, isNot(contains(scope)));
      }
    });
  });

  group('Invariant 2 AT DEPTH — only the chokepoint writes (a RUNNING host)', () {
    test('a deep CapabilityHost`s cursor write goes via the chokepoint onto the '
        'OWN session — never a direct/foreign write', () async {
      // Empty cursor → the peripheral build host (two levels deep) actually
      // MOUNTS, spawns, and writes (not a vacuous all-complete cursor).
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {'tg-b': _session('tg-b', 'tgdog-s')},
        ),
      );
      final m = _mountReal(joined: joined, config: _tg);
      addTearDown(() {
        m.owner.dispose();
        unawaited(m.fakes.provider.close());
      });
      await _pump();

      // The deep build host spawned under the OWN session name.
      expect(m.fakes.provider.started.map((s) => s.name),
          contains('tgdog-s/tg-b/harness/build'));

      // It completes → the host writes the node cursor THROUGH the chokepoint.
      m.fakes.provider.emit(const Exited(name: 'tgdog-s/tg-b/harness/build', exitCode: 0));
      await _pump();

      // The write landed on the OWN session (tgdog-s), at the deep node path —
      // and NO bd call targets the work bead (invariant 2 + A37, at depth).
      final writes = m.fakes.runner
          .callsFor('update')
          .where((c) => c[1] == 'tgdog-s')
          .toList();
      expect(writes, isNotEmpty);
      expect(
        writes.any((c) => c.join(' ').contains('grid.cursor.tg-b/harness/build.state')),
        isTrue,
      );
      for (final call in m.fakes.runner.calls) {
        if (call.length > 1) expect(call[1], isNot('tg-b'));
      }
    });
  });

  group('Invariant 3 AT DEPTH — convergence never mounts a formula subtree', () {
    test('a convergence-typed bead in the ready set mounts ZERO formula nodes; a '
        'plain owned bead mounts a full one', () {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-conv', type: IssueType.convergence), _bead('tg-ok')],
          ready: {'tg-conv', 'tg-ok'},
        ),
      );
      final m = _mount(joined: joined, config: _tg);
      addTearDown(m.owner.dispose);

      // Exactly one WorkBead (tg-ok) — the convergence bead mounts nothing (the
      // A41 isCore allow-list excludes it; a formula selects capabilities, never
      // beads-by-type, so it cannot sneak in at depth either).
      final workBeads = _all(m.root).where((b) => b.seed is WorkBead).toList();
      expect(workBeads, hasLength(1));
      expect((workBeads.single.seed as WorkBead).bead.id, 'tg-ok');
    });
  });

  group('Invariant 4 / A37 AT DEPTH — read-only foreign source (a RUNNING host)',
      () {
    test('a FOREIGN work bead`s deep host writes its cursor to the OWN session, '
        'NEVER the foreign work bead', () async {
      // The_grid dispatches a foreign work source (config owns `genesis`); the
      // session lives in the OWNED state store (`tgdog`, the writer`s allow-set).
      const foreignConfig =
          SubstationConfig(substationId: 'genesis', ownedSubstations: {'genesis'});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('genesis-x')],
          ready: {'genesis-x'},
          // Empty cursor → the deep build host actually RUNS + writes.
          sessions: {'genesis-x': _session('genesis-x', 'tgdog-s')},
        ),
      );
      final m = _mountReal(joined: joined, config: foreignConfig);
      addTearDown(() {
        m.owner.dispose();
        unawaited(m.fakes.provider.close());
      });
      await _pump();

      // The foreign work bead mounted (config owns `genesis`); its deep build
      // host spawned + completes.
      expect(
        _all(m.root).where((b) => b.seed is WorkBead),
        hasLength(1),
      );
      m.fakes.provider.emit(
        const Exited(name: 'tgdog-s/genesis-x/harness/build', exitCode: 0),
      );
      await _pump();

      // The cursor write targeted the OWN session — and NOT ONE bd call touches
      // the foreign work bead `genesis-x` (A37, at depth, with a running host).
      expect(
        m.fakes.runner.callsFor('update').where((c) => c[1] == 'tgdog-s'),
        isNotEmpty,
      );
      for (final call in m.fakes.runner.calls) {
        if (call.length > 1) expect(call[1], isNot('genesis-x'));
      }
    });
  });
}
