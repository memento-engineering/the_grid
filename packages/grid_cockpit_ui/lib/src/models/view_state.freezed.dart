// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PropertyValue {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PropertyValue);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PropertyValue()';
}


}

/// @nodoc
class $PropertyValueCopyWith<$Res>  {
$PropertyValueCopyWith(PropertyValue _, $Res Function(PropertyValue) __);
}


/// Adds pattern-matching-related methods to [PropertyValue].
extension PropertyValuePatterns on PropertyValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StringPropertyValue value)?  string,TResult Function( IntPropertyValue value)?  integer,TResult Function( DoublePropertyValue value)?  decimal,TResult Function( FlagPropertyValue value)?  flag,TResult Function( EnumPropertyValue value)?  enumeration,TResult Function( DurationPropertyValue value)?  duration,TResult Function( TimestampPropertyValue value)?  timestamp,TResult Function( ReferencePropertyValue value)?  reference,TResult Function( ObjectPropertyValue value)?  object,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StringPropertyValue() when string != null:
return string(_that);case IntPropertyValue() when integer != null:
return integer(_that);case DoublePropertyValue() when decimal != null:
return decimal(_that);case FlagPropertyValue() when flag != null:
return flag(_that);case EnumPropertyValue() when enumeration != null:
return enumeration(_that);case DurationPropertyValue() when duration != null:
return duration(_that);case TimestampPropertyValue() when timestamp != null:
return timestamp(_that);case ReferencePropertyValue() when reference != null:
return reference(_that);case ObjectPropertyValue() when object != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StringPropertyValue value)  string,required TResult Function( IntPropertyValue value)  integer,required TResult Function( DoublePropertyValue value)  decimal,required TResult Function( FlagPropertyValue value)  flag,required TResult Function( EnumPropertyValue value)  enumeration,required TResult Function( DurationPropertyValue value)  duration,required TResult Function( TimestampPropertyValue value)  timestamp,required TResult Function( ReferencePropertyValue value)  reference,required TResult Function( ObjectPropertyValue value)  object,}){
final _that = this;
switch (_that) {
case StringPropertyValue():
return string(_that);case IntPropertyValue():
return integer(_that);case DoublePropertyValue():
return decimal(_that);case FlagPropertyValue():
return flag(_that);case EnumPropertyValue():
return enumeration(_that);case DurationPropertyValue():
return duration(_that);case TimestampPropertyValue():
return timestamp(_that);case ReferencePropertyValue():
return reference(_that);case ObjectPropertyValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StringPropertyValue value)?  string,TResult? Function( IntPropertyValue value)?  integer,TResult? Function( DoublePropertyValue value)?  decimal,TResult? Function( FlagPropertyValue value)?  flag,TResult? Function( EnumPropertyValue value)?  enumeration,TResult? Function( DurationPropertyValue value)?  duration,TResult? Function( TimestampPropertyValue value)?  timestamp,TResult? Function( ReferencePropertyValue value)?  reference,TResult? Function( ObjectPropertyValue value)?  object,}){
final _that = this;
switch (_that) {
case StringPropertyValue() when string != null:
return string(_that);case IntPropertyValue() when integer != null:
return integer(_that);case DoublePropertyValue() when decimal != null:
return decimal(_that);case FlagPropertyValue() when flag != null:
return flag(_that);case EnumPropertyValue() when enumeration != null:
return enumeration(_that);case DurationPropertyValue() when duration != null:
return duration(_that);case TimestampPropertyValue() when timestamp != null:
return timestamp(_that);case ReferencePropertyValue() when reference != null:
return reference(_that);case ObjectPropertyValue() when object != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  string,TResult Function( int value)?  integer,TResult Function( double value)?  decimal,TResult Function( bool value)?  flag,TResult Function( String value,  String enumType)?  enumeration,TResult Function( Duration value)?  duration,TResult Function( DateTime value)?  timestamp,TResult Function( ReferenceKind kind,  String value)?  reference,TResult Function( List<PropertyRowModel> properties)?  object,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StringPropertyValue() when string != null:
return string(_that.value);case IntPropertyValue() when integer != null:
return integer(_that.value);case DoublePropertyValue() when decimal != null:
return decimal(_that.value);case FlagPropertyValue() when flag != null:
return flag(_that.value);case EnumPropertyValue() when enumeration != null:
return enumeration(_that.value,_that.enumType);case DurationPropertyValue() when duration != null:
return duration(_that.value);case TimestampPropertyValue() when timestamp != null:
return timestamp(_that.value);case ReferencePropertyValue() when reference != null:
return reference(_that.kind,_that.value);case ObjectPropertyValue() when object != null:
return object(_that.properties);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  string,required TResult Function( int value)  integer,required TResult Function( double value)  decimal,required TResult Function( bool value)  flag,required TResult Function( String value,  String enumType)  enumeration,required TResult Function( Duration value)  duration,required TResult Function( DateTime value)  timestamp,required TResult Function( ReferenceKind kind,  String value)  reference,required TResult Function( List<PropertyRowModel> properties)  object,}) {final _that = this;
switch (_that) {
case StringPropertyValue():
return string(_that.value);case IntPropertyValue():
return integer(_that.value);case DoublePropertyValue():
return decimal(_that.value);case FlagPropertyValue():
return flag(_that.value);case EnumPropertyValue():
return enumeration(_that.value,_that.enumType);case DurationPropertyValue():
return duration(_that.value);case TimestampPropertyValue():
return timestamp(_that.value);case ReferencePropertyValue():
return reference(_that.kind,_that.value);case ObjectPropertyValue():
return object(_that.properties);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  string,TResult? Function( int value)?  integer,TResult? Function( double value)?  decimal,TResult? Function( bool value)?  flag,TResult? Function( String value,  String enumType)?  enumeration,TResult? Function( Duration value)?  duration,TResult? Function( DateTime value)?  timestamp,TResult? Function( ReferenceKind kind,  String value)?  reference,TResult? Function( List<PropertyRowModel> properties)?  object,}) {final _that = this;
switch (_that) {
case StringPropertyValue() when string != null:
return string(_that.value);case IntPropertyValue() when integer != null:
return integer(_that.value);case DoublePropertyValue() when decimal != null:
return decimal(_that.value);case FlagPropertyValue() when flag != null:
return flag(_that.value);case EnumPropertyValue() when enumeration != null:
return enumeration(_that.value,_that.enumType);case DurationPropertyValue() when duration != null:
return duration(_that.value);case TimestampPropertyValue() when timestamp != null:
return timestamp(_that.value);case ReferencePropertyValue() when reference != null:
return reference(_that.kind,_that.value);case ObjectPropertyValue() when object != null:
return object(_that.properties);case _:
  return null;

}
}

}

/// @nodoc


class StringPropertyValue implements PropertyValue {
  const StringPropertyValue(this.value);
  

 final  String value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StringPropertyValueCopyWith<StringPropertyValue> get copyWith => _$StringPropertyValueCopyWithImpl<StringPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StringPropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.string(value: $value)';
}


}

