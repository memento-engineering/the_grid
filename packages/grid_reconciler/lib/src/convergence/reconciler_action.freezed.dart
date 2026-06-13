// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'reconciler_action.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MetadataWrite {

 String get key; String get value;
/// Create a copy of MetadataWrite
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetadataWriteCopyWith<MetadataWrite> get copyWith => _$MetadataWriteCopyWithImpl<MetadataWrite>(this as MetadataWrite, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetadataWrite&&(identical(other.key, key) || other.key == key)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,key,value);



}

/// @nodoc
abstract mixin class $MetadataWriteCopyWith<$Res>  {
  factory $MetadataWriteCopyWith(MetadataWrite value, $Res Function(MetadataWrite) _then) = _$MetadataWriteCopyWithImpl;
@useResult
$Res call({
 String key, String value
});




}
/// @nodoc
class _$MetadataWriteCopyWithImpl<$Res>
    implements $MetadataWriteCopyWith<$Res> {
  _$MetadataWriteCopyWithImpl(this._self, this._then);

  final MetadataWrite _self;
  final $Res Function(MetadataWrite) _then;

/// Create a copy of MetadataWrite
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? value = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MetadataWrite].
extension MetadataWritePatterns on MetadataWrite {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetadataWrite value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetadataWrite() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetadataWrite value)  $default,){
final _that = this;
switch (_that) {
case _MetadataWrite():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetadataWrite value)?  $default,){
final _that = this;
switch (_that) {
case _MetadataWrite() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetadataWrite() when $default != null:
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String value)  $default,) {final _that = this;
switch (_that) {
case _MetadataWrite():
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String value)?  $default,) {final _that = this;
switch (_that) {
case _MetadataWrite() when $default != null:
return $default(_that.key,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _MetadataWrite extends MetadataWrite {
  const _MetadataWrite({required this.key, required this.value}): super._();
  

@override final  String key;
@override final  String value;

/// Create a copy of MetadataWrite
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetadataWriteCopyWith<_MetadataWrite> get copyWith => __$MetadataWriteCopyWithImpl<_MetadataWrite>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetadataWrite&&(identical(other.key, key) || other.key == key)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,key,value);



}

/// @nodoc
abstract mixin class _$MetadataWriteCopyWith<$Res> implements $MetadataWriteCopyWith<$Res> {
  factory _$MetadataWriteCopyWith(_MetadataWrite value, $Res Function(_MetadataWrite) _then) = __$MetadataWriteCopyWithImpl;
@override @useResult
$Res call({
 String key, String value
});




}
/// @nodoc
class __$MetadataWriteCopyWithImpl<$Res>
    implements _$MetadataWriteCopyWith<$Res> {
  __$MetadataWriteCopyWithImpl(this._self, this._then);

  final _MetadataWrite _self;
  final $Res Function(_MetadataWrite) _then;

/// Create a copy of MetadataWrite
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? value = null,}) {
  return _then(_MetadataWrite(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$WispPour {

/// The convergence root bead the wisp hangs off (a parent-child edge;
/// the `parent_id` column stays null — A15).
 String get parentBeadId;/// The formula to cook (`convergence.formula`).
 String get formula;/// `converge:{beadID}:iter:{N}` for [iteration].
 String get idempotencyKey;/// The 1-based iteration this pour creates.
 int get iteration;/// Template variables (`var.*` metadata, prefix stripped — template.go:43).
 Map<String, String> get vars;/// Prompt for the injected evaluate step (`convergence.evaluate_prompt`).
 String? get evaluatePrompt;/// True for the step-3b speculative pour (handler.go:98-100): the A15
/// graph plan is built with each actionable node poured as the
/// ready-excluded type `gate` and its real type/assignee/routing
/// stashed under [DeferredWispFields] (molecule.go:1009-1026) — agents
/// cannot claim it and `bd ready`/`bd children` never surface it.
/// Activation = per-node `bd update` promoting the deferred values
/// back (convergence_store.go:204-246; spike-verified). False for a
/// directly-visible pour (operator iterate, trigger advance).
 bool get speculative;
/// Create a copy of WispPour
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WispPourCopyWith<WispPour> get copyWith => _$WispPourCopyWithImpl<WispPour>(this as WispPour, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WispPour&&(identical(other.parentBeadId, parentBeadId) || other.parentBeadId == parentBeadId)&&(identical(other.formula, formula) || other.formula == formula)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&const DeepCollectionEquality().equals(other.vars, vars)&&(identical(other.evaluatePrompt, evaluatePrompt) || other.evaluatePrompt == evaluatePrompt)&&(identical(other.speculative, speculative) || other.speculative == speculative));
}


@override
int get hashCode => Object.hash(runtimeType,parentBeadId,formula,idempotencyKey,iteration,const DeepCollectionEquality().hash(vars),evaluatePrompt,speculative);

@override
String toString() {
  return 'WispPour(parentBeadId: $parentBeadId, formula: $formula, idempotencyKey: $idempotencyKey, iteration: $iteration, vars: $vars, evaluatePrompt: $evaluatePrompt, speculative: $speculative)';
}


}

/// @nodoc
abstract mixin class $WispPourCopyWith<$Res>  {
  factory $WispPourCopyWith(WispPour value, $Res Function(WispPour) _then) = _$WispPourCopyWithImpl;
@useResult
$Res call({
 String parentBeadId, String formula, String idempotencyKey, int iteration, Map<String, String> vars, String? evaluatePrompt, bool speculative
});




}
/// @nodoc
class _$WispPourCopyWithImpl<$Res>
    implements $WispPourCopyWith<$Res> {
  _$WispPourCopyWithImpl(this._self, this._then);

  final WispPour _self;
  final $Res Function(WispPour) _then;

/// Create a copy of WispPour
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? parentBeadId = null,Object? formula = null,Object? idempotencyKey = null,Object? iteration = null,Object? vars = null,Object? evaluatePrompt = freezed,Object? speculative = null,}) {
  return _then(_self.copyWith(
parentBeadId: null == parentBeadId ? _self.parentBeadId : parentBeadId // ignore: cast_nullable_to_non_nullable
as String,formula: null == formula ? _self.formula : formula // ignore: cast_nullable_to_non_nullable
as String,idempotencyKey: null == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,vars: null == vars ? _self.vars : vars // ignore: cast_nullable_to_non_nullable
as Map<String, String>,evaluatePrompt: freezed == evaluatePrompt ? _self.evaluatePrompt : evaluatePrompt // ignore: cast_nullable_to_non_nullable
as String?,speculative: null == speculative ? _self.speculative : speculative // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [WispPour].
extension WispPourPatterns on WispPour {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WispPour value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WispPour() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WispPour value)  $default,){
final _that = this;
switch (_that) {
case _WispPour():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WispPour value)?  $default,){
final _that = this;
switch (_that) {
case _WispPour() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String parentBeadId,  String formula,  String idempotencyKey,  int iteration,  Map<String, String> vars,  String? evaluatePrompt,  bool speculative)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WispPour() when $default != null:
return $default(_that.parentBeadId,_that.formula,_that.idempotencyKey,_that.iteration,_that.vars,_that.evaluatePrompt,_that.speculative);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String parentBeadId,  String formula,  String idempotencyKey,  int iteration,  Map<String, String> vars,  String? evaluatePrompt,  bool speculative)  $default,) {final _that = this;
switch (_that) {
case _WispPour():
return $default(_that.parentBeadId,_that.formula,_that.idempotencyKey,_that.iteration,_that.vars,_that.evaluatePrompt,_that.speculative);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String parentBeadId,  String formula,  String idempotencyKey,  int iteration,  Map<String, String> vars,  String? evaluatePrompt,  bool speculative)?  $default,) {final _that = this;
switch (_that) {
case _WispPour() when $default != null:
return $default(_that.parentBeadId,_that.formula,_that.idempotencyKey,_that.iteration,_that.vars,_that.evaluatePrompt,_that.speculative);case _:
  return null;

}
}

}

/// @nodoc


class _WispPour extends WispPour {
  const _WispPour({required this.parentBeadId, required this.formula, required this.idempotencyKey, required this.iteration, final  Map<String, String> vars = const <String, String>{}, this.evaluatePrompt, this.speculative = false}): _vars = vars,super._();
  

/// The convergence root bead the wisp hangs off (a parent-child edge;
/// the `parent_id` column stays null — A15).
@override final  String parentBeadId;
/// The formula to cook (`convergence.formula`).
@override final  String formula;
/// `converge:{beadID}:iter:{N}` for [iteration].
@override final  String idempotencyKey;
/// The 1-based iteration this pour creates.
@override final  int iteration;
/// Template variables (`var.*` metadata, prefix stripped — template.go:43).
 final  Map<String, String> _vars;
/// Template variables (`var.*` metadata, prefix stripped — template.go:43).
@override@JsonKey() Map<String, String> get vars {
  if (_vars is EqualUnmodifiableMapView) return _vars;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_vars);
}

/// Prompt for the injected evaluate step (`convergence.evaluate_prompt`).
@override final  String? evaluatePrompt;
/// True for the step-3b speculative pour (handler.go:98-100): the A15
/// graph plan is built with each actionable node poured as the
/// ready-excluded type `gate` and its real type/assignee/routing
/// stashed under [DeferredWispFields] (molecule.go:1009-1026) — agents
/// cannot claim it and `bd ready`/`bd children` never surface it.
/// Activation = per-node `bd update` promoting the deferred values
/// back (convergence_store.go:204-246; spike-verified). False for a
/// directly-visible pour (operator iterate, trigger advance).
@override@JsonKey() final  bool speculative;

/// Create a copy of WispPour
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WispPourCopyWith<_WispPour> get copyWith => __$WispPourCopyWithImpl<_WispPour>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WispPour&&(identical(other.parentBeadId, parentBeadId) || other.parentBeadId == parentBeadId)&&(identical(other.formula, formula) || other.formula == formula)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&const DeepCollectionEquality().equals(other._vars, _vars)&&(identical(other.evaluatePrompt, evaluatePrompt) || other.evaluatePrompt == evaluatePrompt)&&(identical(other.speculative, speculative) || other.speculative == speculative));
}


@override
int get hashCode => Object.hash(runtimeType,parentBeadId,formula,idempotencyKey,iteration,const DeepCollectionEquality().hash(_vars),evaluatePrompt,speculative);

@override
String toString() {
  return 'WispPour(parentBeadId: $parentBeadId, formula: $formula, idempotencyKey: $idempotencyKey, iteration: $iteration, vars: $vars, evaluatePrompt: $evaluatePrompt, speculative: $speculative)';
}


}

