// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'convergence_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConvergenceStateReading {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConvergenceStateReading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConvergenceStateReading()';
}


}

/// @nodoc
class $ConvergenceStateReadingCopyWith<$Res>  {
$ConvergenceStateReadingCopyWith(ConvergenceStateReading _, $Res Function(ConvergenceStateReading) __);
}


/// Adds pattern-matching-related methods to [ConvergenceStateReading].
extension ConvergenceStateReadingPatterns on ConvergenceStateReading {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( KnownConvergenceState value)?  known,TResult Function( ConvergenceNotAdopted value)?  notAdopted,TResult Function( UnrecognizedConvergenceState value)?  unrecognized,required TResult orElse(),}){
final _that = this;
switch (_that) {
case KnownConvergenceState() when known != null:
return known(_that);case ConvergenceNotAdopted() when notAdopted != null:
return notAdopted(_that);case UnrecognizedConvergenceState() when unrecognized != null:
return unrecognized(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( KnownConvergenceState value)  known,required TResult Function( ConvergenceNotAdopted value)  notAdopted,required TResult Function( UnrecognizedConvergenceState value)  unrecognized,}){
final _that = this;
switch (_that) {
case KnownConvergenceState():
return known(_that);case ConvergenceNotAdopted():
return notAdopted(_that);case UnrecognizedConvergenceState():
return unrecognized(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( KnownConvergenceState value)?  known,TResult? Function( ConvergenceNotAdopted value)?  notAdopted,TResult? Function( UnrecognizedConvergenceState value)?  unrecognized,}){
final _that = this;
switch (_that) {
case KnownConvergenceState() when known != null:
return known(_that);case ConvergenceNotAdopted() when notAdopted != null:
return notAdopted(_that);case UnrecognizedConvergenceState() when unrecognized != null:
return unrecognized(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ConvergenceState state)?  known,TResult Function()?  notAdopted,TResult Function( Object? rawValue)?  unrecognized,required TResult orElse(),}) {final _that = this;
switch (_that) {
case KnownConvergenceState() when known != null:
return known(_that.state);case ConvergenceNotAdopted() when notAdopted != null:
return notAdopted();case UnrecognizedConvergenceState() when unrecognized != null:
return unrecognized(_that.rawValue);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ConvergenceState state)  known,required TResult Function()  notAdopted,required TResult Function( Object? rawValue)  unrecognized,}) {final _that = this;
switch (_that) {
case KnownConvergenceState():
return known(_that.state);case ConvergenceNotAdopted():
return notAdopted();case UnrecognizedConvergenceState():
return unrecognized(_that.rawValue);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ConvergenceState state)?  known,TResult? Function()?  notAdopted,TResult? Function( Object? rawValue)?  unrecognized,}) {final _that = this;
switch (_that) {
case KnownConvergenceState() when known != null:
return known(_that.state);case ConvergenceNotAdopted() when notAdopted != null:
return notAdopted();case UnrecognizedConvergenceState() when unrecognized != null:
return unrecognized(_that.rawValue);case _:
  return null;

}
}

}

/// @nodoc


class KnownConvergenceState extends ConvergenceStateReading {
  const KnownConvergenceState(this.state): super._();
  

 final  ConvergenceState state;

/// Create a copy of ConvergenceStateReading
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$KnownConvergenceStateCopyWith<KnownConvergenceState> get copyWith => _$KnownConvergenceStateCopyWithImpl<KnownConvergenceState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is KnownConvergenceState&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,state);

@override
String toString() {
  return 'ConvergenceStateReading.known(state: $state)';
}


}

/// @nodoc
abstract mixin class $KnownConvergenceStateCopyWith<$Res> implements $ConvergenceStateReadingCopyWith<$Res> {
  factory $KnownConvergenceStateCopyWith(KnownConvergenceState value, $Res Function(KnownConvergenceState) _then) = _$KnownConvergenceStateCopyWithImpl;
@useResult
$Res call({
 ConvergenceState state
});




}
/// @nodoc
class _$KnownConvergenceStateCopyWithImpl<$Res>
    implements $KnownConvergenceStateCopyWith<$Res> {
  _$KnownConvergenceStateCopyWithImpl(this._self, this._then);

  final KnownConvergenceState _self;
  final $Res Function(KnownConvergenceState) _then;

/// Create a copy of ConvergenceStateReading
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,}) {
  return _then(KnownConvergenceState(
null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ConvergenceState,
  ));
}


}

/// @nodoc


class ConvergenceNotAdopted extends ConvergenceStateReading {
  const ConvergenceNotAdopted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConvergenceNotAdopted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ConvergenceStateReading.notAdopted()';
}


}




/// @nodoc


class UnrecognizedConvergenceState extends ConvergenceStateReading {
  const UnrecognizedConvergenceState(this.rawValue): super._();
  

 final  Object? rawValue;

/// Create a copy of ConvergenceStateReading
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnrecognizedConvergenceStateCopyWith<UnrecognizedConvergenceState> get copyWith => _$UnrecognizedConvergenceStateCopyWithImpl<UnrecognizedConvergenceState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnrecognizedConvergenceState&&const DeepCollectionEquality().equals(other.rawValue, rawValue));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(rawValue));

@override
String toString() {
  return 'ConvergenceStateReading.unrecognized(rawValue: $rawValue)';
}


}

/// @nodoc
abstract mixin class $UnrecognizedConvergenceStateCopyWith<$Res> implements $ConvergenceStateReadingCopyWith<$Res> {
  factory $UnrecognizedConvergenceStateCopyWith(UnrecognizedConvergenceState value, $Res Function(UnrecognizedConvergenceState) _then) = _$UnrecognizedConvergenceStateCopyWithImpl;
@useResult
$Res call({
 Object? rawValue
});




}
/// @nodoc
class _$UnrecognizedConvergenceStateCopyWithImpl<$Res>
    implements $UnrecognizedConvergenceStateCopyWith<$Res> {
  _$UnrecognizedConvergenceStateCopyWithImpl(this._self, this._then);

  final UnrecognizedConvergenceState _self;
  final $Res Function(UnrecognizedConvergenceState) _then;

/// Create a copy of ConvergenceStateReading
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rawValue = freezed,}) {
  return _then(UnrecognizedConvergenceState(
freezed == rawValue ? _self.rawValue : rawValue ,
  ));
}


}

// dart format on
