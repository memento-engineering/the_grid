// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'process_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProcessSessionUpdate {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProcessSessionUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ProcessSessionUpdate()';
}


}

/// @nodoc
class $ProcessSessionUpdateCopyWith<$Res>  {
$ProcessSessionUpdateCopyWith(ProcessSessionUpdate _, $Res Function(ProcessSessionUpdate) __);
}


/// Adds pattern-matching-related methods to [ProcessSessionUpdate].
extension ProcessSessionUpdatePatterns on ProcessSessionUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProcessSessionProgress value)?  progress,TResult Function( ProcessSessionCompleted value)?  completed,TResult Function( ProcessSessionFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProcessSessionProgress() when progress != null:
return progress(_that);case ProcessSessionCompleted() when completed != null:
return completed(_that);case ProcessSessionFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProcessSessionProgress value)  progress,required TResult Function( ProcessSessionCompleted value)  completed,required TResult Function( ProcessSessionFailed value)  failed,}){
final _that = this;
switch (_that) {
case ProcessSessionProgress():
return progress(_that);case ProcessSessionCompleted():
return completed(_that);case ProcessSessionFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProcessSessionProgress value)?  progress,TResult? Function( ProcessSessionCompleted value)?  completed,TResult? Function( ProcessSessionFailed value)?  failed,}){
final _that = this;
switch (_that) {
case ProcessSessionProgress() when progress != null:
return progress(_that);case ProcessSessionCompleted() when completed != null:
return completed(_that);case ProcessSessionFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Map<String, String> fields)?  progress,TResult Function( Map<String, String> result)?  completed,TResult Function( String reason,  CapabilityFailureKind? kind)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ProcessSessionProgress() when progress != null:
return progress(_that.fields);case ProcessSessionCompleted() when completed != null:
return completed(_that.result);case ProcessSessionFailed() when failed != null:
return failed(_that.reason,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Map<String, String> fields)  progress,required TResult Function( Map<String, String> result)  completed,required TResult Function( String reason,  CapabilityFailureKind? kind)  failed,}) {final _that = this;
switch (_that) {
case ProcessSessionProgress():
return progress(_that.fields);case ProcessSessionCompleted():
return completed(_that.result);case ProcessSessionFailed():
return failed(_that.reason,_that.kind);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Map<String, String> fields)?  progress,TResult? Function( Map<String, String> result)?  completed,TResult? Function( String reason,  CapabilityFailureKind? kind)?  failed,}) {final _that = this;
switch (_that) {
case ProcessSessionProgress() when progress != null:
return progress(_that.fields);case ProcessSessionCompleted() when completed != null:
return completed(_that.result);case ProcessSessionFailed() when failed != null:
return failed(_that.reason,_that.kind);case _:
  return null;

}
}

}

/// @nodoc


class ProcessSessionProgress extends ProcessSessionUpdate {
  const ProcessSessionProgress({final  Map<String, String> fields = const <String, String>{}}): _fields = fields,super._();


 final  Map<String, String> _fields;
@JsonKey() Map<String, String> get fields {
  if (_fields is EqualUnmodifiableMapView) return _fields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_fields);
}


/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProcessSessionProgressCopyWith<ProcessSessionProgress> get copyWith => _$ProcessSessionProgressCopyWithImpl<ProcessSessionProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProcessSessionProgress&&const DeepCollectionEquality().equals(other._fields, _fields));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_fields));

@override
String toString() {
  return 'ProcessSessionUpdate.progress(fields: $fields)';
}


}