/// @nodoc
abstract mixin class _$WispPourCopyWith<$Res> implements $WispPourCopyWith<$Res> {
  factory _$WispPourCopyWith(_WispPour value, $Res Function(_WispPour) _then) = __$WispPourCopyWithImpl;
@override @useResult
$Res call({
 String parentBeadId, String formula, String idempotencyKey, int iteration, Map<String, String> vars, String? evaluatePrompt, bool speculative
});




}
/// @nodoc
class __$WispPourCopyWithImpl<$Res>
    implements _$WispPourCopyWith<$Res> {
  __$WispPourCopyWithImpl(this._self, this._then);

  final _WispPour _self;
  final $Res Function(_WispPour) _then;

/// Create a copy of WispPour
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? parentBeadId = null,Object? formula = null,Object? idempotencyKey = null,Object? iteration = null,Object? vars = null,Object? evaluatePrompt = freezed,Object? speculative = null,}) {
  return _then(_WispPour(
parentBeadId: null == parentBeadId ? _self.parentBeadId : parentBeadId // ignore: cast_nullable_to_non_nullable
as String,formula: null == formula ? _self.formula : formula // ignore: cast_nullable_to_non_nullable
as String,idempotencyKey: null == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,vars: null == vars ? _self._vars : vars // ignore: cast_nullable_to_non_nullable
as Map<String, String>,evaluatePrompt: freezed == evaluatePrompt ? _self.evaluatePrompt : evaluatePrompt // ignore: cast_nullable_to_non_nullable
as String?,speculative: null == speculative ? _self.speculative : speculative // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$EventEmission {

/// Normalized verdict scoped to the closed wisp, `''` when unscoped —
/// the *payload* semantics (handler.go:532-535), NOT the gate path's
/// `block` substitute (handler.go:319-324).
 String get agentVerdict;/// `gateConfig.Mode` for the payload. The stop path's synthetic
/// iteration event defaults an empty stored mode to manual
/// (manual.go:387-389).
 GateMode? get gateMode;/// Full gate result for `GateResultToPayload` parity (events.go:195-206
/// returns nil when the outcome is empty — no gate ran).
 GateResult? get gateResult;/// `wisp.ClosedAt − wisp.CreatedAt` (handler.go:830-835).
 Duration get iterationDuration;/// Σ closed convergence-keyed children durations (handler.go:837-849).
 Duration get cumulativeDuration;/// `PriorState` for `ManualActionPayload` (operator and trigger-advance
/// events — manual.go:97, 204, 422; trigger.go:167).
 ConvergenceState? get priorState;/// `convergence.rig`, stamped into EVERY emitted payload: gc's
/// `withEventRig` (handler.go:860-884) injects `meta[FieldRig]`
/// (metadata.go:35) into each payload type before marshalling; an
/// empty rig leaves the payload untouched (handler.go:862-864), so
/// null here ⇒ omit the field. gc re-reads live metadata for this
/// (`eventRig`, handler.go:886-895); the reducer populates it from the
/// SAME snapshot it reduced over — `convergence.rig` is written once
/// at create (create.go:27-31) and never mutated afterwards, so the
/// snapshot read is exact.
 String? get rig;/// gc's `eventWispID` local — the value of `ManualActionPayload
/// .wisp_id`, which comes from HERE and **never** from the
/// commit-write fields (the actions' `lastProcessedWisp` /
/// `closedWispId` are metadata WRITE values; they diverge from the
/// event value exactly in the corner cases: `active_wisp` still set
/// while waiting_manual on approve, and stop without a force-close).
/// Per-path selection, by the reducer, from the reduced-over snapshot:
///
/// * **operator approve**: `active_wisp`, falling back to
///   `last_processed_wisp` when empty (manual.go:54-56; payload
///   manual.go:100);
/// * **operator stop**: the same active-else-last-processed selection,
///   evaluated AFTER the drain/recovery/force-close steps refreshed
///   `active_wisp` (manual.go:359-361; payload manual.go:425). The
///   synthetic force-close iteration payload uses the force-closed
///   wisp id directly, not this field (manual.go:398);
/// * **operator iterate**: `last_processed_wisp` — the PRIOR wisp,
///   never the just-poured one, which travels as `next_wisp_id`
///   (manual.go:207-208);
/// * **trigger advance**: `last_processed_wisp`, null on the
///   entry-gated first iteration (trigger.go:170).
///
/// Null ⇒ `wisp_id` marshals as JSON null (gc's `NullableString` of
/// the empty string).
 String? get eventWispId;
/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<EventEmission> get copyWith => _$EventEmissionCopyWithImpl<EventEmission>(this as EventEmission, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EventEmission&&(identical(other.agentVerdict, agentVerdict) || other.agentVerdict == agentVerdict)&&(identical(other.gateMode, gateMode) || other.gateMode == gateMode)&&(identical(other.gateResult, gateResult) || other.gateResult == gateResult)&&(identical(other.iterationDuration, iterationDuration) || other.iterationDuration == iterationDuration)&&(identical(other.cumulativeDuration, cumulativeDuration) || other.cumulativeDuration == cumulativeDuration)&&(identical(other.priorState, priorState) || other.priorState == priorState)&&(identical(other.rig, rig) || other.rig == rig)&&(identical(other.eventWispId, eventWispId) || other.eventWispId == eventWispId));
}


@override
int get hashCode => Object.hash(runtimeType,agentVerdict,gateMode,gateResult,iterationDuration,cumulativeDuration,priorState,rig,eventWispId);

@override
String toString() {
  return 'EventEmission(agentVerdict: $agentVerdict, gateMode: $gateMode, gateResult: $gateResult, iterationDuration: $iterationDuration, cumulativeDuration: $cumulativeDuration, priorState: $priorState, rig: $rig, eventWispId: $eventWispId)';
}


}

/// @nodoc
abstract mixin class $EventEmissionCopyWith<$Res>  {
  factory $EventEmissionCopyWith(EventEmission value, $Res Function(EventEmission) _then) = _$EventEmissionCopyWithImpl;
@useResult
$Res call({
 String agentVerdict, GateMode? gateMode, GateResult? gateResult, Duration iterationDuration, Duration cumulativeDuration, ConvergenceState? priorState, String? rig, String? eventWispId
});


$GateResultCopyWith<$Res>? get gateResult;

}
/// @nodoc
class _$EventEmissionCopyWithImpl<$Res>
    implements $EventEmissionCopyWith<$Res> {
  _$EventEmissionCopyWithImpl(this._self, this._then);

  final EventEmission _self;
  final $Res Function(EventEmission) _then;

/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? agentVerdict = null,Object? gateMode = freezed,Object? gateResult = freezed,Object? iterationDuration = null,Object? cumulativeDuration = null,Object? priorState = freezed,Object? rig = freezed,Object? eventWispId = freezed,}) {
  return _then(_self.copyWith(
agentVerdict: null == agentVerdict ? _self.agentVerdict : agentVerdict // ignore: cast_nullable_to_non_nullable
as String,gateMode: freezed == gateMode ? _self.gateMode : gateMode // ignore: cast_nullable_to_non_nullable
as GateMode?,gateResult: freezed == gateResult ? _self.gateResult : gateResult // ignore: cast_nullable_to_non_nullable
as GateResult?,iterationDuration: null == iterationDuration ? _self.iterationDuration : iterationDuration // ignore: cast_nullable_to_non_nullable
as Duration,cumulativeDuration: null == cumulativeDuration ? _self.cumulativeDuration : cumulativeDuration // ignore: cast_nullable_to_non_nullable
as Duration,priorState: freezed == priorState ? _self.priorState : priorState // ignore: cast_nullable_to_non_nullable
as ConvergenceState?,rig: freezed == rig ? _self.rig : rig // ignore: cast_nullable_to_non_nullable
as String?,eventWispId: freezed == eventWispId ? _self.eventWispId : eventWispId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GateResultCopyWith<$Res>? get gateResult {
    if (_self.gateResult == null) {
    return null;
  }

  return $GateResultCopyWith<$Res>(_self.gateResult!, (value) {
    return _then(_self.copyWith(gateResult: value));
  });
}
}


/// Adds pattern-matching-related methods to [EventEmission].
extension EventEmissionPatterns on EventEmission {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _EventEmission value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _EventEmission() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _EventEmission value)  $default,){
final _that = this;
switch (_that) {
case _EventEmission():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _EventEmission value)?  $default,){
final _that = this;
switch (_that) {
case _EventEmission() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String agentVerdict,  GateMode? gateMode,  GateResult? gateResult,  Duration iterationDuration,  Duration cumulativeDuration,  ConvergenceState? priorState,  String? rig,  String? eventWispId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _EventEmission() when $default != null:
return $default(_that.agentVerdict,_that.gateMode,_that.gateResult,_that.iterationDuration,_that.cumulativeDuration,_that.priorState,_that.rig,_that.eventWispId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String agentVerdict,  GateMode? gateMode,  GateResult? gateResult,  Duration iterationDuration,  Duration cumulativeDuration,  ConvergenceState? priorState,  String? rig,  String? eventWispId)  $default,) {final _that = this;
switch (_that) {
case _EventEmission():
return $default(_that.agentVerdict,_that.gateMode,_that.gateResult,_that.iterationDuration,_that.cumulativeDuration,_that.priorState,_that.rig,_that.eventWispId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String agentVerdict,  GateMode? gateMode,  GateResult? gateResult,  Duration iterationDuration,  Duration cumulativeDuration,  ConvergenceState? priorState,  String? rig,  String? eventWispId)?  $default,) {final _that = this;
switch (_that) {
case _EventEmission() when $default != null:
return $default(_that.agentVerdict,_that.gateMode,_that.gateResult,_that.iterationDuration,_that.cumulativeDuration,_that.priorState,_that.rig,_that.eventWispId);case _:
  return null;

}
}

}

/// @nodoc


class _EventEmission extends EventEmission {
  const _EventEmission({this.agentVerdict = '', this.gateMode, this.gateResult, this.iterationDuration = Duration.zero, this.cumulativeDuration = Duration.zero, this.priorState, this.rig, this.eventWispId}): super._();
  

/// Normalized verdict scoped to the closed wisp, `''` when unscoped —
/// the *payload* semantics (handler.go:532-535), NOT the gate path's
/// `block` substitute (handler.go:319-324).
@override@JsonKey() final  String agentVerdict;
/// `gateConfig.Mode` for the payload. The stop path's synthetic
/// iteration event defaults an empty stored mode to manual
/// (manual.go:387-389).
@override final  GateMode? gateMode;
/// Full gate result for `GateResultToPayload` parity (events.go:195-206
/// returns nil when the outcome is empty — no gate ran).
@override final  GateResult? gateResult;
/// `wisp.ClosedAt − wisp.CreatedAt` (handler.go:830-835).
@override@JsonKey() final  Duration iterationDuration;
/// Σ closed convergence-keyed children durations (handler.go:837-849).
@override@JsonKey() final  Duration cumulativeDuration;
/// `PriorState` for `ManualActionPayload` (operator and trigger-advance
/// events — manual.go:97, 204, 422; trigger.go:167).
@override final  ConvergenceState? priorState;
/// `convergence.rig`, stamped into EVERY emitted payload: gc's
/// `withEventRig` (handler.go:860-884) injects `meta[FieldRig]`
/// (metadata.go:35) into each payload type before marshalling; an
/// empty rig leaves the payload untouched (handler.go:862-864), so
/// null here ⇒ omit the field. gc re-reads live metadata for this
/// (`eventRig`, handler.go:886-895); the reducer populates it from the
/// SAME snapshot it reduced over — `convergence.rig` is written once
/// at create (create.go:27-31) and never mutated afterwards, so the
/// snapshot read is exact.
@override final  String? rig;
/// gc's `eventWispID` local — the value of `ManualActionPayload
/// .wisp_id`, which comes from HERE and **never** from the
/// commit-write fields (the actions' `lastProcessedWisp` /
/// `closedWispId` are metadata WRITE values; they diverge from the
/// event value exactly in the corner cases: `active_wisp` still set
/// while waiting_manual on approve, and stop without a force-close).
/// Per-path selection, by the reducer, from the reduced-over snapshot:
///
/// * **operator approve**: `active_wisp`, falling back to
///   `last_processed_wisp` when empty (manual.go:54-56; payload
///   manual.go:100);
/// * **operator stop**: the same active-else-last-processed selection,
///   evaluated AFTER the drain/recovery/force-close steps refreshed
///   `active_wisp` (manual.go:359-361; payload manual.go:425). The
///   synthetic force-close iteration payload uses the force-closed
///   wisp id directly, not this field (manual.go:398);
/// * **operator iterate**: `last_processed_wisp` — the PRIOR wisp,
///   never the just-poured one, which travels as `next_wisp_id`
///   (manual.go:207-208);
/// * **trigger advance**: `last_processed_wisp`, null on the
///   entry-gated first iteration (trigger.go:170).
///
/// Null ⇒ `wisp_id` marshals as JSON null (gc's `NullableString` of
/// the empty string).
@override final  String? eventWispId;

/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$EventEmissionCopyWith<_EventEmission> get copyWith => __$EventEmissionCopyWithImpl<_EventEmission>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _EventEmission&&(identical(other.agentVerdict, agentVerdict) || other.agentVerdict == agentVerdict)&&(identical(other.gateMode, gateMode) || other.gateMode == gateMode)&&(identical(other.gateResult, gateResult) || other.gateResult == gateResult)&&(identical(other.iterationDuration, iterationDuration) || other.iterationDuration == iterationDuration)&&(identical(other.cumulativeDuration, cumulativeDuration) || other.cumulativeDuration == cumulativeDuration)&&(identical(other.priorState, priorState) || other.priorState == priorState)&&(identical(other.rig, rig) || other.rig == rig)&&(identical(other.eventWispId, eventWispId) || other.eventWispId == eventWispId));
}


@override
int get hashCode => Object.hash(runtimeType,agentVerdict,gateMode,gateResult,iterationDuration,cumulativeDuration,priorState,rig,eventWispId);

@override
String toString() {
  return 'EventEmission(agentVerdict: $agentVerdict, gateMode: $gateMode, gateResult: $gateResult, iterationDuration: $iterationDuration, cumulativeDuration: $cumulativeDuration, priorState: $priorState, rig: $rig, eventWispId: $eventWispId)';
}


}

