// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bd_query_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BdQueryResult {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BdQueryResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'BdQueryResult()';
}


}

/// @nodoc
class $BdQueryResultCopyWith<$Res>  {
$BdQueryResultCopyWith(BdQueryResult _, $Res Function(BdQueryResult) __);
}


/// Adds pattern-matching-related methods to [BdQueryResult].
extension BdQueryResultPatterns on BdQueryResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BdQueryRows value)?  rows,TResult Function( BdQueryVerifiedEmpty value)?  verifiedEmpty,TResult Function( BdQueryUnavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BdQueryRows() when rows != null:
return rows(_that);case BdQueryVerifiedEmpty() when verifiedEmpty != null:
return verifiedEmpty(_that);case BdQueryUnavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BdQueryRows value)  rows,required TResult Function( BdQueryVerifiedEmpty value)  verifiedEmpty,required TResult Function( BdQueryUnavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case BdQueryRows():
return rows(_that);case BdQueryVerifiedEmpty():
return verifiedEmpty(_that);case BdQueryUnavailable():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BdQueryRows value)?  rows,TResult? Function( BdQueryVerifiedEmpty value)?  verifiedEmpty,TResult? Function( BdQueryUnavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case BdQueryRows() when rows != null:
return rows(_that);case BdQueryVerifiedEmpty() when verifiedEmpty != null:
return verifiedEmpty(_that);case BdQueryUnavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<Bead> rows)?  rows,TResult Function( List<String> targetCall,  List<String> positiveControlCall)?  verifiedEmpty,TResult Function( List<String> targetCall,  List<String> positiveControlCall,  String reason,  String remedy)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BdQueryRows() when rows != null:
return rows(_that.rows);case BdQueryVerifiedEmpty() when verifiedEmpty != null:
return verifiedEmpty(_that.targetCall,_that.positiveControlCall);case BdQueryUnavailable() when unavailable != null:
return unavailable(_that.targetCall,_that.positiveControlCall,_that.reason,_that.remedy);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<Bead> rows)  rows,required TResult Function( List<String> targetCall,  List<String> positiveControlCall)  verifiedEmpty,required TResult Function( List<String> targetCall,  List<String> positiveControlCall,  String reason,  String remedy)  unavailable,}) {final _that = this;
switch (_that) {
case BdQueryRows():
return rows(_that.rows);case BdQueryVerifiedEmpty():
return verifiedEmpty(_that.targetCall,_that.positiveControlCall);case BdQueryUnavailable():
return unavailable(_that.targetCall,_that.positiveControlCall,_that.reason,_that.remedy);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<Bead> rows)?  rows,TResult? Function( List<String> targetCall,  List<String> positiveControlCall)?  verifiedEmpty,TResult? Function( List<String> targetCall,  List<String> positiveControlCall,  String reason,  String remedy)?  unavailable,}) {final _that = this;
switch (_that) {
case BdQueryRows() when rows != null:
return rows(_that.rows);case BdQueryVerifiedEmpty() when verifiedEmpty != null:
return verifiedEmpty(_that.targetCall,_that.positiveControlCall);case BdQueryUnavailable() when unavailable != null:
return unavailable(_that.targetCall,_that.positiveControlCall,_that.reason,_that.remedy);case _:
  return null;

}
}

}

/// @nodoc


class BdQueryRows implements BdQueryResult {
  const BdQueryRows({required final  List<Bead> rows}): _rows = rows;


 final  List<Bead> _rows;
 List<Bead> get rows {
  if (_rows is EqualUnmodifiableListView) return _rows;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rows);
}


/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BdQueryRowsCopyWith<BdQueryRows> get copyWith => _$BdQueryRowsCopyWithImpl<BdQueryRows>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BdQueryRows&&const DeepCollectionEquality().equals(other._rows, _rows));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_rows));

@override
String toString() {
  return 'BdQueryResult.rows(rows: $rows)';
}


}

/// @nodoc
abstract mixin class $BdQueryRowsCopyWith<$Res> implements $BdQueryResultCopyWith<$Res> {
  factory $BdQueryRowsCopyWith(BdQueryRows value, $Res Function(BdQueryRows) _then) = _$BdQueryRowsCopyWithImpl;
@useResult
$Res call({
 List<Bead> rows
});




}
/// @nodoc
class _$BdQueryRowsCopyWithImpl<$Res>
    implements $BdQueryRowsCopyWith<$Res> {
  _$BdQueryRowsCopyWithImpl(this._self, this._then);

  final BdQueryRows _self;
  final $Res Function(BdQueryRows) _then;

/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? rows = null,}) {
  return _then(BdQueryRows(
rows: null == rows ? _self._rows : rows // ignore: cast_nullable_to_non_nullable
as List<Bead>,
  ));
}


}

/// @nodoc


class BdQueryVerifiedEmpty implements BdQueryResult {
  const BdQueryVerifiedEmpty({required final  List<String> targetCall, required final  List<String> positiveControlCall}): _targetCall = targetCall,_positiveControlCall = positiveControlCall;


