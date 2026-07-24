// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tree_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TreeSnapshot _$TreeSnapshotFromJson(Map<String, dynamic> json) =>
    _TreeSnapshot(
      contractVersion: (json['contractVersion'] as num).toInt(),
      projectedAt: DateTime.parse(json['projectedAt'] as String),
      root: TreeNode.fromJson(json['root'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TreeSnapshotToJson(_TreeSnapshot instance) =>
    <String, dynamic>{
      'contractVersion': instance.contractVersion,
      'projectedAt': instance.projectedAt.toIso8601String(),
      'root': instance.root.toJson(),
    };

_TreeNode _$TreeNodeFromJson(Map<String, dynamic> json) => _TreeNode(
  seedType: json['seedType'] as String,
  id: json['id'] as String,
  key: json['key'] as String?,
  properties: (json['properties'] as List<dynamic>)
      .map((e) => DiagnosticsProperty.fromJson(e as Map<String, dynamic>))
      .toList(),
  children: (json['children'] as List<dynamic>)
      .map((e) => TreeNode.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$TreeNodeToJson(_TreeNode instance) => <String, dynamic>{
  'seedType': instance.seedType,
  'id': instance.id,
  'key': instance.key,
  'properties': instance.properties.map((e) => e.toJson()).toList(),
  'children': instance.children.map((e) => e.toJson()).toList(),
};
