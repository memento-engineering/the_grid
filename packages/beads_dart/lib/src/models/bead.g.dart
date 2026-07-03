// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bead.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Bead _$BeadFromJson(Map<String, dynamic> json) => _Bead(
  id: json['id'] as String,
  title: json['title'] as String? ?? '',
  description: json['description'] as String? ?? '',
  design: json['design'] as String? ?? '',
  acceptanceCriteria: json['acceptance_criteria'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
  specId: json['spec_id'] as String? ?? '',
  status: json['status'] == null
      ? BeadStatus.open
      : const BeadStatusConverter().fromJson(json['status'] as String),
  priority: (json['priority'] as num?)?.toInt() ?? 0,
  issueType: json['issue_type'] == null
      ? IssueType.task
      : const IssueTypeConverter().fromJson(json['issue_type'] as String),
  assignee: json['assignee'] as String? ?? '',
  owner: json['owner'] as String? ?? '',
  estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String? ?? '',
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
  startedAt: json['started_at'] == null
      ? null
      : DateTime.parse(json['started_at'] as String),
  closedAt: json['closed_at'] == null
      ? null
      : DateTime.parse(json['closed_at'] as String),
  closeReason: json['close_reason'] as String? ?? '',
  closedBySession: json['closed_by_session'] as String? ?? '',
  dueAt: json['due_at'] == null
      ? null
      : DateTime.parse(json['due_at'] as String),
  deferUntil: json['defer_until'] == null
      ? null
      : DateTime.parse(json['defer_until'] as String),
  externalRef: json['external_ref'] as String?,
  sourceSystem: json['source_system'] as String? ?? '',
  metadata:
      json['metadata'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  labels: json['labels'] == null
      ? const <String>[]
      : const SortedLabelsConverter().fromJson(json['labels'] as List),
  ephemeral: json['ephemeral'] as bool? ?? false,
  dependencyCount: (json['dependency_count'] as num?)?.toInt() ?? 0,
  dependentCount: (json['dependent_count'] as num?)?.toInt() ?? 0,
  commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
  comments:
      (json['comments'] as List<dynamic>?)
          ?.map((e) => BeadComment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <BeadComment>[],
);

Map<String, dynamic> _$BeadToJson(_Bead instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'description': instance.description,
  'design': instance.design,
  'acceptance_criteria': instance.acceptanceCriteria,
  'notes': instance.notes,
  'spec_id': instance.specId,
  'status': const BeadStatusConverter().toJson(instance.status),
  'priority': instance.priority,
  'issue_type': const IssueTypeConverter().toJson(instance.issueType),
  'assignee': instance.assignee,
  'owner': instance.owner,
  'estimated_minutes': instance.estimatedMinutes,
  'created_at': instance.createdAt?.toIso8601String(),
  'created_by': instance.createdBy,
  'updated_at': instance.updatedAt?.toIso8601String(),
  'started_at': instance.startedAt?.toIso8601String(),
  'closed_at': instance.closedAt?.toIso8601String(),
  'close_reason': instance.closeReason,
  'closed_by_session': instance.closedBySession,
  'due_at': instance.dueAt?.toIso8601String(),
  'defer_until': instance.deferUntil?.toIso8601String(),
  'external_ref': instance.externalRef,
  'source_system': instance.sourceSystem,
  'metadata': instance.metadata,
  'labels': const SortedLabelsConverter().toJson(instance.labels),
  'ephemeral': instance.ephemeral,
  'dependency_count': instance.dependencyCount,
  'dependent_count': instance.dependentCount,
  'comment_count': instance.commentCount,
};
