// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bead_comment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BeadComment {

 String get id;@JsonKey(name: 'issue_id') String get issueId; String get author; String get text;@JsonKey(name: 'created_at') DateTime? get createdAt;
/// Create a copy of BeadComment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadCommentCopyWith<BeadComment> get copyWith => _$BeadCommentCopyWithImpl<BeadComment>(this as BeadComment, _$identity);

  /// Serializes this BeadComment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadComment&&(identical(other.id, id) || other.id == id)&&(identical(other.issueId, issueId) || other.issueId == issueId)&&(identical(other.author, author) || other.author == author)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,issueId,author,text,createdAt);

@override
String toString() {
  return 'BeadComment(id: $id, issueId: $issueId, author: $author, text: $text, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $BeadCommentCopyWith<$Res>  {
  factory $BeadCommentCopyWith(BeadComment value, $Res Function(BeadComment) _then) = _$BeadCommentCopyWithImpl;
@useResult
$Res call({
 String id,@JsonKey(name: 'issue_id') String issueId, String author, String text,@JsonKey(name: 'created_at') DateTime? createdAt
});




}
/// @nodoc
class _$BeadCommentCopyWithImpl<$Res>
    implements $BeadCommentCopyWith<$Res> {
  _$BeadCommentCopyWithImpl(this._self, this._then);

  final BeadComment _self;
  final $Res Function(BeadComment) _then;

/// Create a copy of BeadComment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? issueId = null,Object? author = null,Object? text = null,Object? createdAt = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,issueId: null == issueId ? _self.issueId : issueId // ignore: cast_nullable_to_non_nullable
as String,author: null == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [BeadComment].
extension BeadCommentPatterns on BeadComment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BeadComment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BeadComment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BeadComment value)  $default,){
final _that = this;
switch (_that) {
case _BeadComment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BeadComment value)?  $default,){
final _that = this;
switch (_that) {
case _BeadComment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'issue_id')  String issueId,  String author,  String text, @JsonKey(name: 'created_at')  DateTime? createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BeadComment() when $default != null:
return $default(_that.id,_that.issueId,_that.author,_that.text,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id, @JsonKey(name: 'issue_id')  String issueId,  String author,  String text, @JsonKey(name: 'created_at')  DateTime? createdAt)  $default,) {final _that = this;
switch (_that) {
case _BeadComment():
return $default(_that.id,_that.issueId,_that.author,_that.text,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id, @JsonKey(name: 'issue_id')  String issueId,  String author,  String text, @JsonKey(name: 'created_at')  DateTime? createdAt)?  $default,) {final _that = this;
switch (_that) {
case _BeadComment() when $default != null:
return $default(_that.id,_that.issueId,_that.author,_that.text,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _BeadComment implements BeadComment {
  const _BeadComment({required this.id, @JsonKey(name: 'issue_id') this.issueId = '', this.author = '', this.text = '', @JsonKey(name: 'created_at') this.createdAt});
  factory _BeadComment.fromJson(Map<String, dynamic> json) => _$BeadCommentFromJson(json);

@override final  String id;
@override@JsonKey(name: 'issue_id') final  String issueId;
@override@JsonKey() final  String author;
@override@JsonKey() final  String text;
@override@JsonKey(name: 'created_at') final  DateTime? createdAt;

/// Create a copy of BeadComment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BeadCommentCopyWith<_BeadComment> get copyWith => __$BeadCommentCopyWithImpl<_BeadComment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BeadCommentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BeadComment&&(identical(other.id, id) || other.id == id)&&(identical(other.issueId, issueId) || other.issueId == issueId)&&(identical(other.author, author) || other.author == author)&&(identical(other.text, text) || other.text == text)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,issueId,author,text,createdAt);

@override
String toString() {
  return 'BeadComment(id: $id, issueId: $issueId, author: $author, text: $text, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$BeadCommentCopyWith<$Res> implements $BeadCommentCopyWith<$Res> {
  factory _$BeadCommentCopyWith(_BeadComment value, $Res Function(_BeadComment) _then) = __$BeadCommentCopyWithImpl;
@override @useResult
$Res call({
 String id,@JsonKey(name: 'issue_id') String issueId, String author, String text,@JsonKey(name: 'created_at') DateTime? createdAt
});




}
/// @nodoc
class __$BeadCommentCopyWithImpl<$Res>
    implements _$BeadCommentCopyWith<$Res> {
  __$BeadCommentCopyWithImpl(this._self, this._then);

  final _BeadComment _self;
  final $Res Function(_BeadComment) _then;

/// Create a copy of BeadComment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? issueId = null,Object? author = null,Object? text = null,Object? createdAt = freezed,}) {
  return _then(_BeadComment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,issueId: null == issueId ? _self.issueId : issueId // ignore: cast_nullable_to_non_nullable
as String,author: null == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
