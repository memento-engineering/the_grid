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
/// bead's `grid.cursor.*` metadata and threaded down to `CircuitScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root circuit's frontier mounts from `pending`).
 CircuitCursor get cursor;/// The per-node `grid.result.*` payloads, threaded down pull-free so a
/// `route` step reads its siblings' grades — D-5. Keyed by `nodePath`; empty
/// until a step records a result.
 Map<String, Map<String, String>> get results;/// The OPEN `type=gate` beads blocking this session (D-7), keyed by the
/// parked `nodePath` — scanned from the state snapshot by the join bridge,
/// not from this session bead. A node leaves this map when its gate bead
/// closes, which re-arms the parked node (`SessionScope` flips it back to
/// `pending`). Each entry carries the gate bead's OWN id + reason, so
/// `SessionScope` can BOTH decide whether the park is machine-actionable AND
/// close that exact bead through the chokepoint (tg-b3k) — pull-free (A39):
/// a tree node never re-queries the store.
 Map<String, OpenGate> get openGates;/// The highest REWORK round already retired for this work bead (0 = none) —
/// computed by the join bridge off every session's `work_bead` key
/// (`<workBeadId>#r<N>`). The auto-respec transition mints round
/// `reworkRounds + 1` and refuses at `kMaxReworkRounds` (tg-b3k).
 int get reworkRounds;/// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the wall-clock
/// instant the session bead was minted (its `started_at` metadata, stamped
/// once at first spawn through the chokepoint); null for a legacy bead minted
/// before the stamp shipped. Never gates orchestration.
 DateTime? get startedAt;/// Capture-only session lifecycle telemetry — the wall-clock instant the
/// session bead was closed (its `closed_at` metadata, stamped inside the
/// chokepoint's `close`); null while the session is still open.
 DateTime? get closedAt;
/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<SessionProjection> get copyWith => _$SessionProjectionCopyWithImpl<SessionProjection>(this as SessionProjection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid)&&const DeepCollectionEquality().equals(other.cursor, cursor)&&const DeepCollectionEquality().equals(other.results, results)&&const DeepCollectionEquality().equals(other.openGates, openGates)&&(identical(other.reworkRounds, reworkRounds) || other.reworkRounds == reworkRounds)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,sessionId,isTerminal,pgid,token,pid,const DeepCollectionEquality().hash(cursor),const DeepCollectionEquality().hash(results),const DeepCollectionEquality().hash(openGates),reworkRounds,startedAt,closedAt);

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, sessionId: $sessionId, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid, cursor: $cursor, results: $results, openGates: $openGates, reworkRounds: $reworkRounds, startedAt: $startedAt, closedAt: $closedAt)';
}


}

