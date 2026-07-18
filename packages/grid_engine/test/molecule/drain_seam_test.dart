// pm6-r5-drain — the drain seam: SessionScope's molecule mint-mode branch,
// the effective-cursor `build()` feed, and the reap-on-close collection
// (`DESIGN-tg-pm6.md` §12).
//
// Mirrors `track_c_session_scope_test.dart`'s harness (`_mountFull`) — a REAL
// `TreeOwner`-mounted station tree over the grid_engine testing Fakes
// (`buildFakes`/`RecordingBdRunner`/`RecordingCapabilityRegistry`). Zero I/O.
//
// The drain proof (Q3 dissolves, `DESIGN-tg-pm6.md` §12): adoption
// short-circuits at `SessionScope.initState`'s `LiveSession()` arm BEFORE any
// `CircuitMintMode` check — an in-flight session (flat OR molecule) is never
// reinterpreted; only a FRESH mint ever reads the ambient mode. That is the
// load-bearing claim this suite proves end-to-end, not just per-file.
import 'dart:async';

import 'package:genesis_tree/genesis_tree.dart';
import 'package:beads_dart/beads_dart.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/src/molecule/molecule_schema.dart';
import 'package:grid_engine/src/molecule/process_lease_vendor.dart';
import 'package:grid_engine/src/molecule/station_process_transport.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// The `code` circuit `track_c_session_scope_test.dart` also drives
/// (`agent → verify → land`) — reused so the flat-mode assertions here read
/// directly against that suite's own known-good shapes.
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

