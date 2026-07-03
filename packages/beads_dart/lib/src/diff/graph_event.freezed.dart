// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'graph_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GraphEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GraphEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GraphEvent()';
}


}

/// @nodoc
class $GraphEventCopyWith<$Res>  {
$GraphEventCopyWith(GraphEvent _, $Res Function(GraphEvent) __);
}


/// Adds pattern-matching-related methods to [GraphEvent].
extension GraphEventPatterns on GraphEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SnapshotInitialized value)?  snapshotInitialized,TResult Function( BeadCreated value)?  beadCreated,TResult Function( BeadUpdated value)?  beadUpdated,TResult Function( BeadClosed value)?  beadClosed,TResult Function( BeadReopened value)?  beadReopened,TResult Function( BeadDeleted value)?  beadDeleted,TResult Function( DependencyAdded value)?  dependencyAdded,TResult Function( DependencyRemoved value)?  dependencyRemoved,TResult Function( ReadySetChanged value)?  readySetChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SnapshotInitialized() when snapshotInitialized != null:
return snapshotInitialized(_that);case BeadCreated() when beadCreated != null:
return beadCreated(_that);case BeadUpdated() when beadUpdated != null:
return beadUpdated(_that);case BeadClosed() when beadClosed != null:
return beadClosed(_that);case BeadReopened() when beadReopened != null:
return beadReopened(_that);case BeadDeleted() when beadDeleted != null:
return beadDeleted(_that);case DependencyAdded() when dependencyAdded != null:
return dependencyAdded(_that);case DependencyRemoved() when dependencyRemoved != null:
return dependencyRemoved(_that);case ReadySetChanged() when readySetChanged != null:
return readySetChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SnapshotInitialized value)  snapshotInitialized,required TResult Function( BeadCreated value)  beadCreated,required TResult Function( BeadUpdated value)  beadUpdated,required TResult Function( BeadClosed value)  beadClosed,required TResult Function( BeadReopened value)  beadReopened,required TResult Function( BeadDeleted value)  beadDeleted,required TResult Function( DependencyAdded value)  dependencyAdded,required TResult Function( DependencyRemoved value)  dependencyRemoved,required TResult Function( ReadySetChanged value)  readySetChanged,}){
final _that = this;
switch (_that) {
case SnapshotInitialized():
return snapshotInitialized(_that);case BeadCreated():
return beadCreated(_that);case BeadUpdated():
return beadUpdated(_that);case BeadClosed():
return beadClosed(_that);case BeadReopened():
return beadReopened(_that);case BeadDeleted():
return beadDeleted(_that);case DependencyAdded():
return dependencyAdded(_that);case DependencyRemoved():
return dependencyRemoved(_that);case ReadySetChanged():
return readySetChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SnapshotInitialized value)?  snapshotInitialized,TResult? Function( BeadCreated value)?  beadCreated,TResult? Function( BeadUpdated value)?  beadUpdated,TResult? Function( BeadClosed value)?  beadClosed,TResult? Function( BeadReopened value)?  beadReopened,TResult? Function( BeadDeleted value)?  beadDeleted,TResult? Function( DependencyAdded value)?  dependencyAdded,TResult? Function( DependencyRemoved value)?  dependencyRemoved,TResult? Function( ReadySetChanged value)?  readySetChanged,}){
final _that = this;
switch (_that) {
case SnapshotInitialized() when snapshotInitialized != null:
return snapshotInitialized(_that);case BeadCreated() when beadCreated != null:
return beadCreated(_that);case BeadUpdated() when beadUpdated != null:
return beadUpdated(_that);case BeadClosed() when beadClosed != null:
return beadClosed(_that);case BeadReopened() when beadReopened != null:
return beadReopened(_that);case BeadDeleted() when beadDeleted != null:
return beadDeleted(_that);case DependencyAdded() when dependencyAdded != null:
return dependencyAdded(_that);case DependencyRemoved() when dependencyRemoved != null:
return dependencyRemoved(_that);case ReadySetChanged() when readySetChanged != null:
return readySetChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int beadCount,  int readyCount)?  snapshotInitialized,TResult Function( Bead bead)?  beadCreated,TResult Function( Bead before,  Bead after,  Set<String> changedFields)?  beadUpdated,TResult Function( Bead before,  Bead after)?  beadClosed,TResult Function( Bead before,  Bead after)?  beadReopened,TResult Function( Bead bead)?  beadDeleted,TResult Function( BeadDependency dependency)?  dependencyAdded,TResult Function( BeadDependency dependency)?  dependencyRemoved,TResult Function( Set<String> entered,  Set<String> exited)?  readySetChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SnapshotInitialized() when snapshotInitialized != null:
return snapshotInitialized(_that.beadCount,_that.readyCount);case BeadCreated() when beadCreated != null:
return beadCreated(_that.bead);case BeadUpdated() when beadUpdated != null:
return beadUpdated(_that.before,_that.after,_that.changedFields);case BeadClosed() when beadClosed != null:
return beadClosed(_that.before,_that.after);case BeadReopened() when beadReopened != null:
return beadReopened(_that.before,_that.after);case BeadDeleted() when beadDeleted != null:
return beadDeleted(_that.bead);case DependencyAdded() when dependencyAdded != null:
return dependencyAdded(_that.dependency);case DependencyRemoved() when dependencyRemoved != null:
return dependencyRemoved(_that.dependency);case ReadySetChanged() when readySetChanged != null:
return readySetChanged(_that.entered,_that.exited);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int beadCount,  int readyCount)  snapshotInitialized,required TResult Function( Bead bead)  beadCreated,required TResult Function( Bead before,  Bead after,  Set<String> changedFields)  beadUpdated,required TResult Function( Bead before,  Bead after)  beadClosed,required TResult Function( Bead before,  Bead after)  beadReopened,required TResult Function( Bead bead)  beadDeleted,required TResult Function( BeadDependency dependency)  dependencyAdded,required TResult Function( BeadDependency dependency)  dependencyRemoved,required TResult Function( Set<String> entered,  Set<String> exited)  readySetChanged,}) {final _that = this;
switch (_that) {
case SnapshotInitialized():
return snapshotInitialized(_that.beadCount,_that.readyCount);case BeadCreated():
return beadCreated(_that.bead);case BeadUpdated():
return beadUpdated(_that.before,_that.after,_that.changedFields);case BeadClosed():
return beadClosed(_that.before,_that.after);case BeadReopened():
return beadReopened(_that.before,_that.after);case BeadDeleted():
return beadDeleted(_that.bead);case DependencyAdded():
return dependencyAdded(_that.dependency);case DependencyRemoved():
return dependencyRemoved(_that.dependency);case ReadySetChanged():
return readySetChanged(_that.entered,_that.exited);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int beadCount,  int readyCount)?  snapshotInitialized,TResult? Function( Bead bead)?  beadCreated,TResult? Function( Bead before,  Bead after,  Set<String> changedFields)?  beadUpdated,TResult? Function( Bead before,  Bead after)?  beadClosed,TResult? Function( Bead before,  Bead after)?  beadReopened,TResult? Function( Bead bead)?  beadDeleted,TResult? Function( BeadDependency dependency)?  dependencyAdded,TResult? Function( BeadDependency dependency)?  dependencyRemoved,TResult? Function( Set<String> entered,  Set<String> exited)?  readySetChanged,}) {final _that = this;
switch (_that) {
case SnapshotInitialized() when snapshotInitialized != null:
return snapshotInitialized(_that.beadCount,_that.readyCount);case BeadCreated() when beadCreated != null:
return beadCreated(_that.bead);case BeadUpdated() when beadUpdated != null:
return beadUpdated(_that.before,_that.after,_that.changedFields);case BeadClosed() when beadClosed != null:
return beadClosed(_that.before,_that.after);case BeadReopened() when beadReopened != null:
return beadReopened(_that.before,_that.after);case BeadDeleted() when beadDeleted != null:
return beadDeleted(_that.bead);case DependencyAdded() when dependencyAdded != null:
return dependencyAdded(_that.dependency);case DependencyRemoved() when dependencyRemoved != null:
return dependencyRemoved(_that.dependency);case ReadySetChanged() when readySetChanged != null:
return readySetChanged(_that.entered,_that.exited);case _:
  return null;

}
}

}

