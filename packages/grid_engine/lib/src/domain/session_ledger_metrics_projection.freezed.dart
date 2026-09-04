// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_ledger_metrics_projection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ResultTransport {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResultTransport);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ResultTransport()';
}


}

/// @nodoc
class $ResultTransportCopyWith<$Res>  {
$ResultTransportCopyWith(ResultTransport _, $Res Function(ResultTransport) __);
}


/// Adds pattern-matching-related methods to [ResultTransport].
extension ResultTransportPatterns on ResultTransport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ResultTransportAbsent value)?  absent,TResult Function( ResultTransportFailClosedDefault value)?  failClosedDefault,TResult Function( ResultTransportOperatorRuling value)?  operatorRuling,TResult Function( ResultTransportReported value)?  reported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ResultTransportAbsent() when absent != null:
return absent(_that);case ResultTransportFailClosedDefault() when failClosedDefault != null:
return failClosedDefault(_that);case ResultTransportOperatorRuling() when operatorRuling != null:
return operatorRuling(_that);case ResultTransportReported() when reported != null:
return reported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ResultTransportAbsent value)  absent,required TResult Function( ResultTransportFailClosedDefault value)  failClosedDefault,required TResult Function( ResultTransportOperatorRuling value)  operatorRuling,required TResult Function( ResultTransportReported value)  reported,}){
final _that = this;
switch (_that) {
case ResultTransportAbsent():
return absent(_that);case ResultTransportFailClosedDefault():
return failClosedDefault(_that);case ResultTransportOperatorRuling():
return operatorRuling(_that);case ResultTransportReported():
return reported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ResultTransportAbsent value)?  absent,TResult? Function( ResultTransportFailClosedDefault value)?  failClosedDefault,TResult? Function( ResultTransportOperatorRuling value)?  operatorRuling,TResult? Function( ResultTransportReported value)?  reported,}){
final _that = this;
switch (_that) {
case ResultTransportAbsent() when absent != null:
return absent(_that);case ResultTransportFailClosedDefault() when failClosedDefault != null:
return failClosedDefault(_that);case ResultTransportOperatorRuling() when operatorRuling != null:
return operatorRuling(_that);case ResultTransportReported() when reported != null:
return reported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  absent,TResult Function()?  failClosedDefault,TResult Function()?  operatorRuling,TResult Function( String value)?  reported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ResultTransportAbsent() when absent != null:
return absent();case ResultTransportFailClosedDefault() when failClosedDefault != null:
return failClosedDefault();case ResultTransportOperatorRuling() when operatorRuling != null:
return operatorRuling();case ResultTransportReported() when reported != null:
return reported(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  absent,required TResult Function()  failClosedDefault,required TResult Function()  operatorRuling,required TResult Function( String value)  reported,}) {final _that = this;
switch (_that) {
case ResultTransportAbsent():
return absent();case ResultTransportFailClosedDefault():
return failClosedDefault();case ResultTransportOperatorRuling():
return operatorRuling();case ResultTransportReported():
return reported(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  absent,TResult? Function()?  failClosedDefault,TResult? Function()?  operatorRuling,TResult? Function( String value)?  reported,}) {final _that = this;
switch (_that) {
case ResultTransportAbsent() when absent != null:
return absent();case ResultTransportFailClosedDefault() when failClosedDefault != null:
return failClosedDefault();case ResultTransportOperatorRuling() when operatorRuling != null:
return operatorRuling();case ResultTransportReported() when reported != null:
return reported(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ResultTransportAbsent implements ResultTransport {
  const ResultTransportAbsent();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResultTransportAbsent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ResultTransport.absent()';
}


}




/// @nodoc


class ResultTransportFailClosedDefault implements ResultTransport {
  const ResultTransportFailClosedDefault();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResultTransportFailClosedDefault);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ResultTransport.failClosedDefault()';
}


}




/// @nodoc


class ResultTransportOperatorRuling implements ResultTransport {
  const ResultTransportOperatorRuling();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResultTransportOperatorRuling);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ResultTransport.operatorRuling()';
}


}




/// @nodoc


class ResultTransportReported implements ResultTransport {
  const ResultTransportReported(this.value);
  

 final  String value;

/// Create a copy of ResultTransport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResultTransportReportedCopyWith<ResultTransportReported> get copyWith => _$ResultTransportReportedCopyWithImpl<ResultTransportReported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResultTransportReported&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ResultTransport.reported(value: $value)';
}


}

