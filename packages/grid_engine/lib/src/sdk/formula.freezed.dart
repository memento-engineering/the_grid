// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'formula.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Backoff {

/// The first cooldown (and the floor).
 Duration get min;/// The ceiling — the cooldown never exceeds this.
 Duration get max;/// The geometric growth factor between attempts (≥ 1).
 double get factor;
/// Create a copy of Backoff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackoffCopyWith<Backoff> get copyWith => _$BackoffCopyWithImpl<Backoff>(this as Backoff, _$identity);

  /// Serializes this Backoff to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Backoff&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&(identical(other.factor, factor) || other.factor == factor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,min,max,factor);

@override
String toString() {
  return 'Backoff(min: $min, max: $max, factor: $factor)';
}


}

/// @nodoc
abstract mixin class $BackoffCopyWith<$Res>  {
  factory $BackoffCopyWith(Backoff value, $Res Function(Backoff) _then) = _$BackoffCopyWithImpl;
@useResult
$Res call({
 Duration min, Duration max, double factor
});




}
/// @nodoc
class _$BackoffCopyWithImpl<$Res>
    implements $BackoffCopyWith<$Res> {
  _$BackoffCopyWithImpl(this._self, this._then);

  final Backoff _self;
  final $Res Function(Backoff) _then;

/// Create a copy of Backoff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? min = null,Object? max = null,Object? factor = null,}) {
  return _then(_self.copyWith(
min: null == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as Duration,max: null == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as Duration,factor: null == factor ? _self.factor : factor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [Backoff].
extension BackoffPatterns on Backoff {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Backoff value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Backoff() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Backoff value)  $default,){
final _that = this;
switch (_that) {
case _Backoff():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Backoff value)?  $default,){
final _that = this;
switch (_that) {
case _Backoff() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Duration min,  Duration max,  double factor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Backoff() when $default != null:
return $default(_that.min,_that.max,_that.factor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Duration min,  Duration max,  double factor)  $default,) {final _that = this;
switch (_that) {
case _Backoff():
return $default(_that.min,_that.max,_that.factor);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Duration min,  Duration max,  double factor)?  $default,) {final _that = this;
switch (_that) {
case _Backoff() when $default != null:
return $default(_that.min,_that.max,_that.factor);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Backoff extends Backoff {
  const _Backoff({required this.min, required this.max, this.factor = 2.0}): super._();
  factory _Backoff.fromJson(Map<String, dynamic> json) => _$BackoffFromJson(json);

/// The first cooldown (and the floor).
@override final  Duration min;
/// The ceiling — the cooldown never exceeds this.
@override final  Duration max;
/// The geometric growth factor between attempts (≥ 1).
@override@JsonKey() final  double factor;

/// Create a copy of Backoff
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackoffCopyWith<_Backoff> get copyWith => __$BackoffCopyWithImpl<_Backoff>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackoffToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Backoff&&(identical(other.min, min) || other.min == min)&&(identical(other.max, max) || other.max == max)&&(identical(other.factor, factor) || other.factor == factor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,min,max,factor);

@override
String toString() {
  return 'Backoff(min: $min, max: $max, factor: $factor)';
}


}

/// @nodoc
abstract mixin class _$BackoffCopyWith<$Res> implements $BackoffCopyWith<$Res> {
  factory _$BackoffCopyWith(_Backoff value, $Res Function(_Backoff) _then) = __$BackoffCopyWithImpl;
@override @useResult
$Res call({
 Duration min, Duration max, double factor
});




}
/// @nodoc
class __$BackoffCopyWithImpl<$Res>
    implements _$BackoffCopyWith<$Res> {
  __$BackoffCopyWithImpl(this._self, this._then);

  final _Backoff _self;
  final $Res Function(_Backoff) _then;

/// Create a copy of Backoff
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? min = null,Object? max = null,Object? factor = null,}) {
  return _then(_Backoff(
min: null == min ? _self.min : min // ignore: cast_nullable_to_non_nullable
as Duration,max: null == max ? _self.max : max // ignore: cast_nullable_to_non_nullable
as Duration,factor: null == factor ? _self.factor : factor // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}


/// @nodoc
mixin _$ResourceRequest {

 int get builds; int get processes;
/// Create a copy of ResourceRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceRequestCopyWith<ResourceRequest> get copyWith => _$ResourceRequestCopyWithImpl<ResourceRequest>(this as ResourceRequest, _$identity);

  /// Serializes this ResourceRequest to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceRequest&&(identical(other.builds, builds) || other.builds == builds)&&(identical(other.processes, processes) || other.processes == processes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,builds,processes);

@override
String toString() {
  return 'ResourceRequest(builds: $builds, processes: $processes)';
}


}

/// @nodoc
abstract mixin class $ResourceRequestCopyWith<$Res>  {
  factory $ResourceRequestCopyWith(ResourceRequest value, $Res Function(ResourceRequest) _then) = _$ResourceRequestCopyWithImpl;
@useResult
$Res call({
 int builds, int processes
});




}
/// @nodoc
class _$ResourceRequestCopyWithImpl<$Res>
    implements $ResourceRequestCopyWith<$Res> {
  _$ResourceRequestCopyWithImpl(this._self, this._then);

  final ResourceRequest _self;
  final $Res Function(ResourceRequest) _then;

/// Create a copy of ResourceRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? builds = null,Object? processes = null,}) {
  return _then(_self.copyWith(
builds: null == builds ? _self.builds : builds // ignore: cast_nullable_to_non_nullable
as int,processes: null == processes ? _self.processes : processes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ResourceRequest].
extension ResourceRequestPatterns on ResourceRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResourceRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResourceRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResourceRequest value)  $default,){
final _that = this;
switch (_that) {
case _ResourceRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResourceRequest value)?  $default,){
final _that = this;
switch (_that) {
case _ResourceRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int builds,  int processes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResourceRequest() when $default != null:
return $default(_that.builds,_that.processes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int builds,  int processes)  $default,) {final _that = this;
switch (_that) {
case _ResourceRequest():
return $default(_that.builds,_that.processes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int builds,  int processes)?  $default,) {final _that = this;
switch (_that) {
case _ResourceRequest() when $default != null:
return $default(_that.builds,_that.processes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ResourceRequest implements ResourceRequest {
  const _ResourceRequest({this.builds = 0, this.processes = 0});
  factory _ResourceRequest.fromJson(Map<String, dynamic> json) => _$ResourceRequestFromJson(json);

@override@JsonKey() final  int builds;
@override@JsonKey() final  int processes;

/// Create a copy of ResourceRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResourceRequestCopyWith<_ResourceRequest> get copyWith => __$ResourceRequestCopyWithImpl<_ResourceRequest>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ResourceRequestToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResourceRequest&&(identical(other.builds, builds) || other.builds == builds)&&(identical(other.processes, processes) || other.processes == processes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,builds,processes);

@override
String toString() {
  return 'ResourceRequest(builds: $builds, processes: $processes)';
}


}

/// @nodoc
abstract mixin class _$ResourceRequestCopyWith<$Res> implements $ResourceRequestCopyWith<$Res> {
  factory _$ResourceRequestCopyWith(_ResourceRequest value, $Res Function(_ResourceRequest) _then) = __$ResourceRequestCopyWithImpl;
@override @useResult
$Res call({
 int builds, int processes
});




}
/// @nodoc
class __$ResourceRequestCopyWithImpl<$Res>
    implements _$ResourceRequestCopyWith<$Res> {
  __$ResourceRequestCopyWithImpl(this._self, this._then);

  final _ResourceRequest _self;
  final $Res Function(_ResourceRequest) _then;

/// Create a copy of ResourceRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? builds = null,Object? processes = null,}) {
  return _then(_ResourceRequest(
builds: null == builds ? _self.builds : builds // ignore: cast_nullable_to_non_nullable
as int,processes: null == processes ? _self.processes : processes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

FormulaStep _$FormulaStepFromJson(
  Map<String, dynamic> json
) {
        switch (json['type']) {
                  case 'capability':
          return CapabilityStep.fromJson(
            json
          );
                case 'sub_formula':
          return SubFormulaStep.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'type',
  'FormulaStep',
  'Invalid union type "${json['type']}"!'
);
        }
      
}

/// @nodoc
mixin _$FormulaStep {

/// The step's id (unique within its formula).
 String get stepId;/// Opaque parameters threaded to the capability leaf.
 Map<String, String> get params;/// The sibling step ids whose positive terminals gate this step (the
/// barrier).
 Set<String> get dependsOn;
/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FormulaStepCopyWith<FormulaStep> get copyWith => _$FormulaStepCopyWithImpl<FormulaStep>(this as FormulaStep, _$identity);

  /// Serializes this FormulaStep to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FormulaStep&&(identical(other.stepId, stepId) || other.stepId == stepId)&&const DeepCollectionEquality().equals(other.params, params)&&const DeepCollectionEquality().equals(other.dependsOn, dependsOn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,stepId,const DeepCollectionEquality().hash(params),const DeepCollectionEquality().hash(dependsOn));

@override
String toString() {
  return 'FormulaStep(stepId: $stepId, params: $params, dependsOn: $dependsOn)';
}


}

/// @nodoc
abstract mixin class $FormulaStepCopyWith<$Res>  {
  factory $FormulaStepCopyWith(FormulaStep value, $Res Function(FormulaStep) _then) = _$FormulaStepCopyWithImpl;
@useResult
$Res call({
 String stepId, Map<String, String> params, Set<String> dependsOn
});




}
/// @nodoc
class _$FormulaStepCopyWithImpl<$Res>
    implements $FormulaStepCopyWith<$Res> {
  _$FormulaStepCopyWithImpl(this._self, this._then);

  final FormulaStep _self;
  final $Res Function(FormulaStep) _then;

/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stepId = null,Object? params = null,Object? dependsOn = null,}) {
  return _then(_self.copyWith(
stepId: null == stepId ? _self.stepId : stepId // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self.params : params // ignore: cast_nullable_to_non_nullable
as Map<String, String>,dependsOn: null == dependsOn ? _self.dependsOn : dependsOn // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [FormulaStep].
extension FormulaStepPatterns on FormulaStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CapabilityStep value)?  capability,TResult Function( SubFormulaStep value)?  subFormula,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CapabilityStep() when capability != null:
return capability(_that);case SubFormulaStep() when subFormula != null:
return subFormula(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CapabilityStep value)  capability,required TResult Function( SubFormulaStep value)  subFormula,}){
final _that = this;
switch (_that) {
case CapabilityStep():
return capability(_that);case SubFormulaStep():
return subFormula(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CapabilityStep value)?  capability,TResult? Function( SubFormulaStep value)?  subFormula,}){
final _that = this;
switch (_that) {
case CapabilityStep() when capability != null:
return capability(_that);case SubFormulaStep() when subFormula != null:
return subFormula(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String stepId,  String capabilityId,  Map<String, String> params,  Set<String> dependsOn,  StepKind kind,  ResourceRequest? resources)?  capability,TResult Function( String stepId,  String formulaId,  Map<String, String> params,  Set<String> dependsOn)?  subFormula,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CapabilityStep() when capability != null:
return capability(_that.stepId,_that.capabilityId,_that.params,_that.dependsOn,_that.kind,_that.resources);case SubFormulaStep() when subFormula != null:
return subFormula(_that.stepId,_that.formulaId,_that.params,_that.dependsOn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String stepId,  String capabilityId,  Map<String, String> params,  Set<String> dependsOn,  StepKind kind,  ResourceRequest? resources)  capability,required TResult Function( String stepId,  String formulaId,  Map<String, String> params,  Set<String> dependsOn)  subFormula,}) {final _that = this;
switch (_that) {
case CapabilityStep():
return capability(_that.stepId,_that.capabilityId,_that.params,_that.dependsOn,_that.kind,_that.resources);case SubFormulaStep():
return subFormula(_that.stepId,_that.formulaId,_that.params,_that.dependsOn);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String stepId,  String capabilityId,  Map<String, String> params,  Set<String> dependsOn,  StepKind kind,  ResourceRequest? resources)?  capability,TResult? Function( String stepId,  String formulaId,  Map<String, String> params,  Set<String> dependsOn)?  subFormula,}) {final _that = this;
switch (_that) {
case CapabilityStep() when capability != null:
return capability(_that.stepId,_that.capabilityId,_that.params,_that.dependsOn,_that.kind,_that.resources);case SubFormulaStep() when subFormula != null:
return subFormula(_that.stepId,_that.formulaId,_that.params,_that.dependsOn);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class CapabilityStep extends FormulaStep {
  const CapabilityStep({required this.stepId, required this.capabilityId, final  Map<String, String> params = const <String, String>{}, final  Set<String> dependsOn = const <String>{}, this.kind = StepKind.job, this.resources, final  String? $type}): _params = params,_dependsOn = dependsOn,$type = $type ?? 'capability',super._();
  factory CapabilityStep.fromJson(Map<String, dynamic> json) => _$CapabilityStepFromJson(json);

/// The step's id (unique within its formula).
@override final  String stepId;
/// The capability id resolved via the `CapabilityRegistry`.
 final  String capabilityId;
/// Opaque parameters threaded to the capability leaf.
 final  Map<String, String> _params;
/// Opaque parameters threaded to the capability leaf.
@override@JsonKey() Map<String, String> get params {
  if (_params is EqualUnmodifiableMapView) return _params;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_params);
}

/// The sibling step ids whose positive terminals gate this step (the
/// barrier).
 final  Set<String> _dependsOn;
/// The sibling step ids whose positive terminals gate this step (the
/// barrier).
@override@JsonKey() Set<String> get dependsOn {
  if (_dependsOn is EqualUnmodifiableSetView) return _dependsOn;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dependsOn);
}

/// Whether this leaf runs-to-completion ([StepKind.job]) or stays mounted
/// ([StepKind.daemon]).
@JsonKey() final  StepKind kind;
/// The per-leaf resource request (declared-now, honored-later — D-7).
 final  ResourceRequest? resources;

@JsonKey(name: 'type')
final String $type;


/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CapabilityStepCopyWith<CapabilityStep> get copyWith => _$CapabilityStepCopyWithImpl<CapabilityStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CapabilityStepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CapabilityStep&&(identical(other.stepId, stepId) || other.stepId == stepId)&&(identical(other.capabilityId, capabilityId) || other.capabilityId == capabilityId)&&const DeepCollectionEquality().equals(other._params, _params)&&const DeepCollectionEquality().equals(other._dependsOn, _dependsOn)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.resources, resources) || other.resources == resources));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,stepId,capabilityId,const DeepCollectionEquality().hash(_params),const DeepCollectionEquality().hash(_dependsOn),kind,resources);

@override
String toString() {
  return 'FormulaStep.capability(stepId: $stepId, capabilityId: $capabilityId, params: $params, dependsOn: $dependsOn, kind: $kind, resources: $resources)';
}


}

/// @nodoc
abstract mixin class $CapabilityStepCopyWith<$Res> implements $FormulaStepCopyWith<$Res> {
  factory $CapabilityStepCopyWith(CapabilityStep value, $Res Function(CapabilityStep) _then) = _$CapabilityStepCopyWithImpl;
@override @useResult
$Res call({
 String stepId, String capabilityId, Map<String, String> params, Set<String> dependsOn, StepKind kind, ResourceRequest? resources
});


$ResourceRequestCopyWith<$Res>? get resources;

}
/// @nodoc
class _$CapabilityStepCopyWithImpl<$Res>
    implements $CapabilityStepCopyWith<$Res> {
  _$CapabilityStepCopyWithImpl(this._self, this._then);

  final CapabilityStep _self;
  final $Res Function(CapabilityStep) _then;

/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stepId = null,Object? capabilityId = null,Object? params = null,Object? dependsOn = null,Object? kind = null,Object? resources = freezed,}) {
  return _then(CapabilityStep(
stepId: null == stepId ? _self.stepId : stepId // ignore: cast_nullable_to_non_nullable
as String,capabilityId: null == capabilityId ? _self.capabilityId : capabilityId // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self._params : params // ignore: cast_nullable_to_non_nullable
as Map<String, String>,dependsOn: null == dependsOn ? _self._dependsOn : dependsOn // ignore: cast_nullable_to_non_nullable
as Set<String>,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as StepKind,resources: freezed == resources ? _self.resources : resources // ignore: cast_nullable_to_non_nullable
as ResourceRequest?,
  ));
}

/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceRequestCopyWith<$Res>? get resources {
    if (_self.resources == null) {
    return null;
  }

  return $ResourceRequestCopyWith<$Res>(_self.resources!, (value) {
    return _then(_self.copyWith(resources: value));
  });
}
}

/// @nodoc
@JsonSerializable()

class SubFormulaStep extends FormulaStep {
  const SubFormulaStep({required this.stepId, required this.formulaId, final  Map<String, String> params = const <String, String>{}, final  Set<String> dependsOn = const <String>{}, final  String? $type}): _params = params,_dependsOn = dependsOn,$type = $type ?? 'sub_formula',super._();
  factory SubFormulaStep.fromJson(Map<String, dynamic> json) => _$SubFormulaStepFromJson(json);

/// The step's id (unique within its formula).
@override final  String stepId;
/// The id of the nested formula (resolved via the `CapabilityRegistry`).
 final  String formulaId;
/// Opaque parameters threaded to the nested formula.
 final  Map<String, String> _params;
/// Opaque parameters threaded to the nested formula.
@override@JsonKey() Map<String, String> get params {
  if (_params is EqualUnmodifiableMapView) return _params;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_params);
}

/// The sibling step ids whose positive terminals gate this step.
 final  Set<String> _dependsOn;
/// The sibling step ids whose positive terminals gate this step.
@override@JsonKey() Set<String> get dependsOn {
  if (_dependsOn is EqualUnmodifiableSetView) return _dependsOn;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dependsOn);
}


@JsonKey(name: 'type')
final String $type;


/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubFormulaStepCopyWith<SubFormulaStep> get copyWith => _$SubFormulaStepCopyWithImpl<SubFormulaStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubFormulaStepToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubFormulaStep&&(identical(other.stepId, stepId) || other.stepId == stepId)&&(identical(other.formulaId, formulaId) || other.formulaId == formulaId)&&const DeepCollectionEquality().equals(other._params, _params)&&const DeepCollectionEquality().equals(other._dependsOn, _dependsOn));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,stepId,formulaId,const DeepCollectionEquality().hash(_params),const DeepCollectionEquality().hash(_dependsOn));

@override
String toString() {
  return 'FormulaStep.subFormula(stepId: $stepId, formulaId: $formulaId, params: $params, dependsOn: $dependsOn)';
}


}

/// @nodoc
abstract mixin class $SubFormulaStepCopyWith<$Res> implements $FormulaStepCopyWith<$Res> {
  factory $SubFormulaStepCopyWith(SubFormulaStep value, $Res Function(SubFormulaStep) _then) = _$SubFormulaStepCopyWithImpl;
@override @useResult
$Res call({
 String stepId, String formulaId, Map<String, String> params, Set<String> dependsOn
});




}
/// @nodoc
class _$SubFormulaStepCopyWithImpl<$Res>
    implements $SubFormulaStepCopyWith<$Res> {
  _$SubFormulaStepCopyWithImpl(this._self, this._then);

  final SubFormulaStep _self;
  final $Res Function(SubFormulaStep) _then;

/// Create a copy of FormulaStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stepId = null,Object? formulaId = null,Object? params = null,Object? dependsOn = null,}) {
  return _then(SubFormulaStep(
stepId: null == stepId ? _self.stepId : stepId // ignore: cast_nullable_to_non_nullable
as String,formulaId: null == formulaId ? _self.formulaId : formulaId // ignore: cast_nullable_to_non_nullable
as String,params: null == params ? _self._params : params // ignore: cast_nullable_to_non_nullable
as Map<String, String>,dependsOn: null == dependsOn ? _self._dependsOn : dependsOn // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}


}


/// @nodoc
mixin _$Formula {

/// The formula id (resolved via the `CapabilityRegistry` for a sub-formula).
 String get id;/// The step-graph.
 List<FormulaStep> get steps;/// The terminal step — its positive terminal drives the session close
/// (D-2). A `dependsOn` on this formula (as a sub-formula) resolves here.
 String get terminalStepId;/// How a failed child is supervised (default [SupervisionStrategy.oneForOne]).
 SupervisionStrategy get supervision;/// The mandatory restart backoff (default [Backoff.standard]).
 Backoff get backoff;/// The supervised-restart budget per step — beyond it the breaker trips and
/// the step is circuit-broken (escalation, D-5).
 int get maxRestarts;/// The declared aggregate resource peak (declaration-only — D-7).
 ResourceRequest? get peak;
/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FormulaCopyWith<Formula> get copyWith => _$FormulaCopyWithImpl<Formula>(this as Formula, _$identity);

  /// Serializes this Formula to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Formula&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.steps, steps)&&(identical(other.terminalStepId, terminalStepId) || other.terminalStepId == terminalStepId)&&(identical(other.supervision, supervision) || other.supervision == supervision)&&(identical(other.backoff, backoff) || other.backoff == backoff)&&(identical(other.maxRestarts, maxRestarts) || other.maxRestarts == maxRestarts)&&(identical(other.peak, peak) || other.peak == peak));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(steps),terminalStepId,supervision,backoff,maxRestarts,peak);

@override
String toString() {
  return 'Formula(id: $id, steps: $steps, terminalStepId: $terminalStepId, supervision: $supervision, backoff: $backoff, maxRestarts: $maxRestarts, peak: $peak)';
}


}

/// @nodoc
abstract mixin class $FormulaCopyWith<$Res>  {
  factory $FormulaCopyWith(Formula value, $Res Function(Formula) _then) = _$FormulaCopyWithImpl;
@useResult
$Res call({
 String id, List<FormulaStep> steps, String terminalStepId, SupervisionStrategy supervision, Backoff backoff, int maxRestarts, ResourceRequest? peak
});


$BackoffCopyWith<$Res> get backoff;$ResourceRequestCopyWith<$Res>? get peak;

}
/// @nodoc
class _$FormulaCopyWithImpl<$Res>
    implements $FormulaCopyWith<$Res> {
  _$FormulaCopyWithImpl(this._self, this._then);

  final Formula _self;
  final $Res Function(Formula) _then;

/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? steps = null,Object? terminalStepId = null,Object? supervision = null,Object? backoff = null,Object? maxRestarts = null,Object? peak = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<FormulaStep>,terminalStepId: null == terminalStepId ? _self.terminalStepId : terminalStepId // ignore: cast_nullable_to_non_nullable
as String,supervision: null == supervision ? _self.supervision : supervision // ignore: cast_nullable_to_non_nullable
as SupervisionStrategy,backoff: null == backoff ? _self.backoff : backoff // ignore: cast_nullable_to_non_nullable
as Backoff,maxRestarts: null == maxRestarts ? _self.maxRestarts : maxRestarts // ignore: cast_nullable_to_non_nullable
as int,peak: freezed == peak ? _self.peak : peak // ignore: cast_nullable_to_non_nullable
as ResourceRequest?,
  ));
}
/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackoffCopyWith<$Res> get backoff {
  
  return $BackoffCopyWith<$Res>(_self.backoff, (value) {
    return _then(_self.copyWith(backoff: value));
  });
}/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceRequestCopyWith<$Res>? get peak {
    if (_self.peak == null) {
    return null;
  }

  return $ResourceRequestCopyWith<$Res>(_self.peak!, (value) {
    return _then(_self.copyWith(peak: value));
  });
}
}


/// Adds pattern-matching-related methods to [Formula].
extension FormulaPatterns on Formula {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Formula value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Formula() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Formula value)  $default,){
final _that = this;
switch (_that) {
case _Formula():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Formula value)?  $default,){
final _that = this;
switch (_that) {
case _Formula() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  List<FormulaStep> steps,  String terminalStepId,  SupervisionStrategy supervision,  Backoff backoff,  int maxRestarts,  ResourceRequest? peak)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Formula() when $default != null:
return $default(_that.id,_that.steps,_that.terminalStepId,_that.supervision,_that.backoff,_that.maxRestarts,_that.peak);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  List<FormulaStep> steps,  String terminalStepId,  SupervisionStrategy supervision,  Backoff backoff,  int maxRestarts,  ResourceRequest? peak)  $default,) {final _that = this;
switch (_that) {
case _Formula():
return $default(_that.id,_that.steps,_that.terminalStepId,_that.supervision,_that.backoff,_that.maxRestarts,_that.peak);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  List<FormulaStep> steps,  String terminalStepId,  SupervisionStrategy supervision,  Backoff backoff,  int maxRestarts,  ResourceRequest? peak)?  $default,) {final _that = this;
switch (_that) {
case _Formula() when $default != null:
return $default(_that.id,_that.steps,_that.terminalStepId,_that.supervision,_that.backoff,_that.maxRestarts,_that.peak);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Formula extends Formula {
  const _Formula({required this.id, required final  List<FormulaStep> steps, required this.terminalStepId, this.supervision = SupervisionStrategy.oneForOne, this.backoff = Backoff.standard, this.maxRestarts = 3, this.peak}): _steps = steps,super._();
  factory _Formula.fromJson(Map<String, dynamic> json) => _$FormulaFromJson(json);

/// The formula id (resolved via the `CapabilityRegistry` for a sub-formula).
@override final  String id;
/// The step-graph.
 final  List<FormulaStep> _steps;
/// The step-graph.
@override List<FormulaStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

/// The terminal step — its positive terminal drives the session close
/// (D-2). A `dependsOn` on this formula (as a sub-formula) resolves here.
@override final  String terminalStepId;
/// How a failed child is supervised (default [SupervisionStrategy.oneForOne]).
@override@JsonKey() final  SupervisionStrategy supervision;
/// The mandatory restart backoff (default [Backoff.standard]).
@override@JsonKey() final  Backoff backoff;
/// The supervised-restart budget per step — beyond it the breaker trips and
/// the step is circuit-broken (escalation, D-5).
@override@JsonKey() final  int maxRestarts;
/// The declared aggregate resource peak (declaration-only — D-7).
@override final  ResourceRequest? peak;

/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FormulaCopyWith<_Formula> get copyWith => __$FormulaCopyWithImpl<_Formula>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FormulaToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Formula&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other._steps, _steps)&&(identical(other.terminalStepId, terminalStepId) || other.terminalStepId == terminalStepId)&&(identical(other.supervision, supervision) || other.supervision == supervision)&&(identical(other.backoff, backoff) || other.backoff == backoff)&&(identical(other.maxRestarts, maxRestarts) || other.maxRestarts == maxRestarts)&&(identical(other.peak, peak) || other.peak == peak));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_steps),terminalStepId,supervision,backoff,maxRestarts,peak);

