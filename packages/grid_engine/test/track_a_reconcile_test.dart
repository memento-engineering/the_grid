// Track A — the heart: the pure Seeds reconcile the running system, and the
// derailment-invariant-1 guardrail holds (only the observing node dirties; a
// work tick never rebuilds config; a phase advance is a reconcile transition).
//
// ADR-0007 §6.1 / M4-P0-BUILD-ORDER §3 Track A. Zero I/O — fakes only.
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes: an EffectResolver that mounts effects which record their lifecycle.
// ---------------------------------------------------------------------------

/// Records effect lifecycle in mount/unmount order — the observable proxy for
/// "spawn" (`START`) and "kill" (`STOP`).
class _Recorder {
  final List<String> events = [];
  void record(String event) => events.add(event);
}

/// Returns a `_FakeEffect` keyed `'<beadId>.<capId>'` — the key shape the real
/// resolver must honour so a phase advance swaps the effect child.
class _FakeEffectResolver implements EffectResolver {
  _FakeEffectResolver(this.recorder);
  final _Recorder recorder;

  @override
  Seed effectFor({
    required Bead bead,
    required WorkPhase phase,
    SessionProjection? session,
  }) => _FakeEffect(
    recorder: recorder,
    capId: phase.capId,
    beadId: bead.id,
    key: ValueKey('${bead.id}.${phase.capId}'),
  );
}

class _FakeEffect extends StatefulSeed {
  const _FakeEffect({
    required this.recorder,
    required this.capId,
    required this.beadId,
    super.key,
  });
  final _Recorder recorder;
  final String capId;
  final String beadId;

  @override
  State<_FakeEffect> createState() => _FakeEffectState();
}

class _FakeEffectState extends State<_FakeEffect> {
  @override
  void initState() => seed.recorder.record('START ${seed.capId}(${seed.beadId})');