/// @nodoc
abstract mixin class $StringPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $StringPropertyValueCopyWith(StringPropertyValue value, $Res Function(StringPropertyValue) _then) = _$StringPropertyValueCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$StringPropertyValueCopyWithImpl<$Res>
    implements $StringPropertyValueCopyWith<$Res> {
  _$StringPropertyValueCopyWithImpl(this._self, this._then);

  final StringPropertyValue _self;
  final $Res Function(StringPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(StringPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class IntPropertyValue implements PropertyValue {
  const IntPropertyValue(this.value);
  

 final  int value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IntPropertyValueCopyWith<IntPropertyValue> get copyWith => _$IntPropertyValueCopyWithImpl<IntPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IntPropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.integer(value: $value)';
}


}

/// @nodoc
abstract mixin class $IntPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $IntPropertyValueCopyWith(IntPropertyValue value, $Res Function(IntPropertyValue) _then) = _$IntPropertyValueCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$IntPropertyValueCopyWithImpl<$Res>
    implements $IntPropertyValueCopyWith<$Res> {
  _$IntPropertyValueCopyWithImpl(this._self, this._then);

  final IntPropertyValue _self;
  final $Res Function(IntPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(IntPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DoublePropertyValue implements PropertyValue {
  const DoublePropertyValue(this.value);
  

 final  double value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DoublePropertyValueCopyWith<DoublePropertyValue> get copyWith => _$DoublePropertyValueCopyWithImpl<DoublePropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DoublePropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.decimal(value: $value)';
}


}

/// @nodoc
abstract mixin class $DoublePropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $DoublePropertyValueCopyWith(DoublePropertyValue value, $Res Function(DoublePropertyValue) _then) = _$DoublePropertyValueCopyWithImpl;
@useResult
$Res call({
 double value
});




}
/// @nodoc
class _$DoublePropertyValueCopyWithImpl<$Res>
    implements $DoublePropertyValueCopyWith<$Res> {
  _$DoublePropertyValueCopyWithImpl(this._self, this._then);

  final DoublePropertyValue _self;
  final $Res Function(DoublePropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(DoublePropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class FlagPropertyValue implements PropertyValue {
  const FlagPropertyValue(this.value);
  

 final  bool value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlagPropertyValueCopyWith<FlagPropertyValue> get copyWith => _$FlagPropertyValueCopyWithImpl<FlagPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FlagPropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.flag(value: $value)';
}


}

/// @nodoc
abstract mixin class $FlagPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $FlagPropertyValueCopyWith(FlagPropertyValue value, $Res Function(FlagPropertyValue) _then) = _$FlagPropertyValueCopyWithImpl;
@useResult
$Res call({
 bool value
});




}
/// @nodoc
class _$FlagPropertyValueCopyWithImpl<$Res>
    implements $FlagPropertyValueCopyWith<$Res> {
  _$FlagPropertyValueCopyWithImpl(this._self, this._then);

  final FlagPropertyValue _self;
  final $Res Function(FlagPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FlagPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class EnumPropertyValue implements PropertyValue {
  const EnumPropertyValue(this.value, this.enumType);
  

 final  String value;
 final  String enumType;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EnumPropertyValueCopyWith<EnumPropertyValue> get copyWith => _$EnumPropertyValueCopyWithImpl<EnumPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EnumPropertyValue&&(identical(other.value, value) || other.value == value)&&(identical(other.enumType, enumType) || other.enumType == enumType));
}


@override
int get hashCode => Object.hash(runtimeType,value,enumType);

@override
String toString() {
  return 'PropertyValue.enumeration(value: $value, enumType: $enumType)';
}


}

/// @nodoc
abstract mixin class $EnumPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $EnumPropertyValueCopyWith(EnumPropertyValue value, $Res Function(EnumPropertyValue) _then) = _$EnumPropertyValueCopyWithImpl;
@useResult
$Res call({
 String value, String enumType
});




}
/// @nodoc
class _$EnumPropertyValueCopyWithImpl<$Res>
    implements $EnumPropertyValueCopyWith<$Res> {
  _$EnumPropertyValueCopyWithImpl(this._self, this._then);

  final EnumPropertyValue _self;
  final $Res Function(EnumPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,Object? enumType = null,}) {
  return _then(EnumPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,null == enumType ? _self.enumType : enumType // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DurationPropertyValue implements PropertyValue {
  const DurationPropertyValue(this.value);
  

 final  Duration value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DurationPropertyValueCopyWith<DurationPropertyValue> get copyWith => _$DurationPropertyValueCopyWithImpl<DurationPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DurationPropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.duration(value: $value)';
}


}

/// @nodoc
abstract mixin class $DurationPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $DurationPropertyValueCopyWith(DurationPropertyValue value, $Res Function(DurationPropertyValue) _then) = _$DurationPropertyValueCopyWithImpl;
@useResult
$Res call({
 Duration value
});




}
/// @nodoc
class _$DurationPropertyValueCopyWithImpl<$Res>
    implements $DurationPropertyValueCopyWith<$Res> {
  _$DurationPropertyValueCopyWithImpl(this._self, this._then);

  final DurationPropertyValue _self;
  final $Res Function(DurationPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(DurationPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

/// @nodoc


class TimestampPropertyValue implements PropertyValue {
  const TimestampPropertyValue(this.value);
  

 final  DateTime value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimestampPropertyValueCopyWith<TimestampPropertyValue> get copyWith => _$TimestampPropertyValueCopyWithImpl<TimestampPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimestampPropertyValue&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'PropertyValue.timestamp(value: $value)';
}


}

/// @nodoc
abstract mixin class $TimestampPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $TimestampPropertyValueCopyWith(TimestampPropertyValue value, $Res Function(TimestampPropertyValue) _then) = _$TimestampPropertyValueCopyWithImpl;
@useResult
$Res call({
 DateTime value
});




}
/// @nodoc
class _$TimestampPropertyValueCopyWithImpl<$Res>
    implements $TimestampPropertyValueCopyWith<$Res> {
  _$TimestampPropertyValueCopyWithImpl(this._self, this._then);

  final TimestampPropertyValue _self;
  final $Res Function(TimestampPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(TimestampPropertyValue(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc


class ReferencePropertyValue implements PropertyValue {
  const ReferencePropertyValue(this.kind, this.value);
  

 final  ReferenceKind kind;
 final  String value;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReferencePropertyValueCopyWith<ReferencePropertyValue> get copyWith => _$ReferencePropertyValueCopyWithImpl<ReferencePropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReferencePropertyValue&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,kind,value);

@override
String toString() {
  return 'PropertyValue.reference(kind: $kind, value: $value)';
}


}

/// @nodoc
abstract mixin class $ReferencePropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $ReferencePropertyValueCopyWith(ReferencePropertyValue value, $Res Function(ReferencePropertyValue) _then) = _$ReferencePropertyValueCopyWithImpl;
@useResult
$Res call({
 ReferenceKind kind, String value
});




}
/// @nodoc
class _$ReferencePropertyValueCopyWithImpl<$Res>
    implements $ReferencePropertyValueCopyWith<$Res> {
  _$ReferencePropertyValueCopyWithImpl(this._self, this._then);

  final ReferencePropertyValue _self;
  final $Res Function(ReferencePropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? value = null,}) {
  return _then(ReferencePropertyValue(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ReferenceKind,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ObjectPropertyValue implements PropertyValue {
  const ObjectPropertyValue(final  List<PropertyRowModel> properties): _properties = properties;
  

 final  List<PropertyRowModel> _properties;
 List<PropertyRowModel> get properties {
  if (_properties is EqualUnmodifiableListView) return _properties;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_properties);
}


/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObjectPropertyValueCopyWith<ObjectPropertyValue> get copyWith => _$ObjectPropertyValueCopyWithImpl<ObjectPropertyValue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObjectPropertyValue&&const DeepCollectionEquality().equals(other._properties, _properties));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_properties));

@override
String toString() {
  return 'PropertyValue.object(properties: $properties)';
}


}

/// @nodoc
abstract mixin class $ObjectPropertyValueCopyWith<$Res> implements $PropertyValueCopyWith<$Res> {
  factory $ObjectPropertyValueCopyWith(ObjectPropertyValue value, $Res Function(ObjectPropertyValue) _then) = _$ObjectPropertyValueCopyWithImpl;
@useResult
$Res call({
 List<PropertyRowModel> properties
});




}
/// @nodoc
class _$ObjectPropertyValueCopyWithImpl<$Res>
    implements $ObjectPropertyValueCopyWith<$Res> {
  _$ObjectPropertyValueCopyWithImpl(this._self, this._then);

  final ObjectPropertyValue _self;
  final $Res Function(ObjectPropertyValue) _then;

/// Create a copy of PropertyValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? properties = null,}) {
  return _then(ObjectPropertyValue(
null == properties ? _self._properties : properties // ignore: cast_nullable_to_non_nullable
as List<PropertyRowModel>,
  ));
}


}

/// @nodoc
mixin _$PropertyRowModel {

 String get name; SeverityToken get severity; PropertyValue get value;
/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PropertyRowModelCopyWith<PropertyRowModel> get copyWith => _$PropertyRowModelCopyWithImpl<PropertyRowModel>(this as PropertyRowModel, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PropertyRowModel&&(identical(other.name, name) || other.name == name)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,name,severity,value);

@override
String toString() {
  return 'PropertyRowModel(name: $name, severity: $severity, value: $value)';
}


}

/// @nodoc
abstract mixin class $PropertyRowModelCopyWith<$Res>  {
  factory $PropertyRowModelCopyWith(PropertyRowModel value, $Res Function(PropertyRowModel) _then) = _$PropertyRowModelCopyWithImpl;
@useResult
$Res call({
 String name, SeverityToken severity, PropertyValue value
});


$PropertyValueCopyWith<$Res> get value;

}
/// @nodoc
class _$PropertyRowModelCopyWithImpl<$Res>
    implements $PropertyRowModelCopyWith<$Res> {
  _$PropertyRowModelCopyWithImpl(this._self, this._then);

  final PropertyRowModel _self;
  final $Res Function(PropertyRowModel) _then;

/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? severity = null,Object? value = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as SeverityToken,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PropertyValue,
  ));
}
/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PropertyValueCopyWith<$Res> get value {
  
  return $PropertyValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PropertyRowModel].
extension PropertyRowModelPatterns on PropertyRowModel {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PropertyRowModel value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PropertyRowModel() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PropertyRowModel value)  $default,){
final _that = this;
switch (_that) {
case _PropertyRowModel():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PropertyRowModel value)?  $default,){
final _that = this;
switch (_that) {
case _PropertyRowModel() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  SeverityToken severity,  PropertyValue value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PropertyRowModel() when $default != null:
return $default(_that.name,_that.severity,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  SeverityToken severity,  PropertyValue value)  $default,) {final _that = this;
switch (_that) {
case _PropertyRowModel():
return $default(_that.name,_that.severity,_that.value);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  SeverityToken severity,  PropertyValue value)?  $default,) {final _that = this;
switch (_that) {
case _PropertyRowModel() when $default != null:
return $default(_that.name,_that.severity,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PropertyRowModel implements PropertyRowModel {
  const _PropertyRowModel({required this.name, required this.severity, required this.value});
  

@override final  String name;
@override final  SeverityToken severity;
@override final  PropertyValue value;

/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PropertyRowModelCopyWith<_PropertyRowModel> get copyWith => __$PropertyRowModelCopyWithImpl<_PropertyRowModel>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PropertyRowModel&&(identical(other.name, name) || other.name == name)&&(identical(other.severity, severity) || other.severity == severity)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,name,severity,value);

@override
String toString() {
  return 'PropertyRowModel(name: $name, severity: $severity, value: $value)';
}


}

/// @nodoc
abstract mixin class _$PropertyRowModelCopyWith<$Res> implements $PropertyRowModelCopyWith<$Res> {
  factory _$PropertyRowModelCopyWith(_PropertyRowModel value, $Res Function(_PropertyRowModel) _then) = __$PropertyRowModelCopyWithImpl;
@override @useResult
$Res call({
 String name, SeverityToken severity, PropertyValue value
});


@override $PropertyValueCopyWith<$Res> get value;

}
/// @nodoc
class __$PropertyRowModelCopyWithImpl<$Res>
    implements _$PropertyRowModelCopyWith<$Res> {
  __$PropertyRowModelCopyWithImpl(this._self, this._then);

  final _PropertyRowModel _self;
  final $Res Function(_PropertyRowModel) _then;

/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? severity = null,Object? value = null,}) {
  return _then(_PropertyRowModel(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,severity: null == severity ? _self.severity : severity // ignore: cast_nullable_to_non_nullable
as SeverityToken,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PropertyValue,
  ));
}

/// Create a copy of PropertyRowModel
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PropertyValueCopyWith<$Res> get value {
  
  return $PropertyValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$SubstationSummary {

 String get nodeId; String get substationId; int get mountedWorkCount;
/// Create a copy of SubstationSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubstationSummaryCopyWith<SubstationSummary> get copyWith => _$SubstationSummaryCopyWithImpl<SubstationSummary>(this as SubstationSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubstationSummary&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.substationId, substationId) || other.substationId == substationId)&&(identical(other.mountedWorkCount, mountedWorkCount) || other.mountedWorkCount == mountedWorkCount));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,substationId,mountedWorkCount);

@override
String toString() {
  return 'SubstationSummary(nodeId: $nodeId, substationId: $substationId, mountedWorkCount: $mountedWorkCount)';
}


}

/// @nodoc
abstract mixin class $SubstationSummaryCopyWith<$Res>  {
  factory $SubstationSummaryCopyWith(SubstationSummary value, $Res Function(SubstationSummary) _then) = _$SubstationSummaryCopyWithImpl;
@useResult
$Res call({
 String nodeId, String substationId, int mountedWorkCount
});




}
/// @nodoc
class _$SubstationSummaryCopyWithImpl<$Res>
    implements $SubstationSummaryCopyWith<$Res> {
  _$SubstationSummaryCopyWithImpl(this._self, this._then);

  final SubstationSummary _self;
  final $Res Function(SubstationSummary) _then;

/// Create a copy of SubstationSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? substationId = null,Object? mountedWorkCount = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,substationId: null == substationId ? _self.substationId : substationId // ignore: cast_nullable_to_non_nullable
as String,mountedWorkCount: null == mountedWorkCount ? _self.mountedWorkCount : mountedWorkCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SubstationSummary].
extension SubstationSummaryPatterns on SubstationSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubstationSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubstationSummary() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubstationSummary value)  $default,){
final _that = this;
switch (_that) {
case _SubstationSummary():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubstationSummary value)?  $default,){
final _that = this;
switch (_that) {
case _SubstationSummary() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String substationId,  int mountedWorkCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubstationSummary() when $default != null:
return $default(_that.nodeId,_that.substationId,_that.mountedWorkCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String substationId,  int mountedWorkCount)  $default,) {final _that = this;
switch (_that) {
case _SubstationSummary():
return $default(_that.nodeId,_that.substationId,_that.mountedWorkCount);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String substationId,  int mountedWorkCount)?  $default,) {final _that = this;
switch (_that) {
case _SubstationSummary() when $default != null:
return $default(_that.nodeId,_that.substationId,_that.mountedWorkCount);case _:
  return null;

}
}

}

/// @nodoc


class _SubstationSummary implements SubstationSummary {
  const _SubstationSummary({required this.nodeId, required this.substationId, required this.mountedWorkCount});
  

@override final  String nodeId;
@override final  String substationId;
@override final  int mountedWorkCount;

/// Create a copy of SubstationSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubstationSummaryCopyWith<_SubstationSummary> get copyWith => __$SubstationSummaryCopyWithImpl<_SubstationSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubstationSummary&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.substationId, substationId) || other.substationId == substationId)&&(identical(other.mountedWorkCount, mountedWorkCount) || other.mountedWorkCount == mountedWorkCount));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,substationId,mountedWorkCount);

@override
String toString() {
  return 'SubstationSummary(nodeId: $nodeId, substationId: $substationId, mountedWorkCount: $mountedWorkCount)';
}


}

/// @nodoc
abstract mixin class _$SubstationSummaryCopyWith<$Res> implements $SubstationSummaryCopyWith<$Res> {
  factory _$SubstationSummaryCopyWith(_SubstationSummary value, $Res Function(_SubstationSummary) _then) = __$SubstationSummaryCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String substationId, int mountedWorkCount
});




}
/// @nodoc
class __$SubstationSummaryCopyWithImpl<$Res>
    implements _$SubstationSummaryCopyWith<$Res> {
  __$SubstationSummaryCopyWithImpl(this._self, this._then);

  final _SubstationSummary _self;
  final $Res Function(_SubstationSummary) _then;

/// Create a copy of SubstationSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? substationId = null,Object? mountedWorkCount = null,}) {
  return _then(_SubstationSummary(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,substationId: null == substationId ? _self.substationId : substationId // ignore: cast_nullable_to_non_nullable
as String,mountedWorkCount: null == mountedWorkCount ? _self.mountedWorkCount : mountedWorkCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$OverviewState {

 DateTime get projectedAt; List<SubstationSummary> get substations; int get activeWorkCount; int get warningCount; int get errorCount;
/// Create a copy of OverviewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OverviewStateCopyWith<OverviewState> get copyWith => _$OverviewStateCopyWithImpl<OverviewState>(this as OverviewState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OverviewState&&(identical(other.projectedAt, projectedAt) || other.projectedAt == projectedAt)&&const DeepCollectionEquality().equals(other.substations, substations)&&(identical(other.activeWorkCount, activeWorkCount) || other.activeWorkCount == activeWorkCount)&&(identical(other.warningCount, warningCount) || other.warningCount == warningCount)&&(identical(other.errorCount, errorCount) || other.errorCount == errorCount));
}


@override
int get hashCode => Object.hash(runtimeType,projectedAt,const DeepCollectionEquality().hash(substations),activeWorkCount,warningCount,errorCount);

@override
String toString() {
  return 'OverviewState(projectedAt: $projectedAt, substations: $substations, activeWorkCount: $activeWorkCount, warningCount: $warningCount, errorCount: $errorCount)';
}


}

/// @nodoc
abstract mixin class $OverviewStateCopyWith<$Res>  {
  factory $OverviewStateCopyWith(OverviewState value, $Res Function(OverviewState) _then) = _$OverviewStateCopyWithImpl;
@useResult
$Res call({
 DateTime projectedAt, List<SubstationSummary> substations, int activeWorkCount, int warningCount, int errorCount
});




}
/// @nodoc
class _$OverviewStateCopyWithImpl<$Res>
    implements $OverviewStateCopyWith<$Res> {
  _$OverviewStateCopyWithImpl(this._self, this._then);

  final OverviewState _self;
  final $Res Function(OverviewState) _then;

/// Create a copy of OverviewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectedAt = null,Object? substations = null,Object? activeWorkCount = null,Object? warningCount = null,Object? errorCount = null,}) {
  return _then(_self.copyWith(
projectedAt: null == projectedAt ? _self.projectedAt : projectedAt // ignore: cast_nullable_to_non_nullable
as DateTime,substations: null == substations ? _self.substations : substations // ignore: cast_nullable_to_non_nullable
as List<SubstationSummary>,activeWorkCount: null == activeWorkCount ? _self.activeWorkCount : activeWorkCount // ignore: cast_nullable_to_non_nullable
as int,warningCount: null == warningCount ? _self.warningCount : warningCount // ignore: cast_nullable_to_non_nullable
as int,errorCount: null == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [OverviewState].
extension OverviewStatePatterns on OverviewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OverviewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OverviewState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OverviewState value)  $default,){
final _that = this;
switch (_that) {
case _OverviewState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OverviewState value)?  $default,){
final _that = this;
switch (_that) {
case _OverviewState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( DateTime projectedAt,  List<SubstationSummary> substations,  int activeWorkCount,  int warningCount,  int errorCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OverviewState() when $default != null:
return $default(_that.projectedAt,_that.substations,_that.activeWorkCount,_that.warningCount,_that.errorCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( DateTime projectedAt,  List<SubstationSummary> substations,  int activeWorkCount,  int warningCount,  int errorCount)  $default,) {final _that = this;
switch (_that) {
case _OverviewState():
return $default(_that.projectedAt,_that.substations,_that.activeWorkCount,_that.warningCount,_that.errorCount);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( DateTime projectedAt,  List<SubstationSummary> substations,  int activeWorkCount,  int warningCount,  int errorCount)?  $default,) {final _that = this;
switch (_that) {
case _OverviewState() when $default != null:
return $default(_that.projectedAt,_that.substations,_that.activeWorkCount,_that.warningCount,_that.errorCount);case _:
  return null;

}
}

}

/// @nodoc


class _OverviewState implements OverviewState {
  const _OverviewState({required this.projectedAt, required final  List<SubstationSummary> substations, required this.activeWorkCount, required this.warningCount, required this.errorCount}): _substations = substations;
  

@override final  DateTime projectedAt;
 final  List<SubstationSummary> _substations;
@override List<SubstationSummary> get substations {
  if (_substations is EqualUnmodifiableListView) return _substations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_substations);
}

@override final  int activeWorkCount;
@override final  int warningCount;
@override final  int errorCount;

/// Create a copy of OverviewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OverviewStateCopyWith<_OverviewState> get copyWith => __$OverviewStateCopyWithImpl<_OverviewState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OverviewState&&(identical(other.projectedAt, projectedAt) || other.projectedAt == projectedAt)&&const DeepCollectionEquality().equals(other._substations, _substations)&&(identical(other.activeWorkCount, activeWorkCount) || other.activeWorkCount == activeWorkCount)&&(identical(other.warningCount, warningCount) || other.warningCount == warningCount)&&(identical(other.errorCount, errorCount) || other.errorCount == errorCount));
}


@override
int get hashCode => Object.hash(runtimeType,projectedAt,const DeepCollectionEquality().hash(_substations),activeWorkCount,warningCount,errorCount);

@override
String toString() {
  return 'OverviewState(projectedAt: $projectedAt, substations: $substations, activeWorkCount: $activeWorkCount, warningCount: $warningCount, errorCount: $errorCount)';
}


}

/// @nodoc
abstract mixin class _$OverviewStateCopyWith<$Res> implements $OverviewStateCopyWith<$Res> {
  factory _$OverviewStateCopyWith(_OverviewState value, $Res Function(_OverviewState) _then) = __$OverviewStateCopyWithImpl;
@override @useResult
$Res call({
 DateTime projectedAt, List<SubstationSummary> substations, int activeWorkCount, int warningCount, int errorCount
});




}
/// @nodoc
class __$OverviewStateCopyWithImpl<$Res>
    implements _$OverviewStateCopyWith<$Res> {
  __$OverviewStateCopyWithImpl(this._self, this._then);

  final _OverviewState _self;
  final $Res Function(_OverviewState) _then;

/// Create a copy of OverviewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectedAt = null,Object? substations = null,Object? activeWorkCount = null,Object? warningCount = null,Object? errorCount = null,}) {
  return _then(_OverviewState(
projectedAt: null == projectedAt ? _self.projectedAt : projectedAt // ignore: cast_nullable_to_non_nullable
as DateTime,substations: null == substations ? _self._substations : substations // ignore: cast_nullable_to_non_nullable
as List<SubstationSummary>,activeWorkCount: null == activeWorkCount ? _self.activeWorkCount : activeWorkCount // ignore: cast_nullable_to_non_nullable
as int,warningCount: null == warningCount ? _self.warningCount : warningCount // ignore: cast_nullable_to_non_nullable
as int,errorCount: null == errorCount ? _self.errorCount : errorCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WorkItemView {

 String get nodeId; String get beadId; String? get sessionId; StepVisualState get state;
/// Create a copy of WorkItemView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkItemViewCopyWith<WorkItemView> get copyWith => _$WorkItemViewCopyWithImpl<WorkItemView>(this as WorkItemView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkItemView&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,beadId,sessionId,state);

@override
String toString() {
  return 'WorkItemView(nodeId: $nodeId, beadId: $beadId, sessionId: $sessionId, state: $state)';
}


}

/// @nodoc
abstract mixin class $WorkItemViewCopyWith<$Res>  {
  factory $WorkItemViewCopyWith(WorkItemView value, $Res Function(WorkItemView) _then) = _$WorkItemViewCopyWithImpl;
@useResult
$Res call({
 String nodeId, String beadId, String? sessionId, StepVisualState state
});




}
/// @nodoc
class _$WorkItemViewCopyWithImpl<$Res>
    implements $WorkItemViewCopyWith<$Res> {
  _$WorkItemViewCopyWithImpl(this._self, this._then);

  final WorkItemView _self;
  final $Res Function(WorkItemView) _then;

/// Create a copy of WorkItemView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? beadId = null,Object? sessionId = freezed,Object? state = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepVisualState,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkItemView].
extension WorkItemViewPatterns on WorkItemView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkItemView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkItemView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkItemView value)  $default,){
final _that = this;
switch (_that) {
case _WorkItemView():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkItemView value)?  $default,){
final _that = this;
switch (_that) {
case _WorkItemView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String beadId,  String? sessionId,  StepVisualState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkItemView() when $default != null:
return $default(_that.nodeId,_that.beadId,_that.sessionId,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String beadId,  String? sessionId,  StepVisualState state)  $default,) {final _that = this;
switch (_that) {
case _WorkItemView():
return $default(_that.nodeId,_that.beadId,_that.sessionId,_that.state);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String beadId,  String? sessionId,  StepVisualState state)?  $default,) {final _that = this;
switch (_that) {
case _WorkItemView() when $default != null:
return $default(_that.nodeId,_that.beadId,_that.sessionId,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _WorkItemView implements WorkItemView {
  const _WorkItemView({required this.nodeId, required this.beadId, this.sessionId, required this.state});
  

@override final  String nodeId;
@override final  String beadId;
@override final  String? sessionId;
@override final  StepVisualState state;

/// Create a copy of WorkItemView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkItemViewCopyWith<_WorkItemView> get copyWith => __$WorkItemViewCopyWithImpl<_WorkItemView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkItemView&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,beadId,sessionId,state);

@override
String toString() {
  return 'WorkItemView(nodeId: $nodeId, beadId: $beadId, sessionId: $sessionId, state: $state)';
}


}

/// @nodoc
abstract mixin class _$WorkItemViewCopyWith<$Res> implements $WorkItemViewCopyWith<$Res> {
  factory _$WorkItemViewCopyWith(_WorkItemView value, $Res Function(_WorkItemView) _then) = __$WorkItemViewCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String beadId, String? sessionId, StepVisualState state
});




}
/// @nodoc
class __$WorkItemViewCopyWithImpl<$Res>
    implements _$WorkItemViewCopyWith<$Res> {
  __$WorkItemViewCopyWithImpl(this._self, this._then);

  final _WorkItemView _self;
  final $Res Function(_WorkItemView) _then;

/// Create a copy of WorkItemView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? beadId = null,Object? sessionId = freezed,Object? state = null,}) {
  return _then(_WorkItemView(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepVisualState,
  ));
}


}

/// @nodoc
mixin _$WorkListState {

 List<WorkItemView> get items;
/// Create a copy of WorkListState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkListStateCopyWith<WorkListState> get copyWith => _$WorkListStateCopyWithImpl<WorkListState>(this as WorkListState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkListState&&const DeepCollectionEquality().equals(other.items, items));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items));

@override
String toString() {
  return 'WorkListState(items: $items)';
}


}

/// @nodoc
abstract mixin class $WorkListStateCopyWith<$Res>  {
  factory $WorkListStateCopyWith(WorkListState value, $Res Function(WorkListState) _then) = _$WorkListStateCopyWithImpl;
@useResult
$Res call({
 List<WorkItemView> items
});




}
/// @nodoc
class _$WorkListStateCopyWithImpl<$Res>
    implements $WorkListStateCopyWith<$Res> {
  _$WorkListStateCopyWithImpl(this._self, this._then);

  final WorkListState _self;
  final $Res Function(WorkListState) _then;

/// Create a copy of WorkListState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,}) {
  return _then(_self.copyWith(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<WorkItemView>,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkListState].
extension WorkListStatePatterns on WorkListState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkListState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkListState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkListState value)  $default,){
final _that = this;
switch (_that) {
case _WorkListState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkListState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkListState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<WorkItemView> items)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkListState() when $default != null:
return $default(_that.items);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<WorkItemView> items)  $default,) {final _that = this;
switch (_that) {
case _WorkListState():
return $default(_that.items);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<WorkItemView> items)?  $default,) {final _that = this;
switch (_that) {
case _WorkListState() when $default != null:
return $default(_that.items);case _:
  return null;

}
}

}

/// @nodoc


class _WorkListState implements WorkListState {
  const _WorkListState({required final  List<WorkItemView> items}): _items = items;
  

 final  List<WorkItemView> _items;
@override List<WorkItemView> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of WorkListState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkListStateCopyWith<_WorkListState> get copyWith => __$WorkListStateCopyWithImpl<_WorkListState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkListState&&const DeepCollectionEquality().equals(other._items, _items));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'WorkListState(items: $items)';
}


}

/// @nodoc
abstract mixin class _$WorkListStateCopyWith<$Res> implements $WorkListStateCopyWith<$Res> {
  factory _$WorkListStateCopyWith(_WorkListState value, $Res Function(_WorkListState) _then) = __$WorkListStateCopyWithImpl;
@override @useResult
$Res call({
 List<WorkItemView> items
});




}
/// @nodoc
class __$WorkListStateCopyWithImpl<$Res>
    implements _$WorkListStateCopyWith<$Res> {
  __$WorkListStateCopyWithImpl(this._self, this._then);

  final _WorkListState _self;
  final $Res Function(_WorkListState) _then;

/// Create a copy of WorkListState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,}) {
  return _then(_WorkListState(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<WorkItemView>,
  ));
}


}

/// @nodoc
mixin _$PipelineNodeView {

 String get nodeId; String get label; StepVisualState get state; int get incarnationDepth; Duration? get duration; List<PipelineNodeView> get children;
/// Create a copy of PipelineNodeView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PipelineNodeViewCopyWith<PipelineNodeView> get copyWith => _$PipelineNodeViewCopyWithImpl<PipelineNodeView>(this as PipelineNodeView, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PipelineNodeView&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.label, label) || other.label == label)&&(identical(other.state, state) || other.state == state)&&(identical(other.incarnationDepth, incarnationDepth) || other.incarnationDepth == incarnationDepth)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other.children, children));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,label,state,incarnationDepth,duration,const DeepCollectionEquality().hash(children));

@override
String toString() {
  return 'PipelineNodeView(nodeId: $nodeId, label: $label, state: $state, incarnationDepth: $incarnationDepth, duration: $duration, children: $children)';
}


}

/// @nodoc
abstract mixin class $PipelineNodeViewCopyWith<$Res>  {
  factory $PipelineNodeViewCopyWith(PipelineNodeView value, $Res Function(PipelineNodeView) _then) = _$PipelineNodeViewCopyWithImpl;
@useResult
$Res call({
 String nodeId, String label, StepVisualState state, int incarnationDepth, Duration? duration, List<PipelineNodeView> children
});




}
/// @nodoc
class _$PipelineNodeViewCopyWithImpl<$Res>
    implements $PipelineNodeViewCopyWith<$Res> {
  _$PipelineNodeViewCopyWithImpl(this._self, this._then);

  final PipelineNodeView _self;
  final $Res Function(PipelineNodeView) _then;

/// Create a copy of PipelineNodeView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? label = null,Object? state = null,Object? incarnationDepth = null,Object? duration = freezed,Object? children = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepVisualState,incarnationDepth: null == incarnationDepth ? _self.incarnationDepth : incarnationDepth // ignore: cast_nullable_to_non_nullable
as int,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,children: null == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as List<PipelineNodeView>,
  ));
}

}


