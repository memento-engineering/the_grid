// Track D — the reentrant inflater: CircuitScope maps the eligible frontier to
// keyed child Seeds (linear 1-wide, fan-out + ordering, the await-all barrier,
// the keyed swap, nested sub-circuit reentrancy), and the work-tick flush stays
// isolated to WorkList (invariant 1 AT DEPTH).
//
// ADR-0008 D4 / M4-P1 §4, Track D. Zero I/O — fake registry + fake leaves.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/bead_path_key.dart';
import 'package:grid_engine/src/molecule/inherited_circuit.dart';
import 'package:test/test.dart';

import 'package:grid_engine/testing.dart';

// --- the canonical circuits (local copies; Track H ships the real ones) ------

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
    CapabilityStep(
      stepId: 'report',
      capabilityId: 'report',
      dependsOn: {'coordinator'},
    ),
  ],
);

NodeCursor _done() => const NodeCursor(state: StepState.complete);
NodeCursor _ready() => const NodeCursor(state: StepState.ready);

const _beadIds = <String, String>{
  'root/agent': 'step-agent-v1',
  'root/verify': 'step-verify-v1',
  'root/land': 'step-land-v1',
  'root/harnessPeripheral': 'step-peripheral-v1',
  'root/harnessPeripheral/build': 'step-peripheral-build-v1',
  'root/harnessPeripheral/install': 'step-peripheral-install-v1',
  'root/harnessPeripheral/launch': 'step-peripheral-launch-v1',
  'root/harnessPeripheral/waitWS': 'step-peripheral-wait-v1',
  'root/harnessCentral': 'step-central-v1',
  'root/harnessCentral/build': 'step-central-build-v1',
  'root/harnessCentral/install': 'step-central-install-v1',
  'root/harnessCentral/launch': 'step-central-launch-v1',
  'root/harnessCentral/waitWS': 'step-central-wait-v1',
  'root/coordinator': 'step-coordinator-v1',
  'root/report': 'step-report-v1',
};

// --- a tiny harness that drives a cursor into a CircuitScope in isolation -----

class _CursorHost extends StatefulSeed {
  const _CursorHost(this.circuit, this.initial, {this.beadIds = _beadIds});
  final Circuit circuit;
  final CircuitCursor initial;
  final Map<String, String> beadIds;
  @override
  State<_CursorHost> createState() => _CursorHostState();
}

class _CursorHostState extends State<_CursorHost> {
  late CircuitCursor _cursor;
  late Map<String, String> _incarnations;

  @override
  void initState() {
    _cursor = seed.initial;
    _incarnations = seed.beadIds;
  }

  void advance(CircuitCursor cursor, {Map<String, String>? beadIds}) =>
      setState(() {
        _cursor = cursor;
        if (beadIds != null) _incarnations = beadIds;
      });

