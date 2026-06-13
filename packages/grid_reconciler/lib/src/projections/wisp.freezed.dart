// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wisp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SpeculativeNode {

 String get id;/// `gc.deferred_type` (molecule.go:73) — the real bead type the node
/// is promoted back to on activation (convergence_store.go:224-226).
 String? get deferredType;/// `gc.deferred_assignee` (molecule.go:60) — restored as the assignee
/// (convergence_store.go:214-216).
 String? get deferredAssignee;/// `gc.deferred_routed_to` (molecule.go:64) — restored as
/// `gc.routed_to` (convergence_store.go:218-220).
 String? get deferredRoutedTo;/// `gc.deferred_execution_routed_to` (molecule.go:68) — restored as
/// `gc.execution_routed_to` (convergence_store.go:221-223).
 String? get deferredExecutionRoutedTo;
/// Create a copy of SpeculativeNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SpeculativeNodeCopyWith<SpeculativeNode> get copyWith => _$SpeculativeNodeCopyWithImpl<SpeculativeNode>(this as SpeculativeNode, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SpeculativeNode&&(identical(other.id, id) || other.id == id)&&(identical(other.deferredType, deferredType) || other.deferredType == deferredType)&&(identical(other.deferredAssignee, deferredAssignee) || other.deferredAssignee == deferredAssignee)&&(identical(other.deferredRoutedTo, deferredRoutedTo) || other.deferredRoutedTo == deferredRoutedTo)&&(identical(other.deferredExecutionRoutedTo, deferredExecutionRoutedTo) || other.deferredExecutionRoutedTo == deferredExecutionRoutedTo));
}


@override
int get hashCode => Object.hash(runtimeType,id,deferredType,deferredAssignee,deferredRoutedTo,deferredExecutionRoutedTo);

@override
String toString() {
  return 'SpeculativeNode(id: $id, deferredType: $deferredType, deferredAssignee: $deferredAssignee, deferredRoutedTo: $deferredRoutedTo, deferredExecutionRoutedTo: $deferredExecutionRoutedTo)';
}


}

/// @nodoc
abstract mixin class $SpeculativeNodeCopyWith<$Res>  {
  factory $SpeculativeNodeCopyWith(SpeculativeNode value, $Res Function(SpeculativeNode) _then) = _$SpeculativeNodeCopyWithImpl;
@useResult
$Res call({
 String id, String? deferredType, String? deferredAssignee, String? deferredRoutedTo, String? deferredExecutionRoutedTo
});




}
/// @nodoc
class _$SpeculativeNodeCopyWithImpl<$Res>
    implements $SpeculativeNodeCopyWith<$Res> {
  _$SpeculativeNodeCopyWithImpl(this._self, this._then);

  final SpeculativeNode _self;
  final $Res Function(SpeculativeNode) _then;

/// Create a copy of SpeculativeNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? deferredType = freezed,Object? deferredAssignee = freezed,Object? deferredRoutedTo = freezed,Object? deferredExecutionRoutedTo = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deferredType: freezed == deferredType ? _self.deferredType : deferredType // ignore: cast_nullable_to_non_nullable
as String?,deferredAssignee: freezed == deferredAssignee ? _self.deferredAssignee : deferredAssignee // ignore: cast_nullable_to_non_nullable
as String?,deferredRoutedTo: freezed == deferredRoutedTo ? _self.deferredRoutedTo : deferredRoutedTo // ignore: cast_nullable_to_non_nullable
as String?,deferredExecutionRoutedTo: freezed == deferredExecutionRoutedTo ? _self.deferredExecutionRoutedTo : deferredExecutionRoutedTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SpeculativeNode].
extension SpeculativeNodePatterns on SpeculativeNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SpeculativeNode value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SpeculativeNode() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SpeculativeNode value)  $default,){
final _that = this;
switch (_that) {
case _SpeculativeNode():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SpeculativeNode value)?  $default,){
final _that = this;
switch (_that) {
case _SpeculativeNode() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? deferredType,  String? deferredAssignee,  String? deferredRoutedTo,  String? deferredExecutionRoutedTo)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SpeculativeNode() when $default != null:
return $default(_that.id,_that.deferredType,_that.deferredAssignee,_that.deferredRoutedTo,_that.deferredExecutionRoutedTo);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? deferredType,  String? deferredAssignee,  String? deferredRoutedTo,  String? deferredExecutionRoutedTo)  $default,) {final _that = this;
switch (_that) {
case _SpeculativeNode():
return $default(_that.id,_that.deferredType,_that.deferredAssignee,_that.deferredRoutedTo,_that.deferredExecutionRoutedTo);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? deferredType,  String? deferredAssignee,  String? deferredRoutedTo,  String? deferredExecutionRoutedTo)?  $default,) {final _that = this;
switch (_that) {
case _SpeculativeNode() when $default != null:
return $default(_that.id,_that.deferredType,_that.deferredAssignee,_that.deferredRoutedTo,_that.deferredExecutionRoutedTo);case _:
  return null;

}
}

}

