// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset_catalog_resolver.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AssetCatalogSubstation {

 String get substation; String get root; Map<AssetKey, bool> get overrides;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetCatalogSubstation&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.root, root) || other.root == root)&&const DeepCollectionEquality().equals(other.overrides, overrides));
}


@override
int get hashCode => Object.hash(runtimeType,substation,root,const DeepCollectionEquality().hash(overrides));

@override
String toString() {
  return 'AssetCatalogSubstation(substation: $substation, root: $root, overrides: $overrides)';
}


}




/// Adds pattern-matching-related methods to [AssetCatalogSubstation].
extension AssetCatalogSubstationPatterns on AssetCatalogSubstation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssetCatalogSubstation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssetCatalogSubstation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssetCatalogSubstation value)  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogSubstation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssetCatalogSubstation value)?  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogSubstation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String substation,  String root,  Map<AssetKey, bool> overrides)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssetCatalogSubstation() when $default != null:
return $default(_that.substation,_that.root,_that.overrides);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String substation,  String root,  Map<AssetKey, bool> overrides)  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogSubstation():
return $default(_that.substation,_that.root,_that.overrides);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String substation,  String root,  Map<AssetKey, bool> overrides)?  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogSubstation() when $default != null:
return $default(_that.substation,_that.root,_that.overrides);case _:
  return null;

}
}

}

/// @nodoc


class _AssetCatalogSubstation implements AssetCatalogSubstation {
  const _AssetCatalogSubstation({required this.substation, required this.root, final  Map<AssetKey, bool> overrides = const <AssetKey, bool>{}}): _overrides = overrides;


@override final  String substation;
@override final  String root;
 final  Map<AssetKey, bool> _overrides;
@override@JsonKey() Map<AssetKey, bool> get overrides {
  if (_overrides is EqualUnmodifiableMapView) return _overrides;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_overrides);
}





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssetCatalogSubstation&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.root, root) || other.root == root)&&const DeepCollectionEquality().equals(other._overrides, _overrides));
}


@override
int get hashCode => Object.hash(runtimeType,substation,root,const DeepCollectionEquality().hash(_overrides));

@override
String toString() {
  return 'AssetCatalogSubstation(substation: $substation, root: $root, overrides: $overrides)';
}


}




/// @nodoc
mixin _$AssetCatalogCounts {

 int get total; int get resolved; int get excluded; int get unknown;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetCatalogCounts&&(identical(other.total, total) || other.total == total)&&(identical(other.resolved, resolved) || other.resolved == resolved)&&(identical(other.excluded, excluded) || other.excluded == excluded)&&(identical(other.unknown, unknown) || other.unknown == unknown));
}


@override
int get hashCode => Object.hash(runtimeType,total,resolved,excluded,unknown);

@override
String toString() {
  return 'AssetCatalogCounts(total: $total, resolved: $resolved, excluded: $excluded, unknown: $unknown)';
}


}




/// Adds pattern-matching-related methods to [AssetCatalogCounts].
extension AssetCatalogCountsPatterns on AssetCatalogCounts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssetCatalogCounts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssetCatalogCounts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssetCatalogCounts value)  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogCounts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssetCatalogCounts value)?  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogCounts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int total,  int resolved,  int excluded,  int unknown)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssetCatalogCounts() when $default != null:
return $default(_that.total,_that.resolved,_that.excluded,_that.unknown);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int total,  int resolved,  int excluded,  int unknown)  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogCounts():
return $default(_that.total,_that.resolved,_that.excluded,_that.unknown);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int total,  int resolved,  int excluded,  int unknown)?  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogCounts() when $default != null:
return $default(_that.total,_that.resolved,_that.excluded,_that.unknown);case _:
  return null;

}
}

}

/// @nodoc


class _AssetCatalogCounts extends AssetCatalogCounts {
  const _AssetCatalogCounts({required this.total, required this.resolved, required this.excluded, required this.unknown}): super._();


@override final  int total;
@override final  int resolved;
@override final  int excluded;
@override final  int unknown;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssetCatalogCounts&&(identical(other.total, total) || other.total == total)&&(identical(other.resolved, resolved) || other.resolved == resolved)&&(identical(other.excluded, excluded) || other.excluded == excluded)&&(identical(other.unknown, unknown) || other.unknown == unknown));
}


@override
int get hashCode => Object.hash(runtimeType,total,resolved,excluded,unknown);

@override
String toString() {
  return 'AssetCatalogCounts(total: $total, resolved: $resolved, excluded: $excluded, unknown: $unknown)';
}


}




/// @nodoc
mixin _$AssetParticipation {

 String get decidedBy; String get reason;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetParticipation&&(identical(other.decidedBy, decidedBy) || other.decidedBy == decidedBy)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,decidedBy,reason);