/// Adds pattern-matching-related methods to [PipelineNodeView].
extension PipelineNodeViewPatterns on PipelineNodeView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PipelineNodeView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PipelineNodeView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PipelineNodeView value)  $default,){
final _that = this;
switch (_that) {
case _PipelineNodeView():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PipelineNodeView value)?  $default,){
final _that = this;
switch (_that) {
case _PipelineNodeView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String label,  StepVisualState state,  int incarnationDepth,  Duration? duration,  List<PipelineNodeView> children)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PipelineNodeView() when $default != null:
return $default(_that.nodeId,_that.label,_that.state,_that.incarnationDepth,_that.duration,_that.children);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String label,  StepVisualState state,  int incarnationDepth,  Duration? duration,  List<PipelineNodeView> children)  $default,) {final _that = this;
switch (_that) {
case _PipelineNodeView():
return $default(_that.nodeId,_that.label,_that.state,_that.incarnationDepth,_that.duration,_that.children);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String label,  StepVisualState state,  int incarnationDepth,  Duration? duration,  List<PipelineNodeView> children)?  $default,) {final _that = this;
switch (_that) {
case _PipelineNodeView() when $default != null:
return $default(_that.nodeId,_that.label,_that.state,_that.incarnationDepth,_that.duration,_that.children);case _:
  return null;

}
}

}