/// @nodoc


class _SpeculativeNode extends SpeculativeNode {
  const _SpeculativeNode({required this.id, this.deferredType, this.deferredAssignee, this.deferredRoutedTo, this.deferredExecutionRoutedTo}): super._();
  

@override final  String id;
/// `gc.deferred_type` (molecule.go:73) — the real bead type the node
/// is promoted back to on activation (convergence_store.go:224-226).
@override final  String? deferredType;
/// `gc.deferred_assignee` (molecule.go:60) — restored as the assignee
/// (convergence_store.go:214-216).
@override final  String? deferredAssignee;
/// `gc.deferred_routed_to` (molecule.go:64) — restored as
/// `gc.routed_to` (convergence_store.go:218-220).
@override final  String? deferredRoutedTo;
/// `gc.deferred_execution_routed_to` (molecule.go:68) — restored as
/// `gc.execution_routed_to` (convergence_store.go:221-223).
@override final  String? deferredExecutionRoutedTo;

/// Create a copy of SpeculativeNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SpeculativeNodeCopyWith<_SpeculativeNode> get copyWith => __$SpeculativeNodeCopyWithImpl<_SpeculativeNode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SpeculativeNode&&(identical(other.id, id) || other.id == id)&&(identical(other.deferredType, deferredType) || other.deferredType == deferredType)&&(identical(other.deferredAssignee, deferredAssignee) || other.deferredAssignee == deferredAssignee)&&(identical(other.deferredRoutedTo, deferredRoutedTo) || other.deferredRoutedTo == deferredRoutedTo)&&(identical(other.deferredExecutionRoutedTo, deferredExecutionRoutedTo) || other.deferredExecutionRoutedTo == deferredExecutionRoutedTo));
}


@override
int get hashCode => Object.hash(runtimeType,id,deferredType,deferredAssignee,deferredRoutedTo,deferredExecutionRoutedTo);

@override
String toString() {
  return 'SpeculativeNode(id: $id, deferredType: $deferredType, deferredAssignee: $deferredAssignee, deferredRoutedTo: $deferredRoutedTo, deferredExecutionRoutedTo: $deferredExecutionRoutedTo)';
}


}

