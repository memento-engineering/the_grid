// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'work_assembly.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StationWorkRuntimeState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StationWorkRuntimeState()';
}


}

/// @nodoc
class $StationWorkRuntimeStateCopyWith<$Res>  {
$StationWorkRuntimeStateCopyWith(StationWorkRuntimeState _, $Res Function(StationWorkRuntimeState) __);
}


/// Adds pattern-matching-related methods to [StationWorkRuntimeState].
extension StationWorkRuntimeStatePatterns on StationWorkRuntimeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StationWorkRuntimeNotStarted value)?  notStarted,TResult Function( StationWorkRuntimeStarting value)?  starting,TResult Function( StationWorkRuntimeStarted value)?  started,TResult Function( StationWorkRuntimeFailed value)?  failed,TResult Function( StationWorkRuntimeShutdown value)?  shutdown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted() when notStarted != null:
return notStarted(_that);case StationWorkRuntimeStarting() when starting != null:
return starting(_that);case StationWorkRuntimeStarted() when started != null:
return started(_that);case StationWorkRuntimeFailed() when failed != null:
return failed(_that);case StationWorkRuntimeShutdown() when shutdown != null:
return shutdown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StationWorkRuntimeNotStarted value)  notStarted,required TResult Function( StationWorkRuntimeStarting value)  starting,required TResult Function( StationWorkRuntimeStarted value)  started,required TResult Function( StationWorkRuntimeFailed value)  failed,required TResult Function( StationWorkRuntimeShutdown value)  shutdown,}){
final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted():
return notStarted(_that);case StationWorkRuntimeStarting():
return starting(_that);case StationWorkRuntimeStarted():
return started(_that);case StationWorkRuntimeFailed():
return failed(_that);case StationWorkRuntimeShutdown():
return shutdown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StationWorkRuntimeNotStarted value)?  notStarted,TResult? Function( StationWorkRuntimeStarting value)?  starting,TResult? Function( StationWorkRuntimeStarted value)?  started,TResult? Function( StationWorkRuntimeFailed value)?  failed,TResult? Function( StationWorkRuntimeShutdown value)?  shutdown,}){
final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted() when notStarted != null:
return notStarted(_that);case StationWorkRuntimeStarting() when starting != null:
return starting(_that);case StationWorkRuntimeStarted() when started != null:
return started(_that);case StationWorkRuntimeFailed() when failed != null:
return failed(_that);case StationWorkRuntimeShutdown() when shutdown != null:
return shutdown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notStarted,TResult Function( StationWorkStartStage stage)?  starting,TResult Function()?  started,TResult Function( StationWorkStartStage stage,  Object error,  StackTrace stackTrace)?  failed,TResult Function()?  shutdown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted() when notStarted != null:
return notStarted();case StationWorkRuntimeStarting() when starting != null:
return starting(_that.stage);case StationWorkRuntimeStarted() when started != null:
return started();case StationWorkRuntimeFailed() when failed != null:
return failed(_that.stage,_that.error,_that.stackTrace);case StationWorkRuntimeShutdown() when shutdown != null:
return shutdown();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notStarted,required TResult Function( StationWorkStartStage stage)  starting,required TResult Function()  started,required TResult Function( StationWorkStartStage stage,  Object error,  StackTrace stackTrace)  failed,required TResult Function()  shutdown,}) {final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted():
return notStarted();case StationWorkRuntimeStarting():
return starting(_that.stage);case StationWorkRuntimeStarted():
return started();case StationWorkRuntimeFailed():
return failed(_that.stage,_that.error,_that.stackTrace);case StationWorkRuntimeShutdown():
return shutdown();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notStarted,TResult? Function( StationWorkStartStage stage)?  starting,TResult? Function()?  started,TResult? Function( StationWorkStartStage stage,  Object error,  StackTrace stackTrace)?  failed,TResult? Function()?  shutdown,}) {final _that = this;
switch (_that) {
case StationWorkRuntimeNotStarted() when notStarted != null:
return notStarted();case StationWorkRuntimeStarting() when starting != null:
return starting(_that.stage);case StationWorkRuntimeStarted() when started != null:
return started();case StationWorkRuntimeFailed() when failed != null:
return failed(_that.stage,_that.error,_that.stackTrace);case StationWorkRuntimeShutdown() when shutdown != null:
return shutdown();case _:
  return null;

}
}

}

/// @nodoc