  @override
  Seed build(TreeContext context) => InheritedSeed<InheritedCircuit>(
    value: InheritedCircuit(
      root: BeadPathKey(const ['work', 'session', 'circuit']),
      beadIdByNodePath: _incarnations,
      cursor: _cursor,
    ),
    child: CircuitScope(
      circuit: seed.circuit,
      cursor: _cursor,
      nodePath: 'root',
    ),
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
({
  TreeOwner owner,
  Branch root,
  RecordingCapabilityRegistry reg,
  _CursorHostState state,
})
_mount(_CursorHost host, {Map<String, Circuit> circuits = const {}}) {
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
  return (owner: owner, root: root, reg: reg, state: _cursorState(root));
}

List<Branch> _stepBranches(Branch root) => _all(root).where((branch) {
  final key = branch.seed.key;
  return key is ValueKey<String> && _beadIds.containsKey(key.value);
}).toList();

Branch _stepBranch(Branch root, String path) => _stepBranches(
  root,
).singleWhere((branch) => branch.seed.key == ValueKey(path));

class _BareCircuitHost extends StatelessSeed {
  const _BareCircuitHost();

  @override
  Seed build(TreeContext context) =>
      const CircuitScope(circuit: _code, cursor: {}, nodePath: 'root');
}

void main() {
  group('Track D — linear inflation (1-wide; §6 parity at depth)', () {
    test('empty cursor mounts every step and only the first effect', () {
      final m = _mount(const _CursorHost(_code, {}));
      addTearDown(m.owner.dispose);
      expect(_stepBranches(m.root), hasLength(3));
      expect(
        _stepBranches(m.root).map((branch) => branch.seed.key),
        unorderedEquals([
          const ValueKey('root/agent'),
          const ValueKey('root/verify'),
          const ValueKey('root/land'),
        ]),
      );
      expect(m.reg.events, ['START agent(sess/root/agent)']);
    });

    test('a cursor advance swaps the leaf (old unmounts, new mounts) and keeps '
        'the CircuitScope branch identity', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      expect(m.reg.events, ['START agent(sess/root/agent)']);

      final scopeIdBefore = _whereSeed(
        m.root,
        (s) => s is CircuitScope,
      ).branchId;
      final agentStepId = _stepBranch(m.root, 'root/agent').branchId;
      final verifyStepId = _stepBranch(m.root, 'root/verify').branchId;
      m.reg.events.clear();

      // Advance the cursor: agent complete → verify enters, agent retires.
      m.state.advance({'root/agent': _done()});
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
      expect(_stepBranch(m.root, 'root/agent').branchId, agentStepId);
      expect(_stepBranch(m.root, 'root/verify').branchId, verifyStepId);
      expect(_stepBranches(m.root), hasLength(3));
    });

    test('full linear progression agent → verify → land', () {
      final host = _CursorHost(_code, const {});
      final m = _mount(host);
      addTearDown(m.owner.dispose);
      final st = m.state;

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

  group('Track D — fan-out + ordering + the await-all barrier (§9 at depth)', () {
    test(
      'empty cursor mounts only the peripheral deploy (central ordered after)',
      () {
        final m = _mount(
          const _CursorHost(_burn, {}),
          circuits: {'deploy': _deploy},
        );
        addTearDown(m.owner.dispose);
        // The peripheral sub-circuit inflates its own frontier {build}; central is
        // withheld (its dep's terminal descendant is pending); coordinator too.
        expect(m.reg.events, ['START b(sess/root/harnessPeripheral/build)']);
        expect(_stepBranches(m.root), hasLength(8));
        expect(
          _stepBranches(m.root).where(
            (branch) =>
                branch.seed.key == const ValueKey('root/harnessCentral/build'),
          ),
          isEmpty,
        );
        // The nested CircuitScope for the peripheral exists.
        expect(
          _all(m.root).where((b) => b.seed is CircuitScope).length,
          2, // the outer burn scope + the peripheral deploy scope
        );
      },
    );

    test('peripheral terminal → central enters; coordinator still withheld', () {
      final host = _CursorHost(_burn, const {});
      final m = _mount(host, circuits: {'deploy': _deploy});
      addTearDown(m.owner.dispose);
      final st = m.state;
      final centralStepId = _stepBranch(m.root, 'root/harnessCentral').branchId;

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
      expect(
        _stepBranch(m.root, 'root/harnessCentral').branchId,
        centralStepId,
      );
      expect(_stepBranches(m.root), hasLength(12));
    });

    test('BOTH harness terminals → the coordinator mounts (barrier opens)', () {
      final host = _CursorHost(_burn, const {});
      final m = _mount(host, circuits: {'deploy': _deploy});
      addTearDown(m.owner.dispose);
      final st = m.state;

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

  group('Track D — effect incarnation axes', () {
    test('restartCount replaces only the effect beneath the stable step', () {
      final m = _mount(const _CursorHost(_code, {}));
      addTearDown(m.owner.dispose);
      final stepId = _stepBranch(m.root, 'root/agent').branchId;
      final effectId = _whereSeed(
        m.root,
        (seed) => seed is FakeCapabilityHost,
      ).branchId;
      m.reg.events.clear();

      m.state.advance({
        'root/agent': const NodeCursor(
          state: StepState.failed,
          restartCount: 1,
        ),
      });
      m.owner.flush();

      expect(
        m.reg.events,
        unorderedEquals([
          'STOP agent(sess/root/agent)',
          'START agent(sess/root/agent)',
        ]),
      );
      expect(_stepBranch(m.root, 'root/agent').branchId, stepId);
      expect(
        _whereSeed(m.root, (seed) => seed is FakeCapabilityHost).branchId,
        isNot(effectId),
      );
    });

    test('rewindCount alone preserves the step and effect branches', () {
      final m = _mount(const _CursorHost(_code, {}));
      addTearDown(m.owner.dispose);
      final stepId = _stepBranch(m.root, 'root/agent').branchId;
      final effectId = _whereSeed(
        m.root,
        (seed) => seed is FakeCapabilityHost,
      ).branchId;
      m.reg.events.clear();

      m.state.advance({'root/agent': const NodeCursor(rewindCount: 7)});
      m.owner.flush();

      expect(m.reg.events, isEmpty);
      expect(_stepBranch(m.root, 'root/agent').branchId, stepId);
      expect(
        _whereSeed(m.root, (seed) => seed is FakeCapabilityHost).branchId,
        effectId,
      );
    });

    test(
      'successor bead id replaces only the effect beneath the stable step',
      () {
        final m = _mount(const _CursorHost(_code, {}));
        addTearDown(m.owner.dispose);
        final stepId = _stepBranch(m.root, 'root/agent').branchId;
        final effectId = _whereSeed(
          m.root,
          (seed) => seed is FakeCapabilityHost,
        ).branchId;
        m.reg.events.clear();

        m.state.advance(
          const {'root/agent': NodeCursor(rewindCount: 1)},
          beadIds: {..._beadIds, 'root/agent': 'step-agent-v2'},
        );
        m.owner.flush();

        expect(
          m.reg.events,
          unorderedEquals([
            'STOP agent(sess/root/agent)',
            'START agent(sess/root/agent)',
          ]),
        );
        expect(_stepBranch(m.root, 'root/agent').branchId, stepId);
        expect(
          _whereSeed(m.root, (seed) => seed is FakeCapabilityHost).branchId,
          isNot(effectId),
        );
      },
    );
  });

  group('Track D — incarnation guards and flat adoption', () {
    test('CircuitScope without InheritedCircuit keeps flat adoption live', () {
      final reg = RecordingCapabilityRegistry();
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        InheritedSeed<CapabilityRegistry>(
          value: reg,
          child: const InheritedSeed<SessionHandle>(
            value: SessionHandle('sess'),
            child: _BareCircuitHost(),
          ),
        ),
      );

      expect(_stepBranches(root), hasLength(3));
      expect(reg.events, ['START agent(sess/root/agent)']);
    });

    test('missing declared node path mounts WITHOUT throwing — CapabilityHost '
        'is the contained loud point (tg-nmhy: the build-path throw escaped '
        'the unguarded flush and killed the resident VM on partial-mint '
        'snapshots)', () {
      final m = _mount(
        _CursorHost(
          _code,
          const {},
          beadIds: const {
            'root/verify': 'step-verify-v1',
            'root/land': 'step-land-v1',
          },
        ),
      );
      // The step still mounts; a genuine mis-composition is refused
      // per-work by `CapabilityHost._stepBeadId` at the allocation seam
      // (ADR-0008 D10), never by a fatal build-path throw.
      expect(m.reg.events, contains('START agent(sess/root/agent)'));
      expect(_stepBranches(m.root), hasLength(3));
    });

    test('empty bead id throws StateError', () {
      expect(
        () => _mount(
          _CursorHost(
            _code,
            const {},
            beadIds: {..._beadIds, 'root/agent': ''},
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('empty step-bead id for "root/agent"'),
          ),
        ),
      );
    });

    test('one bead id assigned to two paths throws StateError', () {
      expect(
        () => _mount(
          _CursorHost(
            _code,
            const {},
            beadIds: {..._beadIds, 'root/verify': 'step-agent-v1'},
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('step-bead id "step-agent-v1" is assigned to both'),
              contains('"root/agent" and "root/verify"'),
            ),
          ),
        ),
      );
    });
  });
}
