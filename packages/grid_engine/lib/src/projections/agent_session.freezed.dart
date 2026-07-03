// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionMetadata {

 Map<String, dynamic> get raw;
/// Create a copy of SessionMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionMetadataCopyWith<SessionMetadata> get copyWith => _$SessionMetadataCopyWithImpl<SessionMetadata>(this as SessionMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionMetadata&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'SessionMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $SessionMetadataCopyWith<$Res>  {
  factory $SessionMetadataCopyWith(SessionMetadata value, $Res Function(SessionMetadata) _then) = _$SessionMetadataCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$SessionMetadataCopyWithImpl<$Res>
    implements $SessionMetadataCopyWith<$Res> {
  _$SessionMetadataCopyWithImpl(this._self, this._then);

  final SessionMetadata _self;
  final $Res Function(SessionMetadata) _then;

/// Create a copy of SessionMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionMetadata].
extension SessionMetadataPatterns on SessionMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionMetadata value)  $default,){
final _that = this;
switch (_that) {
case _SessionMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _SessionMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionMetadata() when $default != null:
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _SessionMetadata():
return $default(_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _SessionMetadata() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _SessionMetadata extends SessionMetadata {
  const _SessionMetadata({final  Map<String, dynamic> raw = const <String, dynamic>{}}): _raw = raw,super._();
  

 final  Map<String, dynamic> _raw;
@override@JsonKey() Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of SessionMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionMetadataCopyWith<_SessionMetadata> get copyWith => __$SessionMetadataCopyWithImpl<_SessionMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionMetadata&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'SessionMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$SessionMetadataCopyWith<$Res> implements $SessionMetadataCopyWith<$Res> {
  factory _$SessionMetadataCopyWith(_SessionMetadata value, $Res Function(_SessionMetadata) _then) = __$SessionMetadataCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$SessionMetadataCopyWithImpl<$Res>
    implements _$SessionMetadataCopyWith<$Res> {
  __$SessionMetadataCopyWithImpl(this._self, this._then);

  final _SessionMetadata _self;
  final $Res Function(_SessionMetadata) _then;

/// Create a copy of SessionMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_SessionMetadata(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$AgentSession {

 String get id; String get title; SessionState get state; SessionMetadata get metadata; List<String> get labels; DateTime? get closedAt; String get closeReason;
/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentSessionCopyWith<AgentSession> get copyWith => _$AgentSessionCopyWithImpl<AgentSession>(this as AgentSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.state, state) || other.state == state)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.labels, labels)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,state,metadata,const DeepCollectionEquality().hash(labels),closedAt,closeReason);

@override
String toString() {
  return 'AgentSession(id: $id, title: $title, state: $state, metadata: $metadata, labels: $labels, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class $AgentSessionCopyWith<$Res>  {
  factory $AgentSessionCopyWith(AgentSession value, $Res Function(AgentSession) _then) = _$AgentSessionCopyWithImpl;
@useResult
$Res call({
 String id, String title, SessionState state, SessionMetadata metadata, List<String> labels, DateTime? closedAt, String closeReason
});


$SessionMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class _$AgentSessionCopyWithImpl<$Res>
    implements $AgentSessionCopyWith<$Res> {
  _$AgentSessionCopyWithImpl(this._self, this._then);

  final AgentSession _self;
  final $Res Function(AgentSession) _then;

/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? state = null,Object? metadata = null,Object? labels = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SessionState,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as SessionMetadata,labels: null == labels ? _self.labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionMetadataCopyWith<$Res> get metadata {
  
  return $SessionMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentSession].
extension AgentSessionPatterns on AgentSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentSession value)  $default,){
final _that = this;
switch (_that) {
case _AgentSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentSession value)?  $default,){
final _that = this;
switch (_that) {
case _AgentSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  SessionState state,  SessionMetadata metadata,  List<String> labels,  DateTime? closedAt,  String closeReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentSession() when $default != null:
return $default(_that.id,_that.title,_that.state,_that.metadata,_that.labels,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  SessionState state,  SessionMetadata metadata,  List<String> labels,  DateTime? closedAt,  String closeReason)  $default,) {final _that = this;
switch (_that) {
case _AgentSession():
return $default(_that.id,_that.title,_that.state,_that.metadata,_that.labels,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  SessionState state,  SessionMetadata metadata,  List<String> labels,  DateTime? closedAt,  String closeReason)?  $default,) {final _that = this;
switch (_that) {
case _AgentSession() when $default != null:
return $default(_that.id,_that.title,_that.state,_that.metadata,_that.labels,_that.closedAt,_that.closeReason);case _:
  return null;

}
}

}

/// @nodoc


class _AgentSession extends AgentSession {
  const _AgentSession({required this.id, required this.title, required this.state, required this.metadata, required final  List<String> labels, this.closedAt, this.closeReason = ''}): _labels = labels,super._();
  

@override final  String id;
@override final  String title;
@override final  SessionState state;
@override final  SessionMetadata metadata;
 final  List<String> _labels;
@override List<String> get labels {
  if (_labels is EqualUnmodifiableListView) return _labels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_labels);
}

@override final  DateTime? closedAt;
@override@JsonKey() final  String closeReason;

/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentSessionCopyWith<_AgentSession> get copyWith => __$AgentSessionCopyWithImpl<_AgentSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentSession&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.state, state) || other.state == state)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other._labels, _labels)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,state,metadata,const DeepCollectionEquality().hash(_labels),closedAt,closeReason);

@override
String toString() {
  return 'AgentSession(id: $id, title: $title, state: $state, metadata: $metadata, labels: $labels, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class _$AgentSessionCopyWith<$Res> implements $AgentSessionCopyWith<$Res> {
  factory _$AgentSessionCopyWith(_AgentSession value, $Res Function(_AgentSession) _then) = __$AgentSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, SessionState state, SessionMetadata metadata, List<String> labels, DateTime? closedAt, String closeReason
});


@override $SessionMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class __$AgentSessionCopyWithImpl<$Res>
    implements _$AgentSessionCopyWith<$Res> {
  __$AgentSessionCopyWithImpl(this._self, this._then);

  final _AgentSession _self;
  final $Res Function(_AgentSession) _then;

/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? state = null,Object? metadata = null,Object? labels = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_AgentSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as SessionState,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as SessionMetadata,labels: null == labels ? _self._labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of AgentSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionMetadataCopyWith<$Res> get metadata {
  
  return $SessionMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

// dart format on
