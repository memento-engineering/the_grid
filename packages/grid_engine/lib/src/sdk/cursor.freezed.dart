// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cursor.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NodeCursor {

/// The node's lifecycle state.
 StepState get state;/// The spawned process-group id (the per-node respawn-or-skip kill target —
/// D-4); null until `SessionStarted`, or when pgid resolution failed.
 int? get pgid;/// The spawned leader pid (diagnostics + the liveness fence for the guarded
/// terminate); null until `SessionStarted`.
 int? get pid;/// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (per node — D-4);
/// null until `SessionStarted`.
 String? get token;/// How many times this node has been supervised-restarted (gates the breaker
/// predicate — D-5).
 int get restartCount;/// The earliest time a failed node may re-key (backoff — D-5); null when not
/// cooling down.
 DateTime? get cooldownUntil;/// The durable log byte-offset for the deferred adopt-a-live-process seam
/// (§11); null until restoration ships.
 int? get logOffset;
/// Create a copy of NodeCursor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodeCursorCopyWith<NodeCursor> get copyWith => _$NodeCursorCopyWithImpl<NodeCursor>(this as NodeCursor, _$identity);

  /// Serializes this NodeCursor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodeCursor&&(identical(other.state, state) || other.state == state)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.pid, pid) || other.pid == pid)&&(identical(other.token, token) || other.token == token)&&(identical(other.restartCount, restartCount) || other.restartCount == restartCount)&&(identical(other.cooldownUntil, cooldownUntil) || other.cooldownUntil == cooldownUntil)&&(identical(other.logOffset, logOffset) || other.logOffset == logOffset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,state,pgid,pid,token,restartCount,cooldownUntil,logOffset);

@override
String toString() {
  return 'NodeCursor(state: $state, pgid: $pgid, pid: $pid, token: $token, restartCount: $restartCount, cooldownUntil: $cooldownUntil, logOffset: $logOffset)';
}


}

/// @nodoc
abstract mixin class $NodeCursorCopyWith<$Res>  {
  factory $NodeCursorCopyWith(NodeCursor value, $Res Function(NodeCursor) _then) = _$NodeCursorCopyWithImpl;
@useResult
$Res call({
 StepState state, int? pgid, int? pid, String? token, int restartCount, DateTime? cooldownUntil, int? logOffset
});




}
/// @nodoc
class _$NodeCursorCopyWithImpl<$Res>
    implements $NodeCursorCopyWith<$Res> {
  _$NodeCursorCopyWithImpl(this._self, this._then);

  final NodeCursor _self;
  final $Res Function(NodeCursor) _then;

/// Create a copy of NodeCursor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? pgid = freezed,Object? pid = freezed,Object? token = freezed,Object? restartCount = null,Object? cooldownUntil = freezed,Object? logOffset = freezed,}) {
  return _then(_self.copyWith(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepState,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,restartCount: null == restartCount ? _self.restartCount : restartCount // ignore: cast_nullable_to_non_nullable
as int,cooldownUntil: freezed == cooldownUntil ? _self.cooldownUntil : cooldownUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,logOffset: freezed == logOffset ? _self.logOffset : logOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [NodeCursor].
extension NodeCursorPatterns on NodeCursor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NodeCursor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NodeCursor value)  $default,){
final _that = this;
switch (_that) {
case _NodeCursor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NodeCursor value)?  $default,){
final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  DateTime? cooldownUntil,  int? logOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.cooldownUntil,_that.logOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  DateTime? cooldownUntil,  int? logOffset)  $default,) {final _that = this;
switch (_that) {
case _NodeCursor():
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.cooldownUntil,_that.logOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  DateTime? cooldownUntil,  int? logOffset)?  $default,) {final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.cooldownUntil,_that.logOffset);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NodeCursor extends NodeCursor {
  const _NodeCursor({this.state = StepState.pending, this.pgid, this.pid, this.token, this.restartCount = 0, this.cooldownUntil, this.logOffset}): super._();
  factory _NodeCursor.fromJson(Map<String, dynamic> json) => _$NodeCursorFromJson(json);

/// The node's lifecycle state.
@override@JsonKey() final  StepState state;
/// The spawned process-group id (the per-node respawn-or-skip kill target —
/// D-4); null until `SessionStarted`, or when pgid resolution failed.
@override final  int? pgid;
/// The spawned leader pid (diagnostics + the liveness fence for the guarded
/// terminate); null until `SessionStarted`.
@override final  int? pid;
/// The engine-minted `GRID_INSTANCE_TOKEN` freshness fence (per node — D-4);
/// null until `SessionStarted`.
@override final  String? token;
/// How many times this node has been supervised-restarted (gates the breaker
/// predicate — D-5).
@override@JsonKey() final  int restartCount;
/// The earliest time a failed node may re-key (backoff — D-5); null when not
/// cooling down.
@override final  DateTime? cooldownUntil;
/// The durable log byte-offset for the deferred adopt-a-live-process seam
/// (§11); null until restoration ships.
@override final  int? logOffset;

/// Create a copy of NodeCursor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NodeCursorCopyWith<_NodeCursor> get copyWith => __$NodeCursorCopyWithImpl<_NodeCursor>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NodeCursorToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodeCursor&&(identical(other.state, state) || other.state == state)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.pid, pid) || other.pid == pid)&&(identical(other.token, token) || other.token == token)&&(identical(other.restartCount, restartCount) || other.restartCount == restartCount)&&(identical(other.cooldownUntil, cooldownUntil) || other.cooldownUntil == cooldownUntil)&&(identical(other.logOffset, logOffset) || other.logOffset == logOffset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,state,pgid,pid,token,restartCount,cooldownUntil,logOffset);

@override
String toString() {
  return 'NodeCursor(state: $state, pgid: $pgid, pid: $pid, token: $token, restartCount: $restartCount, cooldownUntil: $cooldownUntil, logOffset: $logOffset)';
}


}

/// @nodoc
abstract mixin class _$NodeCursorCopyWith<$Res> implements $NodeCursorCopyWith<$Res> {
  factory _$NodeCursorCopyWith(_NodeCursor value, $Res Function(_NodeCursor) _then) = __$NodeCursorCopyWithImpl;
@override @useResult
$Res call({
 StepState state, int? pgid, int? pid, String? token, int restartCount, DateTime? cooldownUntil, int? logOffset
});




}
/// @nodoc
class __$NodeCursorCopyWithImpl<$Res>
    implements _$NodeCursorCopyWith<$Res> {
  __$NodeCursorCopyWithImpl(this._self, this._then);

  final _NodeCursor _self;
  final $Res Function(_NodeCursor) _then;

/// Create a copy of NodeCursor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? pgid = freezed,Object? pid = freezed,Object? token = freezed,Object? restartCount = null,Object? cooldownUntil = freezed,Object? logOffset = freezed,}) {
  return _then(_NodeCursor(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepState,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,restartCount: null == restartCount ? _self.restartCount : restartCount // ignore: cast_nullable_to_non_nullable
as int,cooldownUntil: freezed == cooldownUntil ? _self.cooldownUntil : cooldownUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,logOffset: freezed == logOffset ? _self.logOffset : logOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
