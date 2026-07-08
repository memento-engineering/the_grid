// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GridConfiguration {

 Map<String, Object?> get settings;
/// Create a copy of GridConfiguration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridConfigurationCopyWith<GridConfiguration> get copyWith => _$GridConfigurationCopyWithImpl<GridConfiguration>(this as GridConfiguration, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridConfiguration&&const DeepCollectionEquality().equals(other.settings, settings));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(settings));

@override
String toString() {
  return 'GridConfiguration(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $GridConfigurationCopyWith<$Res>  {
  factory $GridConfigurationCopyWith(GridConfiguration value, $Res Function(GridConfiguration) _then) = _$GridConfigurationCopyWithImpl;
@useResult
$Res call({
 Map<String, Object?> settings
});




}
/// @nodoc
class _$GridConfigurationCopyWithImpl<$Res>
    implements $GridConfigurationCopyWith<$Res> {
  _$GridConfigurationCopyWithImpl(this._self, this._then);

  final GridConfiguration _self;
  final $Res Function(GridConfiguration) _then;

/// Create a copy of GridConfiguration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? settings = null,}) {
  return _then(_self.copyWith(
settings: null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,
  ));
}

}


/// Adds pattern-matching-related methods to [GridConfiguration].
extension GridConfigurationPatterns on GridConfiguration {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GridConfiguration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GridConfiguration() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GridConfiguration value)  $default,){
final _that = this;
switch (_that) {
case _GridConfiguration():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GridConfiguration value)?  $default,){
final _that = this;
switch (_that) {
case _GridConfiguration() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, Object?> settings)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GridConfiguration() when $default != null:
return $default(_that.settings);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, Object?> settings)  $default,) {final _that = this;
switch (_that) {
case _GridConfiguration():
return $default(_that.settings);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, Object?> settings)?  $default,) {final _that = this;
switch (_that) {
case _GridConfiguration() when $default != null:
return $default(_that.settings);case _:
  return null;

}
}

}

/// @nodoc


class _GridConfiguration extends GridConfiguration {
  const _GridConfiguration({final  Map<String, Object?> settings = const <String, Object?>{}}): _settings = settings,super._();
  

 final  Map<String, Object?> _settings;
@override@JsonKey() Map<String, Object?> get settings {
  if (_settings is EqualUnmodifiableMapView) return _settings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_settings);
}


/// Create a copy of GridConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GridConfigurationCopyWith<_GridConfiguration> get copyWith => __$GridConfigurationCopyWithImpl<_GridConfiguration>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GridConfiguration&&const DeepCollectionEquality().equals(other._settings, _settings));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_settings));

@override
String toString() {
  return 'GridConfiguration(settings: $settings)';
}


}

/// @nodoc
abstract mixin class _$GridConfigurationCopyWith<$Res> implements $GridConfigurationCopyWith<$Res> {
  factory _$GridConfigurationCopyWith(_GridConfiguration value, $Res Function(_GridConfiguration) _then) = __$GridConfigurationCopyWithImpl;
@override @useResult
$Res call({
 Map<String, Object?> settings
});




}
/// @nodoc
class __$GridConfigurationCopyWithImpl<$Res>
    implements _$GridConfigurationCopyWith<$Res> {
  __$GridConfigurationCopyWithImpl(this._self, this._then);

  final _GridConfiguration _self;
  final $Res Function(_GridConfiguration) _then;

/// Create a copy of GridConfiguration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settings = null,}) {
  return _then(_GridConfiguration(
settings: null == settings ? _self._settings : settings // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,
  ));
}


}

// dart format on
