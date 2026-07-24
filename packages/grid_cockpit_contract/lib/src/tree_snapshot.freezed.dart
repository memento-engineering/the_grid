// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'tree_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TreeSnapshot {

 int get contractVersion; DateTime get projectedAt; TreeNode get root;
/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreeSnapshotCopyWith<TreeSnapshot> get copyWith => _$TreeSnapshotCopyWithImpl<TreeSnapshot>(this as TreeSnapshot, _$identity);

  /// Serializes this TreeSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreeSnapshot&&(identical(other.contractVersion, contractVersion) || other.contractVersion == contractVersion)&&(identical(other.projectedAt, projectedAt) || other.projectedAt == projectedAt)&&(identical(other.root, root) || other.root == root));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,contractVersion,projectedAt,root);

@override
String toString() {
  return 'TreeSnapshot(contractVersion: $contractVersion, projectedAt: $projectedAt, root: $root)';
}


}

/// @nodoc
abstract mixin class $TreeSnapshotCopyWith<$Res>  {
  factory $TreeSnapshotCopyWith(TreeSnapshot value, $Res Function(TreeSnapshot) _then) = _$TreeSnapshotCopyWithImpl;
@useResult
$Res call({
 int contractVersion, DateTime projectedAt, TreeNode root
});


$TreeNodeCopyWith<$Res> get root;

}
/// @nodoc
class _$TreeSnapshotCopyWithImpl<$Res>
    implements $TreeSnapshotCopyWith<$Res> {
  _$TreeSnapshotCopyWithImpl(this._self, this._then);

  final TreeSnapshot _self;
  final $Res Function(TreeSnapshot) _then;

/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? contractVersion = null,Object? projectedAt = null,Object? root = null,}) {
  return _then(_self.copyWith(
contractVersion: null == contractVersion ? _self.contractVersion : contractVersion // ignore: cast_nullable_to_non_nullable
as int,projectedAt: null == projectedAt ? _self.projectedAt : projectedAt // ignore: cast_nullable_to_non_nullable
as DateTime,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as TreeNode,
  ));
}
/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TreeNodeCopyWith<$Res> get root {
  
  return $TreeNodeCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}
}


/// Adds pattern-matching-related methods to [TreeSnapshot].
extension TreeSnapshotPatterns on TreeSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TreeSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TreeSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TreeSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _TreeSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TreeSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _TreeSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int contractVersion,  DateTime projectedAt,  TreeNode root)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TreeSnapshot() when $default != null:
return $default(_that.contractVersion,_that.projectedAt,_that.root);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int contractVersion,  DateTime projectedAt,  TreeNode root)  $default,) {final _that = this;
switch (_that) {
case _TreeSnapshot():
return $default(_that.contractVersion,_that.projectedAt,_that.root);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int contractVersion,  DateTime projectedAt,  TreeNode root)?  $default,) {final _that = this;
switch (_that) {
case _TreeSnapshot() when $default != null:
return $default(_that.contractVersion,_that.projectedAt,_that.root);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TreeSnapshot implements TreeSnapshot {
  const _TreeSnapshot({required this.contractVersion, required this.projectedAt, required this.root});
  factory _TreeSnapshot.fromJson(Map<String, dynamic> json) => _$TreeSnapshotFromJson(json);

@override final  int contractVersion;
@override final  DateTime projectedAt;
@override final  TreeNode root;

/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TreeSnapshotCopyWith<_TreeSnapshot> get copyWith => __$TreeSnapshotCopyWithImpl<_TreeSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TreeSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TreeSnapshot&&(identical(other.contractVersion, contractVersion) || other.contractVersion == contractVersion)&&(identical(other.projectedAt, projectedAt) || other.projectedAt == projectedAt)&&(identical(other.root, root) || other.root == root));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,contractVersion,projectedAt,root);

@override
String toString() {
  return 'TreeSnapshot(contractVersion: $contractVersion, projectedAt: $projectedAt, root: $root)';
}


}

/// @nodoc
abstract mixin class _$TreeSnapshotCopyWith<$Res> implements $TreeSnapshotCopyWith<$Res> {
  factory _$TreeSnapshotCopyWith(_TreeSnapshot value, $Res Function(_TreeSnapshot) _then) = __$TreeSnapshotCopyWithImpl;
@override @useResult
$Res call({
 int contractVersion, DateTime projectedAt, TreeNode root
});


@override $TreeNodeCopyWith<$Res> get root;

}
/// @nodoc
class __$TreeSnapshotCopyWithImpl<$Res>
    implements _$TreeSnapshotCopyWith<$Res> {
  __$TreeSnapshotCopyWithImpl(this._self, this._then);

  final _TreeSnapshot _self;
  final $Res Function(_TreeSnapshot) _then;

/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? contractVersion = null,Object? projectedAt = null,Object? root = null,}) {
  return _then(_TreeSnapshot(
contractVersion: null == contractVersion ? _self.contractVersion : contractVersion // ignore: cast_nullable_to_non_nullable
as int,projectedAt: null == projectedAt ? _self.projectedAt : projectedAt // ignore: cast_nullable_to_non_nullable
as DateTime,root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as TreeNode,
  ));
}

/// Create a copy of TreeSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TreeNodeCopyWith<$Res> get root {
  
  return $TreeNodeCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}
}


