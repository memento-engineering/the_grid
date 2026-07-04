// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'substation_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SubstationConfig {

/// The rig's id (its issue-id prefix and `metadata.rig` marker).
 String get substationId;/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
 Set<String> get ownedSubstations;/// The blessed-bead **drive-list** (ADR-0006): when non-empty, ONLY these
/// bead ids mount a work node + spawn an agent (`WorkList` enforces it at the
/// mount boundary). Empty = no per-bead restriction (dev / dry-run observes
/// all owned dispatchable work); a LIVE run refuses an empty drive-list
/// upstream (`runGridTree` gating), so this gate is active whenever armed.
/// Orthogonal to [ownedSubstations]: ownership says *whose* beads, the
/// drive-list says *which specific* beads Nico has blessed for this arm.
 Set<String> get driveList;/// Resident all-ready arming (RS-3/D-R4): when true, `WorkList` narrows
/// the mount boundary to the DRIVEABLE-WORK types (`task`/`bug`/
/// `feature`/`chore`) ON TOP of the existing A41 `isCore` allow-list — a
/// resident station's ready frontier must never auto-mount an
/// organizational bead (epic/milestone/decision) just because it surfaced
/// ready. Orthogonal to [driveList]: under resident arming the drive-list
/// is always empty (`validateArming` refuses a `--bead`) — this narrows
/// WHICH TYPES of the all-ready frontier are driveable, not which ids.
 bool get resident;/// The registered root NAMES available to this substation's work (tg-7gm,
/// `docs/SCRATCH-grid-alignment.md` §6 amendment) — a bead mounts only when
/// its resolved target root (`metadata.grid.root`, defaulting to the
/// bead's own substation) is a member. EMPTY means UNCONSTRAINED (no
/// `--root` wired — dry-run's/an offline test's default): every owned
/// bead mounts regardless of rooting, exactly today's pre-multi-root
/// behavior. Non-empty activates the gate: an owned bead whose target
/// root is absent from this set is an ARMING-CLASS refusal AT THE MOUNT
/// BOUNDARY (a LOUD skip, never a station-wide gate — the
/// `SCRATCH-orchestration-determinism` §5 failure-discrimination
/// principle) — other owned beads keep mounting.
 Set<String> get registeredRoots;/// The concurrency governor's PER-SUBSTATION override (tg-42f,
/// declare-and-check): the most `WorkList` will mount concurrently for
/// THIS substation. Null (the default) falls back to the station-wide
/// default (`StationServices.maxConcurrentWork`). Either way the
/// station-wide TOTAL across every substation is a hard ceiling this
/// override cannot raise — it only narrows within it. A bead beyond the
/// budget stays ready-unmounted (no session, no spawn, no cost) and mounts
/// on the next reconcile once a slot frees.
 int? get maxConcurrentWork;
/// Create a copy of SubstationConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubstationConfigCopyWith<SubstationConfig> get copyWith => _$SubstationConfigCopyWithImpl<SubstationConfig>(this as SubstationConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SubstationConfig&&(identical(other.substationId, substationId) || other.substationId == substationId)&&const DeepCollectionEquality().equals(other.ownedSubstations, ownedSubstations)&&const DeepCollectionEquality().equals(other.driveList, driveList)&&(identical(other.resident, resident) || other.resident == resident)&&const DeepCollectionEquality().equals(other.registeredRoots, registeredRoots)&&(identical(other.maxConcurrentWork, maxConcurrentWork) || other.maxConcurrentWork == maxConcurrentWork));
}


@override
int get hashCode => Object.hash(runtimeType,substationId,const DeepCollectionEquality().hash(ownedSubstations),const DeepCollectionEquality().hash(driveList),resident,const DeepCollectionEquality().hash(registeredRoots),maxConcurrentWork);

@override
String toString() {
  return 'SubstationConfig(substationId: $substationId, ownedSubstations: $ownedSubstations, driveList: $driveList, resident: $resident, registeredRoots: $registeredRoots, maxConcurrentWork: $maxConcurrentWork)';
}


}

