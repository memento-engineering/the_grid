// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'command_operation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GridCommandRequest {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridCommandRequest);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GridCommandRequest()';
}


}

/// @nodoc
class $GridCommandRequestCopyWith<$Res>  {
$GridCommandRequestCopyWith(GridCommandRequest _, $Res Function(GridCommandRequest) __);
}


/// Adds pattern-matching-related methods to [GridCommandRequest].
extension GridCommandRequestPatterns on GridCommandRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GridRework value)?  rework,TResult Function( GridGateLs value)?  listGates,TResult Function( GridGateResolve value)?  resolveGate,TResult Function( GridSetBeadText value)?  setBeadText,TResult Function( GridBeadBoard value)?  board,TResult Function( GridBeadRound value)?  beadRound,TResult Function( GridAttachSubstation value)?  attachSubstation,TResult Function( GridDetachSubstation value)?  detachSubstation,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GridRework() when rework != null:
return rework(_that);case GridGateLs() when listGates != null:
return listGates(_that);case GridGateResolve() when resolveGate != null:
return resolveGate(_that);case GridSetBeadText() when setBeadText != null:
return setBeadText(_that);case GridBeadBoard() when board != null:
return board(_that);case GridBeadRound() when beadRound != null:
return beadRound(_that);case GridAttachSubstation() when attachSubstation != null:
return attachSubstation(_that);case GridDetachSubstation() when detachSubstation != null:
return detachSubstation(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GridRework value)  rework,required TResult Function( GridGateLs value)  listGates,required TResult Function( GridGateResolve value)  resolveGate,required TResult Function( GridSetBeadText value)  setBeadText,required TResult Function( GridBeadBoard value)  board,required TResult Function( GridBeadRound value)  beadRound,required TResult Function( GridAttachSubstation value)  attachSubstation,required TResult Function( GridDetachSubstation value)  detachSubstation,}){
final _that = this;
switch (_that) {
case GridRework():
return rework(_that);case GridGateLs():
return listGates(_that);case GridGateResolve():
return resolveGate(_that);case GridSetBeadText():
return setBeadText(_that);case GridBeadBoard():
return board(_that);case GridBeadRound():
return beadRound(_that);case GridAttachSubstation():
return attachSubstation(_that);case GridDetachSubstation():
return detachSubstation(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GridRework value)?  rework,TResult? Function( GridGateLs value)?  listGates,TResult? Function( GridGateResolve value)?  resolveGate,TResult? Function( GridSetBeadText value)?  setBeadText,TResult? Function( GridBeadBoard value)?  board,TResult? Function( GridBeadRound value)?  beadRound,TResult? Function( GridAttachSubstation value)?  attachSubstation,TResult? Function( GridDetachSubstation value)?  detachSubstation,}){
final _that = this;
switch (_that) {
case GridRework() when rework != null:
return rework(_that);case GridGateLs() when listGates != null:
return listGates(_that);case GridGateResolve() when resolveGate != null:
return resolveGate(_that);case GridSetBeadText() when setBeadText != null:
return setBeadText(_that);case GridBeadBoard() when board != null:
return board(_that);case GridBeadRound() when beadRound != null:
return beadRound(_that);case GridAttachSubstation() when attachSubstation != null:
return attachSubstation(_that);case GridDetachSubstation() when detachSubstation != null:
return detachSubstation(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String beadId,  String? note,  bool beyondCap,  String? actor)?  rework,TResult Function()?  listGates,TResult Function( String gateId,  Map<String, String> grades,  String? rationale)?  resolveGate,TResult Function( String beadId,  OperatorBeadTextField field,  String content,  bool append)?  setBeadText,TResult Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)?  board,TResult Function( String beadId)?  beadRound,TResult Function( String name,  String root,  String? prefix)?  attachSubstation,TResult Function( String name,  bool force)?  detachSubstation,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GridRework() when rework != null:
return rework(_that.beadId,_that.note,_that.beyondCap,_that.actor);case GridGateLs() when listGates != null:
return listGates();case GridGateResolve() when resolveGate != null:
return resolveGate(_that.gateId,_that.grades,_that.rationale);case GridSetBeadText() when setBeadText != null:
return setBeadText(_that.beadId,_that.field,_that.content,_that.append);case GridBeadBoard() when board != null:
return board(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case GridBeadRound() when beadRound != null:
return beadRound(_that.beadId);case GridAttachSubstation() when attachSubstation != null:
return attachSubstation(_that.name,_that.root,_that.prefix);case GridDetachSubstation() when detachSubstation != null:
return detachSubstation(_that.name,_that.force);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String beadId,  String? note,  bool beyondCap,  String? actor)  rework,required TResult Function()  listGates,required TResult Function( String gateId,  Map<String, String> grades,  String? rationale)  resolveGate,required TResult Function( String beadId,  OperatorBeadTextField field,  String content,  bool append)  setBeadText,required TResult Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)  board,required TResult Function( String beadId)  beadRound,required TResult Function( String name,  String root,  String? prefix)  attachSubstation,required TResult Function( String name,  bool force)  detachSubstation,}) {final _that = this;
switch (_that) {
case GridRework():
return rework(_that.beadId,_that.note,_that.beyondCap,_that.actor);case GridGateLs():
return listGates();case GridGateResolve():
return resolveGate(_that.gateId,_that.grades,_that.rationale);case GridSetBeadText():
return setBeadText(_that.beadId,_that.field,_that.content,_that.append);case GridBeadBoard():
return board(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case GridBeadRound():
return beadRound(_that.beadId);case GridAttachSubstation():
return attachSubstation(_that.name,_that.root,_that.prefix);case GridDetachSubstation():
return detachSubstation(_that.name,_that.force);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String beadId,  String? note,  bool beyondCap,  String? actor)?  rework,TResult? Function()?  listGates,TResult? Function( String gateId,  Map<String, String> grades,  String? rationale)?  resolveGate,TResult? Function( String beadId,  OperatorBeadTextField field,  String content,  bool append)?  setBeadText,TResult? Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)?  board,TResult? Function( String beadId)?  beadRound,TResult? Function( String name,  String root,  String? prefix)?  attachSubstation,TResult? Function( String name,  bool force)?  detachSubstation,}) {final _that = this;
switch (_that) {
case GridRework() when rework != null:
return rework(_that.beadId,_that.note,_that.beyondCap,_that.actor);case GridGateLs() when listGates != null:
return listGates();case GridGateResolve() when resolveGate != null:
return resolveGate(_that.gateId,_that.grades,_that.rationale);case GridSetBeadText() when setBeadText != null:
return setBeadText(_that.beadId,_that.field,_that.content,_that.append);case GridBeadBoard() when board != null:
return board(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case GridBeadRound() when beadRound != null:
return beadRound(_that.beadId);case GridAttachSubstation() when attachSubstation != null:
return attachSubstation(_that.name,_that.root,_that.prefix);case GridDetachSubstation() when detachSubstation != null:
return detachSubstation(_that.name,_that.force);case _:
  return null;

}
}

}

