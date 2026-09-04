// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bead_round.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
RoundContext _$RoundContextFromJson(
  Map<String, dynamic> json
) {
        switch (json['kind']) {
                  case 'round':
          return BeadRoundFound.fromJson(
            json
          );
                case 'no_round':
          return BeadRoundAbsent.fromJson(
            json
          );

          default:
            throw CheckedFromJsonException(
  json,
  'kind',
  'RoundContext',
  'Invalid union type "${json['kind']}"!'
);
        }

}

/// @nodoc
mixin _$RoundContext {

@JsonKey(name: 'bead_id') String get beadId; String get title; String get status;@JsonKey(name: 'validation_plan') String? get validationPlan;
/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoundContextCopyWith<RoundContext> get copyWith => _$RoundContextCopyWithImpl<RoundContext>(this as RoundContext, _$identity);

  /// Serializes this RoundContext to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoundContext&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.validationPlan, validationPlan) || other.validationPlan == validationPlan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,beadId,title,status,validationPlan);

@override
String toString() {
  return 'RoundContext(beadId: $beadId, title: $title, status: $status, validationPlan: $validationPlan)';
}


}

/// @nodoc
abstract mixin class $RoundContextCopyWith<$Res>  {
  factory $RoundContextCopyWith(RoundContext value, $Res Function(RoundContext) _then) = _$RoundContextCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'bead_id') String beadId, String title, String status,@JsonKey(name: 'validation_plan') String? validationPlan
});




}
/// @nodoc
class _$RoundContextCopyWithImpl<$Res>
    implements $RoundContextCopyWith<$Res> {
  _$RoundContextCopyWithImpl(this._self, this._then);

  final RoundContext _self;
  final $Res Function(RoundContext) _then;

/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? beadId = null,Object? title = null,Object? status = null,Object? validationPlan = freezed,}) {
  return _then(_self.copyWith(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,validationPlan: freezed == validationPlan ? _self.validationPlan : validationPlan // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoundContext].
extension RoundContextPatterns on RoundContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BeadRoundFound value)?  round,TResult Function( BeadRoundAbsent value)?  noRound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BeadRoundFound() when round != null:
return round(_that);case BeadRoundAbsent() when noRound != null:
return noRound(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BeadRoundFound value)  round,required TResult Function( BeadRoundAbsent value)  noRound,}){
final _that = this;
switch (_that) {
case BeadRoundFound():
return round(_that);case BeadRoundAbsent():
return noRound(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BeadRoundFound value)?  round,TResult? Function( BeadRoundAbsent value)?  noRound,}){
final _that = this;
switch (_that) {
case BeadRoundFound() when round != null:
return round(_that);case BeadRoundAbsent() when noRound != null:
return noRound(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status, @JsonKey(name: 'session_id')  String sessionId,  int round, @JsonKey(name: 'validation_plan')  String? validationPlan)?  round,TResult Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status,  String reason, @JsonKey(name: 'validation_plan')  String? validationPlan)?  noRound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BeadRoundFound() when round != null:
return round(_that.beadId,_that.title,_that.status,_that.sessionId,_that.round,_that.validationPlan);case BeadRoundAbsent() when noRound != null:
return noRound(_that.beadId,_that.title,_that.status,_that.reason,_that.validationPlan);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status, @JsonKey(name: 'session_id')  String sessionId,  int round, @JsonKey(name: 'validation_plan')  String? validationPlan)  round,required TResult Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status,  String reason, @JsonKey(name: 'validation_plan')  String? validationPlan)  noRound,}) {final _that = this;
switch (_that) {
case BeadRoundFound():
return round(_that.beadId,_that.title,_that.status,_that.sessionId,_that.round,_that.validationPlan);case BeadRoundAbsent():
return noRound(_that.beadId,_that.title,_that.status,_that.reason,_that.validationPlan);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status, @JsonKey(name: 'session_id')  String sessionId,  int round, @JsonKey(name: 'validation_plan')  String? validationPlan)?  round,TResult? Function(@JsonKey(name: 'bead_id')  String beadId,  String title,  String status,  String reason, @JsonKey(name: 'validation_plan')  String? validationPlan)?  noRound,}) {final _that = this;
switch (_that) {
case BeadRoundFound() when round != null:
return round(_that.beadId,_that.title,_that.status,_that.sessionId,_that.round,_that.validationPlan);case BeadRoundAbsent() when noRound != null:
return noRound(_that.beadId,_that.title,_that.status,_that.reason,_that.validationPlan);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class BeadRoundFound implements RoundContext {
  const BeadRoundFound({@JsonKey(name: 'bead_id') required this.beadId, required this.title, required this.status, @JsonKey(name: 'session_id') required this.sessionId, required this.round, @JsonKey(name: 'validation_plan') this.validationPlan, final  String? $type}): $type = $type ?? 'round';
  factory BeadRoundFound.fromJson(Map<String, dynamic> json) => _$BeadRoundFoundFromJson(json);

@override@JsonKey(name: 'bead_id') final  String beadId;
@override final  String title;
@override final  String status;
@JsonKey(name: 'session_id') final  String sessionId;
 final  int round;
@override@JsonKey(name: 'validation_plan') final  String? validationPlan;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadRoundFoundCopyWith<BeadRoundFound> get copyWith => _$BeadRoundFoundCopyWithImpl<BeadRoundFound>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BeadRoundFoundToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadRoundFound&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.round, round) || other.round == round)&&(identical(other.validationPlan, validationPlan) || other.validationPlan == validationPlan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,beadId,title,status,sessionId,round,validationPlan);

@override
String toString() {
  return 'RoundContext.round(beadId: $beadId, title: $title, status: $status, sessionId: $sessionId, round: $round, validationPlan: $validationPlan)';
}


}