/// @nodoc
abstract mixin class $SubstationConfigCopyWith<$Res>  {
  factory $SubstationConfigCopyWith(SubstationConfig value, $Res Function(SubstationConfig) _then) = _$SubstationConfigCopyWithImpl;
@useResult
$Res call({
 String substationId, Set<String> ownedSubstations, Set<String> driveList, bool resident, Set<String> registeredRoots, int? maxConcurrentWork
});




}
/// @nodoc
class _$SubstationConfigCopyWithImpl<$Res>
    implements $SubstationConfigCopyWith<$Res> {
  _$SubstationConfigCopyWithImpl(this._self, this._then);

  final SubstationConfig _self;
  final $Res Function(SubstationConfig) _then;

/// Create a copy of SubstationConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? substationId = null,Object? ownedSubstations = null,Object? driveList = null,Object? resident = null,Object? registeredRoots = null,Object? maxConcurrentWork = freezed,}) {
  return _then(_self.copyWith(
substationId: null == substationId ? _self.substationId : substationId // ignore: cast_nullable_to_non_nullable
as String,ownedSubstations: null == ownedSubstations ? _self.ownedSubstations : ownedSubstations // ignore: cast_nullable_to_non_nullable
as Set<String>,driveList: null == driveList ? _self.driveList : driveList // ignore: cast_nullable_to_non_nullable
as Set<String>,resident: null == resident ? _self.resident : resident // ignore: cast_nullable_to_non_nullable
as bool,registeredRoots: null == registeredRoots ? _self.registeredRoots : registeredRoots // ignore: cast_nullable_to_non_nullable
as Set<String>,maxConcurrentWork: freezed == maxConcurrentWork ? _self.maxConcurrentWork : maxConcurrentWork // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [SubstationConfig].
extension SubstationConfigPatterns on SubstationConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SubstationConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SubstationConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SubstationConfig value)  $default,){
final _that = this;
switch (_that) {
case _SubstationConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SubstationConfig value)?  $default,){
final _that = this;
switch (_that) {
case _SubstationConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String substationId,  Set<String> ownedSubstations,  Set<String> driveList,  bool resident,  Set<String> registeredRoots,  int? maxConcurrentWork)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SubstationConfig() when $default != null:
return $default(_that.substationId,_that.ownedSubstations,_that.driveList,_that.resident,_that.registeredRoots,_that.maxConcurrentWork);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String substationId,  Set<String> ownedSubstations,  Set<String> driveList,  bool resident,  Set<String> registeredRoots,  int? maxConcurrentWork)  $default,) {final _that = this;
switch (_that) {
case _SubstationConfig():
return $default(_that.substationId,_that.ownedSubstations,_that.driveList,_that.resident,_that.registeredRoots,_that.maxConcurrentWork);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String substationId,  Set<String> ownedSubstations,  Set<String> driveList,  bool resident,  Set<String> registeredRoots,  int? maxConcurrentWork)?  $default,) {final _that = this;
switch (_that) {
case _SubstationConfig() when $default != null:
return $default(_that.substationId,_that.ownedSubstations,_that.driveList,_that.resident,_that.registeredRoots,_that.maxConcurrentWork);case _:
  return null;

}
}

}

/// @nodoc


class _SubstationConfig implements SubstationConfig {
  const _SubstationConfig({required this.substationId, final  Set<String> ownedSubstations = const <String>{}, final  Set<String> driveList = const <String>{}, this.resident = false, final  Set<String> registeredRoots = const <String>{}, this.maxConcurrentWork}): _ownedSubstations = ownedSubstations,_driveList = driveList,_registeredRoots = registeredRoots;
  

/// The rig's id (its issue-id prefix and `metadata.rig` marker).
@override final  String substationId;
/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
 final  Set<String> _ownedSubstations;
/// The rig allow-set: the prefixes/markers the_grid owns and may dispatch
/// against (fail-closed — an empty set owns nothing).
@override@JsonKey() Set<String> get ownedSubstations {
  if (_ownedSubstations is EqualUnmodifiableSetView) return _ownedSubstations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_ownedSubstations);
}

/// The blessed-bead **drive-list** (ADR-0006): when non-empty, ONLY these
/// bead ids mount a work node + spawn an agent (`WorkList` enforces it at the
/// mount boundary). Empty = no per-bead restriction (dev / dry-run observes
/// all owned dispatchable work); a LIVE run refuses an empty drive-list
/// upstream (`runGridTree` gating), so this gate is active whenever armed.
/// Orthogonal to [ownedSubstations]: ownership says *whose* beads, the
/// drive-list says *which specific* beads Nico has blessed for this arm.
 final  Set<String> _driveList;
/// The blessed-bead **drive-list** (ADR-0006): when non-empty, ONLY these
/// bead ids mount a work node + spawn an agent (`WorkList` enforces it at the
/// mount boundary). Empty = no per-bead restriction (dev / dry-run observes
/// all owned dispatchable work); a LIVE run refuses an empty drive-list
/// upstream (`runGridTree` gating), so this gate is active whenever armed.
/// Orthogonal to [ownedSubstations]: ownership says *whose* beads, the
/// drive-list says *which specific* beads Nico has blessed for this arm.
@override@JsonKey() Set<String> get driveList {
  if (_driveList is EqualUnmodifiableSetView) return _driveList;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_driveList);
}

/// Resident all-ready arming (RS-3/D-R4): when true, `WorkList` narrows
/// the mount boundary to the DRIVEABLE-WORK types (`task`/`bug`/
/// `feature`/`chore`) ON TOP of the existing A41 `isCore` allow-list — a
/// resident station's ready frontier must never auto-mount an
/// organizational bead (epic/milestone/decision) just because it surfaced
/// ready. Orthogonal to [driveList]: under resident arming the drive-list
/// is always empty (`validateArming` refuses a `--bead`) — this narrows
/// WHICH TYPES of the all-ready frontier are driveable, not which ids.
@override@JsonKey() final  bool resident;
/// The registered root NAMES available to this substation's work (tg-7gm,
/// `docs/SCRATCH-grid-alignment.md` §6 amendment) — a bead mounts only when
/// its resolved target root (`metadata.grid.root`, defaulting to the
/// bead's own substation) is a member. EMPTY means UNCONSTRAINED (no
/// `--root` wired — dry-run's/an offline test's default): every owned
/// bead mounts regardless of rooting, exactly today's pre-multi-root
/// behavior. Non-empty activates the gate: an owned bead whose target
/// root is absent from this set is an ARMING-CLASS refusal AT THE MOUNT
/// BOUNDARY (a LOUD skip, never a station-wide gate — the
/// `SCRATCH-orchestration-determinism` §5 failure-discrimination
/// principle) — other owned beads keep mounting.
 final  Set<String> _registeredRoots;
