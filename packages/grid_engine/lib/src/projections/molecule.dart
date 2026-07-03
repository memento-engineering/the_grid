import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:beads_dart/beads_dart.dart';

part 'molecule.freezed.dart';

/// Typed view over a molecule bead's `metadata` namespace.
///
/// gc writes routing metadata (`gc.routed_to`, `gc.run_target`) plus, for
/// ephemeral molecules, a `wisp_type`/TTL. Unknown keys preserved in [raw].
@freezed
abstract class MoleculeMetadata with _$MoleculeMetadata {
  const MoleculeMetadata._();

  const factory MoleculeMetadata({
    @Default(<String, dynamic>{}) Map<String, dynamic> raw,
  }) = _MoleculeMetadata;

  factory MoleculeMetadata.fromMetadata(Map<String, dynamic> metadata) =>
      MoleculeMetadata(raw: Map<String, dynamic>.unmodifiable(metadata));

  String? _str(String key) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// What the molecule was routed to (`metadata.gc.routed_to`).
  String? get routedTo => _str('gc.routed_to');

  /// The run target (`metadata.gc.run_target`).
  String? get runTarget => _str('gc.run_target');

  /// The wisp type when this is an ephemeral molecule (`metadata.wisp_type`).
  String? get wispType => _str('wisp_type');
}

/// A molecule: "a formula instantiated at runtime — one root bead plus child
/// step beads" (ADR-0002 Decision 2).
///
/// A **wisp** is an ephemeral (TTL'd) molecule — flagged by the bead's
/// `ephemeral` column or a `wisp_type` in metadata. Child [steps] are resolved
/// from the dependency graph (parent-child edges to the molecule); each step's
/// `needs` are its blocking prerequisites.
@freezed
abstract class Molecule with _$Molecule {
  const Molecule._();

  const factory Molecule({
    required String id,
    required String title,
    required bool isClosed,
    required bool isWisp,
    required MoleculeMetadata metadata,
    required List<String> labels,
    @Default(<Step>[]) List<Step> steps,
    DateTime? closedAt,
    @Default('') String closeReason,
  }) = _Molecule;

  /// Projects a `molecule`-typed [bead] into a [Molecule].
  ///
  /// [dependencies] are the snapshot's edges (the projector filters for the
  /// ones touching this molecule and its steps); [beadsById] resolves child
  /// step beads. Both default to empty so a molecule with no captured steps
  /// (the pinned fixture) still projects. Returns a typed [ProjectionError] on
  /// type mismatch; a child bead that fails to project as a [Step] is omitted
  /// from [steps] (M1 has no step fixture to pin the failure path — see
  /// ADR-0000 A13).
  static ProjectionResult<Molecule> project(
    Bead bead, {
    Iterable<BeadDependency> dependencies = const [],
    Map<String, Bead> beadsById = const {},
  }) {
    if (bead.issueType != IssueType.molecule) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'Molecule',
          reason:
              'expected issue_type "molecule", got "${bead.issueType.wire}"',
        ),
      );
    }

    final deps = dependencies.toList(growable: false);

    // Child steps: a step bead joined to this molecule by a parent-child edge.
    // Upstream models parent-child as `issue_id depends_on depends_on_id`, the
    // child being the dependent; the molecule may sit on either end depending
    // on capture, so accept an edge where one side is this molecule and the
    // other is a `step` bead.
    final stepIds = <String>{};
    for (final dep in deps) {
      if (dep.type != DependencyType.parentChild) continue;
      final other = dep.issueId == bead.id
          ? dep.dependsOnId
          : dep.dependsOnId == bead.id
          ? dep.issueId
          : null;
      if (other == null) continue;
      if (beadsById[other]?.issueType == IssueType.step) stepIds.add(other);
    }

    // Each step's `needs`: the ids it blocks-on, restricted to sibling steps.
    final steps = <Step>[];
    for (final stepId in stepIds) {
      final stepBead = beadsById[stepId];
      if (stepBead == null) continue;
      final needs = <String>[
        for (final dep in deps)
          if (dep.issueId == stepId &&
              dep.type.isBlockingEdge &&
              stepIds.contains(dep.dependsOnId))
            dep.dependsOnId,
      ];
      final result = Step.project(stepBead, needs: needs);
      if (result case ProjectionOk<Step>(:final value)) steps.add(value);
    }
    steps.sort((a, b) => a.id.compareTo(b.id));

    final metadata = MoleculeMetadata.fromMetadata(bead.metadata);
    return ProjectionOk(
      Molecule(
        id: bead.id,
        title: bead.title,
        isClosed: bead.status == BeadStatus.closed,
        isWisp: bead.ephemeral || metadata.wispType != null,
        metadata: metadata,
        labels: List<String>.unmodifiable(bead.labels),
        steps: List<Step>.unmodifiable(steps),
        closedAt: bead.closedAt,
        closeReason: bead.closeReason,
      ),
    );
  }

  int get stepCount => steps.length;
  int get closedStepCount => steps.where((s) => s.isClosed).length;

  /// closed / total, as a fraction in [0,1]; 1.0 when there are no steps.
  double get progress => steps.isEmpty ? 1 : closedStepCount / stepCount;

  /// Steps whose every prerequisite (`needs`) is closed and which are not yet
  /// closed themselves — the molecule's runnable frontier.
  List<Step> get runnableSteps {
    final closedIds = {
      for (final step in steps)
        if (step.isClosed) step.id,
    };
    return [
      for (final step in steps)
        if (!step.isClosed && step.needs.every(closedIds.contains)) step,
    ];
  }
}
