// Track D — the reentrant inflater: FormulaScope maps the eligible frontier to
// keyed child Seeds (linear 1-wide, fan-out + ordering, the await-all barrier,
// the keyed swap, nested sub-formula reentrancy), and the work-tick flush stays
// isolated to WorkList (invariant 1 AT DEPTH).
//
// ADR-0008 D4 / M4-P1 §4, Track D. Zero I/O — fake registry + fake leaves.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- the canonical formulas (local copies; Track H ships the real ones) ------

const _code = Formula(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

const _deploy = Formula(
  id: 'deploy',
  terminalStepId: 'waitWS',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'b'),
    CapabilityStep(stepId: 'install', capabilityId: 'i', dependsOn: {'build'}),
    CapabilityStep(
      stepId: 'launch',
      capabilityId: 'l',
      kind: StepKind.daemon,
      dependsOn: {'install'},
    ),
    CapabilityStep(stepId: 'waitWS', capabilityId: 'w', dependsOn: {'launch'}),
  ],
);

const _burn = Formula(
  id: 'burn',
  terminalStepId: 'report',
  supervision: SupervisionStrategy.restForOne,
  steps: [
    SubFormulaStep(stepId: 'harnessPeripheral', formulaId: 'deploy'),
    SubFormulaStep(
      stepId: 'harnessCentral',
      formulaId: 'deploy',
      dependsOn: {'harnessPeripheral'},
    ),
    CapabilityStep(
      stepId: 'coordinator',
      capabilityId: 'coord',
      dependsOn: {'harnessPeripheral', 'harnessCentral'},
    ),
    CapabilityStep(stepId: 'report', capabilityId: 'report', dependsOn: {'coordinator'}),
  ],
);

NodeCursor _done() => const NodeCursor(state: StepState.complete);
NodeCursor _ready() => const NodeCursor(state: StepState.ready);

// --- a tiny harness that drives a cursor into a FormulaScope in isolation -----

class _CursorHost extends StatefulSeed {
  const _CursorHost(this.formula, this.initial);
  final Formula formula;
  final FormulaCursor initial;
  @override
  State<_CursorHost> createState() => _CursorHostState();
}

