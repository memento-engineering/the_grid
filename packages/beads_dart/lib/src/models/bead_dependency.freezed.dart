// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bead_dependency.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BeadDependency {

@JsonKey(name: 'issue_id') String get issueId;@JsonKey(name: 'depends_on_id') String get dependsOnId;@DependencyTypeConverter() DependencyType get type;@JsonKey(name: 'created_at') DateTime? get createdAt;@JsonKey(name: 'created_by') String get createdBy; String get metadata;@JsonKey(name: 'thread_id') String get threadId;
/// Create a copy of BeadDependency
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadDependencyCopyWith<BeadDependency> get copyWith => _$BeadDependencyCopyWithImpl<BeadDependency>(this as BeadDependency, _$identity);

  /// Serializes this BeadDependency to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadDependency&&(identical(other.issueId, issueId) || other.issueId == issueId)&&(identical(other.dependsOnId, dependsOnId) || other.dependsOnId == dependsOnId)&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&(identical(other.threadId, threadId) || other.threadId == threadId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,issueId,dependsOnId,type,createdAt,createdBy,metadata,threadId);

@override
String toString() {
  return 'BeadDependency(issueId: $issueId, dependsOnId: $dependsOnId, type: $type, createdAt: $createdAt, createdBy: $createdBy, metadata: $metadata, threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class $BeadDependencyCopyWith<$Res>  {
  factory $BeadDependencyCopyWith(BeadDependency value, $Res Function(BeadDependency) _then) = _$BeadDependencyCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'issue_id') String issueId,@JsonKey(name: 'depends_on_id') String dependsOnId,@DependencyTypeConverter() DependencyType type,@JsonKey(name: 'created_at') DateTime? createdAt,@JsonKey(name: 'created_by') String createdBy, String metadata,@JsonKey(name: 'thread_id') String threadId
});




}
/// @nodoc
class _$BeadDependencyCopyWithImpl<$Res>
    implements $BeadDependencyCopyWith<$Res> {
  _$BeadDependencyCopyWithImpl(this._self, this._then);

  final BeadDependency _self;
  final $Res Function(BeadDependency) _then;

/// Create a copy of BeadDependency
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? issueId = null,Object? dependsOnId = null,Object? type = null,Object? createdAt = freezed,Object? createdBy = null,Object? metadata = null,Object? threadId = null,}) {
  return _then(_self.copyWith(
issueId: null == issueId ? _self.issueId : issueId // ignore: cast_nullable_to_non_nullable
as String,dependsOnId: null == dependsOnId ? _self.dependsOnId : dependsOnId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as DependencyType,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BeadDependency].
extension BeadDependencyPatterns on BeadDependency {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BeadDependency value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BeadDependency() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BeadDependency value)  $default,){
final _that = this;
switch (_that) {
case _BeadDependency():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BeadDependency value)?  $default,){
final _that = this;
switch (_that) {
case _BeadDependency() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'issue_id')  String issueId, @JsonKey(name: 'depends_on_id')  String dependsOnId, @DependencyTypeConverter()  DependencyType type, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy,  String metadata, @JsonKey(name: 'thread_id')  String threadId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BeadDependency() when $default != null:
return $default(_that.issueId,_that.dependsOnId,_that.type,_that.createdAt,_that.createdBy,_that.metadata,_that.threadId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'issue_id')  String issueId, @JsonKey(name: 'depends_on_id')  String dependsOnId, @DependencyTypeConverter()  DependencyType type, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy,  String metadata, @JsonKey(name: 'thread_id')  String threadId)  $default,) {final _that = this;
switch (_that) {
case _BeadDependency():
return $default(_that.issueId,_that.dependsOnId,_that.type,_that.createdAt,_that.createdBy,_that.metadata,_that.threadId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'issue_id')  String issueId, @JsonKey(name: 'depends_on_id')  String dependsOnId, @DependencyTypeConverter()  DependencyType type, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy,  String metadata, @JsonKey(name: 'thread_id')  String threadId)?  $default,) {final _that = this;
switch (_that) {
case _BeadDependency() when $default != null:
return $default(_that.issueId,_that.dependsOnId,_that.type,_that.createdAt,_that.createdBy,_that.metadata,_that.threadId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BeadDependency extends BeadDependency {
  const _BeadDependency({@JsonKey(name: 'issue_id') required this.issueId, @JsonKey(name: 'depends_on_id') required this.dependsOnId, @DependencyTypeConverter() this.type = DependencyType.blocks, @JsonKey(name: 'created_at') this.createdAt, @JsonKey(name: 'created_by') this.createdBy = '', this.metadata = '', @JsonKey(name: 'thread_id') this.threadId = ''}): super._();
  factory _BeadDependency.fromJson(Map<String, dynamic> json) => _$BeadDependencyFromJson(json);

@override@JsonKey(name: 'issue_id') final  String issueId;
@override@JsonKey(name: 'depends_on_id') final  String dependsOnId;
@override@JsonKey()@DependencyTypeConverter() final  DependencyType type;
@override@JsonKey(name: 'created_at') final  DateTime? createdAt;
@override@JsonKey(name: 'created_by') final  String createdBy;
@override@JsonKey() final  String metadata;
@override@JsonKey(name: 'thread_id') final  String threadId;

/// Create a copy of BeadDependency
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BeadDependencyCopyWith<_BeadDependency> get copyWith => __$BeadDependencyCopyWithImpl<_BeadDependency>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BeadDependencyToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BeadDependency&&(identical(other.issueId, issueId) || other.issueId == issueId)&&(identical(other.dependsOnId, dependsOnId) || other.dependsOnId == dependsOnId)&&(identical(other.type, type) || other.type == type)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&(identical(other.threadId, threadId) || other.threadId == threadId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,issueId,dependsOnId,type,createdAt,createdBy,metadata,threadId);

@override
String toString() {
  return 'BeadDependency(issueId: $issueId, dependsOnId: $dependsOnId, type: $type, createdAt: $createdAt, createdBy: $createdBy, metadata: $metadata, threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class _$BeadDependencyCopyWith<$Res> implements $BeadDependencyCopyWith<$Res> {
  factory _$BeadDependencyCopyWith(_BeadDependency value, $Res Function(_BeadDependency) _then) = __$BeadDependencyCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'issue_id') String issueId,@JsonKey(name: 'depends_on_id') String dependsOnId,@DependencyTypeConverter() DependencyType type,@JsonKey(name: 'created_at') DateTime? createdAt,@JsonKey(name: 'created_by') String createdBy, String metadata,@JsonKey(name: 'thread_id') String threadId
});




}
/// @nodoc
class __$BeadDependencyCopyWithImpl<$Res>
    implements _$BeadDependencyCopyWith<$Res> {
  __$BeadDependencyCopyWithImpl(this._self, this._then);

  final _BeadDependency _self;
  final $Res Function(_BeadDependency) _then;

/// Create a copy of BeadDependency
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? issueId = null,Object? dependsOnId = null,Object? type = null,Object? createdAt = freezed,Object? createdBy = null,Object? metadata = null,Object? threadId = null,}) {
  return _then(_BeadDependency(
issueId: null == issueId ? _self.issueId : issueId // ignore: cast_nullable_to_non_nullable
as String,dependsOnId: null == dependsOnId ? _self.dependsOnId : dependsOnId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as DependencyType,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
