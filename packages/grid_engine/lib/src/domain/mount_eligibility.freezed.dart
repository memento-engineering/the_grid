// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mount_eligibility.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MountEligibilityDecision {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MountEligibilityDecision);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MountEligibilityDecision()';
}


}

/// @nodoc
class $MountEligibilityDecisionCopyWith<$Res>  {
$MountEligibilityDecisionCopyWith(MountEligibilityDecision _, $Res Function(MountEligibilityDecision) __);
}


/// Adds pattern-matching-related methods to [MountEligibilityDecision].
extension MountEligibilityDecisionPatterns on MountEligibilityDecision {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MountEligible value)?  eligible,TResult Function( MountRefused value)?  refused,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MountEligible() when eligible != null:
return eligible(_that);case MountRefused() when refused != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MountEligible value)  eligible,required TResult Function( MountRefused value)  refused,}){
final _that = this;
switch (_that) {
case MountEligible():
return eligible(_that);case MountRefused():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MountEligible value)?  eligible,TResult? Function( MountRefused value)?  refused,}){
final _that = this;
switch (_that) {
case MountEligible() when eligible != null:
return eligible(_that);case MountRefused() when refused != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  eligible,TResult Function( String clause)?  refused,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MountEligible() when eligible != null:
return eligible();case MountRefused() when refused != null:
return refused(_that.clause);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  eligible,required TResult Function( String clause)  refused,}) {final _that = this;
switch (_that) {
case MountEligible():
return eligible();case MountRefused():
return refused(_that.clause);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  eligible,TResult? Function( String clause)?  refused,}) {final _that = this;
switch (_that) {
case MountEligible() when eligible != null:
return eligible();case MountRefused() when refused != null:
return refused(_that.clause);case _:
  return null;

}
}

}

/// @nodoc


class MountEligible implements MountEligibilityDecision {
  const MountEligible();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MountEligible);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'MountEligibilityDecision.eligible()';
}


}




/// @nodoc


class MountRefused implements MountEligibilityDecision {
  const MountRefused({required this.clause});
  

 final  String clause;

/// Create a copy of MountEligibilityDecision
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MountRefusedCopyWith<MountRefused> get copyWith => _$MountRefusedCopyWithImpl<MountRefused>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MountRefused&&(identical(other.clause, clause) || other.clause == clause));
}


@override
int get hashCode => Object.hash(runtimeType,clause);

@override
String toString() {
  return 'MountEligibilityDecision.refused(clause: $clause)';
}


}

/// @nodoc
abstract mixin class $MountRefusedCopyWith<$Res> implements $MountEligibilityDecisionCopyWith<$Res> {
  factory $MountRefusedCopyWith(MountRefused value, $Res Function(MountRefused) _then) = _$MountRefusedCopyWithImpl;
@useResult
$Res call({
 String clause
});




}
/// @nodoc
class _$MountRefusedCopyWithImpl<$Res>
    implements $MountRefusedCopyWith<$Res> {
  _$MountRefusedCopyWithImpl(this._self, this._then);

  final MountRefused _self;
  final $Res Function(MountRefused) _then;

/// Create a copy of MountEligibilityDecision
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? clause = null,}) {
  return _then(MountRefused(
clause: null == clause ? _self.clause : clause // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
