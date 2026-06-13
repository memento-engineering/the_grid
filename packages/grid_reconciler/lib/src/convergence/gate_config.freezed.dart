// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gate_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GateConfig {

/// `convergence.gate_mode`, defaulted to manual (gate.go:46-48).
 GateMode get mode;/// `convergence.gate_condition` — gate script path, taken verbatim;
/// empty for manual-only (gate.go:81).
 String get condition;/// `convergence.gate_timeout`, defaulted to 5m; parse errors and
/// non-positive values are step-3a failures, never carried here
/// (gate.go:57-67).
 GoDuration get timeout;/// `convergence.gate_timeout_action`, defaulted to iterate
/// (gate.go:69-77).
 GateTimeoutAction get timeoutAction;
/// Create a copy of GateConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GateConfigCopyWith<GateConfig> get copyWith => _$GateConfigCopyWithImpl<GateConfig>(this as GateConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GateConfig&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.condition, condition) || other.condition == condition)&&(identical(other.timeout, timeout) || other.timeout == timeout)&&(identical(other.timeoutAction, timeoutAction) || other.timeoutAction == timeoutAction));
}


@override
int get hashCode => Object.hash(runtimeType,mode,condition,timeout,timeoutAction);

@override
String toString() {
  return 'GateConfig(mode: $mode, condition: $condition, timeout: $timeout, timeoutAction: $timeoutAction)';
}


}

/// @nodoc
abstract mixin class $GateConfigCopyWith<$Res>  {
  factory $GateConfigCopyWith(GateConfig value, $Res Function(GateConfig) _then) = _$GateConfigCopyWithImpl;
@useResult
$Res call({
 GateMode mode, String condition, GoDuration timeout, GateTimeoutAction timeoutAction
});




}
/// @nodoc
class _$GateConfigCopyWithImpl<$Res>
    implements $GateConfigCopyWith<$Res> {
  _$GateConfigCopyWithImpl(this._self, this._then);

  final GateConfig _self;
  final $Res Function(GateConfig) _then;

/// Create a copy of GateConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? mode = null,Object? condition = null,Object? timeout = null,Object? timeoutAction = null,}) {
  return _then(_self.copyWith(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as GateMode,condition: null == condition ? _self.condition : condition // ignore: cast_nullable_to_non_nullable
as String,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as GoDuration,timeoutAction: null == timeoutAction ? _self.timeoutAction : timeoutAction // ignore: cast_nullable_to_non_nullable
as GateTimeoutAction,
  ));
}

}


/// Adds pattern-matching-related methods to [GateConfig].
extension GateConfigPatterns on GateConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GateConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GateConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GateConfig value)  $default,){
final _that = this;
switch (_that) {
case _GateConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GateConfig value)?  $default,){
final _that = this;
switch (_that) {
case _GateConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GateMode mode,  String condition,  GoDuration timeout,  GateTimeoutAction timeoutAction)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GateConfig() when $default != null:
return $default(_that.mode,_that.condition,_that.timeout,_that.timeoutAction);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GateMode mode,  String condition,  GoDuration timeout,  GateTimeoutAction timeoutAction)  $default,) {final _that = this;
switch (_that) {
case _GateConfig():
return $default(_that.mode,_that.condition,_that.timeout,_that.timeoutAction);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GateMode mode,  String condition,  GoDuration timeout,  GateTimeoutAction timeoutAction)?  $default,) {final _that = this;
switch (_that) {
case _GateConfig() when $default != null:
return $default(_that.mode,_that.condition,_that.timeout,_that.timeoutAction);case _:
  return null;

}
}

}

/// @nodoc


class _GateConfig extends GateConfig {
  const _GateConfig({required this.mode, required this.condition, required this.timeout, required this.timeoutAction}): super._();
  

/// `convergence.gate_mode`, defaulted to manual (gate.go:46-48).
@override final  GateMode mode;
/// `convergence.gate_condition` — gate script path, taken verbatim;
/// empty for manual-only (gate.go:81).
@override final  String condition;
/// `convergence.gate_timeout`, defaulted to 5m; parse errors and
/// non-positive values are step-3a failures, never carried here
/// (gate.go:57-67).
@override final  GoDuration timeout;
/// `convergence.gate_timeout_action`, defaulted to iterate
/// (gate.go:69-77).
@override final  GateTimeoutAction timeoutAction;

/// Create a copy of GateConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GateConfigCopyWith<_GateConfig> get copyWith => __$GateConfigCopyWithImpl<_GateConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GateConfig&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.condition, condition) || other.condition == condition)&&(identical(other.timeout, timeout) || other.timeout == timeout)&&(identical(other.timeoutAction, timeoutAction) || other.timeoutAction == timeoutAction));
}