/// @nodoc
abstract mixin class $ResultTransportReportedCopyWith<$Res> implements $ResultTransportCopyWith<$Res> {
  factory $ResultTransportReportedCopyWith(ResultTransportReported value, $Res Function(ResultTransportReported) _then) = _$ResultTransportReportedCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ResultTransportReportedCopyWithImpl<$Res>
    implements $ResultTransportReportedCopyWith<$Res> {
  _$ResultTransportReportedCopyWithImpl(this._self, this._then);

  final ResultTransportReported _self;
  final $Res Function(ResultTransportReported) _then;

/// Create a copy of ResultTransport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(ResultTransportReported(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$MetricsDecodeIssue {

 String get beadId; String? get sessionId; String? get nodePath; String get field; String get wireValue; String get reason;
/// Create a copy of MetricsDecodeIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetricsDecodeIssueCopyWith<MetricsDecodeIssue> get copyWith => _$MetricsDecodeIssueCopyWithImpl<MetricsDecodeIssue>(this as MetricsDecodeIssue, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetricsDecodeIssue&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.field, field) || other.field == field)&&(identical(other.wireValue, wireValue) || other.wireValue == wireValue)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,sessionId,nodePath,field,wireValue,reason);

@override
String toString() {
  return 'MetricsDecodeIssue(beadId: $beadId, sessionId: $sessionId, nodePath: $nodePath, field: $field, wireValue: $wireValue, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $MetricsDecodeIssueCopyWith<$Res>  {
  factory $MetricsDecodeIssueCopyWith(MetricsDecodeIssue value, $Res Function(MetricsDecodeIssue) _then) = _$MetricsDecodeIssueCopyWithImpl;
@useResult
$Res call({
 String beadId, String? sessionId, String? nodePath, String field, String wireValue, String reason
});




}
/// @nodoc
class _$MetricsDecodeIssueCopyWithImpl<$Res>
    implements $MetricsDecodeIssueCopyWith<$Res> {
  _$MetricsDecodeIssueCopyWithImpl(this._self, this._then);

  final MetricsDecodeIssue _self;
  final $Res Function(MetricsDecodeIssue) _then;

/// Create a copy of MetricsDecodeIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? beadId = null,Object? sessionId = freezed,Object? nodePath = freezed,Object? field = null,Object? wireValue = null,Object? reason = null,}) {
  return _then(_self.copyWith(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,nodePath: freezed == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String?,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,wireValue: null == wireValue ? _self.wireValue : wireValue // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [MetricsDecodeIssue].
extension MetricsDecodeIssuePatterns on MetricsDecodeIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetricsDecodeIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetricsDecodeIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetricsDecodeIssue value)  $default,){
final _that = this;
switch (_that) {
case _MetricsDecodeIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetricsDecodeIssue value)?  $default,){
final _that = this;
switch (_that) {
case _MetricsDecodeIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String beadId,  String? sessionId,  String? nodePath,  String field,  String wireValue,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetricsDecodeIssue() when $default != null:
return $default(_that.beadId,_that.sessionId,_that.nodePath,_that.field,_that.wireValue,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String beadId,  String? sessionId,  String? nodePath,  String field,  String wireValue,  String reason)  $default,) {final _that = this;
switch (_that) {
case _MetricsDecodeIssue():
return $default(_that.beadId,_that.sessionId,_that.nodePath,_that.field,_that.wireValue,_that.reason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String beadId,  String? sessionId,  String? nodePath,  String field,  String wireValue,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _MetricsDecodeIssue() when $default != null:
return $default(_that.beadId,_that.sessionId,_that.nodePath,_that.field,_that.wireValue,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class _MetricsDecodeIssue implements MetricsDecodeIssue {
  const _MetricsDecodeIssue({required this.beadId, this.sessionId, this.nodePath, required this.field, required this.wireValue, required this.reason});
  

@override final  String beadId;
@override final  String? sessionId;
@override final  String? nodePath;
@override final  String field;
@override final  String wireValue;
@override final  String reason;

/// Create a copy of MetricsDecodeIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetricsDecodeIssueCopyWith<_MetricsDecodeIssue> get copyWith => __$MetricsDecodeIssueCopyWithImpl<_MetricsDecodeIssue>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetricsDecodeIssue&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.field, field) || other.field == field)&&(identical(other.wireValue, wireValue) || other.wireValue == wireValue)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,sessionId,nodePath,field,wireValue,reason);

@override
String toString() {
  return 'MetricsDecodeIssue(beadId: $beadId, sessionId: $sessionId, nodePath: $nodePath, field: $field, wireValue: $wireValue, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$MetricsDecodeIssueCopyWith<$Res> implements $MetricsDecodeIssueCopyWith<$Res> {
  factory _$MetricsDecodeIssueCopyWith(_MetricsDecodeIssue value, $Res Function(_MetricsDecodeIssue) _then) = __$MetricsDecodeIssueCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String? sessionId, String? nodePath, String field, String wireValue, String reason
});




}
/// @nodoc
class __$MetricsDecodeIssueCopyWithImpl<$Res>
    implements _$MetricsDecodeIssueCopyWith<$Res> {
  __$MetricsDecodeIssueCopyWithImpl(this._self, this._then);

  final _MetricsDecodeIssue _self;
  final $Res Function(_MetricsDecodeIssue) _then;

/// Create a copy of MetricsDecodeIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? sessionId = freezed,Object? nodePath = freezed,Object? field = null,Object? wireValue = null,Object? reason = null,}) {
  return _then(_MetricsDecodeIssue(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,nodePath: freezed == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String?,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String,wireValue: null == wireValue ? _self.wireValue : wireValue // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$LedgerNodeMetrics {

 String get beadId; String get nodePath; String get lane; LedgerGrade? get grade; ResultTransport get transport; String? get rationale; String? get delivery; String? get harness; String? get model; double? get costUsd; int? get tokensIn; int? get tokensOut; int? get numTurns; int? get harnessDurationMs; int? get cacheReadInputTokens; int? get cacheCreationInputTokens; int? get modelLatencyMs; String? get transportReliability; DateTime? get startedAt; DateTime? get finishedAt; int? get durationMs; Map<String, String> get rawFields; List<MetricsDecodeIssue> get issues;
/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LedgerNodeMetricsCopyWith<LedgerNodeMetrics> get copyWith => _$LedgerNodeMetricsCopyWithImpl<LedgerNodeMetrics>(this as LedgerNodeMetrics, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LedgerNodeMetrics&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.lane, lane) || other.lane == lane)&&(identical(other.grade, grade) || other.grade == grade)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.rationale, rationale) || other.rationale == rationale)&&(identical(other.delivery, delivery) || other.delivery == delivery)&&(identical(other.harness, harness) || other.harness == harness)&&(identical(other.model, model) || other.model == model)&&(identical(other.costUsd, costUsd) || other.costUsd == costUsd)&&(identical(other.tokensIn, tokensIn) || other.tokensIn == tokensIn)&&(identical(other.tokensOut, tokensOut) || other.tokensOut == tokensOut)&&(identical(other.numTurns, numTurns) || other.numTurns == numTurns)&&(identical(other.harnessDurationMs, harnessDurationMs) || other.harnessDurationMs == harnessDurationMs)&&(identical(other.cacheReadInputTokens, cacheReadInputTokens) || other.cacheReadInputTokens == cacheReadInputTokens)&&(identical(other.cacheCreationInputTokens, cacheCreationInputTokens) || other.cacheCreationInputTokens == cacheCreationInputTokens)&&(identical(other.modelLatencyMs, modelLatencyMs) || other.modelLatencyMs == modelLatencyMs)&&(identical(other.transportReliability, transportReliability) || other.transportReliability == transportReliability)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&const DeepCollectionEquality().equals(other.rawFields, rawFields)&&const DeepCollectionEquality().equals(other.issues, issues));
}


@override
int get hashCode => Object.hashAll([runtimeType,beadId,nodePath,lane,grade,transport,rationale,delivery,harness,model,costUsd,tokensIn,tokensOut,numTurns,harnessDurationMs,cacheReadInputTokens,cacheCreationInputTokens,modelLatencyMs,transportReliability,startedAt,finishedAt,durationMs,const DeepCollectionEquality().hash(rawFields),const DeepCollectionEquality().hash(issues)]);

@override
String toString() {
  return 'LedgerNodeMetrics(beadId: $beadId, nodePath: $nodePath, lane: $lane, grade: $grade, transport: $transport, rationale: $rationale, delivery: $delivery, harness: $harness, model: $model, costUsd: $costUsd, tokensIn: $tokensIn, tokensOut: $tokensOut, numTurns: $numTurns, harnessDurationMs: $harnessDurationMs, cacheReadInputTokens: $cacheReadInputTokens, cacheCreationInputTokens: $cacheCreationInputTokens, modelLatencyMs: $modelLatencyMs, transportReliability: $transportReliability, startedAt: $startedAt, finishedAt: $finishedAt, durationMs: $durationMs, rawFields: $rawFields, issues: $issues)';
}


}

/// @nodoc
abstract mixin class $LedgerNodeMetricsCopyWith<$Res>  {
  factory $LedgerNodeMetricsCopyWith(LedgerNodeMetrics value, $Res Function(LedgerNodeMetrics) _then) = _$LedgerNodeMetricsCopyWithImpl;
@useResult
$Res call({
 String beadId, String nodePath, String lane, LedgerGrade? grade, ResultTransport transport, String? rationale, String? delivery, String? harness, String? model, double? costUsd, int? tokensIn, int? tokensOut, int? numTurns, int? harnessDurationMs, int? cacheReadInputTokens, int? cacheCreationInputTokens, int? modelLatencyMs, String? transportReliability, DateTime? startedAt, DateTime? finishedAt, int? durationMs, Map<String, String> rawFields, List<MetricsDecodeIssue> issues
});


$ResultTransportCopyWith<$Res> get transport;

}
/// @nodoc
class _$LedgerNodeMetricsCopyWithImpl<$Res>
    implements $LedgerNodeMetricsCopyWith<$Res> {
  _$LedgerNodeMetricsCopyWithImpl(this._self, this._then);

  final LedgerNodeMetrics _self;
  final $Res Function(LedgerNodeMetrics) _then;

/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? beadId = null,Object? nodePath = null,Object? lane = null,Object? grade = freezed,Object? transport = null,Object? rationale = freezed,Object? delivery = freezed,Object? harness = freezed,Object? model = freezed,Object? costUsd = freezed,Object? tokensIn = freezed,Object? tokensOut = freezed,Object? numTurns = freezed,Object? harnessDurationMs = freezed,Object? cacheReadInputTokens = freezed,Object? cacheCreationInputTokens = freezed,Object? modelLatencyMs = freezed,Object? transportReliability = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? durationMs = freezed,Object? rawFields = null,Object? issues = null,}) {
  return _then(_self.copyWith(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,nodePath: null == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as String,grade: freezed == grade ? _self.grade : grade // ignore: cast_nullable_to_non_nullable
as LedgerGrade?,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ResultTransport,rationale: freezed == rationale ? _self.rationale : rationale // ignore: cast_nullable_to_non_nullable
as String?,delivery: freezed == delivery ? _self.delivery : delivery // ignore: cast_nullable_to_non_nullable
as String?,harness: freezed == harness ? _self.harness : harness // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,costUsd: freezed == costUsd ? _self.costUsd : costUsd // ignore: cast_nullable_to_non_nullable
as double?,tokensIn: freezed == tokensIn ? _self.tokensIn : tokensIn // ignore: cast_nullable_to_non_nullable
as int?,tokensOut: freezed == tokensOut ? _self.tokensOut : tokensOut // ignore: cast_nullable_to_non_nullable
as int?,numTurns: freezed == numTurns ? _self.numTurns : numTurns // ignore: cast_nullable_to_non_nullable
as int?,harnessDurationMs: freezed == harnessDurationMs ? _self.harnessDurationMs : harnessDurationMs // ignore: cast_nullable_to_non_nullable
as int?,cacheReadInputTokens: freezed == cacheReadInputTokens ? _self.cacheReadInputTokens : cacheReadInputTokens // ignore: cast_nullable_to_non_nullable
as int?,cacheCreationInputTokens: freezed == cacheCreationInputTokens ? _self.cacheCreationInputTokens : cacheCreationInputTokens // ignore: cast_nullable_to_non_nullable
as int?,modelLatencyMs: freezed == modelLatencyMs ? _self.modelLatencyMs : modelLatencyMs // ignore: cast_nullable_to_non_nullable
as int?,transportReliability: freezed == transportReliability ? _self.transportReliability : transportReliability // ignore: cast_nullable_to_non_nullable
as String?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,rawFields: null == rawFields ? _self.rawFields : rawFields // ignore: cast_nullable_to_non_nullable
as Map<String, String>,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}
/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResultTransportCopyWith<$Res> get transport {
  
  return $ResultTransportCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}
}


/// Adds pattern-matching-related methods to [LedgerNodeMetrics].
extension LedgerNodeMetricsPatterns on LedgerNodeMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LedgerNodeMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LedgerNodeMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LedgerNodeMetrics value)  $default,){
final _that = this;
switch (_that) {
case _LedgerNodeMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LedgerNodeMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _LedgerNodeMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String beadId,  String nodePath,  String lane,  LedgerGrade? grade,  ResultTransport transport,  String? rationale,  String? delivery,  String? harness,  String? model,  double? costUsd,  int? tokensIn,  int? tokensOut,  int? numTurns,  int? harnessDurationMs,  int? cacheReadInputTokens,  int? cacheCreationInputTokens,  int? modelLatencyMs,  String? transportReliability,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  Map<String, String> rawFields,  List<MetricsDecodeIssue> issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LedgerNodeMetrics() when $default != null:
return $default(_that.beadId,_that.nodePath,_that.lane,_that.grade,_that.transport,_that.rationale,_that.delivery,_that.harness,_that.model,_that.costUsd,_that.tokensIn,_that.tokensOut,_that.numTurns,_that.harnessDurationMs,_that.cacheReadInputTokens,_that.cacheCreationInputTokens,_that.modelLatencyMs,_that.transportReliability,_that.startedAt,_that.finishedAt,_that.durationMs,_that.rawFields,_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String beadId,  String nodePath,  String lane,  LedgerGrade? grade,  ResultTransport transport,  String? rationale,  String? delivery,  String? harness,  String? model,  double? costUsd,  int? tokensIn,  int? tokensOut,  int? numTurns,  int? harnessDurationMs,  int? cacheReadInputTokens,  int? cacheCreationInputTokens,  int? modelLatencyMs,  String? transportReliability,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  Map<String, String> rawFields,  List<MetricsDecodeIssue> issues)  $default,) {final _that = this;
switch (_that) {
case _LedgerNodeMetrics():
return $default(_that.beadId,_that.nodePath,_that.lane,_that.grade,_that.transport,_that.rationale,_that.delivery,_that.harness,_that.model,_that.costUsd,_that.tokensIn,_that.tokensOut,_that.numTurns,_that.harnessDurationMs,_that.cacheReadInputTokens,_that.cacheCreationInputTokens,_that.modelLatencyMs,_that.transportReliability,_that.startedAt,_that.finishedAt,_that.durationMs,_that.rawFields,_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String beadId,  String nodePath,  String lane,  LedgerGrade? grade,  ResultTransport transport,  String? rationale,  String? delivery,  String? harness,  String? model,  double? costUsd,  int? tokensIn,  int? tokensOut,  int? numTurns,  int? harnessDurationMs,  int? cacheReadInputTokens,  int? cacheCreationInputTokens,  int? modelLatencyMs,  String? transportReliability,  DateTime? startedAt,  DateTime? finishedAt,  int? durationMs,  Map<String, String> rawFields,  List<MetricsDecodeIssue> issues)?  $default,) {final _that = this;
switch (_that) {
case _LedgerNodeMetrics() when $default != null:
return $default(_that.beadId,_that.nodePath,_that.lane,_that.grade,_that.transport,_that.rationale,_that.delivery,_that.harness,_that.model,_that.costUsd,_that.tokensIn,_that.tokensOut,_that.numTurns,_that.harnessDurationMs,_that.cacheReadInputTokens,_that.cacheCreationInputTokens,_that.modelLatencyMs,_that.transportReliability,_that.startedAt,_that.finishedAt,_that.durationMs,_that.rawFields,_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _LedgerNodeMetrics implements LedgerNodeMetrics {
  const _LedgerNodeMetrics({required this.beadId, required this.nodePath, required this.lane, this.grade, this.transport = const ResultTransport.absent(), this.rationale, this.delivery, this.harness, this.model, this.costUsd, this.tokensIn, this.tokensOut, this.numTurns, this.harnessDurationMs, this.cacheReadInputTokens, this.cacheCreationInputTokens, this.modelLatencyMs, this.transportReliability, this.startedAt, this.finishedAt, this.durationMs, final  Map<String, String> rawFields = const <String, String>{}, final  List<MetricsDecodeIssue> issues = const <MetricsDecodeIssue>[]}): _rawFields = rawFields,_issues = issues;
  

@override final  String beadId;
@override final  String nodePath;
@override final  String lane;
@override final  LedgerGrade? grade;
@override@JsonKey() final  ResultTransport transport;
@override final  String? rationale;
@override final  String? delivery;
@override final  String? harness;
@override final  String? model;
@override final  double? costUsd;
@override final  int? tokensIn;
@override final  int? tokensOut;
@override final  int? numTurns;
@override final  int? harnessDurationMs;
@override final  int? cacheReadInputTokens;
@override final  int? cacheCreationInputTokens;
@override final  int? modelLatencyMs;
@override final  String? transportReliability;
@override final  DateTime? startedAt;
@override final  DateTime? finishedAt;
@override final  int? durationMs;
 final  Map<String, String> _rawFields;
@override@JsonKey() Map<String, String> get rawFields {
  if (_rawFields is EqualUnmodifiableMapView) return _rawFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_rawFields);
}

 final  List<MetricsDecodeIssue> _issues;
@override@JsonKey() List<MetricsDecodeIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}


/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LedgerNodeMetricsCopyWith<_LedgerNodeMetrics> get copyWith => __$LedgerNodeMetricsCopyWithImpl<_LedgerNodeMetrics>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LedgerNodeMetrics&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.lane, lane) || other.lane == lane)&&(identical(other.grade, grade) || other.grade == grade)&&(identical(other.transport, transport) || other.transport == transport)&&(identical(other.rationale, rationale) || other.rationale == rationale)&&(identical(other.delivery, delivery) || other.delivery == delivery)&&(identical(other.harness, harness) || other.harness == harness)&&(identical(other.model, model) || other.model == model)&&(identical(other.costUsd, costUsd) || other.costUsd == costUsd)&&(identical(other.tokensIn, tokensIn) || other.tokensIn == tokensIn)&&(identical(other.tokensOut, tokensOut) || other.tokensOut == tokensOut)&&(identical(other.numTurns, numTurns) || other.numTurns == numTurns)&&(identical(other.harnessDurationMs, harnessDurationMs) || other.harnessDurationMs == harnessDurationMs)&&(identical(other.cacheReadInputTokens, cacheReadInputTokens) || other.cacheReadInputTokens == cacheReadInputTokens)&&(identical(other.cacheCreationInputTokens, cacheCreationInputTokens) || other.cacheCreationInputTokens == cacheCreationInputTokens)&&(identical(other.modelLatencyMs, modelLatencyMs) || other.modelLatencyMs == modelLatencyMs)&&(identical(other.transportReliability, transportReliability) || other.transportReliability == transportReliability)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.finishedAt, finishedAt) || other.finishedAt == finishedAt)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&const DeepCollectionEquality().equals(other._rawFields, _rawFields)&&const DeepCollectionEquality().equals(other._issues, _issues));
}


