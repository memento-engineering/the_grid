// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'scopes.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GridRoot {

 String get path;
/// Create a copy of GridRoot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridRootCopyWith<GridRoot> get copyWith => _$GridRootCopyWithImpl<GridRoot>(this as GridRoot, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridRoot&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'GridRoot(path: $path)';
}


}

/// @nodoc
abstract mixin class $GridRootCopyWith<$Res>  {
  factory $GridRootCopyWith(GridRoot value, $Res Function(GridRoot) _then) = _$GridRootCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$GridRootCopyWithImpl<$Res>
    implements $GridRootCopyWith<$Res> {
  _$GridRootCopyWithImpl(this._self, this._then);

  final GridRoot _self;
  final $Res Function(GridRoot) _then;

/// Create a copy of GridRoot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [GridRoot].
extension GridRootPatterns on GridRoot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GridRoot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GridRoot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GridRoot value)  $default,){
final _that = this;
switch (_that) {
case _GridRoot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GridRoot value)?  $default,){
final _that = this;
switch (_that) {
case _GridRoot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String path)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GridRoot() when $default != null:
return $default(_that.path);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String path)  $default,) {final _that = this;
switch (_that) {
case _GridRoot():
return $default(_that.path);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String path)?  $default,) {final _that = this;
switch (_that) {
case _GridRoot() when $default != null:
return $default(_that.path);case _:
  return null;

}
}

}

/// @nodoc


class _GridRoot implements GridRoot {
  const _GridRoot({required this.path});
  

@override final  String path;

/// Create a copy of GridRoot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GridRootCopyWith<_GridRoot> get copyWith => __$GridRootCopyWithImpl<_GridRoot>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _GridRoot&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'GridRoot(path: $path)';
}


}

/// @nodoc
abstract mixin class _$GridRootCopyWith<$Res> implements $GridRootCopyWith<$Res> {
  factory _$GridRootCopyWith(_GridRoot value, $Res Function(_GridRoot) _then) = __$GridRootCopyWithImpl;
@override @useResult
$Res call({
 String path
});




}
/// @nodoc
class __$GridRootCopyWithImpl<$Res>
    implements _$GridRootCopyWith<$Res> {
  __$GridRootCopyWithImpl(this._self, this._then);

  final _GridRoot _self;
  final $Res Function(_GridRoot) _then;

/// Create a copy of GridRoot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(_GridRoot(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StationScope {

 String get name; String get root;
/// Create a copy of StationScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StationScopeCopyWith<StationScope> get copyWith => _$StationScopeCopyWithImpl<StationScope>(this as StationScope, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationScope&&(identical(other.name, name) || other.name == name)&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,name,root);

@override
String toString() {
  return 'StationScope(name: $name, root: $root)';
}


}

/// @nodoc
abstract mixin class $StationScopeCopyWith<$Res>  {
  factory $StationScopeCopyWith(StationScope value, $Res Function(StationScope) _then) = _$StationScopeCopyWithImpl;
@useResult
$Res call({
 String name, String root
});




}
/// @nodoc
class _$StationScopeCopyWithImpl<$Res>
    implements $StationScopeCopyWith<$Res> {
  _$StationScopeCopyWithImpl(this._self, this._then);

  final StationScope _self;
  final $Res Function(StationScope) _then;

/// Create a copy of StationScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? root = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StationScope].
extension StationScopePatterns on StationScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StationScope value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StationScope() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StationScope value)  $default,){
final _that = this;
switch (_that) {
case _StationScope():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StationScope value)?  $default,){
final _that = this;
switch (_that) {
case _StationScope() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String root)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StationScope() when $default != null:
return $default(_that.name,_that.root);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String root)  $default,) {final _that = this;
switch (_that) {
case _StationScope():
return $default(_that.name,_that.root);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String root)?  $default,) {final _that = this;
switch (_that) {
case _StationScope() when $default != null:
return $default(_that.name,_that.root);case _:
  return null;

}
}

}

/// @nodoc


class _StationScope implements StationScope {
  const _StationScope({required this.name, required this.root});
  

@override final  String name;
@override final  String root;

/// Create a copy of StationScope
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StationScopeCopyWith<_StationScope> get copyWith => __$StationScopeCopyWithImpl<_StationScope>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StationScope&&(identical(other.name, name) || other.name == name)&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,name,root);

@override
String toString() {
  return 'StationScope(name: $name, root: $root)';
}


}