/// @nodoc
abstract mixin class $ProcessSessionProgressCopyWith<$Res> implements $ProcessSessionUpdateCopyWith<$Res> {
  factory $ProcessSessionProgressCopyWith(ProcessSessionProgress value, $Res Function(ProcessSessionProgress) _then) = _$ProcessSessionProgressCopyWithImpl;
@useResult
$Res call({
 Map<String, String> fields
});




}
/// @nodoc
class _$ProcessSessionProgressCopyWithImpl<$Res>
    implements $ProcessSessionProgressCopyWith<$Res> {
  _$ProcessSessionProgressCopyWithImpl(this._self, this._then);

  final ProcessSessionProgress _self;
  final $Res Function(ProcessSessionProgress) _then;

/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fields = null,}) {
  return _then(ProcessSessionProgress(
fields: null == fields ? _self._fields : fields // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

/// @nodoc


class ProcessSessionCompleted extends ProcessSessionUpdate {
  const ProcessSessionCompleted({required final  Map<String, String> result}): _result = result,super._();


 final  Map<String, String> _result;
 Map<String, String> get result {
  if (_result is EqualUnmodifiableMapView) return _result;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_result);
}


/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProcessSessionCompletedCopyWith<ProcessSessionCompleted> get copyWith => _$ProcessSessionCompletedCopyWithImpl<ProcessSessionCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProcessSessionCompleted&&const DeepCollectionEquality().equals(other._result, _result));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_result));

@override
String toString() {
  return 'ProcessSessionUpdate.completed(result: $result)';
}


}

/// @nodoc
abstract mixin class $ProcessSessionCompletedCopyWith<$Res> implements $ProcessSessionUpdateCopyWith<$Res> {
  factory $ProcessSessionCompletedCopyWith(ProcessSessionCompleted value, $Res Function(ProcessSessionCompleted) _then) = _$ProcessSessionCompletedCopyWithImpl;
@useResult
$Res call({
 Map<String, String> result
});




}
/// @nodoc
class _$ProcessSessionCompletedCopyWithImpl<$Res>
    implements $ProcessSessionCompletedCopyWith<$Res> {
  _$ProcessSessionCompletedCopyWithImpl(this._self, this._then);

  final ProcessSessionCompleted _self;
  final $Res Function(ProcessSessionCompleted) _then;

/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = null,}) {
  return _then(ProcessSessionCompleted(
result: null == result ? _self._result : result // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

/// @nodoc


class ProcessSessionFailed extends ProcessSessionUpdate {
  const ProcessSessionFailed({required this.reason, this.kind}): super._();


 final  String reason;
 final  CapabilityFailureKind? kind;

/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProcessSessionFailedCopyWith<ProcessSessionFailed> get copyWith => _$ProcessSessionFailedCopyWithImpl<ProcessSessionFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProcessSessionFailed&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode => Object.hash(runtimeType,reason,kind);

@override
String toString() {
  return 'ProcessSessionUpdate.failed(reason: $reason, kind: $kind)';
}


}

/// @nodoc
abstract mixin class $ProcessSessionFailedCopyWith<$Res> implements $ProcessSessionUpdateCopyWith<$Res> {
  factory $ProcessSessionFailedCopyWith(ProcessSessionFailed value, $Res Function(ProcessSessionFailed) _then) = _$ProcessSessionFailedCopyWithImpl;
@useResult
$Res call({
 String reason, CapabilityFailureKind? kind
});




}
/// @nodoc
class _$ProcessSessionFailedCopyWithImpl<$Res>
    implements $ProcessSessionFailedCopyWith<$Res> {
  _$ProcessSessionFailedCopyWithImpl(this._self, this._then);

  final ProcessSessionFailed _self;
  final $Res Function(ProcessSessionFailed) _then;

/// Create a copy of ProcessSessionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,Object? kind = freezed,}) {
  return _then(ProcessSessionFailed(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,kind: freezed == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as CapabilityFailureKind?,
  ));
}


}

/// @nodoc
mixin _$ProcessSessionCommand {

 String get commandId; String get attemptId; String get instanceFence; String get body;
/// Create a copy of ProcessSessionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProcessSessionCommandCopyWith<ProcessSessionCommand> get copyWith => _$ProcessSessionCommandCopyWithImpl<ProcessSessionCommand>(this as ProcessSessionCommand, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProcessSessionCommand&&(identical(other.commandId, commandId) || other.commandId == commandId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.instanceFence, instanceFence) || other.instanceFence == instanceFence)&&(identical(other.body, body) || other.body == body));
}


@override
int get hashCode => Object.hash(runtimeType,commandId,attemptId,instanceFence,body);

@override
String toString() {
  return 'ProcessSessionCommand(commandId: $commandId, attemptId: $attemptId, instanceFence: $instanceFence, body: $body)';
}


}

/// @nodoc
abstract mixin class $ProcessSessionCommandCopyWith<$Res>  {
  factory $ProcessSessionCommandCopyWith(ProcessSessionCommand value, $Res Function(ProcessSessionCommand) _then) = _$ProcessSessionCommandCopyWithImpl;
@useResult
$Res call({
 String commandId, String attemptId, String instanceFence, String body
});




}
/// @nodoc
class _$ProcessSessionCommandCopyWithImpl<$Res>
    implements $ProcessSessionCommandCopyWith<$Res> {
  _$ProcessSessionCommandCopyWithImpl(this._self, this._then);

  final ProcessSessionCommand _self;
  final $Res Function(ProcessSessionCommand) _then;

/// Create a copy of ProcessSessionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? commandId = null,Object? attemptId = null,Object? instanceFence = null,Object? body = null,}) {
  return _then(_self.copyWith(
commandId: null == commandId ? _self.commandId : commandId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,instanceFence: null == instanceFence ? _self.instanceFence : instanceFence // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ProcessSessionCommand].
extension ProcessSessionCommandPatterns on ProcessSessionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProcessSessionCommand value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProcessSessionCommand() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProcessSessionCommand value)  $default,){
final _that = this;
switch (_that) {
case _ProcessSessionCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProcessSessionCommand value)?  $default,){
final _that = this;
switch (_that) {
case _ProcessSessionCommand() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String commandId,  String attemptId,  String instanceFence,  String body)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProcessSessionCommand() when $default != null:
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.body);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String commandId,  String attemptId,  String instanceFence,  String body)  $default,) {final _that = this;
switch (_that) {
case _ProcessSessionCommand():
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.body);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String commandId,  String attemptId,  String instanceFence,  String body)?  $default,) {final _that = this;
switch (_that) {
case _ProcessSessionCommand() when $default != null:
return $default(_that.commandId,_that.attemptId,_that.instanceFence,_that.body);case _:
  return null;

}
}

}

