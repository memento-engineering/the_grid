// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'relay.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RelayObservation {

 String get sessionId; String get workBeadId; DateTime? get startedAt; DateTime get deadline; DateTime get observedAt;
/// Create a copy of RelayObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RelayObservationCopyWith<RelayObservation> get copyWith => _$RelayObservationCopyWithImpl<RelayObservation>(this as RelayObservation, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayObservation&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.observedAt, observedAt) || other.observedAt == observedAt));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,workBeadId,startedAt,deadline,observedAt);

@override
String toString() {
  return 'RelayObservation(sessionId: $sessionId, workBeadId: $workBeadId, startedAt: $startedAt, deadline: $deadline, observedAt: $observedAt)';
}


}

/// @nodoc
abstract mixin class $RelayObservationCopyWith<$Res>  {
  factory $RelayObservationCopyWith(RelayObservation value, $Res Function(RelayObservation) _then) = _$RelayObservationCopyWithImpl;
@useResult
$Res call({
 String sessionId, String workBeadId, DateTime? startedAt, DateTime deadline, DateTime observedAt
});




}
/// @nodoc
class _$RelayObservationCopyWithImpl<$Res>
    implements $RelayObservationCopyWith<$Res> {
  _$RelayObservationCopyWithImpl(this._self, this._then);

  final RelayObservation _self;
  final $Res Function(RelayObservation) _then;

/// Create a copy of RelayObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? workBeadId = null,Object? startedAt = freezed,Object? deadline = null,Object? observedAt = null,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as DateTime,observedAt: null == observedAt ? _self.observedAt : observedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [RelayObservation].
extension RelayObservationPatterns on RelayObservation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RelayObservation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RelayObservation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RelayObservation value)  $default,){
final _that = this;
switch (_that) {
case _RelayObservation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RelayObservation value)?  $default,){
final _that = this;
switch (_that) {
case _RelayObservation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime deadline,  DateTime observedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RelayObservation() when $default != null:
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.deadline,_that.observedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime deadline,  DateTime observedAt)  $default,) {final _that = this;
switch (_that) {
case _RelayObservation():
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.deadline,_that.observedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime deadline,  DateTime observedAt)?  $default,) {final _that = this;
switch (_that) {
case _RelayObservation() when $default != null:
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.deadline,_that.observedAt);case _:
  return null;

}
}

}

/// @nodoc


class _RelayObservation implements RelayObservation {
  const _RelayObservation({required this.sessionId, required this.workBeadId, this.startedAt, required this.deadline, required this.observedAt});
  

@override final  String sessionId;
@override final  String workBeadId;
@override final  DateTime? startedAt;
@override final  DateTime deadline;
@override final  DateTime observedAt;

/// Create a copy of RelayObservation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RelayObservationCopyWith<_RelayObservation> get copyWith => __$RelayObservationCopyWithImpl<_RelayObservation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RelayObservation&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.observedAt, observedAt) || other.observedAt == observedAt));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,workBeadId,startedAt,deadline,observedAt);

@override
String toString() {
  return 'RelayObservation(sessionId: $sessionId, workBeadId: $workBeadId, startedAt: $startedAt, deadline: $deadline, observedAt: $observedAt)';
}


}

