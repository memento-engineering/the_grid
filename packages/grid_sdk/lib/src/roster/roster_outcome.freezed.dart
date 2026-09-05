// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'roster_outcome.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RosterOutcome {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RosterOutcome);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RosterOutcome()';
}


}

/// @nodoc
class $RosterOutcomeCopyWith<$Res>  {
$RosterOutcomeCopyWith(RosterOutcome _, $Res Function(RosterOutcome) __);
}


/// Adds pattern-matching-related methods to [RosterOutcome].
extension RosterOutcomePatterns on RosterOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RosterAttached value)?  attached,TResult Function( RosterDetached value)?  detached,TResult Function( RosterDraining value)?  draining,TResult Function( RosterRefused value)?  refused,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RosterAttached() when attached != null:
return attached(_that);case RosterDetached() when detached != null:
return detached(_that);case RosterDraining() when draining != null:
return draining(_that);case RosterRefused() when refused != null:
return refused(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RosterAttached value)  attached,required TResult Function( RosterDetached value)  detached,required TResult Function( RosterDraining value)  draining,required TResult Function( RosterRefused value)  refused,}){
final _that = this;
switch (_that) {
case RosterAttached():
return attached(_that);case RosterDetached():
return detached(_that);case RosterDraining():
return draining(_that);case RosterRefused():
return refused(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RosterAttached value)?  attached,TResult? Function( RosterDetached value)?  detached,TResult? Function( RosterDraining value)?  draining,TResult? Function( RosterRefused value)?  refused,}){
final _that = this;
switch (_that) {
case RosterAttached() when attached != null:
return attached(_that);case RosterDetached() when detached != null:
return detached(_that);case RosterDraining() when draining != null:
return draining(_that);case RosterRefused() when refused != null:
return refused(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String name,  String prefix,  String root)?  attached,TResult Function( String name,  int reapedWorktrees)?  detached,TResult Function( String name,  Set<String> inFlight)?  draining,TResult Function( String code,  String message)?  refused,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RosterAttached() when attached != null:
return attached(_that.name,_that.prefix,_that.root);case RosterDetached() when detached != null:
return detached(_that.name,_that.reapedWorktrees);case RosterDraining() when draining != null:
return draining(_that.name,_that.inFlight);case RosterRefused() when refused != null:
return refused(_that.code,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String name,  String prefix,  String root)  attached,required TResult Function( String name,  int reapedWorktrees)  detached,required TResult Function( String name,  Set<String> inFlight)  draining,required TResult Function( String code,  String message)  refused,}) {final _that = this;
switch (_that) {
case RosterAttached():
return attached(_that.name,_that.prefix,_that.root);case RosterDetached():
return detached(_that.name,_that.reapedWorktrees);case RosterDraining():
return draining(_that.name,_that.inFlight);case RosterRefused():
return refused(_that.code,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String name,  String prefix,  String root)?  attached,TResult? Function( String name,  int reapedWorktrees)?  detached,TResult? Function( String name,  Set<String> inFlight)?  draining,TResult? Function( String code,  String message)?  refused,}) {final _that = this;
switch (_that) {
case RosterAttached() when attached != null:
return attached(_that.name,_that.prefix,_that.root);case RosterDetached() when detached != null:
return detached(_that.name,_that.reapedWorktrees);case RosterDraining() when draining != null:
return draining(_that.name,_that.inFlight);case RosterRefused() when refused != null:
return refused(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class RosterAttached implements RosterOutcome {
  const RosterAttached({required this.name, required this.prefix, required this.root});


 final  String name;
 final  String prefix;
 final  String root;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RosterAttachedCopyWith<RosterAttached> get copyWith => _$RosterAttachedCopyWithImpl<RosterAttached>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RosterAttached&&(identical(other.name, name) || other.name == name)&&(identical(other.prefix, prefix) || other.prefix == prefix)&&(identical(other.root, root) || other.root == root));
}


@override
int get hashCode => Object.hash(runtimeType,name,prefix,root);

@override
String toString() {
  return 'RosterOutcome.attached(name: $name, prefix: $prefix, root: $root)';
}


}

/// @nodoc
abstract mixin class $RosterAttachedCopyWith<$Res> implements $RosterOutcomeCopyWith<$Res> {
  factory $RosterAttachedCopyWith(RosterAttached value, $Res Function(RosterAttached) _then) = _$RosterAttachedCopyWithImpl;
@useResult
$Res call({
 String name, String prefix, String root
});




}
/// @nodoc
class _$RosterAttachedCopyWithImpl<$Res>
    implements $RosterAttachedCopyWith<$Res> {
  _$RosterAttachedCopyWithImpl(this._self, this._then);

  final RosterAttached _self;
  final $Res Function(RosterAttached) _then;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? prefix = null,Object? root = null,}) {
  return _then(RosterAttached(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,prefix: null == prefix ? _self.prefix : prefix // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RosterDetached implements RosterOutcome {
  const RosterDetached({required this.name, required this.reapedWorktrees});


 final  String name;
 final  int reapedWorktrees;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RosterDetachedCopyWith<RosterDetached> get copyWith => _$RosterDetachedCopyWithImpl<RosterDetached>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RosterDetached&&(identical(other.name, name) || other.name == name)&&(identical(other.reapedWorktrees, reapedWorktrees) || other.reapedWorktrees == reapedWorktrees));
}


@override
int get hashCode => Object.hash(runtimeType,name,reapedWorktrees);

@override
String toString() {
  return 'RosterOutcome.detached(name: $name, reapedWorktrees: $reapedWorktrees)';
}


}

