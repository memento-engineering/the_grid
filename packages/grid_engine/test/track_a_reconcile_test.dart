// Track A — the heart: the pure Seeds reconcile the running system, and the
// derailment-invariant-1 guardrail holds (only the observing node dirties; a
// work tick never rebuilds config; a cursor advance is a reconcile transition
// that threads config DOWN without re-creating the work subtree root).
//
// In the reentrant model the WorkBead's child is the bead's whole work SUBTREE
// (a stable, bead-keyed root); progress is the per-node cursor advancing INSIDE
// that subtree (FormulaScope — Track C/D/H), NOT a swap at the WorkBead level.
// So this file pins the WorkBead/WorkList reconcile + the child-set predicate;
// the in-subtree step swap is proven by track_c/track_h.
//
// ADR-0007 §6.1 / M4-P0-BUILD-ORDER §3 Track A. Zero I/O — fakes only.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes: an EffectResolver that mounts a recording subtree-root per work bead.
// ---------------------------------------------------------------------------

/// Records the work subtree-root lifecycle in mount/unmount order — the
/// observable proxy for "the bead's work mounts" (`START`) / "unmounts" (`STOP`).
class _Recorder {
  final List<String> events = [];
  void record(String event) => events.add(event);
}

/// Returns a `_FakeEffect` keyed `'<beadId>:work'` — the bead-keyed subtree root
/// the real resolver returns (a `SessionScope`). It is STABLE across cursor
/// ticks: a cursor advance threads new config down, never swaps this child.
class _FakeEffectResolver implements EffectResolver {
  _FakeEffectResolver(this.recorder);
  final _Recorder recorder;

  @override
  Seed effectFor({required Bead bead, SessionProjection? session}) => _FakeEffect(
    recorder: recorder,
    beadId: bead.id,
    key: ValueKey('${bead.id}:work'),
  );
}

class _FakeEffect extends StatefulSeed {
  const _FakeEffect({
    required this.recorder,
    required this.beadId,
    super.key,
  });
  final _Recorder recorder;
  final String beadId;

  @override
  State<_FakeEffect> createState() => _FakeEffectState();
}

class _FakeEffectState extends State<_FakeEffect> {
  @override
  void initState() => seed.recorder.record('START work(${seed.beadId})');

  @override
  void dispose() => seed.recorder.record('STOP work(${seed.beadId})');

  @override
  Seed build(TreeContext context) => const Idle();
}

// ---------------------------------------------------------------------------
// Builders + branch-walk helpers.
// ---------------------------------------------------------------------------

Bead _bead(
  String id, {
  IssueType type = IssueType.task,
  BeadStatus status = BeadStatus.open,
}) => Bead(id: id, issueType: type, status: status);

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

/// The root: provide the work-axis notifier + the capability resolver above the
/// Station; give the single rig its config notifier.
Seed _root({
  required JoinedSnapshotNotifier joined,
  required EffectResolver resolver,
  required SubstationConfigNotifier substationConfig,
}) => InheritedSeed<JoinedSnapshotNotifier>(
  value: joined,
  child: InheritedSeed<EffectResolver>(
    value: resolver,
    child: Station([
      SubstationScope(configNotifier: substationConfig, key: const ValueKey('scope.tg')),
    ]),
  ),
);

List<Branch> _all(Branch root) {
  final out = <Branch>[];
  void walk(Branch b) {
    out.add(b);
    b.visitChildren(walk);
  }

  walk(root);
  return out;
}

Branch _branchWhere(Branch root, bool Function(Seed seed) test) =>
    _all(root).firstWhere((b) => test(b.seed));

Branch? _workBead(Branch root, String beadId) {
  for (final b in _all(root)) {
    final seed = b.seed;
    if (seed is WorkBead && seed.bead.id == beadId) return b;
  }
  return null;
}

/// The single child branch of [wb] (the resolver's subtree root).
Branch _effectChild(Branch wb) {
  Branch? found;
  wb.visitChildren((c) => found = c);
  return found!;
}

/// Default rig config: rig `tg`, owning prefix `tg`.
SubstationConfig _tgConfig() => const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg'});