/// A `build → critic → land` circuit whose `critic` VALIDATES `build`
/// (the declarative `kValidatesParam` convention, R1) — the fixture the
/// end-to-end derivation test drives.
const _validatedCode = Circuit(
  id: 'validated',
  terminalStepId: 'land',
  steps: [
    CapabilityStep(stepId: 'build', capabilityId: 'build'),
    CapabilityStep(
      stepId: 'critic',
      capabilityId: 'critic',
      dependsOn: {'build'},
      params: {kValidatesParam: 'build'},
    ),
    CapabilityStep(stepId: 'land', capabilityId: 'land', dependsOn: {'critic'}),
  ],
);

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Polls [condition] with a short real delay, up to [maxTries] — the
/// robust variant [_pump]'s fixed microtask-count drain cannot guarantee: a
/// molecule MINT's `createMolecule` pour rides the REAL `BdCliService`
/// `applyGraph`, which writes a genuine temp file (`dart:io`) before the
/// FAKE `BdRunner` boundary is ever reached — a bounded zero-duration pump
/// is not reliably enough turns of the real event loop for that I/O to
/// settle. Every other write in this suite resolves synchronously through
/// [RecordingBdRunner] (no real I/O), so [_pump] stays the right tool there.
Future<void> _pumpUntil(bool Function() condition, {int maxTries = 500}) async {
  for (var i = 0; i < maxTries && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

JoinedSnapshot _joined({
  required List<Bead> beads,
  required Set<String> ready,
  Map<String, SessionProjection> sessions = const {},
  List<BeadDependency> dependencies = const [],
}) => JoinedSnapshot(
  graph: GraphSnapshot.fromParts(
    beads: beads,
    dependencies: dependencies,
    readyIds: ready,
    capturedAt: DateTime(2026),
  ),
  sessionsByWorkBead: sessions,
);

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

/// A `type=molecule` bead owned by [sessionId] (mirrors
/// `molecule_join_test.dart`'s own fixture).
Bead _moleculeBead(
  String id, {
  required String sessionId,
  String formula = 'code',
}) => Bead(
  id: id,
  issueType: IssueType.molecule,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeCircuitKeys.formula: formula,
    MoleculeCircuitKeys.session: sessionId,
  },
);

/// A `type=step` bead owned by [sessionId] at engine coordinate [path]; an
/// explicit fine [state] is stamped when given (absent ⇒ the bd-status
/// fallback, "hasn't run yet"). [extra] carries additional metadata (e.g. a
/// `grid.result.<path>.grade` stamp for the validates-derivation fixture).
Bead _stepBead(
  String id, {
  required String sessionId,
  required String path,
  StepState? state,
  Map<String, String> extra = const {},
}) => Bead(
  id: id,
  issueType: IssueType.step,
  status: BeadStatus.open,
  metadata: {
    'rig': stateSubstation,
    MoleculeStepKeys.stepId: path.split('/').last,
    MoleculeStepKeys.capability: path.split('/').last,
    MoleculeStepKeys.kind: StepKind.job.name,
    MoleculeStepKeys.path: path,
    MoleculeStepKeys.session: sessionId,
    if (state != null) MoleculeStepKeys.state: state.name,
    ...extra,
  },
);

/// The full new-path root (mirrors `track_c_session_scope_test.dart`'s
/// `_mountFull`, parameterized over [config] so a test can arm
/// `CircuitMintMode.molecule`): `WorkList` observes [joined]; `WorkBead`
/// resolves through the `CircuitResolver` → `SessionScope` → `CircuitScope`;
/// `SessionScope` mints via the `StationServices` writer; `CircuitScope`
/// inflates via the registry.
({TreeOwner owner, Branch root}) _mountFull({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required RootCircuitFor rootCircuit,
  required SubstationConfig config,
}) {
  final owner = TreeOwner();
  final root = owner.mountRoot(
    InheritedSeed<JoinedSnapshotNotifier>(
      value: joined,
      child: InheritedSeed<StationServices>(
        value: ctx,
        child: InheritedSeed<CapabilityRegistry>(
          value: registry,
          child: InheritedSeed<SessionResolver>(
            value: CircuitResolver(rootCircuit),
            child: InheritedSeed<ProcessLeaseVendor>(
              value: defaultProcessLeaseVendor(ctx),
              child: Station([
                SubstationScope(
                  configNotifier: SubstationConfigNotifier(config),
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

const _flatConfig = SubstationConfig(
  substationId: 'tg',
  ownedSubstations: {'tg'},
);
final _moleculeConfig = _flatConfig.copyWith(
  circuitMintMode: CircuitMintMode.molecule,
);

class _LiveArmProcessCap extends ProcessCapability {
  const _LiveArmProcessCap(this.id, {this.payload = const <String, String>{}});

  final String id;
  final Map<String, String> payload;

  @override
  RuntimeConfig spawn(TreeContext context, StepArgs args) => RuntimeConfig(
    workDir: context.getInheritedSeedOfExactType<Workspace>()!.workspaceDir,
    command: 'sh',
    args: const ['-c', 'true'],
    lifecycle: Lifecycle.oneTurn,
  );

  @override
  StepSignal interpretEvent(RuntimeEvent event) => switch (event) {
    Exited(:final exitCode) when exitCode == 0 => StepSignal.complete,
    Exited() || Died() => StepSignal.failed,
    _ => StepSignal.none,
  };

  @override
  Future<Map<String, String>> result(
    TreeContext context,
    StepArgs args,
  ) async => payload;
}

void main() {
  group(
    'the drain seam — flat mode is byte-for-byte (default CircuitMintMode.flatCursor)',
    () {
      test(
        'a flat mint stamps NO grid.session.model key — default mode is flatCursor',
        () async {
          final f = buildFakes();
          final reg = RecordingCapabilityRegistry(circuits: const {});
          final joined = JoinedSnapshotNotifier(
            _joined(beads: [_task('tg-2')], ready: {'tg-2'}),
          );
          final m = _mountFull(
            joined: joined,
            ctx: f.ctx,
            registry: reg,
            rootCircuit: (_) => _code,
            config: _flatConfig,
          );
          addTearDown(m.owner.dispose);

          await _pump();
          m.owner.flush();

          expect(f.runner.callsFor('create'), hasLength(1));
          expect(f.runner.graphApplyCalls, isEmpty);
          final stamp = f.runner.metadataOfUpdate(0);
          expect(stamp.containsKey(SessionBeadKeys.model), isFalse);
          expect(stamp.keys.toSet(), {'rig', 'work_bead', 'started_at'});
          expect(reg.events, ['START agent(tgdog-sess1/tg-2/agent)']);
        },
      );

      test(
        'a flat sessionBead fixture (no grid.session.model key) adopts through '
        'the unchanged flat path and completes — no export/batch call ever '
        '(reapMolecule is molecule-only)',
        () async {
          final f = buildFakes();
          final reg = RecordingCapabilityRegistry(circuits: const {});
          final bead = sessionBead(
            id: 'tgdog-flat1',
            workBeadId: 'tg-1',
            completed: {'agent', 'verify', 'land'},
          );
          expect(
            bead.metadata.containsKey(SessionBeadKeys.model),
            isFalse,
            reason: 'no model key — the ABSENT ⇒ flat drain guarantee',
          );
          final projection = projectSession(bead);
          expect(projection.isMolecule, isFalse);

          final joined = JoinedSnapshotNotifier(
            _joined(
              beads: [_task('tg-1')],
              ready: {'tg-1'},
              sessions: {'tg-1': projection},
            ),
          );
          final m = _mountFull(
            joined: joined,
            ctx: f.ctx,
            registry: reg,
            rootCircuit: (_) => _code,
            config: _flatConfig,
          );
          addTearDown(m.owner.dispose);

          await _pump();
          m.owner.flush();
          await _pump();

          // Adoption is synchronous — no createSession; the positive terminal
          // closes exactly once; the close transcript is IDENTICAL to today's
          // (no export scan, no batch — reapMolecule never fires on this arm).
          expect(f.runner.callsFor('create'), isEmpty);
          expect(f.runner.callsFor('export'), isEmpty);
          expect(f.runner.callsFor('batch'), isEmpty);
          expect(
            f.runner
                .callsFor('close')
                .where((c) => c.length > 1 && c[1] == 'tgdog-flat1'),
            hasLength(1),
          );
        },
      );

      test(
        'a mid-flight FLAT session adopts with ZERO bd calls even under AMBIENT '
        'molecule-mode config — adoption short-circuits before any '
        '`CircuitMintMode` check (the drain guarantee, Q3 dissolves)',
        () async {
          final f = buildFakes();
          final reg = RecordingCapabilityRegistry(circuits: const {});
          final joined = JoinedSnapshotNotifier(
            _joined(
              beads: [_task('tg-1')],
              ready: {'tg-1'},
              sessions: {
                'tg-1': const SessionProjection(
                  workBeadId: 'tg-1',
                  sessionId: 'tgdog-existing',
                  // isMolecule defaults false: a FLAT session, already adopted
                  // — even though the ambient config below is molecule mode.
                ),
              },
            ),
          );
          final m = _mountFull(
            joined: joined,
            ctx: f.ctx,
            registry: reg,
            rootCircuit: (_) => _code,
            // The station-wide default is MOLECULE — proving the in-flight
            // session's OWN durable shape governs, never the ambient config.
            config: _moleculeConfig,
          );
          addTearDown(m.owner.dispose);

          await _pump();
          m.owner.flush();

          expect(
            f.runner.calls,
            isEmpty,
            reason: 'adoption is synchronous — never a bd call of any kind',
          );
          expect(reg.events, ['START agent(tgdog-existing/tg-1/agent)']);
        },
      );
    },
  );

  group('the drain seam — molecule mint mode', () {
    test(
      'a molecule-mode NoSession() mints createSession (stamping '
      'grid.session.model=molecule) then pours the graph EXACTLY once',
      () async {
        final f = buildFakes();
        f.runner.graphApplyIds = {
          'tg-9': 'tgdog-mol1',
          'tg-9/agent': 'tgdog-step-agent',
          'tg-9/verify': 'tgdog-step-verify',
          'tg-9/land': 'tgdog-step-land',
        };
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final joined = JoinedSnapshotNotifier(
          _joined(beads: [_task('tg-9')], ready: {'tg-9'}),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          config: _moleculeConfig,
        );
        addTearDown(m.owner.dispose);

        await _pump();
        m.owner.flush();
        // `createMolecule`'s pour rides the REAL `BdCliService.applyGraph`
        // (a genuine temp-file write before the fake `BdRunner` boundary) —
        // poll rather than a bounded microtask pump (see `_pumpUntil`'s doc).
        await _pumpUntil(() => f.runner.graphApplyCalls.isNotEmpty);

        // `callsFor('create')` INCLUDES graph-apply pours (they share the
        // `create` leading subcommand) — isolate the PLAIN single-bead
        // session create from the graph pour via `graphApplyCalls`.
        final plainCreates = f.runner
            .callsFor('create')
            .where((c) => !c.contains('--graph'));
        expect(plainCreates, hasLength(1), reason: 'the session mint');
        final stamp = f.runner.metadataOfUpdate(0);
        expect(stamp[SessionBeadKeys.model], kSessionModelMolecule);

        expect(
          f.runner.graphApplyCalls,
          hasLength(1),
          reason: 'exactly ONE pour',
        );
        final argv = f.runner.graphApplyCalls.single;
        expect(
          argv,
          isNot(contains('--ephemeral')),
          reason: 'Decided item 1: persistent, never a wisp',
        );

        // A later, unrelated flush must never re-pour (the mint state
        // machine only ever runs `_mint()` once per fresh mount).
        joined.push(_joined(beads: [_task('tg-9')], ready: {'tg-9'}));
        m.owner.flush();
        await _pump();
        expect(
          f.runner.callsFor('create').where((c) => !c.contains('--graph')),
          hasLength(1),
        );
        expect(f.runner.graphApplyCalls, hasLength(1));
      },
    );

    test(
      'mints molecule, stamps step beads, derives one invalidation round, and reaps at close',
      () async {
        final f = buildFakes();
        f.runner.graphApplyIds = {
          'tg-9': 'tgdog-mol9',
          'tg-9/build': 'tgdog-step9-build',
          'tg-9/critic': 'tgdog-step9-critic',
          'tg-9/land': 'tgdog-step9-land',
        };
        final reg = DefaultCapabilityRegistry(
          capabilities: const {
            'build': _LiveArmProcessCap('build'),
            'critic': _LiveArmProcessCap('critic'),
            'land': _LiveArmProcessCap('land'),
          },
          circuits: const {'validated': _validatedCode},
        );
        var joinedState = _joined(beads: [_task('tg-9')], ready: {'tg-9'});
        final joined = JoinedSnapshotNotifier(joinedState);
        var currentBuildStepId = 'tgdog-step9-build';
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _validatedCode,
          config: _moleculeConfig,
        );
        addTearDown(m.owner.dispose);

        Future<void> pushMolecule({
          StepState build = StepState.pending,
          StepState critic = StepState.pending,
          StepState land = StepState.pending,
          String criticGrade = 'A',
          bool includeSuccessor = false,
        }) async {
          currentBuildStepId = includeSuccessor
              ? 'tgdog-step9-build-r1'
              : 'tgdog-step9-build';
          final beads = <Bead>[
            _moleculeBead(
              'tgdog-mol9',
              sessionId: 'tgdog-sess1',
              formula: 'validated',
            ),
            _stepBead(
              currentBuildStepId,
              sessionId: 'tgdog-sess1',
              path: 'tg-9/build',
              state: build,
            ),
            _stepBead(
              'tgdog-step9-critic',
              sessionId: 'tgdog-sess1',
              path: 'tg-9/critic',
              state: critic,
              extra: {
                ResultKeys.keyFor('tg-9/critic', ResultKeys.grade): criticGrade,
              },
            ),
            _stepBead(
              'tgdog-step9-land',
              sessionId: 'tgdog-sess1',
              path: 'tg-9/land',
              state: land,
            ),
          ];
          final deps = includeSuccessor
              ? const [
                  BeadDependency(
                    issueId: 'tgdog-step9-build-r1',
                    dependsOnId: 'tgdog-step9-build',
                    type: DependencyType.supersedes,
                  ),
                ]
              : const <BeadDependency>[];
          f.runner.exportBeads = beads;
          joinedState = _joined(
            beads: [_task('tg-9')],
            ready: {'tg-9'},
            dependencies: deps,
            sessions: {
              'tg-9': SessionProjection(
                workBeadId: 'tg-9',
                sessionId: 'tgdog-sess1',
                isMolecule: true,
                moleculeBeads: beads,
                moleculeDependencies: deps,
              ),
            },
          );
          joined.push(joinedState);
          m.owner.flush();
          await _pump();
          m.owner.flush();
          await _pump();
        }

        bool hasStepStamp(String beadId, StepState state) {
          final updates = f.runner.callsFor('update');
          for (var i = 0; i < updates.length; i++) {
            if (updates[i].length > 1 &&
                updates[i][1] == beadId &&
                f.runner.metadataOfUpdate(i)[MoleculeStepKeys.state] ==
                    state.name) {
              return true;
            }
          }
          return false;
        }

        Future<void> finish(String path) async {
          final name = 'tgdog-sess1/$path';
          final beadId = switch (path) {
            'tg-9/build' => currentBuildStepId,
            'tg-9/critic' => 'tgdog-step9-critic',
            'tg-9/land' => 'tgdog-step9-land',
            _ => throw StateError('unknown step path $path'),
          };
          await _pumpUntil(() => f.provider.started.any((s) => s.name == name));
          f.provider.emit(SessionStarted(name: name, pid: 10, pgid: 10));
          await _pumpUntil(() => hasStepStamp(beadId, StepState.running));
          f.provider.emit(Exited(name: name, exitCode: 0));
          await _pumpUntil(() => hasStepStamp(beadId, StepState.complete));
        }

        await _pump();
        m.owner.flush();
        await _pumpUntil(() => f.runner.graphApplyCalls.isNotEmpty);

        expect(
          f.runner.callsFor('create').where((c) => !c.contains('--graph')),
          hasLength(1),
        );
        expect(f.runner.graphApplyCalls, hasLength(1));
        expect(
          f.runner.metadataOfUpdate(0)[SessionBeadKeys.model],
          kSessionModelMolecule,
        );
        expect(f.runner.graphApplyCalls.single, isNot(contains('--ephemeral')));

        await pushMolecule();
        await finish('tg-9/build');
        expect(hasStepStamp('tgdog-step9-build', StepState.running), isTrue);
        expect(hasStepStamp('tgdog-step9-build', StepState.complete), isTrue);

        await pushMolecule(build: StepState.complete);
        await finish('tg-9/critic');
        await pushMolecule(
          build: StepState.complete,
          critic: StepState.complete,
          criticGrade: 'F',
        );
        await _pumpUntil(
          () => f.runner
              .callsFor('dep')
              .any(
                (call) =>
                    call.length >= 4 &&
                    call[3] == 'tgdog-step9-build' &&
                    call.contains('supersedes'),
              ),
        );
        expect(
          f.runner
              .callsFor('dep')
              .where(
                (call) =>
                    call.length >= 4 &&
                    call[3] == 'tgdog-step9-build' &&
                    call.contains('supersedes'),
              ),
          hasLength(1),
        );

        await pushMolecule(
          build: StepState.pending,
          critic: StepState.complete,
          criticGrade: 'A',
          includeSuccessor: true,
        );
        await finish('tg-9/build');
        await pushMolecule(
          build: StepState.complete,
          critic: StepState.complete,
          criticGrade: 'A',
          includeSuccessor: true,
        );
        await finish('tg-9/land');
        await pushMolecule(
          build: StepState.complete,
          critic: StepState.complete,
          land: StepState.complete,
          criticGrade: 'A',
          includeSuccessor: true,
        );
        await _pumpUntil(() => f.runner.callsFor('batch').isNotEmpty);
        final batch = f.runner.callsFor('batch').single;
        expect(
          f.runner.stdins[f.runner.calls.indexOf(batch)],
          contains('close'),
        );
      },
    );
  });

  group(
    'the drain seam — flat and molecule sessions coexist in one snapshot',
    () {
      test('a flat session and a molecule session, both ADOPTED under the SAME '
          'ambient molecule-mode config, each inflate their OWN frontier '
          'independently', () async {
        final f = buildFakes();
        final reg = RecordingCapabilityRegistry(circuits: const {});
        final moleculeBeads = [
          _moleculeBead('tgdog-mol2', sessionId: 'tgdog-mol-sess'),
          _stepBead(
            'tgdog-step2-agent',
            sessionId: 'tgdog-mol-sess',
            path: 'tg-2/agent',
          ),
        ];
        final joined = JoinedSnapshotNotifier(
          _joined(
            beads: [_task('tg-1'), _task('tg-2')],
            ready: {'tg-1', 'tg-2'},
            sessions: {
              'tg-1': const SessionProjection(
                workBeadId: 'tg-1',
                sessionId: 'tgdog-existing',
              ),
              'tg-2': SessionProjection(
                workBeadId: 'tg-2',
                sessionId: 'tgdog-mol-sess',
                isMolecule: true,
                moleculeBeads: moleculeBeads,
              ),
            },
          ),
        );
        final m = _mountFull(
          joined: joined,
          ctx: f.ctx,
          registry: reg,
          rootCircuit: (_) => _code,
          config: _moleculeConfig,
        );
        addTearDown(m.owner.dispose);

        await _pump();
        m.owner.flush();

        expect(
          reg.events,
          unorderedEquals([
            'START agent(tgdog-existing/tg-1/agent)',
            'START agent(tgdog-mol-sess/tg-2/agent)',
          ]),
        );
        // Both sessions adopted — neither mints, so no bd traffic at all.
        expect(f.runner.calls, isEmpty);
      });
    },
  );

  group(
    'the drain seam — close fires reapMolecule on the molecule arm only',
    () {
      test(
        'a completed molecule session ALSO closes its OWN type=molecule/'
        'type=step beads via ONE bd batch (R6\'s session-close collection)',
        () async {
          final f = buildFakes();
          const sessionId = 'tgdog-mol-sess';
          final moleculeBeads = [
            _moleculeBead('tgdog-mol3', sessionId: sessionId),
            _stepBead(
              'tgdog-step3-agent',
              sessionId: sessionId,
              path: 'tg-3/agent',
              state: StepState.complete,
            ),
            _stepBead(
              'tgdog-step3-verify',
              sessionId: sessionId,
              path: 'tg-3/verify',
              state: StepState.complete,
            ),
            _stepBead(
              'tgdog-step3-land',
              sessionId: sessionId,
              path: 'tg-3/land',
              state: StepState.complete,
            ),
          ];
          // The writer's OWN snapshot scan (reapMolecule's `_moleculeBeadsFor`)
          // sees the SAME beads the join already bucketed.
          f.runner.exportBeads = moleculeBeads;
          final reg = RecordingCapabilityRegistry(circuits: const {});
          final joined = JoinedSnapshotNotifier(
            _joined(
              beads: [_task('tg-3')],
              ready: {'tg-3'},
              sessions: {
                'tg-3': SessionProjection(
                  workBeadId: 'tg-3',
                  sessionId: sessionId,
                  isMolecule: true,
                  moleculeBeads: moleculeBeads,
                ),
              },
            ),
          );
          final m = _mountFull(
            joined: joined,
            ctx: f.ctx,
            registry: reg,
            rootCircuit: (_) => _code,
            config: _moleculeConfig,
          );
          addTearDown(m.owner.dispose);

          await _pump();
          m.owner.flush();
          await _pump();

          expect(
            f.runner
                .callsFor('close')
                .where((c) => c.length > 1 && c[1] == sessionId),
            hasLength(1),
            reason: 'the session bead itself closes exactly once',
          );
          final batches = f.runner.callsFor('batch');
          expect(
            batches,
            hasLength(1),
            reason: 'reapMolecule closes the molecule set in ONE transaction',
          );
          final script =
              f.runner.stdins[f.runner.calls.indexOf(batches.single)]!;
          expect(
            script.split('\n'),
            unorderedEquals([
              'close tgdog-mol3',
              'close tgdog-step3-agent',
              'close tgdog-step3-verify',
              'close tgdog-step3-land',
            ]),
          );
        },
      );
    },
  );

  group('the drain seam — end-to-end derivation (R4 wired live)', () {
    test('a downstream invalidating stamp (critic grade F) remounts the '
        'upstream build step on a successor incarnation bead', () async {
      final f = buildFakes(createdId: 'tgdog-step7-build-r1');
      const sessionId = 'tgdog-mol-sess';
      const workBead = 'tg-7';
      final moleculeRoot = _moleculeBead('tgdog-mol7', sessionId: sessionId);
      Bead buildBead() => _stepBead(
        'tgdog-step7-build',
        sessionId: sessionId,
        path: '$workBead/build',
        state: StepState.complete,
      );
      Bead criticBead(String grade) => _stepBead(
        'tgdog-step7-critic',
        sessionId: sessionId,
        path: '$workBead/critic',
        state: StepState.complete,
        extra: {ResultKeys.keyFor('$workBead/critic', ResultKeys.grade): grade},
      );
      Bead landBead() => _stepBead(
        'tgdog-step7-land',
        sessionId: sessionId,
        path: '$workBead/land',
      );
      final successor = _stepBead(
        'tgdog-step7-build-r1',
        sessionId: sessionId,
        path: '$workBead/build',
      );
      const supersedes = BeadDependency(
        issueId: 'tgdog-step7-build-r1',
        dependsOnId: 'tgdog-step7-build',
        type: DependencyType.supersedes,
      );

      final reg = RecordingCapabilityRegistry(circuits: const {});
      final joined = JoinedSnapshotNotifier(
        _joined(
          beads: [_task(workBead)],
          ready: {workBead},
          sessions: {
            workBead: SessionProjection(
              workBeadId: workBead,
              sessionId: sessionId,
              isMolecule: true,
              moleculeBeads: [
                moleculeRoot,
                buildBead(),
                criticBead('A'),
                landBead(),
              ],
            ),
          },
        ),
      );
      final m = _mountFull(
        joined: joined,
        ctx: f.ctx,
        registry: reg,
        rootCircuit: (_) => _validatedCode,
        config: _moleculeConfig,
      );
      addTearDown(m.owner.dispose);
      await _pump();
      m.owner.flush();

      // Round 1: build + critic are COMPLETE jobs — retired, unmounted;
      // only `land` is eligible (critic is a positive terminal, grade A
      // does not invalidate).
      expect(reg.events, ['START land(tgdog-mol-sess/tg-7/land)']);
      reg.events.clear();
      final callsBeforeRound2 = f.runner.calls.length;

      // Round 2: critic's grade flips to F — a validates-source stamp,
      // nothing else changes. SessionScope holds the retired build bead and
      // schedules the A52 successor mint off build.
      joined.push(
        _joined(
          beads: [_task(workBead)],
          ready: {workBead},
          sessions: {
            workBead: SessionProjection(
              workBeadId: workBead,
              sessionId: sessionId,
              isMolecule: true,
              moleculeBeads: [
                moleculeRoot,
                buildBead(),
                criticBead('F'),
                landBead(),
              ],
            ),
          },
        ),
      );
      m.owner.flush();
      await _pump();

      final round2Calls = f.runner.calls.skip(callsBeforeRound2).toList();
      expect(
        reg.events,
        ['STOP land(tgdog-mol-sess/tg-7/land)'],
        reason:
            'the old terminal build bead is withheld until its successor '
            'arrives in the joined snapshot',
      );
      expect(
        round2Calls.any(
          (c) => c.length >= 2 && c[0] == 'export' && c[1] == '--all',
        ),
        isTrue,
      );
      expect(
        round2Calls.any(
          (c) =>
              c.isNotEmpty &&
              c[0] == 'create' &&
              c.contains('--type') &&
              c.contains(IssueType.step.wire),
        ),
        isTrue,
      );
      expect(
        round2Calls.any(
          (c) =>
              c.length >= 2 &&
              c[0] == 'update' &&
              c[1] == 'tgdog-step7-build-r1',
        ),
        isTrue,
      );
      expect(
        round2Calls.any(
          (c) =>
              c.length >= 6 &&
              c[0] == 'dep' &&
              c[1] == 'add' &&
              c[2] == 'tgdog-step7-build-r1' &&
              c[3] == 'tgdog-step7-build' &&
              c.contains('--type') &&
              c.contains(DependencyType.supersedes.wire),
        ),
        isTrue,
      );

      reg.events.clear();
      joined.push(
        _joined(
          beads: [_task(workBead)],
          ready: {workBead},
          dependencies: const [supersedes],
          sessions: {
            workBead: SessionProjection(
              workBeadId: workBead,
              sessionId: sessionId,
              isMolecule: true,
              moleculeBeads: [
                moleculeRoot,
                buildBead(),
                successor,
                criticBead('F'),
                landBead(),
              ],
              moleculeDependencies: const [supersedes],
            ),
          },
        ),
      );
      m.owner.flush();
      await _pump();

      expect(reg.events, ['START build(tgdog-mol-sess/tg-7/build)']);
    });
  });
}