class _CursorHostState extends State<_CursorHost> {
  late FormulaCursor _cursor;
  @override
  void initState() => _cursor = seed.initial;
  void advance(FormulaCursor cursor) => setState(() => _cursor = cursor);
  @override
  Seed build(TreeContext context) =>
      FormulaScope(
        formula: seed.formula,
        bead: bead('root'),
        cursor: _cursor,
        results: const {},
        nodePath: 'root',
      );
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

/// The mounted [_CursorHostState] under [root] — the cursor-advance driver.
_CursorHostState _cursorState(Branch root) {
  final branch = _whereSeed(root, (s) => s is _CursorHost) as StatefulBranch;
  // ignore: invalid_use_of_protected_member
  return branch.state as _CursorHostState;
}

/// Mounts [host] under a stable registry + a fixed SessionHandle; returns the
/// owner, the root branch, and the recording registry.
({TreeOwner owner, Branch root, RecordingCapabilityRegistry reg}) _mount(
  _CursorHost host, {
  Map<String, Formula> formulas = const {},
}) {
  final reg = RecordingCapabilityRegistry(formulas: formulas);
  final owner = TreeOwner();
  final root = owner.mountRoot(
    StableInheritedSeed<CapabilityRegistry>(
      value: reg,
      child: InheritedSeed<SessionHandle>(
        value: const SessionHandle('sess'),
        child: host,
      ),
    ),
  );
  return (owner: owner, root: root, reg: reg);
}

void main() {
  group('Track D — linear inflation (1-wide; §6 parity at depth)', () {
    test('empty cursor mounts only the dep-free first step', () {
      final m = _mount(const _CursorHost(_code, {}));
      addTearDown(m.owner.dispose);
      expect(m.reg.events, ['START agent(sess/root/agent)']);
    });

    test('a cursor advance swaps the leaf (old unmounts, new mounts) and keeps '
        'the FormulaScope branch identity', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      expect(m.reg.events, ['START agent(sess/root/agent)']);

      final scopeIdBefore =
          _whereSeed(m.root, (s) => s is FormulaScope).branchId;
      m.reg.events.clear();

      // Advance the cursor: agent complete → verify enters, agent retires.
      _cursorState(m.root).advance({'root/agent': _done()});
      m.owner.flush();

      // Genesis multichild reconcile mounts the new child then unmounts the
      // vanished one (order is reconcile-determined; assert the transition set).
      // The completed agent's process already exited (that wrote the cursor), so
      // STOP-after-START is a no-op kill — no double-run.
      expect(
        m.reg.events,
        unorderedEquals([
          'STOP agent(sess/root/agent)',
          'START verify(sess/root/verify)',
        ]),
      );
      expect(
        _whereSeed(m.root, (s) => s is FormulaScope).branchId,
        scopeIdBefore,
        reason: 'the inflater branch persists across a cursor advance',
      );
    });

    test('full linear progression agent → verify → land', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      final st = _cursorState(m.root);

      m.reg.events.clear();
      st.advance({'root/agent': _done()});
      m.owner.flush();
      expect(
        m.reg.events,
        unorderedEquals([
          'STOP agent(sess/root/agent)',
          'START verify(sess/root/verify)',
        ]),
      );

      m.reg.events.clear();
      st.advance({'root/agent': _done(), 'root/verify': _done()});
      m.owner.flush();
      expect(
        m.reg.events,
        unorderedEquals([
          'STOP verify(sess/root/verify)',
          'START land(sess/root/land)',
        ]),
      );
    });

    test('a restartCount bump RE-KEYS the same step (old incarnation unmounts, '
        'new mounts) — the supervised-restart mechanism', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      expect(m.reg.events, ['START agent(sess/root/agent)']);
      final hostIdBefore =
          _whereSeed(m.root, (s) => s is FakeCapabilityHost).branchId;
      m.reg.events.clear();

      // The agent FAILED; supervision bumps restartCount to 1 (within budget) →
      // the incarnation in the key changes ('root/agent#0' → '#1').
      _cursorState(m.root).advance({
        'root/agent': const NodeCursor(state: StepState.failed, restartCount: 1),
      });
      m.owner.flush();

      // The old incarnation unmounted and a new one mounted (re-key, NOT an
      // in-place update). A mutation dropping '#${restartCount}' from the key
      // would update-in-place → no STOP/START, same branchId → this fails.
      expect(
        m.reg.events,
        unorderedEquals([
          'STOP agent(sess/root/agent)',
          'START agent(sess/root/agent)',
        ]),
      );
      expect(
        _whereSeed(m.root, (s) => s is FakeCapabilityHost).branchId,
        isNot(hostIdBefore),
      );
    });
  });

  group('Track D — D-6 stable ambient providers', () {
    test('StableInheritedSeed.updateShouldNotify is ALWAYS false (the gate)', () {
      const a = StableInheritedSeed<SessionHandle>(
        value: SessionHandle('a'),
        child: Idle(),
      );
      const b = StableInheritedSeed<SessionHandle>(
        value: SessionHandle('b'),
        child: Idle(),
      );
      // Even across DIFFERENT values, a stable provider never notifies
      // dependents (D-6) — so a re-provide can never fan-rebuild the subtree.
      expect(a.updateShouldNotify(b), isFalse);
      // Contrast: a plain InheritedSeed WOULD notify on a value change — proving
      // the gate is meaningful, not vacuous.
      const plainA = InheritedSeed<SessionHandle>(
        value: SessionHandle('a'),
        child: Idle(),
      );
      const plainB = InheritedSeed<SessionHandle>(
        value: SessionHandle('b'),
        child: Idle(),
      );
      expect(plainA.updateShouldNotify(plainB), isTrue);
    });
  });

  group('Track D — fan-out + ordering + the await-all barrier (§9 at depth)',
      () {
    test('empty cursor mounts only the peripheral deploy (central ordered after)',
        () {
      final m = _mount(
        const _CursorHost(_burn, {}),
        formulas: {'deploy': _deploy},
      );
      addTearDown(m.owner.dispose);
      // The peripheral sub-formula inflates its own frontier {build}; central is
      // withheld (its dep's terminal descendant is pending); coordinator too.
      expect(m.reg.events, ['START b(sess/root/harnessPeripheral/build)']);
      // The nested FormulaScope for the peripheral exists.
      expect(
        _all(m.root).where((b) => b.seed is FormulaScope).length,
        2, // the outer burn scope + the peripheral deploy scope
      );
    });

    test('peripheral terminal → central enters; coordinator still withheld', () {
      final host = _CursorHost(_burn, const {});
      final m = _mount(host, formulas: {'deploy': _deploy});
      addTearDown(m.owner.dispose);
      final st = _cursorState(m.root);

      m.reg.events.clear();
      // Jump the peripheral deploy to a consistent fully-done cursor (build +
      // install complete, launch ready, waitWS complete) — its terminal
      // descendant waitWS satisfies central's dep. install was complete-without-
      // ever-mounting in this jump, so it neither STARTs nor STOPs.
      st.advance({
        'root/harnessPeripheral/build': _done(),
        'root/harnessPeripheral/install': _done(),
        'root/harnessPeripheral/launch': _ready(),
        'root/harnessPeripheral/waitWS': _done(),
      });
      m.owner.flush();
      // Peripheral: build retired (STOP), launch daemon enters (START). Central:
      // its build spawns. Coordinator withheld (central not terminal).
      expect(
        m.reg.events,
        unorderedEquals([
          'STOP b(sess/root/harnessPeripheral/build)',
          'START l(sess/root/harnessPeripheral/launch)',
          'START b(sess/root/harnessCentral/build)',
        ]),
      );
      expect(
        m.reg.events.any((e) => e.contains('coord')),
        isFalse,
        reason: 'the await-all barrier withholds the coordinator',
      );
    });

    test('BOTH harness terminals → the coordinator mounts (barrier opens)', () {
      final host = _CursorHost(_burn, const {});
      final m = _mount(host, formulas: {'deploy': _deploy});
      addTearDown(m.owner.dispose);
      final st = _cursorState(m.root);

      m.reg.events.clear();
      st.advance({
        'root/harnessPeripheral/waitWS': _done(),
        'root/harnessCentral/waitWS': _done(),
        // keep the daemons + earlier jobs consistent (ready/complete)
        'root/harnessPeripheral/launch': _ready(),
        'root/harnessCentral/launch': _ready(),
      });
      m.owner.flush();
      expect(
        m.reg.events.contains('START coord(sess/root/coordinator)'),
        isTrue,
        reason: 'both barrier deps reached a positive terminal',
      );
    });
  });
}
