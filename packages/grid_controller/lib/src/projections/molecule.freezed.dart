// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'molecule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MoleculeMetadata {

 Map<String, dynamic> get raw;
/// Create a copy of MoleculeMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MoleculeMetadataCopyWith<MoleculeMetadata> get copyWith => _$MoleculeMetadataCopyWithImpl<MoleculeMetadata>(this as MoleculeMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MoleculeMetadata&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'MoleculeMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class $MoleculeMetadataCopyWith<$Res>  {
  factory $MoleculeMetadataCopyWith(MoleculeMetadata value, $Res Function(MoleculeMetadata) _then) = _$MoleculeMetadataCopyWithImpl;
@useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class _$MoleculeMetadataCopyWithImpl<$Res>
    implements $MoleculeMetadataCopyWith<$Res> {
  _$MoleculeMetadataCopyWithImpl(this._self, this._then);

  final MoleculeMetadata _self;
  final $Res Function(MoleculeMetadata) _then;

/// Create a copy of MoleculeMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,}) {
  return _then(_self.copyWith(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [MoleculeMetadata].
extension MoleculeMetadataPatterns on MoleculeMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MoleculeMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MoleculeMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MoleculeMetadata value)  $default,){
final _that = this;
switch (_that) {
case _MoleculeMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MoleculeMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _MoleculeMetadata() when $default != null:
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
case _MoleculeMetadata() when $default != null:
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
case _MoleculeMetadata():
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
case _MoleculeMetadata() when $default != null:
return $default(_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _MoleculeMetadata extends MoleculeMetadata {
  const _MoleculeMetadata({final  Map<String, dynamic> raw = const <String, dynamic>{}}): _raw = raw,super._();
  

 final  Map<String, dynamic> _raw;
@override@JsonKey() Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of MoleculeMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MoleculeMetadataCopyWith<_MoleculeMetadata> get copyWith => __$MoleculeMetadataCopyWithImpl<_MoleculeMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MoleculeMetadata&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'MoleculeMetadata(raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$MoleculeMetadataCopyWith<$Res> implements $MoleculeMetadataCopyWith<$Res> {
  factory _$MoleculeMetadataCopyWith(_MoleculeMetadata value, $Res Function(_MoleculeMetadata) _then) = __$MoleculeMetadataCopyWithImpl;
@override @useResult
$Res call({
 Map<String, dynamic> raw
});




}
/// @nodoc
class __$MoleculeMetadataCopyWithImpl<$Res>
    implements _$MoleculeMetadataCopyWith<$Res> {
  __$MoleculeMetadataCopyWithImpl(this._self, this._then);

  final _MoleculeMetadata _self;
  final $Res Function(_MoleculeMetadata) _then;

/// Create a copy of MoleculeMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,}) {
  return _then(_MoleculeMetadata(
raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$Molecule {

 String get id; String get title; bool get isClosed; bool get isWisp; MoleculeMetadata get metadata; List<String> get labels; List<Step> get steps; DateTime? get closedAt; String get closeReason;
/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MoleculeCopyWith<Molecule> get copyWith => _$MoleculeCopyWithImpl<Molecule>(this as Molecule, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Molecule&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.isWisp, isWisp) || other.isWisp == isWisp)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.labels, labels)&&const DeepCollectionEquality().equals(other.steps, steps)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,isClosed,isWisp,metadata,const DeepCollectionEquality().hash(labels),const DeepCollectionEquality().hash(steps),closedAt,closeReason);

@override
String toString() {
  return 'Molecule(id: $id, title: $title, isClosed: $isClosed, isWisp: $isWisp, metadata: $metadata, labels: $labels, steps: $steps, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class $MoleculeCopyWith<$Res>  {
  factory $MoleculeCopyWith(Molecule value, $Res Function(Molecule) _then) = _$MoleculeCopyWithImpl;
@useResult
$Res call({
 String id, String title, bool isClosed, bool isWisp, MoleculeMetadata metadata, List<String> labels, List<Step> steps, DateTime? closedAt, String closeReason
});


$MoleculeMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class _$MoleculeCopyWithImpl<$Res>
    implements $MoleculeCopyWith<$Res> {
  _$MoleculeCopyWithImpl(this._self, this._then);

  final Molecule _self;
  final $Res Function(Molecule) _then;

/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? isClosed = null,Object? isWisp = null,Object? metadata = null,Object? labels = null,Object? steps = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,isWisp: null == isWisp ? _self.isWisp : isWisp // ignore: cast_nullable_to_non_nullable
as bool,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as MoleculeMetadata,labels: null == labels ? _self.labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MoleculeMetadataCopyWith<$Res> get metadata {
  
  return $MoleculeMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}


/// Adds pattern-matching-related methods to [Molecule].
extension MoleculePatterns on Molecule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Molecule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Molecule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Molecule value)  $default,){
final _that = this;
switch (_that) {
case _Molecule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Molecule value)?  $default,){
final _that = this;
switch (_that) {
case _Molecule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  bool isClosed,  bool isWisp,  MoleculeMetadata metadata,  List<String> labels,  List<Step> steps,  DateTime? closedAt,  String closeReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Molecule() when $default != null:
return $default(_that.id,_that.title,_that.isClosed,_that.isWisp,_that.metadata,_that.labels,_that.steps,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  bool isClosed,  bool isWisp,  MoleculeMetadata metadata,  List<String> labels,  List<Step> steps,  DateTime? closedAt,  String closeReason)  $default,) {final _that = this;
switch (_that) {
case _Molecule():
return $default(_that.id,_that.title,_that.isClosed,_that.isWisp,_that.metadata,_that.labels,_that.steps,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  bool isClosed,  bool isWisp,  MoleculeMetadata metadata,  List<String> labels,  List<Step> steps,  DateTime? closedAt,  String closeReason)?  $default,) {final _that = this;
switch (_that) {
case _Molecule() when $default != null:
return $default(_that.id,_that.title,_that.isClosed,_that.isWisp,_that.metadata,_that.labels,_that.steps,_that.closedAt,_that.closeReason);case _:
  return null;

}
}

}

/// @nodoc


class _Molecule extends Molecule {
  const _Molecule({required this.id, required this.title, required this.isClosed, required this.isWisp, required this.metadata, required final  List<String> labels, final  List<Step> steps = const <Step>[], this.closedAt, this.closeReason = ''}): _labels = labels,_steps = steps,super._();
  

@override final  String id;
@override final  String title;
@override final  bool isClosed;
@override final  bool isWisp;
@override final  MoleculeMetadata metadata;
 final  List<String> _labels;
@override List<String> get labels {
  if (_labels is EqualUnmodifiableListView) return _labels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_labels);
}

 final  List<Step> _steps;
@override@JsonKey() List<Step> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

@override final  DateTime? closedAt;
@override@JsonKey() final  String closeReason;

/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MoleculeCopyWith<_Molecule> get copyWith => __$MoleculeCopyWithImpl<_Molecule>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Molecule&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isClosed, isClosed) || other.isClosed == isClosed)&&(identical(other.isWisp, isWisp) || other.isWisp == isWisp)&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other._labels, _labels)&&const DeepCollectionEquality().equals(other._steps, _steps)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,isClosed,isWisp,metadata,const DeepCollectionEquality().hash(_labels),const DeepCollectionEquality().hash(_steps),closedAt,closeReason);

@override
String toString() {
  return 'Molecule(id: $id, title: $title, isClosed: $isClosed, isWisp: $isWisp, metadata: $metadata, labels: $labels, steps: $steps, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class _$MoleculeCopyWith<$Res> implements $MoleculeCopyWith<$Res> {
  factory _$MoleculeCopyWith(_Molecule value, $Res Function(_Molecule) _then) = __$MoleculeCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, bool isClosed, bool isWisp, MoleculeMetadata metadata, List<String> labels, List<Step> steps, DateTime? closedAt, String closeReason
});


@override $MoleculeMetadataCopyWith<$Res> get metadata;

}
/// @nodoc
class __$MoleculeCopyWithImpl<$Res>
    implements _$MoleculeCopyWith<$Res> {
  __$MoleculeCopyWithImpl(this._self, this._then);

  final _Molecule _self;
  final $Res Function(_Molecule) _then;

/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? isClosed = null,Object? isWisp = null,Object? metadata = null,Object? labels = null,Object? steps = null,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_Molecule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isClosed: null == isClosed ? _self.isClosed : isClosed // ignore: cast_nullable_to_non_nullable
as bool,isWisp: null == isWisp ? _self.isWisp : isWisp // ignore: cast_nullable_to_non_nullable
as bool,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as MoleculeMetadata,labels: null == labels ? _self._labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of Molecule
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MoleculeMetadataCopyWith<$Res> get metadata {
  
  return $MoleculeMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}
}

// dart format on
