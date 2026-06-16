// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'runtime_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RuntimeEvent {

 String get name;
/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeEventCopyWith<RuntimeEvent> get copyWith => _$RuntimeEventCopyWithImpl<RuntimeEvent>(this as RuntimeEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeEvent&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,name);

@override
String toString() {
  return 'RuntimeEvent(name: $name)';
}


}

/// @nodoc
abstract mixin class $RuntimeEventCopyWith<$Res>  {
  factory $RuntimeEventCopyWith(RuntimeEvent value, $Res Function(RuntimeEvent) _then) = _$RuntimeEventCopyWithImpl;
@useResult
$Res call({
 String name
});




}
/// @nodoc
class _$RuntimeEventCopyWithImpl<$Res>
    implements $RuntimeEventCopyWith<$Res> {
  _$RuntimeEventCopyWithImpl(this._self, this._then);

  final RuntimeEvent _self;
  final $Res Function(RuntimeEvent) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeEvent].
extension RuntimeEventPatterns on RuntimeEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionStarted value)?  sessionStarted,TResult Function( Exited value)?  exited,TResult Function( Died value)?  died,TResult Function( Respawned value)?  respawned,TResult Function( ActivityChanged value)?  activityChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionStarted() when sessionStarted != null:
return sessionStarted(_that);case Exited() when exited != null:
return exited(_that);case Died() when died != null:
return died(_that);case Respawned() when respawned != null:
return respawned(_that);case ActivityChanged() when activityChanged != null:
return activityChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionStarted value)  sessionStarted,required TResult Function( Exited value)  exited,required TResult Function( Died value)  died,required TResult Function( Respawned value)  respawned,required TResult Function( ActivityChanged value)  activityChanged,}){
final _that = this;
switch (_that) {
case SessionStarted():
return sessionStarted(_that);case Exited():
return exited(_that);case Died():
return died(_that);case Respawned():
return respawned(_that);case ActivityChanged():
return activityChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionStarted value)?  sessionStarted,TResult? Function( Exited value)?  exited,TResult? Function( Died value)?  died,TResult? Function( Respawned value)?  respawned,TResult? Function( ActivityChanged value)?  activityChanged,}){
final _that = this;
switch (_that) {
case SessionStarted() when sessionStarted != null:
return sessionStarted(_that);case Exited() when exited != null:
return exited(_that);case Died() when died != null:
return died(_that);case Respawned() when respawned != null:
return respawned(_that);case ActivityChanged() when activityChanged != null:
return activityChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String name,  int pid,  int? pgid,  String beadId)?  sessionStarted,TResult Function( String name,  int exitCode)?  exited,TResult Function( String name,  String reason)?  died,TResult Function( String name,  int epoch)?  respawned,TResult Function( String name,  bool active)?  activityChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionStarted() when sessionStarted != null:
return sessionStarted(_that.name,_that.pid,_that.pgid,_that.beadId);case Exited() when exited != null:
return exited(_that.name,_that.exitCode);case Died() when died != null:
return died(_that.name,_that.reason);case Respawned() when respawned != null:
return respawned(_that.name,_that.epoch);case ActivityChanged() when activityChanged != null:
return activityChanged(_that.name,_that.active);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String name,  int pid,  int? pgid,  String beadId)  sessionStarted,required TResult Function( String name,  int exitCode)  exited,required TResult Function( String name,  String reason)  died,required TResult Function( String name,  int epoch)  respawned,required TResult Function( String name,  bool active)  activityChanged,}) {final _that = this;
switch (_that) {
case SessionStarted():
return sessionStarted(_that.name,_that.pid,_that.pgid,_that.beadId);case Exited():
return exited(_that.name,_that.exitCode);case Died():
return died(_that.name,_that.reason);case Respawned():
return respawned(_that.name,_that.epoch);case ActivityChanged():
return activityChanged(_that.name,_that.active);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String name,  int pid,  int? pgid,  String beadId)?  sessionStarted,TResult? Function( String name,  int exitCode)?  exited,TResult? Function( String name,  String reason)?  died,TResult? Function( String name,  int epoch)?  respawned,TResult? Function( String name,  bool active)?  activityChanged,}) {final _that = this;
switch (_that) {
case SessionStarted() when sessionStarted != null:
return sessionStarted(_that.name,_that.pid,_that.pgid,_that.beadId);case Exited() when exited != null:
return exited(_that.name,_that.exitCode);case Died() when died != null:
return died(_that.name,_that.reason);case Respawned() when respawned != null:
return respawned(_that.name,_that.epoch);case ActivityChanged() when activityChanged != null:
return activityChanged(_that.name,_that.active);case _:
  return null;

}
}

}

/// @nodoc


class SessionStarted extends RuntimeEvent {
  const SessionStarted({required this.name, required this.pid, this.pgid, this.beadId = ''}): super._();
  

@override final  String name;
 final  int pid;
 final  int? pgid;
@JsonKey() final  String beadId;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionStartedCopyWith<SessionStarted> get copyWith => _$SessionStartedCopyWithImpl<SessionStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionStarted&&(identical(other.name, name) || other.name == name)&&(identical(other.pid, pid) || other.pid == pid)&&(identical(other.pgid, pgid) || other.pgid == pgid)&&(identical(other.beadId, beadId) || other.beadId == beadId));
}


@override
int get hashCode => Object.hash(runtimeType,name,pid,pgid,beadId);

