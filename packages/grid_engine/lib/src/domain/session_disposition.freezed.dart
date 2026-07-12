// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_disposition.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionDisposition {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionDisposition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionDisposition()';
}


}

/// @nodoc
class $SessionDispositionCopyWith<$Res>  {
$SessionDispositionCopyWith(SessionDisposition _, $Res Function(SessionDisposition) __);
}


/// Adds pattern-matching-related methods to [SessionDisposition].
extension SessionDispositionPatterns on SessionDisposition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NoSession value)?  none,TResult Function( LiveSession value)?  live,TResult Function( DoneSession value)?  done,TResult Function( HeldSession value)?  held,TResult Function( VoidedSession value)?  voided,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NoSession() when none != null:
return none(_that);case LiveSession() when live != null:
return live(_that);case DoneSession() when done != null:
return done(_that);case HeldSession() when held != null:
return held(_that);case VoidedSession() when voided != null:
return voided(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NoSession value)  none,required TResult Function( LiveSession value)  live,required TResult Function( DoneSession value)  done,required TResult Function( HeldSession value)  held,required TResult Function( VoidedSession value)  voided,}){
final _that = this;
switch (_that) {
case NoSession():
return none(_that);case LiveSession():
return live(_that);case DoneSession():
return done(_that);case HeldSession():
return held(_that);case VoidedSession():
return voided(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NoSession value)?  none,TResult? Function( LiveSession value)?  live,TResult? Function( DoneSession value)?  done,TResult? Function( HeldSession value)?  held,TResult? Function( VoidedSession value)?  voided,}){
final _that = this;
switch (_that) {
case NoSession() when none != null:
return none(_that);case LiveSession() when live != null:
return live(_that);case DoneSession() when done != null:
return done(_that);case HeldSession() when held != null:
return held(_that);case VoidedSession() when voided != null:
return voided(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function()?  live,TResult Function()?  done,TResult Function( String reason)?  held,TResult Function( String reason)?  voided,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NoSession() when none != null:
return none();case LiveSession() when live != null:
return live();case DoneSession() when done != null:
return done();case HeldSession() when held != null:
return held(_that.reason);case VoidedSession() when voided != null:
return voided(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function()  live,required TResult Function()  done,required TResult Function( String reason)  held,required TResult Function( String reason)  voided,}) {final _that = this;
switch (_that) {
case NoSession():
return none();case LiveSession():
return live();case DoneSession():
return done();case HeldSession():
return held(_that.reason);case VoidedSession():
return voided(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function()?  live,TResult? Function()?  done,TResult? Function( String reason)?  held,TResult? Function( String reason)?  voided,}) {final _that = this;
switch (_that) {
case NoSession() when none != null:
return none();case LiveSession() when live != null:
return live();case DoneSession() when done != null:
return done();case HeldSession() when held != null:
return held(_that.reason);case VoidedSession() when voided != null:
return voided(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class NoSession extends SessionDisposition {
  const NoSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionDisposition.none()';
}


}




/// @nodoc


class LiveSession extends SessionDisposition {
  const LiveSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionDisposition.live()';
}


}




/// @nodoc


class DoneSession extends SessionDisposition {
  const DoneSession(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DoneSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SessionDisposition.done()';
}


}




/// @nodoc


class HeldSession extends SessionDisposition {
  const HeldSession({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SessionDisposition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HeldSessionCopyWith<HeldSession> get copyWith => _$HeldSessionCopyWithImpl<HeldSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HeldSession&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SessionDisposition.held(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $HeldSessionCopyWith<$Res> implements $SessionDispositionCopyWith<$Res> {
  factory $HeldSessionCopyWith(HeldSession value, $Res Function(HeldSession) _then) = _$HeldSessionCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$HeldSessionCopyWithImpl<$Res>
    implements $HeldSessionCopyWith<$Res> {
  _$HeldSessionCopyWithImpl(this._self, this._then);

  final HeldSession _self;
  final $Res Function(HeldSession) _then;

/// Create a copy of SessionDisposition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(HeldSession(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class VoidedSession extends SessionDisposition {
  const VoidedSession({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SessionDisposition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VoidedSessionCopyWith<VoidedSession> get copyWith => _$VoidedSessionCopyWithImpl<VoidedSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VoidedSession&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SessionDisposition.voided(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $VoidedSessionCopyWith<$Res> implements $SessionDispositionCopyWith<$Res> {
  factory $VoidedSessionCopyWith(VoidedSession value, $Res Function(VoidedSession) _then) = _$VoidedSessionCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$VoidedSessionCopyWithImpl<$Res>
    implements $VoidedSessionCopyWith<$Res> {
  _$VoidedSessionCopyWithImpl(this._self, this._then);

  final VoidedSession _self;
  final $Res Function(VoidedSession) _then;

/// Create a copy of SessionDisposition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(VoidedSession(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