/// @nodoc


class GridRework implements GridCommandRequest {
  const GridRework({required this.beadId, this.note, this.beyondCap = false, this.actor});
  

 final  String beadId;
 final  String? note;
@JsonKey() final  bool beyondCap;
 final  String? actor;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridReworkCopyWith<GridRework> get copyWith => _$GridReworkCopyWithImpl<GridRework>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridRework&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.note, note) || other.note == note)&&(identical(other.beyondCap, beyondCap) || other.beyondCap == beyondCap)&&(identical(other.actor, actor) || other.actor == actor));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,note,beyondCap,actor);

@override
String toString() {
  return 'GridCommandRequest.rework(beadId: $beadId, note: $note, beyondCap: $beyondCap, actor: $actor)';
}


}

/// @nodoc
abstract mixin class $GridReworkCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridReworkCopyWith(GridRework value, $Res Function(GridRework) _then) = _$GridReworkCopyWithImpl;
@useResult
$Res call({
 String beadId, String? note, bool beyondCap, String? actor
});




}
/// @nodoc
class _$GridReworkCopyWithImpl<$Res>
    implements $GridReworkCopyWith<$Res> {
  _$GridReworkCopyWithImpl(this._self, this._then);

  final GridRework _self;
  final $Res Function(GridRework) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? note = freezed,Object? beyondCap = null,Object? actor = freezed,}) {
  return _then(GridRework(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,beyondCap: null == beyondCap ? _self.beyondCap : beyondCap // ignore: cast_nullable_to_non_nullable
as bool,actor: freezed == actor ? _self.actor : actor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class GridGateLs implements GridCommandRequest {
  const GridGateLs();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridGateLs);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'GridCommandRequest.listGates()';
}


}




/// @nodoc


class GridGateResolve implements GridCommandRequest {
  const GridGateResolve({required this.gateId, final  Map<String, String> grades = const <String, String>{}, this.rationale}): _grades = grades;
  

 final  String gateId;
 final  Map<String, String> _grades;
@JsonKey() Map<String, String> get grades {
  if (_grades is EqualUnmodifiableMapView) return _grades;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_grades);
}

 final  String? rationale;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridGateResolveCopyWith<GridGateResolve> get copyWith => _$GridGateResolveCopyWithImpl<GridGateResolve>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridGateResolve&&(identical(other.gateId, gateId) || other.gateId == gateId)&&const DeepCollectionEquality().equals(other._grades, _grades)&&(identical(other.rationale, rationale) || other.rationale == rationale));
}


