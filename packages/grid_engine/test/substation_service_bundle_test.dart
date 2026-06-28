// ADR-0008 D5 — source control is a PER-SUBSTATION responsibility.
//
// The ServiceBundle (the SourceControl a CapabilityHost provisions/lands through)
// is provided by each `SubstationScope`, NOT above the `Station`. So when two
// substations run side by side, each substation's work resolves the NEAREST
// bundle — its OWN SourceControl — never a station-wide one. This is the capability
// the re-home unlocks: a project dictates its own SCM (root/head/remote/land).
//
// The proof drives the REAL kernel with two substations, two ready owned beads
// (one per substation, routed by id-prefix ownership), and two DISTINCT recording
// SourceControls. Each host materializes its workspace before the agent spawns
// (the host owns provisioning, D5) — so the recorded provision is the observable
// routing signal. If a single shared station bundle still existed, BOTH beads
// would hit ONE SourceControl; the per-substation isolation is exactly that they
// do not. Zero I/O — offline fakes (no live tg/gc/claude/git).
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_controller/grid_controller.dart';
import 'package:grid_engine/grid_engine.dart';
import 'package:test/test.dart';

import 'support/engine_fakes.dart';

GraphSnapshot _graph({
  required List<Bead> beads,
  required Set<String> ready,
}) => GraphSnapshot.fromParts(
  beads: beads,
  dependencies: const [],
  readyIds: ready,
  capturedAt: DateTime(2026),
);

/// A recording [SourceControl] that captures the bead ids it was asked to
/// provision. Land is deferred (`canLand == false`); the test never reaches it.
class _RecordingSourceControl implements SourceControl {
  /// Every bead id passed to [provisionWorkspace], in call order.
  final List<String> provisioned = [];

  @override
  bool get canLand => false;

  @override
  Future<void> provisionWorkspace({
    required String beadId,
    required String workspaceDir,
  }) async => provisioned.add(beadId);

  @override
  Future<void> commitAll({
    required String workspaceDir,
    required String message,
  }) async {}

  @override
  Future<void> push({
    required String workspaceDir,
    required String remote,
    required String branch,
  }) async {}

  @override
  Future<PrRef?> openPr({
    required String workspaceDir,
    required String branch,
    required String baseBranch,
    required String title,
  }) async => null;
}

void main() {
  test(
    'each substation\'s CapabilityHost resolves ITS OWN ServiceBundle — two '
    'substations get isolated SourceControl (ADR-0008 D5)',
    () async {
      final f = buildFakes();
      final scA = _RecordingSourceControl();
      final scB = _RecordingSourceControl();

      // Adopted sessions (carried on the STATE axis) so each SessionScope
      // resolves synchronously and the agent spawns under the kernel's flush —
      // distinct session ids, no mint race. The session's own rig is the_grid's
      // state partition; the work beads route by id-prefix ownership.
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(
          beads: [
            sessionBead(id: 'tgdog-a', workBeadId: 'sa-1'),
            sessionBead(id: 'tgdog-b', workBeadId: 'sb-1'),
          ],
          ready: const {},
        ),
      );
      final bridge = StationJoinBridge(work: work, state: state);

      final kernel = StationKernel(
        bridge: bridge,
        effectContext: f.ctx,
        resolver: kCodeResolver,
        registry: buildCodeRegistry(),
        substations: [
          SubstationScope(
            configNotifier: SubstationConfigNotifier(
              const SubstationConfig(substationId: 'sa', ownedSubstations: {'sa'}),
            ),
            services: ServiceBundle(sourceControl: scA),
            key: const ValueKey('scope.sa'),
          ),
          SubstationScope(
            configNotifier: SubstationConfigNotifier(
              const SubstationConfig(substationId: 'sb', ownedSubstations: {'sb'}),
            ),
            services: ServiceBundle(sourceControl: scB),
            key: const ValueKey('scope.sb'),
          ),
        ],
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await pumpEventQueue();

      // One ready owned bead per substation (sa-1 → substation sa, sb-1 → sb).
      work.push(
        _graph(beads: [bead('sa-1'), bead('sb-1')], ready: {'sa-1', 'sb-1'}),
      );
      await pumpEventQueue();

      // Sanity (non-vacuous): both agents actually mounted + spawned, so both
      // hosts ran their provision step.
      expect(
        f.provider.started.map((s) => s.name),
        unorderedEquals(<String>['tgdog-a/sa-1/agent', 'tgdog-b/sb-1/agent']),
        reason: 'one agent per substation spawned through the real code formula',
      );

      // The routing proof: each substation provisioned ONLY its own bead's
      // workspace, through its OWN SourceControl. A shared station-wide bundle
      // would have funnelled BOTH beads into one SourceControl.
      expect(scA.provisioned, equals(<String>['sa-1']));
      expect(scB.provisioned, equals(<String>['sb-1']));
      // Explicit isolation: neither substation ever saw the other's bead.
      expect(scA.provisioned, isNot(contains('sb-1')));
      expect(scB.provisioned, isNot(contains('sa-1')));
    },
  );

  test(
    'a substation with no ServiceBundle resolves the empty default — provisioning '
    'no-ops, the agent still spawns (the offline-build posture)',
    () async {
      final f = buildFakes();
      final work = FakeSnapshotSource(_graph(beads: const [], ready: const {}));
      final state = FakeSnapshotSource(
        _graph(
          beads: [sessionBead(id: 'tgdog-a', workBeadId: 'sa-1')],
          ready: const {},
        ),
      );
      final bridge = StationJoinBridge(work: work, state: state);

      final kernel = StationKernel(
        bridge: bridge,
        effectContext: f.ctx,
        resolver: kCodeResolver,
        registry: buildCodeRegistry(),
        substations: [
          SubstationScope(
            configNotifier: SubstationConfigNotifier(
              const SubstationConfig(substationId: 'sa', ownedSubstations: {'sa'}),
            ),
            // No services — the scope provides the empty default (D5: an offline
            // build wires no SourceControl ⇒ provisioning is a no-op).
            key: const ValueKey('scope.sa'),
          ),
        ],
      );
      addTearDown(kernel.dispose);
      addTearDown(f.provider.close);
      addTearDown(work.close);
      addTearDown(state.close);

      kernel.start();
      await pumpEventQueue();
      work.push(_graph(beads: [bead('sa-1')], ready: {'sa-1'}));
      await pumpEventQueue();

      // The agent spawned even with no SourceControl wired (provision no-op).
      expect(f.provider.started.map((s) => s.name), ['tgdog-a/sa-1/agent']);
    },
  );
}
