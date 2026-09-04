// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bead_board.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BoardFilter {

/// Substation names to keep; empty keeps every store.
 Set<String> get stores;/// `BeadStatus` wire values to keep; empty keeps every non-closed status.
 Set<String> get statuses;/// Keep only beads carrying at least one open blocking edge.
 bool get blockedOnly;/// `true` keeps approval-stamped beads, `false` keeps unstamped ones,
/// null keeps both.
 bool? get approved;
/// Create a copy of BoardFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoardFilterCopyWith<BoardFilter> get copyWith => _$BoardFilterCopyWithImpl<BoardFilter>(this as BoardFilter, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoardFilter&&const DeepCollectionEquality().equals(other.stores, stores)&&const DeepCollectionEquality().equals(other.statuses, statuses)&&(identical(other.blockedOnly, blockedOnly) || other.blockedOnly == blockedOnly)&&(identical(other.approved, approved) || other.approved == approved));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(stores),const DeepCollectionEquality().hash(statuses),blockedOnly,approved);

@override
String toString() {
  return 'BoardFilter(stores: $stores, statuses: $statuses, blockedOnly: $blockedOnly, approved: $approved)';
}


}

/// @nodoc
abstract mixin class $BoardFilterCopyWith<$Res>  {
  factory $BoardFilterCopyWith(BoardFilter value, $Res Function(BoardFilter) _then) = _$BoardFilterCopyWithImpl;
@useResult
$Res call({
 Set<String> stores, Set<String> statuses, bool blockedOnly, bool? approved
});




}
/// @nodoc
class _$BoardFilterCopyWithImpl<$Res>
    implements $BoardFilterCopyWith<$Res> {
  _$BoardFilterCopyWithImpl(this._self, this._then);

  final BoardFilter _self;
  final $Res Function(BoardFilter) _then;

/// Create a copy of BoardFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stores = null,Object? statuses = null,Object? blockedOnly = null,Object? approved = freezed,}) {
  return _then(_self.copyWith(
stores: null == stores ? _self.stores : stores // ignore: cast_nullable_to_non_nullable
as Set<String>,statuses: null == statuses ? _self.statuses : statuses // ignore: cast_nullable_to_non_nullable
as Set<String>,blockedOnly: null == blockedOnly ? _self.blockedOnly : blockedOnly // ignore: cast_nullable_to_non_nullable
as bool,approved: freezed == approved ? _self.approved : approved // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [BoardFilter].
extension BoardFilterPatterns on BoardFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BoardFilter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BoardFilter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BoardFilter value)  $default,){
final _that = this;
switch (_that) {
case _BoardFilter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BoardFilter value)?  $default,){
final _that = this;
switch (_that) {
case _BoardFilter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BoardFilter() when $default != null:
return $default(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)  $default,) {final _that = this;
switch (_that) {
case _BoardFilter():
return $default(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Set<String> stores,  Set<String> statuses,  bool blockedOnly,  bool? approved)?  $default,) {final _that = this;
switch (_that) {
case _BoardFilter() when $default != null:
return $default(_that.stores,_that.statuses,_that.blockedOnly,_that.approved);case _:
  return null;

}
}

}

/// @nodoc


class _BoardFilter implements BoardFilter {
  const _BoardFilter({final  Set<String> stores = const <String>{}, final  Set<String> statuses = const <String>{}, this.blockedOnly = false, this.approved}): _stores = stores,_statuses = statuses;


/// Substation names to keep; empty keeps every store.
 final  Set<String> _stores;
/// Substation names to keep; empty keeps every store.
@override@JsonKey() Set<String> get stores {
  if (_stores is EqualUnmodifiableSetView) return _stores;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_stores);
}

/// `BeadStatus` wire values to keep; empty keeps every non-closed status.
 final  Set<String> _statuses;
/// `BeadStatus` wire values to keep; empty keeps every non-closed status.
@override@JsonKey() Set<String> get statuses {
  if (_statuses is EqualUnmodifiableSetView) return _statuses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_statuses);
}

/// Keep only beads carrying at least one open blocking edge.
@override@JsonKey() final  bool blockedOnly;
/// `true` keeps approval-stamped beads, `false` keeps unstamped ones,
/// null keeps both.
@override final  bool? approved;

/// Create a copy of BoardFilter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BoardFilterCopyWith<_BoardFilter> get copyWith => __$BoardFilterCopyWithImpl<_BoardFilter>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BoardFilter&&const DeepCollectionEquality().equals(other._stores, _stores)&&const DeepCollectionEquality().equals(other._statuses, _statuses)&&(identical(other.blockedOnly, blockedOnly) || other.blockedOnly == blockedOnly)&&(identical(other.approved, approved) || other.approved == approved));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_stores),const DeepCollectionEquality().hash(_statuses),blockedOnly,approved);

@override
String toString() {
  return 'BoardFilter(stores: $stores, statuses: $statuses, blockedOnly: $blockedOnly, approved: $approved)';
}


}

