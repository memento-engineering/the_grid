// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'gate_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GateResult {

/// gc's `Outcome` is an **open string**, not the closed enum:
///
/// * `''` means "no gate ran" — manual mode passes `GateResult{}`
///   (handler.go:305-306) and `GateResultToPayload` returns a nil
///   payload for it (events.go:195-206);
/// * the replay branch reads the persisted value **verbatim** without
///   validation (handler.go:282).
///
/// Step-7 branching compares wire literals (`== "pass"`,
/// `== "timeout"`); anything else — including garbage — falls into the
/// iterate-or-terminal path, exactly like gc. Use [outcome] for the
/// typed view.
 String get outcomeWire;/// Null when no exit code applies (timeout/pre-exec error) — persisted
/// as `""`, never `"0"` or absent (handler.go:780-784).
 int? get exitCode;/// Timed-out attempts before the final one, ≤ 3; counts only timeouts
/// (condition.go:269-287).
 int get retryCount;/// Captured stdout, truncated to 4096 bytes (capture.go).
 String get stdout;/// Captured stderr — or the runner's error string on the `error`
/// outcome (condition.go:385-391).
 String get stderr;/// Wall-clock gate duration; persisted as decimal milliseconds
/// (handler.go:796).
 Duration get duration;/// True when either stream was truncated; persisted as `"true"` / `""`
/// (handler.go:799-803).
 bool get truncated;
/// Create a copy of GateResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GateResultCopyWith<GateResult> get copyWith => _$GateResultCopyWithImpl<GateResult>(this as GateResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GateResult&&(identical(other.outcomeWire, outcomeWire) || other.outcomeWire == outcomeWire)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.retryCount, retryCount) || other.retryCount == retryCount)&&(identical(other.stdout, stdout) || other.stdout == stdout)&&(identical(other.stderr, stderr) || other.stderr == stderr)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.truncated, truncated) || other.truncated == truncated));
}


@override
int get hashCode => Object.hash(runtimeType,outcomeWire,exitCode,retryCount,stdout,stderr,duration,truncated);

@override
String toString() {
  return 'GateResult(outcomeWire: $outcomeWire, exitCode: $exitCode, retryCount: $retryCount, stdout: $stdout, stderr: $stderr, duration: $duration, truncated: $truncated)';
}


}

/// @nodoc
abstract mixin class $GateResultCopyWith<$Res>  {
  factory $GateResultCopyWith(GateResult value, $Res Function(GateResult) _then) = _$GateResultCopyWithImpl;
@useResult
$Res call({
 String outcomeWire, int? exitCode, int retryCount, String stdout, String stderr, Duration duration, bool truncated
});




}
/// @nodoc
class _$GateResultCopyWithImpl<$Res>
    implements $GateResultCopyWith<$Res> {
  _$GateResultCopyWithImpl(this._self, this._then);

  final GateResult _self;
  final $Res Function(GateResult) _then;

/// Create a copy of GateResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outcomeWire = null,Object? exitCode = freezed,Object? retryCount = null,Object? stdout = null,Object? stderr = null,Object? duration = null,Object? truncated = null,}) {
  return _then(_self.copyWith(
outcomeWire: null == outcomeWire ? _self.outcomeWire : outcomeWire // ignore: cast_nullable_to_non_nullable
as String,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,retryCount: null == retryCount ? _self.retryCount : retryCount // ignore: cast_nullable_to_non_nullable
as int,stdout: null == stdout ? _self.stdout : stdout // ignore: cast_nullable_to_non_nullable
as String,stderr: null == stderr ? _self.stderr : stderr // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [GateResult].
extension GateResultPatterns on GateResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GateResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GateResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GateResult value)  $default,){
final _that = this;
switch (_that) {
case _GateResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GateResult value)?  $default,){
final _that = this;
switch (_that) {
case _GateResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String outcomeWire,  int? exitCode,  int retryCount,  String stdout,  String stderr,  Duration duration,  bool truncated)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GateResult() when $default != null:
return $default(_that.outcomeWire,_that.exitCode,_that.retryCount,_that.stdout,_that.stderr,_that.duration,_that.truncated);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String outcomeWire,  int? exitCode,  int retryCount,  String stdout,  String stderr,  Duration duration,  bool truncated)  $default,) {final _that = this;
switch (_that) {
case _GateResult():
return $default(_that.outcomeWire,_that.exitCode,_that.retryCount,_that.stdout,_that.stderr,_that.duration,_that.truncated);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String outcomeWire,  int? exitCode,  int retryCount,  String stdout,  String stderr,  Duration duration,  bool truncated)?  $default,) {final _that = this;
switch (_that) {
case _GateResult() when $default != null:
return $default(_that.outcomeWire,_that.exitCode,_that.retryCount,_that.stdout,_that.stderr,_that.duration,_that.truncated);case _:
  return null;

}
}

}