@override
int get hashCode => Object.hash(runtimeType,gateId,const DeepCollectionEquality().hash(_grades),rationale);

@override
String toString() {
  return 'GridCommandRequest.resolveGate(gateId: $gateId, grades: $grades, rationale: $rationale)';
}


}

/// @nodoc
abstract mixin class $GridGateResolveCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridGateResolveCopyWith(GridGateResolve value, $Res Function(GridGateResolve) _then) = _$GridGateResolveCopyWithImpl;
@useResult
$Res call({
 String gateId, Map<String, String> grades, String? rationale
});




}
/// @nodoc
class _$GridGateResolveCopyWithImpl<$Res>
    implements $GridGateResolveCopyWith<$Res> {
  _$GridGateResolveCopyWithImpl(this._self, this._then);

  final GridGateResolve _self;
  final $Res Function(GridGateResolve) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? gateId = null,Object? grades = null,Object? rationale = freezed,}) {
  return _then(GridGateResolve(
gateId: null == gateId ? _self.gateId : gateId // ignore: cast_nullable_to_non_nullable
as String,grades: null == grades ? _self._grades : grades // ignore: cast_nullable_to_non_nullable
as Map<String, String>,rationale: freezed == rationale ? _self.rationale : rationale // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class GridSetBeadText implements GridCommandRequest {
  const GridSetBeadText({required this.beadId, required this.field, required this.content, this.append = false});
  

 final  String beadId;
 final  OperatorBeadTextField field;
 final  String content;
@JsonKey() final  bool append;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridSetBeadTextCopyWith<GridSetBeadText> get copyWith => _$GridSetBeadTextCopyWithImpl<GridSetBeadText>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridSetBeadText&&(identical(other.beadId, beadId) || other.beadId == beadId)&&(identical(other.field, field) || other.field == field)&&(identical(other.content, content) || other.content == content)&&(identical(other.append, append) || other.append == append));
}


@override
int get hashCode => Object.hash(runtimeType,beadId,field,content,append);

@override
String toString() {
  return 'GridCommandRequest.setBeadText(beadId: $beadId, field: $field, content: $content, append: $append)';
}


}