@override
int get hashCode => Object.hashAll([runtimeType,beadId,nodePath,lane,grade,transport,rationale,delivery,harness,model,costUsd,tokensIn,tokensOut,numTurns,harnessDurationMs,cacheReadInputTokens,cacheCreationInputTokens,modelLatencyMs,transportReliability,startedAt,finishedAt,durationMs,const DeepCollectionEquality().hash(_rawFields),const DeepCollectionEquality().hash(_issues)]);

@override
String toString() {
  return 'LedgerNodeMetrics(beadId: $beadId, nodePath: $nodePath, lane: $lane, grade: $grade, transport: $transport, rationale: $rationale, delivery: $delivery, harness: $harness, model: $model, costUsd: $costUsd, tokensIn: $tokensIn, tokensOut: $tokensOut, numTurns: $numTurns, harnessDurationMs: $harnessDurationMs, cacheReadInputTokens: $cacheReadInputTokens, cacheCreationInputTokens: $cacheCreationInputTokens, modelLatencyMs: $modelLatencyMs, transportReliability: $transportReliability, startedAt: $startedAt, finishedAt: $finishedAt, durationMs: $durationMs, rawFields: $rawFields, issues: $issues)';
}


}

/// @nodoc
abstract mixin class _$LedgerNodeMetricsCopyWith<$Res> implements $LedgerNodeMetricsCopyWith<$Res> {
  factory _$LedgerNodeMetricsCopyWith(_LedgerNodeMetrics value, $Res Function(_LedgerNodeMetrics) _then) = __$LedgerNodeMetricsCopyWithImpl;
@override @useResult
$Res call({
 String beadId, String nodePath, String lane, LedgerGrade? grade, ResultTransport transport, String? rationale, String? delivery, String? harness, String? model, double? costUsd, int? tokensIn, int? tokensOut, int? numTurns, int? harnessDurationMs, int? cacheReadInputTokens, int? cacheCreationInputTokens, int? modelLatencyMs, String? transportReliability, DateTime? startedAt, DateTime? finishedAt, int? durationMs, Map<String, String> rawFields, List<MetricsDecodeIssue> issues
});


@override $ResultTransportCopyWith<$Res> get transport;

}
/// @nodoc
class __$LedgerNodeMetricsCopyWithImpl<$Res>
    implements _$LedgerNodeMetricsCopyWith<$Res> {
  __$LedgerNodeMetricsCopyWithImpl(this._self, this._then);

  final _LedgerNodeMetrics _self;
  final $Res Function(_LedgerNodeMetrics) _then;

/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? nodePath = null,Object? lane = null,Object? grade = freezed,Object? transport = null,Object? rationale = freezed,Object? delivery = freezed,Object? harness = freezed,Object? model = freezed,Object? costUsd = freezed,Object? tokensIn = freezed,Object? tokensOut = freezed,Object? numTurns = freezed,Object? harnessDurationMs = freezed,Object? cacheReadInputTokens = freezed,Object? cacheCreationInputTokens = freezed,Object? modelLatencyMs = freezed,Object? transportReliability = freezed,Object? startedAt = freezed,Object? finishedAt = freezed,Object? durationMs = freezed,Object? rawFields = null,Object? issues = null,}) {
  return _then(_LedgerNodeMetrics(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,nodePath: null == nodePath ? _self.nodePath : nodePath // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as String,grade: freezed == grade ? _self.grade : grade // ignore: cast_nullable_to_non_nullable
as LedgerGrade?,transport: null == transport ? _self.transport : transport // ignore: cast_nullable_to_non_nullable
as ResultTransport,rationale: freezed == rationale ? _self.rationale : rationale // ignore: cast_nullable_to_non_nullable
as String?,delivery: freezed == delivery ? _self.delivery : delivery // ignore: cast_nullable_to_non_nullable
as String?,harness: freezed == harness ? _self.harness : harness // ignore: cast_nullable_to_non_nullable
as String?,model: freezed == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String?,costUsd: freezed == costUsd ? _self.costUsd : costUsd // ignore: cast_nullable_to_non_nullable
as double?,tokensIn: freezed == tokensIn ? _self.tokensIn : tokensIn // ignore: cast_nullable_to_non_nullable
as int?,tokensOut: freezed == tokensOut ? _self.tokensOut : tokensOut // ignore: cast_nullable_to_non_nullable
as int?,numTurns: freezed == numTurns ? _self.numTurns : numTurns // ignore: cast_nullable_to_non_nullable
as int?,harnessDurationMs: freezed == harnessDurationMs ? _self.harnessDurationMs : harnessDurationMs // ignore: cast_nullable_to_non_nullable
as int?,cacheReadInputTokens: freezed == cacheReadInputTokens ? _self.cacheReadInputTokens : cacheReadInputTokens // ignore: cast_nullable_to_non_nullable
as int?,cacheCreationInputTokens: freezed == cacheCreationInputTokens ? _self.cacheCreationInputTokens : cacheCreationInputTokens // ignore: cast_nullable_to_non_nullable
as int?,modelLatencyMs: freezed == modelLatencyMs ? _self.modelLatencyMs : modelLatencyMs // ignore: cast_nullable_to_non_nullable
as int?,transportReliability: freezed == transportReliability ? _self.transportReliability : transportReliability // ignore: cast_nullable_to_non_nullable
as String?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationMs: freezed == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int?,rawFields: null == rawFields ? _self._rawFields : rawFields // ignore: cast_nullable_to_non_nullable
as Map<String, String>,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}

/// Create a copy of LedgerNodeMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResultTransportCopyWith<$Res> get transport {
  
  return $ResultTransportCopyWith<$Res>(_self.transport, (value) {
    return _then(_self.copyWith(transport: value));
  });
}
}

