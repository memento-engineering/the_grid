import 'package:freezed_annotation/freezed_annotation.dart';

import 'bead_comment.dart';
import 'bead_status.dart';
import 'converters.dart';
import 'issue_type.dart';

part 'bead.freezed.dart';
part 'bead.g.dart';

/// An immutable bead (beads `Issue`), the unit of the work graph.
///
/// Field-by-field value equality (freezed-generated, deep on collections) is
/// the diff primitive: two snapshots are reconciled by comparing [Bead]s, so
/// every field the read path fetches must live here or a change to it would be
/// invisible (PDR risk: "diff misses a change class").
///
/// [comments] defaults to empty and is excluded from the structural diff —
/// snapshot composition never fetches it (SQL-vs-CLI equivalence depends on
/// both paths omitting it); [commentCount] carries the change signal instead.
@freezed
abstract class Bead with _$Bead {
  const Bead._();

  const factory Bead({
    required String id,
    @Default('') String title,
    @Default('') String description,
    @Default('') String design,
    @JsonKey(name: 'acceptance_criteria')
    @Default('')
    String acceptanceCriteria,
    @Default('') String notes,
    @JsonKey(name: 'spec_id') @Default('') String specId,
    @BeadStatusConverter() @Default(BeadStatus.open) BeadStatus status,
    @Default(0) int priority,
    @JsonKey(name: 'issue_type')
    @IssueTypeConverter()
    @Default(IssueType.task)
    IssueType issueType,
    @Default('') String assignee,
    @Default('') String owner,
    @JsonKey(name: 'estimated_minutes') int? estimatedMinutes,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'created_by') @Default('') String createdBy,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'closed_at') DateTime? closedAt,
    @JsonKey(name: 'close_reason') @Default('') String closeReason,
    @JsonKey(name: 'closed_by_session') @Default('') String closedBySession,
    @JsonKey(name: 'due_at') DateTime? dueAt,
    @JsonKey(name: 'defer_until') DateTime? deferUntil,
    @JsonKey(name: 'external_ref') String? externalRef,
    @JsonKey(name: 'source_system') @Default('') String sourceSystem,
    @Default(<String, dynamic>{}) Map<String, dynamic> metadata,
    @SortedLabelsConverter() @Default(<String>[]) List<String> labels,
    @Default(false) bool ephemeral,
    @JsonKey(name: 'dependency_count') @Default(0) int dependencyCount,
    @JsonKey(name: 'dependent_count') @Default(0) int dependentCount,
    @JsonKey(name: 'comment_count') @Default(0) int commentCount,
    @JsonKey(includeToJson: false)
    @Default(<BeadComment>[])
    List<BeadComment> comments,
  }) = _Bead;

  factory Bead.fromJson(Map<String, dynamic> json) => _$BeadFromJson(json);

  /// True when this bead is in the terminal `closed` status.
  bool get isClosed => status.isClosed;
}