/// @nodoc


class _PipelineNodeView implements PipelineNodeView {
  const _PipelineNodeView({required this.nodeId, required this.label, required this.state, required this.incarnationDepth, this.duration, required final  List<PipelineNodeView> children}): _children = children;
  

@override final  String nodeId;
@override final  String label;
@override final  StepVisualState state;
@override final  int incarnationDepth;
@override final  Duration? duration;
 final  List<PipelineNodeView> _children;
@override List<PipelineNodeView> get children {
  if (_children is EqualUnmodifiableListView) return _children;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_children);
}


/// Create a copy of PipelineNodeView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PipelineNodeViewCopyWith<_PipelineNodeView> get copyWith => __$PipelineNodeViewCopyWithImpl<_PipelineNodeView>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PipelineNodeView&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.label, label) || other.label == label)&&(identical(other.state, state) || other.state == state)&&(identical(other.incarnationDepth, incarnationDepth) || other.incarnationDepth == incarnationDepth)&&(identical(other.duration, duration) || other.duration == duration)&&const DeepCollectionEquality().equals(other._children, _children));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,label,state,incarnationDepth,duration,const DeepCollectionEquality().hash(_children));

@override
String toString() {
  return 'PipelineNodeView(nodeId: $nodeId, label: $label, state: $state, incarnationDepth: $incarnationDepth, duration: $duration, children: $children)';
}


}

