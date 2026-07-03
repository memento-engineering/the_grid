import 'package:freezed_annotation/freezed_annotation.dart';

import 'converters.dart';
import 'dependency_type.dart';

part 'bead_dependency.freezed.dart';
part 'bead_dependency.g.dart';

/// A directed dependency edge: [issueId] depends on [dependsOnId] via [type].
///
/// Upstream's primary key is the triple (issue_id, depends_on_id, type), so
/// [edgeKey] identifies an edge for diffing.
@freezed
abstract class BeadDependency with _$BeadDependency {
  const BeadDependency._();

  const factory BeadDependency({
    @JsonKey(name: 'issue_id') required String issueId,
    @JsonKey(name: 'depends_on_id') required String dependsOnId,
    @DependencyTypeConverter()
    @Default(DependencyType.blocks)
    DependencyType type,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'created_by') @Default('') String createdBy,
    @Default('') String metadata,
    @JsonKey(name: 'thread_id') @Default('') String threadId,
  }) = _BeadDependency;

  factory BeadDependency.fromJson(Map<String, dynamic> json) =>
      _$BeadDependencyFromJson(json);

  /// Stable identity for diffing: the upstream primary-key triple.
  String get edgeKey => '$issueId $dependsOnId ${type.wire}';
}
