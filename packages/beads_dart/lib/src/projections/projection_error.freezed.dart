// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'projection_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProjectionError {

/// The bead the projector was decoding.
 String get beadId;/// The bead's issue type wire string (for context in diagnostics).
 String get issueType;/// The projection that was attempted (e.g. `AgentSession`, `Molecule`).
 String get projection;/// Human-readable reason the decode failed.
 String get reason;
/// Create a copy of ProjectionError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectionErrorCopyWith<ProjectionError> get copyWith => _$ProjectionErrorCopyWithImpl<ProjectionError>(this as ProjectionError, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectionError&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.issueType, issueType) || other.issueType == issueType)&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,issueType,projection,reason);



}

/// @nodoc
abstract mixin class $ProjectionErrorCopyWith<$Res>  {
  factory $ProjectionErrorCopyWith(ProjectionError value, $Res Function(ProjectionError) _then) = _$ProjectionErrorCopyWithImpl;
@useResult
$Res call({
 String beadId, String issueType, String projection, String reason
});




}
/// @nodoc
class _$ProjectionErrorCopyWithImpl<$Res>
    implements $ProjectionErrorCopyWith<$Res> {
  _$ProjectionErrorCopyWithImpl(this._self, this._then);

  final ProjectionError _self;
  final $Res Function(ProjectionError) _then;

/// Create a copy of ProjectionError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? beadId = null,Object? issueType = null,Object? projection = null,Object? reason = null,}) {
  return _then(_self.copyWith(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,issueType: null == issueType ? _self.issueType : issueType // ignore: cast_nullable_to_non_nullable
as String,projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProjectionError].
extension ProjectionErrorPatterns on ProjectionError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectionError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectionError() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectionError value)  $default,){
final _that = this;
switch (_that) {
case _ProjectionError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectionError value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectionError() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String beadId,  String issueType,  String projection,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectionError() when $default != null:
return $default(_that.beadId,_that.issueType,_that.projection,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String beadId,  String issueType,  String projection,  String reason)  $default,) {final _that = this;
switch (_that) {
case _ProjectionError():
return $default(_that.beadId,_that.issueType,_that.projection,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String beadId,  String issueType,  String projection,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _ProjectionError() when $default != null:
return $default(_that.beadId,_that.issueType,_that.projection,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectionError extends ProjectionError {
  const _ProjectionError({required this.beadId, required this.issueType, required this.projection, required this.reason}): super._();
  

/// The bead the projector was decoding.
@override final  String beadId;
/// The bead's issue type wire string (for context in diagnostics).
@override final  String issueType;
/// The projection that was attempted (e.g. `AgentSession`, `Molecule`).
@override final  String projection;
/// Human-readable reason the decode failed.
@override final  String reason;

/// Create a copy of ProjectionError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectionErrorCopyWith<_ProjectionError> get copyWith => __$ProjectionErrorCopyWithImpl<_ProjectionError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectionError&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.issueType, issueType) || other.issueType == issueType)&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,issueType,projection,reason);



}

/// @nodoc
abstract mixin class _$ProjectionErrorCopyWith<$Res> implements $ProjectionErrorCopyWith<$Res> {
  factory _$ProjectionErrorCopyWith(_ProjectionError value, $Res Function(_ProjectionError) _then) = __$ProjectionErrorCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String issueType, String projection, String reason
});




}
/// @nodoc
class __$ProjectionErrorCopyWithImpl<$Res>
    implements _$ProjectionErrorCopyWith<$Res> {
  __$ProjectionErrorCopyWithImpl(this._self, this._then);

  final _ProjectionError _self;
  final $Res Function(_ProjectionError) _then;

/// Create a copy of ProjectionError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? issueType = null,Object? projection = null,Object? reason = null,}) {
  return _then(_ProjectionError(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,issueType: null == issueType ? _self.issueType : issueType // ignore: cast_nullable_to_non_nullable
as String,projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
