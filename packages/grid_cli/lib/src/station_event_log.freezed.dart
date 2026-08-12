// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'station_event_log.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StationEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'StationEvent()';
}


}




/// Adds pattern-matching-related methods to [StationEvent].
extension StationEventPatterns on StationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionMintedEvent value)?  sessionMinted,TResult Function( GateOpenedEvent value)?  gateOpened,TResult Function( SessionClosedEvent value)?  sessionClosed,TResult Function( GenericStationEvent value)?  generic,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionMintedEvent() when sessionMinted != null:
return sessionMinted(_that);case GateOpenedEvent() when gateOpened != null:
return gateOpened(_that);case SessionClosedEvent() when sessionClosed != null:
return sessionClosed(_that);case GenericStationEvent() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionMintedEvent value)  sessionMinted,required TResult Function( GateOpenedEvent value)  gateOpened,required TResult Function( SessionClosedEvent value)  sessionClosed,required TResult Function( GenericStationEvent value)  generic,}){
final _that = this;
switch (_that) {
case SessionMintedEvent():
return sessionMinted(_that);case GateOpenedEvent():
return gateOpened(_that);case SessionClosedEvent():
return sessionClosed(_that);case GenericStationEvent():
return generic(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionMintedEvent value)?  sessionMinted,TResult? Function( GateOpenedEvent value)?  gateOpened,TResult? Function( SessionClosedEvent value)?  sessionClosed,TResult? Function( GenericStationEvent value)?  generic,}){
final _that = this;
switch (_that) {
case SessionMintedEvent() when sessionMinted != null:
return sessionMinted(_that);case GateOpenedEvent() when gateOpened != null:
return gateOpened(_that);case SessionClosedEvent() when sessionClosed != null:
return sessionClosed(_that);case GenericStationEvent() when generic != null:
return generic(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String sessionId,  String workBeadId)?  sessionMinted,TResult Function( String gateId,  String sessionId,  String nodePath,  String reason,  bool reused)?  gateOpened,TResult Function( String sessionId,  SessionDisposition disposition)?  sessionClosed,TResult Function( String name,  Map<String, String> data)?  generic,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionMintedEvent() when sessionMinted != null:
return sessionMinted(_that.sessionId,_that.workBeadId);case GateOpenedEvent() when gateOpened != null:
return gateOpened(_that.gateId,_that.sessionId,_that.nodePath,_that.reason,_that.reused);case SessionClosedEvent() when sessionClosed != null:
return sessionClosed(_that.sessionId,_that.disposition);case GenericStationEvent() when generic != null:
return generic(_that.name,_that.data);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String sessionId,  String workBeadId)  sessionMinted,required TResult Function( String gateId,  String sessionId,  String nodePath,  String reason,  bool reused)  gateOpened,required TResult Function( String sessionId,  SessionDisposition disposition)  sessionClosed,required TResult Function( String name,  Map<String, String> data)  generic,}) {final _that = this;
switch (_that) {
case SessionMintedEvent():
return sessionMinted(_that.sessionId,_that.workBeadId);case GateOpenedEvent():
return gateOpened(_that.gateId,_that.sessionId,_that.nodePath,_that.reason,_that.reused);case SessionClosedEvent():
return sessionClosed(_that.sessionId,_that.disposition);case GenericStationEvent():
return generic(_that.name,_that.data);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String sessionId,  String workBeadId)?  sessionMinted,TResult? Function( String gateId,  String sessionId,  String nodePath,  String reason,  bool reused)?  gateOpened,TResult? Function( String sessionId,  SessionDisposition disposition)?  sessionClosed,TResult? Function( String name,  Map<String, String> data)?  generic,}) {final _that = this;
switch (_that) {
case SessionMintedEvent() when sessionMinted != null:
return sessionMinted(_that.sessionId,_that.workBeadId);case GateOpenedEvent() when gateOpened != null:
return gateOpened(_that.gateId,_that.sessionId,_that.nodePath,_that.reason,_that.reused);case SessionClosedEvent() when sessionClosed != null:
return sessionClosed(_that.sessionId,_that.disposition);case GenericStationEvent() when generic != null:
return generic(_that.name,_that.data);case _:
  return null;

}
}

}

