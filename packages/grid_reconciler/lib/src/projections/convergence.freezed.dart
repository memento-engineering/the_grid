// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'convergence.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Convergence {

 String get id; String get title; BeadStatus get status; ConvergenceMetadata get metadata;/// Wisps: children whose `metadata.idempotency_key` carries this loop's
/// prefix (`converge:{id}:iter:`), sorted by iteration (unparseable
/// iterations last), then id.
 List<Wisp> get wisps;/// Every parent-child child id (wisp or not), sorted — gc's
/// `Store.Children` surface for Track C recovery.
 List<String> get childIds;/// `idempotency_key` by child id, for **all** children carrying one
/// (prefix-matched or not) — the [findByIdempotencyKey] scan domain,
/// byte-faithful to gc's child scan (cmd/gc/convergence_store.go:264-266).
 Map<String, String> get childIdempotencyKeys; DateTime? get closedAt; String get closeReason;
/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConvergenceCopyWith<Convergence> get copyWith => _$ConvergenceCopyWithImpl<Convergence>(this as Convergence, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Convergence&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.wisps, wisps)&&const DeepCollectionEquality().equals(other.childIds, childIds)&&const DeepCollectionEquality().equals(other.childIdempotencyKeys, childIdempotencyKeys)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,metadata,const DeepCollectionEquality().hash(wisps),const DeepCollectionEquality().hash(childIds),const DeepCollectionEquality().hash(childIdempotencyKeys),closedAt,closeReason);

@override
String toString() {
  return 'Convergence(id: $id, title: $title, status: $status, metadata: $metadata, wisps: $wisps, childIds: $childIds, childIdempotencyKeys: $childIdempotencyKeys, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class $ConvergenceCopyWith<$Res>  {
  factory $ConvergenceCopyWith(Convergence value, $Res Function(Convergence) _then) = _$ConvergenceCopyWithImpl;
@useResult
$Res call({
 String id, String title, BeadStatus status, ConvergenceMetadata metadata, List<Wisp> wisps, List<String> childIds, Map<String, String> childIdempotencyKeys, DateTime? closedAt, String closeReason
});


$ConvergenceMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class _$ConvergenceCopyWithImpl<$Res>
    implements $ConvergenceCopyWith<$Res> {
  _$ConvergenceCopyWithImpl(this._self, this._then);

  final Convergence _self;
  final $Res Function(Convergence) _then;

/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? status = null,Object? metadata = null,Object? wisps = null,Object? childIds = null,Object? childIdempotencyKeys = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as ConvergenceMetadata,wisps: null == wisps ? _self.wisps : wisps // ignore: cast_nullable_to_non_nullable
as List<Wisp>,childIds: null == childIds ? _self.childIds : childIds // ignore: cast_nullable_to_non_nullable
as List<String>,childIdempotencyKeys: null == childIdempotencyKeys ? _self.childIdempotencyKeys : childIdempotencyKeys // ignore: cast_nullable_to_non_nullable
as Map<String, String>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConvergenceMetadataCopyWith<$Res> get metadata {
  
  return $ConvergenceMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [Convergence].
extension ConvergencePatterns on Convergence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Convergence value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Convergence() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Convergence value)  $default,){
final _that = this;
switch (_that) {
case _Convergence():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Convergence value)?  $default,){
final _that = this;
switch (_that) {
case _Convergence() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  BeadStatus status,  ConvergenceMetadata metadata,  List<Wisp> wisps,  List<String> childIds,  Map<String, String> childIdempotencyKeys,  DateTime? closedAt,  String closeReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Convergence() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.metadata,_that.wisps,_that.childIds,_that.childIdempotencyKeys,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  BeadStatus status,  ConvergenceMetadata metadata,  List<Wisp> wisps,  List<String> childIds,  Map<String, String> childIdempotencyKeys,  DateTime? closedAt,  String closeReason)  $default,) {final _that = this;
switch (_that) {
case _Convergence():
return $default(_that.id,_that.title,_that.status,_that.metadata,_that.wisps,_that.childIds,_that.childIdempotencyKeys,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  BeadStatus status,  ConvergenceMetadata metadata,  List<Wisp> wisps,  List<String> childIds,  Map<String, String> childIdempotencyKeys,  DateTime? closedAt,  String closeReason)?  $default,) {final _that = this;
switch (_that) {
case _Convergence() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.metadata,_that.wisps,_that.childIds,_that.childIdempotencyKeys,_that.closedAt,_that.closeReason);case _:
  return null;

}
}

}

/// @nodoc