/// @nodoc
abstract mixin class _$EventEmissionCopyWith<$Res> implements $EventEmissionCopyWith<$Res> {
  factory _$EventEmissionCopyWith(_EventEmission value, $Res Function(_EventEmission) _then) = __$EventEmissionCopyWithImpl;
@override @useResult
$Res call({
 String agentVerdict, GateMode? gateMode, GateResult? gateResult, Duration iterationDuration, Duration cumulativeDuration, ConvergenceState? priorState, String? rig, String? eventWispId
});


@override $GateResultCopyWith<$Res>? get gateResult;

}
/// @nodoc
class __$EventEmissionCopyWithImpl<$Res>
    implements _$EventEmissionCopyWith<$Res> {
  __$EventEmissionCopyWithImpl(this._self, this._then);

  final _EventEmission _self;
  final $Res Function(_EventEmission) _then;

/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? agentVerdict = null,Object? gateMode = freezed,Object? gateResult = freezed,Object? iterationDuration = null,Object? cumulativeDuration = null,Object? priorState = freezed,Object? rig = freezed,Object? eventWispId = freezed,}) {
  return _then(_EventEmission(
agentVerdict: null == agentVerdict ? _self.agentVerdict : agentVerdict // ignore: cast_nullable_to_non_nullable
as String,gateMode: freezed == gateMode ? _self.gateMode : gateMode // ignore: cast_nullable_to_non_nullable
as GateMode?,gateResult: freezed == gateResult ? _self.gateResult : gateResult // ignore: cast_nullable_to_non_nullable
as GateResult?,iterationDuration: null == iterationDuration ? _self.iterationDuration : iterationDuration // ignore: cast_nullable_to_non_nullable
as Duration,cumulativeDuration: null == cumulativeDuration ? _self.cumulativeDuration : cumulativeDuration // ignore: cast_nullable_to_non_nullable
as Duration,priorState: freezed == priorState ? _self.priorState : priorState // ignore: cast_nullable_to_non_nullable
as ConvergenceState?,rig: freezed == rig ? _self.rig : rig // ignore: cast_nullable_to_non_nullable
as String?,eventWispId: freezed == eventWispId ? _self.eventWispId : eventWispId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of EventEmission
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GateResultCopyWith<$Res>? get gateResult {
    if (_self.gateResult == null) {
    return null;
  }

  return $GateResultCopyWith<$Res>(_self.gateResult!, (value) {
    return _then(_self.copyWith(gateResult: value));
  });
}
}

/// @nodoc
mixin _$ReconcilerAction {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReconcilerAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ReconcilerAction()';
}


}

/// @nodoc
class $ReconcilerActionCopyWith<$Res>  {
$ReconcilerActionCopyWith(ReconcilerAction _, $Res Function(ReconcilerAction) __);
}


/// Adds pattern-matching-related methods to [ReconcilerAction].
extension ReconcilerActionPatterns on ReconcilerAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IterateAction value)?  iterate,TResult Function( ApprovedAction value)?  approved,TResult Function( NoConvergenceAction value)?  noConvergence,TResult Function( WaitingManualAction value)?  waitingManual,TResult Function( WaitingTriggerAction value)?  waitingTrigger,TResult Function( StoppedAction value)?  stopped,TResult Function( SkippedAction value)?  skipped,TResult Function( PourSpeculativeAction value)?  pourSpeculative,TResult Function( EvaluateGateAction value)?  evaluateGate,TResult Function( PersistGateOutcomeAction value)?  persistGateOutcome,TResult Function( RepairIterationAction value)?  repairIteration,TResult Function( FailedAction value)?  failed,TResult Function( RequeueAction value)?  requeue,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IterateAction() when iterate != null:
return iterate(_that);case ApprovedAction() when approved != null:
return approved(_that);case NoConvergenceAction() when noConvergence != null:
return noConvergence(_that);case WaitingManualAction() when waitingManual != null:
return waitingManual(_that);case WaitingTriggerAction() when waitingTrigger != null:
return waitingTrigger(_that);case StoppedAction() when stopped != null:
return stopped(_that);case SkippedAction() when skipped != null:
return skipped(_that);case PourSpeculativeAction() when pourSpeculative != null:
return pourSpeculative(_that);case EvaluateGateAction() when evaluateGate != null:
return evaluateGate(_that);case PersistGateOutcomeAction() when persistGateOutcome != null:
return persistGateOutcome(_that);case RepairIterationAction() when repairIteration != null:
return repairIteration(_that);case FailedAction() when failed != null:
return failed(_that);case RequeueAction() when requeue != null:
return requeue(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IterateAction value)  iterate,required TResult Function( ApprovedAction value)  approved,required TResult Function( NoConvergenceAction value)  noConvergence,required TResult Function( WaitingManualAction value)  waitingManual,required TResult Function( WaitingTriggerAction value)  waitingTrigger,required TResult Function( StoppedAction value)  stopped,required TResult Function( SkippedAction value)  skipped,required TResult Function( PourSpeculativeAction value)  pourSpeculative,required TResult Function( EvaluateGateAction value)  evaluateGate,required TResult Function( PersistGateOutcomeAction value)  persistGateOutcome,required TResult Function( RepairIterationAction value)  repairIteration,required TResult Function( FailedAction value)  failed,required TResult Function( RequeueAction value)  requeue,}){
final _that = this;
switch (_that) {
case IterateAction():
return iterate(_that);case ApprovedAction():
return approved(_that);case NoConvergenceAction():
return noConvergence(_that);case WaitingManualAction():
return waitingManual(_that);case WaitingTriggerAction():
return waitingTrigger(_that);case StoppedAction():
return stopped(_that);case SkippedAction():
return skipped(_that);case PourSpeculativeAction():
return pourSpeculative(_that);case EvaluateGateAction():
return evaluateGate(_that);case PersistGateOutcomeAction():
return persistGateOutcome(_that);case RepairIterationAction():
return repairIteration(_that);case FailedAction():
return failed(_that);case RequeueAction():
return requeue(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IterateAction value)?  iterate,TResult? Function( ApprovedAction value)?  approved,TResult? Function( NoConvergenceAction value)?  noConvergence,TResult? Function( WaitingManualAction value)?  waitingManual,TResult? Function( WaitingTriggerAction value)?  waitingTrigger,TResult? Function( StoppedAction value)?  stopped,TResult? Function( SkippedAction value)?  skipped,TResult? Function( PourSpeculativeAction value)?  pourSpeculative,TResult? Function( EvaluateGateAction value)?  evaluateGate,TResult? Function( PersistGateOutcomeAction value)?  persistGateOutcome,TResult? Function( RepairIterationAction value)?  repairIteration,TResult? Function( FailedAction value)?  failed,TResult? Function( RequeueAction value)?  requeue,}){
final _that = this;
switch (_that) {
case IterateAction() when iterate != null:
return iterate(_that);case ApprovedAction() when approved != null:
return approved(_that);case NoConvergenceAction() when noConvergence != null:
return noConvergence(_that);case WaitingManualAction() when waitingManual != null:
return waitingManual(_that);case WaitingTriggerAction() when waitingTrigger != null:
return waitingTrigger(_that);case StoppedAction() when stopped != null:
return stopped(_that);case SkippedAction() when skipped != null:
return skipped(_that);case PourSpeculativeAction() when pourSpeculative != null:
return pourSpeculative(_that);case EvaluateGateAction() when evaluateGate != null:
return evaluateGate(_that);case PersistGateOutcomeAction() when persistGateOutcome != null:
return persistGateOutcome(_that);case RepairIterationAction() when repairIteration != null:
return repairIteration(_that);case FailedAction() when failed != null:
return failed(_that);case RequeueAction() when requeue != null:
return requeue(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String convergenceBeadId,  int iteration,  WispPour pour,  IteratePath path,  String? adoptWispId,  bool adoptFromPriorPour,  String? closedWispId,  bool clearVerdict,  GateOutcome? gateOutcome,  WaitingManualAction? slingFailureFallback,  EventEmission? events)?  iterate,TResult Function( String convergenceBeadId,  TerminalPath path,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearWaitingReason,  String closeReason,  EventEmission? events)?  approved,TResult Function( String convergenceBeadId,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  String closeReason,  EventEmission? events)?  noConvergence,TResult Function( String convergenceBeadId,  String closedWispId,  int iteration,  WaitingReason reason,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearStalePending,  EventEmission? events)?  waitingManual,TResult Function( String convergenceBeadId,  String closedWispId,  int iteration,  GateOutcome? gateOutcome,  bool clearVerdict,  EventEmission? events)?  waitingTrigger,TResult Function( String convergenceBeadId,  String actor,  int totalIterations,  String? lastProcessedWisp,  String? forceCloseWispId,  String closeReason,  EventEmission? events)?  stopped,TResult Function( String convergenceBeadId,  String? wispId,  SkipReason reason,  String? detail,  bool closeRootBestEffort)?  skipped,TResult Function( String convergenceBeadId,  WispPour pour,  String? adoptPendingWispId,  bool clearStalePending)?  pourSpeculative,TResult Function( String convergenceBeadId,  String wispId,  int iteration,  GateConfig config,  GateEnvInputs env)?  evaluateGate,TResult Function( String convergenceBeadId,  String wispId,  GateResult result,  String? burnWispId)?  persistGateOutcome,TResult Function( String convergenceBeadId,  int derivedIteration,  int storedIteration)?  repairIteration,TResult Function( String convergenceBeadId,  String message,  String? burnWispId,  bool clearStalePending)?  failed,TResult Function( ReducerEvent event,  String reason)?  requeue,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IterateAction() when iterate != null:
return iterate(_that.convergenceBeadId,_that.iteration,_that.pour,_that.path,_that.adoptWispId,_that.adoptFromPriorPour,_that.closedWispId,_that.clearVerdict,_that.gateOutcome,_that.slingFailureFallback,_that.events);case ApprovedAction() when approved != null:
return approved(_that.convergenceBeadId,_that.path,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearWaitingReason,_that.closeReason,_that.events);case NoConvergenceAction() when noConvergence != null:
return noConvergence(_that.convergenceBeadId,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.closeReason,_that.events);case WaitingManualAction() when waitingManual != null:
return waitingManual(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.reason,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearStalePending,_that.events);case WaitingTriggerAction() when waitingTrigger != null:
return waitingTrigger(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.gateOutcome,_that.clearVerdict,_that.events);case StoppedAction() when stopped != null:
return stopped(_that.convergenceBeadId,_that.actor,_that.totalIterations,_that.lastProcessedWisp,_that.forceCloseWispId,_that.closeReason,_that.events);case SkippedAction() when skipped != null:
return skipped(_that.convergenceBeadId,_that.wispId,_that.reason,_that.detail,_that.closeRootBestEffort);case PourSpeculativeAction() when pourSpeculative != null:
return pourSpeculative(_that.convergenceBeadId,_that.pour,_that.adoptPendingWispId,_that.clearStalePending);case EvaluateGateAction() when evaluateGate != null:
return evaluateGate(_that.convergenceBeadId,_that.wispId,_that.iteration,_that.config,_that.env);case PersistGateOutcomeAction() when persistGateOutcome != null:
return persistGateOutcome(_that.convergenceBeadId,_that.wispId,_that.result,_that.burnWispId);case RepairIterationAction() when repairIteration != null:
return repairIteration(_that.convergenceBeadId,_that.derivedIteration,_that.storedIteration);case FailedAction() when failed != null:
return failed(_that.convergenceBeadId,_that.message,_that.burnWispId,_that.clearStalePending);case RequeueAction() when requeue != null:
return requeue(_that.event,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String convergenceBeadId,  int iteration,  WispPour pour,  IteratePath path,  String? adoptWispId,  bool adoptFromPriorPour,  String? closedWispId,  bool clearVerdict,  GateOutcome? gateOutcome,  WaitingManualAction? slingFailureFallback,  EventEmission? events)  iterate,required TResult Function( String convergenceBeadId,  TerminalPath path,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearWaitingReason,  String closeReason,  EventEmission? events)  approved,required TResult Function( String convergenceBeadId,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  String closeReason,  EventEmission? events)  noConvergence,required TResult Function( String convergenceBeadId,  String closedWispId,  int iteration,  WaitingReason reason,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearStalePending,  EventEmission? events)  waitingManual,required TResult Function( String convergenceBeadId,  String closedWispId,  int iteration,  GateOutcome? gateOutcome,  bool clearVerdict,  EventEmission? events)  waitingTrigger,required TResult Function( String convergenceBeadId,  String actor,  int totalIterations,  String? lastProcessedWisp,  String? forceCloseWispId,  String closeReason,  EventEmission? events)  stopped,required TResult Function( String convergenceBeadId,  String? wispId,  SkipReason reason,  String? detail,  bool closeRootBestEffort)  skipped,required TResult Function( String convergenceBeadId,  WispPour pour,  String? adoptPendingWispId,  bool clearStalePending)  pourSpeculative,required TResult Function( String convergenceBeadId,  String wispId,  int iteration,  GateConfig config,  GateEnvInputs env)  evaluateGate,required TResult Function( String convergenceBeadId,  String wispId,  GateResult result,  String? burnWispId)  persistGateOutcome,required TResult Function( String convergenceBeadId,  int derivedIteration,  int storedIteration)  repairIteration,required TResult Function( String convergenceBeadId,  String message,  String? burnWispId,  bool clearStalePending)  failed,required TResult Function( ReducerEvent event,  String reason)  requeue,}) {final _that = this;
switch (_that) {
case IterateAction():
return iterate(_that.convergenceBeadId,_that.iteration,_that.pour,_that.path,_that.adoptWispId,_that.adoptFromPriorPour,_that.closedWispId,_that.clearVerdict,_that.gateOutcome,_that.slingFailureFallback,_that.events);case ApprovedAction():
return approved(_that.convergenceBeadId,_that.path,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearWaitingReason,_that.closeReason,_that.events);case NoConvergenceAction():
return noConvergence(_that.convergenceBeadId,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.closeReason,_that.events);case WaitingManualAction():
return waitingManual(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.reason,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearStalePending,_that.events);case WaitingTriggerAction():
return waitingTrigger(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.gateOutcome,_that.clearVerdict,_that.events);case StoppedAction():
return stopped(_that.convergenceBeadId,_that.actor,_that.totalIterations,_that.lastProcessedWisp,_that.forceCloseWispId,_that.closeReason,_that.events);case SkippedAction():
return skipped(_that.convergenceBeadId,_that.wispId,_that.reason,_that.detail,_that.closeRootBestEffort);case PourSpeculativeAction():
return pourSpeculative(_that.convergenceBeadId,_that.pour,_that.adoptPendingWispId,_that.clearStalePending);case EvaluateGateAction():
return evaluateGate(_that.convergenceBeadId,_that.wispId,_that.iteration,_that.config,_that.env);case PersistGateOutcomeAction():
return persistGateOutcome(_that.convergenceBeadId,_that.wispId,_that.result,_that.burnWispId);case RepairIterationAction():
return repairIteration(_that.convergenceBeadId,_that.derivedIteration,_that.storedIteration);case FailedAction():
return failed(_that.convergenceBeadId,_that.message,_that.burnWispId,_that.clearStalePending);case RequeueAction():
return requeue(_that.event,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String convergenceBeadId,  int iteration,  WispPour pour,  IteratePath path,  String? adoptWispId,  bool adoptFromPriorPour,  String? closedWispId,  bool clearVerdict,  GateOutcome? gateOutcome,  WaitingManualAction? slingFailureFallback,  EventEmission? events)?  iterate,TResult? Function( String convergenceBeadId,  TerminalPath path,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearWaitingReason,  String closeReason,  EventEmission? events)?  approved,TResult? Function( String convergenceBeadId,  String actor,  int iteration,  int totalIterations,  String? lastProcessedWisp,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  String closeReason,  EventEmission? events)?  noConvergence,TResult? Function( String convergenceBeadId,  String closedWispId,  int iteration,  WaitingReason reason,  GateOutcome? gateOutcome,  String? burnWispId,  bool burnPriorPour,  bool clearStalePending,  EventEmission? events)?  waitingManual,TResult? Function( String convergenceBeadId,  String closedWispId,  int iteration,  GateOutcome? gateOutcome,  bool clearVerdict,  EventEmission? events)?  waitingTrigger,TResult? Function( String convergenceBeadId,  String actor,  int totalIterations,  String? lastProcessedWisp,  String? forceCloseWispId,  String closeReason,  EventEmission? events)?  stopped,TResult? Function( String convergenceBeadId,  String? wispId,  SkipReason reason,  String? detail,  bool closeRootBestEffort)?  skipped,TResult? Function( String convergenceBeadId,  WispPour pour,  String? adoptPendingWispId,  bool clearStalePending)?  pourSpeculative,TResult? Function( String convergenceBeadId,  String wispId,  int iteration,  GateConfig config,  GateEnvInputs env)?  evaluateGate,TResult? Function( String convergenceBeadId,  String wispId,  GateResult result,  String? burnWispId)?  persistGateOutcome,TResult? Function( String convergenceBeadId,  int derivedIteration,  int storedIteration)?  repairIteration,TResult? Function( String convergenceBeadId,  String message,  String? burnWispId,  bool clearStalePending)?  failed,TResult? Function( ReducerEvent event,  String reason)?  requeue,}) {final _that = this;
switch (_that) {
case IterateAction() when iterate != null:
return iterate(_that.convergenceBeadId,_that.iteration,_that.pour,_that.path,_that.adoptWispId,_that.adoptFromPriorPour,_that.closedWispId,_that.clearVerdict,_that.gateOutcome,_that.slingFailureFallback,_that.events);case ApprovedAction() when approved != null:
return approved(_that.convergenceBeadId,_that.path,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearWaitingReason,_that.closeReason,_that.events);case NoConvergenceAction() when noConvergence != null:
return noConvergence(_that.convergenceBeadId,_that.actor,_that.iteration,_that.totalIterations,_that.lastProcessedWisp,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.closeReason,_that.events);case WaitingManualAction() when waitingManual != null:
return waitingManual(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.reason,_that.gateOutcome,_that.burnWispId,_that.burnPriorPour,_that.clearStalePending,_that.events);case WaitingTriggerAction() when waitingTrigger != null:
return waitingTrigger(_that.convergenceBeadId,_that.closedWispId,_that.iteration,_that.gateOutcome,_that.clearVerdict,_that.events);case StoppedAction() when stopped != null:
return stopped(_that.convergenceBeadId,_that.actor,_that.totalIterations,_that.lastProcessedWisp,_that.forceCloseWispId,_that.closeReason,_that.events);case SkippedAction() when skipped != null:
return skipped(_that.convergenceBeadId,_that.wispId,_that.reason,_that.detail,_that.closeRootBestEffort);case PourSpeculativeAction() when pourSpeculative != null:
return pourSpeculative(_that.convergenceBeadId,_that.pour,_that.adoptPendingWispId,_that.clearStalePending);case EvaluateGateAction() when evaluateGate != null:
return evaluateGate(_that.convergenceBeadId,_that.wispId,_that.iteration,_that.config,_that.env);case PersistGateOutcomeAction() when persistGateOutcome != null:
return persistGateOutcome(_that.convergenceBeadId,_that.wispId,_that.result,_that.burnWispId);case RepairIterationAction() when repairIteration != null:
return repairIteration(_that.convergenceBeadId,_that.derivedIteration,_that.storedIteration);case FailedAction() when failed != null:
return failed(_that.convergenceBeadId,_that.message,_that.burnWispId,_that.clearStalePending);case RequeueAction() when requeue != null:
return requeue(_that.event,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class IterateAction extends ReconcilerAction {
  const IterateAction({required this.convergenceBeadId, required this.iteration, required this.pour, required this.path, this.adoptWispId, this.adoptFromPriorPour = false, this.closedWispId, this.clearVerdict = false, this.gateOutcome, this.slingFailureFallback, this.events}): super._();
  

 final  String convergenceBeadId;
/// gc `HandlerResult.Iteration`: the closed wisp's iteration on
/// [IteratePath.wispClosed]; the NEW iteration on
/// [IteratePath.operatorIterate] (manual.go:214) and
/// [IteratePath.triggerAdvance] (trigger.go:177).
 final  int iteration;
/// The pour payload for the **next** wisp.
 final  WispPour pour;
/// Which gc path this decision came from — selects the write protocol.
 final  IteratePath path;
/// A speculatively-poured wisp to adopt instead of pouring
/// (handler.go:505-507). wispClosed path only. Reduce-time-known ids
/// only: the snapshot's validated `pending_next_wisp`, or phase 2's
/// `GateEvaluatedEvent.pouredSpeculativeWispId`.
 final  String? adoptWispId;
/// wispClosed path only: bind the wisp produced by the
/// [ReconcilerAction.pourSpeculative] earlier in the SAME action list —
/// the pour result no reduce input can name (the replay path pours at
/// 3b in the same reduce that decides to iterate). Mutually exclusive
/// with [adoptWispId]; see protocol step 2 and the class-doc in-list
/// dataflow rule.
@JsonKey() final  bool adoptFromPriorPour;
/// The wisp whose closure triggered this — becomes the new
/// `last_processed_wisp`. Null off the wispClosed path, which alone
/// writes the dedup marker.
 final  String? closedWispId;
/// True when the verdict is scoped and must be cleared — scoped to the
/// closed wisp on the wispClosed path (handler.go:491), to
/// `last_processed_wisp` on the operator path (manual.go:180).
@JsonKey() final  bool clearVerdict;
/// The gate outcome that decided to iterate (informational).
 final  GateOutcome? gateOutcome;
/// wispClosed path only: the pre-built `sling_failure` waiting_manual
/// transition the actuator executes when the fallback pour fails AND
/// the idempotency probe misses (handler.go:520-521 →
/// handleSlingFailure, 714-726).
 final  WaitingManualAction? slingFailureFallback;
/// Step-8 event data (`convergence.iteration` on the wispClosed path,
/// emitted BEFORE the commit writes, handler.go:538-553;
/// `manual_iterate` / `trigger_advance` on the others, emitted after
/// their writes — manual.go:201-210, trigger.go:158-173).
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IterateActionCopyWith<IterateAction> get copyWith => _$IterateActionCopyWithImpl<IterateAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IterateAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.pour, pour) || other.pour == pour)&&(identical(other.path, path) || other.path == path)&&(identical(other.adoptWispId, adoptWispId) || other.adoptWispId == adoptWispId)&&(identical(other.adoptFromPriorPour, adoptFromPriorPour) || other.adoptFromPriorPour == adoptFromPriorPour)&&(identical(other.closedWispId, closedWispId) || other.closedWispId == closedWispId)&&(identical(other.clearVerdict, clearVerdict) || other.clearVerdict == clearVerdict)&&(identical(other.gateOutcome, gateOutcome) || other.gateOutcome == gateOutcome)&&const DeepCollectionEquality().equals(other.slingFailureFallback, slingFailureFallback)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,iteration,pour,path,adoptWispId,adoptFromPriorPour,closedWispId,clearVerdict,gateOutcome,const DeepCollectionEquality().hash(slingFailureFallback),events);

@override
String toString() {
  return 'ReconcilerAction.iterate(convergenceBeadId: $convergenceBeadId, iteration: $iteration, pour: $pour, path: $path, adoptWispId: $adoptWispId, adoptFromPriorPour: $adoptFromPriorPour, closedWispId: $closedWispId, clearVerdict: $clearVerdict, gateOutcome: $gateOutcome, slingFailureFallback: $slingFailureFallback, events: $events)';
}


}