/// @nodoc
abstract mixin class $GridSetBeadTextCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridSetBeadTextCopyWith(GridSetBeadText value, $Res Function(GridSetBeadText) _then) = _$GridSetBeadTextCopyWithImpl;
@useResult
$Res call({
 String beadId, OperatorBeadTextField field, String content, bool append
});




}
/// @nodoc
class _$GridSetBeadTextCopyWithImpl<$Res>
    implements $GridSetBeadTextCopyWith<$Res> {
  _$GridSetBeadTextCopyWithImpl(this._self, this._then);

  final GridSetBeadText _self;
  final $Res Function(GridSetBeadText) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beadId = null,Object? field = null,Object? content = null,Object? append = null,}) {
  return _then(GridSetBeadText(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as OperatorBeadTextField,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,append: null == append ? _self.append : append // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class GridBeadBoard implements GridCommandRequest {
  const GridBeadBoard({final  Set<String> stores = const <String>{}, final  Set<String> statuses = const <String>{}, this.blockedOnly = false, this.approved}): _stores = stores,_statuses = statuses;
  

 final  Set<String> _stores;
@JsonKey() Set<String> get stores {
  if (_stores is EqualUnmodifiableSetView) return _stores;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_stores);
}

 final  Set<String> _statuses;
@JsonKey() Set<String> get statuses {
  if (_statuses is EqualUnmodifiableSetView) return _statuses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_statuses);
}

@JsonKey() final  bool blockedOnly;
 final  bool? approved;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridBeadBoardCopyWith<GridBeadBoard> get copyWith => _$GridBeadBoardCopyWithImpl<GridBeadBoard>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridBeadBoard&&const DeepCollectionEquality().equals(other._stores, _stores)&&const DeepCollectionEquality().equals(other._statuses, _statuses)&&(identical(other.blockedOnly, blockedOnly) || other.blockedOnly == blockedOnly)&&(identical(other.approved, approved) || other.approved == approved));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_stores),const DeepCollectionEquality().hash(_statuses),blockedOnly,approved);

@override
String toString() {
  return 'GridCommandRequest.board(stores: $stores, statuses: $statuses, blockedOnly: $blockedOnly, approved: $approved)';
}


}

/// @nodoc
abstract mixin class $GridBeadBoardCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridBeadBoardCopyWith(GridBeadBoard value, $Res Function(GridBeadBoard) _then) = _$GridBeadBoardCopyWithImpl;
@useResult
$Res call({
 Set<String> stores, Set<String> statuses, bool blockedOnly, bool? approved
});




}
/// @nodoc
class _$GridBeadBoardCopyWithImpl<$Res>
    implements $GridBeadBoardCopyWith<$Res> {
  _$GridBeadBoardCopyWithImpl(this._self, this._then);

  final GridBeadBoard _self;
  final $Res Function(GridBeadBoard) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stores = null,Object? statuses = null,Object? blockedOnly = null,Object? approved = freezed,}) {
  return _then(GridBeadBoard(
stores: null == stores ? _self._stores : stores // ignore: cast_nullable_to_non_nullable
as Set<String>,statuses: null == statuses ? _self._statuses : statuses // ignore: cast_nullable_to_non_nullable
as Set<String>,blockedOnly: null == blockedOnly ? _self.blockedOnly : blockedOnly // ignore: cast_nullable_to_non_nullable
as bool,approved: freezed == approved ? _self.approved : approved // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class GridBeadRound implements GridCommandRequest {
  const GridBeadRound({required this.beadId});
  

 final  String beadId;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridBeadRoundCopyWith<GridBeadRound> get copyWith => _$GridBeadRoundCopyWithImpl<GridBeadRound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridBeadRound&&(identical(other.beadId, beadId) || other.beadId == beadId));
}


@override
int get hashCode => Object.hash(runtimeType,beadId);

@override
String toString() {
  return 'GridCommandRequest.beadRound(beadId: $beadId)';
}


}