/// @nodoc


class SessionMintedEvent implements StationEvent {
  const SessionMintedEvent({required this.sessionId, required this.workBeadId});
  

 final  String sessionId;
 final  String workBeadId;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionMintedEvent&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.workBeadId, workBeadId) || other.workBeadId == workBeadId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,workBeadId);

@override
String toString() {
  return 'StationEvent.sessionMinted(sessionId: $sessionId, workBeadId: $workBeadId)';
}


}




/// @nodoc


class GateOpenedEvent implements StationEvent {
  const GateOpenedEvent({required this.gateId, required this.sessionId, required this.nodePath, required this.reason, required this.reused});
  

 final  String gateId;
 final  String sessionId;
 final  String nodePath;
 final  String reason;
 final  bool reused;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GateOpenedEvent&&(identical(other.gateId, gateId) || other.gateId == gateId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.nodePath, nodePath) || other.nodePath == nodePath)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.reused, reused) || other.reused == reused));
}


@override
int get hashCode => Object.hash(runtimeType,gateId,sessionId,nodePath,reason,reused);

@override
String toString() {
  return 'StationEvent.gateOpened(gateId: $gateId, sessionId: $sessionId, nodePath: $nodePath, reason: $reason, reused: $reused)';
}


}




/// @nodoc


class SessionClosedEvent implements StationEvent {
  const SessionClosedEvent({required this.sessionId, required this.disposition});
  

 final  String sessionId;
 final  SessionDisposition disposition;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionClosedEvent&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.disposition, disposition) || other.disposition == disposition));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,disposition);

@override
String toString() {
  return 'StationEvent.sessionClosed(sessionId: $sessionId, disposition: $disposition)';
}


}




/// @nodoc


class GenericStationEvent implements StationEvent {
  const GenericStationEvent({required this.name, required final  Map<String, String> data}): _data = data;
  

 final  String name;
 final  Map<String, String> _data;
 Map<String, String> get data {
  if (_data is EqualUnmodifiableMapView) return _data;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_data);
}





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GenericStationEvent&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other._data, _data));
}


@override
int get hashCode => Object.hash(runtimeType,name,const DeepCollectionEquality().hash(_data));

@override
String toString() {
  return 'StationEvent.generic(name: $name, data: $data)';
}


}




/// @nodoc
mixin _$StationEventRecord {

 int get cursor; DateTime get timestamp; StationEvent get event;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StationEventRecord&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,cursor,timestamp,event);

@override
String toString() {
  return 'StationEventRecord(cursor: $cursor, timestamp: $timestamp, event: $event)';
}


}




/// Adds pattern-matching-related methods to [StationEventRecord].
extension StationEventRecordPatterns on StationEventRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StationEventRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StationEventRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StationEventRecord value)  $default,){
final _that = this;
switch (_that) {
case _StationEventRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StationEventRecord value)?  $default,){
final _that = this;
switch (_that) {
case _StationEventRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int cursor,  DateTime timestamp,  StationEvent event)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StationEventRecord() when $default != null:
return $default(_that.cursor,_that.timestamp,_that.event);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int cursor,  DateTime timestamp,  StationEvent event)  $default,) {final _that = this;
switch (_that) {
case _StationEventRecord():
return $default(_that.cursor,_that.timestamp,_that.event);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int cursor,  DateTime timestamp,  StationEvent event)?  $default,) {final _that = this;
switch (_that) {
case _StationEventRecord() when $default != null:
return $default(_that.cursor,_that.timestamp,_that.event);case _:
  return null;

}
}

}

/// @nodoc


class _StationEventRecord implements StationEventRecord {
  const _StationEventRecord({required this.cursor, required this.timestamp, required this.event});
  

@override final  int cursor;
@override final  DateTime timestamp;
@override final  StationEvent event;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _StationEventRecord&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,cursor,timestamp,event);

@override
String toString() {
  return 'StationEventRecord(cursor: $cursor, timestamp: $timestamp, event: $event)';
}


}




// dart format on