/// @nodoc
abstract mixin class $IterateActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $IterateActionCopyWith(IterateAction value, $Res Function(IterateAction) _then) = _$IterateActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, int iteration, WispPour pour, IteratePath path, String? adoptWispId, bool adoptFromPriorPour, String? closedWispId, bool clearVerdict, GateOutcome? gateOutcome, WaitingManualAction? slingFailureFallback, EventEmission? events
});


$WispPourCopyWith<$Res> get pour;$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$IterateActionCopyWithImpl<$Res>
    implements $IterateActionCopyWith<$Res> {
  _$IterateActionCopyWithImpl(this._self, this._then);

  final IterateAction _self;
  final $Res Function(IterateAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? iteration = null,Object? pour = null,Object? path = null,Object? adoptWispId = freezed,Object? adoptFromPriorPour = null,Object? closedWispId = freezed,Object? clearVerdict = null,Object? gateOutcome = freezed,Object? slingFailureFallback = freezed,Object? events = freezed,}) {
  return _then(IterateAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,pour: null == pour ? _self.pour : pour // ignore: cast_nullable_to_non_nullable
as WispPour,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as IteratePath,adoptWispId: freezed == adoptWispId ? _self.adoptWispId : adoptWispId // ignore: cast_nullable_to_non_nullable
as String?,adoptFromPriorPour: null == adoptFromPriorPour ? _self.adoptFromPriorPour : adoptFromPriorPour // ignore: cast_nullable_to_non_nullable
as bool,closedWispId: freezed == closedWispId ? _self.closedWispId : closedWispId // ignore: cast_nullable_to_non_nullable
as String?,clearVerdict: null == clearVerdict ? _self.clearVerdict : clearVerdict // ignore: cast_nullable_to_non_nullable
as bool,gateOutcome: freezed == gateOutcome ? _self.gateOutcome : gateOutcome // ignore: cast_nullable_to_non_nullable
as GateOutcome?,slingFailureFallback: freezed == slingFailureFallback ? _self.slingFailureFallback : slingFailureFallback // ignore: cast_nullable_to_non_nullable
as WaitingManualAction?,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WispPourCopyWith<$Res> get pour {
  
  return $WispPourCopyWith<$Res>(_self.pour, (value) {
    return _then(_self.copyWith(pour: value));
  });
}/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class ApprovedAction extends ReconcilerAction {
  const ApprovedAction({required this.convergenceBeadId, required this.path, required this.actor, required this.iteration, required this.totalIterations, this.lastProcessedWisp, this.gateOutcome, this.burnWispId, this.burnPriorPour = false, this.clearWaitingReason = false, required this.closeReason, this.events}): super._();
  

 final  String convergenceBeadId;
/// Which gc origin produced this terminal decision — selects the
/// protocol above. The [closeReason] constants happen to correlate
/// with the origin, but the ordering contract is selected HERE, never
/// parsed back out of a close-reason string.
 final  TerminalPath path;
/// `terminal_actor`: `controller` (handler.go:389) or
/// `operator:<user>` (manual.go:27).
 final  String actor;
/// gc `HandlerResult.Iteration`: the closed wisp's iteration on the
/// handler path (handler.go:708); the derived count on operator
/// approve (manual.go:113). Also the `convergence.iteration` event ID
/// component (`converge:<bead>:iter:<N>:iteration`, events.go:42-46).
 final  int iteration;
/// Derived closed-wisp count (ADR-0003 invariant 4) —
/// `TerminatedPayload.TotalIterations`.
 final  int totalIterations;
/// The value for the final `last_processed_wisp` write; null skips it.
 final  String? lastProcessedWisp;
/// The gate outcome (pass) on the wisp-closed path; null on operator
/// approve.
 final  GateOutcome? gateOutcome;
/// Speculative wisp to burn first, when its id is known at reduce time
/// (snapshot-validated `pending_next_wisp`, or phase 2's
/// `GateEvaluatedEvent.pouredSpeculativeWispId`).
/// [TerminalPath.handlerWispClosed] only.
 final  String? burnWispId;
/// Burn the wisp produced by the [ReconcilerAction.pourSpeculative]
/// earlier in the SAME action list (the replay path pours at 3b even
/// when the persisted outcome is terminal, then burns —
/// handler.go:384-387). Covers the in-list pour whose id no reduce
/// input carries; no-op when that pour produced nothing.
/// [TerminalPath.handlerWispClosed] only — and after termination there
/// is no next handler entry to self-heal a leak, so skipping this burn
/// hides the wisp forever (ADR-0003 invariant 5).
@JsonKey() final  bool burnPriorPour;
/// True on the operator path, which clears `waiting_reason`
/// (manual.go:71-73); the handler path does not.
@JsonKey() final  bool clearWaitingReason;
/// The canonical close reason ([CloseReasons.handlerRoot] or
/// [CloseReasons.manualApprove]).
 final  String closeReason;
/// Step-8 event data. [TerminalPath.handlerWispClosed]: iteration +
/// terminated, BOTH emitted before any terminal write (protocol step
/// 2; handler.go:662-685). [TerminalPath.operatorApprove]: terminated
/// between the writes and the close, manual_approve after the close.
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApprovedActionCopyWith<ApprovedAction> get copyWith => _$ApprovedActionCopyWithImpl<ApprovedAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovedAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.path, path) || other.path == path)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.totalIterations, totalIterations) || other.totalIterations == totalIterations)&&(identical(other.lastProcessedWisp, lastProcessedWisp) || other.lastProcessedWisp == lastProcessedWisp)&&(identical(other.gateOutcome, gateOutcome) || other.gateOutcome == gateOutcome)&&(identical(other.burnWispId, burnWispId) || other.burnWispId == burnWispId)&&(identical(other.burnPriorPour, burnPriorPour) || other.burnPriorPour == burnPriorPour)&&(identical(other.clearWaitingReason, clearWaitingReason) || other.clearWaitingReason == clearWaitingReason)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,path,actor,iteration,totalIterations,lastProcessedWisp,gateOutcome,burnWispId,burnPriorPour,clearWaitingReason,closeReason,events);

