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
  rewindCount: (json['rewindCount'] as num?)?.toInt() ?? 0,
  reapCount: (json['reapCount'] as num?)?.toInt() ?? 0,
  cooldownUntil: json['cooldownUntil'] == null
      ? null
      : DateTime.parse(json['cooldownUntil'] as String),
  logOffset: (json['logOffset'] as num?)?.toInt(),
  startedAt: json['startedAt'] == null
      ? null
      : DateTime.parse(json['startedAt'] as String),
  finishedAt: json['finishedAt'] == null
      ? null
      : DateTime.parse(json['finishedAt'] as String),
  durationMs: (json['durationMs'] as num?)?.toInt(),
  failureReason: json['failureReason'] as String?,
);

Map<String, dynamic> _$NodeCursorToJson(_NodeCursor instance) =>
    <String, dynamic>{
      'state': _$StepStateEnumMap[instance.state]!,
      'pgid': instance.pgid,
      'pid': instance.pid,
      'token': instance.token,
      'restartCount': instance.restartCount,
      'rewindCount': instance.rewindCount,
      'reapCount': instance.reapCount,
      'cooldownUntil': instance.cooldownUntil?.toIso8601String(),
      'logOffset': instance.logOffset,
      'startedAt': instance.startedAt?.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
      'durationMs': instance.durationMs,
      'failureReason': instance.failureReason,
    };

const _$StepStateEnumMap = {
  StepState.pending: 'pending',
  StepState.running: 'running',
  StepState.ready: 'ready',
  StepState.complete: 'complete',
  StepState.failed: 'failed',
  StepState.gated: 'gated',
};