/// @nodoc
mixin _$LedgerSessionMetrics {

 String get sessionId; String get workBeadId; DateTime? get startedAt; DateTime? get closedAt; List<LedgerNodeMetrics> get nodes; Map<String, List<LedgerNodeMetrics>> get nodesByLane; List<MetricsDecodeIssue> get issues;
/// Create a copy of LedgerSessionMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LedgerSessionMetricsCopyWith<LedgerSessionMetrics> get copyWith => _$LedgerSessionMetricsCopyWithImpl<LedgerSessionMetrics>(this as LedgerSessionMetrics, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LedgerSessionMetrics&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&const DeepCollectionEquality().equals(other.nodes, nodes)&&const DeepCollectionEquality().equals(other.nodesByLane, nodesByLane)&&const DeepCollectionEquality().equals(other.issues, issues));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,workBeadId,startedAt,closedAt,const DeepCollectionEquality().hash(nodes),const DeepCollectionEquality().hash(nodesByLane),const DeepCollectionEquality().hash(issues));

@override
String toString() {
  return 'LedgerSessionMetrics(sessionId: $sessionId, workBeadId: $workBeadId, startedAt: $startedAt, closedAt: $closedAt, nodes: $nodes, nodesByLane: $nodesByLane, issues: $issues)';
}


}

/// @nodoc
abstract mixin class $LedgerSessionMetricsCopyWith<$Res>  {
  factory $LedgerSessionMetricsCopyWith(LedgerSessionMetrics value, $Res Function(LedgerSessionMetrics) _then) = _$LedgerSessionMetricsCopyWithImpl;
@useResult
$Res call({
 String sessionId, String workBeadId, DateTime? startedAt, DateTime? closedAt, List<LedgerNodeMetrics> nodes, Map<String, List<LedgerNodeMetrics>> nodesByLane, List<MetricsDecodeIssue> issues
});




}
/// @nodoc
class _$LedgerSessionMetricsCopyWithImpl<$Res>
    implements $LedgerSessionMetricsCopyWith<$Res> {
  _$LedgerSessionMetricsCopyWithImpl(this._self, this._then);

  final LedgerSessionMetrics _self;
  final $Res Function(LedgerSessionMetrics) _then;

/// Create a copy of LedgerSessionMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionId = null,Object? workBeadId = null,Object? startedAt = freezed,Object? closedAt = freezed,Object? nodes = null,Object? nodesByLane = null,Object? issues = null,}) {
  return _then(_self.copyWith(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nodes: null == nodes ? _self.nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<LedgerNodeMetrics>,nodesByLane: null == nodesByLane ? _self.nodesByLane : nodesByLane // ignore: cast_nullable_to_non_nullable
as Map<String, List<LedgerNodeMetrics>>,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}

}


/// Adds pattern-matching-related methods to [LedgerSessionMetrics].
extension LedgerSessionMetricsPatterns on LedgerSessionMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LedgerSessionMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LedgerSessionMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LedgerSessionMetrics value)  $default,){
final _that = this;
switch (_that) {
case _LedgerSessionMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LedgerSessionMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _LedgerSessionMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime? closedAt,  List<LedgerNodeMetrics> nodes,  Map<String, List<LedgerNodeMetrics>> nodesByLane,  List<MetricsDecodeIssue> issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LedgerSessionMetrics() when $default != null:
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.closedAt,_that.nodes,_that.nodesByLane,_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime? closedAt,  List<LedgerNodeMetrics> nodes,  Map<String, List<LedgerNodeMetrics>> nodesByLane,  List<MetricsDecodeIssue> issues)  $default,) {final _that = this;
switch (_that) {
case _LedgerSessionMetrics():
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.closedAt,_that.nodes,_that.nodesByLane,_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String sessionId,  String workBeadId,  DateTime? startedAt,  DateTime? closedAt,  List<LedgerNodeMetrics> nodes,  Map<String, List<LedgerNodeMetrics>> nodesByLane,  List<MetricsDecodeIssue> issues)?  $default,) {final _that = this;
switch (_that) {
case _LedgerSessionMetrics() when $default != null:
return $default(_that.sessionId,_that.workBeadId,_that.startedAt,_that.closedAt,_that.nodes,_that.nodesByLane,_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _LedgerSessionMetrics implements LedgerSessionMetrics {
  const _LedgerSessionMetrics({required this.sessionId, required this.workBeadId, this.startedAt, this.closedAt, final  List<LedgerNodeMetrics> nodes = const <LedgerNodeMetrics>[], final  Map<String, List<LedgerNodeMetrics>> nodesByLane = const <String, List<LedgerNodeMetrics>>{}, final  List<MetricsDecodeIssue> issues = const <MetricsDecodeIssue>[]}): _nodes = nodes,_nodesByLane = nodesByLane,_issues = issues;
  

@override final  String sessionId;
@override final  String workBeadId;
@override final  DateTime? startedAt;
@override final  DateTime? closedAt;
 final  List<LedgerNodeMetrics> _nodes;
@override@JsonKey() List<LedgerNodeMetrics> get nodes {
  if (_nodes is EqualUnmodifiableListView) return _nodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nodes);
}

 final  Map<String, List<LedgerNodeMetrics>> _nodesByLane;
@override@JsonKey() Map<String, List<LedgerNodeMetrics>> get nodesByLane {
  if (_nodesByLane is EqualUnmodifiableMapView) return _nodesByLane;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_nodesByLane);
}

 final  List<MetricsDecodeIssue> _issues;
@override@JsonKey() List<MetricsDecodeIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}


/// Create a copy of LedgerSessionMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LedgerSessionMetricsCopyWith<_LedgerSessionMetrics> get copyWith => __$LedgerSessionMetricsCopyWithImpl<_LedgerSessionMetrics>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LedgerSessionMetrics&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&const DeepCollectionEquality().equals(other._nodes, _nodes)&&const DeepCollectionEquality().equals(other._nodesByLane, _nodesByLane)&&const DeepCollectionEquality().equals(other._issues, _issues));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,workBeadId,startedAt,closedAt,const DeepCollectionEquality().hash(_nodes),const DeepCollectionEquality().hash(_nodesByLane),const DeepCollectionEquality().hash(_issues));

@override
String toString() {
  return 'LedgerSessionMetrics(sessionId: $sessionId, workBeadId: $workBeadId, startedAt: $startedAt, closedAt: $closedAt, nodes: $nodes, nodesByLane: $nodesByLane, issues: $issues)';
}


}

