// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'step.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StepMetadata {

 Map<String, dynamic> get raw;
/// Create a copy of StepMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepMetadataCopyWith<StepMetadata> get copyWith => _$StepMetadataCopyWithImpl<StepMetadata>(this as StepMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StepMetadata&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'StepMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $StepMetadataCopyWith<$Res>  {
  factory $StepMetadataCopyWith(StepMetadata value, $Res Function(StepMetadata) _then) = _$StepMetadataCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$StepMetadataCopyWithImpl<$Res>
    implements $StepMetadataCopyWith<$Res> {
  _$StepMetadataCopyWithImpl(this._self, this._then);

  final StepMetadata _self;
  final $Res Function(StepMetadata) _then;

/// Create a copy of StepMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [StepMetadata].
extension StepMetadataPatterns on StepMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StepMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StepMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StepMetadata value)  $default,){
final _that = this;
switch (_that) {
case _StepMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StepMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _StepMetadata() when $default != null:
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
case _StepMetadata() when $default != null:
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
case _StepMetadata():
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
case _StepMetadata() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _StepMetadata extends StepMetadata {
  const _StepMetadata({final  Map<String, dynamic> raw = const <String, dynamic>{}}): _raw = raw,super._();
  

 final  Map<String, dynamic> _raw;
@override@JsonKey() Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of StepMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepMetadataCopyWith<_StepMetadata> get copyWith => __$StepMetadataCopyWithImpl<_StepMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StepMetadata&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'StepMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$StepMetadataCopyWith<$Res> implements $StepMetadataCopyWith<$Res> {
  factory _$StepMetadataCopyWith(_StepMetadata value, $Res Function(_StepMetadata) _then) = __$StepMetadataCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$StepMetadataCopyWithImpl<$Res>
    implements _$StepMetadataCopyWith<$Res> {
  __$StepMetadataCopyWithImpl(this._self, this._then);

  final _StepMetadata _self;
  final $Res Function(_StepMetadata) _then;

/// Create a copy of StepMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_StepMetadata(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$Step {

 String get id; String get title; bool get isClosed; StepMetadata get metadata; List<String> get labels; List<String> get needs;
/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StepCopyWith<Step> get copyWith => _$StepCopyWithImpl<Step>(this as Step, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Step&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.labels, labels)&&const DeepCollectionEquality().equals(other.needs, needs));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,isClosed,metadata,const DeepCollectionEquality().hash(labels),const DeepCollectionEquality().hash(needs));

@override
String toString() {
  return 'Step(id: $id, title: $title, isClosed: $isClosed, metadata: $metadata, labels: $labels, needs: $needs)';
}


}

/// @nodoc
abstract mixin class $StepCopyWith<$Res>  {
  factory $StepCopyWith(Step value, $Res Function(Step) _then) = _$StepCopyWithImpl;
@useResult
$Res call({
 String id, String title, bool isClosed, StepMetadata metadata, List<String> labels, List<String> needs
});


$StepMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class _$StepCopyWithImpl<$Res>
    implements $StepCopyWith<$Res> {
  _$StepCopyWithImpl(this._self, this._then);

  final Step _self;
  final $Res Function(Step) _then;

/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? isClosed = null,Object? metadata = null,Object? labels = null,Object? needs = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as StepMetadata,labels: null == labels ? _self.labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,needs: null == needs ? _self.needs : needs // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}
/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepMetadataCopyWith<$Res> get metadata {
  
  return $StepMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [Step].
extension StepPatterns on Step {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Step value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Step() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Step value)  $default,){
final _that = this;
switch (_that) {
case _Step():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Step value)?  $default,){
final _that = this;
switch (_that) {
case _Step() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  bool isClosed,  StepMetadata metadata,  List<String> labels,  List<String> needs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that.id,_that.title,_that.isClosed,_that.metadata,_that.labels,_that.needs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  bool isClosed,  StepMetadata metadata,  List<String> labels,  List<String> needs)  $default,) {final _that = this;
switch (_that) {
case _Step():
return $default(_that.id,_that.title,_that.isClosed,_that.metadata,_that.labels,_that.needs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  bool isClosed,  StepMetadata metadata,  List<String> labels,  List<String> needs)?  $default,) {final _that = this;
switch (_that) {
case _Step() when $default != null:
return $default(_that.id,_that.title,_that.isClosed,_that.metadata,_that.labels,_that.needs);case _:
  return null;

}
}

}

/// @nodoc


class _Step extends Step {
  const _Step({required this.id, required this.title, required this.isClosed, required this.metadata, required final  List<String> labels, final  List<String> needs = const <String>[]}): _labels = labels,_needs = needs,super._();
  

@override final  String id;
@override final  String title;
@override final  bool isClosed;
@override final  StepMetadata metadata;
 final  List<String> _labels;
@override List<String> get labels {
  if (_labels is EqualUnmodifiableListView) return _labels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_labels);
}

 final  List<String> _needs;
@override@JsonKey() List<String> get needs {
  if (_needs is EqualUnmodifiableListView) return _needs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_needs);
}


/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StepCopyWith<_Step> get copyWith => __$StepCopyWithImpl<_Step>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Step&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other._labels, _labels)&&const DeepCollectionEquality().equals(other._needs, _needs));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,isClosed,metadata,const DeepCollectionEquality().hash(_labels),const DeepCollectionEquality().hash(_needs));

@override
String toString() {
  return 'Step(id: $id, title: $title, isClosed: $isClosed, metadata: $metadata, labels: $labels, needs: $needs)';
}


}

/// @nodoc
abstract mixin class _$StepCopyWith<$Res> implements $StepCopyWith<$Res> {
  factory _$StepCopyWith(_Step value, $Res Function(_Step) _then) = __$StepCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, bool isClosed, StepMetadata metadata, List<String> labels, List<String> needs
});


@override $StepMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class __$StepCopyWithImpl<$Res>
    implements _$StepCopyWith<$Res> {
  __$StepCopyWithImpl(this._self, this._then);

  final _Step _self;
  final $Res Function(_Step) _then;

/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? isClosed = null,Object? metadata = null,Object? labels = null,Object? needs = null,}) {
  return _then(_Step(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as StepMetadata,labels: null == labels ? _self._labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,needs: null == needs ? _self._needs : needs // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

/// Create a copy of Step
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StepMetadataCopyWith<$Res> get metadata {
  
  return $StepMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

// dart format on