class StationWorkRuntimeNotStarted implements StationWorkRuntimeState {
  const StationWorkRuntimeNotStarted();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeNotStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StationWorkRuntimeState.notStarted()';
}


}




/// @nodoc


class StationWorkRuntimeStarting implements StationWorkRuntimeState {
  const StationWorkRuntimeStarting({required this.stage});
  

 final  StationWorkStartStage stage;

/// Create a copy of StationWorkRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StationWorkRuntimeStartingCopyWith<StationWorkRuntimeStarting> get copyWith => _$StationWorkRuntimeStartingCopyWithImpl<StationWorkRuntimeStarting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeStarting&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode => Object.hash(runtimeType,stage);

@override
String toString() {
  return 'StationWorkRuntimeState.starting(stage: $stage)';
}


}

/// @nodoc
abstract mixin class $StationWorkRuntimeStartingCopyWith<$Res> implements $StationWorkRuntimeStateCopyWith<$Res> {
  factory $StationWorkRuntimeStartingCopyWith(StationWorkRuntimeStarting value, $Res Function(StationWorkRuntimeStarting) _then) = _$StationWorkRuntimeStartingCopyWithImpl;
@useResult
$Res call({
 StationWorkStartStage stage
});




}
/// @nodoc
class _$StationWorkRuntimeStartingCopyWithImpl<$Res>
    implements $StationWorkRuntimeStartingCopyWith<$Res> {
  _$StationWorkRuntimeStartingCopyWithImpl(this._self, this._then);

  final StationWorkRuntimeStarting _self;
  final $Res Function(StationWorkRuntimeStarting) _then;

/// Create a copy of StationWorkRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stage = null,}) {
  return _then(StationWorkRuntimeStarting(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as StationWorkStartStage,
  ));
}


}

/// @nodoc


class StationWorkRuntimeStarted implements StationWorkRuntimeState {
  const StationWorkRuntimeStarted();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeStarted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StationWorkRuntimeState.started()';
}


}




/// @nodoc


class StationWorkRuntimeFailed implements StationWorkRuntimeState {
  const StationWorkRuntimeFailed({required this.stage, required this.error, required this.stackTrace});
  

 final  StationWorkStartStage stage;
 final  Object error;
 final  StackTrace stackTrace;

/// Create a copy of StationWorkRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StationWorkRuntimeFailedCopyWith<StationWorkRuntimeFailed> get copyWith => _$StationWorkRuntimeFailedCopyWithImpl<StationWorkRuntimeFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeFailed&&(identical(other.stage, stage) || other.stage == stage)&&const DeepCollectionEquality().equals(other.error, error)&&(identical(other.stackTrace, stackTrace) || other.stackTrace == stackTrace));
}


@override
int get hashCode => Object.hash(runtimeType,stage,const DeepCollectionEquality().hash(error),stackTrace);

@override
String toString() {
  return 'StationWorkRuntimeState.failed(stage: $stage, error: $error, stackTrace: $stackTrace)';
}


}

/// @nodoc
abstract mixin class $StationWorkRuntimeFailedCopyWith<$Res> implements $StationWorkRuntimeStateCopyWith<$Res> {
  factory $StationWorkRuntimeFailedCopyWith(StationWorkRuntimeFailed value, $Res Function(StationWorkRuntimeFailed) _then) = _$StationWorkRuntimeFailedCopyWithImpl;
@useResult
$Res call({
 StationWorkStartStage stage, Object error, StackTrace stackTrace
});




}
/// @nodoc
class _$StationWorkRuntimeFailedCopyWithImpl<$Res>
    implements $StationWorkRuntimeFailedCopyWith<$Res> {
  _$StationWorkRuntimeFailedCopyWithImpl(this._self, this._then);

  final StationWorkRuntimeFailed _self;
  final $Res Function(StationWorkRuntimeFailed) _then;

/// Create a copy of StationWorkRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stage = null,Object? error = null,Object? stackTrace = null,}) {
  return _then(StationWorkRuntimeFailed(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as StationWorkStartStage,error: null == error ? _self.error : error ,stackTrace: null == stackTrace ? _self.stackTrace : stackTrace // ignore: cast_nullable_to_non_nullable
as StackTrace,
  ));
}


}

/// @nodoc


class StationWorkRuntimeShutdown implements StationWorkRuntimeState {
  const StationWorkRuntimeShutdown();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationWorkRuntimeShutdown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StationWorkRuntimeState.shutdown()';
}


}




// dart format on
