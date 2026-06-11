// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bead_dependency.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BeadDependency _$BeadDependencyFromJson(Map<String, dynamic> json) =>
    _BeadDependency(
      issueId: json['issue_id'] as String,
      dependsOnId: json['depends_on_id'] as String,
      type: json['type'] == null
          ? DependencyType.blocks
          : const DependencyTypeConverter().fromJson(json['type'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String? ?? '',
      metadata: json['metadata'] as String? ?? '',
      threadId: json['thread_id'] as String? ?? '',
    );

Map<String, dynamic> _$BeadDependencyToJson(_BeadDependency instance) =>
    <String, dynamic>{
      'issue_id': instance.issueId,
      'depends_on_id': instance.dependsOnId,
      'type': const DependencyTypeConverter().toJson(instance.type),
      'created_at': instance.createdAt?.toIso8601String(),
      'created_by': instance.createdBy,
      'metadata': instance.metadata,
      'thread_id': instance.threadId,
    };