@override
int get hashCode => Object.hash(runtimeType,mode,condition,timeout,timeoutAction);

@override
String toString() {
  return 'GateConfig(mode: $mode, condition: $condition, timeout: $timeout, timeoutAction: $timeoutAction)';
}


}

/// @nodoc
abstract mixin class _$GateConfigCopyWith<$Res> implements $GateConfigCopyWith<$Res> {
  factory _$GateConfigCopyWith(_GateConfig value, $Res Function(_GateConfig) _then) = __$GateConfigCopyWithImpl;
@override @useResult
$Res call({
 GateMode mode, String condition, GoDuration timeout, GateTimeoutAction timeoutAction
});




}
/// @nodoc
class __$GateConfigCopyWithImpl<$Res>
    implements _$GateConfigCopyWith<$Res> {
  __$GateConfigCopyWithImpl(this._self, this._then);

  final _GateConfig _self;
  final $Res Function(_GateConfig) _then;

/// Create a copy of GateConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? mode = null,Object? condition = null,Object? timeout = null,Object? timeoutAction = null,}) {
  return _then(_GateConfig(
mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as GateMode,condition: null == condition ? _self.condition : condition // ignore: cast_nullable_to_non_nullable
as String,timeout: null == timeout ? _self.timeout : timeout // ignore: cast_nullable_to_non_nullable
as GoDuration,timeoutAction: null == timeoutAction ? _self.timeoutAction : timeoutAction // ignore: cast_nullable_to_non_nullable
as GateTimeoutAction,
  ));
}


}

/// @nodoc
mixin _$GateEnvInputs {

/// `convergence.city_path` (set during create; handler.go:743) — feeds
/// `HOME`, `GC_CITY`/`GC_CITY_PATH`, and the artifact-dir base. Empty
/// sandboxes `HOME` to the temp dir (condition.go:80-86).
 String get cityPath;/// Root-bead metadata `var.doc_path` (handler.go:750) — `GC_DOC_PATH`
/// when non-empty.
 String get docPath;/// `convergence.max_iterations` via gc's collapsing read
/// (handler.go:759-760) — `GC_MAX_ITERATIONS`.
 int get maxIterations;/// `closedAt − createdAt` of the closed wisp (`computeDurations`,
/// handler.go:829-850) — `GC_ITERATION_DURATION_MS`.
 Duration get iterationDuration;/// Σ closed convergence-keyed children durations (handler.go:837-849) —
/// `GC_CUMULATIVE_DURATION_MS`.
 Duration get cumulativeDuration;/// The step-4 **gate-path** verdict (handler.go:317-324): normalized
/// when scoped to the closed wisp, else the `block` substitute — NOT
/// the event payload's `''` (`EventEmission.agentVerdict`). Hybrid mode
/// feeds it to `GC_AGENT_VERDICT` (hybrid.go:14); pure condition mode
/// receives but never exports it (gates-exec.md §1b #16).
 Verdict get agentVerdict;
/// Create a copy of GateEnvInputs
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GateEnvInputsCopyWith<GateEnvInputs> get copyWith => _$GateEnvInputsCopyWithImpl<GateEnvInputs>(this as GateEnvInputs, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GateEnvInputs&&(identical(other.cityPath, cityPath) || other.cityPath == cityPath)&&(identical(other.docPath, docPath) || other.docPath == docPath)&&(identical(other.maxIterations, maxIterations) || other.maxIterations == maxIterations)&&(identical(other.iterationDuration, iterationDuration) || other.iterationDuration == iterationDuration)&&(identical(other.cumulativeDuration, cumulativeDuration) || other.cumulativeDuration == cumulativeDuration)&&(identical(other.agentVerdict, agentVerdict) || other.agentVerdict == agentVerdict));
}


@override
int get hashCode => Object.hash(runtimeType,cityPath,docPath,maxIterations,iterationDuration,cumulativeDuration,agentVerdict);