/// @nodoc
abstract mixin class _$PipelineNodeViewCopyWith<$Res> implements $PipelineNodeViewCopyWith<$Res> {
  factory _$PipelineNodeViewCopyWith(_PipelineNodeView value, $Res Function(_PipelineNodeView) _then) = __$PipelineNodeViewCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String label, StepVisualState state, int incarnationDepth, Duration? duration, List<PipelineNodeView> children
});




}
/// @nodoc
class __$PipelineNodeViewCopyWithImpl<$Res>
    implements _$PipelineNodeViewCopyWith<$Res> {
  __$PipelineNodeViewCopyWithImpl(this._self, this._then);

  final _PipelineNodeView _self;
  final $Res Function(_PipelineNodeView) _then;

/// Create a copy of PipelineNodeView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? label = null,Object? state = null,Object? incarnationDepth = null,Object? duration = freezed,Object? children = null,}) {
  return _then(_PipelineNodeView(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepVisualState,incarnationDepth: null == incarnationDepth ? _self.incarnationDepth : incarnationDepth // ignore: cast_nullable_to_non_nullable
as int,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration?,children: null == children ? _self._children : children // ignore: cast_nullable_to_non_nullable
as List<PipelineNodeView>,
  ));
}


}

/// @nodoc
mixin _$PipelineState {

 List<PipelineNodeView> get roots;
/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PipelineStateCopyWith<PipelineState> get copyWith => _$PipelineStateCopyWithImpl<PipelineState>(this as PipelineState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PipelineState&&const DeepCollectionEquality().equals(other.roots, roots));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(roots));