/// @nodoc
abstract mixin class $GridBeadRoundCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridBeadRoundCopyWith(GridBeadRound value, $Res Function(GridBeadRound) _then) = _$GridBeadRoundCopyWithImpl;
@useResult
$Res call({
 String beadId
});




}
/// @nodoc
class _$GridBeadRoundCopyWithImpl<$Res>
    implements $GridBeadRoundCopyWith<$Res> {
  _$GridBeadRoundCopyWithImpl(this._self, this._then);

  final GridBeadRound _self;
  final $Res Function(GridBeadRound) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beadId = null,}) {
  return _then(GridBeadRound(
beadId: null == beadId ? _self.beadId : beadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class GridAttachSubstation implements GridCommandRequest {
  const GridAttachSubstation({required this.name, required this.root, this.prefix});
  

 final  String name;
 final  String root;
 final  String? prefix;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridAttachSubstationCopyWith<GridAttachSubstation> get copyWith => _$GridAttachSubstationCopyWithImpl<GridAttachSubstation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridAttachSubstation&&(identical(other.name, name) || other.name == name)&&(identical(other.root, root) || other.root == root)&&(identical(other.prefix, prefix) || other.prefix == prefix));
}


@override
int get hashCode => Object.hash(runtimeType,name,root,prefix);

@override
String toString() {
  return 'GridCommandRequest.attachSubstation(name: $name, root: $root, prefix: $prefix)';
}


}

/// @nodoc
abstract mixin class $GridAttachSubstationCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridAttachSubstationCopyWith(GridAttachSubstation value, $Res Function(GridAttachSubstation) _then) = _$GridAttachSubstationCopyWithImpl;
@useResult
$Res call({
 String name, String root, String? prefix
});




}
/// @nodoc
class _$GridAttachSubstationCopyWithImpl<$Res>
    implements $GridAttachSubstationCopyWith<$Res> {
  _$GridAttachSubstationCopyWithImpl(this._self, this._then);

  final GridAttachSubstation _self;
  final $Res Function(GridAttachSubstation) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? root = null,Object? prefix = freezed,}) {
  return _then(GridAttachSubstation(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,prefix: freezed == prefix ? _self.prefix : prefix // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class GridDetachSubstation implements GridCommandRequest {
  const GridDetachSubstation({required this.name, this.force = false});
  

 final  String name;
@JsonKey() final  bool force;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridDetachSubstationCopyWith<GridDetachSubstation> get copyWith => _$GridDetachSubstationCopyWithImpl<GridDetachSubstation>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridDetachSubstation&&(identical(other.name, name) || other.name == name)&&(identical(other.force, force) || other.force == force));
}


@override
int get hashCode => Object.hash(runtimeType,name,force);

@override
String toString() {
  return 'GridCommandRequest.detachSubstation(name: $name, force: $force)';
}


}

