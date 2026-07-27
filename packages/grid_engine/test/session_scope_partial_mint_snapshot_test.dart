import 'dart:async';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:grid_engine/testing.dart';
import 'package:grid_runtime/grid_runtime.dart';
import 'package:test/test.dart';

/// tg-nmhy — a partial-mint joined snapshot must NEVER crash the tree.
///
/// `_mintMolecule` writes the session bead (`createSession`) and the step
/// graph (`createMolecule`) as TWO store writes. A `JoinedSnapshot` captured
/// between them says `isMolecule` yet projects ZERO step beads;
/// `matchesJoin` admits it on session-id alone. Before the fix,
/// `SessionScope.build` mounted an `InheritedCircuit` with an empty
/// `beadIdByNodePath` and `CircuitScope`'s fresh-projection guard threw a
/// `StateError` INSIDE the flush — which runs in an unguarded root-zone
/// microtask (`StationKernel._scheduleFlush`), so one partial snapshot
/// killed the whole resident station VM at boot (three live receipts:
/// tg-5drf.1, tg-udnu, tg-wvmt).
///
/// The fix treats the partial snapshot as STILL RESOLVING: the molecule arm
/// returns `Idle` until the projection carries the poured step graph.
void main() {
  const sessionId = 'tgdog-session';
  const routePath = 'tg-nmhy/spec_review/route';

  const root = Circuit(
    id: 'root',
    terminalStepId: 'spec_review',
    steps: [SubCircuitStep(stepId: 'spec_review', circuitId: 'spec_review')],
  );

  Bead stepBead(
    String id, {
    required String path,
    required StepState state,
    String capability = 'route',
  }) => Bead(
    id: id,
    issueType: IssueType.step,
    status: BeadStatus.open,
    metadata: {
      MoleculeStepKeys.path: path,
      MoleculeStepKeys.session: sessionId,
      MoleculeStepKeys.state: state.name,
      MoleculeStepKeys.stepId: path.split('/').last,
      MoleculeStepKeys.capability: capability,
      MoleculeStepKeys.kind: StepKind.job.name,
    },
  );

  Future<void> pump() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a between-writes molecule snapshot (isMolecule, zero step beads) '
      'idles instead of throwing through the flush; the completed snapshot '
      'then drives normally', () async {
    final fakes = buildFakes();
    final services = StationServices(
      provider: fakes.provider,
      writer: StationBeadWriter(
        bd: BdCliService(fakes.runner),
        ownership: BeadOwnershipPredicate(const {stateSubstation, 'route'}),
      ),
      stateSubstation: stateSubstation,
    );
    final transport = RecordingExplorationTransport();
    final ranRounds = <String?>[];
    final registry = _Registry(_RecordingRoute(ranRounds));
    var owner = TreeOwner();
    addTearDown(() {
      owner.dispose();
      unawaited(fakes.provider.close());
    });

    void mount(SessionProjection projection) {
      owner.mountRoot(
        InheritedSeed<StationServices>(
          value: services,
          child: InheritedSeed<CapabilityRegistry>(
            value: registry,
            child: InheritedSeed<ServiceBundle>(
              value: ServiceBundle(transport: transport),
              child: SessionScope(
                bead: bead('tg-nmhy'),
                circuit: root,
                existingSession: projection,
              ),
            ),
          ),
        ),
      );
    }

    // Phase A — the between-writes snapshot: session bead landed
    // (`isMolecule: true`) but the step-graph pour has not. Pre-fix this
    // threw `CircuitScope has no step-bead id for
    // "tg-nmhy/spec_review/route"` out of the flush.
    final partial = SessionProjection(
      workBeadId: 'tg-nmhy',
      sessionId: sessionId,
      isMolecule: true,
      cursor: const {},
      moleculeBeads: const [],
      moleculeDependencies: const [],
    );
    mount(partial);
    await pump();

    expect(ranRounds, isEmpty, reason: 'no step may mount off a partial pour');
    expect(fakes.runner.callsFor('update'), isEmpty);
    // The partial projection no longer merely idles: the scope RESUMES the
    // potentially-orphaned pour (a single re-entry-safe graph pour — see
    // session_scope_orphaned_pour_resume_test.dart). What it must NEVER do
    // is mint a second session bead.
    expect(
      fakes.runner
          .callsFor('create')
          .where((c) => c.length > 1 && c[1] != '--graph'),
      isEmpty,
      reason: 'a partial projection must never mint a fresh session',
    );

    // Phase B — the next snapshot tick carries the poured graph: the SAME
    // scope shape proceeds into a normal fresh round.
    owner.dispose();
    owner = TreeOwner();
    final complete = SessionProjection(
      workBeadId: 'tg-nmhy',
      sessionId: sessionId,
      isMolecule: true,
      cursor: const {routePath: NodeCursor()},
      moleculeBeads: [
        stepBead(
          'spec-review',
          path: 'tg-nmhy/spec_review',
          state: StepState.pending,
          capability: 'spec_review',
        ),
        stepBead('route-0', path: routePath, state: StepState.pending),
      ],
      moleculeDependencies: const [],
    );
    mount(complete);
    await pump();

    expect(ranRounds, isNotEmpty, reason: 'the complete pour must drive');
    final write = fakes.runner.callsFor('update').single;
    expect(write[1], 'route-0');
  });
}

class _Registry implements CapabilityRegistry {
  _Registry(this.route);

  final _RecordingRoute route;

  @override
  DateTime now() => DateTime(2026);

  @override
  Circuit? circuit(String circuitId) => circuitId == 'spec_review'
      ? const Circuit(
          id: 'spec_review',
          terminalStepId: 'route',
          steps: [CapabilityStep(stepId: 'route', capabilityId: 'route')],
        )
      : null;

  @override
  Seed host(StepMount mount) =>
      CapabilityHost(capability: route, mount: mount, key: mount.key);
}

class _RecordingRoute extends RouteCapability {
  _RecordingRoute(this.ranRounds);

  final List<String?> ranRounds;

  @override
  Future<RouteVerdict> route(TreeContext context, StepArgs args) async {
    ranRounds.add(args.params['grid.round']);
    return const Advance({'lane': 'A'});
  }
}