/// @nodoc


class _GateResult extends GateResult {
  const _GateResult({this.outcomeWire = '', this.exitCode, this.retryCount = 0, this.stdout = '', this.stderr = '', this.duration = Duration.zero, this.truncated = false}): super._();
  

/// gc's `Outcome` is an **open string**, not the closed enum:
///
/// * `''` means "no gate ran" — manual mode passes `GateResult{}`
///   (handler.go:305-306) and `GateResultToPayload` returns a nil
///   payload for it (events.go:195-206);
/// * the replay branch reads the persisted value **verbatim** without
///   validation (handler.go:282).
///
/// Step-7 branching compares wire literals (`== "pass"`,
/// `== "timeout"`); anything else — including garbage — falls into the
/// iterate-or-terminal path, exactly like gc. Use [outcome] for the
/// typed view.
@override@JsonKey() final  String outcomeWire;
/// Null when no exit code applies (timeout/pre-exec error) — persisted
/// as `""`, never `"0"` or absent (handler.go:780-784).
@override final  int? exitCode;
/// Timed-out attempts before the final one, ≤ 3; counts only timeouts
/// (condition.go:269-287).
@override@JsonKey() final  int retryCount;
/// Captured stdout, truncated to 4096 bytes (capture.go).
@override@JsonKey() final  String stdout;
/// Captured stderr — or the runner's error string on the `error`
/// outcome (condition.go:385-391).
@override@JsonKey() final  String stderr;
/// Wall-clock gate duration; persisted as decimal milliseconds
/// (handler.go:796).
@override@JsonKey() final  Duration duration;
/// True when either stream was truncated; persisted as `"true"` / `""`
/// (handler.go:799-803).
@override@JsonKey() final  bool truncated;

/// Create a copy of GateResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GateResultCopyWith<_GateResult> get copyWith => __$GateResultCopyWithImpl<_GateResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GateResult&&(identical(other.outcomeWire, outcomeWire) || other.outcomeWire == outcomeWire)&&(identical(other.exitCode, exitCode) || other.exitCode == exitCode)&&(identical(other.retryCount, retryCount) || other.retryCount == retryCount)&&(identical(other.stdout, stdout) || other.stdout == stdout)&&(identical(other.stderr, stderr) || other.stderr == stderr)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.truncated, truncated) || other.truncated == truncated));
}


@override
int get hashCode => Object.hash(runtimeType,outcomeWire,exitCode,retryCount,stdout,stderr,duration,truncated);

@override
String toString() {
  return 'GateResult(outcomeWire: $outcomeWire, exitCode: $exitCode, retryCount: $retryCount, stdout: $stdout, stderr: $stderr, duration: $duration, truncated: $truncated)';
}


}

/// @nodoc
abstract mixin class _$GateResultCopyWith<$Res> implements $GateResultCopyWith<$Res> {
  factory _$GateResultCopyWith(_GateResult value, $Res Function(_GateResult) _then) = __$GateResultCopyWithImpl;
@override @useResult
$Res call({
 String outcomeWire, int? exitCode, int retryCount, String stdout, String stderr, Duration duration, bool truncated
});




}
/// @nodoc
class __$GateResultCopyWithImpl<$Res>
    implements _$GateResultCopyWith<$Res> {
  __$GateResultCopyWithImpl(this._self, this._then);

  final _GateResult _self;
  final $Res Function(_GateResult) _then;

/// Create a copy of GateResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outcomeWire = null,Object? exitCode = freezed,Object? retryCount = null,Object? stdout = null,Object? stderr = null,Object? duration = null,Object? truncated = null,}) {
  return _then(_GateResult(
outcomeWire: null == outcomeWire ? _self.outcomeWire : outcomeWire // ignore: cast_nullable_to_non_nullable
as String,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,retryCount: null == retryCount ? _self.retryCount : retryCount // ignore: cast_nullable_to_non_nullable
as int,stdout: null == stdout ? _self.stdout : stdout // ignore: cast_nullable_to_non_nullable
as String,stderr: null == stderr ? _self.stderr : stderr // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,truncated: null == truncated ? _self.truncated : truncated // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