/// @nodoc
abstract mixin class _$StationScopeCopyWith<$Res> implements $StationScopeCopyWith<$Res> {
  factory _$StationScopeCopyWith(_StationScope value, $Res Function(_StationScope) _then) = __$StationScopeCopyWithImpl;
@override @useResult
$Res call({
 String name, String root
});




}
/// @nodoc
class __$StationScopeCopyWithImpl<$Res>
    implements _$StationScopeCopyWith<$Res> {
  __$StationScopeCopyWithImpl(this._self, this._then);

  final _StationScope _self;
  final $Res Function(_StationScope) _then;

/// Create a copy of StationScope
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? root = null,}) {
  return _then(_StationScope(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SubstationScope {

 String get name; String get root; String get prefix;
/// Create a copy of SubstationScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubstationScopeCopyWith<SubstationScope> get copyWith => _$SubstationScopeCopyWithImpl<SubstationScope>(this as SubstationScope, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubstationScope&&(identical(other.name, name) || other.name == name)&&(identical(other.root, root) || other.root == root)&&(identical(other.prefix, prefix) || other.prefix == prefix));
}


@override
int get hashCode => Object.hash(runtimeType,name,root,prefix);

@override
String toString() {
  return 'SubstationScope(name: $name, root: $root, prefix: $prefix)';
}


}

/// @nodoc
abstract mixin class $SubstationScopeCopyWith<$Res>  {
  factory $SubstationScopeCopyWith(SubstationScope value, $Res Function(SubstationScope) _then) = _$SubstationScopeCopyWithImpl;
@useResult
$Res call({
 String name, String root, String prefix
});




}
/// @nodoc
class _$SubstationScopeCopyWithImpl<$Res>
    implements $SubstationScopeCopyWith<$Res> {
  _$SubstationScopeCopyWithImpl(this._self, this._then);

  final SubstationScope _self;
  final $Res Function(SubstationScope) _then;

/// Create a copy of SubstationScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? root = null,Object? prefix = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,prefix: null == prefix ? _self.prefix : prefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SubstationScope].
extension SubstationScopePatterns on SubstationScope {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubstationScope value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubstationScope() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubstationScope value)  $default,){
final _that = this;
switch (_that) {
case _SubstationScope():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubstationScope value)?  $default,){
final _that = this;
switch (_that) {
case _SubstationScope() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String root,  String prefix)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubstationScope() when $default != null:
return $default(_that.name,_that.root,_that.prefix);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String root,  String prefix)  $default,) {final _that = this;
switch (_that) {
case _SubstationScope():
return $default(_that.name,_that.root,_that.prefix);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String root,  String prefix)?  $default,) {final _that = this;
switch (_that) {
case _SubstationScope() when $default != null:
return $default(_that.name,_that.root,_that.prefix);case _:
  return null;

}
}

}

/// @nodoc


class _SubstationScope implements SubstationScope {
  const _SubstationScope({required this.name, required this.root, required this.prefix});
  

@override final  String name;
@override final  String root;
@override final  String prefix;

/// Create a copy of SubstationScope
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubstationScopeCopyWith<_SubstationScope> get copyWith => __$SubstationScopeCopyWithImpl<_SubstationScope>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubstationScope&&(identical(other.name, name) || other.name == name)&&(identical(other.root, root) || other.root == root)&&(identical(other.prefix, prefix) || other.prefix == prefix));
}


@override
int get hashCode => Object.hash(runtimeType,name,root,prefix);

@override
String toString() {
  return 'SubstationScope(name: $name, root: $root, prefix: $prefix)';
}


}

/// @nodoc
abstract mixin class _$SubstationScopeCopyWith<$Res> implements $SubstationScopeCopyWith<$Res> {
  factory _$SubstationScopeCopyWith(_SubstationScope value, $Res Function(_SubstationScope) _then) = __$SubstationScopeCopyWithImpl;
@override @useResult
$Res call({
 String name, String root, String prefix
});




}
/// @nodoc
class __$SubstationScopeCopyWithImpl<$Res>
    implements _$SubstationScopeCopyWith<$Res> {
  __$SubstationScopeCopyWithImpl(this._self, this._then);

  final _SubstationScope _self;
  final $Res Function(_SubstationScope) _then;

/// Create a copy of SubstationScope
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? root = null,Object? prefix = null,}) {
  return _then(_SubstationScope(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,prefix: null == prefix ? _self.prefix : prefix // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
