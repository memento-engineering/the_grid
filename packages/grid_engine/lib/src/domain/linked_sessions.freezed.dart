// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'linked_sessions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkedSessionVerdict {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkedSessionVerdict);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LinkedSessionVerdict()';
}


}

/// @nodoc
class $LinkedSessionVerdictCopyWith<$Res>  {
$LinkedSessionVerdictCopyWith(LinkedSessionVerdict _, $Res Function(LinkedSessionVerdict) __);
}


/// Adds pattern-matching-related methods to [LinkedSessionVerdict].
extension LinkedSessionVerdictPatterns on LinkedSessionVerdict {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NoLinkedSession value)?  none,TResult Function( AdoptLinkedSession value)?  adopt,TResult Function( BlockedLinkedSession value)?  blocked,TResult Function( RemintLinkedSession value)?  remint,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NoLinkedSession() when none != null:
return none(_that);case AdoptLinkedSession() when adopt != null:
return adopt(_that);case BlockedLinkedSession() when blocked != null:
return blocked(_that);case RemintLinkedSession() when remint != null:
return remint(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NoLinkedSession value)  none,required TResult Function( AdoptLinkedSession value)  adopt,required TResult Function( BlockedLinkedSession value)  blocked,required TResult Function( RemintLinkedSession value)  remint,}){
final _that = this;
switch (_that) {
case NoLinkedSession():
return none(_that);case AdoptLinkedSession():
return adopt(_that);case BlockedLinkedSession():
return blocked(_that);case RemintLinkedSession():
return remint(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NoLinkedSession value)?  none,TResult? Function( AdoptLinkedSession value)?  adopt,TResult? Function( BlockedLinkedSession value)?  blocked,TResult? Function( RemintLinkedSession value)?  remint,}){
final _that = this;
switch (_that) {
case NoLinkedSession() when none != null:
return none(_that);case AdoptLinkedSession() when adopt != null:
return adopt(_that);case BlockedLinkedSession() when blocked != null:
return blocked(_that);case RemintLinkedSession() when remint != null:
return remint(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  none,TResult Function( SessionProjection session,  List<SessionProjection> rivals)?  adopt,TResult Function( SessionProjection session)?  blocked,TResult Function( SessionProjection session,  List<SessionProjection> surplus)?  remint,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NoLinkedSession() when none != null:
return none();case AdoptLinkedSession() when adopt != null:
return adopt(_that.session,_that.rivals);case BlockedLinkedSession() when blocked != null:
return blocked(_that.session);case RemintLinkedSession() when remint != null:
return remint(_that.session,_that.surplus);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  none,required TResult Function( SessionProjection session,  List<SessionProjection> rivals)  adopt,required TResult Function( SessionProjection session)  blocked,required TResult Function( SessionProjection session,  List<SessionProjection> surplus)  remint,}) {final _that = this;
switch (_that) {
case NoLinkedSession():
return none();case AdoptLinkedSession():
return adopt(_that.session,_that.rivals);case BlockedLinkedSession():
return blocked(_that.session);case RemintLinkedSession():
return remint(_that.session,_that.surplus);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  none,TResult? Function( SessionProjection session,  List<SessionProjection> rivals)?  adopt,TResult? Function( SessionProjection session)?  blocked,TResult? Function( SessionProjection session,  List<SessionProjection> surplus)?  remint,}) {final _that = this;
switch (_that) {
case NoLinkedSession() when none != null:
return none();case AdoptLinkedSession() when adopt != null:
return adopt(_that.session,_that.rivals);case BlockedLinkedSession() when blocked != null:
return blocked(_that.session);case RemintLinkedSession() when remint != null:
return remint(_that.session,_that.surplus);case _:
  return null;

}
}

}

/// @nodoc


class NoLinkedSession extends LinkedSessionVerdict {
  const NoLinkedSession(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoLinkedSession);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LinkedSessionVerdict.none()';
}


}




/// @nodoc


class AdoptLinkedSession extends LinkedSessionVerdict {
  const AdoptLinkedSession({required this.session, required final  List<SessionProjection> rivals}): _rivals = rivals,super._();


 final  SessionProjection session;
 final  List<SessionProjection> _rivals;
 List<SessionProjection> get rivals {
  if (_rivals is EqualUnmodifiableListView) return _rivals;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rivals);
}


/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AdoptLinkedSessionCopyWith<AdoptLinkedSession> get copyWith => _$AdoptLinkedSessionCopyWithImpl<AdoptLinkedSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AdoptLinkedSession&&(identical(other.session, session) || other.session == session)&&const DeepCollectionEquality().equals(other._rivals, _rivals));
}


@override
int get hashCode => Object.hash(runtimeType,session,const DeepCollectionEquality().hash(_rivals));

@override
String toString() {
  return 'LinkedSessionVerdict.adopt(session: $session, rivals: $rivals)';
}


}

