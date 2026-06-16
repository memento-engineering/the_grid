import 'package:freezed_annotation/freezed_annotation.dart';

part 'runtime_event.freezed.dart';

/// An observation from a [RuntimeProvider]'s session lifecycle, emitted on the
/// `events` stream (Streams for observations; APIs convention, CLAUDE.md).
///
/// The five variants are the M3-trimmed projection of the lifecycle signals gc's
/// runtime surfaces (`gascity/internal/runtime/` + `internal/session/`): a
/// session was created, its process exited cleanly with a code, it died
/// unexpectedly (crash — the restart/quarantine trigger Track 4 consumes), it
/// was respawned (restart generation bumped), or its activity state changed.
/// Each carries the session [name] so a multiplexed stream is demuxable.
///
/// Consume with an exhaustive `switch` (sealed) — a new lifecycle signal forces
/// every consumer to handle it.
@freezed
sealed class RuntimeEvent with _$RuntimeEvent {
  const RuntimeEvent._();

  /// The session's process was created and is live. Carries the OS [pid] and the
  /// resolved process-group [pgid] (the kill target; null only if pgid
  /// resolution failed, in which case stop() falls back to a direct
  /// single-process kill).
  const factory RuntimeEvent.sessionStarted({
    required String name,
    required int pid,
    int? pgid,
    @Default('') String beadId,
  }) = SessionStarted;

  /// The session's process exited with [exitCode] (negative for signal-killed,
  /// Dart's `Process.exitCode` convention). The normal end of a one-turn agent;
  /// for a long-lived session this is the death the supervisor reacts to. This
  /// is the "observe death as a `RuntimeEvent`" DoD signal (M3-BUILD-ORDER Track
  /// 2): an exit with a code, observed, never inferred from stdout EOF alone.
  const factory RuntimeEvent.exited({
    required String name,
    required int exitCode,
  }) = Exited;

  /// The session died without a clean exit code we could read (e.g. the process
  /// vanished from the table while we were watching it). Distinct from [Exited]
  /// because the crash/quarantine path (Track 4) branches on it.
  const factory RuntimeEvent.died({
    required String name,
    @Default('') String reason,
  }) = Died;

  /// The session was restarted in a new incarnation; [epoch] is the new runtime
  /// generation (gc's `GRID_RUNTIME_EPOCH` bump). Emitted by the supervisor, not
  /// by a bare subprocess spawn.
  const factory RuntimeEvent.respawned({
    required String name,
    required int epoch,
  }) = Respawned;

  /// The session's activity state changed (e.g. idle → active). [active] is the
  /// new state. The subprocess provider emits this coarsely (it has no terminal
  /// to watch); a tmux provider refines it.
  const factory RuntimeEvent.activityChanged({
    required String name,
    required bool active,
  }) = ActivityChanged;

  // [name] — the session this event concerns — is a field shared by every
  // variant, so freezed generates a single `String get name` on the union;
  // consumers demux on it without a `switch`.
}