/// @nodoc
abstract mixin class $RosterDetachedCopyWith<$Res> implements $RosterOutcomeCopyWith<$Res> {
  factory $RosterDetachedCopyWith(RosterDetached value, $Res Function(RosterDetached) _then) = _$RosterDetachedCopyWithImpl;
@useResult
$Res call({
 String name, int reapedWorktrees
});




}
/// @nodoc
class _$RosterDetachedCopyWithImpl<$Res>
    implements $RosterDetachedCopyWith<$Res> {
  _$RosterDetachedCopyWithImpl(this._self, this._then);

  final RosterDetached _self;
  final $Res Function(RosterDetached) _then;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? reapedWorktrees = null,}) {
  return _then(RosterDetached(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,reapedWorktrees: null == reapedWorktrees ? _self.reapedWorktrees : reapedWorktrees // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RosterDraining implements RosterOutcome {
  const RosterDraining({required this.name, required final  Set<String> inFlight}): _inFlight = inFlight;


 final  String name;
 final  Set<String> _inFlight;
 Set<String> get inFlight {
  if (_inFlight is EqualUnmodifiableSetView) return _inFlight;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_inFlight);
}


/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RosterDrainingCopyWith<RosterDraining> get copyWith => _$RosterDrainingCopyWithImpl<RosterDraining>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RosterDraining&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._inFlight, _inFlight));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_inFlight));

@override
String toString() {
  return 'RosterOutcome.draining(name: $name, inFlight: $inFlight)';
}


}

/// @nodoc
abstract mixin class $RosterDrainingCopyWith<$Res> implements $RosterOutcomeCopyWith<$Res> {
  factory $RosterDrainingCopyWith(RosterDraining value, $Res Function(RosterDraining) _then) = _$RosterDrainingCopyWithImpl;
@useResult
$Res call({
 String name, Set<String> inFlight
});




}
/// @nodoc
class _$RosterDrainingCopyWithImpl<$Res>
    implements $RosterDrainingCopyWith<$Res> {
  _$RosterDrainingCopyWithImpl(this._self, this._then);

  final RosterDraining _self;
  final $Res Function(RosterDraining) _then;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? inFlight = null,}) {
  return _then(RosterDraining(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,inFlight: null == inFlight ? _self._inFlight : inFlight // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}


}

/// @nodoc


class RosterRefused implements RosterOutcome {
  const RosterRefused({required this.code, required this.message});


 final  String code;
 final  String message;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RosterRefusedCopyWith<RosterRefused> get copyWith => _$RosterRefusedCopyWithImpl<RosterRefused>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RosterRefused&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,code,message);

@override
String toString() {
  return 'RosterOutcome.refused(code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $RosterRefusedCopyWith<$Res> implements $RosterOutcomeCopyWith<$Res> {
  factory $RosterRefusedCopyWith(RosterRefused value, $Res Function(RosterRefused) _then) = _$RosterRefusedCopyWithImpl;
@useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$RosterRefusedCopyWithImpl<$Res>
    implements $RosterRefusedCopyWith<$Res> {
  _$RosterRefusedCopyWithImpl(this._self, this._then);

  final RosterRefused _self;
  final $Res Function(RosterRefused) _then;

/// Create a copy of RosterOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(RosterRefused(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
