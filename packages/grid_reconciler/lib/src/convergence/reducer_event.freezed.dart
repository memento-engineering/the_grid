// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reducer_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReducerEvent {

 String get convergenceBeadId;
/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReducerEventCopyWith<ReducerEvent> get copyWith => _$ReducerEventCopyWithImpl<ReducerEvent>(this as ReducerEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReducerEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId);

@override
String toString() {
  return 'ReducerEvent(convergenceBeadId: $convergenceBeadId)';
}


}

/// @nodoc
abstract mixin class $ReducerEventCopyWith<$Res>  {
  factory $ReducerEventCopyWith(ReducerEvent value, $Res Function(ReducerEvent) _then) = _$ReducerEventCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId
});




}
/// @nodoc
class _$ReducerEventCopyWithImpl<$Res>
    implements $ReducerEventCopyWith<$Res> {
  _$ReducerEventCopyWithImpl(this._self, this._then);

  final ReducerEvent _self;
  final $Res Function(ReducerEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? convergenceBeadId = null,}) {
  return _then(_self.copyWith(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ReducerEvent].
extension ReducerEventPatterns on ReducerEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( WispClosedEvent value)?  wispClosed,TResult Function( GateEvaluatedEvent value)?  gateEvaluated,TResult Function( OperatorApproveEvent value)?  operatorApprove,TResult Function( OperatorIterateEvent value)?  operatorIterate,TResult Function( OperatorStopEvent value)?  operatorStop,TResult Function( TriggerPassedEvent value)?  triggerPassed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case WispClosedEvent() when wispClosed != null:
return wispClosed(_that);case GateEvaluatedEvent() when gateEvaluated != null:
return gateEvaluated(_that);case OperatorApproveEvent() when operatorApprove != null:
return operatorApprove(_that);case OperatorIterateEvent() when operatorIterate != null:
return operatorIterate(_that);case OperatorStopEvent() when operatorStop != null:
return operatorStop(_that);case TriggerPassedEvent() when triggerPassed != null:
return triggerPassed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( WispClosedEvent value)  wispClosed,required TResult Function( GateEvaluatedEvent value)  gateEvaluated,required TResult Function( OperatorApproveEvent value)  operatorApprove,required TResult Function( OperatorIterateEvent value)  operatorIterate,required TResult Function( OperatorStopEvent value)  operatorStop,required TResult Function( TriggerPassedEvent value)  triggerPassed,}){
final _that = this;
switch (_that) {
case WispClosedEvent():
return wispClosed(_that);case GateEvaluatedEvent():
return gateEvaluated(_that);case OperatorApproveEvent():
return operatorApprove(_that);case OperatorIterateEvent():
return operatorIterate(_that);case OperatorStopEvent():
return operatorStop(_that);case TriggerPassedEvent():
return triggerPassed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( WispClosedEvent value)?  wispClosed,TResult? Function( GateEvaluatedEvent value)?  gateEvaluated,TResult? Function( OperatorApproveEvent value)?  operatorApprove,TResult? Function( OperatorIterateEvent value)?  operatorIterate,TResult? Function( OperatorStopEvent value)?  operatorStop,TResult? Function( TriggerPassedEvent value)?  triggerPassed,}){
final _that = this;
switch (_that) {
case WispClosedEvent() when wispClosed != null:
return wispClosed(_that);case GateEvaluatedEvent() when gateEvaluated != null:
return gateEvaluated(_that);case OperatorApproveEvent() when operatorApprove != null:
return operatorApprove(_that);case OperatorIterateEvent() when operatorIterate != null:
return operatorIterate(_that);case OperatorStopEvent() when operatorStop != null:
return operatorStop(_that);case TriggerPassedEvent() when triggerPassed != null:
return triggerPassed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String convergenceBeadId,  String wispId)?  wispClosed,TResult Function( String convergenceBeadId,  String wispId,  GateResult result,  String? pouredSpeculativeWispId,  bool pourFailed)?  gateEvaluated,TResult Function( String convergenceBeadId,  String user)?  operatorApprove,TResult Function( String convergenceBeadId,  String user)?  operatorIterate,TResult Function( String convergenceBeadId,  String user,  bool postDrain)?  operatorStop,TResult Function( String convergenceBeadId,  int nextIteration)?  triggerPassed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case WispClosedEvent() when wispClosed != null:
return wispClosed(_that.convergenceBeadId,_that.wispId);case GateEvaluatedEvent() when gateEvaluated != null:
return gateEvaluated(_that.convergenceBeadId,_that.wispId,_that.result,_that.pouredSpeculativeWispId,_that.pourFailed);case OperatorApproveEvent() when operatorApprove != null:
return operatorApprove(_that.convergenceBeadId,_that.user);case OperatorIterateEvent() when operatorIterate != null:
return operatorIterate(_that.convergenceBeadId,_that.user);case OperatorStopEvent() when operatorStop != null:
return operatorStop(_that.convergenceBeadId,_that.user,_that.postDrain);case TriggerPassedEvent() when triggerPassed != null:
return triggerPassed(_that.convergenceBeadId,_that.nextIteration);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String convergenceBeadId,  String wispId)  wispClosed,required TResult Function( String convergenceBeadId,  String wispId,  GateResult result,  String? pouredSpeculativeWispId,  bool pourFailed)  gateEvaluated,required TResult Function( String convergenceBeadId,  String user)  operatorApprove,required TResult Function( String convergenceBeadId,  String user)  operatorIterate,required TResult Function( String convergenceBeadId,  String user,  bool postDrain)  operatorStop,required TResult Function( String convergenceBeadId,  int nextIteration)  triggerPassed,}) {final _that = this;
switch (_that) {
case WispClosedEvent():
return wispClosed(_that.convergenceBeadId,_that.wispId);case GateEvaluatedEvent():
return gateEvaluated(_that.convergenceBeadId,_that.wispId,_that.result,_that.pouredSpeculativeWispId,_that.pourFailed);case OperatorApproveEvent():
return operatorApprove(_that.convergenceBeadId,_that.user);case OperatorIterateEvent():
return operatorIterate(_that.convergenceBeadId,_that.user);case OperatorStopEvent():
return operatorStop(_that.convergenceBeadId,_that.user,_that.postDrain);case TriggerPassedEvent():
return triggerPassed(_that.convergenceBeadId,_that.nextIteration);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String convergenceBeadId,  String wispId)?  wispClosed,TResult? Function( String convergenceBeadId,  String wispId,  GateResult result,  String? pouredSpeculativeWispId,  bool pourFailed)?  gateEvaluated,TResult? Function( String convergenceBeadId,  String user)?  operatorApprove,TResult? Function( String convergenceBeadId,  String user)?  operatorIterate,TResult? Function( String convergenceBeadId,  String user,  bool postDrain)?  operatorStop,TResult? Function( String convergenceBeadId,  int nextIteration)?  triggerPassed,}) {final _that = this;
switch (_that) {
case WispClosedEvent() when wispClosed != null:
return wispClosed(_that.convergenceBeadId,_that.wispId);case GateEvaluatedEvent() when gateEvaluated != null:
return gateEvaluated(_that.convergenceBeadId,_that.wispId,_that.result,_that.pouredSpeculativeWispId,_that.pourFailed);case OperatorApproveEvent() when operatorApprove != null:
return operatorApprove(_that.convergenceBeadId,_that.user);case OperatorIterateEvent() when operatorIterate != null:
return operatorIterate(_that.convergenceBeadId,_that.user);case OperatorStopEvent() when operatorStop != null:
return operatorStop(_that.convergenceBeadId,_that.user,_that.postDrain);case TriggerPassedEvent() when triggerPassed != null:
return triggerPassed(_that.convergenceBeadId,_that.nextIteration);case _:
  return null;

}
}

}

