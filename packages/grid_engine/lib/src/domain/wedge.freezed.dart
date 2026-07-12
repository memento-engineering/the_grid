// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wedge.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WedgeSample {

/// Live (non-terminal) sessions.
 int get live;/// Live sessions with at least one node in [StepState.running] — the ONLY
/// evidence of an active stage. [StepState.ready] does NOT count: it is a
/// POSITIVE TERMINAL (a daemon signalled up, its dep satisfied), so a
/// session whose sole non-terminal node is a `ready` daemon with nothing
/// downstream mounting is genuinely not advancing.
 int get running;/// Live sessions parked at a gate (>=1 node [StepState.gated]) with no
/// running node.
 int get gated;/// Live sessions with a failed node whose `cooldownUntil` is still in the
/// FUTURE — a supervised restart is SCHEDULED (ADR-0008 D7's restorable
/// backoff), so the grid IS making forward progress.
 int get cooling;
/// Create a copy of WedgeSample
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WedgeSampleCopyWith<WedgeSample> get copyWith => _$WedgeSampleCopyWithImpl<WedgeSample>(this as WedgeSample, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WedgeSample&&(identical(other.live, live) || other.live == live)&&(identical(other.running, running) || other.running == running)&&(identical(other.gated, gated) || other.gated == gated)&&(identical(other.cooling, cooling) || other.cooling == cooling));
}


@override
int get hashCode => Object.hash(runtimeType,live,running,gated,cooling);

@override
String toString() {
  return 'WedgeSample(live: $live, running: $running, gated: $gated, cooling: $cooling)';
}


}

/// @nodoc
abstract mixin class $WedgeSampleCopyWith<$Res>  {
  factory $WedgeSampleCopyWith(WedgeSample value, $Res Function(WedgeSample) _then) = _$WedgeSampleCopyWithImpl;
@useResult
$Res call({
 int live, int running, int gated, int cooling
});




}
/// @nodoc
class _$WedgeSampleCopyWithImpl<$Res>
    implements $WedgeSampleCopyWith<$Res> {
  _$WedgeSampleCopyWithImpl(this._self, this._then);

  final WedgeSample _self;
  final $Res Function(WedgeSample) _then;

/// Create a copy of WedgeSample
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? live = null,Object? running = null,Object? gated = null,Object? cooling = null,}) {
  return _then(_self.copyWith(
live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as int,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as int,gated: null == gated ? _self.gated : gated // ignore: cast_nullable_to_non_nullable
as int,cooling: null == cooling ? _self.cooling : cooling // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WedgeSample].
extension WedgeSamplePatterns on WedgeSample {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WedgeSample value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WedgeSample() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WedgeSample value)  $default,){
final _that = this;
switch (_that) {
case _WedgeSample():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WedgeSample value)?  $default,){
final _that = this;
switch (_that) {
case _WedgeSample() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int live,  int running,  int gated,  int cooling)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WedgeSample() when $default != null:
return $default(_that.live,_that.running,_that.gated,_that.cooling);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int live,  int running,  int gated,  int cooling)  $default,) {final _that = this;
switch (_that) {
case _WedgeSample():
return $default(_that.live,_that.running,_that.gated,_that.cooling);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int live,  int running,  int gated,  int cooling)?  $default,) {final _that = this;
switch (_that) {
case _WedgeSample() when $default != null:
return $default(_that.live,_that.running,_that.gated,_that.cooling);case _:
  return null;

}
}

}

/// @nodoc


class _WedgeSample extends WedgeSample {
  const _WedgeSample({this.live = 0, this.running = 0, this.gated = 0, this.cooling = 0}): super._();
  

/// Live (non-terminal) sessions.
@override@JsonKey() final  int live;
/// Live sessions with at least one node in [StepState.running] — the ONLY
/// evidence of an active stage. [StepState.ready] does NOT count: it is a
/// POSITIVE TERMINAL (a daemon signalled up, its dep satisfied), so a
/// session whose sole non-terminal node is a `ready` daemon with nothing
/// downstream mounting is genuinely not advancing.
@override@JsonKey() final  int running;
/// Live sessions parked at a gate (>=1 node [StepState.gated]) with no
/// running node.
@override@JsonKey() final  int gated;
/// Live sessions with a failed node whose `cooldownUntil` is still in the
/// FUTURE — a supervised restart is SCHEDULED (ADR-0008 D7's restorable
/// backoff), so the grid IS making forward progress.
@override@JsonKey() final  int cooling;

/// Create a copy of WedgeSample
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WedgeSampleCopyWith<_WedgeSample> get copyWith => __$WedgeSampleCopyWithImpl<_WedgeSample>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _WedgeSample&&(identical(other.live, live) || other.live == live)&&(identical(other.running, running) || other.running == running)&&(identical(other.gated, gated) || other.gated == gated)&&(identical(other.cooling, cooling) || other.cooling == cooling));
}


@override
int get hashCode => Object.hash(runtimeType,live,running,gated,cooling);

