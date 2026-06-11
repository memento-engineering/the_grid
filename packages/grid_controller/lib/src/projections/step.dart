import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/bead.dart';
import '../models/bead_status.dart';
import '../models/issue_type.dart';
import 'projection_error.dart';

part 'step.freezed.dart';

/// Typed view over a step bead's `metadata` namespace.
///
/// Steps carry per-step run metadata; unknown keys are preserved in [raw].
@freezed
abstract class StepMetadata with _$StepMetadata {
  const StepMetadata._();

  const factory StepMetadata({
    @Default(<String, dynamic>{}) Map<String, dynamic> raw,
  }) = _StepMetadata;

  factory StepMetadata.fromMetadata(Map<String, dynamic> metadata) =>
      StepMetadata(raw: Map<String, dynamic>.unmodifiable(metadata));

  String? _str(String key) {
    final value = raw[key];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// The id of the molecule this step belongs to, if recorded in metadata
  /// (`metadata.molecule` / `metadata.molecule_id`). Parentage is primarily a
  /// dependency edge; this is a metadata fallback.
  String? get moleculeId => _str('molecule_id') ?? _str('molecule');

  /// Ordinal position within the molecule (`metadata.step_index`), parsed.
  int? get index => int.tryParse(_str('step_index') ?? '');
}

/// A step: one child bead of a molecule's instantiated formula.
///
/// "one root bead plus child step beads; `needs` declares step deps"
/// (ADR-0002 Decision 2). The step's prerequisites ([needs]) are the ids it
/// depends on, resolved from the snapshot's dependency edges by the Molecule
/// projector — a step is *runnable* when every id in [needs] is closed.
@freezed
abstract class Step with _$Step {
  const Step._();

  const factory Step({
    required String id,
    required String title,
    required bool isClosed,
    required StepMetadata metadata,
    required List<String> labels,
    @Default(<String>[]) List<String> needs,
  }) = _Step;

  /// Projects a `step`-typed [bead] into a [Step], or returns a typed
  /// [ProjectionError] on type mismatch. [needs] is supplied by the caller
  /// (the Molecule projector) from the dependency graph; callers projecting a
  /// step in isolation may pass it directly.
  static ProjectionResult<Step> project(
    Bead bead, {
    List<String> needs = const [],
  }) {
    if (bead.issueType != IssueType.step) {
      return ProjectionFailed(
        ProjectionError(
          beadId: bead.id,
          issueType: bead.issueType.wire,
          projection: 'Step',
          reason: 'expected issue_type "step", got "${bead.issueType.wire}"',
        ),
      );
    }
    return ProjectionOk(
      Step(
        id: bead.id,
        title: bead.title,
        isClosed: bead.status == BeadStatus.closed,
        metadata: StepMetadata.fromMetadata(bead.metadata),
        labels: List<String>.unmodifiable(bead.labels),
        needs: List<String>.unmodifiable(needs),
      ),
    );
  }
}
