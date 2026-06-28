// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'formula.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Backoff _$BackoffFromJson(Map<String, dynamic> json) => _Backoff(
  min: Duration(microseconds: (json['min'] as num).toInt()),
  max: Duration(microseconds: (json['max'] as num).toInt()),
  factor: (json['factor'] as num?)?.toDouble() ?? 2.0,
);

Map<String, dynamic> _$BackoffToJson(_Backoff instance) => <String, dynamic>{
  'min': instance.min.inMicroseconds,
  'max': instance.max.inMicroseconds,
  'factor': instance.factor,
};

_ResourceRequest _$ResourceRequestFromJson(Map<String, dynamic> json) =>
    _ResourceRequest(
      builds: (json['builds'] as num?)?.toInt() ?? 0,
      processes: (json['processes'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ResourceRequestToJson(_ResourceRequest instance) =>
    <String, dynamic>{
      'builds': instance.builds,
      'processes': instance.processes,
    };

CapabilityStep _$CapabilityStepFromJson(
  Map<String, dynamic> json,
) => CapabilityStep(
  stepId: json['stepId'] as String,
  capabilityId: json['capabilityId'] as String,
  params:
      (json['params'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const <String, String>{},
  dependsOn:
      (json['dependsOn'] as List<dynamic>?)?.map((e) => e as String).toSet() ??
      const <String>{},
  kind: $enumDecodeNullable(_$StepKindEnumMap, json['kind']) ?? StepKind.job,
  resources: json['resources'] == null
      ? null
      : ResourceRequest.fromJson(json['resources'] as Map<String, dynamic>),
  $type: json['type'] as String?,
);

Map<String, dynamic> _$CapabilityStepToJson(CapabilityStep instance) =>
    <String, dynamic>{
      'stepId': instance.stepId,
      'capabilityId': instance.capabilityId,
      'params': instance.params,
      'dependsOn': instance.dependsOn.toList(),
      'kind': _$StepKindEnumMap[instance.kind]!,
      'resources': instance.resources,
      'type': instance.$type,
    };

const _$StepKindEnumMap = {StepKind.job: 'job', StepKind.daemon: 'daemon'};

SubFormulaStep _$SubFormulaStepFromJson(Map<String, dynamic> json) =>
    SubFormulaStep(
      stepId: json['stepId'] as String,
      formulaId: json['formulaId'] as String,
      params:
          (json['params'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
      dependsOn:
          (json['dependsOn'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toSet() ??
          const <String>{},
      $type: json['type'] as String?,
    );

Map<String, dynamic> _$SubFormulaStepToJson(SubFormulaStep instance) =>
    <String, dynamic>{
      'stepId': instance.stepId,
      'formulaId': instance.formulaId,
      'params': instance.params,
      'dependsOn': instance.dependsOn.toList(),
      'type': instance.$type,
    };

_Formula _$FormulaFromJson(Map<String, dynamic> json) => _Formula(
  id: json['id'] as String,
  steps: (json['steps'] as List<dynamic>)
      .map((e) => FormulaStep.fromJson(e as Map<String, dynamic>))
      .toList(),
  terminalStepId: json['terminalStepId'] as String,
  supervision:
      $enumDecodeNullable(_$SupervisionStrategyEnumMap, json['supervision']) ??
      SupervisionStrategy.oneForOne,
  backoff: json['backoff'] == null
      ? Backoff.standard
      : Backoff.fromJson(json['backoff'] as Map<String, dynamic>),
  maxRestarts: (json['maxRestarts'] as num?)?.toInt() ?? 3,
  peak: json['peak'] == null
      ? null
      : ResourceRequest.fromJson(json['peak'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FormulaToJson(_Formula instance) => <String, dynamic>{
  'id': instance.id,
  'steps': instance.steps,
  'terminalStepId': instance.terminalStepId,
  'supervision': _$SupervisionStrategyEnumMap[instance.supervision]!,
  'backoff': instance.backoff,
  'maxRestarts': instance.maxRestarts,
  'peak': instance.peak,
};

const _$SupervisionStrategyEnumMap = {
  SupervisionStrategy.oneForOne: 'oneForOne',
  SupervisionStrategy.restForOne: 'restForOne',
  SupervisionStrategy.oneForAll: 'oneForAll',
};
