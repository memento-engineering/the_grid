// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bead_round.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BeadRoundFound _$BeadRoundFoundFromJson(Map<String, dynamic> json) =>
    BeadRoundFound(
      beadId: json['bead_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      sessionId: json['session_id'] as String,
      round: (json['round'] as num).toInt(),
      validationPlan: json['validation_plan'] as String?,
      $type: json['kind'] as String?,
    );

Map<String, dynamic> _$BeadRoundFoundToJson(BeadRoundFound instance) =>
    <String, dynamic>{
      'bead_id': instance.beadId,
      'title': instance.title,
      'status': instance.status,
      'session_id': instance.sessionId,
      'round': instance.round,
      'validation_plan': instance.validationPlan,
      'kind': instance.$type,
    };

BeadRoundAbsent _$BeadRoundAbsentFromJson(Map<String, dynamic> json) =>
    BeadRoundAbsent(
      beadId: json['bead_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      reason: json['reason'] as String,
      validationPlan: json['validation_plan'] as String?,
      $type: json['kind'] as String?,
    );

Map<String, dynamic> _$BeadRoundAbsentToJson(BeadRoundAbsent instance) =>
    <String, dynamic>{
      'bead_id': instance.beadId,
      'title': instance.title,
      'status': instance.status,
      'reason': instance.reason,
      'validation_plan': instance.validationPlan,
      'kind': instance.$type,
    };