@override
String toString() {
  return 'AssetParticipation(decidedBy: $decidedBy, reason: $reason)';
}


}




/// Adds pattern-matching-related methods to [AssetParticipation].
extension AssetParticipationPatterns on AssetParticipation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AssetResolved value)?  resolved,TResult Function( AssetExcluded value)?  excluded,TResult Function( AssetUnknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AssetResolved() when resolved != null:
return resolved(_that);case AssetExcluded() when excluded != null:
return excluded(_that);case AssetUnknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AssetResolved value)  resolved,required TResult Function( AssetExcluded value)  excluded,required TResult Function( AssetUnknown value)  unknown,}){
final _that = this;
switch (_that) {
case AssetResolved():
return resolved(_that);case AssetExcluded():
return excluded(_that);case AssetUnknown():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AssetResolved value)?  resolved,TResult? Function( AssetExcluded value)?  excluded,TResult? Function( AssetUnknown value)?  unknown,}){
final _that = this;
switch (_that) {
case AssetResolved() when resolved != null:
return resolved(_that);case AssetExcluded() when excluded != null:
return excluded(_that);case AssetUnknown() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String decidedBy,  String reason)?  resolved,TResult Function( String decidedBy,  String reason)?  excluded,TResult Function( String decidedBy,  String reason)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AssetResolved() when resolved != null:
return resolved(_that.decidedBy,_that.reason);case AssetExcluded() when excluded != null:
return excluded(_that.decidedBy,_that.reason);case AssetUnknown() when unknown != null:
return unknown(_that.decidedBy,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String decidedBy,  String reason)  resolved,required TResult Function( String decidedBy,  String reason)  excluded,required TResult Function( String decidedBy,  String reason)  unknown,}) {final _that = this;
switch (_that) {
case AssetResolved():
return resolved(_that.decidedBy,_that.reason);case AssetExcluded():
return excluded(_that.decidedBy,_that.reason);case AssetUnknown():
return unknown(_that.decidedBy,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String decidedBy,  String reason)?  resolved,TResult? Function( String decidedBy,  String reason)?  excluded,TResult? Function( String decidedBy,  String reason)?  unknown,}) {final _that = this;
switch (_that) {
case AssetResolved() when resolved != null:
return resolved(_that.decidedBy,_that.reason);case AssetExcluded() when excluded != null:
return excluded(_that.decidedBy,_that.reason);case AssetUnknown() when unknown != null:
return unknown(_that.decidedBy,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AssetResolved extends AssetParticipation {
  const AssetResolved({required this.decidedBy, required this.reason}): super._();


@override final  String decidedBy;
@override final  String reason;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetResolved&&(identical(other.decidedBy, decidedBy) || other.decidedBy == decidedBy)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,decidedBy,reason);

@override
String toString() {
  return 'AssetParticipation.resolved(decidedBy: $decidedBy, reason: $reason)';
}


}




/// @nodoc


class AssetExcluded extends AssetParticipation {
  const AssetExcluded({required this.decidedBy, required this.reason}): super._();


@override final  String decidedBy;
@override final  String reason;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetExcluded&&(identical(other.decidedBy, decidedBy) || other.decidedBy == decidedBy)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,decidedBy,reason);

@override
String toString() {
  return 'AssetParticipation.excluded(decidedBy: $decidedBy, reason: $reason)';
}


}




/// @nodoc


class AssetUnknown extends AssetParticipation {
  const AssetUnknown({required this.decidedBy, required this.reason}): super._();


@override final  String decidedBy;
@override final  String reason;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetUnknown&&(identical(other.decidedBy, decidedBy) || other.decidedBy == decidedBy)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,decidedBy,reason);

@override
String toString() {
  return 'AssetParticipation.unknown(decidedBy: $decidedBy, reason: $reason)';
}


}




/// @nodoc
mixin _$AssetCatalogEntry {

 String get id; String get kind; String get pack; String get description; String get visibility; String get audience; Map<String, Object?> get selector; AssetParticipation get participation;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetCatalogEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.pack, pack) || other.pack == pack)&&(identical(other.description, description) || other.description == description)&&(identical(other.visibility, visibility) || other.visibility == visibility)&&(identical(other.audience, audience) || other.audience == audience)&&const DeepCollectionEquality().equals(other.selector, selector)&&(identical(other.participation, participation) || other.participation == participation));
}


@override
int get hashCode => Object.hash(runtimeType,id,kind,pack,description,visibility,audience,const DeepCollectionEquality().hash(selector),participation);

@override
String toString() {
  return 'AssetCatalogEntry(id: $id, kind: $kind, pack: $pack, description: $description, visibility: $visibility, audience: $audience, selector: $selector, participation: $participation)';
}


}