/// @nodoc


class _ProcessSessionCommand implements ProcessSessionCommand {
  const _ProcessSessionCommand({required this.commandId, required this.attemptId, required this.instanceFence, required this.body});


@override final  String commandId;
@override final  String attemptId;
@override final  String instanceFence;
@override final  String body;

/// Create a copy of ProcessSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProcessSessionCommandCopyWith<_ProcessSessionCommand> get copyWith => __$ProcessSessionCommandCopyWithImpl<_ProcessSessionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProcessSessionCommand&&(identical(other.commandId, commandId) || other.commandId == commandId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.instanceFence, instanceFence) || other.instanceFence == instanceFence)&&(identical(other.body, body) || other.body == body));
}


@override
int get hashCode => Object.hash(runtimeType,commandId,attemptId,instanceFence,body);

@override
String toString() {
  return 'ProcessSessionCommand(commandId: $commandId, attemptId: $attemptId, instanceFence: $instanceFence, body: $body)';
}


}

/// @nodoc
abstract mixin class _$ProcessSessionCommandCopyWith<$Res> implements $ProcessSessionCommandCopyWith<$Res> {
  factory _$ProcessSessionCommandCopyWith(_ProcessSessionCommand value, $Res Function(_ProcessSessionCommand) _then) = __$ProcessSessionCommandCopyWithImpl;
@override @useResult
$Res call({
 String commandId, String attemptId, String instanceFence, String body
});




}
/// @nodoc
class __$ProcessSessionCommandCopyWithImpl<$Res>
    implements _$ProcessSessionCommandCopyWith<$Res> {
  __$ProcessSessionCommandCopyWithImpl(this._self, this._then);

  final _ProcessSessionCommand _self;
  final $Res Function(_ProcessSessionCommand) _then;

/// Create a copy of ProcessSessionCommand
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? commandId = null,Object? attemptId = null,Object? instanceFence = null,Object? body = null,}) {
  return _then(_ProcessSessionCommand(
commandId: null == commandId ? _self.commandId : commandId // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,instanceFence: null == instanceFence ? _self.instanceFence : instanceFence // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
