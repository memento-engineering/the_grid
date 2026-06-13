// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'convergence_metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConvergenceMetadataFailure {

/// The metadata key that failed to decode.
 String get key;/// The offending raw value, preserved verbatim.
 Object? get rawValue;/// Human-readable reason.
 String get reason;
/// Create a copy of ConvergenceMetadataFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConvergenceMetadataFailureCopyWith<ConvergenceMetadataFailure> get copyWith => _$ConvergenceMetadataFailureCopyWithImpl<ConvergenceMetadataFailure>(this as ConvergenceMetadataFailure, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConvergenceMetadataFailure&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other.rawValue, rawValue)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,key,const DeepCollectionEquality().hash(rawValue),reason);



}

/// @nodoc
abstract mixin class $ConvergenceMetadataFailureCopyWith<$Res>  {
  factory $ConvergenceMetadataFailureCopyWith(ConvergenceMetadataFailure value, $Res Function(ConvergenceMetadataFailure) _then) = _$ConvergenceMetadataFailureCopyWithImpl;
@useResult
$Res call({
 String key, Object? rawValue, String reason
});




}
/// @nodoc
class _$ConvergenceMetadataFailureCopyWithImpl<$Res>
    implements $ConvergenceMetadataFailureCopyWith<$Res> {
  _$ConvergenceMetadataFailureCopyWithImpl(this._self, this._then);

  final ConvergenceMetadataFailure _self;
  final $Res Function(ConvergenceMetadataFailure) _then;

/// Create a copy of ConvergenceMetadataFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? rawValue = freezed,Object? reason = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,rawValue: freezed == rawValue ? _self.rawValue : rawValue ,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ConvergenceMetadataFailure].
extension ConvergenceMetadataFailurePatterns on ConvergenceMetadataFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConvergenceMetadataFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConvergenceMetadataFailure value)  $default,){
final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConvergenceMetadataFailure value)?  $default,){
final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  Object? rawValue,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure() when $default != null:
return $default(_that.key,_that.rawValue,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  Object? rawValue,  String reason)  $default,) {final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure():
return $default(_that.key,_that.rawValue,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  Object? rawValue,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _ConvergenceMetadataFailure() when $default != null:
return $default(_that.key,_that.rawValue,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _ConvergenceMetadataFailure extends ConvergenceMetadataFailure {
  const _ConvergenceMetadataFailure({required this.key, required this.rawValue, required this.reason}): super._();
  

/// The metadata key that failed to decode.
@override final  String key;
/// The offending raw value, preserved verbatim.
@override final  Object? rawValue;
/// Human-readable reason.
@override final  String reason;

/// Create a copy of ConvergenceMetadataFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConvergenceMetadataFailureCopyWith<_ConvergenceMetadataFailure> get copyWith => __$ConvergenceMetadataFailureCopyWithImpl<_ConvergenceMetadataFailure>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConvergenceMetadataFailure&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other.rawValue, rawValue)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,key,const DeepCollectionEquality().hash(rawValue),reason);



}

/// @nodoc
abstract mixin class _$ConvergenceMetadataFailureCopyWith<$Res> implements $ConvergenceMetadataFailureCopyWith<$Res> {
  factory _$ConvergenceMetadataFailureCopyWith(_ConvergenceMetadataFailure value, $Res Function(_ConvergenceMetadataFailure) _then) = __$ConvergenceMetadataFailureCopyWithImpl;
@override @useResult
$Res call({
 String key, Object? rawValue, String reason
});




}
/// @nodoc
class __$ConvergenceMetadataFailureCopyWithImpl<$Res>
    implements _$ConvergenceMetadataFailureCopyWith<$Res> {
  __$ConvergenceMetadataFailureCopyWithImpl(this._self, this._then);

  final _ConvergenceMetadataFailure _self;
  final $Res Function(_ConvergenceMetadataFailure) _then;

/// Create a copy of ConvergenceMetadataFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? rawValue = freezed,Object? reason = null,}) {
  return _then(_ConvergenceMetadataFailure(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,rawValue: freezed == rawValue ? _self.rawValue : rawValue ,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ConvergenceMetadata {

 Map<String, dynamic> get raw;
/// Create a copy of ConvergenceMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConvergenceMetadataCopyWith<ConvergenceMetadata> get copyWith => _$ConvergenceMetadataCopyWithImpl<ConvergenceMetadata>(this as ConvergenceMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConvergenceMetadata&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'ConvergenceMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $ConvergenceMetadataCopyWith<$Res>  {
  factory $ConvergenceMetadataCopyWith(ConvergenceMetadata value, $Res Function(ConvergenceMetadata) _then) = _$ConvergenceMetadataCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$ConvergenceMetadataCopyWithImpl<$Res>
    implements $ConvergenceMetadataCopyWith<$Res> {
  _$ConvergenceMetadataCopyWithImpl(this._self, this._then);

  final ConvergenceMetadata _self;
  final $Res Function(ConvergenceMetadata) _then;

/// Create a copy of ConvergenceMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [ConvergenceMetadata].
extension ConvergenceMetadataPatterns on ConvergenceMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConvergenceMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConvergenceMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConvergenceMetadata value)  $default,){
final _that = this;
switch (_that) {
case _ConvergenceMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConvergenceMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _ConvergenceMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConvergenceMetadata() when $default != null:
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _ConvergenceMetadata():
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _ConvergenceMetadata() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _ConvergenceMetadata extends ConvergenceMetadata {
  const _ConvergenceMetadata({final  Map<String, dynamic> raw = const <String, dynamic>{}}): _raw = raw,super._();
  

 final  Map<String, dynamic> _raw;
@override@JsonKey() Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of ConvergenceMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConvergenceMetadataCopyWith<_ConvergenceMetadata> get copyWith => __$ConvergenceMetadataCopyWithImpl<_ConvergenceMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConvergenceMetadata&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'ConvergenceMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$ConvergenceMetadataCopyWith<$Res> implements $ConvergenceMetadataCopyWith<$Res> {
  factory _$ConvergenceMetadataCopyWith(_ConvergenceMetadata value, $Res Function(_ConvergenceMetadata) _then) = __$ConvergenceMetadataCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$ConvergenceMetadataCopyWithImpl<$Res>
    implements _$ConvergenceMetadataCopyWith<$Res> {
  __$ConvergenceMetadataCopyWithImpl(this._self, this._then);

  final _ConvergenceMetadata _self;
  final $Res Function(_ConvergenceMetadata) _then;

/// Create a copy of ConvergenceMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_ConvergenceMetadata(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on