@override
String toString() {
  return 'ReconcilerAction.approved(convergenceBeadId: $convergenceBeadId, path: $path, actor: $actor, iteration: $iteration, totalIterations: $totalIterations, lastProcessedWisp: $lastProcessedWisp, gateOutcome: $gateOutcome, burnWispId: $burnWispId, burnPriorPour: $burnPriorPour, clearWaitingReason: $clearWaitingReason, closeReason: $closeReason, events: $events)';
}


}

/// @nodoc
abstract mixin class $ApprovedActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $ApprovedActionCopyWith(ApprovedAction value, $Res Function(ApprovedAction) _then) = _$ApprovedActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, TerminalPath path, String actor, int iteration, int totalIterations, String? lastProcessedWisp, GateOutcome? gateOutcome, String? burnWispId, bool burnPriorPour, bool clearWaitingReason, String closeReason, EventEmission? events
});


$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$ApprovedActionCopyWithImpl<$Res>
    implements $ApprovedActionCopyWith<$Res> {
  _$ApprovedActionCopyWithImpl(this._self, this._then);

  final ApprovedAction _self;
  final $Res Function(ApprovedAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? path = null,Object? actor = null,Object? iteration = null,Object? totalIterations = null,Object? lastProcessedWisp = freezed,Object? gateOutcome = freezed,Object? burnWispId = freezed,Object? burnPriorPour = null,Object? clearWaitingReason = null,Object? closeReason = null,Object? events = freezed,}) {
  return _then(ApprovedAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as TerminalPath,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,totalIterations: null == totalIterations ? _self.totalIterations : totalIterations // ignore: cast_nullable_to_non_nullable
as int,lastProcessedWisp: freezed == lastProcessedWisp ? _self.lastProcessedWisp : lastProcessedWisp // ignore: cast_nullable_to_non_nullable
as String?,gateOutcome: freezed == gateOutcome ? _self.gateOutcome : gateOutcome // ignore: cast_nullable_to_non_nullable
as GateOutcome?,burnWispId: freezed == burnWispId ? _self.burnWispId : burnWispId // ignore: cast_nullable_to_non_nullable
as String?,burnPriorPour: null == burnPriorPour ? _self.burnPriorPour : burnPriorPour // ignore: cast_nullable_to_non_nullable
as bool,clearWaitingReason: null == clearWaitingReason ? _self.clearWaitingReason : clearWaitingReason // ignore: cast_nullable_to_non_nullable
as bool,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class NoConvergenceAction extends ReconcilerAction {
  const NoConvergenceAction({required this.convergenceBeadId, required this.actor, required this.iteration, required this.totalIterations, this.lastProcessedWisp, this.gateOutcome, this.burnWispId, this.burnPriorPour = false, required this.closeReason, this.events}): super._();
  

 final  String convergenceBeadId;
 final  String actor;
/// The closed wisp's iteration (handler.go:708) — see
/// [ApprovedAction.iteration].
 final  int iteration;
 final  int totalIterations;
 final  String? lastProcessedWisp;
 final  GateOutcome? gateOutcome;
/// Reduce-time-known speculative wisp to burn first — see
/// [ApprovedAction.burnWispId].
 final  String? burnWispId;
/// Burn the in-list prior pour's wisp — see
/// [ApprovedAction.burnPriorPour]. Reachable on a timeout-terminate
/// replay below max iterations: 3b still pours (handler.go:254), the
/// persisted outcome terminates, the pour burns (handler.go:384-387).
/// The at-max case never poured (`wispIteration < maxIterations` gates
/// 3b), so it carries neither burn field.
@JsonKey() final  bool burnPriorPour;
 final  String closeReason;
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoConvergenceActionCopyWith<NoConvergenceAction> get copyWith => _$NoConvergenceActionCopyWithImpl<NoConvergenceAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoConvergenceAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.totalIterations, totalIterations) || other.totalIterations == totalIterations)&&(identical(other.lastProcessedWisp, lastProcessedWisp) || other.lastProcessedWisp == lastProcessedWisp)&&(identical(other.gateOutcome, gateOutcome) || other.gateOutcome == gateOutcome)&&(identical(other.burnWispId, burnWispId) || other.burnWispId == burnWispId)&&(identical(other.burnPriorPour, burnPriorPour) || other.burnPriorPour == burnPriorPour)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,actor,iteration,totalIterations,lastProcessedWisp,gateOutcome,burnWispId,burnPriorPour,closeReason,events);

