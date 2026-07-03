// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bead.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Bead {

 String get id; String get title; String get description; String get design;@JsonKey(name: 'acceptance_criteria') String get acceptanceCriteria; String get notes;@JsonKey(name: 'spec_id') String get specId;@BeadStatusConverter() BeadStatus get status; int get priority;@JsonKey(name: 'issue_type')@IssueTypeConverter() IssueType get issueType; String get assignee; String get owner;@JsonKey(name: 'estimated_minutes') int? get estimatedMinutes;@JsonKey(name: 'created_at') DateTime? get createdAt;@JsonKey(name: 'created_by') String get createdBy;@JsonKey(name: 'updated_at') DateTime? get updatedAt;@JsonKey(name: 'started_at') DateTime? get startedAt;@JsonKey(name: 'closed_at') DateTime? get closedAt;@JsonKey(name: 'close_reason') String get closeReason;@JsonKey(name: 'closed_by_session') String get closedBySession;@JsonKey(name: 'due_at') DateTime? get dueAt;@JsonKey(name: 'defer_until') DateTime? get deferUntil;@JsonKey(name: 'external_ref') String? get externalRef;@JsonKey(name: 'source_system') String get sourceSystem; Map<String, dynamic> get metadata;@SortedLabelsConverter() List<String> get labels; bool get ephemeral;@JsonKey(name: 'dependency_count') int get dependencyCount;@JsonKey(name: 'dependent_count') int get dependentCount;@JsonKey(name: 'comment_count') int get commentCount;@JsonKey(includeToJson: false) List<BeadComment> get comments;
/// Create a copy of Bead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BeadCopyWith<Bead> get copyWith => _$BeadCopyWithImpl<Bead>(this as Bead, _$identity);

  /// Serializes this Bead to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Bead&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.design, design) || other.design == design)&&(identical(other.acceptanceCriteria, acceptanceCriteria) || other.acceptanceCriteria == acceptanceCriteria)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.specId, specId) || other.specId == specId)&&(identical(other.status, status) || other.status == status)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.issueType, issueType) || other.issueType == issueType)&&(identical(other.assignee, assignee) || other.assignee == assignee)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason)&&(identical(other.closedBySession, closedBySession) || other.closedBySession == closedBySession)&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&(identical(other.deferUntil, deferUntil) || other.deferUntil == deferUntil)&&(identical(other.externalRef, externalRef) || other.externalRef == externalRef)&&(identical(other.sourceSystem, sourceSystem) || other.sourceSystem == sourceSystem)&&const DeepCollectionEquality().equals(other.metadata, metadata)&&const DeepCollectionEquality().equals(other.labels, labels)&&(identical(other.ephemeral, ephemeral) || other.ephemeral == ephemeral)&&(identical(other.dependencyCount, dependencyCount) || other.dependencyCount == dependencyCount)&&(identical(other.dependentCount, dependentCount) || other.dependentCount == dependentCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&const DeepCollectionEquality().equals(other.comments, comments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,description,design,acceptanceCriteria,notes,specId,status,priority,issueType,assignee,owner,estimatedMinutes,createdAt,createdBy,updatedAt,startedAt,closedAt,closeReason,closedBySession,dueAt,deferUntil,externalRef,sourceSystem,const DeepCollectionEquality().hash(metadata),const DeepCollectionEquality().hash(labels),ephemeral,dependencyCount,dependentCount,commentCount,const DeepCollectionEquality().hash(comments)]);

@override
String toString() {
  return 'Bead(id: $id, title: $title, description: $description, design: $design, acceptanceCriteria: $acceptanceCriteria, notes: $notes, specId: $specId, status: $status, priority: $priority, issueType: $issueType, assignee: $assignee, owner: $owner, estimatedMinutes: $estimatedMinutes, createdAt: $createdAt, createdBy: $createdBy, updatedAt: $updatedAt, startedAt: $startedAt, closedAt: $closedAt, closeReason: $closeReason, closedBySession: $closedBySession, dueAt: $dueAt, deferUntil: $deferUntil, externalRef: $externalRef, sourceSystem: $sourceSystem, metadata: $metadata, labels: $labels, ephemeral: $ephemeral, dependencyCount: $dependencyCount, dependentCount: $dependentCount, commentCount: $commentCount, comments: $comments)';
}


}

