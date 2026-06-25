// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'rig_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RigConfig {

/// The rig's id (its issue-id prefix and `metadata.rig` marker).
 String get rigId;/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
 Set<String> get ownedRigs;
/// Create a copy of RigConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RigConfigCopyWith<RigConfig> get copyWith => _$RigConfigCopyWithImpl<RigConfig>(this as RigConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RigConfig&&(identical(other.rigId, rigId) || other.rigId == rigId)&&const DeepCollectionEquality().equals(other.ownedRigs, ownedRigs));
}


@override
int get hashCode => Object.hash(runtimeType,rigId,const DeepCollectionEquality().hash(ownedRigs));

@override
String toString() {
  return 'RigConfig(rigId: $rigId, ownedRigs: $ownedRigs)';
}


}

/// @nodoc
abstract mixin class $RigConfigCopyWith<$Res>  {
  factory $RigConfigCopyWith(RigConfig value, $Res Function(RigConfig) _then) = _$RigConfigCopyWithImpl;
@useResult
$Res call({
 String rigId, Set<String> ownedRigs
});




}
/// @nodoc
class _$RigConfigCopyWithImpl<$Res>
    implements $RigConfigCopyWith<$Res> {
  _$RigConfigCopyWithImpl(this._self, this._then);

  final RigConfig _self;
  final $Res Function(RigConfig) _then;

/// Create a copy of RigConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? rigId = null,Object? ownedRigs = null,}) {
  return _then(_self.copyWith(
rigId: null == rigId ? _self.rigId : rigId // ignore: cast_nullable_to_non_nullable
as String,ownedRigs: null == ownedRigs ? _self.ownedRigs : ownedRigs // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [RigConfig].
extension RigConfigPatterns on RigConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RigConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RigConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RigConfig value)  $default,){
final _that = this;
switch (_that) {
case _RigConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RigConfig value)?  $default,){
final _that = this;
switch (_that) {
case _RigConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String rigId,  Set<String> ownedRigs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RigConfig() when $default != null:
return $default(_that.rigId,_that.ownedRigs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String rigId,  Set<String> ownedRigs)  $default,) {final _that = this;
switch (_that) {
case _RigConfig():
return $default(_that.rigId,_that.ownedRigs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String rigId,  Set<String> ownedRigs)?  $default,) {final _that = this;
switch (_that) {
case _RigConfig() when $default != null:
return $default(_that.rigId,_that.ownedRigs);case _:
  return null;

}
}

}

/// @nodoc


class _RigConfig implements RigConfig {
  const _RigConfig({required this.rigId, final  Set<String> ownedRigs = const <String>{}}): _ownedRigs = ownedRigs;
  

/// The rig's id (its issue-id prefix and `metadata.rig` marker).
@override final  String rigId;
/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
 final  Set<String> _ownedRigs;
/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
@override@JsonKey() Set<String> get ownedRigs {
  if (_ownedRigs is EqualUnmodifiableSetView) return _ownedRigs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_ownedRigs);
}


/// Create a copy of RigConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RigConfigCopyWith<_RigConfig> get copyWith => __$RigConfigCopyWithImpl<_RigConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RigConfig&&(identical(other.rigId, rigId) || other.rigId == rigId)&&const DeepCollectionEquality().equals(other._ownedRigs, _ownedRigs));
}


@override
int get hashCode => Object.hash(runtimeType,rigId,const DeepCollectionEquality().hash(_ownedRigs));

@override
String toString() {
  return 'RigConfig(rigId: $rigId, ownedRigs: $ownedRigs)';
}


}

/// @nodoc
abstract mixin class _$RigConfigCopyWith<$Res> implements $RigConfigCopyWith<$Res> {
  factory _$RigConfigCopyWith(_RigConfig value, $Res Function(_RigConfig) _then) = __$RigConfigCopyWithImpl;
@override @useResult
$Res call({
 String rigId, Set<String> ownedRigs
});




}
/// @nodoc
class __$RigConfigCopyWithImpl<$Res>
    implements _$RigConfigCopyWith<$Res> {
  __$RigConfigCopyWithImpl(this._self, this._then);

  final _RigConfig _self;
  final $Res Function(_RigConfig) _then;

/// Create a copy of RigConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? rigId = null,Object? ownedRigs = null,}) {
  return _then(_RigConfig(
rigId: null == rigId ? _self.rigId : rigId // ignore: cast_nullable_to_non_nullable
as String,ownedRigs: null == ownedRigs ? _self._ownedRigs : ownedRigs // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}


}

// dart format on