/// @nodoc
abstract mixin class $SessionProjectionCopyWith<$Res>  {
  factory $SessionProjectionCopyWith(SessionProjection value, $Res Function(SessionProjection) _then) = _$SessionProjectionCopyWithImpl;
@useResult
$Res call({
 String workBeadId, String? sessionId, bool isTerminal, int? pgid, String? token, int? pid, CircuitCursor cursor, Map<String, Map<String, String>> results, Map<String, OpenGate> openGates, int reworkRounds, DateTime? startedAt, DateTime? closedAt
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
@pragma('vm:prefer-inline') @override $Res call({Object? workBeadId = null,Object? sessionId = freezed,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,Object? cursor = null,Object? results = null,Object? openGates = null,Object? reworkRounds = null,Object? startedAt = freezed,Object? closedAt = freezed,}) {
  return _then(_self.copyWith(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as CircuitCursor,results: null == results ? _self.results : results // ignore: cast_nullable_to_non_nullable
as Map<String, Map<String, String>>,openGates: null == openGates ? _self.openGates : openGates // ignore: cast_nullable_to_non_nullable
as Map<String, OpenGate>,reworkRounds: null == reworkRounds ? _self.reworkRounds : reworkRounds // ignore: cast_nullable_to_non_nullable
as int,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  CircuitCursor cursor,  Map<String, Map<String, String>> results,  Map<String, OpenGate> openGates,  int reworkRounds,  DateTime? startedAt,  DateTime? closedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor,_that.results,_that.openGates,_that.reworkRounds,_that.startedAt,_that.closedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  CircuitCursor cursor,  Map<String, Map<String, String>> results,  Map<String, OpenGate> openGates,  int reworkRounds,  DateTime? startedAt,  DateTime? closedAt)  $default,) {final _that = this;
switch (_that) {
case _SessionProjection():
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor,_that.results,_that.openGates,_that.reworkRounds,_that.startedAt,_that.closedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String workBeadId,  String? sessionId,  bool isTerminal,  int? pgid,  String? token,  int? pid,  CircuitCursor cursor,  Map<String, Map<String, String>> results,  Map<String, OpenGate> openGates,  int reworkRounds,  DateTime? startedAt,  DateTime? closedAt)?  $default,) {final _that = this;
switch (_that) {
case _SessionProjection() when $default != null:
return $default(_that.workBeadId,_that.sessionId,_that.isTerminal,_that.pgid,_that.token,_that.pid,_that.cursor,_that.results,_that.openGates,_that.reworkRounds,_that.startedAt,_that.closedAt);case _:
  return null;

}
}

}

/// @nodoc


class _SessionProjection extends SessionProjection {
  const _SessionProjection({required this.workBeadId, this.sessionId, this.isTerminal = false, this.pgid, this.token, this.pid, final  CircuitCursor cursor = const <String, NodeCursor>{}, final  Map<String, Map<String, String>> results = const <String, Map<String, String>>{}, final  Map<String, OpenGate> openGates = const <String, OpenGate>{}, this.reworkRounds = 0, this.startedAt, this.closedAt}): _cursor = cursor,_results = results,_openGates = openGates,super._();
  

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
/// bead's `grid.cursor.*` metadata and threaded down to `CircuitScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root circuit's frontier mounts from `pending`).
 final  CircuitCursor _cursor;
/// The per-node reentrant cursor (ADR-0008 D4 / D-3) — every inflated
/// node's [NodeCursor] keyed by its `nodePath`, projected from the session
/// bead's `grid.cursor.*` metadata and threaded down to `CircuitScope`
/// pull-free (A39). Empty for a freshly-minted session (no node has written
/// its cursor yet — the root circuit's frontier mounts from `pending`).
@override@JsonKey() CircuitCursor get cursor {
  if (_cursor is EqualUnmodifiableMapView) return _cursor;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_cursor);
}

/// The per-node `grid.result.*` payloads, threaded down pull-free so a
/// `route` step reads its siblings' grades — D-5. Keyed by `nodePath`; empty
/// until a step records a result.
 final  Map<String, Map<String, String>> _results;
/// The per-node `grid.result.*` payloads, threaded down pull-free so a
/// `route` step reads its siblings' grades — D-5. Keyed by `nodePath`; empty
/// until a step records a result.
@override@JsonKey() Map<String, Map<String, String>> get results {
  if (_results is EqualUnmodifiableMapView) return _results;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_results);
}

/// The OPEN `type=gate` beads blocking this session (D-7), keyed by the
/// parked `nodePath` — scanned from the state snapshot by the join bridge,
/// not from this session bead. A node leaves this map when its gate bead
/// closes, which re-arms the parked node (`SessionScope` flips it back to
/// `pending`). Each entry carries the gate bead's OWN id + reason, so
/// `SessionScope` can BOTH decide whether the park is machine-actionable AND
/// close that exact bead through the chokepoint (tg-b3k) — pull-free (A39):
/// a tree node never re-queries the store.
 final  Map<String, OpenGate> _openGates;
/// The OPEN `type=gate` beads blocking this session (D-7), keyed by the
/// parked `nodePath` — scanned from the state snapshot by the join bridge,
/// not from this session bead. A node leaves this map when its gate bead
/// closes, which re-arms the parked node (`SessionScope` flips it back to
/// `pending`). Each entry carries the gate bead's OWN id + reason, so
/// `SessionScope` can BOTH decide whether the park is machine-actionable AND
/// close that exact bead through the chokepoint (tg-b3k) — pull-free (A39):
/// a tree node never re-queries the store.
@override@JsonKey() Map<String, OpenGate> get openGates {
  if (_openGates is EqualUnmodifiableMapView) return _openGates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_openGates);
}

/// The highest REWORK round already retired for this work bead (0 = none) —
/// computed by the join bridge off every session's `work_bead` key
/// (`<workBeadId>#r<N>`). The auto-respec transition mints round
/// `reworkRounds + 1` and refuses at `kMaxReworkRounds` (tg-b3k).
@override@JsonKey() final  int reworkRounds;
/// Capture-only session lifecycle telemetry (FT-1, tg-pez) — the wall-clock
/// instant the session bead was minted (its `started_at` metadata, stamped
/// once at first spawn through the chokepoint); null for a legacy bead minted
/// before the stamp shipped. Never gates orchestration.
@override final  DateTime? startedAt;
/// Capture-only session lifecycle telemetry — the wall-clock instant the
/// session bead was closed (its `closed_at` metadata, stamped inside the
/// chokepoint's `close`); null while the session is still open.
@override final  DateTime? closedAt;

/// Create a copy of SessionProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionProjectionCopyWith<_SessionProjection> get copyWith => __$SessionProjectionCopyWithImpl<_SessionProjection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionProjection&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.isTerminal, isTerminal) || other.isTerminal == isTerminal)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.token, token) || other.token == token)&&(identical(other.pid, pid) || other.pid == pid)&&const DeepCollectionEquality().equals(other._cursor, _cursor)&&const DeepCollectionEquality().equals(other._results, _results)&&const DeepCollectionEquality().equals(other._openGates, _openGates)&&(identical(other.reworkRounds, reworkRounds) || other.reworkRounds == reworkRounds)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt));
}