/// @nodoc
abstract mixin class $BeadCopyWith<$Res>  {
  factory $BeadCopyWith(Bead value, $Res Function(Bead) _then) = _$BeadCopyWithImpl;
@useResult
$Res call({
 String id, String title, String description, String design,@JsonKey(name: 'acceptance_criteria') String acceptanceCriteria, String notes,@JsonKey(name: 'spec_id') String specId,@BeadStatusConverter() BeadStatus status, int priority,@JsonKey(name: 'issue_type')@IssueTypeConverter() IssueType issueType, String assignee, String owner,@JsonKey(name: 'estimated_minutes') int? estimatedMinutes,@JsonKey(name: 'created_at') DateTime? createdAt,@JsonKey(name: 'created_by') String createdBy,@JsonKey(name: 'updated_at') DateTime? updatedAt,@JsonKey(name: 'started_at') DateTime? startedAt,@JsonKey(name: 'closed_at') DateTime? closedAt,@JsonKey(name: 'close_reason') String closeReason,@JsonKey(name: 'closed_by_session') String closedBySession,@JsonKey(name: 'due_at') DateTime? dueAt,@JsonKey(name: 'defer_until') DateTime? deferUntil,@JsonKey(name: 'external_ref') String? externalRef,@JsonKey(name: 'source_system') String sourceSystem, Map<String, dynamic> metadata,@SortedLabelsConverter() List<String> labels, bool ephemeral,@JsonKey(name: 'dependency_count') int dependencyCount,@JsonKey(name: 'dependent_count') int dependentCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(includeToJson: false) List<BeadComment> comments
});




}
/// @nodoc
class _$BeadCopyWithImpl<$Res>
    implements $BeadCopyWith<$Res> {
  _$BeadCopyWithImpl(this._self, this._then);

  final Bead _self;
  final $Res Function(Bead) _then;

/// Create a copy of Bead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? description = null,Object? design = null,Object? acceptanceCriteria = null,Object? notes = null,Object? specId = null,Object? status = null,Object? priority = null,Object? issueType = null,Object? assignee = null,Object? owner = null,Object? estimatedMinutes = freezed,Object? createdAt = freezed,Object? createdBy = null,Object? updatedAt = freezed,Object? startedAt = freezed,Object? closedAt = freezed,Object? closeReason = null,Object? closedBySession = null,Object? dueAt = freezed,Object? deferUntil = freezed,Object? externalRef = freezed,Object? sourceSystem = null,Object? metadata = null,Object? labels = null,Object? ephemeral = null,Object? dependencyCount = null,Object? dependentCount = null,Object? commentCount = null,Object? comments = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,design: null == design ? _self.design : design // ignore: cast_nullable_to_non_nullable
as String,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,specId: null == specId ? _self.specId : specId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,issueType: null == issueType ? _self.issueType : issueType // ignore: cast_nullable_to_non_nullable
as IssueType,assignee: null == assignee ? _self.assignee : assignee // ignore: cast_nullable_to_non_nullable
as String,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,estimatedMinutes: freezed == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,closedBySession: null == closedBySession ? _self.closedBySession : closedBySession // ignore: cast_nullable_to_non_nullable
as String,dueAt: freezed == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deferUntil: freezed == deferUntil ? _self.deferUntil : deferUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,externalRef: freezed == externalRef ? _self.externalRef : externalRef // ignore: cast_nullable_to_non_nullable
as String?,sourceSystem: null == sourceSystem ? _self.sourceSystem : sourceSystem // ignore: cast_nullable_to_non_nullable
as String,metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,labels: null == labels ? _self.labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,ephemeral: null == ephemeral ? _self.ephemeral : ephemeral // ignore: cast_nullable_to_non_nullable
as bool,dependencyCount: null == dependencyCount ? _self.dependencyCount : dependencyCount // ignore: cast_nullable_to_non_nullable
as int,dependentCount: null == dependentCount ? _self.dependentCount : dependentCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,comments: null == comments ? _self.comments : comments // ignore: cast_nullable_to_non_nullable
as List<BeadComment>,
  ));
}

}


