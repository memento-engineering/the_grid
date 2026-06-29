// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cursor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NodeCursor _$NodeCursorFromJson(Map<String, dynamic> json) => _NodeCursor(
  state:
      $enumDecodeNullable(_$StepStateEnumMap, json['state']) ??
      StepState.pending,
  pgid: (json['pgid'] as num?)?.toInt(),
  pid: (json['pid'] as num?)?.toInt(),
  token: json['token'] as String?,
  restartCount: (json['restartCount'] as num?)?.toInt() ?? 0,
  cooldownUntil: json['cooldownUntil'] == null
      ? null
      : DateTime.parse(json['cooldownUntil'] as String),
  logOffset: (json['logOffset'] as num?)?.toInt(),
);

Map<String, dynamic> _$NodeCursorToJson(_NodeCursor instance) =>
    <String, dynamic>{
      'state': _$StepStateEnumMap[instance.state]!,
      'pgid': instance.pgid,
      'pid': instance.pid,
      'token': instance.token,
      'restartCount': instance.restartCount,
      'cooldownUntil': instance.cooldownUntil?.toIso8601String(),
      'logOffset': instance.logOffset,
    };

const _$StepStateEnumMap = {
  StepState.pending: 'pending',
  StepState.running: 'running',
  StepState.ready: 'ready',
  StepState.complete: 'complete',
  StepState.failed: 'failed',
  StepState.gated: 'gated',
};