@override
String toString() {
  return 'RuntimeEvent.sessionStarted(name: $name, pid: $pid, pgid: $pgid, beadId: $beadId)';
}


}

/// @nodoc
abstract mixin class $SessionStartedCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory $SessionStartedCopyWith(SessionStarted value, $Res Function(SessionStarted) _then) = _$SessionStartedCopyWithImpl;
@override @useResult
$Res call({
 String name, int pid, int? pgid, String beadId
});




}
/// @nodoc
class _$SessionStartedCopyWithImpl<$Res>
    implements $SessionStartedCopyWith<$Res> {
  _$SessionStartedCopyWithImpl(this._self, this._then);

  final SessionStarted _self;
  final $Res Function(SessionStarted) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? pid = null,Object? pgid = freezed,Object? beadId = null,}) {
  return _then(SessionStarted(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,pid: null == pid ? _self.pid : pid // ignore: cast_nullable_to_non_nullable
as int,pgid: freezed == pgid ? _self.pgid : pgid // ignore: cast_nullable_to_non_nullable
as int?,beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Exited extends RuntimeEvent {
  const Exited({required this.name, required this.exitCode}): super._();
  

@override final  String name;
 final  int exitCode;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExitedCopyWith<Exited> get copyWith => _$ExitedCopyWithImpl<Exited>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Exited&&(identical(other.name, name) || other.name == name)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode));
}


@override
int get hashCode => Object.hash(runtimeType,name,exitCode);

@override
String toString() {
  return 'RuntimeEvent.exited(name: $name, exitCode: $exitCode)';
}


}

/// @nodoc
abstract mixin class $ExitedCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory $ExitedCopyWith(Exited value, $Res Function(Exited) _then) = _$ExitedCopyWithImpl;
@override @useResult
$Res call({
 String name, int exitCode
});




}
/// @nodoc
class _$ExitedCopyWithImpl<$Res>
    implements $ExitedCopyWith<$Res> {
  _$ExitedCopyWithImpl(this._self, this._then);

  final Exited _self;
  final $Res Function(Exited) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? exitCode = null,}) {
  return _then(Exited(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,exitCode: null == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class Died extends RuntimeEvent {
  const Died({required this.name, this.reason = ''}): super._();
  

@override final  String name;
@JsonKey() final  String reason;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DiedCopyWith<Died> get copyWith => _$DiedCopyWithImpl<Died>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Died&&(identical(other.name, name) || other.name == name)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,name,reason);

@override
String toString() {
  return 'RuntimeEvent.died(name: $name, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $DiedCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory $DiedCopyWith(Died value, $Res Function(Died) _then) = _$DiedCopyWithImpl;
@override @useResult
$Res call({
 String name, String reason
});




}
/// @nodoc
class _$DiedCopyWithImpl<$Res>
    implements $DiedCopyWith<$Res> {
  _$DiedCopyWithImpl(this._self, this._then);

  final Died _self;
  final $Res Function(Died) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? reason = null,}) {
  return _then(Died(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Respawned extends RuntimeEvent {
  const Respawned({required this.name, required this.epoch}): super._();
  

@override final  String name;
 final  int epoch;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RespawnedCopyWith<Respawned> get copyWith => _$RespawnedCopyWithImpl<Respawned>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Respawned&&(identical(other.name, name) || other.name == name)&&(identical(other.epoch, epoch) || other.epoch == epoch));
}


@override
int get hashCode => Object.hash(runtimeType,name,epoch);

@override
String toString() {
  return 'RuntimeEvent.respawned(name: $name, epoch: $epoch)';
}


}

/// @nodoc
abstract mixin class $RespawnedCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory $RespawnedCopyWith(Respawned value, $Res Function(Respawned) _then) = _$RespawnedCopyWithImpl;
@override @useResult
$Res call({
 String name, int epoch
});




}
/// @nodoc
class _$RespawnedCopyWithImpl<$Res>
    implements $RespawnedCopyWith<$Res> {
  _$RespawnedCopyWithImpl(this._self, this._then);

  final Respawned _self;
  final $Res Function(Respawned) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? epoch = null,}) {
  return _then(Respawned(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,epoch: null == epoch ? _self.epoch : epoch // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ActivityChanged extends RuntimeEvent {
  const ActivityChanged({required this.name, required this.active}): super._();
  

@override final  String name;
 final  bool active;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityChangedCopyWith<ActivityChanged> get copyWith => _$ActivityChangedCopyWithImpl<ActivityChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityChanged&&(identical(other.name, name) || other.name == name)&&(identical(other.active, active) || other.active == active));
}


@override
int get hashCode => Object.hash(runtimeType,name,active);

@override
String toString() {
  return 'RuntimeEvent.activityChanged(name: $name, active: $active)';
}


}

/// @nodoc
abstract mixin class $ActivityChangedCopyWith<$Res> implements $RuntimeEventCopyWith<$Res> {
  factory $ActivityChangedCopyWith(ActivityChanged value, $Res Function(ActivityChanged) _then) = _$ActivityChangedCopyWithImpl;
@override @useResult
$Res call({
 String name, bool active
});




}
/// @nodoc
class _$ActivityChangedCopyWithImpl<$Res>
    implements $ActivityChangedCopyWith<$Res> {
  _$ActivityChangedCopyWithImpl(this._self, this._then);

  final ActivityChanged _self;
  final $Res Function(ActivityChanged) _then;

/// Create a copy of RuntimeEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? active = null,}) {
  return _then(ActivityChanged(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
