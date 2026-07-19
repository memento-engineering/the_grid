// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'runtime_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RuntimeConfig {

/// The working directory for the session process — **the per-bead git
/// worktree** (Track 3 allocates it; gc's `Config.WorkDir`,
/// `runtime.go:461-462`). Required: an agent never launches into an
/// unprepared cwd.
 String get workDir;/// The executable to run (`claude` for the dogfood). gc splits command +
/// args; the_grid carries the executable here and the args in [args] so the
/// no-shell `Process.start(executable, args)` contract holds (no shell word-
/// splitting; gc's `condition.go:319` exit-code contract).
 String get command;/// The argv passed to [command] — permission flag, optional
/// `--model`/`--effort`, `-p` for non-interactive print mode, the prompt
/// positional/`--prompt`. NEVER carries a secret (the OAuth token rides
/// [env]/the allowlist, never argv).
 List<String> get args;/// Long-lived vs one-turn (gc's `Config.Lifecycle`, `runtime.go:468-470`).
 Lifecycle get lifecycle;/// Additional environment variables set in the session, layered OVER the
/// allowlist and the per-incarnation `GRID_*` env (gc's `Config.Env`,
/// `runtime.go:472-473`). This is where the **inherited agent token** is
/// threaded when a caller wants to pass it explicitly rather than inherit it
/// from the parent allowlist; either way it lands as an env var, never argv.
 Map<String, String> get env;/// Optional human-readable startup hint surfaced in logs/events — gc's
/// startup-reliability hints (`runtime.go:483-577`) collapsed to a single
/// opaque note for M3 (the prompt-prefix / ready-delay / dialog machinery is
/// CUT). Null when unset.
 String? get startupHint;/// Absolute lifetime limit for this process. Null means the provider's
/// default applies; callers set this for validation and critic lanes so a
/// hung lane reaches a terminal event instead of occupying its cursor
/// forever.
 Duration? get deadline;
/// Create a copy of RuntimeConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeConfigCopyWith<RuntimeConfig> get copyWith => _$RuntimeConfigCopyWithImpl<RuntimeConfig>(this as RuntimeConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeConfig&&(identical(other.workDir, workDir) || other.workDir == workDir)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other.args, args)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&const DeepCollectionEquality().equals(other.env, env)&&(identical(other.startupHint, startupHint) || other.startupHint == startupHint)&&(identical(other.deadline, deadline) || other.deadline == deadline));
}


@override
int get hashCode => Object.hash(runtimeType,workDir,command,const DeepCollectionEquality().hash(args),lifecycle,const DeepCollectionEquality().hash(env),startupHint,deadline);

@override
String toString() {
  return 'RuntimeConfig(workDir: $workDir, command: $command, args: $args, lifecycle: $lifecycle, env: $env, startupHint: $startupHint, deadline: $deadline)';
}


}

