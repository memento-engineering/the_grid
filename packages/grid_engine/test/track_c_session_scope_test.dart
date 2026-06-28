// Track C — SessionScope (D-2): adopt-or-mint the session ABOVE the fan-out
// (one mint per work bead, never per leaf), provide the SessionHandle, own the
// positive-terminal close — and the work-tick flush stays isolated to WorkList
// (invariant 1 AT DEPTH, the new path).
//
// ADR-0008 D4 / M4-P1 §4, Track C. Zero I/O — fakes + the recording chokepoint.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

const _code = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

const _burn = Formula(
  id: 'burn',
  terminalStepId: 'report',
  steps: [
    CapabilityStep(stepId: 'a', capabilityId: 'a'),
    CapabilityStep(stepId: 'b', capabilityId: 'b'), // also dep-free → fan-out
    CapabilityStep(stepId: 'report', capabilityId: 'report', dependsOn: {'a', 'b'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

Bead _task(String id, {BeadStatus status = BeadStatus.open}) =>
    Bead(id: id, issueType: IssueType.task, status: status);

const _tgConfig = SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

/// The full new-path root: WorkList observes [joined]; WorkBead resolves through
/// the FormulaResolver → SessionScope → FormulaScope; SessionScope mints via the
/// EffectContext writer; FormulaScope inflates via the registry.
({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required EffectContext ctx,
  required CapabilityRegistry registry,
  required RootFormulaFor rootFormula,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<EffectContext>(
        value: ctx,
        child: StableInheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<EffectResolver>(
            value: FormulaResolver(rootFormula),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(_tgConfig),
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

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _whereSeed(Branch root, bool Function(Seed seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

void main() {
  group('Track C — SessionScope mints ONCE, above the fan-out', () {
    test('a ready bead with no session mints exactly one session, then inflates',
        () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_task('tg-1')], ready: {'tg-1'}),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // Resolving: no leaf yet (the session mint is async).
      expect(reg.events, isEmpty);
      await _pump();
      m.owner.flush();

      // Exactly ONE createSession (minted above the fan-out), then the first
      // step inflates under the minted SessionHandle (id = tgdog-sess1).
      expect(f.runner.callsFor('create'), hasLength(1));
      expect(reg.events, ['START agent(tgdog-sess1/tg-1/agent)']);
    });

    test('a fan-out formula (two dep-free steps) still mints ONE session', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_task('tg-burn')], ready: {'tg-burn'}),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _burn,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      // ONE mint, both dep-free leaves mounted under the SAME session id, with
      // DISJOINT paths (disjoint routing) — never two mints / two sessions.
      expect(f.runner.callsFor('create'), hasLength(1));
      expect(
        reg.events,
        unorderedEquals([
          'START a(tgdog-sess1/tg-burn/a)',
          'START b(tgdog-sess1/tg-burn/b)',
        ]),
      );
    });
  });

  group('Track C — SessionScope adopts an existing session', () {
    test('a bead with a linked session adopts it synchronously (no mint)', () {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-existing',
              phase: WorkPhase.implement,
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // Adopted synchronously on mount — no createSession, leaf under the
      // adopted id.
      expect(f.runner.callsFor('create'), isEmpty);
      expect(reg.events, ['START agent(tgdog-existing/tg-1/agent)']);
    });
  });

  group('Track C — SessionScope owns the positive-terminal close (D-2)', () {
    test('when the terminal step completes, the session is closed exactly once',
        () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              phase: WorkPhase.land,
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _code,
      );
      addTearDown(m.owner.dispose);

      // Drive the cursor to the terminal (land complete).
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              phase: WorkPhase.land,
              cursor: {
                'tg-1/agent': NodeCursor(state: StepState.complete),
                'tg-1/verify': NodeCursor(state: StepState.complete),
                'tg-1/land': NodeCursor(state: StepState.complete),
              },
            ),
          },
        ),
      );
      m.owner.flush();

      // The close is SCHEDULED off build, NOT written during build (invariant 2:
      // no writes in build()) — so immediately after the synchronous flush, no
      // close has been issued yet.
      expect(
        f.runner.callsFor('close'),
        isEmpty,
        reason: 'the close must be scheduled off build, not written in build()',
      );

      await _pump();

      // After the microtask drains, SessionScope closed the session, exactly once
      // (latched).
      expect(f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'), hasLength(1));
    });

    test('the close is latched once across repeated terminal rebuilds', () async {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      const terminal = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-s',
        phase: WorkPhase.land,
        cursor: {
          'tg-1/agent': NodeCursor(state: StepState.complete),
          'tg-1/verify': NodeCursor(state: StepState.complete),
          'tg-1/land': NodeCursor(state: StepState.complete),
        },
      );
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {'tg-1': terminal},
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      await _pump();

      // Re-push the SAME terminal snapshot twice → SessionScope rebuilds, but the
      // _closeScheduled latch fires the close exactly once.
      joined.push(
        _joined(beads: [_task('tg-1')], ready: {'tg-1'}, sessions: {'tg-1': terminal}),
      );
      m.owner.flush();
      await _pump();
      expect(f.runner.callsFor('close').where((c) => c[1] == 'tgdog-s'), hasLength(1));
    });
  });

  group('Track C — invariant 1 at depth: only WorkList dirties on a work tick',
      () {
    test('a cursor advance flush() returns exactly [WorkList]; config ancestors '
        '+ the inflater are absent from the drain', () {
      final f = buildFakes();
      final reg = RecordingCapabilityRegistry(formulas: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              phase: WorkPhase.implement,
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootFormula: (_) => _code,
      );
      addTearDown(m.owner.dispose);
      expect(reg.events, ['START agent(tgdog-s/tg-1/agent)']);
      reg.events.clear();

      // Advance the per-node cursor (agent complete) via the join.
      joined.push(
        _joined(
          beads: [_task('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              phase: WorkPhase.implement,
              cursor: {'tg-1/agent': NodeCursor(state: StepState.complete)},
            ),
          },
        ),
      );
      final flushed = m.owner.flush();

      // Only the observing node drained — the SessionScope/FormulaScope/leaves
      // are force-rebuilt by WorkList's cascade, excluded from the drain.
      final workList = _whereSeed(m.root, (s) => s is WorkList);
      expect(flushed, equals([workList]));
      // The swap happened (agent retired, verify entered).
      expect(
        reg.events,
        unorderedEquals([
          'STOP agent(tgdog-s/tg-1/agent)',
          'START verify(tgdog-s/tg-1/verify)',
        ]),
      );
      // Config ancestors + the inflater are absent from the drain.
      expect(flushed, isNot(contains(_whereSeed(m.root, (s) => s is Station))));
      expect(flushed, isNot(contains(_whereSeed(m.root, (s) => s is SubstationScope))));
      expect(flushed, isNot(contains(_whereSeed(m.root, (s) => s is FormulaScope))));
      expect(flushed, isNot(contains(_whereSeed(m.root, (s) => s is SessionScope))));
    });
  });
}
