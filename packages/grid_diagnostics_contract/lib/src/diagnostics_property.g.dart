// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostics_property.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DiagnosticsStringProperty _$DiagnosticsStringPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsStringProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: json['value'] as String,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsStringPropertyToJson(
  DiagnosticsStringProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value,
  'kind': instance.$type,
};

const _$DiagnosticsLevelEnumMap = {
  DiagnosticsLevel.fine: 'fine',
  DiagnosticsLevel.info: 'info',
  DiagnosticsLevel.warning: 'warning',
  DiagnosticsLevel.error: 'error',
};

DiagnosticsIntProperty _$DiagnosticsIntPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsIntProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: (json['value'] as num).toInt(),
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsIntPropertyToJson(
  DiagnosticsIntProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value,
  'kind': instance.$type,
};

DiagnosticsDoubleProperty _$DiagnosticsDoublePropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsDoubleProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: (json['value'] as num).toDouble(),
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsDoublePropertyToJson(
  DiagnosticsDoubleProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value,
  'kind': instance.$type,
};

DiagnosticsFlagProperty _$DiagnosticsFlagPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsFlagProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: json['value'] as bool,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsFlagPropertyToJson(
  DiagnosticsFlagProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value,
  'kind': instance.$type,
};

DiagnosticsEnumProperty _$DiagnosticsEnumPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsEnumProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: json['value'] as String,
  enumType: json['enumType'] as String,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsEnumPropertyToJson(
  DiagnosticsEnumProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value,
  'enumType': instance.enumType,
  'kind': instance.$type,
};

DiagnosticsDurationProperty _$DiagnosticsDurationPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsDurationProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: Duration(microseconds: (json['value'] as num).toInt()),
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsDurationPropertyToJson(
  DiagnosticsDurationProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value.inMicroseconds,
  'kind': instance.$type,
};

DiagnosticsTimestampProperty _$DiagnosticsTimestampPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsTimestampProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  value: DateTime.parse(json['value'] as String),
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsTimestampPropertyToJson(
  DiagnosticsTimestampProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'value': instance.value.toIso8601String(),
  'kind': instance.$type,
};

DiagnosticsReferenceProperty _$DiagnosticsReferencePropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsReferenceProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  referenceKind: $enumDecode(_$ReferenceKindEnumMap, json['referenceKind']),
  value: json['value'] as String,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsReferencePropertyToJson(
  DiagnosticsReferenceProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'referenceKind': _$ReferenceKindEnumMap[instance.referenceKind]!,
  'value': instance.value,
  'kind': instance.$type,
};

const _$ReferenceKindEnumMap = {
  ReferenceKind.bead: 'bead',
  ReferenceKind.session: 'session',
  ReferenceKind.substation: 'substation',
  ReferenceKind.pid: 'pid',
};

DiagnosticsObjectProperty _$DiagnosticsObjectPropertyFromJson(
  Map<String, dynamic> json,
) => DiagnosticsObjectProperty(
  name: json['name'] as String,
  level: $enumDecode(_$DiagnosticsLevelEnumMap, json['level']),
  properties: (json['properties'] as List<dynamic>)
      .map((e) => DiagnosticsProperty.fromJson(e as Map<String, dynamic>))
      .toList(),
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$DiagnosticsObjectPropertyToJson(
  DiagnosticsObjectProperty instance,
) => <String, dynamic>{
  'name': instance.name,
  'level': _$DiagnosticsLevelEnumMap[instance.level]!,
  'properties': instance.properties.map((e) => e.toJson()).toList(),
  'kind': instance.$type,
};