@override
String toString() {
  return 'ReconcilerAction.noConvergence(convergenceBeadId: $convergenceBeadId, actor: $actor, iteration: $iteration, totalIterations: $totalIterations, lastProcessedWisp: $lastProcessedWisp, gateOutcome: $gateOutcome, burnWispId: $burnWispId, burnPriorPour: $burnPriorPour, closeReason: $closeReason, events: $events)';
}


}

/// @nodoc
abstract mixin class $NoConvergenceActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $NoConvergenceActionCopyWith(NoConvergenceAction value, $Res Function(NoConvergenceAction) _then) = _$NoConvergenceActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String actor, int iteration, int totalIterations, String? lastProcessedWisp, GateOutcome? gateOutcome, String? burnWispId, bool burnPriorPour, String closeReason, EventEmission? events
});


$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$NoConvergenceActionCopyWithImpl<$Res>
    implements $NoConvergenceActionCopyWith<$Res> {
  _$NoConvergenceActionCopyWithImpl(this._self, this._then);

  final NoConvergenceAction _self;
  final $Res Function(NoConvergenceAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? actor = null,Object? iteration = null,Object? totalIterations = null,Object? lastProcessedWisp = freezed,Object? gateOutcome = freezed,Object? burnWispId = freezed,Object? burnPriorPour = null,Object? closeReason = null,Object? events = freezed,}) {
  return _then(NoConvergenceAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,totalIterations: null == totalIterations ? _self.totalIterations : totalIterations // ignore: cast_nullable_to_non_nullable
as int,lastProcessedWisp: freezed == lastProcessedWisp ? _self.lastProcessedWisp : lastProcessedWisp // ignore: cast_nullable_to_non_nullable
as String?,gateOutcome: freezed == gateOutcome ? _self.gateOutcome : gateOutcome // ignore: cast_nullable_to_non_nullable
as GateOutcome?,burnWispId: freezed == burnWispId ? _self.burnWispId : burnWispId // ignore: cast_nullable_to_non_nullable
as String?,burnPriorPour: null == burnPriorPour ? _self.burnPriorPour : burnPriorPour // ignore: cast_nullable_to_non_nullable
as bool,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class WaitingManualAction extends ReconcilerAction {
  const WaitingManualAction({required this.convergenceBeadId, required this.closedWispId, required this.iteration, required this.reason, this.gateOutcome, this.burnWispId, this.burnPriorPour = false, this.clearStalePending = false, this.events}): super._();
  

 final  String convergenceBeadId;
/// Becomes the new `last_processed_wisp`.
 final  String closedWispId;
 final  int iteration;
 final  WaitingReason reason;
/// Null when no gate ran (pure manual mode passes `""` —
/// handler.go:305-306).
 final  GateOutcome? gateOutcome;
/// Reduce-time-known speculative wisp to burn first: the snapshot's
/// validated `pending_next_wisp` (manual / hybrid-no-condition holds
/// skip the 3b pour, so only an adopted pending can exist —
/// handler.go:300-316), or phase 2's
/// `GateEvaluatedEvent.pouredSpeculativeWispId` (the fresh
/// timeout-manual hold burns it, handler.go:344-352). The
/// sling-failure hold never burns — its defining condition is that no
/// wisp exists (handler.go:370-373).
 final  String? burnWispId;
/// Burn the in-list prior pour's wisp — see
/// [ApprovedAction.burnPriorPour]. Reachable on a
/// timeout-with-manual-action replay: 3b pours, the persisted timeout
/// outcome holds, the pour burns (handler.go:344-352).
@JsonKey() final  bool burnPriorPour;
/// Best-effort `pending_next_wisp` ← `''` BEFORE everything else: the
/// snapshot's pointer failed validation. gc's `validPendingNextWisp`
/// clears a stale pointer as a side effect of validating it
/// (handler.go:935-945) and runs on EVERY wisp-closed entry —
/// including the hold paths that pour nothing (manual /
/// hybrid-no-condition, handler.go:300-316, where step 3b is skipped
/// so no [ReconcilerAction.pourSpeculative] exists to carry the
/// clear). Without this carrier a stale pointer would survive into
/// waiting_manual, where only operator paths — which never validate
/// it — run next.
@JsonKey() final  bool clearStalePending;
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingManualActionCopyWith<WaitingManualAction> get copyWith => _$WaitingManualActionCopyWithImpl<WaitingManualAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingManualAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.closedWispId, closedWispId) || other.closedWispId == closedWispId)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.gateOutcome, gateOutcome) || other.gateOutcome == gateOutcome)&&(identical(other.burnWispId, burnWispId) || other.burnWispId == burnWispId)&&(identical(other.burnPriorPour, burnPriorPour) || other.burnPriorPour == burnPriorPour)&&(identical(other.clearStalePending, clearStalePending) || other.clearStalePending == clearStalePending)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,closedWispId,iteration,reason,gateOutcome,burnWispId,burnPriorPour,clearStalePending,events);

@override
String toString() {
  return 'ReconcilerAction.waitingManual(convergenceBeadId: $convergenceBeadId, closedWispId: $closedWispId, iteration: $iteration, reason: $reason, gateOutcome: $gateOutcome, burnWispId: $burnWispId, burnPriorPour: $burnPriorPour, clearStalePending: $clearStalePending, events: $events)';
}


}

/// @nodoc
abstract mixin class $WaitingManualActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $WaitingManualActionCopyWith(WaitingManualAction value, $Res Function(WaitingManualAction) _then) = _$WaitingManualActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String closedWispId, int iteration, WaitingReason reason, GateOutcome? gateOutcome, String? burnWispId, bool burnPriorPour, bool clearStalePending, EventEmission? events
});


$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$WaitingManualActionCopyWithImpl<$Res>
    implements $WaitingManualActionCopyWith<$Res> {
  _$WaitingManualActionCopyWithImpl(this._self, this._then);

  final WaitingManualAction _self;
  final $Res Function(WaitingManualAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? closedWispId = null,Object? iteration = null,Object? reason = null,Object? gateOutcome = freezed,Object? burnWispId = freezed,Object? burnPriorPour = null,Object? clearStalePending = null,Object? events = freezed,}) {
  return _then(WaitingManualAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,closedWispId: null == closedWispId ? _self.closedWispId : closedWispId // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as WaitingReason,gateOutcome: freezed == gateOutcome ? _self.gateOutcome : gateOutcome // ignore: cast_nullable_to_non_nullable
as GateOutcome?,burnWispId: freezed == burnWispId ? _self.burnWispId : burnWispId // ignore: cast_nullable_to_non_nullable
as String?,burnPriorPour: null == burnPriorPour ? _self.burnPriorPour : burnPriorPour // ignore: cast_nullable_to_non_nullable
as bool,clearStalePending: null == clearStalePending ? _self.clearStalePending : clearStalePending // ignore: cast_nullable_to_non_nullable
as bool,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class WaitingTriggerAction extends ReconcilerAction {
  const WaitingTriggerAction({required this.convergenceBeadId, required this.closedWispId, required this.iteration, this.gateOutcome, this.clearVerdict = false, this.events}): super._();
  

 final  String convergenceBeadId;
 final  String closedWispId;
 final  int iteration;
 final  GateOutcome? gateOutcome;
/// True when the verdict was scoped to the closed wisp
/// (handler.go:589-596).
@JsonKey() final  bool clearVerdict;
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitingTriggerActionCopyWith<WaitingTriggerAction> get copyWith => _$WaitingTriggerActionCopyWithImpl<WaitingTriggerAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitingTriggerAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.closedWispId, closedWispId) || other.closedWispId == closedWispId)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.gateOutcome, gateOutcome) || other.gateOutcome == gateOutcome)&&(identical(other.clearVerdict, clearVerdict) || other.clearVerdict == clearVerdict)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,closedWispId,iteration,gateOutcome,clearVerdict,events);