/// @nodoc
abstract mixin class _$SpeculativeNodeCopyWith<$Res> implements $SpeculativeNodeCopyWith<$Res> {
  factory _$SpeculativeNodeCopyWith(_SpeculativeNode value, $Res Function(_SpeculativeNode) _then) = __$SpeculativeNodeCopyWithImpl;
@override @useResult
$Res call({
 String id, String? deferredType, String? deferredAssignee, String? deferredRoutedTo, String? deferredExecutionRoutedTo
});




}
/// @nodoc
class __$SpeculativeNodeCopyWithImpl<$Res>
    implements _$SpeculativeNodeCopyWith<$Res> {
  __$SpeculativeNodeCopyWithImpl(this._self, this._then);

  final _SpeculativeNode _self;
  final $Res Function(_SpeculativeNode) _then;

/// Create a copy of SpeculativeNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? deferredType = freezed,Object? deferredAssignee = freezed,Object? deferredRoutedTo = freezed,Object? deferredExecutionRoutedTo = freezed,}) {
  return _then(_SpeculativeNode(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,deferredType: freezed == deferredType ? _self.deferredType : deferredType // ignore: cast_nullable_to_non_nullable
as String?,deferredAssignee: freezed == deferredAssignee ? _self.deferredAssignee : deferredAssignee // ignore: cast_nullable_to_non_nullable
as String?,deferredRoutedTo: freezed == deferredRoutedTo ? _self.deferredRoutedTo : deferredRoutedTo // ignore: cast_nullable_to_non_nullable
as String?,deferredExecutionRoutedTo: freezed == deferredExecutionRoutedTo ? _self.deferredExecutionRoutedTo : deferredExecutionRoutedTo // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$Wisp {

 String get id; String get title; BeadStatus get status; bool get ephemeral;/// The full `converge:{beadID}:iter:{N}` key, verbatim.
 String get idempotencyKey;/// The iteration parsed from [idempotencyKey], or null when the suffix
/// does not parse (gc's `ParseIterationFromKey` ok=false). A null
/// iteration still **counts** toward the closed-wisp count (gc counts by
/// prefix + closed, not by parseability) but is skipped by
/// highest-closed-wisp resolution (reconcile.go:640-643).
 int? get iteration;/// Step children of the **ACTIVATED**-wisp view: children that are
/// step-typed RIGHT NOW. A speculative (deferred) pour creates its
/// actionable nodes as the ready-excluded type `gate` with the real
/// type under `gc.deferred_type` (molecule.go:1009-1026), so for
/// exactly the wisps Track E must activate or burn this list is EMPTY
/// (and `bd children` hides them too — spike-pinned). Enumerate a
/// speculative subtree via [subtreeIds] / [speculativeNodes] instead.
 List<Step> get steps;/// The wisp's full subtree from parent-child edges, in **POST-ORDER**
/// — children before parents, the wisp itself LAST. **Burn order is
/// exactly this list**: gc's burn is a recursive post-order subtree
/// delete (`deleteBeadSubtree`, handler.go:919-933 — each node's
/// children deleted before the node, the root last). Built from the
/// dependency edges alone (a child id missing from the bead map is
/// still included — the edge proves it exists; siblings ordered by id
/// for determinism, where gc takes whatever `Store.Children`
/// returns). Includes EVERY descendant regardless of type — unlike
/// [steps], which filters — because speculative steps are gate-typed
/// and crash-adopted wisps (`adoptWispId` / `adoptPendingWispId` from
/// the snapshot) have no pour-time id map to fall back on.
 List<String> get subtreeIds;/// Every subtree node (the wisp itself included) carrying at least one
/// `gc.deferred_*` key, in **PRE-ORDER** — parent before children,
/// matching the activation recursion (`activateDeferredAssignees`
/// updates the node, then recurses into its children —
/// convergence_store.go:208-246). Empty for an activated or
/// directly-poured wisp. This is the Track E activation worklist: one
/// `bd update` per node promoting the deferred values back.
 List<SpeculativeNode> get speculativeNodes; DateTime? get createdAt; DateTime? get closedAt; String get closeReason;
/// Create a copy of Wisp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WispCopyWith<Wisp> get copyWith => _$WispCopyWithImpl<Wisp>(this as Wisp, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Wisp&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.ephemeral, ephemeral) || other.ephemeral == ephemeral)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&const DeepCollectionEquality().equals(other.steps, steps)&&const DeepCollectionEquality().equals(other.subtreeIds, subtreeIds)&&const DeepCollectionEquality().equals(other.speculativeNodes, speculativeNodes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,ephemeral,idempotencyKey,iteration,const DeepCollectionEquality().hash(steps),const DeepCollectionEquality().hash(subtreeIds),const DeepCollectionEquality().hash(speculativeNodes),createdAt,closedAt,closeReason);

@override
String toString() {
  return 'Wisp(id: $id, title: $title, status: $status, ephemeral: $ephemeral, idempotencyKey: $idempotencyKey, iteration: $iteration, steps: $steps, subtreeIds: $subtreeIds, speculativeNodes: $speculativeNodes, createdAt: $createdAt, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class $WispCopyWith<$Res>  {
  factory $WispCopyWith(Wisp value, $Res Function(Wisp) _then) = _$WispCopyWithImpl;
@useResult
$Res call({
 String id, String title, BeadStatus status, bool ephemeral, String idempotencyKey, int? iteration, List<Step> steps, List<String> subtreeIds, List<SpeculativeNode> speculativeNodes, DateTime? createdAt, DateTime? closedAt, String closeReason
});




}
/// @nodoc
class _$WispCopyWithImpl<$Res>
    implements $WispCopyWith<$Res> {
  _$WispCopyWithImpl(this._self, this._then);

  final Wisp _self;
  final $Res Function(Wisp) _then;

/// Create a copy of Wisp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? status = null,Object? ephemeral = null,Object? idempotencyKey = null,Object? iteration = freezed,Object? steps = null,Object? subtreeIds = null,Object? speculativeNodes = null,Object? createdAt = freezed,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,ephemeral: null == ephemeral ? _self.ephemeral : ephemeral // ignore: cast_nullable_to_non_nullable
as bool,idempotencyKey: null == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String,iteration: freezed == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int?,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,subtreeIds: null == subtreeIds ? _self.subtreeIds : subtreeIds // ignore: cast_nullable_to_non_nullable
as List<String>,speculativeNodes: null == speculativeNodes ? _self.speculativeNodes : speculativeNodes // ignore: cast_nullable_to_non_nullable
as List<SpeculativeNode>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Wisp].
extension WispPatterns on Wisp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Wisp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Wisp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Wisp value)  $default,){
final _that = this;
switch (_that) {
case _Wisp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Wisp value)?  $default,){
final _that = this;
switch (_that) {
case _Wisp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  BeadStatus status,  bool ephemeral,  String idempotencyKey,  int? iteration,  List<Step> steps,  List<String> subtreeIds,  List<SpeculativeNode> speculativeNodes,  DateTime? createdAt,  DateTime? closedAt,  String closeReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Wisp() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.ephemeral,_that.idempotencyKey,_that.iteration,_that.steps,_that.subtreeIds,_that.speculativeNodes,_that.createdAt,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  BeadStatus status,  bool ephemeral,  String idempotencyKey,  int? iteration,  List<Step> steps,  List<String> subtreeIds,  List<SpeculativeNode> speculativeNodes,  DateTime? createdAt,  DateTime? closedAt,  String closeReason)  $default,) {final _that = this;
switch (_that) {
case _Wisp():
return $default(_that.id,_that.title,_that.status,_that.ephemeral,_that.idempotencyKey,_that.iteration,_that.steps,_that.subtreeIds,_that.speculativeNodes,_that.createdAt,_that.closedAt,_that.closeReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  BeadStatus status,  bool ephemeral,  String idempotencyKey,  int? iteration,  List<Step> steps,  List<String> subtreeIds,  List<SpeculativeNode> speculativeNodes,  DateTime? createdAt,  DateTime? closedAt,  String closeReason)?  $default,) {final _that = this;
switch (_that) {
case _Wisp() when $default != null:
return $default(_that.id,_that.title,_that.status,_that.ephemeral,_that.idempotencyKey,_that.iteration,_that.steps,_that.subtreeIds,_that.speculativeNodes,_that.createdAt,_that.closedAt,_that.closeReason);case _:
  return null;

}
}

}

/// @nodoc


class _Wisp extends Wisp {
  const _Wisp({required this.id, required this.title, required this.status, required this.ephemeral, required this.idempotencyKey, required this.iteration, final  List<Step> steps = const <Step>[], final  List<String> subtreeIds = const <String>[], final  List<SpeculativeNode> speculativeNodes = const <SpeculativeNode>[], this.createdAt, this.closedAt, this.closeReason = ''}): _steps = steps,_subtreeIds = subtreeIds,_speculativeNodes = speculativeNodes,super._();
  

@override final  String id;
@override final  String title;
@override final  BeadStatus status;
@override final  bool ephemeral;
/// The full `converge:{beadID}:iter:{N}` key, verbatim.
@override final  String idempotencyKey;
/// The iteration parsed from [idempotencyKey], or null when the suffix
/// does not parse (gc's `ParseIterationFromKey` ok=false). A null
/// iteration still **counts** toward the closed-wisp count (gc counts by
/// prefix + closed, not by parseability) but is skipped by
/// highest-closed-wisp resolution (reconcile.go:640-643).
@override final  int? iteration;
/// Step children of the **ACTIVATED**-wisp view: children that are
/// step-typed RIGHT NOW. A speculative (deferred) pour creates its
/// actionable nodes as the ready-excluded type `gate` with the real
/// type under `gc.deferred_type` (molecule.go:1009-1026), so for
/// exactly the wisps Track E must activate or burn this list is EMPTY
/// (and `bd children` hides them too — spike-pinned). Enumerate a
/// speculative subtree via [subtreeIds] / [speculativeNodes] instead.
 final  List<Step> _steps;
/// Step children of the **ACTIVATED**-wisp view: children that are
/// step-typed RIGHT NOW. A speculative (deferred) pour creates its
/// actionable nodes as the ready-excluded type `gate` with the real
/// type under `gc.deferred_type` (molecule.go:1009-1026), so for
/// exactly the wisps Track E must activate or burn this list is EMPTY
/// (and `bd children` hides them too — spike-pinned). Enumerate a
/// speculative subtree via [subtreeIds] / [speculativeNodes] instead.
@override@JsonKey() List<Step> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

/// The wisp's full subtree from parent-child edges, in **POST-ORDER**
/// — children before parents, the wisp itself LAST. **Burn order is
/// exactly this list**: gc's burn is a recursive post-order subtree
/// delete (`deleteBeadSubtree`, handler.go:919-933 — each node's
/// children deleted before the node, the root last). Built from the
/// dependency edges alone (a child id missing from the bead map is
/// still included — the edge proves it exists; siblings ordered by id
/// for determinism, where gc takes whatever `Store.Children`
/// returns). Includes EVERY descendant regardless of type — unlike
/// [steps], which filters — because speculative steps are gate-typed
/// and crash-adopted wisps (`adoptWispId` / `adoptPendingWispId` from
/// the snapshot) have no pour-time id map to fall back on.
 final  List<String> _subtreeIds;
/// The wisp's full subtree from parent-child edges, in **POST-ORDER**
/// — children before parents, the wisp itself LAST. **Burn order is
/// exactly this list**: gc's burn is a recursive post-order subtree
/// delete (`deleteBeadSubtree`, handler.go:919-933 — each node's
/// children deleted before the node, the root last). Built from the
/// dependency edges alone (a child id missing from the bead map is
/// still included — the edge proves it exists; siblings ordered by id
/// for determinism, where gc takes whatever `Store.Children`
/// returns). Includes EVERY descendant regardless of type — unlike
/// [steps], which filters — because speculative steps are gate-typed
/// and crash-adopted wisps (`adoptWispId` / `adoptPendingWispId` from
/// the snapshot) have no pour-time id map to fall back on.
@override@JsonKey() List<String> get subtreeIds {
  if (_subtreeIds is EqualUnmodifiableListView) return _subtreeIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_subtreeIds);
}

/// Every subtree node (the wisp itself included) carrying at least one
/// `gc.deferred_*` key, in **PRE-ORDER** — parent before children,
/// matching the activation recursion (`activateDeferredAssignees`
/// updates the node, then recurses into its children —
/// convergence_store.go:208-246). Empty for an activated or
/// directly-poured wisp. This is the Track E activation worklist: one
/// `bd update` per node promoting the deferred values back.
 final  List<SpeculativeNode> _speculativeNodes;
/// Every subtree node (the wisp itself included) carrying at least one
/// `gc.deferred_*` key, in **PRE-ORDER** — parent before children,
/// matching the activation recursion (`activateDeferredAssignees`
/// updates the node, then recurses into its children —
/// convergence_store.go:208-246). Empty for an activated or
/// directly-poured wisp. This is the Track E activation worklist: one
/// `bd update` per node promoting the deferred values back.
@override@JsonKey() List<SpeculativeNode> get speculativeNodes {
  if (_speculativeNodes is EqualUnmodifiableListView) return _speculativeNodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_speculativeNodes);
}