/// @nodoc
abstract mixin class $BeadRoundFoundCopyWith<$Res> implements $RoundContextCopyWith<$Res> {
  factory $BeadRoundFoundCopyWith(BeadRoundFound value, $Res Function(BeadRoundFound) _then) = _$BeadRoundFoundCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'bead_id') String beadId, String title, String status,@JsonKey(name: 'session_id') String sessionId, int round,@JsonKey(name: 'validation_plan') String? validationPlan
});




}
/// @nodoc
class _$BeadRoundFoundCopyWithImpl<$Res>
    implements $BeadRoundFoundCopyWith<$Res> {
  _$BeadRoundFoundCopyWithImpl(this._self, this._then);

  final BeadRoundFound _self;
  final $Res Function(BeadRoundFound) _then;

/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? title = null,Object? status = null,Object? sessionId = null,Object? round = null,Object? validationPlan = freezed,}) {
  return _then(BeadRoundFound(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,round: null == round ? _self.round : round // ignore: cast_nullable_to_non_nullable
as int,validationPlan: freezed == validationPlan ? _self.validationPlan : validationPlan // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class BeadRoundAbsent implements RoundContext {
  const BeadRoundAbsent({@JsonKey(name: 'bead_id') required this.beadId, required this.title, required this.status, required this.reason, @JsonKey(name: 'validation_plan') this.validationPlan, final  String? $type}): $type = $type ?? 'no_round';
  factory BeadRoundAbsent.fromJson(Map<String, dynamic> json) => _$BeadRoundAbsentFromJson(json);

@override@JsonKey(name: 'bead_id') final  String beadId;
@override final  String title;
@override final  String status;
 final  String reason;
@override@JsonKey(name: 'validation_plan') final  String? validationPlan;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadRoundAbsentCopyWith<BeadRoundAbsent> get copyWith => _$BeadRoundAbsentCopyWithImpl<BeadRoundAbsent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BeadRoundAbsentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadRoundAbsent&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.validationPlan, validationPlan) || other.validationPlan == validationPlan));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,beadId,title,status,reason,validationPlan);

@override
String toString() {
  return 'RoundContext.noRound(beadId: $beadId, title: $title, status: $status, reason: $reason, validationPlan: $validationPlan)';
}


}

/// @nodoc
abstract mixin class $BeadRoundAbsentCopyWith<$Res> implements $RoundContextCopyWith<$Res> {
  factory $BeadRoundAbsentCopyWith(BeadRoundAbsent value, $Res Function(BeadRoundAbsent) _then) = _$BeadRoundAbsentCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'bead_id') String beadId, String title, String status, String reason,@JsonKey(name: 'validation_plan') String? validationPlan
});




}
/// @nodoc
class _$BeadRoundAbsentCopyWithImpl<$Res>
    implements $BeadRoundAbsentCopyWith<$Res> {
  _$BeadRoundAbsentCopyWithImpl(this._self, this._then);

  final BeadRoundAbsent _self;
  final $Res Function(BeadRoundAbsent) _then;

/// Create a copy of RoundContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? title = null,Object? status = null,Object? reason = null,Object? validationPlan = freezed,}) {
  return _then(BeadRoundAbsent(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,validationPlan: freezed == validationPlan ? _self.validationPlan : validationPlan // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