/// @nodoc
abstract mixin class _$BoardFilterCopyWith<$Res> implements $BoardFilterCopyWith<$Res> {
  factory _$BoardFilterCopyWith(_BoardFilter value, $Res Function(_BoardFilter) _then) = __$BoardFilterCopyWithImpl;
@override @useResult
$Res call({
 Set<String> stores, Set<String> statuses, bool blockedOnly, bool? approved
});




}
/// @nodoc
class __$BoardFilterCopyWithImpl<$Res>
    implements _$BoardFilterCopyWith<$Res> {
  __$BoardFilterCopyWithImpl(this._self, this._then);

  final _BoardFilter _self;
  final $Res Function(_BoardFilter) _then;

/// Create a copy of BoardFilter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stores = null,Object? statuses = null,Object? blockedOnly = null,Object? approved = freezed,}) {
  return _then(_BoardFilter(
stores: null == stores ? _self._stores : stores // ignore: cast_nullable_to_non_nullable
as Set<String>,statuses: null == statuses ? _self._statuses : statuses // ignore: cast_nullable_to_non_nullable
as Set<String>,blockedOnly: null == blockedOnly ? _self.blockedOnly : blockedOnly // ignore: cast_nullable_to_non_nullable
as bool,approved: freezed == approved ? _self.approved : approved // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

BoardRow _$BoardRowFromJson(
  Map<String, dynamic> json
) {
        switch (json['kind']) {
                  case 'bead':
          return BoardBeadRow.fromJson(
            json
          );
                case 'store_unreadable':
          return BoardStoreUnreadableRow.fromJson(
            json
          );

          default:
            throw CheckedFromJsonException(
  json,
  'kind',
  'BoardRow',
  'Invalid union type "${json['kind']}"!'
);
        }

}

/// @nodoc
mixin _$BoardRow {

 String get store; String get root;
/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoardRowCopyWith<BoardRow> get copyWith => _$BoardRowCopyWithImpl<BoardRow>(this as BoardRow, _$identity);

  /// Serializes this BoardRow to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoardRow&&(identical(other.store, store) || other.store == store)&&(identical(other.root, root) || other.root == root));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,store,root);

@override
String toString() {
  return 'BoardRow(store: $store, root: $root)';
}


}

/// @nodoc
abstract mixin class $BoardRowCopyWith<$Res>  {
  factory $BoardRowCopyWith(BoardRow value, $Res Function(BoardRow) _then) = _$BoardRowCopyWithImpl;
@useResult
$Res call({
 String store, String root
});




}
/// @nodoc
class _$BoardRowCopyWithImpl<$Res>
    implements $BoardRowCopyWith<$Res> {
  _$BoardRowCopyWithImpl(this._self, this._then);

  final BoardRow _self;
  final $Res Function(BoardRow) _then;

/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? store = null,Object? root = null,}) {
  return _then(_self.copyWith(
store: null == store ? _self.store : store // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BoardRow].
extension BoardRowPatterns on BoardRow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BoardBeadRow value)?  bead,TResult Function( BoardStoreUnreadableRow value)?  storeUnreadable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BoardBeadRow() when bead != null:
return bead(_that);case BoardStoreUnreadableRow() when storeUnreadable != null:
return storeUnreadable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BoardBeadRow value)  bead,required TResult Function( BoardStoreUnreadableRow value)  storeUnreadable,}){
final _that = this;
switch (_that) {
case BoardBeadRow():
return bead(_that);case BoardStoreUnreadableRow():
return storeUnreadable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BoardBeadRow value)?  bead,TResult? Function( BoardStoreUnreadableRow value)?  storeUnreadable,}){
final _that = this;
switch (_that) {
case BoardBeadRow() when bead != null:
return bead(_that);case BoardStoreUnreadableRow() when storeUnreadable != null:
return storeUnreadable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String store,  String root,  String type,  String status,  String title,  bool ready, @JsonKey(name: 'blocked_by')  List<String> blockedBy, @JsonKey(name: 'approved_by')  String? approvedBy, @JsonKey(name: 'approved_at')  String? approvedAt, @JsonKey(name: 'approved_rev')  String? approvedRev)?  bead,TResult Function( String store,  String root,  String reason)?  storeUnreadable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BoardBeadRow() when bead != null:
return bead(_that.id,_that.store,_that.root,_that.type,_that.status,_that.title,_that.ready,_that.blockedBy,_that.approvedBy,_that.approvedAt,_that.approvedRev);case BoardStoreUnreadableRow() when storeUnreadable != null:
return storeUnreadable(_that.store,_that.root,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String store,  String root,  String type,  String status,  String title,  bool ready, @JsonKey(name: 'blocked_by')  List<String> blockedBy, @JsonKey(name: 'approved_by')  String? approvedBy, @JsonKey(name: 'approved_at')  String? approvedAt, @JsonKey(name: 'approved_rev')  String? approvedRev)  bead,required TResult Function( String store,  String root,  String reason)  storeUnreadable,}) {final _that = this;
switch (_that) {
case BoardBeadRow():
return bead(_that.id,_that.store,_that.root,_that.type,_that.status,_that.title,_that.ready,_that.blockedBy,_that.approvedBy,_that.approvedAt,_that.approvedRev);case BoardStoreUnreadableRow():
return storeUnreadable(_that.store,_that.root,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String store,  String root,  String type,  String status,  String title,  bool ready, @JsonKey(name: 'blocked_by')  List<String> blockedBy, @JsonKey(name: 'approved_by')  String? approvedBy, @JsonKey(name: 'approved_at')  String? approvedAt, @JsonKey(name: 'approved_rev')  String? approvedRev)?  bead,TResult? Function( String store,  String root,  String reason)?  storeUnreadable,}) {final _that = this;
switch (_that) {
case BoardBeadRow() when bead != null:
return bead(_that.id,_that.store,_that.root,_that.type,_that.status,_that.title,_that.ready,_that.blockedBy,_that.approvedBy,_that.approvedAt,_that.approvedRev);case BoardStoreUnreadableRow() when storeUnreadable != null:
return storeUnreadable(_that.store,_that.root,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class BoardBeadRow implements BoardRow {
  const BoardBeadRow({required this.id, required this.store, required this.root, required this.type, required this.status, required this.title, this.ready = false, @JsonKey(name: 'blocked_by') final  List<String> blockedBy = const <String>[], @JsonKey(name: 'approved_by') this.approvedBy, @JsonKey(name: 'approved_at') this.approvedAt, @JsonKey(name: 'approved_rev') this.approvedRev, final  String? $type}): _blockedBy = blockedBy,$type = $type ?? 'bead';
  factory BoardBeadRow.fromJson(Map<String, dynamic> json) => _$BoardBeadRowFromJson(json);

 final  String id;
@override final  String store;
@override final  String root;
 final  String type;
 final  String status;
 final  String title;
@JsonKey() final  bool ready;
 final  List<String> _blockedBy;
@JsonKey(name: 'blocked_by') List<String> get blockedBy {
  if (_blockedBy is EqualUnmodifiableListView) return _blockedBy;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blockedBy);
}

@JsonKey(name: 'approved_by') final  String? approvedBy;
@JsonKey(name: 'approved_at') final  String? approvedAt;
@JsonKey(name: 'approved_rev') final  String? approvedRev;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoardBeadRowCopyWith<BoardBeadRow> get copyWith => _$BoardBeadRowCopyWithImpl<BoardBeadRow>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BoardBeadRowToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoardBeadRow&&(identical(other.id, id) || other.id == id)&&(identical(other.store, store) || other.store == store)&&(identical(other.root, root) || other.root == root)&&(identical(other.type, type) || other.type == type)&&(identical(other.status, status) || other.status == status)&&(identical(other.title, title) || other.title == title)&&(identical(other.ready, ready) || other.ready == ready)&&const DeepCollectionEquality().equals(other._blockedBy, _blockedBy)&&(identical(other.approvedBy, approvedBy) || other.approvedBy == approvedBy)&&(identical(other.approvedAt, approvedAt) || other.approvedAt == approvedAt)&&(identical(other.approvedRev, approvedRev) || other.approvedRev == approvedRev));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,store,root,type,status,title,ready,const DeepCollectionEquality().hash(_blockedBy),approvedBy,approvedAt,approvedRev);

@override
String toString() {
  return 'BoardRow.bead(id: $id, store: $store, root: $root, type: $type, status: $status, title: $title, ready: $ready, blockedBy: $blockedBy, approvedBy: $approvedBy, approvedAt: $approvedAt, approvedRev: $approvedRev)';
}


}