@override
String toString() {
  return 'PipelineState(roots: $roots)';
}


}

/// @nodoc
abstract mixin class $PipelineStateCopyWith<$Res>  {
  factory $PipelineStateCopyWith(PipelineState value, $Res Function(PipelineState) _then) = _$PipelineStateCopyWithImpl;
@useResult
$Res call({
 List<PipelineNodeView> roots
});




}
/// @nodoc
class _$PipelineStateCopyWithImpl<$Res>
    implements $PipelineStateCopyWith<$Res> {
  _$PipelineStateCopyWithImpl(this._self, this._then);

  final PipelineState _self;
  final $Res Function(PipelineState) _then;

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? roots = null,}) {
  return _then(_self.copyWith(
roots: null == roots ? _self.roots : roots // ignore: cast_nullable_to_non_nullable
as List<PipelineNodeView>,
  ));
}

}


/// Adds pattern-matching-related methods to [PipelineState].
extension PipelineStatePatterns on PipelineState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PipelineState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PipelineState value)  $default,){
final _that = this;
switch (_that) {
case _PipelineState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PipelineState value)?  $default,){
final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<PipelineNodeView> roots)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that.roots);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<PipelineNodeView> roots)  $default,) {final _that = this;
switch (_that) {
case _PipelineState():
return $default(_that.roots);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<PipelineNodeView> roots)?  $default,) {final _that = this;
switch (_that) {
case _PipelineState() when $default != null:
return $default(_that.roots);case _:
  return null;

}
}

}