 final  List<String> _targetCall;
 List<String> get targetCall {
  if (_targetCall is EqualUnmodifiableListView) return _targetCall;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targetCall);
}

 final  List<String> _positiveControlCall;
 List<String> get positiveControlCall {
  if (_positiveControlCall is EqualUnmodifiableListView) return _positiveControlCall;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_positiveControlCall);
}


/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BdQueryVerifiedEmptyCopyWith<BdQueryVerifiedEmpty> get copyWith => _$BdQueryVerifiedEmptyCopyWithImpl<BdQueryVerifiedEmpty>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BdQueryVerifiedEmpty&&const DeepCollectionEquality().equals(other._targetCall, _targetCall)&&const DeepCollectionEquality().equals(other._positiveControlCall, _positiveControlCall));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_targetCall),const DeepCollectionEquality().hash(_positiveControlCall));

@override
String toString() {
  return 'BdQueryResult.verifiedEmpty(targetCall: $targetCall, positiveControlCall: $positiveControlCall)';
}


}

/// @nodoc
abstract mixin class $BdQueryVerifiedEmptyCopyWith<$Res> implements $BdQueryResultCopyWith<$Res> {
  factory $BdQueryVerifiedEmptyCopyWith(BdQueryVerifiedEmpty value, $Res Function(BdQueryVerifiedEmpty) _then) = _$BdQueryVerifiedEmptyCopyWithImpl;
@useResult
$Res call({
 List<String> targetCall, List<String> positiveControlCall
});




}
/// @nodoc
class _$BdQueryVerifiedEmptyCopyWithImpl<$Res>
    implements $BdQueryVerifiedEmptyCopyWith<$Res> {
  _$BdQueryVerifiedEmptyCopyWithImpl(this._self, this._then);

  final BdQueryVerifiedEmpty _self;
  final $Res Function(BdQueryVerifiedEmpty) _then;

/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetCall = null,Object? positiveControlCall = null,}) {
  return _then(BdQueryVerifiedEmpty(
targetCall: null == targetCall ? _self._targetCall : targetCall // ignore: cast_nullable_to_non_nullable
as List<String>,positiveControlCall: null == positiveControlCall ? _self._positiveControlCall : positiveControlCall // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class BdQueryUnavailable implements BdQueryResult {
  const BdQueryUnavailable({required final  List<String> targetCall, required final  List<String> positiveControlCall, required this.reason, required this.remedy}): _targetCall = targetCall,_positiveControlCall = positiveControlCall;


 final  List<String> _targetCall;
 List<String> get targetCall {
  if (_targetCall is EqualUnmodifiableListView) return _targetCall;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_targetCall);
}

 final  List<String> _positiveControlCall;
 List<String> get positiveControlCall {
  if (_positiveControlCall is EqualUnmodifiableListView) return _positiveControlCall;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_positiveControlCall);
}

 final  String reason;
 final  String remedy;

/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BdQueryUnavailableCopyWith<BdQueryUnavailable> get copyWith => _$BdQueryUnavailableCopyWithImpl<BdQueryUnavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BdQueryUnavailable&&const DeepCollectionEquality().equals(other._targetCall, _targetCall)&&const DeepCollectionEquality().equals(other._positiveControlCall, _positiveControlCall)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.remedy, remedy) || other.remedy == remedy));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_targetCall),const DeepCollectionEquality().hash(_positiveControlCall),reason,remedy);

@override
String toString() {
  return 'BdQueryResult.unavailable(targetCall: $targetCall, positiveControlCall: $positiveControlCall, reason: $reason, remedy: $remedy)';
}


}

/// @nodoc
abstract mixin class $BdQueryUnavailableCopyWith<$Res> implements $BdQueryResultCopyWith<$Res> {
  factory $BdQueryUnavailableCopyWith(BdQueryUnavailable value, $Res Function(BdQueryUnavailable) _then) = _$BdQueryUnavailableCopyWithImpl;
@useResult
$Res call({
 List<String> targetCall, List<String> positiveControlCall, String reason, String remedy
});




}
/// @nodoc
class _$BdQueryUnavailableCopyWithImpl<$Res>
    implements $BdQueryUnavailableCopyWith<$Res> {
  _$BdQueryUnavailableCopyWithImpl(this._self, this._then);

  final BdQueryUnavailable _self;
  final $Res Function(BdQueryUnavailable) _then;

/// Create a copy of BdQueryResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetCall = null,Object? positiveControlCall = null,Object? reason = null,Object? remedy = null,}) {
  return _then(BdQueryUnavailable(
targetCall: null == targetCall ? _self._targetCall : targetCall // ignore: cast_nullable_to_non_nullable
as List<String>,positiveControlCall: null == positiveControlCall ? _self._positiveControlCall : positiveControlCall // ignore: cast_nullable_to_non_nullable
as List<String>,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,remedy: null == remedy ? _self.remedy : remedy // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