/// Adds pattern-matching-related methods to [AssetCatalogEntry].
extension AssetCatalogEntryPatterns on AssetCatalogEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssetCatalogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssetCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssetCatalogEntry value)  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssetCatalogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String kind,  String pack,  String description,  String visibility,  String audience,  Map<String, Object?> selector,  AssetParticipation participation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssetCatalogEntry() when $default != null:
return $default(_that.id,_that.kind,_that.pack,_that.description,_that.visibility,_that.audience,_that.selector,_that.participation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String kind,  String pack,  String description,  String visibility,  String audience,  Map<String, Object?> selector,  AssetParticipation participation)  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogEntry():
return $default(_that.id,_that.kind,_that.pack,_that.description,_that.visibility,_that.audience,_that.selector,_that.participation);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String kind,  String pack,  String description,  String visibility,  String audience,  Map<String, Object?> selector,  AssetParticipation participation)?  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogEntry() when $default != null:
return $default(_that.id,_that.kind,_that.pack,_that.description,_that.visibility,_that.audience,_that.selector,_that.participation);case _:
  return null;

}
}

}

/// @nodoc


class _AssetCatalogEntry extends AssetCatalogEntry {
  const _AssetCatalogEntry({required this.id, required this.kind, required this.pack, required this.description, required this.visibility, required this.audience, required final  Map<String, Object?> selector, required this.participation}): _selector = selector,super._();


@override final  String id;
@override final  String kind;
@override final  String pack;
@override final  String description;
@override final  String visibility;
@override final  String audience;
 final  Map<String, Object?> _selector;
@override Map<String, Object?> get selector {
  if (_selector is EqualUnmodifiableMapView) return _selector;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_selector);
}

@override final  AssetParticipation participation;




@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssetCatalogEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.pack, pack) || other.pack == pack)&&(identical(other.description, description) || other.description == description)&&(identical(other.visibility, visibility) || other.visibility == visibility)&&(identical(other.audience, audience) || other.audience == audience)&&const DeepCollectionEquality().equals(other._selector, _selector)&&(identical(other.participation, participation) || other.participation == participation));
}


@override
int get hashCode => Object.hash(runtimeType,id,kind,pack,description,visibility,audience,const DeepCollectionEquality().hash(_selector),participation);

@override
String toString() {
  return 'AssetCatalogEntry(id: $id, kind: $kind, pack: $pack, description: $description, visibility: $visibility, audience: $audience, selector: $selector, participation: $participation)';
}


}




/// @nodoc
mixin _$AssetCatalogReport {

 String? get substation; AssetCatalogCounts get counts; List<AssetCatalogEntry> get assets;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AssetCatalogReport&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.counts, counts) || other.counts == counts)&&const DeepCollectionEquality().equals(other.assets, assets));
}


@override
int get hashCode => Object.hash(runtimeType,substation,counts,const DeepCollectionEquality().hash(assets));

@override
String toString() {
  return 'AssetCatalogReport(substation: $substation, counts: $counts, assets: $assets)';
}


}




/// Adds pattern-matching-related methods to [AssetCatalogReport].
extension AssetCatalogReportPatterns on AssetCatalogReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AssetCatalogReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AssetCatalogReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AssetCatalogReport value)  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AssetCatalogReport value)?  $default,){
final _that = this;
switch (_that) {
case _AssetCatalogReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? substation,  AssetCatalogCounts counts,  List<AssetCatalogEntry> assets)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AssetCatalogReport() when $default != null:
return $default(_that.substation,_that.counts,_that.assets);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? substation,  AssetCatalogCounts counts,  List<AssetCatalogEntry> assets)  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogReport():
return $default(_that.substation,_that.counts,_that.assets);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? substation,  AssetCatalogCounts counts,  List<AssetCatalogEntry> assets)?  $default,) {final _that = this;
switch (_that) {
case _AssetCatalogReport() when $default != null:
return $default(_that.substation,_that.counts,_that.assets);case _:
  return null;

}
}

}

/// @nodoc


class _AssetCatalogReport extends AssetCatalogReport {
  const _AssetCatalogReport({required this.substation, required this.counts, required final  List<AssetCatalogEntry> assets}): _assets = assets,super._();


@override final  String? substation;
@override final  AssetCatalogCounts counts;
 final  List<AssetCatalogEntry> _assets;
@override List<AssetCatalogEntry> get assets {
  if (_assets is EqualUnmodifiableListView) return _assets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_assets);
}





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AssetCatalogReport&&(identical(other.substation, substation) || other.substation == substation)&&(identical(other.counts, counts) || other.counts == counts)&&const DeepCollectionEquality().equals(other._assets, _assets));
}


@override
int get hashCode => Object.hash(runtimeType,substation,counts,const DeepCollectionEquality().hash(_assets));

@override
String toString() {
  return 'AssetCatalogReport(substation: $substation, counts: $counts, assets: $assets)';
}


}




// dart format on