/// @nodoc
mixin _$TreeNode {

 String get seedType; String get id; String? get key; List<DiagnosticsProperty> get properties; List<TreeNode> get children;
/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreeNodeCopyWith<TreeNode> get copyWith => _$TreeNodeCopyWithImpl<TreeNode>(this as TreeNode, _$identity);

  /// Serializes this TreeNode to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreeNode&&(identical(other.seedType, seedType) || other.seedType == seedType)&&(identical(other.id, id) || other.id == id)&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other.properties, properties)&&const DeepCollectionEquality().equals(other.children, children));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seedType,id,key,const DeepCollectionEquality().hash(properties),const DeepCollectionEquality().hash(children));

@override
String toString() {
  return 'TreeNode(seedType: $seedType, id: $id, key: $key, properties: $properties, children: $children)';
}


}

/// @nodoc
abstract mixin class $TreeNodeCopyWith<$Res>  {
  factory $TreeNodeCopyWith(TreeNode value, $Res Function(TreeNode) _then) = _$TreeNodeCopyWithImpl;
@useResult
$Res call({
 String seedType, String id, String? key, List<DiagnosticsProperty> properties, List<TreeNode> children
});




}
/// @nodoc
class _$TreeNodeCopyWithImpl<$Res>
    implements $TreeNodeCopyWith<$Res> {
  _$TreeNodeCopyWithImpl(this._self, this._then);

  final TreeNode _self;
  final $Res Function(TreeNode) _then;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? seedType = null,Object? id = null,Object? key = freezed,Object? properties = null,Object? children = null,}) {
  return _then(_self.copyWith(
seedType: null == seedType ? _self.seedType : seedType // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,properties: null == properties ? _self.properties : properties // ignore: cast_nullable_to_non_nullable
as List<DiagnosticsProperty>,children: null == children ? _self.children : children // ignore: cast_nullable_to_non_nullable
as List<TreeNode>,
  ));
}

}


/// Adds pattern-matching-related methods to [TreeNode].
extension TreeNodePatterns on TreeNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TreeNode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TreeNode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TreeNode value)  $default,){
final _that = this;
switch (_that) {
case _TreeNode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TreeNode value)?  $default,){
final _that = this;
switch (_that) {
case _TreeNode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String seedType,  String id,  String? key,  List<DiagnosticsProperty> properties,  List<TreeNode> children)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TreeNode() when $default != null:
return $default(_that.seedType,_that.id,_that.key,_that.properties,_that.children);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String seedType,  String id,  String? key,  List<DiagnosticsProperty> properties,  List<TreeNode> children)  $default,) {final _that = this;
switch (_that) {
case _TreeNode():
return $default(_that.seedType,_that.id,_that.key,_that.properties,_that.children);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String seedType,  String id,  String? key,  List<DiagnosticsProperty> properties,  List<TreeNode> children)?  $default,) {final _that = this;
switch (_that) {
case _TreeNode() when $default != null:
return $default(_that.seedType,_that.id,_that.key,_that.properties,_that.children);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TreeNode implements TreeNode {
  const _TreeNode({required this.seedType, required this.id, this.key, required final  List<DiagnosticsProperty> properties, required final  List<TreeNode> children}): _properties = properties,_children = children;
  factory _TreeNode.fromJson(Map<String, dynamic> json) => _$TreeNodeFromJson(json);

@override final  String seedType;
@override final  String id;
@override final  String? key;
 final  List<DiagnosticsProperty> _properties;
@override List<DiagnosticsProperty> get properties {
  if (_properties is EqualUnmodifiableListView) return _properties;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_properties);
}

 final  List<TreeNode> _children;
@override List<TreeNode> get children {
  if (_children is EqualUnmodifiableListView) return _children;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_children);
}


/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TreeNodeCopyWith<_TreeNode> get copyWith => __$TreeNodeCopyWithImpl<_TreeNode>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TreeNodeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TreeNode&&(identical(other.seedType, seedType) || other.seedType == seedType)&&(identical(other.id, id) || other.id == id)&&(identical(other.key, key) || other.key == key)&&const DeepCollectionEquality().equals(other._properties, _properties)&&const DeepCollectionEquality().equals(other._children, _children));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,seedType,id,key,const DeepCollectionEquality().hash(_properties),const DeepCollectionEquality().hash(_children));

@override
String toString() {
  return 'TreeNode(seedType: $seedType, id: $id, key: $key, properties: $properties, children: $children)';
}


}

/// @nodoc
abstract mixin class _$TreeNodeCopyWith<$Res> implements $TreeNodeCopyWith<$Res> {
  factory _$TreeNodeCopyWith(_TreeNode value, $Res Function(_TreeNode) _then) = __$TreeNodeCopyWithImpl;
@override @useResult
$Res call({
 String seedType, String id, String? key, List<DiagnosticsProperty> properties, List<TreeNode> children
});




}
/// @nodoc
class __$TreeNodeCopyWithImpl<$Res>
    implements _$TreeNodeCopyWith<$Res> {
  __$TreeNodeCopyWithImpl(this._self, this._then);

  final _TreeNode _self;
  final $Res Function(_TreeNode) _then;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? seedType = null,Object? id = null,Object? key = freezed,Object? properties = null,Object? children = null,}) {
  return _then(_TreeNode(
seedType: null == seedType ? _self.seedType : seedType // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,key: freezed == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String?,properties: null == properties ? _self._properties : properties // ignore: cast_nullable_to_non_nullable
as List<DiagnosticsProperty>,children: null == children ? _self._children : children // ignore: cast_nullable_to_non_nullable
as List<TreeNode>,
  ));
}


}

// dart format on