@override
String toString() {
  return 'ReconcilerAction.waitingTrigger(convergenceBeadId: $convergenceBeadId, closedWispId: $closedWispId, iteration: $iteration, gateOutcome: $gateOutcome, clearVerdict: $clearVerdict, events: $events)';
}


}

/// @nodoc
abstract mixin class $WaitingTriggerActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $WaitingTriggerActionCopyWith(WaitingTriggerAction value, $Res Function(WaitingTriggerAction) _then) = _$WaitingTriggerActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String closedWispId, int iteration, GateOutcome? gateOutcome, bool clearVerdict, EventEmission? events
});


$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$WaitingTriggerActionCopyWithImpl<$Res>
    implements $WaitingTriggerActionCopyWith<$Res> {
  _$WaitingTriggerActionCopyWithImpl(this._self, this._then);

  final WaitingTriggerAction _self;
  final $Res Function(WaitingTriggerAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? closedWispId = null,Object? iteration = null,Object? gateOutcome = freezed,Object? clearVerdict = null,Object? events = freezed,}) {
  return _then(WaitingTriggerAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,closedWispId: null == closedWispId ? _self.closedWispId : closedWispId // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,gateOutcome: freezed == gateOutcome ? _self.gateOutcome : gateOutcome // ignore: cast_nullable_to_non_nullable
as GateOutcome?,clearVerdict: null == clearVerdict ? _self.clearVerdict : clearVerdict // ignore: cast_nullable_to_non_nullable
as bool,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class StoppedAction extends ReconcilerAction {
  const StoppedAction({required this.convergenceBeadId, required this.actor, required this.totalIterations, this.lastProcessedWisp, this.forceCloseWispId, required this.closeReason, this.events}): super._();
  

 final  String convergenceBeadId;
/// `operator:<user>` (manual.go:248).
 final  String actor;
/// Derived closed-wisp count after any force-close (manual.go:342-347).
 final  int totalIterations;
/// The value for the final `last_processed_wisp` write (the force-closed
/// wisp when one exists — manual.go:430-434); null skips it.
 final  String? lastProcessedWisp;
/// Still-open active wisp to force-close first; null when none.
 final  String? forceCloseWispId;
 final  String closeReason;
/// Carries `gateMode` for the synthetic iteration event (defaulted to
/// manual when the stored mode is empty, manual.go:387-389) and
/// `priorState` for `ManualActionPayload` (manual.go:422).
 final  EventEmission? events;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedActionCopyWith<StoppedAction> get copyWith => _$StoppedActionCopyWithImpl<StoppedAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.actor, actor) || other.actor == actor)&&(identical(other.totalIterations, totalIterations) || other.totalIterations == totalIterations)&&(identical(other.lastProcessedWisp, lastProcessedWisp) || other.lastProcessedWisp == lastProcessedWisp)&&(identical(other.forceCloseWispId, forceCloseWispId) || other.forceCloseWispId == forceCloseWispId)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason)&&(identical(other.events, events) || other.events == events));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,actor,totalIterations,lastProcessedWisp,forceCloseWispId,closeReason,events);

@override
String toString() {
  return 'ReconcilerAction.stopped(convergenceBeadId: $convergenceBeadId, actor: $actor, totalIterations: $totalIterations, lastProcessedWisp: $lastProcessedWisp, forceCloseWispId: $forceCloseWispId, closeReason: $closeReason, events: $events)';
}


}

/// @nodoc
abstract mixin class $StoppedActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $StoppedActionCopyWith(StoppedAction value, $Res Function(StoppedAction) _then) = _$StoppedActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String actor, int totalIterations, String? lastProcessedWisp, String? forceCloseWispId, String closeReason, EventEmission? events
});


$EventEmissionCopyWith<$Res>? get events;

}
/// @nodoc
class _$StoppedActionCopyWithImpl<$Res>
    implements $StoppedActionCopyWith<$Res> {
  _$StoppedActionCopyWithImpl(this._self, this._then);

  final StoppedAction _self;
  final $Res Function(StoppedAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? actor = null,Object? totalIterations = null,Object? lastProcessedWisp = freezed,Object? forceCloseWispId = freezed,Object? closeReason = null,Object? events = freezed,}) {
  return _then(StoppedAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,actor: null == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String,totalIterations: null == totalIterations ? _self.totalIterations : totalIterations // ignore: cast_nullable_to_non_nullable
as int,lastProcessedWisp: freezed == lastProcessedWisp ? _self.lastProcessedWisp : lastProcessedWisp // ignore: cast_nullable_to_non_nullable
as String?,forceCloseWispId: freezed == forceCloseWispId ? _self.forceCloseWispId : forceCloseWispId // ignore: cast_nullable_to_non_nullable
as String?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,events: freezed == events ? _self.events : events // ignore: cast_nullable_to_non_nullable
as EventEmission?,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$EventEmissionCopyWith<$Res>? get events {
    if (_self.events == null) {
    return null;
  }

  return $EventEmissionCopyWith<$Res>(_self.events!, (value) {
    return _then(_self.copyWith(events: value));
  });
}
}

/// @nodoc


class SkippedAction extends ReconcilerAction {
  const SkippedAction({required this.convergenceBeadId, this.wispId, required this.reason, this.detail, this.closeRootBestEffort = false}): super._();
  

 final  String convergenceBeadId;
/// The wisp the skipped event concerned, when one applies.
 final  String? wispId;
 final  SkipReason reason;
/// Free-text diagnostics (e.g. the compared iterations on dedup).
 final  String? detail;
/// True for the already-terminated guard, where gc best-effort closes
/// the root with [CloseReasons.handlerCleanup] (handler.go:172-173).
@JsonKey() final  bool closeRootBestEffort;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkippedActionCopyWith<SkippedAction> get copyWith => _$SkippedActionCopyWithImpl<SkippedAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkippedAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.wispId, wispId) || other.wispId == wispId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.closeRootBestEffort, closeRootBestEffort) || other.closeRootBestEffort == closeRootBestEffort));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,wispId,reason,detail,closeRootBestEffort);

@override
String toString() {
  return 'ReconcilerAction.skipped(convergenceBeadId: $convergenceBeadId, wispId: $wispId, reason: $reason, detail: $detail, closeRootBestEffort: $closeRootBestEffort)';
}


}

/// @nodoc
abstract mixin class $SkippedActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $SkippedActionCopyWith(SkippedAction value, $Res Function(SkippedAction) _then) = _$SkippedActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String? wispId, SkipReason reason, String? detail, bool closeRootBestEffort
});




}
/// @nodoc
class _$SkippedActionCopyWithImpl<$Res>
    implements $SkippedActionCopyWith<$Res> {
  _$SkippedActionCopyWithImpl(this._self, this._then);

  final SkippedAction _self;
  final $Res Function(SkippedAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? wispId = freezed,Object? reason = null,Object? detail = freezed,Object? closeRootBestEffort = null,}) {
  return _then(SkippedAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,wispId: freezed == wispId ? _self.wispId : wispId // ignore: cast_nullable_to_non_nullable
as String?,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as SkipReason,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,closeRootBestEffort: null == closeRootBestEffort ? _self.closeRootBestEffort : closeRootBestEffort // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class PourSpeculativeAction extends ReconcilerAction {
  const PourSpeculativeAction({required this.convergenceBeadId, required this.pour, this.adoptPendingWispId, this.clearStalePending = false}): super._();
  

 final  String convergenceBeadId;
 final  WispPour pour;
/// A validated `pending_next_wisp` from a previous attempt to adopt
/// instead of pouring (handler.go:247).
 final  String? adoptPendingWispId;
/// True when the snapshot's `pending_next_wisp` pointed at a
/// missing/mismatched/closed bead and must be cleared (self-heal).
@JsonKey() final  bool clearStalePending;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PourSpeculativeActionCopyWith<PourSpeculativeAction> get copyWith => _$PourSpeculativeActionCopyWithImpl<PourSpeculativeAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PourSpeculativeAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.pour, pour) || other.pour == pour)&&(identical(other.adoptPendingWispId, adoptPendingWispId) || other.adoptPendingWispId == adoptPendingWispId)&&(identical(other.clearStalePending, clearStalePending) || other.clearStalePending == clearStalePending));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,pour,adoptPendingWispId,clearStalePending);

@override
String toString() {
  return 'ReconcilerAction.pourSpeculative(convergenceBeadId: $convergenceBeadId, pour: $pour, adoptPendingWispId: $adoptPendingWispId, clearStalePending: $clearStalePending)';
}


}

/// @nodoc
abstract mixin class $PourSpeculativeActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $PourSpeculativeActionCopyWith(PourSpeculativeAction value, $Res Function(PourSpeculativeAction) _then) = _$PourSpeculativeActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, WispPour pour, String? adoptPendingWispId, bool clearStalePending
});


$WispPourCopyWith<$Res> get pour;

}
/// @nodoc
class _$PourSpeculativeActionCopyWithImpl<$Res>
    implements $PourSpeculativeActionCopyWith<$Res> {
  _$PourSpeculativeActionCopyWithImpl(this._self, this._then);

  final PourSpeculativeAction _self;
  final $Res Function(PourSpeculativeAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? pour = null,Object? adoptPendingWispId = freezed,Object? clearStalePending = null,}) {
  return _then(PourSpeculativeAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,pour: null == pour ? _self.pour : pour // ignore: cast_nullable_to_non_nullable
as WispPour,adoptPendingWispId: freezed == adoptPendingWispId ? _self.adoptPendingWispId : adoptPendingWispId // ignore: cast_nullable_to_non_nullable
as String?,clearStalePending: null == clearStalePending ? _self.clearStalePending : clearStalePending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WispPourCopyWith<$Res> get pour {
  
  return $WispPourCopyWith<$Res>(_self.pour, (value) {
    return _then(_self.copyWith(pour: value));
  });
}
}

/// @nodoc


class EvaluateGateAction extends ReconcilerAction {
  const EvaluateGateAction({required this.convergenceBeadId, required this.wispId, required this.iteration, required this.config, required this.env}): super._();
  

 final  String convergenceBeadId;
/// The just-closed wisp — `GC_WISP_ID`, and the scope marker the
/// outcome will be persisted under (handler.go:749, 806-807).
 final  String wispId;
/// The closed wisp's iteration — `GC_ITERATION` (handler.go:746).
 final  int iteration;
/// The step-3a `ParseGateConfig` product, defaults applied
/// (handler.go:218-223). Mode here is condition or hybrid-with-
/// condition only — manual and hybrid-no-condition short-circuit to
/// waiting_manual before any gate runs (handler.go:300-316).
 final  GateConfig config;
/// Snapshot-derived `ConditionEnv` inputs (handler.go:743-760) — see
/// [GateEnvInputs] for what Track D derives itself.
 final  GateEnvInputs env;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EvaluateGateActionCopyWith<EvaluateGateAction> get copyWith => _$EvaluateGateActionCopyWithImpl<EvaluateGateAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is EvaluateGateAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.wispId, wispId) || other.wispId == wispId)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&(identical(other.config, config) || other.config == config)&&(identical(other.env, env) || other.env == env));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,wispId,iteration,config,env);