/// @nodoc
abstract mixin class $BoardBeadRowCopyWith<$Res> implements $BoardRowCopyWith<$Res> {
  factory $BoardBeadRowCopyWith(BoardBeadRow value, $Res Function(BoardBeadRow) _then) = _$BoardBeadRowCopyWithImpl;
@override @useResult
$Res call({
 String id, String store, String root, String type, String status, String title, bool ready,@JsonKey(name: 'blocked_by') List<String> blockedBy,@JsonKey(name: 'approved_by') String? approvedBy,@JsonKey(name: 'approved_at') String? approvedAt,@JsonKey(name: 'approved_rev') String? approvedRev
});




}
/// @nodoc
class _$BoardBeadRowCopyWithImpl<$Res>
    implements $BoardBeadRowCopyWith<$Res> {
  _$BoardBeadRowCopyWithImpl(this._self, this._then);

  final BoardBeadRow _self;
  final $Res Function(BoardBeadRow) _then;

/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? store = null,Object? root = null,Object? type = null,Object? status = null,Object? title = null,Object? ready = null,Object? blockedBy = null,Object? approvedBy = freezed,Object? approvedAt = freezed,Object? approvedRev = freezed,}) {
  return _then(BoardBeadRow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,store: null == store ? _self.store : store // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,blockedBy: null == blockedBy ? _self._blockedBy : blockedBy // ignore: cast_nullable_to_non_nullable
as List<String>,approvedBy: freezed == approvedBy ? _self.approvedBy : approvedBy // ignore: cast_nullable_to_non_nullable
as String?,approvedAt: freezed == approvedAt ? _self.approvedAt : approvedAt // ignore: cast_nullable_to_non_nullable
as String?,approvedRev: freezed == approvedRev ? _self.approvedRev : approvedRev // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class BoardStoreUnreadableRow implements BoardRow {
  const BoardStoreUnreadableRow({required this.store, required this.root, required this.reason, final  String? $type}): $type = $type ?? 'store_unreadable';
  factory BoardStoreUnreadableRow.fromJson(Map<String, dynamic> json) => _$BoardStoreUnreadableRowFromJson(json);

@override final  String store;
@override final  String root;
 final  String reason;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BoardStoreUnreadableRowCopyWith<BoardStoreUnreadableRow> get copyWith => _$BoardStoreUnreadableRowCopyWithImpl<BoardStoreUnreadableRow>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BoardStoreUnreadableRowToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BoardStoreUnreadableRow&&(identical(other.store, store) || other.store == store)&&(identical(other.root, root) || other.root == root)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,store,root,reason);

@override
String toString() {
  return 'BoardRow.storeUnreadable(store: $store, root: $root, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BoardStoreUnreadableRowCopyWith<$Res> implements $BoardRowCopyWith<$Res> {
  factory $BoardStoreUnreadableRowCopyWith(BoardStoreUnreadableRow value, $Res Function(BoardStoreUnreadableRow) _then) = _$BoardStoreUnreadableRowCopyWithImpl;
@override @useResult
$Res call({
 String store, String root, String reason
});




}
/// @nodoc
class _$BoardStoreUnreadableRowCopyWithImpl<$Res>
    implements $BoardStoreUnreadableRowCopyWith<$Res> {
  _$BoardStoreUnreadableRowCopyWithImpl(this._self, this._then);

  final BoardStoreUnreadableRow _self;
  final $Res Function(BoardStoreUnreadableRow) _then;

/// Create a copy of BoardRow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? store = null,Object? root = null,Object? reason = null,}) {
  return _then(BoardStoreUnreadableRow(
store: null == store ? _self.store : store // ignore: cast_nullable_to_non_nullable
as String,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