  @override
  void dispose() => seed.recorder.record('STOP ${seed.capId}(${seed.beadId})');

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
/// Grid; give the single rig its config notifier.
Seed _root({
  required JoinedSnapshotNotifier joined,
  required EffectResolver resolver,
  required RigConfigNotifier rigConfig,
}) => InheritedSeed<JoinedSnapshotNotifier>(
  value: joined,
  child: InheritedSeed<EffectResolver>(
    value: resolver,
    child: Grid([
      RigScope(configNotifier: rigConfig, key: const ValueKey('scope.tg')),
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

/// Default rig config: rig `tg`, owning prefix `tg`.
RigConfig _tgConfig() => const RigConfig(rigId: 'tg', ownedRigs: {'tg'});

void main() {
  group('Track A — reconcile is the work lifecycle', () {
    test('two ready owned beads mount one implement effect each', () {
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
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );

      // mount = spawn; no session cursor ⇒ implement (capId `agent`).
      expect(recorder.events, ['START agent(tg-1)', 'START agent(tg-2)']);
    });

    test(
      'a phase advance is a reconcile transition: effect swaps, WorkBead branch '
      'persists, flush() returns exactly [WorkList], config + sibling absent',
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
            rigConfig: RigConfigNotifier(_tgConfig()),
          ),
        );

        expect(recorder.events, ['START agent(tg-1)', 'START agent(tg-2)']);
        final wb1IdBefore = _workBead(root, 'tg-1')!.branchId;
        recorder.events.clear();

        // Advance tg-1's SESSION cursor implement → verify (A40: the cursor
        // lives on the_grid's own session bead, not the work bead).
        joined.push(
          _joined(
            beads: [_bead('tg-1'), _bead('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                phase: WorkPhase.verify,
              ),
            },
          ),
        );
        final flushed = owner.flush();

        // Only the observing node is drained. The changed WorkBead is
        // force-rebuilt by WorkList's reconcile cascade (its dirty flag cleared
        // before the drain) and is correctly EXCLUDED — asserting it were IN
        // the flush list would require it to observe the notifier itself, a
        // derailment-invariant-1 violation.
        final workList = _branchWhere(root, (s) => s is WorkList);
        expect(flushed, equals([workList]));

        // The phase swap, proven separately: old capability killed, new spawned
        // — for tg-1 only.
        expect(recorder.events, ['STOP agent(tg-1)', 'START verify(tg-1)']);

        // The WorkBead branch keeps its identity across the swap.
        expect(_workBead(root, 'tg-1')!.branchId, wb1IdBefore);

        // Guardrail: config ancestors + the sibling are ABSENT from the drain
        // (they were never dirtied — ancestors of the sole dirtied node cannot
        // be force-rebuilt by a descendant's change, so their build did not
        // run; the sibling's effect recorded nothing above).
        expect(flushed, isNot(contains(_branchWhere(root, (s) => s is Grid))));
        expect(
          flushed,
          isNot(contains(_branchWhere(root, (s) => s is RigScope))),
        );
        expect(flushed, isNot(contains(_branchWhere(root, (s) => s is Rig))));
        expect(flushed, isNot(contains(_workBead(root, 'tg-2'))));
      },
    );

    test('a bead can run implement → verify → land as successive transitions', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1')], ready: {'tg-1'}),
      );
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );
      expect(recorder.events, ['START agent(tg-1)']);

      void advance(WorkPhase phase) {
        recorder.events.clear();
        joined.push(
          _joined(
            beads: [_bead('tg-1')],
            ready: {'tg-1'},
            sessions: {
              'tg-1': SessionProjection(workBeadId: 'tg-1', phase: phase),
            },
          ),
        );
        owner.flush();
      }

      advance(WorkPhase.verify);
      expect(recorder.events, ['STOP agent(tg-1)', 'START verify(tg-1)']);
      advance(WorkPhase.land);
      expect(recorder.events, ['STOP verify(tg-1)', 'START land(tg-1)']);
    });
  });

  group('Track A — the config axis is separate and live', () {
    test('a config tick rebuilds the config scope and starts/stops no work '
        'effect (the inverse of the work-tick guardrail)', () {
      final recorder = _Recorder();
      final joined = JoinedSnapshotNotifier(
        _joined(beads: [_bead('tg-1')], ready: {'tg-1'}),
      );
      final rigConfig = RigConfigNotifier(_tgConfig());
      final owner = TreeOwner();
      addTearDown(owner.dispose);
      final root = owner.mountRoot(
        _root(
          joined: joined,
          resolver: _FakeEffectResolver(recorder),
          rigConfig: rigConfig,
        ),
      );
      expect(recorder.events, ['START agent(tg-1)']);
      recorder.events.clear();

      // Tick the CONFIG axis (a different owned set value).
      rigConfig.push(const RigConfig(rigId: 'tg', ownedRigs: {'tg', 'other'}));
      final flushed = owner.flush();

      // The config observer (RigScope) rebuilt; Rig is force-rebuilt by the
      // cascade and excluded. A config tick is real (proving the work-tick
      // guardrail's absence is meaningful, not because config is inert)...
      expect(flushed, equals([_branchWhere(root, (s) => s is RigScope)]));
      // ...yet it touches NO work effect.
      expect(recorder.events, isEmpty);
    });
  });

  group('Track A — the corrected child-set predicate', () {
    test('positive-terminal-only unmount: a ready→blocked bead with a live '
        'agent stays mounted; a closed bead unmounts and kills', () {
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
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );
      expect(recorder.events, ['START agent(tg-1)']);

      // tg-1 leaves the ready-set (blocked) but keeps a live (non-terminal)
      // session — its agent must NOT be unmounted/killed.
      recorder.events.clear();
      joined.push(
        _joined(
          beads: [_bead('tg-1', status: BeadStatus.blocked)],
          ready: const {},
          sessions: {
            'tg-1': const SessionProjection(
              workBeadId: 'tg-1',
              phase: WorkPhase.implement,
            ),
          },
        ),
      );
      owner.flush();
      expect(
        recorder.events,
        isEmpty,
        reason: 'a ready-set exit with a live agent is not a positive terminal',
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
              phase: WorkPhase.implement,
            ),
          },
        ),
      );
      owner.flush();
      expect(recorder.events, ['STOP agent(tg-1)']);
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
              phase: WorkPhase.land,
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
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );
      expect(recorder.events, ['START land(tg-1)']);

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
              phase: WorkPhase.land,
              isTerminal: true,
            ),
          },
        ),
      );
      owner.flush();
      expect(recorder.events, ['STOP land(tg-1)']);
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
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );

      // Only the plain task spawned an agent.
      expect(recorder.events, ['START agent(tg-1)']);
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
          rigConfig: RigConfigNotifier(_tgConfig()),
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
          rigConfig: RigConfigNotifier(_tgConfig()),
        ),
      );

      expect(recorder.events, ['START agent(tg-1)']);
      expect(_workBead(root, 'gc-9'), isNull);
    });
  });
}
