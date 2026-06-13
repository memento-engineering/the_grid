import 'package:grid_controller/grid_controller.dart';

final fakeClock = DateTime.utc(2026, 6, 12, 12);

/// Builds a snapshot from beads + optional deps (repo fake convention —
/// grid_controller test/support/reactivity_fakes.dart).
GraphSnapshot snap(List<Bead> beads, {List<BeadDependency> deps = const []}) =>
    GraphSnapshot.fromParts(
      beads: beads,
      dependencies: deps,
      readyIds: const {},
      capturedAt: fakeClock,
    );

/// A `convergence`-typed root bead.
Bead convergenceBead(
  String id, {
  String title = 'Convergence: vapor',
  BeadStatus status = BeadStatus.inProgress,
  Map<String, dynamic> metadata = const {},
}) => Bead(
  id: id,
  title: title,
  issueType: IssueType.convergence,
  status: status,
  metadata: metadata,
);

/// A wisp root bead (an ephemeral molecule carrying an idempotency key,
/// per ADR-0000 A15).
Bead wispBead(
  String id, {
  required String key,
  BeadStatus status = BeadStatus.open,
  DateTime? createdAt,
  DateTime? closedAt,
  Map<String, dynamic> extraMetadata = const {},
}) => Bead(
  id: id,
  title: 'wisp $id',
  issueType: IssueType.molecule,
  ephemeral: true,
  status: status,
  createdAt: createdAt,
  closedAt: closedAt,
  metadata: {'idempotency_key': key, ...extraMetadata},
);

/// A parent-child edge in gc's direction: child = issue_id, parent =
/// depends_on_id (beads/internal/storage/issueops/blocked.go:60-63).
BeadDependency parentChild(String childId, String parentId) => BeadDependency(
  issueId: childId,
  dependsOnId: parentId,
  type: DependencyType.parentChild,
);