@override
String toString() {
  return 'WedgeSample(live: $live, running: $running, gated: $gated, cooling: $cooling)';
}


}

/// @nodoc
abstract mixin class _$WedgeSampleCopyWith<$Res> implements $WedgeSampleCopyWith<$Res> {
  factory _$WedgeSampleCopyWith(_WedgeSample value, $Res Function(_WedgeSample) _then) = __$WedgeSampleCopyWithImpl;
@override @useResult
$Res call({
 int live, int running, int gated, int cooling
});




}
/// @nodoc
class __$WedgeSampleCopyWithImpl<$Res>
    implements _$WedgeSampleCopyWith<$Res> {
  __$WedgeSampleCopyWithImpl(this._self, this._then);

  final _WedgeSample _self;
  final $Res Function(_WedgeSample) _then;

/// Create a copy of WedgeSample
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? live = null,Object? running = null,Object? gated = null,Object? cooling = null,}) {
  return _then(_WedgeSample(
live: null == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as int,running: null == running ? _self.running : running // ignore: cast_nullable_to_non_nullable
as int,gated: null == gated ? _self.gated : gated // ignore: cast_nullable_to_non_nullable
as int,cooling: null == cooling ? _self.cooling : cooling // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WedgeState {

 WedgeSample get sample;
/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WedgeStateCopyWith<WedgeState> get copyWith => _$WedgeStateCopyWithImpl<WedgeState>(this as WedgeState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WedgeState&&(identical(other.sample, sample) || other.sample == sample));
}


@override
int get hashCode => Object.hash(runtimeType,sample);

@override
String toString() {
  return 'WedgeState(sample: $sample)';
}


}

/// @nodoc
abstract mixin class $WedgeStateCopyWith<$Res>  {
  factory $WedgeStateCopyWith(WedgeState value, $Res Function(WedgeState) _then) = _$WedgeStateCopyWithImpl;
@useResult
$Res call({
 WedgeSample sample
});


$WedgeSampleCopyWith<$Res> get sample;

}
/// @nodoc
class _$WedgeStateCopyWithImpl<$Res>
    implements $WedgeStateCopyWith<$Res> {
  _$WedgeStateCopyWithImpl(this._self, this._then);

  final WedgeState _self;
  final $Res Function(WedgeState) _then;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sample = null,}) {
  return _then(_self.copyWith(
sample: null == sample ? _self.sample : sample // ignore: cast_nullable_to_non_nullable
as WedgeSample,
  ));
}
/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WedgeSampleCopyWith<$Res> get sample {
  
  return $WedgeSampleCopyWith<$Res>(_self.sample, (value) {
    return _then(_self.copyWith(sample: value));
  });
}
}


/// Adds pattern-matching-related methods to [WedgeState].
extension WedgeStatePatterns on WedgeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Flowing value)?  flowing,TResult Function( Stalling value)?  stalling,TResult Function( Wedged value)?  wedged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Flowing() when flowing != null:
return flowing(_that);case Stalling() when stalling != null:
return stalling(_that);case Wedged() when wedged != null:
return wedged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Flowing value)  flowing,required TResult Function( Stalling value)  stalling,required TResult Function( Wedged value)  wedged,}){
final _that = this;
switch (_that) {
case Flowing():
return flowing(_that);case Stalling():
return stalling(_that);case Wedged():
return wedged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Flowing value)?  flowing,TResult? Function( Stalling value)?  stalling,TResult? Function( Wedged value)?  wedged,}){
final _that = this;
switch (_that) {
case Flowing() when flowing != null:
return flowing(_that);case Stalling() when stalling != null:
return stalling(_that);case Wedged() when wedged != null:
return wedged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( WedgeSample sample)?  flowing,TResult Function( DateTime since,  WedgeSample sample)?  stalling,TResult Function( DateTime since,  WedgeSample sample)?  wedged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Flowing() when flowing != null:
return flowing(_that.sample);case Stalling() when stalling != null:
return stalling(_that.since,_that.sample);case Wedged() when wedged != null:
return wedged(_that.since,_that.sample);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( WedgeSample sample)  flowing,required TResult Function( DateTime since,  WedgeSample sample)  stalling,required TResult Function( DateTime since,  WedgeSample sample)  wedged,}) {final _that = this;
switch (_that) {
case Flowing():
return flowing(_that.sample);case Stalling():
return stalling(_that.since,_that.sample);case Wedged():
return wedged(_that.since,_that.sample);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( WedgeSample sample)?  flowing,TResult? Function( DateTime since,  WedgeSample sample)?  stalling,TResult? Function( DateTime since,  WedgeSample sample)?  wedged,}) {final _that = this;
switch (_that) {
case Flowing() when flowing != null:
return flowing(_that.sample);case Stalling() when stalling != null:
return stalling(_that.since,_that.sample);case Wedged() when wedged != null:
return wedged(_that.since,_that.sample);case _:
  return null;

}
}

}

/// @nodoc


