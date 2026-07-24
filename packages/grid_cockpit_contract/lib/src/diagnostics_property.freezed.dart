// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'diagnostics_property.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
DiagnosticsProperty _$DiagnosticsPropertyFromJson(
  Map<String, dynamic> json
) {
        switch (json['kind']) {
                  case 'string':
          return DiagnosticsStringProperty.fromJson(
            json
          );
                case 'int':
          return DiagnosticsIntProperty.fromJson(
            json
          );
                case 'double':
          return DiagnosticsDoubleProperty.fromJson(
            json
          );
                case 'flag':
          return DiagnosticsFlagProperty.fromJson(
            json
          );
                case 'enumValue':
          return DiagnosticsEnumProperty.fromJson(
            json
          );
                case 'duration':
          return DiagnosticsDurationProperty.fromJson(
            json
          );
                case 'timestamp':
          return DiagnosticsTimestampProperty.fromJson(
            json
          );
                case 'reference':
          return DiagnosticsReferenceProperty.fromJson(
            json
          );
                case 'object':
          return DiagnosticsObjectProperty.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'kind',
  'DiagnosticsProperty',
  'Invalid union type "${json['kind']}"!'
);
        }
      
}

/// @nodoc
mixin _$DiagnosticsProperty {

 String get name; DiagnosticsLevel get level;
/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsPropertyCopyWith<DiagnosticsProperty> get copyWith => _$DiagnosticsPropertyCopyWithImpl<DiagnosticsProperty>(this as DiagnosticsProperty, _$identity);

  /// Serializes this DiagnosticsProperty to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level);

@override
String toString() {
  return 'DiagnosticsProperty(name: $name, level: $level)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsPropertyCopyWith<$Res>  {
  factory $DiagnosticsPropertyCopyWith(DiagnosticsProperty value, $Res Function(DiagnosticsProperty) _then) = _$DiagnosticsPropertyCopyWithImpl;
@useResult
$Res call({
 String name, DiagnosticsLevel level
});




}
/// @nodoc
class _$DiagnosticsPropertyCopyWithImpl<$Res>
    implements $DiagnosticsPropertyCopyWith<$Res> {
  _$DiagnosticsPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsProperty _self;
  final $Res Function(DiagnosticsProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? level = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,
  ));
}

}