@override
String toString() {
  return 'Formula(id: $id, steps: $steps, terminalStepId: $terminalStepId, supervision: $supervision, backoff: $backoff, maxRestarts: $maxRestarts, peak: $peak)';
}


}

/// @nodoc
abstract mixin class _$FormulaCopyWith<$Res> implements $FormulaCopyWith<$Res> {
  factory _$FormulaCopyWith(_Formula value, $Res Function(_Formula) _then) = __$FormulaCopyWithImpl;
@override @useResult
$Res call({
 String id, List<FormulaStep> steps, String terminalStepId, SupervisionStrategy supervision, Backoff backoff, int maxRestarts, ResourceRequest? peak
});


@override $BackoffCopyWith<$Res> get backoff;@override $ResourceRequestCopyWith<$Res>? get peak;

}
/// @nodoc
class __$FormulaCopyWithImpl<$Res>
    implements _$FormulaCopyWith<$Res> {
  __$FormulaCopyWithImpl(this._self, this._then);

  final _Formula _self;
  final $Res Function(_Formula) _then;

/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? steps = null,Object? terminalStepId = null,Object? supervision = null,Object? backoff = null,Object? maxRestarts = null,Object? peak = freezed,}) {
  return _then(_Formula(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<FormulaStep>,terminalStepId: null == terminalStepId ? _self.terminalStepId : terminalStepId // ignore: cast_nullable_to_non_nullable
as String,supervision: null == supervision ? _self.supervision : supervision // ignore: cast_nullable_to_non_nullable
as SupervisionStrategy,backoff: null == backoff ? _self.backoff : backoff // ignore: cast_nullable_to_non_nullable
as Backoff,maxRestarts: null == maxRestarts ? _self.maxRestarts : maxRestarts // ignore: cast_nullable_to_non_nullable
as int,peak: freezed == peak ? _self.peak : peak // ignore: cast_nullable_to_non_nullable
as ResourceRequest?,
  ));
}

/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BackoffCopyWith<$Res> get backoff {
  
  return $BackoffCopyWith<$Res>(_self.backoff, (value) {
    return _then(_self.copyWith(backoff: value));
  });
}/// Create a copy of Formula
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceRequestCopyWith<$Res>? get peak {
    if (_self.peak == null) {
    return null;
  }

  return $ResourceRequestCopyWith<$Res>(_self.peak!, (value) {
    return _then(_self.copyWith(peak: value));
  });
}
}

// dart format on