/// @nodoc
abstract mixin class $RuntimeConfigCopyWith<$Res>  {
  factory $RuntimeConfigCopyWith(RuntimeConfig value, $Res Function(RuntimeConfig) _then) = _$RuntimeConfigCopyWithImpl;
@useResult
$Res call({
 String workDir, String command, List<String> args, Lifecycle lifecycle, Map<String, String> env, String? startupHint, Duration? deadline
});




}
/// @nodoc
class _$RuntimeConfigCopyWithImpl<$Res>
    implements $RuntimeConfigCopyWith<$Res> {
  _$RuntimeConfigCopyWithImpl(this._self, this._then);

  final RuntimeConfig _self;
  final $Res Function(RuntimeConfig) _then;

/// Create a copy of RuntimeConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workDir = null,Object? command = null,Object? args = null,Object? lifecycle = null,Object? env = null,Object? startupHint = freezed,Object? deadline = freezed,}) {
  return _then(_self.copyWith(
workDir: null == workDir ? _self.workDir : workDir // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self.args : args // ignore: cast_nullable_to_non_nullable
as List<String>,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as Lifecycle,env: null == env ? _self.env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,startupHint: freezed == startupHint ? _self.startupHint : startupHint // ignore: cast_nullable_to_non_nullable
as String?,deadline: freezed == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeConfig].
extension RuntimeConfigPatterns on RuntimeConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeConfig value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeConfig value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String workDir,  String command,  List<String> args,  Lifecycle lifecycle,  Map<String, String> env,  String? startupHint,  Duration? deadline)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeConfig() when $default != null:
return $default(_that.workDir,_that.command,_that.args,_that.lifecycle,_that.env,_that.startupHint,_that.deadline);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String workDir,  String command,  List<String> args,  Lifecycle lifecycle,  Map<String, String> env,  String? startupHint,  Duration? deadline)  $default,) {final _that = this;
switch (_that) {
case _RuntimeConfig():
return $default(_that.workDir,_that.command,_that.args,_that.lifecycle,_that.env,_that.startupHint,_that.deadline);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String workDir,  String command,  List<String> args,  Lifecycle lifecycle,  Map<String, String> env,  String? startupHint,  Duration? deadline)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeConfig() when $default != null:
return $default(_that.workDir,_that.command,_that.args,_that.lifecycle,_that.env,_that.startupHint,_that.deadline);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeConfig extends RuntimeConfig {
  const _RuntimeConfig({required this.workDir, required this.command, final  List<String> args = const <String>[], this.lifecycle = Lifecycle.longLived, final  Map<String, String> env = const <String, String>{}, this.startupHint, this.deadline}): _args = args,_env = env,super._();
  

/// The working directory for the session process — **the per-bead git
/// worktree** (Track 3 allocates it; gc's `Config.WorkDir`,
/// `runtime.go:461-462`). Required: an agent never launches into an
/// unprepared cwd.
@override final  String workDir;
/// The executable to run (`claude` for the dogfood). gc splits command +
/// args; the_grid carries the executable here and the args in [args] so the
/// no-shell `Process.start(executable, args)` contract holds (no shell word-
/// splitting; gc's `condition.go:319` exit-code contract).
@override final  String command;
/// The argv passed to [command] — permission flag, optional
/// `--model`/`--effort`, `-p` for non-interactive print mode, the prompt
/// positional/`--prompt`. NEVER carries a secret (the OAuth token rides
/// [env]/the allowlist, never argv).
 final  List<String> _args;
/// The argv passed to [command] — permission flag, optional
/// `--model`/`--effort`, `-p` for non-interactive print mode, the prompt
/// positional/`--prompt`. NEVER carries a secret (the OAuth token rides
/// [env]/the allowlist, never argv).
@override@JsonKey() List<String> get args {
  if (_args is EqualUnmodifiableListView) return _args;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_args);
}

/// Long-lived vs one-turn (gc's `Config.Lifecycle`, `runtime.go:468-470`).
@override@JsonKey() final  Lifecycle lifecycle;
/// Additional environment variables set in the session, layered OVER the
/// allowlist and the per-incarnation `GRID_*` env (gc's `Config.Env`,
/// `runtime.go:472-473`). This is where the **inherited agent token** is
/// threaded when a caller wants to pass it explicitly rather than inherit it
/// from the parent allowlist; either way it lands as an env var, never argv.
 final  Map<String, String> _env;
/// Additional environment variables set in the session, layered OVER the
/// allowlist and the per-incarnation `GRID_*` env (gc's `Config.Env`,
/// `runtime.go:472-473`). This is where the **inherited agent token** is
/// threaded when a caller wants to pass it explicitly rather than inherit it
/// from the parent allowlist; either way it lands as an env var, never argv.
@override@JsonKey() Map<String, String> get env {
  if (_env is EqualUnmodifiableMapView) return _env;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_env);
}

/// Optional human-readable startup hint surfaced in logs/events — gc's
/// startup-reliability hints (`runtime.go:483-577`) collapsed to a single
/// opaque note for M3 (the prompt-prefix / ready-delay / dialog machinery is
/// CUT). Null when unset.
@override final  String? startupHint;
/// Absolute lifetime limit for this process. Null means the provider's
/// default applies; callers set this for validation and critic lanes so a
/// hung lane reaches a terminal event instead of occupying its cursor
/// forever.
@override final  Duration? deadline;

/// Create a copy of RuntimeConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeConfigCopyWith<_RuntimeConfig> get copyWith => __$RuntimeConfigCopyWithImpl<_RuntimeConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeConfig&&(identical(other.workDir, workDir) || other.workDir == workDir)&&(identical(other.command, command) || other.command == command)&&const DeepCollectionEquality().equals(other._args, _args)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&const DeepCollectionEquality().equals(other._env, _env)&&(identical(other.startupHint, startupHint) || other.startupHint == startupHint)&&(identical(other.deadline, deadline) || other.deadline == deadline));
}


@override
int get hashCode => Object.hash(runtimeType,workDir,command,const DeepCollectionEquality().hash(_args),lifecycle,const DeepCollectionEquality().hash(_env),startupHint,deadline);