/// @nodoc


class _PipelineState implements PipelineState {
  const _PipelineState({required final  List<PipelineNodeView> roots}): _roots = roots;
  

 final  List<PipelineNodeView> _roots;
@override List<PipelineNodeView> get roots {
  if (_roots is EqualUnmodifiableListView) return _roots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roots);
}


/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PipelineStateCopyWith<_PipelineState> get copyWith => __$PipelineStateCopyWithImpl<_PipelineState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PipelineState&&const DeepCollectionEquality().equals(other._roots, _roots));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_roots));

@override
String toString() {
  return 'PipelineState(roots: $roots)';
}


}

/// @nodoc
abstract mixin class _$PipelineStateCopyWith<$Res> implements $PipelineStateCopyWith<$Res> {
  factory _$PipelineStateCopyWith(_PipelineState value, $Res Function(_PipelineState) _then) = __$PipelineStateCopyWithImpl;
@override @useResult
$Res call({
 List<PipelineNodeView> roots
});




}
/// @nodoc
class __$PipelineStateCopyWithImpl<$Res>
    implements _$PipelineStateCopyWith<$Res> {
  __$PipelineStateCopyWithImpl(this._self, this._then);

  final _PipelineState _self;
  final $Res Function(_PipelineState) _then;

/// Create a copy of PipelineState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? roots = null,}) {
  return _then(_PipelineState(
roots: null == roots ? _self._roots : roots // ignore: cast_nullable_to_non_nullable
as List<PipelineNodeView>,
  ));
}


}

/// @nodoc
mixin _$InspectorState {

 String get nodeId; String get seedType; String? get key; List<PropertyRowModel> get properties;
/// Create a copy of InspectorState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InspectorStateCopyWith<InspectorState> get copyWith => _$InspectorStateCopyWithImpl<InspectorState>(this as InspectorState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InspectorState&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.seedType, seedType) || other.seedType == seedType)&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other.properties, properties));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,seedType,key,const DeepCollectionEquality().hash(properties));

@override
String toString() {
  return 'InspectorState(nodeId: $nodeId, seedType: $seedType, key: $key, properties: $properties)';
}


}

/// @nodoc
abstract mixin class $InspectorStateCopyWith<$Res>  {
  factory $InspectorStateCopyWith(InspectorState value, $Res Function(InspectorState) _then) = _$InspectorStateCopyWithImpl;
@useResult
$Res call({
 String nodeId, String seedType, String? key, List<PropertyRowModel> properties
});




}
/// @nodoc
class _$InspectorStateCopyWithImpl<$Res>
    implements $InspectorStateCopyWith<$Res> {
  _$InspectorStateCopyWithImpl(this._self, this._then);

  final InspectorState _self;
  final $Res Function(InspectorState) _then;

/// Create a copy of InspectorState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? seedType = null,Object? key = freezed,Object? properties = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,seedType: null == seedType ? _self.seedType : seedType // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,properties: null == properties ? _self.properties : properties // ignore: cast_nullable_to_non_nullable
as List<PropertyRowModel>,
  ));
}

}


/// Adds pattern-matching-related methods to [InspectorState].
extension InspectorStatePatterns on InspectorState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InspectorState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InspectorState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InspectorState value)  $default,){
final _that = this;
switch (_that) {
case _InspectorState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InspectorState value)?  $default,){
final _that = this;
switch (_that) {
case _InspectorState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String seedType,  String? key,  List<PropertyRowModel> properties)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InspectorState() when $default != null:
return $default(_that.nodeId,_that.seedType,_that.key,_that.properties);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String seedType,  String? key,  List<PropertyRowModel> properties)  $default,) {final _that = this;
switch (_that) {
case _InspectorState():
return $default(_that.nodeId,_that.seedType,_that.key,_that.properties);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String seedType,  String? key,  List<PropertyRowModel> properties)?  $default,) {final _that = this;
switch (_that) {
case _InspectorState() when $default != null:
return $default(_that.nodeId,_that.seedType,_that.key,_that.properties);case _:
  return null;

}
}

}

/// @nodoc


class _InspectorState implements InspectorState {
  const _InspectorState({required this.nodeId, required this.seedType, this.key, required final  List<PropertyRowModel> properties}): _properties = properties;
  

@override final  String nodeId;
@override final  String seedType;
@override final  String? key;
 final  List<PropertyRowModel> _properties;
@override List<PropertyRowModel> get properties {
  if (_properties is EqualUnmodifiableListView) return _properties;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_properties);
}