/// @nodoc
abstract mixin class _$LedgerSessionMetricsCopyWith<$Res> implements $LedgerSessionMetricsCopyWith<$Res> {
  factory _$LedgerSessionMetricsCopyWith(_LedgerSessionMetrics value, $Res Function(_LedgerSessionMetrics) _then) = __$LedgerSessionMetricsCopyWithImpl;
@override @useResult
$Res call({
 String sessionId, String workBeadId, DateTime? startedAt, DateTime? closedAt, List<LedgerNodeMetrics> nodes, Map<String, List<LedgerNodeMetrics>> nodesByLane, List<MetricsDecodeIssue> issues
});




}
/// @nodoc
class __$LedgerSessionMetricsCopyWithImpl<$Res>
    implements _$LedgerSessionMetricsCopyWith<$Res> {
  __$LedgerSessionMetricsCopyWithImpl(this._self, this._then);

  final _LedgerSessionMetrics _self;
  final $Res Function(_LedgerSessionMetrics) _then;

/// Create a copy of LedgerSessionMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? workBeadId = null,Object? startedAt = freezed,Object? closedAt = freezed,Object? nodes = null,Object? nodesByLane = null,Object? issues = null,}) {
  return _then(_LedgerSessionMetrics(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,workBeadId: null == workBeadId ? _self.workBeadId : workBeadId // ignore: cast_nullable_to_non_nullable
as String,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nodes: null == nodes ? _self._nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<LedgerNodeMetrics>,nodesByLane: null == nodesByLane ? _self._nodesByLane : nodesByLane // ignore: cast_nullable_to_non_nullable
as Map<String, List<LedgerNodeMetrics>>,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}


}

/// @nodoc
mixin _$FalseFMetrics {

 int get total; int get failClosedDefault; int get realVerdict; double? get rate;
/// Create a copy of FalseFMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FalseFMetricsCopyWith<FalseFMetrics> get copyWith => _$FalseFMetricsCopyWithImpl<FalseFMetrics>(this as FalseFMetrics, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FalseFMetrics&&(identical(other.total, total) || other.total == total)&&(identical(other.failClosedDefault, failClosedDefault) || other.failClosedDefault == failClosedDefault)&&(identical(other.realVerdict, realVerdict) || other.realVerdict == realVerdict)&&(identical(other.rate, rate) || other.rate == rate));
}


@override
int get hashCode => Object.hash(runtimeType,total,failClosedDefault,realVerdict,rate);

@override
String toString() {
  return 'FalseFMetrics(total: $total, failClosedDefault: $failClosedDefault, realVerdict: $realVerdict, rate: $rate)';
}


}

/// @nodoc
abstract mixin class $FalseFMetricsCopyWith<$Res>  {
  factory $FalseFMetricsCopyWith(FalseFMetrics value, $Res Function(FalseFMetrics) _then) = _$FalseFMetricsCopyWithImpl;
@useResult
$Res call({
 int total, int failClosedDefault, int realVerdict, double? rate
});




}
/// @nodoc
class _$FalseFMetricsCopyWithImpl<$Res>
    implements $FalseFMetricsCopyWith<$Res> {
  _$FalseFMetricsCopyWithImpl(this._self, this._then);

  final FalseFMetrics _self;
  final $Res Function(FalseFMetrics) _then;

/// Create a copy of FalseFMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? total = null,Object? failClosedDefault = null,Object? realVerdict = null,Object? rate = freezed,}) {
  return _then(_self.copyWith(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,failClosedDefault: null == failClosedDefault ? _self.failClosedDefault : failClosedDefault // ignore: cast_nullable_to_non_nullable
as int,realVerdict: null == realVerdict ? _self.realVerdict : realVerdict // ignore: cast_nullable_to_non_nullable
as int,rate: freezed == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [FalseFMetrics].
extension FalseFMetricsPatterns on FalseFMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FalseFMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FalseFMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FalseFMetrics value)  $default,){
final _that = this;
switch (_that) {
case _FalseFMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FalseFMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _FalseFMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int total,  int failClosedDefault,  int realVerdict,  double? rate)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FalseFMetrics() when $default != null:
return $default(_that.total,_that.failClosedDefault,_that.realVerdict,_that.rate);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int total,  int failClosedDefault,  int realVerdict,  double? rate)  $default,) {final _that = this;
switch (_that) {
case _FalseFMetrics():
return $default(_that.total,_that.failClosedDefault,_that.realVerdict,_that.rate);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int total,  int failClosedDefault,  int realVerdict,  double? rate)?  $default,) {final _that = this;
switch (_that) {
case _FalseFMetrics() when $default != null:
return $default(_that.total,_that.failClosedDefault,_that.realVerdict,_that.rate);case _:
  return null;

}
}

}

/// @nodoc


class _FalseFMetrics implements FalseFMetrics {
  const _FalseFMetrics({this.total = 0, this.failClosedDefault = 0, this.realVerdict = 0, this.rate});
  

@override@JsonKey() final  int total;
@override@JsonKey() final  int failClosedDefault;
@override@JsonKey() final  int realVerdict;
@override final  double? rate;

/// Create a copy of FalseFMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FalseFMetricsCopyWith<_FalseFMetrics> get copyWith => __$FalseFMetricsCopyWithImpl<_FalseFMetrics>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FalseFMetrics&&(identical(other.total, total) || other.total == total)&&(identical(other.failClosedDefault, failClosedDefault) || other.failClosedDefault == failClosedDefault)&&(identical(other.realVerdict, realVerdict) || other.realVerdict == realVerdict)&&(identical(other.rate, rate) || other.rate == rate));
}


@override
int get hashCode => Object.hash(runtimeType,total,failClosedDefault,realVerdict,rate);

@override
String toString() {
  return 'FalseFMetrics(total: $total, failClosedDefault: $failClosedDefault, realVerdict: $realVerdict, rate: $rate)';
}


}

/// @nodoc
abstract mixin class _$FalseFMetricsCopyWith<$Res> implements $FalseFMetricsCopyWith<$Res> {
  factory _$FalseFMetricsCopyWith(_FalseFMetrics value, $Res Function(_FalseFMetrics) _then) = __$FalseFMetricsCopyWithImpl;
@override @useResult
$Res call({
 int total, int failClosedDefault, int realVerdict, double? rate
});




}
/// @nodoc
class __$FalseFMetricsCopyWithImpl<$Res>
    implements _$FalseFMetricsCopyWith<$Res> {
  __$FalseFMetricsCopyWithImpl(this._self, this._then);

  final _FalseFMetrics _self;
  final $Res Function(_FalseFMetrics) _then;

/// Create a copy of FalseFMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? total = null,Object? failClosedDefault = null,Object? realVerdict = null,Object? rate = freezed,}) {
  return _then(_FalseFMetrics(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,failClosedDefault: null == failClosedDefault ? _self.failClosedDefault : failClosedDefault // ignore: cast_nullable_to_non_nullable
as int,realVerdict: null == realVerdict ? _self.realVerdict : realVerdict // ignore: cast_nullable_to_non_nullable
as int,rate: freezed == rate ? _self.rate : rate // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$CacheTokenTotals {

/// Input tokens served from cache.
 int get cacheRead;/// Input tokens written into cache.
 int get cacheCreate;/// Input tokens not served from or written into cache.
 int get uncachedInput;
/// Create a copy of CacheTokenTotals
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CacheTokenTotalsCopyWith<CacheTokenTotals> get copyWith => _$CacheTokenTotalsCopyWithImpl<CacheTokenTotals>(this as CacheTokenTotals, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CacheTokenTotals&&(identical(other.cacheRead, cacheRead) || other.cacheRead == cacheRead)&&(identical(other.cacheCreate, cacheCreate) || other.cacheCreate == cacheCreate)&&(identical(other.uncachedInput, uncachedInput) || other.uncachedInput == uncachedInput));
}


@override
int get hashCode => Object.hash(runtimeType,cacheRead,cacheCreate,uncachedInput);

@override
String toString() {
  return 'CacheTokenTotals(cacheRead: $cacheRead, cacheCreate: $cacheCreate, uncachedInput: $uncachedInput)';
}


}

/// @nodoc
abstract mixin class $CacheTokenTotalsCopyWith<$Res>  {
  factory $CacheTokenTotalsCopyWith(CacheTokenTotals value, $Res Function(CacheTokenTotals) _then) = _$CacheTokenTotalsCopyWithImpl;
@useResult
$Res call({
 int cacheRead, int cacheCreate, int uncachedInput
});




}
/// @nodoc
class _$CacheTokenTotalsCopyWithImpl<$Res>
    implements $CacheTokenTotalsCopyWith<$Res> {
  _$CacheTokenTotalsCopyWithImpl(this._self, this._then);

  final CacheTokenTotals _self;
  final $Res Function(CacheTokenTotals) _then;

/// Create a copy of CacheTokenTotals
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? cacheRead = null,Object? cacheCreate = null,Object? uncachedInput = null,}) {
  return _then(_self.copyWith(
cacheRead: null == cacheRead ? _self.cacheRead : cacheRead // ignore: cast_nullable_to_non_nullable
as int,cacheCreate: null == cacheCreate ? _self.cacheCreate : cacheCreate // ignore: cast_nullable_to_non_nullable
as int,uncachedInput: null == uncachedInput ? _self.uncachedInput : uncachedInput // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [CacheTokenTotals].
extension CacheTokenTotalsPatterns on CacheTokenTotals {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CacheTokenTotals value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CacheTokenTotals() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CacheTokenTotals value)  $default,){
final _that = this;
switch (_that) {
case _CacheTokenTotals():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CacheTokenTotals value)?  $default,){
final _that = this;
switch (_that) {
case _CacheTokenTotals() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int cacheRead,  int cacheCreate,  int uncachedInput)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CacheTokenTotals() when $default != null:
return $default(_that.cacheRead,_that.cacheCreate,_that.uncachedInput);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int cacheRead,  int cacheCreate,  int uncachedInput)  $default,) {final _that = this;
switch (_that) {
case _CacheTokenTotals():
return $default(_that.cacheRead,_that.cacheCreate,_that.uncachedInput);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int cacheRead,  int cacheCreate,  int uncachedInput)?  $default,) {final _that = this;
switch (_that) {
case _CacheTokenTotals() when $default != null:
return $default(_that.cacheRead,_that.cacheCreate,_that.uncachedInput);case _:
  return null;

}
}

}