@override final  DateTime? createdAt;
@override final  DateTime? closedAt;
@override@JsonKey() final  String closeReason;

/// Create a copy of Wisp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WispCopyWith<_Wisp> get copyWith => __$WispCopyWithImpl<_Wisp>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Wisp&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.status, status) || other.status == status)&&(identical(other.ephemeral, ephemeral) || other.ephemeral == ephemeral)&&(identical(other.idempotencyKey, idempotencyKey) || other.idempotencyKey == idempotencyKey)&&(identical(other.iteration, iteration) || other.iteration == iteration)&&const DeepCollectionEquality().equals(other._steps, _steps)&&const DeepCollectionEquality().equals(other._subtreeIds, _subtreeIds)&&const DeepCollectionEquality().equals(other._speculativeNodes, _speculativeNodes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,status,ephemeral,idempotencyKey,iteration,const DeepCollectionEquality().hash(_steps),const DeepCollectionEquality().hash(_subtreeIds),const DeepCollectionEquality().hash(_speculativeNodes),createdAt,closedAt,closeReason);

@override
String toString() {
  return 'Wisp(id: $id, title: $title, status: $status, ephemeral: $ephemeral, idempotencyKey: $idempotencyKey, iteration: $iteration, steps: $steps, subtreeIds: $subtreeIds, speculativeNodes: $speculativeNodes, createdAt: $createdAt, closedAt: $closedAt, closeReason: $closeReason)';
}


}