/// Create a copy of InspectorState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InspectorStateCopyWith<_InspectorState> get copyWith => __$InspectorStateCopyWithImpl<_InspectorState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _InspectorState&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.seedType, seedType) || other.seedType == seedType)&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other._properties, _properties));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,seedType,key,const DeepCollectionEquality().hash(_properties));

@override
String toString() {
  return 'InspectorState(nodeId: $nodeId, seedType: $seedType, key: $key, properties: $properties)';
}


}

/// @nodoc
abstract mixin class _$InspectorStateCopyWith<$Res> implements $InspectorStateCopyWith<$Res> {
  factory _$InspectorStateCopyWith(_InspectorState value, $Res Function(_InspectorState) _then) = __$InspectorStateCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String seedType, String? key, List<PropertyRowModel> properties
});




}
/// @nodoc
class __$InspectorStateCopyWithImpl<$Res>
    implements _$InspectorStateCopyWith<$Res> {
  __$InspectorStateCopyWithImpl(this._self, this._then);

  final _InspectorState _self;
  final $Res Function(_InspectorState) _then;

/// Create a copy of InspectorState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? seedType = null,Object? key = freezed,Object? properties = null,}) {
  return _then(_InspectorState(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,seedType: null == seedType ? _self.seedType : seedType // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,properties: null == properties ? _self._properties : properties // ignore: cast_nullable_to_non_nullable
as List<PropertyRowModel>,
  ));
}


}

/// @nodoc
mixin _$CostRollupState {

 int? get inputTokens; int? get outputTokens; double? get costUsd; bool get hasData;
/// Create a copy of CostRollupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CostRollupStateCopyWith<CostRollupState> get copyWith => _$CostRollupStateCopyWithImpl<CostRollupState>(this as CostRollupState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CostRollupState&&(identical(other.inputTokens, inputTokens) || other.inputTokens == inputTokens)&&(identical(other.outputTokens, outputTokens) || other.outputTokens == outputTokens)&&(identical(other.costUsd, costUsd) || other.costUsd == costUsd)&&(identical(other.hasData, hasData) || other.hasData == hasData));
}


@override
int get hashCode => Object.hash(runtimeType,inputTokens,outputTokens,costUsd,hasData);

@override
String toString() {
  return 'CostRollupState(inputTokens: $inputTokens, outputTokens: $outputTokens, costUsd: $costUsd, hasData: $hasData)';
}


}

/// @nodoc
abstract mixin class $CostRollupStateCopyWith<$Res>  {
  factory $CostRollupStateCopyWith(CostRollupState value, $Res Function(CostRollupState) _then) = _$CostRollupStateCopyWithImpl;
@useResult
$Res call({
 int? inputTokens, int? outputTokens, double? costUsd, bool hasData
});




}
/// @nodoc
class _$CostRollupStateCopyWithImpl<$Res>
    implements $CostRollupStateCopyWith<$Res> {
  _$CostRollupStateCopyWithImpl(this._self, this._then);

  final CostRollupState _self;
  final $Res Function(CostRollupState) _then;

/// Create a copy of CostRollupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputTokens = freezed,Object? outputTokens = freezed,Object? costUsd = freezed,Object? hasData = null,}) {
  return _then(_self.copyWith(
inputTokens: freezed == inputTokens ? _self.inputTokens : inputTokens // ignore: cast_nullable_to_non_nullable
as int?,outputTokens: freezed == outputTokens ? _self.outputTokens : outputTokens // ignore: cast_nullable_to_non_nullable
as int?,costUsd: freezed == costUsd ? _self.costUsd : costUsd // ignore: cast_nullable_to_non_nullable
as double?,hasData: null == hasData ? _self.hasData : hasData // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [CostRollupState].
extension CostRollupStatePatterns on CostRollupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CostRollupState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CostRollupState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CostRollupState value)  $default,){
final _that = this;
switch (_that) {
case _CostRollupState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CostRollupState value)?  $default,){
final _that = this;
switch (_that) {
case _CostRollupState() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? inputTokens,  int? outputTokens,  double? costUsd,  bool hasData)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CostRollupState() when $default != null:
return $default(_that.inputTokens,_that.outputTokens,_that.costUsd,_that.hasData);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? inputTokens,  int? outputTokens,  double? costUsd,  bool hasData)  $default,) {final _that = this;
switch (_that) {
case _CostRollupState():
return $default(_that.inputTokens,_that.outputTokens,_that.costUsd,_that.hasData);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? inputTokens,  int? outputTokens,  double? costUsd,  bool hasData)?  $default,) {final _that = this;
switch (_that) {
case _CostRollupState() when $default != null:
return $default(_that.inputTokens,_that.outputTokens,_that.costUsd,_that.hasData);case _:
  return null;

}
}

}

/// @nodoc


class _CostRollupState implements CostRollupState {
  const _CostRollupState({this.inputTokens, this.outputTokens, this.costUsd, required this.hasData});
  

@override final  int? inputTokens;
@override final  int? outputTokens;
@override final  double? costUsd;
@override final  bool hasData;

/// Create a copy of CostRollupState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CostRollupStateCopyWith<_CostRollupState> get copyWith => __$CostRollupStateCopyWithImpl<_CostRollupState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CostRollupState&&(identical(other.inputTokens, inputTokens) || other.inputTokens == inputTokens)&&(identical(other.outputTokens, outputTokens) || other.outputTokens == outputTokens)&&(identical(other.costUsd, costUsd) || other.costUsd == costUsd)&&(identical(other.hasData, hasData) || other.hasData == hasData));
}


@override
int get hashCode => Object.hash(runtimeType,inputTokens,outputTokens,costUsd,hasData);

@override
String toString() {
  return 'CostRollupState(inputTokens: $inputTokens, outputTokens: $outputTokens, costUsd: $costUsd, hasData: $hasData)';
}


}

/// @nodoc
abstract mixin class _$CostRollupStateCopyWith<$Res> implements $CostRollupStateCopyWith<$Res> {
  factory _$CostRollupStateCopyWith(_CostRollupState value, $Res Function(_CostRollupState) _then) = __$CostRollupStateCopyWithImpl;
@override @useResult
$Res call({
 int? inputTokens, int? outputTokens, double? costUsd, bool hasData
});




}
/// @nodoc
class __$CostRollupStateCopyWithImpl<$Res>
    implements _$CostRollupStateCopyWith<$Res> {
  __$CostRollupStateCopyWithImpl(this._self, this._then);

  final _CostRollupState _self;
  final $Res Function(_CostRollupState) _then;

/// Create a copy of CostRollupState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inputTokens = freezed,Object? outputTokens = freezed,Object? costUsd = freezed,Object? hasData = null,}) {
  return _then(_CostRollupState(
inputTokens: freezed == inputTokens ? _self.inputTokens : inputTokens // ignore: cast_nullable_to_non_nullable
as int?,outputTokens: freezed == outputTokens ? _self.outputTokens : outputTokens // ignore: cast_nullable_to_non_nullable
as int?,costUsd: freezed == costUsd ? _self.costUsd : costUsd // ignore: cast_nullable_to_non_nullable
as double?,hasData: null == hasData ? _self.hasData : hasData // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