/// @nodoc


class _CacheTokenTotals implements CacheTokenTotals {
  const _CacheTokenTotals({this.cacheRead = 0, this.cacheCreate = 0, this.uncachedInput = 0});
  

/// Input tokens served from cache.
@override@JsonKey() final  int cacheRead;
/// Input tokens written into cache.
@override@JsonKey() final  int cacheCreate;
/// Input tokens not served from or written into cache.
@override@JsonKey() final  int uncachedInput;

/// Create a copy of CacheTokenTotals
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CacheTokenTotalsCopyWith<_CacheTokenTotals> get copyWith => __$CacheTokenTotalsCopyWithImpl<_CacheTokenTotals>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CacheTokenTotals&&(identical(other.cacheRead, cacheRead) || other.cacheRead == cacheRead)&&(identical(other.cacheCreate, cacheCreate) || other.cacheCreate == cacheCreate)&&(identical(other.uncachedInput, uncachedInput) || other.uncachedInput == uncachedInput));
}


@override
int get hashCode => Object.hash(runtimeType,cacheRead,cacheCreate,uncachedInput);

@override
String toString() {
  return 'CacheTokenTotals(cacheRead: $cacheRead, cacheCreate: $cacheCreate, uncachedInput: $uncachedInput)';
}


}

/// @nodoc
abstract mixin class _$CacheTokenTotalsCopyWith<$Res> implements $CacheTokenTotalsCopyWith<$Res> {
  factory _$CacheTokenTotalsCopyWith(_CacheTokenTotals value, $Res Function(_CacheTokenTotals) _then) = __$CacheTokenTotalsCopyWithImpl;
@override @useResult
$Res call({
 int cacheRead, int cacheCreate, int uncachedInput
});




}
/// @nodoc
class __$CacheTokenTotalsCopyWithImpl<$Res>
    implements _$CacheTokenTotalsCopyWith<$Res> {
  __$CacheTokenTotalsCopyWithImpl(this._self, this._then);

  final _CacheTokenTotals _self;
  final $Res Function(_CacheTokenTotals) _then;

/// Create a copy of CacheTokenTotals
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? cacheRead = null,Object? cacheCreate = null,Object? uncachedInput = null,}) {
  return _then(_CacheTokenTotals(
cacheRead: null == cacheRead ? _self.cacheRead : cacheRead // ignore: cast_nullable_to_non_nullable
as int,cacheCreate: null == cacheCreate ? _self.cacheCreate : cacheCreate // ignore: cast_nullable_to_non_nullable
as int,uncachedInput: null == uncachedInput ? _self.uncachedInput : uncachedInput // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$LandedDeliveryTotals {

/// Cost in US dollars across landed sessions.
 double get landedCost;/// Number of sessions with a non-empty delivery.
 int get landedCount;
/// Create a copy of LandedDeliveryTotals
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LandedDeliveryTotalsCopyWith<LandedDeliveryTotals> get copyWith => _$LandedDeliveryTotalsCopyWithImpl<LandedDeliveryTotals>(this as LandedDeliveryTotals, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LandedDeliveryTotals&&(identical(other.landedCost, landedCost) || other.landedCost == landedCost)&&(identical(other.landedCount, landedCount) || other.landedCount == landedCount));
}


@override
int get hashCode => Object.hash(runtimeType,landedCost,landedCount);

@override
String toString() {
  return 'LandedDeliveryTotals(landedCost: $landedCost, landedCount: $landedCount)';
}


}

/// @nodoc
abstract mixin class $LandedDeliveryTotalsCopyWith<$Res>  {
  factory $LandedDeliveryTotalsCopyWith(LandedDeliveryTotals value, $Res Function(LandedDeliveryTotals) _then) = _$LandedDeliveryTotalsCopyWithImpl;
@useResult
$Res call({
 double landedCost, int landedCount
});




}
/// @nodoc
class _$LandedDeliveryTotalsCopyWithImpl<$Res>
    implements $LandedDeliveryTotalsCopyWith<$Res> {
  _$LandedDeliveryTotalsCopyWithImpl(this._self, this._then);

  final LandedDeliveryTotals _self;
  final $Res Function(LandedDeliveryTotals) _then;

/// Create a copy of LandedDeliveryTotals
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? landedCost = null,Object? landedCount = null,}) {
  return _then(_self.copyWith(
landedCost: null == landedCost ? _self.landedCost : landedCost // ignore: cast_nullable_to_non_nullable
as double,landedCount: null == landedCount ? _self.landedCount : landedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [LandedDeliveryTotals].
extension LandedDeliveryTotalsPatterns on LandedDeliveryTotals {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LandedDeliveryTotals value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LandedDeliveryTotals() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LandedDeliveryTotals value)  $default,){
final _that = this;
switch (_that) {
case _LandedDeliveryTotals():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LandedDeliveryTotals value)?  $default,){
final _that = this;
switch (_that) {
case _LandedDeliveryTotals() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( double landedCost,  int landedCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LandedDeliveryTotals() when $default != null:
return $default(_that.landedCost,_that.landedCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( double landedCost,  int landedCount)  $default,) {final _that = this;
switch (_that) {
case _LandedDeliveryTotals():
return $default(_that.landedCost,_that.landedCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( double landedCost,  int landedCount)?  $default,) {final _that = this;
switch (_that) {
case _LandedDeliveryTotals() when $default != null:
return $default(_that.landedCost,_that.landedCount);case _:
  return null;

}
}

}

/// @nodoc


class _LandedDeliveryTotals implements LandedDeliveryTotals {
  const _LandedDeliveryTotals({this.landedCost = 0, this.landedCount = 0});
  

/// Cost in US dollars across landed sessions.
@override@JsonKey() final  double landedCost;
/// Number of sessions with a non-empty delivery.
@override@JsonKey() final  int landedCount;

/// Create a copy of LandedDeliveryTotals
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LandedDeliveryTotalsCopyWith<_LandedDeliveryTotals> get copyWith => __$LandedDeliveryTotalsCopyWithImpl<_LandedDeliveryTotals>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LandedDeliveryTotals&&(identical(other.landedCost, landedCost) || other.landedCost == landedCost)&&(identical(other.landedCount, landedCount) || other.landedCount == landedCount));
}


@override
int get hashCode => Object.hash(runtimeType,landedCost,landedCount);

@override
String toString() {
  return 'LandedDeliveryTotals(landedCost: $landedCost, landedCount: $landedCount)';
}


}

/// @nodoc
abstract mixin class _$LandedDeliveryTotalsCopyWith<$Res> implements $LandedDeliveryTotalsCopyWith<$Res> {
  factory _$LandedDeliveryTotalsCopyWith(_LandedDeliveryTotals value, $Res Function(_LandedDeliveryTotals) _then) = __$LandedDeliveryTotalsCopyWithImpl;
@override @useResult
$Res call({
 double landedCost, int landedCount
});




}
/// @nodoc
class __$LandedDeliveryTotalsCopyWithImpl<$Res>
    implements _$LandedDeliveryTotalsCopyWith<$Res> {
  __$LandedDeliveryTotalsCopyWithImpl(this._self, this._then);

  final _LandedDeliveryTotals _self;
  final $Res Function(_LandedDeliveryTotals) _then;

/// Create a copy of LandedDeliveryTotals
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? landedCost = null,Object? landedCount = null,}) {
  return _then(_LandedDeliveryTotals(
landedCost: null == landedCost ? _self.landedCost : landedCost // ignore: cast_nullable_to_non_nullable
as double,landedCount: null == landedCount ? _self.landedCount : landedCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$SessionLedgerMetricsProjection {

 Map<String, LedgerSessionMetrics> get sessionsById; Map<String, List<LedgerSessionMetrics>> get sessionsByLane; FalseFMetrics get falseFs;/// Components used to derive [cacheHitRatio].
 CacheTokenTotals get cacheTokens; double? get cacheHitRatio; Map<String, int> get reworkRoundsByWorkBead;/// Components used to derive [costPerLandedDelivery].
 LandedDeliveryTotals get landedDeliveries; double? get costPerLandedDelivery; Map<String, Map<LedgerGrade, int>> get gradeDistributionByLane; List<MetricsDecodeIssue> get issues;
/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionLedgerMetricsProjectionCopyWith<SessionLedgerMetricsProjection> get copyWith => _$SessionLedgerMetricsProjectionCopyWithImpl<SessionLedgerMetricsProjection>(this as SessionLedgerMetricsProjection, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionLedgerMetricsProjection&&const DeepCollectionEquality().equals(other.sessionsById, sessionsById)&&const DeepCollectionEquality().equals(other.sessionsByLane, sessionsByLane)&&(identical(other.falseFs, falseFs) || other.falseFs == falseFs)&&(identical(other.cacheTokens, cacheTokens) || other.cacheTokens == cacheTokens)&&(identical(other.cacheHitRatio, cacheHitRatio) || other.cacheHitRatio == cacheHitRatio)&&const DeepCollectionEquality().equals(other.reworkRoundsByWorkBead, reworkRoundsByWorkBead)&&(identical(other.landedDeliveries, landedDeliveries) || other.landedDeliveries == landedDeliveries)&&(identical(other.costPerLandedDelivery, costPerLandedDelivery) || other.costPerLandedDelivery == costPerLandedDelivery)&&const DeepCollectionEquality().equals(other.gradeDistributionByLane, gradeDistributionByLane)&&const DeepCollectionEquality().equals(other.issues, issues));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(sessionsById),const DeepCollectionEquality().hash(sessionsByLane),falseFs,cacheTokens,cacheHitRatio,const DeepCollectionEquality().hash(reworkRoundsByWorkBead),landedDeliveries,costPerLandedDelivery,const DeepCollectionEquality().hash(gradeDistributionByLane),const DeepCollectionEquality().hash(issues));

@override
String toString() {
  return 'SessionLedgerMetricsProjection(sessionsById: $sessionsById, sessionsByLane: $sessionsByLane, falseFs: $falseFs, cacheTokens: $cacheTokens, cacheHitRatio: $cacheHitRatio, reworkRoundsByWorkBead: $reworkRoundsByWorkBead, landedDeliveries: $landedDeliveries, costPerLandedDelivery: $costPerLandedDelivery, gradeDistributionByLane: $gradeDistributionByLane, issues: $issues)';
}


}

/// @nodoc
abstract mixin class $SessionLedgerMetricsProjectionCopyWith<$Res>  {
  factory $SessionLedgerMetricsProjectionCopyWith(SessionLedgerMetricsProjection value, $Res Function(SessionLedgerMetricsProjection) _then) = _$SessionLedgerMetricsProjectionCopyWithImpl;
@useResult
$Res call({
 Map<String, LedgerSessionMetrics> sessionsById, Map<String, List<LedgerSessionMetrics>> sessionsByLane, FalseFMetrics falseFs, CacheTokenTotals cacheTokens, double? cacheHitRatio, Map<String, int> reworkRoundsByWorkBead, LandedDeliveryTotals landedDeliveries, double? costPerLandedDelivery, Map<String, Map<LedgerGrade, int>> gradeDistributionByLane, List<MetricsDecodeIssue> issues
});


$FalseFMetricsCopyWith<$Res> get falseFs;$CacheTokenTotalsCopyWith<$Res> get cacheTokens;$LandedDeliveryTotalsCopyWith<$Res> get landedDeliveries;

}
/// @nodoc
class _$SessionLedgerMetricsProjectionCopyWithImpl<$Res>
    implements $SessionLedgerMetricsProjectionCopyWith<$Res> {
  _$SessionLedgerMetricsProjectionCopyWithImpl(this._self, this._then);

  final SessionLedgerMetricsProjection _self;
  final $Res Function(SessionLedgerMetricsProjection) _then;

/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sessionsById = null,Object? sessionsByLane = null,Object? falseFs = null,Object? cacheTokens = null,Object? cacheHitRatio = freezed,Object? reworkRoundsByWorkBead = null,Object? landedDeliveries = null,Object? costPerLandedDelivery = freezed,Object? gradeDistributionByLane = null,Object? issues = null,}) {
  return _then(_self.copyWith(
sessionsById: null == sessionsById ? _self.sessionsById : sessionsById // ignore: cast_nullable_to_non_nullable
as Map<String, LedgerSessionMetrics>,sessionsByLane: null == sessionsByLane ? _self.sessionsByLane : sessionsByLane // ignore: cast_nullable_to_non_nullable
as Map<String, List<LedgerSessionMetrics>>,falseFs: null == falseFs ? _self.falseFs : falseFs // ignore: cast_nullable_to_non_nullable
as FalseFMetrics,cacheTokens: null == cacheTokens ? _self.cacheTokens : cacheTokens // ignore: cast_nullable_to_non_nullable
as CacheTokenTotals,cacheHitRatio: freezed == cacheHitRatio ? _self.cacheHitRatio : cacheHitRatio // ignore: cast_nullable_to_non_nullable
as double?,reworkRoundsByWorkBead: null == reworkRoundsByWorkBead ? _self.reworkRoundsByWorkBead : reworkRoundsByWorkBead // ignore: cast_nullable_to_non_nullable
as Map<String, int>,landedDeliveries: null == landedDeliveries ? _self.landedDeliveries : landedDeliveries // ignore: cast_nullable_to_non_nullable
as LandedDeliveryTotals,costPerLandedDelivery: freezed == costPerLandedDelivery ? _self.costPerLandedDelivery : costPerLandedDelivery // ignore: cast_nullable_to_non_nullable
as double?,gradeDistributionByLane: null == gradeDistributionByLane ? _self.gradeDistributionByLane : gradeDistributionByLane // ignore: cast_nullable_to_non_nullable
as Map<String, Map<LedgerGrade, int>>,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}
/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FalseFMetricsCopyWith<$Res> get falseFs {
  
  return $FalseFMetricsCopyWith<$Res>(_self.falseFs, (value) {
    return _then(_self.copyWith(falseFs: value));
  });
}/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CacheTokenTotalsCopyWith<$Res> get cacheTokens {
  
  return $CacheTokenTotalsCopyWith<$Res>(_self.cacheTokens, (value) {
    return _then(_self.copyWith(cacheTokens: value));
  });
}/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LandedDeliveryTotalsCopyWith<$Res> get landedDeliveries {
  
  return $LandedDeliveryTotalsCopyWith<$Res>(_self.landedDeliveries, (value) {
    return _then(_self.copyWith(landedDeliveries: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionLedgerMetricsProjection].
extension SessionLedgerMetricsProjectionPatterns on SessionLedgerMetricsProjection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionLedgerMetricsProjection value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionLedgerMetricsProjection value)  $default,){
final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionLedgerMetricsProjection value)?  $default,){
final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Map<String, LedgerSessionMetrics> sessionsById,  Map<String, List<LedgerSessionMetrics>> sessionsByLane,  FalseFMetrics falseFs,  CacheTokenTotals cacheTokens,  double? cacheHitRatio,  Map<String, int> reworkRoundsByWorkBead,  LandedDeliveryTotals landedDeliveries,  double? costPerLandedDelivery,  Map<String, Map<LedgerGrade, int>> gradeDistributionByLane,  List<MetricsDecodeIssue> issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection() when $default != null:
return $default(_that.sessionsById,_that.sessionsByLane,_that.falseFs,_that.cacheTokens,_that.cacheHitRatio,_that.reworkRoundsByWorkBead,_that.landedDeliveries,_that.costPerLandedDelivery,_that.gradeDistributionByLane,_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Map<String, LedgerSessionMetrics> sessionsById,  Map<String, List<LedgerSessionMetrics>> sessionsByLane,  FalseFMetrics falseFs,  CacheTokenTotals cacheTokens,  double? cacheHitRatio,  Map<String, int> reworkRoundsByWorkBead,  LandedDeliveryTotals landedDeliveries,  double? costPerLandedDelivery,  Map<String, Map<LedgerGrade, int>> gradeDistributionByLane,  List<MetricsDecodeIssue> issues)  $default,) {final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection():
return $default(_that.sessionsById,_that.sessionsByLane,_that.falseFs,_that.cacheTokens,_that.cacheHitRatio,_that.reworkRoundsByWorkBead,_that.landedDeliveries,_that.costPerLandedDelivery,_that.gradeDistributionByLane,_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Map<String, LedgerSessionMetrics> sessionsById,  Map<String, List<LedgerSessionMetrics>> sessionsByLane,  FalseFMetrics falseFs,  CacheTokenTotals cacheTokens,  double? cacheHitRatio,  Map<String, int> reworkRoundsByWorkBead,  LandedDeliveryTotals landedDeliveries,  double? costPerLandedDelivery,  Map<String, Map<LedgerGrade, int>> gradeDistributionByLane,  List<MetricsDecodeIssue> issues)?  $default,) {final _that = this;
switch (_that) {
case _SessionLedgerMetricsProjection() when $default != null:
return $default(_that.sessionsById,_that.sessionsByLane,_that.falseFs,_that.cacheTokens,_that.cacheHitRatio,_that.reworkRoundsByWorkBead,_that.landedDeliveries,_that.costPerLandedDelivery,_that.gradeDistributionByLane,_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _SessionLedgerMetricsProjection implements SessionLedgerMetricsProjection {
  const _SessionLedgerMetricsProjection({final  Map<String, LedgerSessionMetrics> sessionsById = const <String, LedgerSessionMetrics>{}, final  Map<String, List<LedgerSessionMetrics>> sessionsByLane = const <String, List<LedgerSessionMetrics>>{}, this.falseFs = const FalseFMetrics(), this.cacheTokens = const CacheTokenTotals(), this.cacheHitRatio, final  Map<String, int> reworkRoundsByWorkBead = const <String, int>{}, this.landedDeliveries = const LandedDeliveryTotals(), this.costPerLandedDelivery, final  Map<String, Map<LedgerGrade, int>> gradeDistributionByLane = const <String, Map<LedgerGrade, int>>{}, final  List<MetricsDecodeIssue> issues = const <MetricsDecodeIssue>[]}): _sessionsById = sessionsById,_sessionsByLane = sessionsByLane,_reworkRoundsByWorkBead = reworkRoundsByWorkBead,_gradeDistributionByLane = gradeDistributionByLane,_issues = issues;
  

 final  Map<String, LedgerSessionMetrics> _sessionsById;
@override@JsonKey() Map<String, LedgerSessionMetrics> get sessionsById {
  if (_sessionsById is EqualUnmodifiableMapView) return _sessionsById;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_sessionsById);
}

 final  Map<String, List<LedgerSessionMetrics>> _sessionsByLane;
@override@JsonKey() Map<String, List<LedgerSessionMetrics>> get sessionsByLane {
  if (_sessionsByLane is EqualUnmodifiableMapView) return _sessionsByLane;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_sessionsByLane);
}

@override@JsonKey() final  FalseFMetrics falseFs;
/// Components used to derive [cacheHitRatio].
@override@JsonKey() final  CacheTokenTotals cacheTokens;
@override final  double? cacheHitRatio;
 final  Map<String, int> _reworkRoundsByWorkBead;
@override@JsonKey() Map<String, int> get reworkRoundsByWorkBead {
  if (_reworkRoundsByWorkBead is EqualUnmodifiableMapView) return _reworkRoundsByWorkBead;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_reworkRoundsByWorkBead);
}

/// Components used to derive [costPerLandedDelivery].
@override@JsonKey() final  LandedDeliveryTotals landedDeliveries;
@override final  double? costPerLandedDelivery;
 final  Map<String, Map<LedgerGrade, int>> _gradeDistributionByLane;
@override@JsonKey() Map<String, Map<LedgerGrade, int>> get gradeDistributionByLane {
  if (_gradeDistributionByLane is EqualUnmodifiableMapView) return _gradeDistributionByLane;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_gradeDistributionByLane);
}

 final  List<MetricsDecodeIssue> _issues;
@override@JsonKey() List<MetricsDecodeIssue> get issues {
  if (_issues is EqualUnmodifiableListView) return _issues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_issues);
}


/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionLedgerMetricsProjectionCopyWith<_SessionLedgerMetricsProjection> get copyWith => __$SessionLedgerMetricsProjectionCopyWithImpl<_SessionLedgerMetricsProjection>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionLedgerMetricsProjection&&const DeepCollectionEquality().equals(other._sessionsById, _sessionsById)&&const DeepCollectionEquality().equals(other._sessionsByLane, _sessionsByLane)&&(identical(other.falseFs, falseFs) || other.falseFs == falseFs)&&(identical(other.cacheTokens, cacheTokens) || other.cacheTokens == cacheTokens)&&(identical(other.cacheHitRatio, cacheHitRatio) || other.cacheHitRatio == cacheHitRatio)&&const DeepCollectionEquality().equals(other._reworkRoundsByWorkBead, _reworkRoundsByWorkBead)&&(identical(other.landedDeliveries, landedDeliveries) || other.landedDeliveries == landedDeliveries)&&(identical(other.costPerLandedDelivery, costPerLandedDelivery) || other.costPerLandedDelivery == costPerLandedDelivery)&&const DeepCollectionEquality().equals(other._gradeDistributionByLane, _gradeDistributionByLane)&&const DeepCollectionEquality().equals(other._issues, _issues));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_sessionsById),const DeepCollectionEquality().hash(_sessionsByLane),falseFs,cacheTokens,cacheHitRatio,const DeepCollectionEquality().hash(_reworkRoundsByWorkBead),landedDeliveries,costPerLandedDelivery,const DeepCollectionEquality().hash(_gradeDistributionByLane),const DeepCollectionEquality().hash(_issues));

@override
String toString() {
  return 'SessionLedgerMetricsProjection(sessionsById: $sessionsById, sessionsByLane: $sessionsByLane, falseFs: $falseFs, cacheTokens: $cacheTokens, cacheHitRatio: $cacheHitRatio, reworkRoundsByWorkBead: $reworkRoundsByWorkBead, landedDeliveries: $landedDeliveries, costPerLandedDelivery: $costPerLandedDelivery, gradeDistributionByLane: $gradeDistributionByLane, issues: $issues)';
}


}

/// @nodoc
abstract mixin class _$SessionLedgerMetricsProjectionCopyWith<$Res> implements $SessionLedgerMetricsProjectionCopyWith<$Res> {
  factory _$SessionLedgerMetricsProjectionCopyWith(_SessionLedgerMetricsProjection value, $Res Function(_SessionLedgerMetricsProjection) _then) = __$SessionLedgerMetricsProjectionCopyWithImpl;
@override @useResult
$Res call({
 Map<String, LedgerSessionMetrics> sessionsById, Map<String, List<LedgerSessionMetrics>> sessionsByLane, FalseFMetrics falseFs, CacheTokenTotals cacheTokens, double? cacheHitRatio, Map<String, int> reworkRoundsByWorkBead, LandedDeliveryTotals landedDeliveries, double? costPerLandedDelivery, Map<String, Map<LedgerGrade, int>> gradeDistributionByLane, List<MetricsDecodeIssue> issues
});


@override $FalseFMetricsCopyWith<$Res> get falseFs;@override $CacheTokenTotalsCopyWith<$Res> get cacheTokens;@override $LandedDeliveryTotalsCopyWith<$Res> get landedDeliveries;

}
/// @nodoc
class __$SessionLedgerMetricsProjectionCopyWithImpl<$Res>
    implements _$SessionLedgerMetricsProjectionCopyWith<$Res> {
  __$SessionLedgerMetricsProjectionCopyWithImpl(this._self, this._then);

  final _SessionLedgerMetricsProjection _self;
  final $Res Function(_SessionLedgerMetricsProjection) _then;

/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sessionsById = null,Object? sessionsByLane = null,Object? falseFs = null,Object? cacheTokens = null,Object? cacheHitRatio = freezed,Object? reworkRoundsByWorkBead = null,Object? landedDeliveries = null,Object? costPerLandedDelivery = freezed,Object? gradeDistributionByLane = null,Object? issues = null,}) {
  return _then(_SessionLedgerMetricsProjection(
sessionsById: null == sessionsById ? _self._sessionsById : sessionsById // ignore: cast_nullable_to_non_nullable
as Map<String, LedgerSessionMetrics>,sessionsByLane: null == sessionsByLane ? _self._sessionsByLane : sessionsByLane // ignore: cast_nullable_to_non_nullable
as Map<String, List<LedgerSessionMetrics>>,falseFs: null == falseFs ? _self.falseFs : falseFs // ignore: cast_nullable_to_non_nullable
as FalseFMetrics,cacheTokens: null == cacheTokens ? _self.cacheTokens : cacheTokens // ignore: cast_nullable_to_non_nullable
as CacheTokenTotals,cacheHitRatio: freezed == cacheHitRatio ? _self.cacheHitRatio : cacheHitRatio // ignore: cast_nullable_to_non_nullable
as double?,reworkRoundsByWorkBead: null == reworkRoundsByWorkBead ? _self._reworkRoundsByWorkBead : reworkRoundsByWorkBead // ignore: cast_nullable_to_non_nullable
as Map<String, int>,landedDeliveries: null == landedDeliveries ? _self.landedDeliveries : landedDeliveries // ignore: cast_nullable_to_non_nullable
as LandedDeliveryTotals,costPerLandedDelivery: freezed == costPerLandedDelivery ? _self.costPerLandedDelivery : costPerLandedDelivery // ignore: cast_nullable_to_non_nullable
as double?,gradeDistributionByLane: null == gradeDistributionByLane ? _self._gradeDistributionByLane : gradeDistributionByLane // ignore: cast_nullable_to_non_nullable
as Map<String, Map<LedgerGrade, int>>,issues: null == issues ? _self._issues : issues // ignore: cast_nullable_to_non_nullable
as List<MetricsDecodeIssue>,
  ));
}

/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FalseFMetricsCopyWith<$Res> get falseFs {
  
  return $FalseFMetricsCopyWith<$Res>(_self.falseFs, (value) {
    return _then(_self.copyWith(falseFs: value));
  });
}/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CacheTokenTotalsCopyWith<$Res> get cacheTokens {
  
  return $CacheTokenTotalsCopyWith<$Res>(_self.cacheTokens, (value) {
    return _then(_self.copyWith(cacheTokens: value));
  });
}/// Create a copy of SessionLedgerMetricsProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LandedDeliveryTotalsCopyWith<$Res> get landedDeliveries {
  
  return $LandedDeliveryTotalsCopyWith<$Res>(_self.landedDeliveries, (value) {
    return _then(_self.copyWith(landedDeliveries: value));
  });
}
}

// dart format on
