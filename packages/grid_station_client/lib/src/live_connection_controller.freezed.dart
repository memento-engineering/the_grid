// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'live_connection_controller.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LiveConnectionState implements DiagnosticableTreeMixin {




@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState()';
}


}

/// @nodoc
class $LiveConnectionStateCopyWith<$Res>  {
$LiveConnectionStateCopyWith(LiveConnectionState _, $Res Function(LiveConnectionState) __);
}


/// Adds pattern-matching-related methods to [LiveConnectionState].
extension LiveConnectionStatePatterns on LiveConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LiveDisconnected value)?  disconnected,TResult Function( LiveDiscovering value)?  discovering,TResult Function( LiveManual value)?  manual,TResult Function( LiveConnecting value)?  connecting,TResult Function( LiveConnected value)?  connected,TResult Function( LiveFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LiveDisconnected() when disconnected != null:
return disconnected(_that);case LiveDiscovering() when discovering != null:
return discovering(_that);case LiveManual() when manual != null:
return manual(_that);case LiveConnecting() when connecting != null:
return connecting(_that);case LiveConnected() when connected != null:
return connected(_that);case LiveFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LiveDisconnected value)  disconnected,required TResult Function( LiveDiscovering value)  discovering,required TResult Function( LiveManual value)  manual,required TResult Function( LiveConnecting value)  connecting,required TResult Function( LiveConnected value)  connected,required TResult Function( LiveFailed value)  failed,}){
final _that = this;
switch (_that) {
case LiveDisconnected():
return disconnected(_that);case LiveDiscovering():
return discovering(_that);case LiveManual():
return manual(_that);case LiveConnecting():
return connecting(_that);case LiveConnected():
return connected(_that);case LiveFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LiveDisconnected value)?  disconnected,TResult? Function( LiveDiscovering value)?  discovering,TResult? Function( LiveManual value)?  manual,TResult? Function( LiveConnecting value)?  connecting,TResult? Function( LiveConnected value)?  connected,TResult? Function( LiveFailed value)?  failed,}){
final _that = this;
switch (_that) {
case LiveDisconnected() when disconnected != null:
return disconnected(_that);case LiveDiscovering() when discovering != null:
return discovering(_that);case LiveManual() when manual != null:
return manual(_that);case LiveConnecting() when connecting != null:
return connecting(_that);case LiveConnected() when connected != null:
return connected(_that);case LiveFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disconnected,TResult Function()?  discovering,TResult Function( String? message)?  manual,TResult Function()?  connecting,TResult Function( TreeSource source)?  connected,TResult Function( String message)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LiveDisconnected() when disconnected != null:
return disconnected();case LiveDiscovering() when discovering != null:
return discovering();case LiveManual() when manual != null:
return manual(_that.message);case LiveConnecting() when connecting != null:
return connecting();case LiveConnected() when connected != null:
return connected(_that.source);case LiveFailed() when failed != null:
return failed(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disconnected,required TResult Function()  discovering,required TResult Function( String? message)  manual,required TResult Function()  connecting,required TResult Function( TreeSource source)  connected,required TResult Function( String message)  failed,}) {final _that = this;
switch (_that) {
case LiveDisconnected():
return disconnected();case LiveDiscovering():
return discovering();case LiveManual():
return manual(_that.message);case LiveConnecting():
return connecting();case LiveConnected():
return connected(_that.source);case LiveFailed():
return failed(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disconnected,TResult? Function()?  discovering,TResult? Function( String? message)?  manual,TResult? Function()?  connecting,TResult? Function( TreeSource source)?  connected,TResult? Function( String message)?  failed,}) {final _that = this;
switch (_that) {
case LiveDisconnected() when disconnected != null:
return disconnected();case LiveDiscovering() when discovering != null:
return discovering();case LiveManual() when manual != null:
return manual(_that.message);case LiveConnecting() when connecting != null:
return connecting();case LiveConnected() when connected != null:
return connected(_that.source);case LiveFailed() when failed != null:
return failed(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class LiveDisconnected with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveDisconnected();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.disconnected'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveDisconnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.disconnected()';
}


}




/// @nodoc


class LiveDiscovering with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveDiscovering();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.discovering'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveDiscovering);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.discovering()';
}


}




/// @nodoc


class LiveManual with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveManual({this.message});


 final  String? message;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveManualCopyWith<LiveManual> get copyWith => _$LiveManualCopyWithImpl<LiveManual>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.manual'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveManual&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.manual(message: $message)';
}


}

/// @nodoc
abstract mixin class $LiveManualCopyWith<$Res> implements $LiveConnectionStateCopyWith<$Res> {
  factory $LiveManualCopyWith(LiveManual value, $Res Function(LiveManual) _then) = _$LiveManualCopyWithImpl;
@useResult
$Res call({
 String? message
});




}
/// @nodoc
class _$LiveManualCopyWithImpl<$Res>
    implements $LiveManualCopyWith<$Res> {
  _$LiveManualCopyWithImpl(this._self, this._then);

  final LiveManual _self;
  final $Res Function(LiveManual) _then;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = freezed,}) {
  return _then(LiveManual(
message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class LiveConnecting with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveConnecting();






@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.connecting'))
    ;
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveConnecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.connecting()';
}


}




/// @nodoc


class LiveConnected with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveConnected({required this.source});


 final  TreeSource source;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveConnectedCopyWith<LiveConnected> get copyWith => _$LiveConnectedCopyWithImpl<LiveConnected>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.connected'))
    ..add(DiagnosticsProperty('source', source));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveConnected&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,source);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.connected(source: $source)';
}


}

/// @nodoc
abstract mixin class $LiveConnectedCopyWith<$Res> implements $LiveConnectionStateCopyWith<$Res> {
  factory $LiveConnectedCopyWith(LiveConnected value, $Res Function(LiveConnected) _then) = _$LiveConnectedCopyWithImpl;
@useResult
$Res call({
 TreeSource source
});




}
/// @nodoc
class _$LiveConnectedCopyWithImpl<$Res>
    implements $LiveConnectedCopyWith<$Res> {
  _$LiveConnectedCopyWithImpl(this._self, this._then);

  final LiveConnected _self;
  final $Res Function(LiveConnected) _then;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? source = null,}) {
  return _then(LiveConnected(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as TreeSource,
  ));
}


}

/// @nodoc


class LiveFailed with DiagnosticableTreeMixin implements LiveConnectionState {
  const LiveFailed({required this.message});


 final  String message;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveFailedCopyWith<LiveFailed> get copyWith => _$LiveFailedCopyWithImpl<LiveFailed>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LiveConnectionState.failed'))
    ..add(DiagnosticsProperty('message', message));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveFailed&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LiveConnectionState.failed(message: $message)';
}


}

/// @nodoc
abstract mixin class $LiveFailedCopyWith<$Res> implements $LiveConnectionStateCopyWith<$Res> {
  factory $LiveFailedCopyWith(LiveFailed value, $Res Function(LiveFailed) _then) = _$LiveFailedCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$LiveFailedCopyWithImpl<$Res>
    implements $LiveFailedCopyWith<$Res> {
  _$LiveFailedCopyWithImpl(this._self, this._then);

  final LiveFailed _self;
  final $Res Function(LiveFailed) _then;

/// Create a copy of LiveConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(LiveFailed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