@override
int get hashCode => Object.hash(runtimeType,workBeadId,sessionId,isTerminal,pgid,token,pid,const DeepCollectionEquality().hash(_cursor),const DeepCollectionEquality().hash(_results),const DeepCollectionEquality().hash(_openGates),reworkRounds,startedAt,closedAt);

@override
String toString() {
  return 'SessionProjection(workBeadId: $workBeadId, sessionId: $sessionId, isTerminal: $isTerminal, pgid: $pgid, token: $token, pid: $pid, cursor: $cursor, results: $results, openGates: $openGates, reworkRounds: $reworkRounds, startedAt: $startedAt, closedAt: $closedAt)';
}


}

/// @nodoc
abstract mixin class _$SessionProjectionCopyWith<$Res> implements $SessionProjectionCopyWith<$Res> {
  factory _$SessionProjectionCopyWith(_SessionProjection value, $Res Function(_SessionProjection) _then) = __$SessionProjectionCopyWithImpl;
@override @useResult
$Res call({
 String workBeadId, String? sessionId, bool isTerminal, int? pgid, String? token, int? pid, CircuitCursor cursor, Map<String, Map<String, String>> results, Map<String, OpenGate> openGates, int reworkRounds, DateTime? startedAt, DateTime? closedAt
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
@override @pragma('vm:prefer-inline') $Res call({Object? workBeadId = null,Object? sessionId = freezed,Object? isTerminal = null,Object? pgid = freezed,Object? token = freezed,Object? pid = freezed,Object? cursor = null,Object? results = null,Object? openGates = null,Object? reworkRounds = null,Object? startedAt = freezed,Object? closedAt = freezed,}) {
  return _then(_SessionProjection(
workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,isTerminal: null == isTerminal ? _self.isTerminal : isTerminal // ignore: cast_nullable_to_non_nullable
as bool,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,cursor: null == cursor ? _self._cursor : cursor // ignore: cast_nullable_to_non_nullable
as CircuitCursor,results: null == results ? _self._results : results // ignore: cast_nullable_to_non_nullable
as Map<String, Map<String, String>>,openGates: null == openGates ? _self._openGates : openGates // ignore: cast_nullable_to_non_nullable
as Map<String, OpenGate>,reworkRounds: null == reworkRounds ? _self.reworkRounds : reworkRounds // ignore: cast_nullable_to_non_nullable
as int,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$OpenGate {

/// The gate bead's own id in the state store — the close target.
 String get gateId;/// The parked node's path (the gate bead's `metadata.node`).
 String get nodePath;/// Why the work parked (the gate bead's `metadata.reason`). A reason
/// carrying `kRespecGatePrefix` is MACHINE-ACTIONABLE; anything else is a
/// human gate.
 String get reason;
/// Create a copy of OpenGate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpenGateCopyWith<OpenGate> get copyWith => _$OpenGateCopyWithImpl<OpenGate>(this as OpenGate, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpenGate&&(identical(other.gateId, gateId) || other.gateId == gateId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,gateId,nodePath,reason);

@override
String toString() {
  return 'OpenGate(gateId: $gateId, nodePath: $nodePath, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $OpenGateCopyWith<$Res>  {
  factory $OpenGateCopyWith(OpenGate value, $Res Function(OpenGate) _then) = _$OpenGateCopyWithImpl;
@useResult
$Res call({
 String gateId, String nodePath, String reason
});




}
/// @nodoc
class _$OpenGateCopyWithImpl<$Res>
    implements $OpenGateCopyWith<$Res> {
  _$OpenGateCopyWithImpl(this._self, this._then);

  final OpenGate _self;
  final $Res Function(OpenGate) _then;

/// Create a copy of OpenGate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gateId = null,Object? nodePath = null,Object? reason = null,}) {
  return _then(_self.copyWith(
gateId: null == gateId ? _self.gateId : gateId // ignore: cast_nullable_to_non_nullable
as String,nodePath: null == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [OpenGate].
extension OpenGatePatterns on OpenGate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OpenGate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OpenGate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OpenGate value)  $default,){
final _that = this;
switch (_that) {
case _OpenGate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OpenGate value)?  $default,){
final _that = this;
switch (_that) {
case _OpenGate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String gateId,  String nodePath,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OpenGate() when $default != null:
return $default(_that.gateId,_that.nodePath,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String gateId,  String nodePath,  String reason)  $default,) {final _that = this;
switch (_that) {
case _OpenGate():
return $default(_that.gateId,_that.nodePath,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String gateId,  String nodePath,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _OpenGate() when $default != null:
return $default(_that.gateId,_that.nodePath,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _OpenGate implements OpenGate {
  const _OpenGate({required this.gateId, required this.nodePath, this.reason = ''});
  

/// The gate bead's own id in the state store — the close target.
@override final  String gateId;
/// The parked node's path (the gate bead's `metadata.node`).
@override final  String nodePath;
/// Why the work parked (the gate bead's `metadata.reason`). A reason
/// carrying `kRespecGatePrefix` is MACHINE-ACTIONABLE; anything else is a
/// human gate.
@override@JsonKey() final  String reason;

/// Create a copy of OpenGate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpenGateCopyWith<_OpenGate> get copyWith => __$OpenGateCopyWithImpl<_OpenGate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OpenGate&&(identical(other.gateId, gateId) || other.gateId == gateId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,gateId,nodePath,reason);

@override
String toString() {
  return 'OpenGate(gateId: $gateId, nodePath: $nodePath, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$OpenGateCopyWith<$Res> implements $OpenGateCopyWith<$Res> {
  factory _$OpenGateCopyWith(_OpenGate value, $Res Function(_OpenGate) _then) = __$OpenGateCopyWithImpl;
@override @useResult
$Res call({
 String gateId, String nodePath, String reason
});




}
/// @nodoc
class __$OpenGateCopyWithImpl<$Res>
    implements _$OpenGateCopyWith<$Res> {
  __$OpenGateCopyWithImpl(this._self, this._then);

  final _OpenGate _self;
  final $Res Function(_OpenGate) _then;

/// Create a copy of OpenGate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gateId = null,Object? nodePath = null,Object? reason = null,}) {
  return _then(_OpenGate(
gateId: null == gateId ? _self.gateId : gateId // ignore: cast_nullable_to_non_nullable
as String,nodePath: null == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