@override
String toString() {
  return 'RuntimeConfig(workDir: $workDir, command: $command, args: $args, lifecycle: $lifecycle, env: $env, startupHint: $startupHint, deadline: $deadline)';
}


}

/// @nodoc
abstract mixin class _$RuntimeConfigCopyWith<$Res> implements $RuntimeConfigCopyWith<$Res> {
  factory _$RuntimeConfigCopyWith(_RuntimeConfig value, $Res Function(_RuntimeConfig) _then) = __$RuntimeConfigCopyWithImpl;
@override @useResult
$Res call({
 String workDir, String command, List<String> args, Lifecycle lifecycle, Map<String, String> env, String? startupHint, Duration? deadline
});




}
/// @nodoc
class __$RuntimeConfigCopyWithImpl<$Res>
    implements _$RuntimeConfigCopyWith<$Res> {
  __$RuntimeConfigCopyWithImpl(this._self, this._then);

  final _RuntimeConfig _self;
  final $Res Function(_RuntimeConfig) _then;

/// Create a copy of RuntimeConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workDir = null,Object? command = null,Object? args = null,Object? lifecycle = null,Object? env = null,Object? startupHint = freezed,Object? deadline = freezed,}) {
  return _then(_RuntimeConfig(
workDir: null == workDir ? _self.workDir : workDir // ignore: cast_nullable_to_non_nullable
as String,command: null == command ? _self.command : command // ignore: cast_nullable_to_non_nullable
as String,args: null == args ? _self._args : args // ignore: cast_nullable_to_non_nullable
as List<String>,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as Lifecycle,env: null == env ? _self._env : env // ignore: cast_nullable_to_non_nullable
as Map<String, String>,startupHint: freezed == startupHint ? _self.startupHint : startupHint // ignore: cast_nullable_to_non_nullable
as String?,deadline: freezed == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as Duration?,
  ));
}


}

/// @nodoc
mixin _$RuntimeCapabilities {

/// Whether the provider can observe agent-process liveness/exit
/// (`isRunning`/`processAlive`/`RuntimeEvent.exited`).
 bool get detectsLiveness;/// Whether the provider streams a live transcript (`output(name)`).
 bool get streamsOutput;/// Whether the provider can attach a user terminal (tmux only; the
/// subprocess provider cannot).
 bool get supportsAttach;/// Whether the provider reports last-activity time from terminal I/O
/// (tmux only).
 bool get detectsActivity;
/// Create a copy of RuntimeCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeCapabilitiesCopyWith<RuntimeCapabilities> get copyWith => _$RuntimeCapabilitiesCopyWithImpl<RuntimeCapabilities>(this as RuntimeCapabilities, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeCapabilities&&(identical(other.detectsLiveness, detectsLiveness) || other.detectsLiveness == detectsLiveness)&&(identical(other.streamsOutput, streamsOutput) || other.streamsOutput == streamsOutput)&&(identical(other.supportsAttach, supportsAttach) || other.supportsAttach == supportsAttach)&&(identical(other.detectsActivity, detectsActivity) || other.detectsActivity == detectsActivity));
}


@override
int get hashCode => Object.hash(runtimeType,detectsLiveness,streamsOutput,supportsAttach,detectsActivity);

@override
String toString() {
  return 'RuntimeCapabilities(detectsLiveness: $detectsLiveness, streamsOutput: $streamsOutput, supportsAttach: $supportsAttach, detectsActivity: $detectsActivity)';
}


}

