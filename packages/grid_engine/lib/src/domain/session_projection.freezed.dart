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
 String get workBeadId;/// The session/lifecycle bead's OWN id in the state store — the target the
/// capability hosts advance the cursor on (injected pull-free so a host
/// never re-queries the store; A39). Null only in synthetic/test
/// projections — the join bridge always populates it.
 String? get sessionId;/// True once the session reached a positive terminal (the session bead
/// `closed`, or the cursor advanced past `land`). A terminal session means
/// the work node unmounts — never respawns.
 bool get isTerminal;/// The spawned agent's process-group id, stamped at `SessionStarted` for
/// orphan-kill on restart (Track D).
 int? get pgid;/// The engine-minted `GRID_INSTANCE_TOKEN`, stamped at `SessionStarted` —
/// the freshness fence against a stale prior-incarnation completion
/// (Track C/D).
 String? get token;/// The spawned agent's pid (diagnostics).
 int? get pid;/// The per-node reentrant cursor (ADR-0008 D4 / D-3) — every inflated
/// node's [NodeCursor] keyed by its `nodePath`, projected from the session
/// bead's `grid.cursor.*` metadata and threaded down to `FormulaScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root formula's frontier mounts from `pending`).
 FormulaCursor get cursor;
/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<SessionProjection> get copyWith => _$SessionProjectionCopyWithImpl<SessionProjection>(this as SessionProjection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid)&&const DeepCollectionEquality().equals(other.cursor, cursor));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,sessionId,isTerminal,pgid,token,pid,const DeepCollectionEquality().hash(cursor));

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, sessionId: $sessionId, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid, cursor: $cursor)';
}


}

/// @nodoc
abstract mixin class $SessionProjectionCopyWith<$Res>  {
  factory $SessionProjectionCopyWith(SessionProjection value, $Res Function(SessionProjection) _then) = _$SessionProjectionCopyWithImpl;
@useResult
$Res call({
 String workBeadId, String? sessionId, bool isTerminal, int? pgid, String? token, int? pid, FormulaCursor cursor
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
@pragma('vm:prefer-inline') @override $Res call({Object? workBeadId = null,Object? sessionId = freezed,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,Object? cursor = null,}) {
  return _then(_self.copyWith(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as FormulaCursor,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  FormulaCursor cursor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  FormulaCursor cursor)  $default,) {final _that = this;
switch (_that) {
case _SessionProjection():
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  FormulaCursor cursor)?  $default,) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor);case _:
  return null;

}
}

}

/// @nodoc


class _SessionProjection implements SessionProjection {
  const _SessionProjection({required this.workBeadId, this.sessionId, this.isTerminal = false, this.pgid, this.token, this.pid, final  FormulaCursor cursor = const <String, NodeCursor>{}}): _cursor = cursor;
  

/// The work bead this session drives (`metadata.work_bead`).
@override final  String workBeadId;
/// The session/lifecycle bead's OWN id in the state store — the target the
/// capability hosts advance the cursor on (injected pull-free so a host
/// never re-queries the store; A39). Null only in synthetic/test
/// projections — the join bridge always populates it.
@override final  String? sessionId;
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
/// The per-node reentrant cursor (ADR-0008 D4 / D-3) — every inflated
/// node's [NodeCursor] keyed by its `nodePath`, projected from the session
/// bead's `grid.cursor.*` metadata and threaded down to `FormulaScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root formula's frontier mounts from `pending`).
 final  FormulaCursor _cursor;
/// The per-node reentrant cursor (ADR-0008 D4 / D-3) — every inflated
/// node's [NodeCursor] keyed by its `nodePath`, projected from the session
/// bead's `grid.cursor.*` metadata and threaded down to `FormulaScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root formula's frontier mounts from `pending`).
@override@JsonKey() FormulaCursor get cursor {
  if (_cursor is EqualUnmodifiableMapView) return _cursor;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_cursor);
}


/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionProjectionCopyWith<_SessionProjection> get copyWith => __$SessionProjectionCopyWithImpl<_SessionProjection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid)&&const DeepCollectionEquality().equals(other._cursor, _cursor));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,sessionId,isTerminal,pgid,token,pid,const DeepCollectionEquality().hash(_cursor));

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, sessionId: $sessionId, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid, cursor: $cursor)';
}


}

/// @nodoc
abstract mixin class _$SessionProjectionCopyWith<$Res> implements $SessionProjectionCopyWith<$Res> {
  factory _$SessionProjectionCopyWith(_SessionProjection value, $Res Function(_SessionProjection) _then) = __$SessionProjectionCopyWithImpl;
@override @useResult
$Res call({
 String workBeadId, String? sessionId, bool isTerminal, int? pgid, String? token, int? pid, FormulaCursor cursor
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
@override @pragma('vm:prefer-inline') $Res call({Object? workBeadId = null,Object? sessionId = freezed,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,Object? cursor = null,}) {
  return _then(_SessionProjection(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,cursor: null == cursor ? _self._cursor : cursor // ignore: cast_nullable_to_non_nullable
as FormulaCursor,
  ));
}


}

// dart format on