class Flowing extends WedgeState {
  const Flowing({required this.sample}): super._();
  

@override final  WedgeSample sample;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlowingCopyWith<Flowing> get copyWith => _$FlowingCopyWithImpl<Flowing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Flowing&&(identical(other.sample, sample) || other.sample == sample));
}


@override
int get hashCode => Object.hash(runtimeType,sample);

@override
String toString() {
  return 'WedgeState.flowing(sample: $sample)';
}


}

/// @nodoc
abstract mixin class $FlowingCopyWith<$Res> implements $WedgeStateCopyWith<$Res> {
  factory $FlowingCopyWith(Flowing value, $Res Function(Flowing) _then) = _$FlowingCopyWithImpl;
@override @useResult
$Res call({
 WedgeSample sample
});


@override $WedgeSampleCopyWith<$Res> get sample;

}
/// @nodoc
class _$FlowingCopyWithImpl<$Res>
    implements $FlowingCopyWith<$Res> {
  _$FlowingCopyWithImpl(this._self, this._then);

  final Flowing _self;
  final $Res Function(Flowing) _then;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sample = null,}) {
  return _then(Flowing(
sample: null == sample ? _self.sample : sample // ignore: cast_nullable_to_non_nullable
as WedgeSample,
  ));
}

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WedgeSampleCopyWith<$Res> get sample {
  
  return $WedgeSampleCopyWith<$Res>(_self.sample, (value) {
    return _then(_self.copyWith(sample: value));
  });
}
}

/// @nodoc


class Stalling extends WedgeState {
  const Stalling({required this.since, required this.sample}): super._();
  

 final  DateTime since;
@override final  WedgeSample sample;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StallingCopyWith<Stalling> get copyWith => _$StallingCopyWithImpl<Stalling>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Stalling&&(identical(other.since, since) || other.since == since)&&(identical(other.sample, sample) || other.sample == sample));
}


@override
int get hashCode => Object.hash(runtimeType,since,sample);

@override
String toString() {
  return 'WedgeState.stalling(since: $since, sample: $sample)';
}


}

/// @nodoc
abstract mixin class $StallingCopyWith<$Res> implements $WedgeStateCopyWith<$Res> {
  factory $StallingCopyWith(Stalling value, $Res Function(Stalling) _then) = _$StallingCopyWithImpl;
@override @useResult
$Res call({
 DateTime since, WedgeSample sample
});


@override $WedgeSampleCopyWith<$Res> get sample;

}
/// @nodoc
class _$StallingCopyWithImpl<$Res>
    implements $StallingCopyWith<$Res> {
  _$StallingCopyWithImpl(this._self, this._then);

  final Stalling _self;
  final $Res Function(Stalling) _then;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? since = null,Object? sample = null,}) {
  return _then(Stalling(
since: null == since ? _self.since : since // ignore: cast_nullable_to_non_nullable
as DateTime,sample: null == sample ? _self.sample : sample // ignore: cast_nullable_to_non_nullable
as WedgeSample,
  ));
}

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WedgeSampleCopyWith<$Res> get sample {
  
  return $WedgeSampleCopyWith<$Res>(_self.sample, (value) {
    return _then(_self.copyWith(sample: value));
  });
}
}

/// @nodoc


class Wedged extends WedgeState {
  const Wedged({required this.since, required this.sample}): super._();
  

 final  DateTime since;
@override final  WedgeSample sample;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WedgedCopyWith<Wedged> get copyWith => _$WedgedCopyWithImpl<Wedged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Wedged&&(identical(other.since, since) || other.since == since)&&(identical(other.sample, sample) || other.sample == sample));
}


@override
int get hashCode => Object.hash(runtimeType,since,sample);

@override
String toString() {
  return 'WedgeState.wedged(since: $since, sample: $sample)';
}


}

/// @nodoc
abstract mixin class $WedgedCopyWith<$Res> implements $WedgeStateCopyWith<$Res> {
  factory $WedgedCopyWith(Wedged value, $Res Function(Wedged) _then) = _$WedgedCopyWithImpl;
@override @useResult
$Res call({
 DateTime since, WedgeSample sample
});


@override $WedgeSampleCopyWith<$Res> get sample;

}
/// @nodoc
class _$WedgedCopyWithImpl<$Res>
    implements $WedgedCopyWith<$Res> {
  _$WedgedCopyWithImpl(this._self, this._then);

  final Wedged _self;
  final $Res Function(Wedged) _then;

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? since = null,Object? sample = null,}) {
  return _then(Wedged(
since: null == since ? _self.since : since // ignore: cast_nullable_to_non_nullable
as DateTime,sample: null == sample ? _self.sample : sample // ignore: cast_nullable_to_non_nullable
as WedgeSample,
  ));
}

/// Create a copy of WedgeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WedgeSampleCopyWith<$Res> get sample {
  
  return $WedgeSampleCopyWith<$Res>(_self.sample, (value) {
    return _then(_self.copyWith(sample: value));
  });
}
}

// dart format on