void main() {
  group('Track A — reconcile is the work lifecycle', () {
    test('two ready owned beads mount one work subtree each', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1'), _bead('tg-2')], ready: {'tg-1', 'tg-2'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);

      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );

      // mount = spawn the bead's work subtree, one per ready owned bead.
      expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
    });

    test(
      'a cursor advance is a reconcile transition: WorkList alone drains, the '
      'WorkBead AND its subtree-root child persist (config threads down in '
      'place — no WorkBead-level swap), config + sibling absent from the drain',
      () {
        final recorder = _Recorder();
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
          ),
        );
        final owner = TreeOwner();
        addTearDown(owner.dispose);
        final root = owner.mountRoot(
          _root(
            joined: joined,
            resolver: _FakeEffectResolver(recorder),
            substationConfig: SubstationConfigNotifier(_tgConfig()),
          ),
        );

        expect(recorder.events, ['START work(tg-1)', 'START work(tg-2)']);
        final wb1IdBefore = _workBead(root, 'tg-1')!.branchId;
        final child1IdBefore = _effectChild(_workBead(root, 'tg-1')!).branchId;
        recorder.events.clear();

        // Advance tg-1's SESSION cursor (A40: the cursor lives on the_grid's own
        // session bead). In the reentrant model this re-keys steps INSIDE the
        // subtree; at the WorkBead level the child is bead-keyed and PERSISTS.
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-s',
                cursor: {'tg-1/agent': NodeCursor(state: StepState.complete)},
              ),
            },
          ),
        );
        final flushed = owner.flush();

        // Only the observing node is drained. The changed WorkBead is
        // force-rebuilt by WorkList's reconcile cascade (its dirty flag cleared
        // before the drain) and is correctly EXCLUDED — asserting it were IN the
        // flush list would require it to observe the notifier itself, a
        // derailment-invariant-1 violation.
        final workList = _branchWhere(root, (s) => s is WorkList);
        expect(flushed, equals([workList]));

        // The WorkBead branch AND its subtree-root child keep their identity —
        // the cursor advance threaded down as config, never a WorkBead-level
        // swap (the fake root records NOTHING; the in-subtree step swap is
        // track_c/track_h's concern).
        expect(recorder.events, isEmpty);
        expect(_workBead(root, 'tg-1')!.branchId, wb1IdBefore);
        expect(_effectChild(_workBead(root, 'tg-1')!).branchId, child1IdBefore);

        // Guardrail: config ancestors + the sibling are ABSENT from the drain.
        expect(flushed, isNot(contains(_branchWhere(root, (s) => s is Station))));
        expect(
          flushed,
          isNot(contains(_branchWhere(root, (s) => s is SubstationScope))),
        );
        expect(flushed, isNot(contains(_branchWhere(root, (s) => s is Substation))));
        expect(flushed, isNot(contains(_workBead(root, 'tg-2'))));
      },
    );
  });

  group('Track A — the config axis is separate and live', () {
    test('a config tick rebuilds the config scope and starts/stops no work '
        'subtree (the inverse of the work-tick guardrail)', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1')], ready: {'tg-1'}),
      );
      final substationConfig = SubstationConfigNotifier(_tgConfig());
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: substationConfig,
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);
      recorder.events.clear();

      // Tick the CONFIG axis (a different owned set value).
      substationConfig.push(const SubstationConfig(substationId: 'tg', ownedSubstations: {'tg', 'other'}));
      final flushed = owner.flush();

      // The config observer (SubstationScope) rebuilt; Substation is force-rebuilt by the
      // cascade and excluded. A config tick is real (proving the work-tick
      // guardrail's absence is meaningful, not because config is inert)...
      expect(flushed, equals([_branchWhere(root, (s) => s is SubstationScope)]));
      // ...yet it touches NO work subtree.
      expect(recorder.events, isEmpty);
    });
  });

  group('Track A — the corrected child-set predicate', () {
    test('positive-terminal-only unmount: a ready→blocked bead with a live '
        'session stays mounted; a closed bead unmounts and kills', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1')], ready: {'tg-1'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);

      // tg-1 leaves the ready-set (blocked) but keeps a live (non-terminal)
      // session — its work subtree must NOT be unmounted/killed.
      recorder.events.clear();
      joined.push(
        _joined(
          beads: [_bead('tg-1', status: BeadStatus.blocked)],
          ready: const {},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
            ),
          },
        ),
      );
      owner.flush();
      expect(
        recorder.events,
        isEmpty,
        reason: 'a ready-set exit with a live session is not a positive terminal',
      );
      expect(_workBead(root, 'tg-1'), isNotNull);

      // A positive terminal (bead closed) unmounts + kills.
      recorder.events.clear();
      joined.push(
        _joined(
          beads: [_bead('tg-1', status: BeadStatus.closed)],
          ready: const {},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
            ),
          },
        ),
      );
      owner.flush();
      expect(recorder.events, ['STOP work(tg-1)']);
      expect(_workBead(root, 'tg-1'), isNull);
    });

    test('a terminal session cursor also unmounts (the foreign-bead arm: the '
        'cursor is on the_grid own bead, so done shows even if the work bead '
        'never closes)', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
            ),
          },
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );
      expect(recorder.events, ['START work(tg-1)']);

      recorder.events.clear();
      // The work bead is STILL open + ready, but the owned session cursor went
      // terminal → unmount (never respawn).
      joined.push(
        _joined(
          beads: [_bead('tg-1')],
          ready: {'tg-1'},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              sessionId: 'tgdog-s',
              isTerminal: true,
            ),
          },
        ),
      );
      owner.flush();
      expect(recorder.events, ['STOP work(tg-1)']);
      expect(_workBead(root, 'tg-1'), isNull);
    });

    test('allow-list type gate (A41): only core work mounts — every the_grid '
        'custom type (convergence, infra, AND the orchestration nouns bd ready '
        'leaks) mounts ZERO work beads', () {
      final recorder = _Recorder();
      // Every the_grid custom IssueType, all owned + ready. NONE may mount —
      // especially the orchestration nouns (convoy/event/step/spec/gate/
      // molecule/message/merge-request) that bd ready does NOT narrow out and a
      // deny-list missed.
      final customs = <String, IssueType>{
        'tg-conv': IssueType.convergence,
        'tg-cvy': IssueType.convoy,
        'tg-evt': IssueType.event,
        'tg-gate': IssueType.gate,
        'tg-mr': IssueType.mergeRequest,
        'tg-msg': IssueType.message,
        'tg-mol': IssueType.molecule,
        'tg-role': IssueType.role,
        'tg-rig': IssueType.rig,
        'tg-agent': IssueType.agent,
        'tg-sess': IssueType.session,
        'tg-spec': IssueType.spec,
        'tg-step': IssueType.step,
      };
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            for (final e in customs.entries) _bead(e.key, type: e.value),
            _bead('tg-1'), // a plain task
          ],
          ready: {...customs.keys, 'tg-1'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );

      // Only the plain task mounted a work subtree.
      expect(recorder.events, ['START work(tg-1)']);
      for (final id in customs.keys) {
        expect(_workBead(root, id), isNull, reason: '$id must not mount');
      }
      expect(_workBead(root, 'tg-1'), isNotNull);
    });

    test('core work types each mount (the allow-list is not over-narrow)', () {
      final recorder = _Recorder();
      final core = <String, IssueType>{
        'tg-task': IssueType.task,
        'tg-bug': IssueType.bug,
        'tg-feat': IssueType.feature,
        'tg-chore': IssueType.chore,
      };
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [for (final e in core.entries) _bead(e.key, type: e.value)],
          ready: core.keys.toSet(),
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );

      for (final id in core.keys) {
        expect(_workBead(root, id), isNotNull, reason: '$id should mount');
      }
      expect(recorder.events.length, core.length);
    });

    test('an unowned bead (foreign prefix) never mounts (fail-closed)', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1'), _bead('gc-9')], ready: {'tg-1', 'gc-9'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(_tgConfig()),
        ),
      );

      expect(recorder.events, ['START work(tg-1)']);
      expect(_workBead(root, 'gc-9'), isNull);
    });

    test('blessed-bead drive-list (ADR-0006): when non-empty, ONLY listed beads '
        'mount — owned, ready, core beads not blessed stay dormant', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_bead('tg-1'), _bead('tg-2'), _bead('tg-3')],
          ready: {'tg-1', 'tg-2', 'tg-3'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            _tgConfig().copyWith(driveList: const {'tg-2'}),
          ),
        ),
      );

      // Only the blessed bead mounted; the other owned/ready/core beads did not.
      expect(recorder.events, ['START work(tg-2)']);
      expect(_workBead(root, 'tg-1'), isNull);
      expect(_workBead(root, 'tg-2'), isNotNull);
      expect(_workBead(root, 'tg-3'), isNull);
    });

    test('the drive-list NARROWS, never widens: a blessed bead still fails the '
        'ownership + type gates', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [
            _bead('tg-1'), // owned + core + blessed → mounts
            _bead('gc-9'), // blessed but UNOWNED → no
            _bead('tg-conv', type: IssueType.convergence), // blessed but non-core → no
          ],
          ready: {'tg-1', 'gc-9', 'tg-conv'},
        ),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          substationConfig: SubstationConfigNotifier(
            // ALL three blessed — the drive-list cannot resurrect a bead the
            // ownership / type gates reject.
            _tgConfig().copyWith(driveList: const {'tg-1', 'gc-9', 'tg-conv'}),
          ),
        ),
      );

      expect(recorder.events, ['START work(tg-1)']);
      expect(_workBead(root, 'gc-9'), isNull);
      expect(_workBead(root, 'tg-conv'), isNull);
    });
  });
}
