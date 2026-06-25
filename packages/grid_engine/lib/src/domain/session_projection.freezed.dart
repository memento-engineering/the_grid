// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_projection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionProjection {

/// The work bead this session drives (`metadata.work_bead`).
 String get workBeadId;/// The cursor phase (`metadata.grid.phase`): implement | verify | land.
 WorkPhase get phase;/// True once the session reached a positive terminal (the session bead
/// `closed`, or the cursor advanced past `land`). A terminal session means
/// the work node unmounts — never respawns.
 bool get isTerminal;/// The spawned agent's process-group id, stamped at `SessionStarted` for
/// orphan-kill on restart (Track D).
 int? get pgid;/// The engine-minted `GRID_INSTANCE_TOKEN`, stamped at `SessionStarted` —
/// the freshness fence against a stale prior-incarnation completion
/// (Track C/D).
 String? get token;/// The spawned agent's pid (diagnostics).
 int? get pid;
/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<SessionProjection> get copyWith => _$SessionProjectionCopyWithImpl<SessionProjection>(this as SessionProjection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,phase,isTerminal,pgid,token,pid);

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, phase: $phase, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid)';
}


}

/// @nodoc
abstract mixin class $SessionProjectionCopyWith<$Res>  {
  factory $SessionProjectionCopyWith(SessionProjection value, $Res Function(SessionProjection) _then) = _$SessionProjectionCopyWithImpl;
@useResult
$Res call({
 String workBeadId, WorkPhase phase, bool isTerminal, int? pgid, String? token, int? pid
});




}
/// @nodoc
class _$SessionProjectionCopyWithImpl<$Res>
    implements $SessionProjectionCopyWith<$Res> {
  _$SessionProjectionCopyWithImpl(this._self, this._then);

  final SessionProjection _self;
  final $Res Function(SessionProjection) _then;

/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workBeadId = null,Object? phase = null,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,}) {
  return _then(_self.copyWith(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as WorkPhase,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionProjection].
extension SessionProjectionPatterns on SessionProjection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionProjection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionProjection value)  $default,){
final _that = this;
switch (_that) {
case _SessionProjection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionProjection value)?  $default,){
final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String workBeadId,  WorkPhase phase,  bool isTerminal,  int? pgid,  String? token,  int? pid)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.phase,_that.isTerminal,_that.pgid,_that.token,_that.pid);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String workBeadId,  WorkPhase phase,  bool isTerminal,  int? pgid,  String? token,  int? pid)  $default,) {final _that = this;
switch (_that) {
case _SessionProjection():
return $default(_that.workBeadId,_that.phase,_that.isTerminal,_that.pgid,_that.token,_that.pid);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String workBeadId,  WorkPhase phase,  bool isTerminal,  int? pgid,  String? token,  int? pid)?  $default,) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.phase,_that.isTerminal,_that.pgid,_that.token,_that.pid);case _:
  return null;

}
}

}

/// @nodoc


class _SessionProjection implements SessionProjection {
  const _SessionProjection({required this.workBeadId, required this.phase, this.isTerminal = false, this.pgid, this.token, this.pid});
  

/// The work bead this session drives (`metadata.work_bead`).
@override final  String workBeadId;
/// The cursor phase (`metadata.grid.phase`): implement | verify | land.
@override final  WorkPhase phase;
/// True once the session reached a positive terminal (the session bead
/// `closed`, or the cursor advanced past `land`). A terminal session means
/// the work node unmounts — never respawns.
@override@JsonKey() final  bool isTerminal;
/// The spawned agent's process-group id, stamped at `SessionStarted` for
/// orphan-kill on restart (Track D).
@override final  int? pgid;
/// The engine-minted `GRID_INSTANCE_TOKEN`, stamped at `SessionStarted` —
/// the freshness fence against a stale prior-incarnation completion
/// (Track C/D).
@override final  String? token;
/// The spawned agent's pid (diagnostics).
@override final  int? pid;

/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionProjectionCopyWith<_SessionProjection> get copyWith => __$SessionProjectionCopyWithImpl<_SessionProjection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,phase,isTerminal,pgid,token,pid);

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, phase: $phase, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid)';
}


}

/// @nodoc
abstract mixin class _$SessionProjectionCopyWith<$Res> implements $SessionProjectionCopyWith<$Res> {
  factory _$SessionProjectionCopyWith(_SessionProjection value, $Res Function(_SessionProjection) _then) = __$SessionProjectionCopyWithImpl;
@override @useResult
$Res call({
 String workBeadId, WorkPhase phase, bool isTerminal, int? pgid, String? token, int? pid
});




}
/// @nodoc
class __$SessionProjectionCopyWithImpl<$Res>
    implements _$SessionProjectionCopyWith<$Res> {
  __$SessionProjectionCopyWithImpl(this._self, this._then);

  final _SessionProjection _self;
  final $Res Function(_SessionProjection) _then;

/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workBeadId = null,Object? phase = null,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,}) {
  return _then(_SessionProjection(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as WorkPhase,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