/// @nodoc
abstract mixin class $GridDetachSubstationCopyWith<$Res> implements $GridCommandRequestCopyWith<$Res> {
  factory $GridDetachSubstationCopyWith(GridDetachSubstation value, $Res Function(GridDetachSubstation) _then) = _$GridDetachSubstationCopyWithImpl;
@useResult
$Res call({
 String name, bool force
});




}
/// @nodoc
class _$GridDetachSubstationCopyWithImpl<$Res>
    implements $GridDetachSubstationCopyWith<$Res> {
  _$GridDetachSubstationCopyWithImpl(this._self, this._then);

  final GridDetachSubstation _self;
  final $Res Function(GridDetachSubstation) _then;

/// Create a copy of GridCommandRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? force = null,}) {
  return _then(GridDetachSubstation(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,force: null == force ? _self.force : force // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$GridCommandResult {

 String get message;
/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridCommandResultCopyWith<GridCommandResult> get copyWith => _$GridCommandResultCopyWithImpl<GridCommandResult>(this as GridCommandResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridCommandResult&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'GridCommandResult(message: $message)';
}


}

/// @nodoc
abstract mixin class $GridCommandResultCopyWith<$Res>  {
  factory $GridCommandResultCopyWith(GridCommandResult value, $Res Function(GridCommandResult) _then) = _$GridCommandResultCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$GridCommandResultCopyWithImpl<$Res>
    implements $GridCommandResultCopyWith<$Res> {
  _$GridCommandResultCopyWithImpl(this._self, this._then);

  final GridCommandResult _self;
  final $Res Function(GridCommandResult) _then;

/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [GridCommandResult].
extension GridCommandResultPatterns on GridCommandResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GridCommandCompleted value)?  completed,TResult Function( GridCommandRefused value)?  refused,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GridCommandCompleted() when completed != null:
return completed(_that);case GridCommandRefused() when refused != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GridCommandCompleted value)  completed,required TResult Function( GridCommandRefused value)  refused,}){
final _that = this;
switch (_that) {
case GridCommandCompleted():
return completed(_that);case GridCommandRefused():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GridCommandCompleted value)?  completed,TResult? Function( GridCommandRefused value)?  refused,}){
final _that = this;
switch (_that) {
case GridCommandCompleted() when completed != null:
return completed(_that);case GridCommandRefused() when refused != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message,  Map<String, Object?> value)?  completed,TResult Function( String code,  String message)?  refused,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GridCommandCompleted() when completed != null:
return completed(_that.message,_that.value);case GridCommandRefused() when refused != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message,  Map<String, Object?> value)  completed,required TResult Function( String code,  String message)  refused,}) {final _that = this;
switch (_that) {
case GridCommandCompleted():
return completed(_that.message,_that.value);case GridCommandRefused():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message,  Map<String, Object?> value)?  completed,TResult? Function( String code,  String message)?  refused,}) {final _that = this;
switch (_that) {
case GridCommandCompleted() when completed != null:
return completed(_that.message,_that.value);case GridCommandRefused() when refused != null:
return refused(_that.code,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class GridCommandCompleted implements GridCommandResult {
  const GridCommandCompleted({required this.message, final  Map<String, Object?> value = const <String, Object?>{}}): _value = value;
  

@override final  String message;
 final  Map<String, Object?> _value;
@JsonKey() Map<String, Object?> get value {
  if (_value is EqualUnmodifiableMapView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_value);
}


/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridCommandCompletedCopyWith<GridCommandCompleted> get copyWith => _$GridCommandCompletedCopyWithImpl<GridCommandCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridCommandCompleted&&(identical(other.message, message) || other.message == message)&&const DeepCollectionEquality().equals(other._value, _value));
}


@override
int get hashCode => Object.hash(runtimeType,message,const DeepCollectionEquality().hash(_value));

@override
String toString() {
  return 'GridCommandResult.completed(message: $message, value: $value)';
}


}

/// @nodoc
abstract mixin class $GridCommandCompletedCopyWith<$Res> implements $GridCommandResultCopyWith<$Res> {
  factory $GridCommandCompletedCopyWith(GridCommandCompleted value, $Res Function(GridCommandCompleted) _then) = _$GridCommandCompletedCopyWithImpl;
@override @useResult
$Res call({
 String message, Map<String, Object?> value
});




}
/// @nodoc
class _$GridCommandCompletedCopyWithImpl<$Res>
    implements $GridCommandCompletedCopyWith<$Res> {
  _$GridCommandCompletedCopyWithImpl(this._self, this._then);

  final GridCommandCompleted _self;
  final $Res Function(GridCommandCompleted) _then;

/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? value = null,}) {
  return _then(GridCommandCompleted(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as Map<String, Object?>,
  ));
}


}

/// @nodoc


class GridCommandRefused implements GridCommandResult {
  const GridCommandRefused({required this.code, required this.message});
  

 final  String code;
@override final  String message;

/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GridCommandRefusedCopyWith<GridCommandRefused> get copyWith => _$GridCommandRefusedCopyWithImpl<GridCommandRefused>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GridCommandRefused&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,code,message);

@override
String toString() {
  return 'GridCommandResult.refused(code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $GridCommandRefusedCopyWith<$Res> implements $GridCommandResultCopyWith<$Res> {
  factory $GridCommandRefusedCopyWith(GridCommandRefused value, $Res Function(GridCommandRefused) _then) = _$GridCommandRefusedCopyWithImpl;
@override @useResult
$Res call({
 String code, String message
});




}
/// @nodoc
class _$GridCommandRefusedCopyWithImpl<$Res>
    implements $GridCommandRefusedCopyWith<$Res> {
  _$GridCommandRefusedCopyWithImpl(this._self, this._then);

  final GridCommandRefused _self;
  final $Res Function(GridCommandRefused) _then;

/// Create a copy of GridCommandResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,}) {
  return _then(GridCommandRefused(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