/// @nodoc
abstract mixin class _$RelayObservationCopyWith<$Res> implements $RelayObservationCopyWith<$Res> {
  factory _$RelayObservationCopyWith(_RelayObservation value, $Res Function(_RelayObservation) _then) = __$RelayObservationCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String workBeadId, DateTime? startedAt, DateTime deadline, DateTime observedAt
});




}
/// @nodoc
class __$RelayObservationCopyWithImpl<$Res>
    implements _$RelayObservationCopyWith<$Res> {
  __$RelayObservationCopyWithImpl(this._self, this._then);

  final _RelayObservation _self;
  final $Res Function(_RelayObservation) _then;

/// Create a copy of RelayObservation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? workBeadId = null,Object? startedAt = freezed,Object? deadline = null,Object? observedAt = null,}) {
  return _then(_RelayObservation(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as DateTime,observedAt: null == observedAt ? _self.observedAt : observedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$RelayVerdict {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayVerdict);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RelayVerdict()';
}


}

/// @nodoc
class $RelayVerdictCopyWith<$Res>  {
$RelayVerdictCopyWith(RelayVerdict _, $Res Function(RelayVerdict) __);
}


/// Adds pattern-matching-related methods to [RelayVerdict].
extension RelayVerdictPatterns on RelayVerdict {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RelayAbsorb value)?  absorb,TResult Function( RelayEscalate value)?  escalate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RelayAbsorb() when absorb != null:
return absorb(_that);case RelayEscalate() when escalate != null:
return escalate(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RelayAbsorb value)  absorb,required TResult Function( RelayEscalate value)  escalate,}){
final _that = this;
switch (_that) {
case RelayAbsorb():
return absorb(_that);case RelayEscalate():
return escalate(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RelayAbsorb value)?  absorb,TResult? Function( RelayEscalate value)?  escalate,}){
final _that = this;
switch (_that) {
case RelayAbsorb() when absorb != null:
return absorb(_that);case RelayEscalate() when escalate != null:
return escalate(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Duration nextHorizon)?  absorb,TResult Function( String reason)?  escalate,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RelayAbsorb() when absorb != null:
return absorb(_that.nextHorizon);case RelayEscalate() when escalate != null:
return escalate(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Duration nextHorizon)  absorb,required TResult Function( String reason)  escalate,}) {final _that = this;
switch (_that) {
case RelayAbsorb():
return absorb(_that.nextHorizon);case RelayEscalate():
return escalate(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Duration nextHorizon)?  absorb,TResult? Function( String reason)?  escalate,}) {final _that = this;
switch (_that) {
case RelayAbsorb() when absorb != null:
return absorb(_that.nextHorizon);case RelayEscalate() when escalate != null:
return escalate(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RelayAbsorb implements RelayVerdict {
  const RelayAbsorb({required this.nextHorizon});
  

 final  Duration nextHorizon;

/// Create a copy of RelayVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RelayAbsorbCopyWith<RelayAbsorb> get copyWith => _$RelayAbsorbCopyWithImpl<RelayAbsorb>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayAbsorb&&(identical(other.nextHorizon, nextHorizon) || other.nextHorizon == nextHorizon));
}


@override
int get hashCode => Object.hash(runtimeType,nextHorizon);

@override
String toString() {
  return 'RelayVerdict.absorb(nextHorizon: $nextHorizon)';
}


}

/// @nodoc
abstract mixin class $RelayAbsorbCopyWith<$Res> implements $RelayVerdictCopyWith<$Res> {
  factory $RelayAbsorbCopyWith(RelayAbsorb value, $Res Function(RelayAbsorb) _then) = _$RelayAbsorbCopyWithImpl;
@useResult
$Res call({
 Duration nextHorizon
});




}
/// @nodoc
class _$RelayAbsorbCopyWithImpl<$Res>
    implements $RelayAbsorbCopyWith<$Res> {
  _$RelayAbsorbCopyWithImpl(this._self, this._then);

  final RelayAbsorb _self;
  final $Res Function(RelayAbsorb) _then;

/// Create a copy of RelayVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nextHorizon = null,}) {
  return _then(RelayAbsorb(
nextHorizon: null == nextHorizon ? _self.nextHorizon : nextHorizon // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

/// @nodoc


class RelayEscalate implements RelayVerdict {
  const RelayEscalate({required this.reason});
  

 final  String reason;

/// Create a copy of RelayVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RelayEscalateCopyWith<RelayEscalate> get copyWith => _$RelayEscalateCopyWithImpl<RelayEscalate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RelayEscalate&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RelayVerdict.escalate(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RelayEscalateCopyWith<$Res> implements $RelayVerdictCopyWith<$Res> {
  factory $RelayEscalateCopyWith(RelayEscalate value, $Res Function(RelayEscalate) _then) = _$RelayEscalateCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RelayEscalateCopyWithImpl<$Res>
    implements $RelayEscalateCopyWith<$Res> {
  _$RelayEscalateCopyWithImpl(this._self, this._then);

  final RelayEscalate _self;
  final $Res Function(RelayEscalate) _then;

/// Create a copy of RelayVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RelayEscalate(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