/// @nodoc


class SnapshotInitialized extends GraphEvent {
  const SnapshotInitialized({required this.beadCount, required this.readyCount}): super._();
  

 final  int beadCount;
 final  int readyCount;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SnapshotInitializedCopyWith<SnapshotInitialized> get copyWith => _$SnapshotInitializedCopyWithImpl<SnapshotInitialized>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SnapshotInitialized&&(identical(other.beadCount, beadCount) || other.beadCount == beadCount)&&(identical(other.readyCount, readyCount) || other.readyCount == readyCount));
}


@override
int get hashCode => Object.hash(runtimeType,beadCount,readyCount);

@override
String toString() {
  return 'GraphEvent.snapshotInitialized(beadCount: $beadCount, readyCount: $readyCount)';
}


}

/// @nodoc
abstract mixin class $SnapshotInitializedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $SnapshotInitializedCopyWith(SnapshotInitialized value, $Res Function(SnapshotInitialized) _then) = _$SnapshotInitializedCopyWithImpl;
@useResult
$Res call({
 int beadCount, int readyCount
});




}
/// @nodoc
class _$SnapshotInitializedCopyWithImpl<$Res>
    implements $SnapshotInitializedCopyWith<$Res> {
  _$SnapshotInitializedCopyWithImpl(this._self, this._then);

  final SnapshotInitialized _self;
  final $Res Function(SnapshotInitialized) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beadCount = null,Object? readyCount = null,}) {
  return _then(SnapshotInitialized(
beadCount: null == beadCount ? _self.beadCount : beadCount // ignore: cast_nullable_to_non_nullable
as int,readyCount: null == readyCount ? _self.readyCount : readyCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BeadCreated extends GraphEvent {
  const BeadCreated(this.bead): super._();
  

 final  Bead bead;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadCreatedCopyWith<BeadCreated> get copyWith => _$BeadCreatedCopyWithImpl<BeadCreated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadCreated&&(identical(other.bead, bead) || other.bead == bead));
}


@override
int get hashCode => Object.hash(runtimeType,bead);

@override
String toString() {
  return 'GraphEvent.beadCreated(bead: $bead)';
}


}

/// @nodoc
abstract mixin class $BeadCreatedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $BeadCreatedCopyWith(BeadCreated value, $Res Function(BeadCreated) _then) = _$BeadCreatedCopyWithImpl;
@useResult
$Res call({
 Bead bead
});


$BeadCopyWith<$Res> get bead;

}
/// @nodoc
class _$BeadCreatedCopyWithImpl<$Res>
    implements $BeadCreatedCopyWith<$Res> {
  _$BeadCreatedCopyWithImpl(this._self, this._then);

  final BeadCreated _self;
  final $Res Function(BeadCreated) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bead = null,}) {
  return _then(BeadCreated(
null == bead ? _self.bead : bead // ignore: cast_nullable_to_non_nullable
as Bead,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get bead {
  
  return $BeadCopyWith<$Res>(_self.bead, (value) {
    return _then(_self.copyWith(bead: value));
  });
}
}

/// @nodoc


class BeadUpdated extends GraphEvent {
  const BeadUpdated({required this.before, required this.after, required final  Set<String> changedFields}): _changedFields = changedFields,super._();
  

 final  Bead before;
 final  Bead after;
 final  Set<String> _changedFields;
 Set<String> get changedFields {
  if (_changedFields is EqualUnmodifiableSetView) return _changedFields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_changedFields);
}


/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadUpdatedCopyWith<BeadUpdated> get copyWith => _$BeadUpdatedCopyWithImpl<BeadUpdated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadUpdated&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after)&&const DeepCollectionEquality().equals(other._changedFields, _changedFields));
}