class _Convergence extends Convergence {
  const _Convergence({required this.id, required this.title, required this.status, required this.metadata, final  List<Wisp> wisps = const <Wisp>[], final  List<String> childIds = const <String>[], final  Map<String, String> childIdempotencyKeys = const <String, String>{}, this.closedAt, this.closeReason = ''}): _wisps = wisps,_childIds = childIds,_childIdempotencyKeys = childIdempotencyKeys,super._();
  

@override final  String id;
@override final  String title;
@override final  BeadStatus status;
@override final  ConvergenceMetadata metadata;
/// Wisps: children whose `metadata.idempotency_key` carries this loop's
/// prefix (`converge:{id}:iter:`), sorted by iteration (unparseable
/// iterations last), then id.
 final  List<Wisp> _wisps;
/// Wisps: children whose `metadata.idempotency_key` carries this loop's
/// prefix (`converge:{id}:iter:`), sorted by iteration (unparseable
/// iterations last), then id.
@override@JsonKey() List<Wisp> get wisps {
  if (_wisps is EqualUnmodifiableListView) return _wisps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_wisps);
}

/// Every parent-child child id (wisp or not), sorted — gc's
/// `Store.Children` surface for Track C recovery.
 final  List<String> _childIds;
/// Every parent-child child id (wisp or not), sorted — gc's
/// `Store.Children` surface for Track C recovery.
@override@JsonKey() List<String> get childIds {
  if (_childIds is EqualUnmodifiableListView) return _childIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_childIds);
}

/// `idempotency_key` by child id, for **all** children carrying one
/// (prefix-matched or not) — the [findByIdempotencyKey] scan domain,
/// byte-faithful to gc's child scan (cmd/gc/convergence_store.go:264-266).
 final  Map<String, String> _childIdempotencyKeys;
/// `idempotency_key` by child id, for **all** children carrying one
/// (prefix-matched or not) — the [findByIdempotencyKey] scan domain,
/// byte-faithful to gc's child scan (cmd/gc/convergence_store.go:264-266).
@override@JsonKey() Map<String, String> get childIdempotencyKeys {
  if (_childIdempotencyKeys is EqualUnmodifiableMapView) return _childIdempotencyKeys;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_childIdempotencyKeys);
}

@override final  DateTime? closedAt;
@override@JsonKey() final  String closeReason;

/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConvergenceCopyWith<_Convergence> get copyWith => __$ConvergenceCopyWithImpl<_Convergence>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Convergence&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other._wisps, _wisps)&&const DeepCollectionEquality().equals(other._childIds, _childIds)&&const DeepCollectionEquality().equals(other._childIdempotencyKeys, _childIdempotencyKeys)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,metadata,const DeepCollectionEquality().hash(_wisps),const DeepCollectionEquality().hash(_childIds),const DeepCollectionEquality().hash(_childIdempotencyKeys),closedAt,closeReason);

@override
String toString() {
  return 'Convergence(id: $id, title: $title, status: $status, metadata: $metadata, wisps: $wisps, childIds: $childIds, childIdempotencyKeys: $childIdempotencyKeys, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class _$ConvergenceCopyWith<$Res> implements $ConvergenceCopyWith<$Res> {
  factory _$ConvergenceCopyWith(_Convergence value, $Res Function(_Convergence) _then) = __$ConvergenceCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, BeadStatus status, ConvergenceMetadata metadata, List<Wisp> wisps, List<String> childIds, Map<String, String> childIdempotencyKeys, DateTime? closedAt, String closeReason
});


@override $ConvergenceMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class __$ConvergenceCopyWithImpl<$Res>
    implements _$ConvergenceCopyWith<$Res> {
  __$ConvergenceCopyWithImpl(this._self, this._then);

  final _Convergence _self;
  final $Res Function(_Convergence) _then;

/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? status = null,Object? metadata = null,Object? wisps = null,Object? childIds = null,Object? childIdempotencyKeys = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_Convergence(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as ConvergenceMetadata,wisps: null == wisps ? _self._wisps : wisps // ignore: cast_nullable_to_non_nullable
as List<Wisp>,childIds: null == childIds ? _self._childIds : childIds // ignore: cast_nullable_to_non_nullable
as List<String>,childIdempotencyKeys: null == childIdempotencyKeys ? _self._childIdempotencyKeys : childIdempotencyKeys // ignore: cast_nullable_to_non_nullable
as Map<String, String>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of Convergence
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConvergenceMetadataCopyWith<$Res> get metadata {
  
  return $ConvergenceMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

// dart format on
