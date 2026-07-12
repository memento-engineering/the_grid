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
 int get restartCount;/// How many times this node has been RE-KEYED BY A ROUTING REWIND
/// (`StepOutcome.Rewind` — tg-o90). Bumped monotonically per node on every
/// rewind wave that names it, and part of the node's reconcile key
/// (`CircuitScope`), so a rewound node that is still MOUNTED (a daemon) is
/// torn down and re-run rather than silently left alive under a stale
/// incarnation.
///
/// DISTINCT from [restartCount] (a supervised CRASH restart, D-5): a rework
/// round never spends the restart budget and a crash never spends a rework
/// round. It is also the BOUNDED-ROUNDS counter — the host refuses a rewind
/// from a node that has reached `kMaxReworkRounds`, and a `route` reads its
/// own count back through the ambient `SiblingView` to escalate first.
 int get rewindCount;/// How many times this node was REAPED ON ADOPTION — a prior station
/// generation left it at [StepState.running] and its recorded process was
/// found DEAD at boot, so the reaper re-mounted it.
///
/// CAPTURE-ONLY, and deliberately a THIRD incarnation axis — disjoint from
/// BOTH [restartCount] (a LIVE-supervised crash, D-5) and [rewindCount] (a
/// routing rework round, A47). A47's rule is the law here: "Two axes, not
/// one: a rework round never spends the supervised-restart budget, and a
/// crash never spends a rework round." A STATION DEATH is a third cause, so
/// it gets a third counter — **a station death is not a step failure:** the
/// `maxRestarts` breaker is for a process that died while the station was
/// ALIVE to supervise it, so charging a bounce to it would make the
/// operator's recovery lever destructive (the third bounce that caught a
/// long step mid-run would trip the breaker and close a session whose step
/// never failed).
///
/// UNLIKE the other two axes it is **NOT part of the reconcile key**
/// (`CircuitScope`'s `ValueKey('$path#$restartCount.$rewindCount')` — A47):
/// a re-key exists to TEAR DOWN a still-mounted effect, and the reap runs at
/// boot BEFORE the kernel mounts anything, so there is no live incarnation
/// to displace and nothing to re-key. Nothing in the frontier reads it and
/// no breaker trips on it — so a bounce stays FREE. Its ONLY job is to make
/// a crash-LOOPING station visible ("this step has died with the station 4
/// times") instead of silently invisible.
 int get reapCount;/// The earliest time a failed node may re-key (backoff — D-5); null when not
/// cooling down.
 DateTime? get cooldownUntil;/// The durable log byte-offset for the deferred adopt-a-live-process seam
/// (§11); null until restoration ships.
 int? get logOffset;/// Capture-only FLOW TELEMETRY (FT-1, tg-pez) — the wall-clock instant this
/// incarnation began driving its effect (the host's kick), ISO-8601 UTC on
/// the wire; null until the node has started. Never gates orchestration.
 DateTime? get startedAt;/// Capture-only flow telemetry — the wall-clock instant of this incarnation's
/// terminal transition (complete/failed/ready/gated); null until terminal.
 DateTime? get finishedAt;/// Capture-only flow telemetry — `finishedAt - startedAt` in milliseconds,
/// derived at the terminal write; null when the start was never measured
/// (fail-safe omission).
 int? get durationMs;/// Capture-only flow telemetry — the truncated diagnostic reason persisted
/// alongside a `failed` terminal (the `AllocationFailed.reason`); null when
/// the failure carried no diagnostic.
 String? get failureReason;
/// Create a copy of NodeCursor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NodeCursorCopyWith<NodeCursor> get copyWith => _$NodeCursorCopyWithImpl<NodeCursor>(this as NodeCursor, _$identity);

  /// Serializes this NodeCursor to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NodeCursor&&(identical(other.state, state) || other.state == state)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.pid, pid) || other.pid == pid)&&(identical(other.token, token) || other.token == token)&&(identical(other.restartCount, restartCount) || other.restartCount == restartCount)&&(identical(other.rewindCount, rewindCount) || other.rewindCount == rewindCount)&&(identical(other.reapCount, reapCount) || other.reapCount == reapCount)&&(identical(other.cooldownUntil, cooldownUntil) || other.cooldownUntil == cooldownUntil)&&(identical(other.logOffset, logOffset) || other.logOffset == logOffset)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.failureReason, failureReason) || other.failureReason == failureReason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,state,pgid,pid,token,restartCount,rewindCount,reapCount,cooldownUntil,logOffset,startedAt,finishedAt,durationMs,failureReason);

@override
String toString() {
  return 'NodeCursor(state: $state, pgid: $pgid, pid: $pid, token: $token, restartCount: $restartCount, rewindCount: $rewindCount, reapCount: $reapCount, cooldownUntil: $cooldownUntil, logOffset: $logOffset, startedAt: $startedAt, finishedAt: $finishedAt, durationMs: $durationMs, failureReason: $failureReason)';
}


}