@override
int get hashCode => Object.hash(runtimeType,before,after,const DeepCollectionEquality().hash(_changedFields));

@override
String toString() {
  return 'GraphEvent.beadUpdated(before: $before, after: $after, changedFields: $changedFields)';
}


}

/// @nodoc
abstract mixin class $BeadUpdatedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $BeadUpdatedCopyWith(BeadUpdated value, $Res Function(BeadUpdated) _then) = _$BeadUpdatedCopyWithImpl;
@useResult
$Res call({
 Bead before, Bead after, Set<String> changedFields
});


$BeadCopyWith<$Res> get before;$BeadCopyWith<$Res> get after;

}
/// @nodoc
class _$BeadUpdatedCopyWithImpl<$Res>
    implements $BeadUpdatedCopyWith<$Res> {
  _$BeadUpdatedCopyWithImpl(this._self, this._then);

  final BeadUpdated _self;
  final $Res Function(BeadUpdated) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? before = null,Object? after = null,Object? changedFields = null,}) {
  return _then(BeadUpdated(
before: null == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as Bead,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as Bead,changedFields: null == changedFields ? _self._changedFields : changedFields // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get before {
  
  return $BeadCopyWith<$Res>(_self.before, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get after {
  
  return $BeadCopyWith<$Res>(_self.after, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}

/// @nodoc


class BeadClosed extends GraphEvent {
  const BeadClosed({required this.before, required this.after}): super._();
  

 final  Bead before;
 final  Bead after;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadClosedCopyWith<BeadClosed> get copyWith => _$BeadClosedCopyWithImpl<BeadClosed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadClosed&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}


@override
int get hashCode => Object.hash(runtimeType,before,after);

@override
String toString() {
  return 'GraphEvent.beadClosed(before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class $BeadClosedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $BeadClosedCopyWith(BeadClosed value, $Res Function(BeadClosed) _then) = _$BeadClosedCopyWithImpl;
@useResult
$Res call({
 Bead before, Bead after
});


$BeadCopyWith<$Res> get before;$BeadCopyWith<$Res> get after;

}
/// @nodoc
class _$BeadClosedCopyWithImpl<$Res>
    implements $BeadClosedCopyWith<$Res> {
  _$BeadClosedCopyWithImpl(this._self, this._then);

  final BeadClosed _self;
  final $Res Function(BeadClosed) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? before = null,Object? after = null,}) {
  return _then(BeadClosed(
before: null == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as Bead,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as Bead,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get before {
  
  return $BeadCopyWith<$Res>(_self.before, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get after {
  
  return $BeadCopyWith<$Res>(_self.after, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}

/// @nodoc


class BeadReopened extends GraphEvent {
  const BeadReopened({required this.before, required this.after}): super._();
  

 final  Bead before;
 final  Bead after;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadReopenedCopyWith<BeadReopened> get copyWith => _$BeadReopenedCopyWithImpl<BeadReopened>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadReopened&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}


@override
int get hashCode => Object.hash(runtimeType,before,after);

@override
String toString() {
  return 'GraphEvent.beadReopened(before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class $BeadReopenedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $BeadReopenedCopyWith(BeadReopened value, $Res Function(BeadReopened) _then) = _$BeadReopenedCopyWithImpl;
@useResult
$Res call({
 Bead before, Bead after
});


$BeadCopyWith<$Res> get before;$BeadCopyWith<$Res> get after;

}
/// @nodoc
class _$BeadReopenedCopyWithImpl<$Res>
    implements $BeadReopenedCopyWith<$Res> {
  _$BeadReopenedCopyWithImpl(this._self, this._then);

  final BeadReopened _self;
  final $Res Function(BeadReopened) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? before = null,Object? after = null,}) {
  return _then(BeadReopened(
before: null == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as Bead,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as Bead,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get before {
  
  return $BeadCopyWith<$Res>(_self.before, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get after {
  
  return $BeadCopyWith<$Res>(_self.after, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}

/// @nodoc


class BeadDeleted extends GraphEvent {
  const BeadDeleted(this.bead): super._();
  

 final  Bead bead;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadDeletedCopyWith<BeadDeleted> get copyWith => _$BeadDeletedCopyWithImpl<BeadDeleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BeadDeleted&&(identical(other.bead, bead) || other.bead == bead));
}


@override
int get hashCode => Object.hash(runtimeType,bead);

@override
String toString() {
  return 'GraphEvent.beadDeleted(bead: $bead)';
}


}

/// @nodoc
abstract mixin class $BeadDeletedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $BeadDeletedCopyWith(BeadDeleted value, $Res Function(BeadDeleted) _then) = _$BeadDeletedCopyWithImpl;
@useResult
$Res call({
 Bead bead
});


$BeadCopyWith<$Res> get bead;

}
/// @nodoc
class _$BeadDeletedCopyWithImpl<$Res>
    implements $BeadDeletedCopyWith<$Res> {
  _$BeadDeletedCopyWithImpl(this._self, this._then);

  final BeadDeleted _self;
  final $Res Function(BeadDeleted) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bead = null,}) {
  return _then(BeadDeleted(
null == bead ? _self.bead : bead // ignore: cast_nullable_to_non_nullable
as Bead,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadCopyWith<$Res> get bead {
  
  return $BeadCopyWith<$Res>(_self.bead, (value) {
    return _then(_self.copyWith(bead: value));
  });
}
}

/// @nodoc


class DependencyAdded extends GraphEvent {
  const DependencyAdded(this.dependency): super._();
  

 final  BeadDependency dependency;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DependencyAddedCopyWith<DependencyAdded> get copyWith => _$DependencyAddedCopyWithImpl<DependencyAdded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DependencyAdded&&(identical(other.dependency, dependency) || other.dependency == dependency));
}


@override
int get hashCode => Object.hash(runtimeType,dependency);

@override
String toString() {
  return 'GraphEvent.dependencyAdded(dependency: $dependency)';
}


}

/// @nodoc
abstract mixin class $DependencyAddedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $DependencyAddedCopyWith(DependencyAdded value, $Res Function(DependencyAdded) _then) = _$DependencyAddedCopyWithImpl;
@useResult
$Res call({
 BeadDependency dependency
});


$BeadDependencyCopyWith<$Res> get dependency;

}
/// @nodoc
class _$DependencyAddedCopyWithImpl<$Res>
    implements $DependencyAddedCopyWith<$Res> {
  _$DependencyAddedCopyWithImpl(this._self, this._then);

  final DependencyAdded _self;
  final $Res Function(DependencyAdded) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dependency = null,}) {
  return _then(DependencyAdded(
null == dependency ? _self.dependency : dependency // ignore: cast_nullable_to_non_nullable
as BeadDependency,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadDependencyCopyWith<$Res> get dependency {
  
  return $BeadDependencyCopyWith<$Res>(_self.dependency, (value) {
    return _then(_self.copyWith(dependency: value));
  });
}
}

/// @nodoc


class DependencyRemoved extends GraphEvent {
  const DependencyRemoved(this.dependency): super._();
  

 final  BeadDependency dependency;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DependencyRemovedCopyWith<DependencyRemoved> get copyWith => _$DependencyRemovedCopyWithImpl<DependencyRemoved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DependencyRemoved&&(identical(other.dependency, dependency) || other.dependency == dependency));
}


@override
int get hashCode => Object.hash(runtimeType,dependency);

@override
String toString() {
  return 'GraphEvent.dependencyRemoved(dependency: $dependency)';
}


}

/// @nodoc
abstract mixin class $DependencyRemovedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $DependencyRemovedCopyWith(DependencyRemoved value, $Res Function(DependencyRemoved) _then) = _$DependencyRemovedCopyWithImpl;
@useResult
$Res call({
 BeadDependency dependency
});


$BeadDependencyCopyWith<$Res> get dependency;

}
/// @nodoc
class _$DependencyRemovedCopyWithImpl<$Res>
    implements $DependencyRemovedCopyWith<$Res> {
  _$DependencyRemovedCopyWithImpl(this._self, this._then);

  final DependencyRemoved _self;
  final $Res Function(DependencyRemoved) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? dependency = null,}) {
  return _then(DependencyRemoved(
null == dependency ? _self.dependency : dependency // ignore: cast_nullable_to_non_nullable
as BeadDependency,
  ));
}

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BeadDependencyCopyWith<$Res> get dependency {
  
  return $BeadDependencyCopyWith<$Res>(_self.dependency, (value) {
    return _then(_self.copyWith(dependency: value));
  });
}
}

/// @nodoc


class ReadySetChanged extends GraphEvent {
  const ReadySetChanged({required final  Set<String> entered, required final  Set<String> exited}): _entered = entered,_exited = exited,super._();
  

 final  Set<String> _entered;
 Set<String> get entered {
  if (_entered is EqualUnmodifiableSetView) return _entered;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_entered);
}

 final  Set<String> _exited;
 Set<String> get exited {
  if (_exited is EqualUnmodifiableSetView) return _exited;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_exited);
}


/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadySetChangedCopyWith<ReadySetChanged> get copyWith => _$ReadySetChangedCopyWithImpl<ReadySetChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadySetChanged&&const DeepCollectionEquality().equals(other._entered, _entered)&&const DeepCollectionEquality().equals(other._exited, _exited));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_entered),const DeepCollectionEquality().hash(_exited));

@override
String toString() {
  return 'GraphEvent.readySetChanged(entered: $entered, exited: $exited)';
}


}

/// @nodoc
abstract mixin class $ReadySetChangedCopyWith<$Res> implements $GraphEventCopyWith<$Res> {
  factory $ReadySetChangedCopyWith(ReadySetChanged value, $Res Function(ReadySetChanged) _then) = _$ReadySetChangedCopyWithImpl;
@useResult
$Res call({
 Set<String> entered, Set<String> exited
});




}
/// @nodoc
class _$ReadySetChangedCopyWithImpl<$Res>
    implements $ReadySetChangedCopyWith<$Res> {
  _$ReadySetChangedCopyWithImpl(this._self, this._then);

  final ReadySetChanged _self;
  final $Res Function(ReadySetChanged) _then;

/// Create a copy of GraphEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entered = null,Object? exited = null,}) {
  return _then(ReadySetChanged(
entered: null == entered ? _self._entered : entered // ignore: cast_nullable_to_non_nullable
as Set<String>,exited: null == exited ? _self._exited : exited // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}


}

// dart format on