/// The registered root NAMES available to this substation's work (tg-7gm,
/// `docs/SCRATCH-grid-alignment.md` §6 amendment) — a bead mounts only when
/// its resolved target root (`metadata.grid.root`, defaulting to the
/// bead's own substation) is a member. EMPTY means UNCONSTRAINED (no
/// `--root` wired — dry-run's/an offline test's default): every owned
/// bead mounts regardless of rooting, exactly today's pre-multi-root
/// behavior. Non-empty activates the gate: an owned bead whose target
/// root is absent from this set is an ARMING-CLASS refusal AT THE MOUNT
/// BOUNDARY (a LOUD skip, never a station-wide gate — the
/// `SCRATCH-orchestration-determinism` §5 failure-discrimination
/// principle) — other owned beads keep mounting.
@override@JsonKey() Set<String> get registeredRoots {
  if (_registeredRoots is EqualUnmodifiableSetView) return _registeredRoots;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_registeredRoots);
}

/// The concurrency governor's PER-SUBSTATION override (tg-42f,
/// declare-and-check): the most `WorkList` will mount concurrently for
/// THIS substation. Null (the default) falls back to the station-wide
/// default (`StationServices.maxConcurrentWork`). Either way the
/// station-wide TOTAL across every substation is a hard ceiling this
/// override cannot raise — it only narrows within it. A bead beyond the
/// budget stays ready-unmounted (no session, no spawn, no cost) and mounts
/// on the next reconcile once a slot frees.
@override final  int? maxConcurrentWork;

/// Create a copy of SubstationConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubstationConfigCopyWith<_SubstationConfig> get copyWith => __$SubstationConfigCopyWithImpl<_SubstationConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SubstationConfig&&(identical(other.substationId, substationId) || other.substationId == substationId)&&const DeepCollectionEquality().equals(other._ownedSubstations, _ownedSubstations)&&const DeepCollectionEquality().equals(other._driveList, _driveList)&&(identical(other.resident, resident) || other.resident == resident)&&const DeepCollectionEquality().equals(other._registeredRoots, _registeredRoots)&&(identical(other.maxConcurrentWork, maxConcurrentWork) || other.maxConcurrentWork == maxConcurrentWork));
}


@override
int get hashCode => Object.hash(runtimeType,substationId,const DeepCollectionEquality().hash(_ownedSubstations),const DeepCollectionEquality().hash(_driveList),resident,const DeepCollectionEquality().hash(_registeredRoots),maxConcurrentWork);

@override
String toString() {
  return 'SubstationConfig(substationId: $substationId, ownedSubstations: $ownedSubstations, driveList: $driveList, resident: $resident, registeredRoots: $registeredRoots, maxConcurrentWork: $maxConcurrentWork)';
}


}

/// @nodoc
abstract mixin class _$SubstationConfigCopyWith<$Res> implements $SubstationConfigCopyWith<$Res> {
  factory _$SubstationConfigCopyWith(_SubstationConfig value, $Res Function(_SubstationConfig) _then) = __$SubstationConfigCopyWithImpl;
@override @useResult
$Res call({
 String substationId, Set<String> ownedSubstations, Set<String> driveList, bool resident, Set<String> registeredRoots, int? maxConcurrentWork
});




}
/// @nodoc
class __$SubstationConfigCopyWithImpl<$Res>
    implements _$SubstationConfigCopyWith<$Res> {
  __$SubstationConfigCopyWithImpl(this._self, this._then);

  final _SubstationConfig _self;
  final $Res Function(_SubstationConfig) _then;

/// Create a copy of SubstationConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? substationId = null,Object? ownedSubstations = null,Object? driveList = null,Object? resident = null,Object? registeredRoots = null,Object? maxConcurrentWork = freezed,}) {
  return _then(_SubstationConfig(
substationId: null == substationId ? _self.substationId : substationId // ignore: cast_nullable_to_non_nullable
as String,ownedSubstations: null == ownedSubstations ? _self._ownedSubstations : ownedSubstations // ignore: cast_nullable_to_non_nullable
as Set<String>,driveList: null == driveList ? _self._driveList : driveList // ignore: cast_nullable_to_non_nullable
as Set<String>,resident: null == resident ? _self.resident : resident // ignore: cast_nullable_to_non_nullable
as bool,registeredRoots: null == registeredRoots ? _self._registeredRoots : registeredRoots // ignore: cast_nullable_to_non_nullable
as Set<String>,maxConcurrentWork: freezed == maxConcurrentWork ? _self.maxConcurrentWork : maxConcurrentWork // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