/// @nodoc
abstract mixin class _$WispCopyWith<$Res> implements $WispCopyWith<$Res> {
  factory _$WispCopyWith(_Wisp value, $Res Function(_Wisp) _then) = __$WispCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, BeadStatus status, bool ephemeral, String idempotencyKey, int? iteration, List<Step> steps, List<String> subtreeIds, List<SpeculativeNode> speculativeNodes, DateTime? createdAt, DateTime? closedAt, String closeReason
});




}
/// @nodoc
class __$WispCopyWithImpl<$Res>
    implements _$WispCopyWith<$Res> {
  __$WispCopyWithImpl(this._self, this._then);

  final _Wisp _self;
  final $Res Function(_Wisp) _then;

/// Create a copy of Wisp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? status = null,Object? ephemeral = null,Object? idempotencyKey = null,Object? iteration = freezed,Object? steps = null,Object? subtreeIds = null,Object? speculativeNodes = null,Object? createdAt = freezed,Object? closedAt = freezed,Object? closeReason = null,}) {
  return _then(_Wisp(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,ephemeral: null == ephemeral ? _self.ephemeral : ephemeral // ignore: cast_nullable_to_non_nullable
as bool,idempotencyKey: null == idempotencyKey ? _self.idempotencyKey : idempotencyKey // ignore: cast_nullable_to_non_nullable
as String,iteration: freezed == iteration ? _self.iteration : iteration // ignore: cast_nullable_to_non_nullable
as int?,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<Step>,subtreeIds: null == subtreeIds ? _self._subtreeIds : subtreeIds // ignore: cast_nullable_to_non_nullable
as List<String>,speculativeNodes: null == speculativeNodes ? _self._speculativeNodes : speculativeNodes // ignore: cast_nullable_to_non_nullable
as List<SpeculativeNode>,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