/// @nodoc
abstract mixin class $AdoptLinkedSessionCopyWith<$Res> implements $LinkedSessionVerdictCopyWith<$Res> {
  factory $AdoptLinkedSessionCopyWith(AdoptLinkedSession value, $Res Function(AdoptLinkedSession) _then) = _$AdoptLinkedSessionCopyWithImpl;
@useResult
$Res call({
 SessionProjection session, List<SessionProjection> rivals
});


$SessionProjectionCopyWith<$Res> get session;

}
/// @nodoc
class _$AdoptLinkedSessionCopyWithImpl<$Res>
    implements $AdoptLinkedSessionCopyWith<$Res> {
  _$AdoptLinkedSessionCopyWithImpl(this._self, this._then);

  final AdoptLinkedSession _self;
  final $Res Function(AdoptLinkedSession) _then;

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? session = null,Object? rivals = null,}) {
  return _then(AdoptLinkedSession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionProjection,rivals: null == rivals ? _self._rivals : rivals // ignore: cast_nullable_to_non_nullable
as List<SessionProjection>,
  ));
}

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<$Res> get session {

  return $SessionProjectionCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}

/// @nodoc


class BlockedLinkedSession extends LinkedSessionVerdict {
  const BlockedLinkedSession({required this.session}): super._();


 final  SessionProjection session;

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockedLinkedSessionCopyWith<BlockedLinkedSession> get copyWith => _$BlockedLinkedSessionCopyWithImpl<BlockedLinkedSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockedLinkedSession&&(identical(other.session, session) || other.session == session));
}


@override
int get hashCode => Object.hash(runtimeType,session);

@override
String toString() {
  return 'LinkedSessionVerdict.blocked(session: $session)';
}


}

/// @nodoc
abstract mixin class $BlockedLinkedSessionCopyWith<$Res> implements $LinkedSessionVerdictCopyWith<$Res> {
  factory $BlockedLinkedSessionCopyWith(BlockedLinkedSession value, $Res Function(BlockedLinkedSession) _then) = _$BlockedLinkedSessionCopyWithImpl;
@useResult
$Res call({
 SessionProjection session
});


$SessionProjectionCopyWith<$Res> get session;

}
/// @nodoc
class _$BlockedLinkedSessionCopyWithImpl<$Res>
    implements $BlockedLinkedSessionCopyWith<$Res> {
  _$BlockedLinkedSessionCopyWithImpl(this._self, this._then);

  final BlockedLinkedSession _self;
  final $Res Function(BlockedLinkedSession) _then;

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? session = null,}) {
  return _then(BlockedLinkedSession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionProjection,
  ));
}

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<$Res> get session {

  return $SessionProjectionCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}

/// @nodoc


class RemintLinkedSession extends LinkedSessionVerdict {
  const RemintLinkedSession({required this.session, required final  List<SessionProjection> surplus}): _surplus = surplus,super._();


 final  SessionProjection session;
 final  List<SessionProjection> _surplus;
 List<SessionProjection> get surplus {
  if (_surplus is EqualUnmodifiableListView) return _surplus;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_surplus);
}


/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemintLinkedSessionCopyWith<RemintLinkedSession> get copyWith => _$RemintLinkedSessionCopyWithImpl<RemintLinkedSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemintLinkedSession&&(identical(other.session, session) || other.session == session)&&const DeepCollectionEquality().equals(other._surplus, _surplus));
}


@override
int get hashCode => Object.hash(runtimeType,session,const DeepCollectionEquality().hash(_surplus));

@override
String toString() {
  return 'LinkedSessionVerdict.remint(session: $session, surplus: $surplus)';
}


}

/// @nodoc
abstract mixin class $RemintLinkedSessionCopyWith<$Res> implements $LinkedSessionVerdictCopyWith<$Res> {
  factory $RemintLinkedSessionCopyWith(RemintLinkedSession value, $Res Function(RemintLinkedSession) _then) = _$RemintLinkedSessionCopyWithImpl;
@useResult
$Res call({
 SessionProjection session, List<SessionProjection> surplus
});


$SessionProjectionCopyWith<$Res> get session;

}
/// @nodoc
class _$RemintLinkedSessionCopyWithImpl<$Res>
    implements $RemintLinkedSessionCopyWith<$Res> {
  _$RemintLinkedSessionCopyWithImpl(this._self, this._then);

  final RemintLinkedSession _self;
  final $Res Function(RemintLinkedSession) _then;

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? session = null,Object? surplus = null,}) {
  return _then(RemintLinkedSession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as SessionProjection,surplus: null == surplus ? _self._surplus : surplus // ignore: cast_nullable_to_non_nullable
as List<SessionProjection>,
  ));
}

/// Create a copy of LinkedSessionVerdict
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionProjectionCopyWith<$Res> get session {

  return $SessionProjectionCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}

// dart format on