@override
String toString() {
  return 'GateEnvInputs(cityPath: $cityPath, docPath: $docPath, maxIterations: $maxIterations, iterationDuration: $iterationDuration, cumulativeDuration: $cumulativeDuration, agentVerdict: $agentVerdict)';
}


}

/// @nodoc
abstract mixin class $GateEnvInputsCopyWith<$Res>  {
  factory $GateEnvInputsCopyWith(GateEnvInputs value, $Res Function(GateEnvInputs) _then) = _$GateEnvInputsCopyWithImpl;
@useResult
$Res call({
 String cityPath, String docPath, int maxIterations, Duration iterationDuration, Duration cumulativeDuration, Verdict agentVerdict
});




}
/// @nodoc
class _$GateEnvInputsCopyWithImpl<$Res>
    implements $GateEnvInputsCopyWith<$Res> {
  _$GateEnvInputsCopyWithImpl(this._self, this._then);

  final GateEnvInputs _self;
  final $Res Function(GateEnvInputs) _then;

/// Create a copy of GateEnvInputs
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cityPath = null,Object? docPath = null,Object? maxIterations = null,Object? iterationDuration = null,Object? cumulativeDuration = null,Object? agentVerdict = null,}) {
  return _then(_self.copyWith(
cityPath: null == cityPath ? _self.cityPath : cityPath // ignore: cast_nullable_to_non_nullable
as String,docPath: null == docPath ? _self.docPath : docPath // ignore: cast_nullable_to_non_nullable
as String,maxIterations: null == maxIterations ? _self.maxIterations : maxIterations // ignore: cast_nullable_to_non_nullable
as int,iterationDuration: null == iterationDuration ? _self.iterationDuration : iterationDuration // ignore: cast_nullable_to_non_nullable
as Duration,cumulativeDuration: null == cumulativeDuration ? _self.cumulativeDuration : cumulativeDuration // ignore: cast_nullable_to_non_nullable
as Duration,agentVerdict: null == agentVerdict ? _self.agentVerdict : agentVerdict // ignore: cast_nullable_to_non_nullable
as Verdict,
  ));
}

}


/// Adds pattern-matching-related methods to [GateEnvInputs].
extension GateEnvInputsPatterns on GateEnvInputs {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GateEnvInputs value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GateEnvInputs() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GateEnvInputs value)  $default,){
final _that = this;
switch (_that) {
case _GateEnvInputs():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GateEnvInputs value)?  $default,){
final _that = this;
switch (_that) {
case _GateEnvInputs() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String cityPath,  String docPath,  int maxIterations,  Duration iterationDuration,  Duration cumulativeDuration,  Verdict agentVerdict)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GateEnvInputs() when $default != null:
return $default(_that.cityPath,_that.docPath,_that.maxIterations,_that.iterationDuration,_that.cumulativeDuration,_that.agentVerdict);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String cityPath,  String docPath,  int maxIterations,  Duration iterationDuration,  Duration cumulativeDuration,  Verdict agentVerdict)  $default,) {final _that = this;
switch (_that) {
case _GateEnvInputs():
return $default(_that.cityPath,_that.docPath,_that.maxIterations,_that.iterationDuration,_that.cumulativeDuration,_that.agentVerdict);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String cityPath,  String docPath,  int maxIterations,  Duration iterationDuration,  Duration cumulativeDuration,  Verdict agentVerdict)?  $default,) {final _that = this;
switch (_that) {
case _GateEnvInputs() when $default != null:
return $default(_that.cityPath,_that.docPath,_that.maxIterations,_that.iterationDuration,_that.cumulativeDuration,_that.agentVerdict);case _:
  return null;

}
}

}

/// @nodoc