/// @nodoc
abstract mixin class $NodeCursorCopyWith<$Res>  {
  factory $NodeCursorCopyWith(NodeCursor value, $Res Function(NodeCursor) _then) = _$NodeCursorCopyWithImpl;
@useResult
$Res call({
 StepState state, int? pgid, int? pid, String? token, int restartCount, int rewindCount, int reapCount, DateTime? cooldownUntil, int? logOffset, DateTime? startedAt, DateTime? finishedAt, int? durationMs, String? failureReason
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
@pragma('vm:prefer-inline') @override $Res call({Object? state = null,Object? pgid = freezed,Object? pid = freezed,Object? token = freezed,Object? restartCount = null,Object? rewindCount = null,Object? reapCount = null,Object? cooldownUntil = freezed,Object? logOffset = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? durationMs = freezed,Object? failureReason = freezed,}) {
  return _then(_self.copyWith(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepState,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,restartCount: null == restartCount ? _self.restartCount : restartCount // ignore: cast_nullable_to_non_nullable
as int,rewindCount: null == rewindCount ? _self.rewindCount : rewindCount // ignore: cast_nullable_to_non_nullable
as int,reapCount: null == reapCount ? _self.reapCount : reapCount // ignore: cast_nullable_to_non_nullable
as int,cooldownUntil: freezed == cooldownUntil ? _self.cooldownUntil : cooldownUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,logOffset: freezed == logOffset ? _self.logOffset : logOffset // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,failureReason: freezed == failureReason ? _self.failureReason : failureReason // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  int rewindCount,  int reapCount,  DateTime? cooldownUntil,  int? logOffset,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  String? failureReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.rewindCount,_that.reapCount,_that.cooldownUntil,_that.logOffset,_that.startedAt,_that.finishedAt,_that.durationMs,_that.failureReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  int rewindCount,  int reapCount,  DateTime? cooldownUntil,  int? logOffset,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  String? failureReason)  $default,) {final _that = this;
switch (_that) {
case _NodeCursor():
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.rewindCount,_that.reapCount,_that.cooldownUntil,_that.logOffset,_that.startedAt,_that.finishedAt,_that.durationMs,_that.failureReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StepState state,  int? pgid,  int? pid,  String? token,  int restartCount,  int rewindCount,  int reapCount,  DateTime? cooldownUntil,  int? logOffset,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  String? failureReason)?  $default,) {final _that = this;
switch (_that) {
case _NodeCursor() when $default != null:
return $default(_that.state,_that.pgid,_that.pid,_that.token,_that.restartCount,_that.rewindCount,_that.reapCount,_that.cooldownUntil,_that.logOffset,_that.startedAt,_that.finishedAt,_that.durationMs,_that.failureReason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NodeCursor extends NodeCursor {
  const _NodeCursor({this.state = StepState.pending, this.pgid, this.pid, this.token, this.restartCount = 0, this.rewindCount = 0, this.reapCount = 0, this.cooldownUntil, this.logOffset, this.startedAt, this.finishedAt, this.durationMs, this.failureReason}): super._();
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
/// How many times this node has been RE-KEYED BY A ROUTING REWIND
/// (`StepOutcome.Rewind` — tg-o90). Bumped monotonically per node on every
/// rewind wave that names it, and part of the node's reconcile key
/// (`CircuitScope`), so a rewound node that is still MOUNTED (a daemon) is
/// torn down and re-run rather than silently left alive under a stale
/// incarnation.
///
/// DISTINCT from [restartCount] (a supervised CRASH restart, D-5): a rework
/// round never spends the restart budget and a crash never spends a rework
/// round. It is also the BOUNDED-ROUNDS counter — the host refuses a rewind
/// from a node that has reached `kMaxReworkRounds`, and a `route` reads its
/// own count back through the ambient `SiblingView` to escalate first.
@override@JsonKey() final  int rewindCount;
/// How many times this node was REAPED ON ADOPTION — a prior station
/// generation left it at [StepState.running] and its recorded process was
/// found DEAD at boot, so the reaper re-mounted it.
///
/// CAPTURE-ONLY, and deliberately a THIRD incarnation axis — disjoint from
/// BOTH [restartCount] (a LIVE-supervised crash, D-5) and [rewindCount] (a
/// routing rework round, A47). A47's rule is the law here: "Two axes, not
/// one: a rework round never spends the supervised-restart budget, and a
/// crash never spends a rework round." A STATION DEATH is a third cause, so
/// it gets a third counter — **a station death is not a step failure:** the
/// `maxRestarts` breaker is for a process that died while the station was
/// ALIVE to supervise it, so charging a bounce to it would make the
/// operator's recovery lever destructive (the third bounce that caught a
/// long step mid-run would trip the breaker and close a session whose step
/// never failed).
///
/// UNLIKE the other two axes it is **NOT part of the reconcile key**
/// (`CircuitScope`'s `ValueKey('$path#$restartCount.$rewindCount')` — A47):
/// a re-key exists to TEAR DOWN a still-mounted effect, and the reap runs at
/// boot BEFORE the kernel mounts anything, so there is no live incarnation
/// to displace and nothing to re-key. Nothing in the frontier reads it and
/// no breaker trips on it — so a bounce stays FREE. Its ONLY job is to make
/// a crash-LOOPING station visible ("this step has died with the station 4
/// times") instead of silently invisible.
@override@JsonKey() final  int reapCount;
/// The earliest time a failed node may re-key (backoff — D-5); null when not
/// cooling down.
@override final  DateTime? cooldownUntil;
/// The durable log byte-offset for the deferred adopt-a-live-process seam
/// (§11); null until restoration ships.
@override final  int? logOffset;
/// Capture-only FLOW TELEMETRY (FT-1, tg-pez) — the wall-clock instant this
/// incarnation began driving its effect (the host's kick), ISO-8601 UTC on
/// the wire; null until the node has started. Never gates orchestration.
@override final  DateTime? startedAt;
/// Capture-only flow telemetry — the wall-clock instant of this incarnation's
/// terminal transition (complete/failed/ready/gated); null until terminal.
@override final  DateTime? finishedAt;
/// Capture-only flow telemetry — `finishedAt - startedAt` in milliseconds,
/// derived at the terminal write; null when the start was never measured
/// (fail-safe omission).
@override final  int? durationMs;
/// Capture-only flow telemetry — the truncated diagnostic reason persisted
/// alongside a `failed` terminal (the `AllocationFailed.reason`); null when
/// the failure carried no diagnostic.
@override final  String? failureReason;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NodeCursor&&(identical(other.state, state) || other.state == state)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.pid, pid) || other.pid == pid)&&(identical(other.token, token) || other.token == token)&&(identical(other.restartCount, restartCount) || other.restartCount == restartCount)&&(identical(other.rewindCount, rewindCount) || other.rewindCount == rewindCount)&&(identical(other.reapCount, reapCount) || other.reapCount == reapCount)&&(identical(other.cooldownUntil, cooldownUntil) || other.cooldownUntil == cooldownUntil)&&(identical(other.logOffset, logOffset) || other.logOffset == logOffset)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.failureReason, failureReason) || other.failureReason == failureReason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,state,pgid,pid,token,restartCount,rewindCount,reapCount,cooldownUntil,logOffset,startedAt,finishedAt,durationMs,failureReason);

@override
String toString() {
  return 'NodeCursor(state: $state, pgid: $pgid, pid: $pid, token: $token, restartCount: $restartCount, rewindCount: $rewindCount, reapCount: $reapCount, cooldownUntil: $cooldownUntil, logOffset: $logOffset, startedAt: $startedAt, finishedAt: $finishedAt, durationMs: $durationMs, failureReason: $failureReason)';
}


}

/// @nodoc
abstract mixin class _$NodeCursorCopyWith<$Res> implements $NodeCursorCopyWith<$Res> {
  factory _$NodeCursorCopyWith(_NodeCursor value, $Res Function(_NodeCursor) _then) = __$NodeCursorCopyWithImpl;
@override @useResult
$Res call({
 StepState state, int? pgid, int? pid, String? token, int restartCount, int rewindCount, int reapCount, DateTime? cooldownUntil, int? logOffset, DateTime? startedAt, DateTime? finishedAt, int? durationMs, String? failureReason
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
@override @pragma('vm:prefer-inline') $Res call({Object? state = null,Object? pgid = freezed,Object? pid = freezed,Object? token = freezed,Object? restartCount = null,Object? rewindCount = null,Object? reapCount = null,Object? cooldownUntil = freezed,Object? logOffset = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? durationMs = freezed,Object? failureReason = freezed,}) {
  return _then(_NodeCursor(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as StepState,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,pid: freezed == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int?,token: freezed == token ? _self.token : token // ignore: cast_nullable_to_non_nullable
as String?,restartCount: null == restartCount ? _self.restartCount : restartCount // ignore: cast_nullable_to_non_nullable
as int,rewindCount: null == rewindCount ? _self.rewindCount : rewindCount // ignore: cast_nullable_to_non_nullable
as int,reapCount: null == reapCount ? _self.reapCount : reapCount // ignore: cast_nullable_to_non_nullable
as int,cooldownUntil: freezed == cooldownUntil ? _self.cooldownUntil : cooldownUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,logOffset: freezed == logOffset ? _self.logOffset : logOffset // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,failureReason: freezed == failureReason ? _self.failureReason : failureReason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