/// Adds pattern-matching-related methods to [Bead].
extension BeadPatterns on Bead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Bead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Bead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Bead value)  $default,){
final _that = this;
switch (_that) {
case _Bead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Bead value)?  $default,){
final _that = this;
switch (_that) {
case _Bead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String description,  String design, @JsonKey(name: 'acceptance_criteria')  String acceptanceCriteria,  String notes, @JsonKey(name: 'spec_id')  String specId, @BeadStatusConverter()  BeadStatus status,  int priority, @JsonKey(name: 'issue_type')@IssueTypeConverter()  IssueType issueType,  String assignee,  String owner, @JsonKey(name: 'estimated_minutes')  int? estimatedMinutes, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'started_at')  DateTime? startedAt, @JsonKey(name: 'closed_at')  DateTime? closedAt, @JsonKey(name: 'close_reason')  String closeReason, @JsonKey(name: 'closed_by_session')  String closedBySession, @JsonKey(name: 'due_at')  DateTime? dueAt, @JsonKey(name: 'defer_until')  DateTime? deferUntil, @JsonKey(name: 'external_ref')  String? externalRef, @JsonKey(name: 'source_system')  String sourceSystem,  Map<String, dynamic> metadata, @SortedLabelsConverter()  List<String> labels,  bool ephemeral, @JsonKey(name: 'dependency_count')  int dependencyCount, @JsonKey(name: 'dependent_count')  int dependentCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(includeToJson: false)  List<BeadComment> comments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Bead() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.specId,_that.status,_that.priority,_that.issueType,_that.assignee,_that.owner,_that.estimatedMinutes,_that.createdAt,_that.createdBy,_that.updatedAt,_that.startedAt,_that.closedAt,_that.closeReason,_that.closedBySession,_that.dueAt,_that.deferUntil,_that.externalRef,_that.sourceSystem,_that.metadata,_that.labels,_that.ephemeral,_that.dependencyCount,_that.dependentCount,_that.commentCount,_that.comments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String description,  String design, @JsonKey(name: 'acceptance_criteria')  String acceptanceCriteria,  String notes, @JsonKey(name: 'spec_id')  String specId, @BeadStatusConverter()  BeadStatus status,  int priority, @JsonKey(name: 'issue_type')@IssueTypeConverter()  IssueType issueType,  String assignee,  String owner, @JsonKey(name: 'estimated_minutes')  int? estimatedMinutes, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'started_at')  DateTime? startedAt, @JsonKey(name: 'closed_at')  DateTime? closedAt, @JsonKey(name: 'close_reason')  String closeReason, @JsonKey(name: 'closed_by_session')  String closedBySession, @JsonKey(name: 'due_at')  DateTime? dueAt, @JsonKey(name: 'defer_until')  DateTime? deferUntil, @JsonKey(name: 'external_ref')  String? externalRef, @JsonKey(name: 'source_system')  String sourceSystem,  Map<String, dynamic> metadata, @SortedLabelsConverter()  List<String> labels,  bool ephemeral, @JsonKey(name: 'dependency_count')  int dependencyCount, @JsonKey(name: 'dependent_count')  int dependentCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(includeToJson: false)  List<BeadComment> comments)  $default,) {final _that = this;
switch (_that) {
case _Bead():
return $default(_that.id,_that.title,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.specId,_that.status,_that.priority,_that.issueType,_that.assignee,_that.owner,_that.estimatedMinutes,_that.createdAt,_that.createdBy,_that.updatedAt,_that.startedAt,_that.closedAt,_that.closeReason,_that.closedBySession,_that.dueAt,_that.deferUntil,_that.externalRef,_that.sourceSystem,_that.metadata,_that.labels,_that.ephemeral,_that.dependencyCount,_that.dependentCount,_that.commentCount,_that.comments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String description,  String design, @JsonKey(name: 'acceptance_criteria')  String acceptanceCriteria,  String notes, @JsonKey(name: 'spec_id')  String specId, @BeadStatusConverter()  BeadStatus status,  int priority, @JsonKey(name: 'issue_type')@IssueTypeConverter()  IssueType issueType,  String assignee,  String owner, @JsonKey(name: 'estimated_minutes')  int? estimatedMinutes, @JsonKey(name: 'created_at')  DateTime? createdAt, @JsonKey(name: 'created_by')  String createdBy, @JsonKey(name: 'updated_at')  DateTime? updatedAt, @JsonKey(name: 'started_at')  DateTime? startedAt, @JsonKey(name: 'closed_at')  DateTime? closedAt, @JsonKey(name: 'close_reason')  String closeReason, @JsonKey(name: 'closed_by_session')  String closedBySession, @JsonKey(name: 'due_at')  DateTime? dueAt, @JsonKey(name: 'defer_until')  DateTime? deferUntil, @JsonKey(name: 'external_ref')  String? externalRef, @JsonKey(name: 'source_system')  String sourceSystem,  Map<String, dynamic> metadata, @SortedLabelsConverter()  List<String> labels,  bool ephemeral, @JsonKey(name: 'dependency_count')  int dependencyCount, @JsonKey(name: 'dependent_count')  int dependentCount, @JsonKey(name: 'comment_count')  int commentCount, @JsonKey(includeToJson: false)  List<BeadComment> comments)?  $default,) {final _that = this;
switch (_that) {
case _Bead() when $default != null:
return $default(_that.id,_that.title,_that.description,_that.design,_that.acceptanceCriteria,_that.notes,_that.specId,_that.status,_that.priority,_that.issueType,_that.assignee,_that.owner,_that.estimatedMinutes,_that.createdAt,_that.createdBy,_that.updatedAt,_that.startedAt,_that.closedAt,_that.closeReason,_that.closedBySession,_that.dueAt,_that.deferUntil,_that.externalRef,_that.sourceSystem,_that.metadata,_that.labels,_that.ephemeral,_that.dependencyCount,_that.dependentCount,_that.commentCount,_that.comments);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Bead extends Bead {
  const _Bead({required this.id, this.title = '', this.description = '', this.design = '', @JsonKey(name: 'acceptance_criteria') this.acceptanceCriteria = '', this.notes = '', @JsonKey(name: 'spec_id') this.specId = '', @BeadStatusConverter() this.status = BeadStatus.open, this.priority = 0, @JsonKey(name: 'issue_type')@IssueTypeConverter() this.issueType = IssueType.task, this.assignee = '', this.owner = '', @JsonKey(name: 'estimated_minutes') this.estimatedMinutes, @JsonKey(name: 'created_at') this.createdAt, @JsonKey(name: 'created_by') this.createdBy = '', @JsonKey(name: 'updated_at') this.updatedAt, @JsonKey(name: 'started_at') this.startedAt, @JsonKey(name: 'closed_at') this.closedAt, @JsonKey(name: 'close_reason') this.closeReason = '', @JsonKey(name: 'closed_by_session') this.closedBySession = '', @JsonKey(name: 'due_at') this.dueAt, @JsonKey(name: 'defer_until') this.deferUntil, @JsonKey(name: 'external_ref') this.externalRef, @JsonKey(name: 'source_system') this.sourceSystem = '', final  Map<String, dynamic> metadata = const <String, dynamic>{}, @SortedLabelsConverter() final  List<String> labels = const <String>[], this.ephemeral = false, @JsonKey(name: 'dependency_count') this.dependencyCount = 0, @JsonKey(name: 'dependent_count') this.dependentCount = 0, @JsonKey(name: 'comment_count') this.commentCount = 0, @JsonKey(includeToJson: false) final  List<BeadComment> comments = const <BeadComment>[]}): _metadata = metadata,_labels = labels,_comments = comments,super._();
  factory _Bead.fromJson(Map<String, dynamic> json) => _$BeadFromJson(json);

@override final  String id;
@override@JsonKey() final  String title;
@override@JsonKey() final  String description;
@override@JsonKey() final  String design;
@override@JsonKey(name: 'acceptance_criteria') final  String acceptanceCriteria;
@override@JsonKey() final  String notes;
@override@JsonKey(name: 'spec_id') final  String specId;
@override@JsonKey()@BeadStatusConverter() final  BeadStatus status;
@override@JsonKey() final  int priority;
@override@JsonKey(name: 'issue_type')@IssueTypeConverter() final  IssueType issueType;
@override@JsonKey() final  String assignee;
@override@JsonKey() final  String owner;
@override@JsonKey(name: 'estimated_minutes') final  int? estimatedMinutes;
@override@JsonKey(name: 'created_at') final  DateTime? createdAt;
@override@JsonKey(name: 'created_by') final  String createdBy;
@override@JsonKey(name: 'updated_at') final  DateTime? updatedAt;
@override@JsonKey(name: 'started_at') final  DateTime? startedAt;
@override@JsonKey(name: 'closed_at') final  DateTime? closedAt;
@override@JsonKey(name: 'close_reason') final  String closeReason;
@override@JsonKey(name: 'closed_by_session') final  String closedBySession;
@override@JsonKey(name: 'due_at') final  DateTime? dueAt;
@override@JsonKey(name: 'defer_until') final  DateTime? deferUntil;
@override@JsonKey(name: 'external_ref') final  String? externalRef;
@override@JsonKey(name: 'source_system') final  String sourceSystem;
 final  Map<String, dynamic> _metadata;
@override@JsonKey() Map<String, dynamic> get metadata {
  if (_metadata is EqualUnmodifiableMapView) return _metadata;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_metadata);
}

 final  List<String> _labels;
@override@JsonKey()@SortedLabelsConverter() List<String> get labels {
  if (_labels is EqualUnmodifiableListView) return _labels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_labels);
}

@override@JsonKey() final  bool ephemeral;
@override@JsonKey(name: 'dependency_count') final  int dependencyCount;
@override@JsonKey(name: 'dependent_count') final  int dependentCount;
@override@JsonKey(name: 'comment_count') final  int commentCount;
 final  List<BeadComment> _comments;
@override@JsonKey(includeToJson: false) List<BeadComment> get comments {
  if (_comments is EqualUnmodifiableListView) return _comments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_comments);
}


/// Create a copy of Bead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BeadCopyWith<_Bead> get copyWith => __$BeadCopyWithImpl<_Bead>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BeadToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Bead&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.design, design) || other.design == design)&&(identical(other.acceptanceCriteria, acceptanceCriteria) || other.acceptanceCriteria == acceptanceCriteria)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.specId, specId) || other.specId == specId)&&(identical(other.status, status) || other.status == status)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.issueType, issueType) || other.issueType == issueType)&&(identical(other.assignee, assignee) || other.assignee == assignee)&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.createdBy, createdBy) || other.createdBy == createdBy)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.closedAt, closedAt) || other.closedAt == closedAt)&&(identical(other.closeReason, closeReason) || other.closeReason == closeReason)&&(identical(other.closedBySession, closedBySession) || other.closedBySession == closedBySession)&&(identical(other.dueAt, dueAt) || other.dueAt == dueAt)&&(identical(other.deferUntil, deferUntil) || other.deferUntil == deferUntil)&&(identical(other.externalRef, externalRef) || other.externalRef == externalRef)&&(identical(other.sourceSystem, sourceSystem) || other.sourceSystem == sourceSystem)&&const DeepCollectionEquality().equals(other._metadata, _metadata)&&const DeepCollectionEquality().equals(other._labels, _labels)&&(identical(other.ephemeral, ephemeral) || other.ephemeral == ephemeral)&&(identical(other.dependencyCount, dependencyCount) || other.dependencyCount == dependencyCount)&&(identical(other.dependentCount, dependentCount) || other.dependentCount == dependentCount)&&(identical(other.commentCount, commentCount) || other.commentCount == commentCount)&&const DeepCollectionEquality().equals(other._comments, _comments));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,description,design,acceptanceCriteria,notes,specId,status,priority,issueType,assignee,owner,estimatedMinutes,createdAt,createdBy,updatedAt,startedAt,closedAt,closeReason,closedBySession,dueAt,deferUntil,externalRef,sourceSystem,const DeepCollectionEquality().hash(_metadata),const DeepCollectionEquality().hash(_labels),ephemeral,dependencyCount,dependentCount,commentCount,const DeepCollectionEquality().hash(_comments)]);

@override
String toString() {
  return 'Bead(id: $id, title: $title, description: $description, design: $design, acceptanceCriteria: $acceptanceCriteria, notes: $notes, specId: $specId, status: $status, priority: $priority, issueType: $issueType, assignee: $assignee, owner: $owner, estimatedMinutes: $estimatedMinutes, createdAt: $createdAt, createdBy: $createdBy, updatedAt: $updatedAt, startedAt: $startedAt, closedAt: $closedAt, closeReason: $closeReason, closedBySession: $closedBySession, dueAt: $dueAt, deferUntil: $deferUntil, externalRef: $externalRef, sourceSystem: $sourceSystem, metadata: $metadata, labels: $labels, ephemeral: $ephemeral, dependencyCount: $dependencyCount, dependentCount: $dependentCount, commentCount: $commentCount, comments: $comments)';
}


}