/// @nodoc
abstract mixin class $RuntimeCapabilitiesCopyWith<$Res>  {
  factory $RuntimeCapabilitiesCopyWith(RuntimeCapabilities value, $Res Function(RuntimeCapabilities) _then) = _$RuntimeCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool detectsLiveness, bool streamsOutput, bool supportsAttach, bool detectsActivity
});




}
/// @nodoc
class _$RuntimeCapabilitiesCopyWithImpl<$Res>
    implements $RuntimeCapabilitiesCopyWith<$Res> {
  _$RuntimeCapabilitiesCopyWithImpl(this._self, this._then);

  final RuntimeCapabilities _self;
  final $Res Function(RuntimeCapabilities) _then;

/// Create a copy of RuntimeCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? detectsLiveness = null,Object? streamsOutput = null,Object? supportsAttach = null,Object? detectsActivity = null,}) {
  return _then(_self.copyWith(
detectsLiveness: null == detectsLiveness ? _self.detectsLiveness : detectsLiveness // ignore: cast_nullable_to_non_nullable
as bool,streamsOutput: null == streamsOutput ? _self.streamsOutput : streamsOutput // ignore: cast_nullable_to_non_nullable
as bool,supportsAttach: null == supportsAttach ? _self.supportsAttach : supportsAttach // ignore: cast_nullable_to_non_nullable
as bool,detectsActivity: null == detectsActivity ? _self.detectsActivity : detectsActivity // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeCapabilities].
extension RuntimeCapabilitiesPatterns on RuntimeCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool detectsLiveness,  bool streamsOutput,  bool supportsAttach,  bool detectsActivity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeCapabilities() when $default != null:
return $default(_that.detectsLiveness,_that.streamsOutput,_that.supportsAttach,_that.detectsActivity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool detectsLiveness,  bool streamsOutput,  bool supportsAttach,  bool detectsActivity)  $default,) {final _that = this;
switch (_that) {
case _RuntimeCapabilities():
return $default(_that.detectsLiveness,_that.streamsOutput,_that.supportsAttach,_that.detectsActivity);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool detectsLiveness,  bool streamsOutput,  bool supportsAttach,  bool detectsActivity)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeCapabilities() when $default != null:
return $default(_that.detectsLiveness,_that.streamsOutput,_that.supportsAttach,_that.detectsActivity);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeCapabilities extends RuntimeCapabilities {
  const _RuntimeCapabilities({this.detectsLiveness = false, this.streamsOutput = false, this.supportsAttach = false, this.detectsActivity = false}): super._();
  

/// Whether the provider can observe agent-process liveness/exit
/// (`isRunning`/`processAlive`/`RuntimeEvent.exited`).
@override@JsonKey() final  bool detectsLiveness;
/// Whether the provider streams a live transcript (`output(name)`).
@override@JsonKey() final  bool streamsOutput;
/// Whether the provider can attach a user terminal (tmux only; the
/// subprocess provider cannot).
@override@JsonKey() final  bool supportsAttach;
/// Whether the provider reports last-activity time from terminal I/O
/// (tmux only).
@override@JsonKey() final  bool detectsActivity;

/// Create a copy of RuntimeCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeCapabilitiesCopyWith<_RuntimeCapabilities> get copyWith => __$RuntimeCapabilitiesCopyWithImpl<_RuntimeCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeCapabilities&&(identical(other.detectsLiveness, detectsLiveness) || other.detectsLiveness == detectsLiveness)&&(identical(other.streamsOutput, streamsOutput) || other.streamsOutput == streamsOutput)&&(identical(other.supportsAttach, supportsAttach) || other.supportsAttach == supportsAttach)&&(identical(other.detectsActivity, detectsActivity) || other.detectsActivity == detectsActivity));
}


@override
int get hashCode => Object.hash(runtimeType,detectsLiveness,streamsOutput,supportsAttach,detectsActivity);

@override
String toString() {
  return 'RuntimeCapabilities(detectsLiveness: $detectsLiveness, streamsOutput: $streamsOutput, supportsAttach: $supportsAttach, detectsActivity: $detectsActivity)';
}


}

/// @nodoc
abstract mixin class _$RuntimeCapabilitiesCopyWith<$Res> implements $RuntimeCapabilitiesCopyWith<$Res> {
  factory _$RuntimeCapabilitiesCopyWith(_RuntimeCapabilities value, $Res Function(_RuntimeCapabilities) _then) = __$RuntimeCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool detectsLiveness, bool streamsOutput, bool supportsAttach, bool detectsActivity
});




}
/// @nodoc
class __$RuntimeCapabilitiesCopyWithImpl<$Res>
    implements _$RuntimeCapabilitiesCopyWith<$Res> {
  __$RuntimeCapabilitiesCopyWithImpl(this._self, this._then);

  final _RuntimeCapabilities _self;
  final $Res Function(_RuntimeCapabilities) _then;

/// Create a copy of RuntimeCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? detectsLiveness = null,Object? streamsOutput = null,Object? supportsAttach = null,Object? detectsActivity = null,}) {
  return _then(_RuntimeCapabilities(
detectsLiveness: null == detectsLiveness ? _self.detectsLiveness : detectsLiveness // ignore: cast_nullable_to_non_nullable
as bool,streamsOutput: null == streamsOutput ? _self.streamsOutput : streamsOutput // ignore: cast_nullable_to_non_nullable
as bool,supportsAttach: null == supportsAttach ? _self.supportsAttach : supportsAttach // ignore: cast_nullable_to_non_nullable
as bool,detectsActivity: null == detectsActivity ? _self.detectsActivity : detectsActivity // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