@override
String toString() {
  return 'ReconcilerAction.evaluateGate(convergenceBeadId: $convergenceBeadId, wispId: $wispId, iteration: $iteration, config: $config, env: $env)';
}


}

/// @nodoc
abstract mixin class $EvaluateGateActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $EvaluateGateActionCopyWith(EvaluateGateAction value, $Res Function(EvaluateGateAction) _then) = _$EvaluateGateActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String wispId, int iteration, GateConfig config, GateEnvInputs env
});


$GateConfigCopyWith<$Res> get config;$GateEnvInputsCopyWith<$Res> get env;

}
/// @nodoc
class _$EvaluateGateActionCopyWithImpl<$Res>
    implements $EvaluateGateActionCopyWith<$Res> {
  _$EvaluateGateActionCopyWithImpl(this._self, this._then);

  final EvaluateGateAction _self;
  final $Res Function(EvaluateGateAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? wispId = null,Object? iteration = null,Object? config = null,Object? env = null,}) {
  return _then(EvaluateGateAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,wispId: null == wispId ? _self.wispId : wispId // ignore: cast_nullable_to_non_nullable
as String,iteration: null == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int,config: null == config ? _self.config : config // ignore: cast_nullable_to_non_nullable
as GateConfig,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as GateEnvInputs,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GateConfigCopyWith<$Res> get config {
  
  return $GateConfigCopyWith<$Res>(_self.config, (value) {
    return _then(_self.copyWith(config: value));
  });
}/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GateEnvInputsCopyWith<$Res> get env {
  
  return $GateEnvInputsCopyWith<$Res>(_self.env, (value) {
    return _then(_self.copyWith(env: value));
  });
}
}

/// @nodoc


class PersistGateOutcomeAction extends ReconcilerAction {
  const PersistGateOutcomeAction({required this.convergenceBeadId, required this.wispId, required this.result, this.burnWispId}): super._();
  

 final  String convergenceBeadId;
/// The closed wisp the outcome is scoped to — the idempotency marker
/// value (handler.go:806-807).
 final  String wispId;
 final  GateResult result;
/// The phase-1 speculative wisp (threaded back through
/// `GateEvaluatedEvent.pouredSpeculativeWispId`) to burn when the
/// write sequence fails (handler.go:331-338; class-doc burn protocol).
/// Null when phase 1 produced no wisp. Always concrete — this action
/// only ever appears in the phase-2 reduce, where the id is event
/// data, never an unresolved in-list pour.
 final  String? burnWispId;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistGateOutcomeActionCopyWith<PersistGateOutcomeAction> get copyWith => _$PersistGateOutcomeActionCopyWithImpl<PersistGateOutcomeAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistGateOutcomeAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.wispId, wispId) || other.wispId == wispId)&&(identical(other.result, result) || other.result == result)&&(identical(other.burnWispId, burnWispId) || other.burnWispId == burnWispId));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,wispId,result,burnWispId);

@override
String toString() {
  return 'ReconcilerAction.persistGateOutcome(convergenceBeadId: $convergenceBeadId, wispId: $wispId, result: $result, burnWispId: $burnWispId)';
}


}

/// @nodoc
abstract mixin class $PersistGateOutcomeActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $PersistGateOutcomeActionCopyWith(PersistGateOutcomeAction value, $Res Function(PersistGateOutcomeAction) _then) = _$PersistGateOutcomeActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String wispId, GateResult result, String? burnWispId
});


$GateResultCopyWith<$Res> get result;

}
/// @nodoc
class _$PersistGateOutcomeActionCopyWithImpl<$Res>
    implements $PersistGateOutcomeActionCopyWith<$Res> {
  _$PersistGateOutcomeActionCopyWithImpl(this._self, this._then);

  final PersistGateOutcomeAction _self;
  final $Res Function(PersistGateOutcomeAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? wispId = null,Object? result = null,Object? burnWispId = freezed,}) {
  return _then(PersistGateOutcomeAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,wispId: null == wispId ? _self.wispId : wispId // ignore: cast_nullable_to_non_nullable
as String,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as GateResult,burnWispId: freezed == burnWispId ? _self.burnWispId : burnWispId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ReconcilerAction
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


class RepairIterationAction extends ReconcilerAction {
  const RepairIterationAction({required this.convergenceBeadId, required this.derivedIteration, this.storedIteration = 0}): super._();
  

 final  String convergenceBeadId;
/// `deriveIterationCount` — the closed convergence-keyed child count.
 final  int derivedIteration;
/// The (collapsed) stored value, for diagnostics (handler.go:208).
@JsonKey() final  int storedIteration;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RepairIterationActionCopyWith<RepairIterationAction> get copyWith => _$RepairIterationActionCopyWithImpl<RepairIterationAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RepairIterationAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.derivedIteration, derivedIteration) || other.derivedIteration == derivedIteration)&&(identical(other.storedIteration, storedIteration) || other.storedIteration == storedIteration));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,derivedIteration,storedIteration);

@override
String toString() {
  return 'ReconcilerAction.repairIteration(convergenceBeadId: $convergenceBeadId, derivedIteration: $derivedIteration, storedIteration: $storedIteration)';
}


}

/// @nodoc
abstract mixin class $RepairIterationActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $RepairIterationActionCopyWith(RepairIterationAction value, $Res Function(RepairIterationAction) _then) = _$RepairIterationActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, int derivedIteration, int storedIteration
});




}
/// @nodoc
class _$RepairIterationActionCopyWithImpl<$Res>
    implements $RepairIterationActionCopyWith<$Res> {
  _$RepairIterationActionCopyWithImpl(this._self, this._then);

  final RepairIterationAction _self;
  final $Res Function(RepairIterationAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? derivedIteration = null,Object? storedIteration = null,}) {
  return _then(RepairIterationAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,derivedIteration: null == derivedIteration ? _self.derivedIteration : derivedIteration // ignore: cast_nullable_to_non_nullable
as int,storedIteration: null == storedIteration ? _self.storedIteration : storedIteration // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FailedAction extends ReconcilerAction {
  const FailedAction({required this.convergenceBeadId, required this.message, this.burnWispId, this.clearStalePending = false}): super._();
  

 final  String convergenceBeadId;
/// gc's error message shape, for conformance binding (Track H) — e.g.
/// `parsing iteration from wisp key "<key>"` or
/// `cannot approve bead "<id>": state is "<s>", expected "waiting_manual"`.
 final  String message;
/// Misconfig path only: burn this valid pending speculative wisp
/// BEFORE surfacing the error (handler.go:235-242; trap 9 — skipping
/// the burn leaks a hidden wisp a later recovery pass adopts). Burn =
/// post-order subtree DELETE, see the class-doc burn protocol.
 final  String? burnWispId;
/// Misconfig path only: best-effort `pending_next_wisp` ← `''` BEFORE
/// surfacing the error — the misconfig check validates the pointer
/// (handler.go:236) and gc's `validPendingNextWisp` clears a STALE one
/// as a side effect (handler.go:935-945) even though this path pours
/// nothing. Mutually exclusive with [burnWispId] (a pointer is either
/// valid → burn, or stale → clear). See
/// [FailedActionWrites.stalePendingClear].
@JsonKey() final  bool clearStalePending;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedActionCopyWith<FailedAction> get copyWith => _$FailedActionCopyWithImpl<FailedAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedAction&&(identical(other.convergenceBeadId, convergenceBeadId) || other.convergenceBeadId == convergenceBeadId)&&(identical(other.message, message) || other.message == message)&&(identical(other.burnWispId, burnWispId) || other.burnWispId == burnWispId)&&(identical(other.clearStalePending, clearStalePending) || other.clearStalePending == clearStalePending));
}


@override
int get hashCode => Object.hash(runtimeType,convergenceBeadId,message,burnWispId,clearStalePending);

@override
String toString() {
  return 'ReconcilerAction.failed(convergenceBeadId: $convergenceBeadId, message: $message, burnWispId: $burnWispId, clearStalePending: $clearStalePending)';
}


}

/// @nodoc
abstract mixin class $FailedActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $FailedActionCopyWith(FailedAction value, $Res Function(FailedAction) _then) = _$FailedActionCopyWithImpl;
@useResult
$Res call({
 String convergenceBeadId, String message, String? burnWispId, bool clearStalePending
});




}
/// @nodoc
class _$FailedActionCopyWithImpl<$Res>
    implements $FailedActionCopyWith<$Res> {
  _$FailedActionCopyWithImpl(this._self, this._then);

  final FailedAction _self;
  final $Res Function(FailedAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? convergenceBeadId = null,Object? message = null,Object? burnWispId = freezed,Object? clearStalePending = null,}) {
  return _then(FailedAction(
convergenceBeadId: null == convergenceBeadId ? _self.convergenceBeadId : convergenceBeadId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,burnWispId: freezed == burnWispId ? _self.burnWispId : burnWispId // ignore: cast_nullable_to_non_nullable
as String?,clearStalePending: null == clearStalePending ? _self.clearStalePending : clearStalePending // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RequeueAction extends ReconcilerAction {
  const RequeueAction({required this.event, required this.reason}): super._();
  

/// The deferred reducer input, re-enqueued as-is. For the operator-stop
/// drain this is `OperatorStopEvent(postDrain: true)` — the re-entry
/// marker travels inside [event]; Track G preserves it verbatim.
 final  ReducerEvent event;
/// Diagnostic — why the event was deferred (e.g. "operator stop
/// deferred behind drain of closed active wisp gt-w2").
 final  String reason;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RequeueActionCopyWith<RequeueAction> get copyWith => _$RequeueActionCopyWithImpl<RequeueAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RequeueAction&&(identical(other.event, event) || other.event == event)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,event,reason);

@override
String toString() {
  return 'ReconcilerAction.requeue(event: $event, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RequeueActionCopyWith<$Res> implements $ReconcilerActionCopyWith<$Res> {
  factory $RequeueActionCopyWith(RequeueAction value, $Res Function(RequeueAction) _then) = _$RequeueActionCopyWithImpl;
@useResult
$Res call({
 ReducerEvent event, String reason
});


$ReducerEventCopyWith<$Res> get event;

}
/// @nodoc
class _$RequeueActionCopyWithImpl<$Res>
    implements $RequeueActionCopyWith<$Res> {
  _$RequeueActionCopyWithImpl(this._self, this._then);

  final RequeueAction _self;
  final $Res Function(RequeueAction) _then;

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? event = null,Object? reason = null,}) {
  return _then(RequeueAction(
event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ReducerEvent,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of ReconcilerAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReducerEventCopyWith<$Res> get event {
  
  return $ReducerEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

// dart format on
