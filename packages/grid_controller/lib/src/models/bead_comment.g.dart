// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bead_comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BeadComment _$BeadCommentFromJson(Map<String, dynamic> json) => _BeadComment(
  id: json['id'] as String,
  issueId: json['issue_id'] as String? ?? '',
  author: json['author'] as String? ?? '',
  text: json['text'] as String? ?? '',
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
);

Map<String, dynamic> _$BeadCommentToJson(_BeadComment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'issue_id': instance.issueId,
      'author': instance.author,
      'text': instance.text,
      'created_at': instance.createdAt?.toIso8601String(),
    };