/// @nodoc


class WispClosedEvent extends ReducerEvent {
  const WispClosedEvent({required this.convergenceBeadId, required this.wispId}): super._();
  

@override final  String convergenceBeadId;
 final  String wispId;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WispClosedEventCopyWith<WispClosedEvent> get copyWith => _$WispClosedEventCopyWithImpl<WispClosedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WispClosedEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.wispId, wispId) || other.wispId == wispId));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,wispId);

@override
String toString() {
  return 'ReducerEvent.wispClosed(convergenceBeadId: $convergenceBeadId, wispId: $wispId)';
}


}

/// @nodoc
abstract mixin class $WispClosedEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $WispClosedEventCopyWith(WispClosedEvent value, $Res Function(WispClosedEvent) _then) = _$WispClosedEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, String wispId
});




}
/// @nodoc
class _$WispClosedEventCopyWithImpl<$Res>
    implements $WispClosedEventCopyWith<$Res> {
  _$WispClosedEventCopyWithImpl(this._self, this._then);

  final WispClosedEvent _self;
  final $Res Function(WispClosedEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? wispId = null,}) {
  return _then(WispClosedEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,wispId: null == wispId ? _self.wispId : wispId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class GateEvaluatedEvent extends ReducerEvent {
  const GateEvaluatedEvent({required this.convergenceBeadId, required this.wispId, required this.result, this.pouredSpeculativeWispId, this.pourFailed = false}): super._();
  

@override final  String convergenceBeadId;
 final  String wispId;
 final  GateResult result;
/// The wisp the phase-1 `ReconcilerAction.pourSpeculative` produced —
/// its fresh pour, its `adoptPendingWispId` adoption, or its
/// find-before-pour hit; null when no wisp resulted (pour skipped, or
/// failed with a probe miss). Feeds the phase-2 reduce's
/// `IterateAction.adoptWispId`, the terminal/waiting `burnWispId`s,
/// and `PersistGateOutcomeAction.burnWispId`.
 final  String? pouredSpeculativeWispId;
/// gc's deferred `speculativePourErr` (handler.go:259-266): the
/// speculative pour failed AND the idempotency probe missed. Not fatal
/// at pour time — the phase-2 reduce surfaces it as the
/// `sling_failure` waiting_manual transition exactly when the gate
/// outcome is non-terminal (handler.go:370-373); terminal outcomes
/// swallow it, exactly like gc.
@JsonKey() final  bool pourFailed;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GateEvaluatedEventCopyWith<GateEvaluatedEvent> get copyWith => _$GateEvaluatedEventCopyWithImpl<GateEvaluatedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GateEvaluatedEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.wispId, wispId) || other.wispId == wispId)&&(identical(other.result, result) || other.result == result)&&(identical(other.pouredSpeculativeWispId, pouredSpeculativeWispId) || other.pouredSpeculativeWispId == pouredSpeculativeWispId)&&(identical(other.pourFailed, pourFailed) || other.pourFailed == pourFailed));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,wispId,result,pouredSpeculativeWispId,pourFailed);

