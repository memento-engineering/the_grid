// Track D — the reentrant inflater: CircuitScope maps the eligible frontier to
// keyed child Seeds (linear 1-wide, fan-out + ordering, the await-all barrier,
// the keyed swap, nested sub-circuit reentrancy), and the work-tick flush stays
// isolated to WorkList (invariant 1 AT DEPTH).
//
// ADR-0008 D4 / M4-P1 §4, Track D. Zero I/O — fake registry + fake leaves.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

// --- the canonical circuits (local copies; Track H ships the real ones) ------

const _code = Circuit(
  id: 'code',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'agent', capabilityId: 'agent'),
    CapabilityStep(stepId: 'verify', capabilityId: 'verify', dependsOn: {'agent'}),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'verify'}),
  ],
);

const _deploy = Circuit(
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

const _burn = Circuit(
  id: 'burn',
  terminalStepId: 'report',
  supervision: SupervisionStrategy.restForOne,
  steps: [
    SubCircuitStep(stepId: 'harnessPeripheral', circuitId: 'deploy'),
    SubCircuitStep(
      stepId: 'harnessCentral',
      circuitId: 'deploy',
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

// --- a tiny harness that drives a cursor into a CircuitScope in isolation -----

class _CursorHost extends StatefulSeed {
  const _CursorHost(this.circuit, this.initial);
  final Circuit circuit;
  final CircuitCursor initial;
  @override
  State<_CursorHost> createState() => _CursorHostState();
}

class _CursorHostState extends State<_CursorHost> {
  late CircuitCursor _cursor;
  @override
  void initState() => _cursor = seed.initial;
  void advance(CircuitCursor cursor) => setState(() => _cursor = cursor);
  @override
  Seed build(TreeContext context) =>
      CircuitScope(
        circuit: seed.circuit,
        cursor: _cursor,
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

/// Mounts [host] under a fixed-at-mount registry + a fixed SessionHandle;
/// returns the owner, the root branch, and the recording registry.
({TreeOwner owner, Branch root, RecordingCapabilityRegistry reg}) _mount(
  _CursorHost host, {
  Map<String, Circuit> circuits = const {},
}) {
  final reg = RecordingCapabilityRegistry(circuits: circuits);
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<CapabilityRegistry>(
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
        'the CircuitScope branch identity', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      expect(m.reg.events, ['START agent(sess/root/agent)']);

      final scopeIdBefore =
          _whereSeed(m.root, (s) => s is CircuitScope).branchId;
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
        _whereSeed(m.root, (s) => s is CircuitScope).branchId,
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

  group('Track D — ambient providers (D-6, superseded 2026-07-02)', () {
    test('a re-provide of an EQUAL value never notifies; a genuine change does '
        "(genesis's default replaces the deleted StableInheritedSeed)", () {
      // StableInheritedSeed (never-notify, even across DIFFERENT values) is
      // DELETED with the context rip-out: the ambient providers are plain
      // InheritedSeeds riding genesis's default `value != oldSeed.value`. The
      // stability D-6 wanted survives via VALUE EQUALITY — a value-equal
      // SessionHandle (or the same registry instance) re-provided unchanged
      // never fan-rebuilds the subtree…
      const old = InheritedSeed<SessionHandle>(
        value: SessionHandle('a'),
        child: Idle(),
      );
      const same = InheritedSeed<SessionHandle>(
        value: SessionHandle('a'),
        child: Idle(),
      );
      expect(same.updateShouldNotify(old), isFalse);
      // …while a GENUINE value change now notifies dependents (the "always
      // false" gate is gone with the type) — proving the no-notify above is
      // value equality at work, not a vacuous never-notify.
      const changed = InheritedSeed<SessionHandle>(
        value: SessionHandle('b'),
        child: Idle(),
      );
      expect(changed.updateShouldNotify(old), isTrue);
    });
  });

  group('Track D — fan-out + ordering + the await-all barrier (§9 at depth)',
      () {
    test('empty cursor mounts only the peripheral deploy (central ordered after)',
        () {
      final m = _mount(
        const _CursorHost(_burn, {}),
        circuits: {'deploy': _deploy},
      );
      addTearDown(m.owner.dispose);
      // The peripheral sub-circuit inflates its own frontier {build}; central is
      // withheld (its dep's terminal descendant is pending); coordinator too.
      expect(m.reg.events, ['START b(sess/root/harnessPeripheral/build)']);
      // The nested CircuitScope for the peripheral exists.
      expect(
        _all(m.root).where((b) => b.seed is CircuitScope).length,
        2, // the outer burn scope + the peripheral deploy scope
      );
    });

    test('peripheral terminal → central enters; coordinator still withheld', () {
      final host = _CursorHost(_burn, const {});
      final m = _mount(host, circuits: {'deploy': _deploy});
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
      final m = _mount(host, circuits: {'deploy': _deploy});
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