/// @nodoc
abstract mixin class _$BeadCopyWith<$Res> implements $BeadCopyWith<$Res> {
  factory _$BeadCopyWith(_Bead value, $Res Function(_Bead) _then) = __$BeadCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String description, String design,@JsonKey(name: 'acceptance_criteria') String acceptanceCriteria, String notes,@JsonKey(name: 'spec_id') String specId,@BeadStatusConverter() BeadStatus status, int priority,@JsonKey(name: 'issue_type')@IssueTypeConverter() IssueType issueType, String assignee, String owner,@JsonKey(name: 'estimated_minutes') int? estimatedMinutes,@JsonKey(name: 'created_at') DateTime? createdAt,@JsonKey(name: 'created_by') String createdBy,@JsonKey(name: 'updated_at') DateTime? updatedAt,@JsonKey(name: 'started_at') DateTime? startedAt,@JsonKey(name: 'closed_at') DateTime? closedAt,@JsonKey(name: 'close_reason') String closeReason,@JsonKey(name: 'closed_by_session') String closedBySession,@JsonKey(name: 'due_at') DateTime? dueAt,@JsonKey(name: 'defer_until') DateTime? deferUntil,@JsonKey(name: 'external_ref') String? externalRef,@JsonKey(name: 'source_system') String sourceSystem, Map<String, dynamic> metadata,@SortedLabelsConverter() List<String> labels, bool ephemeral,@JsonKey(name: 'dependency_count') int dependencyCount,@JsonKey(name: 'dependent_count') int dependentCount,@JsonKey(name: 'comment_count') int commentCount,@JsonKey(includeToJson: false) List<BeadComment> comments
});




}
/// @nodoc
class __$BeadCopyWithImpl<$Res>
    implements _$BeadCopyWith<$Res> {
  __$BeadCopyWithImpl(this._self, this._then);

  final _Bead _self;
  final $Res Function(_Bead) _then;

/// Create a copy of Bead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? description = null,Object? design = null,Object? acceptanceCriteria = null,Object? notes = null,Object? specId = null,Object? status = null,Object? priority = null,Object? issueType = null,Object? assignee = null,Object? owner = null,Object? estimatedMinutes = freezed,Object? createdAt = freezed,Object? createdBy = null,Object? updatedAt = freezed,Object? startedAt = freezed,Object? closedAt = freezed,Object? closeReason = null,Object? closedBySession = null,Object? dueAt = freezed,Object? deferUntil = freezed,Object? externalRef = freezed,Object? sourceSystem = null,Object? metadata = null,Object? labels = null,Object? ephemeral = null,Object? dependencyCount = null,Object? dependentCount = null,Object? commentCount = null,Object? comments = null,}) {
  return _then(_Bead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,design: null == design ? _self.design : design // ignore: cast_nullable_to_non_nullable
as String,acceptanceCriteria: null == acceptanceCriteria ? _self.acceptanceCriteria : acceptanceCriteria // ignore: cast_nullable_to_non_nullable
as String,notes: null == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String,specId: null == specId ? _self.specId : specId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BeadStatus,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,issueType: null == issueType ? _self.issueType : issueType // ignore: cast_nullable_to_non_nullable
as IssueType,assignee: null == assignee ? _self.assignee : assignee // ignore: cast_nullable_to_non_nullable
as String,owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as String,estimatedMinutes: freezed == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdBy: null == createdBy ? _self.createdBy : createdBy // ignore: cast_nullable_to_non_nullable
as String,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closedAt: freezed == closedAt ? _self.closedAt : closedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,closeReason: null == closeReason ? _self.closeReason : closeReason // ignore: cast_nullable_to_non_nullable
as String,closedBySession: null == closedBySession ? _self.closedBySession : closedBySession // ignore: cast_nullable_to_non_nullable
as String,dueAt: freezed == dueAt ? _self.dueAt : dueAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deferUntil: freezed == deferUntil ? _self.deferUntil : deferUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,externalRef: freezed == externalRef ? _self.externalRef : externalRef // ignore: cast_nullable_to_non_nullable
as String?,sourceSystem: null == sourceSystem ? _self.sourceSystem : sourceSystem // ignore: cast_nullable_to_non_nullable
as String,metadata: null == metadata ? _self._metadata : metadata // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,labels: null == labels ? _self._labels : labels // ignore: cast_nullable_to_non_nullable
as List<String>,ephemeral: null == ephemeral ? _self.ephemeral : ephemeral // ignore: cast_nullable_to_non_nullable
as bool,dependencyCount: null == dependencyCount ? _self.dependencyCount : dependencyCount // ignore: cast_nullable_to_non_nullable
as int,dependentCount: null == dependentCount ? _self.dependentCount : dependentCount // ignore: cast_nullable_to_non_nullable
as int,commentCount: null == commentCount ? _self.commentCount : commentCount // ignore: cast_nullable_to_non_nullable
as int,comments: null == comments ? _self._comments : comments // ignore: cast_nullable_to_non_nullable
as List<BeadComment>,
  ));
}


}

// dart format on
