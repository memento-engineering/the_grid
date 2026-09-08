// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'trajectory_append_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TrajectoryAppendResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TrajectoryAppendResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrajectoryAppendResult()';
}


}

/// @nodoc
class $TrajectoryAppendResultCopyWith<$Res>  {
$TrajectoryAppendResultCopyWith(TrajectoryAppendResult _, $Res Function(TrajectoryAppendResult) __);
}


/// Adds pattern-matching-related methods to [TrajectoryAppendResult].
extension TrajectoryAppendResultPatterns on TrajectoryAppendResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Acked value)?  acked,TResult Function( Dropped value)?  dropped,TResult Function( Suppressed value)?  suppressed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Acked() when acked != null:
return acked(_that);case Dropped() when dropped != null:
return dropped(_that);case Suppressed() when suppressed != null:
return suppressed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Acked value)  acked,required TResult Function( Dropped value)  dropped,required TResult Function( Suppressed value)  suppressed,}){
final _that = this;
switch (_that) {
case Acked():
return acked(_that);case Dropped():
return dropped(_that);case Suppressed():
return suppressed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Acked value)?  acked,TResult? Function( Dropped value)?  dropped,TResult? Function( Suppressed value)?  suppressed,}){
final _that = this;
switch (_that) {
case Acked() when acked != null:
return acked(_that);case Dropped() when dropped != null:
return dropped(_that);case Suppressed() when suppressed != null:
return suppressed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  acked,TResult Function()?  dropped,TResult Function()?  suppressed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Acked() when acked != null:
return acked();case Dropped() when dropped != null:
return dropped();case Suppressed() when suppressed != null:
return suppressed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  acked,required TResult Function()  dropped,required TResult Function()  suppressed,}) {final _that = this;
switch (_that) {
case Acked():
return acked();case Dropped():
return dropped();case Suppressed():
return suppressed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  acked,TResult? Function()?  dropped,TResult? Function()?  suppressed,}) {final _that = this;
switch (_that) {
case Acked() when acked != null:
return acked();case Dropped() when dropped != null:
return dropped();case Suppressed() when suppressed != null:
return suppressed();case _:
  return null;

}
}

}

/// @nodoc


class Acked implements TrajectoryAppendResult {
  const Acked();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Acked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrajectoryAppendResult.acked()';
}


}




/// @nodoc


class Dropped implements TrajectoryAppendResult {
  const Dropped();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Dropped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrajectoryAppendResult.dropped()';
}


}




/// @nodoc


class Suppressed implements TrajectoryAppendResult {
  const Suppressed();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Suppressed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'TrajectoryAppendResult.suppressed()';
}


}




// dart format on
