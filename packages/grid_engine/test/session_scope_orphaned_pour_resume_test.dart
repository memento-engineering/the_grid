// tg-nmhy case 2 / tg-hceh sequel — an ORPHANED POUR is resumed, not idled.
//
// `_mintMolecule` writes the session bead, then checks `_cancelled` /
// `context.mounted` before pouring the step graph. The session write itself
// triggers the snapshot tick that reconciles the WorkList — which can retire
// the minting scope mid-flight. The pour is then silently abandoned, and the
// ADOPTING scope joins a step-less molecule session that nobody will ever
// pour: pre-#122 that partial projection crashed the VM; post-#122 it idled
// FOREVER. Live receipt (2026-07-26): an entire arm minted 14 sessions and
// poured ZERO step graphs — 14 silent idles.
//
// The fix: the adopting scope RESUMES the pour — the plan is deterministic
// (`instantiateMolecule`) and `createMolecule` is re-entry-safe (R6 dedup),
// so a snapshot-lag false positive degrades to a no-op.
//
// Zero I/O — the recording chokepoint + a fake transport (Fakes, not mocks).
import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:test/test.dart';

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

class _RecordingTransport implements ExplorationTransport {
  final List<({String name, Map<String, String> data})> flares = [];

  @override
  void flare(String name, Map<String, String> data) =>
      flares.add((name: name, data: data));

  List<({String name, Map<String, String> data})> named(String name) =>
      flares.where((f) => f.name == name).toList();
}

Bead _task(String id) =>
    Bead(id: id, issueType: IssueType.task, status: BeadStatus.open);

Bead _stepBead(String id, {required String path, required String session}) =>
    Bead(
      id: id,
      issueType: IssueType.step,
      status: BeadStatus.open,
      metadata: {
        MoleculeStepKeys.path: path,
        MoleculeStepKeys.session: session,
        MoleculeStepKeys.state: StepState.pending.name,
        MoleculeStepKeys.stepId: path.split('/').last,
        MoleculeStepKeys.capability: path.split('/').last,
        MoleculeStepKeys.kind: StepKind.job.name,
      },
    );

JoinedSnapshot _joined(Map<String, SessionProjection> sessions) =>
    JoinedSnapshot(
      graph: GraphSnapshot.fromParts(
        beads: [_task('tg-1')],
        dependencies: const [],
        readyIds: const {'tg-1'},
        capturedAt: DateTime(2026),
      ),
      sessionsByWorkBead: sessions,
    );

({TreeOwner owner, Branch root}) _mount({
  required JoinedSnapshotNotifier joined,
  required StationServices ctx,
  required CapabilityRegistry registry,
  required ExplorationTransport transport,
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
            value: CircuitResolver((_) => _code),
            child: Station([
              SubstationScope(
                configNotifier: SubstationConfigNotifier(
                  const SubstationConfig(
                    substationId: 'tg',
                    ownedSubstations: {'tg'},
                  ),
                ),
                services: ServiceBundle(transport: transport),
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

Future<void> _pumpUntil(
  TreeOwner owner,
  bool Function() condition, {
  int maxRounds = 500,
}) async {
  for (var i = 0; i < maxRounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    owner.flush();
  }
}

/// The orphan: an OPEN molecule session bead with ZERO step beads — the
/// abandoned-pour shape the adopting scope joins.
const _orphan = SessionProjection(
  workBeadId: 'tg-1',
  sessionId: 'tgdog-orphan',
  isMolecule: true,
  cursor: {},
  moleculeBeads: [],
  moleculeDependencies: [],
);

void main() {
  test('an adopted step-less molecule session gets its pour RESUMED: exactly '
      'one graph pour, NO fresh session mint, no flares', () async {
    final f = buildFakes();
    final transport = _RecordingTransport();
    final reg = RecordingCapabilityRegistry(circuits: const {});
    final m = _mount(
      joined: JoinedSnapshotNotifier(_joined(const {'tg-1': _orphan})),
      ctx: f.ctx,
      registry: reg,
      transport: transport,
    );
    addTearDown(m.owner.dispose);

    await _pumpUntil(m.owner, () => f.runner.callsFor('create').isNotEmpty);

    final creates = f.runner.callsFor('create');
    // Pre-fix: ZERO creates, ever — the scope idled forever on the partial
    // projection. Post-fix: exactly the resumed graph pour, and NOTHING
    // else — resuming must never mint a second session bead.
    expect(creates, isNotEmpty, reason: 'the orphaned pour must be resumed');
    expect(
      creates.where((c) => c.length > 1 && c[1] == '--graph'),
      hasLength(1),
      reason: 'the resume is a single graph pour',
    );
    expect(
      creates.where((c) => c.length > 1 && c[1] != '--graph'),
      isEmpty,
      reason: 'adoption resumes the EXISTING session — no fresh mint',
    );
    expect(transport.named('session.orphanedPourResumeFailed'), isEmpty);
  });

  test(
    'a healthy adopted molecule session (steps present) pours NOTHING',
    () async {
      final f = buildFakes();
      final transport = _RecordingTransport();
      final reg = RecordingCapabilityRegistry(circuits: const {});
      final healthy = SessionProjection(
        workBeadId: 'tg-1',
        sessionId: 'tgdog-live',
        isMolecule: true,
        cursor: const {'tg-1/agent': NodeCursor()},
        moleculeBeads: [
          _stepBead('step-agent', path: 'tg-1/agent', session: 'tgdog-live'),
          _stepBead('step-verify', path: 'tg-1/verify', session: 'tgdog-live'),
          _stepBead('step-land', path: 'tg-1/land', session: 'tgdog-live'),
        ],
        moleculeDependencies: const [],
      );
      final m = _mount(
        joined: JoinedSnapshotNotifier(_joined({'tg-1': healthy})),
        ctx: f.ctx,
        registry: reg,
        transport: transport,
      );
      addTearDown(m.owner.dispose);

      await _pumpUntil(m.owner, () => reg.events.isNotEmpty, maxRounds: 200);

      expect(
        f.runner
            .callsFor('create')
            .where((c) => c.length > 1 && c[1] == '--graph'),
        isEmpty,
        reason: 'a complete projection never triggers a resume pour',
      );
    },
  );
}