/// Adds pattern-matching-related methods to [DiagnosticsProperty].
extension DiagnosticsPropertyPatterns on DiagnosticsProperty {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DiagnosticsStringProperty value)?  string,TResult Function( DiagnosticsIntProperty value)?  int,TResult Function( DiagnosticsDoubleProperty value)?  double,TResult Function( DiagnosticsFlagProperty value)?  flag,TResult Function( DiagnosticsEnumProperty value)?  enumValue,TResult Function( DiagnosticsDurationProperty value)?  duration,TResult Function( DiagnosticsTimestampProperty value)?  timestamp,TResult Function( DiagnosticsReferenceProperty value)?  reference,TResult Function( DiagnosticsObjectProperty value)?  object,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DiagnosticsStringProperty() when string != null:
return string(_that);case DiagnosticsIntProperty() when int != null:
return int(_that);case DiagnosticsDoubleProperty() when double != null:
return double(_that);case DiagnosticsFlagProperty() when flag != null:
return flag(_that);case DiagnosticsEnumProperty() when enumValue != null:
return enumValue(_that);case DiagnosticsDurationProperty() when duration != null:
return duration(_that);case DiagnosticsTimestampProperty() when timestamp != null:
return timestamp(_that);case DiagnosticsReferenceProperty() when reference != null:
return reference(_that);case DiagnosticsObjectProperty() when object != null:
return object(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DiagnosticsStringProperty value)  string,required TResult Function( DiagnosticsIntProperty value)  int,required TResult Function( DiagnosticsDoubleProperty value)  double,required TResult Function( DiagnosticsFlagProperty value)  flag,required TResult Function( DiagnosticsEnumProperty value)  enumValue,required TResult Function( DiagnosticsDurationProperty value)  duration,required TResult Function( DiagnosticsTimestampProperty value)  timestamp,required TResult Function( DiagnosticsReferenceProperty value)  reference,required TResult Function( DiagnosticsObjectProperty value)  object,}){
final _that = this;
switch (_that) {
case DiagnosticsStringProperty():
return string(_that);case DiagnosticsIntProperty():
return int(_that);case DiagnosticsDoubleProperty():
return double(_that);case DiagnosticsFlagProperty():
return flag(_that);case DiagnosticsEnumProperty():
return enumValue(_that);case DiagnosticsDurationProperty():
return duration(_that);case DiagnosticsTimestampProperty():
return timestamp(_that);case DiagnosticsReferenceProperty():
return reference(_that);case DiagnosticsObjectProperty():
return object(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DiagnosticsStringProperty value)?  string,TResult? Function( DiagnosticsIntProperty value)?  int,TResult? Function( DiagnosticsDoubleProperty value)?  double,TResult? Function( DiagnosticsFlagProperty value)?  flag,TResult? Function( DiagnosticsEnumProperty value)?  enumValue,TResult? Function( DiagnosticsDurationProperty value)?  duration,TResult? Function( DiagnosticsTimestampProperty value)?  timestamp,TResult? Function( DiagnosticsReferenceProperty value)?  reference,TResult? Function( DiagnosticsObjectProperty value)?  object,}){
final _that = this;
switch (_that) {
case DiagnosticsStringProperty() when string != null:
return string(_that);case DiagnosticsIntProperty() when int != null:
return int(_that);case DiagnosticsDoubleProperty() when double != null:
return double(_that);case DiagnosticsFlagProperty() when flag != null:
return flag(_that);case DiagnosticsEnumProperty() when enumValue != null:
return enumValue(_that);case DiagnosticsDurationProperty() when duration != null:
return duration(_that);case DiagnosticsTimestampProperty() when timestamp != null:
return timestamp(_that);case DiagnosticsReferenceProperty() when reference != null:
return reference(_that);case DiagnosticsObjectProperty() when object != null:
return object(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String name,  DiagnosticsLevel level,  String value)?  string,TResult Function( String name,  DiagnosticsLevel level,  int value)?  int,TResult Function( String name,  DiagnosticsLevel level,  double value)?  double,TResult Function( String name,  DiagnosticsLevel level,  bool value)?  flag,TResult Function( String name,  DiagnosticsLevel level,  String value,  String enumType)?  enumValue,TResult Function( String name,  DiagnosticsLevel level,  Duration value)?  duration,TResult Function( String name,  DiagnosticsLevel level,  DateTime value)?  timestamp,TResult Function( String name,  DiagnosticsLevel level,  ReferenceKind referenceKind,  String value)?  reference,TResult Function( String name,  DiagnosticsLevel level,  List<DiagnosticsProperty> properties)?  object,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DiagnosticsStringProperty() when string != null:
return string(_that.name,_that.level,_that.value);case DiagnosticsIntProperty() when int != null:
return int(_that.name,_that.level,_that.value);case DiagnosticsDoubleProperty() when double != null:
return double(_that.name,_that.level,_that.value);case DiagnosticsFlagProperty() when flag != null:
return flag(_that.name,_that.level,_that.value);case DiagnosticsEnumProperty() when enumValue != null:
return enumValue(_that.name,_that.level,_that.value,_that.enumType);case DiagnosticsDurationProperty() when duration != null:
return duration(_that.name,_that.level,_that.value);case DiagnosticsTimestampProperty() when timestamp != null:
return timestamp(_that.name,_that.level,_that.value);case DiagnosticsReferenceProperty() when reference != null:
return reference(_that.name,_that.level,_that.referenceKind,_that.value);case DiagnosticsObjectProperty() when object != null:
return object(_that.name,_that.level,_that.properties);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String name,  DiagnosticsLevel level,  String value)  string,required TResult Function( String name,  DiagnosticsLevel level,  int value)  int,required TResult Function( String name,  DiagnosticsLevel level,  double value)  double,required TResult Function( String name,  DiagnosticsLevel level,  bool value)  flag,required TResult Function( String name,  DiagnosticsLevel level,  String value,  String enumType)  enumValue,required TResult Function( String name,  DiagnosticsLevel level,  Duration value)  duration,required TResult Function( String name,  DiagnosticsLevel level,  DateTime value)  timestamp,required TResult Function( String name,  DiagnosticsLevel level,  ReferenceKind referenceKind,  String value)  reference,required TResult Function( String name,  DiagnosticsLevel level,  List<DiagnosticsProperty> properties)  object,}) {final _that = this;
switch (_that) {
case DiagnosticsStringProperty():
return string(_that.name,_that.level,_that.value);case DiagnosticsIntProperty():
return int(_that.name,_that.level,_that.value);case DiagnosticsDoubleProperty():
return double(_that.name,_that.level,_that.value);case DiagnosticsFlagProperty():
return flag(_that.name,_that.level,_that.value);case DiagnosticsEnumProperty():
return enumValue(_that.name,_that.level,_that.value,_that.enumType);case DiagnosticsDurationProperty():
return duration(_that.name,_that.level,_that.value);case DiagnosticsTimestampProperty():
return timestamp(_that.name,_that.level,_that.value);case DiagnosticsReferenceProperty():
return reference(_that.name,_that.level,_that.referenceKind,_that.value);case DiagnosticsObjectProperty():
return object(_that.name,_that.level,_that.properties);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String name,  DiagnosticsLevel level,  String value)?  string,TResult? Function( String name,  DiagnosticsLevel level,  int value)?  int,TResult? Function( String name,  DiagnosticsLevel level,  double value)?  double,TResult? Function( String name,  DiagnosticsLevel level,  bool value)?  flag,TResult? Function( String name,  DiagnosticsLevel level,  String value,  String enumType)?  enumValue,TResult? Function( String name,  DiagnosticsLevel level,  Duration value)?  duration,TResult? Function( String name,  DiagnosticsLevel level,  DateTime value)?  timestamp,TResult? Function( String name,  DiagnosticsLevel level,  ReferenceKind referenceKind,  String value)?  reference,TResult? Function( String name,  DiagnosticsLevel level,  List<DiagnosticsProperty> properties)?  object,}) {final _that = this;
switch (_that) {
case DiagnosticsStringProperty() when string != null:
return string(_that.name,_that.level,_that.value);case DiagnosticsIntProperty() when int != null:
return int(_that.name,_that.level,_that.value);case DiagnosticsDoubleProperty() when double != null:
return double(_that.name,_that.level,_that.value);case DiagnosticsFlagProperty() when flag != null:
return flag(_that.name,_that.level,_that.value);case DiagnosticsEnumProperty() when enumValue != null:
return enumValue(_that.name,_that.level,_that.value,_that.enumType);case DiagnosticsDurationProperty() when duration != null:
return duration(_that.name,_that.level,_that.value);case DiagnosticsTimestampProperty() when timestamp != null:
return timestamp(_that.name,_that.level,_that.value);case DiagnosticsReferenceProperty() when reference != null:
return reference(_that.name,_that.level,_that.referenceKind,_that.value);case DiagnosticsObjectProperty() when object != null:
return object(_that.name,_that.level,_that.properties);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class DiagnosticsStringProperty implements DiagnosticsProperty {
  const DiagnosticsStringProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'string';
  factory DiagnosticsStringProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsStringPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  String value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsStringPropertyCopyWith<DiagnosticsStringProperty> get copyWith => _$DiagnosticsStringPropertyCopyWithImpl<DiagnosticsStringProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsStringPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsStringProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.string(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsStringPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsStringPropertyCopyWith(DiagnosticsStringProperty value, $Res Function(DiagnosticsStringProperty) _then) = _$DiagnosticsStringPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, String value
});




}
/// @nodoc
class _$DiagnosticsStringPropertyCopyWithImpl<$Res>
    implements $DiagnosticsStringPropertyCopyWith<$Res> {
  _$DiagnosticsStringPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsStringProperty _self;
  final $Res Function(DiagnosticsStringProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsStringProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsIntProperty implements DiagnosticsProperty {
  const DiagnosticsIntProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'int';
  factory DiagnosticsIntProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsIntPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  int value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsIntPropertyCopyWith<DiagnosticsIntProperty> get copyWith => _$DiagnosticsIntPropertyCopyWithImpl<DiagnosticsIntProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsIntPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsIntProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.int(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsIntPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsIntPropertyCopyWith(DiagnosticsIntProperty value, $Res Function(DiagnosticsIntProperty) _then) = _$DiagnosticsIntPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, int value
});




}
/// @nodoc
class _$DiagnosticsIntPropertyCopyWithImpl<$Res>
    implements $DiagnosticsIntPropertyCopyWith<$Res> {
  _$DiagnosticsIntPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsIntProperty _self;
  final $Res Function(DiagnosticsIntProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsIntProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsDoubleProperty implements DiagnosticsProperty {
  const DiagnosticsDoubleProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'double';
  factory DiagnosticsDoubleProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsDoublePropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  double value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsDoublePropertyCopyWith<DiagnosticsDoubleProperty> get copyWith => _$DiagnosticsDoublePropertyCopyWithImpl<DiagnosticsDoubleProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsDoublePropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsDoubleProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.double(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsDoublePropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsDoublePropertyCopyWith(DiagnosticsDoubleProperty value, $Res Function(DiagnosticsDoubleProperty) _then) = _$DiagnosticsDoublePropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, double value
});




}
/// @nodoc
class _$DiagnosticsDoublePropertyCopyWithImpl<$Res>
    implements $DiagnosticsDoublePropertyCopyWith<$Res> {
  _$DiagnosticsDoublePropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsDoubleProperty _self;
  final $Res Function(DiagnosticsDoubleProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsDoubleProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsFlagProperty implements DiagnosticsProperty {
  const DiagnosticsFlagProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'flag';
  factory DiagnosticsFlagProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsFlagPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  bool value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsFlagPropertyCopyWith<DiagnosticsFlagProperty> get copyWith => _$DiagnosticsFlagPropertyCopyWithImpl<DiagnosticsFlagProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsFlagPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsFlagProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.flag(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsFlagPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsFlagPropertyCopyWith(DiagnosticsFlagProperty value, $Res Function(DiagnosticsFlagProperty) _then) = _$DiagnosticsFlagPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, bool value
});




}
/// @nodoc
class _$DiagnosticsFlagPropertyCopyWithImpl<$Res>
    implements $DiagnosticsFlagPropertyCopyWith<$Res> {
  _$DiagnosticsFlagPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsFlagProperty _self;
  final $Res Function(DiagnosticsFlagProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsFlagProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsEnumProperty implements DiagnosticsProperty {
  const DiagnosticsEnumProperty({required this.name, required this.level, required this.value, required this.enumType, final  String? $type}): $type = $type ?? 'enumValue';
  factory DiagnosticsEnumProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsEnumPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  String value;
 final  String enumType;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsEnumPropertyCopyWith<DiagnosticsEnumProperty> get copyWith => _$DiagnosticsEnumPropertyCopyWithImpl<DiagnosticsEnumProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsEnumPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsEnumProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value)&&(identical(other.enumType, enumType) || other.enumType == enumType));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value,enumType);

@override
String toString() {
  return 'DiagnosticsProperty.enumValue(name: $name, level: $level, value: $value, enumType: $enumType)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsEnumPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsEnumPropertyCopyWith(DiagnosticsEnumProperty value, $Res Function(DiagnosticsEnumProperty) _then) = _$DiagnosticsEnumPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, String value, String enumType
});




}
/// @nodoc
class _$DiagnosticsEnumPropertyCopyWithImpl<$Res>
    implements $DiagnosticsEnumPropertyCopyWith<$Res> {
  _$DiagnosticsEnumPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsEnumProperty _self;
  final $Res Function(DiagnosticsEnumProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,Object? enumType = null,}) {
  return _then(DiagnosticsEnumProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,enumType: null == enumType ? _self.enumType : enumType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsDurationProperty implements DiagnosticsProperty {
  const DiagnosticsDurationProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'duration';
  factory DiagnosticsDurationProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsDurationPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  Duration value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsDurationPropertyCopyWith<DiagnosticsDurationProperty> get copyWith => _$DiagnosticsDurationPropertyCopyWithImpl<DiagnosticsDurationProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsDurationPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsDurationProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.duration(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsDurationPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsDurationPropertyCopyWith(DiagnosticsDurationProperty value, $Res Function(DiagnosticsDurationProperty) _then) = _$DiagnosticsDurationPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, Duration value
});




}
/// @nodoc
class _$DiagnosticsDurationPropertyCopyWithImpl<$Res>
    implements $DiagnosticsDurationPropertyCopyWith<$Res> {
  _$DiagnosticsDurationPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsDurationProperty _self;
  final $Res Function(DiagnosticsDurationProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsDurationProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsTimestampProperty implements DiagnosticsProperty {
  const DiagnosticsTimestampProperty({required this.name, required this.level, required this.value, final  String? $type}): $type = $type ?? 'timestamp';
  factory DiagnosticsTimestampProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsTimestampPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  DateTime value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsTimestampPropertyCopyWith<DiagnosticsTimestampProperty> get copyWith => _$DiagnosticsTimestampPropertyCopyWithImpl<DiagnosticsTimestampProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsTimestampPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsTimestampProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,value);

@override
String toString() {
  return 'DiagnosticsProperty.timestamp(name: $name, level: $level, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsTimestampPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsTimestampPropertyCopyWith(DiagnosticsTimestampProperty value, $Res Function(DiagnosticsTimestampProperty) _then) = _$DiagnosticsTimestampPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, DateTime value
});




}
/// @nodoc
class _$DiagnosticsTimestampPropertyCopyWithImpl<$Res>
    implements $DiagnosticsTimestampPropertyCopyWith<$Res> {
  _$DiagnosticsTimestampPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsTimestampProperty _self;
  final $Res Function(DiagnosticsTimestampProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? value = null,}) {
  return _then(DiagnosticsTimestampProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsReferenceProperty implements DiagnosticsProperty {
  const DiagnosticsReferenceProperty({required this.name, required this.level, required this.referenceKind, required this.value, final  String? $type}): $type = $type ?? 'reference';
  factory DiagnosticsReferenceProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsReferencePropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  ReferenceKind referenceKind;
 final  String value;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsReferencePropertyCopyWith<DiagnosticsReferenceProperty> get copyWith => _$DiagnosticsReferencePropertyCopyWithImpl<DiagnosticsReferenceProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsReferencePropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsReferenceProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&(identical(other.referenceKind, referenceKind) || other.referenceKind == referenceKind)&&(identical(other.value, value) || other.value == value));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,referenceKind,value);

@override
String toString() {
  return 'DiagnosticsProperty.reference(name: $name, level: $level, referenceKind: $referenceKind, value: $value)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsReferencePropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsReferencePropertyCopyWith(DiagnosticsReferenceProperty value, $Res Function(DiagnosticsReferenceProperty) _then) = _$DiagnosticsReferencePropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, ReferenceKind referenceKind, String value
});




}
/// @nodoc
class _$DiagnosticsReferencePropertyCopyWithImpl<$Res>
    implements $DiagnosticsReferencePropertyCopyWith<$Res> {
  _$DiagnosticsReferencePropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsReferenceProperty _self;
  final $Res Function(DiagnosticsReferenceProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? referenceKind = null,Object? value = null,}) {
  return _then(DiagnosticsReferenceProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,referenceKind: null == referenceKind ? _self.referenceKind : referenceKind // ignore: cast_nullable_to_non_nullable
as ReferenceKind,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class DiagnosticsObjectProperty implements DiagnosticsProperty {
  const DiagnosticsObjectProperty({required this.name, required this.level, required final  List<DiagnosticsProperty> properties, final  String? $type}): _properties = properties,$type = $type ?? 'object';
  factory DiagnosticsObjectProperty.fromJson(Map<String, dynamic> json) => _$DiagnosticsObjectPropertyFromJson(json);

@override final  String name;
@override final  DiagnosticsLevel level;
 final  List<DiagnosticsProperty> _properties;
 List<DiagnosticsProperty> get properties {
  if (_properties is EqualUnmodifiableListView) return _properties;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_properties);
}


@JsonKey(name: 'kind')
final String $type;


/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiagnosticsObjectPropertyCopyWith<DiagnosticsObjectProperty> get copyWith => _$DiagnosticsObjectPropertyCopyWithImpl<DiagnosticsObjectProperty>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DiagnosticsObjectPropertyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DiagnosticsObjectProperty&&(identical(other.name, name) || other.name == name)&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other._properties, _properties));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,name,level,const DeepCollectionEquality().hash(_properties));

@override
String toString() {
  return 'DiagnosticsProperty.object(name: $name, level: $level, properties: $properties)';
}


}

/// @nodoc
abstract mixin class $DiagnosticsObjectPropertyCopyWith<$Res> implements $DiagnosticsPropertyCopyWith<$Res> {
  factory $DiagnosticsObjectPropertyCopyWith(DiagnosticsObjectProperty value, $Res Function(DiagnosticsObjectProperty) _then) = _$DiagnosticsObjectPropertyCopyWithImpl;
@override @useResult
$Res call({
 String name, DiagnosticsLevel level, List<DiagnosticsProperty> properties
});




}
/// @nodoc
class _$DiagnosticsObjectPropertyCopyWithImpl<$Res>
    implements $DiagnosticsObjectPropertyCopyWith<$Res> {
  _$DiagnosticsObjectPropertyCopyWithImpl(this._self, this._then);

  final DiagnosticsObjectProperty _self;
  final $Res Function(DiagnosticsObjectProperty) _then;

/// Create a copy of DiagnosticsProperty
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? level = null,Object? properties = null,}) {
  return _then(DiagnosticsObjectProperty(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as DiagnosticsLevel,properties: null == properties ? _self._properties : properties // ignore: cast_nullable_to_non_nullable
as List<DiagnosticsProperty>,
  ));
}


}

// dart format on