class _GateEnvInputs extends GateEnvInputs {
  const _GateEnvInputs({this.cityPath = '', this.docPath = '', this.maxIterations = 0, this.iterationDuration = Duration.zero, this.cumulativeDuration = Duration.zero, this.agentVerdict = Verdict.block}): super._();
  

/// `convergence.city_path` (set during create; handler.go:743) — feeds
/// `HOME`, `GC_CITY`/`GC_CITY_PATH`, and the artifact-dir base. Empty
/// sandboxes `HOME` to the temp dir (condition.go:80-86).
@override@JsonKey() final  String cityPath;
/// Root-bead metadata `var.doc_path` (handler.go:750) — `GC_DOC_PATH`
/// when non-empty.
@override@JsonKey() final  String docPath;
/// `convergence.max_iterations` via gc's collapsing read
/// (handler.go:759-760) — `GC_MAX_ITERATIONS`.
@override@JsonKey() final  int maxIterations;
/// `closedAt − createdAt` of the closed wisp (`computeDurations`,
/// handler.go:829-850) — `GC_ITERATION_DURATION_MS`.
@override@JsonKey() final  Duration iterationDuration;
/// Σ closed convergence-keyed children durations (handler.go:837-849) —
/// `GC_CUMULATIVE_DURATION_MS`.
@override@JsonKey() final  Duration cumulativeDuration;
/// The step-4 **gate-path** verdict (handler.go:317-324): normalized
/// when scoped to the closed wisp, else the `block` substitute — NOT
/// the event payload's `''` (`EventEmission.agentVerdict`). Hybrid mode
/// feeds it to `GC_AGENT_VERDICT` (hybrid.go:14); pure condition mode
/// receives but never exports it (gates-exec.md §1b #16).
@override@JsonKey() final  Verdict agentVerdict;

/// Create a copy of GateEnvInputs
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GateEnvInputsCopyWith<_GateEnvInputs> get copyWith => __$GateEnvInputsCopyWithImpl<_GateEnvInputs>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GateEnvInputs&&(identical(other.cityPath, cityPath) || other.cityPath == cityPath)&&(identical(other.docPath, docPath) || other.docPath == docPath)&&(identical(other.maxIterations, maxIterations) || other.maxIterations == maxIterations)&&(identical(other.iterationDuration, iterationDuration) || other.iterationDuration == iterationDuration)&&(identical(other.cumulativeDuration, cumulativeDuration) || other.cumulativeDuration == cumulativeDuration)&&(identical(other.agentVerdict, agentVerdict) || other.agentVerdict == agentVerdict));
}


@override
int get hashCode => Object.hash(runtimeType,cityPath,docPath,maxIterations,iterationDuration,cumulativeDuration,agentVerdict);

@override
String toString() {
  return 'GateEnvInputs(cityPath: $cityPath, docPath: $docPath, maxIterations: $maxIterations, iterationDuration: $iterationDuration, cumulativeDuration: $cumulativeDuration, agentVerdict: $agentVerdict)';
}


}

/// @nodoc
abstract mixin class _$GateEnvInputsCopyWith<$Res> implements $GateEnvInputsCopyWith<$Res> {
  factory _$GateEnvInputsCopyWith(_GateEnvInputs value, $Res Function(_GateEnvInputs) _then) = __$GateEnvInputsCopyWithImpl;
@override @useResult
$Res call({
 String cityPath, String docPath, int maxIterations, Duration iterationDuration, Duration cumulativeDuration, Verdict agentVerdict
});




}
/// @nodoc
class __$GateEnvInputsCopyWithImpl<$Res>
    implements _$GateEnvInputsCopyWith<$Res> {
  __$GateEnvInputsCopyWithImpl(this._self, this._then);

  final _GateEnvInputs _self;
  final $Res Function(_GateEnvInputs) _then;

/// Create a copy of GateEnvInputs
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cityPath = null,Object? docPath = null,Object? maxIterations = null,Object? iterationDuration = null,Object? cumulativeDuration = null,Object? agentVerdict = null,}) {
  return _then(_GateEnvInputs(
cityPath: null == cityPath ? _self.cityPath : cityPath // ignore: cast_nullable_to_non_nullable
as String,docPath: null == docPath ? _self.docPath : docPath // ignore: cast_nullable_to_non_nullable
as String,maxIterations: null == maxIterations ? _self.maxIterations : maxIterations // ignore: cast_nullable_to_non_nullable
as int,iterationDuration: null == iterationDuration ? _self.iterationDuration : iterationDuration // ignore: cast_nullable_to_non_nullable
as Duration,cumulativeDuration: null == cumulativeDuration ? _self.cumulativeDuration : cumulativeDuration // ignore: cast_nullable_to_non_nullable
as Duration,agentVerdict: null == agentVerdict ? _self.agentVerdict : agentVerdict // ignore: cast_nullable_to_non_nullable
as Verdict,
  ));
}


}

// dart format on
