// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mdns_station_discovery.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StationChoice {

/// The advertised station identifier.
 String get station;/// The normalized control-door `host:port`, or null when unavailable.
 String? get controlDoor;
/// Create a copy of StationChoice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StationChoiceCopyWith<StationChoice> get copyWith => _$StationChoiceCopyWithImpl<StationChoice>(this as StationChoice, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationChoice&&(identical(other.station, station) || other.station == station)&&(identical(other.controlDoor, controlDoor) || other.controlDoor == controlDoor));
}


@override
int get hashCode => Object.hash(runtimeType,station,controlDoor);

@override
String toString() {
  return 'StationChoice(station: $station, controlDoor: $controlDoor)';
}


}

/// @nodoc
abstract mixin class $StationChoiceCopyWith<$Res>  {
  factory $StationChoiceCopyWith(StationChoice value, $Res Function(StationChoice) _then) = _$StationChoiceCopyWithImpl;
@useResult
$Res call({
 String station, String? controlDoor
});




}
/// @nodoc
class _$StationChoiceCopyWithImpl<$Res>
    implements $StationChoiceCopyWith<$Res> {
  _$StationChoiceCopyWithImpl(this._self, this._then);

  final StationChoice _self;
  final $Res Function(StationChoice) _then;

/// Create a copy of StationChoice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? station = null,Object? controlDoor = freezed,}) {
  return _then(_self.copyWith(
station: null == station ? _self.station : station // ignore: cast_nullable_to_non_nullable
as String,controlDoor: freezed == controlDoor ? _self.controlDoor : controlDoor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [StationChoice].
extension StationChoicePatterns on StationChoice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StationChoice value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StationChoice() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StationChoice value)  $default,){
final _that = this;
switch (_that) {
case _StationChoice():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StationChoice value)?  $default,){
final _that = this;
switch (_that) {
case _StationChoice() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String station,  String? controlDoor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StationChoice() when $default != null:
return $default(_that.station,_that.controlDoor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String station,  String? controlDoor)  $default,) {final _that = this;
switch (_that) {
case _StationChoice():
return $default(_that.station,_that.controlDoor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String station,  String? controlDoor)?  $default,) {final _that = this;
switch (_that) {
case _StationChoice() when $default != null:
return $default(_that.station,_that.controlDoor);case _:
  return null;

}
}

}

/// @nodoc


class _StationChoice extends StationChoice {
  const _StationChoice({required this.station, required this.controlDoor}): super._();


/// The advertised station identifier.
@override final  String station;
/// The normalized control-door `host:port`, or null when unavailable.
@override final  String? controlDoor;

/// Create a copy of StationChoice
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StationChoiceCopyWith<_StationChoice> get copyWith => __$StationChoiceCopyWithImpl<_StationChoice>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StationChoice&&(identical(other.station, station) || other.station == station)&&(identical(other.controlDoor, controlDoor) || other.controlDoor == controlDoor));
}


@override
int get hashCode => Object.hash(runtimeType,station,controlDoor);

@override
String toString() {
  return 'StationChoice(station: $station, controlDoor: $controlDoor)';
}


}

/// @nodoc
abstract mixin class _$StationChoiceCopyWith<$Res> implements $StationChoiceCopyWith<$Res> {
  factory _$StationChoiceCopyWith(_StationChoice value, $Res Function(_StationChoice) _then) = __$StationChoiceCopyWithImpl;
@override @useResult
$Res call({
 String station, String? controlDoor
});




}
/// @nodoc
class __$StationChoiceCopyWithImpl<$Res>
    implements _$StationChoiceCopyWith<$Res> {
  __$StationChoiceCopyWithImpl(this._self, this._then);

  final _StationChoice _self;
  final $Res Function(_StationChoice) _then;

/// Create a copy of StationChoice
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? station = null,Object? controlDoor = freezed,}) {
  return _then(_StationChoice(
station: null == station ? _self.station : station // ignore: cast_nullable_to_non_nullable
as String,controlDoor: freezed == controlDoor ? _self.controlDoor : controlDoor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
