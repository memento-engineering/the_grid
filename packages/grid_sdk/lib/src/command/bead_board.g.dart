// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bead_board.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BoardBeadRow _$BoardBeadRowFromJson(Map<String, dynamic> json) => BoardBeadRow(
  id: json['id'] as String,
  store: json['store'] as String,
  root: json['root'] as String,
  type: json['type'] as String,
  status: json['status'] as String,
  title: json['title'] as String,
  ready: json['ready'] as bool? ?? false,
  blockedBy:
      (json['blocked_by'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  approvedBy: json['approved_by'] as String?,
  approvedAt: json['approved_at'] as String?,
  approvedRev: json['approved_rev'] as String?,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$BoardBeadRowToJson(BoardBeadRow instance) =>
    <String, dynamic>{
      'id': instance.id,
      'store': instance.store,
      'root': instance.root,
      'type': instance.type,
      'status': instance.status,
      'title': instance.title,
      'ready': instance.ready,
      'blocked_by': instance.blockedBy,
      'approved_by': instance.approvedBy,
      'approved_at': instance.approvedAt,
      'approved_rev': instance.approvedRev,
      'kind': instance.$type,
    };

BoardStoreUnreadableRow _$BoardStoreUnreadableRowFromJson(
  Map<String, dynamic> json,
) => BoardStoreUnreadableRow(
  store: json['store'] as String,
  root: json['root'] as String,
  reason: json['reason'] as String,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$BoardStoreUnreadableRowToJson(
  BoardStoreUnreadableRow instance,
) => <String, dynamic>{
  'store': instance.store,
  'root': instance.root,
  'reason': instance.reason,
  'kind': instance.$type,
};