@override
String toString() {
  return 'ReducerEvent.gateEvaluated(convergenceBeadId: $convergenceBeadId, wispId: $wispId, result: $result, pouredSpeculativeWispId: $pouredSpeculativeWispId, pourFailed: $pourFailed)';
}


}

/// @nodoc
abstract mixin class $GateEvaluatedEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $GateEvaluatedEventCopyWith(GateEvaluatedEvent value, $Res Function(GateEvaluatedEvent) _then) = _$GateEvaluatedEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, String wispId, GateResult result, String? pouredSpeculativeWispId, bool pourFailed
});


$GateResultCopyWith<$Res> get result;

}
/// @nodoc
class _$GateEvaluatedEventCopyWithImpl<$Res>
    implements $GateEvaluatedEventCopyWith<$Res> {
  _$GateEvaluatedEventCopyWithImpl(this._self, this._then);

  final GateEvaluatedEvent _self;
  final $Res Function(GateEvaluatedEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? wispId = null,Object? result = null,Object? pouredSpeculativeWispId = freezed,Object? pourFailed = null,}) {
  return _then(GateEvaluatedEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,wispId: null == wispId ? _self.wispId : wispId // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GateResult,pouredSpeculativeWispId: freezed == pouredSpeculativeWispId ? _self.pouredSpeculativeWispId : pouredSpeculativeWispId // ignore: cast_nullable_to_non_nullable
as String?,pourFailed: null == pourFailed ? _self.pourFailed : pourFailed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GateResultCopyWith<$Res> get result {
  
  return $GateResultCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class OperatorApproveEvent extends ReducerEvent {
  const OperatorApproveEvent({required this.convergenceBeadId, required this.user}): super._();
  

@override final  String convergenceBeadId;
 final  String user;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperatorApproveEventCopyWith<OperatorApproveEvent> get copyWith => _$OperatorApproveEventCopyWithImpl<OperatorApproveEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperatorApproveEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.user, user) || other.user == user));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,user);

@override
String toString() {
  return 'ReducerEvent.operatorApprove(convergenceBeadId: $convergenceBeadId, user: $user)';
}


}

/// @nodoc
abstract mixin class $OperatorApproveEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $OperatorApproveEventCopyWith(OperatorApproveEvent value, $Res Function(OperatorApproveEvent) _then) = _$OperatorApproveEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, String user
});




}
/// @nodoc
class _$OperatorApproveEventCopyWithImpl<$Res>
    implements $OperatorApproveEventCopyWith<$Res> {
  _$OperatorApproveEventCopyWithImpl(this._self, this._then);

  final OperatorApproveEvent _self;
  final $Res Function(OperatorApproveEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? user = null,}) {
  return _then(OperatorApproveEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class OperatorIterateEvent extends ReducerEvent {
  const OperatorIterateEvent({required this.convergenceBeadId, required this.user}): super._();
  

@override final  String convergenceBeadId;
 final  String user;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperatorIterateEventCopyWith<OperatorIterateEvent> get copyWith => _$OperatorIterateEventCopyWithImpl<OperatorIterateEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperatorIterateEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.user, user) || other.user == user));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,user);

