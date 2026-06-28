// Track I — the four derailment-invariants as gates AT DEPTH (M4-P1 §8).
//
// The per-track suites prove the invariants where each mechanism lives
// (invariant 1: track_a/c/d flush isolation; invariant 2: track_e sandbox +
// the D-1 race in grid_runtime; invariant 3: track_a A41 allow-list; invariant
// 4: track_c/restart). THIS file re-proves all four INSIDE a nested formula
// subtree (the Burn shape), each as a mutation-resistant gate. Zero I/O.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

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
  phase: WorkPhase.implement,
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

  group('Invariant 2 AT DEPTH — only the chokepoint writes', () {
    test('the only bd writes in a driven formula are the chokepoint`s (the '
        'recording runner sees every one; no bypass)', () async {
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-b')],
          ready: {'tg-b'},
          sessions: {
            'tg-b': _session('tg-b', 'tgdog-s', cursor: const {
              'tg-b/harness/build': NodeCursor(state: StepState.complete),
              'tg-b/harness/install': NodeCursor(state: StepState.complete),
              'tg-b/harness/waitWS': NodeCursor(state: StepState.complete),
              'tg-b/report': NodeCursor(state: StepState.complete),
            }),
          },
        ),
      );
      final m = _mount(joined: joined, config: _tg);
      addTearDown(m.owner.dispose);
      await Future<void>.delayed(Duration.zero);

      // The formula is complete → SessionScope closes via the chokepoint. EVERY
      // recorded bd call is a session-bead write (never the foreign work bead),
      // and the runner is the SOLE write surface (CapabilityContext has no
      // writer — track_e; the D-1 same-key race — grid_runtime).
      for (final call in m.fakes.runner.calls) {
        if (call.length > 1 && {'update', 'close', 'create'}.contains(call.first)) {
          // a mutation targeting the work bead would put 'tg-b' here.
          expect(call[1], isNot('tg-b'));
        }
      }
      expect(
        m.fakes.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
        hasLength(1),
      );
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

  group('Invariant 4 / A37 AT DEPTH — read-only foreign source', () {
    test('a FOREIGN work bead`s formula writes its cursor/close to the OWN '
        'session bead, NEVER the foreign work bead', () async {
      // The_grid dispatches a foreign work source (config owns `genesis`); the
      // session lives in the OWNED state store (`tgdog`, the writer`s allow-set).
      const foreignConfig =
          SubstationConfig(substationId: 'genesis', ownedSubstations: {'genesis'});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('genesis-x')],
          ready: {'genesis-x'},
          sessions: {
            'genesis-x': _session('genesis-x', 'tgdog-s', cursor: const {
              'genesis-x/harness/build': NodeCursor(state: StepState.complete),
              'genesis-x/harness/install': NodeCursor(state: StepState.complete),
              'genesis-x/harness/waitWS': NodeCursor(state: StepState.complete),
              'genesis-x/report': NodeCursor(state: StepState.complete),
            }),
          },
        ),
      );
      final m = _mount(joined: joined, config: foreignConfig);
      addTearDown(m.owner.dispose);
      await Future<void>.delayed(Duration.zero);

      // The foreign work bead mounted (config owns `genesis`), the formula
      // completed, and the close targeted the OWN session — never `genesis-x`.
      expect(
        _all(m.root).whereType<Branch>().where((b) => b.seed is WorkBead),
        hasLength(1),
      );
      expect(
        m.fakes.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'),
        hasLength(1),
      );
      for (final call in m.fakes.runner.calls) {
        if (call.length > 1) expect(call[1], isNot('genesis-x'));
      }
    });
  });
}