@override
String toString() {
  return 'ReducerEvent.operatorIterate(convergenceBeadId: $convergenceBeadId, user: $user)';
}


}

/// @nodoc
abstract mixin class $OperatorIterateEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $OperatorIterateEventCopyWith(OperatorIterateEvent value, $Res Function(OperatorIterateEvent) _then) = _$OperatorIterateEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, String user
});




}
/// @nodoc
class _$OperatorIterateEventCopyWithImpl<$Res>
    implements $OperatorIterateEventCopyWith<$Res> {
  _$OperatorIterateEventCopyWithImpl(this._self, this._then);

  final OperatorIterateEvent _self;
  final $Res Function(OperatorIterateEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? user = null,}) {
  return _then(OperatorIterateEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class OperatorStopEvent extends ReducerEvent {
  const OperatorStopEvent({required this.convergenceBeadId, required this.user, this.postDrain = false}): super._();
  

@override final  String convergenceBeadId;
 final  String user;
/// `true` only on the [ReconcilerAction.requeue] re-entry, after Track
/// G ran the inline drain (manual.go:272-314). Marks "this stop already
/// drained the closed active wisp; its termination, if any, is MINE"
/// so the reducer maps `operatorStop` over `terminated/non-stopped` to
/// `SkipReason.drainTerminated` (gc's no-reason `ActionStopped` return,
/// manual.go:303-308) instead of the fresh-stop error path
/// (manual.go:258-263). A first-arrival operator stop is always
/// `false`. The snapshot alone cannot recover this — gc only knows
/// because the same handler call ran the drain.
@JsonKey() final  bool postDrain;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperatorStopEventCopyWith<OperatorStopEvent> get copyWith => _$OperatorStopEventCopyWithImpl<OperatorStopEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperatorStopEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.user, user) || other.user == user)&&(identical(other.postDrain, postDrain) || other.postDrain == postDrain));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,user,postDrain);

@override
String toString() {
  return 'ReducerEvent.operatorStop(convergenceBeadId: $convergenceBeadId, user: $user, postDrain: $postDrain)';
}


}

/// @nodoc
abstract mixin class $OperatorStopEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $OperatorStopEventCopyWith(OperatorStopEvent value, $Res Function(OperatorStopEvent) _then) = _$OperatorStopEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, String user, bool postDrain
});




}
/// @nodoc
class _$OperatorStopEventCopyWithImpl<$Res>
    implements $OperatorStopEventCopyWith<$Res> {
  _$OperatorStopEventCopyWithImpl(this._self, this._then);

  final OperatorStopEvent _self;
  final $Res Function(OperatorStopEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? user = null,Object? postDrain = null,}) {
  return _then(OperatorStopEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,user: null == user ? _self.user : user // ignore: cast_nullable_to_non_nullable
as String,postDrain: null == postDrain ? _self.postDrain : postDrain // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class TriggerPassedEvent extends ReducerEvent {
  const TriggerPassedEvent({required this.convergenceBeadId, required this.nextIteration}): super._();
  

@override final  String convergenceBeadId;
 final  int nextIteration;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TriggerPassedEventCopyWith<TriggerPassedEvent> get copyWith => _$TriggerPassedEventCopyWithImpl<TriggerPassedEvent>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TriggerPassedEvent&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.nextIteration, nextIteration) || other.nextIteration == nextIteration));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,nextIteration);

@override
String toString() {
  return 'ReducerEvent.triggerPassed(convergenceBeadId: $convergenceBeadId, nextIteration: $nextIteration)';
}


}

/// @nodoc
abstract mixin class $TriggerPassedEventCopyWith<$Res> implements $ReducerEventCopyWith<$Res> {
  factory $TriggerPassedEventCopyWith(TriggerPassedEvent value, $Res Function(TriggerPassedEvent) _then) = _$TriggerPassedEventCopyWithImpl;
@override @useResult
$Res call({
 String convergenceBeadId, int nextIteration
});




}
/// @nodoc
class _$TriggerPassedEventCopyWithImpl<$Res>
    implements $TriggerPassedEventCopyWith<$Res> {
  _$TriggerPassedEventCopyWithImpl(this._self, this._then);

  final TriggerPassedEvent _self;
  final $Res Function(TriggerPassedEvent) _then;

/// Create a copy of ReducerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? nextIteration = null,}) {
  return _then(TriggerPassedEvent(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,nextIteration: null == nextIteration ? _self.nextIteration : nextIteration // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
